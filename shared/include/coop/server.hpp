#pragma once
#include "coop/net.hpp"
#include "coop/session.hpp"
#include <functional>
namespace coop {
using LogSink = std::function<void(const std::string&)>;
struct ServerConfig {
    std::string bind = "127.0.0.1", accessKey;
    std::uint16_t port = 11779;
    SessionLimits limits{};
    std::size_t maxConnections = 512;
    unsigned snapshotRate = 60, distantRate = 15;
    unsigned npcSnapshotRate=20, npcDistantRate=10;
    float nearDistance = 60, interestDistance = 250;
};
struct ServerStats {
    std::uint64_t hellos=0, creates=0, joins=0, acceptedStates=0, stale=0, rejected=0, routed=0, filtered=0;
};
// One owner thread. TCP controls and UDP snapshots share authenticated membership.
class SessionServer {
#ifdef COOP_TESTING
    friend struct SessionServerTestAccess;
#endif
public:
    explicit SessionServer(ServerConfig config, LogSink log = {});
    void Tick(std::uint64_t now);
    std::uint16_t Port() const { return net::LocalPort(listener_); }
    const ServerStats& Stats() const { return stats_; }
private:
    struct Sent { std::uint32_t sequence=0; std::uint64_t time=0; bool initialized=false; };
    struct Peer {
        net::Channel control;
        std::uint64_t connected=0, closing=0, window=0;
        unsigned frames=0;
        bool authorized=false, baselineSent=false;
        std::optional<Membership> member;
        ConnectionToken token{};
        std::optional<net::Endpoint> endpoint;
        std::unordered_map<EntityId,Sent> sent;
        std::deque<Packet> npcOutbox;
        std::unordered_map<EntityId,std::uint64_t> sourceTimes;
    };
    struct Room { std::string name; std::unordered_map<EntityId,Packet> states; };
    void Control(ConnectionId id, Peer& peer, const Packet& packet, std::uint64_t now);
    void State(const net::Datagram& datagram, std::uint64_t now);
    void RejectPeer(Peer& peer, RejectReason reason, std::uint64_t now);
    void NotifyRemoval(const Removal& removal, std::uint64_t now);
    void RouteStates(std::uint64_t now);
    void QueueNpc(Peer& peer,Payload payload);
    void RouteNpcs(std::uint64_t now);
    void Log(const std::string& message) const { if (log_) log_(message); }
    ServerConfig config_;
    LogSink log_;
    SessionRegistry registry_;
    net::Socket listener_, udp_;
    ConnectionId nextConnection_=1;
    std::unordered_map<ConnectionId,Peer> peers_;
    std::unordered_map<SessionId,Room> rooms_;
    std::unordered_map<std::string,SessionId> names_;
    ServerStats stats_;
};
} // namespace coop
