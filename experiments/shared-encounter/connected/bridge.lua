-- Parser/helpers for the generic bridge, separate from CPEX1 diagnostic bodies.
local Codec=assert(require("connected/codec"), "Cannot load connected/codec")
local M={}
local function split(line)
    if type(line)~="string" or #line>2400 or line:find("[^%w_|]") then return nil end
    local p={}; for token in (line.."|"):gmatch("([^|]*)|") do p[#p+1]=token end
    return p
end
local function u32(s,zero)
    if type(s)~="string" or (s~="0" and not s:match("^[1-9]%d*$")) then return nil end
    local n=tonumber(s)
    if zero and n==0 then return 0 end
    return Codec.integer(n,4294967295) and n or nil
end
function M.opaque(value)
    if type(value)=="number" then return nil end
    local text=tostring(value)
    text=text:match("^(%d+)ULL$") or text
    return Codec.id(text) and text or nil
end
function M.scope(line)
    local p=split(line)
    if not p or #p~=6 or not Codec.id(p[1],true) or not Codec.id(p[3],true) then return nil end
    local epoch,self,host,phase=u32(p[2],true),u32(p[4],true),u32(p[5],true),u32(p[6],true)
    if not epoch or not self or not host or not phase or phase>5 then return nil end
    return {session=p[1],epoch=epoch,generation=p[3],self=self,host=host,phase=phase,active=phase==4}
end
function M.event(line)
    local p=split(line)
    if not p or not Codec.id(p[2]) or not u32(p[3]) or not Codec.id(p[4]) then return nil end
    local e={type=p[1],session=p[2],epoch=u32(p[3]),generation=p[4]}
    if e.type=="intent" and #p==8 and u32(p[5]) and Codec.id(p[6]) and u32(p[7])
        and tonumber(p[7])<=65535 and Codec.unhex(p[8]) then
        e.sender,e.event,e.kind,e.body=u32(p[5]),p[6],u32(p[7]),p[8]
    elseif e.type=="outcome" and #p==12 and u32(p[5]) and Codec.id(p[6]) and u32(p[7])
        and Codec.id(p[8]) and u32(p[9]) and tonumber(p[9])<=65535
        and u32(p[10]) and tonumber(p[10])>=2 and tonumber(p[10])<=5 and u32(p[11],true) and tonumber(p[11])<=65535
        and Codec.unhex(p[12]) then
        e.host,e.hostEvent,e.requester,e.requestEvent=u32(p[5]),p[6],u32(p[7]),p[8]
        e.kind,e.disposition,e.reason,e.body=u32(p[9]),u32(p[10]),u32(p[11],true),p[12]
    elseif (e.type=="sent_intent" or e.type=="sent_result") and #p==6 and Codec.id(p[5]) and Codec.id(p[6]) then
        e.ticket,e.event=p[5],p[6]
    elseif e.type=="status" and #p==8 and Codec.id(p[5]) and u32(p[6]) and tonumber(p[6])<=5
        and u32(p[7],true) and tonumber(p[7])<=65535 and (p[8]=="0" or p[8]=="1") then
        e.event,e.disposition,e.reason,e.committed=p[5],u32(p[6]),u32(p[7],true),p[8]=="1"
    else return nil end
    return e
end
function M.queued(line)
    if type(line)~="string" then return nil end
    local ticket=line:match("^queued|([1-9]%d*)$")
    return Codec.id(ticket) and ticket or nil
end
return M
