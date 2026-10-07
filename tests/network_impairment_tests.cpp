#include "check.hpp"
#include "coop/client.hpp"
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <thread>
#include <tuple>
#include <utility>
#include <vector>
#ifdef _WIN32
#include <winsock2.h>
#ifdef max
#undef max
#endif
#ifdef min
#undef min
#endif
#else
#include <cerrno>
#include <sys/socket.h>
#endif
using namespace coop;
using namespace std::chrono_literals;

namespace coop {
struct SessionServerTestAccess {
    static std::uint32_t CurrentEpoch(const SessionServer& server,SessionId id) { const auto* session=server.registry_.Find(id); return session?session->epoch:0; }
    static SessionError AdvanceHostEpoch(SessionServer& server) {
        for (const auto& [connection, peer] : server.peers_)
            if (peer.member && peer.member->role == Role::Host) return server.registry_.ResetWorld(connection);
        return SessionError::MissingMember;
    }
};
}
namespace {
#ifdef _WIN32
using RawSocket = SOCKET;
RawSocket Raw(const net::Socket& socket) { return static_cast<SOCKET>(socket.Handle()); }
bool WouldBlock() { const auto e=WSAGetLastError(); return e==WSAEWOULDBLOCK || e==WSAEINTR; }
#else
using RawSocket = int;
RawSocket Raw(const net::Socket& socket) { return static_cast<int>(socket.Handle()); }
bool WouldBlock() { return errno==EAGAIN || errno==EWOULDBLOCK || errno==EINTR; }
#endif
struct ImpairmentProfile {
    std::string name="moderate-loss-delay";
    unsigned delayMs=20,jitterMs=9,lossPercent=12,duplicatePercent=10;
    std::uint64_t seed=0xC02077C001ULL;
    std::size_t queueCapacity=256;
};
struct LinkMetrics {
    std::uint64_t statePacketsSeen=0,policyDrops=0,queueDrops=0;
    std::uint64_t duplicateCopiesScheduled=0,uniqueCopiesDelivered=0,duplicateCopiesDelivered=0;
    std::uint64_t udpSendFailures=0,tcpBroken=0,tcpBufferHighWater=0,tcpBufferOverflows=0;
    std::size_t pending=0,maxPending=0,queueCapacity=0;
};
struct AdmissionInfo { SessionId session=0; std::uint32_t epoch=0; PlayerId player=0,host=0; ConnectionToken token{}; };
struct FlowKey {
    ConnectionToken token{};
    PacketType type=PacketType::Heartbeat;
    EntityId entity=0;
    std::uint32_t sequence=0;
    bool fromServer=false;
    auto operator<=>(const FlowKey&) const = default;
};
std::uint64_t Mix(std::uint64_t x) {
    x+=0x9e3779b97f4a7c15ULL; x=(x^(x>>30))*0xbf58476d1ce4e5b9ULL;
    x=(x^(x>>27))*0x94d049bb133111ebULL; return x^(x>>31);
}
std::optional<EntityId> StateEntity(const Packet& p) {
    if(auto* x=std::get_if<PlayerPose>(&p.payload)) return x->entity;
    if(auto* x=std::get_if<PlayerState>(&p.payload)) return x->entity;
    if(auto* x=std::get_if<NpcState>(&p.payload)) return x->entity;
    return {};
}
FlowKey MakeKey(const ConnectionToken& token,const Packet& p,bool fromServer) {
    return {token,TypeOf(p.payload),StateEntity(p).value_or(0),p.header.sequence,fromServer};
}
class ImpairedLink {
    struct Peer {
        std::size_t index=0; net::Socket client,upstream;
        std::atomic<bool> breakRequested=false;
        bool closed=false,stalled=false;
        std::vector<std::uint8_t> c2s,s2c,inspect;
        std::size_t c2sOffset=0,s2cOffset=0;
    };
    struct Scheduled { ConnectionToken token{}; Packet packet; net::Endpoint target; FlowKey key; };
public:
    ImpairedLink(std::uint16_t upstreamPort,ImpairmentProfile profile)
      : upstreamPort_(upstreamPort),profile_(std::move(profile)),listener_(net::Listen("127.0.0.1",0)),
        udp_(net::BindUdp("127.0.0.1",net::LocalPort(listener_))),lastActivity_(net::NowMs()) {
        CHECK(listener_ && udp_ && Port()!=0); metrics_.queueCapacity=profile_.queueCapacity;
        worker_=std::jthread([this](std::stop_token stop){Run(stop);});
    }
    ~ImpairedLink() { worker_.request_stop(); if(worker_.joinable()) worker_.join(); }
    std::uint16_t Port() const { return net::LocalPort(listener_); }
    std::size_t AcceptedCount() const { std::lock_guard lock(peerMutex_); return peers_.size(); }
    std::size_t Attach(SessionClient& c) {
        const auto before=AcceptedCount(); CHECK(c.Connect()); const auto deadline=net::NowMs()+3000;
        while(AcceptedCount()==before) { CHECK(net::NowMs()<deadline); std::this_thread::sleep_for(1ms); }
        return before;
    }
    void StallNextControl() { stallNext_.store(true); }
    bool WasStalled(std::size_t i) const { std::lock_guard lock(peerMutex_); return i<peers_.size() && peers_[i]->stalled; }
    void BreakControl(std::size_t i) { std::lock_guard lock(peerMutex_); CHECK(i<peers_.size()); peers_[i]->breakRequested.store(true); }
    std::optional<AdmissionInfo> Admission(std::size_t i) const {
        std::lock_guard lock(peerMutex_); if(auto it=admissions_.find(i);it!=admissions_.end()) return it->second; return {};
    }
    void HoldUdp(bool value) { holdUdp_.store(value); }
    void EnableImpairments(bool value) { impairmentEnabled_.store(value); }
    LinkMetrics Metrics() const { std::lock_guard lock(metricsMutex_); return metrics_; }
    bool InjectUdp(const ConnectionToken& token,const Packet& p) {
        return net::SendUdp(udp_,{"127.0.0.1",upstreamPort_},token,p);
    }
private:
    static constexpr std::size_t kTcpBufferLimit=64*1024;
    void Metric(const std::function<void(LinkMetrics&)>& fn) { std::lock_guard lock(metricsMutex_); fn(metrics_); }
    bool IsState(const Packet& p) const { return StateEntity(p).has_value(); }
    std::uint64_t Fingerprint(const ConnectionToken& token,const Packet& p,bool fromServer) const {
        std::uint64_t x=profile_.seed^p.header.session^(std::uint64_t(p.header.epoch)<<32)
            ^(std::uint64_t(p.header.sender)<<17)^(std::uint64_t(p.header.sequence)<<1)
            ^(std::uint64_t(TypeOf(p.payload))<<48)^(fromServer?0xD1B54A32D192ED03ULL:0)
            ^StateEntity(p).value_or(0);
        for(auto b:token) x=Mix(x^b);
        return Mix(x);
    }
    void Enqueue(ConnectionToken token,Packet p,net::Endpoint target,bool fromServer) {
        const bool state=IsState(p); const auto key=MakeKey(token,p,fromServer);
        if(!state || !impairmentEnabled_.load()) {
            if(!net::SendUdp(udp_,target,token,p)) Metric([](auto& m){++m.udpSendFailures;});
            else if(state) { if(delivered_.insert(key).second) Metric([](auto& m){++m.uniqueCopiesDelivered;}); else Metric([](auto& m){++m.duplicateCopiesDelivered;}); }
            return;
        }
        Metric([](auto& m){++m.statePacketsSeen;});
        const auto h=Fingerprint(token,p,fromServer);
        if(h%10000 < profile_.lossPercent*100ULL) { Metric([](auto& m){++m.policyDrops;}); return; }
        const auto jitter=profile_.jitterMs?Mix(h^0xA0761D6478BD642FULL)%(profile_.jitterMs+1):0;
        const auto due=net::NowMs()+profile_.delayMs+jitter;
        auto schedule=[&](bool duplicate) {
            if(scheduled_.size()>=profile_.queueCapacity) { Metric([](auto& m){++m.queueDrops;}); return; }
            scheduled_.emplace(due,Scheduled{token,p,target,key});
            Metric([&](auto& m){m.pending=scheduled_.size();m.maxPending=std::max(m.maxPending,m.pending);});
            if(duplicate) Metric([](auto& m){++m.duplicateCopiesScheduled;});
        };
        schedule(false);
        if(Mix(h^0xE7037ED1A0B428DBULL)%10000 < profile_.duplicatePercent*100ULL) schedule(true);
    }
    void ReceiveUdp() {
        for(unsigned i=0;i<2048;++i) {
            auto d=net::ReceiveUdp(udp_); if(!d) break;
            if(d->data.size()<16+kHeaderSize) continue;
            ConnectionToken token{}; std::copy_n(d->data.begin(),token.size(),token.begin());
            auto decoded=Decode(std::span<const std::uint8_t>(d->data).subspan(16)); if(!decoded) continue;
            const bool fromServer=d->sender.port==upstreamPort_;
            net::Endpoint target;
            if(fromServer) { auto it=targets_.find(token); if(it==targets_.end()) continue; target=it->second; }
            else { targets_[token]=d->sender; target={"127.0.0.1",upstreamPort_}; }
            lastActivity_.store(net::NowMs());
            if(IsState(*decoded.packet) && holdUdp_.load()) {
                Metric([](auto& m){++m.statePacketsSeen;});
                if(scheduled_.size()>=profile_.queueCapacity) Metric([](auto& m){++m.queueDrops;});
                else {
                    auto key=MakeKey(token,*decoded.packet,fromServer);
                    scheduled_.emplace(net::NowMs()+profile_.delayMs,Scheduled{token,*decoded.packet,target,key});
                    Metric([&](auto& m){m.pending=scheduled_.size();m.maxPending=std::max(m.maxPending,m.pending);});
                }
                continue;
            }
            Enqueue(token,*decoded.packet,target,fromServer);
        }
    }
    void DispatchUdp() {
        if(holdUdp_.load()) return;
        const auto now=net::NowMs();
        while(!scheduled_.empty() && scheduled_.begin()->first<=now) {
            auto item=std::move(scheduled_.begin()->second); scheduled_.erase(scheduled_.begin());
            if(!net::SendUdp(udp_,item.target,item.token,item.packet)) Metric([](auto& m){++m.udpSendFailures;});
            else if(delivered_.insert(item.key).second) Metric([](auto& m){++m.uniqueCopiesDelivered;});
            else Metric([](auto& m){++m.duplicateCopiesDelivered;});
        }
        Metric([&](auto& m){m.pending=scheduled_.size();});
    }
    void Capture(Peer& peer,std::span<const std::uint8_t> bytes) {
        if(peer.inspect.size()+bytes.size()>kTcpBufferLimit) { Metric([](auto& m){++m.tcpBufferOverflows;}); peer.inspect.clear(); return; }
        peer.inspect.insert(peer.inspect.end(),bytes.begin(),bytes.end());
        while(peer.inspect.size()>=4) {
            std::uint32_t size=0; for(unsigned i=0;i<4;++i) size=(size<<8)|peer.inspect[i];
            if(size<kHeaderSize || size>kMaxPacketSize) { peer.inspect.clear(); return; }
            if(peer.inspect.size()<size+4) return;
            auto decoded=Decode(std::span<const std::uint8_t>(peer.inspect).subspan(4,size));
            if(decoded) if(const auto* a=std::get_if<SessionAccepted>(&decoded.packet->payload)) {
                std::lock_guard lock(peerMutex_);
                admissions_[peer.index]={decoded.packet->header.session,decoded.packet->header.epoch,a->player,a->host,a->token};
            }
            peer.inspect.erase(peer.inspect.begin(),peer.inspect.begin()+static_cast<std::ptrdiff_t>(size+4));
        }
    }
    bool Relay(net::Socket& src,net::Socket& dst,std::vector<std::uint8_t>& buffer,std::size_t& offset,Peer& peer,bool inspect) {
        if(offset<buffer.size()) {
#ifdef _WIN32
            constexpr int flags=0;
#else
            constexpr int flags=MSG_NOSIGNAL;
#endif
            auto n=send(Raw(dst),reinterpret_cast<const char*>(buffer.data()+offset),static_cast<int>(buffer.size()-offset),flags);
            if(n>0) offset+=static_cast<std::size_t>(n); else if(n==0 || !WouldBlock()) return false;
            if(offset==buffer.size()) { buffer.clear(); offset=0; }
        }
        if(buffer.size()>=kTcpBufferLimit) { Metric([](auto& m){++m.tcpBufferOverflows;}); return false; }
        std::array<std::uint8_t,8192> bytes{};
        auto n=recv(Raw(src),reinterpret_cast<char*>(bytes.data()),static_cast<int>(bytes.size()),0);
        if(n==0) return false; if(n<0) return WouldBlock();
        if(buffer.size()+static_cast<std::size_t>(n)>kTcpBufferLimit) { Metric([](auto& m){++m.tcpBufferOverflows;}); return false; }
        auto span=std::span<const std::uint8_t>(bytes).first(static_cast<std::size_t>(n));
        if(inspect) Capture(peer,span);
        buffer.insert(buffer.end(),span.begin(),span.end());
        Metric([&](auto& m){m.tcpBufferHighWater=std::max<std::uint64_t>(m.tcpBufferHighWater,buffer.size());});
        return true;
    }
    void AcceptTcp() {
        for(unsigned i=0;i<16;++i) {
            auto client=net::Accept(listener_); if(!client) break;
            auto upstream=net::Connect("127.0.0.1",upstreamPort_,1500); if(!upstream) continue;
            auto p=std::make_shared<Peer>(); p->client=std::move(client); p->upstream=std::move(upstream); p->stalled=stallNext_.exchange(false);
            std::lock_guard lock(peerMutex_); p->index=peers_.size(); peers_.push_back(std::move(p));
        }
    }
    void PumpTcp() {
        std::vector<std::shared_ptr<Peer>> peers; { std::lock_guard lock(peerMutex_); peers=peers_; }
        for(auto& p:peers) {
            if(p->closed) continue;
            if(p->breakRequested.exchange(false)) { p->client.Close(); p->upstream.Close(); p->closed=true; Metric([](auto& m){++m.tcpBroken;}); continue; }
            if(!p->stalled && !Relay(p->client,p->upstream,p->c2s,p->c2sOffset,*p,false)) { p->client.Close();p->upstream.Close();p->closed=true;continue; }
            if(p->closed) continue;
            if(!Relay(p->upstream,p->client,p->s2c,p->s2cOffset,*p,true)) { p->client.Close();p->upstream.Close();p->closed=true; }
        }
    }
    void Run(std::stop_token stop) {
        while(!stop.stop_requested()) { AcceptTcp();PumpTcp();ReceiveUdp();DispatchUdp();std::this_thread::sleep_for(1ms); }
        std::lock_guard lock(peerMutex_); for(auto& p:peers_){p->client.Close();p->upstream.Close();p->closed=true;}
    }
    std::uint16_t upstreamPort_; ImpairmentProfile profile_; net::Socket listener_,udp_; std::jthread worker_;
    std::atomic<bool> stallNext_=false,holdUdp_=false,impairmentEnabled_=true;
    mutable std::mutex peerMutex_,metricsMutex_; std::vector<std::shared_ptr<Peer>> peers_;
    std::map<std::size_t,AdmissionInfo> admissions_; std::map<ConnectionToken,net::Endpoint> targets_;
    std::multimap<std::uint64_t,Scheduled> scheduled_; std::set<FlowKey> delivered_; LinkMetrics metrics_;
    std::atomic<std::uint64_t> lastActivity_;
};
class Fixture {
public:
    explicit Fixture(ImpairmentProfile profile={}):server(ServerConfig{.bind="127.0.0.1",.accessKey=std::string(64,'a'),.port=0}),link(server.Port(),std::move(profile)) {}
    void Add(SessionClient& c){clients.push_back(&c);}
    void Step(){auto now=net::NowMs();server.Tick(now);for(auto*c:clients)c->Tick(now);server.Tick(net::NowMs());std::this_thread::sleep_for(1ms);}
    template<class F> void Until(F done,std::uint64_t timeoutMs=8000){auto deadline=net::NowMs()+timeoutMs;while(!done()){Step();CHECK(net::NowMs()<deadline);}}
    std::unique_ptr<SessionClient> Make(bool host,Vec3 position,std::uint64_t timeout=5000){
        ClientConfig c;c.server={"127.0.0.1",link.Port()};c.accessKey=std::string(64,'a');c.host=host;c.automaticSnapshots=true;c.timeoutMs=timeout;
        auto client=std::make_unique<SessionClient>(c);client->SetLocal({position,{}});return client;
    }
    SessionServer server;ImpairedLink link;std::vector<SessionClient*> clients;
};
void QueueBounded(){
    auto listener=net::Listen("127.0.0.1",0);CHECK(listener);auto outgoing=net::Connect("127.0.0.1",net::LocalPort(listener));CHECK(outgoing);
    net::Socket incoming;auto deadline=net::NowMs()+2000;while(!incoming){incoming=net::Accept(listener);CHECK(net::NowMs()<deadline);}
    net::Channel channel{std::move(incoming)};const Packet packet{{},Hello{std::string(64,'a')}};
    for(unsigned i=0;i<128;++i)CHECK(channel.Queue(packet));CHECK(!channel.Queue(packet));CHECK(!channel.Open());
}
void MultiplayerImpairment(){
    ImpairmentProfile profile;profile.queueCapacity=64;Fixture f(profile);
    auto host=f.Make(true,{0,0,0});f.Add(*host);auto hostPeer=f.link.Attach(*host);
    f.Until([&]{return host->Phase()==ClientPhase::Active && f.server.Stats().acceptedStates>0;});
    auto a=f.Make(false,{2,0,0});f.Add(*a);auto peerA=f.link.Attach(*a);f.Until([&]{return a->Phase()==ClientPhase::Active;});
    auto b=f.Make(false,{4,0,0});f.Add(*b);auto peerB=f.link.Attach(*b);f.Until([&]{return b->Phase()==ClientPhase::Active;});
    CHECK(f.link.Admission(hostPeer)->player==host->Member().player);CHECK(f.link.Admission(peerA)->player==a->Member().player);CHECK(f.link.Admission(peerB)->player==b->Member().player);
    CHECK(host->Host()==host->Member().player && a->Member().session==b->Member().session && a->Member().player!=b->Member().player);
    CHECK(host->Remotes().contains(a->Member().player) && host->Remotes().contains(b->Member().player));
    CHECK(a->Remotes().contains(host->Member().player) && a->Remotes().contains(b->Member().player));
    CHECK(b->Remotes().contains(host->Member().player) && b->Remotes().contains(a->Member().player));
    auto deadline=net::NowMs()+3000;while(!host->AdoptNpc(7001,123,{{8,0,0},{}})){f.Step();CHECK(net::NowMs()<deadline);}
    f.Until([&]{return host->Npcs().size()==1&&a->Npcs().size()==1&&b->Npcs().size()==1;});const auto npc=host->Npcs().begin()->first;
    const auto profileStart=net::NowMs();f.Until([&]{return net::NowMs()-profileStart>=1100;});
    const auto impaired=f.link.Metrics();CHECK(impaired.statePacketsSeen>0&&impaired.policyDrops>0&&impaired.duplicateCopiesDelivered>0);
    CHECK(f.server.Stats().stale+host->Stats().stale+a->Stats().stale+b->Stats().stale>0);
    f.link.HoldUdp(true);const auto hostAdmission=f.link.Admission(hostPeer);CHECK(hostAdmission.has_value());
    Packet pressure{{host->Member().session,host->Member().epoch,host->Member().player,1,0},NpcState{npc,{{12,0,0},{}},1}};
    for(std::size_t i=0;i<profile.queueCapacity*2;++i)CHECK(f.link.InjectUdp(hostAdmission->token,pressure));
    const auto queueStart=net::NowMs();f.Until([&]{return net::NowMs()-queueStart>=500;});f.link.HoldUdp(false);
    std::this_thread::sleep_for(250ms);const auto bounded=f.link.Metrics();
    CHECK(bounded.maxPending<=profile.queueCapacity && bounded.queueDrops>0);
    f.link.EnableImpairments(false);
    std::uint32_t npcSequence=100;std::uint64_t sample=net::NowMs();const auto stateDeadline=net::NowMs()+3000;
    while(b->Npcs().at(npc).descriptor.sequence<npcSequence){host->SendNpcSnapshot(npc,{{15,0,0},{}},npcSequence,++sample);f.Step();CHECK(net::NowMs()<stateDeadline);}
    const auto oldPlayer=b->Member().player;f.link.BreakControl(peerB);
    f.Until([&]{return b->Phase()==ClientPhase::Failed&&!host->Remotes().contains(oldPlayer);});
    const auto recoveryStart=net::NowMs();const auto reconnectPeer=f.link.Attach(*b);
    f.Until([&]{return b->Phase()==ClientPhase::Active&&b->Member().player!=oldPlayer&&b->Npcs().contains(npc)&&b->Npcs().at(npc).descriptor.sequence==npcSequence;},10000);
    const auto recoveryMs=net::NowMs()-recoveryStart;CHECK(recoveryMs<10000);
    auto admission=f.link.Admission(reconnectPeer);CHECK(admission&&admission->session==host->Member().session&&admission->player==b->Member().player);
    CHECK(SessionServerTestAccess::AdvanceHostEpoch(f.server)==SessionError::None);
    const auto rejected=f.server.Stats().rejected;CHECK(host->SendLocalSnapshot({{0,0,0},{}},0x7fffffffu,net::NowMs()));
    f.Until([&]{return f.server.Stats().rejected>rejected;});CHECK(SessionServerTestAccess::CurrentEpoch(f.server,host->Member().session)==2);
    const double loss=100.0*double(impaired.policyDrops)/double(impaired.statePacketsSeen);
    const double dup=100.0*double(impaired.duplicateCopiesDelivered)/double(impaired.uniqueCopiesDelivered+impaired.duplicateCopiesDelivered);
    std::cout<<"IMPAIRMENT profile="<<profile.name<<" seed="<<profile.seed<<" delay_config_ms="<<profile.delayMs<<" jitter_config_ms="<<profile.jitterMs
      <<" udp_loss_config_pct="<<profile.lossPercent<<" udp_loss_observed_pct="<<loss<<" udp_dup_config_pct="<<profile.duplicatePercent
      <<" udp_dup_observed_pct="<<dup<<" state_seen="<<impaired.statePacketsSeen<<" policy_drops="<<impaired.policyDrops
      <<" duplicate_copies="<<impaired.duplicateCopiesDelivered<<" queue_capacity="<<bounded.queueCapacity<<" queue_max="<<bounded.maxPending
      <<" queue_overflow="<<bounded.queueDrops<<" reconnect_recovery_ms="<<recoveryMs<<" stale_epoch_rejected=true tcp_broken="<<f.link.Metrics().tcpBroken<<'\n';
    f.link.BreakControl(reconnectPeer);f.Until([&]{return b->Phase()==ClientPhase::Failed;});f.link.BreakControl(hostPeer);
}
void StalledControl(){
    Fixture f;auto host=f.Make(true,{0,0,0});f.Add(*host);auto hostPeer=f.link.Attach(*host);f.Until([&]{return host->Phase()==ClientPhase::Active;});
    auto stalled=f.Make(false,{1,0,0},1200);f.Add(*stalled);f.link.StallNextControl();auto peer=f.link.Attach(*stalled);
    f.Until([&]{return stalled->Phase()==ClientPhase::Failed;},3000);CHECK(f.link.WasStalled(peer));CHECK(f.server.Stats().hellos==1);
    f.link.BreakControl(peer);f.link.BreakControl(hostPeer);
    std::cout<<"TCP_CONTROL stalled=true explicit_timeout_ms=1200 server_hellos=1\n";
}
}
int main(){return Run([]{QueueBounded();MultiplayerImpairment();StalledControl();});}