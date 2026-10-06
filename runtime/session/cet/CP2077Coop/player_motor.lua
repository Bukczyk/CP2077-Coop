-- Per-player game-thread actuator. Network interpolation already chose the
-- target: never predict that position a second time in the engine adapter.
local Motor = {}
Motor.__index = Motor
local function distance(a,b)
    local x,y,z=a.x-b.x,a.y-b.y,a.z-b.z
    return math.sqrt(x*x+y*y+z*z)
end
local function angle(a,b) return (a-b+180)%360-180 end
function Motor.new(actor)
    return setmetatable({actor=actor,clock=0,speed=0,nextCommand=0,nextSnap=0,
        nextTurn=0,commands=0,snaps=0,stalled=0,spawnWait=0},Motor)
end
function Motor:stop()
    if self.command then self.actor:CP2077Session_StopMove(self.command) end
    self.command=nil
end
function Motor:step(target,delta)
    if delta <= 0 or delta ~= delta then return end
    self.clock=self.clock+delta
    local current=self.actor:GetWorldPosition()
    local error=distance(current,target)
    self.error=error
    -- Newly streamed entities can briefly report the origin. Do not flood the
    -- controller before its placement has settled.
    if math.abs(current.x)+math.abs(current.y)+math.abs(current.z)<0.01 and
        math.abs(target.x)+math.abs(target.y)+math.abs(target.z)>1 and self.spawnWait<2 then
        self.spawnWait=self.spawnWait+delta; return
    end
    local jump=false
    if self.previous and delta<0.25 then
        local displacement=distance(target,self.previous)
        jump=displacement>6
        local raw=jump and 0 or math.min(30,displacement/delta)
        self.speed=self.speed+(raw-self.speed)*(1-math.exp(-delta/0.12))
    else self.speed=0 end
    self.previous={x=target.x,y=target.y,z=target.z}
    if self.observed and error>0.75 and distance(current,self.observed)<0.15*delta then
        self.stalled=self.stalled+delta
    else self.stalled=0 end
    self.observed={x=current.x,y=current.y,z=current.z}

    if (error>6 or math.abs(current.z-target.z)>1.5 or self.stalled>1.5 or jump) and self.clock>=self.nextSnap then
        self:stop()
        self.actor:CP2077Session_SnapProxy(target.x,target.y,target.z,math.deg(target.yaw))
        self.snaps=self.snaps+1
        self.nextSnap=self.clock+1
        self.nextCommand=self.clock+0.25
        self.stalled=0
        -- Success is judged next frame from GetWorldPosition, not this call.
        return
    end
    if self.clock<self.nextCommand then return end
    if error<0.20 and self.speed<0.25 then
        self:stop()
        local yaw=math.deg(target.yaw)
        local actual=self.actor:GetWorldOrientation():ToEulerAngles().yaw
        if math.abs(angle(yaw,actual))>5 and self.clock>=self.nextTurn then
            self.actor:CP2077Session_TurnProxy(yaw)
            self.nextTurn=self.clock+0.5
        end
        return
    end
    local pace=self.speed+math.min(2,error*0.6)
    local gait=pace>4.5 and "Sprint" or (pace>1.8 and "Run" or "Walk")
    -- Keep the current gait around thresholds instead of restarting every frame.
    if self.gait=="Sprint" and pace>4.0 then gait="Sprint"
    elseif self.gait=="Run" and pace>1.4 and pace<4.8 then gait="Run" end
    if self.command and gait==self.gait then
        local state=self.actor:CP2077Session_RetargetMove(self.command,target.x,target.y,target.z)
        if state==2 then
            self.nextCommand=self.clock+0.08
            return
        end
        if (state==0 or state==1) and self.clock-self.issued<1 then return end
    end
    self:stop()
    self.command=self.actor:CP2077Session_StartMove(target.x,target.y,target.z,({Walk=0,Run=1,Sprint=2})[gait])
    self.gait,self.issued=gait,self.clock
    self.nextCommand=self.clock+0.25
    self.commands=self.commands+1
end
return Motor
