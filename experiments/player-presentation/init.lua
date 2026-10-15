-- Opt-in CET folder only. Returning this API does not spawn or adopt an actor.
local Fixture=require("fixture")
local fixture=Fixture.new()
local previous,emitted=nil,0
registerForEvent("onUpdate",function(delta)
    fixture:update(delta)
    local s=fixture:status()
    local text=table.concat({s.generation,s.phase,s.reason or "",s.cleanupRoute or ""},"|")
    if text~=previous and emitted<64 then
        print("[PlayerActionFixture] "..text);previous=text;emitted=emitted+1
    end
end)
registerForEvent("onShutdown",function() fixture:shutdown() end)
return {
    start=function(pose)return fixture:start(pose)end,
    capture=function(generation)return fixture:capture(generation)end,
    aim=function(generation)return fixture:aim(generation)end,
    stop=function()return fixture:stop()end,
    status=function()return fixture:status()end
}
