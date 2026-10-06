// EXPERIMENT ONLY: not packaged or installed. Visual acceptance failed on 2026-10-06.
// Presentation hooks for the proposed typed state boundary. The v3 runtime
// does NOT call these for network synchronization: v3 carries transforms only.
// Local measurement fixtures may exercise them on an owned player projection.
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
public func CP2077Session_ApplyStance(crouched: Bool) -> Void {
    if crouched { NPCPuppet.ChangeStanceState(this, gamedataNPCStanceState.Crouch); }
    else { NPCPuppet.ChangeStanceState(this, gamedataNPCStanceState.Stand); }
}

@addMethod(NPCPuppet)
public func CP2077Session_EquipPresentation(record: TweakDBID, drawn: Bool) -> Bool {
    let controller = this.GetAIControllerComponent();
    if !IsDefined(controller) { return false; }
    if !drawn {
        let holster = new AIUnequipCommand();
        holster.slotId = t"AttachmentSlots.WeaponRight";
        controller.SendCommand(holster);
        return true;
    }
    let item = TweakDBInterface.GetItemRecord(record);
    if !IsDefined(item) { return false; }
    // Body-integrated weapons cannot be represented by a normal held prop.
    let kind = item.ItemType().Type();
    if Equals(kind, gamedataItemType.Wea_Fists) || Equals(kind, gamedataItemType.Cyb_StrongArms)
        || Equals(kind, gamedataItemType.Cyb_NanoWires) || Equals(kind, gamedataItemType.Cyb_Launcher)
        || Equals(kind, gamedataItemType.Cyb_MantisBlades) { return false; }
    let id = ItemID.FromTDBID(record);
    let transactions = GameInstance.GetTransactionSystem(this.GetGame());
    if !transactions.HasItem(this, id) { transactions.GiveItem(this, id, 1); }
    let equip = new AIEquipCommand();
    equip.slotId = t"AttachmentSlots.WeaponRight";
    equip.itemId = record;
    controller.SendCommand(equip);
    return true; // Queued only. The caller must observe the actual held item.
}
