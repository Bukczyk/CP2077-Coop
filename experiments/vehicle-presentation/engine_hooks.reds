// EXPERIMENT ONLY. Excluded from runtime/session and all default packages.
// A request is not a completed mount, animation, camera transition or deletion.
public class CP2077VehicleSeatEvent {
    public let serial: Uint32;
    public let child: EntityID;
    public let slot: String;
    public let mounting: Bool;
}

@addMethod(PlayerPuppet)
public func CP2077VehicleProbe_DefaultAppearance() -> String {
    let record = TweakDBInterface.GetVehicleRecord(t"Vehicle.v_standard2_archer_hella_player");
    if !IsDefined(record) { return ""; }
    return NameToString(record.AppearanceName());
}

public class CP2077VehicleMountObservation {
    public let child: EntityID;
    public let parent: EntityID;
    public let slot: String;
}

@addMethod(VehicleObject)
public func CP2077VehicleProbe_Appearance() -> String {
    return NameToString(this.GetCurrentAppearanceName());
}
@addMethod(VehicleObject)
public func CP2077VehicleProbe_ColorVariant() -> String {
    return NameToString(this.GetCurrentColorVariantName());
}

@addMethod(PlayerPuppet)
public func CP2077VehicleProbe_MountInfo() -> MountingInfo {
    let parent: EntityID;
    let slot: MountingSlotId;
    return GameInstance.GetMountingFacility(this.GetGame()).GetMountingInfoSingleWithIds(this.GetEntityID(), parent, slot);
}

@addMethod(PlayerPuppet)
public func CP2077VehicleProbe_OnFoot() -> Bool {
    let board = this.GetPlayerStateMachineBlackboard();
    if !this.IsAttached() || !IsDefined(board) { return false; }
    return !IMountingFacility.InfoHasParent(this.CP2077VehicleProbe_MountInfo())
        && board.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Vehicle) == EnumInt(gamePSMVehicle.Default);
}

@addMethod(PlayerPuppet)
public func CP2077VehicleProbe_MountSlot() -> String {
    return NameToString(this.CP2077VehicleProbe_MountInfo().slotId.id);
}

@addField(VehicleObject)
private let CP2077VehicleProbe_owned: Bool;
@addField(VehicleObject)
private let CP2077VehicleProbe_player: EntityID;
@addField(VehicleObject)
private let CP2077VehicleProbe_serial: Uint32;
@addField(VehicleObject)
private let CP2077VehicleProbe_overflow: Bool;
@addField(VehicleObject)
private let CP2077VehicleProbe_events: array<ref<CP2077VehicleSeatEvent>>;

@addMethod(VehicleObject)
public func CP2077VehicleProbe_Owned(player: ref<PlayerPuppet>) -> Bool {
    let dynamic = GameInstance.GetDynamicEntitySystem();
    if !IsDefined(player) || !player.IsAttached() || !this.IsAttached()
        || !IsDefined(dynamic) || !dynamic.IsReady() || !dynamic.IsManaged(this.GetEntityID())
        || !dynamic.IsSpawned(this.GetEntityID()) || dynamic.IsSpawning(this.GetEntityID())
        || !dynamic.IsTagged(this.GetEntityID(), n"CP2077VehicleSeatFixture")
        || this.GetRecordID() != t"Vehicle.v_standard2_archer_hella_player" { return false; }
    if this.CP2077VehicleProbe_owned && this.CP2077VehicleProbe_player != player.GetEntityID() { return false; }
    this.CP2077VehicleProbe_owned = true;
    this.CP2077VehicleProbe_player = player.GetEntityID();
    return true;
}

@addMethod(VehicleObject)
public func CP2077VehicleProbe_Mounts() -> array<MountingInfo> {
    let child: EntityID;
    let slot: MountingSlotId;
    return GameInstance.GetMountingFacility(this.GetGame()).GetMountingInfoMultipleWithIds(child, this.GetEntityID(), slot);
}

@addMethod(VehicleObject)
public func CP2077VehicleProbe_ReadSeats() -> array<ref<CP2077VehicleMountObservation>> {
    let result: array<ref<CP2077VehicleMountObservation>>;
    let item: ref<CP2077VehicleMountObservation>;
    for mount in this.CP2077VehicleProbe_Mounts() {
        item = new CP2077VehicleMountObservation();
        item.parent = mount.parentId;
        item.child = mount.childId;
        item.slot = NameToString(mount.slotId.id);
        ArrayPush(result, item);
    }
    return result;
}

@addMethod(VehicleObject)
public func CP2077VehicleProbe_HasSeat(slot: CName) -> Bool {
    if NotEquals(slot, n"seat_front_left") && NotEquals(slot, n"seat_front_right")
        && NotEquals(slot, n"seat_back_left") && NotEquals(slot, n"seat_back_right") { return false; }
    return VehicleComponent.HasSlot(this.GetGame(), this, slot);
}

@addMethod(VehicleObject)
public func CP2077VehicleProbe_CanRetire(player: ref<PlayerPuppet>) -> Bool {
    return this.CP2077VehicleProbe_Owned(player) && player.CP2077VehicleProbe_OnFoot()
        && ArraySize(this.CP2077VehicleProbe_Mounts()) == 0 && Vector4.Length(this.GetLinearVelocity()) < 0.20;
}

@addMethod(VehicleObject)
public func CP2077VehicleProbe_Request(player: ref<PlayerPuppet>, slot: CName, mounting: Bool) -> Bool {
    let current: MountingInfo;
    let info: MountingInfo;
    let data: ref<MountEventData>;
    let mount: ref<MountingRequest>;
    let unmount: ref<UnmountingRequest>;
    if !this.CP2077VehicleProbe_Owned(player) || !this.CP2077VehicleProbe_HasSeat(slot)
        || Vector4.Length(this.GetLinearVelocity()) >= 0.20 { return false; }
    current = player.CP2077VehicleProbe_MountInfo();
    if mounting {
        if !player.CP2077VehicleProbe_OnFoot() || !VehicleComponent.IsSlotAvailable(this.GetGame(), this, slot) { return false; }
    } else {
        if current.parentId != this.GetEntityID() || current.childId != player.GetEntityID()
            || NotEquals(current.slotId.id, slot) { return false; }
    }
    info.parentId = this.GetEntityID();
    info.childId = player.GetEntityID();
    info.slotId.id = slot;
    data = new MountEventData();
    data.slotName = slot;
    data.mountParentEntityId = this.GetEntityID();
    data.isInstant = false;
    // Vanilla VehicleComponent reads mountEventOptions.entityID without a
    // null guard to choose normal entry versus stealing another occupant.
    data.mountEventOptions = new MountEventOptions();
    if mounting {
        mount = new MountingRequest();
        mount.lowLevelMountingInfo = info;
        mount.mountData = data;
        GameInstance.GetMountingFacility(this.GetGame()).Mount(mount);
    } else {
        unmount = new UnmountingRequest();
        unmount.lowLevelMountingInfo = info;
        unmount.mountData = data;
        GameInstance.GetMountingFacility(this.GetGame()).Unmount(unmount);
    }
    return true; // Submitted only. Exact relationship and finished event are separate.
}

@addMethod(VehicleObject)
public func CP2077VehicleProbe_Finished(evt: ref<VehicleFinishedMountingEvent>) -> Void {
    let value: ref<CP2077VehicleSeatEvent>;
    if !this.CP2077VehicleProbe_owned { return; }
    if !IsDefined(evt.character) || ArraySize(this.CP2077VehicleProbe_events) >= 64
        || this.CP2077VehicleProbe_serial >= 100000u {
        this.CP2077VehicleProbe_overflow = true;
        return;
    }
    this.CP2077VehicleProbe_serial += 1u;
    value = new CP2077VehicleSeatEvent();
    value.serial = this.CP2077VehicleProbe_serial;
    value.child = evt.character.GetEntityID();
    value.slot = NameToString(evt.slotID);
    value.mounting = evt.isMounting;
    ArrayPush(this.CP2077VehicleProbe_events, value);
}

@addMethod(VehicleObject)
public func CP2077VehicleProbe_EventOverflow() -> Bool {
    return this.CP2077VehicleProbe_overflow;
}

@addMethod(VehicleObject)
public func CP2077VehicleProbe_ReadEvents() -> array<ref<CP2077VehicleSeatEvent>> {
    return this.CP2077VehicleProbe_events;
}

@addMethod(VehicleObject)
public func CP2077VehicleProbe_AcknowledgeEvents(serial: Uint32) -> Bool {
    if !this.CP2077VehicleProbe_owned || serial > this.CP2077VehicleProbe_serial { return false; }
    while ArraySize(this.CP2077VehicleProbe_events) > 0 && this.CP2077VehicleProbe_events[0].serial <= serial {
        ArrayErase(this.CP2077VehicleProbe_events, 0);
    }
    return true;
}

@wrapMethod(VehicleComponent)
protected cb func OnVehicleFinishedMountingEvent(evt: ref<VehicleFinishedMountingEvent>) -> Bool {
    let result = wrappedMethod(evt);
    let vehicle = this.GetVehicle();
    if IsDefined(vehicle) { vehicle.CP2077VehicleProbe_Finished(evt); }
    return result;
}

@addField(VehicleObject)
private let CP2077VehicleProbe_poseGeneration: Uint32;
@addField(VehicleObject)
private let CP2077VehicleProbe_poseRequest: Uint32;
@addField(VehicleObject)
private let CP2077VehicleProbe_poseOrigin: Vector4;
@addField(VehicleObject)
private let CP2077VehicleProbe_poseOrientation: Quaternion;

@addMethod(VehicleObject)
public func CP2077VehicleProbe_ApplyPose(player: ref<PlayerPuppet>, generation: Uint32,
    request: Uint32, position: Vector4, orientation: Quaternion) -> Bool {
    let currentPosition: Vector4;
    let currentOrientation: Quaternion;
    let dot: Float;
    if generation == 0u || generation > 1000000000u || request == 0u || request > 16u
        || request <= this.CP2077VehicleProbe_poseRequest
        || (this.CP2077VehicleProbe_poseGeneration != 0u && generation != this.CP2077VehicleProbe_poseGeneration)
        || !this.CP2077VehicleProbe_CanRetire(player) { return false; }
    if !(AbsF(position.X) < 100000.0 && AbsF(position.Y) < 100000.0 && AbsF(position.Z) < 100000.0)
        || !(AbsF(Quaternion.MagnitudeSq(orientation) - 1.0) <= 0.001) { return false; }
    if NotEquals(this.CP2077VehicleProbe_Appearance(), player.CP2077VehicleProbe_DefaultAppearance())
        || NotEquals(this.CP2077VehicleProbe_ColorVariant(), "None") { return false; }
    currentPosition = this.GetWorldPosition();
    currentOrientation = Quaternion.Normalized(this.GetWorldOrientation());
    orientation = Quaternion.Normalized(orientation);
    dot = AbsF(Quaternion.Dot(currentOrientation, orientation));
    // Maximum single jump 0.5 m / 10 degrees. Reject no-op requests below
    // the probe's independent readback resolution (0.1 m / 2 degrees).
    if !(Vector4.Distance(currentPosition, position) <= 0.5 && dot >= 0.996194698)
        || (Vector4.Distance(currentPosition, position) < 0.1 && dot > 0.999847695) { return false; }
    if this.CP2077VehicleProbe_poseGeneration == 0u {
        this.CP2077VehicleProbe_poseOrigin = currentPosition;
        this.CP2077VehicleProbe_poseOrientation = currentOrientation;
    }
    if !(Vector4.Distance(this.CP2077VehicleProbe_poseOrigin, position) <= 2.0
        && AbsF(position.Z - this.CP2077VehicleProbe_poseOrigin.Z) <= 0.25
        && AbsF(Quaternion.Dot(this.CP2077VehicleProbe_poseOrientation, orientation)) >= 0.965925826) { return false; }
    this.CP2077VehicleProbe_poseGeneration = generation;
    this.CP2077VehicleProbe_poseRequest = request;
    // Vanilla vehicleTransition uses this exact whole-vehicle API and converts
    // the full quaternion to all three Euler angles. It returns Void.
    GameInstance.GetTeleportationFacility(this.GetGame()).Teleport(this, position, Quaternion.ToEulerAngles(orientation));
    return true; // Submission only; the Lua probe independently observes settling.
}
