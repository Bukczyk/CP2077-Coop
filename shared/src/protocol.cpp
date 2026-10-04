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
constexpr std::array<PacketType, 12> kTypes{
    PacketType::Heartbeat, PacketType::Leave, PacketType::Ack,
    PacketType::PlayerPose, PacketType::PlayerState, PacketType::VehicleInput,
    PacketType::VehicleState, PacketType::HitRequest, PacketType::DamageApplied,
    PacketType::EntitySpawn, PacketType::EntityDespawn, PacketType::WorldState};
constexpr std::array<std::uint32_t, 12> kSizes{0, 0, 8, 32, 32, 20, 32, 20, 28, 37, 8, 32};
struct Writer {
    std::vector<std::uint8_t> data;
    void integer(std::uint64_t value, unsigned width) {
        for (unsigned i = width; i > 0; --i)
            data.push_back(static_cast<std::uint8_t>(value >> ((i - 1) * 8)));
    }
    void scalar(float value) { integer(std::bit_cast<std::uint32_t>(value), 4); }
    void vector(Vec3 v) { scalar(v.x); scalar(v.y); scalar(v.z); }
    void transform(const Transform& t) { vector(t.position); vector(t.rotation); }
};
// Decode checks the exact type-specific size before any payload reads.
struct Reader {
    std::span<const std::uint8_t> data;
    std::size_t offset = 0;
    std::uint64_t integer(unsigned width) {
        std::uint64_t value = 0;
        for (unsigned i = 0; i < width; ++i) value = (value << 8) | data[offset++];
        return value;
    }
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
        || type == PacketType::DamageApplied || type == PacketType::EntitySpawn
        || type == PacketType::EntityDespawn;
}
bool IsNewer(std::uint32_t candidate, std::uint32_t previous) {
    const auto distance = candidate - previous;
    return distance != 0 && distance < 0x80000000u;
}
bool Validate(const Packet& packet) {
    const auto& h = packet.header;
    if (h.session == 0 || h.epoch == 0 || h.sender == 0) return false;
    if (IsReliable(TypeOf(packet.payload)) ? (h.event == 0 || h.sequence != 0) : h.event != 0) return false;
    return std::visit([](const auto& p) {
        using T = std::decay_t<decltype(p)>;
        if constexpr (std::is_same_v<T, Heartbeat> || std::is_same_v<T, Leave>) return true;
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
    w.integer(kSizes[packet.payload.index()], 4);
    const auto& h = packet.header;
    w.integer(h.session, 8); w.integer(h.epoch, 4); w.integer(h.sender, 4);
    w.integer(h.sequence, 4); w.integer(h.event, 8);
    std::visit([&](const auto& p) {
        using T = std::decay_t<decltype(p)>;
        if constexpr (std::is_same_v<T, Heartbeat> || std::is_same_v<T, Leave>) {}
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
            } else if constexpr (!std::is_same_v<T, EntityDespawn>) w.transform(p.transform);
        }
    }, packet.payload);
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
    if (length != kSizes[index] || bytes.size() != kHeaderSize + length) return fail(CodecError::Length);
    Packet packet;
    packet.header = {r.integer(8), r.u32(), r.u32(), r.u32(), r.integer(8)};
    switch (type) {
    case PacketType::Heartbeat: packet.payload = Heartbeat{}; break;
    case PacketType::Leave: packet.payload = Leave{}; break;
    case PacketType::Ack: packet.payload = Ack{r.integer(8)}; break;
    case PacketType::PlayerPose: packet.payload = PlayerPose{r.integer(8), r.transform()}; break;
    case PacketType::PlayerState: packet.payload = PlayerState{r.integer(8), r.transform()}; break;
    case PacketType::VehicleInput: packet.payload = VehicleInput{r.integer(8), r.scalar(), r.scalar(), r.scalar()}; break;
    case PacketType::VehicleState: packet.payload = VehicleState{r.integer(8), r.transform()}; break;
    case PacketType::HitRequest: packet.payload = HitRequest{r.integer(8), r.integer(8), r.scalar()}; break;
    case PacketType::DamageApplied: packet.payload = DamageApplied{r.integer(8), r.integer(8), r.scalar(), r.integer(8)}; break;
    case PacketType::EntitySpawn: packet.payload = EntitySpawn{r.integer(8), static_cast<EntityKind>(r.integer(1)), r.u32(), r.transform()}; break;
    case PacketType::EntityDespawn: packet.payload = EntityDespawn{r.integer(8)}; break;
    case PacketType::WorldState: packet.payload = WorldState{r.integer(8), r.transform()}; break;
    }
    if (!Validate(packet)) return fail(CodecError::InvalidValue);
    return {packet, CodecError::None};
}
} // namespace coop
