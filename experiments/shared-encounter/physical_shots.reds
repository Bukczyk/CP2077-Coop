// Opt-in local weapon evidence. Never sends a network request or applies damage.
// UI ShootEvent is a firing notification, not a verified passive-proxy collision.
@addField(PlayerPuppet)
private let CPPhysicalShotEnabled: Bool;

@addField(PlayerPuppet)
private let CPPhysicalShotSession: Uint64;

@addField(PlayerPuppet)
private let CPPhysicalShotEpoch: Uint32;

@addField(PlayerPuppet)
private let CPPhysicalShotGeneration: Uint64;

@addField(PlayerPuppet)
private let CPPhysicalShotBlackboard: ref<IBlackboard>;

@addField(PlayerPuppet)
private let CPPhysicalShotListener: ref<CallbackHandle>;

@addField(PlayerPuppet)
private let CPPhysicalShotLines: array<String>;

@addField(PlayerPuppet)
private let CPPhysicalShotSequence: Uint32;

@addField(PlayerPuppet)
private let CPPhysicalShotDropped: Uint32;

@addField(PlayerPuppet)
private let CPPhysicalShotRejected: Uint32;

@addField(PlayerPuppet)
private let CPPhysicalShotPreviousWeapon: Uint64;

@addField(PlayerPuppet)
private let CPPhysicalShotPreviousAmmo: Uint32;

@addMethod(PlayerPuppet)
public func CP2077Encounter_PhysicalShotScoped() -> Bool {
    return this.CPPhysicalShotEnabled && this.IsAttached()
        && this == GetPlayer(this.GetGame()) && CP2077Session_Phase() == 4u
        && this.CPPhysicalShotSession != 0ul
        && this.CPPhysicalShotSession == CP2077Session_Session()
        && this.CPPhysicalShotEpoch == CP2077Session_Epoch()
        && this.CPPhysicalShotGeneration == CP2077Session_Generation();
}

@addMethod(PlayerPuppet)
public func CP2077Encounter_EnablePhysicalShotCapture(enabled: Bool) -> Bool {
    // Re-enabling deliberately starts a fresh scope and cannot stack listeners.
    this.CPPhysicalShotEnabled = false;
    this.CP2077Encounter_SetPhysicalTraceTarget(null);
    if IsDefined(this.CPPhysicalShotBlackboard) && IsDefined(this.CPPhysicalShotListener) {
        this.CPPhysicalShotBlackboard.UnregisterListenerVariant(
            GetAllBlackboardDefs().UI_ActiveWeaponData.ShootEvent, this.CPPhysicalShotListener);
    }
    this.CPPhysicalShotListener = null;
    this.CPPhysicalShotBlackboard = null;
    ArrayClear(this.CPPhysicalShotLines);
    this.CPPhysicalShotSequence = 0u;
    this.CPPhysicalShotDropped = 0u;
    this.CPPhysicalShotRejected = 0u;
    this.CPPhysicalShotPreviousWeapon = 0ul;
    this.CPPhysicalShotPreviousAmmo = 0u;
    if !enabled { return true; }
    if !this.IsAttached() || this != GetPlayer(this.GetGame())
        || CP2077Session_Phase() != 4u || CP2077Session_Session() == 0ul
        || CP2077Session_Self() == 0u { return false; }
    let bb = GameInstance.GetBlackboardSystem(this.GetGame()).Get(GetAllBlackboardDefs().UI_ActiveWeaponData);
    if !IsDefined(bb) { return false; }
    this.CPPhysicalShotSession = CP2077Session_Session();
    this.CPPhysicalShotEpoch = CP2077Session_Epoch();
    this.CPPhysicalShotGeneration = CP2077Session_Generation();
    let weapon = GameObject.GetActiveWeapon(this);
    if IsDefined(weapon) {
        let weaponId = weapon.GetEntityID();
        this.CPPhysicalShotPreviousWeapon = weaponId.hash;
        this.CPPhysicalShotPreviousAmmo = WeaponObject.GetMagazineAmmoCount(weapon);
    }
    this.CPPhysicalShotBlackboard = bb;
    // No immediate callback: an old blackboard value is not a fresh shot.
    this.CPPhysicalShotListener = bb.RegisterListenerVariant(
        GetAllBlackboardDefs().UI_ActiveWeaponData.ShootEvent, this,
        n"CP2077Encounter_OnPhysicalShot", false);
    this.CPPhysicalShotEnabled = IsDefined(this.CPPhysicalShotListener);
    return this.CPPhysicalShotEnabled;
}

@addMethod(PlayerPuppet)
private func CP2077Encounter_PhysicalShotFinite(value: Float, bound: Float) -> Bool {
    // These ordered comparisons reject NaN and infinity too. Bounds are probe
    // sanity limits, not a claim that a firing origin is authoritative.
    return value >= -bound && value <= bound;
}

@addMethod(PlayerPuppet)
protected cb func CP2077Encounter_OnPhysicalShot(value: Variant) -> Bool {
    if !this.CP2077Encounter_PhysicalShotScoped() {
        this.CP2077Encounter_EnablePhysicalShotCapture(false);
        return false;
    }
    let actualType = Reflection.GetTypeOf(value);
    let expectedValue: gameuiWeaponShootParams;
    let expectedType = Reflection.GetTypeOf(ToVariant(expectedValue));
    if !IsDefined(actualType) || !IsDefined(expectedType)
        || NotEquals(actualType.GetName(), expectedType.GetName()) {
        this.CPPhysicalShotRejected += 1u;
        return false;
    }
    let data = FromVariant<gameuiWeaponShootParams>(value);
    let p = data.fromWorldPosition;
    let d = data.forward;
    if !this.CP2077Encounter_PhysicalShotFinite(p.X, 1000000.0)
        || !this.CP2077Encounter_PhysicalShotFinite(p.Y, 1000000.0)
        || !this.CP2077Encounter_PhysicalShotFinite(p.Z, 1000000.0)
        || !this.CP2077Encounter_PhysicalShotFinite(d.X, 2.0)
        || !this.CP2077Encounter_PhysicalShotFinite(d.Y, 2.0)
        || !this.CP2077Encounter_PhysicalShotFinite(d.Z, 2.0) {
        this.CPPhysicalShotRejected += 1u;
        return false;
    }
    let directionLengthSquared = d.X * d.X + d.Y * d.Y + d.Z * d.Z;
    if !(directionLengthSquared >= 0.01 && directionLengthSquared <= 4.0) {
        this.CPPhysicalShotRejected += 1u;
        return false;
    }
    // Only validated XYZ enter native point/vector math. The UI variant's W
    // is not used as an unchecked homogeneous coordinate.
    p.W = 1.0;
    d.W = 0.0;
    let weapon = GameObject.GetActiveWeapon(this);
    if !IsDefined(weapon) || !weapon.IsRanged() {
        this.CPPhysicalShotRejected += 1u;
        return false;
    }
    let weaponId = weapon.GetEntityID();
    let playerId = this.GetEntityID();
    let ammo = WeaponObject.GetMagazineAmmoCount(weapon);
    let sameWeapon = weaponId.hash == this.CPPhysicalShotPreviousWeapon;
    this.CPPhysicalShotSequence += 1u;
    if ArraySize(this.CPPhysicalShotLines) < 128 {
        ArrayPush(this.CPPhysicalShotLines, "physical_shot seq=" + ToString(this.CPPhysicalShotSequence)
            + " sim=" + ToString(EngineTime.ToDouble(GameInstance.GetSimTime(this.GetGame())))
            + " session=" + ToString(this.CPPhysicalShotSession)
            + " epoch=" + ToString(this.CPPhysicalShotEpoch)
            + " generation=" + ToString(this.CPPhysicalShotGeneration)
            + " player=" + ToString(CP2077Session_Self()) + " local=" + ToString(playerId.hash)
            + " weapon=" + ToString(weaponId.hash)
            + " originX=" + ToString(p.X) + " originY=" + ToString(p.Y) + " originZ=" + ToString(p.Z)
            + " forwardX=" + ToString(d.X) + " forwardY=" + ToString(d.Y) + " forwardZ=" + ToString(d.Z)
            + " directionLengthSquared=" + ToString(directionLengthSquared)
            + " magazine=" + ToString(ammo) + " capacity=" + ToString(WeaponObject.GetMagazineCapacity(weapon))
            + " totalAmmo=" + ToString(weapon.GetTotalAmmoCount())
            + " previousMagazine=" + ToString(this.CPPhysicalShotPreviousAmmo)
            + " sameWeapon=" + ToString(sameWeapon)
            + " ammoDecreasedSincePreviousObservation=" + ToString(sameWeapon && ammo < this.CPPhysicalShotPreviousAmmo)
            + " geometrySource=ui_shoot_event collision=false bulletTrajectory=unverified");
        // A separately enabled exact passive target adds an observation only.
        // Keep the combined diagnostics bounded to the same 128-line limit.
        if ArraySize(this.CPPhysicalShotLines) < 128 {
            ArrayPush(this.CPPhysicalShotLines, this.CP2077Encounter_TracePhysicalShot(p, d));
        } else {
            this.CPPhysicalShotDropped += 1u;
        }
    } else {
        this.CPPhysicalShotDropped += 1u;
    }
    this.CPPhysicalShotPreviousWeapon = weaponId.hash;
    this.CPPhysicalShotPreviousAmmo = ammo;
    return true;
}

@addMethod(PlayerPuppet)
public func CP2077Encounter_DrainPhysicalShots() -> array<String> {
    if !this.CP2077Encounter_PhysicalShotScoped() {
        this.CP2077Encounter_EnablePhysicalShotCapture(false);
    }
    let result = this.CPPhysicalShotLines;
    ArrayClear(this.CPPhysicalShotLines);
    if this.CPPhysicalShotDropped > 0u || this.CPPhysicalShotRejected > 0u {
        ArrayPush(result, "physical_shot_diagnostic dropped=" + ToString(this.CPPhysicalShotDropped)
            + " rejected=" + ToString(this.CPPhysicalShotRejected));
        this.CPPhysicalShotDropped = 0u;
        this.CPPhysicalShotRejected = 0u;
    }
    return result;
}

@addMethod(PlayerPuppet)
public func CP2077Encounter_PhysicalShotReadback() -> String {
    if this.CPPhysicalShotEnabled && !this.CP2077Encounter_PhysicalShotScoped() {
        this.CP2077Encounter_EnablePhysicalShotCapture(false);
    }
    if !this.IsAttached() || this != GetPlayer(this.GetGame()) { return "not_local_attached_player"; }
    let weapon = GameObject.GetActiveWeapon(this);
    let weaponText = "weaponDefined=false";
    if IsDefined(weapon) {
        let weaponId = weapon.GetEntityID();
        weaponText = "weaponDefined=true weapon=" + ToString(weaponId.hash)
            + " ranged=" + ToString(weapon.IsRanged())
            + " magazine=" + ToString(WeaponObject.GetMagazineAmmoCount(weapon))
            + " capacity=" + ToString(WeaponObject.GetMagazineCapacity(weapon))
            + " totalAmmo=" + ToString(weapon.GetTotalAmmoCount());
    }
    let bb = this.GetPlayerStateMachineBlackboard();
    let stateText = "playerStateBlackboard=false";
    if IsDefined(bb) {
        let highLevel = bb.GetInt(GetAllBlackboardDefs().PlayerStateMachine.HighLevel);
        stateText = "highLevel=" + ToString(highLevel)
            + " weaponState=" + ToString(bb.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Weapon))
            + " safeSceneTier=" + ToString(highLevel > 1 && highLevel <= 5)
            + " sceneAimForced=" + ToString(bb.GetBool(GetAllBlackboardDefs().PlayerStateMachine.SceneAimForced))
            + " combatGadget=" + ToString(bb.GetInt(GetAllBlackboardDefs().PlayerStateMachine.CombatGadget))
            + " takedown=" + ToString(bb.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Takedown));
    }
    return "physical_shot_readback enabled=" + ToString(this.CPPhysicalShotEnabled)
        + " scoped=" + ToString(this.CP2077Encounter_PhysicalShotScoped())
        + " seq=" + ToString(this.CPPhysicalShotSequence)
        + " queued=" + ToString(ArraySize(this.CPPhysicalShotLines))
        + " dropped=" + ToString(this.CPPhysicalShotDropped)
        + " rejected=" + ToString(this.CPPhysicalShotRejected)
        + " " + weaponText + " " + stateText
        + " noCombat=" + ToString(StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"NoCombat"))
        + " fastForward=" + ToString(StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"FastForward"))
        + " vehicleScene=" + ToString(StatusEffectSystem.ObjectHasStatusEffectWithTag(this, n"VehicleScene"))
        + " restrictions=partial_read_only";
}
