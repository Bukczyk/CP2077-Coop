-- Separate opt-in CET mod entrypoint. Loading registers callbacks, spawns nothing.
local Engine=require("engine")
local Fixture=require("fixture")
local function text(v)
    return string.format("%q",tostring(v):sub(1,256):gsub("[\r\n]"," "))
end
local function pose(p)
    if not p then return "unavailable" end
    local fields={}
    for _,k in ipairs({"x","y","z","yaw","qx","qy","qz","qw"}) do
        if p[k]~=nil then fields[#fields+1]=k.."="..text(p[k]) end
    end
    return "{"..table.concat(fields,",").."}"
end
local controller=Fixture.new(Engine.new(),function(slot,state,reason,s)
    local o=s.observed or {}
    -- Transition snapshots only, with a controller-wide limit of 64 lines.
    print("[PassiveModelFixture] slot="..text(slot).." state="..text(state)
        .." reason="..text(reason).." profile="..text(s.profile)
        .." generation="..text(s.generation).." entity="..text(s.entity)
        .." requestedAppearance="..text(s.requestedAppearance)
        .." observedAppearance="..text(s.observedAppearance).." appearanceVerified="..text(s.appearanceVerified)
        .." observedAppearanceHash="..text(s.observedAppearanceHash)
        .." observedColor="..text(s.observedColor).." observedColorHash="..text(s.observedColorHash)
        .." visualStateObserved="..text(s.visualStateObserved).." colorObserved="..text(s.colorObserved)
        .." identityVerified="..text(s.identityVerified).." identityFault="..text(s.identityFault)
        .." colorNameAvailable="..text(s.colorNameAvailable).." colorMatchVerified=false"
        .." requested="..pose(s.requestedTarget).." submitted="..pose(s.submittedTarget)
        .." observed="..pose(o.pose).." template="..text(o.template)
        .." templateHash="..text(o.templateHash).." templateVerified="..text(o.templateVerified)
        .." rootVerified="..text(o.rootVerified).." placementVerified="..text(s.placementVerified)
        .." visualQualified=false moveSubmission="..text(s.moveSubmission))
end)
registerForEvent("onUpdate",function() controller:pump() end)
registerForEvent("onShutdown",function()
    -- No engine mutation outside onUpdate. Stop and observe closed before
    -- unloading; if no further update runs, historical tags block replacement.
    controller:shutdown()
end)
return {
    start=function(slot,profile,pose) return controller:start(slot,profile,pose) end,
    status=function(slot) return controller:status(slot) end,
    stop=function(slot) return controller:stop(slot) end,
    move=function(slot,generation,pose) return controller:move(slot,generation,pose) end,
    reset=function() return controller:reset() end,
}
