-- ase.lua - Aseprite files (.ase / .aseprite) read into a spritesheet and a
-- .anim's data (plugins/spriteanim; plain Lua: the editor imports with it,
-- tests run it). From Aseprite's file format spec (docs/ase-file-specs.md in
-- its repository): RGBA, grayscale and indexed sprites; layers (visible ones,
-- normal blend, their opacity), cels (raw, linked, zlib), tags (animations:
-- forward, reverse, ping-pong, their repeat), slices (hitboxes, pivots).
--
--   local doc = Ase.read(bytes) -> { w, h, depth, frames = { { duration, rgba } },
--     layers, tags = { { name, from, to, dir, rep } }, slices = { { name, keys } } } | nil, why
--   local sheet = Ase.sheet(doc [, cols]) -> { w, h, rgba, rects = { { x0, y0, x1, y1 } per frame } }
--   local def = Ase.anim(doc, sheet, "hero.png") -> a .anim's data (runtime/anim.lua):
--     a tag per animation (none: one "all"), each frame's duration as its pause,
--     slices named hit1 / hit2 (or hitbox, hurtbox) as hitboxes, a slice's pivot as
--     the anchor (else the bottom middle), repeat 0 as looping
local Tmx = dofile((rawget(_G, "ASE_TMX") or ((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./") .. "../tilemap/tmx.lua")))
local M = {}

local function rd(s)
  local p = 1
  local R = {}
  function R.pos() return p end
  function R.seek(q) p = q end
  function R.skip(n) p = p + n end
  function R.byte() local b = s:byte(p) or 0; p = p + 1; return b end
  function R.word() local a, b = s:byte(p, p + 1); p = p + 2; return (a or 0) + (b or 0) * 256 end
  function R.short() local v = R.word(); return v >= 32768 and v - 65536 or v end
  function R.dword() local a, b, c, d = s:byte(p, p + 3); p = p + 4; return (a or 0) + (b or 0) * 256 + (c or 0) * 65536 + (d or 0) * 16777216 end
  function R.long() local v = R.dword(); return v >= 2147483648 and v - 4294967296 or v end
  function R.str() local n = R.word(); local t = s:sub(p, p + n - 1); p = p + n; return t end
  function R.bytes(n) local t = s:sub(p, p + n - 1); p = p + n; return t end
  return R
end

function M.read(s)
  if type(s) ~= "string" or #s < 128 then return nil, "too short for an Aseprite file" end
  local R = rd(s)
  R.dword()
  if R.word() ~= 0xA5E0 then return nil, "not an Aseprite file (no A5E0)" end
  local nframes, W, H, depth = R.word(), R.word(), R.word(), R.word()
  local flags = R.dword()
  R.word(); R.dword(); R.dword()
  local transparent = R.byte()
  R.seek(129)
  if depth ~= 32 and depth ~= 16 and depth ~= 8 then return nil, "colour depth " .. depth .. "?" end
  local bpp = depth / 8
  local doc = { w = W, h = H, depth = depth, frames = {}, layers = {}, tags = {}, slices = {}, palette = {}, notes = {} }
  local cels = {}                                  -- per frame: { layer, x, y, opacity, w, h, px | link }
  for f = 1, nframes do
    local start = R.pos()
    local size = R.dword()
    if R.word() ~= 0xF1FA then return nil, "frame " .. f .. ": bad magic" end
    local old = R.word()
    local dur = R.word()
    R.skip(2)
    local n = R.dword()
    if n == 0 then n = old end
    doc.frames[f] = { duration = dur > 0 and dur or 100 }
    cels[f] = {}
    for _ = 1, n do
      local cstart = R.pos()
      local csize, ctype = R.dword(), R.word()
      if ctype == 0x2004 then                      -- a layer
        local lf, lt, lchild = R.word(), R.word(), R.word()
        R.word(); R.word()
        local blend, opacity = R.word(), R.byte()
        R.skip(3)
        local name = R.str()
        doc.layers[#doc.layers + 1] = { name = name, visible = lf % 2 == 1, type = lt, child = lchild, blend = blend,
                                        opacity = (flags % 2 == 1) and opacity or 255 }
      elseif ctype == 0x2005 then                  -- a cel
        local li, x, y, op, kind = R.word(), R.short(), R.short(), R.byte(), R.word()
        R.short(); R.skip(5)
        local c = { layer = li + 1, x = x, y = y, opacity = op }
        if kind == 0 or kind == 2 then
          c.w, c.h = R.word(), R.word()
          local data = s:sub(R.pos(), cstart + csize - 1)
          if kind == 2 then
            local raw, err = Tmx.unzip(data, "zlib")
            if not raw then return nil, "a cel's pixels: " .. tostring(err) end
            data = raw
          end
          c.px = data
        elseif kind == 1 then c.link = R.word() + 1
        else doc.notes[#doc.notes + 1] = "a tilemap cel: left out" end
        cels[f][#cels[f] + 1] = c
      elseif ctype == 0x2018 then                  -- tags
        local nt = R.word()
        R.skip(8)
        for _ = 1, nt do
          local from, to, dir, rep = R.word(), R.word(), R.byte(), R.word()
          R.skip(6 + 3 + 1)
          doc.tags[#doc.tags + 1] = { name = R.str(), from = from + 1, to = to + 1, dir = dir, rep = rep }
        end
      elseif ctype == 0x2019 then                  -- the palette
        R.dword()
        local first, last = R.dword(), R.dword()
        R.skip(8)
        for i = first, last do
          local ef = R.word()
          doc.palette[i] = { R.byte(), R.byte(), R.byte(), R.byte() }
          if ef % 2 == 1 then R.str() end
        end
      elseif (ctype == 0x0004 or ctype == 0x0011) and not next(doc.palette) then   -- an old palette (when there's no new one)
        local packets, idx = R.word(), 0
        for _ = 1, packets do
          idx = idx + R.byte()
          local nc = R.byte(); if nc == 0 then nc = 256 end
          for _ = 1, nc do
            local r, g, b = R.byte(), R.byte(), R.byte()
            if ctype == 0x0011 then r, g, b = r * 4, g * 4, b * 4 end
            doc.palette[idx] = { r, g, b, 255 }; idx = idx + 1
          end
        end
      elseif ctype == 0x2022 then                  -- a slice
        local nk, sf = R.dword(), R.dword()
        R.dword()
        local sl = { name = R.str(), keys = {} }
        for _ = 1, nk do
          local k = { frame = R.dword() + 1, x = R.long(), y = R.long(), w = R.dword(), h = R.dword() }
          if sf % 2 == 1 then R.long(); R.long(); R.dword(); R.dword() end
          if math.floor(sf / 2) % 2 == 1 then k.px, k.py = R.long(), R.long() end
          sl.keys[#sl.keys + 1] = k
        end
        doc.slices[#doc.slices + 1] = sl
      end
      R.seek(cstart + csize)
    end
    R.seek(start + size)
  end
  -- frames flattened: the visible normal layers, bottom to top, over transparent
  local hidden = {}                                -- (a layer under a hidden group: hidden)
  local stack = {}
  for i, L in ipairs(doc.layers) do
    stack[L.child] = L.visible and not (L.child > 0 and stack[L.child - 1] == false)
    hidden[i] = not stack[L.child] or L.type ~= 0
  end
  local function color_at(c, i)                    -- a cel's pixel i (0-based) -> r, g, b, a
    local px = c.px
    if bpp == 4 then local r, g, b, a = px:byte(i * 4 + 1, i * 4 + 4); return r or 0, g or 0, b or 0, a or 0 end
    if bpp == 2 then local v, a = px:byte(i * 2 + 1, i * 2 + 2); return v or 0, v or 0, v or 0, a or 0 end
    local k = px:byte(i + 1) or 0
    if k == transparent then return 0, 0, 0, 0 end
    local p = doc.palette[k] or { 0, 0, 0, 255 }
    return p[1], p[2], p[3], p[4]
  end
  for f = 1, nframes do
    local out = {}
    for i = 1, W * H * 4 do out[i] = 0 end
    local list = {}
    for _, c in ipairs(cels[f]) do
      if c.link then                               -- (linked: that frame's cel of the same layer)
        for _, o in ipairs(cels[c.link] or {}) do if o.layer == c.layer and o.px then c = o break end end
      end
      if c.px and not hidden[c.layer] then list[#list + 1] = c end
    end
    table.sort(list, function(a, b) return a.layer < b.layer end)
    for _, c in ipairs(list) do
      local op = (c.opacity / 255) * ((doc.layers[c.layer] or {}).opacity or 255) / 255
      for y = 0, c.h - 1 do
        local ty = c.y + y
        if ty >= 0 and ty < H then
          for x = 0, c.w - 1 do
            local tx = c.x + x
            if tx >= 0 and tx < W then
              local r, g, b, a = color_at(c, y * c.w + x)
              a = a * op
              if a > 0 then
                local o = (ty * W + tx) * 4
                local da = out[o + 4] / 255
                local sa = a / 255
                local na = sa + da * (1 - sa)
                if na > 0 then
                  out[o + 1] = math.floor((r * sa + out[o + 1] * da * (1 - sa)) / na + 0.5)
                  out[o + 2] = math.floor((g * sa + out[o + 2] * da * (1 - sa)) / na + 0.5)
                  out[o + 3] = math.floor((b * sa + out[o + 3] * da * (1 - sa)) / na + 0.5)
                end
                out[o + 4] = math.floor(na * 255 + 0.5)
              end
            end
          end
        end
      end
    end
    local parts = {}
    local unpack = table.unpack or unpack
    for k = 1, #out, 4096 do parts[#parts + 1] = string.char(unpack(out, k, math.min(#out, k + 4095))) end
    doc.frames[f].rgba = table.concat(parts)
  end
  return doc
end

-- the frames side by side (cols a row; default: a square-ish grid)
function M.sheet(doc, cols)
  local n = #doc.frames
  cols = math.max(1, math.min(n, cols or math.ceil(math.sqrt(n))))
  local rows = math.ceil(n / cols)
  local SW, SH = doc.w * cols, doc.h * rows
  local row_bytes = {}
  local rects = {}
  local blank = string.rep("\0", doc.w * 4)
  local lines = {}
  for y = 0, SH - 1 do lines[y] = {} end
  for i, fr in ipairs(doc.frames) do
    local cx, cy = (i - 1) % cols, math.floor((i - 1) / cols)
    rects[i] = { cx * doc.w, cy * doc.h, cx * doc.w + doc.w, cy * doc.h + doc.h }
    for y = 0, doc.h - 1 do
      lines[cy * doc.h + y][cx + 1] = fr.rgba:sub(y * doc.w * 4 + 1, (y + 1) * doc.w * 4)
    end
  end
  for y = 0, SH - 1 do
    local l = lines[y]
    for c = 1, cols do l[c] = l[c] or blank end
    row_bytes[#row_bytes + 1] = table.concat(l)
  end
  return { w = SW, h = SH, rgba = table.concat(row_bytes), rects = rects, cols = cols }
end

local HIT = { hit1 = 1, hitbox = 1, hit = 1, hit2 = 2, hurtbox = 2, hurt = 2 }
local function slice_key(sl, f)                    -- a slice's key for frame f: the last one at or before it
  local k
  for _, x in ipairs(sl.keys) do if x.frame <= f then k = x end end
  return k
end
function M.anim(doc, sheet, sheet_name)
  local tags = doc.tags
  if #tags == 0 then tags = { { name = "all", from = 1, to = #doc.frames, dir = 0, rep = 0 } } end
  local def = { version = 2, sheet = sheet_name or "", anims = {} }
  local slot, names, nexti = {}, {}, 3              -- (slices: hit1 / hit2 (and their aliases) as hitboxes 1, 2; any other name, the next one: named)
  for _, sl in ipairs(doc.slices) do
    local key = sl.name:lower()
    if key == "pivot" or key == "anchor" or key == "origin" then   -- (a slice for the anchor only: its pivot, no hitbox)
    elseif HIT[key] then slot[sl.name] = HIT[key]
    elseif not slot[sl.name] and nexti <= 10 then slot[sl.name] = nexti; names[nexti] = sl.name; nexti = nexti + 1 end
  end
  if next(names) then
    def.hit_names = {}
    for k = 1, nexti - 1 do def.hit_names[k] = names[k] or false end
  end
  for _, t in ipairs(tags) do
    local order = {}
    for f = t.from, t.to do order[#order + 1] = f end
    if t.dir == 1 or t.dir == 3 then local r = {}; for i = #order, 1, -1 do r[#r + 1] = order[i] end; order = r end
    if t.dir == 2 or t.dir == 3 then for i = #order - 1, 2, -1 do order[#order + 1] = order[i] end end   -- (ping-pong: back, ends not twice)
    local loops = t.rep == 0
    local A = { name = t.name, frames = {} }
    for _, f in ipairs(order) do
      local r = sheet.rects[f]
      local fr = { rect = { r[1], r[2], r[3], r[4] }, pause = doc.frames[f].duration, pivot = { (r[3] - r[1]) / 2, r[4] - r[2] } }   -- (its anchor: the bottom middle, from the rect's top left)
      for _, sl in ipairs(doc.slices) do
        local k = slice_key(sl, f)
        local which = slot[sl.name]
        if k and which then fr.hits = fr.hits or {}; fr.hits[which] = { k.x, k.y, k.x + k.w, k.y + k.h } end
        if k and k.px then fr.pivot = { k.x + k.px, k.y + k.py } end
      end
      if fr.hits then for w = 1, #fr.hits do if fr.hits[w] == nil then fr.hits[w] = false end end end
      A.frames[#A.frames + 1] = fr
    end
    if t.rep and t.rep > 1 and not loops then      -- (played N times, then it ends: the frames N times)
      local once = #A.frames
      for _ = 2, t.rep do for i = 1, once do A.frames[#A.frames + 1] = A.frames[i] end end
    end
    if loops and #A.frames > 0 then                -- (it loops: its last frame jumps to the first)
      local last = {}
      for k, v in pairs(A.frames[#A.frames]) do last[k] = v end
      last.jump = 1
      A.frames[#A.frames] = last
    end
    def.anims[#def.anims + 1] = A
  end
  return def
end
return M
