# Imported game runtime (legacy baseline)

Imported read-only from the installed CP2077Coop mod on 2026-10-04. Source and destination SHA-256 matched before/after copying; import-manifest.json records exact relative game paths. No game file was written. Logs, databases, other mods and user configuration are excluded.

- cet/CP2077Coop/init.lua: installed v0.0.26 vehicle-sync script, currently IS_HOST=true.
- redscript/CP2077Coop: remote.reds, combat.reds and natives.reds.
- tweaks/CP2077Coop/vehicle_proxy.yaml: unchanged content from installed vehicle_proxy_v7.yaml. The installed root tweaks/vehicle_proxy_v7.yaml is an identical duplicate; only one copy is tracked. Neither installed copy was removed.

These files freeze the existing sentinel-based bridge for migration, not a new protocol implementation. Do not extend its markers. The plugin remains v0.0.25; script/plugin version labels are not synchronized. No game loading or REDscript compilation was performed during import.

The repository paths are source layout, not an install command. Future packaging must map CET to bin/x64/plugins/cyber_engine_tweaks/mods, REDscript to r6/scripts and tweaks to r6/tweaks, and avoid installing duplicate TweakXL definitions.
