-- ties.lua - canvas.ties: wires tied together, for any node editor (the node
-- graph's ties.lua, canvas.GraphView: the material editor). Geometry and
-- drawing only, in screen space; who keeps the ties (the text, a file's data)
-- is the caller's.
--
-- A tie holds wires the way a cable tie does: through it they lie side by
-- side, in the order that crosses least, for a short straight stretch (the
-- tie's width: more wires, a longer one), along the direction they pull it
-- (the mean of where each comes from and goes to); either side they ease in
-- and out over a long curve, so a bundle between two ties stays parallel
-- ("zipped") and fans out near its ends. One wire: a control point it bends
-- through (no stretch). The bar is drawn across the bundle.
--
--   local TI = require "plugins.canvas.ties"
--   local info = TI.route(wires, centre_of, z)
--     wires: { { x1, y1, x2, y2, via = { tie, ... }, t1 = { dx, dy }, t2 = { dx, dy } } ... }
--       (screen; t1 / t2: the pins' directions, default to the right; via:
--       the caller's tie objects, in order)
--     centre_of(tie) -> x, y (screen)
--     -> info: info.segs[wire] (cubics: { x1, y1, c1x, c1y, c2x, c2y, x2, y2 }),
--        info.centre[tie], info.dir[tie], info.count[tie]
--   TI.plain(x1, y1, x2, y2, z) -> segs        a wire with no ties (Blender's curve)
--   TI.near(segs, x, y, r), TI.at(seg, t), TI.mid(segs)
--   TI.hits(list, x1, y1, x2, y2 [, reach]) -> { { item, k, t, x, y } } (list: { { item, segs } }),
--     the wires a drawn line crosses, nearest its start first; k: in which curve;
--     the line reaches back `reach` px (default 6) before its start: the wire pressed on counts
--   TI.tie_at(info, ties, x, y, z) -> the tie whose bar is under (x, y)
--   TI.crosses_tie(info, ties, x1, y1, x2, y2, z) -> the tie a line crosses
--   TI.draw(info, ties, hot, z), TI.draw_line(x1, y1, x2, y2, hint)
--   TI.hint(n, joining) -> "Tie 3 wires" / "Add a control point" / ...
local style = require "core.style"
local D = require "plugins.canvas.draw"
local T = require "plugins.canvas.theme"
local rgb, alpha, C = T.rgb, T.alpha, T.C

local M = {}
M.GAP = 6                                          -- world units between the wires in a tie
M.EASE = 0.5                                       -- a curve's handle at a tie: this much of its length (long: zipped)
local TIE_C, TIE_EDGE, LINE = rgb"#c9ccd6", rgb"#1b1c22", rgb"#7aa8ff"

local function unit(x, y)
  local l = math.sqrt(x * x + y * y)
  if l == 0 then return 1, 0, 0 end
  return x / l, y / l, l
end
function M.at(s, t)
  local u = 1 - t
  return u * u * u * s[1] + 3 * u * u * t * s[3] + 3 * u * t * t * s[5] + t * t * t * s[7],
         u * u * u * s[2] + 3 * u * u * t * s[4] + 3 * u * t * t * s[6] + t * t * t * s[8]
end
function M.plain(x1, y1, x2, y2, z)
  local d = math.max(math.abs(x2 - x1) * 0.5, 40 * z)
  return { { x1, y1, x1 + d, y1, x2 - d, y2, x2, y2 } }
end
-- is (x, y) within r of these curves? The distance to the lines between
-- points along each (as many as its length needs: a long wire, or one zoomed
-- in, is as easy to hit all along as a short one; points alone left gaps)
function M.near(segs, x, y, r)
  local r2 = r * r
  for _, s in ipairs(segs) do
    if x >= math.min(s[1], s[3], s[5], s[7]) - r and x <= math.max(s[1], s[3], s[5], s[7]) + r
       and y >= math.min(s[2], s[4], s[6], s[8]) - r and y <= math.max(s[2], s[4], s[6], s[8]) + r then   -- (inside its points' box: worth a look)
      local len = math.abs(s[3] - s[1]) + math.abs(s[4] - s[2]) + math.abs(s[5] - s[3]) + math.abs(s[6] - s[4])
                + math.abs(s[7] - s[5]) + math.abs(s[8] - s[6])
      local n = math.max(8, math.min(256, math.ceil(len / 6)))
      local px, py = s[1], s[2]
      for i = 1, n do
        local cx, cy = M.at(s, i / n)
        local dx, dy = cx - px, cy - py
        local l2 = dx * dx + dy * dy
        local t = l2 > 0 and ((x - px) * dx + (y - py) * dy) / l2 or 0
        t = t < 0 and 0 or t > 1 and 1 or t
        local ex, ey = px + t * dx - x, py + t * dy - y
        if ex * ex + ey * ey <= r2 then return true end
        px, py = cx, cy
      end
    end
  end
  return false
end
function M.mid(segs)
  local s = segs[math.floor((#segs + 1) / 2)]
  return M.at(s, #segs % 2 == 1 and 0.5 or 1)
end
local function stretch(n, z) return n > 1 and (8 + (n - 1) * M.GAP * 0.6) * z or 0 end   -- (the tie's width along the wires)

function M.route(wires, centre_of, z)
  local centre, dir, count, members = {}, {}, {}, {}
  for _, w in ipairs(wires) do
    for k, t in ipairs(w.via or {}) do
      if not centre[t] then
        local x, y = centre_of(t)
        centre[t] = { x, y }
        count[t], members[t] = 0, {}
      end
      count[t] = count[t] + 1
      members[t][#members[t] + 1] = { w, k }
    end
  end
  local function nb(w, k)                          -- the points either side of its k-th tie (centres)
    local px, py, nx, ny = w[1], w[2], w[3], w[4]
    if k > 1 then px, py = centre[w.via[k - 1]][1], centre[w.via[k - 1]][2] end
    if k < #w.via then nx, ny = centre[w.via[k + 1]][1], centre[w.via[k + 1]][2] end
    return px, py, nx, ny
  end
  for t, list in pairs(members) do                 -- the direction the wires pull it: their mean, each way round made the same
    local sx, sy = 0, 0
    for _, m in ipairs(list) do
      local px, py, nx, ny = nb(m[1], m[2])
      local c = centre[t]
      local ax, ay = unit(c[1] - px, c[2] - py)    -- (coming in, and going out: both count)
      local bx, by = unit(nx - c[1], ny - c[2])
      local dx, dy = ax + bx, ay + by
      if sx * dx + sy * dy < 0 then dx, dy = -dx, -dy end
      sx, sy = sx + dx, sy + dy
    end
    local tx, ty = 0, 0                            -- (a tie beside another on its wires: the line between them; glued, straight)
    for _, m in ipairs(list) do
      local w, k = m[1], m[2]
      local c = centre[t]
      if k > 1 then local q = centre[w.via[k - 1]]; local ux, uy = unit(c[1] - q[1], c[2] - q[2]); tx, ty = tx + ux, ty + uy end
      if k < #w.via then local q = centre[w.via[k + 1]]; local ux, uy = unit(q[1] - c[1], q[2] - c[2]); tx, ty = tx + ux, ty + uy end
    end
    if tx * tx + ty * ty > 1e-6 then
      if sx * tx + sy * ty < 0 then tx, ty = -tx, -ty end
      sx, sy = tx, ty
    end
    local x, y, l = unit(sx, sy)
    dir[t] = l > 0 and { x, y } or { 1, 0 }
  end
  -- the order across each tie: by where its wires come from and go to. A tie
  -- next to one already placed (on a wire, either way) takes the order the
  -- wires have there, so a bundle between two ties never crosses itself
  -- (they cross, if they must, outside: where they fan out). The ties with
  -- the most wires first, then in the order they were met (stable).
  local slot, pos, done, seq = {}, {}, {}, {}
  for _, w in ipairs(wires) do
    for _, t in ipairs(w.via or {}) do if not seq[t] then seq[#seq + 1] = t; seq[t] = #seq end end
  end
  local ties_list = {}
  for i = 1, #seq do ties_list[i] = seq[i] end
  table.sort(ties_list, function(a, b) if count[a] ~= count[b] then return count[a] > count[b] end return seq[a] < seq[b] end)
  local function placed(w, k)                      -- the wire's place at its k-th tie, when that tie's done
    local t = w.via[k]
    return t and done[t] and pos[t][w] and pos[t][w][k]
  end
  for _, t in ipairs(ties_list) do
    local list, c, d = members[t], centre[t], dir[t]
    local ax, ay = -d[2], d[1]
    local order = {}
    for i, m in ipairs(list) do
      local w, k = m[1], m[2]
      local px, py, nx, ny = nb(w, k)
      local sgn = ((nx - px) * d[1] + (ny - py) * d[2]) < 0 and -1 or 1
      local ref = placed(w, k - 1) or placed(w, k + 1)
      local key
      if ref then key = 2 * ((ref[1] - c[1]) * ax + (ref[2] - c[2]) * ay)
      else                                         -- (which side its ends lie: by their ways from the tie, not how far:
        local ux, uy = unit(px - c[1], py - c[2])  --  a far end straight along a tilted tie mustn't outweigh a near one beside it)
        local vx, vy = unit(nx - c[1], ny - c[2])
        key = ux * ax + uy * ay + vx * ax + vy * ay
      end
      order[i] = { m = m, key = key, i = i, s = sgn }
    end
    table.sort(order, function(a, b) if a.key ~= b.key then return a.key < b.key end return a.i < b.i end)
    slot[t], pos[t] = {}, {}
    for i, o in ipairs(order) do
      local w, k = o.m[1], o.m[2]
      local off = (i - (#order + 1) / 2) * M.GAP * z
      slot[t][w] = slot[t][w] or {}; slot[t][w][k] = { off, o.s }
      pos[t][w] = pos[t][w] or {}; pos[t][w][k] = { c[1] - d[2] * off, c[2] + d[1] * off }
    end
    done[t] = true
  end
  local segs = {}
  for _, w in ipairs(wires) do
    local pts = { { w[1], w[2], (w.t1 or { 1, 0 })[1], (w.t1 or { 1, 0 })[2], true } }
    for k, t in ipairs(w.via or {}) do
      local c, d = centre[t], dir[t]
      local sl = slot[t][w][k]
      local off, s = sl[1], sl[2]
      local h = stretch(count[t], z) / 2
      local bx, by = c[1] - d[2] * off, c[2] + d[1] * off
      local tx, ty = d[1] * s, d[2] * s
      if h > 0 then                                -- in at one side of the tie, out at the other
        pts[#pts + 1] = { bx - tx * h, by - ty * h, tx, ty, false, straight = true }
        pts[#pts + 1] = { bx + tx * h, by + ty * h, tx, ty, false }
      else pts[#pts + 1] = { bx, by, tx, ty, false } end
    end
    pts[#pts + 1] = { w[3], w[4], (w.t2 or { 1, 0 })[1], (w.t2 or { 1, 0 })[2], true }
    local out = {}
    for k = 1, #pts - 1 do
      local p, q = pts[k], pts[k + 1]
      local dist = math.sqrt((q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2)
      if p.straight then                           -- (through the tie: straight)
        out[#out + 1] = { p[1], p[2], p[1] + p[3] * dist / 3, p[2] + p[4] * dist / 3, q[1] - q[3] * dist / 3, q[2] - q[4] * dist / 3, q[1], q[2] }
      else
        local hp = p[5] and math.max(dist * 0.4, 30 * z) or dist * M.EASE
        local hq = q[5] and math.max(dist * 0.4, 30 * z) or dist * M.EASE
        if not p[5] and not q[5] then hp, hq = dist / 3, dist / 3 end   -- (from a tie to the next: as straight as their directions let it)
        out[#out + 1] = { p[1], p[2], p[1] + p[3] * hp, p[2] + p[4] * hp, q[1] - q[3] * hq, q[2] - q[4] * hq, q[1], q[2] }
      end
    end
    segs[w] = out
  end
  return { segs = segs, centre = centre, dir = dir, count = count }
end

local function bar(info, t, z)
  local c, d, n = info.centre[t], info.dir[t], info.count[t] or 1
  local half = (math.max(0, n - 1) * M.GAP / 2 + 5) * z
  return c, d, half
end
function M.tie_at(info, ties, x, y, z)
  for k = #ties, 1, -1 do
    local t = ties[k]
    if info.centre[t] then
      local c, d, half = bar(info, t, z)
      local rx, ry = x - c[1], y - c[2]
      local along, across = rx * -d[2] + ry * d[1], rx * d[1] + ry * d[2]
      if math.abs(along) <= half + 2 and math.abs(across) <= math.max(6, stretch(info.count[t], z) / 2 + 3) then return t end
    end
  end
end
local function cross(ax, ay, bx, by, cx, cy, dx, dy)
  local rx, ry, sx, sy = bx - ax, by - ay, dx - cx, dy - cy
  local den = rx * sy - ry * sx
  if den == 0 then return nil end
  local t = ((cx - ax) * sy - (cy - ay) * sx) / den
  local u = ((cx - ax) * ry - (cy - ay) * rx) / den
  if t >= 0 and t <= 1 and u >= 0 and u <= 1 then return t end
end
function M.crosses_tie(info, ties, x1, y1, x2, y2, z)
  for _, t in ipairs(ties) do
    if info.centre[t] then
      local c, d, half = bar(info, t, z)
      if cross(x1, y1, x2, y2, c[1] + d[2] * half, c[2] - d[1] * half, c[1] - d[2] * half, c[2] + d[1] * half) then return t end
    end
  end
end
-- the ties whose centres lie in a screen box (the selection box)
function M.in_box(info, ties, x1, y1, x2, y2)
  local out = {}
  if not info then return out end
  x1, x2 = math.min(x1, x2), math.max(x1, x2)
  y1, y2 = math.min(y1, y2), math.max(y1, y2)
  for _, t in ipairs(ties) do
    local c = info.centre[t]
    if c and c[1] >= x1 and c[1] <= x2 and c[2] >= y1 and c[2] <= y2 then out[#out + 1] = t end
  end
  return out
end
-- a short line across these curves at the point nearest (x, y) (screen):
-- x1, y1, x2, y2, r long each side, square to the wire there. A tie gesture
-- along it adds a control point there (double-click on a wire)
function M.cross_at(segs, x, y, r)
  r = r or 6
  local best, bx, by, tx, ty = math.huge
  for _, s in ipairs(segs) do
    local n = 64
    local px, py = s[1], s[2]
    for i = 1, n do
      local cx, cy = M.at(s, i / n)
      local dx, dy = cx - px, cy - py
      local l2 = dx * dx + dy * dy
      local t = l2 > 0 and ((x - px) * dx + (y - py) * dy) / l2 or 0
      t = t < 0 and 0 or t > 1 and 1 or t
      local qx, qy = px + t * dx, py + t * dy
      local d = (qx - x) ^ 2 + (qy - y) ^ 2
      if d < best and l2 > 0 then best, bx, by, tx, ty = d, qx, qy, dx, dy end
      px, py = cx, cy
    end
  end
  if not bx then return nil end
  local len = math.sqrt(tx * tx + ty * ty)
  local nx, ny = -ty / len * r, tx / len * r
  return bx - nx, by - ny, bx + nx, by + ny
end

-- align things ({ x, y, w, h } each; ties: w = h = 0): sets .nx / .ny where
-- each goes. how: left | centre | right | top | middle | bottom | across | down
-- (across / down: the same gap between each, in their order, the ends kept;
-- gap: the least one). For every node editor (the node graph has its own,
-- with Tidy: plugins/nodegraph/arrange.lua)
function M.align(list, how, gap)
  gap = gap or 30
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, b in ipairs(list) do x0, y0, x1, y1 = math.min(x0, b.x), math.min(y0, b.y), math.max(x1, b.x + b.w), math.max(y1, b.y + b.h) end
  if how == "left" then for _, b in ipairs(list) do b.nx = x0 end
  elseif how == "right" then for _, b in ipairs(list) do b.nx = x1 - b.w end
  elseif how == "centre" then local c = (x0 + x1) / 2; for _, b in ipairs(list) do b.nx = c - b.w / 2 end
  elseif how == "top" then for _, b in ipairs(list) do b.ny = y0 end
  elseif how == "bottom" then for _, b in ipairs(list) do b.ny = y1 - b.h end
  elseif how == "middle" then local c = (y0 + y1) / 2; for _, b in ipairs(list) do b.ny = c - b.h / 2 end
  elseif (how == "across" or how == "down") and #list > 1 then
    local ax = how == "across"
    local order = {}
    for i, b in ipairs(list) do order[i] = b end
    table.sort(order, function(p, q) if ax then return p.x < q.x end return p.y < q.y end)
    local total = 0
    for _, b in ipairs(order) do total = total + (ax and b.w or b.h) end
    local g = ((ax and (x1 - x0) or (y1 - y0)) - total) / (#order - 1)
    if g < gap then g = gap end
    local at = ax and x0 or y0
    for _, b in ipairs(order) do
      if ax then b.nx = at; at = at + b.w + g else b.ny = at; at = at + b.h + g end
    end
  end
  return list
end
-- the Align submenu's items: { text, how }; points only (ties): a row, a column, spaced
function M.align_choices(points_only)
  if points_only then
    return { { "Middles (a row)", "middle" }, { "Centres (a column)", "centre" }, { "Space across", "across" }, { "Space down", "down" } }
  end
  return { { "Left edges", "left" }, { "Centres", "centre" }, { "Right edges", "right" }, { "Tops", "top" },
           { "Middles", "middle" }, { "Bottoms", "bottom" }, { "Space across", "across" }, { "Space down", "down" } }
end
function M.hits(list, x1, y1, x2, y2, reach)
  local hits = {}
  local dx, dy, len = unit(x2 - x1, y2 - y1)       -- (started a few pixels inside a wire: that one counts too; the
  if len > 0 then                                  -- line reaches back as far as a press on a wire can be from it)
    reach = reach or 6 * SCALE
    x1, y1 = x1 - dx * reach, y1 - dy * reach
  end
  for _, it in ipairs(list) do
    local best
    for k, s in ipairs(it.segs) do
      local px, py = M.at(s, 0)
      local len = math.abs(s[3] - s[1]) + math.abs(s[4] - s[2]) + math.abs(s[5] - s[3]) + math.abs(s[6] - s[4])
                + math.abs(s[7] - s[5]) + math.abs(s[8] - s[6])
      local n = math.max(24, math.min(256, math.ceil(len / 6)))   -- (close to the curve as drawn: a short line across it counts)
      for i = 1, n do
        local qx, qy = M.at(s, i / n)
        local t = cross(x1, y1, x2, y2, px, py, qx, qy)
        if t and (not best or t < best.t) then best = { t = t, k = k, x = x1 + (x2 - x1) * t, y = y1 + (y2 - y1) * t } end
        px, py = qx, qy
      end
    end
    if best then best.item = it.item; hits[#hits + 1] = best end
  end
  table.sort(hits, function(p, q) return p.t < q.t end)
  return hits
end
function M.hint(n, joining)
  if joining then return n == 1 and "Tie 1 more wire" or ("Tie " .. n .. " more wires") end
  if n == 1 then return "Add a control point" end
  if n > 1 then return "Tie " .. n .. " wires" end
  return "Draw across wires to tie them"
end

-- sel: the selected ties ({ [tie] = true }, or nil): drawn in the selection's colour
function M.draw(info, ties, hot, z, scale, sel)
  scale = scale or SCALE
  for _, t in ipairs(ties) do
    if info.centre[t] then
      local c, d, half = bar(info, t, z)
      local col = hot == t and C.active or (sel and sel[t] and C.sel) or TIE_C
      if (info.count[t] or 0) <= 1 then
        D.disc(c[1], c[2], 5.5 * z * scale, TIE_EDGE)
        D.disc(c[1], c[2], 4 * z * scale, col)
      else
        local ax, ay = -d[2] * half, d[1] * half
        local w = math.max(3, stretch(info.count[t], z) * 0.45)   -- (a strap: as wide as the stretch it holds, a little less)
        D.line(c[1] - ax, c[2] - ay, c[1] + ax, c[2] + ay, TIE_EDGE, w + 2.5 * z * scale)
        D.line(c[1] - ax, c[2] - ay, c[1] + ax, c[2] + ay, col, w)
      end
    end
  end
end
-- the selection box (screen): an unfilled orange rect, as the node graph's
function M.draw_box(x1, y1, x2, y2)
  local bx, by = math.min(x1, x2), math.min(y1, y2)
  local bw, bh = math.abs(x2 - x1), math.abs(y2 - y1)
  local t = math.max(1, SCALE)
  renderer.draw_rect(bx, by, bw, bh, alpha(C.sel, 25))
  renderer.draw_rect(bx, by, bw, t, C.sel); renderer.draw_rect(bx, by + bh - t, bw, t, C.sel)
  renderer.draw_rect(bx, by, t, bh, C.sel); renderer.draw_rect(bx + bw - t, by, t, bh, C.sel)
end
function M.draw_line(x1, y1, x2, y2, hint, scale)
  scale = scale or SCALE
  D.line(x1, y1, x2, y2, LINE, 2 * scale)
  if hint then
    local f = style.font
    local w, h = f:get_width(hint) + 16 * scale, f:get_height() + 10 * scale
    local bx, by = x2 + 14 * scale, y2 + 10 * scale
    D.rrect(bx, by, w, h, 6 * scale, alpha(rgb"#1e1f26", 235))
    renderer.draw_text(f, hint, bx + 8 * scale, by + 5 * scale, style.text)
  end
end

return M
