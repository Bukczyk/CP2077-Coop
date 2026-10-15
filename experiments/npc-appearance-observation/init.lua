-- Separate opt-in CET mod, excluded from normal runtime/packages.
local Observer = require("observer")
local observer = Observer.new({ getGame = function() return Game end, log = print })
local api = {}
function api.request(label, actor) return observer:request(label, actor) end
function api.status(label) return observer:status(label) end
function api.reset() return observer:reset() end
registerForEvent("onUpdate", function(dt) observer:update(dt) end)
registerForEvent("onShutdown", function() observer:close() end)
return api
