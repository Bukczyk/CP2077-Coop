// Matched with the typed session plugin. Never install alongside legacy natives.reds.
public native func CP2077Session_SetActive(active: Bool) -> Void;
public native func CP2077Session_PushLocal(x: Float, y: Float, z: Float, yawRadians: Float) -> Void;
public native func CP2077Session_BeginFrame() -> Uint32;
public native func CP2077Session_Select(index: Uint32) -> Bool;
public native func CP2077Session_Bind(entity: Uint64, local: EntityID) -> Bool;
public native func CP2077Session_Phase() -> Uint32;
public native func CP2077Session_Generation() -> Uint64;
public native func CP2077Session_Host() -> Uint32;
public native func CP2077Session_Self() -> Uint32;
public native func CP2077Session_Session() -> Uint64;
public native func CP2077Session_Entity() -> Uint64;
public native func CP2077Session_Player() -> Uint32;
public native func CP2077Session_X() -> Float;
public native func CP2077Session_Y() -> Float;
public native func CP2077Session_Z() -> Float;
public native func CP2077Session_Yaw() -> Float;
public native func CP2077Session_SelfEntity() -> Uint64;
