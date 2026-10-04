#include "check.hpp"
#include "coop/session.hpp"
using namespace coop;
struct Fixture {
    SessionRegistry registry{SessionLimits{16,2,1024,10000}};
    Membership host, joiner;
    Fixture() {
        host = registry.Create(11,0).membership.value();
        joiner = registry.Join(host.session,22,0).membership.value();
        CHECK(registry.MarkSynchronized(host.session,joiner.player,1) == SessionError::None);
    }
    Packet packet(const Membership& member, Payload payload, std::uint32_t sequence = 1) {
        const auto* s = registry.Find(member.session);
        const auto event = IsReliable(TypeOf(payload)) ? s->members.at(member.player).lastEvent + 1 : 0;
        return {{member.session,s->epoch,member.player,event ? 0u : sequence,event}, payload};
    }
    void spawn() {
        CHECK(registry.Receive(11,packet(host,EntitySpawn{1,EntityKind::Player,host.player,{}}),1));
        CHECK(registry.Receive(11,packet(host,EntitySpawn{2,EntityKind::Player,joiner.player,{}}),1));
        CHECK(registry.Receive(11,packet(host,EntitySpawn{3,EntityKind::Vehicle,joiner.player,{}}),1));
        CHECK(registry.Receive(11,packet(host,EntitySpawn{4,EntityKind::World,0,{}}),1));
    }
};
void AuthorityAndIsolation() {
    Fixture f; f.spawn();
    const auto other = f.registry.Create(33,0).membership.value();
    auto pose = f.packet(f.joiner,PlayerPose{2,{}});
    auto result = f.registry.Receive(22,pose,2);
    CHECK(result && result.route == Route::Host && result.recipients == std::vector<PlayerId>{f.host.player});
    CHECK(f.registry.Receive(33,pose,2).error == SessionError::Identity);
    pose.header.session = other.session;
    CHECK(f.registry.Receive(22,pose,2).error == SessionError::MissingMember);
    CHECK(f.registry.Find(other.session)->entities.empty());
    CHECK(f.registry.Receive(22,f.packet(f.joiner,PlayerState{2,{}}),2).error == SessionError::Authority);
    CHECK(f.registry.Receive(22,f.packet(f.joiner,DamageApplied{2,4,5,1}),2).error == SessionError::Authority);
    CHECK(f.registry.Receive(22,f.packet(f.joiner,WorldState{4,{}}),2).error == SessionError::Authority);
    CHECK(f.registry.Receive(22,f.packet(f.joiner,EntitySpawn{5,EntityKind::World,0,{}}),2).error == SessionError::Authority);
    CHECK(f.registry.Receive(22,f.packet(f.joiner,PlayerPose{1,{}}),2).error == SessionError::Ownership);
    CHECK(f.registry.Receive(22,f.packet(f.joiner,VehicleInput{2,0,0,0}),2).error == SessionError::Kind);
    CHECK(f.registry.Receive(22,f.packet(f.joiner,VehicleInput{3,0,0,0}),2));
    CHECK(f.registry.Receive(22,f.packet(f.joiner,HitRequest{1,4,5}),2).error == SessionError::Ownership);
    CHECK(f.registry.Receive(22,f.packet(f.joiner,HitRequest{2,999,5}),2).error == SessionError::MissingEntity);
    auto hit = f.packet(f.joiner,HitRequest{2,4,5});
    CHECK(f.registry.Receive(22,hit,2));
    CHECK(f.registry.Receive(22,hit,2).error == SessionError::Duplicate);
    auto damage = f.packet(f.host,DamageApplied{2,4,5,hit.header.event});
    CHECK(f.registry.Receive(11,damage,2));
    CHECK(f.registry.Receive(11,damage,2).error == SessionError::Duplicate);
    CHECK(f.registry.Find(f.host.session)->members.at(f.host.player).lastEvent == 5);
}
void StateAndOrdering() {
    Fixture f; f.spawn();
    auto p = f.packet(f.host,PlayerState{2,{{1,2,3},{}}},0xfffffffeu);
    CHECK(f.registry.Receive(11,p,2));
    p.header.sequence = 0xffffffffu; CHECK(f.registry.Receive(11,p,2));
    p.header.sequence = 0; CHECK(f.registry.Receive(11,p,2));
    p.header.sequence = 0xffffffffu; CHECK(f.registry.Receive(11,p,2).error == SessionError::Stale);
    CHECK(f.registry.Find(f.host.session)->entities.at(2).transform.position.x == 1);
    auto client = f.packet(f.joiner,PlayerPose{2,{{99,0,0},{}}});
    CHECK(f.registry.Receive(22,client,2));
    CHECK(f.registry.Find(f.host.session)->entities.at(2).transform.position.x == 1);
    // Player and vehicle streams cannot suppress one another.
    CHECK(f.registry.Receive(11,f.packet(f.host,VehicleState{3,{}},0),2));
    auto spawn = f.packet(f.host,EntitySpawn{5,EntityKind::World,0,{}});
    spawn.header.event += 1;
    CHECK(f.registry.Receive(11,spawn,2).error == SessionError::EventGap);
    CHECK(!f.registry.Find(f.host.session)->entities.contains(5));
    spawn.header.event -= 1; CHECK(f.registry.Receive(11,spawn,2));
    CHECK(f.registry.Receive(11,f.packet(f.host,EntityDespawn{5}),2));
    CHECK(f.registry.Receive(11,f.packet(f.host,EntitySpawn{5,EntityKind::World,0,{}}),2).error == SessionError::EntityReuse);
    CHECK(f.registry.Receive(11,f.packet(f.host,EntitySpawn{6,EntityKind::Player,f.joiner.player,{}}),2).error == SessionError::Ownership);
    CHECK(f.registry.Receive(11,f.packet(f.host,EntitySpawn{6,EntityKind::World,999,{}}),2).error == SessionError::Ownership);
}
void Lifecycle() {
    Fixture f; f.spawn();
    auto old = f.packet(f.joiner,PlayerPose{2,{}});
    CHECK(f.registry.ResetWorld(22) == SessionError::Authority);
    CHECK(f.registry.ResetWorld(11) == SessionError::None);
    CHECK(f.registry.Find(f.host.session)->entities.empty());
    CHECK(f.registry.Receive(22,old,2).error == SessionError::Epoch);
    auto syncing = f.packet(f.joiner,PlayerPose{2,{}});
    CHECK(f.registry.Receive(22,syncing,2).error == SessionError::NotReady);
    CHECK(f.registry.MarkSynchronized(f.host.session,f.joiner.player,1) == SessionError::Epoch);
    CHECK(f.registry.MarkSynchronized(f.host.session,f.joiner.player,2) == SessionError::None);
    f.spawn();
    auto leave = f.packet(f.joiner,Leave{});
    auto left = f.registry.Receive(22,leave,2);
    CHECK(left && left.removal && !left.removal->closed && left.removal->entities.size() == 2);
    CHECK(!f.registry.Find(f.host.session)->entities.contains(2));
    CHECK(!f.registry.Find(f.host.session)->entities.contains(3));
    auto rejoin = f.registry.Join(f.host.session,44,3);
    CHECK(rejoin && rejoin.membership->player != f.joiner.player);
    CHECK(f.registry.Receive(22,leave,3).error == SessionError::MissingMember);
    CHECK(f.registry.Find(f.host.session)->members.at(rejoin.membership->player).phase == Phase::Synchronizing);
    auto closed = f.registry.Disconnect(11);
    CHECK(closed && closed->closed && closed->notify.size() == 1);
    CHECK(!f.registry.Find(f.host.session));
    CHECK(f.registry.Join(f.host.session,55,4).error == SessionError::MissingSession);
}
void LimitsAndExpiry() {
    SessionRegistry registry{SessionLimits{16,2,1024,10000}};
    CHECK(!registry.Create(0,0));
    for (std::uint64_t i = 1; i <= 16; ++i) CHECK(registry.Create(i,0));
    CHECK(registry.Create(100,0).error == SessionError::Capacity);
    CHECK(registry.Create(1,0).error == SessionError::ConnectionInUse);
    CHECK(registry.Expire(9999).empty());
    CHECK(registry.Expire(10000).size() == 16);
    CHECK(registry.Size() == 0);
    Fixture f;
    CHECK(f.registry.Join(f.host.session,33,0).error == SessionError::Capacity);
    auto heartbeat = f.packet(f.host,Heartbeat{});
    CHECK(f.registry.Receive(11,heartbeat,9000));
    CHECK(f.registry.Receive(11,heartbeat,9001).error == SessionError::Stale);
    CHECK(f.registry.Receive(11,f.packet(f.host,Heartbeat{},2),8000).error == SessionError::Clock);
    auto removed = f.registry.Expire(10000);
    CHECK(removed.size() == 1 && !removed[0].closed && removed[0].player == f.joiner.player);
    CHECK(f.registry.Receive(11,f.packet(f.host,Heartbeat{},2),19000).error == SessionError::Expired);
    CHECK(f.registry.Join(f.host.session,44,19000).error == SessionError::Expired);
    CHECK(f.registry.Expire(19000).size() == 1);
    Fixture bounded;
    for (EntityId id = 1; id <= 1024; ++id)
        CHECK(bounded.registry.Receive(11,bounded.packet(bounded.host,EntitySpawn{id,EntityKind::World,0,{}}),1));
    CHECK(bounded.registry.Receive(11,bounded.packet(bounded.host,EntitySpawn{1025,EntityKind::World,0,{}}),1).error == SessionError::Capacity);
}
void WireFlow() {
    Fixture f;
    auto deliver = [&](ConnectionId connection, const Packet& packet) {
        const auto bytes = Encode(packet);
        CHECK(bytes);
        const auto parsed = Decode(*bytes);
        CHECK(parsed);
        return f.registry.Receive(connection,*parsed.packet,1);
    };
    CHECK(deliver(11,f.packet(f.host,EntitySpawn{1,EntityKind::Player,f.joiner.player,{}})));
    CHECK(deliver(11,f.packet(f.host,EntitySpawn{2,EntityKind::World,0,{}})));
    const auto hit = f.packet(f.joiner,HitRequest{1,2,20});
    auto later = hit;
    later.header.event = 2;
    // Lost first event: second cannot skip ahead. Retransmit and retry in order.
    CHECK(deliver(22,later).error == SessionError::EventGap);
    CHECK(deliver(22,hit));
    CHECK(deliver(22,later));
    CHECK(deliver(22,hit).error == SessionError::Duplicate);
    CHECK(deliver(11,f.packet(f.host,DamageApplied{1,2,20,1})));
    const auto state = f.packet(f.host,WorldState{2,{{3,4,5},{}}});
    CHECK(deliver(11,state).recipients == std::vector<PlayerId>{f.joiner.player});
    CHECK(f.registry.Find(f.host.session)->entities.at(2).transform.position == (Vec3{3,4,5}));
}
int main() { return Run([] { AuthorityAndIsolation(); StateAndOrdering(); Lifecycle(); LimitsAndExpiry(); WireFlow(); }); }
