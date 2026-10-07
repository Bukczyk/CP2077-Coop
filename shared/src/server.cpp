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
        || !config_.gameplayRequestCapacity || config_.gameplayMemberCapacity<config_.limits.maxMembers
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
GameplayLedger* SessionServer::EnsureGameplayLedger(SessionId id) {
    const auto* session=registry_.Find(id);
    if(!session) return nullptr;
    auto it=gameplayLedgers_.find(id);
    if(it==gameplayLedgers_.end()) {
        auto ledger=std::make_unique<GameplayLedger>(GameplayRequestScope{id,session->epoch},
            config_.gameplayRequestCapacity,config_.gameplayMemberCapacity);
        it=gameplayLedgers_.emplace(id,std::move(ledger)).first;
    } else {
        const auto scope=it->second->Scope();
        if(scope.epoch!=session->epoch) {
            if(!it->second->Reset({id,session->epoch})) return nullptr;
        }
    }
    for(const auto& [player,unused]:session->members) {
        (void)unused;
        const auto result=it->second->AddMember(player);
        if(result!=RequestMemberResult::Added && result!=RequestMemberResult::AlreadyActive) return nullptr;
    }
    return it->second.get();
}
bool SessionServer::QueueGameplayStatus(Peer& peer,const Membership& member,std::uint64_t request,
    GameplayDisposition disposition,std::uint16_t reason,bool committed) {
    if(!peer.control.CanQueue()) return false;
    return peer.control.Queue(serverPacket(member,GameplayStatus{request,disposition,reason,committed}));
}
Packet SessionServer::CachedResult(const GameplayRequestKey& key,const CachedGameplayOutcome& value) const {
    const auto* session=registry_.Find(key.session);
    if(!session || value.bodySize>value.body.size() || !value.hostEvent) return {};
    std::vector<std::uint8_t> body(value.body.begin(),value.body.begin()+value.bodySize);
    return {{key.session,key.epoch,session->host,0,value.hostEvent},
        GameplayResult{key.sender,key.event,value.kind,value.disposition,value.reason,std::move(body)}};
}
void SessionServer::GameplayIntentMessage(ConnectionId id,Peer& peer,const Packet& packet,std::uint64_t now) {
    if(!peer.member || peer.member->role!=Role::Joiner) { RejectPeer(peer,RejectReason::Policy,now); return; }
    const auto member=*peer.member;
    if(!peer.control.CanQueue()) { peer.control.Close(); return; }
    auto* ledger=EnsureGameplayLedger(member.session);
    const auto* session=registry_.Find(member.session);
    if(!ledger || !session) { QueueGameplayStatus(peer,member,packet.header.event,GameplayDisposition::Full); return; }
    const GameplayRequestKey key{member.session,member.epoch,member.player,packet.header.event};
    const auto admission=ledger->Begin(key);
    if(admission.result==RequestLedgerResult::DuplicatePending) {
        QueueGameplayStatus(peer,member,key.event,GameplayDisposition::Pending); return;
    }
    if(admission.result==RequestLedgerResult::DuplicateCommitted) {
        if(!admission.replay) { RejectPeer(peer,RejectReason::Policy,now); return; }
        const auto& cached=admission.replay->value;
        if(cached.hostEvent) {
            if(peer.control.CanQueue()) peer.control.Queue(CachedResult(key,cached));
        } else {
            QueueGameplayStatus(peer,member,key.event,cached.disposition,cached.reason,true);
        }
        return;
    }
    if(admission.result==RequestLedgerResult::Capacity) {
        const auto accepted=registry_.Receive(id,packet,now);
        if(!accepted && accepted.error!=SessionError::Duplicate) {
            QueueGameplayStatus(peer,member,key.event,GameplayDisposition::Rejected,static_cast<std::uint16_t>(accepted.error)); return;
        }
        QueueGameplayStatus(peer,member,packet.header.event,GameplayDisposition::Full,0,true); return;
    }
    if(admission.result!=RequestLedgerResult::New) {
        QueueGameplayStatus(peer,member,key.event,GameplayDisposition::Rejected,static_cast<std::uint16_t>(admission.result)); return;
    }
    const auto hostMember=session->members.find(session->host);
    auto hostPeer=hostMember==session->members.end()?peers_.end():peers_.find(hostMember->second.connection);
    if(hostPeer==peers_.end() || !hostPeer->second.member || hostPeer->second.closing
        || !hostPeer->second.control.CanQueue()) {
        const auto accepted=registry_.Receive(id,packet,now);
        if(!accepted) {
            ledger->CancelPending(key);
            QueueGameplayStatus(peer,member,key.event,GameplayDisposition::Rejected,static_cast<std::uint16_t>(accepted.error)); return;
        }
        CachedGameplayOutcome cached{};
        cached.kind=std::get<GameplayIntent>(packet.payload).kind;
        cached.disposition=GameplayDisposition::Full; cached.reason=1;
        ledger->Commit(key,GameplayRequestStatus::Full,cached);
        QueueGameplayStatus(peer,member,key.event,GameplayDisposition::Full,cached.reason,true); return;
    }
    const auto accepted=registry_.Receive(id,packet,now);
    if(!accepted) {
        ledger->CancelPending(key);
        QueueGameplayStatus(peer,member,key.event,GameplayDisposition::Rejected,static_cast<std::uint16_t>(accepted.error)); return;
    }
    if(accepted.route!=Route::Host || accepted.recipients.size()!=1 || accepted.recipients.front()!=session->host
        || !hostPeer->second.control.Queue(packet)) {
        CachedGameplayOutcome cached{}; cached.kind=std::get<GameplayIntent>(packet.payload).kind;
        cached.disposition=GameplayDisposition::Full; cached.reason=1;
        ledger->Commit(key,GameplayRequestStatus::Full,cached);
        QueueGameplayStatus(peer,member,key.event,GameplayDisposition::Full,cached.reason,true); return;
    }
    QueueGameplayStatus(peer,member,key.event,GameplayDisposition::Pending);
}
void SessionServer::GameplayResultMessage(ConnectionId id,Peer& peer,const Packet& packet,std::uint64_t now) {
    if(!peer.member || peer.member->role!=Role::Host) { RejectPeer(peer,RejectReason::Policy,now); return; }
    const auto member=*peer.member;
    const auto& result=std::get<GameplayResult>(packet.payload);
    if(!peer.control.CanQueue()) { peer.control.Close(); return; }
    auto* ledger=EnsureGameplayLedger(member.session);
    const GameplayRequestKey key{member.session,member.epoch,result.requester,result.requestEvent};
    if(!ledger) { QueueGameplayStatus(peer,member,packet.header.event,GameplayDisposition::Full); return; }
    const auto admission=ledger->Begin(key);
    if(admission.result==RequestLedgerResult::DuplicateCommitted) {
        if(!admission.replay) { RejectPeer(peer,RejectReason::Policy,now); return; }
        const auto& cached=admission.replay->value;
        const auto replay=CachedResult(key,cached);
        if(!cached.hostEvent || cached.hostEvent!=packet.header.event || replay.payload!=packet.payload) {
            QueueGameplayStatus(peer,member,packet.header.event,GameplayDisposition::Rejected,2,false); return;
        }
        const auto* session=registry_.Find(member.session);
        if(session) {
            const auto requester=session->members.find(result.requester);
            if(requester!=session->members.end()) {
                const auto target=peers_.find(requester->second.connection);
                if(target!=peers_.end() && target->second.member && target->second.control.CanQueue())
                    target->second.control.Queue(replay);
            }
        }
        QueueGameplayStatus(peer,member,cached.hostEvent,result.disposition,result.reason,true); return;
    }
    if(admission.result==RequestLedgerResult::New) {
        ledger->CancelPending(key);
        const auto consumed=registry_.Receive(id,packet,now);
        if(!consumed) {
            QueueGameplayStatus(peer,member,packet.header.event,GameplayDisposition::Rejected,static_cast<std::uint16_t>(consumed.error)); return;
        }
        QueueGameplayStatus(peer,member,packet.header.event,GameplayDisposition::Rejected,
            static_cast<std::uint16_t>(RequestLedgerResult::MissingRequest)); return;
    }
    if(admission.result!=RequestLedgerResult::DuplicatePending) {
        QueueGameplayStatus(peer,member,packet.header.event,GameplayDisposition::Rejected,static_cast<std::uint16_t>(admission.result)); return;
    }
    const auto* session=registry_.Find(member.session);
    if(!session) { QueueGameplayStatus(peer,member,key.event,GameplayDisposition::Rejected); return; }
    for(const auto& [player,active]:session->members) {
        if(player==session->host || active.phase!=Phase::Active || now<active.lastSeen
            || now-active.lastSeen>=config_.limits.timeoutMs) continue;
        const auto recipient=peers_.find(active.connection);
        if(recipient==peers_.end() || !recipient->second.member || recipient->second.closing
            || !recipient->second.control.CanQueue()) {
            QueueGameplayStatus(peer,member,packet.header.event,GameplayDisposition::Full); return;
        }
    }
    const auto accepted=registry_.Receive(id,packet,now);
    if(!accepted) {
        QueueGameplayStatus(peer,member,key.event,GameplayDisposition::Rejected,static_cast<std::uint16_t>(accepted.error)); return;
    }
    CachedGameplayOutcome cached{}; cached.hostEvent=packet.header.event; cached.kind=result.kind;
    cached.disposition=result.disposition; cached.reason=result.reason;
    cached.bodySize=static_cast<std::uint16_t>(result.body.size());
    std::copy(result.body.begin(),result.body.end(),cached.body.begin());
    const auto committed=ledger->Commit(key,static_cast<GameplayRequestStatus>(static_cast<unsigned>(result.disposition)-static_cast<unsigned>(GameplayDisposition::Accepted)),cached);
    if(committed!=RequestLedgerResult::Committed) { RejectPeer(peer,RejectReason::Policy,now); return; }
    for(const auto recipientId:accepted.recipients) {
        const auto recipientMember=session->members.find(recipientId);
        if(recipientMember==session->members.end()) continue;
        const auto recipient=peers_.find(recipientMember->second.connection);
        if(recipient!=peers_.end()) recipient->second.control.Queue(packet);
    }
    QueueGameplayStatus(peer,member,packet.header.event,result.disposition,result.reason,true);
}void SessionServer::RejectPeer(Peer& p,RejectReason reason,std::uint64_t now) {
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
        if(!EnsureGameplayLedger(m.session)) {
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
    if(std::holds_alternative<GameplayIntent>(packet.payload)) { GameplayIntentMessage(id,p,packet,now); return; }
    if(std::holds_alternative<GameplayResult>(packet.payload)) { GameplayResultMessage(id,p,packet,now); return; }
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
    if(auto ledger=gameplayLedgers_.find(r.session);ledger!=gameplayLedgers_.end()) {
        if(r.closed) gameplayLedgers_.erase(ledger);
        else ledger->second->RemoveMember(r.player);
    }
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
