-- path.lua - pathfinding for games (and the tilemap editor's Path tool): A*
-- on grids (4 or 8 ways, no cutting corners, costs per cell), jump point
-- search on big uniform grids, A* on any graph, smoothing (line of sight), and
-- flow fields (many units heading for one place). Plain Lua, no world needed;
-- in a system it's w:path(...) (and the global `path`); elsewhere require "path".
--
--   local g = path.grid(w, h, solid [, cost])   solid(x, y) -> true (cells 0-based, outside: solid);
--                                               cost(x, y) -> how dear a cell is (1: plain)
--   path.find(g, sx, sy, tx, ty [, opts]) -> { { x, y }... } cells | nil, info
--     opts: diagonal = true (8 ways; false: 4), jps = true (jump point search:
--     8 ways, uniform cost only), max = 100000 (cells looked at, at most),
--     smooth = false (true: path.smooth after)
--     info: { cost, visited = n, closed = { [i] = true } (i = y * w + x: what it looked at) }
--   path.smooth(g, cells) -> fewer cells: each one sees the next (straight lines)
--   path.flow(g, tx, ty [, opts]) -> field: f.dist[i], f:dir(x, y) -> dx, dy (to the next cell; 0, 0 there or no way)
--   path.search(start, goal, neighbours, heuristic [, max]) -> list | nil, cost
--     any graph: neighbours(n) -> { { m, cost }... }, heuristic(n, goal) -> a guess (never more than the real cost)
--   path.from_map(map, opts) -> a grid of a tilemap's layer (opts.layer = "ground" or { "walls", "decor" },
--     opts.solid = { tiles } | function(tile) -> bool (default: any tile), opts.open = { tiles that aren't })
-- In a game: w:path({ x, y }, { x, y }, { map = "level1.tmap", layer = "ground", tile = 16, ox = -240, oy = -136 })
--   -> world points (cell centres), smoothed; nil if there's no way.
local M = {}
local sqrt, abs, huge, floor = math.sqrt, math.abs, math.huge, math.floor
local SQ2 = sqrt(2)

-- a binary heap of (priority, value)
local function heap() return { n = 0, k = {}, v = {} } end
local function push(h, k, v)
  local n = h.n + 1
  h.n = n
  local K, V = h.k, h.v
  while n > 1 do
    local p = floor(n / 2)
    if K[p] <= k then break end
    K[n], V[n] = K[p], V[p]
    n = p
  end
  K[n], V[n] = k, v
end
local function pop(h)
  local K, V, n = h.k, h.v, h.n
  if n == 0 then return nil end
  local top, tk = V[1], K[1]
  local lk, lv = K[n], V[n]
  K[n], V[n] = nil, nil
  n = n - 1
  h.n = n
  local i = 1
  while true do
    local c = i * 2
    if c > n then break end
    if c < n and K[c + 1] < K[c] then c = c + 1 end
    if K[c] >= lk then break end
    K[i], V[i] = K[c], V[c]
    i = c
  end
  if n > 0 then K[i], V[i] = lk, lv end
  return top, tk
end
M.heap, M.push, M.pop = heap, push, pop

function M.grid(w, h, solid, cost)
  local g = { w = w, h = h, solid = solid, cost = cost }
  g.blocked = function(x, y) return x < 0 or y < 0 or x >= w or y >= h or (solid and solid(x, y)) and true or false end
  return g
end
local DIRS8 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local function octile(dx, dy) dx, dy = abs(dx), abs(dy); return (dx + dy) + (SQ2 - 2) * math.min(dx, dy) end

local function rebuild(g, came, i)
  local out = {}
  while i do
    out[#out + 1] = { i % g.w, floor(i / g.w) }
    i = came[i]
  end
  for a = 1, floor(#out / 2) do out[a], out[#out + 1 - a] = out[#out + 1 - a], out[a] end
  return out
end

local function astar(g, sx, sy, tx, ty, opts)
  local W, B, cost = g.w, g.blocked, g.cost
  local diag = opts.diagonal ~= false
  local ndir = diag and 8 or 4
  local start, goal = sy * W + sx, ty * W + tx
  local gs, came, closed = { [start] = 0 }, {}, {}
  local open = heap()
  local hfun = diag and octile or function(dx, dy) return abs(dx) + abs(dy) end
  push(open, hfun(tx - sx, ty - sy), start)
  local visited, max = 0, opts.max or 100000
  while open.n > 0 do
    local i = pop(open)
    if not closed[i] then
      if i == goal then return rebuild(g, came, i), { cost = gs[i], visited = visited, closed = closed } end
      closed[i] = true
      visited = visited + 1
      if visited > max then break end
      local x, y = i % W, floor(i / W)
      for d = 1, ndir do
        local dx, dy = DIRS8[d][1], DIRS8[d][2]
        local nx, ny = x + dx, y + dy
        if not B(nx, ny) and (dx == 0 or dy == 0 or (not B(x + dx, y) and not B(x, y + dy))) then   -- (no cutting a corner)
          local j = ny * W + nx
          if not closed[j] then
            local step = (dx ~= 0 and dy ~= 0) and SQ2 or 1
            local c = gs[i] + step * (cost and cost(nx, ny) or 1)
            if not gs[j] or c < gs[j] then
              gs[j], came[j] = c, i
              push(open, c + hfun(tx - nx, ty - ny), j)
            end
          end
        end
      end
    end
  end
  return nil, { visited = visited, closed = closed }
end

-- jump point search (Harabor & Grastien), the no-corner-cutting variant: from
-- each point, run straight until something forces a turn; only those points
-- go in the open list. The same paths as A* on a uniform 8-way grid, much less work.
local function jps(g, sx, sy, tx, ty, opts)
  local W, B = g.w, g.blocked
  local function free(x, y) return not B(x, y) end
  local function jump(x, y, dx, dy)
    while true do
      local nx, ny = x + dx, y + dy
      if not free(nx, ny) then return nil end
      if dx ~= 0 and dy ~= 0 and not (free(x + dx, y) and free(x, y + dy)) then return nil end   -- (corner)
      if nx == tx and ny == ty then return nx, ny end
      if dx ~= 0 and dy ~= 0 then
        if jump(nx, ny, dx, 0) or jump(nx, ny, 0, dy) then return nx, ny end
      elseif dx ~= 0 then                          -- (straight: a wall ending beside it forces a turn)
        if (free(nx, ny + 1) and not free(x, y + 1)) or (free(nx, ny - 1) and not free(x, y - 1)) then return nx, ny end
      else
        if (free(nx + 1, ny) and not free(x + 1, y)) or (free(nx - 1, ny) and not free(x - 1, y)) then return nx, ny end
      end
      x, y = nx, ny
    end
  end
  local function sign(v) return v > 0 and 1 or v < 0 and -1 or 0 end
  local function neighbours(x, y, px, py)          -- (the ways worth trying from here, coming from px, py)
    if not px then return DIRS8 end
    local dx, dy = sign(x - px), sign(y - py)
    local out = {}
    if dx ~= 0 and dy ~= 0 then
      out[#out + 1] = { dx, 0 }; out[#out + 1] = { 0, dy }; out[#out + 1] = { dx, dy }
    elseif dx ~= 0 then
      out[#out + 1] = { dx, 0 }
      for _, s in ipairs({ 1, -1 }) do
        if free(x, y + s) then out[#out + 1] = { 0, s }; out[#out + 1] = { dx, s } end
      end
    else
      out[#out + 1] = { 0, dy }
      for _, s in ipairs({ 1, -1 }) do
        if free(x + s, y) then out[#out + 1] = { s, 0 }; out[#out + 1] = { s, dy } end
      end
    end
    return out
  end
  local start, goal = sy * W + sx, ty * W + tx
  local gs, came, closed = { [start] = 0 }, {}, {}
  local open = heap()
  push(open, octile(tx - sx, ty - sy), start)
  local visited, max = 0, opts.max or 100000
  while open.n > 0 do
    local i = pop(open)
    if not closed[i] then
      local x, y = i % W, floor(i / W)
      if i == goal then
        local pts = rebuild(g, came, i)            -- (jump points: filled in between)
        local out = { pts[1] }
        for k = 2, #pts do
          local ax, ay, bx, by = pts[k - 1][1], pts[k - 1][2], pts[k][1], pts[k][2]
          local ddx, ddy = sign(bx - ax), sign(by - ay)
          while ax ~= bx or ay ~= by do ax, ay = ax + ddx, ay + ddy; out[#out + 1] = { ax, ay } end
        end
        return out, { cost = gs[i], visited = visited, closed = closed }
      end
      closed[i] = true
      visited = visited + 1
      if visited > max then break end
      local p = came[i]
      for _, d in ipairs(neighbours(x, y, p and p % W, p and floor(p / W))) do
        local jx, jy = jump(x, y, d[1], d[2])
        if jx then
          local j = jy * W + jx
          if not closed[j] then
            local c = gs[i] + octile(jx - x, jy - y)
            if not gs[j] or c < gs[j] then
              gs[j], came[j] = c, i
              push(open, c + octile(tx - jx, ty - jy), j)
            end
          end
        end
      end
    end
  end
  return nil, { visited = visited, closed = closed }
end

function M.find(g, sx, sy, tx, ty, opts)
  opts = opts or {}
  sx, sy, tx, ty = floor(sx), floor(sy), floor(tx), floor(ty)
  if g.blocked(sx, sy) or g.blocked(tx, ty) then return nil, { visited = 0, closed = {} } end
  local cells, info
  if opts.jps and opts.diagonal ~= false and not g.cost then cells, info = jps(g, sx, sy, tx, ty, opts)
  else cells, info = astar(g, sx, sy, tx, ty, opts) end
  if cells and opts.smooth then cells = M.smooth(g, cells) end
  return cells, info
end

-- can a straight line go from cell a to cell b (every cell it passes through free)?
function M.sees(g, ax, ay, bx, by)
  local dx, dy = abs(bx - ax), abs(by - ay)
  local sx, sy = bx > ax and 1 or -1, by > ay and 1 or -1
  local x, y, err = ax, ay, dx - dy
  dx, dy = dx * 2, dy * 2
  while true do                                    -- (every cell the line touches: a "supercover" walk)
    if g.blocked(x, y) then return false end
    if x == bx and y == by then return true end
    if err > 0 then x, err = x + sx, err - dy
    elseif err < 0 then y, err = y + sy, err + dx
    else                                           -- (through a corner: both neighbours must be free)
      if g.blocked(x + sx, y) or g.blocked(x, y + sy) then return false end
      x, y, err = x + sx, y + sy, err - dy + dx
    end
  end
end
function M.smooth(g, cells)
  if not cells or #cells < 3 then return cells end
  local out, i = { cells[1] }, 1
  while i < #cells do
    local j = #cells
    while j > i + 1 and not M.sees(g, cells[i][1], cells[i][2], cells[j][1], cells[j][2]) do j = j - 1 end
    out[#out + 1] = cells[j]
    i = j
  end
  return out
end

-- a flow field: every cell's distance to (tx, ty), and the way to go from it
local Flow = {}
Flow.__index = Flow
function M.flow(g, tx, ty, opts)
  opts = opts or {}
  local W, B, cost = g.w, g.blocked, g.cost
  local dist = {}
  local open = heap()
  local goal = ty * W + tx
  if not B(tx, ty) then dist[goal] = 0; push(open, 0, goal) end
  while open.n > 0 do
    local i, d = pop(open)
    if d <= dist[i] then
      local x, y = i % W, floor(i / W)
      for k = 1, opts.diagonal == false and 4 or 8 do
        local dx, dy = DIRS8[k][1], DIRS8[k][2]
        local nx, ny = x + dx, y + dy
        if not B(nx, ny) and (dx == 0 or dy == 0 or (not B(x + dx, y) and not B(x, y + dy))) then
          local j = ny * W + nx
          local c = d + ((dx ~= 0 and dy ~= 0) and SQ2 or 1) * (cost and cost(x, y) or 1)
          if not dist[j] or c < dist[j] then dist[j] = c; push(open, c, j) end
        end
      end
    end
  end
  return setmetatable({ g = g, dist = dist, tx = tx, ty = ty }, Flow)
end
function Flow:dir(x, y)                            -- the neighbour nearest the goal: dx, dy (0, 0: there, or no way)
  local W, B = self.g.w, self.g.blocked
  x, y = floor(x), floor(y)
  local here = self.dist[y * W + x]
  if not here or here == 0 then return 0, 0 end
  local best, bx, by = here, 0, 0
  for k = 1, 8 do
    local dx, dy = DIRS8[k][1], DIRS8[k][2]
    local d = self.dist[(y + dy) * W + (x + dx)]
    if d and d < best and not B(x + dx, y + dy) and (dx == 0 or dy == 0 or (not B(x + dx, y) and not B(x, y + dy))) then
      best, bx, by = d, dx, dy
    end
  end
  return bx, by
end
function Flow:distance(x, y) return self.dist[floor(y) * self.g.w + floor(x)] end

-- A* on any graph
function M.search(start, goal, neighbours, heuristic, max)
  heuristic = heuristic or function() return 0 end
  local gs, came, closed, key = { [start] = 0 }, {}, {}, 0
  local open = heap()
  push(open, heuristic(start, goal), start)
  local n = 0
  while open.n > 0 do
    local cur = pop(open)
    if not closed[cur] then
      if cur == goal then
        local out = {}
        while cur ~= nil do table.insert(out, 1, cur); cur = came[cur] end
        return out, gs[goal]
      end
      closed[cur] = true
      n = n + 1
      if max and n > max then return nil end
      for _, e in ipairs(neighbours(cur) or {}) do
        local m, c = e[1], gs[cur] + (e[2] or 1)
        if not closed[m] and (gs[m] == nil or c < gs[m]) then
          gs[m], came[m] = c, cur
          push(open, c + heuristic(m, goal), m)
        end
      end
    end
  end
  return nil
end

-- a tilemap's layer (plugins/tilemap's data: { w, h, layers = { { name, rows } } }) as a grid
function M.from_map(map, opts)
  opts = opts or {}
  local names = type(opts.layer) == "table" and opts.layer or { opts.layer or "ground" }   -- (one layer, or several: { "walls", "decor" })
  local layers = {}
  for _, nm in ipairs(names) do for _, l in ipairs(map.layers or {}) do if l.name == nm then layers[#layers + 1] = l end end end
  if #layers == 0 and (map.layers or {})[1] then layers[1] = map.layers[1] end
  local solid_set, open_set = {}, {}
  if type(opts.solid) == "table" then for _, t in ipairs(opts.solid) do solid_set[t] = true end end
  if type(opts.open) == "table" then for _, t in ipairs(opts.open) do open_set[t] = true end end
  local cells = {}
  local W, H = map.w or 0, map.h or #((layers[1] or {}).rows or {})
  local D = map.digits == 4 and 4 or 2             -- (hex digits a cell: 4 for a tileset of more than 256 tiles)
  for _, layer in ipairs(layers) do
    local rows = layer.rows or {}
    for y = 0, H - 1 do
      local row = rows[y + 1] or ""
      for x = 0, W - 1 do
        local s = row:sub(x * D + 1, x * D + D)
        local t = (s ~= "" and not s:find("%.")) and tonumber(s, 16) or nil
        local blocked
        if t == nil then blocked = false
        elseif open_set[t] then blocked = false
        elseif type(opts.solid) == "function" then blocked = opts.solid(t) and true or false
        elseif type(opts.solid) == "table" then blocked = solid_set[t] or false
        else blocked = true end
        if blocked then cells[y * W + x] = true end
      end
    end
  end
  return M.grid(W, H, function(x, y) return cells[y * W + x] end)
end

local ok, ecs = pcall(require, "ecs")
if ok and type(ecs) == "table" and ecs.code_globals then
  ecs.code_globals.path = M
  local World = getmetatable(ecs.world()).__index
  local cache = {}
  function World:path(from, to, opts)
    opts = opts or {}
    local g = opts.grid
    if not g and opts.map then
      local lk = type(opts.layer) == "table" and table.concat(opts.layer, ",") or tostring(opts.layer)
      local key = type(opts.map) == "string" and (opts.map .. "|" .. lk) or opts.map
      local map = type(opts.map) == "string" and self:asset(opts.map) or opts.map
      if type(map) ~= "table" then return nil, "no map " .. tostring(opts.map) end
      local c = cache[key]
      if not c or c.map ~= map then c = { map = map, g = M.from_map(map, opts) }; cache[key] = c end
      g = c.g
    end
    if not g then return nil, "w:path: opts.map or opts.grid" end
    local ts, ox, oy = opts.tile or (type(opts.map) == "table" and opts.map.tile) or 16, opts.ox or 0, opts.oy or 0
    local function cell(p) return floor(((p.x or p[1]) - ox) / ts), floor(((p.y or p[2]) - oy) / ts) end
    local sx, sy = cell(from)
    local tx, ty = cell(to)
    local cells, info = M.find(g, sx, sy, tx, ty, { diagonal = opts.diagonal, jps = opts.jps, smooth = opts.smooth ~= false, max = opts.max })
    if not cells then return nil, info end
    local out = {}
    for i, c in ipairs(cells) do out[i] = { x = ox + (c[1] + 0.5) * ts, y = oy + (c[2] + 0.5) * ts } end
    return out, info
  end
end
return M
