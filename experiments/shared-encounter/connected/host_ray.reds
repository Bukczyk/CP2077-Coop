// Opt-in controlled diagnostic only. No transport, damage or ambient mutation.
// Installed only with engine_hooks.reds by the private test owner.
@addField(NPCPuppet)
private let CPConnectedRayStatus: String;

@addMethod(NPCPuppet)
public func CP2077Encounter_ConnectedRayStatus() -> String {
    return this.CPConnectedRayStatus;
}

@addMethod(NPCPuppet)
public func CP2077Encounter_ValidateConnectedRay(shooter: ref<Entity>, shooterSession: Uint64,
    targetSession: Uint64, origin: Vector4, direction: Vector4) -> Bool {
    // Bounded read-only evidence. None of the acceptance checks below change.
    let shooterId: EntityID;
    let shooterMapped: Uint64 = 0ul;
    let shooterPosition: Vector4;
    if IsDefined(shooter) && shooter.IsAttached() {
        shooterId = shooter.GetEntityID();
        shooterMapped = CP2077Session_Resolve(shooterId);
        shooterPosition = shooter.GetWorldPosition();
    }
    let observedTargetId: EntityID = this.GetEntityID();
    let targetMapped = CP2077Session_Resolve(observedTargetId);
    let targetPosition = this.GetWorldPosition();
    let details = " shooterDefined=" + ToString(IsDefined(shooter))
        + " shooterLocal=" + ToString(shooterId.hash)
        + " shooterSession=" + ToString(shooterSession)
        + " shooterResolved=" + ToString(shooterMapped)
        + " targetLocal=" + ToString(observedTargetId.hash)
        + " targetSession=" + ToString(targetSession)
        + " targetResolved=" + ToString(targetMapped)
        + " shooterX=" + ToString(shooterPosition.X)
        + " shooterY=" + ToString(shooterPosition.Y)
        + " shooterZ=" + ToString(shooterPosition.Z)
        + " targetX=" + ToString(targetPosition.X)
        + " targetY=" + ToString(targetPosition.Y)
        + " targetZ=" + ToString(targetPosition.Z);
    this.CPConnectedRayStatus = "stage=rejected_scope_binding" + details;
    if !this.CP2077Encounter_HostReady() || !IsDefined(shooter) || !shooter.IsAttached()
        || shooterSession == 0ul || targetSession == 0ul
        || CP2077Session_Resolve(shooter.GetEntityID()) != shooterSession
        || CP2077Session_Resolve(this.GetEntityID()) != targetSession {
        return false;
    }
    // Range comparisons reject non-finite inputs before native spatial math.
    this.CPConnectedRayStatus = "stage=rejected_finite_bounds" + details;
    if !(origin.X >= -1000000.0 && origin.X <= 1000000.0)
        || !(origin.Y >= -1000000.0 && origin.Y <= 1000000.0)
        || !(origin.Z >= -1000000.0 && origin.Z <= 1000000.0)
        || !(direction.X >= -2.0 && direction.X <= 2.0)
        || !(direction.Y >= -2.0 && direction.Y <= 2.0)
        || !(direction.Z >= -2.0 && direction.Z <= 2.0) { return false; }
    origin.W = 1.0;
    direction.W = 0.0;
    let length = direction.X * direction.X + direction.Y * direction.Y + direction.Z * direction.Z;
    details += " directionLengthSquared=" + ToString(length);
    this.CPConnectedRayStatus = "stage=rejected_direction_length" + details;
    if !(length >= 0.01 && length <= 4.0) { return false; }
    let offset = origin - shooter.GetWorldPosition();
    let distance = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z;
    details += " originDistanceSquared=" + ToString(distance);
    this.CPConnectedRayStatus = "stage=rejected_origin_distance" + details;
    if !(distance >= 0.0 && distance <= 25.0) { return false; }
    let filter = QueryFilter.ZERO();
    QueryFilter.AddGroup(filter, n"Static");
    QueryFilter.AddGroup(filter, n"Vehicle");
    QueryFilter.AddGroup(filter, n"PlayerBlocker");
    QueryFilter.AddGroup(filter, n"AI");
    let result: TraceResult;
    let hit = GameInstance.GetSpatialQueriesSystem(this.GetGame()).SyncRaycastByQueryFilter(
        origin, origin + Vector4.Normalize(direction) * 100.0, filter, result, false, false);
    details += " traceHit=" + ToString(hit) + " traceValid=" + ToString(TraceResult.IsValid(result));
    this.CPConnectedRayStatus = "stage=rejected_trace_miss" + details;
    if !hit || !TraceResult.IsValid(result) { return false; }
    let entity = TraceResult.GetHitEntity(result);
    this.CPConnectedRayStatus = "stage=rejected_hit_entity_missing" + details;
    if !IsDefined(entity) { return false; }
    let hitId: EntityID = entity.GetEntityID();
    let targetId: EntityID = this.GetEntityID();
    let hitMapped = CP2077Session_Resolve(hitId);
    let hitPoint = Cast<Vector4>(result.position);
    this.CPConnectedRayStatus = "stage=exact_identity_check" + details
        + " hitLocal=" + ToString(hitId.hash) + " hitResolved=" + ToString(hitMapped)
        + " hitX=" + ToString(hitPoint.X) + " hitY=" + ToString(hitPoint.Y) + " hitZ=" + ToString(hitPoint.Z)
        + " hitIsShooter=" + ToString(hitId.hash == shooterId.hash)
        + " hitIsTarget=" + ToString(hitId.hash == targetId.hash)
        + " hitSessionMatches=" + ToString(hitMapped == targetSession);
    return hitId.hash == targetId.hash && CP2077Session_Resolve(hitId) == targetSession;
}
