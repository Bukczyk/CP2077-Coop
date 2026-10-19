// PRIVATE read-only resource metadata. No mesh bytes or gameplay operations.
// Existing game/Codeware declarations already expose these native fields.

public class CP2077WeaponVisualRow extends IScriptable {
    public let name: String;
    public let kind: String;
    public let path: String;
    public let appearance: String;
    public let enabled: Bool;
    public let parent: String;
    public let slot: String;
    public let skin: String;
    public let localTransform: WorldTransform;
    public let scale: Vector3;
    public let mask: Uint64;
}

@addMethod(PlayerPuppet)
public func CP2077Capture_HeldVisuals() -> array<ref<CP2077WeaponVisualRow>> {
    let output: array<ref<CP2077WeaponVisualRow>>;
    let empty: array<ref<CP2077WeaponVisualRow>>;
    let transactions=GameInstance.GetTransactionSystem(this.GetGame());
    if !IsDefined(transactions) { return output; }
    let weapon=transactions.GetItemInSlot(this,t"AttachmentSlots.WeaponRight") as WeaponObject;
    if !IsDefined(weapon) || !weapon.IsAttached() { return output; }
    let components=weapon.GetComponents();
    if ArraySize(components)>128 { return output; }
    let index: Int32=0;
    while index<ArraySize(components) {
        let component=components[index];
        let animated=component as AnimatedComponent;
        let mesh=component as MeshComponent;
        let skinned=component as entSkinnedMeshComponent;
        let placed=component as IPlacedComponent;
        let row=new CP2077WeaponVisualRow();
        row.name=NameToString(component.name);
        if IsDefined(placed) {
            row.localTransform=placed.localTransform;
            if IsDefined(placed.parentTransform) {
                row.parent=NameToString(placed.parentTransform.bindName);
                let hard=placed.parentTransform as entHardTransformBinding;
                if IsDefined(hard) { row.slot=NameToString(hard.slotName); }
            }
        }
        if IsDefined(animated) {
            row.kind="rig";
            row.path=ResRef.ToString(ResourceRef.GetPath(animated.rig));
            row.enabled=true;
        } else {
            if IsDefined(mesh) {
                row.kind="static";
                row.path=ResRef.ToString(ResourceAsyncRef.GetPath(mesh.mesh));
                row.appearance=NameToString(mesh.meshAppearance);
                row.enabled=mesh.isEnabled;
                row.mask=mesh.chunkMask;
                row.scale=mesh.visualScale;
            } else {
                if IsDefined(skinned) {
                    row.kind="skinned";
                    row.path=ResRef.ToString(ResourceAsyncRef.GetPath(skinned.mesh));
                    row.appearance=NameToString(skinned.meshAppearance);
                    row.enabled=skinned.isEnabled;
                    row.mask=skinned.chunkMask;
                    if IsDefined(skinned.skinning) { row.skin=NameToString(skinned.skinning.bindName); }
                }
            }
        }
        if NotEquals(row.kind,"") { ArrayPush(output,row); }
        index+=1;
    }
    let current=transactions.GetItemInSlot(this,t"AttachmentSlots.WeaponRight");
    if !IsDefined(current) || !Equals(current.GetEntityID(),weapon.GetEntityID()) { return empty; }
    return output;
}

@addMethod(PlayerPuppet)
public func CP2077Capture_HeldAppearance() -> CName {
    let transactions=GameInstance.GetTransactionSystem(this.GetGame());
    if !IsDefined(transactions) { return n""; }
    let weapon=transactions.GetItemInSlot(this,t"AttachmentSlots.WeaponRight") as WeaponObject;
    if !IsDefined(weapon) || !weapon.IsAttached() { return n""; }
    return transactions.GetItemAppearance(this,weapon.GetItemID());
}
