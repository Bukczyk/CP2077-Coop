#pragma once
#include "coop/protocol.hpp"
#include <cstddef>
#include <functional>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <type_traits>
#include <unordered_map>
#include <unordered_set>
#include <utility>

namespace coop {

// Request identity is independent of any gameplay payload. The sender is the
// PlayerId authenticated by the session transport, never a payload claim.
struct GameplayRequestKey {
    SessionId session = 0;
    std::uint32_t epoch = 0;
    PlayerId sender = 0;
    std::uint64_t event = 0;
    bool operator==(const GameplayRequestKey&) const = default;
};

struct GameplayRequestKeyHash {
    std::size_t operator()(const GameplayRequestKey& key) const noexcept {
        std::size_t value = std::hash<SessionId>{}(key.session);
        const auto mix = [&value](std::size_t part) {
            value ^= part + std::size_t{0x9e3779b9} + (value << 6) + (value >> 2);
        };
        mix(std::hash<std::uint32_t>{}(key.epoch));
        mix(std::hash<PlayerId>{}(key.sender));
        mix(std::hash<std::uint64_t>{}(key.event));
        return value;
    }
};

struct GameplayRequestScope {
    SessionId session = 0;
    std::uint32_t epoch = 0;
};

enum class GameplayRequestStatus {
    Accepted,
    Rejected,
    Unsupported,
    Full
};

enum class RequestMemberResult {
    Added,
    AlreadyActive,
    Retired,
    Invalid,
    Capacity
};

enum class RequestLedgerResult {
    New,
    DuplicatePending,
    DuplicateCommitted,
    Committed,
    StaleSession,
    StaleEpoch,
    NotMember,
    InvalidKey,
    Capacity,
    MissingRequest,
    Cancelled
};

template<class Outcome>
struct StoredGameplayOutcome {
    GameplayRequestStatus status = GameplayRequestStatus::Rejected;
    Outcome value;
    bool operator==(const StoredGameplayOutcome&) const = default;
};

template<class Outcome>
struct RequestAdmission {
    RequestLedgerResult result = RequestLedgerResult::InvalidKey;
    std::optional<StoredGameplayOutcome<Outcome>> replay;
};

// Bounded, in-memory idempotency ledger for reliable gameplay intents. It has
// no knowledge of packet payloads or game objects. The owner registers only
// authenticated active requestors. Outcomes must be fixed-size value types.
// Entries and membership tombstones are never
// evicted: capacity exhaustion is explicit until an epoch/session reset.
template<class Outcome>
class BoundedGameplayRequestLedger {
    static_assert(std::is_trivially_copyable_v<Outcome>,
                  "Outcome must be a bounded, fixed-size value type");
public:
    // By default, membership/tombstone capacity equals request entry capacity.
    BoundedGameplayRequestLedger(GameplayRequestScope scope, std::size_t capacity)
        : BoundedGameplayRequestLedger(scope, capacity, capacity) {}

    BoundedGameplayRequestLedger(GameplayRequestScope scope, std::size_t capacity,
                                 std::size_t memberCapacity)
        : scope_(scope), capacity_(capacity), memberCapacity_(memberCapacity) {
        if (!scope_.session || !scope_.epoch || !capacity_ || !memberCapacity_)
            throw std::invalid_argument("Invalid gameplay request ledger configuration");
    }

    RequestMemberResult AddMember(PlayerId player) {
        if (!player) return RequestMemberResult::Invalid;
        std::lock_guard lock(mutex_);
        if (members_.contains(player)) return RequestMemberResult::AlreadyActive;
        if (retired_.contains(player)) return RequestMemberResult::Retired;
        if (members_.size() + retired_.size() >= memberCapacity_)
            return RequestMemberResult::Capacity;
        members_.insert(player);
        return RequestMemberResult::Added;
    }

    bool RemoveMember(PlayerId player) {
        std::lock_guard lock(mutex_);
        if (!members_.erase(player)) return false;
        // Preserve request entries and retire the identity for this epoch.
        // A reconnect must be admitted under a fresh PlayerId.
        retired_.insert(player);
        return true;
    }

    RequestAdmission<Outcome> Begin(const GameplayRequestKey& key) {
        std::lock_guard lock(mutex_);
        if (key.session != scope_.session)
            return {RequestLedgerResult::StaleSession, {}};
        if (key.epoch != scope_.epoch)
            return {RequestLedgerResult::StaleEpoch, {}};
        if (!key.sender || !key.event)
            return {RequestLedgerResult::InvalidKey, {}};
        // Existing request keys retain their correlation after the requester
        // retires. Only a new request requires current membership.
        if (const auto it = entries_.find(key); it != entries_.end()) {
            if (it->second.outcome)
                return {RequestLedgerResult::DuplicateCommitted, it->second.outcome};
            return {RequestLedgerResult::DuplicatePending, {}};
        }
        if (!members_.contains(key.sender))
            return {RequestLedgerResult::NotMember, {}};
        if (entries_.size() >= capacity_)
            return {RequestLedgerResult::Capacity, {}};
        entries_.emplace(key, Entry{});
        return {RequestLedgerResult::New, {}};
    }

    // The first terminal outcome wins. Repeated commits never overwrite it.
    RequestLedgerResult Commit(const GameplayRequestKey& key,
                              GameplayRequestStatus status,
                              Outcome value) {
        std::lock_guard lock(mutex_);
        if (key.session != scope_.session) return RequestLedgerResult::StaleSession;
        if (key.epoch != scope_.epoch) return RequestLedgerResult::StaleEpoch;
        const auto it = entries_.find(key);
        if (it == entries_.end()) return RequestLedgerResult::MissingRequest;
        if (it->second.outcome) return RequestLedgerResult::DuplicateCommitted;
        it->second.outcome.emplace(StoredGameplayOutcome<Outcome>{status, std::move(value)});
        return RequestLedgerResult::Committed;
    }

    // Undo only a not-yet-committed reservation when a later policy check
    // rejects the request before it can be routed or executed.
    RequestLedgerResult CancelPending(const GameplayRequestKey& key) {
        std::lock_guard lock(mutex_);
        if (key.session != scope_.session) return RequestLedgerResult::StaleSession;
        if (key.epoch != scope_.epoch) return RequestLedgerResult::StaleEpoch;
        const auto it = entries_.find(key);
        if (it == entries_.end()) return RequestLedgerResult::MissingRequest;
        if (it->second.outcome) return RequestLedgerResult::DuplicateCommitted;
        entries_.erase(it);
        return RequestLedgerResult::Cancelled;
    }
    // Reset is explicit and starts a new identity generation. Within one
    // session the epoch must strictly advance, preventing rollback to old keys.
    bool Reset(GameplayRequestScope next) {
        if (!next.session || !next.epoch) return false;
        std::lock_guard lock(mutex_);
        if (next.session == scope_.session && next.epoch <= scope_.epoch) return false;
        scope_ = next;
        entries_.clear();
        members_.clear();
        retired_.clear();
        return true;
    }

    GameplayRequestScope Scope() const {
        std::lock_guard lock(mutex_);
        return scope_;
    }

    std::size_t Size() const {
        std::lock_guard lock(mutex_);
        return entries_.size();
    }

    std::size_t Capacity() const { return capacity_; }
    std::size_t MemberCapacity() const { return memberCapacity_; }

private:
    struct Entry {
        std::optional<StoredGameplayOutcome<Outcome>> outcome;
    };

    mutable std::mutex mutex_;
    GameplayRequestScope scope_;
    const std::size_t capacity_;
    const std::size_t memberCapacity_;
    std::unordered_set<PlayerId> members_;
    std::unordered_set<PlayerId> retired_;
    std::unordered_map<GameplayRequestKey, Entry, GameplayRequestKeyHash> entries_;
};

} // namespace coop