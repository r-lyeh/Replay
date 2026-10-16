-- tmx.lua - Tiled's maps (.tmx, their tilesets .tsx) read into a .tmap's data
-- (no lite here: plain Lua, the editor opens a .tmx with it, tests run it).
--
--   local data, notes = Tmx.import(text [, read])
--     text: the .tmx's XML; read(path) -> a file's text, its path as the .tmx
--     names it (an external tileset: <tileset source="x.tsx">)
--     data: a .tmap's data (plugins/tilemap/map.lua: tileset, tile, w, h,
--     digits, layers with rows, areas, paths); notes: what couldn't come
--     along ({ "3 tiles of a 2nd tileset dropped", ... })
--
-- What comes along: orthogonal maps; tile layers (in groups too) as layers,
-- their data in CSV, base64, base64 + zlib or gzip (inflated here; zstd:
-- no), infinite maps' chunks; the first tileset's picture as the tileset
-- (embedded or a .tsx; tiles of the others are dropped, a note says how
-- many), its tile size; object layers: rectangles, ellipses and points as
-- areas, polygons as polygon areas, polylines as paths, an object's type and
-- properties as its props (ints and floats numbers, bools booleans), named
-- by its name (or its type, or "object <id>"). Flipped / turned tiles: the
-- tile, unflipped (a note). Image layers, text objects, margins and spacing
-- in a tileset: a note each.
local M = {}

-- XML: elements { tag, attr = {}, kids = {}, text } (enough for Tiled's files)
local ENT = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }
local function unescape(s)
  return (s:gsub("&(#?x?)(%w+);", function(p, n)
    if p == "" then return ENT[n] or ("&" .. n .. ";") end
    local v = tonumber(n, p == "#x" and 16 or 10)
    return v and v < 128 and string.char(v) or "?"
  end))
end
function M.xml(text)
  local root = { tag = "#root", attr = {}, kids = {} }
  local stack = { root }
  local pos = 1
  text = text:gsub("<!%-%-.-%-%->", ""):gsub("<%?.-%?>", ""):gsub("<!%[CDATA%[(.-)%]%]>", function(c) return c:gsub("<", "&lt;") end)
  while true do
    local s, e, close, tag, attrs, selfclose = text:find("<(/?)([%w_:%.%-]+)(.-)(/?)>", pos)
    local top = stack[#stack]
    local between = text:sub(pos, (s or #text + 1) - 1)
    if between:find("%S") then top.text = (top.text or "") .. unescape(between) end
    if not s then break end
    if close == "/" then
      if #stack > 1 then table.remove(stack) end
    else
      local el = { tag = tag, attr = {}, kids = {} }
      for k, _, v in attrs:gmatch("([%w_:%.%-]+)%s*=%s*([\"'])(.-)%2") do el.attr[k] = unescape(v) end
      top.kids[#top.kids + 1] = el
      if selfclose ~= "/" then stack[#stack + 1] = el end
    end
    pos = e + 1
  end
  return root
end
local function kids(el, tag)
  local out = {}
  for _, k in ipairs(el and el.kids or {}) do if not tag or k.tag == tag then out[#out + 1] = k end end
  return out
end
local function kid(el, tag) return kids(el, tag)[1] end

-- base64 -> bytes (a string)
local B64 = {}
do
  local a = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for i = 1, 64 do B64[a:byte(i)] = i - 1 end
end
function M.base64(s)
  local out, acc, bits = {}, 0, 0
  for i = 1, #s do
    local v = B64[s:byte(i)]
    if v then
      acc = acc * 64 + v
      bits = bits + 6
      if bits >= 8 then
        bits = bits - 8
        local p = 2 ^ bits
        local b = math.floor(acc / p)
        out[#out + 1] = string.char(b)
        acc = acc - b * p
      end
    end
  end
  return table.concat(out)
end

-- inflate (RFC 1951, after zlib's 2-byte header or gzip's) -> bytes | nil, why
local LBASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEXT = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DBASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DEXT = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }
local function huffman(lengths, n)                 -- (puff's: counts per length, symbols in code order)
  local h = { count = {}, symbol = {} }
  for l = 0, 15 do h.count[l] = 0 end
  for i = 0, n - 1 do h.count[lengths[i] or 0] = h.count[lengths[i] or 0] + 1 end
  local offs = { [1] = 0 }
  for l = 1, 14 do offs[l + 1] = offs[l] + h.count[l] end
  for i = 0, n - 1 do
    local l = lengths[i] or 0
    if l ~= 0 then h.symbol[offs[l]] = i; offs[l] = offs[l] + 1 end
  end
  return h
end
function M.inflate(data, start)
  local pos, buf, cnt = start or 1, 0, 0
  local out, n = {}, 0
  local function bits(k)
    while cnt < k do
      local b = data:byte(pos)
      if not b then error("inflate: the data ends early", 0) end
      pos = pos + 1
      buf = buf + b * 2 ^ cnt
      cnt = cnt + 8
    end
    local p = 2 ^ k
    local v = buf % p
    buf = (buf - v) / p
    cnt = cnt - k
    return v
  end
  local function decode(h)
    local code, first, index = 0, 0, 0
    for len = 1, 15 do
      code = code + bits(1)
      local count = h.count[len]
      if code - count < first then return h.symbol[index + (code - first)] end
      index = index + count
      first = (first + count) * 2
      code = code * 2
    end
    error("inflate: a bad code", 0)
  end
  local fixed_l, fixed_d
  local function codes(lh, dh)
    while true do
      local sym = decode(lh)
      if sym < 256 then n = n + 1; out[n] = sym
      elseif sym == 256 then return
      else
        sym = sym - 257
        if sym >= 29 then error("inflate: a bad length", 0) end
        local len = LBASE[sym + 1] + bits(LEXT[sym + 1])
        local ds = decode(dh)
        if ds >= 30 then error("inflate: a bad distance", 0) end
        local dist = DBASE[ds + 1] + bits(DEXT[ds + 1])
        if dist > n then error("inflate: too far back", 0) end
        for _ = 1, len do n = n + 1; out[n] = out[n - dist] end
      end
    end
  end
  local ok, err = pcall(function()
    repeat
      local last = bits(1)
      local kind = bits(2)
      if kind == 0 then                            -- stored
        buf, cnt = 0, 0
        local a, b = data:byte(pos, pos + 1)
        local len = (a or 0) + (b or 0) * 256
        pos = pos + 4
        for i = 0, len - 1 do n = n + 1; out[n] = data:byte(pos + i) or 0 end
        pos = pos + len
      elseif kind == 1 then                        -- fixed codes
        if not fixed_l then
          local l = {}
          for i = 0, 143 do l[i] = 8 end
          for i = 144, 255 do l[i] = 9 end
          for i = 256, 279 do l[i] = 7 end
          for i = 280, 287 do l[i] = 8 end
          fixed_l = huffman(l, 288)
          local d = {}
          for i = 0, 29 do d[i] = 5 end
          fixed_d = huffman(d, 30)
        end
        codes(fixed_l, fixed_d)
      elseif kind == 2 then                        -- dynamic codes
        local nlen, ndist, ncode = bits(5) + 257, bits(5) + 1, bits(4) + 4
        local lens = {}
        for i = 0, 18 do lens[i] = 0 end
        for i = 1, ncode do lens[ORDER[i]] = bits(3) end
        local ch = huffman(lens, 19)
        local all, i = {}, 0
        while i < nlen + ndist do
          local sym = decode(ch)
          if sym < 16 then all[i] = sym; i = i + 1
          else
            local rep, v = 0, 0
            if sym == 16 then
              if i == 0 then error("inflate: a repeat with nothing before", 0) end
              v = all[i - 1]; rep = 3 + bits(2)
            elseif sym == 17 then rep = 3 + bits(3)
            else rep = 11 + bits(7) end
            for _ = 1, rep do all[i] = v; i = i + 1 end
          end
        end
        local ll, dl = {}, {}
        for k = 0, nlen - 1 do ll[k] = all[k] end
        for k = 0, ndist - 1 do dl[k] = all[nlen + k] end
        codes(huffman(ll, nlen), huffman(dl, ndist))
      else error("inflate: a bad block", 0) end
    until last == 1
  end)
  if not ok then return nil, err end
  local parts = {}
  for k = 1, n, 4096 do parts[#parts + 1] = string.char((table.unpack or unpack)(out, k, math.min(n, k + 4095))) end
  return table.concat(parts)
end
function M.unzip(data, how)                        -- zlib / gzip -> bytes | nil, why
  if how == "zlib" then return M.inflate(data, 3) end
  if how == "gzip" then
    local flg = data:byte(4) or 0
    local p = 11
    local function has(b) return math.floor(flg / b) % 2 == 1 end
    if has(4) then local a, b = data:byte(p, p + 1); p = p + 2 + (a or 0) + (b or 0) * 256 end
    if has(8) then p = (data:find("\0", p, true) or #data) + 1 end
    if has(16) then p = (data:find("\0", p, true) or #data) + 1 end
    if has(2) then p = p + 2 end
    return M.inflate(data, p)
  end
  return nil, "no " .. tostring(how)
end

-- a layer's (or a chunk's) <data> -> its gids (a list)
local function gids(data, notes)
  local enc, comp = data.attr.encoding, data.attr.compression
  local out = {}
  if enc == "csv" then
    for v in (data.text or ""):gmatch("%d+") do out[#out + 1] = tonumber(v) end
  elseif enc == "base64" then
    local bytes = M.base64(data.text or "")
    if comp and comp ~= "" then
      local raw, err = M.unzip(bytes, comp)
      if not raw then notes[#notes + 1] = "a layer's data (" .. tostring(comp) .. "): " .. tostring(err); return out end
      bytes = raw
    end
    for i = 1, #bytes - 3, 4 do
      local a, b, c, d = bytes:byte(i, i + 3)
      out[#out + 1] = a + b * 256 + c * 65536 + d * 16777216
    end
  else                                             -- (the old XML form: <tile gid="..."/>)
    for _, t in ipairs(kids(data, "tile")) do out[#out + 1] = tonumber(t.attr.gid) or 0 end
  end
  return out
end

local function dir_of(p) return p:match("^(.*)[/\\]") end
local function join(dir, p)
  if not dir or p:match("^/") or p:match("^%a:[/\\]") then return p end
  local parts = {}
  for s in (dir .. "/" .. p):gmatch("[^/\\]+") do
    if s == ".." and #parts > 0 and parts[#parts] ~= ".." then parts[#parts] = nil
    elseif s ~= "." then parts[#parts + 1] = s end
  end
  return table.concat(parts, "/")
end
local function props_of(el, into)
  local pr = kid(el, "properties")
  for _, p in ipairs(kids(pr, "property")) do
    local name = p.attr.name
    if name then
      local v, ty = p.attr.value or p.text or "", p.attr.type
      if ty == "int" or ty == "float" then v = tonumber(v) or 0
      elseif ty == "bool" then v = v == "true" end
      into = into or {}
      into[name] = v
    end
  end
  return into
end

function M.import(text, read)
  local notes = {}
  local doc = M.xml(text or "")
  local map = kid(doc, "map")
  if not map then return nil, { "not a Tiled map (no <map>)" } end
  local A = map.attr
  if A.orientation and A.orientation ~= "orthogonal" then notes[#notes + 1] = "a " .. A.orientation .. " map: drawn as an orthogonal one" end
  local tw, th = tonumber(A.tilewidth) or 16, tonumber(A.tileheight) or 16
  if tw ~= th then notes[#notes + 1] = string.format("tiles %d x %d: square ones here (%d)", tw, th, tw) end
  local W, H = tonumber(A.width) or 1, tonumber(A.height) or 1
  -- the tilesets: the first one's picture is the tileset
  local sets = {}
  for _, ts in ipairs(kids(map, "tileset")) do
    local el, base = ts, nil
    if ts.attr.source then                        -- (an external one: its .tsx)
      local t = read and read(ts.attr.source)
      local tsx = t and kid(M.xml(t), "tileset")
      if tsx then el, base = tsx, dir_of(ts.attr.source) else notes[#notes + 1] = "can't read the tileset " .. ts.attr.source end
    end
    local img = kid(el, "image")
    sets[#sets + 1] = { first = tonumber(ts.attr.firstgid) or 1, name = el.attr.name, image = img and img.attr.source and join(base, img.attr.source),
                        margin = tonumber(el.attr.margin) or 0, spacing = tonumber(el.attr.spacing) or 0, columns = tonumber(el.attr.columns) }
  end
  table.sort(sets, function(a, b) return a.first < b.first end)
  local set = sets[1]
  if not set then notes[#notes + 1] = "no tileset: the plugin's" end
  if set and not set.image then notes[#notes + 1] = "the tileset has no single picture (a collection of images): the plugin's" end
  if set and (set.margin > 0 or set.spacing > 0) then notes[#notes + 1] = "the tileset's margin / spacing: not read (tiles packed edge to edge here)" end
  local first = set and set.first or 1
  local last = sets[2] and sets[2].first or math.huge
  local dropped, flipped = 0, 0
  local maxtile = 0
  local layers, areas, paths = {}, {}, {}
  -- infinite maps: their chunks' bounds first
  local ox, oy = 0, 0
  if A.infinite == "1" then
    local x0, y0, x1, y1
    local function scan(el)
      for _, k in ipairs(el.kids) do
        if k.tag == "layer" then
          for _, c in ipairs(kids(kid(k, "data"), "chunk")) do
            local cx, cy, cw, chh = tonumber(c.attr.x) or 0, tonumber(c.attr.y) or 0, tonumber(c.attr.width) or 0, tonumber(c.attr.height) or 0
            x0, y0 = math.min(x0 or cx, cx), math.min(y0 or cy, cy)
            x1, y1 = math.max(x1 or cx + cw, cx + cw), math.max(y1 or cy + chh, cy + chh)
          end
        elseif k.tag == "group" then scan(k) end
      end
    end
    scan(map)
    if x0 then ox, oy, W, H = x0, y0, x1 - x0, y1 - y0 end
    notes[#notes + 1] = string.format("an infinite map: its chunks in a %d x %d map", W, H)
  end
  W, H = math.max(1, math.min(512, W)), math.max(1, math.min(512, H))
  local function cell_of(gid)
    if gid == 0 then return false end
    local id = gid % 268435456                     -- (flip / turn flags: the top bits)
    if id ~= gid then flipped = flipped + 1 end
    if id < first or id >= last then dropped = dropped + 1 return false end
    local c = id - first
    if c >= 65535 then dropped = dropped + 1 return false end
    if c > maxtile then maxtile = c end
    return c
  end
  local function walk(el, prefix)
    for _, k in ipairs(el.kids) do
      if k.tag == "layer" then
        local cells = {}
        local data = kid(k, "data")
        if data then
          local chunks = kids(data, "chunk")
          if #chunks > 0 then
            for _, c in ipairs(chunks) do
              local cx, cy, cw = (tonumber(c.attr.x) or 0) - ox, (tonumber(c.attr.y) or 0) - oy, tonumber(c.attr.width) or 0
              c.attr.encoding, c.attr.compression = data.attr.encoding, data.attr.compression
              for i, g in ipairs(gids(c, notes)) do
                local x, y = cx + (i - 1) % cw, cy + math.floor((i - 1) / cw)
                if x >= 0 and y >= 0 and x < W and y < H then cells[y * W + x + 1] = cell_of(g) end
              end
            end
          else
            for i, g in ipairs(gids(data, notes)) do if i <= W * H then cells[i] = cell_of(g) end end
          end
        end
        layers[#layers + 1] = { name = prefix .. (k.attr.name or ("layer " .. (#layers + 1))), visible = k.attr.visible ~= "0", cells = cells }
      elseif k.tag == "group" then walk(k, prefix .. (k.attr.name or "group") .. "/")
      elseif k.tag == "objectgroup" then
        for _, o in ipairs(kids(k, "object")) do
          local x, y = tonumber(o.attr.x) or 0, tonumber(o.attr.y) or 0
          local name = o.attr.name or o.attr.type or o.attr.class or ("object " .. tostring(o.attr.id))
          local props = props_of(o)
          local ty = o.attr.type or o.attr.class
          if ty then props = props or {}; props.type = ty end
          if (tonumber(o.attr.rotation) or 0) ~= 0 then notes[#notes + 1] = name .. ": its rotation dropped" end
          local poly, line = kid(o, "polygon"), kid(o, "polyline")
          local function pts(el2)
            local list = {}
            for px, py in (el2.attr.points or ""):gmatch("([%-%d%.eE]+),([%-%d%.eE]+)") do list[#list + 1] = x + tonumber(px); list[#list + 1] = y + tonumber(py) end
            return list
          end
          if kid(o, "text") then notes[#notes + 1] = name .. ": a text object, dropped"
          elseif poly then
            local p = pts(poly)
            if #p >= 6 then areas[#areas + 1] = { name = name, points = p, props = props } end
          elseif line then
            local p = pts(line)
            if #p >= 2 then paths[#paths + 1] = { name = name, points = p, props = props } end
          else
            local w, h = tonumber(o.attr.width) or 0, tonumber(o.attr.height) or 0
            if o.attr.gid then                     -- (a tile object: its y is its bottom)
              y = y - h
              local c = cell_of(tonumber(o.attr.gid) or 0)
              if c then props = props or {}; props.tile = c end
            end
            if kid(o, "ellipse") then props = props or {}; props.shape = "ellipse"
            elseif kid(o, "point") then props = props or {}; props.shape = "point" end
            areas[#areas + 1] = { name = name, x = x, y = y, w = w, h = h, props = props }
          end
        end
      elseif k.tag == "imagelayer" then notes[#notes + 1] = "the image layer " .. tostring(k.attr.name) .. ": dropped"
      end
    end
  end
  walk(map, "")
  if dropped > 0 then notes[#notes + 1] = dropped .. " cells of other tilesets dropped (the first one's tiles only)" end
  if flipped > 0 then notes[#notes + 1] = flipped .. " flipped / turned tiles: unflipped" end
  if #layers == 0 then layers[1] = { name = "ground", visible = true, cells = {} } end
  local d = maxtile > 255 and 4 or 2
  local fmt, none = "%0" .. d .. "x", string.rep(".", d)
  local out = { tileset = set and set.image or "plugin:tiles.png", tile = tw, w = W, h = H, digits = d == 4 and 4 or nil, layers = {} }
  for _, l in ipairs(layers) do
    local rows = {}
    for y = 0, H - 1 do
      local parts = {}
      for x = 0, W - 1 do local c = l.cells[y * W + x + 1]; parts[x + 1] = c and string.format(fmt, c) or none end
      rows[y + 1] = table.concat(parts)
    end
    out.layers[#out.layers + 1] = { name = l.name, visible = l.visible, rows = rows }
  end
  if #areas > 0 then out.areas = areas end
  if #paths > 0 then out.paths = paths end
  return out, notes
end

return M
