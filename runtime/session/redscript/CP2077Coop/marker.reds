// Position markers belong to the receiving PlayerPuppet, never a proxy actor.
// CET supplies session-scoped membership and removes an old lifetime before
// reusing PlayerId. These handles never replace the navigation waypoint.
public class CP2077SessionPlayerMarkerData extends MappinScriptData {
    public let playerId: Uint32;
    // Coherent body-facing heading from the same pose, in radians. Retained for
    // the opt-in UI calibration fixture. Normal marker updates never draw it.
    public let yawRadians: Float;
    public let poseRevision: Uint32;
    public let owner: wref<PlayerPuppet>;
    public let facingAllowed: Bool;
    public let facingPreviews: array<wref<CP2077SessionMarkerFacingPreview>>;

    public func ClearFacingPreviews() -> Void {
        let previews = this.facingPreviews;
        ArrayClear(this.facingPreviews);
        let index = 0;
        while index < ArraySize(previews) {
            if IsDefined(previews[index]) {
                previews[index].Hide();
            }
            index += 1;
        }
    }
}

public class CP2077SessionPlayerMarkerEntry extends IScriptable {
    public let playerId: Uint32;
    public let mappinId: NewMappinID;
    public let data: ref<CP2077SessionPlayerMarkerData>;
}

@addField(PlayerPuppet)
private let CP2077Session_PlayerMarkers: array<ref<CP2077SessionPlayerMarkerEntry>>;

@addMethod(PlayerPuppet)
private func CP2077Session_FindPlayerMarker(playerId: Uint32) -> Int32 {
    let index = 0;
    while index < ArraySize(this.CP2077Session_PlayerMarkers) {
        if this.CP2077Session_PlayerMarkers[index].playerId == playerId {
            return index;
        }
        index += 1;
    }
    return -1;
}

@addMethod(PlayerPuppet)
public func CP2077Session_SetPlayerMarker(playerId: Uint32, x: Float, y: Float, z: Float, yaw: Float) -> Bool {
    // Match the existing protocol transform bounds. Positive comparisons also
    // reject NaN and infinities before touching a previously valid marker.
    if !this.IsAttached() || playerId == 0u || !(x >= -1000000.0 && x <= 1000000.0
        && y >= -1000000.0 && y <= 1000000.0
        && z >= -1000000.0 && z <= 1000000.0
        && yaw >= -6.283186 && yaw <= 6.283186) {
        return false;
    }
    let system = GameInstance.GetMappinSystem(this.GetGame());
    if !IsDefined(system) {
        return false;
    }
    let index = this.CP2077Session_FindPlayerMarker(playerId);
    let position = new Vector4(x, y, z, 1.0);
    let entry: ref<CP2077SessionPlayerMarkerEntry>;
    if index >= 0 {
        entry = this.CP2077Session_PlayerMarkers[index];
        entry.data.ClearFacingPreviews();
        if entry.data.poseRevision < 4294967295u {
            entry.data.poseRevision += 1u;
        }
        entry.data.yawRadians = yaw;
        entry.data.facingAllowed = true;
        system.SetMappinScriptData(entry.mappinId, entry.data);
        system.SetMappinPosition(entry.mappinId, position);
        return true;
    }

    entry = new CP2077SessionPlayerMarkerEntry();
    entry.playerId = playerId;
    entry.data = new CP2077SessionPlayerMarkerData();
    entry.data.playerId = playerId;
    entry.data.yawRadians = yaw;
    entry.data.poseRevision = 1u;
    entry.data.owner = this;
    let data: MappinData;
    // The generic controller accepts position-only mappins. CPO_RemotePlayerVariant
    // requires a RemotePlayerMappin and must not be used with RegisterMappin.
    data.mappinType = t"Mappins.CustomPositionMappinDefinition";
    data.variant = gamedataMappinVariant.CustomPositionVariant;
    data.active = true;
    data.debugCaption = "Co-op teammate " + ToString(playerId);
    data.visibleThroughWalls = true;
    data.scriptData = entry.data;
    entry.mappinId = system.RegisterMappin(data, position);
    // Native PlayerPuppet.UnregisterRemoteMappin uses value != Uint64(0).
    if entry.mappinId.value == Cast<Uint64>(0) {
        return false;
    }
    entry.data.facingAllowed = true;
    ArrayPush(this.CP2077Session_PlayerMarkers, entry);
    return true;
}

@addMethod(PlayerPuppet)
public func CP2077Session_RemovePlayerMarker(playerId: Uint32) -> Bool {
    if playerId == 0u {
        return false;
    }
    let index = this.CP2077Session_FindPlayerMarker(playerId);
    if index < 0 {
        return true;
    }
    this.CP2077Session_PlayerMarkers[index].data.facingAllowed = false;
    this.CP2077Session_PlayerMarkers[index].data.ClearFacingPreviews();
    let system = GameInstance.GetMappinSystem(this.GetGame());
    if !IsDefined(system) {
        return false;
    }
    system.UnregisterMappin(this.CP2077Session_PlayerMarkers[index].mappinId);
    ArrayErase(this.CP2077Session_PlayerMarkers, index);
    return true;
}

@addMethod(PlayerPuppet)
public func CP2077Session_ClearPlayerMarkers() -> Bool {
    if ArraySize(this.CP2077Session_PlayerMarkers) == 0 {
        return true;
    }
    let index = 0;
    while index < ArraySize(this.CP2077Session_PlayerMarkers) {
        this.CP2077Session_PlayerMarkers[index].data.facingAllowed = false;
        this.CP2077Session_PlayerMarkers[index].data.ClearFacingPreviews();
        index += 1;
    }
    let system = GameInstance.GetMappinSystem(this.GetGame());
    if !IsDefined(system) {
        return false;
    }
    index = 0;
    while index < ArraySize(this.CP2077Session_PlayerMarkers) {
        system.UnregisterMappin(this.CP2077Session_PlayerMarkers[index].mappinId);
        index += 1;
    }
    ArrayClear(this.CP2077Session_PlayerMarkers);
    return true;
}

@wrapMethod(PlayerPuppet)
protected cb func OnDetach() -> Bool {
    this.CP2077Session_ClearPlayerMarkers();
    return wrappedMethod();
}

public class CP2077SessionPlayerMarkerUI extends IScriptable {
    public static func ApplyIcon(mappin: wref<IMappin>, iconWidget: inkImageRef) -> Void {
        if !IsDefined(mappin) || !inkWidgetRef.IsValid(iconWidget) {
            return;
        }
        let marker = mappin.GetScriptData() as CP2077SessionPlayerMarkerData;
        if !IsDefined(marker) || marker.playerId == 0u {
            return;
        }
        let icon = TweakDBInterface.GetUIIconRecord(t"MappinIcons.NPCMappin");
        if !IsDefined(icon) {
            return;
        }
        // The shipped record's part is "npc" in mappin_icons.inkatlas. Change
        // only an existing part of this widget's atlas, preserving the standard
        // marker when the installed widget cannot resolve the person symbol.
        if inkImageRef.IsTexturePartExist(iconWidget, icon.AtlasPartName()) {
            inkImageRef.SetTexturePart(iconWidget, icon.AtlasPartName());
        }
    }
}

@wrapMethod(MinimapPOIMappinController)
protected func UpdateIcon() -> Void {
    this.CP2077Session_ClearFacingPreview();
    wrappedMethod();
    CP2077SessionPlayerMarkerUI.ApplyIcon(this.GetMappin(), this.iconWidget);
}

@wrapMethod(BaseWorldMapMappinController)
protected func UpdateIcon() -> Void {
    this.CP2077Session_ClearFacingPreview();
    wrappedMethod();
    CP2077SessionPlayerMarkerUI.ApplyIcon(this.GetMappin(), this.iconWidget);
}

// Calibration fixture only. No automatic world-to-map basis is known. Each
// call must supply a new sample in this exact controller root's coordinates.
// A normal icon refresh or pose change invalidates the one-shot preview.
public class CP2077SessionMarkerFacingPreview extends IScriptable {
    private let marker: wref<CP2077SessionPlayerMarkerData>;
    private let root: wref<inkCompoundWidget>;
    private let arrow: ref<inkCanvas>;
    private let fade: ref<inkAnimProxy>;
    private let lastSampleToken: Uint32;

    public func Hide() -> Void {
        if IsDefined(this.marker) {
            ArrayRemove(this.marker.facingPreviews, this);
            this.marker = null;
        }
        if IsDefined(this.fade) {
            this.fade.UnregisterFromCallback(inkanimEventType.OnFinish, this, n"OnFadeFinished");
            this.fade.Stop(true);
            this.fade = null;
        }
        if IsDefined(this.arrow) {
            this.arrow.SetVisible(false);
            if IsDefined(this.root) {
                this.root.RemoveChild(this.arrow);
            }
            this.arrow = null;
        }
        this.root = null;
    }

    protected cb func OnFadeFinished(proxy: ref<inkAnimProxy>) -> Bool {
        // An old animation must not remove a newer sample.
        if proxy == this.fade {
            this.Hide();
        }
        return true;
    }

    private static func Bounded(value: Float) -> Bool {
        return value >= -10000.0 && value <= 10000.0;
    }

    private static func AddStroke(parent: ref<inkCanvas>, x: Float, y: Float, length: Float, degrees: Float) -> Void {
        let stroke = new inkRectangle();
        stroke.SetName(n"CP2077Session_FacingStroke");
        stroke.SetSize(2.0, length);
        stroke.SetAnchorPoint(0.5, 0.5);
        stroke.SetMargin(x, y, 0.0, 0.0);
        stroke.SetRenderTransformPivot(0.5, 0.5);
        stroke.SetRotation(degrees);
        stroke.SetTintColor(new HDRColor(0.31, 0.94, 1.0, 1.0));
        stroke.SetInteractive(false);
        stroke.Reparent(parent);
    }

    public func Show(mappin: wref<IMappin>, rootWidget: wref<inkWidget>, expectedRoot: wref<inkWidget>, expectedData: ref<CP2077SessionPlayerMarkerData>, expectedPoseRevision: Uint32, sampleToken: Uint32, worldXx: Float, worldXy: Float, worldYx: Float, worldYy: Float, rotationSign: Float, zeroDegrees: Float) -> Bool {
        this.Hide();
        if !IsDefined(mappin) || !IsDefined(expectedData) || sampleToken <= this.lastSampleToken {
            return false;
        }
        // Consume even rejected tokens so stale retries cannot resurrect an arrow.
        this.lastSampleToken = sampleToken;
        let marker = mappin.GetScriptData() as CP2077SessionPlayerMarkerData;
        let parent = rootWidget as inkCompoundWidget;
        if !IsDefined(marker) || marker != expectedData || marker.playerId == 0u
            || expectedPoseRevision == 0u || expectedPoseRevision == 4294967295u || marker.poseRevision != expectedPoseRevision
            || !marker.facingAllowed || !IsDefined(marker.owner) || !marker.owner.IsAttached()
            || !IsDefined(parent) || parent != expectedRoot || !parent.IsVisible() {
            return false;
        }
        if !CP2077SessionMarkerFacingPreview.Bounded(worldXx) || !CP2077SessionMarkerFacingPreview.Bounded(worldXy)
            || !CP2077SessionMarkerFacingPreview.Bounded(worldYx) || !CP2077SessionMarkerFacingPreview.Bounded(worldYy)
            || !(rotationSign == 1.0 || rotationSign == -1.0) || !(zeroDegrees >= -180.0 && zeroDegrees <= 180.0) {
            return false;
        }
        let xLength = worldXx * worldXx + worldXy * worldXy;
        let yLength = worldYx * worldYx + worldYy * worldYy;
        let determinant = worldXx * worldYy - worldYx * worldXy;
        if xLength < 0.00000001 || yLength < 0.00000001
            || determinant * determinant < 0.000001 * xLength * yLength {
            return false;
        }
        // Native conversion owns Euler handedness. Do not substitute movement
        // direction or a sin/cos guess for the received body-facing yaw.
        let rotation: EulerAngles;
        rotation.Yaw = Rad2Deg(marker.yawRadians);
        let forward = Quaternion.GetForward(EulerAngles.ToQuat(rotation));
        let dx = worldXx * forward.X + worldYx * forward.Y;
        let dy = worldXy * forward.X + worldYy * forward.Y;
        let degrees = rotationSign * Rad2Deg(AtanF(dx, -dy)) + zeroDegrees;
        this.root = parent;
        this.arrow = new inkCanvas();
        this.arrow.SetName(n"CP2077Session_FacingPreview");
        this.arrow.SetSize(40.0, 40.0);
        this.arrow.SetAnchor(inkEAnchor.Centered);
        this.arrow.SetAnchorPoint(0.5, 0.5);
        this.arrow.SetRenderTransformPivot(0.5, 0.5);
        this.arrow.SetInteractive(false);
        this.arrow.SetRotation(degrees);
        CP2077SessionMarkerFacingPreview.AddStroke(this.arrow, 20.0, 9.0, 12.0, 0.0);
        CP2077SessionMarkerFacingPreview.AddStroke(this.arrow, 17.5, 5.5, 8.0, 45.0);
        CP2077SessionMarkerFacingPreview.AddStroke(this.arrow, 22.5, 5.5, 8.0, -45.0);
        this.arrow.Reparent(parent);

        // UI animation time is explicitly independent of time dilation. Also
        // removed on every UpdateIcon, without relying on game/simulation time.
        let alpha = new inkAnimTransparency();
        alpha.SetStartTransparency(1.0);
        alpha.SetEndTransparency(0.0);
        alpha.SetDuration(0.15);
        let animation = new inkAnimDef();
        animation.AddInterpolator(alpha);
        let options: inkAnimOptions;
        options.dependsOnTimeDilation = false;
        options.applyCustomTimeDilation = false;
        this.fade = this.arrow.PlayAnimationWithOptions(animation, options);
        if !IsDefined(this.fade) {
            this.Hide();
            return false;
        }
        this.fade.RegisterToCallback(inkanimEventType.OnFinish, this, n"OnFadeFinished");
        // A dead controller may have disappeared without an icon refresh.
        let index = ArraySize(marker.facingPreviews) - 1;
        while index >= 0 {
            if !IsDefined(marker.facingPreviews[index]) {
                ArrayErase(marker.facingPreviews, index);
            }
            index -= 1;
        }
        this.marker = marker;
        ArrayPush(marker.facingPreviews, this);
        return true;
    }
}

@addField(MinimapPOIMappinController)
private let CP2077Session_FacingPreview: ref<CP2077SessionMarkerFacingPreview>;

@addField(BaseWorldMapMappinController)
private let CP2077Session_FacingPreview: ref<CP2077SessionMarkerFacingPreview>;

@addField(MinimapPOIMappinController)
private let CP2077Session_FacingGeneration: Uint32;

@addField(BaseWorldMapMappinController)
private let CP2077Session_FacingGeneration: Uint32;

@addMethod(MinimapPOIMappinController)
public func CP2077Session_GetFacingPreviewGeneration() -> Uint32 {
    return this.CP2077Session_FacingGeneration;
}

@addMethod(BaseWorldMapMappinController)
public func CP2077Session_GetFacingPreviewGeneration() -> Uint32 {
    return this.CP2077Session_FacingGeneration;
}

@addMethod(MinimapPOIMappinController)
public func CP2077Session_ClearFacingPreview() -> Void {
    // Saturate rather than wrap into a generation from an earlier lifetime.
    if this.CP2077Session_FacingGeneration < 4294967295u {
        this.CP2077Session_FacingGeneration += 1u;
    }
    if IsDefined(this.CP2077Session_FacingPreview) {
        this.CP2077Session_FacingPreview.Hide();
    }
}

@addMethod(BaseWorldMapMappinController)
public func CP2077Session_ClearFacingPreview() -> Void {
    if this.CP2077Session_FacingGeneration < 4294967295u {
        this.CP2077Session_FacingGeneration += 1u;
    }
    if IsDefined(this.CP2077Session_FacingPreview) {
        this.CP2077Session_FacingPreview.Hide();
    }
}

@addMethod(MinimapPOIMappinController)
public func CP2077Session_PreviewFacingBasis(expectedRoot: wref<inkWidget>, expectedData: ref<CP2077SessionPlayerMarkerData>, expectedPoseRevision: Uint32, sampleToken: Uint32, worldXx: Float, worldXy: Float, worldYx: Float, worldYy: Float, rotationSign: Float, zeroDegrees: Float) -> Bool {
    if IsDefined(this.CP2077Session_FacingPreview) {
        this.CP2077Session_FacingPreview.Hide();
    }
    if sampleToken == 0u || sampleToken != this.CP2077Session_FacingGeneration
        || sampleToken == 4294967295u || this.IsClamped() {
        return false;
    }
    if !IsDefined(this.CP2077Session_FacingPreview) {
        this.CP2077Session_FacingPreview = new CP2077SessionMarkerFacingPreview();
    }
    return this.CP2077Session_FacingPreview.Show(this.GetMappin(), this.GetRootWidget(), expectedRoot, expectedData, expectedPoseRevision, sampleToken, worldXx, worldXy, worldYx, worldYy, rotationSign, zeroDegrees);
}

@addMethod(BaseWorldMapMappinController)
public func CP2077Session_PreviewFacingBasis(expectedRoot: wref<inkWidget>, expectedData: ref<CP2077SessionPlayerMarkerData>, expectedPoseRevision: Uint32, sampleToken: Uint32, worldXx: Float, worldXy: Float, worldYx: Float, worldYy: Float, rotationSign: Float, zeroDegrees: Float) -> Bool {
    if IsDefined(this.CP2077Session_FacingPreview) {
        this.CP2077Session_FacingPreview.Hide();
    }
    if sampleToken == 0u || sampleToken != this.CP2077Session_FacingGeneration || sampleToken == 4294967295u
        || this.IsClamped() || this.IsGrouped() || this.IsCollection() || this.IsInCollection() {
        return false;
    }
    if !IsDefined(this.CP2077Session_FacingPreview) {
        this.CP2077Session_FacingPreview = new CP2077SessionMarkerFacingPreview();
    }
    return this.CP2077Session_FacingPreview.Show(this.GetMappin(), this.GetRootWidget(), expectedRoot, expectedData, expectedPoseRevision, sampleToken, worldXx, worldXy, worldYx, worldYy, rotationSign, zeroDegrees);
}
