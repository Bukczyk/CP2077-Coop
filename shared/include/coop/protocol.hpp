#pragma once
#include <cstdint>
#include <array>
#include <optional>
#include <span>
#include <string>
#include <variant>
#include <vector>

namespace coop {
using SessionId = std::uint64_t;
using PlayerId = std::uint32_t;
using EntityId = std::uint64_t;
using VehicleId = EntityId;
using ConnectionToken = std::array<std::uint8_t,16>;
constexpr std::uint16_t kProtocolVersion = 4;
constexpr std::size_t kHeaderSize = 40;
constexpr std::size_t kMaxPacketSize = 1200;

enum class PacketType : std::uint16_t {
    Heartbeat = 1, Leave = 2, Ack = 3,
    Hello = 0x10, HelloOk, CreateSession, JoinSession, SessionAccepted,
    Reject, MemberJoined, MemberLeft, SessionClosed, Ready, SessionReady,
    PlayerPose = 0x100, PlayerState = 0x101,
    VehicleInput = 0x200, VehicleState = 0x201,
    HitRequest = 0x300, DamageApplied = 0x301,
    EntitySpawn = 0x400, EntityDespawn = 0x401, WorldState = 0x402,
    NpcAdopt = 0x500, NpcSpawn, NpcDespawn, NpcRemoved, NpcState, NpcSnapshotEnd, NpcDenied,
    GameplayIntent = 0x600, GameplayResult, GameplayStatus
};
enum class EntityKind : std::uint8_t { Player = 1, Vehicle = 2, World = 3, NPC = 4 };
struct Header {
    SessionId session = 0;
    std::uint32_t epoch = 0;
    PlayerId sender = 0;
    std::uint32_t sequence = 0;
    std::uint64_t event = 0;
    bool operator==(const Header&) const = default;
};
struct Vec3 {
    float x = 0, y = 0, z = 0;
    bool operator==(const Vec3&) const = default;
};
// Euler angles in radians; rotation is never a packet discriminator.
struct Transform {
    Vec3 position{}, rotation{};
    bool operator==(const Transform&) const = default;
};
struct Heartbeat { bool operator==(const Heartbeat&) const = default; };
struct Leave { bool operator==(const Leave&) const = default; };
struct Ack {
    std::uint64_t event = 0;
    bool operator==(const Ack&) const = default;
};
struct PlayerPose {
    EntityId entity = 0;
    Transform transform{};
    std::uint64_t sampleTimeMs = 0;
    bool operator==(const PlayerPose&) const = default;
};
struct PlayerState {
    EntityId entity = 0;
    Transform transform{};
    std::uint64_t sampleTimeMs = 0;
    bool operator==(const PlayerState&) const = default;
};
struct VehicleInput {
    EntityId entity = 0;
    float throttle = 0, steering = 0, brake = 0;
    bool operator==(const VehicleInput&) const = default;
};
struct VehicleState {
    EntityId entity = 0;
    Transform transform{};
    std::uint64_t sampleTimeMs = 0;
    bool operator==(const VehicleState&) const = default;
};
struct HitRequest {
    EntityId attacker = 0, target = 0;
    float proposedDamage = 0;
    bool operator==(const HitRequest&) const = default;
};
struct DamageApplied {
    EntityId attacker = 0, target = 0;
    float damage = 0;
    std::uint64_t request = 0;
    bool operator==(const DamageApplied&) const = default;
};
struct EntitySpawn {
    EntityId entity = 0;
    EntityKind kind = EntityKind::World;
    PlayerId owner = 0;
    Transform transform{};
    bool operator==(const EntitySpawn&) const = default;
};
struct EntityDespawn {
    EntityId entity = 0;
    bool operator==(const EntityDespawn&) const = default;
};
struct WorldState {
    EntityId entity = 0;
    Transform transform{};
    bool operator==(const WorldState&) const = default;
};
struct Hello { std::string key; bool operator==(const Hello&) const = default; };
struct HelloOk { bool operator==(const HelloOk&) const = default; };
struct CreateSession { std::string name; bool operator==(const CreateSession&) const = default; };
struct JoinSession { std::string name; bool operator==(const JoinSession&) const = default; };
struct SessionAccepted {
    PlayerId player = 0, host = 0;
    ConnectionToken token{};
    bool operator==(const SessionAccepted&) const = default;
};
enum class RejectReason : std::uint16_t { Auth = 1, Protocol, NameInUse, MissingSession, Full, Policy, Timeout, HostLeft };
struct Reject { RejectReason reason = RejectReason::Protocol; bool operator==(const Reject&) const = default; };
struct MemberJoined { PlayerId player = 0; bool operator==(const MemberJoined&) const = default; };
struct MemberLeft { PlayerId player = 0; bool operator==(const MemberLeft&) const = default; };
struct SessionClosed { bool operator==(const SessionClosed&) const = default; };
struct Ready { bool operator==(const Ready&) const = default; };
struct SessionReady { bool operator==(const SessionReady&) const = default; };
// NPC IDs are allocated by the session server, disjoint from PlayerId space.
constexpr EntityId kNpcEntityBase = EntityId{1} << 32;
struct NpcAdopt {
    std::uint64_t adoption=0, record=0;
    Transform transform{};
    bool operator==(const NpcAdopt&) const = default;
};
struct NpcSpawn {
    EntityId entity=0;
    std::uint64_t adoption=0, record=0;
    Transform transform{};
    std::uint32_t sequence=0;
    std::uint64_t sampleTimeMs=0;
    bool operator==(const NpcSpawn&) const = default;
};
struct NpcDespawn { EntityId entity=0; bool operator==(const NpcDespawn&) const = default; };
struct NpcRemoved { EntityId entity=0; bool operator==(const NpcRemoved&) const = default; };
struct NpcState {
    EntityId entity=0; Transform transform{}; std::uint64_t sampleTimeMs=0;
    bool operator==(const NpcState&) const = default;
};
struct NpcSnapshotEnd { bool operator==(const NpcSnapshotEnd&) const = default; };
struct NpcDenied { std::uint64_t adoption=0; bool operator==(const NpcDenied&) const = default; };
// Opaque reliable gameplay values. Their kind/body schemas are owned by a
// separately reviewed application adapter; the session backend does not parse them.
constexpr std::size_t kMaxGameplayBodySize = 1024;
enum class GameplayDisposition : std::uint8_t { Pending=1, Accepted, Rejected, Unsupported, Full };
struct GameplayIntent {
    std::uint16_t kind=0;
    std::vector<std::uint8_t> body;
    bool operator==(const GameplayIntent&) const = default;
};
struct GameplayResult {
    PlayerId requester=0;
    std::uint64_t requestEvent=0;
    std::uint16_t kind=0;
    GameplayDisposition disposition=GameplayDisposition::Rejected;
    std::uint16_t reason=0;
    std::vector<std::uint8_t> body;
    bool operator==(const GameplayResult&) const = default;
};
// Server-to-requester receipt on the ordered TCP control channel. It has no
// independent event stream; requestEvent correlates it with the sender's intent.
struct GameplayStatus {
    std::uint64_t correlationEvent=0;
    GameplayDisposition disposition=GameplayDisposition::Pending;
    std::uint16_t reason=0;
    bool committed=false;
    bool operator==(const GameplayStatus&) const = default;
};
using Payload = std::variant<Heartbeat, Leave, Ack, PlayerPose, PlayerState,
    VehicleInput, VehicleState, HitRequest, DamageApplied, EntitySpawn, EntityDespawn, WorldState, Hello, HelloOk, CreateSession, JoinSession,
    SessionAccepted, Reject, MemberJoined, MemberLeft, SessionClosed, Ready, SessionReady,
    NpcAdopt, NpcSpawn, NpcDespawn, NpcRemoved, NpcState, NpcSnapshotEnd, NpcDenied,
    GameplayIntent, GameplayResult, GameplayStatus>;
struct Packet {
    Header header{};
    Payload payload{};
    bool operator==(const Packet&) const = default;
};
enum class CodecError { None, Size, Magic, Version, Type, Length, InvalidValue };
struct DecodeResult {
    std::optional<Packet> packet;
    CodecError error = CodecError::None;
    explicit operator bool() const { return packet.has_value(); }
};
PacketType TypeOf(const Payload& payload);
bool IsReliable(PacketType type);
bool IsNewer(std::uint32_t candidate, std::uint32_t previous);
bool Validate(const Packet& packet);
std::optional<std::vector<std::uint8_t>> Encode(const Packet& packet);
DecodeResult Decode(std::span<const std::uint8_t> bytes);
} // namespace coop
