-- tmap.lua - a tile map's data for games (and the tilemap editor): its cells,
-- its named areas and its splines (plugins/tilemap writes them in a .tmap).
-- Plain Lua, no world needed; in a system it's the global `tmap`; elsewhere
-- require "tmap". A map is what w:asset("level1.tmap") gives: { tileset,
-- tile, w, h, digits, layers = { { name, rows } }, areas = {...}, paths = {...} }.
-- Coordinates are the map's pixels (its top left 0, 0; a cell is `tile` px).
--
--   tmap.cell(map, layer, x, y) -> the tile at cell x, y (0-based) of a layer
--     (its name or number) | false (none) | nil (off the map)
--   areas: { name = "spawn", x, y, w, h } (a rectangle) or { name, points =
--     { x1, y1, x2, y2, ... } } (a polygon), props = { key = value } (yours)
--   tmap.area(map, name) -> the first area of that name | nil
--   tmap.contains(area, x, y) -> is the point inside it
--   tmap.areas_at(map, x, y) -> { areas the point is in }, in the file's order
--   paths: { name = "patrol", points = { x1, y1, ... }, closed = false, props }:
--     a Catmull-Rom spline through its points (a road, a rail, a patrol)
--   tmap.path(map, name) -> the first path of that name | nil
--   tmap.spline(path_or_points [, per, closed]) -> { x1, y1, ... }: points along
--     the curve, `per` (8) a segment, through every control point
--   tmap.length(points) -> its length (a flat list, as spline gives)
--   tmap.at(points, d) -> x, y, angle: where you are `d` along it (clamped)
local M = {}

local function digits(map) return (map and map.digits == 4) and 4 or 2 end
M.digits = digits

function M.cell(map, layer, x, y)
  if type(map) ~= "table" or x < 0 or y < 0 or x >= (map.w or 0) or y >= (map.h or 0) then return nil end
  local l
  for i, ly in ipairs(map.layers or {}) do if i == layer or ly.name == layer then l = ly break end end
  if not l then return nil end
  local d = digits(map)
  local s = ((l.rows or {})[y + 1] or ""):sub(x * d + 1, x * d + d)
  if s == "" or s:find("%.") then return false end
  return tonumber(s, 16) or false
end

function M.contains(a, x, y)
  if type(a) ~= "table" then return false end
  local p = a.points
  if type(p) == "table" and #p >= 6 then         -- a polygon: crossings of a ray to the right
    local inside, n = false, #p / 2
    local j = n
    for i = 1, n do
      local xi, yi, xj, yj = p[i * 2 - 1], p[i * 2], p[j * 2 - 1], p[j * 2]
      if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then inside = not inside end
      j = i
    end
    return inside
  end
  local ax, ay, aw, ah = a.x or 0, a.y or 0, a.w or 0, a.h or 0
  return x >= ax and y >= ay and x < ax + aw and y < ay + ah
end
function M.area(map, name)
  for _, a in ipairs(type(map) == "table" and map.areas or {}) do if a.name == name then return a end end
end
function M.areas_at(map, x, y)
  local out = {}
  for _, a in ipairs(type(map) == "table" and map.areas or {}) do if M.contains(a, x, y) then out[#out + 1] = a end end
  return out
end
function M.path(map, name)
  for _, p in ipairs(type(map) == "table" and map.paths or {}) do if p.name == name then return p end end
end

-- Catmull-Rom (uniform) through the control points; open: the ends doubled
function M.spline(p, per, closed)
  local pts = p
  if type(p) == "table" and type(p.points) == "table" then pts, closed = p.points, (closed == nil) and p.closed or closed end
  per = math.max(1, math.floor(per or 8))
  local n = math.floor(#(pts or {}) / 2)
  if n == 0 then return {} end
  if n == 1 then return { pts[1], pts[2] } end
  local function P(i)
    if closed then i = (i - 1) % n + 1 else i = math.max(1, math.min(n, i)) end
    return pts[i * 2 - 1], pts[i * 2]
  end
  local out = {}
  local segs = closed and n or n - 1
  for s = 1, segs do
    local x0, y0 = P(s - 1)
    local x1, y1 = P(s)
    local x2, y2 = P(s + 1)
    local x3, y3 = P(s + 2)
    for k = 0, per - 1 do
      local t = k / per
      local t2, t3 = t * t, t * t * t
      out[#out + 1] = 0.5 * ((2 * x1) + (-x0 + x2) * t + (2 * x0 - 5 * x1 + 4 * x2 - x3) * t2 + (-x0 + 3 * x1 - 3 * x2 + x3) * t3)
      out[#out + 1] = 0.5 * ((2 * y1) + (-y0 + y2) * t + (2 * y0 - 5 * y1 + 4 * y2 - y3) * t2 + (-y0 + 3 * y1 - 3 * y2 + y3) * t3)
    end
  end
  local lx, ly = P(closed and n + 1 or n)          -- (the last point: the curve ends on it)
  out[#out + 1], out[#out + 2] = lx, ly
  return out
end
function M.length(pts)
  local len = 0
  for i = 3, #pts - 1, 2 do len = len + math.sqrt((pts[i] - pts[i - 2]) ^ 2 + (pts[i + 1] - pts[i - 1]) ^ 2) end
  return len
end
function M.at(pts, d)
  local n = #pts
  if n < 2 then return 0, 0, 0 end
  if n < 4 then return pts[1], pts[2], 0 end
  d = math.max(0, d or 0)
  for i = 3, n - 1, 2 do
    local dx, dy = pts[i] - pts[i - 2], pts[i + 1] - pts[i - 1]
    local seg = math.sqrt(dx * dx + dy * dy)
    if d <= seg or i >= n - 1 then
      local k = seg > 0 and math.min(1, d / seg) or 0
      return pts[i - 2] + dx * k, pts[i - 1] + dy * k, (math.atan2 or math.atan)(dy, dx)
    end
    d = d - seg
  end
  return pts[n - 1], pts[n], 0
end

local ok, ecs = pcall(require, "ecs")
if ok and type(ecs) == "table" and ecs.code_globals then ecs.code_globals.tmap = M end
return M
