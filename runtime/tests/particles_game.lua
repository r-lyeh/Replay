-- particles_game.lua - a test scene: effects in 2D (runtime/tests: the "particles" suite): a node's particles, the
-- emitter where the node is; one moving (its trail), one added, one squares.
local ecs = require("ecs")
local w = ecs.world()
w:spawn("/config", { window = { w = 320, h = 200 } })
w:spawn("/objects/fire", { transform = { x = -80, y = 40 }, particles = { "fire.pfx", seed = 3 } })
w:spawn("/objects/smoke", { transform = { x = 0, y = 40 }, particles = { "smoke.pfx" } })
w:spawn("/objects/sparks", { transform = { x = 80, y = 40 }, particles = { "sparks.pfx", rate = 30 } })
w:spawn("/systems/move", { system = ecs.system(function()
  return function(w, dt) local t = w:node("/objects/fire").c.transform; t.x = t.x + dt * 30 end
end) })
return w
