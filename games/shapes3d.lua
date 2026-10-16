-- shapes3d.lua - the built-in 3D shapes, solid and wireframe, billboards, and dd's 3D lines (3D demo)
--
-- Each shape is a node's `mesh = { "cylinder" }` (cube, sphere, plane, cylinder, cone, capsule, triangle,
-- line: 1 m, centred), its colour, and `wire = true` for its edges only (the front row). Over them,
-- dd's 3D calls (debug drawing, the editor only): dd.axes3 at the middle, dd.box3 round the turning cube,
-- dd.sphere3 round the sphere, an arrow3 from the cone up, a line3 between the capsules, cross3 on top.
-- At the back, two billboards: pictures that face the camera (the flame turning about y only).
-- Keys: left / right: turn round them, W: the wireframes on / off.
local ecs = require("ecs")
local w = ecs.world()

local SHAPES = { "cube", "sphere", "cylinder", "cone", "capsule", "triangle", "line" }
local COLORS = { { 230, 90, 80 }, { 240, 200, 70 }, { 90, 200, 120 }, { 80, 160, 240 }, { 190, 110, 230 }, { 240, 150, 60 }, { 255, 255, 255 } }

w:spawn("/config", { window = { w = 640, h = 400, title = "shapes3d" } })
w:spawn("/data/state", { orbit = 0.5, t = 0, wire = true, shapes = SHAPES })   -- (the systems read the names here: they run on their own)
w:spawn("/data/input", { held = {} })
w:spawn("/objects/view", {
  transform = { x = 0, y = -10 },
  camera3d = { w = 640, h = 380, fov = 45, eye = { 0, 4, 10 }, at = { 0, 0.5, 0 },
               clear = { 34, 38, 52 }, ambient = { 90, 95, 110 },
               sun = { dir = { -0.4, -1, -0.5 }, color = { 255, 248, 235 } }, shadows = { size = 2048, area = 10 } },
})
w:spawn("/objects/view/floor", { transform3d = { s = 14 }, mesh = { "plane", color = { 120, 128, 140 } } })
for i, name in ipairs(SHAPES) do
  local x = (i - 4) * 1.6
  w:spawn("/objects/view/solid_" .. name, { transform3d = { x = x, y = 0.5, z = -1 }, mesh = { name, color = COLORS[i] } })
  w:spawn("/objects/view/wire_" .. name, { transform3d = { x = x, y = 0.5, z = 1.2 }, mesh = { name, color = COLORS[i], wire = true } })
end
w:spawn("/objects/view/flame", { transform3d = { x = -1.6, y = 0.9, z = -3 }, billboard = { "/assets/flame.png", w = 1.2, h = 1.8, axis = "y" } })   -- (pictures facing the camera: upright, about y)
w:spawn("/objects/view/ship", { transform3d = { x = 1.6, y = 1.2, z = -3 }, billboard = { "/assets/ship.png", w = 1.4, h = 1.4 } })   -- (all the way round)
w:spawn("/objects/title", { transform = { x = 0, y = 186 }, text = { "left / right: turn round them, W: wireframes on / off", font = "sans", size = 14, align = "center" }, color = { 200, 205, 215 } })

w:spawn("/systems/input", { system = ecs.system(function()
  return {
    on_key = function(w, key, down)
      w:node("/data/input").c.held[key] = down or nil
      if down and key == "w" then
        local st = w:node("/data/state").c
        st.wire = not st.wire
        for _, name in ipairs(st.shapes) do w:node("/objects/view/wire_" .. name).c.mesh.wire = st.wire end
      end
    end,
  }
end) })
w:spawn("/systems/turn", { system = ecs.system(function()
  return function(w, dt)
    local st, held = w:node("/data/state").c, w:node("/data/input").c.held
    st.t = st.t + dt
    if held.left then st.orbit = st.orbit - dt end
    if held.right then st.orbit = st.orbit + dt end
    for _, name in ipairs(st.shapes) do    -- (each turning slowly about y, the wireframes the other way)
      w:node("/objects/view/solid_" .. name).c.transform3d.ry = st.t * 0.5
      w:node("/objects/view/wire_" .. name).c.transform3d.ry = -st.t * 0.5
    end
    local cam = w:node("/objects/view").c.camera3d
    cam.eye = { math.sin(st.orbit) * 10, 4, math.cos(st.orbit) * 10 }
    -- dd in 3D (the editor only: no-ops in a game on its own)
    dd.axes3(0, 0.01, 0, 1.5)
    dd.box3(-4.8, 0.5, -1, 1.2, 1.2, 1.2, "#ff606080")
    dd.sphere3(-3.2, 0.5, -1, 0.65, { 255, 220, 80 })
    dd.arrow3(0, 1.1, -1, 0, 2.2, -1, { 120, 200, 255 })
    dd.line3(1.6, 0.5, -1, 1.6, 0.5, 1.2, { 220, 140, 255 })
    dd.cross3(3.2, 1.2, -1, 0.4, { 255, 255, 255 })
  end
end) })
return w
