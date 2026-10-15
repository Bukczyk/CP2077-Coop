// Opt-in diagnostic source. Not installed or loaded by the session runtime.
// Native UI coordinates are observations, never a qualified map projection.
public class CP2077MapBasisProbeData extends MappinScriptData {
    public let probe: wref<CP2077MapBasisProbe>;
    public let slot: Int32;
    public let id: NewMappinID;
    public let position: Vector4;
    public let minimap: wref<MinimapPOIMappinController>;
    public let fullmap: wref<BaseWorldMapMappinController>;
    public let minimapUpdate: Uint32;
    public let fullmapUpdate: Uint32;
    public let deleteIssued: Bool;
}

public class CP2077MapBasisReading extends IScriptable {
    public let controller: wref<BaseMappinBaseController>;
    public let root: wref<inkWidget>;
    public let data: wref<MappinScriptData>;
    public let mappin: wref<IMappin>;
    public let id: NewMappinID;
    public let world: Vector4;
    public let update: Uint32;
    public let eligible: Bool;
    public let ancestry: array<wref<inkWidget>>;
    public let ancestryValid: Bool;
    public let size: Vector2;
    public let anchorPoint: Vector2;
    public let pivotPoint: Vector2;
    // Origin, anchor*size, pivot*size, local +X and +Y. Each remains a
    // separately named candidate; none is presumed to be the native anchor.
    public let localPoints: array<Vector2>;
    public let globalPoints: array<Vector2>;
    public let parentPoints: array<Vector2>;
    public let roundtripPoints: array<Vector2>;
}

public class CP2077MapBasisSnapshot extends IScriptable {
    public let probe: ref<CP2077MapBasisProbe>;
    public let owner: wref<PlayerPuppet>;
    public let token: Uint32;
    public let surface: String;
    public let container: wref<inkWidget>;
    public let blockedContainer: wref<inkWidget>;
    public let viewRoot: wref<inkWidget>;
    public let targetData: wref<CP2077SessionPlayerMarkerData>;
    public let poseRevision: Uint32;
    public let distance: Float;
    public let before: array<ref<CP2077MapBasisReading>>;
    public let after: array<ref<CP2077MapBasisReading>>;
    public let complete: Bool;
    public let reason: String;
    // Deliberately never set true by this experiment.
    public let layoutVerified: Bool;
    public let onscreenVerified: Bool;
    public let projectionAnchorVerified: Bool;
    public let facingQualified: Bool;
}

public class CP2077MapBasisProbe extends IScriptable {
    public let owner: wref<PlayerPuppet>;
    public let points: array<ref<CP2077MapBasisProbeData>>;
    public let distance: Float;
    public let active: Bool;
    private let token: Uint32;
    private let mappinSystem: wref<MappinSystem>;

    private static func Bounded(value: Float, limit: Float) -> Bool {
        return value >= -limit && value <= limit;
    }

    public func Start(player: ref<PlayerPuppet>, origin: Vector4, distance: Float) -> Bool {
        if IsDefined(this.owner) || ArraySize(this.points) != 0 || !IsDefined(player) || !player.IsAttached()
            || !CP2077MapBasisProbe.Bounded(origin.X, 999900.0)
            || !CP2077MapBasisProbe.Bounded(origin.Y, 999900.0)
            || !CP2077MapBasisProbe.Bounded(origin.Z, 999900.0)
            || !(distance >= 0.1 && distance <= 100.0) {
            return false;
        }
        this.owner = player;
        this.distance = distance;
        let system = GameInstance.GetMappinSystem(player.GetGame());
        if !IsDefined(system) { return false; }
        this.mappinSystem = system;
        let slot = 0;
        while slot < 4 {
            let point = new CP2077MapBasisProbeData();
            point.probe = this;
            point.slot = slot;
            point.position = origin;
            point.position.W = 1.0;
            if slot == 1 || slot == 3 { point.position.X += distance; }
            if slot == 2 || slot == 3 { point.position.Y += distance; }
            let data: MappinData;
            data.mappinType = t"Mappins.CustomPositionMappinDefinition";
            data.variant = gamedataMappinVariant.CustomPositionVariant;
            data.active = true;
            data.debugCaption = "Map basis probe " + ToString(slot);
            data.visibleThroughWalls = true;
            data.scriptData = point;
            // Retain each successful exact ID immediately. Partial registration
            // is not readiness and does not discard ownership of earlier IDs.
            point.id = system.RegisterMappin(data, point.position);
            if point.id.value == Cast<Uint64>(0) { return false; }
            ArrayPush(this.points, point);
            slot += 1;
        }
        this.active = true;
        return true;
    }

    public func Stop() -> Bool {
        this.active = false;
        if ArraySize(this.points) == 0 { return true; }
        // Cleanup must not require a still-attached/live owner, or discover a
        // different world's system. The caller retains this probe until true.
        let system = this.mappinSystem;
        if !IsDefined(system) { return false; }
        let index = ArraySize(this.points) - 1;
        while index >= 0 {
            let point = this.points[index];
            let current = system.GetMappin(point.id);
            if IsDefined(current) {
                // An ID reused by somebody else is never ours to unregister.
                if current.GetScriptData() != point { return false; }
                if !point.deleteIssued {
                    system.UnregisterMappin(point.id);
                    point.deleteIssued = true;
                }
            }
            // A never-observed registration may still be pending. Absence
            // before our exact unregister is not proof of cancellation.
            if !point.deleteIssued { return false; }
            // Void UnregisterMappin is not a cleanup acknowledgement.
            if IsDefined(system.GetMappin(point.id)) { return false; }
            ArrayErase(this.points, index);
            index -= 1;
        }
        return true;
    }

    private func Read(controller: wref<BaseMappinBaseController>, destination: wref<inkWidget>, surface: String,
        container: wref<inkWidget>, blocked: wref<inkWidget>, view: wref<inkWidget>) -> ref<CP2077MapBasisReading> {
        let result = new CP2077MapBasisReading();
        if !IsDefined(controller) || !IsDefined(destination) { return result; }
        result.controller = controller;
        result.root = controller.GetRootWidget();
        result.mappin = controller.GetMappin();
        if !IsDefined(result.root) || !IsDefined(result.mappin) { return result; }
        result.data = result.mappin.GetScriptData();
        result.id = result.mappin.GetNewMappinID();
        result.world = result.mappin.GetWorldPosition();
        let mini = controller as MinimapPOIMappinController;
        let full = controller as BaseWorldMapMappinController;
        let data = result.data as CP2077MapBasisProbeData;
        if Equals(surface, "minimap") && IsDefined(mini) {
            result.eligible = mini.CP2077MapBasis_Eligible();
            if IsDefined(data) && data.minimap == mini { result.update = data.minimapUpdate; }
            if !IsDefined(data) { result.update = mini.CP2077Session_GetFacingPreviewGeneration(); }
        }
        if Equals(surface, "fullmap") && IsDefined(full) {
            result.eligible = full.CP2077MapBasis_Eligible();
            if IsDefined(data) && data.fullmap == full { result.update = data.fullmapUpdate; }
            if !IsDefined(data) { result.update = full.CP2077Session_GetFacingPreviewGeneration(); }
        }
        result.eligible = result.eligible && result.mappin.IsActive() && result.mappin.IsVisible();
        let cursor = result.root;
        let reachedContainer = false;
        while IsDefined(cursor) && ArraySize(result.ancestry) < 64 {
            if ArrayContains(result.ancestry, cursor) || cursor == blocked
                || !cursor.IsVisible() || !(cursor.GetOpacity() > 0.0 && cursor.GetOpacity() <= 1.0) {
                return result;
            }
            ArrayPush(result.ancestry, cursor);
            if cursor == container { reachedContainer = true; }
            if cursor == view {
                result.ancestryValid = reachedContainer;
                break;
            }
            cursor = cursor.GetParentWidget();
        }
        if !result.ancestryValid { return result; }
        result.size = result.root.GetSize();
        result.anchorPoint = result.root.GetAnchorPoint();
        result.pivotPoint = result.root.GetRenderTransformPivot();
        let point: Vector2;
        ArrayPush(result.localPoints, point);
        point.X = result.anchorPoint.X * result.size.X;
        point.Y = result.anchorPoint.Y * result.size.Y;
        ArrayPush(result.localPoints, point);
        point.X = result.pivotPoint.X * result.size.X;
        point.Y = result.pivotPoint.Y * result.size.Y;
        ArrayPush(result.localPoints, point);
        point.X = 1.0; point.Y = 0.0;
        ArrayPush(result.localPoints, point);
        point.X = 0.0; point.Y = 1.0;
        ArrayPush(result.localPoints, point);
        let index = 0;
        while index < ArraySize(result.localPoints) {
            let globalPoint = WidgetUtils.LocalToGlobal(result.root, result.localPoints[index]);
            ArrayPush(result.globalPoints, globalPoint);
            ArrayPush(result.parentPoints, WidgetUtils.GlobalToLocal(destination, globalPoint));
            ArrayPush(result.roundtripPoints, WidgetUtils.GlobalToLocal(result.root, globalPoint));
            index += 1;
        }
        return result;
    }

    private func Capture(target: wref<BaseMappinBaseController>, surface: String, container: wref<inkWidget>,
        blocked: wref<inkWidget>, view: wref<inkWidget>) -> ref<CP2077MapBasisSnapshot> {
        let sample = new CP2077MapBasisSnapshot();
        sample.probe = this;
        sample.owner = this.owner;
        sample.surface = surface;
        sample.container = container;
        sample.blockedContainer = blocked;
        sample.viewRoot = view;
        sample.distance = this.distance;
        sample.reason = "unavailable";
        if this.token == 4294967295u { return sample; }
        this.token += 1u;
        sample.token = this.token;
        if !this.active || ArraySize(this.points) != 4 || !IsDefined(this.owner) || !this.owner.IsAttached()
            || !IsDefined(target) || !IsDefined(container) || !IsDefined(view) { return sample; }
        let destination = target.GetRootWidget();
        let mappin = target.GetMappin();
        if !IsDefined(destination) || !IsDefined(mappin) { return sample; }
        let marker = mappin.GetScriptData() as CP2077SessionPlayerMarkerData;
        if !IsDefined(marker) || marker.owner != this.owner || marker.playerId == 0u || !marker.facingAllowed
            || marker.poseRevision == 0u || marker.poseRevision == 4294967295u { return sample; }
        sample.targetData = marker;
        sample.poseRevision = marker.poseRevision;
        // Two immediate complete reads detect changed provenance, not a native
        // post-layout barrier. Lua validates every pair and the world geometry.
        let pass = 0;
        while pass < 2 {
            let readings: array<ref<CP2077MapBasisReading>>;
            ArrayPush(readings, this.Read(target, destination, surface, container, blocked, view));
            let slot = 0;
            while slot < 4 {
                let data = this.points[slot];
                let controller: wref<BaseMappinBaseController>;
                if Equals(surface, "minimap") { controller = data.minimap; }
                else { controller = data.fullmap; }
                let reading = this.Read(controller, destination, surface, container, blocked, view);
                if data.probe != this || data.slot != slot || reading.data != data || reading.id.value != data.id.value {
                    sample.reason = "probe_identity";
                    return sample;
                }
                ArrayPush(readings, reading);
                slot += 1;
            }
            if pass == 0 { sample.before = readings; }
            else { sample.after = readings; }
            pass += 1;
        }
        if marker != mappin.GetScriptData() || marker.poseRevision != sample.poseRevision
            || !marker.facingAllowed || marker.owner != this.owner || !this.owner.IsAttached() {
            sample.reason = "target_changed";
            return sample;
        }
        sample.complete = true;
        sample.reason = "raw_capture_only";
        return sample;
    }

    public func CaptureMinimap(target: ref<MinimapPOIMappinController>, view: ref<MinimapContainerController>) -> ref<CP2077MapBasisSnapshot> {
        if !IsDefined(view) { return null; }
        let sample = this.Capture(target, "minimap", inkWidgetRef.Get(view.unclampedMappinContainer),
            inkWidgetRef.Get(view.clampedMappinContainer), view.GetRootWidget());
        if sample.container != inkWidgetRef.Get(view.unclampedMappinContainer)
            || sample.blockedContainer != inkWidgetRef.Get(view.clampedMappinContainer)
            || sample.viewRoot != view.GetRootWidget() {
            sample.complete = false;
            sample.reason = "view_changed";
        }
        return sample;
    }

    public func CaptureFullmap(target: ref<BaseWorldMapMappinController>, view: ref<WorldMapMenuGameController>) -> ref<CP2077MapBasisSnapshot> {
        if !IsDefined(view) { return null; }
        let sample = this.Capture(target, "fullmap", view.CP2077MapBasis_SpawnContainer(), null, view.GetRootWidget());
        if sample.container != view.CP2077MapBasis_SpawnContainer() || sample.viewRoot != view.GetRootWidget() {
            sample.complete = false;
            sample.reason = "view_changed";
        }
        return sample;
    }
}

@addField(PlayerPuppet)
private let CP2077MapBasis_Probe: ref<CP2077MapBasisProbe>;

@addMethod(PlayerPuppet)
public func CP2077MapBasis_Start(origin: Vector4, distance: Float) -> ref<CP2077MapBasisProbe> {
    if IsDefined(this.CP2077MapBasis_Probe) {
        // An active or uncertain previous lifetime must be stopped explicitly.
        return null;
    }
    this.CP2077MapBasis_Probe = new CP2077MapBasisProbe();
    this.CP2077MapBasis_Probe.Start(this, origin, distance);
    return this.CP2077MapBasis_Probe;
}

@addMethod(PlayerPuppet)
public func CP2077MapBasis_Stop() -> Bool {
    if !IsDefined(this.CP2077MapBasis_Probe) { return true; }
    if !this.CP2077MapBasis_Probe.Stop() { return false; }
    this.CP2077MapBasis_Probe = null;
    return true;
}

@wrapMethod(PlayerPuppet)
protected cb func OnDetach() -> Bool {
    // Best effort only. The explicit experiment caller retains any pending
    // probe and retries Stop; this callback does not certify cleanup.
    this.CP2077MapBasis_Stop();
    return wrappedMethod();
}

@addMethod(WorldMapMenuGameController)
public func CP2077MapBasis_SpawnContainer() -> wref<inkWidget> {
    return this.GetSpawnContainer();
}

@addMethod(MinimapContainerController)
public func CP2077MapBasis_UnclampedContainer() -> wref<inkWidget> {
    return inkWidgetRef.Get(this.unclampedMappinContainer);
}

@addMethod(MinimapContainerController)
public func CP2077MapBasis_ClampedContainer() -> wref<inkWidget> {
    return inkWidgetRef.Get(this.clampedMappinContainer);
}

@addMethod(MinimapPOIMappinController)
public func CP2077MapBasis_Eligible() -> Bool {
    return !this.IsClamped();
}

@addMethod(BaseWorldMapMappinController)
public func CP2077MapBasis_Eligible() -> Bool {
    return !this.IsClamped() && !this.IsGrouped() && !this.IsCollection() && !this.IsInCollection()
        && this.isVisibleInFilterAndZoom && this.inZoomLevel;
}

@wrapMethod(MinimapPOIMappinController)
protected func Update() -> Void {
    wrappedMethod();
    let mappin = this.GetMappin();
    if IsDefined(mappin) {
        let data = mappin.GetScriptData() as CP2077MapBasisProbeData;
        if IsDefined(data) {
            data.minimap = this;
            if data.minimapUpdate < 4294967295u { data.minimapUpdate += 1u; }
        }
    }
}

@wrapMethod(BaseWorldMapMappinController)
protected func Update() -> Void {
    wrappedMethod();
    let mappin = this.GetMappin();
    if IsDefined(mappin) {
        let data = mappin.GetScriptData() as CP2077MapBasisProbeData;
        if IsDefined(data) {
            data.fullmap = this;
            if data.fullmapUpdate < 4294967295u { data.fullmapUpdate += 1u; }
        }
    }
}
