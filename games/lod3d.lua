-- lod3d.lua - levels of detail: a crowd far into the distance (3D demo)
--
-- /config lod (docs/3D.md §31): past 6, 14 and 28 m a node's mesh is a simpler copy of itself (made for it: vertex
-- clustering, skinned ones too, posed as before), past 60 m it isn't drawn; the sun's pass draws a level simpler
-- still. A system reads each node's level as last drawn (w:lod(n)): the title counts them.
-- Everyone loops the long take ("Take 001", 17 s) from a moment of their own. Keys (shown at the bottom): D: each level tinted (white, green, yellow, orange) on / off, L: levels of detail on / off,
-- left / right: turn, up / down: nearer / further.
local ecs = require("ecs")
local w = ecs.world()

w:spawn("/config", { window = { w = 640, h = 400, title = "lod3d" },
                     lod = { distances = { 6, 14, 28 }, cull = 60, shadow = 1, debug = true } })
w:spawn("/data/state", { orbit = 0.4, dist = 8, t = 0, lod_on = true })
w:spawn("/data/input", { held = {} })
w:spawn("/objects/view", {
  transform = { x = 0, y = -20 },
  camera3d = { w = 640, h = 360, fov = 55, eye = { 0, 3, 8 }, at = { 0, 1, -10 }, far = 120,
               clear = { 150, 175, 205 }, ambient = { 100, 105, 115 },
               sun = { dir = { -0.4, -1, -0.3 }, color = { 255, 246, 230 } }, shadows = { size = 2048, area = 30 } },
})
w:spawn("/objects/view/ground", { transform3d = { z = -30, s = 90 }, mesh = { "plane", color = { 110, 130, 95 } } })
local k = 0
for row = 0, 13 do                                   -- (a crowd: rows going away, each a little wider)
  for col = -3, 3 do
    k = k + 1
    local x, z = col * 1.8 + (row % 2) * 0.9, -row * 4.5
    w:spawn("/objects/view/girl" .. k, { transform3d = { x = x, z = z, ry = (k * 0.7) % 6.28 },
      mesh = { "/assets/kgirl/kgirls01.fbx" }, animator = { clip = 1, t = (k * 7.919) % 16.8, loop = true } })   -- ("Take 001": the whole 17 s take, each from its own moment)
    if col == 3 then w:spawn("/objects/view/crate" .. row, { transform3d = { x = x + 2, y = 0.5, z = z, s = 1 }, mesh = { "/assets/crate.glb" } }) end
  end
end
w:spawn("/objects/title", { transform = { x = 0, y = 171 }, text = { "", font = "sans", size = 14, align = "center" }, color = { 225, 230, 238 } })
w:spawn("/objects/keys", { transform = { x = 0, y = 189 }, text = { "D: tint the levels   L: levels of detail on / off   left / right: turn   up / down: nearer / further", font = "sans", size = 12, align = "center" }, color = { 160, 170, 186 } })

w:spawn("/systems/input", { system = ecs.system(function()
  return {
    on_key = function(w, key, down)
      w:node("/data/input").c.held[key] = down or nil
      local cfg = w:node("/config").c
      local st = w:node("/data/state").c
      if down and key == "d" and type(cfg.lod) == "table" then cfg.lod.debug = not cfg.lod.debug end
      if down and key == "l" then
        st.lod_on = not st.lod_on
        cfg.lod = st.lod_on and { distances = { 6, 14, 28 }, cull = 60, shadow = 1, debug = true } or false
      end
    end,
  }
end) })
w:spawn("/systems/play", { system = ecs.system(function()
  return function(w, dt)                            -- (everyone's clip on; the camera; the title: how many at each level)
    local st, held = w:node("/data/state").c, w:node("/data/input").c.held
    st.t = st.t + dt
    if held.left then st.orbit = st.orbit - dt * 0.6 end
    if held.right then st.orbit = st.orbit + dt * 0.6 end
    if held.up then st.dist = math.max(3, st.dist - dt * 6) end
    if held.down then st.dist = math.min(40, st.dist + dt * 6) end
    local cam = w:node("/objects/view").c.camera3d
    cam.eye = { math.sin(st.orbit) * st.dist, 2 + st.dist * 0.15, math.cos(st.orbit) * st.dist }
    local per = { [0] = 0, 0, 0, 0 }
    for _, n in ipairs(w:select("/objects/view/girl*")) do
      n.c.animator.t = n.c.animator.t + dt
      local l = w:lod(n)
      per[l] = (per[l] or 0) + 1
    end
    w:node("/objects/title").c.text[1] = st.lod_on
      and string.format("level 0: %d   1: %d   2: %d   3: %d", per[0], per[1], per[2], per[3])
      or "levels of detail off"
  end
end) })
return w
