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
    if(!active) { local_.reset(); frame_=Frame{}; remote_.clear(); }
}
bool SessionBridge::SetLocal(Transform value) {
    if(!Validate(Packet{{1,1,1,1,0},PlayerPose{1,value,1}})) return false;
    std::lock_guard lock(mutex_); local_=value; return true;
}
Frame SessionBridge::ReadFrame(std::uint64_t now) const {
    std::lock_guard lock(mutex_);
    auto result=frame_;
    for(const auto& [id,remote]:remote_) {
        if(!remote.initialized || now<remote.receivedTime || now-remote.receivedTime>1000) continue;
        if(auto pose=remote.snapshots.Sample(static_cast<double>(now))) result.players.push_back({id,id,*pose});
    }
    std::sort(result.players.begin(),result.players.end(),[](auto& a,auto& b){return a.player<b.player;});
    return result;
}
void SessionBridge::Run(std::stop_token stop) {
    try {
        SessionClient client(config_,log_);
        bool connected=false;
        std::uint64_t generation=0, observedActivation=0;
        while(!stop.stop_requested()) {
            bool active; std::uint64_t activation; std::optional<Transform> local;
            { std::lock_guard lock(mutex_); active=active_; activation=activation_; local=local_; }
            if(activation!=observedActivation) { client.Disconnect(); connected=false; observedActivation=activation; }
            if(active && local && !connected) { client.Connect(); connected=true; ++generation; }
            if(!active && connected) { client.Disconnect(); connected=false; }
            if(connected) {
                if(local) client.SetLocal(*local);
                client.Tick(net::NowMs());
                std::lock_guard lock(mutex_);
                if(active_ && activation_==activation) {
                    frame_={client.Phase(),client.Member(),client.Host(),generation,{}};
                    remote_=client.Remotes();
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }
        client.Disconnect();
    } catch(const std::exception& error) {
        if(log_) log_(std::string("BRIDGE_ERROR ")+error.what());
        std::lock_guard lock(mutex_); frame_.phase=ClientPhase::Failed; remote_.clear();
    }
}
}
