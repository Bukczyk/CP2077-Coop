#include "coop/game_bridge.hpp"
#include <algorithm>
#include <chrono>
#include <stdexcept>
namespace coop::game {
EntityRegistry::EntityRegistry(std::size_t capacity):capacity_(capacity) {
    if(!capacity) throw std::invalid_argument("Empty entity registry");
}
void EntityRegistry::Reset(Identity identity,PlayerId host) {
    identity_=identity; host_=host; entities_.clear(); reverse_.clear();
}
bool EntityRegistry::Accept(Identity identity,Projection p,PlayerId authority) {
    if(identity!=identity_ || !identity.session || !identity.epoch || !host_ || authority!=host_ ||
       !p.id || p.authority!=host_ || p.local || static_cast<unsigned>(p.kind)>static_cast<unsigned>(Kind::World)) return false;
    if(auto it=entities_.find(p.id);it!=entities_.end())
        return it->second.kind==p.kind && it->second.owner==p.owner && it->second.authority==p.authority;
    if(entities_.size()>=capacity_) return false;
    entities_.emplace(p.id,p); return true;
}
bool EntityRegistry::Bind(SessionEntityId id,LocalEntityId local) {
    auto it=entities_.find(id); if(it==entities_.end() || !local) return false;
    if(auto other=reverse_.find(local);other!=reverse_.end() && other->second!=id) return false;
    if(it->second.local) reverse_.erase(it->second.local);
    it->second.local=local; reverse_[local]=id; return true;
}
bool EntityRegistry::Unbind(SessionEntityId id) {
    auto it=entities_.find(id); if(it==entities_.end()) return false;
    reverse_.erase(it->second.local); it->second.local=0; return true;
}
bool EntityRegistry::Remove(SessionEntityId id) {
    auto it=entities_.find(id); if(it==entities_.end()) return false;
    reverse_.erase(it->second.local); entities_.erase(it); return true;
}
const Projection* EntityRegistry::Find(SessionEntityId id) const {
    auto it=entities_.find(id); return it==entities_.end()?nullptr:&it->second;
}
std::optional<SessionEntityId> EntityRegistry::FromLocal(LocalEntityId local) const {
    auto it=reverse_.find(local); if(it==reverse_.end()) return {}; return it->second;
}
EventInbox::EventInbox(std::size_t capacity):capacity_(capacity) {
    if(!capacity) throw std::invalid_argument("Empty event inbox");
}
void EventInbox::Reset(Identity identity,PlayerId authority) {
    std::lock_guard lock(mutex_); identity_=identity; authority_=authority; last_=0; events_.clear();
}
SubmitResult EventInbox::Push(AcceptedEvent event) {
    std::lock_guard lock(mutex_);
    if(!identity_.session || event.identity!=identity_ || event.event!=last_+1) return SubmitResult::Stale;
    if(!authority_ || event.authority!=authority_) return SubmitResult::Authority;
    if(events_.size()>=capacity_) return SubmitResult::Full;
    last_=event.event; events_.push_back(std::move(event)); return SubmitResult::Accepted;
}
std::optional<AcceptedEvent> EventInbox::Pop() {
    std::lock_guard lock(mutex_); if(events_.empty()) return {};
    auto event=std::move(events_.front()); events_.pop_front(); return event;
}
SessionBridge::SessionBridge(ClientConfig config,LogSink log):config_(std::move(config)),log_(std::move(log)) {
    // Validate synchronously so construction errors cannot escape the worker.
    SessionClient validate(config_);
    worker_=std::jthread([this](std::stop_token stop){Run(stop);});
}
SessionBridge::~SessionBridge() { worker_.request_stop(); if(worker_.joinable()) worker_.join(); }
void SessionBridge::SetActive(bool active) {
    std::lock_guard lock(mutex_); if(active_!=active) ++activation_; active_=active;
    if(!active) { local_.reset(); frame_=Frame{}; remote_.clear(); desiredNpcs_.clear(); npcSnapshots_.clear(); npcLocals_.clear(); nextAdoption_=1; }
}
bool SessionBridge::SetLocal(Transform value) {
    if(!Validate(Packet{{1,1,1,1,0},PlayerPose{1,value,1}})) return false;
    std::lock_guard lock(mutex_); local_=value; return true;
}
bool SessionBridge::OfferNpc(LocalEntityId local,std::uint64_t record,Transform transform) {
    if(!config_.host || !local || !Validate(Packet{{1,1,1,0,1},NpcAdopt{1,record,transform}})) return false;
    std::lock_guard lock(mutex_);
    if(!active_) return false;
    auto prior=desiredNpcs_.find(local);
    if(prior!=desiredNpcs_.end()) {
        if(prior->second.releasing || prior->second.record!=record) return false;
        prior->second.transform=transform; return true;
    }
    if(desiredNpcs_.size()>=config_.maxNpcs || nextAdoption_==0) return false;
    desiredNpcs_.emplace(local,DesiredNpc{nextAdoption_++,record,transform,false}); return true;
}
void SessionBridge::ForgetNpc(LocalEntityId local) {
    std::lock_guard lock(mutex_);
    if(auto it=desiredNpcs_.find(local);it!=desiredNpcs_.end()) it->second.releasing=true;
}
Frame SessionBridge::ReadFrame(std::uint64_t now) const {
    std::lock_guard lock(mutex_);
    auto result=frame_;
    for(const auto& [id,remote]:remote_) {
        if(!remote.initialized || now<remote.receivedTime || now-remote.receivedTime>1000) continue;
        if(auto pose=remote.snapshots.Sample(static_cast<double>(now))) result.players.push_back({id,id,*pose});
    }
    for(const auto& [id,npc]:npcSnapshots_) {
        (void)id;
        if(auto pose=npc.snapshots.Sample(static_cast<double>(now))) {
            auto local=npcLocals_.find(npc.descriptor.adoption);
            result.npcs.push_back({npc.descriptor,local==npcLocals_.end()?0:local->second,*pose});
        }
    }
    std::sort(result.npcs.begin(),result.npcs.end(),[](const auto& a,const auto& b){return a.descriptor.entity<b.descriptor.entity;});
    std::sort(result.players.begin(),result.players.end(),[](auto& a,auto& b){return a.player<b.player;});
    return result;
}
void SessionBridge::Run(std::stop_token stop) {
    try {
        SessionClient client(config_,log_);
        bool connected=false;
        std::uint64_t generation=0, observedActivation=0;
        struct Work { bool submitted=false; EntityId entity=0; std::uint32_t sequence=0; };
        std::unordered_map<std::uint64_t,Work> work;
        double nextNpcSample=0;
        while(!stop.stop_requested()) {
            bool active; std::uint64_t activation; std::optional<Transform> local;
            std::unordered_map<LocalEntityId,DesiredNpc> desired;
            { std::lock_guard lock(mutex_); active=active_; activation=activation_; local=local_; desired=desiredNpcs_; }
            if(activation!=observedActivation) { client.Disconnect(); connected=false; observedActivation=activation; work.clear(); nextNpcSample=0; }
            if(active && local && !connected) { client.Connect(); connected=true; ++generation; }
            if(!active && connected) { client.Disconnect(); connected=false; }
            if(connected) {
                if(local) client.SetLocal(*local);
                const auto now=net::NowMs(); client.Tick(now);
                std::vector<LocalEntityId> retired;
                std::unordered_map<std::uint64_t,EntityId> accepted;
                for(const auto& [entity,npc]:client.Npcs()) accepted[npc.descriptor.adoption]=entity;
                const bool sample=static_cast<double>(now)>=nextNpcSample;
                if(client.Phase()==ClientPhase::Active && config_.host) {
                    for(const auto& [engineId,npc]:desired) {
                        auto& state=work[npc.adoption];
                        auto found=accepted.find(npc.adoption);
                        if(found!=accepted.end()) state.entity=found->second;
                        if(npc.releasing) {
                            if(found!=accepted.end()) client.DespawnNpc(found->second);
                            else if(!state.submitted || state.entity || client.NpcDeniedByServer(npc.adoption)) {
                                client.ForgetDeniedNpc(npc.adoption); retired.push_back(engineId);
                            }
                        } else if(found!=accepted.end()) {
                            if(sample) client.SendNpcSnapshot(found->second,npc.transform,++state.sequence,now);
                        } else if(!state.submitted) state.submitted=client.AdoptNpc(npc.adoption,npc.record,npc.transform);
                    }
                    if(sample) nextNpcSample=static_cast<double>(now)+1000.0/config_.npcSnapshotRate;
                }
                std::lock_guard lock(mutex_);
                if(active_ && activation_==activation) {
                    for(auto id:retired) {
                        auto it=desiredNpcs_.find(id);
                        if(it!=desiredNpcs_.end() && it->second.releasing && it->second.adoption==desired.at(id).adoption) {
                            work.erase(it->second.adoption); desiredNpcs_.erase(it);
                        }
                    }
                    frame_={client.Phase(),client.Member(),client.Host(),generation,{},{}};
                    remote_=client.Remotes(); npcSnapshots_=client.Npcs(); npcLocals_.clear();
                    for(const auto& [id,npc]:desiredNpcs_) if(!npc.releasing) npcLocals_[npc.adoption]=id;
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }
        client.Disconnect();
    } catch(const std::exception& error) {
        if(log_) log_(std::string("BRIDGE_ERROR ")+error.what());
        std::lock_guard lock(mutex_); frame_.phase=ClientPhase::Failed; remote_.clear(); npcSnapshots_.clear(); npcLocals_.clear();
    }
}
}
