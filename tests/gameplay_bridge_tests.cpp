#include "check.hpp"
#include "coop/game_bridge.hpp"
#include <chrono>
#include <memory>
#include <thread>
#include <limits>
using namespace coop;
namespace g=coop::game;

namespace coop {
struct SessionServerTestAccess {
    static std::optional<std::pair<ConnectionId,Packet>> TakeHostResult(SessionServer& server,PlayerId host) {
        for(auto& [id,peer]:server.peers_) {
            if(!peer.member || peer.member->player!=host) continue;
            std::vector<Packet> incoming; CHECK(peer.control.Pump(incoming));
            std::optional<std::pair<ConnectionId,Packet>> result;
            for(const auto& packet:incoming) {
                if(std::holds_alternative<GameplayResult>(packet.payload)) {CHECK(!result); result=std::pair{id,packet};}
                else server.Control(id,peer,packet,net::NowMs());
            }
            return result;
        }
        return {};
    }
    static void ReleaseHostResult(SessionServer& server,const std::pair<ConnectionId,Packet>& result) {
        server.Control(result.first,server.peers_.at(result.first),result.second,net::NowMs());
    }
    // Intercept one real HOST TCP result and temporarily make one recipient's
    // channel unavailable. The production policy must return uncommitted Full.
    // Restore the original socket immediately; the worker must retry unchanged.
    static bool ResultBackpressure(SessionServer& server,PlayerId host,PlayerId recipient) {
        SessionServer::Peer* destination=nullptr;
        for(auto& [unused,peer]:server.peers_) {
            (void)unused;
            if(peer.member && peer.member->player==recipient) destination=&peer;
        }
        CHECK(destination);
        for(auto& [id,peer]:server.peers_) {
            if(!peer.member || peer.member->player!=host) continue;
            std::vector<Packet> incoming;
            CHECK(peer.control.Pump(incoming));
            bool intercepted=false;
            for(const auto& packet:incoming) {
                if(std::holds_alternative<GameplayResult>(packet.payload)) {
                    auto saved=std::move(destination->control);
                    destination->control=net::Channel{};
                    server.GameplayResultMessage(id,peer,packet,net::NowMs());
                    destination->control=std::move(saved);
                    intercepted=true;
                } else server.Control(id,peer,packet,net::NowMs());
            }
            return intercepted;
        }
        return false;
    }
};
}

struct Network {
    SessionServer server;
    std::vector<std::unique_ptr<g::SessionBridge>> clients;
    Network():server(Config()) {}
    static ServerConfig Config() { ServerConfig c; c.port=0; c.accessKey=std::string(64,'a'); return c; }
    g::SessionBridge& Add(bool host,std::size_t capacity=128,const std::string& room="bridge-route") {
        ClientConfig c; c.host=host; c.accessKey=std::string(64,'a'); c.server.port=server.Port();
        c.gameplayQueueCapacity=capacity; c.sessionName=room;
        clients.push_back(std::make_unique<g::SessionBridge>(c));
        auto& bridge=*clients.back(); CHECK(bridge.SetLocal({})); bridge.SetActive(true);
        Until([&]{return bridge.ReadFrame(net::NowMs()).phase==ClientPhase::Active;}); return bridge;
    }
    template<class F> void Until(F predicate) {
        const auto deadline=net::NowMs()+5000;
        while(!predicate()) {
            CHECK(net::NowMs()<deadline); server.Tick(net::NowMs());
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
    }
    static g::GameplayScope Scope(g::SessionBridge& b) {
        const auto f=b.ReadFrame(net::NowMs()); return {{f.member.session,f.member.epoch},f.generation};
    }
    g::GameplayEvent Wait(g::SessionBridge& b,g::GameplayEventType type) {
        std::optional<g::GameplayEvent> found;
        Until([&]{while(auto event=b.PopGameplay()) if(event->type==type) {found=std::move(*event); return true;} return false;});
        return *found;
    }
};

void ExactTextBoundary() {
    CHECK(g::ParseGameplayId("18446744073709551615")==std::numeric_limits<std::uint64_t>::max());
    CHECK(g::ParseGameplayId("9007199254740993")==9007199254740993ULL);
    for(const auto* invalid:{"","00","01","-1","+1"," 1","1 ","1ULL","1.0","18446744073709551616"}) CHECK(!g::ParseGameplayId(invalid));
    CHECK(g::DecodeGameplayHex("")->empty());
    CHECK((g::DecodeGameplayHex("00ffA17c")==std::vector<std::uint8_t>{0,255,161,124}));
    CHECK(!g::DecodeGameplayHex("0")); CHECK(!g::DecodeGameplayHex("zz"));
    CHECK(g::DecodeGameplayHex(std::string(2048,'a'))->size()==1024);
    CHECK(!g::DecodeGameplayHex(std::string(2050,'a')));
    g::GameplayEvent event;
    event.type=g::GameplayEventType::Outcome;
    event.scope={{9007199254740993ULL,7},18446744073709551615ULL};
    event.packet={{9007199254740993ULL,7,4,0,9007199254740995ULL},GameplayResult{12,9007199254740997ULL,3,GameplayDisposition::Accepted,0,{0,255}}};
    CHECK(g::EncodeGameplayEvent(event)=="outcome|9007199254740993|7|18446744073709551615|4|9007199254740995|12|9007199254740997|3|2|0|00ff");
}

void WorkerRoutingAndReservedResult() {
    Network n; auto& host=n.Add(true); auto& joiner=n.Add(false); auto& observer=n.Add(false);
    auto& otherHost=n.Add(true,128,"other-room"); auto& other=n.Add(false,128,"other-room");
    const auto hs=Network::Scope(host),js=Network::Scope(joiner);
    CHECK(host.SubmitGameplay(hs,1,{1}).status==g::GameplayAdmission::Authority);
    auto stale=js; ++stale.generation;
    CHECK(joiner.SubmitGameplay(stale,1,{1}).status==g::GameplayAdmission::Stale);
    stale=js; ++stale.identity.epoch;
    CHECK(joiner.SubmitGameplay(stale,1,{1}).status==g::GameplayAdmission::Stale);
    CHECK(joiner.SubmitGameplay(js,0,{}).status==g::GameplayAdmission::Invalid);
    CHECK(joiner.SubmitGameplay(js,1,std::vector<std::uint8_t>(1025)).status==g::GameplayAdmission::Invalid);
    std::vector<std::uint8_t> bytes(1024); for(std::size_t i=0;i<bytes.size();++i) bytes[i]=static_cast<std::uint8_t>(i);
    auto submitted=joiner.SubmitGameplay(js,321,bytes); CHECK(submitted.status==g::GameplayAdmission::Queued);
    auto intent=n.Wait(host,g::GameplayEventType::Intent);
    CHECK(intent.scope==hs); CHECK(intent.packet.header.sender==joiner.ReadFrame(net::NowMs()).member.player);
    CHECK(std::get<GameplayIntent>(intent.packet.payload).body==bytes);
    auto sent=n.Wait(joiner,g::GameplayEventType::SentIntent);
    CHECK(sent.ticket==submitted.ticket && sent.event==intent.packet.header.event);
    GameplayResult result{intent.packet.header.sender,intent.packet.header.event,321,GameplayDisposition::Accepted,9,bytes};
    CHECK(joiner.CompleteGameplay(js,result).status==g::GameplayAdmission::Authority);
    auto wrong=result; ++wrong.requestEvent;
    CHECK(host.CompleteGameplay(hs,wrong).status==g::GameplayAdmission::Missing);
    wrong=result; wrong.kind=0;
    CHECK(host.CompleteGameplay(hs,wrong).status==g::GameplayAdmission::Invalid);
    auto reply=host.CompleteGameplay(hs,result); CHECK(reply.status==g::GameplayAdmission::Queued);
    CHECK(host.CompleteGameplay(hs,result).ticket==reply.ticket);
    wrong=result; wrong.body.clear(); CHECK(host.CompleteGameplay(hs,wrong).status==g::GameplayAdmission::Invalid);
    auto outcome=n.Wait(joiner,g::GameplayEventType::Outcome);
    auto seen=n.Wait(observer,g::GameplayEventType::Outcome);
    CHECK(outcome.scope==js); CHECK(outcome.packet==seen.packet);
    CHECK(std::get<GameplayResult>(outcome.packet.payload)==result);
    CHECK(outcome.packet.header.sender==host.ReadFrame(net::NowMs()).member.player);
    auto ack=n.Wait(host,g::GameplayEventType::Status);
    CHECK(ack.status.committed && ack.status.correlationEvent==outcome.packet.header.event);
    CHECK(host.CompleteGameplay(hs,result).status==g::GameplayAdmission::Missing);
    CHECK(!other.PopGameplay()); CHECK(!otherHost.PopGameplay()); CHECK(host.GameplayFault().empty());
    CHECK(host.SubmitWorld(g::EntityDeath{7,1})==g::SubmitResult::Unsupported);
}

void FullQueuesAndScopeReset() {
    Network n; auto& host=n.Add(true,1); auto& joiner=n.Add(false,1);
    const auto old=Network::Scope(joiner);
    bool full=false;
    for(int i=0;i<100;++i) {
        auto sent=joiner.SubmitGameplay(old,8,{1});
        if(sent.status==g::GameplayAdmission::Full) {full=true; break;}
        CHECK(sent.status==g::GameplayAdmission::Queued);
    }
    CHECK(full);
    joiner.SetActive(false);
    CHECK(!joiner.PopGameplay());
    CHECK(joiner.SubmitGameplay(old,8,{1}).status==g::GameplayAdmission::Inactive);
    CHECK(joiner.SetLocal({})); joiner.SetActive(true);
    n.Until([&]{const auto f=joiner.ReadFrame(net::NowMs()); return f.phase==ClientPhase::Active && f.generation!=old.generation;});
    CHECK(!joiner.PopGameplay());
    CHECK(joiner.SubmitGameplay(old,8,{1}).status==g::GameplayAdmission::Stale);
    // Old HOST ingress, if already delivered by TCP, is a distinct retired
    // sender identity. It is never reassigned to this new member.
    while(auto ignored=host.PopGameplay()) { (void)ignored; }
}

void ResultBackpressureRetainsExactOutcome() {
    Network n; auto& host=n.Add(true); auto& joiner=n.Add(false);
    const auto hs=Network::Scope(host),js=Network::Scope(joiner);
    const auto request=joiner.SubmitGameplay(js,4,{0x44}); CHECK(request.status==g::GameplayAdmission::Queued);
    auto intent=n.Wait(host,g::GameplayEventType::Intent);
    GameplayResult result{intent.packet.header.sender,intent.packet.header.event,4,GameplayDisposition::Accepted,0,{0x55,0x66}};
    const auto reply=host.CompleteGameplay(hs,result); CHECK(reply.status==g::GameplayAdmission::Queued);
    const auto hostId=host.ReadFrame(net::NowMs()).member.player;
    const auto joinerId=joiner.ReadFrame(net::NowMs()).member.player;
    const auto deadline=net::NowMs()+5000;
    while(!SessionServerTestAccess::ResultBackpressure(n.server,hostId,joinerId)) {
        CHECK(net::NowMs()<deadline); std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    bool full=false,committed=false; std::uint64_t sentEvent=0; unsigned sentCount=0;
    std::optional<g::GameplayEvent> outcome;
    // An NPC lifecycle command must not leap over the uncommitted result ID.
    CHECK(host.OfferNpc(900,123,{}));
    n.Until([&]{
        while(auto event=host.PopGameplay()) {
            if(event->type==g::GameplayEventType::SentResult) {++sentCount; sentEvent=event->event; CHECK(event->ticket==reply.ticket);}
            if(event->type==g::GameplayEventType::Status) {
                if(event->status.disposition==GameplayDisposition::Full) {CHECK(!event->status.committed); full=true;}
                if(event->status.committed) {CHECK(event->status.correlationEvent==sentEvent); committed=true;}
            }
        }
        while(auto event=joiner.PopGameplay()) if(event->type==g::GameplayEventType::Outcome) {CHECK(!outcome); outcome=*event;}
        return full && committed && outcome && joiner.ReadFrame(net::NowMs()).npcs.size()==1;
    });
    CHECK(sentCount==1); CHECK(outcome->packet.header.event==sentEvent);
    CHECK(std::get<GameplayResult>(outcome->packet.payload)==result);
    CHECK(host.GameplayFault().empty()); CHECK(joiner.GameplayFault().empty());
}

void TransportFailureIsExplicit() {
    Network n; auto& host=n.Add(true); auto& joiner=n.Add(false);
    const auto hs=Network::Scope(host),js=Network::Scope(joiner);
    CHECK(joiner.SubmitGameplay(js,2,{1}).status==g::GameplayAdmission::Queued);
    auto intent=n.Wait(host,g::GameplayEventType::Intent); (void)intent;
    host.SetActive(false);
    n.Until([&]{return joiner.ReadFrame(net::NowMs()).phase==ClientPhase::Failed;});
    CHECK(!joiner.GameplayFault().empty()); CHECK(!joiner.PopGameplay());
    CHECK(joiner.SubmitGameplay(js,2,{1}).status==g::GameplayAdmission::Inactive);
    CHECK(host.CompleteGameplay(hs,{1,1,1,GameplayDisposition::Accepted,0,{}}).status==g::GameplayAdmission::Inactive);
}

void ResultsPreserveCompletionOrderAcrossPlayers() {
    Network n; auto& host=n.Add(true); auto& earlierPlayer=n.Add(false); auto& laterPlayer=n.Add(false);
    const auto hs=Network::Scope(host);
    CHECK(earlierPlayer.SubmitGameplay(Network::Scope(earlierPlayer),1,{0}).status==g::GameplayAdmission::Queued);
    auto first=n.Wait(host,g::GameplayEventType::Intent);
    CHECK(host.CompleteGameplay(hs,{first.packet.header.sender,first.packet.header.event,1,GameplayDisposition::Accepted,0,{0}}).status==g::GameplayAdmission::Queued);
    // Keep the preceding result unacknowledged, so both next completions are
    // certainly ready before the worker can select either one.
    std::optional<std::pair<ConnectionId,Packet>> held;
    const auto deadline=net::NowMs()+5000;
    while(!held) {
        held=SessionServerTestAccess::TakeHostResult(n.server,host.ReadFrame(net::NowMs()).member.player);
        CHECK(net::NowMs()<deadline); std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    CHECK(earlierPlayer.SubmitGameplay(Network::Scope(earlierPlayer),1,{1}).status==g::GameplayAdmission::Queued);
    CHECK(laterPlayer.SubmitGameplay(Network::Scope(laterPlayer),1,{2}).status==g::GameplayAdmission::Queued);
    auto a=n.Wait(host,g::GameplayEventType::Intent),b=n.Wait(host,g::GameplayEventType::Intent);
    const auto* lower=&a; const auto* higher=&b;
    if(a.packet.header.sender>b.packet.header.sender) {lower=&b; higher=&a;}
    const auto high=host.CompleteGameplay(hs,{higher->packet.header.sender,higher->packet.header.event,1,GameplayDisposition::Accepted,0,{75}});
    const auto low=host.CompleteGameplay(hs,{lower->packet.header.sender,lower->packet.header.event,1,GameplayDisposition::Accepted,0,{50}});
    CHECK(high.status==g::GameplayAdmission::Queued && low.status==g::GameplayAdmission::Queued && high.ticket<low.ticket);
    SessionServerTestAccess::ReleaseHostResult(n.server,*held);
    std::vector<unsigned> health;
    n.Until([&]{
        while(auto event=host.PopGameplay()) {(void)event;}
        while(auto event=laterPlayer.PopGameplay()) if(event->type==g::GameplayEventType::Outcome)
            health.push_back(std::get<GameplayResult>(event->packet.payload).body.at(0));
        while(auto event=earlierPlayer.PopGameplay()) {(void)event;}
        return health.size()==3;
    });
    CHECK((health==std::vector<unsigned>{0,75,50}));
}

int main() { return Run([]{ExactTextBoundary(); WorkerRoutingAndReservedResult(); FullQueuesAndScopeReset(); ResultBackpressureRetainsExactOutcome(); TransportFailureIsExplicit(); ResultsPreserveCompletionOrderAcrossPlayers();}); }
