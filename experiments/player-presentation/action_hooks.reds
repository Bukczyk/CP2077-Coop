// EXPERIMENT ONLY: not packaged or installed. Visual acceptance failed on 2026-10-06.
// Presentation hooks for a LOCAL boundary. The v5 runtime does not call these
// for player action synchronization. No agreed action/appearance route exists.
// Local measurement fixtures may exercise them on an owned player projection.
@addMethod(PlayerPuppet)
public func CP2077Session_ActionCaptureReady() -> Bool {
    return this.IsAttached() && IsDefined(this.GetPlayerStateMachineBlackboard());
}

@addMethod(PlayerPuppet)
public func CP2077Session_IsCrouched() -> Bool {
    let board = this.GetPlayerStateMachineBlackboard();
    return IsDefined(board) && board.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Locomotion)
        == EnumInt(gamePSMLocomotionStates.Crouch);
}

@addMethod(PlayerPuppet)
public func CP2077Session_IsAiming() -> Bool {
    let board = this.GetPlayerStateMachineBlackboard();
    return IsDefined(board) && board.GetInt(GetAllBlackboardDefs().PlayerStateMachine.UpperBody)
        == EnumInt(gamePSMUpperBodyStates.Aim);
}

@addMethod(PlayerPuppet)
public func CP2077Session_HeldWeapon() -> TweakDBID {
    let weapon = GameObject.GetActiveWeapon(this);
    if IsDefined(weapon) { return ItemID.GetTDBID(weapon.GetItemID()); }
    return t"";
}

@addMethod(NPCPuppet)
public func CP2077Session_ApplyStance(crouched: Bool) -> Bool {
    if !this.IsAttached() || this.CP2077Session_PresentationProbeLocked
        || this.CP2077Session_PresentationStancePending { return false; }
    this.CP2077Session_PresentationStancePending = true;
    this.CP2077Session_PresentationCrouched = crouched;
    if crouched { NPCPuppet.ChangeStanceState(this, gamedataNPCStanceState.Crouch); }
    else { NPCPuppet.ChangeStanceState(this, gamedataNPCStanceState.Stand); }
    return true; // State request only, not proof of a visible crouch.
}

@addMethod(NPCPuppet)
public func CP2077Session_StanceMatches(crouched: Bool) -> Bool {
    let actual = this.GetStanceStateFromBlackboard();
    if this.CP2077Session_PresentationStancePending {
        if (this.CP2077Session_PresentationCrouched && Equals(actual, gamedataNPCStanceState.Crouch))
            || (!this.CP2077Session_PresentationCrouched && Equals(actual, gamedataNPCStanceState.Stand)) {
            this.CP2077Session_PresentationStancePending = false;
        }
    }
    if crouched { return Equals(actual, gamedataNPCStanceState.Crouch); }
    return Equals(actual, gamedataNPCStanceState.Stand);
}

@addField(NPCPuppet)
private let CP2077Session_PresentationProbeLocked: Bool;
@addField(NPCPuppet)
private let CP2077Session_PresentationStancePending: Bool;
@addField(NPCPuppet)
private let CP2077Session_PresentationCrouched: Bool;
@addField(NPCPuppet)
private let CP2077Session_PresentationCommand: ref<AICommand>;

public class CP2077PlayerPresentation {
    public static func SupportedWeapon(record: TweakDBID) -> Bool {
        let item = TweakDBInterface.GetItemRecord(record);
        if !IsDefined(item) || !IsDefined(item.ItemType()) { return false; }
        // Deliberate firearm allowlist. Clothing, quest props, consumables,
        // fists, integrated cyberware and unknown future types cannot be given.
        switch item.ItemType().Type() {
            case gamedataItemType.Wea_Handgun:
            case gamedataItemType.Wea_Revolver:
            case gamedataItemType.Wea_AssaultRifle:
            case gamedataItemType.Wea_Rifle:
            case gamedataItemType.Wea_SubmachineGun:
            case gamedataItemType.Wea_LightMachineGun:
            case gamedataItemType.Wea_Shotgun:
            case gamedataItemType.Wea_ShotgunDual:
            case gamedataItemType.Wea_SniperRifle:
            case gamedataItemType.Wea_PrecisionRifle:
                return true;
            default:
                return false;
        }
    }
}

@addMethod(PlayerPuppet)
public func CP2077Session_HasPresentationWeapon() -> Bool {
    return IsDefined(GameObject.GetActiveWeapon(this));
}

@addMethod(NPCPuppet)
public func CP2077Session_HeldPresentationMatches(record: TweakDBID, drawn: Bool) -> Bool {
    let sample = this.CP2077Session_ReadPresentationWeapon(record, drawn);
    return IsDefined(sample) && sample.matches;
}

// Local observation only. No network descriptor or visual ADS verdict.
public class CP2077PresentationWeaponSample extends IScriptable {
    public let ownerID: EntityID;
    public let entityID: EntityID;
    public let record: TweakDBID;
    public let spawning: Bool;
    public let slotEmpty: Bool;
    public let hasItem: Bool;
    public let attached: Bool;
    public let matches: Bool;
    public let appearance: CName;
    public let muzzleAvailable: Bool;
    public let muzzlePosition: Vector4;
    public let muzzleRotation: Quaternion;
}

@addMethod(NPCPuppet)
public func CP2077Session_ReadPresentationWeapon(record: TweakDBID, drawn: Bool) -> ref<CP2077PresentationWeaponSample> {
    let transactions = GameInstance.GetTransactionSystem(this.GetGame());
    if !this.IsAttached() || !IsDefined(transactions) { return null; }
    let sample = new CP2077PresentationWeaponSample();
    sample.ownerID = this.GetEntityID();
    sample.record = t"";
    sample.spawning = transactions.IsSlotSpawningAnyItem(this, t"AttachmentSlots.WeaponRight");
    sample.slotEmpty = transactions.IsSlotEmpty(this, t"AttachmentSlots.WeaponRight");
    let held = transactions.GetItemInSlot(this, t"AttachmentSlots.WeaponRight");
    sample.hasItem = IsDefined(held);
    let itemID: ItemID;
    if sample.hasItem {
        sample.entityID = held.GetEntityID();
        if !EntityID.IsDefined(sample.entityID) { return null; }
        itemID = held.GetItemID();
        sample.record = ItemID.GetTDBID(itemID);
        sample.attached = held.IsAttached();
        if sample.attached && !sample.spawning && !sample.slotEmpty {
            sample.appearance = transactions.GetItemAppearance(this, itemID);
            let weapon = held as WeaponObject;
            if IsDefined(weapon) && CP2077PlayerPresentation.SupportedWeapon(sample.record) {
                let muzzle = weapon.GetMuzzleSlotWorldTransform();
                sample.muzzlePosition = Transform.GetPosition(muzzle);
                sample.muzzleRotation = Transform.GetOrientation(muzzle);
                sample.muzzleAvailable = true; // Caller checks finite values; not visual proof.
            }
        }
    }
    // Reject a changing slot/actor rather than joining observations from two
    // item lifetimes. All reads occur on the caller's game-thread tick.
    let current = transactions.GetItemInSlot(this, t"AttachmentSlots.WeaponRight");
    if !this.IsAttached() || NotEquals(this.GetEntityID(), sample.ownerID)
        || NotEquals(IsDefined(current), sample.hasItem)
        || NotEquals(transactions.IsSlotSpawningAnyItem(this, t"AttachmentSlots.WeaponRight"), sample.spawning)
        || NotEquals(transactions.IsSlotEmpty(this, t"AttachmentSlots.WeaponRight"), sample.slotEmpty) { return null; }
    if sample.hasItem {
        if NotEquals(current.GetEntityID(), sample.entityID) || current.GetItemID() != itemID
            || NotEquals(current.IsAttached(), sample.attached) { return null; }
    }
    if !sample.spawning {
        if drawn {
            sample.matches = sample.hasItem && sample.attached && !sample.slotEmpty && Equals(sample.record, record);
        } else {
            sample.matches = !sample.hasItem && sample.slotEmpty;
        }
    }
    return sample;
}

// Retained on the exact disposable projection, including across Lua rebinding.
// No inventory-removal hook is qualified here. Fail closed at eight grants and
// let the verified actor-retirement owner remove the whole temporary projection.
@addField(NPCPuppet)
private let CP2077Session_PresentationGrants: array<TweakDBID>;

@addMethod(NPCPuppet)
public func CP2077Session_PresentationGrantCount() -> Int32 {
    return ArraySize(this.CP2077Session_PresentationGrants);
}

@addMethod(NPCPuppet)
public func CP2077Session_HasPresentationItem(record: TweakDBID) -> Bool {
    let transactions = GameInstance.GetTransactionSystem(this.GetGame());
    return IsDefined(transactions) && transactions.HasItem(this, ItemID.FromTDBID(record));
}

@addMethod(NPCPuppet)
public func CP2077Session_EquipPresentation(record: TweakDBID, drawn: Bool) -> ref<AICommand> {
    let controller = this.GetAIControllerComponent();
    if !this.IsAttached() || !IsDefined(controller) || this.CP2077Session_PresentationProbeLocked
        || IsDefined(this.CP2077Session_PresentationCommand) { return null; }
    if !drawn {
        let holster = new AIUnequipCommand();
        holster.slotId = t"AttachmentSlots.WeaponRight";
        this.CP2077Session_PresentationCommand = holster;
        if !controller.SendCommand(holster) { this.CP2077Session_PresentationCommand = null; return null; }
        return holster;
    }
    if !CP2077PlayerPresentation.SupportedWeapon(record) { return null; }
    let id = ItemID.FromTDBID(record);
    let transactions = GameInstance.GetTransactionSystem(this.GetGame());
    if !IsDefined(transactions) { return null; }
    if !transactions.HasItem(this, id) {
        if ArraySize(this.CP2077Session_PresentationGrants) >= 8 { return null; }
        // Reserve BEFORE the mutation: an uncertain/failed GiveItem cannot
        // produce an unbounded retry loop or erase provenance of a new item.
        ArrayPush(this.CP2077Session_PresentationGrants, record);
        transactions.GiveItem(this, id, 1);
        if !transactions.HasItem(this, id) { return null; }
    }
    let equip = new AIEquipCommand();
    equip.slotId = t"AttachmentSlots.WeaponRight";
    equip.itemId = record;
    this.CP2077Session_PresentationCommand = equip;
    if !controller.SendCommand(equip) { this.CP2077Session_PresentationCommand = null; return null; }
    return equip; // Queued only. The owner retains and retires this command.
}

@addMethod(NPCPuppet)
public func CP2077Session_StopPresentation(command: ref<AICommand>) -> Bool {
    if !IsDefined(command) { return true; }
    if this.CP2077Session_PresentationCommand != command { return false; }
    let controller = this.GetAIControllerComponent();
    if !IsDefined(controller) { return false; }
    let state = controller.GetCommandState(command);
    if NotEquals(state, AICommandState.Cancelled) && NotEquals(state, AICommandState.Interrupted)
        && NotEquals(state, AICommandState.Success) && NotEquals(state, AICommandState.Failure) {
        controller.StopExecutingCommand(command, false);
        controller.CancelCommand(command);
        state = controller.GetCommandState(command);
    }
    if Equals(state, AICommandState.Cancelled) || Equals(state, AICommandState.Interrupted)
        || Equals(state, AICommandState.Success) || Equals(state, AICommandState.Failure) {
        this.CP2077Session_PresentationCommand = null;
        return true;
    }
    return false;
}
