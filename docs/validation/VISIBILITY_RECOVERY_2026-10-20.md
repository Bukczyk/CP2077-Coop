# Recover a rejected cosmetic weapon update

The private action adapter latched its visibility attempt using desired
visibility, action revision and freshness. After one rejected/throwing engine
call, identical valid state could never retry. Periodic repairs change packet
sequence, but not necessarily action revision. The player therefore had to
change state before the same cosmetic update could recover.

Action layer `20261020-realtime-actions-3` retries a pending visibility update
after 250 ms, then backs off through 500 ms, 1 second and 2 seconds. Persistent
failure is bounded to one attempt per 2 seconds. The existing real presentation
clock drives deadlines, independently of world dilation. Missing time does not
admit repeated attempts; a clock rewind rebases the deadline. A different desired
state immediately replaces the pending attempt. Stale state cannot resurrect a
previously requested weapon. Successful application stops all retry work.

Exact actor identity, attachment, canonical Igla visual checks and native
component guards are unchanged. This does not equip weapons, alter inventory,
modify authority or change either network protocol. Failed calls remain failures;
a successful method return is still only a visibility submission.

## Validation

The focused regression fails the retained original at same-state recovery and
passes the candidate. It covers transient rejection, thrown calls, persistent
failure backoff, no per-frame spam, recovery without changing revision/sequence,
clock rewind, stale cancellation and fresh recovery. Existing actor identity,
opaque record and no-clock checks also pass. Windows Release experimental77/77
and production-v5 control75/75 pass sequentially.

After both games/server stopped, exactly two action Lua copies changed, with
backups and all13 protected configuration hashes unchanged. Installed module
SHA256: `c4706d72db920c07cce7d26c087aabf094b70cb9d13c8d367d914501238051bb`.
Lower M13, private assets and native DLL/server `9f27bd4` remain unchanged.

The subsequent `connected-visibility-regression01` repeats the complete92-second
synthetic crouch-sides/weapon/repair/reconnect route, recorded for117 seconds in
both real games. It contains2832 HOST and2801 JOINER original frames, passes
coverage/cadence checks, and retains unchanged tool hashes. Maximum replay frame
gaps are164.7 ms and73.8 ms. Fresh callback rates are24.36/24.10 Hz, not engine FPS.

There are409/406 complete matching diagnostic rows, no actor faults and root
readback error <=0.000002 m. Both directions, holstered/Igla crouch states and
distinct reconnect actors are retained. HOST actors10838768/10838908 and JOINER
actors10838666/10838787 are distinct before/after rejoin. Original middle, stop,
weapon/aim, expiry/repair and crouch recovery frames were reviewed in both views;
expected low poses and supported weapon states remain visible in those samples.
Occluded frames are excluded. This is a normal-path renderer regression. Engine
rejection was injected in the focused test, not reproduced naturally in-game.

Controls, graphics, keys/configuration and current saves are preserved. Games
and local server remain open. Raw logs, videos, old Lua modules and owned-game
assets stay private. Stable v0.0.37/latest is unchanged. KyleBuildsAI owns the
adapter, focused test and this evidence; no session/server/protocol file changed.
