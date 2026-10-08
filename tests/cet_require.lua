-- Test-only CET module loader model. This is not shipped and does not implement
-- the complete CET sandbox/security policy. Its path/error behavior is based on
-- https://github.com/maximegmd/CyberEngineTweaks/blob/v1.37.1/src/scripting/LuaSandbox.cpp#L381-L454
-- CET tries literal path, path.lua, path/init.lua; dots are NOT separators.
-- Missing/failed modules return nil,error instead of stock require's exception.
return function(root, transform)
    assert(type(root)=="string")
    local cache,loaded={},{}
    local env={assert=assert,error=error,type=type,tostring=tostring,tonumber=tonumber,
        pairs=pairs,ipairs=ipairs,next=next,select=select,pcall=pcall,
        string=string,table=table,math=math}
    local function requireCet(name)
        if type(name)~="string" or name=="" or name:find("%z") or name:find(":")
            or name:sub(1,1)=="/" or name:find("%.%.") then return nil,"invalid fixture path" end
        local literal=name:gsub("\\","/")
        local source,path
        for _,candidate in ipairs({literal,literal..".lua",literal.."/init.lua"}) do
            local file=io.open(root.."/"..candidate,"rb")
            if file then source,path=file:read("*a"),candidate;file:close();break end
        end
        if not path then return nil,"Tried to access invalid path '"..name.."'!" end
        if loaded[path] then return cache[path] end
        if transform then source=transform(name,source) end
        local chunk,reason
        if setfenv then -- LuaJIT/Lua 5.1, as used by CET.
            chunk,reason=loadstring(source,"@"..path)
            if chunk then setfenv(chunk,env) end
        else chunk,reason=load(source,"@"..path,"t",env) end
        if not chunk then return nil,reason end
        loaded[path]=true -- A circular require observes nil, matching CET.
        local ok,value=pcall(chunk)
        if not ok then return nil,value end
        cache[path]=value
        return value
    end
    env.require=requireCet
    return requireCet
end
