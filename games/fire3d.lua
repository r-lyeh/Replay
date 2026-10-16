-- fire3d.lua - particles in 3D: campfires round a clearing at night (3D demo)
--
-- Each fire is a node with `particles3d = { "fire.pfx" }` (plugins/particles' effects, runtime/particles.lua): the
-- effect's px as cm (scale 0.01), flames added (blend "add"), smoke over them (alpha, drawn far to near), sparks; logs
-- under them (cylinders). A torch circles the clearing: a moving emitter, its flames left behind as it goes.
-- Keys: Space: another fire somewhere, left / right: turn round the clearing, up / down: nearer / further.
local ecs = require("ecs")
local w = ecs.world()

w:spawn("/config", { window = { w = 640, h = 400, title = "fire3d" } })
w:spawn("/data/state", { orbit = 0.3, dist = 9, t = 0, fires = 0, seed = 7 })
w:spawn("/data/input", { held = {} })
w:spawn("/objects/view", {
  transform = { x = 0, y = -10 },
  camera3d = { w = 640, h = 380, fov = 50, eye = { 0, 3.5, 9 }, at = { 0, 0.6, 0 },
               clear = { 10, 12, 22 }, ambient = { 40, 44, 60 },
               sun = { dir = { -0.3, -1, -0.2 }, color = { 110, 90, 80 } }, shadows = { size = 2048, area = 12 } },
})
w:spawn("/objects/view/ground", { transform3d = { s = 24 }, mesh = { "plane", color = { 70, 62, 50 } } })
w:spawn("/objects/title", { transform = { x = 0, y = 186 }, text = { "", font = "sans", size = 14, align = "center" }, color = { 220, 200, 180 } })

-- a fire: logs crossed, flames, smoke above, a few sparks (its own seed each: no two alike)
local function fire(w, k, x, z)
  local p = "/objects/view/fire" .. k
  w:spawn(p, { transform3d = { x = x, y = 0, z = z } })
  w:spawn(p .. "/log1", { transform3d = { y = 0.08, rz = math.pi / 2, ry = 0.4, sx = 0.16, sy = 0.9, sz = 0.16 }, mesh = { "cylinder", color = { 90, 60, 40 } } })
  w:spawn(p .. "/log2", { transform3d = { y = 0.1, rz = math.pi / 2, ry = -0.9, sx = 0.16, sy = 0.9, sz = 0.16 }, mesh = { "cylinder", color = { 80, 55, 35 } } })
  w:spawn(p .. "/flames", { transform3d = { y = 0.1 }, particles3d = { "fire.pfx", seed = k * 13 + 1, scale = 0.014, radius = 16 } })
  w:spawn(p .. "/smoke", { transform3d = { y = 0.9 }, particles3d = { "smoke.pfx", seed = k * 17 + 2, scale = 0.015 } })
  w:spawn(p .. "/sparks", { transform3d = { y = 0.3 }, particles3d = { "sparks.pfx", seed = k * 19 + 3, scale = 0.004, rate = 8, gravity = { 0, -60 } } })
end
for k = 1, 5 do                                     -- (five round the clearing)
  local a = k / 5 * math.pi * 2
  fire(w, k, math.cos(a) * 3, math.sin(a) * 3)
end
w:node("/data/state").c.fires = 5
w:spawn("/objects/view/torch", { transform3d = { x = 4, y = 1.2, z = 0 }, particles3d = { "fire.pfx", seed = 99, scale = 0.006, rate = 140 } })

w:spawn("/systems/input", { system = ecs.system(function()
  return {
    on_key = function(w, key, down)
      w:node("/data/input").c.held[key] = down or nil
      if down and key == "space" then          -- (another fire: somewhere in the clearing)
        local st = w:node("/data/state").c
        st.fires = st.fires + 1
        st.seed = (st.seed * 48271) % 2147483647
        local a, r = (st.seed % 1000) / 1000 * math.pi * 2, 1.5 + (st.seed % 7) * 0.8
        local p = "/objects/view/fire" .. st.fires
        w:spawn(p, { transform3d = { x = math.cos(a) * r, y = 0, z = math.sin(a) * r } })
        w:spawn(p .. "/log1", { transform3d = { y = 0.08, rz = math.pi / 2, ry = a, sx = 0.16, sy = 0.9, sz = 0.16 }, mesh = { "cylinder", color = { 90, 60, 40 } } })
        w:spawn(p .. "/flames", { transform3d = { y = 0.1 }, particles3d = { "fire.pfx", seed = st.fires * 13 + 1, scale = 0.014, radius = 16 } })
        w:spawn(p .. "/smoke", { transform3d = { y = 0.9 }, particles3d = { "smoke.pfx", seed = st.fires * 17 + 2, scale = 0.015 } })
      end
    end,
  }
end) })
w:spawn("/systems/camera", { system = ecs.system(function()
  return function(w, dt)
    local st, held = w:node("/data/state").c, w:node("/data/input").c.held
    st.t = st.t + dt
    if held.left then st.orbit = st.orbit - dt * 0.8 end
    if held.right then st.orbit = st.orbit + dt * 0.8 end
    if held.up then st.dist = math.max(3, st.dist - dt * 4) end
    if held.down then st.dist = math.min(20, st.dist + dt * 4) end
    st.orbit = st.orbit + dt * 0.04
    local cam = w:node("/objects/view").c.camera3d
    cam.eye = { math.sin(st.orbit) * st.dist, 1.2 + st.dist * 0.25, math.cos(st.orbit) * st.dist }
    local t = w:node("/objects/view/torch").c.transform3d    -- (the torch: round the clearing, its flames trailing)
    t.x, t.z = math.cos(st.t * 0.6) * 4.6, math.sin(st.t * 0.6) * 4.6
    w:node("/objects/title").c.text[1] = string.format("%d fires   Space: another, left / right: turn, up / down: zoom", st.fires)
  end
end) })
return w
