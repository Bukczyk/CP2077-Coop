#include "check.hpp"
#include "coop/client.hpp"
#include "coop/game_bridge.hpp"
#include <chrono>
#include <limits>
#include <thread>
using namespace coop;
void Codec() {
    const EntityId id=kNpcEntityBase;
    const std::vector<Packet> packets{
        {{1,1,1,0,1},NpcAdopt{8,123,{}}},
        {{1,1,0,0,0},NpcSpawn{id,8,123,{},9,100}},
        {{1,1,1,0,2},NpcDespawn{id}}, {{1,1,0,0,0},NpcRemoved{id}},
        {{1,1,1,1,0},NpcState{id,{},100}}, {{1,1,0,0,0},NpcSnapshotEnd{}},
        {{1,1,0,0,0},NpcDenied{8}}};
    for(auto p:packets) {
        auto bytes=Encode(p); CHECK(bytes); CHECK(Decode(*bytes).packet==p);
        for(std::size_t i=0;i<bytes->size();++i) CHECK(!Decode(std::span<const std::uint8_t>(*bytes).first(i)));
        bytes->push_back(0); CHECK(!Decode(*bytes));
    }
    CHECK(!Encode(Packet{{1,1,1,0,1},NpcAdopt{1,0,{}}}));
    CHECK(!Encode(Packet{{1,1,1,0,1},NpcAdopt{1,1ULL<<40,{}}}));
    CHECK(!Encode(Packet{{1,1,1,0,1},NpcAdopt{0,123,{}}}));
    CHECK(!Encode(Packet{{1,1,1,1,0},NpcState{1,{},100}}));
    Transform nan; nan.position.x=std::numeric_limits<float>::quiet_NaN();
    CHECK(!Encode(Packet{{1,1,1,1,0},NpcState{id,nan,100}}));
}
void Policy() {
    SessionRegistry r; auto h=*r.Create(10,0).membership; auto j=*r.Join(h.session,11,0).membership;
    CHECK(r.RegisterPlayer(h.session,h.player)==SessionError::None);
    CHECK(r.RegisterPlayer(j.session,j.player)==SessionError::None);
    CHECK(r.MarkSynchronized(j.session,j.player,j.epoch)==SessionError::None);
    Packet adopt{{h.session,h.epoch,h.player,0,1},NpcAdopt{99,123,{{1,2,3},{}}}};
    auto wrong=adopt; wrong.header.sender=j.player;
    CHECK(r.Receive(11,wrong,1).error==SessionError::Authority);
    CHECK(r.Receive(11,adopt,1).error==SessionError::Identity);
    auto first=r.Receive(10,adopt,1); CHECK(first && first.adopted);
    const auto id=first.adopted->entity; CHECK(id>=kNpcEntityBase);
    CHECK(r.Find(h.session)->entities.at(id).owner==h.player);
    CHECK(r.Receive(10,adopt,2).error==SessionError::Duplicate);
    adopt.header.event=3; CHECK(r.Receive(10,adopt,2).error==SessionError::EventGap);
    adopt.header.event=2; auto duplicate=r.Receive(10,adopt,2);
    CHECK(duplicate.adopted->entity==id && r.Find(h.session)->npcs.size()==1);
    Packet state{{h.session,h.epoch,h.player,5,0},NpcState{id,{{4,5,6},{}},100}};
    CHECK(r.Receive(10,state,3)); CHECK(r.Receive(10,state,4).error==SessionError::Stale);
    state.header.sequence=4; std::get<NpcState>(state.payload).sampleTimeMs=101;
    CHECK(r.Receive(10,state,4).error==SessionError::Stale);
    state.header.sequence=6; std::get<NpcState>(state.payload).sampleTimeMs=99;
    CHECK(r.Receive(10,state,4).error==SessionError::Stale);
    state.header.sender=j.player; CHECK(r.Receive(11,state,4).error==SessionError::Authority);
    state.header.sender=h.player;
    auto other=*r.Create(20,4).membership; state.header.session=other.session;
    CHECK(!r.Receive(10,state,4)); state.header.session=h.session;
    CHECK(r.Receive(10,Packet{{h.session,h.epoch,h.player,0,3},NpcDespawn{id}},5));
    CHECK(r.Find(h.session)->npcs.empty());
    CHECK(r.Receive(10,state,6).error==SessionError::MissingEntity);
    adopt.header.event=4; CHECK(r.Receive(10,adopt,6).error==SessionError::EntityReuse);
    CHECK(r.ResetWorld(11)==SessionError::Authority);
    CHECK(r.ResetWorld(10)==SessionError::None);
    CHECK(r.Receive(10,adopt,7).error==SessionError::Epoch);
    adopt.header.epoch++; adopt.header.event=1;
    auto reset=r.Receive(10,adopt,7); CHECK(reset && reset.adopted);
    CHECK(reset.adopted->entity==id); // Same numeric namespace, distinct epoch identity.
    game::EntityRegistry mappings; mappings.Reset({h.session,h.epoch},h.player);
    CHECK(mappings.Accept({h.session,h.epoch},{id,game::Kind::NPC,h.player,h.player,0},h.player));
    CHECK(mappings.Bind(id,0x123456789abcdefULL)); CHECK(mappings.FromLocal(0x123456789abcdefULL)==id);
    mappings.Reset({h.session,h.epoch+1},h.player); CHECK(!mappings.FromLocal(0x123456789abcdefULL));
    CHECK(!mappings.Accept({h.session,h.epoch},{id,game::Kind::NPC,h.player,h.player,0},h.player));
    SessionLimits limits; limits.maxNpcs=1; SessionRegistry bounded(limits); auto b=*bounded.Create(30,0).membership;
    CHECK(bounded.Receive(30,Packet{{b.session,b.epoch,b.player,0,1},NpcAdopt{1,123,{}}},1).adopted);
    auto denied=bounded.Receive(30,Packet{{b.session,b.epoch,b.player,0,2},NpcAdopt{2,123,{}}},2);
    CHECK(denied && denied.npcDenied && bounded.Find(b.session)->npcs.size()==1);
}
void Sockets() {
    ServerConfig sc; sc.port=0; sc.accessKey=std::string(64,'a'); SessionServer server(sc);
    ClientConfig hc; hc.host=true; hc.server.port=server.Port(); hc.accessKey=sc.accessKey;
    ClientConfig jc=hc; jc.host=false;
    SessionClient host(hc),joiner(jc);
    host.SetLocal({}); joiner.SetLocal({}); CHECK(host.Connect());
    auto until=[&](auto done) {
        const auto deadline=net::NowMs()+5000;
        while(!done()) {
            CHECK(net::NowMs()<deadline); auto now=net::NowMs(); server.Tick(now); host.Tick(now); joiner.Tick(now);
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
    };
    until([&]{return host.Phase()==ClientPhase::Active;});
    until([&]{return host.AdoptNpc(77,123,{{1,0,0},{}});});
    until([&]{return host.Npcs().size()==1;}); const auto id=host.Npcs().begin()->first;
    CHECK(host.AdoptNpc(77,123,{})); CHECK(host.Npcs().size()==1);
    CHECK(joiner.Connect()); until([&]{return joiner.Phase()==ClientPhase::Active;});
    CHECK(joiner.Npcs().size()==1 && joiner.Npcs().contains(id));
    CHECK(!joiner.AdoptNpc(88,123,{})); CHECK(!joiner.SendNpcSnapshot(id,{},1,100)); CHECK(!joiner.DespawnNpc(id));
    CHECK(host.SendNpcSnapshot(id,{{2,0,0},{}},1,100));
    until([&]{return joiner.Npcs().at(id).descriptor.sequence==1;});
    auto stale=server.Stats().stale;
    CHECK(host.SendNpcSnapshot(id,{{99,0,0},{}},1,101)); until([&]{return server.Stats().stale>stale;});
    stale=server.Stats().stale;
    CHECK(host.SendNpcSnapshot(id,{{99,0,0},{}},2,99)); until([&]{return server.Stats().stale>stale;});
    CHECK(joiner.Npcs().at(id).descriptor.transform.position.x==2);
    CHECK(host.SendNpcSnapshot(id,{{3,0,0},{}},2,102));
    until([&]{return joiner.Npcs().at(id).descriptor.sequence==2;});
    CHECK(joiner.Npcs().at(id).snapshots.Sample(static_cast<double>(net::NowMs())));
    const auto oldPlayer=joiner.Member().player;
    joiner.Disconnect(); until([&]{return !host.Remotes().contains(oldPlayer);});
    CHECK(joiner.Connect()); until([&]{return joiner.Phase()==ClientPhase::Active;});
    CHECK(joiner.Member().player!=oldPlayer && joiner.Npcs().contains(id));
    CHECK(joiner.Npcs().at(id).descriptor.sequence==2);
    CHECK(joiner.Npcs().at(id).descriptor.transform.position.x==3);
    until([&]{return host.DespawnNpc(id);});
    until([&]{return host.Npcs().empty() && joiner.Npcs().empty();});
    joiner.Disconnect(); CHECK(joiner.Connect());
    until([&]{return joiner.Phase()==ClientPhase::Active;}); CHECK(joiner.Npcs().empty());
    until([&]{return host.AdoptNpc(78,123,{});}); until([&]{return !joiner.Npcs().empty();});
    CHECK(joiner.Npcs().begin()->first!=id);
    host.Disconnect(); until([&]{return joiner.Phase()==ClientPhase::Failed;}); CHECK(joiner.Npcs().empty());
}
void CatalogAndInterest() {
    ServerConfig sc; sc.port=0; sc.accessKey=std::string(64,'a'); SessionServer server(sc);
    ClientConfig hc; hc.host=true; hc.server.port=server.Port(); hc.accessKey=sc.accessKey;
    ClientConfig jc=hc; jc.host=false;
    SessionClient host(hc),joiner(jc); host.SetLocal({}); joiner.SetLocal({}); CHECK(host.Connect());
    auto until=[&](auto done) {
        const auto deadline=net::NowMs()+8000;
        while(!done()) {
            CHECK(net::NowMs()<deadline); auto now=net::NowMs(); server.Tick(now); host.Tick(now); joiner.Tick(now);
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
    };
    until([&]{return host.Phase()==ClientPhase::Active;});
    for(unsigned i=1;i<=48;++i) until([&]{return host.AdoptNpc(i,123,{{1000,0,0},{}});});
    until([&]{return host.Npcs().size()==48;});
    CHECK(joiner.Connect()); until([&]{return joiner.Phase()==ClientPhase::Active;});
    CHECK(joiner.Npcs().size()==48); // catalog exceeds a single control batch
    const auto id=host.Npcs().begin()->first;
    CHECK(host.SendNpcSnapshot(id,{{1000,0,0},{}},1,100));
    const auto stop=net::NowMs()+200;
    until([&]{return net::NowMs()>=stop;});
    CHECK(joiner.Npcs().at(id).descriptor.sequence==0 && server.Stats().filtered>0);
    joiner.SetLocal({{1000,0,0},{}});
    until([&]{return joiner.Npcs().at(id).descriptor.sequence==1;});
    const auto old=joiner.Member().player;
    joiner.Disconnect(); until([&]{return !host.Remotes().contains(old);}); CHECK(joiner.Connect());
    until([&]{return joiner.Phase()==ClientPhase::Active;}); CHECK(joiner.Npcs().size()==48);
    CHECK(joiner.Npcs().at(id).descriptor.sequence==1);
    std::vector<EntityId> ids; for(const auto& [entity,npc]:host.Npcs()) { (void)npc; ids.push_back(entity); }
    for(auto entity:ids) until([&]{return host.DespawnNpc(entity);});
    until([&]{return host.Npcs().empty() && joiner.Npcs().empty();});
}
int main() { return Run([]{Codec();Policy();Sockets();CatalogAndInterest();}); }
