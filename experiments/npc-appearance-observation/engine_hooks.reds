// Opt-in observation only. No spawn, adoption, state changes or network calls.
public class CP2077NpcAppearanceObservationSnapshot {
  public let valid: Bool;
  public let reason: String;
  public let contextDecimal: String;
  public let entityDecimal: String;
  public let recordDecimal: String;
  public let templateHash: String;
  public let templatePath: String;
  public let appearance: String;
  public let appearanceHash: String;
  public let color: String;
  public let colorHash: String;
}

// Reference comparisons happen natively, never by comparing CET Lua wrappers.
@addMethod(PlayerPuppet)
public final func CP2077NpcAppearanceObservation_ContextIdentity(other: ref<PlayerPuppet>) -> String {
  let id: EntityID = this.GetEntityID();
  if !IsDefined(other) || this != other || !this.IsAttached() || !EntityID.IsDefined(id) {
    return "";
  };
  if GameInstance.FindEntityByID(this.GetGame(), id) != this { return ""; };
  return ToString(EntityID.ToHash(id));
}

@addMethod(Entity)
public final func CP2077NpcAppearanceObservation_Identity(context: ref<PlayerPuppet>) -> String {
  let npc: ref<NPCPuppet> = this as NPCPuppet;
  let id: EntityID = this.GetEntityID();
  if !IsDefined(context) || !context.IsAttached() || !IsDefined(npc)
    || !this.IsAttached() || !EntityID.IsDefined(id) { return ""; };
  if GameInstance.FindEntityByID(context.GetGame(), id) != this { return ""; };
  return ToString(EntityID.ToHash(id));
}

@addMethod(Entity)
public final func CP2077NpcAppearanceObservation_Capture(context: ref<PlayerPuppet>, expected: EntityID) -> ref<CP2077NpcAppearanceObservationSnapshot> {
  let result: ref<CP2077NpcAppearanceObservationSnapshot> = new CP2077NpcAppearanceObservationSnapshot();
  let npc: ref<NPCPuppet>;
  let contextId: EntityID;
  let recordId: TweakDBID;
  let template: ResRef;
  let appearance: CName;
  let color: CName;
  result.reason = "context_unavailable";
  if !IsDefined(context) { return result; };
  contextId = context.GetEntityID();
  if !context.IsAttached() || !EntityID.IsDefined(contextId)
    || GameInstance.FindEntityByID(context.GetGame(), contextId) != context { return result; };
  npc = this as NPCPuppet;
  result.reason = "unsupported_root";
  if !IsDefined(npc) { return result; };
  result.reason = "target_unavailable";
  if !EntityID.IsDefined(expected) || !this.IsAttached() || this.GetEntityID() != expected
    || GameInstance.FindEntityByID(context.GetGame(), expected) != this { return result; };

  recordId = npc.GetRecordID();
  template = this.GetTemplatePath();
  appearance = this.GetCurrentAppearanceName();
  color = this.GetCurrentColorVariantName();
  result.contextDecimal = ToString(EntityID.ToHash(contextId));
  result.entityDecimal = ToString(EntityID.ToHash(expected));
  result.recordDecimal = ToString(TDBID.ToNumber(recordId));
  result.templateHash = ToString(ResRef.GetHash(template));
  result.templatePath = ResRef.ToString(template);
  result.appearance = NameToString(appearance);
  result.appearanceHash = ToString(NameToHash(appearance));
  result.color = NameToString(color);
  result.colorHash = ToString(NameToHash(color));

  result.reason = "incoherent_capture";
  if !this.IsAttached() || this.GetEntityID() != expected
    || GameInstance.FindEntityByID(context.GetGame(), expected) != this
    || npc.GetRecordID() != recordId
    || ResRef.GetHash(this.GetTemplatePath()) != ResRef.GetHash(template)
    || !Equals(this.GetCurrentAppearanceName(), appearance)
    || !Equals(this.GetCurrentColorVariantName(), color)
    || !context.IsAttached() || context.GetEntityID() != contextId
    || GameInstance.FindEntityByID(context.GetGame(), contextId) != context { return result; };
  result.reason = "unknown_record_or_template";
  if Equals(result.recordDecimal, "0") || Equals(result.templateHash, "0") { return result; };
  // None/zero-hash CNames are observations, not invented default appearances.
  result.valid = true;
  result.reason = "captured";
  return result;
}
