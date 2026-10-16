-- flock.lua - boids, swarms, flocks (plugins/flock edits a .flock; games run it
-- with w:flock(name); one file for both). Reynolds' three rules, separation,
-- alignment, cohesion, plus a goal, wandering, obstacles (circles, or a
-- tilemap's solid cells), leaders, predators to flee and the edges of a field;
-- neighbours found through a spatial grid (collide.grid), so hundreds stay cheap.
--
-- A .flock (Lua data): return { count = 60, radius = 40, separation = 1.6, ... }
-- (DEFAULTS below says what each is). In a game:
--   local f = w:flock("birds.flock")        -- parsed, with its methods
--   st = f:new(seed [, count])               -- the boids: plain data (keep it in the world)
--   f:step(st, dt, { goal = { x, y }, predators = { { x, y }... }, obstacles = { { x, y, r }... },
--                    solid = function(x, y) -> bool, leader = { x, y } })
--   f:look(st [, out]) -> { tris = {...} } a node's `tris` (one triangle a boid, pointing where it flies)
--   f:dots(st [, out]) -> a `bullets` component's xy, a, rgb (one batch, any picture)
--   f:preset("fish") -> that kind's settings, in this one's field
local M = {}
local sqrt, cos, sin, atan2, floor, pi = math.sqrt, math.cos, math.sin, math.atan2 or math.atan, math.floor, math.pi

M.DEFAULTS = {
  count = 60,                 -- boids
  radius = 40,                -- how far a boid sees its neighbours (px)
  separation = 1.6,           -- keep away from those too near (within separation_radius)
  separation_radius = 16,
  alignment = 1.0,            -- fly the way the neighbours fly
  cohesion = 0.8,             -- towards the neighbours' middle
  goal = 0.4,                 -- towards the goal (opts.goal), when there's one
  wander = 0.3,               -- a little random turning
  avoid = 3.0,                -- away from obstacles (circles, solid cells), and the field's edges
  flee = 4.0,                 -- away from predators within flee_radius
  flee_radius = 90,
  leader = 0.0,               -- towards the leader (opts.leader) instead of the goal, when > 0
  min_speed = 40,
  max_speed = 120,
  max_force = 240,            -- how hard it can turn (px/s²)
  size = 5,                   -- a boid's length (px), for look
  field = { w = 640, h = 400 },   -- where they fly (centred on 0, 0); edges: "bounce" | "wrap"
  edges = "bounce",
  color = { 220, 230, 255, 255 },
  color2 = { 120, 170, 255, 255 },   -- (look: each boid between the two)
}
M.PRESETS = { "birds", "fish", "bats", "bees", "sheep" }
M.PRESET_NAMES = { birds = "Birds", fish = "Fish school", bats = "Bats", bees = "Bees", sheep = "Sheep" }
local PRESETS = {
  birds = {},
  fish = { count = 90, radius = 30, separation = 1.2, separation_radius = 10, alignment = 1.6, cohesion = 1.2, wander = 0.15,
           min_speed = 50, max_speed = 90, max_force = 160, size = 6, color = { 255, 190, 90, 255 }, color2 = { 255, 120, 60, 255 } },
  bats = { count = 40, radius = 50, separation = 2.0, separation_radius = 22, alignment = 0.4, cohesion = 0.6, wander = 1.2,
           min_speed = 70, max_speed = 160, max_force = 420, size = 6, color = { 70, 60, 90, 255 }, color2 = { 130, 110, 150, 255 } },
  bees = { count = 70, radius = 25, separation = 1.4, separation_radius = 8, alignment = 0.2, cohesion = 1.8, goal = 1.2, wander = 1.6,
           min_speed = 30, max_speed = 110, max_force = 500, size = 3, color = { 255, 220, 60, 255 }, color2 = { 60, 40, 10, 255 } },
  sheep = { count = 30, radius = 45, separation = 2.2, separation_radius = 18, alignment = 0.6, cohesion = 1.0, wander = 0.2, flee = 5.0,
            flee_radius = 110, min_speed = 0, max_speed = 45, max_force = 120, size = 8, color = { 240, 240, 230, 255 }, color2 = { 200, 200, 190, 255 } },
}
local function copy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = copy(x) end
  return o
end
M.copy = copy
function M.preset(name)
  local d = copy(M.DEFAULTS)
  for k, v in pairs(PRESETS[name] or {}) do d[k] = copy(v) end
  return d
end
function M.check(t)                                -- missing settings: the defaults; wrong types: the defaults
  local d = copy(M.DEFAULTS)
  if type(t) == "table" then
    for k, v in pairs(t) do if d[k] ~= nil and type(v) == type(d[k]) then d[k] = copy(v) end end
  end
  d.count = math.max(0, math.min(2000, floor(d.count)))
  d.min_speed = math.max(0, d.min_speed)
  d.max_speed = math.max(d.min_speed, d.max_speed)
  d.field.w, d.field.h = tonumber(d.field.w) or 640, tonumber(d.field.h) or 400
  return d
end

local function rng(st)                             -- (the state's own: replays the same)
  st.seed = (st.seed * 16807) % 2147483647
  return st.seed / 2147483647
end
function M.new(d, seed, count)
  local st = { seed = math.max(1, floor(seed or 1)) % 2147483647, b = {}, t = 0 }
  if st.seed == 0 then st.seed = 1 end
  local n = count or d.count
  local W, H = d.field.w, d.field.h
  for i = 1, n do
    local a = rng(st) * 2 * pi
    local s = d.min_speed + (d.max_speed - d.min_speed) * 0.5
    st.b[i] = { (rng(st) - 0.5) * W * 0.8, (rng(st) - 0.5) * H * 0.8, cos(a) * s, sin(a) * s, rng(st) }   -- x, y, vx, vy, its shade
  end
  return st
end

local function limit(x, y, m)
  local l = sqrt(x * x + y * y)
  if l > m and l > 0 then return x / l * m, y / l * m end
  return x, y
end
-- one step: dt seconds
function M.step(d, st, dt, opts)
  opts = opts or {}
  dt = math.min(dt or 0, 1 / 20)
  if dt <= 0 then return end
  st.t = st.t + dt
  local B = st.b
  local cell = math.max(8, d.radius)
  local grid = {}                                  -- (who's where: cells of `radius`)
  for i, b in ipairs(B) do
    local k = floor(b[1] / cell) .. "," .. floor(b[2] / cell)
    local l = grid[k]
    if not l then l = {}; grid[k] = l end
    l[#l + 1] = i
  end
  local R2, SR2 = d.radius * d.radius, d.separation_radius * d.separation_radius
  local W, H = d.field.w / 2, d.field.h / 2
  local goal = opts.goal
  local target = (d.leader > 0 and opts.leader) or goal
  local tw = (d.leader > 0 and opts.leader) and d.leader or d.goal
  local acc = {}
  for i, b in ipairs(B) do
    local x, y, vx, vy = b[1], b[2], b[3], b[4]
    local cx, cy = floor(x / cell), floor(y / cell)
    local n, ax, ay, mx, my, sx, sy, ns = 0, 0, 0, 0, 0, 0, 0, 0
    for gy = cy - 1, cy + 1 do
      for gx = cx - 1, cx + 1 do
        for _, j in ipairs(grid[gx .. "," .. gy] or {}) do
          if j ~= i then
            local o = B[j]
            local dx, dy = o[1] - x, o[2] - y
            local d2 = dx * dx + dy * dy
            if d2 < R2 then
              n = n + 1
              ax, ay = ax + o[3], ay + o[4]
              mx, my = mx + o[1], my + o[2]
              if d2 < SR2 and d2 > 0 then
                local l = sqrt(d2)
                sx, sy = sx - dx / l * (1 - l / d.separation_radius), sy - dy / l * (1 - l / d.separation_radius)
                ns = ns + 1
              end
            end
          end
        end
      end
    end
    local fx, fy = 0, 0
    local speed = d.max_speed
    local function steer(tx, ty, w)                -- towards a direction (tx, ty: any length), weight w
      local l = sqrt(tx * tx + ty * ty)
      if l == 0 or w == 0 then return end
      local dvx, dvy = tx / l * speed - vx, ty / l * speed - vy
      fx, fy = fx + dvx * w, fy + dvy * w
    end
    if n > 0 then
      steer(ax / n, ay / n, d.alignment)
      steer(mx / n - x, my / n - y, d.cohesion)
    end
    if ns > 0 then steer(sx, sy, d.separation * 1.5) end
    if target and tw > 0 then steer(target[1] - x, target[2] - y, tw) end
    if d.wander > 0 then                           -- (a slowly turning random pull)
      b[5] = (b[5] + (rng(st) - 0.5) * 0.6 * dt * 4) % 1
      local a = b[5] * 2 * pi + st.t * 0.5
      steer(cos(a), sin(a), d.wander * 0.5)
    end
    for _, p in ipairs(opts.predators or {}) do    -- flee
      local dx, dy = x - p[1], y - p[2]
      local d2 = dx * dx + dy * dy
      if d2 < d.flee_radius * d.flee_radius then
        local k = 1 - sqrt(d2) / d.flee_radius
        steer(dx, dy, d.flee * k * 2)
      end
    end
    for _, o in ipairs(opts.obstacles or {}) do    -- circles: pushed off their edge, and round them
      local dx, dy = x - o[1], y - o[2]
      local l = sqrt(dx * dx + dy * dy)
      local r = (o[3] or 10) + d.separation_radius
      if l < r * 1.6 and l > 0 then steer(dx, dy, d.avoid * (1 - (l - r) / (r * 0.6))) end
    end
    if opts.solid then                             -- solid cells: look ahead, turn from what's there
      local vl = sqrt(vx * vx + vy * vy)
      if vl > 0 then
        local ux, uy = vx / vl, vy / vl
        local look = d.separation_radius + vl * 0.25
        if opts.solid(x + ux * look, y + uy * look) then
          local left = not opts.solid(x - uy * look, y + ux * look)
          steer(left and -uy or uy, left and ux or -ux, d.avoid * 1.5)
          steer(-ux, -uy, d.avoid * 0.5)
        end
      end
    end
    if d.edges == "bounce" then                    -- the field's edges: turned back before them
      local m = d.radius
      if x < -W + m then steer(1, 0, d.avoid * (1 - (x + W) / m)) end
      if x > W - m then steer(-1, 0, d.avoid * (1 - (W - x) / m)) end
      if y < -H + m then steer(0, 1, d.avoid * (1 - (y + H) / m)) end
      if y > H - m then steer(0, -1, d.avoid * (1 - (H - y) / m)) end
    end
    acc[i] = { limit(fx, fy, d.max_force) }
  end
  for i, b in ipairs(B) do
    local a = acc[i]
    local vx, vy = b[3] + a[1] * dt, b[4] + a[2] * dt
    local l = sqrt(vx * vx + vy * vy)
    if l > d.max_speed then vx, vy = vx / l * d.max_speed, vy / l * d.max_speed
    elseif l < d.min_speed and l > 0 then vx, vy = vx / l * d.min_speed, vy / l * d.min_speed end
    local nx, ny = b[1] + vx * dt, b[2] + vy * dt
    if opts.solid and opts.solid(nx, ny) then      -- (never into a wall: stop that way)
      if not opts.solid(nx, b[2]) then ny, vy = b[2], -vy * 0.5
      elseif not opts.solid(b[1], ny) then nx, vx = b[1], -vx * 0.5
      else nx, ny, vx, vy = b[1], b[2], -vx * 0.5, -vy * 0.5 end
    end
    if d.edges == "wrap" then
      if nx < -W then nx = nx + 2 * W elseif nx > W then nx = nx - 2 * W end
      if ny < -H then ny = ny + 2 * H elseif ny > H then ny = ny - 2 * H end
    else
      if nx < -W then nx, vx = -W, math.abs(vx) elseif nx > W then nx, vx = W, -math.abs(vx) end
      if ny < -H then ny, vy = -H, math.abs(vy) elseif ny > H then ny, vy = H, -math.abs(vy) end
    end
    b[1], b[2], b[3], b[4] = nx, ny, vx, vy
  end
end

-- how they look: a triangle each, pointing where it flies (a node's tris)
function M.look(d, st, out)
  out = out or {}
  local t = out.tris or {}
  local n = 0
  local s = d.size
  for _, b in ipairs(st.b) do
    local vx, vy = b[3], b[4]
    local l = sqrt(vx * vx + vy * vy)
    local ux, uy = 1, 0
    if l > 0 then ux, uy = vx / l, vy / l end
    local x, y = b[1], b[2]
    t[n + 1], t[n + 2] = x + ux * s, y + uy * s
    t[n + 3], t[n + 4] = x - ux * s * 0.6 - uy * s * 0.45, y - uy * s * 0.6 + ux * s * 0.45
    t[n + 5], t[n + 6] = x - ux * s * 0.6 + uy * s * 0.45, y - uy * s * 0.6 - ux * s * 0.45
    n = n + 6
  end
  for i = #t, n + 1, -1 do t[i] = nil end
  out.tris = t
  return out
end
-- or a bullets component: each boid a picture, turned the way it flies, shaded between the two colours
function M.dots(d, st, out)
  out = out or {}
  local xy, a, rgb = out.xy or {}, out.a or {}, out.rgb or {}
  local c1, c2 = d.color, d.color2
  for i, b in ipairs(st.b) do
    xy[i * 2 - 1], xy[i * 2] = b[1], b[2]
    a[i] = atan2(b[4], b[3])
    local k = b[5]
    local r = floor(c1[1] + (c2[1] - c1[1]) * k)
    local g = floor(c1[2] + (c2[2] - c1[2]) * k)
    local bl = floor(c1[3] + (c2[3] - c1[3]) * k)
    rgb[i] = r * 65536 + g * 256 + bl
  end
  local n = #st.b
  for i = #xy, n * 2 + 1, -1 do xy[i] = nil end
  for i = #a, n + 1, -1 do a[i], rgb[i] = nil, nil end
  out.xy, out.a, out.rgb, out.size = xy, a, rgb, out.size or d.size * 2
  return out
end

M.methods = { __index = {
  new = function(d, seed, count) return M.new(d, seed, count) end,
  step = function(d, st, dt, opts) return M.step(d, st, dt, opts) end,
  look = function(d, st, out) return M.look(d, st, out) end,
  dots = function(d, st, out) return M.dots(d, st, out) end,
  preset = function(d, name)                       -- another kind (birds, fish, bats, bees, sheep) in this one's field
    local p = M.check(M.preset(name))
    p.field, p.edges = M.copy(d.field), d.edges
    return setmetatable(p, M.methods)
  end,
} }

-- games: w:flock("birds.flock") -> its settings, checked, with the methods; read again when it changes
local ok, ecs = pcall(require, "ecs")
if ok and type(ecs) == "table" and ecs.assets then
  local cache = {}
  local World = getmetatable(ecs.world()).__index
  function World:flock(name)
    name = tostring(name):gsub("^/assets/", ""):gsub("^/", "")
    if not name:find("%.%w+$") then name = name .. ".flock" end
    local text = ecs.assets.read(name)
    if not text then return nil, "no asset " .. name end
    local c = cache[name]
    if not c or c.text ~= text then
      local raw = ecs.decode(text, name)
      c = { text = text, d = setmetatable(M.check(raw), M.methods) }
      cache[name] = c
    end
    return c.d
  end
end
return M
