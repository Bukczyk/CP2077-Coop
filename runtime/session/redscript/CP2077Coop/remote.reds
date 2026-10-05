// Judy is a temporary, non-persistent player rendering projection.
// NPC/world adoption must use server-issued SessionEntityId and authority records.
@addMethod(PlayerPuppet)
public func CP2077Session_SpawnProxy(tag: CName, x: Float, y: Float, z: Float) -> Void {
    let system = GameInstance.GetDynamicEntitySystem();
    if !IsDefined(system) || !system.IsReady() || system.IsPopulated(tag) {
        return;
    }
    let position: Vector4;
    position.X = x;
    position.Y = y;
    position.Z = z;
    position.W = 1.0;
    let spec = new DynamicEntitySpec();
    spec.recordID = t"Character.Judy";
    spec.position = position;
    spec.orientation = this.GetWorldOrientation();
    spec.persistState = false;
    spec.persistSpawn = false;
    spec.alwaysSpawned = true;
    spec.spawnInView = true;
    spec.active = true;
    spec.tags = [n"CP2077Session.Projection", tag];
    system.CreateEntity(spec);
}
