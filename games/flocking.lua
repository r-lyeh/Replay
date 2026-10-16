-- FLOCKING: boids for Replay, in one file (runtime/flock.lua; the flock editor
-- edits common/birds.flock: change it while this plays, the birds change).
-- Run with: replay games/flocking.lua
-- The birds keep together, fly round the rocks and flee the hawk. Hold the
-- mouse button: they head for the pointer. SPACE: the hawk on / off;
-- 1..5: birds, fish, bats, bees, sheep (the file's settings, then that kind).
local ecs = require("ecs")
local w = ecs.world()
w:spawn("/config", { window = { w = 800, h = 500, title = "FLOCKING", mouse = true } })
w:spawn("/data/state", { seed = 20261029, kind = false, hawk = true, hx = 300, hy = 0, hvx = -60, hvy = 40, taps = {} })
w:spawn("/data/rocks", { list = { { -160, -60, 34 }, { 120, 90, 46 }, { 40, -130, 24 }, { -60, 140, 28 } } })
w:spawn("/data/layers", { order = { "sky", "default", "hud" } })   -- (siblings draw in name order: the sky under all)
w:spawn("/objects/sky", { xform = { x = 0, y = 0 }, color = { 14, 20, 34 }, rect = { w = 800, h = 500, fill = true }, layer = "sky" })
for i, r in ipairs(w:node("/data/rocks").c.list) do
  w:spawn("/objects/rocks/" .. i, { xform = { x = r[1], y = r[2] }, color = { 70, 66, 62 }, circle = { r = r[3], fill = true } })
end
w:spawn("/objects/flock", { xform = { x = 0, y = 0 }, color = { 220, 230, 255 }, tris = {} })
w:spawn("/objects/hawk", { xform = { x = 300, y = 0 }, color = { 230, 90, 80 }, circle = { r = 9, fill = true } })
w:spawn("/objects/hud", { xform = { x = -390, y = -240 }, color = { 140, 160, 190 }, text = "HOLD THE MOUSE: A GOAL   SPACE: THE HAWK   1..5: BIRDS FISH BATS BEES SHEEP", layer = "hud" })

local input = ecs.system(function()
  return { on_key = function(w, key, down)
    if down then local s = w:node("/data/state").c; s.taps[key] = true end
  end }
end)

local fly = ecs.system(function()
  local KINDS = { ["1"] = "birds", ["2"] = "fish", ["3"] = "bats", ["4"] = "bees", ["5"] = "sheep" }
  local cache = {}
  local LOOKS = { birds = { 220, 230, 255 }, fish = { 255, 170, 80 }, bats = { 120, 100, 150 }, bees = { 255, 220, 60 }, sheep = { 240, 240, 230 } }
  return function(w, dt)
    local s = w:node("/data/state").c
    local F = w:flock("birds.flock")
    if not F then return end
    for k in pairs(s.taps) do
      if k == "space" then s.hawk = not s.hawk end
      if KINDS[k] then s.kind = KINDS[k]; s.flock = nil end
    end
    s.taps = {}
    local d = F
    if s.kind and s.kind ~= "birds" then           -- (another kind: its settings, in the file's field)
      if not (cache.kind == s.kind and cache.of == F) then cache.kind, cache.of, cache.d = s.kind, F, F:preset(s.kind) end
      d = cache.d
    end
    s.flock = s.flock or d:new(s.seed)
    local m = w.mouse
    local goal = m and m.left and m.inside and { m.x, m.y } or nil
    local rocks = w:node("/data/rocks").c.list
    if s.hawk then                                 -- the hawk: round the field, after the flock's middle
      local cx, cy = 0, 0
      for _, b in ipairs(s.flock.b) do cx, cy = cx + b[1], cy + b[2] end
      local n = math.max(1, #s.flock.b)
      cx, cy = cx / n, cy / n
      local ax, ay = cx - s.hx, cy - s.hy
      local l = math.sqrt(ax * ax + ay * ay)
      if l > 0 then s.hvx, s.hvy = s.hvx + ax / l * 120 * dt, s.hvy + ay / l * 120 * dt end
      local v = math.sqrt(s.hvx ^ 2 + s.hvy ^ 2)
      if v > 95 then s.hvx, s.hvy = s.hvx / v * 95, s.hvy / v * 95 end
      s.hx, s.hy = s.hx + s.hvx * dt, s.hy + s.hvy * dt
    end
    d:step(s.flock, dt, { goal = goal, obstacles = rocks, predators = s.hawk and { { s.hx, s.hy } } or nil })
    local node = w:node("/objects/flock")
    d:look(s.flock, node.c)
    local c = LOOKS[s.kind or "birds"]
    node.c.color[1], node.c.color[2], node.c.color[3] = c[1], c[2], c[3]
    local hawk = w:node("/objects/hawk")
    hawk.c.hidden = not s.hawk or nil
    hawk.c.xform.x, hawk.c.xform.y = s.hx, s.hy
  end
end)

w:spawn("/systems", { order = { "input", "fly" } })
w:spawn("/systems/input", { system = input })
w:spawn("/systems/fly", { system = fly })
return w
