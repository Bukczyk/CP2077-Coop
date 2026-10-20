# Record the first actor frames after encoder warmup

The paired runner previously admitted the synthetic player as soon as both
`first.png` files existed. Those PNGs are written before the first NVENC encode.
The retained trace shows an approximately 1.1-second capture gap immediately
after that image, hiding much of the initial actor appearance. The recording
could pass its duration check while missing those frames.

The runner now requires at least six encoded frames spanning 150 ms, with recent
gaps <=150 ms, increasing frame counts and PTS, and a fresh UTC receipt. A longer
recent window admits faster recorders without requiring duplicated frames. An
exited, stalled, malformed or stale recorder cannot admit a participant.

After recording, it checks actual encoded-frame timestamps across the complete
replay. Any gap over250 ms or missing head/tail fails the run. A pre-replay
encoder initialization gap is outside that claim. This is a recording-quality
gate, not proof that every animation transition is visually correct.

Runner, recorder and replay executable hashes are captured before the run and
verified afterward. A changed or missing tool downgrades completion to diagnostic
evidence, preserving the original hash rather than recording only a later file.
Tests exercise the actual CLI completion path with temporary files.

## Validation

Windows experimental77/77 and production-v5 control75/75 pass sequentially.
Focused tests also cover60 Hz, startup stalls, stale/future timestamps, partial
live rows, invalid numeric data, duplicate PTS, first-actor blind intervals,
failed recorder admission and changed/missing tools.

`connected-warmup02` records the complete92-second crouch/repair/rejoin sequence
in both real games, with117-second videos. Both require stable encoded frames
before admission, pass actual head/tail coverage and retain unchanged tool hashes.
Maximum replay frame gaps: HOST73.8 ms, JOINER227.6 ms. This does not qualify
events shorter than those gaps. The installed f15c089 game runtime is unchanged.

Original first-appearance and reconnect frames were inspected in both views.
Visible models use crouch/aim poses without a sustained T-pose in those samples.
A brief standing-to-crouch initialization remains visible in some samples and
needs its own source-state investigation. `SessionClient::SetLocalPresentation`
currently requires Active, so the synthetic replay cannot preseed stance before
admission. Do not silently change that networking contract or assume the same
initialization behavior is proven for actual game clients.

The subsequent [actual crouched reconnect](ACTUAL_CROUCHED_RECONNECT_2026-10-20.md)
shows a real JOINER replacement already crouched in the reviewed first visible
frames. Keep the synthetic and actual-client results separate.

Earlier `connected-warmup01` is retained as diagnostic evidence; runner edits
near its completion leave load-time source provenance unconfirmed. It is
superseded by02. Older duration-qualified recordings still support their reviewed
later poses; they do not establish uninterrupted first-spawn coverage.

Raw video/frame logs/PTS remain private under `20261020-crouch-mask`. Controls,
graphics, saves, native DLL/server, protocol and stable packages are unchanged.
