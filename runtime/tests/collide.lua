-- collide.lua - runtime/collide.lua: overlaps with their push-out, rays,
-- sweeps (a fast ball can't pass a thin wall), reflect / slide, node shapes,
-- the grid, and `collide` inside a system.   cd runtime/tests && luajit collide.lua
package.path = "../?.lua;" .. package.path
local C = require "collide"
local ecs = require "ecs"
local n, fails = 0, 0
local function check(c, m) n = n + 1; if not c then fails = fails + 1; print("  FAIL: " .. m) end end
local function near(a, b) return math.abs(a - b) < 1e-6 end

local hit, nx, ny, d = C.circle_circle(0, 0, 5, 8, 0, 5)
check(hit and near(nx, -1) and near(ny, 0) and near(d, 2), "circles: overlap 2, pushed left")
check(not C.circle_circle(0, 0, 5, 11, 0, 5), "circles apart")
hit, nx, ny, d = C.circle_box(0, -9, 5, 0, 0, 10, 5)
check(hit and near(nx, 0) and near(ny, -1) and near(d, 1), "a circle on a box's top: up, 1 deep")
hit, nx, ny, d = C.circle_box(1, 1, 2, 0, 0, 10, 5)
check(hit and near(ny, 1) and near(d, 6), "a circle's centre inside: out the nearest side (" .. tostring(ny) .. ", " .. tostring(d) .. ")")
hit, nx, ny, d = C.box_box(0, 0, 5, 5, 8, 1, 5, 5)
check(hit and near(nx, -1) and near(d, 2), "boxes: the smaller overlap (x)")
check(C.point_box(1, 1, 0, 0, 2, 2) and not C.point_circle(3, 3, 0, 0, 4), "points")

local t, rx, ry = C.ray_box(-20, 0, 20, 0, 0, 0, 5, 5)
check(near(t, 15 / 40) and near(rx, -1), "a ray enters the box's left side at 15/40")
check(C.ray_box(-20, 10, 20, 10, 0, 0, 5, 5) == nil, "a ray passing above: nil")
t = C.ray_circle(-20, 0, 20, 0, 0, 0, 5)
check(near(t, 15 / 40), "a ray meets a circle")

-- a fast ball (30 px a step) and a 4 px wall: it would jump through it
t, nx, ny = C.sweep_circle_box(0, 0, 3, 30, 0, 15, 0, 2, 20)
check(t and near(t * 30, 10) and near(nx, -1), "sweep: the ball stops where it touches the wall (10 px, from the left)")
t, nx, ny = C.sweep_circle_box(0, 0, 3, 30, 30, 20, 20, 2, 2)
check(t and nx < 0 and ny < 0, "sweep: a corner meets it on its rounded corner (" .. tostring(nx) .. ", " .. tostring(ny) .. ")")
check(C.sweep_circle_box(0, 0, 3, 30, 0, 15, 40, 2, 2) == nil, "sweep: missing it")
t = C.sweep_box_box(0, 0, 2, 2, 20, 0, 10, 0, 2, 2)
check(near(t, 6 / 20), "sweep boxes")
t = C.sweep_circle_circle(0, 0, 1, 10, 0, 6, 0, 1)
check(near(t, 0.4), "sweep circles")

local vx, vy = C.reflect(3, 4, 0, -1)
check(vx == 3 and vy == -4, "reflect off a floor")
vx, vy = C.reflect(3, -4, 0, -1)
check(vx == 3 and vy == -4, "moving away: unchanged")
vx, vy = C.slide(3, 4, 0, -1)
check(vx == 3 and vy == 0, "slide along it")

local a = { c = { xform = { x = 0, y = 0 }, rect = { w = 20, h = 10 } } }
local b = { c = { xform = { x = 0, y = -8, s = 2 }, circle = { r = 2 } } }
local k, x, y, hw, hh = C.shape(a)
check(k == "box" and hw == 10 and hh == 5, "shape: a rect, half sizes")
hit, nx, ny = C.test(a, b)
check(hit and near(ny, 1), "test: the box pushed down, away from the circle above")

local g = C.grid(32)
g:add("p", 10, 10, 5, 5); g:add("q", 100, 100, 5, 5); g:add("big", 40, 10, 40, 4)
local keys = table.concat(g:near(12, 12, 2, 2), ",")
check(keys:find("p") and keys:find("big") and not keys:find("q"), "grid: what's near (" .. keys .. ")")

local w = ecs.world()
w:spawn("/data", { out = 0 })
w:spawn("/systems/s", { system = ecs.system(function()
  return function(w, dt)
    local hit = collide.circle_circle(0, 0, 1, 1, 0, 1)
    w:node("/data").c.out = hit and 1 or -1
  end
end) })
w:tick("/**", 1 / 60)
check(w:node("/data").c.out == 1, "a system has `collide`")

print(string.format("collide: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
