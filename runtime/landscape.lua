-- landscape.lua - a landscape: a height field over an area (3D), as UE5's. Its base is made by rules (the
-- generator: hills, or flat), then edited by hand: sculpt, smooth, flatten, erase (back to the generator's).
-- No Lite in it: plugins/landscape edits with it, the renderer draws with it (a node's `landscape3d`:
-- runtime/boot.lua viewer_landscape, editor/render.h), a game reads heights from it (w:landscape).
--
-- A .land (Lua data; every field optional, M.DEFAULTS):
--   w, d        the area, in meters (x across, z deep), centred on the node
--   cells       the grid: that many cells along the longer side (8..256); points every w / cells meters
--   base        the generator: { kind = "hills" | "flat", seed, height (m: its highest), scale (m: its hills'
--               size), octaves (1..8: finer and finer detail), ridges (0..1: sharp crests), sea (0..1: below
--               that share of its height, flat) }
--   edits       the brushes' work, over the base: a row of the grid a string, centimeters up (+) or down (-),
--               "0*40" for 40 zeros running ("" a row with none). None: the base alone
--   colors      the ground's, by height and slope: { low, high, rock, snow = { r, g, b }, rock_slope (0..1: that
--               steep is rock), snow_at (0..1 of the generator's height: above it snow; 1: none) }
--
--   M.check(t) -> settings (defaults filled, numbers in range)
--   M.build(s) -> land: { nx, nz, w, d, h = { heights, row by row from the back (-d/2), x from -w/2 }, base,
--     delta (the edits: m), c = { 0xRRGGBB a point }, ver } (the renderer reads h and c as they are)
--   M.height_at(land, x, z) -> y (bilinear; outside: the nearest edge's)   M.normal_at(land, x, z) -> nx, ny, nz
--     (also land:height_at(x, z), land:normal_at(x, z), land:ray(...): a game's systems have no require)
--   M.ray(land, ox, oy, oz, dx, dy, dz, far) -> t, x, y, z (where a ray first meets it) | nil
--   The brushes (a land changed in place; its ver up, its colours again):
--     M.brush(land, s, mode, x, z, radius, strength, o) mode: "sculpt" (strength < 0 lowers), "smooth", "flatten"
--       (to o.target, else the height under x, z), "erase" (back to the generator's); falloff smooth to the rim.
--       -> how many points changed
--     M.pack(land, s) the edits into s.edits (to save)   M.rebuild(s, old) -> land (built again: old's edits kept,
--     stretched over a grid of another size)   M.recolor(land, s)   M.edited(land) -> points moved
--   w:landscape(name | settings) -> land (an asset's: read again when it changes)
local M = {}

M.DEFAULTS = { w = 64, d = 64, cells = 64,
  base = { kind = "hills", seed = 1, height = 8, scale = 24, octaves = 4, ridges = 0, sea = 0 },
  colors = { low = { 96, 140, 70 }, high = { 130, 150, 90 }, rock = { 125, 118, 108 }, snow = { 240, 242, 248 }, rock_slope = 0.55, snow_at = 1 } }
M.MAX_CELLS = 256

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end
M.copy = copy
local function num(v, def, lo, hi)
  v = tonumber(v) or def
  if v ~= v then v = def end
  if lo and v < lo then v = lo end
  if hi and v > hi then v = hi end
  return v
end
local function rgb(c, def)
  if type(c) ~= "table" then return { def[1], def[2], def[3] } end
  return { num(c[1], def[1], 0, 255), num(c[2], def[2], 0, 255), num(c[3], def[3], 0, 255) }
end

function M.check(t)
  t = type(t) == "table" and t or {}
  local D, s = M.DEFAULTS, {}
  s.w, s.d = num(t.w, D.w, 1, 100000), num(t.d, D.d, 1, 100000)
  s.cells = math.floor(num(t.cells, D.cells, 8, M.MAX_CELLS) + 0.5)
  local b, DB = type(t.base) == "table" and t.base or {}, D.base
  s.base = { kind = (b.kind == "flat" or b.kind == "hills") and b.kind or DB.kind,
             seed = math.floor(num(b.seed, DB.seed)), height = num(b.height, DB.height, 0, 10000),
             scale = num(b.scale, DB.scale, 0.5, 100000), octaves = math.floor(num(b.octaves, DB.octaves, 1, 8) + 0.5),
             ridges = num(b.ridges, DB.ridges, 0, 1), sea = num(b.sea, DB.sea, 0, 1) }
  local c, DC = type(t.colors) == "table" and t.colors or {}, D.colors
  s.colors = { low = rgb(c.low, DC.low), high = rgb(c.high, DC.high), rock = rgb(c.rock, DC.rock), snow = rgb(c.snow, DC.snow),
               rock_slope = num(c.rock_slope, DC.rock_slope, 0, 1), snow_at = num(c.snow_at, DC.snow_at, 0, 1) }
  s.edits = type(t.edits) == "table" and t.edits or nil
  return s
end

-- the grid's size: cells along the longer side, the other in proportion (at least 2)
local function dims(s)
  local nx, nz
  if s.w >= s.d then nx = s.cells; nz = math.max(2, math.floor(s.cells * s.d / s.w + 0.5))
  else nz = s.cells; nx = math.max(2, math.floor(s.cells * s.w / s.d + 0.5)) end
  return nx + 1, nz + 1
end
M.dims = dims

-- value noise: a lattice of randoms from the seed, smoothly blended (fbm: octaves of it, each half as big)
local function hash(seed, ix, iz)                -- (squares mod a prime, mixed both ways: every step under 2^33, whole
  local a = (ix * 7919 + seed * 104729 + 1) % 65521   --  numbers, so LuaJIT and Lua 5.4 agree to the bit)
  local b = (iz * 6271 + seed * 3571 + 2) % 65521
  for _ = 1, 4 do
    a = (a * a + b * 31 + 17) % 65521
    b = (b * b + a * 47 + 29) % 65521
  end
  return (a * 65521 + b) / (65521 * 65521)
end
local function vnoise(seed, x, z)
  local ix, iz = math.floor(x), math.floor(z)
  local fx, fz = x - ix, z - iz
  local ux, uz = fx * fx * (3 - 2 * fx), fz * fz * (3 - 2 * fz)
  local a, b = hash(seed, ix, iz), hash(seed, ix + 1, iz)
  local c, d = hash(seed, ix, iz + 1), hash(seed, ix + 1, iz + 1)
  return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uz
end
function M.base_at(b, x, z)                        -- the generator's height at x, z (m)
  if b.kind == "flat" or b.height <= 0 then return 0 end
  local sum, amp, tot, f = 0, 1, 0, 1 / b.scale
  for o = 1, b.octaves do
    local v = vnoise(b.seed + o * 101, x * f + 31.7, z * f + 17.3)
    if b.ridges > 0 then v = v * (1 - b.ridges) + (1 - math.abs(v * 2 - 1)) * b.ridges end
    sum = sum + v * amp; tot = tot + amp
    amp = amp * 0.5; f = f * 2
  end
  local v = sum / tot                              -- (0..1, mostly 0.2..0.8)
  v = math.max(0, math.min(1, (v - 0.2) / 0.6))
  if b.sea > 0 then v = math.max(0, (v - b.sea) / (1 - b.sea)) end
  return v * b.height
end

local floor = math.floor
function M.base_grid(b, land)                      -- the generator's height at every point of a land (as base_at, the same
  local n, nx, nz, out = land.nx * land.nz, land.nx, land.nz, {}   --  numbers: octave by octave, each lattice corner's hash
  for k = 1, n do out[k] = 0 end                   --  made once, not once for each point round it)
  if b.kind == "flat" or b.height <= 0 then return out end
  local xs, zs = {}, {}
  for i = 1, nx do xs[i] = -land.w / 2 + (i - 1) * land.w / (nx - 1) end
  for j = 1, nz do zs[j] = -land.d / 2 + (j - 1) * land.d / (nz - 1) end
  local sum, amp, tot, f = out, 1, 0, 1 / b.scale
  local ridges = b.ridges
  for o = 1, b.octaves do
    local seed = b.seed + o * 101
    local ix0, iz0 = floor(xs[1] * f + 31.7), floor(zs[1] * f + 17.3)
    local span = floor(xs[nx] * f + 31.7) - ix0 + 2
    local cache = {}
    local function H(ix, iz)
      local key = (iz - iz0) * span + (ix - ix0) + 1
      local v = cache[key]
      if not v then v = hash(seed, ix, iz); cache[key] = v end
      return v
    end
    for j = 1, nz do
      local z = zs[j] * f + 17.3
      local iz = floor(z)
      local fz = z - iz
      local uz = fz * fz * (3 - 2 * fz)
      local row = (j - 1) * nx
      for i = 1, nx do
        local x = xs[i] * f + 31.7
        local ix = floor(x)
        local fx = x - ix
        local ux = fx * fx * (3 - 2 * fx)
        local a, bb = H(ix, iz), H(ix + 1, iz)
        local c, d = H(ix, iz + 1), H(ix + 1, iz + 1)
        local v = (a + (bb - a) * ux) + ((c + (d - c) * ux) - (a + (bb - a) * ux)) * uz
        if ridges > 0 then v = v * (1 - ridges) + (1 - math.abs(v * 2 - 1)) * ridges end
        sum[row + i] = sum[row + i] + v * amp
      end
    end
    tot = tot + amp
    amp = amp * 0.5; f = f * 2
  end
  local height, sea = b.height, b.sea
  for k = 1, n do
    local v = sum[k] / tot
    v = math.max(0, math.min(1, (v - 0.2) / 0.6))
    if sea > 0 then v = math.max(0, (v - sea) / (1 - sea)) end
    out[k] = v * height
  end
  return out
end

-- the edits, read / written: a row a string of centimeters, "0*n" for n zeros running
local function unpack_edits(s, nx, nz)
  local delta = {}
  for i = 1, nx * nz do delta[i] = 0 end
  if not s.edits then return delta end
  for row = 1, nz do
    local str, i = s.edits[row], 0
    if type(str) == "string" then
      for tok in str:gmatch("%S+") do
        local z, n = tok:match("^(-?%d+)%*(%d+)$")
        if z then i = i + tonumber(n)
        else
          i = i + 1
          if i <= nx then delta[(row - 1) * nx + i] = (tonumber(tok) or 0) / 100 end
        end
      end
    end
  end
  return delta
end
function M.pack(land, s)
  local rows, any = {}, false
  for row = 1, land.nz do
    local t, zeros = {}, 0
    for i = 1, land.nx do
      local cm = math.floor(land.delta[(row - 1) * land.nx + i] * 100 + 0.5)
      if cm == 0 then zeros = zeros + 1
      else
        if zeros > 0 then t[#t + 1] = zeros == 1 and "0" or ("0*" .. zeros); zeros = 0 end
        t[#t + 1] = tostring(cm); any = true
      end
    end
    rows[row] = table.concat(t, " ")
  end
  s.edits = any and rows or nil
  return s.edits
end

local function pos(land, i, j)                     -- the grid's point (i: 1..nx, j: 1..nz) -> x, z
  return -land.w / 2 + (i - 1) * land.w / (land.nx - 1), -land.d / 2 + (j - 1) * land.d / (land.nz - 1)
end
M.pos = pos

local function color_at(land, s, k, i, j)          -- a point's colour: low to high by height, rock where steep, snow up high
  local C = s.colors
  local top = land.ctop or math.max(s.base.height, land.top or 0, 1e-3)
  local t = land.h[k] / top
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local lo, hi = C.low, C.high
  local R, G, B = lo[1] + (hi[1] - lo[1]) * t, lo[2] + (hi[2] - lo[2]) * t, lo[3] + (hi[3] - lo[3]) * t
  local _, ny = M.normal_at_grid(land, i, j)
  local thr = C.rock_slope * 0.6                   -- (steep: 1 - the normal's y; 0.6 about 66°; whole rock from there, blended in below)
  local r = (1 - ny - thr + 0.06) / 0.06
  if r < 0 then r = 0 elseif r > 1 then r = 1 end
  if C.rock_slope < 1 and r > 0 then local q = C.rock; R, G, B = R + (q[1] - R) * r, G + (q[2] - G) * r, B + (q[3] - B) * r end
  if C.snow_at < 1 and t > C.snow_at then
    local m, q = math.min(1, (t - C.snow_at) / 0.05) * (1 - r * 0.6), C.snow
    R, G, B = R + (q[1] - R) * m, G + (q[2] - G) * m, B + (q[3] - B) * m
  end
  local g = land.grain[k]                          -- (a little grain)
  R, G, B = floor(R + g + 0.5), floor(G + g + 0.5), floor(B + g + 0.5)
  R = R < 0 and 0 or R > 255 and 255 or R
  G = G < 0 and 0 or G > 255 and 255 or G
  B = B < 0 and 0 or B > 255 and 255 or B
  return R * 65536 + G * 256 + B
end
function M.normal_at_grid(land, i, j)             -- the normal at a grid point (central differences)
  local nx, nz, h = land.nx, land.nz, land.h
  local i0, i1, j0, j1 = math.max(1, i - 1), math.min(nx, i + 1), math.max(1, j - 1), math.min(nz, j + 1)
  local sx, sz = land.w / (nx - 1), land.d / (nz - 1)
  local dx = (h[(j - 1) * nx + i1] - h[(j - 1) * nx + i0]) / ((i1 - i0) * sx)
  local dz = (h[(j1 - 1) * nx + i] - h[(j0 - 1) * nx + i]) / ((j1 - j0) * sz)
  local l = math.sqrt(dx * dx + 1 + dz * dz)
  return -dx / l, 1 / l, -dz / l
end
local function recolor(land, s, i0, i1, j0, j1)   -- the colours again, over a part of it (all: none given)
  i0, i1, j0, j1 = i0 or 1, i1 or land.nx, j0 or 1, j1 or land.nz
  for j = math.max(1, j0), math.min(land.nz, j1) do
    for i = math.max(1, i0), math.min(land.nx, i1) do
      local k = (j - 1) * land.nx + i
      land.c[k] = color_at(land, s, k, i, j)
    end
  end
end

local ver = 0
local LAND = {}                                     -- (a land's methods: land:height_at(x, z), land:normal_at, land:ray: a
LAND.__index = LAND                                --  game's systems (sandboxed) get them through w:landscape)
function M.build(s)
  local nx, nz = dims(s)
  local land = setmetatable({ nx = nx, nz = nz, w = s.w, d = s.d, h = {}, base = {}, c = {} }, LAND)
  land.delta = unpack_edits(s, nx, nz)
  land.base = M.base_grid(s.base, land)
  local top, h, base, delta, grain = 0, land.h, land.base, land.delta, {}
  for j = 1, nz do
    for i = 1, nx do
      local k = (j - 1) * nx + i
      h[k] = base[k] + delta[k]
      if h[k] > top then top = h[k] end
      grain[k] = (hash(7, i, j) - 0.5) * 10        -- (each point's grain: its colour a little off)
    end
  end
  land.grain = grain
  land.top = top
  recolor(land, s)
  ver = ver + 1
  land.ver = ver
  return land
end

M.recolor = function(land, s) recolor(land, s); ver = ver + 1; land.ver = ver end   -- (the colours changed: all again)
function M.rebuild(s, old)                         -- the settings changed: built again; the old one's edits kept, stretched
  if not old or (old.nx == dims(s) and select(2, dims(s)) == old.nz) then return M.build(s) end   --  over a grid of another size
  local s2 = copy(s); s2.edits = nil
  local land = M.build(s2)
  local o = { nx = old.nx, nz = old.nz, w = land.w, d = land.d, h = old.delta }   -- (the old edits, as heights over the new area)
  for j = 1, land.nz do
    for i = 1, land.nx do
      local x, z = pos(land, i, j)
      local k = (j - 1) * land.nx + i
      land.delta[k] = M.height_at(o, x, z)
      land.h[k] = land.base[k] + land.delta[k]
      if land.h[k] > land.top then land.top = land.h[k] end
    end
  end
  M.recolor(land, s)
  M.pack(land, s)
  return land
end
function M.edited(land)                            -- how many points the brushes moved
  local n = 0
  for k = 1, #land.delta do if math.abs(land.delta[k]) >= 0.005 then n = n + 1 end end
  return n
end
function M.height_at(land, x, z)
  local fx = (x + land.w / 2) / land.w * (land.nx - 1)
  local fz = (z + land.d / 2) / land.d * (land.nz - 1)
  fx = math.max(0, math.min(land.nx - 1, fx)); fz = math.max(0, math.min(land.nz - 1, fz))
  local i, j = math.min(land.nx - 2, math.floor(fx)), math.min(land.nz - 2, math.floor(fz))
  local tx, tz = fx - i, fz - j
  local h, nx = land.h, land.nx
  local a, b = h[j * nx + i + 1], h[j * nx + i + 2]
  local c, d = h[(j + 1) * nx + i + 1], h[(j + 1) * nx + i + 2]
  return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * tz
end
function M.normal_at(land, x, z)
  local e = math.min(land.w / (land.nx - 1), land.d / (land.nz - 1))
  local dx = (M.height_at(land, x + e, z) - M.height_at(land, x - e, z)) / (2 * e)
  local dz = (M.height_at(land, x, z + e) - M.height_at(land, x, z - e)) / (2 * e)
  local l = math.sqrt(dx * dx + 1 + dz * dz)
  return -dx / l, 1 / l, -dz / l
end
function M.ray(land, ox, oy, oz, dx, dy, dz, far)   -- marched a half cell at a time, then halved down to the crossing
  far = far or 1e4
  local l = math.sqrt(dx * dx + dy * dy + dz * dz)
  if l < 1e-9 then return nil end
  dx, dy, dz = dx / l, dy / l, dz / l
  local t0, t1 = 0, far                            -- (only inside its box: x, z within it)
  local hw, hd = land.w / 2, land.d / 2
  for _, ax in ipairs({ { ox, dx, -hw, hw }, { oz, dz, -hd, hd } }) do
    local o, d, lo, hi = ax[1], ax[2], ax[3], ax[4]
    if math.abs(d) < 1e-9 then
      if o < lo or o > hi then return nil end
    else
      local a, b = (lo - o) / d, (hi - o) / d
      if a > b then a, b = b, a end
      t0, t1 = math.max(t0, a), math.min(t1, b)
    end
  end
  if t0 > t1 then return nil end
  local step = math.min(land.w / (land.nx - 1), land.d / (land.nz - 1)) * 0.5
  local prev = t0
  local function above(t) return oy + dy * t - M.height_at(land, ox + dx * t, oz + dz * t) end
  if above(t0) < 0 then return nil end             -- (starts under it)
  local t = t0
  while t <= t1 do
    if above(t) < 0 then
      local a, b = prev, t
      for _ = 1, 20 do local m = (a + b) / 2; if above(m) < 0 then b = m else a = m end end
      return b, ox + dx * b, oy + dy * b, oz + dz * b
    end
    prev = t
    t = t + step
  end
  return nil
end

function M.brush(land, s, mode, x, z, radius, strength, o)
  o = o or {}
  local nx, nz = land.nx, land.nz
  local sx, sz = land.w / (nx - 1), land.d / (nz - 1)
  local i0 = math.max(1, math.floor((x - radius + land.w / 2) / sx) + 1)
  local i1 = math.min(nx, math.ceil((x + radius + land.w / 2) / sx) + 1)
  local j0 = math.max(1, math.floor((z - radius + land.d / 2) / sz) + 1)
  local j1 = math.min(nz, math.ceil((z + radius + land.d / 2) / sz) + 1)
  if i0 > i1 or j0 > j1 then return 0 end
  local h, delta, base = land.h, land.delta, land.base
  local target = o.target or M.height_at(land, x, z)
  local old = (mode == "smooth") and {} or nil
  if old then for j = j0, j1 do for i = i0, i1 do local k = (j - 1) * nx + i; old[k] = h[k] end end end
  local function at(i, j)                          -- (smoothing: the heights before this dab)
    i, j = math.max(1, math.min(nx, i)), math.max(1, math.min(nz, j))
    local k = (j - 1) * nx + i
    return old[k] or h[k]
  end
  local n = 0
  for j = j0, j1 do
    for i = i0, i1 do
      local px, pz = pos(land, i, j)
      local d2 = ((px - x) ^ 2 + (pz - z) ^ 2) / (radius * radius)
      if d2 < 1 then
        local f = (1 - d2) ^ 2 * strength          -- (falloff: full in the middle, none at the rim)
        local k = (j - 1) * nx + i
        local y = h[k]
        if mode == "sculpt" then y = y + f * (o.rate or radius * 0.1)
        elseif mode == "smooth" then
          local avg = (at(i - 1, j) + at(i + 1, j) + at(i, j - 1) + at(i, j + 1) + at(i, j) * 4) / 8
          y = y + (avg - y) * math.min(1, f * 2)
        elseif mode == "flatten" then y = y + (target - y) * math.min(1, f * 2)
        elseif mode == "erase" then y = y + (base[k] - y) * math.min(1, f * 2) end
        if y ~= h[k] then
          h[k] = y; delta[k] = y - base[k]; n = n + 1
          if y > (land.top or 0) then land.top = y end
        end
      end
    end
  end
  if n > 0 then
    recolor(land, s, i0 - 1, i1 + 1, j0 - 1, j1 + 1)
    ver = ver + 1
    land.ver = ver
  end
  return n
end

function LAND.height_at(land, x, z) return M.height_at(land, x, z) end
function LAND.normal_at(land, x, z) return M.normal_at(land, x, z) end
function LAND.ray(land, ...) return M.ray(land, ...) end

-- games: w:landscape("hills.land" | settings) -> land; an asset's read again when it changes
local ok, ecs = pcall(require, "ecs")
if ok and type(ecs) == "table" and ecs.world then
  local cache, read_at = {}, {}
  local World = getmetatable(ecs.world()).__index
  function World:landscape(what, over)
    local key, s
    if type(what) == "table" then
      s = what
      key = ecs.encode and ecs.encode(what) or tostring(what)
    else
      local name = tostring(what):gsub("^/assets/", ""):gsub("^/", "")
      if not name:find("%.%w+$") then name = name .. ".land" end
      local r, now = read_at[name], os.time()      -- (the file read again at most once a second: not every call, every frame)
      if not r or now ~= r.at then
        local text = ecs.assets and ecs.assets.read(name)
        if not text then return nil, "no asset " .. name end
        if not r or r.text ~= text then
          local t = ecs.decode(text, name)
          if type(t) ~= "table" then return nil, "not a landscape: " .. name end
          r = { text = text, s = t, key = name .. "#" .. (r and r.n + 1 or 1), n = r and r.n + 1 or 1 }
          read_at[name] = r
        end
        r.at = now
      end
      key, s = r.key, r.s
    end
    if over then
      s = copy(s)
      for k, v in pairs(over) do s[k] = copy(v) end
      key = key .. "|" .. (ecs.encode and ecs.encode(over) or "")
    end
    local c = cache[key]
    if not c then
      c = M.build(M.check(s))
      cache[key] = c
      local n = 0
      for _ in pairs(cache) do n = n + 1 end
      if n > 16 then cache = { [key] = c } end
    end
    return c
  end
end
return M
