// Judy is a temporary, non-persistent player rendering projection.
// NPC/world adoption must use server-issued SessionEntityId and authority records.
@addMethod(PlayerPuppet)
public func CP2077Session_SpawnProxy(tag: CName, x: Float, y: Float, z: Float) -> Void {
    let system = GameInstance.GetDynamicEntitySystem();
    if !IsDefined(system) || !system.IsReady() || system.IsPopulated(tag) {
        return;
    }
    let position: Vector4;
    position.X = x;
    position.Y = y;
    position.Z = z;
    position.W = 1.0;
    let spec = new DynamicEntitySpec();
    spec.recordID = t"Character.Judy";
    spec.position = position;
    spec.orientation = this.GetWorldOrientation();
    spec.persistState = false;
    spec.persistSpawn = false;
    spec.alwaysSpawned = true;
    spec.spawnInView = true;
    spec.active = true;
    spec.tags = [n"CP2077Session.Projection", tag];
    system.CreateEntity(spec);
}

// Exact player-proxy actor only. SendCommand acceptance is not proof that its
// transform moved; the CET owner observes placement and bounds retries.
@addMethod(NPCPuppet)
public func CP2077Session_PoseReady() -> Bool {
    return this.IsAttached() && IsDefined(this.GetAIControllerComponent());
}

@addMethod(NPCPuppet)
public func CP2077Session_SubmitPose(x: Float, y: Float, z: Float, yawDegrees: Float) -> ref<AITeleportCommand> {
    let controller = this.GetAIControllerComponent();
    if !this.IsAttached() || !IsDefined(controller) { return null; }
    let command = new AITeleportCommand();
    command.position = new Vector4(x, y, z, 1.0);
    command.rotation = yawDegrees;
    command.doNavTest = false;
    if !controller.SendCommand(command) { return null; }
    return command;
}

@addMethod(NPCPuppet)
public func CP2077Session_PoseState(command: ref<AITeleportCommand>) -> Int32 {
    let controller = this.GetAIControllerComponent();
    if !IsDefined(controller) || !IsDefined(command) { return -1; }
    return EnumInt(controller.GetCommandState(command));
}

@addMethod(NPCPuppet)
public func CP2077Session_StopPose(command: ref<AITeleportCommand>) -> Bool {
    let controller = this.GetAIControllerComponent();
    if !IsDefined(command) { return true; }
    if !IsDefined(controller) { return false; }
    let state = controller.GetCommandState(command);
    // NotExecuting can precede Enqueued after an accepted submission. It is
    // not evidence that the scheduled command has been retired.
    if NotEquals(state, AICommandState.Cancelled) && NotEquals(state, AICommandState.Interrupted) && NotEquals(state, AICommandState.Success) && NotEquals(state, AICommandState.Failure) {
        controller.StopExecutingCommand(command, false);
        controller.CancelCommand(command);
        state = controller.GetCommandState(command);
    }
    return Equals(state, AICommandState.Cancelled) || Equals(state, AICommandState.Interrupted) || Equals(state, AICommandState.Success) || Equals(state, AICommandState.Failure);
}
