-- foliage.lua - foliage scattered over an area (grass, bushes, trees, rocks): a .foliage's settings ->
-- where each copy goes. No Lite in it: plugins/foliage previews with it, the renderer draws with it
-- (a node's `foliage3d`: runtime/boot.lua viewer_foliage, editor/render.h), a game can read it too.
--
-- A .foliage (Lua data; every field optional, M.DEFAULTS):
--   seed        the same seed, the same scatter
--   w, d        the area, in meters (x across, z deep), centred on the node; y: its height
--   layers      one a kind of thing scattered, each:
--     name        what it's called (the editor's list)
--     mesh        what's drawn: "grass" (a tuft), "tree", "pine", "bush" (plants made by rules), "cube", "sphere",
--                 "plane", or a model ("/assets/tree.glb", "file:...")
--     variants    1..8: grass and the plants: that many of the kind ("tree", "tree:2"...), each copy one of them
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
--     mask        where it grows (painted: the brush's Density): rows of digits '0'..'9' (none..all), a square
--                 grid over the area (row 1: the back, -d/2; column 1: -w/2); none: everywhere
--     points      copies put by hand (the brush's Copies), besides the scatter: { x, z, yaw, scale }... (meters,
--                 radians, times size); their tilt, shade and variant from the seed
--     On a landscape (the settings' ground), each layer's rules:
--     align       0..1: 0 upright, 1 leaning as the ground slopes there (rocks 1, grass a little, trees 0)
--     slope       { min, max } degrees: grows only where the ground is that steep ({ 0, 90 }: anywhere)
--     altitude    { min, max } meters: grows only that high (none: anywhere)
--   ground      a landscape it grows on (a .land asset's name, or its settings: runtime/landscape.lua), its middle
--               where the scatter's is: each copy at the ground's height there (+ y), made again when it changes
--
--   M.check(t) -> settings (defaults filled, numbers in range)
--   M.generate(s [, land]) -> items, info (land: the ground's, runtime/landscape.lua's build; else flat at y): items = { meshes = { name... }, wind = { a mesh's }, fade = { a mesh's }, of = { its layer },
--     n, layer, part (which of meshes: a layer's variants are parts), x, y, z, ry, rx, rz, sx, sy, sz, r, g, b (0..1) }
--     (arrays, a copy each: the renderer reads them as they are), info = { count, per = { n... } }
--   M.drape(items, s, land, x0, z0, x1, z1) the copies there on the ground again (a landscape's brush, live)
--   The brush (plugins/foliage; a layer of settings changed in place):
--     M.paint_points(L, s, x, z, r, o) copies added round x, z up to o.density a m² (o.strength 0..1 of the
--       way there a dab, o.yaw: theirs, else at random as the layer says, o.rand: a random stream)
--     M.erase_points(L, x, z, r, strength, rand)   M.paint_mask(L, s, x, z, r, amount: -1..1)
--   w:foliage(name | settings) -> items, info (an asset's: read again when it changes)
local M = {}

M.LAYER = { name = "grass", mesh = "grass", size = { 0.35, 0.45, 0.35 }, density = 4, scale = { 0.7, 1.3 },
            yaw = true, tilt = 12, sink = 0, color = { 90, 160, 70 }, shade = 0.25, cluster = 0.3, clump = 4,
            spacing = 0, max = 20000, wind = 0, fade = 0, variants = 1, align = 0, slope = { 0, 90 } }
M.DEFAULTS = { seed = 1, w = 20, d = 20, y = 0, layers = { M.LAYER } }
M.MAX = 50000                                      -- (every layer together)
M.MASK = 32                                        -- (a new mask: that many cells across)
M.PLANTS = { grass = true, tree = true, pine = true, bush = true }   -- (built in, with variants: "tree:2")
M.PARTS = 32                                       -- (meshes in a scatter, variants included: the renderer's)

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
    ground = (type(t.ground) == "string" and t.ground ~= "" or type(t.ground) == "table") and t.ground or nil,
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
        variants = math.floor(num(l.variants, D.variants, 1, 8)),
        align = num(l.align, D.align, 0, 1),
        slope = vec(l.slope, D.slope, 0, 90),
        altitude = type(l.altitude) == "table" and vec(l.altitude, { -1e5, 1e5 }, -1e5, 1e5) or nil,
      }
      if L.slope[2] < L.slope[1] then L.slope[1], L.slope[2] = L.slope[2], L.slope[1] end
      if type(l.mask) == "table" and #l.mask >= 2 then   -- (rows of digits, as many as each is long)
        local n, m = math.min(#l.mask, 256), {}
        for r = 1, n do
          local row = type(l.mask[r]) == "string" and l.mask[r]:gsub("[^0-9]", "9") or ""
          m[r] = (row .. string.rep("9", n)):sub(1, n)
        end
        L.mask = m
      end
      if type(l.points) == "table" then
        local pts = {}
        for _, q in ipairs(l.points) do
          if type(q) == "table" and #pts < M.MAX then
            pts[#pts + 1] = { num(q[1], 0, -1e5, 1e5), num(q[2], 0, -1e5, 1e5), num(q[3], 0), num(q[4], 1, 0.01, 100) }
          end
        end
        L.points = pts
      end
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

local function mask_of(L, s)                       -- the mask's 0..1 at x, z (bilinear), and its mean
  local m = L.mask
  if not m then return nil, 1 end
  local n, g, sum = #m, {}, 0
  for r = 1, n do
    local row = {}
    for c = 1, n do local v = (m[r]:byte(c) - 48) / 9; row[c] = v; sum = sum + v end
    g[r] = row
  end
  return function(x, z)
    local fx, fz = (x / s.w + 0.5) * n + 0.5, (z / s.d + 0.5) * n + 0.5
    local cx, cz = math.floor(fx), math.floor(fz)
    local tx, tz = fx - cx, fz - cz
    local function at(c, r) return g[math.max(1, math.min(n, r))][math.max(1, math.min(n, c))] end
    local a, b = at(cx, cz), at(cx + 1, cz)
    local c, d = at(cx, cz + 1), at(cx + 1, cz + 1)
    local top, bot = a + (b - a) * tx, c + (d - c) * tx
    return top + (bot - top) * tz
  end, sum / (n * n)
end

local function lean(nx, ny, nz, a, ry)              -- (a copy turned ry about y, leaning a of the way to the normal n:
  if a <= 0 then return 0, 0 end                   --  rx, rz for the renderer's R = Ry Rx Rz, up mapped onto it)
  nx, ny, nz = nx * a, 1 + (ny - 1) * a, nz * a
  local l = math.sqrt(nx * nx + ny * ny + nz * nz)
  nx, ny, nz = nx / l, ny / l, nz / l
  local cy, sy = math.cos(ry), math.sin(ry)
  local ux, uy, uz = cy * nx - sy * nz, ny, sy * nx + cy * nz
  return (math.atan2 or math.atan)(uz, uy), math.asin(math.max(-1, math.min(1, -ux)))
end
M.lean = lean
function M.generate(s, land)
  s = M.check(s)
  if land and not (land.height_at and land.normal_at) then land = nil end   -- (the ground: a landscape's build, its methods)
  local it = { meshes = {}, wind = {}, fade = {}, of = {}, n = 0, layer = {}, part = {}, x = {}, y = {}, z = {}, ry = {}, rx = {}, rz = {}, sx = {}, sy = {}, sz = {}, r = {}, g = {}, b = {}, tx = {}, tz = {} }
  local info = { count = 0, per = {} }
  local total = 0
  for li, L in ipairs(s.layers) do
    local parts = {}                               -- (the layer's meshes: its variants)
    local nv = M.PLANTS[L.mesh] and L.variants or 1
    for v = 1, nv do
      local m = #it.meshes + 1
      if m > M.PARTS then break end
      it.meshes[m] = v == 1 and L.mesh or (L.mesh .. ":" .. v)
      it.wind[m], it.fade[m], it.of[m] = L.wind, L.fade, li
      parts[v] = m
    end
    nv = #parts
    local smin, smax = math.cos(math.rad(L.slope[2])), math.cos(math.rad(L.slope[1]))   -- (the normal's y: steepest .. flattest)
    local function put(rand, x, z, ry, k)          -- (a copy: its tilt, shade, variant from rand; on the ground: false where
      local n = it.n + 1                           --  its rules say it doesn't grow, the randoms drawn all the same)
      it.n = n
      it.layer[n] = li
      it.part[n] = parts[1] or 0
      it.x[n], it.z[n] = x, z
      it.y[n] = s.y - L.sink
      it.ry[n] = ry
      local t = math.rad(L.tilt) * rand()
      local a = rand() * math.pi * 2
      it.rx[n], it.rz[n] = t * math.cos(a), t * math.sin(a)
      it.tx[n], it.tz[n] = it.rx[n], it.rz[n]      -- (its own tilt, kept: M.drape leans it again)
      local ok = true
      if land then
        local gy = land:height_at(x, z)
        local gx, gny, gz = land:normal_at(x, z)
        if gny < smin - 1e-9 or gny > smax + 1e-9 then ok = false end
        if L.altitude and (gy < L.altitude[1] or gy > L.altitude[2]) then ok = false end
        it.y[n] = s.y + gy - L.sink
        local lx, lz = lean(gx, gny, gz, L.align, ry)
        it.rx[n], it.rz[n] = it.rx[n] + lx, it.rz[n] + lz
      end
      it.sx[n], it.sy[n], it.sz[n] = L.size[1] * k, L.size[2] * k, L.size[3] * k
      local sh = 1 + (rand() * 2 - 1) * L.shade
      it.r[n] = math.min(1, L.color[1] / 255 * sh)
      it.g[n] = math.min(1, L.color[2] / 255 * sh)
      it.b[n] = math.min(1, L.color[3] / 255 * sh)
      if nv > 1 then it.part[n] = parts[1 + math.floor(rand() * nv) % nv] end
      if not ok then it.n = n - 1 end
      return ok
    end
    local rand = rng(s.seed * 7919 + li * 104729)
    local nz = noise2(s.seed + li * 31)
    local mask, mean = mask_of(L, s)
    local want = math.floor(L.density * s.w * s.d * mean + 0.5)
    want = math.min(want, L.max, M.MAX - total)
    local grid, cell = {}, L.spacing
    local made, tries = 0, 0
    while made < want and tries < want * 6 + 16 do
      tries = tries + 1
      local x, z = (rand() - 0.5) * s.w, (rand() - 0.5) * s.d
      local keep = true
      if mask and rand() >= mask(x, z) then keep = false end   -- (painted away)
      if keep and L.cluster > 0 then                        -- (in clumps: the noise there against a threshold; 1: only its peaks)
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
      end
      if keep then
        local k = L.scale[1] + (L.scale[2] - L.scale[1]) * rand()
        if put(rand, x, z, L.yaw and rand() * math.pi * 2 or 0, k) then
          made = made + 1
          if cell > 0 then
            local gk = math.floor(x / cell) * 65536 + math.floor(z / cell)
            grid[gk] = grid[gk] or {}
            table.insert(grid[gk], { x, z })
          end
        end
      end
    end
    if L.points then                               -- (put by hand: their own random stream, the scatter's unchanged)
      local pr = rng(s.seed * 48271 + li * 7 + 3)
      for _, q in ipairs(L.points) do
        if total + made >= M.MAX then break end
        if put(pr, q[1], q[2], q[3], q[4]) then made = made + 1 end
      end
    end
    info.per[li] = made
    total = total + made
  end
  info.count = total
  return it, info
end

-- a landscape changed under it (its editor's brush, a dab): the copies within x0..x1, z0..z1 put on the ground again
-- and leaned again (their places and rules as they were: M.generate makes it anew, at the stroke's end) -> how many
function M.drape(it, s, land, x0, z0, x1, z1)
  if not (land and land.height_at and it) then return 0 end
  local n = 0
  for i = 1, it.n do
    local x, z = it.x[i], it.z[i]
    if x >= x0 and x <= x1 and z >= z0 and z <= z1 then
      local L = s.layers[it.layer[i]]
      if L then
        local gx, gy, gz = land:normal_at(x, z)
        it.y[i] = s.y + land:height_at(x, z) - L.sink
        local lx, lz = lean(gx, gy, gz, L.align, it.ry[i])
        it.rx[i], it.rz[i] = (it.tx[i] or 0) + lx, (it.tz[i] or 0) + lz
        n = n + 1
      end
    end
  end
  return n
end

-- the brush ---------------------------------------------------------------------------------------------
local function r3(v) return math.floor(v * 1000 + 0.5) / 1000 end
function M.paint_points(L, s, x, z, r, o)          -- copies round x, z: up to o.density a m² there
  local rand = o.rand or math.random
  L.points = L.points or {}
  local pts, r2 = L.points, r * r
  local have = 0
  for _, q in ipairs(pts) do if (q[1] - x) ^ 2 + (q[2] - z) ^ 2 < r2 then have = have + 1 end end
  local add = math.max(0, (o.density or 1) * math.pi * r2 - have) * (o.strength or 0.5)
  local n = math.floor(add)
  if rand() < add - n then n = n + 1 end
  local sp2, hw, hd, made = (L.spacing or 0) ^ 2, s.w / 2, s.d / 2, 0
  for _ = 1, n do
    for _ = 1, 8 do                                -- (a few tries a copy: the spacing, the edge)
      local a, d = rand() * math.pi * 2, r * math.sqrt(rand())
      local px, pz = x + math.cos(a) * d, z + math.sin(a) * d
      local ok = math.abs(px) <= hw and math.abs(pz) <= hd and rand() < 1 - 0.6 * (d / r) ^ 2   -- (fewer near its edge)
      if ok and sp2 > 0 then
        for _, q in ipairs(pts) do if (q[1] - px) ^ 2 + (q[2] - pz) ^ 2 < sp2 then ok = false break end end
      end
      if ok then
        local k = L.scale and (L.scale[1] + (L.scale[2] - L.scale[1]) * rand()) or 1
        local yaw = o.yaw or (L.yaw ~= false and rand() * math.pi * 2 or 0)
        pts[#pts + 1] = { r3(px), r3(pz), r3(yaw), r3(k) }
        made = made + 1
        break
      end
    end
  end
  return made
end
function M.erase_points(L, x, z, r, strength, rand)   -- copies put by hand, taken away round x, z
  rand = rand or math.random
  local pts, gone = L.points or {}, 0
  for i = #pts, 1, -1 do
    local d2 = ((pts[i][1] - x) ^ 2 + (pts[i][2] - z) ^ 2) / (r * r)
    if d2 < 1 and rand() < (strength or 1) * (1 - 0.5 * d2) then table.remove(pts, i); gone = gone + 1 end
  end
  return gone
end
function M.paint_mask(L, s, x, z, r, amount)       -- where it grows, more (amount > 0) or less, round x, z
  local n = L.mask and #L.mask or M.MASK
  local g = {}
  for row = 1, n do
    g[row] = {}
    local str = L.mask and L.mask[row]
    for c = 1, n do g[row][c] = str and (str:byte(c) - 48) or (amount > 0 and 0 or 9) end   -- (a new one: none to paint in, all to erase from)
  end
  for row = 1, n do
    local cz = ((row - 0.5) / n - 0.5) * s.d
    for c = 1, n do
      local cx = ((c - 0.5) / n - 0.5) * s.w
      local d2 = ((cx - x) ^ 2 + (cz - z) ^ 2) / (r * r)
      if d2 < 1 then g[row][c] = math.max(0, math.min(9, g[row][c] + amount * 9 * (1 - d2))) end
    end
  end
  local m = {}
  for row = 1, n do
    local t = {}
    for c = 1, n do t[c] = string.char(48 + math.floor(g[row][c] + 0.5)) end
    m[row] = table.concat(t)
  end
  L.mask = m
end

-- games: w:foliage("meadow.foliage" | settings) -> items, info; an asset's read again when it changes
local ok, ecs = pcall(require, "ecs")
if ok and type(ecs) == "table" then
  local cache = {}
  local World = getmetatable(ecs.world()).__index
  local read_at = {}
  function World:foliage(what, over)
    local key, s
    if type(what) == "table" then
      s = what
      key = ecs.encode and ecs.encode(what) or tostring(what)
    else
      local name = tostring(what):gsub("^/assets/", ""):gsub("^/", "")
      if not name:find("%.%w+$") then name = name .. ".foliage" end
      local r, now = read_at[name], os.time()      -- (the file read again at most once a second: not every call, every frame)
      if not r or now ~= r.at then
        local text = ecs.assets and ecs.assets.read(name)
        if not text then return nil, "no asset " .. name end
        if not r or r.text ~= text then
          local t = ecs.decode(text, name)
          if type(t) ~= "table" then return nil, "not foliage settings: " .. name end
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
    local land                                     -- (on a landscape: its version in the key, so a change grows it again)
    if s.ground and self.landscape then
      land = self:landscape(s.ground)
      if land then key = key .. "|land:" .. tostring(land.ver) end
    end
    local c = cache[key]
    if not c then
      local items, info = M.generate(s, land)
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
