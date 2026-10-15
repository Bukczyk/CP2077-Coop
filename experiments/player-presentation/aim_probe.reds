// Opt-in LOCAL logical upper-body experiment. No aim direction, combat target,
// shooting or proven ADS animation. See docs/validation/PLAYER_AIM_PROBE.md.
public class CP2077AimProbeLease extends IScriptable {
    public let requested: Bool;
    public let observedAim: Bool;
    public let restoreRequested: Bool;
}

@addField(NPCPuppet)
private let CP2077Session_AimProbeOwner: ref<CP2077AimProbeLease>;

@addMethod(NPCPuppet)
public func CP2077Session_AcquireAimProbe(record: TweakDBID) -> ref<CP2077AimProbeLease> {
    if IsDefined(this.CP2077Session_AimProbeOwner) || !this.IsAttached() || this.IsDead()
        || this.CP2077Session_PresentationProbeLocked || this.CP2077Session_PresentationStancePending
        || IsDefined(this.CP2077Session_PresentationCommand)
        || !IsDefined(this.GetAIControllerComponent()) || !IsDefined(this.GetSignalTable())
        || !IsDefined(this.GetStatesComponent()) || !CP2077PlayerPresentation.SupportedWeapon(record)
        || !this.CP2077Session_HeldPresentationMatches(record, true)
        || NotEquals(this.GetUpperBodyStateFromBlackboard(), gamedataNPCUpperBodyState.Normal) {
        return null;
    }
    let lease = new CP2077AimProbeLease();
    this.CP2077Session_AimProbeOwner = lease;
    this.CP2077Session_PresentationProbeLocked = true;
    return lease;
}

@addMethod(NPCPuppet)
public func CP2077Session_ReadAimProbe(lease: ref<CP2077AimProbeLease>) -> Int32 {
    if !IsDefined(lease) || this.CP2077Session_AimProbeOwner != lease
        || !this.IsAttached() || this.IsDead() { return -1; }
    let state = this.GetUpperBodyStateFromBlackboard();
    if Equals(state, gamedataNPCUpperBodyState.Normal) { return 0; }
    if Equals(state, gamedataNPCUpperBodyState.Aim) {
        if lease.requested { lease.observedAim = true; }
        return 1;
    }
    return 2; // Competing state: do not overwrite Equip/Reload/Shoot/etc.
}

@addMethod(NPCPuppet)
public func CP2077Session_RequestAimProbe(lease: ref<CP2077AimProbeLease>, aiming: Bool) -> Bool {
    let state = this.CP2077Session_ReadAimProbe(lease);
    if aiming {
        if state != 0 || lease.requested { return false; }
        lease.requested = true;
        NPCPuppet.ChangeUpperBodyState(this, gamedataNPCUpperBodyState.Aim);
    } else {
        // The stock setter skips an equal current state. Never infer that a
        // Normal readback before the queued Aim drained safely cancels it.
        if state != 1 || !lease.observedAim || lease.restoreRequested { return false; }
        lease.restoreRequested = true;
        NPCPuppet.ChangeUpperBodyState(this, gamedataNPCUpperBodyState.Normal);
    }
    return true; // Signal submitted only, never engine/visual completion.
}

@addMethod(NPCPuppet)
public func CP2077Session_ReleaseAimProbe(lease: ref<CP2077AimProbeLease>) -> Bool {
    if this.CP2077Session_ReadAimProbe(lease) != 0 { return false; }
    if lease.requested && (!lease.observedAim || !lease.restoreRequested) { return false; }
    this.CP2077Session_AimProbeOwner = null;
    this.CP2077Session_PresentationProbeLocked = false;
    return true;
}
