-- foliage.lua - foliage scattered over an area (grass, bushes, trees, rocks): a .foliage's settings ->
-- where each copy goes. No Lite in it: plugins/foliage previews with it, the renderer draws with it
-- (a node's `foliage3d`: runtime/boot.lua viewer_foliage, editor/render.h), a game can read it too.
--
-- A .foliage (Lua data; every field optional, M.DEFAULTS):
--   seed        the same seed, the same scatter
--   w, d        the area, in meters (x across, z deep), centred on the node; y: its height
--   layers      one a kind of thing scattered, each:
--     name        what it's called (the editor's list)
--     mesh        what's drawn: "cube", "sphere", "plane" or a model ("/assets/tree.glb", "file:...")
--     size        { x, y, z }: the mesh's size, before the random scale (a blade of grass: { 0.04, 0.5, 0.04 })
--     density     copies a square meter
--     scale       { min, max }: each copy's size, at random
--     yaw         true: turned round y at random
--     tilt        up to that many degrees off upright, at random
--     sink        meters into the ground (a rock half buried)
--     color       { r, g, b } 0..255, and shade 0..1: each copy that much darker or lighter, at random
--     cluster     0..1: 0 even, 1 in clumps (noise: where it's high), clump: the clumps' size in meters
--     spacing     no two copies of the layer nearer than that (meters; 0: anywhere)
--     max         at most that many copies of the layer (20000)
--     wind        0..1: how much the wind bends it (by its height: grass, a tip more than its root; the GPU's)
--     fade        meters: whole up to that far from the camera, fewer copies further, none past 1.5x (0: never)
--
--   M.check(t) -> settings (defaults filled, numbers in range)
--   M.generate(s) -> items, info: items = { meshes = { name... }, wind = { a layer's }, fade = { a layer's }, n,
--     layer, x, y, z, ry, rx, rz, sx, sy, sz, r, g, b (0..1) } (arrays, a copy each: the renderer reads them as they are), info = { count, per = { n... } }
--   w:foliage(name | settings) -> items, info (an asset's: read again when it changes)
local M = {}

M.LAYER = { name = "grass", mesh = "grass", size = { 0.35, 0.45, 0.35 }, density = 4, scale = { 0.7, 1.3 },
            yaw = true, tilt = 12, sink = 0, color = { 90, 160, 70 }, shade = 0.25, cluster = 0.3, clump = 4,
            spacing = 0, max = 20000, wind = 0, fade = 0 }
M.DEFAULTS = { seed = 1, w = 20, d = 20, y = 0, layers = { M.LAYER } }
M.MAX = 50000                                      -- (every layer together)

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end
M.copy = copy
local function num(v, def, lo, hi)
  v = tonumber(v)
  if not v or v ~= v then v = def end
  if lo and v < lo then v = lo end
  if hi and v > hi then v = hi end
  return v
end
local function vec(t, def, lo, hi)
  local o = {}
  for i = 1, #def do o[i] = num(type(t) == "table" and t[i] or nil, def[i], lo, hi) end
  return o
end
function M.check(t)
  t = type(t) == "table" and t or {}
  local s = {
    seed = math.floor(num(t.seed, M.DEFAULTS.seed, 0, 2147483646)),
    w = num(t.w, M.DEFAULTS.w, 0.1, 10000), d = num(t.d, M.DEFAULTS.d, 0.1, 10000), y = num(t.y, 0),
    layers = {},
  }
  local layers = type(t.layers) == "table" and t.layers or M.DEFAULTS.layers
  for i, l in ipairs(layers) do
    if type(l) == "table" then
      local D = M.LAYER
      local L = {
        name = type(l.name) == "string" and l.name or ("layer " .. i),
        mesh = type(l.mesh) == "string" and l.mesh ~= "" and l.mesh or D.mesh,
        size = vec(l.size, D.size, 0.001, 1000),
        density = num(l.density, D.density, 0, 1000),
        scale = vec(l.scale, D.scale, 0.01, 100),
        yaw = l.yaw == nil and D.yaw or not not l.yaw,
        tilt = num(l.tilt, D.tilt, 0, 90),
        sink = num(l.sink, D.sink, -100, 100),
        color = vec(l.color, D.color, 0, 255),
        shade = num(l.shade, D.shade, 0, 1),
        cluster = num(l.cluster, D.cluster, 0, 1),
        clump = num(l.clump, D.clump, 0.1, 1000),
        spacing = num(l.spacing, D.spacing, 0, 1000),
        max = math.floor(num(l.max, D.max, 0, M.MAX)),
        wind = num(l.wind, D.wind, 0, 1),
        fade = num(l.fade, D.fade, 0, 10000),
      }
      if L.scale[2] < L.scale[1] then L.scale[1], L.scale[2] = L.scale[2], L.scale[1] end
      s.layers[#s.layers + 1] = L
    end
  end
  return s
end

-- a random stream: Park-Miller (exact in doubles: the same on LuaJIT and Lua 5.4)
local function rng(seed)
  local x = seed % 2147483646 + 1
  return function()
    x = (x * 16807) % 2147483647
    return (x - 1) / 2147483646
  end
end
-- value noise 0..1, smooth, a lattice of random values (the layer's own seed)
local function noise2(seed)
  local cache = {}
  local function at(ix, iy)
    local k = ix * 73856093 + iy * 19349663
    local v = cache[k]
    if not v then
      local h = ((ix % 65536) * 7919 + (iy % 65536) * 104729 + (seed % 100000) * 31 + 1) % 2147483647   -- (every product under 2^53: the same in doubles and in 5.4's integers)
      for _ = 1, 3 do h = (h * 16807) % 2147483647 end
      v = h / 2147483647
      cache[k] = v
    end
    return v
  end
  return function(x, y)
    local ix, iy = math.floor(x), math.floor(y)
    local fx, fy = x - ix, y - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    local a, b = at(ix, iy), at(ix + 1, iy)
    local c, d = at(ix, iy + 1), at(ix + 1, iy + 1)
    local top, bot = a + (b - a) * fx, c + (d - c) * fx
    return top + (bot - top) * fy
  end
end

function M.generate(s)
  s = M.check(s)
  local it = { meshes = {}, wind = {}, fade = {}, n = 0, layer = {}, x = {}, y = {}, z = {}, ry = {}, rx = {}, rz = {}, sx = {}, sy = {}, sz = {}, r = {}, g = {}, b = {} }
  local info = { count = 0, per = {} }
  local total = 0
  for li, L in ipairs(s.layers) do
    it.meshes[li] = L.mesh
    it.wind[li], it.fade[li] = L.wind, L.fade
    local rand = rng(s.seed * 7919 + li * 104729)
    local nz = noise2(s.seed + li * 31)
    local want = math.floor(L.density * s.w * s.d + 0.5)
    want = math.min(want, L.max, M.MAX - total)
    local grid, cell = {}, L.spacing
    local made, tries = 0, 0
    while made < want and tries < want * 6 + 16 do
      tries = tries + 1
      local x, z = (rand() - 0.5) * s.w, (rand() - 0.5) * s.d
      local keep = true
      if L.cluster > 0 then                        -- (in clumps: the noise there against a threshold; 1: only its peaks)
        local v = nz(x / L.clump + 1000, z / L.clump + 1000)
        if v < L.cluster * 0.85 then keep = false end
      end
      if keep and cell > 0 then                    -- (spacing: the neighbouring cells' copies)
        local gx, gz = math.floor(x / cell), math.floor(z / cell)
        for ax = gx - 1, gx + 1 do
          for az = gz - 1, gz + 1 do
            local c = grid[ax * 65536 + az]
            if c then for _, p in ipairs(c) do if (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < cell * cell then keep = false end end end
          end
        end
        if keep then
          local k = gx * 65536 + gz
          grid[k] = grid[k] or {}
          table.insert(grid[k], { x, z })
        end
      end
      if keep then
        made = made + 1
        local n = it.n + 1
        it.n = n
        local k = L.scale[1] + (L.scale[2] - L.scale[1]) * rand()
        it.layer[n] = li
        it.x[n], it.z[n] = x, z
        it.y[n] = s.y - L.sink
        it.ry[n] = L.yaw and rand() * math.pi * 2 or 0
        local t = math.rad(L.tilt) * rand()
        local a = rand() * math.pi * 2
        it.rx[n], it.rz[n] = t * math.cos(a), t * math.sin(a)
        it.sx[n], it.sy[n], it.sz[n] = L.size[1] * k, L.size[2] * k, L.size[3] * k
        local sh = 1 + (rand() * 2 - 1) * L.shade
        it.r[n] = math.min(1, L.color[1] / 255 * sh)
        it.g[n] = math.min(1, L.color[2] / 255 * sh)
        it.b[n] = math.min(1, L.color[3] / 255 * sh)
      end
    end
    info.per[li] = made
    total = total + made
  end
  info.count = total
  return it, info
end

-- games: w:foliage("meadow.foliage" | settings) -> items, info; an asset's read again when it changes
local ok, ecs = pcall(require, "ecs")
if ok and type(ecs) == "table" then
  local cache = {}
  local World = getmetatable(ecs.world()).__index
  function World:foliage(what, over)
    local key, s
    if type(what) == "table" then
      s = what
      key = ecs.encode and ecs.encode(what) or tostring(what)
    else
      local name = tostring(what):gsub("^/assets/", ""):gsub("^/", "")
      if not name:find("%.%w+$") then name = name .. ".foliage" end
      local text = ecs.assets and ecs.assets.read(name)
      if not text then return nil, "no asset " .. name end
      key = text
      s = ecs.decode(text, name)
      if type(s) ~= "table" then return nil, "not foliage settings: " .. name end
    end
    if over then
      s = copy(s)
      for k, v in pairs(over) do s[k] = copy(v) end
      key = key .. "|" .. (ecs.encode and ecs.encode(over) or "")
    end
    local c = cache[key]
    if not c then
      local items, info = M.generate(s)
      c = { items = items, info = info }
      cache[key] = c
      local n = 0
      for _ in pairs(cache) do n = n + 1 end
      if n > 32 then cache = { [key] = c } end   -- (settings changed often: the old scatters let go)
    end
    return c.items, c.info
  end
end
return M
