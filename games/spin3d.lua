-- spin3d.lua - 3D viewport demo
-- about: 3D viewport demo: a glTF ship, crate and animated arm, built-in shapes, a sun, shadows and ambient light
--
-- A camera3d node draws the 3D nodes under it (transform3d, mesh) into a picture
-- in the 2D world: the HUD stays 2D, on top. The ship and the crate are
-- glTF files of games/common (made by games/common/tools/make_models3d.py);
-- the floor and the ball are built-in shapes ("plane", "sphere", "cube"). The arm
-- is skinned: its `animator` plays its clip "bend" (t: the clip's time, ours to move).
-- Drawn on the GPU when there's one, else on the CPU. The sun casts shadows
-- (`shadows = true`; S turns them off and on).
-- Keys: left / right turn the camera round, up / down nearer / further, S shadows.

local ecs = require("ecs")
local w = ecs.world()

w:spawn("/config", { window = { w = 640, h = 400, title = "spin3d" } })
w:spawn("/data/state", { orbit = 0.6, dist = 6, t = 0 })
w:spawn("/data/input", { held = {} })

w:spawn("/objects/view", {
  transform = { x = 0, y = -10 },
  camera3d = { w = 640, h = 360, fov = 55, eye = { 0, 2.5, 6 }, at = { 0, 0.5, 0 },
               clear = { 34, 40, 58 }, ambient = { 70, 74, 92 },
               sun = { dir = { -0.5, -1, -0.35 }, color = { 255, 240, 214 } }, shadows = true },
})
w:spawn("/objects/view/floor", { transform3d = { y = 0, s = 8 }, mesh = { "plane", color = { 120, 170, 110 } } })
w:spawn("/objects/view/ship", { transform3d = { x = 0, y = 1.2, z = 0, s = 1.4 }, mesh = { "/assets/ship.glb" } })
w:spawn("/objects/view/crate", { transform3d = { x = -1.8, y = 0.5, z = 0.6, ry = 0.4 }, mesh = { "/assets/crate.glb" } })
w:spawn("/objects/view/box", { transform3d = { x = 1.9, y = 0.4, z = -0.4, s = 0.8 }, mesh = { "cube", texture = "/assets/crate.png", color = { 200, 220, 255 } } })
w:spawn("/objects/view/arm", { transform3d = { x = 1.0, y = 0, z = 1.4, s = 0.6, ry = -0.5 }, mesh = { "/assets/arm.glb" }, animator = { clip = "bend", t = 0 } })
w:spawn("/objects/view/ball", { transform3d = { x = 0.2, y = 0.35, z = 1.6, s = 0.7 }, mesh = { "sphere", color = { 240, 110, 90 } } })
w:spawn("/objects/title", { transform = { x = 0, y = 186 }, text = { "spin3d: left / right / up / down, S: shadows", font = "sans", size = 16, align = "center" }, color = { 230, 230, 240 } })

w:spawn("/systems/input", { system = ecs.system(function()
  return {
    on_key = function(w, key, down)
      w:node("/data/input").c.held[key] = down or nil
      if key == "s" and down then local c = w:node("/objects/view").c.camera3d; c.shadows = not c.shadows end
    end,
  }
end) })
w:spawn("/systems/spin", { system = ecs.system(function()
  return function(w, dt)
    local st = w:node("/data/state").c
    local held = w:node("/data/input").c.held
    st.t = st.t + dt
    if held.left then st.orbit = st.orbit - dt * 1.5 end
    if held.right then st.orbit = st.orbit + dt * 1.5 end
    if held.up then st.dist = math.max(2.5, st.dist - dt * 3) end
    if held.down then st.dist = math.min(14, st.dist + dt * 3) end
    local cam = w:node("/objects/view").c.camera3d
    cam.eye = { math.sin(st.orbit) * st.dist, 1 + st.dist * 0.3, math.cos(st.orbit) * st.dist }
    local ship = w:node("/objects/view/ship").c.transform3d
    ship.ry = st.t * 0.8
    ship.y = 1.2 + math.sin(st.t * 2) * 0.15
    local arm = w:node("/objects/view/arm").c.animator  -- (to 90 degrees and back: the clip's 1 s, there and back)
    local k = st.t % 2
    arm.t, arm.loop = k < 1 and k or 2 - k, false
  end
end) })
w:spawn("/systems", { order = { "input", "spin" } })
return w
