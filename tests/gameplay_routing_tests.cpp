#include "check.hpp"
#include "coop/client.hpp"
#include <chrono>
#include <memory>
#include <thread>

using namespace coop;
using namespace std::chrono_literals;

namespace coop {
struct SessionServerTestAccess {
    static bool ResetHostEpoch(SessionServer& server, PlayerId host) {
        for (const auto& [connection, peer] : server.peers_)
            if (peer.member && peer.member->player == host)
                return server.registry_.ResetWorld(connection) == SessionError::None;
        return false;
    }
};
struct SessionClientTestAccess {
    static bool QueueIntentAs(SessionClient& client, PlayerId sender, std::uint64_t event) {
        Packet packet{{client.member_.session, client.member_.epoch, sender, 0, event},
                      GameplayIntent{1, {0x2a}}};
        return Validate(packet) && client.control_.CanQueue() && client.control_.Queue(packet);
    }
    static bool QueueResultAs(SessionClient& client, PlayerId sender, PlayerId requester,
                              std::uint64_t requestEvent, std::uint64_t hostEvent) {
        Packet packet{{client.member_.session, client.member_.epoch, sender, 0, hostEvent},
            GameplayResult{requester, requestEvent, 1, GameplayDisposition::Rejected, 7, {}}};
        return Validate(packet) && client.control_.CanQueue() && client.control_.Queue(packet);
    }
    static void DeliverDuplicateResult(SessionClient& client, const Packet& packet) {
        client.Control(packet,net::NowMs());
    }
};
} // namespace coop

struct Network {
    std::vector<std::string> logs;
    SessionServer server;
    std::vector<std::unique_ptr<SessionClient>> clients;
    explicit Network(ServerConfig config = Config())
        : server(std::move(config), [this](const std::string& line) { logs.push_back(line); }) {}
    static ServerConfig Config() {
        ServerConfig config;
        config.accessKey = std::string(64, 'a');
        config.port = 0;
        return config;
    }
    SessionClient& Add(bool host, const std::string& name = "routing-session",
                       std::size_t gameplayCapacity = 128) {
        ClientConfig config;
        config.server.port = server.Port();
        config.accessKey = std::string(64, 'a');
        config.host = host;
        config.sessionName = name;
        config.gameplayQueueCapacity = gameplayCapacity;
        clients.push_back(std::make_unique<SessionClient>(
            config, [this](const std::string& line) { logs.push_back(line); }));
        clients.back()->SetLocal({});
        CHECK(clients.back()->Connect());
        return *clients.back();
    }
    void Step() {
        server.Tick(net::NowMs());
        for (auto& client : clients) client->Tick(net::NowMs());
        server.Tick(net::NowMs());
    }
    template<class Predicate> void Until(Predicate done) {
        const auto deadline = net::NowMs() + 5000;
        while (!done()) {
            Step();
            if (net::NowMs() >= deadline) {
                for (const auto& line : logs) std::cerr << line << '\n';
                CHECK(false);
            }
            std::this_thread::sleep_for(1ms);
        }
    }
    void Active(SessionClient& client) {
        Until([&] { return client.Phase() == ClientPhase::Active; });
    }
};

void ResultRoutesOnlyToActiveSameSessionMembers() {
    Network n;
    auto& host=n.Add(true); n.Active(host);
    auto& requester=n.Add(false); n.Active(requester);
    auto& peer=n.Add(false); n.Active(peer);
    auto& otherHost=n.Add(true,"other-session"); n.Active(otherHost);
    auto& otherMember=n.Add(false,"other-session"); n.Active(otherMember);

    const std::vector<std::uint8_t> body{0x10,0x20,0x30};
    const auto request=requester.SendGameplayIntent(7,body);
    CHECK(request);
    std::optional<GameplayStatus> pending;
    n.Until([&]{if(!pending) pending=requester.PopGameplayStatus(); return pending.has_value();});
    CHECK(pending->correlationEvent==*request && pending->disposition==GameplayDisposition::Pending);
    std::optional<Packet> intent;
    n.Until([&]{if(!intent) intent=host.PopGameplayIntent(); return intent.has_value();});
    CHECK(intent->header.sender==requester.Member().player);
    CHECK((std::get<GameplayIntent>(intent->payload)==GameplayIntent{7,body}));
    CHECK(!peer.PopGameplayIntent());

    const auto hostEvent=host.SendGameplayResult(requester.Member().player,*request,7,
        GameplayDisposition::Accepted,0,{0x99});
    CHECK(hostEvent);
    std::optional<Packet> requesterOutcome, peerOutcome;
    std::optional<GameplayStatus> hostAck;
    n.Until([&]{
        if(!requesterOutcome) requesterOutcome=requester.PopGameplayOutcome();
        if(!peerOutcome) peerOutcome=peer.PopGameplayOutcome();
        if(!hostAck) hostAck=host.PopGameplayStatus();
        return requesterOutcome && peerOutcome && hostAck;
    });
    CHECK(std::get<GameplayResult>(requesterOutcome->payload).disposition==GameplayDisposition::Accepted);
    CHECK(std::get<GameplayResult>(peerOutcome->payload).disposition==GameplayDisposition::Accepted);
    CHECK(hostAck->correlationEvent==*hostEvent && hostAck->committed);
    CHECK(!otherMember.PopGameplayOutcome());
    CHECK(!otherHost.PopGameplayOutcome());

    CHECK(requester.RetryGameplayIntent(*request,7,body));
    for(int i=0;i<20;++i) n.Step();
    CHECK(!requester.PopGameplayOutcome());
    CHECK(requester.Phase()==ClientPhase::Active);
    CHECK(!host.PopGameplayIntent());
    CHECK(!peer.PopGameplayOutcome());
    CHECK(!otherMember.PopGameplayOutcome());
    CHECK(!host.RetryGameplayResult(*hostEvent));
}

void DuplicatePendingRoutesOnce() {
    Network n;
    auto& host=n.Add(true); n.Active(host);
    auto& joiner=n.Add(false); n.Active(joiner);
    const std::vector<std::uint8_t> body{4,5};
    const auto request=joiner.SendGameplayIntent(3,body);
    CHECK(request && joiner.RetryGameplayIntent(*request,3,body));
    unsigned statuses=0;
    n.Until([&]{
        while(auto status=joiner.PopGameplayStatus()) {
            CHECK(status->correlationEvent==*request);
            CHECK(status->disposition==GameplayDisposition::Pending);
            ++statuses;
        }
        return statuses==2;
    });
    std::optional<Packet> first;
    n.Until([&]{if(!first) first=host.PopGameplayIntent(); return first.has_value();});
    CHECK(!host.PopGameplayIntent());
}

void StaleEpochIsRejectedBeforeHostRouting() {
    Network n;
    auto& host=n.Add(true); n.Active(host);
    auto& joiner=n.Add(false); n.Active(joiner);
    CHECK(SessionServerTestAccess::ResetHostEpoch(n.server,host.Member().player));
    const auto request=joiner.SendGameplayIntent(9,{1});
    CHECK(request);
    std::optional<GameplayStatus> status;
    n.Until([&]{if(!status) status=joiner.PopGameplayStatus(); return status.has_value();});
    CHECK(status->correlationEvent==*request);
    CHECK(status->disposition==GameplayDisposition::Rejected);
    CHECK(!host.PopGameplayIntent());
}

void RetiredPlayerIdCannotSubmitAfterReconnect() {
    Network n;
    auto& host=n.Add(true); n.Active(host);
    auto& joiner=n.Add(false); n.Active(joiner);
    const auto retired=joiner.Member().player;
    joiner.Disconnect();
    n.Until([&]{return !host.Remotes().contains(retired);});
    CHECK(joiner.Connect()); n.Active(joiner);
    CHECK(joiner.Member().player!=retired);
    CHECK(joiner.Member().session==host.Member().session);
    CHECK(SessionClientTestAccess::QueueIntentAs(joiner,retired,1));
    n.Until([&]{return joiner.Phase()==ClientPhase::Failed;});
    CHECK(!host.PopGameplayIntent());
}

void JoinerCannotSendHostOnlyResult() {
    Network n;
    auto& host=n.Add(true); n.Active(host);
    auto& joiner=n.Add(false); n.Active(joiner);
    CHECK(SessionClientTestAccess::QueueResultAs(joiner,joiner.Member().player,
        host.Member().player,1,1));
    n.Until([&]{return joiner.Phase()==ClientPhase::Failed;});
    CHECK(!host.PopGameplayIntent());
}

void RequestCapacityIsExplicitAndBounded() {
    auto config=Network::Config();
    config.limits.maxMembers=2;
    config.gameplayRequestCapacity=2;
    config.gameplayMemberCapacity=32;
    Network n(config);
    auto& host=n.Add(true); n.Active(host);
    auto& joiner=n.Add(false); n.Active(joiner);
    const auto first=joiner.SendGameplayIntent(1,{1});
    const auto second=joiner.SendGameplayIntent(1,{2});
    CHECK(first && second);
    std::vector<Packet> intents;
    n.Until([&]{
        while(auto packet=host.PopGameplayIntent()) intents.push_back(std::move(*packet));
        return intents.size()==2;
    });
    const auto r1=host.SendGameplayResult(joiner.Member().player,*first,1,
        GameplayDisposition::Unsupported,1,{});
    CHECK(r1);
    std::optional<Packet> outcome;
    n.Until([&]{if(!outcome) outcome=joiner.PopGameplayOutcome(); return outcome.has_value();});
    const auto r2=host.SendGameplayResult(joiner.Member().player,*second,1,
        GameplayDisposition::Rejected,2,{});
    CHECK(r2);
    outcome.reset();
    n.Until([&]{if(!outcome) outcome=joiner.PopGameplayOutcome(); return outcome.has_value();});

    const auto full=joiner.SendGameplayIntent(1,{3});
    CHECK(full);
    std::optional<GameplayStatus> status;
    n.Until([&]{
        while(auto next=joiner.PopGameplayStatus())
            if(next->correlationEvent==*full) {status=*next; break;}
        return status.has_value();
    });
    CHECK(status->disposition==GameplayDisposition::Full && status->committed);
    CHECK(!host.PopGameplayIntent());
}

void DrainedGameplayResultsUseMonotonicDedup() {
    Network n;
    auto& host=n.Add(true);
    n.Active(host);
    auto& joiner=n.Add(false,"routing-session",2);
    n.Active(joiner);
    std::optional<Packet> oldest,latest;
    for(std::uint64_t i=0;i<6;++i) {
        const auto request=joiner.SendGameplayIntent(11,{static_cast<std::uint8_t>(i)});
        CHECK(request);
        std::optional<Packet> intent;
        n.Until([&]{if(!intent) intent=host.PopGameplayIntent(); return intent.has_value();});
        CHECK(std::get<GameplayIntent>(intent->payload).body==std::vector<std::uint8_t>{static_cast<std::uint8_t>(i)});
        const auto result=host.SendGameplayResult(joiner.Member().player,*request,11,
            GameplayDisposition::Accepted,0,{static_cast<std::uint8_t>(i)});
        CHECK(result);
        std::optional<Packet> outcome;
        std::optional<GameplayStatus> hostAck;
        n.Until([&]{
            if(!outcome) outcome=joiner.PopGameplayOutcome();
            while(joiner.PopGameplayStatus()) {}
            if(!hostAck) hostAck=host.PopGameplayStatus();
            return outcome && hostAck;
        });
        CHECK(std::get<GameplayResult>(outcome->payload).requestEvent==*request);
        CHECK(joiner.Phase()==ClientPhase::Active);
        if(i==0) oldest=*outcome;
        latest=*outcome;
    }
    CHECK(oldest && latest);
    CHECK(joiner.Phase()==ClientPhase::Active);
    SessionClientTestAccess::DeliverDuplicateResult(joiner,*oldest);
    CHECK(joiner.Phase()==ClientPhase::Active);
    CHECK(!joiner.PopGameplayOutcome());
}

void PendingRequestCanFinalizeAfterRequesterDisconnects() {
    Network n;
    auto& host=n.Add(true); n.Active(host);
    auto& requester=n.Add(false); n.Active(requester);
    auto& remaining=n.Add(false); n.Active(remaining);
    const auto retired=requester.Member().player;
    const auto request=requester.SendGameplayIntent(12,{0x31});
    CHECK(request);
    std::optional<Packet> intent;
    n.Until([&]{if(!intent) intent=host.PopGameplayIntent(); return intent.has_value();});
    CHECK(intent->header.sender==retired);
    requester.Disconnect();
    n.Until([&]{return !host.Remotes().contains(retired) && !remaining.Remotes().contains(retired);});
    const auto hostEvent=host.SendGameplayResult(retired,*request,12,
        GameplayDisposition::Accepted,0,{0x55});
    CHECK(hostEvent);
    std::optional<Packet> outcome;
    std::optional<GameplayStatus> hostAck;
    n.Until([&]{
        if(!outcome) outcome=remaining.PopGameplayOutcome();
        if(!hostAck) hostAck=host.PopGameplayStatus();
        return outcome && hostAck;
    });
    const auto& result=std::get<GameplayResult>(outcome->payload);
    CHECK(result.requester==retired && result.requestEvent==*request);
    CHECK(hostAck->correlationEvent==*hostEvent && hostAck->committed);
    CHECK(!requester.PopGameplayOutcome());
    CHECK(requester.Connect()); n.Active(requester);
    CHECK(requester.Member().player!=retired);
    CHECK(SessionClientTestAccess::QueueIntentAs(requester,retired,1));
    n.Until([&]{return requester.Phase()==ClientPhase::Failed;});
    CHECK(!host.PopGameplayIntent());
}
void HostIntentInboxOverflowReturnsFull() {
    Network n;
    auto& host=n.Add(true,"routing-session",1); n.Active(host);
    auto& joiner=n.Add(false); n.Active(joiner);
    const auto first=joiner.SendGameplayIntent(4,{1});
    const auto second=joiner.SendGameplayIntent(4,{2});
    CHECK(first && second);
    std::optional<Packet> delivered;
    n.Until([&]{if(!delivered) delivered=host.PopGameplayIntent(); return delivered.has_value();});
    CHECK(std::get<GameplayIntent>(delivered->payload).body==std::vector<std::uint8_t>{1});
    std::optional<Packet> full;
    n.Until([&]{
        while(auto outcome=joiner.PopGameplayOutcome()) {
            const auto& result=std::get<GameplayResult>(outcome->payload);
            if(result.requestEvent==*second) {full=std::move(*outcome); break;}
        }
        return full.has_value();
    });
    CHECK(std::get<GameplayResult>(full->payload).disposition==GameplayDisposition::Full);
    CHECK(!host.PopGameplayIntent());
}

int main() {
    return Run([]{
        ResultRoutesOnlyToActiveSameSessionMembers();
        DuplicatePendingRoutesOnce();
        StaleEpochIsRejectedBeforeHostRouting();
        RetiredPlayerIdCannotSubmitAfterReconnect();
        JoinerCannotSendHostOnlyResult();
        RequestCapacityIsExplicitAndBounded();
        DrainedGameplayResultsUseMonotonicDedup();
        PendingRequestCanFinalizeAfterRequesterDisconnects();
        HostIntentInboxOverflowReturnsFull();
    });
}
