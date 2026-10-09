// Position markers belong to the receiving PlayerPuppet, never a proxy actor.
// CET supplies session-scoped membership and removes an old lifetime before
// reusing PlayerId. These handles never replace the navigation waypoint.
public class CP2077SessionPlayerMarkerData extends MappinScriptData {
    public let playerId: Uint32;
    // Coherent body-facing heading from the same pose, in radians. Retained for
    // later UI calibration; no facing arrow is rendered by this implementation.
    public let yawRadians: Float;
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
        entry.data.yawRadians = yaw;
        system.SetMappinScriptData(entry.mappinId, entry.data);
        system.SetMappinPosition(entry.mappinId, position);
        return true;
    }

    entry = new CP2077SessionPlayerMarkerEntry();
    entry.playerId = playerId;
    entry.data = new CP2077SessionPlayerMarkerData();
    entry.data.playerId = playerId;
    entry.data.yawRadians = yaw;
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
    let system = GameInstance.GetMappinSystem(this.GetGame());
    if !IsDefined(system) {
        return false;
    }
    let index = 0;
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
    wrappedMethod();
    CP2077SessionPlayerMarkerUI.ApplyIcon(this.GetMappin(), this.iconWidget);
}

@wrapMethod(BaseWorldMapMappinController)
protected func UpdateIcon() -> Void {
    wrappedMethod();
    CP2077SessionPlayerMarkerUI.ApplyIcon(this.GetMappin(), this.iconWidget);
}
