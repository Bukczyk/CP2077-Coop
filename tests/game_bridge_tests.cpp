#include "check.hpp"
#include "coop/game_bridge.hpp"
#include <chrono>
#include <limits>
#include <thread>
using namespace coop;
namespace g=coop::game;
void Registry() {
    g::EntityRegistry r(3); r.Reset({7,1},10);
    const EntityId npc=0x20000000000001ULL; // no Lua-number/position identity truncation
    CHECK(r.Accept({7,1},{npc,g::Kind::NPC,10,10,0},10));
    CHECK(r.Accept({7,1},{11,g::Kind::Player,11,10,0},10));
    CHECK(!r.Accept({7,1},{12,g::Kind::World,10,10,0},11));
    CHECK(!r.Accept({8,1},{12,g::Kind::World,10,10,0},10));
    CHECK(!r.Accept({7,2},{12,g::Kind::World,10,10,0},10));
    CHECK(!r.Accept({7,1},{npc,g::Kind::Vehicle,10,10,0},10));
    CHECK(r.Bind(npc,900)); CHECK(!r.Bind(11,900));
    CHECK(r.FromLocal(900)==npc); CHECK(r.Bind(npc,901)); CHECK(!r.FromLocal(900));
    CHECK(r.Accept({7,1},{12,g::Kind::Vehicle,10,10,0},10));
    CHECK(!r.Accept({7,1},{13,g::Kind::World,10,10,0},10));
    CHECK(r.Remove(npc)); CHECK(!r.FromLocal(901));
    r.Reset({7,2},10); CHECK(r.Size()==0); CHECK(!r.Find(11));
}
void Events() {
    g::EventInbox inbox(1); inbox.Reset({7,1},10);
    g::AcceptedEvent a{{7,1},10,1,g::EntityDeath{42,3}};
    auto wrong=a; wrong.authority=11; CHECK(inbox.Push(wrong)==g::SubmitResult::Authority);
    wrong=a; wrong.identity.session=8; CHECK(inbox.Push(wrong)==g::SubmitResult::Stale);
    CHECK(inbox.Push(a)==g::SubmitResult::Accepted);
    CHECK(inbox.Push(a)==g::SubmitResult::Stale);
    a.event=3; CHECK(inbox.Push(a)==g::SubmitResult::Stale);
    a.event=2; CHECK(inbox.Push(a)==g::SubmitResult::Full);
    CHECK(inbox.Pop()->event==1); CHECK(inbox.Push(a)==g::SubmitResult::Accepted);
    inbox.Reset({7,2},10); CHECK(!inbox.Pop()); CHECK(inbox.Push(a)==g::SubmitResult::Stale);
}
void WorkerSockets() {
    ServerConfig sc; sc.port=0; sc.accessKey=std::string(64,'a'); SessionServer server(sc);
    ClientConfig hc; hc.host=true; hc.accessKey=sc.accessKey; hc.server.port=server.Port();
    ClientConfig jc=hc; jc.host=false;
    g::SessionBridge host(hc),joiner(jc);
    auto until=[&](auto predicate) {
        const auto deadline=net::NowMs()+5000;
        while(!predicate()) { CHECK(net::NowMs()<deadline); server.Tick(net::NowMs()); std::this_thread::sleep_for(std::chrono::milliseconds(1)); }
    };
    CHECK(host.SetLocal({{10,20,30},{}})); host.SetActive(true);
    until([&]{return host.ReadFrame(net::NowMs()).phase==ClientPhase::Active;});
    CHECK(joiner.SetLocal({{11,20,30},{}})); joiner.SetActive(true);
    until([&]{return joiner.ReadFrame(net::NowMs()).phase==ClientPhase::Active && host.ReadFrame(net::NowMs()).players.size()==1;});
    auto frame=joiner.ReadFrame(net::NowMs()); CHECK(frame.players.size()==1);
    CHECK(frame.players[0].player==frame.host); CHECK(frame.players[0].transform.position.x==10);
    const auto old=frame.member.player;
    constexpr std::uint64_t localNpc=0x123456789abcULL;
    CHECK(host.OfferNpc(localNpc,123,{{12,20,30},{}}));
    CHECK(host.OfferNpc(localNpc,123,{{13,20,30},{}}));
    CHECK(!host.OfferNpc(localNpc,124,{})); CHECK(!joiner.OfferNpc(42,123,{}));
    until([&]{return joiner.ReadFrame(net::NowMs()).npcs.size()==1 && host.ReadFrame(net::NowMs()).npcs.size()==1;});
    const auto npcId=joiner.ReadFrame(net::NowMs()).npcs.front().descriptor.entity;
    CHECK(npcId>=kNpcEntityBase);
    auto hostFrame=host.ReadFrame(net::NowMs()); CHECK(hostFrame.npcs.size()==1 && hostFrame.npcs.front().hostLocal==localNpc);
    CHECK(joiner.ReadFrame(net::NowMs()).npcs.front().hostLocal==0);
    host.ForgetNpc(localNpc);
    until([&]{return joiner.ReadFrame(net::NowMs()).npcs.empty() && host.ReadFrame(net::NowMs()).npcs.empty();});
    until([&]{return host.OfferNpc(localNpc,123,{{14,20,30},{}});});
    until([&]{return !joiner.ReadFrame(net::NowMs()).npcs.empty();});
    CHECK(joiner.ReadFrame(net::NowMs()).npcs.front().descriptor.entity!=npcId);
    Transform invalid; invalid.position.x=std::numeric_limits<float>::quiet_NaN(); CHECK(!host.SetLocal(invalid));
    CHECK(host.SubmitWorld(g::EntityDeath{10,1})==g::SubmitResult::Unsupported);
    joiner.SetActive(false); CHECK(joiner.ReadFrame(net::NowMs()).players.empty());
    // Rapid load transition must not be lost between worker iterations.
    CHECK(joiner.SetLocal({{12,20,30},{}})); joiner.SetActive(true);
    until([&]{auto f=joiner.ReadFrame(net::NowMs());return f.phase==ClientPhase::Active && f.member.player!=old;});
    until([&]{auto f=host.ReadFrame(net::NowMs());return f.players.size()==1 && f.players[0].player!=old;});
    host.SetActive(false);
    until([&]{return joiner.ReadFrame(net::NowMs()).phase==ClientPhase::Failed;});
}
int main() { return Run([]{Registry(); Events(); WorkerSockets();}); }
