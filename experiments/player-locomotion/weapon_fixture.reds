// PRIVATE fixture only. Does not equip a WeaponObject or change a real player.
@addMethod(Entity)
public func CP2077Fixture_SetWeaponVisible(visible: Bool) -> Bool {
    if !this.IsAttached()
        || ResRef.GetHash(this.GetTemplatePath()) != ResRef.GetHash(r"base\\cp2077coop\\entities\\player_weapon_igla_fixture.ent") {
        return false;
    }
    let components=this.GetComponents();
    if ArraySize(components)>64 { return false; }
    let names: array<CName>=[n"CP2077WeaponMesh_0", n"CP2077WeaponMesh_1", n"CP2077WeaponMesh_2", n"CP2077WeaponMesh_3", n"CP2077WeaponMesh_4"];
    let selected: array<ref<IComponent>>;
    let i: Int32=0;
    while i<ArraySize(names) {
        let j: Int32=0;
        let found: ref<IComponent>;
        while j<ArraySize(components) {
            if Equals(components[j].name,names[i]) {
                if IsDefined(found) || !IsDefined(components[j] as entSkinnedMeshComponent) { return false; }
                found=components[j];
            }
            j+=1;
        }
        if !IsDefined(found) { return false; }
        ArrayPush(selected,found);
        i+=1;
    }
    i=0;
    while i<ArraySize(selected) {
        selected[i].Toggle(visible);
        i+=1;
    }
    // Submission only. Visibility and attachment still require video review.
    return true;
}
