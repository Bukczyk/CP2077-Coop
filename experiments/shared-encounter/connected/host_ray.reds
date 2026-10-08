// Opt-in controlled diagnostic only. No transport, damage or ambient mutation.
// Installed only with engine_hooks.reds by the private test owner.
@addMethod(NPCPuppet)
public func CP2077Encounter_ValidateConnectedRay(shooter: ref<Entity>, shooterSession: Uint64,
    targetSession: Uint64, origin: Vector4, direction: Vector4) -> Bool {
    if !this.CP2077Encounter_HostReady() || !IsDefined(shooter) || !shooter.IsAttached()
        || shooterSession == 0ul || targetSession == 0ul
        || CP2077Session_Resolve(shooter.GetEntityID()) != shooterSession
        || CP2077Session_Resolve(this.GetEntityID()) != targetSession {
        return false;
    }
    // Range comparisons reject non-finite inputs before native spatial math.
    if !(origin.X >= -1000000.0 && origin.X <= 1000000.0)
        || !(origin.Y >= -1000000.0 && origin.Y <= 1000000.0)
        || !(origin.Z >= -1000000.0 && origin.Z <= 1000000.0)
        || !(direction.X >= -2.0 && direction.X <= 2.0)
        || !(direction.Y >= -2.0 && direction.Y <= 2.0)
        || !(direction.Z >= -2.0 && direction.Z <= 2.0) { return false; }
    origin.W = 1.0;
    direction.W = 0.0;
    let length = direction.X * direction.X + direction.Y * direction.Y + direction.Z * direction.Z;
    if !(length >= 0.01 && length <= 4.0) { return false; }
    let offset = origin - shooter.GetWorldPosition();
    let distance = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z;
    if !(distance >= 0.0 && distance <= 25.0) { return false; }
    let filter = QueryFilter.ZERO();
    QueryFilter.AddGroup(filter, n"Static");
    QueryFilter.AddGroup(filter, n"Vehicle");
    QueryFilter.AddGroup(filter, n"PlayerBlocker");
    QueryFilter.AddGroup(filter, n"AI");
    let result: TraceResult;
    let hit = GameInstance.GetSpatialQueriesSystem(this.GetGame()).SyncRaycastByQueryFilter(
        origin, origin + Vector4.Normalize(direction) * 100.0, filter, result, false, false);
    if !hit || !TraceResult.IsValid(result) { return false; }
    let entity = TraceResult.GetHitEntity(result);
    if !IsDefined(entity) { return false; }
    let hitId: EntityID = entity.GetEntityID();
    let targetId: EntityID = this.GetEntityID();
    return hitId.hash == targetId.hash && CP2077Session_Resolve(hitId) == targetSession;
}
