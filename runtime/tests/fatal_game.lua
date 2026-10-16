-- fatal_game.lua - a game whose system fails after a few ticks (the error
-- overlay's test: runtime/tests/run.lua "error overlay"). Not a demo.
local ecs = require("ecs")
local w = ecs.world()
local boom = ecs.system(function()
  return function(w, dt)
    local n = w:node("/data/count").c
    n.ticks = n.ticks + 1
    if n.ticks == 10 then
      local t = nil
      return t.x                                   -- (fails here: line 11)
    end
  end
end)
local fine = ecs.system(function()
  return function(w, dt)
    local n = w:node("/data/count").c
    n.fine = n.fine + 1
  end
end)
w:spawn("/data/count", { ticks = 0, fine = 0 })
w:spawn("/systems", { order = { "boom", "fine" } })
w:spawn("/systems/boom", { system = boom })
w:spawn("/systems/fine", { system = fine })
return w
