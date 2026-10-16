-- flock.lua - boids (runtime/flock.lua): they keep apart, fly together, go to
-- a goal, flee a predator, keep off obstacles and walls, stay in the field;
-- the same seed flies the same; look / dots; w:flock.   cd runtime/tests && luajit flock.lua
package.path = "../?.lua;" .. package.path
local ecs = require "ecs"
local F = require "flock"
local n, fails = 0, 0
local function check(c, m) n = n + 1; if not c then fails = fails + 1; print("  FAIL: " .. m) end end
local function centre(st) local x, y = 0, 0; for _, b in ipairs(st.b) do x, y = x + b[1], y + b[2] end; return x / #st.b, y / #st.b end
local function run(d, st, secs, opts) for _ = 1, math.floor(secs * 60) do F.step(d, st, 1 / 60, opts) end end

local d = F.check({ count = 40 })
check(d.count == 40 and d.radius == F.DEFAULTS.radius and d.field.w == 640, "settings: given, and the defaults")
check(F.check({ count = "lots" }).count == F.DEFAULTS.count, "a wrong type: the default")
local st = F.new(d, 7)
check(#st.b == 40, "40 boids")
run(d, st, 4)
local minsep, inside = math.huge, true
for i, a in ipairs(st.b) do
  for j = i + 1, #st.b do local b = st.b[j]; minsep = math.min(minsep, math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)) end
  if math.abs(a[1]) > 320.01 or math.abs(a[2]) > 200.01 then inside = false end
end
check(minsep > 2, "they keep apart: nearest " .. string.format("%.1f", minsep))
check(inside, "in the field")
-- alignment: each flies much the way its neighbours do
local function local_order(dd, ss)
  local tot, cnt = 0, 0
  for i, a in ipairs(ss.b) do
    local mx, my = 0, 0
    for j, b in ipairs(ss.b) do
      if i ~= j and (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 < dd.radius * dd.radius then mx, my = mx + b[3], my + b[4] end
    end
    local l1, l2 = math.sqrt(a[3] ^ 2 + a[4] ^ 2), math.sqrt(mx * mx + my * my)
    if l1 > 0 and l2 > 0 then tot = tot + (a[3] * mx + a[4] * my) / (l1 * l2); cnt = cnt + 1 end
  end
  return cnt > 0 and tot / cnt or 0
end
local order = local_order(d, st)
local loose = F.check({ count = 40, alignment = 0, cohesion = 0, wander = 2 })
local st2 = F.new(loose, 7)
run(loose, st2, 4)
local order2 = local_order(loose, st2)
check(order > order2 and order > 0.5, string.format("alignment: with neighbours (%.2f), more than without (%.2f)", order, order2))
-- a goal
local g = F.check({ count = 30, goal = 2 })
local s3 = F.new(g, 3)
run(g, s3, 5, { goal = { 200, 100 } })
local cx, cy = centre(s3)
check(math.sqrt((cx - 200) ^ 2 + (cy - 100) ^ 2) < 90, string.format("a goal: they gather there (%.0f, %.0f)", cx, cy))
-- a predator
local s4 = F.new(g, 3)
run(g, s4, 3, { goal = { 0, 0 } })
run(g, s4, 2, { goal = { 0, 0 }, predators = { { 0, 0 } } })
local near = 0
for _, b in ipairs(s4.b) do if b[1] ^ 2 + b[2] ^ 2 < 40 * 40 then near = near + 1 end end
check(near <= 3, "a predator in the middle: they keep off (" .. near .. " near it)")
-- obstacles and solid cells
local s5 = F.new(g, 5)
run(g, s5, 4, { goal = { 0, 0 }, obstacles = { { 0, 0, 40 } } })
local inobs = 0
for _, b in ipairs(s5.b) do if b[1] ^ 2 + b[2] ^ 2 < 30 * 30 then inobs = inobs + 1 end end
check(inobs <= 1, "an obstacle on the goal: they keep off it (" .. inobs .. " inside)")
local function wall(x, y) return x > 100 and x < 140 end
local s6 = F.new(g, 9)
for i, b in ipairs(s6.b) do b[1] = -250 + (i % 5) * 10 end   -- (all left of the wall)
local crossed = false
for _ = 1, 300 do
  local before = {}
  for i, b in ipairs(s6.b) do before[i] = b[1] end
  F.step(g, s6, 1 / 60, { goal = { 250, 0 }, solid = wall })
  for i, b in ipairs(s6.b) do if wall(b[1], b[2]) then crossed = true end end
end
check(not crossed, "solid cells: never inside one")
-- the same seed: the same flight
local a1, a2 = F.new(d, 11), F.new(d, 11)
run(d, a1, 1); run(d, a2, 1)
check(a1.b[5][1] == a2.b[5][1] and a1.b[17][4] == a2.b[17][4], "the same seed: the same")
-- look
local L = F.look(d, a1)
check(#L.tris == 6 * 40, "look: a triangle each")
local Dt = F.dots(d, a1)
check(#Dt.xy == 80 and #Dt.a == 40 and #Dt.rgb == 40, "dots: a bullets batch")
-- presets, w:flock
for _, p in ipairs(F.PRESETS) do local pd = F.check(F.preset(p)); local ps = F.new(pd, 1); run(pd, ps, 0.5) end
check(true, "every preset runs")
ecs.assets.read = function(name) if name == "birds.flock" then return "return { count = 12, edges = 'wrap' }" end end
local w = ecs.world()
local f = w:flock("birds")
check(f and f.count == 12 and f.edges == "wrap" and f.step and #f:new(1).b == 12, "w:flock: the file, with its methods")
print(string.format("flock: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
