#pragma once
#include "coop/server.hpp"
#include "coop/interpolation.hpp"
#include <deque>
#include <unordered_set>
namespace coop {
enum class ClientPhase { Disconnected, Hello, Admission, Synchronizing, Active, Failed };
struct ClientConfig {
    net::Endpoint server{"127.0.0.1",11779};
    std::string accessKey, sessionName="first-test";
    bool host=false, automaticSnapshots=true;
    unsigned playerSnapshotRate=60, vehicleSnapshotRate=60, npcSnapshotRate=20;
    std::size_t maxNpcs=128;
    std::size_t gameplayQueueCapacity=128;
    InterpolationConfig interpolation{};
    std::uint64_t timeoutMs=10000;
};
struct RemotePlayer {
    SnapshotBuffer snapshots;
    std::uint32_t sequence=0;
    std::uint64_t sourceTime=0, receivedTime=0;
    bool initialized=false;
    explicit RemotePlayer(InterpolationConfig config = {}) : snapshots(config) {}
};
struct RemoteNpc {
    NpcSpawn descriptor;
    SnapshotBuffer snapshots;
    RemoteNpc(NpcSpawn value,InterpolationConfig config):descriptor(value),snapshots(config) {}
};
struct ClientStats { std::uint64_t sent=0, received=0, stale=0, rejected=0; };
class SessionClient {
#ifdef COOP_TESTING
    friend struct SessionClientTestAccess;
#endif
public:
    explicit SessionClient(ClientConfig config, LogSink log = {});
    bool Connect();
    void Disconnect();
    void Tick(std::uint64_t now);
    void SetLocal(Transform value) { local_=value; }
    // Engine snapshots have explicit sequence/time. Automatic Tick uses the configured rate.
    bool SendLocalSnapshot(Transform value, std::uint32_t sequence, std::uint64_t sourceTime);
    bool AdoptNpc(std::uint64_t adoption,std::uint64_t record,Transform transform);
    bool DespawnNpc(EntityId entity);
    bool SendNpcSnapshot(EntityId entity,Transform transform,std::uint32_t sequence,std::uint64_t time);
    std::optional<std::uint64_t> SendGameplayIntent(std::uint16_t kind,std::vector<std::uint8_t> body);
    bool RetryGameplayIntent(std::uint64_t requestEvent,std::uint16_t kind,std::vector<std::uint8_t> body);
    std::optional<std::uint64_t> SendGameplayResult(PlayerId requester,std::uint64_t requestEvent,std::uint16_t kind,GameplayDisposition disposition,std::uint16_t reason,std::vector<std::uint8_t> body);
    bool RetryGameplayResult(std::uint64_t hostEvent);
    std::optional<Packet> PopGameplayIntent();
    std::optional<Packet> PopGameplayOutcome();
    std::optional<GameplayStatus> PopGameplayStatus();
    void ForgetDeniedNpc(std::uint64_t adoption);
    bool NpcDeniedByServer(std::uint64_t adoption) const { return npcDenied_.contains(adoption); }
    const std::unordered_map<EntityId,RemoteNpc>& Npcs() const { return npcs_; }
    ClientPhase Phase() const { return phase_; }
    const Membership& Member() const { return member_; }
    PlayerId Host() const { return host_; }
    const std::unordered_map<PlayerId,RemotePlayer>& Remotes() const { return remotes_; }
    const ClientStats& Stats() const { return stats_; }
private:
    void Control(const Packet& packet,std::uint64_t now);
    void State(const net::Datagram& datagram,std::uint64_t now);
    void Fail(const std::string& reason);
    bool Snapshot(PlayerId player,const Packet& packet,const Transform& value,std::uint64_t sourceTime,std::uint64_t now);
    void Log(const std::string& message) const { if(log_) log_(message); }
    ClientConfig config_;
    LogSink log_;
    net::Channel control_;
    net::Socket udp_;
    ConnectionToken token_{};
    ClientPhase phase_=ClientPhase::Disconnected;
    Membership member_{};
    PlayerId host_=0;
    std::unordered_set<PlayerId> members_;
    std::unordered_map<PlayerId,RemotePlayer> remotes_;
    std::optional<Transform> local_;
    std::uint64_t lastReceive_=0, nextHeartbeat_=0;
    double nextSnapshot_=0;
    std::uint32_t sequence_=0, heartbeat_=0;
    bool readySent_=false, npcSnapshotReady_=false;
    std::uint64_t npcEvent_=0;
    std::unordered_map<EntityId,RemoteNpc> npcs_;
    std::unordered_map<std::uint64_t,NpcAdopt> npcRequests_;
    std::unordered_set<EntityId> npcReleasing_;
    std::unordered_set<std::uint64_t> npcDenied_;
    std::uint64_t gameplayEvent_=0;
    std::optional<std::uint64_t> blockedGameplayResult_;
    std::deque<Packet> gameplayIntents_, gameplayOutcomes_;
    std::deque<GameplayStatus> gameplayStatuses_;
    std::uint64_t lastGameplayResultEvent_=0;
    std::unordered_map<std::uint64_t,Packet> outboundGameplayResults_;
    ClientStats stats_;
};
} // namespace coop
