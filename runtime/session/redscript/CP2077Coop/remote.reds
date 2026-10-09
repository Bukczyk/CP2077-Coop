// Judy is a temporary, non-persistent player rendering projection.
// NPC/world adoption must use server-issued SessionEntityId and authority records.
@addMethod(PlayerPuppet)
public func CP2077Session_SpawnProxy(tag: CName, x: Float, y: Float, z: Float) -> EntityID {
    let empty: EntityID;
    let system = GameInstance.GetDynamicEntitySystem();
    if !IsDefined(system) || !system.IsReady() || system.IsPopulated(tag) {
        return empty;
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
    return system.CreateEntity(spec);
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

// Actor-specific adapters. Never select a single global remote tag: each
// PlayerId owns its own command handle and engine projection.
@addField(NPCPuppet)
private let CP2077Session_motorCommand: ref<AICommand>;

@addMethod(NPCPuppet)
public func CP2077Session_MotorState(command: ref<AICommand>) -> Int32 {
    let controller = this.GetAIControllerComponent();
    if !IsDefined(controller) || !IsDefined(command) || NotEquals(command, this.CP2077Session_motorCommand) { return -1; }
    return EnumInt(controller.GetCommandState(command));
}

@addMethod(NPCPuppet)
public func CP2077Session_StartMove(x: Float, y: Float, z: Float, gait: Int32) -> ref<AIMoveToCommand> {
    let controller = this.GetAIControllerComponent();
    if !this.IsAttached() || !IsDefined(controller) || IsDefined(this.CP2077Session_motorCommand) { return null; }
    let target: WorldPosition;
    WorldPosition.SetVector4(target, new Vector4(x, y, z, 1.0));
    let position: AIPositionSpec;
    AIPositionSpec.SetWorldPosition(position, target);
    let command = new AIMoveToCommand();
    command.movementTarget = position;
    command.rotateEntityTowardsFacingTarget = false;
    command.ignoreNavigation = false;
    command.desiredDistanceFromTarget = 0.05;
    command.movementType = moveMovementType.Walk;
    if gait == 1 { command.movementType = moveMovementType.Run; }
    if gait == 2 { command.movementType = moveMovementType.Sprint; }
    command.useStart = false;
    command.useStop = false;
    command.finishWhenDestinationReached = false;
    command.alwaysUseStealth = false;
    if !controller.SendCommand(command) { return null; }
    this.CP2077Session_motorCommand = command;
    return command;
}

@addMethod(NPCPuppet)
public func CP2077Session_RetargetMove(command: ref<AIMoveToCommand>, x: Float, y: Float, z: Float, gait: Int32) -> Int32 {
    let state = this.CP2077Session_MotorState(command);
    if state != EnumInt(AICommandState.Executing) { return state; }
    let target: WorldPosition;
    WorldPosition.SetVector4(target, new Vector4(x, y, z, 1.0));
    let position: AIPositionSpec;
    AIPositionSpec.SetWorldPosition(position, target);
    command.movementTarget = position;
    command.movementType = moveMovementType.Walk;
    if gait == 1 { command.movementType = moveMovementType.Run; }
    if gait == 2 { command.movementType = moveMovementType.Sprint; }
    // Updating the command object alone did not keep the engine path current
    // in the live test. Refresh its active movement policy on this owned actor.
    let component = this.GetMovePolicesComponent();
    if !IsDefined(component) { return -1; }
    let policies = component.GetTopPolicies();
    if !IsDefined(policies) { return -1; }
    policies.SetDestinationPosition(new Vector4(x, y, z, 1.0));
    policies.SetMovementType(command.movementType);
    policies.SetUseStartStop(false, false);
    policies.SetDistancePolicy(0.05, 0.05);
    component.ChangeMovementType(command.movementType);
    return EnumInt(AICommandState.Executing);
}

@addMethod(NPCPuppet)
public func CP2077Session_StopMove(command: ref<AICommand>) -> Bool {
    let controller = this.GetAIControllerComponent();
    if !IsDefined(command) { return !IsDefined(this.CP2077Session_motorCommand); }
    if !IsDefined(controller) || NotEquals(command, this.CP2077Session_motorCommand) { return false; }
    let state = controller.GetCommandState(command);
    if NotEquals(state, AICommandState.Cancelled) && NotEquals(state, AICommandState.Interrupted) && NotEquals(state, AICommandState.Success) && NotEquals(state, AICommandState.Failure) {
        controller.StopExecutingCommand(command, false);
        controller.CancelCommand(command);
        state = controller.GetCommandState(command);
    }
    if NotEquals(state, AICommandState.Cancelled) && NotEquals(state, AICommandState.Interrupted) && NotEquals(state, AICommandState.Success) && NotEquals(state, AICommandState.Failure) { return false; }
    this.CP2077Session_motorCommand = null;
    return true;
}

@addMethod(NPCPuppet)
public func CP2077Session_SnapProxy(x: Float, y: Float, z: Float, yaw: Float) -> ref<AITeleportCommand> {
    let controller = this.GetAIControllerComponent();
    if !this.IsAttached() || !IsDefined(controller) || IsDefined(this.CP2077Session_motorCommand) { return null; }
    let command = new AITeleportCommand();
    command.position = new Vector4(x, y, z, 1.0);
    command.rotation = yaw;
    command.doNavTest = false;
    if !controller.SendCommand(command) { return null; }
    this.CP2077Session_motorCommand = command;
    return command;
}

@addMethod(NPCPuppet)
public func CP2077Session_TurnProxy(yaw: Float) -> ref<AIRotateToCommand> {
    let controller = this.GetAIControllerComponent();
    if !this.IsAttached() || !IsDefined(controller) || IsDefined(this.CP2077Session_motorCommand) { return null; }
    let angles: EulerAngles;
    angles.Yaw = yaw;
    let facing = EulerAngles.ToQuat(angles);
    let direction = Quaternion.GetForward(facing);
    let target: WorldPosition;
    WorldPosition.SetVector4(target, this.GetWorldPosition() + direction * 5.0);
    let position: AIPositionSpec;
    AIPositionSpec.SetWorldPosition(position, target);
    let command = new AIRotateToCommand();
    command.target = position;
    command.angleOffset = 0.0;
    command.angleTolerance = 3.0;
    command.speed = 2.0;
    if !controller.SendCommand(command) { return null; }
    this.CP2077Session_motorCommand = command;
    return command;
}
