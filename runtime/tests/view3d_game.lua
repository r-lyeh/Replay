-- view3d_game.lua - a world for the 3D viewport test (run.lua: "3d viewport"):
-- built-in shapes in camera3d viewports, lit flat (ambient white, no sun) so
-- the colours are exact: a red cube, near-plane clipping (a floor that
-- passes behind the camera), culling (the camera inside a cube), nesting
-- (transform3d under transform3d), a texture on a built-in cube; a shadow (a cube over a
-- floor, the sun slanting: seen from above, its shadow beside it); a skinned arm
-- posed by its animator (games/common/arm.glb, its clip "bend" at 1 s: 90 degrees);
-- a sphere's bounds3d (picked by its shape: bigger than its mesh).
local ecs = require("ecs")
local w = ecs.world()
w:spawn("/config", { window = { w = 400, h = 100 } })
local flat = { clear = { 0, 0, 0 }, ambient = { 255, 255, 255 }, sun = { color = { 0, 0, 0 } } }
local function cam(name, x, t)
  local c = { w = 64, h = 64, fov = 60 }
  for k, v in pairs(flat) do c[k] = v end
  for k, v in pairs(t) do c[k] = v end
  w:spawn("/objects/" .. name, { transform = { x = x, y = 0 }, camera3d = c })
end
cam("red", -150, { eye = { 0, 0, 3 }, at = { 0, 0, 0 } })
w:spawn("/objects/red/cube", { transform3d = {}, mesh = { "cube", color = { 255, 0, 0 } } })
cam("floor", -75, { eye = { 0, 0, 0 }, at = { 0, 0, -5 } })
w:spawn("/objects/floor/plane", { transform3d = { y = -1, s = 100 }, mesh = { "plane", color = { 0, 255, 0 } } })
cam("inside", 0, { eye = { 0, 0, 0 }, at = { 0, 0, -1 } })
w:spawn("/objects/inside/box", { transform3d = { s = 10 }, mesh = { "cube", color = { 0, 0, 255 } } })
cam("nested", 75, { eye = { 0, 0, 4 }, at = { 0, 0, 0 } })
w:spawn("/objects/nested/arm", { transform3d = { x = 1 } })
w:spawn("/objects/nested/arm/hand", { transform3d = { x = 0.5, s = 0.5 }, mesh = { "cube", color = { 255, 255, 0 } } })
cam("tex", 150, { eye = { 0, 0, 1.6 }, at = { 0, 0, 0 } })
w:spawn("/objects/tex/box", { transform3d = {}, mesh = { "cube", texture = "plugin:tiles.png" } })
w:spawn("/objects/shadow", { transform = { x = 0, y = 70 }, camera3d = { w = 64, h = 64, fov = 60, clear = { 0, 0, 0 },
  eye = { 0, 6, 0 }, at = { 0, -1, 0 }, up = { 0, 0, -1 }, ambient = { 60, 60, 60 },
  sun = { dir = { 1, -1, 0 }, color = { 255, 255, 255 } }, shadows = { size = 512 } } })
w:spawn("/objects/shadow/floor", { transform3d = { y = -1, s = 20 }, mesh = { "plane" } })
w:spawn("/objects/shadow/cube", { transform3d = {}, mesh = { "cube", color = { 255, 0, 0 } } })
cam("arm", 0, { eye = { 0, 1, 5 }, at = { 0, 1, 0 } })
w:node("/objects/arm").c.transform.y = -70
w:spawn("/objects/arm/arm", { transform3d = {}, mesh = { "file:games/common/arm.glb" }, animator = { clip = "bend", t = 1, loop = false } })
cam("ball", 0, { eye = { 0, 0, 4 }, at = { 0, 0, 0 } })
w:node("/objects/ball").c.transform.y = 140
w:spawn("/objects/ball/b", { transform3d = { x = -1 }, mesh = { "cube", color = { 0, 200, 200 } }, bounds3d = { r = 0.9 } })
w:spawn("/objects/ball/c", { transform3d = { x = 1, s = 0.5 }, mesh = { "cube", color = { 200, 200, 0 } } })
return w
