#pragma once
#include "coop/protocol.hpp"
#include <map>
#include <unordered_map>

namespace coop {
// Issued by a future authenticated transport adapter, NEVER decoded from a packet.
using ConnectionId = std::uint64_t;
enum class Role { Host, Joiner };
enum class Phase { Synchronizing, Active };
enum class SessionError {
    None, Invalid, Capacity, MissingSession, MissingMember, ConnectionInUse,
    Identity, Epoch, NotReady, Authority, MissingEntity, Ownership, Kind,
    Stale, Duplicate, EventGap, Expired, Clock, EntityReuse
};
enum class Route { None, Host, Peers };
struct Membership {
    SessionId session = 0;
    PlayerId player = 0;
    std::uint32_t epoch = 0;
    Role role = Role::Joiner;
};
struct Admission {
    std::optional<Membership> membership;
    SessionError error = SessionError::None;
    explicit operator bool() const { return membership.has_value(); }
};
struct Member {
    PlayerId id = 0;
    ConnectionId connection = 0;
    Role role = Role::Joiner;
    Phase phase = Phase::Synchronizing;
    std::uint64_t lastSeen = 0, lastEvent = 0;
    std::map<std::pair<PacketType, EntityId>, std::uint32_t> sequences;
};
struct Entity {
    EntityKind kind = EntityKind::World;
    PlayerId owner = 0;
    Transform transform{};
};
struct Session {
    SessionId id = 0;
    std::uint32_t epoch = 1;
    PlayerId host = 0;
    EntityId lastEntity = 0;
    std::unordered_map<PlayerId, Member> members;
    std::unordered_map<EntityId, Entity> entities;
    EntityId lastNpc=kNpcEntityBase-1;
    std::unordered_map<EntityId,NpcSpawn> npcs;
    // Tombstones prevent an adoption token from resurrecting a retired NPC.
    std::unordered_map<std::uint64_t,EntityId> npcAdoptions;
};
struct Removal {
    SessionId session = 0;
    PlayerId player = 0;
    bool closed = false;
    std::vector<PlayerId> notify;
    std::vector<EntityId> entities;
};
struct ReceiveResult {
    SessionError error = SessionError::None;
    Route route = Route::None;
    std::vector<PlayerId> recipients;
    std::optional<Removal> removal;
    std::optional<NpcSpawn> adopted;
    bool npcDenied=false;
    explicit operator bool() const { return error == SessionError::None; }
};
// Single-threaded policy core: the owning server serializes calls. No sockets,
// credential issuance, retransmission scheduler or game simulation lives here.
struct SessionLimits {
    std::size_t maxSessions = 16, maxMembers = 16, maxEntities = 4096;
    std::uint64_t timeoutMs = 10000;
    std::size_t maxNpcs = 128;
};
class SessionRegistry {
public:
    explicit SessionRegistry(SessionLimits limits = {});
    Admission Create(ConnectionId connection, std::uint64_t now);
    Admission Join(SessionId session, ConnectionId connection, std::uint64_t now);
    // Trusted adapter calls this only after complete snapshot acknowledgment.
    SessionError RegisterPlayer(SessionId session, PlayerId player);
    SessionError MarkSynchronized(SessionId session, PlayerId player, std::uint32_t epoch);
    ReceiveResult Receive(ConnectionId connection, const Packet& packet, std::uint64_t now);
    std::optional<Removal> Disconnect(ConnectionId connection);
    std::vector<Removal> Expire(std::uint64_t now);
    SessionError ResetWorld(ConnectionId hostConnection);
    const Session* Find(SessionId id) const;
    std::size_t Size() const { return sessions_.size(); }
private:
    SessionLimits limits_;
    bool ConnectionUsed(ConnectionId connection) const;
    SessionId nextSession_ = 1;
    PlayerId nextPlayer_ = 1;
    std::unordered_map<SessionId, Session> sessions_;
};
} // namespace coop
