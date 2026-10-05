#include "coop/session.hpp"
#include <algorithm>
#include <limits>
#include <stdexcept>
#include <type_traits>

namespace coop {
namespace {
bool expired(const Member& m, std::uint64_t now, std::uint64_t timeout) {
    return now >= m.lastSeen && now - m.lastSeen >= timeout;
}
EntityId entityOf(const Payload& payload) {
    return std::visit([](const auto& p) -> EntityId {
        if constexpr (requires { p.entity; }) return p.entity;
        else return 0;
    }, payload);
}
bool hostOnly(PacketType t) {
    return t == PacketType::PlayerState || t == PacketType::VehicleState
        || t == PacketType::DamageApplied || t == PacketType::EntitySpawn
        || t == PacketType::EntityDespawn || t == PacketType::WorldState
        || t == PacketType::NpcAdopt || t == PacketType::NpcDespawn || t == PacketType::NpcState;
}
void eraseEntity(Session& s, EntityId id) {
    s.entities.erase(id); s.npcs.erase(id);
    for (auto& [unused, m] : s.members) {
        (void)unused;
        std::erase_if(m.sequences, [id](const auto& entry) { return entry.first.second == id; });
    }
}
} // namespace
SessionRegistry::SessionRegistry(SessionLimits limits) : limits_(limits) {
    if (!limits.maxSessions || !limits.maxMembers || limits.maxEntities < limits.maxMembers || !limits.timeoutMs || !limits.maxNpcs)
        throw std::invalid_argument("Invalid session limits");
}
bool SessionRegistry::ConnectionUsed(ConnectionId connection) const {
    for (const auto& [unused, s] : sessions_) {
        (void)unused;
        for (const auto& [id, m] : s.members) {
            (void)id;
            if (m.connection == connection) return true;
        }
    }
    return false;
}
const Session* SessionRegistry::Find(SessionId id) const {
    const auto it = sessions_.find(id);
    return it == sessions_.end() ? nullptr : &it->second;
}
Admission SessionRegistry::Create(ConnectionId connection, std::uint64_t now) {
    if (!connection) return {{}, SessionError::Invalid};
    if (ConnectionUsed(connection)) return {{}, SessionError::ConnectionInUse};
    if (sessions_.size() >= limits_.maxSessions || nextSession_ == std::numeric_limits<SessionId>::max()
        || nextPlayer_ == std::numeric_limits<PlayerId>::max()) return {{}, SessionError::Capacity};
    Session s;
    s.id = nextSession_++;
    s.host = nextPlayer_++;
    s.members.emplace(s.host, Member{s.host, connection, Role::Host, Phase::Active, now, 0, {}});
    const Membership result{s.id, s.host, s.epoch, Role::Host};
    sessions_.emplace(s.id, std::move(s));
    return {result, SessionError::None};
}
Admission SessionRegistry::Join(SessionId id, ConnectionId connection, std::uint64_t now) {
    if (!connection) return {{}, SessionError::Invalid};
    if (ConnectionUsed(connection)) return {{}, SessionError::ConnectionInUse};
    auto it = sessions_.find(id);
    if (it == sessions_.end()) return {{}, SessionError::MissingSession};
    auto& s = it->second;
    const auto& host = s.members.at(s.host);
    if (now < host.lastSeen) return {{}, SessionError::Clock};
    if (expired(host, now, limits_.timeoutMs)) return {{}, SessionError::Expired};
    if (s.members.size() >= limits_.maxMembers || nextPlayer_ == std::numeric_limits<PlayerId>::max())
        return {{}, SessionError::Capacity};
    const auto player = nextPlayer_++;
    s.members.emplace(player, Member{player, connection, Role::Joiner, Phase::Synchronizing, now, 0, {}});
    return {Membership{id, player, s.epoch, Role::Joiner}, SessionError::None};
}
SessionError SessionRegistry::RegisterPlayer(SessionId id, PlayerId player) {
    auto it = sessions_.find(id);
    if (it == sessions_.end()) return SessionError::MissingSession;
    auto& s = it->second;
    if (!s.members.contains(player)) return SessionError::MissingMember;
    if (s.entities.contains(player) || s.entities.size() >= limits_.maxEntities) return SessionError::Capacity;
    s.entities.emplace(player, Entity{EntityKind::Player,player,{}});
    s.lastEntity = std::max(s.lastEntity,static_cast<EntityId>(player));
    return SessionError::None;
}
SessionError SessionRegistry::MarkSynchronized(SessionId id, PlayerId player, std::uint32_t epoch) {
    auto it = sessions_.find(id);
    if (it == sessions_.end()) return SessionError::MissingSession;
    auto& s = it->second;
    if (s.epoch != epoch) return SessionError::Epoch;
    auto member = s.members.find(player);
    if (member == s.members.end()) return SessionError::MissingMember;
    member->second.phase = Phase::Active;
    return SessionError::None;
}
ReceiveResult SessionRegistry::Receive(ConnectionId connection, const Packet& packet, std::uint64_t now) {
    const auto fail = [](SessionError e) { return ReceiveResult{e, Route::None, {}, {}, {}, false}; };
    if (!Validate(packet)) return fail(SessionError::Invalid);
    if (TypeOf(packet.payload) >= PacketType::Hello && TypeOf(packet.payload) <= PacketType::SessionReady) return fail(SessionError::Invalid); // Admission is transport policy, not gameplay.
    if (TypeOf(packet.payload)==PacketType::NpcSpawn || TypeOf(packet.payload)==PacketType::NpcRemoved ||
        TypeOf(packet.payload)==PacketType::NpcSnapshotEnd || TypeOf(packet.payload)==PacketType::NpcDenied) return fail(SessionError::Invalid);
    auto it = sessions_.find(packet.header.session);
    if (it == sessions_.end()) return fail(SessionError::MissingSession);
    auto& s = it->second;
    if (packet.header.epoch != s.epoch) return fail(SessionError::Epoch);
    auto member = s.members.find(packet.header.sender);
    if (member == s.members.end()) return fail(SessionError::MissingMember);
    auto& m = member->second;
    if (connection == 0 || m.connection != connection) return fail(SessionError::Identity);
    const auto& host = s.members.at(s.host);
    if (now < m.lastSeen || now < host.lastSeen) return fail(SessionError::Clock);
    if (expired(m, now, limits_.timeoutMs) || expired(host, now, limits_.timeoutMs)) return fail(SessionError::Expired);
    const auto type = TypeOf(packet.payload);
    const bool control = type == PacketType::Heartbeat || type == PacketType::Ack || type == PacketType::Leave;
    if (!control && m.phase != Phase::Active) return fail(SessionError::NotReady);
    if (hostOnly(type) && m.role != Role::Host) return fail(SessionError::Authority);
    const bool reliable = IsReliable(type);
    if (reliable) {
        if (packet.header.event <= m.lastEvent) return fail(SessionError::Duplicate);
        if (packet.header.event - m.lastEvent != 1) return fail(SessionError::EventGap);
    }
    const auto id = entityOf(packet.payload);
    auto entity = s.entities.find(id);
    if (id && type != PacketType::EntitySpawn && entity == s.entities.end()) return fail(SessionError::MissingEntity);
    if (type == PacketType::PlayerPose || type == PacketType::VehicleInput) {
        if (entity->second.owner != m.id) return fail(SessionError::Ownership);
    }
    if ((type == PacketType::PlayerPose || type == PacketType::PlayerState) && entity->second.kind != EntityKind::Player)
        return fail(SessionError::Kind);
    if ((type == PacketType::VehicleInput || type == PacketType::VehicleState) && entity->second.kind != EntityKind::Vehicle)
        return fail(SessionError::Kind);
    if (type == PacketType::WorldState && entity->second.kind != EntityKind::World) return fail(SessionError::Kind);
    if (const auto* spawn = std::get_if<EntitySpawn>(&packet.payload)) {
        if (spawn->entity>=kNpcEntityBase) return fail(SessionError::Kind);
        if (spawn->entity <= s.lastEntity) return fail(SessionError::EntityReuse);
        if (s.entities.size() >= limits_.maxEntities) return fail(SessionError::Capacity);
        if (spawn->owner && !s.members.contains(spawn->owner)) return fail(SessionError::Ownership);
        if (spawn->kind == EntityKind::World && spawn->owner != 0) return fail(SessionError::Ownership);
        if (spawn->kind == EntityKind::Player) {
            for (const auto& [unused, e] : s.entities) {
                (void)unused;
                if (e.kind == EntityKind::Player && e.owner == spawn->owner) return fail(SessionError::Ownership);
            }
        }
    }
    EntityId attacker = 0, target = 0;
    if (const auto* hit = std::get_if<HitRequest>(&packet.payload)) { attacker = hit->attacker; target = hit->target; }
    if (const auto* damage = std::get_if<DamageApplied>(&packet.payload)) { attacker = damage->attacker; target = damage->target; }
    if (attacker) {
        const auto a = s.entities.find(attacker);
        if (a == s.entities.end() || !s.entities.contains(target)) return fail(SessionError::MissingEntity);
        if (type == PacketType::HitRequest && (a->second.owner != m.id || a->second.kind != EntityKind::Player))
            return fail(SessionError::Ownership);
    }
    if (type==PacketType::NpcState || type==PacketType::NpcDespawn) {
        if(entity->second.kind!=EntityKind::NPC) return fail(SessionError::Kind);
    }
    if(const auto* state=std::get_if<NpcState>(&packet.payload)) {
        if(state->sampleTimeMs<=s.npcs.at(id).sampleTimeMs) return fail(SessionError::Stale);
    }
    bool npcDenied=false;
    if(const auto* adopt=std::get_if<NpcAdopt>(&packet.payload)) {
        const auto prior=s.npcAdoptions.find(adopt->adoption);
        if(prior!=s.npcAdoptions.end()) {
            const auto npc=s.npcs.find(prior->second);
            if(npc==s.npcs.end()) return fail(SessionError::EntityReuse);
            if(npc->second.record!=adopt->record) return fail(SessionError::Identity);
        } else if(s.npcs.size()>=limits_.maxNpcs || s.entities.size()>=limits_.maxEntities ||
            s.npcAdoptions.size()>=limits_.maxEntities || s.lastNpc==std::numeric_limits<EntityId>::max()) npcDenied=true;
    }
    const auto stream = std::pair{type, id};
    // Ack is not sequenced: a transport may acknowledge the same event repeatedly.
    if (!reliable && type != PacketType::Ack) {
        auto previous = m.sequences.find(stream);
        if (previous != m.sequences.end() && !IsNewer(packet.header.sequence, previous->second)) return fail(SessionError::Stale);
    }
    // All rejection paths above are mutation-free. Only accepted traffic renews liveness.
    m.lastSeen = now;
    if (reliable) m.lastEvent = packet.header.event;
    else if (type != PacketType::Ack) m.sequences[stream] = packet.header.sequence;
    ReceiveResult result;
    if (!control) {
        result.route = hostOnly(type) ? Route::Peers : Route::Host;
        for (const auto& [peerId, peer] : s.members) {
            if (peerId != m.id && peer.phase == Phase::Active && !expired(peer, now, limits_.timeoutMs)
                && (result.route == Route::Peers || peer.role == Role::Host)) result.recipients.push_back(peerId);
        }
    }
    if (const auto* adopt=std::get_if<NpcAdopt>(&packet.payload)) {
        if(npcDenied) { result.npcDenied=true; return result; } // Command consumed; bounded capacity denial is not an event gap.
        auto prior=s.npcAdoptions.find(adopt->adoption);
        EntityId npc=prior==s.npcAdoptions.end()?++s.lastNpc:prior->second;
        if(prior==s.npcAdoptions.end()) {
            s.npcAdoptions.emplace(adopt->adoption,npc);
            s.npcs.emplace(npc,NpcSpawn{npc,adopt->adoption,adopt->record,adopt->transform,0,0});
            s.entities.emplace(npc,Entity{EntityKind::NPC,s.host,adopt->transform});
        }
        result.adopted=s.npcs.at(npc);
    } else if (type==PacketType::NpcDespawn) { eraseEntity(s,id);
    } else if (const auto* state=std::get_if<NpcState>(&packet.payload)) {
        auto& npc=s.npcs.at(id); npc.transform=state->transform; npc.sequence=packet.header.sequence; npc.sampleTimeMs=state->sampleTimeMs;
        entity->second.transform=state->transform;
    } else if (const auto* spawn = std::get_if<EntitySpawn>(&packet.payload)) {
        s.entities.emplace(id, Entity{spawn->kind, spawn->owner, spawn->transform});
        s.lastEntity = id;
    } else if (type == PacketType::EntityDespawn) {
        eraseEntity(s, id);
    } else if (type == PacketType::PlayerState || type == PacketType::VehicleState || type == PacketType::WorldState) {
        std::visit([&](const auto& p) {
            if constexpr (requires { p.transform; }) entity->second.transform = p.transform;
        }, packet.payload);
    } else if (type == PacketType::Leave) {
        result.removal = Disconnect(connection);
    }
    return result;
}
std::optional<Removal> SessionRegistry::Disconnect(ConnectionId connection) {
    for (auto it = sessions_.begin(); it != sessions_.end(); ++it) {
        auto& s = it->second;
        for (auto member = s.members.begin(); member != s.members.end(); ++member) {
            if (member->second.connection != connection) continue;
            Removal result{s.id, member->first, member->second.role == Role::Host, {}, {}};
            for (const auto& [id, unused] : s.members) {
                (void)unused;
                if (id != member->first) result.notify.push_back(id);
            }
            for (const auto& [id, e] : s.entities)
                if (result.closed || e.owner == member->first) result.entities.push_back(id);
            if (result.closed) sessions_.erase(it);
            else {
                s.members.erase(member);
                for (auto id : result.entities) eraseEntity(s, id);
            }
            return result;
        }
    }
    return std::nullopt;
}
std::vector<Removal> SessionRegistry::Expire(std::uint64_t now) {
    std::vector<ConnectionId> expiredConnections;
    for (const auto& [unused, s] : sessions_) {
        (void)unused;
        if (expired(s.members.at(s.host), now, limits_.timeoutMs)) expiredConnections.push_back(s.members.at(s.host).connection);
        else for (const auto& [id, m] : s.members) {
            (void)id;
            if (expired(m, now, limits_.timeoutMs)) expiredConnections.push_back(m.connection);
        }
    }
    std::vector<Removal> result;
    for (auto connection : expiredConnections)
        if (auto removed = Disconnect(connection)) result.push_back(std::move(*removed));
    return result;
}
SessionError SessionRegistry::ResetWorld(ConnectionId connection) {
    for (auto& [unused, s] : sessions_) {
        (void)unused;
        for (const auto& [id, m] : s.members) {
            (void)id;
            if (m.connection != connection) continue;
            if (m.role != Role::Host) return SessionError::Authority;
            if (s.epoch == std::numeric_limits<std::uint32_t>::max()) return SessionError::Capacity;
            ++s.epoch;
            s.entities.clear(); s.lastEntity = 0; s.npcs.clear(); s.npcAdoptions.clear(); s.lastNpc=kNpcEntityBase-1;
            for (auto& [peerId, peer] : s.members) {
                (void)peerId;
                peer.sequences.clear(); peer.lastEvent = 0;
                peer.phase = peer.role == Role::Host ? Phase::Active : Phase::Synchronizing;
            }
            return SessionError::None;
        }
    }
    return SessionError::MissingMember;
}
} // namespace coop
