#include "check.hpp"
#include "coop/client.hpp"
#include "coop/game_bridge.hpp"
#include <chrono>
#include <memory>
#include <thread>
using namespace coop;
using namespace std::chrono_literals;

PresentationValues Gun() {
    return {PresentationStance::Crouching,PresentationWeapon::DrawnSupported,kPresentationIglaPimp,PresentationAim::Aiming};
}
void Codec() {
    const Packet packet{{1,1,7,9,0},PlayerPresentation{7,123,Gun()}};
    const auto encoded=Encode(packet); CHECK(encoded && encoded->size()==kHeaderSize+23);
    CHECK((*encoded)[4]==0x80 && (*encoded)[5]==5 && (*encoded)[6]==0x7f && (*encoded)[7]==0);
    CHECK(Decode(*encoded).packet==packet);
    for(std::size_t size=0;size<encoded->size();++size)
        CHECK(!Decode(std::span<const std::uint8_t>(*encoded).first(size)));
    auto invalid=*encoded; invalid.push_back(0); CHECK(!Decode(invalid));
    invalid=*encoded; invalid[4]=0; CHECK(Decode(invalid).error==CodecError::Version);
    auto state=std::get<PlayerPresentation>(packet.payload);
    for(const auto offset:{12u,13u,22u}) {
        invalid=*encoded; invalid[kHeaderSize+offset]=255; CHECK(!Decode(invalid));
    }
    state.values.weaponRecord|=0x1234560000000000ULL;
    CHECK(!Validate(Packet{packet.header,state}));
    state.values=Gun(); state.values.weapon=PresentationWeapon::Holstered;
    CHECK(!Validate(Packet{packet.header,state}));
    state.values.weaponRecord=0; CHECK(!Validate(Packet{packet.header,state})); // aiming while holstered
    state.values.aiming=PresentationAim::NotAiming; CHECK(Validate(Packet{packet.header,state}));
    const Packet baseline{{1,1,0,0,0},PlayerPresentationBaseline{7,9,std::get<PlayerPresentation>(packet.payload)}};
    CHECK(Encode(baseline)->size()==kHeaderSize+31 && Decode(*Encode(baseline)).packet==baseline);
    const Packet fence{{1,1,0,0,0},PlayerPresentationBaselineEnd{}};
    CHECK(Encode(fence)->size()==kHeaderSize && Decode(*Encode(fence)).packet==fence);
    auto forged=baseline; forged.header.sender=7; CHECK(!Validate(forged));
}
void Policy() {
    SessionRegistry registry;
    const auto host=registry.Create(11,100).membership.value();
    const auto join=registry.Join(host.session,22,100).membership.value();
    CHECK(registry.RegisterPlayer(host.session,host.player)==SessionError::None);
    CHECK(registry.RegisterPlayer(host.session,join.player)==SessionError::None);
    CHECK(registry.MarkSynchronized(host.session,join.player,host.epoch)==SessionError::None);
    auto packet=Packet{{host.session,host.epoch,join.player,1,0},PlayerPresentation{join.player,1,Gun()}};
    CHECK(registry.Receive(22,packet,101));
    const auto cached=[&] { return registry.Find(host.session)->presentations.at(join.player); };
    CHECK(cached().receivedAt==101 && cached().baseline.state.values==Gun());
    packet.header.sequence=2;
    auto invalid=packet; std::get<PlayerPresentation>(invalid.payload).values.aiming=PresentationAim::NotAiming;
    CHECK(registry.Receive(22,invalid,102).error==SessionError::Invalid);
    CHECK(cached().receivedAt==101); // failed same-revision mutation does not renew state or liveness
    CHECK(registry.Receive(22,packet,103));
    CHECK(cached().baseline.state.revision==1 && cached().baseline.sequence==2 && cached().receivedAt==103);
    CHECK(registry.Receive(22,packet,104).error==SessionError::Stale);
    packet.header.sequence=3;
    std::get<PlayerPresentation>(packet.payload).entity=host.player;
    CHECK(registry.Receive(22,packet,105).error==SessionError::Ownership);
    CHECK(registry.Receive(11,packet,105).error==SessionError::Identity);
    std::get<PlayerPresentation>(packet.payload).entity=join.player;
    CHECK(registry.Receive(22,packet,106)); // rejected sequence was not consumed
    const auto other=registry.Create(44,106).membership.value();
    auto cross=packet; cross.header.session=other.session;
    CHECK(registry.Receive(22,cross,107).error==SessionError::MissingMember);
    CHECK(registry.Find(other.session)->presentations.empty());
    auto old=packet; old.header.epoch++; CHECK(registry.Receive(22,old,107).error==SessionError::Epoch);
    CHECK(registry.Disconnect(22));
    CHECK(registry.Find(host.session)->presentations.empty());
    const auto replacement=registry.Join(host.session,33,108).membership.value();
    CHECK(replacement.player!=join.player);
    CHECK(registry.RegisterPlayer(host.session,replacement.player)==SessionError::None);
    CHECK(registry.MarkSynchronized(host.session,replacement.player,host.epoch)==SessionError::None);
    CHECK(registry.Receive(22,packet,109).error==SessionError::MissingMember);
    packet.header.sender=replacement.player; packet.header.sequence=1;
    packet.payload=PlayerPresentation{replacement.player,0xfffffffeu,Gun()};
    CHECK(registry.Receive(33,packet,110));
    packet.header.sequence=2; std::get<PlayerPresentation>(packet.payload).revision=0xffffffffu;
    CHECK(registry.Receive(33,packet,111));
    packet.header.sequence=3; std::get<PlayerPresentation>(packet.payload).revision=1;
    CHECK(registry.Receive(33,packet,112));
    packet.header.sequence=4; std::get<PlayerPresentation>(packet.payload).revision=0xffffffffu;
    CHECK(registry.Receive(33,packet,113).error==SessionError::Stale);
    CHECK(registry.ResetWorld(11)==SessionError::None);
    CHECK(registry.Find(host.session)->presentations.empty());
}
struct Network {
    SessionServer server;
    std::vector<std::unique_ptr<SessionClient>> clients;
    static ServerConfig Config() { ServerConfig c; c.accessKey=std::string(64,'a'); c.port=0; return c; }
    Network():server(Config()) {}
    SessionClient& Add(bool host,Transform pose={}) {
        ClientConfig c; c.server.port=server.Port(); c.accessKey=std::string(64,'a'); c.host=host;
        clients.push_back(std::make_unique<SessionClient>(c));
        auto& client=*clients.back(); CHECK(client.Connect()); client.SetLocal(pose); return client;
    }
    void Step() { auto now=net::NowMs(); server.Tick(now); for(auto& c:clients)c->Tick(now); server.Tick(net::NowMs()); }
    template<class F> void Until(F done) {
        const auto end=net::NowMs()+5000;
        while(!done()) { CHECK(net::NowMs()<end); Step(); std::this_thread::sleep_for(1ms); }
    }
};
void RealSockets() {
    Network n;
    auto& host=n.Add(true);
    n.Until([&]{return host.Phase()==ClientPhase::Active;});
    CHECK(host.SetLocalPresentation(Gun()));
    // Wait until HOST is published before the next client's reliable baseline.
    const auto first=net::NowMs();
    n.Until([&]{return net::NowMs()>first+60;});
    auto& join=n.Add(false);
    n.Until([&]{return join.Phase()==ClientPhase::Active && join.PresentationBaselineReady()
        && join.Remotes().at(host.Member().player).presentation.has_value();});
    const auto hostId=host.Member().player;
    auto received=join.Remotes().at(hostId).presentation.value();
    CHECK(received.state.values==Gun());
    n.Until([&]{return join.Remotes().at(hostId).presentation->receivedAt>received.receivedAt;});
    const auto repaired=join.Remotes().at(hostId).presentation.value();
    CHECK(repaired.state.revision==received.state.revision && IsNewer(repaired.sequence,received.sequence));
    PresentationValues neutral{PresentationStance::Standing,PresentationWeapon::Holstered,0,PresentationAim::NotAiming};
    CHECK(join.SetLocalPresentation(neutral));
    const auto joinId=join.Member().player;
    n.Until([&]{return host.Remotes().at(joinId).presentation.has_value();});
    CHECK(host.Remotes().at(joinId).presentation->state.values==neutral);
    auto& third=n.Add(false,{{2,0,0},{}});
    n.Until([&]{return third.Phase()==ClientPhase::Active && third.PresentationBaselineReady();});
    n.Until([&]{return third.Remotes().at(joinId).presentation.has_value();});
    CHECK(third.Remotes().at(joinId).presentation->state.values==neutral);
    CHECK(join.SetLocalPresentation(Gun()));
    n.Until([&]{return host.Remotes().at(joinId).presentation->state.values==Gun()
        && third.Remotes().at(joinId).presentation->state.values==Gun();});
    const auto thirdId=third.Member().player;
    third.SetLocal({{1000,0,0},{}});
    n.Until([&]{const auto sample=host.Remotes().at(thirdId).snapshots.Sample(static_cast<double>(net::NowMs()));
        return sample && sample->position.x>990;});
    n.Step();
    const auto farReceipt=third.Remotes().at(hostId).presentation->receivedAt;
    CHECK(host.SetLocalPresentation(neutral));
    n.Until([&]{return join.Remotes().at(hostId).presentation->state.values==neutral;});
    const auto wait=net::NowMs(); n.Until([&]{return net::NowMs()>wait+650;});
    CHECK(third.Remotes().at(hostId).presentation->receivedAt==farReceipt); // relevance, not unconditional broadcast
    CHECK(host.SetLocalPresentation(Gun()));
    join.Disconnect();
    n.Until([&]{return !host.Remotes().contains(joinId) && !third.Remotes().contains(joinId);});
    CHECK(join.Connect()); join.SetLocal({});
    n.Until([&]{return join.Phase()==ClientPhase::Active && join.PresentationBaselineReady();});
    CHECK(join.Member().player!=joinId);
    n.Until([&]{return host.Remotes().contains(join.Member().player);});
    CHECK(!host.Remotes().at(join.Member().player).presentation);
    CHECK(join.Remotes().at(hostId).presentation->state.values==Gun());
    host.Disconnect();
    n.Until([&]{return join.Phase()==ClientPhase::Failed && third.Phase()==ClientPhase::Failed;});
    CHECK(join.Remotes().empty() && !join.PresentationBaselineReady());
}
void BridgeScopeAndFreshness() {
    namespace game=coop::game;
    SessionServer server(Network::Config());
    ClientConfig config; config.server.port=server.Port(); config.accessKey=std::string(64,'a');
    config.host=true; config.presentationRepairRate=1;
    game::SessionBridge host(config);
    CHECK(host.SetLocal({})); host.SetActive(true);
    const auto until=[&](auto done) {
        const auto end=net::NowMs()+7000;
        while(!done()) { CHECK(net::NowMs()<end); server.Tick(net::NowMs()); std::this_thread::sleep_for(1ms); }
    };
    until([&]{return host.ReadFrame(net::NowMs()).phase==ClientPhase::Active;});
    const auto original=host.ReadFrame(net::NowMs());
    const game::GameplayScope scope{{original.member.session,original.member.epoch},original.generation};
    CHECK(host.SetLocalPresentation(scope,Gun())==game::PresentationAdmission::Queued);
    CHECK(host.SetLocalPresentation(scope,Gun())==game::PresentationAdmission::Unchanged);
    auto stale=scope; stale.generation++;
    CHECK(host.SetLocalPresentation(stale,Gun())==game::PresentationAdmission::Stale);
    auto invalid=Gun(); invalid.weaponRecord|=0xff00000000000000ULL;
    CHECK(host.SetLocalPresentation(scope,invalid)==game::PresentationAdmission::Invalid);
    config.host=false; config.presentationStaleAfterMs=500;
    game::SessionBridge join(config);
    CHECK(join.SetLocal({{1,0,0},{}})); join.SetActive(true);
    const auto observed=[&]() -> std::optional<game::RenderPresentation> {
        const auto frame=join.ReadFrame(net::NowMs());
        for(const auto& player:frame.players) if(player.player==original.member.player) return player.presentation;
        return {};
    };
    until([&]{const auto value=observed();return value && value->fresh;});
    const auto first=observed().value(); CHECK(first.state.values==Gun());
    until([&]{const auto value=observed();return value && !value->fresh;});
    CHECK(!join.ReadFrame(net::NowMs()).players.empty()); // stale presentation never stalls the body
    until([&]{const auto value=observed();return value && value->fresh && IsNewer(value->sequence,first.sequence);});
    CHECK(observed()->state.revision==first.state.revision); // repair is freshness, not a new command revision
    host.SetActive(false);
    CHECK(host.SetLocalPresentation(scope,Gun())==game::PresentationAdmission::Inactive);
    until([&]{return join.ReadFrame(net::NowMs()).phase==ClientPhase::Failed;});
    CHECK(host.SetLocal({}));host.SetActive(true);
    until([&]{return host.ReadFrame(net::NowMs()).phase==ClientPhase::Active;});
    const auto replacement=host.ReadFrame(net::NowMs());
    CHECK(replacement.member.session!=original.member.session && replacement.generation!=original.generation);
    CHECK(host.SetLocalPresentation(scope,Gun())==game::PresentationAdmission::Stale);
    CHECK(replacement.players.empty());
}
int main() { Codec(); Policy(); RealSockets(); BridgeScopeAndFreshness(); }
