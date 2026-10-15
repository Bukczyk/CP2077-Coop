// Opt-in local disposable actor fixture. No session or protocol identity.
public class CP2077ActionFixture {
    public static func Same(left: ref<Entity>, right: ref<Entity>) -> Bool {
        return IsDefined(left) && IsDefined(right) && left == right;
    }

    public static func Context(current: ref<PlayerPuppet>, original: ref<PlayerPuppet>) -> Int32 {
        if !IsDefined(current) || !IsDefined(original) { return -1; }
        if current != original || current.GetEntityID() != original.GetEntityID() { return 0; }
        if !current.IsAttached() { return -1; }
        let found = GameInstance.FindEntityByID(current.GetGame(), current.GetEntityID());
        if !IsDefined(found) { return -1; }
        if found != original { return 0; }
        return 1;
    }

    // Exact references distinguish a new native actor from a new CET wrapper.
    // Missing lookup data is unknown; a positively different reference is foreign.
    public static func Actor(context: ref<PlayerPuppet>, original: ref<NPCPuppet>, expected: EntityID, population: ref<Entity>) -> Int32 {
        if !IsDefined(context) || !context.IsAttached() || !IsDefined(original) { return -1; }
        if original.GetEntityID() != expected || original.GetRecordID() != t"Character.Judy" { return 0; }
        let found = GameInstance.FindEntityByID(context.GetGame(), expected);
        if !IsDefined(found) || !IsDefined(population) || !original.IsAttached() { return -1; }
        if found != original || population != original { return 0; }
        return 1;
    }
}
