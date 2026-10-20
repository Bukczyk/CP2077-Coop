return {
    -- Development only. JOINER projection AI is not passive yet. Opt in only
    -- for controlled NPC experiments, using the same setting on both clients.
    experimentalNpcReplication = false,
    -- Private diagnostic only: original idle-only static cosmetic players.
    -- Requires the experimental asset archive. No player hit collider or PvP.
    experimentalPassivePlayers = false,
    -- Private no-AI locomotion asset. Requires its separately qualified archive.
    -- XYZ-derived cosmetic pose inference is not replicated player action state.
    experimentalPlayerLocomotion = false,
    -- Private incompatible protocol0x8005, authored weapon/body assets and
    -- local game-derived clips required. Does not work with the v5 VPS.
    experimentalPlayerPresentation = false,
    -- PRIVATE matched directional action/weapon graphs and unique clip cache.
    -- Masked standing supported-weapon/holstered directions and crouch forward/back.
    -- Requires the separate private backward-crouch clip, no sideways-crouch claim.
    experimentalPlayerDirectionalWalk = false,
    -- Optional locomotion experiment; keep the latest main pose path by default.
    experimentalPlayerMovement = false,
    -- Independent per-player map markers; visual qualification still pending.
    experimentalPlayerMarkers = false,
    -- Status panel is shown only while the CET overlay is open.
    showSessionUI = true,
}
