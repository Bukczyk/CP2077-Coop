return {
    -- Development only. JOINER projection AI is not passive yet. Opt in only
    -- for controlled NPC experiments, using the same setting on both clients.
    experimentalNpcReplication = false,
    -- Private diagnostic only: original idle-only static cosmetic players.
    -- Requires the experimental asset archive. No player hit collider or PvP.
    experimentalPassivePlayers = false,
    -- Optional locomotion experiment; keep the latest main pose path by default.
    experimentalPlayerMovement = false,
    -- Independent per-player map markers; visual qualification still pending.
    experimentalPlayerMarkers = false,
    -- Status panel is shown only while the CET overlay is open.
    showSessionUI = true,
}
