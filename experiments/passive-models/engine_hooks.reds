// EXPERIMENT ONLY. Read-only coherent evidence, never a color matching rule.
public class CP2077PassiveModelFixtureVisualState {
    public let valid: Bool;
    public let entityDecimal: String;
    public let contextDecimal: String;
    public let appearance: String;
    public let appearanceHash: String;
    public let color: String;
    public let colorHash: String;
}

// 1 = exact original native actor, 0 = unknown, -1 = positively different.
// Independent of cosmetic getters so unavailable color never blocks exact cleanup.
@addMethod(Entity)
public final func CP2077PassiveModelFixture_OwnedIdentity(context: ref<PlayerPuppet>, original: ref<Entity>, expected: EntityID) -> Int32 {
    let found: ref<Entity>;
    if !IsDefined(original) || !EntityID.IsDefined(expected) { return 0; };
    if this != original || this.GetEntityID() != expected || original.GetEntityID() != expected { return -1; };
    if !IsDefined(context) || !context.IsAttached() || !this.IsAttached() { return 0; };
    if GameInstance.FindEntityByID(context.GetGame(), context.GetEntityID()) != context { return 0; };
    found = GameInstance.FindEntityByID(context.GetGame(), expected);
    if !IsDefined(found) { return 0; };
    if found != original { return -1; };
    return 1;
}

@addMethod(Entity)
public final func CP2077PassiveModelFixture_CurrentVisualState(context: ref<PlayerPuppet>, originalContext: ref<PlayerPuppet>, originalActor: ref<Entity>, expected: EntityID) -> ref<CP2077PassiveModelFixtureVisualState> {
    let result: ref<CP2077PassiveModelFixtureVisualState> = new CP2077PassiveModelFixtureVisualState();
    let contextId: EntityID;
    let appearance: CName;
    let color: CName;
    if this.CP2077PassiveModelFixture_OwnedIdentity(context, originalActor, expected) != 1
        || !IsDefined(context) || !IsDefined(originalContext) || context != originalContext
        || !IsDefined(originalActor) || this != originalActor
        || !context.IsAttached() || !EntityID.IsDefined(expected)
        || !this.IsAttached() || this.GetEntityID() != expected { return result; };
    contextId = context.GetEntityID();
    if !EntityID.IsDefined(contextId)
        || GameInstance.FindEntityByID(context.GetGame(), contextId) != context
        || GameInstance.FindEntityByID(context.GetGame(), expected) != this { return result; };
    appearance = this.GetCurrentAppearanceName();
    color = this.GetCurrentColorVariantName();
    result.entityDecimal = ToString(EntityID.ToHash(expected));
    result.contextDecimal = ToString(EntityID.ToHash(contextId));
    result.appearance = NameToString(appearance);
    result.appearanceHash = ToString(NameToHash(appearance));
    result.color = NameToString(color);
    result.colorHash = ToString(NameToHash(color));
    result.valid = this == originalActor && context == originalContext
        && this.IsAttached() && this.GetEntityID() == expected
        && GameInstance.FindEntityByID(context.GetGame(), expected) == this
        && Equals(this.GetCurrentAppearanceName(), appearance)
        && Equals(this.GetCurrentColorVariantName(), color)
        && context.IsAttached() && context.GetEntityID() == contextId
        && GameInstance.FindEntityByID(context.GetGame(), contextId) == context;
    return result;
}
