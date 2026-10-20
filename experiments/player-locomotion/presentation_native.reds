// LOCAL experimental compatibility domain0x8005 ONLY. Never install with v5 DLL.
// All calls run on the game thread. Opaque IDs/records stay native, not Lua numbers.
public native func CP2077Presentation_Version() -> Uint32;
public native func CP2077Presentation_IsIgla(record: TweakDBID) -> Bool;
public native func CP2077Presentation_RecordsEqual(left: TweakDBID, right: TweakDBID) -> Bool;
public native func CP2077Presentation_Push(session: Uint64, epoch: Uint32, generation: Uint64, stance: Uint32, weapon: Uint32, record: TweakDBID, aim: Uint32) -> Uint32;
public native func CP2077Presentation_Read() -> String;
