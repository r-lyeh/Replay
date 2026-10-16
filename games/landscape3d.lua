-- landscape3d.lua - a landscape: hills made by rules, things standing on them (3D demo)
--
-- One node's `landscape3d = { "hills.land" }` (games/common/hills.land: the landscape editor's, plugins/landscape)
-- is a height field: its base made by rules (hills: a seed, a height, a scale), then sculpted by hand. The game
-- reads it too: w:landscape("hills.land") -> land, and land:height_at(x, z) puts a crate on the
-- ground wherever it falls, and keeps a kgirl's feet on it as she walks round. A meadow grows on it
-- (games/common/hills_meadow.foliage: ground = "hills.land"): grass and flowers where it's gentle, rocks on the
-- steep sides leaning with them, pines low down; edit the hills and it follows.
-- Keys: left / right: turn round it, up / down: nearer / further, Space: crates dropped at random.
local ecs = require("ecs")
local w = ecs.world()

w:spawn("/config", { window = { w = 800, h = 600, title = "landscape3d" } })
w:spawn("/data/state", { orbit = 0.7, dist = 46, t = 0, crates = 0, want = 12, seed = 5 })
w:spawn("/data/input", { held = {} })
w:spawn("/objects/view", {
  transform = { x = 0, y = -14 },
  camera3d = { w = 800, h = 572, fov = 50, eye = { 0, 20, 40 }, at = { 0, 2, 0 }, far = 400,
               clear = { 160, 196, 232 }, ambient = { 105, 110, 120 },
               sun = { dir = { -0.5, -0.8, -0.3 }, color = { 255, 244, 222 } }, shadows = { size = 4096, area = 70 } },
})
w:spawn("/objects/view/land", { transform3d = {}, landscape3d = { "hills.land" } })
w:spawn("/objects/view/meadow", { transform3d = {}, foliage3d = { "hills_meadow.foliage" } })   -- (grows on hills.land: its ground; each copy on it)
w:spawn("/objects/view/girl", { transform3d = { x = 6, z = 0, s = 1 }, mesh = { "/assets/kgirl/kgirls01.fbx" }, animator = { clip = 1, loop = true } })
w:spawn("/objects/title", { transform = { x = 0, y = 286 }, text = { "", font = "sans", size = 14, align = "center" }, color = { 30, 40, 55 } })

w:spawn("/systems/input", { system = ecs.system(function()
  return {
    on_key = function(w, key, down)
      w:node("/data/input").c.held[key] = down or nil
      if down and key == "space" then local st = w:node("/data/state").c; st.want = st.want + 10 end
    end,
  }
end) })
w:spawn("/systems/play", { system = ecs.system(function()
  return function(w, dt)
    local st, held = w:node("/data/state").c, w:node("/data/input").c.held
    st.t = st.t + dt
    if held.left then st.orbit = st.orbit - dt * 0.7 end
    if held.right then st.orbit = st.orbit + dt * 0.7 end
    if held.up then st.dist = math.max(8, st.dist - dt * 20) end
    if held.down then st.dist = math.min(120, st.dist + dt * 20) end
    local L = w:landscape("hills.land")
    while st.crates < st.want do                   -- (crates wanted: each at a random spot, on the ground there)
      st.seed = (st.seed * 48271) % 2147483647
      local x = (st.seed % 10007) / 10007 * 50 - 25
      st.seed = (st.seed * 48271) % 2147483647
      local z = (st.seed % 10007) / 10007 * 50 - 25
      st.crates = st.crates + 1
      w:spawn("/objects/view/crate" .. st.crates, { transform3d = { x = x, y = L:height_at(x, z) + 0.5, z = z, ry = st.seed % 628 / 100 },
                                                   mesh = { "/assets/crate.glb" } })
    end
    local cam = w:node("/objects/view").c.camera3d
    cam.eye = { math.sin(st.orbit) * st.dist, 6 + st.dist * 0.45, math.cos(st.orbit) * st.dist }
    local g = w:node("/objects/view/girl").c
    local a = st.t * 0.15                          -- (round a circle, her feet on the ground, facing the way she goes)
    g.transform3d.x, g.transform3d.z = math.cos(a) * 12, math.sin(a) * 12
    g.transform3d.y = L:height_at(g.transform3d.x, g.transform3d.z)
    g.transform3d.ry = -a
    g.animator.t = (g.animator.t or 0) + dt
    w:node("/objects/title").c.text[1] = string.format("%d crates on the hills   Space: more, left / right: turn, up / down: zoom", st.crates)
  end
end) })
return w
