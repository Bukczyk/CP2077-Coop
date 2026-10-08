#include "coop/protocol.hpp"
#include <array>
#include <bit>
#include <cmath>
#include <limits>
#include <type_traits>

namespace coop {
namespace {
static_assert(sizeof(float) == 4 && std::numeric_limits<float>::is_iec559);
constexpr std::uint32_t kMagic = 0x43505331; // CPS1
constexpr std::array<PacketType, 33> kTypes{
    PacketType::Heartbeat, PacketType::Leave, PacketType::Ack,
    PacketType::PlayerPose, PacketType::PlayerState, PacketType::VehicleInput,
    PacketType::VehicleState, PacketType::HitRequest, PacketType::DamageApplied,
    PacketType::EntitySpawn, PacketType::EntityDespawn, PacketType::WorldState,
    PacketType::Hello, PacketType::HelloOk, PacketType::CreateSession, PacketType::JoinSession,
    PacketType::SessionAccepted, PacketType::Reject, PacketType::MemberJoined, PacketType::MemberLeft,
    PacketType::SessionClosed, PacketType::Ready, PacketType::SessionReady,
    PacketType::NpcAdopt, PacketType::NpcSpawn, PacketType::NpcDespawn, PacketType::NpcRemoved,
    PacketType::NpcState, PacketType::NpcSnapshotEnd, PacketType::NpcDenied,
    PacketType::GameplayIntent, PacketType::GameplayResult, PacketType::GameplayStatus};
constexpr std::array<std::uint32_t, 33> kSizes{0, 0, 8, 40, 40, 20, 40, 20, 28, 37, 8, 32, 64, 0, 32, 32, 24, 2, 4, 4, 0, 0, 0, 40, 60, 8, 8, 40, 0, 8, 0, 0, 12};
struct Writer {
    std::vector<std::uint8_t> data;
    void integer(std::uint64_t value, unsigned width) {
        for (unsigned i = width; i > 0; --i)
            data.push_back(static_cast<std::uint8_t>(value >> ((i - 1) * 8)));
    }
    void bytes(const std::vector<std::uint8_t>& value) { data.insert(data.end(),value.begin(),value.end()); }
    void text(const std::string& value, unsigned width) {
        for (unsigned i = 0; i < width; ++i) integer(i < value.size() ? static_cast<unsigned char>(value[i]) : 0, 1);
    }
    void scalar(float value) { integer(std::bit_cast<std::uint32_t>(value), 4); }
    void vector(Vec3 v) { scalar(v.x); scalar(v.y); scalar(v.z); }
    void transform(const Transform& t) { vector(t.position); vector(t.rotation); }
};
// Decode checks the exact type-specific size before any payload reads.
struct Reader {
    std::span<const std::uint8_t> data;
    std::size_t offset = 0;
    bool canonical = true;
    std::string text(unsigned width) {
        std::string value; bool end = false;
        for (unsigned i = 0; i < width; ++i) {
            char c = static_cast<char>(integer(1));
            if (!c) end = true;
            else if (end) canonical = false;
            else value.push_back(c);
        }
        return value;
    }
    std::uint64_t integer(unsigned width) {
        std::uint64_t value = 0;
        for (unsigned i = 0; i < width; ++i) value = (value << 8) | data[offset++];
        return value;
    }
    std::vector<std::uint8_t> bytes(std::size_t count) {
        if(offset>data.size() || count>data.size()-offset) { canonical=false; return {}; }
        std::vector<std::uint8_t> value(data.begin()+static_cast<std::ptrdiff_t>(offset),data.begin()+static_cast<std::ptrdiff_t>(offset+count));
        offset+=count; return value;
    }
    bool boolean() { const auto value=integer(1); if(value>1) canonical=false; return value!=0; }
    std::uint32_t u32() { return static_cast<std::uint32_t>(integer(4)); }
    float scalar() { return std::bit_cast<float>(u32()); }
    Vec3 vector() { return {scalar(), scalar(), scalar()}; }
    Transform transform() { return {vector(), vector()}; }
};
bool bounded(float value, float low, float high) {
    return std::isfinite(value) && value >= low && value <= high;
}
bool valid(const Transform& t) {
    const auto& p = t.position;
    const auto& r = t.rotation;
    return bounded(p.x, -1000000, 1000000) && bounded(p.y, -1000000, 1000000)
        && bounded(p.z, -1000000, 1000000) && bounded(r.x, -6.283186f, 6.283186f)
        && bounded(r.y, -6.283186f, 6.283186f) && bounded(r.z, -6.283186f, 6.283186f);
}
bool valid(EntityKind kind) {
    return kind == EntityKind::Player || kind == EntityKind::Vehicle || kind == EntityKind::World;
}
} // namespace

PacketType TypeOf(const Payload& payload) { return kTypes[payload.index()]; }
bool IsReliable(PacketType type) {
    return type == PacketType::Leave || type == PacketType::HitRequest
        || type == PacketType::DamageApplied || type == PacketType::GameplayIntent || type == PacketType::GameplayResult || type == PacketType::EntitySpawn
        || type == PacketType::EntityDespawn || type == PacketType::NpcAdopt || type == PacketType::NpcDespawn;
}
bool IsNewer(std::uint32_t candidate, std::uint32_t previous) {
    const auto distance = candidate - previous;
    return distance != 0 && distance < 0x80000000u;
}
bool Validate(const Packet& packet) {
    const auto& h = packet.header;
    const auto type = TypeOf(packet.payload);
    const bool pre = type == PacketType::Hello || type == PacketType::HelloOk
        || type == PacketType::CreateSession || type == PacketType::JoinSession || type == PacketType::Reject;
    const bool server = type == PacketType::SessionAccepted || type == PacketType::MemberJoined
        || type == PacketType::MemberLeft || type == PacketType::SessionClosed || type == PacketType::SessionReady
        || type == PacketType::NpcSpawn || type == PacketType::NpcRemoved || type == PacketType::NpcSnapshotEnd || type == PacketType::NpcDenied || type == PacketType::GameplayStatus;
    if (pre) { if (h.session || h.epoch || h.sender || h.sequence || h.event) return false; }
    else if (server) { if (!h.session || !h.epoch || h.sender || h.sequence || h.event) return false; }
    else if (h.session == 0 || h.epoch == 0 || h.sender == 0) return false;
    if (IsReliable(TypeOf(packet.payload)) ? (h.event == 0 || h.sequence != 0) : h.event != 0) return false;
    return std::visit([](const auto& p) {
        using T = std::decay_t<decltype(p)>;
        if constexpr (std::is_same_v<T, Heartbeat> || std::is_same_v<T, Leave>) return true;
        else if constexpr (std::is_same_v<T, Hello>) {
            if (p.key.size() != 64) return false;
            for (auto c : p.key) if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
            return true;
        } else if constexpr (std::is_same_v<T, CreateSession> || std::is_same_v<T, JoinSession>) {
            if (p.name.empty() || p.name.size() > 31) return false;
            for (auto c : p.name) if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                || (c >= '0' && c <= '9') || c == '-' || c == '_')) return false;
            return true;
        } else if constexpr (std::is_same_v<T, SessionAccepted>) return p.player && p.host;
        else if constexpr (std::is_same_v<T, Reject>) return p.reason >= RejectReason::Auth && p.reason <= RejectReason::HostLeft;
        else if constexpr (std::is_same_v<T, MemberJoined> || std::is_same_v<T, MemberLeft>) return p.player != 0;
        else if constexpr (std::is_same_v<T, HelloOk> || std::is_same_v<T, SessionClosed>
            || std::is_same_v<T, Ready> || std::is_same_v<T, SessionReady>) return true;
        else if constexpr (std::is_same_v<T, NpcAdopt>) return p.adoption && p.record && p.record<=0xffffffffffULL && valid(p.transform);
        else if constexpr (std::is_same_v<T, NpcSpawn>) return p.entity>=kNpcEntityBase && p.adoption && p.record && p.record<=0xffffffffffULL && valid(p.transform);
        else if constexpr (std::is_same_v<T, NpcDespawn> || std::is_same_v<T, NpcRemoved>) return p.entity>=kNpcEntityBase;
        else if constexpr (std::is_same_v<T, NpcState>) return p.entity>=kNpcEntityBase && p.sampleTimeMs && valid(p.transform);
        else if constexpr (std::is_same_v<T, NpcSnapshotEnd>) return true;
        else if constexpr (std::is_same_v<T, NpcDenied>) return p.adoption!=0;
        else if constexpr (std::is_same_v<T, GameplayIntent>) return p.kind!=0 && p.body.size()<=kMaxGameplayBodySize;
        else if constexpr (std::is_same_v<T, GameplayResult>) return p.requester!=0 && p.requestEvent!=0 && p.kind!=0 && p.disposition>=GameplayDisposition::Accepted && p.disposition<=GameplayDisposition::Full && p.body.size()<=kMaxGameplayBodySize;
        else if constexpr (std::is_same_v<T, GameplayStatus>) return p.correlationEvent!=0 && p.disposition>=GameplayDisposition::Pending && p.disposition<=GameplayDisposition::Full;
        else if constexpr (std::is_same_v<T, Ack>) return p.event != 0;
        else if constexpr (std::is_same_v<T, HitRequest>)
            return p.attacker != 0 && p.target != 0 && p.attacker != p.target && bounded(p.proposedDamage, 0.001f, 100000);
        else if constexpr (std::is_same_v<T, DamageApplied>)
            return p.attacker != 0 && p.target != 0 && p.attacker != p.target && p.request != 0 && bounded(p.damage, 0.001f, 100000);
        else if constexpr (std::is_same_v<T, VehicleInput>)
            return p.entity != 0 && bounded(p.throttle, -1, 1) && bounded(p.steering, -1, 1) && bounded(p.brake, 0, 1);
        else if constexpr (std::is_same_v<T, EntitySpawn>)
            return p.entity != 0 && valid(p.kind) && (p.kind != EntityKind::Player || p.owner != 0) && valid(p.transform);
        else if constexpr (std::is_same_v<T, EntityDespawn>) return p.entity != 0;
        else return p.entity != 0 && valid(p.transform);
    }, packet.payload);
}
std::optional<std::vector<std::uint8_t>> Encode(const Packet& packet) {
    if (!Validate(packet)) return std::nullopt;
    Writer w;
    w.data.reserve(kHeaderSize + kSizes[packet.payload.index()]);
    w.integer(kMagic, 4); w.integer(kProtocolVersion, 2);
    w.integer(static_cast<std::uint16_t>(TypeOf(packet.payload)), 2);
    w.integer(0, 4); // patched after the payload is serialized
    const auto& h = packet.header;
    w.integer(h.session, 8); w.integer(h.epoch, 4); w.integer(h.sender, 4);
    w.integer(h.sequence, 4); w.integer(h.event, 8);
    std::visit([&](const auto& p) {
        using T = std::decay_t<decltype(p)>;
        if constexpr (std::is_same_v<T, GameplayIntent>) { w.integer(p.kind,2); w.integer(p.body.size(),2); w.bytes(p.body); }
        else if constexpr (std::is_same_v<T, GameplayResult>) {
            w.integer(p.requester,4); w.integer(p.requestEvent,8); w.integer(p.kind,2);
            w.integer(static_cast<std::uint8_t>(p.disposition),1); w.integer(p.reason,2);
            w.integer(p.body.size(),2); w.bytes(p.body);
        }
        else if constexpr (std::is_same_v<T, GameplayStatus>) {
            w.integer(p.correlationEvent,8); w.integer(static_cast<std::uint8_t>(p.disposition),1); w.integer(p.reason,2); w.integer(p.committed?1:0,1);
        }
        else if constexpr (std::is_same_v<T, NpcSnapshotEnd>) {}
        else if constexpr (std::is_same_v<T, NpcDenied>) w.integer(p.adoption,8);
        else if constexpr (std::is_same_v<T, NpcAdopt>) { w.integer(p.adoption,8); w.integer(p.record,8); w.transform(p.transform); }
        else if constexpr (std::is_same_v<T, NpcSpawn>) {
            w.integer(p.entity,8); w.integer(p.adoption,8); w.integer(p.record,8); w.transform(p.transform);
            w.integer(p.sequence,4); w.integer(p.sampleTimeMs,8);
        }
        else if constexpr (std::is_same_v<T, NpcDespawn> || std::is_same_v<T, NpcRemoved>) w.integer(p.entity,8);
        else if constexpr (std::is_same_v<T, Heartbeat> || std::is_same_v<T, Leave>) {}
        else if constexpr (std::is_same_v<T, Hello>) w.text(p.key,64);
        else if constexpr (std::is_same_v<T, CreateSession> || std::is_same_v<T, JoinSession>) w.text(p.name,32);
        else if constexpr (std::is_same_v<T, SessionAccepted>) { w.integer(p.player,4); w.integer(p.host,4); for (auto b : p.token) w.integer(b,1); }
        else if constexpr (std::is_same_v<T, Reject>) w.integer(static_cast<std::uint16_t>(p.reason),2);
        else if constexpr (std::is_same_v<T, MemberJoined> || std::is_same_v<T, MemberLeft>) w.integer(p.player,4);
        else if constexpr (std::is_same_v<T, HelloOk> || std::is_same_v<T, SessionClosed>
            || std::is_same_v<T, Ready> || std::is_same_v<T, SessionReady>) {}
        else if constexpr (std::is_same_v<T, Ack>) w.integer(p.event, 8);
        else if constexpr (std::is_same_v<T, HitRequest> || std::is_same_v<T, DamageApplied>) {
            w.integer(p.attacker, 8); w.integer(p.target, 8);
            if constexpr (std::is_same_v<T, HitRequest>) w.scalar(p.proposedDamage);
            else { w.scalar(p.damage); w.integer(p.request, 8); }
        } else {
            w.integer(p.entity, 8);
            if constexpr (std::is_same_v<T, VehicleInput>) {
                w.scalar(p.throttle); w.scalar(p.steering); w.scalar(p.brake);
            } else if constexpr (std::is_same_v<T, EntitySpawn>) {
                w.integer(static_cast<std::uint8_t>(p.kind), 1); w.integer(p.owner, 4); w.transform(p.transform);
            } else if constexpr (!std::is_same_v<T, EntityDespawn>) {
                w.transform(p.transform);
                if constexpr (requires { p.sampleTimeMs; }) w.integer(p.sampleTimeMs,8);
            }
        }
    }, packet.payload);
    const auto payloadSize=static_cast<std::uint32_t>(w.data.size()-kHeaderSize);
    w.data[8]=static_cast<std::uint8_t>(payloadSize>>24); w.data[9]=static_cast<std::uint8_t>(payloadSize>>16); w.data[10]=static_cast<std::uint8_t>(payloadSize>>8); w.data[11]=static_cast<std::uint8_t>(payloadSize);
    return w.data;
}
DecodeResult Decode(std::span<const std::uint8_t> bytes) {
    const auto fail = [](CodecError e) { return DecodeResult{std::nullopt, e}; };
    if (bytes.size() < kHeaderSize || bytes.size() > kMaxPacketSize) return fail(CodecError::Size);
    Reader r{bytes};
    if (r.integer(4) != kMagic) return fail(CodecError::Magic);
    if (r.integer(2) != kProtocolVersion) return fail(CodecError::Version);
    const auto type = static_cast<PacketType>(r.integer(2));
    std::size_t index = 0;
    while (index < kTypes.size() && kTypes[index] != type) ++index;
    if (index == kTypes.size()) return fail(CodecError::Type);
    const auto length = r.u32();
    if ((kSizes[index] && length != kSizes[index]) || bytes.size() != kHeaderSize + length) return fail(CodecError::Length);
    if (type == PacketType::GameplayIntent && (length < 4 || length > 4+kMaxGameplayBodySize)) return fail(CodecError::Length);
    if (type == PacketType::GameplayResult && (length < 19 || length > 19+kMaxGameplayBodySize)) return fail(CodecError::Length);
    Packet packet;
    packet.header = {r.integer(8), r.u32(), r.u32(), r.u32(), r.integer(8)};
    switch (type) {
    case PacketType::NpcAdopt: packet.payload=NpcAdopt{r.integer(8),r.integer(8),r.transform()}; break;
    case PacketType::NpcSpawn: packet.payload=NpcSpawn{r.integer(8),r.integer(8),r.integer(8),r.transform(),r.u32(),r.integer(8)}; break;
    case PacketType::NpcDespawn: packet.payload=NpcDespawn{r.integer(8)}; break;
    case PacketType::NpcRemoved: packet.payload=NpcRemoved{r.integer(8)}; break;
    case PacketType::NpcState: packet.payload=NpcState{r.integer(8),r.transform(),r.integer(8)}; break;
    case PacketType::NpcSnapshotEnd: packet.payload=NpcSnapshotEnd{}; break;
    case PacketType::NpcDenied: packet.payload=NpcDenied{r.integer(8)}; break;
    case PacketType::GameplayIntent: { auto kind=static_cast<std::uint16_t>(r.integer(2)); auto size=static_cast<std::size_t>(r.integer(2)); packet.payload=GameplayIntent{kind,r.bytes(size)}; break; }
    case PacketType::GameplayResult: { auto requester=r.u32(); auto requestEvent=r.integer(8); auto kind=static_cast<std::uint16_t>(r.integer(2)); auto status=static_cast<GameplayDisposition>(r.integer(1)); auto reason=static_cast<std::uint16_t>(r.integer(2)); auto size=static_cast<std::size_t>(r.integer(2)); packet.payload=GameplayResult{requester,requestEvent,kind,status,reason,r.bytes(size)}; break; }
    case PacketType::GameplayStatus: packet.payload=GameplayStatus{r.integer(8),static_cast<GameplayDisposition>(r.integer(1)),static_cast<std::uint16_t>(r.integer(2)),r.boolean()}; break;
    case PacketType::Hello: packet.payload = Hello{r.text(64)}; break;
    case PacketType::HelloOk: packet.payload = HelloOk{}; break;
    case PacketType::CreateSession: packet.payload = CreateSession{r.text(32)}; break;
    case PacketType::JoinSession: packet.payload = JoinSession{r.text(32)}; break;
    case PacketType::SessionAccepted: { SessionAccepted accepted{r.u32(),r.u32(),{}}; for (auto& b : accepted.token) b = static_cast<std::uint8_t>(r.integer(1)); packet.payload = accepted; break; }
    case PacketType::Reject: packet.payload = Reject{static_cast<RejectReason>(r.integer(2))}; break;
    case PacketType::MemberJoined: packet.payload = MemberJoined{r.u32()}; break;
    case PacketType::MemberLeft: packet.payload = MemberLeft{r.u32()}; break;
    case PacketType::SessionClosed: packet.payload = SessionClosed{}; break;
    case PacketType::Ready: packet.payload = Ready{}; break;
    case PacketType::SessionReady: packet.payload = SessionReady{}; break;
    case PacketType::Heartbeat: packet.payload = Heartbeat{}; break;
    case PacketType::Leave: packet.payload = Leave{}; break;
    case PacketType::Ack: packet.payload = Ack{r.integer(8)}; break;
    case PacketType::PlayerPose: packet.payload = PlayerPose{r.integer(8), r.transform(), r.integer(8)}; break;
    case PacketType::PlayerState: packet.payload = PlayerState{r.integer(8), r.transform(), r.integer(8)}; break;
    case PacketType::VehicleInput: packet.payload = VehicleInput{r.integer(8), r.scalar(), r.scalar(), r.scalar()}; break;
    case PacketType::VehicleState: packet.payload = VehicleState{r.integer(8), r.transform(), r.integer(8)}; break;
    case PacketType::HitRequest: packet.payload = HitRequest{r.integer(8), r.integer(8), r.scalar()}; break;
    case PacketType::DamageApplied: packet.payload = DamageApplied{r.integer(8), r.integer(8), r.scalar(), r.integer(8)}; break;
    case PacketType::EntitySpawn: packet.payload = EntitySpawn{r.integer(8), static_cast<EntityKind>(r.integer(1)), r.u32(), r.transform()}; break;
    case PacketType::EntityDespawn: packet.payload = EntityDespawn{r.integer(8)}; break;
    case PacketType::WorldState: packet.payload = WorldState{r.integer(8), r.transform()}; break;
    }
    if (!r.canonical || r.offset!=bytes.size() || !Validate(packet)) return fail(CodecError::InvalidValue);
    return {packet, CodecError::None};
}
} // namespace coop
