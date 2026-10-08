#include "check.hpp"
#include "coop/request_ledger.hpp"
#include <cstdint>

using namespace coop;

namespace {
struct Outcome { std::uint32_t code=0; std::uint64_t value=0; bool operator==(const Outcome&) const = default; };
using Ledger = BoundedGameplayRequestLedger<Outcome>;

GameplayRequestKey Key(SessionId session, std::uint32_t epoch, PlayerId sender, std::uint64_t event) {
    return {session, epoch, sender, event};
}

void DuplicatePendingAndCommitted() {
    Ledger ledger({41, 3}, 8);
    CHECK(ledger.AddMember(7) == RequestMemberResult::Added);
    const auto key = Key(41, 3, 7, 1);

    const auto first = ledger.Begin(key);
    CHECK(first.result == RequestLedgerResult::New);
    CHECK(!first.replay);
    CHECK(ledger.Begin(key).result == RequestLedgerResult::DuplicatePending);

    CHECK(ledger.MarkAccepted(key) == RequestLedgerResult::Accepted);
    CHECK(ledger.Commit(key, GameplayRequestStatus::Accepted, Outcome{1, 12})
          == RequestLedgerResult::Committed);
    const auto duplicate = ledger.Begin(key);
    CHECK(duplicate.result == RequestLedgerResult::DuplicateCommitted);
    CHECK(duplicate.replay.has_value());
    CHECK(duplicate.replay->status == GameplayRequestStatus::Accepted);
    CHECK(duplicate.replay->value.code == 1 && duplicate.replay->value.value == 12);

    CHECK(ledger.Commit(key, GameplayRequestStatus::Rejected, Outcome{2, 99})
          == RequestLedgerResult::DuplicateCommitted);
    const auto stillOriginal = ledger.Begin(key);
    CHECK(stillOriginal.replay && stillOriginal.replay->value.code == 1 && stillOriginal.replay->value.value == 12);
}

void RejectStaleIdentityAndMembership() {
    Ledger ledger({41, 3}, 8);
    CHECK(ledger.AddMember(7) == RequestMemberResult::Added);
    CHECK(ledger.Begin(Key(42, 3, 7, 1)).result == RequestLedgerResult::StaleSession);
    CHECK(ledger.Begin(Key(41, 2, 7, 1)).result == RequestLedgerResult::StaleEpoch);
    CHECK(ledger.Begin(Key(41, 3, 8, 1)).result == RequestLedgerResult::NotMember);
    CHECK(ledger.Begin(Key(41, 3, 7, 0)).result == RequestLedgerResult::InvalidKey);
    CHECK(ledger.Begin(Key(41, 3, 0, 1)).result == RequestLedgerResult::InvalidKey);
    CHECK(ledger.AddMember(0) == RequestMemberResult::Invalid);
}

void ReconnectUsesNewPlayerIdentity() {
    Ledger ledger({41, 3}, 8);
    CHECK(ledger.AddMember(7) == RequestMemberResult::Added);
    const auto oldKey = Key(41, 3, 7, 1);
    CHECK(ledger.Begin(oldKey).result == RequestLedgerResult::New);
    CHECK(ledger.MarkAccepted(oldKey) == RequestLedgerResult::Accepted);
    CHECK(ledger.Commit(oldKey, GameplayRequestStatus::Accepted, Outcome{3, 1})
          == RequestLedgerResult::Committed);

    CHECK(ledger.RemoveMember(7));
    CHECK(ledger.AddMember(7) == RequestMemberResult::Retired);
    CHECK(ledger.AddMember(9) == RequestMemberResult::Added);
    const auto duplicate = ledger.Begin(oldKey);
    CHECK(duplicate.result == RequestLedgerResult::DuplicateCommitted);
    CHECK(duplicate.replay && duplicate.replay->value.value == 1);
    CHECK(ledger.Begin(Key(41, 3, 7, 2)).result == RequestLedgerResult::NotMember);
    CHECK(ledger.Begin(Key(41, 3, 9, 1)).result == RequestLedgerResult::New);
}

void CancelPendingAllowsSafeRetry() {
    Ledger ledger({41, 3}, 2);
    CHECK(ledger.AddMember(7) == RequestMemberResult::Added);
    const auto key = Key(41, 3, 7, 1);
    CHECK(ledger.Begin(key).result == RequestLedgerResult::New);
    CHECK(ledger.CancelPending(key) == RequestLedgerResult::Cancelled);
    CHECK(ledger.Size() == 0);
    CHECK(ledger.Begin(key).result == RequestLedgerResult::New);
}
void TerminalReplayWindowPrunesSafely() {
    constexpr std::size_t capacity = 3;
    Ledger ledger({41, 3}, capacity);
    CHECK(ledger.AddMember(7) == RequestMemberResult::Added);

    GameplayRequestKey oldest{};
    GameplayRequestKey newest{};
    for (std::uint64_t event = 1; event <= capacity * 3; ++event) {
        const auto key = Key(41, 3, 7, event);
        if (event == 1) oldest = key;
        newest = key;
        CHECK(ledger.Begin(key).result == RequestLedgerResult::New);
        CHECK(ledger.MarkAccepted(key) == RequestLedgerResult::Accepted);
        const Outcome outcome{static_cast<std::uint32_t>(event), event * 17};
        CHECK(ledger.Commit(key, GameplayRequestStatus::Accepted, outcome)
              == RequestLedgerResult::Committed);
        const auto duplicate = ledger.Begin(key);
        CHECK(duplicate.result == RequestLedgerResult::DuplicateCommitted);
        CHECK(duplicate.replay);
        CHECK(duplicate.replay->status == GameplayRequestStatus::Accepted);
        CHECK(duplicate.replay->value == outcome);
        CHECK(ledger.Size() <= capacity);
    }

    const auto oldDuplicate = ledger.Begin(oldest);
    CHECK(oldDuplicate.result == RequestLedgerResult::StaleRequest);
    CHECK(!oldDuplicate.replay);
    const auto recentDuplicate = ledger.Begin(newest);
    CHECK(recentDuplicate.result == RequestLedgerResult::DuplicateCommitted);
    CHECK(recentDuplicate.replay);
    CHECK(recentDuplicate.replay->value == (Outcome{9, 9 * 17}));
}

void PendingEntriesAreNeverEvicted() {
    Ledger ledger({41, 3}, 1, 2);
    CHECK(ledger.AddMember(7) == RequestMemberResult::Added);
    CHECK(ledger.AddMember(9) == RequestMemberResult::Added);
    CHECK(ledger.AddMember(11) == RequestMemberResult::Capacity);
    const auto pending = Key(41, 3, 7, 1);
    const auto blocked = Key(41, 3, 9, 1);

    CHECK(ledger.Begin(pending).result == RequestLedgerResult::New);
    CHECK(ledger.MarkAccepted(pending) == RequestLedgerResult::Accepted);
    CHECK(ledger.Begin(blocked).result == RequestLedgerResult::Capacity);
    CHECK(ledger.Size() == 1);
    CHECK(ledger.Begin(pending).result == RequestLedgerResult::DuplicatePending);
    CHECK(ledger.Commit(pending, GameplayRequestStatus::Rejected, Outcome{4, 0})
          == RequestLedgerResult::Committed);
    CHECK(ledger.Begin(blocked).result == RequestLedgerResult::New);
    CHECK(ledger.Size() == 1);
}
void EpochResetClearsScopedState() {
    Ledger ledger({41, 3}, 4);
    CHECK(ledger.AddMember(7) == RequestMemberResult::Added);
    const auto oldKey = Key(41, 3, 7, 1);
    CHECK(ledger.Begin(oldKey).result == RequestLedgerResult::New);
    CHECK(ledger.MarkAccepted(oldKey) == RequestLedgerResult::Accepted);
    CHECK(ledger.Commit(oldKey, GameplayRequestStatus::Accepted, Outcome{5, 0})
          == RequestLedgerResult::Committed);

    CHECK(!ledger.Reset({41, 3}));
    CHECK(!ledger.Reset({41, 2}));
    CHECK(ledger.Reset({41, 4}));
    CHECK(ledger.Size() == 0);
    CHECK(ledger.Begin(oldKey).result == RequestLedgerResult::StaleEpoch);
    CHECK(ledger.AddMember(7) == RequestMemberResult::Added);
    const auto newKey = Key(41, 4, 7, 1);
    CHECK(ledger.Begin(newKey).result == RequestLedgerResult::New);
    CHECK(ledger.Commit(newKey, GameplayRequestStatus::Unsupported, Outcome{6, 0})
          == RequestLedgerResult::Committed);
    const auto replay = ledger.Begin(newKey);
    CHECK(replay.result == RequestLedgerResult::DuplicateCommitted);
    CHECK(replay.replay && replay.replay->status == GameplayRequestStatus::Unsupported);
}
}

int main() {
    return Run([] {
        DuplicatePendingAndCommitted();
        RejectStaleIdentityAndMembership();
        ReconnectUsesNewPlayerIdentity();
        TerminalReplayWindowPrunesSafely();
        PendingEntriesAreNeverEvicted();
        CancelPendingAllowsSafeRetry();
        EpochResetClearsScopedState();
    });
}
