local root=assert(arg[1])
package.path=root.."/runtime/session/cet/CP2077Coop/?.lua;"..package.path
Game=nil
local reader=require("npc_life_frame") -- Loading must not query the game.
local function opaque(text)return setmetatable({},{__tostring=function()return text end})end
local entity=opaque("9007199254740993ULL")
local foreign=opaque("9007199254740994ULL")
local function fixture()
    local f={known=true,health=75,maxHealth=100,status=1,revision=1,entity=entity,reads=0}
    Game={
        CP2077Session_NpcLifeKnown=function()return f.known end,
        CP2077Session_NpcEntity=function()return f.entity end,
        CP2077Session_NpcLifeHealth=function()f.reads=f.reads+1;return f.health end,
        CP2077Session_NpcLifeMaxHealth=function()return f.maxHealth end,
        CP2077Session_NpcLifeStatus=function()return f.status end,
        CP2077Session_NpcLifeRevision=function()return f.revision end,
    }
    return f
end
local f=fixture();local first=assert(reader.read(entity))
assert(first.entity==entity and first.health==75 and first.maxHealth==100 and first.status==1 and first.revision==1)
for _,status in ipairs({2,3})do
    f.health,f.status,f.revision=0,status,status
    local v=assert(reader.read(entity));assert(v.health==0 and v.status==status and v.revision==status)
end
assert(first.health==75 and first.status==1,"read data is a value copy")
f.known=false;local prior=f.reads;assert(reader.read(entity)==nil and f.reads==prior,"unknown is absent, not manufactured Alive")
for _,unknown in ipairs({0,"true",{}})do f.known=unknown;assert(reader.read(entity)==nil)end
f=fixture();f.entity=foreign;assert(reader.read(entity)==nil,"adjacent opaque identities must never match")
for _,bad in ipairs({"0ULL","18446744073709551616ULL","01ULL","nan"})do
    assert(reader.read(opaque(bad))==nil)
end
assert(reader.read(9007199254740992)==nil,"lossy numeric identities cannot select life state")
for field,values in pairs({health={-1,101,0/0,math.huge,"75"},maxHealth={0,-1,10000001,0/0,math.huge},
    status={0,4,1.5,"1"},revision={0,-1,1.5,4294967296,"1"}})do
    for _,bad in ipairs(values)do f=fixture();f[field]=bad;assert(reader.read(entity)==nil,field.." must fail closed")end
end
-- Keep the existing typed meaning: health zero alone does not infer death.
f=fixture();f.health=0;assert(reader.read(entity).status==1)
f=fixture();local count=0
Game.CP2077Session_NpcLifeRevision=function()count=count+1;return count end
assert(reader.read(entity)==nil,"mixed revisions cannot form an admitted frame")
f=fixture();count=0
Game.CP2077Session_NpcEntity=function()count=count+1;return count==1 and entity or foreign end
assert(reader.read(entity)==nil,"selection changed while reading")
f=fixture();count=0
Game.CP2077Session_NpcLifeKnown=function()count=count+1;return count==1 end
assert(reader.read(entity)==nil,"baseline vanished while reading")
for _,name in ipairs({"CP2077Session_NpcLifeKnown","CP2077Session_NpcLifeHealth","CP2077Session_NpcLifeMaxHealth", 
    "CP2077Session_NpcLifeStatus","CP2077Session_NpcLifeRevision","CP2077Session_NpcEntity"})do
    fixture();Game[name]=nil;assert(reader.read(entity)==nil,"older DLL/missing API is unavailable")
    fixture();Game[name]=function()error("injected getter failure")end
    assert(reader.read(entity)==nil,"getter failure is not death")
end
print("NPC life frame: exact opaque identity, known/unknown, typed values and coherent read checks passed")
