// EXPERIMENT ONLY. Read-only helper for the separate local CET fixture.
// The observed appearance name is not proof of mesh quality or animation.
@addMethod(Entity)
public func CP2077PassiveModelFixture_CurrentAppearance() -> String {
    return NameToString(this.GetCurrentAppearanceName());
}
