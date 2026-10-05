#include "check.hpp"
#include "coop/client.hpp"
#include <chrono>
#include <cmath>
#include <memory>
#include <thread>
using namespace coop;
using namespace std::chrono_literals;
struct Network {
    std::vector<std::string> logs;
    SessionServer server;
    std::vector<std::unique_ptr<SessionClient>> clients;
    Network() : server(Config(),[this](const std::string& s){ logs.push_back(s); }) {}
    static ServerConfig Config() { ServerConfig c; c.accessKey=std::string(64,'a'); c.port=0; return c; }
    SessionClient& Add(bool host,bool automatic=false,std::string key=std::string(64,'a'),unsigned rate=60) {
        ClientConfig c; c.server.port=server.Port(); c.accessKey=std::move(key); c.host=host;
        c.automaticSnapshots=automatic; c.playerSnapshotRate=rate;
        clients.push_back(std::make_unique<SessionClient>(c,[this](const std::string& s){ logs.push_back(s); }));
        CHECK(clients.back()->Connect()); return *clients.back();
    }
    void Step() {
        const auto now=net::NowMs(); server.Tick(now);
        for(auto& c:clients) c->Tick(now);
        server.Tick(net::NowMs());
    }
    template<class F> void Until(F done) {
        const auto deadline=net::NowMs()+5000;
        while(!done()) {
            Step();
            if(net::NowMs()>=deadline) { for(const auto& l:logs) std::cerr<<l<<'\n'; CHECK(false); }
            std::this_thread::sleep_for(1ms);
        }
    }
};
void EndToEnd() {
    Network n;
    auto& host=n.Add(true);
    n.Until([&]{ return host.Phase()==ClientPhase::Active; });
    CHECK(host.Member().session && host.Member().player && host.Host()==host.Member().player);
    CHECK(host.SendLocalSnapshot({{10,20,30},{}},1,net::NowMs()));
    auto& joiner=n.Add(false);
    n.Until([&]{ return joiner.Phase()==ClientPhase::Active; });
    const auto firstId=joiner.Member().player;
    CHECK(firstId!=host.Member().player && joiner.Member().session==host.Member().session);
    CHECK(joiner.Remotes().at(host.Member().player).initialized);
    CHECK(n.server.Stats().hellos==2 && n.server.Stats().creates==1 && n.server.Stats().joins==1);
    const auto firstTime=net::NowMs();
    CHECK(joiner.SendLocalSnapshot({{1,0,0},{}},10,firstTime));
    n.Until([&]{ return host.Remotes().contains(firstId) && host.Remotes().at(firstId).sequence==10; });
    const auto arrivalA=host.Remotes().at(firstId).receivedTime;
    auto rejected=n.server.Stats().stale;
    CHECK(joiner.SendLocalSnapshot({{99,0,0},{}},9,firstTime+1));
    n.Until([&]{ return n.server.Stats().stale>rejected; });
    CHECK(host.Remotes().at(firstId).sequence==10);
    rejected=n.server.Stats().stale;
    CHECK(joiner.SendLocalSnapshot({{99,0,0},{}},11,firstTime-1));
    n.Until([&]{ return n.server.Stats().stale>rejected; });
    CHECK(host.Remotes().at(firstId).sequence==10);
    CHECK(joiner.SendLocalSnapshot({{2,0,0},{}},11,firstTime+100));
    n.Until([&]{ return host.Remotes().at(firstId).sequence==11; });
    const auto& remote=host.Remotes().at(firstId);
    CHECK(remote.receivedTime>arrivalA);
    const auto interpolated=remote.snapshots.Sample((static_cast<double>(arrivalA)+static_cast<double>(remote.receivedTime))/2+100);
    CHECK(interpolated && std::abs(interpolated->position.x-1.5f)<0.01f);
    joiner.Disconnect();
    n.Until([&]{ return !host.Remotes().contains(firstId); });
    CHECK(joiner.Connect());
    n.Until([&]{ return joiner.Phase()==ClientPhase::Active; });
    CHECK(joiner.Member().player!=firstId && joiner.Member().session==host.Member().session);
    CHECK(host.Remotes().contains(joiner.Member().player));
    host.Disconnect();
    n.Until([&]{ return joiner.Phase()==ClientPhase::Failed; });
    CHECK(joiner.Remotes().empty());
}
void DynamicPlayersAndInterest() {
    Network n;
    auto& host=n.Add(true,true); host.SetLocal({});
    n.Until([&]{ return host.Phase()==ClientPhase::Active; });
    for(unsigned i=0;i<15;++i) {
        auto& c=n.Add(false,true); c.SetLocal({{i==14?1000.0f:static_cast<float>(i),0,0},{}});
        n.Until([&]{ return c.Phase()==ClientPhase::Active; });
    }
    CHECK(host.Remotes().size()==15);
    auto& near=*n.clients[1]; auto& far=*n.clients[15]; const auto farId=far.Member().player;
    n.Until([&]{ return host.Remotes().at(farId).initialized && n.server.Stats().filtered>0; });
    CHECK(near.Remotes().size()==15);
    CHECK(!near.Remotes().at(farId).initialized); // membership known, irrelevant world state not broadcast
    far.SetLocal({{3,0,0},{}});
    n.Until([&]{ return near.Remotes().at(farId).initialized; });
    auto& full=n.Add(false);
    n.Until([&]{ return full.Phase()==ClientPhase::Failed; });
    CHECK(n.server.Stats().joins==15);
    auto& bad=n.Add(false,false,std::string(64,'b'));
    n.Until([&]{ return bad.Phase()==ClientPhase::Failed; });
    CHECK(n.server.Stats().hellos==17); // authenticated full-session attempt included; bad key excluded
}
void ConfiguredRate() {
    Network n; auto& host=n.Add(true,true); host.SetLocal({});
    n.Until([&]{ return host.Phase()==ClientPhase::Active; });
    auto& slow=n.Add(false,true,std::string(64,'a'),10); slow.SetLocal({});
    n.Until([&]{ return slow.Phase()==ClientPhase::Active; });
    const auto start=net::NowMs(), before=slow.Stats().sent;
    n.Until([&]{ return net::NowMs()-start>=400; });
    const auto count=slow.Stats().sent-before;
    CHECK(count>=1 && count<=5);
}
int main() { return Run([]{ EndToEnd(); DynamicPlayersAndInterest(); ConfiguredRate(); }); }
