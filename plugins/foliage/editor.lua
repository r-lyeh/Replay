-- editor.lua - the foliage editor: .foliage files (runs in Lite). What's scattered over an area, a layer
-- a kind of thing (grass, flowers, bushes, rocks, trees: a mesh each), seen from above in the middle as
-- it falls: in 3D (each copy drawn by the GPU, instanced: the wind in the grass; LMB drag turns round it,
-- the wheel nearer / further, double-click: back to the start), or from above (a dot a copy, its footprint;
-- MMB pans, CTRL+wheel zooms, double-click fits).
-- The brush (left, under 3D / Above) paints on the picked layer: Copies puts copies by hand (its points: up to
-- so many a m², each turned at random or along the stroke), Density paints where the scatter grows (its
-- mask). LMB paints, SHIFT+LMB erases, RMB turns the 3D view round; a stroke is one undo step.
-- Left: the layers (a click picks one; add, remove, move up / down), kinds to start from, Save. Right:
-- the area (its size, its seed: New seed) and the picked layer's settings, as sliders: the scatter
-- changes as they move. In a game: a node's foliage3d = { "meadow.foliage" } under a camera3d
-- (games/meadow3d.lua); the GPU draws each layer's copies instanced.
--
-- The scatter is runtime/foliage.lua's (no Lite there: the renderer and games make the same one).
local P = ...
P.title = "Foliage editor"                         -- (its name in menus: Open with, the main menu's Plugins)
P.category = "Levels"                              -- (the main menu: Levels >)
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local canvas = require "plugins.canvas"
local F = dofile((rawget(_G, "REPLAY_ROOT") or (DATADIR .. "/../../..")) .. "/runtime/foliage.lua")
local LS = dofile((rawget(_G, "REPLAY_ROOT") or (DATADIR .. "/../../..")) .. "/runtime/landscape.lua")

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
-- a landscape's file by its asset name (the settings' ground): beside the .foliage, else the game's assets/, common/
local function find_asset(name, near)
  name = tostring(name):gsub("^/assets/", ""):gsub("^/", "")
  if not name:find("%.%w+$") then name = name .. ".land" end
  local dirs = {}
  if near and near ~= "" then dirs[#dirs + 1] = (near:gsub("\\", "/"):match("^(.*)/") or ".") end
  local root = rawget(_G, "replay_open_dir") and replay_open_dir() or nil
  if root and root ~= "" then root = root:gsub("\\", "/"):gsub("/$", ""); dirs[#dirs + 1] = root .. "/assets"; dirs[#dirs + 1] = root .. "/common"; dirs[#dirs + 1] = root end
  dirs[#dirs + 1] = "games/common"
  for _, d in ipairs(dirs) do
    local p = d .. "/" .. name
    local f = io.open(p, "rb")
    if f then local text = f:read("*a"); f:close(); return p, text end
  end
end
local KINDS = {                                    -- (layers to add: a kind each, its look)
  { "Grass", { name = "grass", mesh = "grass", size = { 0.35, 0.45, 0.35 }, density = 6, scale = { 0.6, 1.4 }, tilt = 10, color = { 96, 168, 72 }, shade = 0.3, cluster = 0.35, clump = 3, wind = 0.25, fade = 20 } },
  { "Flowers", { name = "flowers", mesh = "sphere", size = { 0.09, 0.09, 0.09 }, density = 0.5, sink = -0.35, color = { 240, 210, 80 }, shade = 0.15, cluster = 0.55, clump = 2.5 } },
  { "Bushes", { name = "bushes", mesh = "bush", variants = 3, size = { 1.1, 0.8, 1.1 }, density = 0.05, sink = 0.05, color = { 220, 235, 215 }, shade = 0.2, cluster = 0, spacing = 1.5, wind = 0.08 } },
  { "Rocks", { name = "rocks", mesh = "cube", size = { 0.5, 0.35, 0.45 }, density = 0.03, scale = { 0.5, 1.6 }, tilt = 25, sink = 0.1, color = { 140, 136, 128 }, shade = 0.2, cluster = 0, spacing = 2 } },
  { "Trees", { name = "trees", mesh = "tree", variants = 4, size = { 4.5, 6, 4.5 }, density = 0.01, scale = { 0.7, 1.3 }, tilt = 4, color = { 240, 240, 225 }, shade = 0.15, cluster = 0.4, clump = 8, spacing = 4, wind = 0.04 } },
  { "Pines", { name = "pines", mesh = "pine", variants = 3, size = { 3, 7, 3 }, density = 0.015, scale = { 0.7, 1.4 }, tilt = 3, color = { 235, 240, 235 }, shade = 0.15, cluster = 0.5, clump = 9, spacing = 2.5, wind = 0.03 } },
}

-- the 3D views drawn in a frame of Lite's: the others (a tab behind another, closed, back to "Above") are
-- taken away from the host's list, so their pictures don't stay (as plugins/modelview's)
local shown = package.loaded["foliage.shown"]
if not shown then
  shown = { now = {}, last = {} }
  package.loaded["foliage.shown"] = shown
  local begin_frame, end_frame = renderer.begin_frame, renderer.end_frame
  renderer.begin_frame = function(...) shown.now = {}; return begin_frame(...) end
  renderer.end_frame = function(...)
    for key in pairs(shown.last) do if not shown.now[key] and host_view3d then host_view3d { key = key, remove = true } end end
    shown.last = shown.now
    return end_frame(...)
  end
end
local next_id = 0

local FView = canvas.View:extend()
FView.grid = 1
FView.zoom_min, FView.zoom_max = 1, 400

function FView:new(state)
  FView.super.new(self)
  self.filename = state and state.filename or ""
  self.untitled = state and state.untitled or self.filename == ""
  self.left, self.right = canvas.ui.new(), canvas.ui.new()
  self.undo, self.redo = {}, {}
  self.sel = 1
  self.brush = { mode = nil, radius = 2, strength = 0.5, density = 0.3, along = false }   -- (mode: "copies", "density")
  next_id = next_id + 1
  self.key = "foliage" .. next_id
  self.in3d = rawget(_G, "host_view3d") ~= nil      -- (3D first, when the host draws it)
  self:reset_view()
  local t, err = read(self.untitled and (P.dir .. "/templates/foliage.foliage") or self.filename)
  self.err = not t and err or nil
  self.s = F.check(t)
  self:make()
  if state and state.cam then self:set_camera(state.cam) else self.want_fit = true end
end
function FView:try_close(do_close)
  if host_view3d then host_view3d { key = self.key, remove = true } end
  return FView.super.try_close(self, do_close)
end
function FView:get_name() return (self.untitled and "untitled.foliage" or base_of(self.filename)) .. (self.dirty and "*" or "") end
function FView:get_state() return { filename = self.filename, untitled = self.untitled, cam = self:camera_state() } end
function FView:bounds() local s = self.s; return -s.w / 2 - 1, -s.d / 2 - 1, s.w + 2, s.d + 2 end

function FView:reset_view() self.yaw, self.pitch, self.dist = 0.6, 0.42, nil; core.redraw = true end
function FView:eye()
  local d = self.dist or math.max(self.s and self.s.w or 20, self.s and self.s.d or 20) * 0.75
  local cp = math.cos(self.pitch)
  local a = self:at3d()
  return { a[1] + math.sin(self.yaw) * cp * d, a[2] + math.sin(self.pitch) * d, a[3] + math.cos(self.yaw) * cp * d }
end
function FView:windy() for _, L in ipairs(self.s.layers) do if L.wind > 0 then return true end end end
local FOV = 50                                     -- (the 3D view's: draw_3d)
function FView:at3d() return { 0, 0.2 + (self.land and self.land.top * 0.3 or 0), 0 } end   -- (looked at: on a landscape, a third of its height up)
local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function unit(a) local l = math.sqrt(dot(a, a)); return l > 1e-9 and { a[1] / l, a[2] / l, a[3] / l } or a end
local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
function FView:frame3d()                           -- the 3D view's camera: eye, forward, right, up, tan(fov / 2), aspect, its rect
  local m = self:rects().mid
  local eye = self:eye()
  local f = unit(sub(self:at3d(), eye))
  local r = unit(cross(f, { 0, 1, 0 }))
  return eye, f, r, cross(r, f), math.tan(math.rad(FOV) / 2), m[3] / math.max(1, m[4]), m
end
function FView:ground_at(x, y)                     -- the point of the area's ground under the mouse (x, z) | nil
  local m = self:rects().mid
  if x < m[1] or y < m[2] or x >= m[1] + m[3] or y >= m[2] + m[4] then return nil end
  if not self.in3d then return self:to_world(x, y) end
  local eye, f, r, u, t, asp = self:frame3d()
  local nx, ny = (x - m[1]) / m[3] * 2 - 1, 1 - (y - m[2]) / m[4] * 2
  local d = { f[1] + (r[1] * nx * asp + u[1] * ny) * t, f[2] + (r[2] * nx * asp + u[2] * ny) * t, f[3] + (r[3] * nx * asp + u[3] * ny) * t }
  if self.land then                                -- (on a landscape: where the ray meets it)
    local t, hx, _, hz = LS.ray(self.land, eye[1], eye[2] - self.s.y, eye[3], d[1], d[2], d[3], 1e5)
    if t then return hx, hz end
    return nil
  end
  if d[2] > -1e-4 then return nil end              -- (the sky)
  local k = (self.s.y - eye[2]) / d[2]
  return eye[1] + d[1] * k, eye[3] + d[3] * k
end
function FView:project(p)                          -- a point of the world -> the 3D view's pixel | nil (behind)
  local eye, f, r, u, t, asp, m = self:frame3d()
  local rel = sub(p, eye)
  local z = dot(rel, f)
  if z < 0.05 then return nil end
  return m[1] + (1 + dot(rel, r) / (z * t * asp)) * m[3] / 2, m[2] + (1 - dot(rel, u) / (z * t)) * m[4] / 2
end
function FView:dab(x, z, yaw)                      -- the brush, once, at x, z (the picked layer)
  local b, k, erase = self.brush, self.sel, self.painting and self.painting.erase
  self:edit(function(t)
    local L = t.layers[k]
    if not L then return end
    if b.mode == "density" then F.paint_mask(L, t, x, z, b.radius, (erase and -1 or 1) * b.strength)
    elseif erase then F.erase_points(L, x, z, b.radius, b.strength)
    else F.paint_points(L, t, x, z, b.radius, { density = b.density, strength = b.strength, yaw = b.along and yaw or nil }) end
  end, true)
end
function FView:draw_ring()                         -- where the brush is: a ring of dots on the ground
  local h = self.brush.mode and self.hover
  if not h then return end
  local erase = keymap.modkeys["shift"]
  local c = erase and { 255, 120, 110, 255 } or { 255, 255, 255, 255 }
  local r, d = self.brush.radius, S(2)
  for i = 0, 47 do
    local a = i / 48 * math.pi * 2
    local px, pz = h[1] + math.cos(a) * r, h[2] + math.sin(a) * r
    local sx, sy
    if self.in3d then sx, sy = self:project({ px, self.s.y + (self.land and LS.height_at(self.land, px, pz) + 0.05 or 0), pz }) else sx, sy = self:to_screen(px, pz) end
    if sx then renderer.draw_rect(sx - d / 2, sy - d / 2, d, d, c) end
  end
end
function FView:ground_land()                       -- the settings' ground: a landscape, built (again when its file changes) | nil
  local g = self.s.ground
  if not g then self.land, self.land_src = nil, nil return nil end
  if type(g) == "table" then
    if self.land_src ~= g then self.land, self.land_src = LS.build(LS.check(g)), g end
    return self.land
  end
  local path, text = find_asset(g, not self.untitled and self.filename or nil)
  if not path then self.land, self.land_src, self.land_err = nil, nil, "can't find " .. g return nil end
  self.land_err = nil
  if self.land_src ~= text then
    local fn = load(text, "=" .. path, "t", {})
    local ok, t = pcall(fn or error)
    self.land = ok and type(t) == "table" and LS.build(LS.check(t)) or nil
    self.land_src, self.land_path = text, path
  end
  return self.land
end
function FView:make()                              -- the scatter again (each change: the same seed, the same one)
  local t0 = system.get_time()
  self.items, self.info = F.generate(self.s, self:ground_land())
  self.ms = (system.get_time() - t0) * 1000
  core.redraw = true
end
function FView:edit(fn, held)                      -- fn(settings) changes a copy; held: a slider still dragged (one undo step)
  if not held or not self.holding then
    self.undo[#self.undo + 1] = F.copy(self.s)
    if #self.undo > 200 then table.remove(self.undo, 1) end
    self.redo = {}
  end
  self.holding = held
  local d = F.copy(self.s)
  fn(d)
  self.s = F.check(d)
  self.sel = math.max(1, math.min(self.sel, #self.s.layers))
  self.dirty = true
  self:make()
end
function FView:undo_step(back)
  local from, to = back and self.undo or self.redo, back and self.redo or self.undo
  if #from == 0 then return end
  to[#to + 1] = F.copy(self.s)
  self.s = F.check(table.remove(from))
  self.sel = math.max(1, math.min(self.sel, #self.s.layers))
  self.dirty = true
  self:make()
end
function FView:use_sample(name)
  local t = read(P.dir .. "/samples/" .. name .. ".foliage")
  if t then self:edit(function(d) for k in pairs(d) do d[k] = nil end for k, v in pairs(t) do d[k] = v end end); self.sel = 1; self.want_fit = true end
end
function FView:save()
  if self.untitled then
    return canvas.save_as("foliage", function(path) self.filename, self.untitled = path, nil; self:save() end)
  end
  local f = io.open(self.filename, "wb")
  if not f then core.error("can't write %s", self.filename) return end
  f:write("-- foliage (plugins/foliage): what's scattered over an area, a layer a kind (runtime/foliage.lua says what each is)\nreturn ", canvas.to_lua(self.s), "\n")
  f:close()
  self.dirty = false
  self:flash("Saved")
end
function FView:update()
  FView.super.update(self)
  if self.want_fit and self.size.x > 0 then self.want_fit = false; self:fit() end
  if self.in3d and self:windy() then core.redraw = true end   -- (the wind: a picture every frame)
  local now = system.get_time()
  if self.s.ground and now >= (self.next_ground or 0) then   -- (its landscape saved anew (the landscape editor): grown on it again)
    self.next_ground = now + 1
    local before = self.land
    if self:ground_land() ~= before then self:make() end
  end
  if now >= (FView.next_check or 0) then
    FView.next_check = now + 0.5
    if P.changed("files") then P.open_with(P.read("files") or {}, FView) end
  end
end

-- the panels --------------------------------------------------------------
function FView:rects()
  local x, y, w, h = self.position.x, self.position.y, self.size.x, self.size.y
  local lw = math.floor(math.min(S(190), w * 0.24))
  local rw = math.floor(math.min(S(300), w * 0.38))
  return { left = { x, y, lw, h }, right = { x + w - rw, y, rw, h }, mid = { x + lw, y, w - lw - rw, h } }
end
function FView:fit()
  local r = self:rects().mid
  local s = self.s
  local z = math.min(r[3] / (s.w + 2), r[4] / (s.d + 2)) / SCALE
  self.cam.zoom = math.max(self.zoom_min, math.min(self.zoom_max, z))
  self.cam.x = r[1] - self.position.x + r[3] / 2
  self.cam.y = r[2] - self.position.y + r[4] / 2
  core.redraw = true
end
local function to255(c) return { math.floor(c[1] + 0.5), math.floor(c[2] + 0.5), math.floor(c[3] + 0.5) } end
function FView:draw_left(r)
  local ui = self.left
  ui:begin(r[1], r[2], r[3], r[4], { divider_right = true })
  if rawget(_G, "host_view3d") then
    ui:buttons({ { "3D", function() self.in3d = true; core.redraw = true end, accent = self.in3d },
                 { "Above", function() self.in3d = false; self.want_fit = true; core.redraw = true end, accent = not self.in3d } })
  end
  local b = self.brush
  ui:head("Brush")
  ui:buttons({ { "Off", function() b.mode = nil; core.redraw = true end, accent = not b.mode },
               { "Copies", function() b.mode = "copies"; core.redraw = true end, accent = b.mode == "copies" },
               { "Density", function() b.mode = "density"; core.redraw = true end, accent = b.mode == "density" } })
  if b.mode then
    ui:slider("Radius", b.radius, 0.2, 30, function(v) b.radius = v end, { fmt = "%.1f m", step = 0.1, def = 2 })
    ui:slider("Strength", b.strength, 0.05, 1, function(v) b.strength = v end, { fmt = "%.2f", step = 0.01, def = 0.5 })
    local L, k = self.s.layers[self.sel], self.sel
    if b.mode == "copies" then
      ui:slider("A m²", b.density, 0.01, 10, function(v) b.density = v end, { fmt = "%.2f", step = 0.01, def = 0.3 })
      ui:check("Along the stroke", b.along, function() b.along = not b.along end)
      if L and L.points and #L.points > 0 then
        ui:buttons({ { "Clear " .. #L.points .. " put", function() self:edit(function(t) t.layers[k].points = nil end) end } })
      end
    elseif L then
      ui:buttons({ { "Everywhere", function() self:edit(function(t) t.layers[k].mask = nil end) end, accent = not L.mask },
                   { "Nowhere", function() self:edit(function(t) local m = {}; for i = 1, F.MASK do m[i] = string.rep("0", F.MASK) end; t.layers[k].mask = m end) end } })
    end
    ui:label("On", L and L.name or "-")
    ui:text("LMB: paint", style.dim)
    ui:text("SHIFT+LMB: erase", style.dim)
    if self.in3d then ui:text("RMB: turn round", style.dim) end
  end
  ui:space()
  ui:head("Layers")
  for i, L in ipairs(self.s.layers) do
    local n = self.info and self.info.per[i] or 0
    ui:buttons({ { string.format("%s  %d", L.name, n), function() self.sel = i; core.redraw = true end, accent = i == self.sel } })
  end
  local nl = #self.s.layers
  ui:buttons({ { "Up", function() if self.sel > 1 then local k = self.sel; self:edit(function(d) d.layers[k], d.layers[k - 1] = d.layers[k - 1], d.layers[k] end); self.sel = k - 1 end end },
               { "Down", function() if self.sel < nl then local k = self.sel; self:edit(function(d) d.layers[k], d.layers[k + 1] = d.layers[k + 1], d.layers[k] end); self.sel = k + 1 end end },
               { "Remove", function() if nl > 1 then local k = self.sel; self:edit(function(d) table.remove(d.layers, k) end) end end } })
  ui:space()
  ui:head("Add a layer")
  for _, k in ipairs(KINDS) do
    ui:buttons({ { k[1], function() self:edit(function(d) d.layers[#d.layers + 1] = F.copy(k[2]) end); self.sel = #self.s.layers end } })
  end
  ui:space()
  ui:head("Start from")
  ui:buttons({ { "Meadow", function() self:use_sample("meadow") end }, { "Forest", function() self:use_sample("forest") end }, { "Rocks", function() self:use_sample("rocks") end } })
  ui:space()
  ui:buttons({ { self.dirty and "Save  CTRL+S" or "Saved", function() self:save() end, accent = self.dirty } })
  ui:label("Copies", tostring(self.info and self.info.count or 0))
  ui:label("Made in", string.format("%.0f ms", self.ms or 0))
  ui:text("In a game: foliage3d = { \"" .. (self.untitled and "x" or base_of(self.filename)) .. "\" }", style.dim)
  ui:finish()
end
function FView:draw_right(r)
  local ui, s = self.right, self.s
  ui:begin(r[1], r[2], r[3], r[4])
  local done = function() self.holding = false end
  ui:head("Area")
  ui:slider("Width", s.w, 1, 200, function(v) self:edit(function(t) t.w = v end, true) end, { fmt = "%.1f m", step = 0.5, def = 20, done = done })
  ui:slider("Depth", s.d, 1, 200, function(v) self:edit(function(t) t.d = v end, true) end, { fmt = "%.1f m", step = 0.5, def = 20, done = done })
  ui:slider("Height", s.y, -10, 10, function(v) self:edit(function(t) t.y = v end, true) end, { fmt = "%.2f m", step = 0.05, def = 0, done = done })
  ui:slider("Seed", s.seed, 0, 9999, function(v) self:edit(function(t) t.seed = math.floor(v + 0.5) end, true) end, { fmt = "%d", int = true, step = 1, def = 1, done = done })
  ui:buttons({ { "New seed", function() self:edit(function(t) t.seed = (t.seed * 7 + 13) % 9973 end) end } })
  ui:head("Ground")                                -- (flat, or a landscape: each copy on it, its layers' rules)
  ui:buttons({ { "Flat", function() self:edit(function(t) t.ground = nil end) end, accent = not s.ground },
               { "A landscape...", function()
                   require("plugins.projectplugins").pick_file("A landscape", { "land" }, function(path)
                     local name = path:gsub("\\", "/"):match("[^/]*$")
                     self:edit(function(t) t.ground = name end)
                   end)
                 end, accent = s.ground ~= nil } })
  if s.ground then
    ui:label("On", type(s.ground) == "string" and s.ground or "(its own)")
    if self.land_err then ui:text(self.land_err, style.error or style.text)
    elseif self.land then ui:text(string.format("%d x %d m, up to %.1f m", self.land.w, self.land.d, self.land.top), style.dim) end
    if self.land then ui:buttons({ { "Its size", function() local L = self.land; self:edit(function(t) t.w, t.d = L.w, L.d end) end } }) end
  end
  local L = s.layers[self.sel]
  if L then
    local k = self.sel
    local function num(label, key, lo, hi, o)
      o = o or {}
      o.done, o.def = done, o.def == nil and F.LAYER[key] or o.def
      ui:slider(label, L[key], lo, hi, function(v) self:edit(function(t) t.layers[k][key] = o.int and math.floor(v + 0.5) or v end, true) end, o)
    end
    local function pair(label, key, i, lo, hi, o)
      o = o or {}
      o.done, o.def = done, F.LAYER[key][i]
      ui:slider(label, L[key][i], lo, hi, function(v) self:edit(function(t) t.layers[k][key][i] = v end, true) end, o)
    end
    ui:head("Layer: " .. L.name)
    ui:field("Name", L.name, function(v) if v ~= "" then self:edit(function(t) t.layers[k].name = v end) end end)
    ui:field("Mesh", L.mesh, function(v) if v ~= "" then self:edit(function(t) t.layers[k].mesh = v end) end end)
    local function mesh(name) return { name:sub(1, 1):upper() .. name:sub(2), function() self:edit(function(t) t.layers[k].mesh = name end) end, accent = L.mesh == name } end
    ui:buttons({ mesh("grass"), mesh("tree"), mesh("pine"), mesh("bush") })
    ui:buttons({ { "Cube", function() self:edit(function(t) t.layers[k].mesh = "cube" end) end },
                 { "Sphere", function() self:edit(function(t) t.layers[k].mesh = "sphere" end) end },
                 { "A model...", function()
                     require("plugins.projectplugins").pick_file("A model", { "glb", "gltf", "fbx", "vox" }, function(path)
                       local root = (rawget(_G, "replay_open_dir") and replay_open_dir() or ""):gsub("\\", "/")
                       local rel = path:gsub("\\", "/")
                       if root ~= "" and rel:sub(1, #root) == root then rel = rel:sub(#root + 1) end
                       rel = rel:gsub("^assets/", "/assets/"):gsub("^common/", "/assets/")
                       if not rel:find("^/") then rel = "file:" .. path:gsub("\\", "/") end
                       self:edit(function(t) t.layers[k].mesh = rel end)
                     end)
                   end } })
    if F.PLANTS[L.mesh] then num("Variants", "variants", 1, 8, { fmt = "%d", int = true, step = 1 }) end
    pair("Width", "size", 1, 0.01, 20, { fmt = "%.2f m", step = 0.01 })
    pair("Height", "size", 2, 0.01, 40, { fmt = "%.2f m", step = 0.01 })
    pair("Depth", "size", 3, 0.01, 10, { fmt = "%.2f m", step = 0.01 })
    num("Density", "density", 0, 20, { fmt = "%.2f a m²", step = 0.01 })
    pair("Smallest", "scale", 1, 0.05, 4, { fmt = "x%.2f", step = 0.05 })
    pair("Biggest", "scale", 2, 0.05, 4, { fmt = "x%.2f", step = 0.05 })
    ui:check("Turned at random", L.yaw, function() self:edit(function(t) t.layers[k].yaw = not t.layers[k].yaw end) end)
    num("Tilt", "tilt", 0, 90, { fmt = "%.0f°", step = 1 })
    num("Sink", "sink", -2, 2, { fmt = "%.2f m", step = 0.01 })
    ui:color("Colour", to255(L.color), function(c) self:edit(function(t) t.layers[k].color = { c[1], c[2], c[3] } end, true) end, { done = done })
    num("Shade", "shade", 0, 1, { fmt = "%.2f", step = 0.01 })
    num("Clumps", "cluster", 0, 1, { fmt = "%.2f", step = 0.01 })
    num("Clump size", "clump", 0.2, 50, { fmt = "%.1f m", step = 0.1 })
    num("Spacing", "spacing", 0, 20, { fmt = "%.2f m", step = 0.05 })
    num("At most", "max", 0, F.MAX, { fmt = "%d", int = true, step = 100 })
    num("Wind", "wind", 0, 1, { fmt = "%.2f", step = 0.01 })
    num("Whole up to", "fade", 0, 200, { fmt = "%.0f m", step = 1 })
    if s.ground then                               -- (on a landscape: how it leans, where it grows)
      num("Leans with it", "align", 0, 1, { fmt = "%.2f", step = 0.01 })
      pair("Slope from", "slope", 1, 0, 90, { fmt = "%.0f°", step = 1 })
      pair("Slope up to", "slope", 2, 0, 90, { fmt = "%.0f°", step = 1 })
      ui:check("Only so high", L.altitude ~= nil, function()
        self:edit(function(t) t.layers[k].altitude = not t.layers[k].altitude and { 0, math.max(1, self.land and self.land.top or 10) } or nil end)
      end)
      if L.altitude then
        ui:slider("From", L.altitude[1], -50, 500, function(v) self:edit(function(t) t.layers[k].altitude[1] = v end, true) end, { fmt = "%.1f m", step = 0.1, def = 0, done = done })
        ui:slider("Up to", L.altitude[2], -50, 500, function(v) self:edit(function(t) t.layers[k].altitude[2] = v end, true) end, { fmt = "%.1f m", step = 0.1, def = 10, done = done })
      end
    end
  end
  ui:finish()
end
function FView:draw_3d(m)                         -- the middle, in 3D: a hole in Lite's picture, the host draws it there
  renderer.clear_rect(m[1], m[2], m[3], m[4])
  shown.now[self.key] = true
  local s = self.s
  host_view3d { key = self.key, x = m[1], y = m[2], w = m[3], h = m[4], eye = self:eye(), at = self:at3d(), fov = 50, land = self.land,
                clear = { 150, 190, 230, 255 }, ambient = { 110, 115, 120 }, sun = { dir = { -0.5, -1, -0.35 }, color = { 255, 246, 225 } },
                shadows = true, ground = not self.land, foliage = self.items, area = { w = s.w, d = s.d }, time = system.get_time() }
end
function FView:draw()
  if not self.in3d then return FView.super.draw(self) end
  self:draw_background(self:draw_background_color())
  local px, py, sw, sh = self.position.x, self.position.y, self.size.x, self.size.y
  core.push_clip_rect(px, py, sw, sh)
  canvas.draw.set_view(px, py, sw, sh)
  self:draw_3d(self:rects().mid)
  self:draw_ring()
  self:draw_overlay()
  if self.note then self.note:draw(nil, nil, { x = px, y = py, w = sw, h = sh }) end
  core.pop_clip_rect()
end
function FView:draw_canvas()
  local z = self:z()
  local s = self.s
  local x0, y0 = self:to_screen(-s.w / 2, -s.d / 2)
  local w, h = s.w * z, s.d * z
  renderer.draw_rect(x0, y0, w, h, { 70, 92, 52, 255 })   -- (the ground)
  local c = { style.dim[1], style.dim[2], style.dim[3], 200 }
  renderer.draw_rect(x0, y0, w, 1, c); renderer.draw_rect(x0, y0 + h, w, 1, c)
  renderer.draw_rect(x0, y0, 1, h, c); renderer.draw_rect(x0 + w, y0, 1, h, c)
  local it = self.items
  if not it then return end
  local cx, cy = self:to_screen(0, 0)
  for li = 1, #s.layers do                         -- (layer by layer, the first under the others; the picked one outlined)
    for i = 1, it.n do
      if it.layer[i] == li then
        local fw, fd = math.max(1, it.sx[i] * z), math.max(1, it.sz[i] * z)
        local px, py = cx + it.x[i] * z - fw / 2, cy + it.z[i] * z - fd / 2
        renderer.draw_rect(px, py, fw, fd, { it.r[i] * 255, it.g[i] * 255, it.b[i] * 255, 255 })
      end
    end
  end
  self:draw_ring()
end
function FView:draw_overlay()
  local r = self:rects()
  renderer.draw_text(style.font, self:get_name() .. (self.err and ("   can't read: " .. self.err) or "") .. (self.brush.mode and ("   (brush: LMB paints, SHIFT+LMB erases" .. (self.in3d and ", RMB turns)" or ")")) or self.in3d and "   (3D: LMB turns, the wheel zooms)" or "   (seen from above)"),
                     r.mid[1] + S(12), r.mid[2] + S(10), self.err and (style.error or style.text) or style.dim)
  self:draw_left(r.left)
  self:draw_right(r.right)
end

function FView:on_mouse_pressed(button, x, y, clicks)
  if self.left:pressed(button, x, y, clicks) or self.right:pressed(button, x, y, clicks) then return true end
  if self.brush.mode and button == "left" then     -- (the brush: a stroke, one undo step)
    local gx, gz = self:ground_at(x, y)
    if gx then
      self.holding = false
      self.painting = { x = gx, z = gz, erase = keymap.modkeys["shift"] }
      self:dab(gx, gz)
    end
    return true
  end
  if self.in3d and self.brush.mode and button == "right" then self.turning = { x, y } return true end
  if self.in3d then
    if clicks == 2 then self:reset_view() return true end
    if button == "left" then self.turning = { x, y } return true end
  end
  if button == "left" and clicks == 2 then self:fit() return true end
  return FView.super.on_mouse_pressed(self, button, x, y, clicks)
end
function FView:on_mouse_moved(x, y, dx, dy)
  if self.left:moved(x, y) or self.right:moved(x, y) then return end
  if self.brush.mode then
    local gx, gz = self:ground_at(x, y)
    self.hover = gx and { gx, gz } or nil
    core.redraw = true
    local p = self.painting
    if p and gx then                               -- (a dab each so far along: a third of the radius)
      local dx, dz = gx - p.x, gz - p.z
      if dx * dx + dz * dz >= math.max(0.1, self.brush.radius * 0.3) ^ 2 then
        p.x, p.z = gx, gz
        self:dab(gx, gz, (math.atan2 or math.atan)(dx, dz))
      end
      return
    end
  end
  if self.turning then                             -- (3D: round it)
    self.yaw = self.yaw - dx * 0.008
    self.pitch = math.max(0.05, math.min(1.5, self.pitch + dy * 0.006))
    core.redraw = true
    return
  end
  FView.super.on_mouse_moved(self, x, y, dx, dy)
end
function FView:on_mouse_released(button, x, y)
  if self.left:released(button) or self.right:released(button) then return end
  if button == "left" and self.painting then self.painting = nil; self.holding = false return end
  if (button == "left" or button == "right") and self.turning then self.turning = nil return end
  FView.super.on_mouse_released(self, button, x, y)
end
function FView:on_mouse_wheel(dy, dx)
  if self.right:wheel(dy) or self.left:wheel(dy) then return true end
  if self.in3d then                                -- (3D: nearer / further)
    local d = self.dist or math.max(self.s.w, self.s.d) * 0.75
    self.dist = math.max(0.5, math.min(500, d * (dy > 0 and 0.88 or 1 / 0.88)))
    core.redraw = true
    return true
  end
  return FView.super.on_mouse_wheel(self, dy, dx)
end
function FView:menu_items()
  local DIV = require("plugins.contextmenu").DIVIDER
  local items = {
    { text = "Save", info = "CTRL+S", command = function() self:save() end },
    { text = "New seed", command = function() self:edit(function(t) t.seed = (t.seed * 7 + 13) % 9973 end) end },
    DIV,
  }
  for _, k in ipairs(KINDS) do items[#items + 1] = { text = "Add: " .. k[1], command = function() self:edit(function(d) d.layers[#d.layers + 1] = F.copy(k[2]) end); self.sel = #self.s.layers end } end
  items[#items + 1] = DIV
  items[#items + 1] = { text = "Undo", info = "CTRL+Z", command = function() self:undo_step(true) end }
  items[#items + 1] = { text = "Redo", info = "CTRL+Y", command = function() self:undo_step(false) end }
  items[#items + 1] = { text = "Fit", info = "dbl-click", command = function() self:fit() end }
  return items
end

command.add(function() return core.active_view and core.active_view:is(FView) end, {
  ["foliage:undo"] = function() core.active_view:undo_step(true) end,
  ["foliage:redo"] = function() core.active_view:undo_step(false) end,
  ["foliage:seed"] = function() local v = core.active_view; v:edit(function(t) t.seed = (t.seed * 7 + 13) % 9973 end) end,
})
if not package.loaded["foliage.keys"] then
  package.loaded["foliage.keys"] = true
  keymap.add { ["ctrl+z"] = "foliage:undo", ["ctrl+y"] = "foliage:redo" }
end

P.open_with(P.read("files") or {}, FView)
P.commands = { { "New seed", "foliage:seed" }, { "Undo", "foliage:undo" }, { "Redo", "foliage:redo" }, { "Save", "canvas:save" } }
P.tab = function() return FView({}) end            -- (the main menu's <category> > <plugin> > New: untitled)
FView.F = F                                        -- (tests)
FView.LS = LS
return FView
