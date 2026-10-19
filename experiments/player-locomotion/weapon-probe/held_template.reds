// Read the actual attached weapon template, not a guessed record-to-path map.
@addMethod(PlayerPuppet)
public func CP2077Capture_HeldTemplate() -> String {
    let transactions=GameInstance.GetTransactionSystem(this.GetGame());
    if !IsDefined(transactions) { return ""; }
    let weapon=transactions.GetItemInSlot(this,t"AttachmentSlots.WeaponRight") as WeaponObject;
    if !IsDefined(weapon) || !weapon.IsAttached() { return ""; }
    return ResRef.ToString(weapon.GetTemplatePath());
}
