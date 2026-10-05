#pragma once
#include "coop/client.hpp"
#include <deque>
#include <mutex>
#include <thread>
namespace coop::game {
using SessionEntityId = EntityId;
// Opaque engine EntityID value; never an address, never dereferenced by networking.
using LocalEntityId = std::uint64_t;
enum class Kind { Player, NPC, Vehicle, World };
struct Identity {
    SessionId session=0;
    std::uint32_t epoch=0;
    bool operator==(const Identity&) const = default;
};
struct Projection {
    SessionEntityId id=0;
    Kind kind=Kind::World;
    PlayerId owner=0, authority=0;
    LocalEntityId local=0;
};
// Game-thread-only registry. IDs must originate from accepted server registry records.
class EntityRegistry {
public:
    explicit EntityRegistry(std::size_t capacity=4096);
    void Reset(Identity identity,PlayerId host);
    bool Accept(Identity identity,Projection projection,PlayerId authority);
    bool Bind(SessionEntityId id,LocalEntityId local);
    bool Remove(SessionEntityId id);
    bool Unbind(SessionEntityId id);
    const Projection* Find(SessionEntityId id) const;
    std::optional<SessionEntityId> FromLocal(LocalEntityId local) const;
    std::size_t Size() const { return entities_.size(); }
private:
    Identity identity_{};
    PlayerId host_=0;
    std::size_t capacity_;
    std::unordered_map<SessionEntityId,Projection> entities_;
    std::unordered_map<LocalEntityId,SessionEntityId> reverse_;
};
// Local game-adapter contracts, NOT new wire packet declarations. Unsupported until
// the server allocation/authority/event route and corresponding engine hooks exist.
struct EntityAdopt { SessionEntityId entity; Kind kind; LocalEntityId local; };
struct EntitySpawn { SessionEntityId entity; Kind kind; Transform transform; };
struct EntityDespawn { SessionEntityId entity; };
struct NpcState { SessionEntityId entity; Transform transform; std::uint32_t sequence; };
struct PlayerFire { SessionEntityId shooter; Vec3 origin,direction; std::uint64_t action; };
struct WorldStimulus { SessionEntityId source; Vec3 position; float radius; };
struct HitRequest { SessionEntityId attacker,target; float proposedDamage; std::uint64_t action; };
struct DamageApplied { SessionEntityId attacker,target; float damage; std::uint64_t request; };
struct EntityDeath { SessionEntityId entity; std::uint64_t cause; };
using WorldAction=std::variant<EntityAdopt,EntitySpawn,EntityDespawn,NpcState,PlayerFire,WorldStimulus,HitRequest,DamageApplied,EntityDeath>;
struct AcceptedEvent { Identity identity; PlayerId authority; std::uint64_t event; WorldAction action; };
enum class SubmitResult { Accepted, Unsupported, Full, Stale, Authority };
// Separate reliable game-thread inbox; overflow is explicit, never drops oldest.
class EventInbox {
public:
    explicit EventInbox(std::size_t capacity=256);
    void Reset(Identity identity,PlayerId authority);
    SubmitResult Push(AcceptedEvent event);
    std::optional<AcceptedEvent> Pop();
private:
    std::mutex mutex_;
    std::size_t capacity_;
    Identity identity_{};
    PlayerId authority_=0;
    std::uint64_t last_=0;
    std::deque<AcceptedEvent> events_;
};
struct RenderPlayer { PlayerId player=0; SessionEntityId entity=0; Transform transform{}; };
struct RenderNpc { NpcSpawn descriptor{}; LocalEntityId hostLocal=0; Transform transform{}; };
struct Frame {
    ClientPhase phase=ClientPhase::Disconnected;
    Membership member{};
    PlayerId host=0;
    std::uint64_t generation=0;
    std::vector<RenderPlayer> players;
    std::vector<RenderNpc> npcs;
};
// Worker owns SessionClient. Only value snapshots cross the mutex. Render sampling
// happens in ReadFrame at the caller's frame time, independently of network ticks.
class SessionBridge {
public:
    explicit SessionBridge(ClientConfig config,LogSink log={});
    ~SessionBridge();
    SessionBridge(const SessionBridge&)=delete;
    SessionBridge& operator=(const SessionBridge&)=delete;
    void SetActive(bool active);
    bool SetLocal(Transform transform);
    Frame ReadFrame(std::uint64_t now) const;
    bool OfferNpc(LocalEntityId local,std::uint64_t record,Transform transform);
    void ForgetNpc(LocalEntityId local);
    SubmitResult SubmitWorld(const WorldAction&) { return SubmitResult::Unsupported; }
private:
    void Run(std::stop_token stop);
    ClientConfig config_;
    LogSink log_;
    mutable std::mutex mutex_;
    bool active_=false;
    std::uint64_t activation_=0;
    std::optional<Transform> local_;
    Frame frame_;
    std::unordered_map<PlayerId,RemotePlayer> remote_;
    struct DesiredNpc { std::uint64_t adoption=0, record=0; Transform transform{}; bool releasing=false; };
    std::uint64_t nextAdoption_=1;
    std::unordered_map<LocalEntityId,DesiredNpc> desiredNpcs_;
    std::unordered_map<EntityId,RemoteNpc> npcSnapshots_;
    std::unordered_map<std::uint64_t,LocalEntityId> npcLocals_;
    std::jthread worker_;
};
} // namespace coop::game
