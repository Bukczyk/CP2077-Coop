#include "coop/server.hpp"
#include <algorithm>
#include <cmath>
#include <stdexcept>
namespace coop {
namespace {
Packet serverPacket(const Membership& m, Payload payload) { return {{m.session,m.epoch,0,0,0},std::move(payload)}; }
float distance(Vec3 a, Vec3 b) {
    return std::sqrt((a.x-b.x)*(a.x-b.x)+(a.y-b.y)*(a.y-b.y)+(a.z-b.z)*(a.z-b.z));
}
bool equalKey(const std::string& a,const std::string& b) {
    if(a.size()!=b.size()) return false;
    unsigned difference=0;
    for(std::size_t i=0;i<a.size();++i) difference|=static_cast<unsigned char>(a[i]^b[i]);
    return difference==0;
}
}
SessionServer::SessionServer(ServerConfig config,LogSink log)
    : config_(std::move(config)),log_(std::move(log)),registry_(config_.limits) {
    if(!Validate(Packet{{},Hello{config_.accessKey}}) || config_.maxConnections<config_.limits.maxMembers
        || config_.snapshotRate<1 || config_.snapshotRate>60 || config_.distantRate<1 || config_.distantRate>config_.snapshotRate
        || !std::isfinite(config_.nearDistance) || !std::isfinite(config_.interestDistance)
        || config_.npcSnapshotRate<1 || config_.npcSnapshotRate>20 || config_.npcDistantRate<1 || config_.npcDistantRate>config_.npcSnapshotRate
        || config_.nearDistance<=0 || config_.interestDistance<config_.nearDistance)
        throw std::invalid_argument("Invalid server config");
    listener_=net::Listen(config_.bind,config_.port);
    if(!listener_) throw std::runtime_error("TCP bind failed");
    udp_=net::BindUdp(config_.bind,Port());
    if(!udp_) throw std::runtime_error("UDP bind failed");
    Log("LISTEN tcp+udp="+std::to_string(Port())+" max_players="+std::to_string(config_.limits.maxMembers));
}
void SessionServer::RejectPeer(Peer& p,RejectReason reason,std::uint64_t now) {
    ++stats_.rejected;
    p.control.Queue(Packet{{},Reject{reason}}); p.closing=now+100;
    Log("REJECT reason="+std::to_string(static_cast<unsigned>(reason)));
}
void SessionServer::Control(ConnectionId id,Peer& p,const Packet& packet,std::uint64_t now) {
    if(p.closing) return;
    if(!p.authorized) {
        const auto* hello=std::get_if<Hello>(&packet.payload);
        if(!hello || !equalKey(hello->key,config_.accessKey)) { RejectPeer(p,RejectReason::Auth,now); return; }
        p.authorized=true; ++stats_.hellos; p.control.Queue(Packet{{},HelloOk{}});
        Log("HELLO_OK connection="+std::to_string(id)); return;
    }
    if(!p.member) {
        const auto* create=std::get_if<CreateSession>(&packet.payload);
        const auto* join=std::get_if<JoinSession>(&packet.payload);
        if(!create && !join) { RejectPeer(p,RejectReason::Protocol,now); return; }
        const auto& name=create?create->name:join->name;
        if(create && names_.contains(name)) { RejectPeer(p,RejectReason::NameInUse,now); return; }
        if(join && !names_.contains(name)) { RejectPeer(p,RejectReason::MissingSession,now); return; }
        const auto admission=create?registry_.Create(id,now):registry_.Join(names_.at(name),id,now);
        if(!admission) { RejectPeer(p,RejectReason::Full,now); return; }
        p.member=admission.membership;
        const auto& m=*p.member;
        if(registry_.RegisterPlayer(m.session,m.player)!=SessionError::None) {
            registry_.Disconnect(id); p.member.reset(); RejectPeer(p,RejectReason::Full,now); return;
        }
        p.token=net::RandomToken();
        if(create) { names_[name]=m.session; rooms_.emplace(m.session,Room{name,{}}); ++stats_.creates; }
        else ++stats_.joins;
        const auto* s=registry_.Find(m.session);
        p.control.Queue(serverPacket(m,SessionAccepted{m.player,s->host,p.token}));
        for(auto& [peerId,other]:peers_) {
            if(peerId==id || !other.member || other.member->session!=m.session || other.closing) continue;
            p.control.Queue(serverPacket(m,MemberJoined{other.member->player}));
            other.control.Queue(serverPacket(*other.member,MemberJoined{m.player}));
        }
        for(const auto& [npcId,npc]:s->npcs) { (void)npcId; QueueNpc(p,npc); }
        QueueNpc(p,NpcSnapshotEnd{});
        if(create) p.control.Queue(serverPacket(m,SessionReady{}));
        Log(std::string(create?"CREATE_SESSION":"JOIN_SESSION")+" session="+std::to_string(m.session)
            +" player="+std::to_string(m.player)+" host="+std::to_string(s->host));
        return;
    }
    const auto& m=*p.member;
    if(packet.header.session!=m.session || packet.header.epoch!=m.epoch || packet.header.sender!=m.player) {
        RejectPeer(p,RejectReason::Policy,now); return;
    }
    if(std::holds_alternative<Ready>(packet.payload) && p.baselineSent) {
        if(registry_.MarkSynchronized(m.session,m.player,m.epoch)!=SessionError::None) {
            RejectPeer(p,RejectReason::Policy,now); return;
        }
        p.control.Queue(serverPacket(m,SessionReady{}));
        Log("SESSION_READY session="+std::to_string(m.session)+" player="+std::to_string(m.player)); return;
    }
    if(std::holds_alternative<NpcAdopt>(packet.payload) || std::holds_alternative<NpcDespawn>(packet.payload)) {
        const auto accepted=registry_.Receive(id,packet,now);
        if(!accepted) { RejectPeer(p,RejectReason::Policy,now); return; }
        if(accepted.npcDenied) { QueueNpc(p,NpcDenied{std::get<NpcAdopt>(packet.payload).adoption}); return; }
        for(auto& [unused,peer]:peers_) {
            (void)unused;
            if(!peer.member || peer.member->session!=m.session || peer.closing) continue;
            if(accepted.adopted) QueueNpc(peer,*accepted.adopted);
            else {
                auto entity=std::get<NpcDespawn>(packet.payload).entity;
                QueueNpc(peer,NpcRemoved{entity}); peer.sent.erase(entity); peer.sourceTimes.erase(entity);
            }
        }
        Log(accepted.adopted?"NPC_ADOPTED entity="+std::to_string(accepted.adopted->entity):"NPC_DESPAWN");
        return;
    }
    if(std::holds_alternative<Leave>(packet.payload)) { p.closing=now+1; return; }
    RejectPeer(p,RejectReason::Protocol,now);
}
void SessionServer::State(const net::Datagram& d,std::uint64_t now) {
    if(d.data.size()<16+kHeaderSize || d.data.size()>16+kMaxPacketSize) { ++stats_.rejected; return; }
    const auto decoded=Decode(std::span<const std::uint8_t>(d.data).subspan(16));
    if(!decoded) { ++stats_.rejected; return; }
    const auto& packet=*decoded.packet;
    for(auto& [connection,p]:peers_) {
        if(!p.member || p.closing || !std::equal(p.token.begin(),p.token.end(),d.data.begin())) continue;
        const auto& m=*p.member;
        if(packet.header.session!=m.session || packet.header.sender!=m.player || packet.header.epoch!=m.epoch
            || (p.endpoint && *p.endpoint!=d.sender)) { ++stats_.rejected; return; }
        if(now-p.window>=1000) { p.window=now; p.frames=0; }
        if(++p.frames > 120+config_.snapshotRate*config_.limits.maxMembers*2+config_.npcSnapshotRate*config_.limits.maxNpcs*2) { ++stats_.rejected; return; }
        if(std::holds_alternative<NpcState>(packet.payload)) {
            const auto accepted=registry_.Receive(connection,packet,now);
            if(accepted) { p.endpoint=d.sender; ++stats_.acceptedStates; }
            else if(accepted.error==SessionError::Stale) ++stats_.stale;
            else ++stats_.rejected;
            return;
        }
        const auto* pose=std::get_if<PlayerPose>(&packet.payload);
        const auto* state=std::get_if<PlayerState>(&packet.payload);
        const bool heartbeat=std::holds_alternative<Heartbeat>(packet.payload);
        if(!pose && !state && !heartbeat) { ++stats_.rejected; return; }
        EntityId entity=pose?pose->entity:state?state->entity:0;
        const std::uint64_t time=pose?pose->sampleTimeMs:state?state->sampleTimeMs:0;
        if(entity && (!time || (p.sourceTimes.contains(entity) && time<=p.sourceTimes.at(entity)))) { ++stats_.stale; return; }
        const auto accepted=registry_.Receive(connection,packet,now);
        if(!accepted) {
            if(accepted.error==SessionError::Stale || accepted.error==SessionError::Duplicate) ++stats_.stale;
            else ++stats_.rejected;
            return;
        }
        p.endpoint=d.sender;
        if(heartbeat) { net::SendUdp(udp_,d.sender,p.token,packet); return; }
        p.sourceTimes[entity]=time;
        if(pose) {
            for(auto& [unused,host]:peers_) {
                (void)unused;
                if(host.member && host.member->session==m.session && host.member->role==Role::Host && host.endpoint && !host.closing)
                    net::SendUdp(udp_,*host.endpoint,host.token,packet);
            }
        } else {
            rooms_.at(m.session).states[entity]=packet; ++stats_.acceptedStates;
        }
        return;
    }
    ++stats_.rejected;
}
void SessionServer::RouteStates(std::uint64_t now) {
    for(auto& [unused,p]:peers_) {
        (void)unused;
        if(!p.member || !p.endpoint || p.closing || p.member->role==Role::Host) continue;
        const auto& m=*p.member;
        const auto* session=registry_.Find(m.session);
        if(!session) continue;
        const bool active=session->members.at(m.player).phase==Phase::Active;
        const auto& states=rooms_.at(m.session).states;
        const auto observer=states.find(m.player);
        for(const auto& [entity,packet]:states) {
            if(entity==m.player) continue;
            const auto& state=std::get<PlayerState>(packet.payload);
            unsigned rate=config_.snapshotRate;
            if(!active || observer==states.end()) {
                if(entity!=session->host) continue; // HOST baseline is required before spatial relevance is known.
            } else {
                const float d=distance(std::get<PlayerState>(observer->second.payload).transform.position,state.transform.position);
                if(d>config_.interestDistance) { ++stats_.filtered; continue; }
                if(d>config_.nearDistance) rate=config_.distantRate;
            }
            auto& sent=p.sent[entity];
            if(sent.initialized && now-sent.time < static_cast<std::uint64_t>(1000/rate)) continue;
            if(active && sent.initialized && sent.sequence==packet.header.sequence) continue;
            if(net::SendUdp(udp_,*p.endpoint,p.token,packet)) {
                sent={packet.header.sequence,now,true}; ++stats_.routed;
                if(entity==session->host) p.baselineSent=true;
            }
        }
    }
}
void SessionServer::QueueNpc(Peer& p,Payload payload) {
    if(!p.member || p.npcOutbox.size()>=2*config_.limits.maxNpcs+16) { p.control.Close(); return; }
    p.npcOutbox.push_back(serverPacket(*p.member,std::move(payload)));
}
void SessionServer::RouteNpcs(std::uint64_t now) {
    for(auto& [unused,p]:peers_) {
        (void)unused;
        if(!p.member || !p.endpoint || p.closing || p.member->role==Role::Host) continue;
        const auto& m=*p.member; const auto* session=registry_.Find(m.session);
        if(!session || session->members.at(m.player).phase!=Phase::Active) continue;
        const auto& playerStates=rooms_.at(m.session).states;
        const auto observer=playerStates.find(m.player); if(observer==playerStates.end()) continue;
        auto position=std::get<PlayerState>(observer->second.payload).transform.position;
        for(const auto& [entity,npc]:session->npcs) {
            if(!npc.sampleTimeMs) continue;
            const auto d=distance(position,npc.transform.position);
            if(d>config_.interestDistance) { ++stats_.filtered; continue; }
            const auto rate=d>config_.nearDistance?config_.npcDistantRate:config_.npcSnapshotRate;
            auto& sent=p.sent[entity];
            if(sent.initialized && now-sent.time<1000/rate) continue;
            // Repeat latest state after loss/interest re-entry; clients reject duplicates.
            Packet packet{{m.session,m.epoch,session->host,npc.sequence,0},NpcState{entity,npc.transform,npc.sampleTimeMs}};
            if(net::SendUdp(udp_,*p.endpoint,p.token,packet)) { sent={npc.sequence,now,true}; ++stats_.routed; }
        }
    }
}
void SessionServer::NotifyRemoval(const Removal& r,std::uint64_t now) {
    auto room=rooms_.find(r.session);
    if(room!=rooms_.end()) {
        if(r.closed) { names_.erase(room->second.name); rooms_.erase(room); }
        else for(auto entity:r.entities) room->second.states.erase(entity);
    }
    for(auto& [unused,p]:peers_) {
        (void)unused;
        if(!p.member || p.member->session!=r.session || p.member->player==r.player) continue;
        if(r.closed) { p.control.Queue(serverPacket(*p.member,SessionClosed{})); p.closing=now+100; }
        else {
            p.control.Queue(serverPacket(*p.member,MemberLeft{r.player}));
            for(auto entity:r.entities) { p.sent.erase(entity); p.sourceTimes.erase(entity); }
        }
    }
    Log("DISCONNECT session="+std::to_string(r.session)+" player="+std::to_string(r.player)+(r.closed?" SESSION_CLOSED":""));
}
void SessionServer::Tick(std::uint64_t now) {
    for(unsigned i=0;i<16;++i) {
        auto socket=net::Accept(listener_); if(!socket) break;
        if(peers_.size()>=config_.maxConnections) continue;
        Peer peer; peer.control=net::Channel{std::move(socket)}; peer.connected=now;
        peers_.emplace(nextConnection_++,std::move(peer));
    }
    for(auto& [id,p]:peers_) {
        std::vector<Packet> incoming;
        if(!p.control.Pump(incoming)) continue;
        if(!p.control.Pending()) {
            for(unsigned i=0;i<8 && !p.npcOutbox.empty();++i) {
                if(!p.control.Queue(p.npcOutbox.front())) break;
                p.npcOutbox.pop_front();
            }
        }
        if(incoming.size()>32) { RejectPeer(p,RejectReason::Protocol,now); continue; }
        for(const auto& packet:incoming) Control(id,p,packet,now);
        if(!p.member && now-p.connected>5000) RejectPeer(p,RejectReason::Timeout,now);
        if(p.closing && (now>=p.closing || !p.control.Pending())) p.control.Close();
    }
    for(unsigned i=0;i<2048;++i) { auto d=net::ReceiveUdp(udp_); if(!d) break; State(*d,now); }
    for(const auto& removal:registry_.Expire(now)) {
        NotifyRemoval(removal,now);
        for(auto& [unused,p]:peers_) {
            (void)unused;
            if(p.member && p.member->session==removal.session && p.member->player==removal.player) p.control.Close();
        }
    }
    for(auto it=peers_.begin();it!=peers_.end();) {
        if(it->second.control.Open()) { ++it; continue; }
        if(auto removed=registry_.Disconnect(it->first)) NotifyRemoval(*removed,now);
        it=peers_.erase(it);
    }
    RouteStates(now); RouteNpcs(now);
}
} // namespace coop
