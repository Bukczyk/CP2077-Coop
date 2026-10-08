// Opt-in, local evidence probe. No encounter transport or production authority API.
// Every observer requires both an explicitly enabled flag and an owned test tag.
@addField(NPCPuppet)
private let CPEncounterEnabled: Bool;

@addField(NPCPuppet)
private let CPEncounterSession: Uint64;

@addField(NPCPuppet)
private let CPEncounterEpoch: Uint32;

@addField(NPCPuppet)
private let CPEncounterGeneration: Uint64;

@addField(NPCPuppet)
private let CPEncounterLines: array<String>;

@addField(NPCPuppet)
private let CPEncounterDropped: Uint32;

@addField(NPCPuppet)
private let CPEncounterSequence: Uint32;

@addField(NPCPuppet)
private let CPEncounterLastRequest: Uint32;

@addField(NPCPuppet)
private let CPEncounterPending: Bool;

@addField(NPCPuppet)
private let CPEncounterPendingKind: String;

@addField(NPCPuppet)
private let CPEncounterBeforeHealth: Float;

@addMethod(NPCPuppet)
public func CP2077Encounter_Scoped() -> Bool {
    let system = GameInstance.GetDynamicEntitySystem();
    return this.CPEncounterEnabled && this.IsAttached()
        && this.CPEncounterSession == CP2077Session_Session()
        && this.CPEncounterEpoch == CP2077Session_Epoch()
        && this.CPEncounterGeneration == CP2077Session_Generation()
        && IsDefined(system) && system.IsManaged(this.GetEntityID())
        && system.IsTagged(this.GetEntityID(), n"CP2077Coop.ControlledEncounter");
}

@addMethod(NPCPuppet)
public func CP2077Encounter_Enable(enabled: Bool) -> Bool {
    let system = GameInstance.GetDynamicEntitySystem();
    if !enabled {
        this.CPEncounterEnabled = false;
        return true;
    }
    if this.CPEncounterEnabled {
        return this.CP2077Encounter_Scoped();
    }
    if !this.IsAttached() || !IsDefined(system) || !system.IsManaged(this.GetEntityID())
        || !system.IsTagged(this.GetEntityID(), n"CP2077Coop.ControlledEncounter")
        || CP2077Session_Phase() != 4u || CP2077Session_Session() == 0ul {
        return false;
    }
    this.CPEncounterSession = CP2077Session_Session();
    this.CPEncounterEpoch = CP2077Session_Epoch();
    this.CPEncounterGeneration = CP2077Session_Generation();
    this.CPEncounterEnabled = true;
    this.CP2077Encounter_Log("enabled", "");
    return true;
}

@addMethod(NPCPuppet)
public func CP2077Encounter_Health() -> Float {
    return GameInstance.GetStatPoolsSystem(this.GetGame()).GetStatPoolValue(
        Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.Health, false);
}

@addMethod(NPCPuppet)
public func CP2077Encounter_Log(kind: String, detail: String) -> Void {
    if !this.CP2077Encounter_Scoped() { return; }
    this.CPEncounterSequence += 1u;
    if ArraySize(this.CPEncounterLines) >= 256 {
        this.CPEncounterDropped += 1u;
        return;
    }
    // Read Codeware's native Uint64 field directly. The script_ref ToHash helper
    // produced unstable diagnostic values in the first live probe.
    let localId: EntityID = this.GetEntityID();
    ArrayPush(this.CPEncounterLines, "encounter seq=" + ToString(this.CPEncounterSequence)
        + " kind=" + kind + " sim=" + ToString(EngineTime.ToDouble(GameInstance.GetSimTime(this.GetGame())))
        + " local=" + ToString(localId.hash)
        + " session=" + ToString(this.CPEncounterSession) + " epoch=" + ToString(this.CPEncounterEpoch)
        + " entity=" + ToString(CP2077Session_Resolve(this.GetEntityID()))
        + " self=" + ToString(CP2077Session_Self()) + " host=" + ToString(CP2077Session_Host())
        + " healthPoints=" + ToString(this.CP2077Encounter_Health())
        + " healthMin=" + ToString(this.IsDead()) + " persistentDead=" + ToString(this.IsDeadNoStatPool())
        + " defeated=" + ToString(ScriptedPuppet.IsDefeated(this))
        + " fixtureRequest=" + ToString(this.CPEncounterLastRequest) + " " + detail);
}

@addMethod(NPCPuppet)
public func CP2077Encounter_Drain() -> array<String> {
    let lines: array<String> = this.CPEncounterLines;
    ArrayClear(this.CPEncounterLines);
    if this.CPEncounterDropped > 0u {
        ArrayPush(lines, "encounter log_overflow dropped=" + ToString(this.CPEncounterDropped));
        this.CPEncounterDropped = 0u;
    }
    return lines;
}

@addMethod(NPCPuppet)
public func CP2077Encounter_Readback() -> String {
    if !this.CP2077Encounter_Scoped() { return "not_scoped"; }
    let health = this.CP2077Encounter_Health();
    if this.CPEncounterPending && NotEquals(this.CPEncounterPendingKind, "gunshot")
        && (health != this.CPEncounterBeforeHealth || this.IsDeadNoStatPool()) {
        this.CPEncounterPending = false;
        this.CP2077Encounter_Log("fixture_observed_change", "attribution=not_proven");
    }
    let god = GameInstance.GetGodModeSystem(this.GetGame());
    let value = "healthPoints=" + ToString(health)
        + " healthMaxPoints=" + ToString(GameInstance.GetStatPoolsSystem(this.GetGame()).GetStatPoolMaxPointValue(
            Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.Health))
        + " persistentDead=" + ToString(this.IsDeadNoStatPool())
        + " healthMin=" + ToString(this.IsDead())
        + " defeated=" + ToString(ScriptedPuppet.IsDefeated(this))
        + " immortal=" + ToString(god.HasGodMode(this.GetEntityID(), gameGodModeType.Immortal))
        + " invulnerable=" + ToString(god.HasGodMode(this.GetEntityID(), gameGodModeType.Invulnerable))
        + " pending=" + ToString(this.CPEncounterPending)
        + " highLevelState=" + ToString(EnumInt(this.GetHighLevelStateFromBlackboard()));
    this.CP2077Encounter_Log("readback", value);
    return value;
}

@addMethod(NPCPuppet)
public func CP2077Encounter_HostReady() -> Bool {
    return this.CP2077Encounter_Scoped() && CP2077Session_Phase() == 4u
        && CP2077Session_Self() != 0u && CP2077Session_Self() == CP2077Session_Host()
        && CP2077Session_Resolve(this.GetEntityID()) != 0ul && !this.IsDeadNoStatPool();
}

// LOCAL fixture only. This deliberately does not claim weapon-pipeline behavior.
@addMethod(NPCPuppet)
public func CP2077Encounter_HostHealthDrain(request: Uint32, points: Float) -> String {
    if !this.CP2077Encounter_HostReady() { return "rejected_scope_or_role"; }
    if request == 0u || request <= this.CPEncounterLastRequest { return "rejected_duplicate_or_old_fixture_request"; }
    if this.CPEncounterPending { return "rejected_fixture_busy"; }
    if !(points > 0.0 && points <= 10000.0) { return "rejected_amount"; }
    this.CPEncounterLastRequest = request;
    this.CPEncounterBeforeHealth = this.CP2077Encounter_Health();
    this.CPEncounterPending = true;
    this.CPEncounterPendingKind = "raw_pool";
    this.CP2077Encounter_Log("raw_pool_fixture_queued", "points=" + ToString(points));
    GameInstance.GetStatPoolsSystem(this.GetGame()).RequestChangingStatPoolValue(
        Cast<StatsObjectID>(this.GetEntityID()), gamedataStatPoolType.Health, -points,
        GetPlayer(this.GetGame()), false, false);
    return "queued_raw_pool_fixture_not_observed";
}

// HOST-local current-weapon pipeline fixture. No physical shot/raycast is claimed.
// No incoming client weapon, damage, source identity or hit geometry is accepted.
@addMethod(NPCPuppet)
public func CP2077Encounter_HostWeaponHit(request: Uint32) -> String {
    if !this.CP2077Encounter_HostReady() { return "rejected_scope_or_role"; }
    if request == 0u || request <= this.CPEncounterLastRequest { return "rejected_duplicate_or_old_fixture_request"; }
    if this.CPEncounterPending { return "rejected_fixture_busy"; }
    if this.IsDead() || ScriptedPuppet.IsDefeated(this) { return "rejected_incapacitated_target"; }
    let player = GetPlayer(this.GetGame());
    let weapon = GameObject.GetActiveWeapon(player);
    if !IsDefined(player) || !IsDefined(weapon) || !weapon.IsRanged() { return "rejected_no_host_ranged_weapon"; }
    let current = weapon.GetCurrentAttack();
    if !IsDefined(current) || !IsDefined(current.GetRecord()) { return "rejected_no_current_attack"; }
    let record = current.GetRecord();
    if !IsDefined(record.AttackType()) || NotEquals(record.AttackType().Type(), gamedataAttackType.Ranged) {
        return "rejected_attack_not_simple_ranged";
    }
    let context: AttackInitContext;
    context.record = record;
    context.instigator = player;
    context.source = player;
    context.weapon = weapon;
    let attack = IAttack.Create(context);
    if !IsDefined(attack) { return "rejected_attack_creation"; }
    let evt = new gameHitEvent();
    evt.target = this;
    evt.attackData = new AttackData();
    evt.attackData.SetAttackDefinition(attack);
    evt.attackData.SetInstigator(player);
    evt.attackData.SetSource(player);
    evt.attackData.SetWeapon(weapon);
    evt.attackData.SetAttackType(record.AttackType().Type());
    evt.attackData.SetAttackPosition(player.GetWorldPosition());
    evt.attackData.SetAttackTime(Cast<Float>(EngineTime.ToDouble(GameInstance.GetSimTime(this.GetGame()))));
    evt.hitPosition = this.GetWorldPosition();
    evt.hitPosition.Z += 1.0;
    evt.hitDirection = Vector4.Normalize(evt.hitPosition - player.GetWorldPosition());
    let shape: HitShapeData;
    shape.result.hitPositionEnter = evt.hitPosition;
    shape.result.hitPositionExit = evt.hitPosition;
    ArrayPush(evt.hitRepresentationResult.hitShapes, shape);
    this.CPEncounterLastRequest = request;
    this.CPEncounterBeforeHealth = this.CP2077Encounter_Health();
    this.CPEncounterPending = true;
    this.CPEncounterPendingKind = "weapon_pipeline";
    this.CP2077Encounter_Log("host_weapon_fixture_queued", "attack=" + TDBID.ToStringDEBUG(record.GetID())
        + " physicalShot=false hitGeometry=synthetic source=host_local_player");
    GameInstance.GetDamageSystem(this.GetGame()).QueueHitEvent(evt, this);
    return "queued_host_weapon_pipeline_fixture_not_observed";
}

// Directed to the one tagged test NPC; never broadcasts over ambient population.
@addMethod(NPCPuppet)
public func CP2077Encounter_HostGunshot(request: Uint32) -> String {
    if !this.CP2077Encounter_HostReady() { return "rejected_scope_or_role"; }
    if request == 0u || request <= this.CPEncounterLastRequest { return "rejected_duplicate_or_old_fixture_request"; }
    if this.CPEncounterPending { return "rejected_fixture_busy"; }
    let player = GetPlayer(this.GetGame());
    if !IsDefined(player) || !IsDefined(player.GetStimBroadcasterComponent()) { return "rejected_no_host_broadcaster"; }
    this.CPEncounterLastRequest = request;
    this.CPEncounterPending = true;
    this.CPEncounterPendingKind = "gunshot";
    this.CP2077Encounter_Log("host_gunshot_fixture_queued", "source=host_local_player received=false reaction=false");
    StimBroadcasterComponent.SendStimDirectly(player, gamedataStimType.Gunshot, this);
    return "queued_direct_gunshot_fixture_not_observed";
}

@addMethod(NPCPuppet)
public func CP2077Encounter_GunshotReceived() -> Void {
    if !this.CP2077Encounter_Scoped() { return; }
    this.CP2077Encounter_Log("gunshot_stimulus_received", "reaction=not_yet_observed attribution=not_proven");
    if this.CPEncounterPending && Equals(this.CPEncounterPendingKind, "gunshot") {
        this.CPEncounterPending = false;
    }
}

// Finish a timed-out fixture without allowing its request ID to be used again.
@addMethod(NPCPuppet)
public func CP2077Encounter_AbandonPending() -> Void {
    if !this.CP2077Encounter_Scoped() { return; }
    this.CP2077Encounter_Log("fixture_abandoned", "outcome=unresolved_do_not_retry");
    this.CPEncounterPending = false;
}

@addMethod(NPCPuppet)
public func CP2077Encounter_RecordHit(kind: String, hit: ref<gameHitEvent>) -> Void {
    if !this.CP2077Encounter_Scoped() || !IsDefined(hit) || !IsDefined(hit.attackData) { return; }
    let computed: Float = -1.0;
    if IsDefined(hit.attackComputed) {
        computed = hit.attackComputed.GetTotalAttackValue(gamedataStatPoolType.Health);
    }
    this.CP2077Encounter_Log(kind, "computedNotObserved=" + ToString(computed)
        + " projectionPipeline=" + ToString(hit.projectionPipeline)
        + " instigatorDefined=" + ToString(IsDefined(hit.attackData.GetInstigator()))
        + " weaponDefined=" + ToString(IsDefined(hit.attackData.GetWeapon()))
        + " attackType=" + ToString(EnumInt(hit.attackData.GetAttackType()))
        + " hitX=" + ToString(hit.hitPosition.X) + " hitY=" + ToString(hit.hitPosition.Y)
        + " hitZ=" + ToString(hit.hitPosition.Z)
        + " hitShapes=" + ToString(ArraySize(hit.hitRepresentationResult.hitShapes)));
}

@wrapMethod(DamageSystem)
private final func PreProcess(hitEvent: ref<gameHitEvent>, cache: ref<CacheData>) -> Bool {
    let npc: ref<NPCPuppet>;
    if IsDefined(hitEvent) { npc = hitEvent.target as NPCPuppet; }
    if IsDefined(npc) { npc.CP2077Encounter_RecordHit("candidate_before_preprocess", hitEvent); }
    let result = wrappedMethod(hitEvent, cache);
    if IsDefined(npc) { npc.CP2077Encounter_RecordHit("after_preprocess", hitEvent); }
    return result;
}

@wrapMethod(DamageSystem)
private final func DealDamages(hitEvent: ref<gameHitEvent>) -> Void {
    wrappedMethod(hitEvent);
    let npc: ref<NPCPuppet>;
    if IsDefined(hitEvent) { npc = hitEvent.target as NPCPuppet; }
    if IsDefined(npc) { npc.CP2077Encounter_RecordHit("after_deal_await_readback", hitEvent); }
}

@wrapMethod(NPCPuppet)
protected cb func OnDeath(evt: ref<gameDeathEvent>) -> Bool {
    let result = wrappedMethod(evt);
    this.CP2077Encounter_Log("death_callback", "await_persistent_flag");
    return result;
}

@wrapMethod(ScriptedPuppet)
protected func OnDied() -> Void {
    wrappedMethod();
    let npc = this as NPCPuppet;
    if IsDefined(npc) { npc.CP2077Encounter_Log("on_died_after_vanilla", ""); }
}

@wrapMethod(ReactionManagerComponent)
protected cb func OnEventReceived(stimEvent: ref<StimuliEvent>) -> Bool {
    let result = wrappedMethod(stimEvent);
    let npc = this.GetOwner() as NPCPuppet;
    if IsDefined(npc) && IsDefined(stimEvent) && Equals(stimEvent.GetStimType(), gamedataStimType.Gunshot) {
        npc.CP2077Encounter_GunshotReceived();
    }
    return result;
}

@addField(PlayerPuppet)
private let CPEncounterGunshotEnabled: Bool;

@addField(PlayerPuppet)
private let CPEncounterGunshotSession: Uint64;

@addField(PlayerPuppet)
private let CPEncounterGunshotGeneration: Uint64;

@addField(PlayerPuppet)
private let CPEncounterGunshotEpoch: Uint32;

@addField(PlayerPuppet)
private let CPEncounterGunshotLines: array<String>;

@addField(PlayerPuppet)
private let CPEncounterGunshotDropped: Uint32;

@addMethod(PlayerPuppet)
public func CP2077Encounter_EnableGunshotCapture(enabled: Bool) -> Bool {
    this.CPEncounterGunshotEnabled = false;
    if !enabled { return true; }
    if this != GetPlayer(this.GetGame()) || CP2077Session_Phase() != 4u { return false; }
    this.CPEncounterGunshotSession = CP2077Session_Session();
    this.CPEncounterGunshotEpoch = CP2077Session_Epoch();
    this.CPEncounterGunshotGeneration = CP2077Session_Generation();
    this.CPEncounterGunshotEnabled = true;
    return true;
}

@addMethod(PlayerPuppet)
public func CP2077Encounter_RecordGunshot(radius: Float, propagationChange: Bool) -> Void {
    if !this.CPEncounterGunshotEnabled || this != GetPlayer(this.GetGame()) || CP2077Session_Phase() != 4u
        || this.CPEncounterGunshotSession != CP2077Session_Session()
        || this.CPEncounterGunshotEpoch != CP2077Session_Epoch()
        || this.CPEncounterGunshotGeneration != CP2077Session_Generation() { return; }
    if ArraySize(this.CPEncounterGunshotLines) >= 128 {
        this.CPEncounterGunshotDropped += 1u;
        return;
    }
    let p = this.GetWorldPosition();
    let localId: EntityID = this.GetEntityID();
    ArrayPush(this.CPEncounterGunshotLines, "gunshot_capture sim="
        + ToString(EngineTime.ToDouble(GameInstance.GetSimTime(this.GetGame())))
        + " session=" + ToString(CP2077Session_Session()) + " epoch=" + ToString(CP2077Session_Epoch())
        + " player=" + ToString(CP2077Session_Self()) + " local=" + ToString(localId.hash)
        + " x=" + ToString(p.X) + " y=" + ToString(p.Y) + " z=" + ToString(p.Z)
        + " radius=" + ToString(radius) + " propagationChange=" + ToString(propagationChange)
        + " semanticShotCount=unverified");
}

@addMethod(PlayerPuppet)
public func CP2077Encounter_DrainGunshots() -> array<String> {
    let lines = this.CPEncounterGunshotLines;
    ArrayClear(this.CPEncounterGunshotLines);
    if this.CPEncounterGunshotDropped > 0u {
        ArrayPush(lines, "gunshot_capture_overflow dropped=" + ToString(this.CPEncounterGunshotDropped));
        this.CPEncounterGunshotDropped = 0u;
    }
    return lines;
}

@wrapMethod(StimBroadcasterComponent)
public final func TriggerSingleBroadcast(contextOwner: wref<GameObject>, gdStimType: gamedataStimType,
    opt radius: Float, opt investigateData: stimInvestigateData, opt propagationChange: Bool) -> Void {
    wrappedMethod(contextOwner, gdStimType, radius, investigateData, propagationChange);
    if Equals(gdStimType, gamedataStimType.Gunshot) && contextOwner == this.GetOwner() {
        let player = contextOwner as PlayerPuppet;
        if IsDefined(player) { player.CP2077Encounter_RecordGunshot(radius, propagationChange); }
    }
}
