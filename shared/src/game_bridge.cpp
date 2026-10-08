#include "coop/game_bridge.hpp"
#include <algorithm>
#include <chrono>
#include <charconv>
#include <limits>
#include <stdexcept>
namespace coop::game {
std::optional<std::uint64_t> ParseGameplayId(const std::string& value) {
    if(value.empty() || value.size()>20 || (value.size()>1 && value.front()=='0')) return {};
    std::uint64_t id=0;
    const auto parsed=std::from_chars(value.data(),value.data()+value.size(),id);
    if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size()) return {};
    return id;
}
std::optional<std::vector<std::uint8_t>> DecodeGameplayHex(const std::string& value) {
    if(value.size()>2*kMaxGameplayBodySize || value.size()%2) return {};
    const auto digit=[](char c)->int { return c>='0' && c<='9'?c-'0':c>='a' && c<='f'?c-'a'+10:c>='A' && c<='F'?c-'A'+10:-1; };
    std::vector<std::uint8_t> bytes; bytes.reserve(value.size()/2);
    for(std::size_t i=0;i<value.size();i+=2) {
        const auto a=digit(value[i]),b=digit(value[i+1]);
        if(a<0 || b<0) return {};
        bytes.push_back(static_cast<std::uint8_t>(a*16+b));
    }
    return bytes;
}
std::string EncodeGameplaySubmission(GameplaySubmission value) {
    switch(value.status) {
    case GameplayAdmission::Queued: return "queued|"+std::to_string(value.ticket);
    case GameplayAdmission::Inactive: return "inactive";
    case GameplayAdmission::Stale: return "stale";
    case GameplayAdmission::Authority: return "authority";
    case GameplayAdmission::Invalid: return "invalid";
    case GameplayAdmission::Full: return "full";
    case GameplayAdmission::Missing: return "missing";
    }
    return "invalid";
}
std::string EncodeGameplayEvent(const GameplayEvent& value) {
    const auto scope="|"+std::to_string(value.scope.identity.session)+"|"+std::to_string(value.scope.identity.epoch)+"|"+std::to_string(value.scope.generation);
    const auto hex=[](const std::vector<std::uint8_t>& bytes) {
        constexpr char digits[]="0123456789abcdef";
        std::string text; text.reserve(bytes.size()*2);
        for(auto byte:bytes) { text+=digits[byte>>4]; text+=digits[byte&15]; }
        return text;
    };
    const auto& h=value.packet.header;
    switch(value.type) {
    case GameplayEventType::Intent: {
        const auto& p=std::get<GameplayIntent>(value.packet.payload);
        return "intent"+scope+"|"+std::to_string(h.sender)+"|"+std::to_string(h.event)+"|"+std::to_string(p.kind)+"|"+hex(p.body);
    }
    case GameplayEventType::Outcome: {
        const auto& p=std::get<GameplayResult>(value.packet.payload);
        return "outcome"+scope+"|"+std::to_string(h.sender)+"|"+std::to_string(h.event)+"|"+std::to_string(p.requester)+"|"+std::to_string(p.requestEvent)+"|"+std::to_string(p.kind)+"|"+std::to_string(static_cast<unsigned>(p.disposition))+"|"+std::to_string(p.reason)+"|"+hex(p.body);
    }
    case GameplayEventType::SentIntent:
    case GameplayEventType::SentResult:
        return std::string(value.type==GameplayEventType::SentIntent?"sent_intent":"sent_result")+scope+"|"+std::to_string(value.ticket)+"|"+std::to_string(value.event);
    case GameplayEventType::Status:
        return "status"+scope+"|"+std::to_string(value.status.correlationEvent)+"|"+std::to_string(static_cast<unsigned>(value.status.disposition))+"|"+std::to_string(value.status.reason)+"|"+(value.status.committed?"1":"0");
    }
    return {};
}
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
    if(!active) { local_.reset(); frame_=Frame{}; remote_.clear(); desiredNpcs_.clear(); npcSnapshots_.clear(); npcLocals_.clear(); nextAdoption_=1; ClearGameplay(); gameplayFault_.clear(); }
}
void SessionBridge::ClearGameplay() {
    gameplayCommands_.clear(); gameplayEvents_.clear(); gameplayPending_.clear(); nextGameplayTicket_=1;
}
GameplayAdmission SessionBridge::CheckGameplayScope(GameplayScope scope) const {
    if(!active_ || frame_.phase!=ClientPhase::Active || !gameplayFault_.empty()) return GameplayAdmission::Inactive;
    if(scope.identity!=Identity{frame_.member.session,frame_.member.epoch} || scope.generation!=frame_.generation)
        return GameplayAdmission::Stale;
    return GameplayAdmission::Queued;
}
GameplaySubmission SessionBridge::SubmitGameplay(GameplayScope scope,std::uint16_t kind,std::vector<std::uint8_t> body) {
    std::lock_guard lock(mutex_);
    if(auto status=CheckGameplayScope(scope);status!=GameplayAdmission::Queued) return {status,0};
    if(config_.host) return {GameplayAdmission::Authority,0};
    if(!kind || body.size()>kMaxGameplayBodySize) return {GameplayAdmission::Invalid,0};
    if(gameplayCommands_.size()>=config_.gameplayQueueCapacity || nextGameplayTicket_==std::numeric_limits<std::uint64_t>::max()) return {GameplayAdmission::Full,0};
    const auto ticket=nextGameplayTicket_++;
    gameplayCommands_.push_back({ticket,{kind,std::move(body)}});
    return {GameplayAdmission::Queued,ticket};
}
GameplaySubmission SessionBridge::CompleteGameplay(GameplayScope scope,GameplayResult result) {
    std::lock_guard lock(mutex_);
    if(auto status=CheckGameplayScope(scope);status!=GameplayAdmission::Queued) return {status,0};
    if(!config_.host) return {GameplayAdmission::Authority,0};
    if(!Validate(Packet{{scope.identity.session,scope.identity.epoch,frame_.member.player,0,1},result})) return {GameplayAdmission::Invalid,0};
    auto it=gameplayPending_.find({result.requester,result.requestEvent});
    if(it==gameplayPending_.end()) return {GameplayAdmission::Missing,0};
    auto& pending=it->second;
    if(pending.result) return *pending.result==result?GameplaySubmission{GameplayAdmission::Queued,pending.ticket}:GameplaySubmission{GameplayAdmission::Invalid,0};
    if(nextGameplayTicket_==std::numeric_limits<std::uint64_t>::max()) return {GameplayAdmission::Full,0};
    pending.ticket=nextGameplayTicket_++; pending.result=std::move(result);
    return {GameplayAdmission::Queued,pending.ticket};
}
std::optional<GameplayEvent> SessionBridge::PopGameplay() {
    std::lock_guard lock(mutex_);
    if(!active_ || frame_.phase!=ClientPhase::Active || !gameplayFault_.empty() || gameplayEvents_.empty()) return {};
    auto event=std::move(gameplayEvents_.front()); gameplayEvents_.pop_front(); return event;
}
std::string SessionBridge::GameplayFault() const { std::lock_guard lock(mutex_); return gameplayFault_; }
bool SessionBridge::ServiceGameplay(SessionClient& client,std::uint64_t generation,std::uint64_t now) {
    const auto fail=[&](const char* reason) {
        gameplayFault_=reason; ClearGameplay(); client.Disconnect(); return false;
    };
    if(client.Phase()==ClientPhase::Failed || client.Phase()==ClientPhase::Disconnected) {
        if((client.Phase()==ClientPhase::Failed && gameplayFault_.empty()) || frame_.phase==ClientPhase::Active || !gameplayCommands_.empty() || !gameplayPending_.empty() || !gameplayEvents_.empty()) {
            gameplayFault_="transport_failed_scope_invalidated";
            ClearGameplay();
        }
        return false;
    }
    if(client.Phase()!=ClientPhase::Active) return false;
    const GameplayScope scope{{client.Member().session,client.Member().epoch},generation};
    const auto room=[&]{return gameplayEvents_.size()<config_.gameplayQueueCapacity;};
    while(room()) {
        auto status=client.PopGameplayStatus(); if(!status) break;
        if(config_.host) {
            auto pending=std::find_if(gameplayPending_.begin(),gameplayPending_.end(),[&](const auto& entry) {return entry.second.hostEvent && entry.second.hostEvent==status->correlationEvent;});
            if(pending!=gameplayPending_.end()) {
                if(status->committed) gameplayPending_.erase(pending);
                else if(status->disposition==GameplayDisposition::Full) pending->second.retryAt=now+50;
                else if(status->disposition!=GameplayDisposition::Pending)
                    return fail("GAMEPLAY_RESULT_REJECTED_EFFECT_MAY_BE_COMMITTED");
            } else if(status->disposition==GameplayDisposition::Full && !status->committed) {
                // Includes the client's automatic inbox-Full responses. Fail
                // explicitly rather than silently wedge the shared event stream.
                return fail("GAMEPLAY_UNTRACKED_RESULT_BACKPRESSURE");
            } else if(!status->committed && status->disposition!=GameplayDisposition::Pending) {
                return fail("GAMEPLAY_UNTRACKED_RESULT_REJECTED");
            }
        }
        GameplayEvent event; event.type=GameplayEventType::Status; event.scope=scope; event.status=*status;
        gameplayEvents_.push_back(std::move(event));
    }
    // Reserve ticket headroom for every exposed request as well as result bytes.
    // Tickets are assigned on completion to preserve application ordering.
    while(room() && gameplayPending_.size()<config_.gameplayQueueCapacity
        && nextGameplayTicket_<std::numeric_limits<std::uint64_t>::max()-gameplayPending_.size()) {
        auto packet=client.PopGameplayIntent(); if(!packet) break;
        const auto key=std::pair{packet->header.sender,packet->header.event};
        if(auto prior=gameplayPending_.find(key);prior!=gameplayPending_.end()) {
            if(prior->second.request!=*packet) return fail("GAMEPLAY_REQUEST_IDENTITY_CHANGED");
            continue;
        }
        // Reserve immutable request/result storage BEFORE exposing an engine job.
        PendingGameplay pending; pending.request=*packet;
        gameplayPending_.emplace(key,std::move(pending));
        GameplayEvent event; event.type=GameplayEventType::Intent; event.scope=scope; event.packet=std::move(*packet);
        gameplayEvents_.push_back(std::move(event));
    }
    while(room()) {
        auto packet=client.PopGameplayOutcome(); if(!packet) break;
        GameplayEvent event; event.type=GameplayEventType::Outcome; event.scope=scope; event.packet=std::move(*packet);
        gameplayEvents_.push_back(std::move(event));
    }
    // Serialize HOST results until the server acknowledges the current one.
    // NPC lifecycle shares its event stream; the caller pauses those writes too.
    auto inFlight=std::find_if(gameplayPending_.begin(),gameplayPending_.end(),[](const auto& entry){return entry.second.hostEvent!=0;});
    if(inFlight!=gameplayPending_.end()) {
        auto& pending=inFlight->second;
        if(pending.retryAt && now>=pending.retryAt && client.RetryGameplayResult(pending.hostEvent)) pending.retryAt=0;
        return true;
    }
    // Completion order is application order, independent of requester PlayerId.
    auto ready=gameplayPending_.end();
    for(auto it=gameplayPending_.begin();it!=gameplayPending_.end();++it)
        if(it->second.result && (ready==gameplayPending_.end() || it->second.ticket<ready->second.ticket)) ready=it;
    if(ready!=gameplayPending_.end()) {
        if(room()) {
            auto& pending=ready->second; const auto& result=*pending.result;
            if(auto eventId=client.SendGameplayResult(result.requester,result.requestEvent,result.kind,result.disposition,result.reason,result.body)) {
                pending.hostEvent=*eventId;
                GameplayEvent event; event.type=GameplayEventType::SentResult; event.scope=scope; event.ticket=pending.ticket; event.event=*eventId;
                gameplayEvents_.push_back(std::move(event));
            }
        }
        return true;
    }
    while(room() && !gameplayCommands_.empty()) {
        const auto& command=gameplayCommands_.front();
        auto eventId=client.SendGameplayIntent(command.intent.kind,command.intent.body);
        if(!eventId) break; // bounded transport busy: retain the original command
        GameplayEvent event; event.type=GameplayEventType::SentIntent; event.scope=scope; event.ticket=command.ticket; event.event=*eventId;
        gameplayEvents_.push_back(std::move(event)); gameplayCommands_.pop_front();
    }
    return false;
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
                bool resultPending=false;
                {
                    std::lock_guard lock(mutex_);
                    if(active_ && activation_==activation) resultPending=ServiceGameplay(client,generation,now);
                }
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
                            if(found!=accepted.end()) { if(!resultPending) client.DespawnNpc(found->second); }
                            else if(!state.submitted || state.entity || client.NpcDeniedByServer(npc.adoption)) {
                                client.ForgetDeniedNpc(npc.adoption); retired.push_back(engineId);
                            }
                        } else if(found!=accepted.end()) {
                            if(sample) client.SendNpcSnapshot(found->second,npc.transform,++state.sequence,now);
                        } else if(!state.submitted && !resultPending) state.submitted=client.AdoptNpc(npc.adoption,npc.record,npc.transform);
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
                    frame_={gameplayFault_.empty()?client.Phase():ClientPhase::Failed,client.Member(),client.Host(),generation,{},{}};
                    remote_=client.Remotes(); npcSnapshots_=client.Npcs(); npcLocals_.clear();
                    for(const auto& [id,npc]:desiredNpcs_) if(!npc.releasing) npcLocals_[npc.adoption]=id;
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }
        client.Disconnect();
    } catch(const std::exception& error) {
        if(log_) log_(std::string("BRIDGE_ERROR ")+error.what());
        std::lock_guard lock(mutex_); gameplayFault_=error.what(); ClearGameplay(); frame_.phase=ClientPhase::Failed; remote_.clear(); npcSnapshots_.clear(); npcLocals_.clear();
    }
}
}
