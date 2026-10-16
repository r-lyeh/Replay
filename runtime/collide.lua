-- collide.lua - 2D collision helpers for games: overlap tests with a push-out,
-- swept tests (nothing tunnels at speed), rays, a reflect, a spatial grid, and
-- the shapes of nodes (rect / circle components at their xform). Plain math
-- on numbers: no world needed, so systems call it as they like. In a system
-- it's the global `collide` (ecs.code_globals); elsewhere require "collide".
--
-- Boxes are centre + half sizes (x, y, hw, hh), axis-aligned; circles x, y, r.
-- A hit gives the normal (nx, ny: unit, pointing from the other shape to the
-- first) and the depth to move the first along it to separate them.
--   collide.circle_circle(ax, ay, ar, bx, by, br)          -> hit, nx, ny, depth
--   collide.circle_box(cx, cy, r, bx, by, hw, hh)          -> hit, nx, ny, depth
--   collide.box_box(ax, ay, ahw, ahh, bx, by, bhw, bhh)    -> hit, nx, ny, depth
--   collide.point_box(px, py, bx, by, hw, hh) / point_circle(px, py, cx, cy, r) -> inside?
--   collide.ray_box(x1, y1, x2, y2, bx, by, hw, hh)        -> t (0..1), nx, ny | nil
--   collide.ray_circle(x1, y1, x2, y2, cx, cy, r)          -> t, nx, ny | nil
--   collide.sweep_circle_box(cx, cy, r, dx, dy, bx, by, hw, hh)   -> t, nx, ny | nil
--   collide.sweep_circle_circle(ax, ay, ar, dx, dy, bx, by, br)   -> t, nx, ny | nil
--   collide.sweep_box_box(ax, ay, ahw, ahh, dx, dy, bx, by, bhw, bhh) -> t, nx, ny | nil
--     (moving the first by dx, dy: the fraction t of it where they touch; 0 if
--     they overlap already. Move t of the way, then reflect or slide.)
--   collide.reflect(vx, vy, nx, ny [, bounce = 1]) -> vx, vy   (only when moving into it)
--   collide.slide(vx, vy, nx, ny) -> vx, vy                    (the part along the surface)
--   collide.shape(node) -> "box", x, y, hw, hh | "circle", x, y, r | nil   (rect / circle at xform, scaled by xform.s)
--   collide.test(a, b) -> hit, nx, ny, depth                   (two nodes' shapes)
--   local g = collide.grid(64); g:add(key, x, y, hw, hh); g:near(x, y, hw, hh) -> keys; g:clear()
local M = {}
local sqrt, abs, huge = math.sqrt, math.abs, math.huge

local function unit(x, y)
  local l = sqrt(x * x + y * y)
  if l == 0 then return 0, -1, 0 end
  return x / l, y / l, l
end

function M.point_box(px, py, bx, by, hw, hh) return abs(px - bx) <= hw and abs(py - by) <= hh end
function M.point_circle(px, py, cx, cy, r) return (px - cx) ^ 2 + (py - cy) ^ 2 <= r * r end

function M.circle_circle(ax, ay, ar, bx, by, br)
  local dx, dy = ax - bx, ay - by
  local rr = ar + br
  if dx * dx + dy * dy > rr * rr then return false end
  local nx, ny, d = unit(dx, dy)
  return true, nx, ny, rr - d
end

function M.circle_box(cx, cy, r, bx, by, hw, hh)
  local qx = math.max(bx - hw, math.min(bx + hw, cx))   -- the box's point nearest the centre
  local qy = math.max(by - hh, math.min(by + hh, cy))
  local dx, dy = cx - qx, cy - qy
  local d2 = dx * dx + dy * dy
  if d2 > r * r then return false end
  if d2 > 0 then
    local nx, ny, d = unit(dx, dy)
    return true, nx, ny, r - d
  end
  local ox, oy = hw - abs(cx - bx), hh - abs(cy - by)   -- (the centre inside: out the nearest side)
  if ox < oy then return true, cx < bx and -1 or 1, 0, ox + r end
  return true, 0, cy < by and -1 or 1, oy + r
end

function M.box_box(ax, ay, ahw, ahh, bx, by, bhw, bhh)
  local ox = ahw + bhw - abs(ax - bx)
  local oy = ahh + bhh - abs(ay - by)
  if ox < 0 or oy < 0 then return false end
  if ox < oy then return true, ax < bx and -1 or 1, 0, ox end
  return true, 0, ay < by and -1 or 1, oy
end

-- a segment against a box (the slab method) -> t, normal of the side it enters by
function M.ray_box(x1, y1, x2, y2, bx, by, hw, hh)
  local dx, dy = x2 - x1, y2 - y1
  local t0, t1, nx, ny = 0, 1, 0, 0
  if M.point_box(x1, y1, bx, by, hw, hh) then
    local _, ex, ey = M.box_box(x1, y1, 0, 0, bx, by, hw, hh)   -- (inside already: t 0, out the nearest side)
    return 0, ex, ey
  end
  for axis = 1, 2 do
    local p, d, lo, hi = x1, dx, bx - hw, bx + hw
    if axis == 2 then p, d, lo, hi = y1, dy, by - hh, by + hh end
    if d == 0 then
      if p < lo or p > hi then return nil end
    else
      local ta, tb = (lo - p) / d, (hi - p) / d
      local n = -1
      if ta > tb then ta, tb, n = tb, ta, 1 end
      if ta > t0 then t0 = ta; if axis == 1 then nx, ny = n, 0 else nx, ny = 0, n end end
      if tb < t1 then t1 = tb end
      if t0 > t1 then return nil end
    end
  end
  return t0, nx, ny
end

function M.ray_circle(x1, y1, x2, y2, cx, cy, r)
  local dx, dy = x2 - x1, y2 - y1
  local fx, fy = x1 - cx, y1 - cy
  local c = fx * fx + fy * fy - r * r
  if c <= 0 then local nx, ny = unit(fx, fy); return 0, nx, ny end   -- (inside already)
  local a = dx * dx + dy * dy
  if a == 0 then return nil end
  local b = 2 * (fx * dx + fy * dy)
  local disc = b * b - 4 * a * c
  if disc < 0 then return nil end
  local t = (-b - sqrt(disc)) / (2 * a)
  if t < 0 or t > 1 then return nil end
  local nx, ny = unit(fx + dx * t, fy + dy * t)
  return t, nx, ny
end

function M.sweep_circle_circle(ax, ay, ar, dx, dy, bx, by, br)
  return M.ray_circle(ax, ay, ax + dx, ay + dy, bx, by, ar + br)
end

-- a moving circle against a box: the box grown by r (its sides), and circles
-- of r at its corners (rounded, as a ball really meets a corner)
function M.sweep_circle_box(cx, cy, r, dx, dy, bx, by, hw, hh)
  local bt, bnx, bny
  local function try(t, nx, ny) if t and (not bt or t < bt) then bt, bnx, bny = t, nx, ny end end
  local qx = math.max(bx - hw, math.min(bx + hw, cx))
  local qy = math.max(by - hh, math.min(by + hh, cy))
  if (cx - qx) ^ 2 + (cy - qy) ^ 2 <= r * r then   -- (touching already)
    local _, nx, ny = M.circle_box(cx, cy, r, bx, by, hw, hh)
    return 0, nx, ny
  end
  local x2, y2 = cx + dx, cy + dy
  try(M.ray_box(cx, cy, x2, y2, bx, by, hw + r, hh))
  try(M.ray_box(cx, cy, x2, y2, bx, by, hw, hh + r))
  for sx = -1, 1, 2 do
    for sy = -1, 1, 2 do try(M.ray_circle(cx, cy, x2, y2, bx + sx * hw, by + sy * hh, r)) end
  end
  return bt, bnx, bny
end

function M.sweep_box_box(ax, ay, ahw, ahh, dx, dy, bx, by, bhw, bhh)
  return M.ray_box(ax, ay, ax + dx, ay + dy, bx, by, ahw + bhw, ahh + bhh)
end

function M.reflect(vx, vy, nx, ny, bounce)
  local d = vx * nx + vy * ny
  if d >= 0 then return vx, vy end                -- (moving away already)
  local k = (1 + (bounce or 1)) * d
  return vx - k * nx, vy - k * ny
end
function M.slide(vx, vy, nx, ny)
  local d = vx * nx + vy * ny
  if d >= 0 then return vx, vy end
  return vx - d * nx, vy - d * ny
end

-- a node's shape: its rect (w, h) or circle (r) at its xform (x, y, s)
function M.shape(n)
  local c = n and (n.c or n)
  local x = c and c.xform
  if not x then return nil end
  local s = tonumber(x.s) or 1
  if type(c.rect) == "table" then return "box", x.x or 0, x.y or 0, (c.rect.w or 0) * s / 2, (c.rect.h or 0) * s / 2 end
  if type(c.circle) == "table" then return "circle", x.x or 0, x.y or 0, (c.circle.r or 0) * s end
  return nil
end
function M.test(a, b)
  local ka, ax, ay, a3, a4 = M.shape(a)
  local kb, bx, by, b3, b4 = M.shape(b)
  if not ka or not kb then return false end
  if ka == "box" and kb == "box" then return M.box_box(ax, ay, a3, a4, bx, by, b3, b4) end
  if ka == "circle" and kb == "circle" then return M.circle_circle(ax, ay, a3, bx, by, b3) end
  if ka == "circle" then return M.circle_box(ax, ay, a3, bx, by, b3, b4) end
  local hit, nx, ny, d = M.circle_box(bx, by, b3, ax, ay, a3, a4)   -- (a box against a circle: the other way round)
  if hit then return true, -nx, -ny, d end
  return false
end

-- a uniform grid: keys in the cells they cover; near() lists each once
local Grid = {}
Grid.__index = Grid
function M.grid(cell) return setmetatable({ cell = cell or 64, cells = {}, n = 0 }, Grid) end
function Grid:clear() self.cells = {}; self.n = 0 end
local function span(g, x, y, hw, hh)
  local c = g.cell
  return math.floor((x - hw) / c), math.floor((y - hh) / c), math.floor((x + hw) / c), math.floor((y + hh) / c)
end
function Grid:add(key, x, y, hw, hh)
  local x0, y0, x1, y1 = span(self, x, y, hw or 0, hh or hw or 0)
  for gy = y0, y1 do
    for gx = x0, x1 do
      local k = gx .. "," .. gy
      local l = self.cells[k]
      if not l then l = {}; self.cells[k] = l end
      l[#l + 1] = key
    end
  end
  self.n = self.n + 1
end
function Grid:near(x, y, hw, hh)
  local x0, y0, x1, y1 = span(self, x, y, hw or 0, hh or hw or 0)
  local out, seen = {}, {}
  for gy = y0, y1 do
    for gx = x0, x1 do
      for _, key in ipairs(self.cells[gx .. "," .. gy] or {}) do
        if not seen[key] then seen[key] = true; out[#out + 1] = key end
      end
    end
  end
  return out
end

return M
