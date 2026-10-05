#include "coop/client.hpp"
#include <algorithm>
#include <limits>
#include <stdexcept>
namespace coop {
SessionClient::SessionClient(ClientConfig config,LogSink log) : config_(std::move(config)),log_(std::move(log)) {
    if(!Validate(Packet{{},Hello{config_.accessKey}}) || !Validate(Packet{{},CreateSession{config_.sessionName}})
        || !config_.server.port || config_.playerSnapshotRate<1 || config_.playerSnapshotRate>60
        || !config_.maxNpcs || config_.maxNpcs>4096 || config_.npcSnapshotRate<1 || config_.npcSnapshotRate>20
        || config_.vehicleSnapshotRate<1 || config_.vehicleSnapshotRate>60 || config_.timeoutMs<1000)
        throw std::invalid_argument("Invalid client config");
    SnapshotBuffer validation{config_.interpolation};
}
bool SessionClient::Connect() {
    Disconnect();
    auto socket=net::Connect(config_.server.ip,config_.server.port);
    if(!socket) { Fail("TCP_CONNECT_FAILED"); return false; }
    udp_=net::BindUdp("0.0.0.0",0);
    if(!udp_) { Fail("UDP_BIND_FAILED"); return false; }
    control_=net::Channel{std::move(socket)};
    control_.Queue(Packet{{},Hello{config_.accessKey}});
    phase_=ClientPhase::Hello; lastReceive_=net::NowMs(); nextHeartbeat_=0; nextSnapshot_=0;
    sequence_=0; heartbeat_=0; readySent_=false; stats_={};
    Log("HELLO sent"); return true;
}
void SessionClient::Disconnect() {
    control_.Close(); udp_.Close(); members_.clear(); remotes_.clear(); member_={}; host_=0; token_={};
    phase_=ClientPhase::Disconnected; npcs_.clear(); npcDenied_.clear(); npcRequests_.clear(); npcReleasing_.clear(); npcEvent_=0; npcSnapshotReady_=false;
}
void SessionClient::Fail(const std::string& reason) { Disconnect(); phase_=ClientPhase::Failed; Log(reason); }
void SessionClient::Control(const Packet& packet,std::uint64_t now) {
    if(const auto* reject=std::get_if<Reject>(&packet.payload)) {
        Fail("REJECT reason="+std::to_string(static_cast<unsigned>(reject->reason))); return;
    }
    if(phase_==ClientPhase::Hello && std::holds_alternative<HelloOk>(packet.payload)) {
        control_.Queue(Packet{{},config_.host?Payload{CreateSession{config_.sessionName}}:Payload{JoinSession{config_.sessionName}}});
        phase_=ClientPhase::Admission; lastReceive_=now; Log(config_.host?"CREATE_SESSION sent":"JOIN_SESSION sent"); return;
    }
    if(phase_==ClientPhase::Admission) {
        if(const auto* accepted=std::get_if<SessionAccepted>(&packet.payload)) {
            if(accepted->token==ConnectionToken{} || (config_.host!=(accepted->player==accepted->host))) { Fail("INVALID_ADMISSION"); return; }
            member_={packet.header.session,accepted->player,packet.header.epoch,config_.host?Role::Host:Role::Joiner};
            host_=accepted->host; token_=accepted->token; members_.insert(member_.player); members_.insert(host_);
            if(host_!=member_.player) remotes_.try_emplace(host_,config_.interpolation);
            phase_=ClientPhase::Synchronizing; lastReceive_=now;
            Log("SESSION_ACCEPTED session="+std::to_string(member_.session)+" player="+std::to_string(member_.player)+" host="+std::to_string(host_));
            return;
        }
    }
    if(!member_.session || packet.header.session!=member_.session || packet.header.epoch!=member_.epoch || packet.header.sender!=0) {
        Fail("INVALID_CONTROL"); return;
    }
    lastReceive_=now;
    if(std::holds_alternative<SessionReady>(packet.payload)) { phase_=ClientPhase::Active; Log("SESSION_READY"); }
    else if(const auto* joined=std::get_if<MemberJoined>(&packet.payload)) {
        members_.insert(joined->player);
        if(joined->player!=member_.player) remotes_.try_emplace(joined->player,config_.interpolation);
        Log("MEMBER_JOINED player="+std::to_string(joined->player));
    } else if(const auto* left=std::get_if<MemberLeft>(&packet.payload)) {
        members_.erase(left->player); remotes_.erase(left->player); Log("MEMBER_LEFT player="+std::to_string(left->player));
    } else if(const auto* spawn=std::get_if<NpcSpawn>(&packet.payload)) {
        auto prior=npcs_.find(spawn->entity);
        if(prior!=npcs_.end()) {
            if(prior->second.descriptor.adoption!=spawn->adoption || prior->second.descriptor.record!=spawn->record) Fail("NPC_IDENTITY_CHANGED");
            return;
        }
        if(npcs_.size()>=config_.maxNpcs) { Fail("NPC_CAPACITY"); return; }
        auto [it,inserted]=npcs_.try_emplace(spawn->entity,*spawn,config_.interpolation); (void)inserted;
        it->second.snapshots.Push(spawn->sequence,static_cast<double>(now),spawn->transform,spawn->sampleTimeMs);
        Log("NPC_SPAWN entity="+std::to_string(spawn->entity));
    } else if(const auto* removed=std::get_if<NpcRemoved>(&packet.payload)) {
        auto it=npcs_.find(removed->entity);
        if(it!=npcs_.end()) npcRequests_.erase(it->second.descriptor.adoption);
        npcs_.erase(removed->entity); npcReleasing_.erase(removed->entity);
        Log("NPC_REMOVED entity="+std::to_string(removed->entity));
    } else if(std::holds_alternative<NpcSnapshotEnd>(packet.payload)) {
        npcSnapshotReady_=true; Log("NPC_SNAPSHOT_COMPLETE");
    } else if(const auto* denied=std::get_if<NpcDenied>(&packet.payload)) {
        if(!config_.host || !npcRequests_.contains(denied->adoption)) { Fail("UNEXPECTED_NPC_DENIAL"); return; }
        npcDenied_.insert(denied->adoption);
        Log("NPC_ADOPTION_DENIED"); // Retain bounded request to avoid retrying a denied token.
    } else if(std::holds_alternative<SessionClosed>(packet.payload)) Fail("SESSION_CLOSED");
    else Fail("UNEXPECTED_CONTROL");
}
bool SessionClient::Snapshot(PlayerId player,const Packet& packet,const Transform& value,std::uint64_t sourceTime,std::uint64_t now) {
    auto it=remotes_.find(player);
    if(it==remotes_.end() || !sourceTime) { ++stats_.rejected; return false; }
    auto& remote=it->second;
    if(!remote.snapshots.Push(packet.header.sequence,static_cast<double>(now),value,sourceTime)) { ++stats_.stale; return false; }
    if(!remote.initialized) Log("PLAYER_STATE player="+std::to_string(player));
    remote.sequence=packet.header.sequence; remote.sourceTime=sourceTime; remote.receivedTime=now; remote.initialized=true;
    ++stats_.received; return true;
}
void SessionClient::State(const net::Datagram& d,std::uint64_t now) {
    if(!member_.session || d.sender!=config_.server || d.data.size()<16+kHeaderSize || d.data.size()>16+kMaxPacketSize
        || !std::equal(token_.begin(),token_.end(),d.data.begin())) { ++stats_.rejected; return; }
    const auto parsed=Decode(std::span<const std::uint8_t>(d.data).subspan(16));
    if(!parsed) { ++stats_.rejected; return; }
    const auto& packet=*parsed.packet;
    if(packet.header.session!=member_.session || packet.header.epoch!=member_.epoch) { ++stats_.rejected; return; }
    if(std::holds_alternative<Heartbeat>(packet.payload) && packet.header.sender==member_.player) { lastReceive_=now; return; }
    if(const auto* state=std::get_if<NpcState>(&packet.payload)) {
        auto it=npcs_.find(state->entity);
        if(config_.host || packet.header.sender!=host_ || it==npcs_.end()) { ++stats_.rejected; return; }
        if(!it->second.snapshots.Push(packet.header.sequence,static_cast<double>(now),state->transform,state->sampleTimeMs)) { ++stats_.stale; return; }
        auto& descriptor=it->second.descriptor; descriptor.transform=state->transform;
        descriptor.sequence=packet.header.sequence; descriptor.sampleTimeMs=state->sampleTimeMs;
        lastReceive_=now; ++stats_.received; return;
    }
    if(const auto* pose=std::get_if<PlayerPose>(&packet.payload)) {
        if(!config_.host || phase_!=ClientPhase::Active || pose->entity!=packet.header.sender || !members_.contains(packet.header.sender)) {
            ++stats_.rejected; return;
        }
        if(Snapshot(packet.header.sender,packet,pose->transform,pose->sampleTimeMs,now)) {
            // Initial movement test: HOST accepts bounded, finite owned player poses.
            // Gameplay movement plausibility rules can replace this authority decision later.
            Packet approved{{member_.session,member_.epoch,member_.player,packet.header.sequence,0},
                PlayerState{pose->entity,pose->transform,pose->sampleTimeMs}};
            net::SendUdp(udp_,config_.server,token_,approved); ++stats_.sent;
        }
        lastReceive_=now; return;
    }
    if(const auto* state=std::get_if<PlayerState>(&packet.payload)) {
        if(config_.host || packet.header.sender!=host_ || state->entity>std::numeric_limits<PlayerId>::max()) { ++stats_.rejected; return; }
        const auto player=static_cast<PlayerId>(state->entity);
        if(player==member_.player) return;
        if(Snapshot(player,packet,state->transform,state->sampleTimeMs,now)) {
            lastReceive_=now;

        }
        return;
    }
    ++stats_.rejected;
}
bool SessionClient::SendLocalSnapshot(Transform value,std::uint32_t sequence,std::uint64_t time) {
    if(phase_!=ClientPhase::Active) return false;
    Packet packet{{member_.session,member_.epoch,member_.player,sequence,0},
        config_.host?Payload{PlayerState{member_.player,value,time}}:Payload{PlayerPose{member_.player,value,time}}};
    const bool result=net::SendUdp(udp_,config_.server,token_,packet);
    if(result) ++stats_.sent;
    return result;
}
bool SessionClient::AdoptNpc(std::uint64_t adoption,std::uint64_t record,Transform transform) {
    if(!config_.host || phase_!=ClientPhase::Active) return false;
    if(auto prior=npcRequests_.find(adoption);prior!=npcRequests_.end()) return prior->second.record==record;
    if(npcRequests_.size()>=config_.maxNpcs || control_.Pending()) return false;
    NpcAdopt request{adoption,record,transform};
    if(!control_.Queue(Packet{{member_.session,member_.epoch,member_.player,0,npcEvent_+1},request})) return false;
    ++npcEvent_; npcRequests_.emplace(adoption,request); return true;
}
void SessionClient::ForgetDeniedNpc(std::uint64_t adoption) {
    if(npcDenied_.erase(adoption)) npcRequests_.erase(adoption);
}
bool SessionClient::DespawnNpc(EntityId entity) {
    if(!config_.host || phase_!=ClientPhase::Active || !npcs_.contains(entity)) return false;
    if(npcReleasing_.contains(entity)) return true;
    if(control_.Pending()) return false;
    if(!control_.Queue(Packet{{member_.session,member_.epoch,member_.player,0,npcEvent_+1},NpcDespawn{entity}})) return false;
    ++npcEvent_; npcReleasing_.insert(entity); return true;
}
bool SessionClient::SendNpcSnapshot(EntityId entity,Transform transform,std::uint32_t sequence,std::uint64_t time) {
    if(!config_.host || phase_!=ClientPhase::Active || !npcs_.contains(entity) || npcReleasing_.contains(entity)) return false;
    Packet packet{{member_.session,member_.epoch,member_.player,sequence,0},NpcState{entity,transform,time}};
    const bool sent=net::SendUdp(udp_,config_.server,token_,packet);
    if(sent) ++stats_.sent;
    return sent;
}
void SessionClient::Tick(std::uint64_t now) {
    if(phase_==ClientPhase::Disconnected || phase_==ClientPhase::Failed) return;
    std::vector<Packet> incoming;
    if(!control_.Pump(incoming)) { Fail("CONTROL_DISCONNECTED"); return; }
    for(const auto& packet:incoming) {
        Control(packet,now);
        if(phase_==ClientPhase::Failed) return;
    }
    for(unsigned i=0;i<2048;++i) { auto d=net::ReceiveUdp(udp_); if(!d) break; State(*d,now); }
    if(phase_==ClientPhase::Synchronizing && !config_.host && npcSnapshotReady_ && !readySent_
        && remotes_.contains(host_) && remotes_.at(host_).initialized) {
        if(control_.Queue(Packet{{member_.session,member_.epoch,member_.player,0,0},Ready{}})) readySent_=true;
    }
    if(now>=lastReceive_ && now-lastReceive_>config_.timeoutMs) { Fail("SESSION_TIMEOUT"); return; }
    if(member_.session && now>=nextHeartbeat_) {
        net::SendUdp(udp_,config_.server,token_,Packet{{member_.session,member_.epoch,member_.player,++heartbeat_,0},Heartbeat{}});
        nextHeartbeat_=now+500;
    }
    if(phase_==ClientPhase::Active && config_.automaticSnapshots && local_ && static_cast<double>(now)>=nextSnapshot_) {
        SendLocalSnapshot(*local_,++sequence_,now);
        nextSnapshot_=static_cast<double>(now)+1000.0/config_.playerSnapshotRate;
    }
}
} // namespace coop
