// Private action-capture experiment. No networking, actor setters or gameplay.
@addMethod(PlayerPuppet)
public func CP2077Capture_Ready() -> Bool {
    return this.IsAttached() && IsDefined(this.GetPlayerStateMachineBlackboard());
}
@addMethod(PlayerPuppet)
public func CP2077Capture_Crouched() -> Bool {
    let board=this.GetPlayerStateMachineBlackboard();
    return IsDefined(board) && board.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Locomotion)
        == EnumInt(gamePSMLocomotionStates.Crouch);
}
@addMethod(PlayerPuppet)
public func CP2077Capture_Aiming() -> Bool {
    let board=this.GetPlayerStateMachineBlackboard();
    return IsDefined(board) && board.GetInt(GetAllBlackboardDefs().PlayerStateMachine.UpperBody)
        == EnumInt(gamePSMUpperBodyStates.Aim);
}
@addMethod(PlayerPuppet)
public func CP2077Capture_HeldRecord() -> TweakDBID {
    let transactions=GameInstance.GetTransactionSystem(this.GetGame());
    if !IsDefined(transactions) { return t""; }
    let weapon=transactions.GetItemInSlot(this,t"AttachmentSlots.WeaponRight") as WeaponObject;
    if IsDefined(weapon) && weapon.IsAttached() { return ItemID.GetTDBID(weapon.GetItemID()); }
    return t"";
}
@addMethod(PlayerPuppet)
public func CP2077Capture_HasWeapon() -> Bool {
    let transactions=GameInstance.GetTransactionSystem(this.GetGame());
    if !IsDefined(transactions) { return false; }
    let weapon=transactions.GetItemInSlot(this,t"AttachmentSlots.WeaponRight") as WeaponObject;
    return IsDefined(weapon) && weapon.IsAttached();
}
