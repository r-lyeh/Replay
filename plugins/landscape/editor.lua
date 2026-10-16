-- editor.lua - the landscape editor: .land files (runs in Lite). A height field over an area, as UE5's: its base
-- made by rules (the generator: hills or flat; a seed, a height, a scale, detail, ridges, a sea level), then the
-- brushes on top: Sculpt (SHIFT lowers), Smooth, Flatten (to the height where the stroke began), Erase (back to
-- the generator's). The middle shows it in 3D as a game draws it (the host's picture: shadows, its colours by
-- height and slope); LMB paints with the brush, RMB drag turns round it, MMB drag pans, the wheel zooms,
-- double-click: back to the start. A stroke is one undo step. Left: the brush, samples to start from, Save.
-- Right: the area (size, cells), the generator, the colours. Changing the generator keeps the brushes' work
-- on top of it; another grid size stretches it over the new one.
-- In a game: a node's landscape3d = { "hills.land" } under a camera3d (games/landscape3d.lua); w:landscape(name)
-- -> land, land:height_at(x, z).
--
-- The height field is runtime/landscape.lua's (no Lite there: the renderer and games build the same one).
local P = ...
P.title = "Landscape editor"                       -- (its name in menus: Open with, the main menu's Plugins)
P.category = "Levels"                              -- (the main menu: Levels >)
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local canvas = require "plugins.canvas"
local M = dofile((rawget(_G, "REPLAY_ROOT") or (DATADIR .. "/../../..")) .. "/runtime/landscape.lua")
local F = dofile((rawget(_G, "REPLAY_ROOT") or (DATADIR .. "/../../..")) .. "/runtime/foliage.lua")

local function S(n) return math.floor(n * SCALE + 0.5) end
local function base_of(f) return (f:match("[^/\\]*$")) end
local function read(file)
  local f = io.open(file, "rb")
  if not f then return nil, "can't read" end
  local src = f:read("*a")
  f:close()
  if src:match("^%s*$") then return {} end
  local fn, err = load(src, "=" .. file, "t", {})
  if not fn then return nil, err end
  local ok, v = pcall(fn)
  if not ok or type(v) ~= "table" then return nil, ok and "not a table" or v end
  return v
end
local TOOLS = {                                    -- (the brushes: name, what it does, its tip)
  { "sculpt", "Sculpt", "up (SHIFT: down)" },
  { "smooth", "Smooth", "evens out bumps" },
  { "flatten", "Flatten", "to where the stroke began" },
  { "erase", "Erase", "back to the generator's" },
}

-- the 3D views drawn in a frame of Lite's: the others (a tab behind another, closed) are taken away from the
-- host's list, so their pictures don't stay (as plugins/modelview's, plugins/foliage's)
local shown = package.loaded["landscape.shown"]
if not shown then
  shown = { now = {}, last = {} }
  package.loaded["landscape.shown"] = shown
  local begin_frame, end_frame = renderer.begin_frame, renderer.end_frame
  renderer.begin_frame = function(...) shown.now = {}; return begin_frame(...) end
  renderer.end_frame = function(...)
    for key in pairs(shown.last) do if not shown.now[key] and host_view3d then host_view3d { key = key, remove = true } end end
    shown.last = shown.now
    return end_frame(...)
  end
end
local next_id = 0

local LView = canvas.View:extend()

function LView:new(state)
  LView.super.new(self)
  self.filename = state and state.filename or ""
  self.untitled = state and state.untitled or self.filename == ""
  self.left, self.right = canvas.ui.new(), canvas.ui.new()
  self.undo, self.redo = {}, {}
  self.brush = { tool = "sculpt", radius = 6, strength = 0.5 }
  self.show_foliage = true                         -- (the .foliage files growing on it, shown on it)
  next_id = next_id + 1
  self.key = "landscape" .. next_id
  local t, err = read(self.untitled and (P.dir .. "/templates/landscape.land") or self.filename)
  self.err = not t and err or nil
  self.s = M.check(t)
  self:make()
  self:reset_view()
  if state and state.cam then self.yaw, self.pitch, self.dist, self.at = state.cam.yaw or self.yaw, state.cam.pitch or self.pitch, state.cam.dist, state.cam.at end
end
function LView:try_close(do_close)
  if host_view3d then host_view3d { key = self.key, remove = true } end
  return LView.super.try_close(self, do_close)
end
function LView:get_name() return (self.untitled and "untitled.land" or base_of(self.filename)) .. (self.dirty and "*" or "") end
function LView:get_state() return { filename = self.filename, untitled = self.untitled, cam = { yaw = self.yaw, pitch = self.pitch, dist = self.dist, at = self.at } } end

-- the camera: round a point (at), yaw / pitch / dist
function LView:reset_view()
  self.yaw, self.pitch, self.dist, self.at = 0.7, 0.55, nil, nil
  core.redraw = true
end
function LView:target() return self.at or { 0, (self.land and self.land.top or 0) * 0.3, 0 } end
function LView:distance() return self.dist or math.max(self.s.w, self.s.d) * 1.05 end
function LView:eye()
  local d, a, cp = self:distance(), self:target(), math.cos(self.pitch)
  return { a[1] + math.sin(self.yaw) * cp * d, a[2] + math.sin(self.pitch) * d, a[3] + math.cos(self.yaw) * cp * d }
end
local FOV = 50
local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function unit(a) local l = math.sqrt(dot(a, a)); return l > 1e-9 and { a[1] / l, a[2] / l, a[3] / l } or a end
local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
function LView:frame3d()                           -- the camera: eye, forward, right, up, tan(fov / 2), aspect, its rect
  local m = self:rects().mid
  local eye = self:eye()
  local f = unit(sub(self:target(), eye))
  local r = unit(cross(f, { 0, 1, 0 }))
  return eye, f, r, cross(r, f), math.tan(math.rad(FOV) / 2), m[3] / math.max(1, m[4]), m
end
function LView:ground_at(x, y)                     -- the landscape under the mouse -> x, y, z | nil (the sky, past its edge)
  local m = self:rects().mid
  if x < m[1] or y < m[2] or x >= m[1] + m[3] or y >= m[2] + m[4] then return nil end
  local eye, f, r, u, t, asp = self:frame3d()
  local nx, ny = (x - m[1]) / m[3] * 2 - 1, 1 - (y - m[2]) / m[4] * 2
  local d = { f[1] + (r[1] * nx * asp + u[1] * ny) * t, f[2] + (r[2] * nx * asp + u[2] * ny) * t, f[3] + (r[3] * nx * asp + u[3] * ny) * t }
  local hit, hx, hy, hz = M.ray(self.land, eye[1], eye[2], eye[3], d[1], d[2], d[3], 1e5)
  if hit then return hx, hy, hz end
end
function LView:project(p)                          -- a point of the world -> the view's pixel | nil (behind)
  local eye, f, r, u, t, asp, m = self:frame3d()
  local rel = sub(p, eye)
  local z = dot(rel, f)
  if z < 0.05 then return nil end
  return m[1] + (1 + dot(rel, r) / (z * t * asp)) * m[3] / 2, m[2] + (1 - dot(rel, u) / (z * t)) * m[4] / 2
end

-- the foliage growing on it: the project's .foliage files whose ground is this landscape (beside it, the game's
-- assets/, common/), each grown on it as it is: again at a stroke's end, the copies under the brush put back on
-- the ground at each dab (F.drape); all of them one scatter for the host (merged)
local function dirs_near(file)
  local dirs, seen = {}, {}
  local function add(d) if d and d ~= "" and not seen[d] then seen[d] = true; dirs[#dirs + 1] = d end end
  if file and file ~= "" then add(file:gsub("\\", "/"):match("^(.*)/")) end
  local root = rawget(_G, "replay_open_dir") and replay_open_dir() or nil
  if root and root ~= "" then root = root:gsub("\\", "/"):gsub("/$", ""); add(root .. "/assets"); add(root .. "/common") end
  return dirs
end
function LView:find_foliage()                      -- -> { { path, s } } (the .foliage files on this landscape)
  local out = {}
  if self.untitled then return out end
  local me = base_of(self.filename):lower()
  for _, d in ipairs(dirs_near(self.filename)) do
    for _, f in ipairs(system.list_dir(d) or {}) do
      if f:match("%.foliage$") then
        local t = read(d .. "/" .. f)
        if t and type(t.ground) == "string" and (t.ground:gsub("^/assets/", ""):gsub("^.*/", ""):lower() == me or (t.ground:lower() .. ".land") == me) then
          out[#out + 1] = { path = d .. "/" .. f, s = F.check(t) }
        end
      end
    end
  end
  return out
end
local function merge(list)                         -- several scatters -> one (their meshes one after another)
  if #list == 1 then return list[1] end
  local it = { meshes = {}, wind = {}, fade = {}, of = {}, n = 0 }
  local arrays = { "layer", "part", "x", "y", "z", "ry", "rx", "rz", "sx", "sy", "sz", "r", "g", "b" }
  for _, a in ipairs(arrays) do it[a] = {} end
  for _, src in ipairs(list) do
    local base = #it.meshes
    for m = 1, #src.meshes do
      if base + m > F.PARTS then break end
      it.meshes[base + m], it.wind[base + m], it.fade[base + m] = src.meshes[m], src.wind[m], src.fade[m]
    end
    for i = 1, src.n do
      if src.part[i] + base <= F.PARTS then
        local n = it.n + 1
        it.n = n
        for _, a in ipairs(arrays) do it[a][n] = src[a][i] end
        it.part[n] = src.part[i] + base
      end
    end
  end
  return it
end
function LView:grow(x0, z0, x1, z1)               -- the foliage on it: anew (none given), or the copies within that put back on it
  if not self.show_foliage then self.fol_items = nil return end
  if not self.fol then self.fol = self:find_foliage() end
  if #self.fol == 0 then self.fol_items = nil return end
  local list = {}
  for _, f in ipairs(self.fol) do
    if x0 and f.items then F.drape(f.items, f.s, self.land, x0, z0, x1, z1)
    else f.items, f.info = F.generate(f.s, self.land) end
    list[#list + 1] = f.items
  end
  local it = merge(list)
  if it == list[1] then                            -- (the host reads a scatter again when it's another table: a shallow copy)
    local c = {}
    for k, v in pairs(it) do c[k] = v end
    it = c
  end
  self.fol_items = it
end

-- the height field
function LView:make(old)                           -- built again from the settings (old: the last one, its edits kept)
  local t0 = system.get_time()
  self.land = M.rebuild(self.s, old)
  self.ms = (system.get_time() - t0) * 1000
  self.edited = M.edited(self.land)
  self:grow()
  core.redraw = true
end
function LView:snapshot()                          -- (an undo step: the settings, the edits packed into them)
  M.pack(self.land, self.s)
  self.undo[#self.undo + 1] = M.copy(self.s)
  if #self.undo > 100 then table.remove(self.undo, 1) end
  self.redo = {}
end
function LView:edit(fn, held)                      -- fn(settings) changes a copy; held: a slider still dragged (one undo step)
  if not held or not self.holding then self:snapshot() end
  self.holding = held
  M.pack(self.land, self.s)
  local d = M.copy(self.s)
  fn(d)
  self.s = M.check(d)
  self.dirty = true
  self:make(self.land)
end
function LView:undo_step(back)
  local from, to = back and self.undo or self.redo, back and self.redo or self.undo
  if #from == 0 then return end
  M.pack(self.land, self.s)
  to[#to + 1] = M.copy(self.s)
  self.s = M.check(table.remove(from))
  self.dirty = true
  self:make()
end
function LView:use_sample(name)
  local t = read(P.dir .. "/samples/" .. name .. ".land") or read(P.dir .. "/templates/landscape.land")
  if t then
    self:snapshot()
    self.s = M.check(t)
    self.dirty = true
    self:make()
    self:reset_view()
  end
end
function LView:dab(x, z)                           -- the brush, once, at x, z
  local b, p = self.brush, self.painting
  local t0 = system.get_time()
  local strength = b.strength * ((b.tool == "sculpt" and p and p.lower) and -1 or 1)
  local n = M.brush(self.land, self.s, b.tool, x, z, b.radius, strength, { target = p and p.target })
  self.dab_ms = (system.get_time() - t0) * 1000
  if n > 0 then
    self.dirty = true; core.redraw = true
    if self.fol_items then                         -- (the foliage there: back on the ground; a cell more: a copy in a cell
      local e = b.radius + 1.5 * math.max(self.land.w / (self.land.nx - 1), self.land.d / (self.land.nz - 1))   --  whose corner moved)
      self:grow(x - e, z - e, x + e, z + e)
    end
  end
end
function LView:stroke_begin(x, y, z, lower)      -- a stroke from x, y, z (one undo step): its first dab
  self.holding = false
  self:snapshot()
  self.painting = { x = x, z = z, lower = lower, target = y }
  self:dab(x, z)
end
function LView:stroke_end()
  if not self.painting then return end
  self.painting = nil
  M.pack(self.land, self.s)
  self.edited = M.edited(self.land)
  if self.fol_items then self:grow() end           -- (grown anew: where the slopes and heights changed, its rules again)
end
function LView:save()
  if self.untitled then
    return canvas.save_as("land", function(path) self.filename, self.untitled = path, nil; self:save() end)
  end
  M.pack(self.land, self.s)
  local f = io.open(self.filename, "wb")
  if not f then core.error("can't write %s", self.filename) return end
  f:write("-- a landscape (plugins/landscape): a height field, its base made by rules, edited by hand (runtime/landscape.lua says what each is)\nreturn ", canvas.to_lua(self.s), "\n")
  f:close()
  self.dirty = false
  self:flash("Saved")
end
function LView:update()
  LView.super.update(self)
  local now = system.get_time()
  if now >= (LView.next_check or 0) then
    LView.next_check = now + 0.5
    if P.changed("files") then P.open_with(P.read("files") or {}, LView) end
  end
  if self.show_foliage and not self.untitled and now >= (self.next_fol or 0) then   -- (a .foliage on it saved anew: grown again)
    self.next_fol = now + 2
    local found, old = self:find_foliage(), self.fol or {}
    local same = #found == #old
    for i = 1, #found do if same and (found[i].path ~= old[i].path or canvas.to_lua(found[i].s) ~= canvas.to_lua(old[i].s)) then same = false end end
    if not same then self.fol = found; self:grow() end
  end
  if self.fol_items then core.redraw = true end    -- (the wind: a picture every frame)
end

-- the panels --------------------------------------------------------------
function LView:rects()
  local x, y, w, h = self.position.x, self.position.y, self.size.x, self.size.y
  local lw = math.floor(math.min(S(190), w * 0.24))
  local rw = math.floor(math.min(S(280), w * 0.36))
  return { left = { x, y, lw, h }, right = { x + w - rw, y, rw, h }, mid = { x + lw, y, w - lw - rw, h } }
end
function LView:draw_left(r)
  local ui, b = self.left, self.brush
  ui:begin(r[1], r[2], r[3], r[4], { divider_right = true })
  ui:head("Brush")
  for i = 1, #TOOLS, 2 do
    local row = {}
    for k = i, math.min(i + 1, #TOOLS) do
      local T = TOOLS[k]
      row[#row + 1] = { T[2], function() b.tool = T[1]; core.redraw = true end, accent = b.tool == T[1] }
    end
    ui:buttons(row)
  end
  for _, T in ipairs(TOOLS) do if T[1] == b.tool then ui:text(T[3], style.dim) end end
  ui:slider("Radius", b.radius, 0.5, math.max(40, math.max(self.s.w, self.s.d) / 3), function(v) b.radius = v end, { fmt = "%.1f m", step = 0.1, def = 6 })
  ui:slider("Strength", b.strength, 0.02, 1, function(v) b.strength = v end, { fmt = "%.2f", step = 0.01, def = 0.5 })
  ui:text("LMB: paint", style.dim)
  ui:text("RMB: turn   MMB: pan", style.dim)
  ui:text("wheel: zoom", style.dim)
  ui:space()
  ui:head("Foliage on it")
  local fol = self.fol or {}
  if #fol == 0 then ui:text(self.untitled and "(saved first: then the .foliage" or "(none: a .foliage with", style.dim); ui:text(self.untitled and "files on it show here)" or "ground = \"" .. base_of(self.filename) .. "\")", style.dim)
  else
    for _, f in ipairs(fol) do ui:label(base_of(f.path), tostring(f.info and f.info.count or 0)) end
    ui:check("Show it", self.show_foliage, function() self.show_foliage = not self.show_foliage; self:grow(); core.redraw = true end)
  end
  ui:buttons({ { "Look again", function() self.fol = nil; self:grow(); core.redraw = true end } })
  ui:space()
  ui:head("Start from")
  ui:buttons({ { "Flat", function() self:use_sample("flat") end }, { "Hills", function() self:use_sample("hills") end } })
  ui:buttons({ { "Peaks", function() self:use_sample("peaks") end }, { "Dunes", function() self:use_sample("dunes") end } })
  ui:space()
  ui:buttons({ { self.dirty and "Save  CTRL+S" or "Saved", function() self:save() end, accent = self.dirty } })
  local L = self.land
  ui:label("Grid", string.format("%d x %d", L.nx, L.nz))
  ui:label("Edited", string.format("%d points", self.edited or 0))
  ui:label("Built in", string.format("%.0f ms", self.ms or 0))
  if self.dab_ms then ui:label("A dab", string.format("%.1f ms", self.dab_ms)) end
  if (self.edited or 0) > 0 then ui:buttons({ { "Clear the edits", function() self:edit(function(t) t.edits = nil end) end } }) end
  ui:text("In a game: landscape3d = { \"" .. (self.untitled and "x.land" or base_of(self.filename)) .. "\" }", style.dim)
  ui:finish()
end
local function to255(c) return { math.floor(c[1] + 0.5), math.floor(c[2] + 0.5), math.floor(c[3] + 0.5) } end
function LView:draw_right(r)
  local ui, s = self.right, self.s
  ui:begin(r[1], r[2], r[3], r[4])
  local done = function() self.holding = false end
  local function num(label, get, set, lo, hi, o)
    o = o or {}
    o.done = done
    ui:slider(label, get, lo, hi, function(v) self:edit(function(t) set(t, o.int and math.floor(v + 0.5) or v) end, true) end, o)
  end
  ui:head("Area")
  num("Width", s.w, function(t, v) t.w = v end, 4, 2048, { fmt = "%.0f m", step = 1, def = 64 })
  num("Depth", s.d, function(t, v) t.d = v end, 4, 2048, { fmt = "%.0f m", step = 1, def = 64 })
  num("Cells", s.cells, function(t, v) t.cells = v end, 8, M.MAX_CELLS, { fmt = "%d", int = true, step = 1, def = 64 })
  ui:text(string.format("A point every %.2f m", math.max(s.w, s.d) / s.cells), style.dim)
  local B = s.base
  ui:head("Generator")
  ui:buttons({ { "Flat", function() self:edit(function(t) t.base.kind = "flat" end) end, accent = B.kind == "flat" },
               { "Hills", function() self:edit(function(t) t.base.kind = "hills" end) end, accent = B.kind == "hills" } })
  if B.kind == "hills" then
    num("Seed", B.seed, function(t, v) t.base.seed = v end, 0, 9999, { fmt = "%d", int = true, step = 1, def = 1 })
    ui:buttons({ { "New seed", function() self:edit(function(t) t.base.seed = (t.base.seed * 7 + 13) % 9973 end) end } })
    num("Height", B.height, function(t, v) t.base.height = v end, 0, 200, { fmt = "%.1f m", step = 0.1, def = 8 })
    num("Hills' size", B.scale, function(t, v) t.base.scale = v end, 1, 1000, { fmt = "%.0f m", step = 1, def = 24 })
    num("Detail", B.octaves, function(t, v) t.base.octaves = v end, 1, 8, { fmt = "%d", int = true, step = 1, def = 4 })
    num("Ridges", B.ridges, function(t, v) t.base.ridges = v end, 0, 1, { fmt = "%.2f", step = 0.01, def = 0 })
    num("Sea level", B.sea, function(t, v) t.base.sea = v end, 0, 0.95, { fmt = "%.2f", step = 0.01, def = 0 })
  end
  local C = s.colors
  ui:head("Colours")
  for _, k in ipairs({ { "low", "Low" }, { "high", "High" }, { "rock", "Rock" }, { "snow", "Snow" } }) do
    ui:color(k[2], to255(C[k[1]]), function(c) self:edit(function(t) t.colors[k[1]] = { c[1], c[2], c[3] } end, true) end, { done = done })
  end
  num("Rock from", C.rock_slope, function(t, v) t.colors.rock_slope = v end, 0, 1, { fmt = "%.2f steep", step = 0.01, def = 0.55 })
  num("Snow above", C.snow_at, function(t, v) t.colors.snow_at = v end, 0, 1, { fmt = "%.2f", step = 0.01, def = 1 })
  ui:text("(of the highest point; 1: no snow)", style.dim)
  ui:finish()
end
function LView:draw_ring()                         -- where the brush is: a ring of dots on the ground
  local h = self.hover
  if not h then return end
  local lower = self.brush.tool == "sculpt" and keymap.modkeys["shift"]
  local c = lower and { 255, 140, 110, 255 } or { 255, 255, 255, 255 }
  local r, d = self.brush.radius, S(2)
  for i = 0, 63 do
    local a = i / 64 * math.pi * 2
    local px, pz = h[1] + math.cos(a) * r, h[3] + math.sin(a) * r
    local sx, sy = self:project({ px, M.height_at(self.land, px, pz) + 0.05, pz })
    if sx then renderer.draw_rect(sx - d / 2, sy - d / 2, d, d, c) end
  end
  local cx, cy = self:project(h)
  if cx then renderer.draw_rect(cx - d, cy - d, d * 2, d * 2, c) end
end
function LView:draw()
  self:draw_background(style.background)
  local r = self:rects()
  local m = r.mid
  local px, py, sw, sh = self.position.x, self.position.y, self.size.x, self.size.y
  core.push_clip_rect(px, py, sw, sh)
  if rawget(_G, "host_view3d") and m[3] > 2 and m[4] > 2 then
    renderer.clear_rect(m[1], m[2], m[3], m[4])    -- (the hole: the host's 3D shows through)
    shown.now[self.key] = true
    local top = math.max(self.land.top or 1, 1)
    host_view3d { key = self.key, x = m[1], y = m[2], w = m[3], h = m[4], eye = self:eye(), at = self:target(), fov = FOV,
                  far = math.max(self.s.w, self.s.d) * 6 + top * 4, near = 0.05,
                  clear = { 160, 196, 232, 255 }, ambient = { 105, 110, 120 }, sun = { dir = { -0.5, -0.8, -0.3 }, color = { 255, 244, 222 } },
                  shadows = true, ground = false, land = self.land, foliage = self.fol_items, time = self.fol_items and system.get_time() or 0 }   -- (the time: the wind in its grass)
    self:draw_ring()
  end
  renderer.draw_text(style.font, self:get_name() .. (self.err and ("   can't read: " .. self.err) or "") .. (rawget(_G, "host_view3d") and "" or "   (no 3D here: the host draws it)"),
                     m[1] + S(12), m[2] + S(10), self.err and (style.error or style.text) or { 30, 40, 55, 255 })
  self:draw_left(r.left)
  self:draw_right(r.right)
  if self.note then self.note:draw(nil, nil, { x = px, y = py, w = sw, h = sh }) end
  core.pop_clip_rect()
end

function LView:on_mouse_pressed(button, x, y, clicks)
  if self.left:pressed(button, x, y, clicks) or self.right:pressed(button, x, y, clicks) then return true end
  if button == "left" and clicks == 2 then self:reset_view() return true end
  if button == "left" then                         -- (the brush: a stroke, one undo step)
    local gx, gy, gz = self:ground_at(x, y)
    if gx then self:stroke_begin(gx, gy, gz, keymap.modkeys["shift"]) end
    return true
  end
  if button == "right" then self.turning = { x, y } return true end
  if button == "middle" then self.panning = true return true end
  return LView.super.on_mouse_pressed(self, button, x, y, clicks)
end
function LView:on_mouse_moved(x, y, dx, dy)
  if self.left:moved(x, y) or self.right:moved(x, y) then return end
  if self.turning then
    self.yaw = self.yaw - dx * 0.008
    self.pitch = math.max(0.05, math.min(1.5, self.pitch + dy * 0.006))
    core.redraw = true
    return
  end
  if self.panning then                             -- (the point looked at, across the ground)
    local _, f, r = self:frame3d()
    local k = self:distance() * 0.0015
    local fl = unit({ f[1], 0, f[3] })
    local a = self:target()
    self.at = { a[1] - r[1] * dx * k + fl[1] * dy * k, a[2], a[3] - r[3] * dx * k + fl[3] * dy * k }
    core.redraw = true
    return
  end
  local gx, gy, gz = self:ground_at(x, y)
  self.hover = gx and { gx, gy, gz } or nil
  core.redraw = true
  local p = self.painting
  if p and gx then                                 -- (a dab each so far along: a fifth of the radius)
    local ddx, ddz = gx - p.x, gz - p.z
    if ddx * ddx + ddz * ddz >= math.max(0.05, self.brush.radius * 0.2) ^ 2 then
      p.x, p.z = gx, gz
      self:dab(gx, gz)
    end
  end
end
function LView:on_mouse_released(button, x, y)
  if self.left:released(button) or self.right:released(button) then return end
  if button == "left" and self.painting then self:stroke_end() return end
  if button == "right" and self.turning then self.turning = nil return end
  if button == "middle" and self.panning then self.panning = nil return end
  LView.super.on_mouse_released(self, button, x, y)
end
function LView:on_mouse_wheel(dy, dx)
  if self.right:wheel(dy) or self.left:wheel(dy) then return true end
  self.dist = math.max(1, math.min(20000, self:distance() * (dy > 0 and 0.88 or 1 / 0.88)))
  core.redraw = true
  return true
end
function LView:menu_items()
  local DIV = require("plugins.contextmenu").DIVIDER
  local items = {
    { text = "Save", info = "CTRL+S", command = function() self:save() end },
    { text = "New seed", command = function() self:edit(function(t) t.base.seed = (t.base.seed * 7 + 13) % 9973 end) end },
    DIV,
  }
  for _, T in ipairs(TOOLS) do items[#items + 1] = { text = "Brush: " .. T[2], command = function() self.brush.tool = T[1]; core.redraw = true end } end
  items[#items + 1] = DIV
  items[#items + 1] = { text = "Undo", info = "CTRL+Z", command = function() self:undo_step(true) end }
  items[#items + 1] = { text = "Redo", info = "CTRL+Y", command = function() self:undo_step(false) end }
  items[#items + 1] = { text = "Reset the view", info = "dbl-click", command = function() self:reset_view() end }
  return items
end

command.add(function() return core.active_view and core.active_view:is(LView) end, {
  ["landscape:undo"] = function() core.active_view:undo_step(true) end,
  ["landscape:redo"] = function() core.active_view:undo_step(false) end,
  ["landscape:seed"] = function() local v = core.active_view; v:edit(function(t) t.base.seed = (t.base.seed * 7 + 13) % 9973 end) end,
  ["landscape:sculpt"] = function() core.active_view.brush.tool = "sculpt"; core.redraw = true end,
  ["landscape:smooth"] = function() core.active_view.brush.tool = "smooth"; core.redraw = true end,
  ["landscape:flatten"] = function() core.active_view.brush.tool = "flatten"; core.redraw = true end,
  ["landscape:erase"] = function() core.active_view.brush.tool = "erase"; core.redraw = true end,
})
if not package.loaded["landscape.keys"] then
  package.loaded["landscape.keys"] = true
  keymap.add { ["ctrl+z"] = "landscape:undo", ["ctrl+y"] = "landscape:redo" }
end

P.open_with(P.read("files") or {}, LView)
P.commands = { { "New seed", "landscape:seed" }, { "Sculpt", "landscape:sculpt" }, { "Smooth", "landscape:smooth" },
               { "Flatten", "landscape:flatten" }, { "Erase", "landscape:erase" }, { "Undo", "landscape:undo" }, { "Redo", "landscape:redo" }, { "Save", "canvas:save" } }
P.tab = function() return LView({}) end            -- (the main menu's <category> > <plugin> > New: untitled)
LView.M = M                                        -- (tests)
return LView
