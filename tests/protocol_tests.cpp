#include "check.hpp"
#include "coop/protocol.hpp"
#include <array>
#include <limits>
using namespace coop;

void Golden() {
    const Packet packet{{0x0102030405060708ULL, 9, 10, 11, 0}, Heartbeat{}};
    const std::vector<std::uint8_t> golden{
        0x43,0x50,0x53,0x31, 0,3, 0,1, 0,0,0,0,
        1,2,3,4,5,6,7,8, 0,0,0,9, 0,0,0,10, 0,0,0,11,
        0,0,0,0,0,0,0,0};
    CHECK(Encode(packet).value() == golden);
    CHECK(Decode(golden).packet.value() == packet);
    const Packet pose{{1,1,1,1,0}, PlayerPose{2, {{1.0f, -2.0f, 0}, {0,0,0}}}};
    auto bytes = Encode(pose).value();
    CHECK(bytes.size() == 80);
    CHECK(bytes[6] == 1 && bytes[7] == 0 && bytes[11] == 40);
    const std::array<std::uint8_t, 12> expected{0x3f,0x80,0,0, 0xc0,0,0,0, 0,0,0,0};
    for (std::size_t i = 0; i < expected.size(); ++i) CHECK(bytes[48+i] == expected[i]);
}
void CodecCases() {
    const Transform t{{12.5f,-3.25f,9}, {0.5f,-0.75f,1.25f}};
    const std::vector<Payload> payloads{Heartbeat{}, Leave{}, Ack{9}, PlayerPose{1,t},
        PlayerState{1,t}, VehicleInput{2,0.5f,-0.5f,1}, VehicleState{2,t},
        HitRequest{1,3,42}, DamageApplied{1,3,42,1}, EntitySpawn{3,EntityKind::World,0,t},
        EntityDespawn{3}, WorldState{3,t}};
    for (const auto& payload : payloads) {
        const bool reliable = IsReliable(TypeOf(payload));
        Packet packet{{123,2,4,reliable ? 0u : 0xffffffffu,reliable ? 1u : 0u}, payload};
        auto bytes = Encode(packet);
        CHECK(bytes);
        auto decoded = Decode(*bytes);
        CHECK(decoded && decoded.packet.value() == packet);
        // Every truncated prefix and any trailing byte must be rejected.
        for (std::size_t size = 0; size < bytes->size(); ++size)
            CHECK(!Decode(std::span<const std::uint8_t>(*bytes).first(size)));
        bytes->push_back(0);
        CHECK(!Decode(*bytes));
    }
    auto bad = Encode(Packet{{1,1,1,1,0}, Heartbeat{}}).value();
    bad[0] = 0; CHECK(Decode(bad).error == CodecError::Magic); bad[0] = 0x43;
    bad[5] = 2; CHECK(Decode(bad).error == CodecError::Version); bad[5] = 3;
    bad[7] = 255; CHECK(Decode(bad).error == CodecError::Type); bad[7] = 1;
    bad[11] = 1; CHECK(Decode(bad).error == CodecError::Length);
    CHECK(Decode(std::vector<std::uint8_t>(1201)).error == CodecError::Size);
    Packet pose{{1,1,1,1,0}, PlayerPose{1,t}};
    auto nanBytes = Encode(pose).value();
    nanBytes[48] = 0x7f; nanBytes[49] = 0xc0; nanBytes[50] = 0; nanBytes[51] = 1;
    CHECK(Decode(nanBytes).error == CodecError::InvalidValue);
    std::get<PlayerPose>(pose.payload).transform.position.x = std::numeric_limits<float>::infinity();
    CHECK(!Encode(pose));
    pose.payload = VehicleInput{2,2,0,0}; CHECK(!Encode(pose));
    pose.payload = PlayerPose{0,t}; CHECK(!Encode(pose));
    pose.payload = Heartbeat{}; pose.header.session = 0; CHECK(!Encode(pose));
    pose.header = {1,1,1,0,1}; pose.payload = EntitySpawn{1,static_cast<EntityKind>(99),0,t}; CHECK(!Encode(pose));
    pose.payload = EntitySpawn{1,EntityKind::Player,0,t}; CHECK(!Encode(pose));
    pose.payload = DamageApplied{1,2,-1,1}; CHECK(!Encode(pose));
    pose.payload = HitRequest{1,1,1}; CHECK(!Encode(pose));
    pose.payload = Leave{}; pose.header.event = 0; CHECK(!Encode(pose));
    CHECK(IsNewer(0, 0xffffffffu));
    CHECK(!IsNewer(0xffffffffu, 0));
    CHECK(!IsNewer(7, 7));
    CHECK(!IsNewer(0x80000000u, 0));
}
void Handshake() {
    const std::vector<Packet> packets{
        {{},Hello{std::string(64,'a')}},{{},HelloOk{}},{{},CreateSession{"first-test"}},{{},JoinSession{"first-test"}},
        {{1,1,0,0,0},SessionAccepted{1,1,{}}},{{},Reject{RejectReason::Full}},
        {{1,1,0,0,0},MemberJoined{2}},{{1,1,0,0,0},MemberLeft{2}},
        {{1,1,0,0,0},SessionClosed{}},{{1,1,2,0,0},Ready{}},{{1,1,0,0,0},SessionReady{}}};
    for (const auto& p:packets) {
        const auto bytes=Encode(p); CHECK(bytes); CHECK(Decode(*bytes).packet.value()==p);
        for(std::size_t i=0;i<bytes->size();++i) CHECK(!Decode(std::span<const std::uint8_t>(*bytes).first(i)));
    }
    CHECK(!Encode(Packet{{},Hello{"short"}})); CHECK(!Encode(Packet{{},CreateSession{"has space"}}));
    CHECK(!Encode(Packet{{1,1,0,0,0},Ready{}}));
    auto invalid=Encode(Packet{{},JoinSession{"x"}}).value(); invalid[42]='z';
    CHECK(!Decode(invalid)); // noncanonical text after a NUL
}
void FuzzSmoke() {
    std::uint32_t seed = 0x2077;
    auto next = [&]() { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return seed; };
    for (int i = 0; i < 20000; ++i) {
        std::vector<std::uint8_t> bytes(next() % 1250);
        for (auto& byte : bytes) byte = static_cast<std::uint8_t>(next());
        const auto result = Decode(bytes);
        if (result) CHECK(Encode(*result.packet).value() == bytes);
    }
    auto seedPacket = Encode(Packet{{1,1,1,0,1}, EntitySpawn{1,EntityKind::Player,1,{}}}).value();
    for (std::size_t i = 0; i < seedPacket.size(); ++i) {
        for (unsigned value = 0; value < 256; ++value) {
            auto bytes = seedPacket; bytes[i] = static_cast<std::uint8_t>(value);
            auto result = Decode(bytes);
            if (result) CHECK(Encode(*result.packet).value() == bytes);
        }
    }
}
int main() { return Run([] { Golden(); CodecCases(); Handshake(); FuzzSmoke(); }); }
