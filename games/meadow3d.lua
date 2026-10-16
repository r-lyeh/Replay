-- meadow3d.lua - foliage: a meadow scattered over the ground (3D demo)
--
-- One node's `foliage3d = { "meadow.foliage" }` (games/common/meadow.foliage: the foliage editor's,
-- plugins/foliage) is thousands of copies of a few meshes: grass in clumps, flowers, bushes, rocks.
-- The GPU draws each layer's copies instanced (one draw a part, editor/render3d.h); the scatter is
-- runtime/foliage.lua's, made once (the same seed, the same meadow).
-- Keys: left / right: turn round it, up / down: nearer / further, S: another seed.
local ecs = require("ecs")
local w = ecs.world()

w:spawn("/config", { window = { w = 640, h = 400, title = "meadow3d" } })
w:spawn("/data/state", { orbit = 0.6, dist = 9, seed = 11 })
w:spawn("/data/input", { held = {} })
w:spawn("/objects/view", {
  transform = { x = 0, y = -6 },
  camera3d = { w = 640, h = 360, fov = 45, eye = { 0, 3, 9 }, at = { 0, 0.3, 0 },
               clear = { 150, 190, 230 }, ambient = { 110, 115, 120 },
               sun = { dir = { -0.5, -1, -0.35 }, color = { 255, 246, 225 } }, shadows = { size = 2048, area = 14 } },
})
w:spawn("/objects/view/ground", { transform3d = { s = 26 }, mesh = { "plane", color = { 104, 132, 72 } } })
w:spawn("/objects/view/meadow", { transform3d = {}, foliage3d = { "meadow.foliage" } })
w:spawn("/objects/title", { transform = { x = 0, y = 188 }, text = { "", font = "sans", size = 14, align = "center" }, color = { 30, 40, 50 } })

w:spawn("/systems/input", { system = ecs.system(function()
  return {
    on_key = function(w, key, down)
      w:node("/data/input").c.held[key] = down or nil
      if down and key == "s" then                  -- (another meadow: the same layers, another seed)
        local st = w:node("/data/state").c
        st.seed = st.seed % 9973 + 17
        w:node("/objects/view/meadow").c.foliage3d.seed = st.seed
      end
    end,
  }
end) })
w:spawn("/systems/camera", { system = ecs.system(function()
  return function(w, dt)
    local st, held = w:node("/data/state").c, w:node("/data/input").c.held
    if held.left then st.orbit = st.orbit - dt * 0.8 end
    if held.right then st.orbit = st.orbit + dt * 0.8 end
    if held.up then st.dist = math.max(2, st.dist - dt * 4) end
    if held.down then st.dist = math.min(20, st.dist + dt * 4) end
    st.orbit = st.orbit + dt * 0.05                -- (a slow turn by itself)
    local cam = w:node("/objects/view").c.camera3d
    cam.eye = { math.sin(st.orbit) * st.dist, 1 + st.dist * 0.3, math.cos(st.orbit) * st.dist }
    local f = w:node("/objects/view/meadow").c.foliage3d
    local _, info = w:foliage(f[1], { seed = f.seed })
    w:node("/objects/title").c.text[1] = string.format("%d copies, seed %d   left / right: turn, up / down: zoom, S: another seed",
      info and info.count or 0, f.seed or 11)
  end
end) })
return w
