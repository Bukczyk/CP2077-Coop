// Opt-in physics-query evidence for the query-only passive entity variant.
// This does not produce a native hit event, damage, or a network request.
@addField(PlayerPuppet)
private let CPPhysicalTraceTarget: wref<Entity>;

@addField(PlayerPuppet)
private let CPPhysicalTraceSession: Uint64;

@addField(PlayerPuppet)
private let CPPhysicalTraceEpoch: Uint32;

@addField(PlayerPuppet)
private let CPPhysicalTraceGeneration: Uint64;

@addField(PlayerPuppet)
private let CPPhysicalTraceTargetSession: Uint64;

@addField(PlayerPuppet)
private let CPPhysicalTraceStatus: String;

@addMethod(PlayerPuppet)
public func CP2077Encounter_GetPhysicalTraceStatus() -> String {
    return this.CPPhysicalTraceStatus;
}

@addMethod(PlayerPuppet)
public func CP2077Encounter_SetPhysicalTraceTarget(target: ref<Entity>) -> Bool {
    this.CPPhysicalTraceTarget = null;
    this.CPPhysicalTraceTargetSession = 0ul;
    this.CPPhysicalTraceStatus = "disabled";
    if !IsDefined(target) { return true; }
    if !this.CP2077Encounter_PhysicalShotScoped() {
        this.CPPhysicalTraceStatus = "rejected_not_scoped";
        return false;
    }
    if !target.IsAttached() {
        this.CPPhysicalTraceStatus = "rejected_target_detached";
        return false;
    }
    if IsDefined(target as NPCPuppet) {
        this.CPPhysicalTraceStatus = "rejected_npc_puppet";
        return false;
    }
    let id = target.GetEntityID();
    let system = GameInstance.GetStaticEntitySystem();
    if !IsDefined(system) {
        this.CPPhysicalTraceStatus = "rejected_no_static_system";
        return false;
    }
    if !system.IsManaged(id) {
        this.CPPhysicalTraceStatus = "rejected_not_managed expected=" + ToString(id.hash);
        return false;
    }
    // Codeware 1.18 StaticEntitySystem.IsTagged ignores the requested tag.
    // Materialize the tag's entity collection before comparing exact IDs.
    // Avoid the GetTags/ArrayContains expression implicated in trial four.
    let tagged: array<ref<Entity>> = system.GetTagged(n"CP2077Coop.ExperimentalStaticNpc");
    let index: Int32 = 0;
    let owned: Bool = false;
    let details: String = " expected=" + ToString(id.hash)
        + " taggedCount=" + ToString(ArraySize(tagged)) + " taggedIds=";
    // This is a bounded probe, not a capacity claim for multiplayer.
    if ArraySize(tagged) > 256 {
        this.CPPhysicalTraceStatus = "rejected_tagged_limit" + details;
        return false;
    }
    while index < ArraySize(tagged) {
        // Keep the native EntityID return alive before reading its added hash
        // field. Trial six returned a pointer-like value from the chained form.
        let taggedEntity: ref<Entity> = tagged[index];
        let taggedId: EntityID;
        if IsDefined(taggedEntity) {
            taggedId = taggedEntity.GetEntityID();
        }
        // Keep diagnostic text bounded even if the private cohort expands.
        if index < 8 {
            if IsDefined(taggedEntity) {
                details += ToString(taggedId.hash) + ",";
            } else {
                details += "null,";
            }
        }
        if IsDefined(taggedEntity) && taggedId.hash == id.hash {
            owned = true;
            break;
        }
        index += 1;
    }
    if !owned {
        this.CPPhysicalTraceStatus = "rejected_exact_tag_membership" + details;
        return false;
    }
    let sessionEntity = CP2077Session_Resolve(id);
    if sessionEntity == 0ul {
        this.CPPhysicalTraceStatus = "rejected_no_session_mapping" + details;
        return false;
    }
    this.CPPhysicalTraceTarget = target;
    this.CPPhysicalTraceTargetSession = sessionEntity;
    this.CPPhysicalTraceSession = CP2077Session_Session();
    this.CPPhysicalTraceEpoch = CP2077Session_Epoch();
    this.CPPhysicalTraceGeneration = CP2077Session_Generation();
    this.CPPhysicalTraceStatus = "accepted" + details + " sessionEntity=" + ToString(sessionEntity);
    return true;
}

@addMethod(PlayerPuppet)
private func CP2077Encounter_TracePhysicalShot(origin: Vector4, direction: Vector4) -> String {
    if !IsDefined(this.CPPhysicalTraceTarget) { return "physical_trace disabled"; }
    let target = this.CPPhysicalTraceTarget;
    if !this.CP2077Encounter_PhysicalShotScoped() || !target.IsAttached()
        || this.CPPhysicalTraceSession != CP2077Session_Session()
        || this.CPPhysicalTraceEpoch != CP2077Session_Epoch()
        || this.CPPhysicalTraceGeneration != CP2077Session_Generation() {
        this.CP2077Encounter_SetPhysicalTraceTarget(null);
        return "physical_trace rejected_scope";
    }
    let id = target.GetEntityID();
    let mapped = CP2077Session_Resolve(id);
    if mapped == 0ul || mapped != this.CPPhysicalTraceTargetSession {
        this.CP2077Encounter_SetPhysicalTraceTarget(null);
        return "physical_trace rejected_mapping";
    }
    // Caller has already checked all finite components. Reject an implausible
    // on-foot firing origin rather than trace from arbitrary world coordinates.
    let offset = origin - this.GetWorldPosition();
    let originDistanceSquared = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z;
    if !(originDistanceSquared >= 0.0 && originDistanceSquared <= 25.0) {
        return "physical_trace rejected_origin_not_near_local_player";
    }
    let query: QueryFilter = QueryFilter.ZERO();
    QueryFilter.AddGroup(query, n"Static");
    QueryFilter.AddGroup(query, n"Vehicle");
    QueryFilter.AddGroup(query, n"PlayerBlocker");
    QueryFilter.AddGroup(query, n"AI");
    // The vanilla NPC Hitbox preset exposes the query-only capsule to AI.
    // Ordinary NPC hitboxes can now occlude it, alongside the world groups.
    let endpoint = origin + Vector4.Normalize(direction) * 100.0;
    let result: TraceResult;
    let hit = GameInstance.GetSpatialQueriesSystem(this.GetGame()).SyncRaycastByQueryFilter(
        origin, endpoint, query, result, false, false);
    if !hit || !TraceResult.IsValid(result) {
        return "physical_trace seq=" + ToString(this.CPPhysicalShotSequence)
            + " outcome=miss expectedLocal=" + ToString(id.hash)
            + " expectedSession=" + ToString(mapped) + " nativeDamage=false";
    }
    let object = TraceResult.GetHitEntity(result);
    let hitId: EntityID;
    let hitSession: Uint64 = 0ul;
    if IsDefined(object) {
        hitId = object.GetEntityID();
        hitSession = CP2077Session_Resolve(hitId);
    }
    let hitPoint = Cast<Vector4>(result.position);
    let travel = hitPoint - origin;
    let distanceSquared = travel.X * travel.X + travel.Y * travel.Y + travel.Z * travel.Z;
    if !(distanceSquared >= 0.0 && distanceSquared <= 10000.01) {
        return "physical_trace rejected_result_distance";
    }
    let exact = IsDefined(object) && hitId.hash == id.hash && hitSession == mapped;
    return "physical_trace seq=" + ToString(this.CPPhysicalShotSequence)
        + " exactTarget=" + ToString(exact)
        + " expectedLocal=" + ToString(id.hash) + " expectedSession=" + ToString(mapped)
        + " hitEntityDefined=" + ToString(IsDefined(object))
        + " hitLocal=" + ToString(hitId.hash) + " hitSession=" + ToString(hitSession)
        + " hitX=" + ToString(hitPoint.X) + " hitY=" + ToString(hitPoint.Y) + " hitZ=" + ToString(hitPoint.Z)
        + " distanceSquared=" + ToString(distanceSquared)
        + " firstHitInGroups=Static_Vehicle_PlayerBlocker_AI queryOnly=true nativeDamage=false"
        + " bulletSpreadPenetration=unsupported";
}
