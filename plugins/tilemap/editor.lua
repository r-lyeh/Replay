-- editor.lua - the tilemap editor: .tmap tile maps (runs in lite). The map in
-- the middle (a canvas: MMB or SPACE+drag pans, CTRL+wheel zooms); the tools,
-- the layers and the tileset on the left; the map's size on the right.
--
--   LMB          the tool: Paint (the picked tiles, a stamp), Rect, Fill, Erase,
--                Path (click a start, then a goal: the way between them; runtime/path.lua),
--                Area (drag: a named rectangle; drag one to move it, its corner to
--                size it, a polygon's points), Spline (click points, Enter or a
--                double-click ends it; drag a point to move it)
--   RMB          erases (the tile tools)  ALT+LMB  picks the tile under it
--   B / R / F / E / P / A / C   the tools    CTRL+Z / CTRL+Y  undo / redo
--   Delete       the area / spline picked  Enter / ESC  a spline: done / dropped
--   1..9         the layer                CTRL+S  save
-- SHIFT while placing an area or a spline's point: free (else on the half-cell grid).
-- A .tmx (Tiled) opens here too: read into a map (tmx.lua; what couldn't come
-- along: in the log), saved as a .tmap beside it.
--
-- The tileset: tiles.png, 256 x 256, 16 x 16 tiles (ours, CC0: made by
-- tools/make_tiles.py), or a picture beside the map (`tileset` in the file).
-- map.lua is the model (no lite in it): a game can read a .tmap the same way.
local P = ...
P.title = "Tilemap editor"                         -- (its name in menus: Open with, the main menu's Plugins)
P.category = "Levels"                         -- (the main menu: Levels >)
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local canvas = require "plugins.canvas"
local Map = P.require("map")
local Path = dofile((rawget(_G, "REPLAY_ROOT") or (DATADIR .. "/../../..")) .. "/runtime/path.lua")
local Tmap = dofile((rawget(_G, "REPLAY_ROOT") or (DATADIR .. "/../../..")) .. "/runtime/tmap.lua")   -- (areas, splines: as a game reads them)
local Tmx = P.require("tmx")

local DEFAULTS = { grid = true, w = 32, h = 20 }
local cfg = {}
local function load_config()
  local c = P.read("config")
  cfg = {}
  for k, v in pairs(DEFAULTS) do cfg[k] = v end
  if type(c) == "table" then for k, v in pairs(c) do if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then cfg[k] = v end end end
end

local function S(n) return math.floor(n * SCALE + 0.5) end
local function base_of(f) return (f:match("[^/\\]*$")) end
local function dir_of(f) return f:match("^(.*)[/\\]") or "." end
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
local NAMES = (function()                          -- the plugin's tiles' names (tiles.lua)
  local t = read(P.dir .. "/tiles.lua")
  return type(t) == "table" and type(t.names) == "table" and t.names or {}
end)()

local AUTO = (function()                           -- the plugin's auto-tiles (tiles.lua's auto: { shore = { first = 64 } })
  local t = read(P.dir .. "/tiles.lua")
  return type(t) == "table" and type(t.auto) == "table" and t.auto or Map.AUTO
end)()
local NAMED_ROWS = 0                               -- (the plugin's sheet: only its rows with tiles show)
for i in pairs(NAMES) do NAMED_ROWS = math.max(NAMED_ROWS, math.floor(i / 16) + 1) end
local TOOLS = { "paint", "rect", "fill", "erase", "path", "area", "spline" }
local TOOL_NAMES = { paint = "Paint", rect = "Rect", fill = "Fill", erase = "Erase", path = "Path", area = "Area", spline = "Spline" }
local TOOL_KEYS = { paint = "B", rect = "R", fill = "F", erase = "E", path = "P", area = "A", spline = "C" }

local TileView = canvas.View:extend()
TileView.grid = nil                                -- (the map draws its own)
TileView.zoom_min, TileView.zoom_max = 0.1, 16

function TileView:new(state)
  TileView.super.new(self)
  self.filename = state and state.filename or ""
  self.untitled = state and state.untitled or self.filename == ""
  self.left, self.right = canvas.ui.new(), canvas.ui.new()
  self.undo, self.redo = {}, {}
  self.tool, self.layer, self.sel = "paint", 1, { 0, 0 }
  self.path_opts = { diagonal = true, jps = false, smooth = false }
  local t, err
  if self.untitled then t = { w = cfg.w, h = cfg.h }
  elseif self.filename:lower():match("%.tmx$") then t, err = self:import_tmx(self.filename)
  else t, err = read(self.filename) end
  self.err = not t and err or nil
  self.map = (t and t.layers) and Map.from_data(t) or Map.new(t and t.w, t and t.h)
  self.pick_area, self.pick_path = nil, nil        -- (the area / spline picked: its index)
  if t and t.tileset then self.map.tileset = t.tileset end
  self:load_tileset()
  if state and state.cam then self:set_camera(state.cam) end
end
-- a Tiled map: read into ours (tmx.lua), to be saved as a .tmap beside it
function TileView:import_tmx(file)
  local f = io.open(file, "rb")
  if not f then return nil, "can't read" end
  local text = f:read("*a")
  f:close()
  local dir = dir_of(file)
  local t, notes = Tmx.import(text, function(p)
    local h = io.open(dir .. "/" .. p, "rb")
    if not h then return nil end
    local s = h:read("*a"); h:close(); return s
  end)
  if not t then return nil, table.concat(notes or {}, "; ") end
  local out = file:gsub("%.[Tt][Mm][Xx]$", ".tmap")
  if system.get_file_info(out) then out = file:gsub("%.[Tt][Mm][Xx]$", "_tmx.tmap") end   -- (a .tmap of that name already: not over it)
  self.imported, self.filename, self.dirty = file, out, true
  for _, n in ipairs(notes) do core.log("tilemap: %s: %s", base_of(file), n) end
  self.import_notes = notes
  core.log("tilemap: %s read (%d note%s); CTRL+S writes %s", base_of(file), #notes, #notes == 1 and "" or "s", base_of(out))
  return t
end
function TileView:get_name() return (self.untitled and "untitled.tmap" or base_of(self.filename)) .. (self.dirty and "*" or "") end
function TileView:get_state() return { filename = self.filename, untitled = self.untitled, cam = self:camera_state() } end

function TileView:tileset_path()
  local ts = self.map.tileset
  if ts:match("^plugin:") then return P.dir .. "/" .. ts:sub(8) end
  return dir_of(self.filename) .. "/" .. ts
end
function TileView:load_tileset()
  local img, err = renderer.image.load(self:tileset_path())
  if not img then                                  -- (the plugin's own, then)
    self.ts_err = err
    img = renderer.image.load(P.dir .. "/tiles.png")
  else self.ts_err = nil end
  self.img = img
  local iw, ih = 256, 256
  if img then iw, ih = img:get_size() end
  self.cols, self.rows = math.max(1, math.floor(iw / self.map.tile)), math.max(1, math.floor(ih / self.map.tile))
end
function TileView:bounds() return 0, 0, self.map.w * self.map.tile, self.map.h * self.map.tile end

-- edits: a stroke is one undo step (a copy of the map before it)
function TileView:begin_edit()
  self.undo[#self.undo + 1] = Map.copy(self.map)
  if #self.undo > 100 then table.remove(self.undo, 1) end
  self.redo = {}
end
function TileView:changed() self.dirty = true; core.redraw = true; if self.path_b then self:find_path() end end
-- auto-tiles (the plugin's tileset, on unless turned off): the cells about
-- an edit re-picked from their neighbours (water shores, wall edges)
function TileView:autotile(x0, y0, x1, y1)
  if self.auto == false or self.map.tileset ~= Map.DEFAULTS.tileset then return end
  if Map.autotile(self.map, self.layer, AUTO, x0, y0, x1, y1) > 0 then self:changed() end
end
function TileView:undo_step(back)
  local from, to = back and self.undo or self.redo, back and self.redo or self.undo
  local m = table.remove(from)
  if not m then return end
  to[#to + 1] = Map.copy(self.map)
  self.map = m
  self:changed()
end

function TileView:reload()                         -- (read again from the disk: a regenerated map)
  local t, err = read(self.filename)
  if not t then self.err = err return end
  self.err = nil
  self.map = Map.from_data(t)
  if t.tileset then self.map.tileset = t.tileset end
  self.layer = math.min(self.layer, #self.map.layers)
  self.dirty = false
  self:load_tileset()
  core.redraw = true
end
function TileView:regenerate(src)
  local out, err = require("plugins.chain").rebuild(src)
  if not out then core.error("regenerate: %s", tostring(err)) self:flash("Can't regenerate", true) return end
  self:reload()
  self:flash("Regenerated")
end
function TileView:save()
  if self.untitled then
    return canvas.save_as("tmap", function(path) self.filename, self.untitled = path, nil; self:save() end)
  end
  local f = io.open(self.filename, "wb")
  if not f then core.error("can't write %s", self.filename) return end
  f:write("-- a tile map (plugins/tilemap): its tileset, size and layers (plugins/tilemap/map.lua)\nreturn ",
          canvas.to_lua(Map.to_data(self.map)), "\n")
  f:close()
  self.dirty = false
  core.log("Saved %s", self:get_name())
  self:flash("Saved")                              -- (canvas.tip: a note on the tab, bottom right)
end

function TileView:update()
  TileView.super.update(self)
  local now = system.get_time()
  if now >= (TileView.next_check or 0) then
    TileView.next_check = now + 0.5
    if P.changed("config") then load_config() end
    if P.changed("files") then P.open_with(P.read("files") or {}, TileView) end
  end
end

-- layout: the panels, the map between them
function TileView:rects()
  local x, y, w, h = self.position.x, self.position.y, self.size.x, self.size.y
  local lw = math.floor(math.min(S(340), w * 0.34))
  local rw = math.floor(math.min(S(190), w * 0.22))
  return { left = { x, y, lw, h }, right = { x + w - rw, y, rw, h }, mid = { x + lw, y, w - lw - rw, h } }
end
function TileView:fit()
  local r = self:rects().mid
  local mw, mh = self.map.w * self.map.tile, self.map.h * self.map.tile
  local z = math.min(r[3] / mw, r[4] / mh) * 0.9 / SCALE
  self.cam.zoom = math.max(self.zoom_min, math.min(self.zoom_max, z))
  self.cam.x = r[1] - self.position.x + r[3] / 2 - mw / 2 * self.cam.zoom * SCALE
  self.cam.y = r[2] - self.position.y + r[4] / 2 - mh / 2 * self.cam.zoom * SCALE
  self.fitting = true
  self.fit_w, self.fit_h = self.size.x, self.size.y
  core.redraw = true
end

function TileView:stamp() return Map.stamp(self.sel, self.cols) end
-- the Path tool: the way from path_a to path_b, any tile of the edited layer a wall
function TileView:find_path()
  local a, b = self.path_a, self.path_b
  if not (a and b) then self.path_result = nil; core.redraw = true return end
  local m, L = self.map, self.layer
  local g = Path.grid(m.w, m.h, function(x, y) return Map.get(m, L, x, y) ~= nil and Map.get(m, L, x, y) ~= false end)
  local cells, info = Path.find(g, a[1], a[2], b[1], b[2], self.path_opts)
  self.path_result = { cells = cells, info = info }
  core.redraw = true
end
function TileView:tile_name(i)
  if not i then return "none" end
  return (self.map.tileset == Map.DEFAULTS.tileset and NAMES[i]) or ("tile " .. i)
end

-- areas and splines (map pixels): drawn over the cells, picked, moved
local AREA_C, PATH_C = { 120, 220, 160 }, { 240, 170, 80 }
local function alpha(c, a) return { c[1], c[2], c[3], a } end
function TileView:snap(v, free)
  if free then return math.floor(v + 0.5) end
  local h = self.map.tile / 2
  return math.floor(v / h + 0.5) * h
end
function TileView:unique(list, stem)
  local names = {}
  for _, x in ipairs(list) do names[x.name] = true end
  local k = #list + 1
  while names[stem .. " " .. k] do k = k + 1 end
  return stem .. " " .. k
end
function TileView:draw_shapes(ox, oy, z)
  local D = canvas.draw
  local m = self.map
  local zs = z                                     -- (map px -> screen px)
  local f = style.font
  local on = self.tool == "area" or self.tool == "spline"
  for i, a in ipairs(m.areas or {}) do
    local picked = self.pick_area == i and self.tool == "area"
    local c = alpha(AREA_C, picked and 255 or (on and 200 or 120))
    if a.points then
      local p = a.points
      for k = 1, #p, 2 do
        local j = k + 2 <= #p and k + 2 or 1
        D.line(ox + p[k] * zs, oy + p[k + 1] * zs, ox + p[j] * zs, oy + p[j + 1] * zs, c, picked and 2 or 1)
        if picked then D.disc(ox + p[k] * zs, oy + p[k + 1] * zs, 8, c) end
      end
      renderer.draw_text(f, a.name, ox + p[1] * zs + 3, oy + p[2] * zs + 2, c)
    else
      local x, y, w, h = ox + a.x * zs, oy + a.y * zs, a.w * zs, a.h * zs
      renderer.draw_rect(x, y, w, h, alpha(AREA_C, picked and 50 or 22))
      renderer.draw_rect(x, y, w, 1, c); renderer.draw_rect(x, y + h, w, 1, c)
      renderer.draw_rect(x, y, 1, h, c); renderer.draw_rect(x + w, y, 1, h + 1, c)
      if picked then D.disc(x + w, y + h, 9, c) end   -- (its corner: drag it to size it)
      renderer.draw_text(f, a.name, x + 3, y + 2, c)
    end
  end
  for i, p in ipairs(m.paths or {}) do
    local picked = (self.pick_path == i or self.building == i) and self.tool == "spline"
    local c = alpha(PATH_C, picked and 255 or (on and 200 or 130))
    local s = Tmap.spline(p, 10)
    for k = 3, #s, 2 do D.line(ox + s[k - 2] * zs, oy + s[k - 1] * zs, ox + s[k] * zs, oy + s[k + 1] * zs, c, picked and 2.5 or 1.5) end
    if picked or on then
      for k = 1, #p.points, 2 do D.disc(ox + p.points[k] * zs, oy + p.points[k + 1] * zs, picked and 8 or 5, c) end
    end
    if #p.points >= 2 then renderer.draw_text(f, p.name, ox + p.points[1] * zs + 6, oy + p.points[2] * zs - f:get_height() - 2, c) end
  end
end
function TileView:hit_shape(wx, wy)              -- -> "area" | "path", index, what ("move", "corner", "point" k)
  local m, r = self.map, 7 / self:z()
  if self.tool == "spline" then
    for i = #(m.paths or {}), 1, -1 do
      local p = m.paths[i].points
      for k = 1, #p, 2 do if math.abs(p[k] - wx) <= r and math.abs(p[k + 1] - wy) <= r then return "path", i, "point", k end end
    end
    return nil
  end
  for i = #(m.areas or {}), 1, -1 do
    local a = m.areas[i]
    if a.points then
      if self.pick_area == i then
        for k = 1, #a.points, 2 do if math.abs(a.points[k] - wx) <= r and math.abs(a.points[k + 1] - wy) <= r then return "area", i, "point", k end end
      end
      if Tmap.contains(a, wx, wy) then return "area", i, "move" end
    else
      if self.pick_area == i and math.abs(a.x + a.w - wx) <= r and math.abs(a.y + a.h - wy) <= r then return "area", i, "corner" end
      if Tmap.contains(a, wx, wy) then return "area", i, "move" end
    end
  end
end
function TileView:shape_press(wx, wy, clicks)    -- the Area / Spline tools, LMB
  local m = self.map
  local free = keymap.modkeys["shift"]
  m.areas, m.paths = m.areas or {}, m.paths or {}
  if self.tool == "spline" then
    if self.building then
      if clicks >= 2 then self:finish_spline() return true end
      local p = m.paths[self.building].points
      p[#p + 1], p[#p + 2] = self:snap(wx, free), self:snap(wy, free)
      self:changed()
      return true
    end
    local kind, i, what, k = self:hit_shape(wx, wy)
    if kind == "path" then
      self.pick_path = i
      self.shape_drag = { kind = "path", i = i, what = what, k = k, edited = false }
      core.redraw = true
      return true
    end
    self:begin_edit()
    m.paths[#m.paths + 1] = { name = self:unique(m.paths, "path"), points = { self:snap(wx, free), self:snap(wy, free) } }
    self.building, self.pick_path = #m.paths, #m.paths
    self:changed()
    return true
  end
  local kind, i, what, k = self:hit_shape(wx, wy)
  if kind == "area" then
    self.pick_area = i
    local a = m.areas[i]
    local from = { a.x, a.y, a.w, a.h }            -- (where it was: a move is from there)
    if a.points then from = {}; for j = 1, #a.points do from[j] = a.points[j] end end
    self.shape_drag = { kind = "area", i = i, what = what, k = k, wx = wx, wy = wy, edited = false, from = from }
    core.redraw = true
    return true
  end
  self:begin_edit()                                -- a new one: dragged out
  local x, y = self:snap(wx, free), self:snap(wy, free)
  m.areas[#m.areas + 1] = { name = self:unique(m.areas, "area"), x = x, y = y, w = 0, h = 0 }
  self.pick_area = #m.areas
  self.shape_drag = { kind = "area", i = #m.areas, what = "new", x0 = x, y0 = y, edited = true }
  self:changed()
  return true
end
function TileView:shape_move(wx, wy)
  local d = self.shape_drag
  if not d then return end
  local m, free = self.map, keymap.modkeys["shift"]
  if not d.edited then self:begin_edit(); d.edited = true end
  if d.kind == "path" then
    local p = m.paths[d.i].points
    p[d.k], p[d.k + 1] = self:snap(wx, free), self:snap(wy, free)
  else
    local a = m.areas[d.i]
    if d.what == "new" then
      local x, y = self:snap(wx, free), self:snap(wy, free)
      a.x, a.y, a.w, a.h = math.min(d.x0, x), math.min(d.y0, y), math.abs(x - d.x0), math.abs(y - d.y0)
    elseif d.what == "corner" then
      a.w, a.h = math.max(0, self:snap(wx, free) - a.x), math.max(0, self:snap(wy, free) - a.y)
    elseif d.what == "point" then
      a.points[d.k], a.points[d.k + 1] = self:snap(wx, free), self:snap(wy, free)
    else                                           -- (moved: by whole steps of the grid)
      local dx, dy = self:snap(wx - d.wx, free), self:snap(wy - d.wy, free)
      if a.points then for j = 1, #a.points, 2 do a.points[j], a.points[j + 1] = d.from[j] + dx, d.from[j + 1] + dy end
      else a.x, a.y = d.from[1] + dx, d.from[2] + dy end
    end
  end
  self:changed()
end
function TileView:shape_release()
  local d = self.shape_drag
  self.shape_drag = nil
  if d and d.what == "new" then                    -- (a click, not a drag: no area)
    local a = self.map.areas[d.i]
    if a and (a.w <= 0 or a.h <= 0) then
      table.remove(self.map.areas, d.i)
      table.remove(self.undo)
      self.pick_area = nil
      core.redraw = true
    end
  end
end
function TileView:finish_spline()
  local i = self.building
  self.building = nil
  local p = i and self.map.paths[i]
  if p and #p.points < 4 then table.remove(self.map.paths, i); self.pick_path = nil end   -- (one point: no spline)
  self:changed()
end
function TileView:delete_shape()
  local m = self.map
  if self.tool == "area" and self.pick_area and m.areas[self.pick_area] then
    self:begin_edit(); table.remove(m.areas, self.pick_area); self.pick_area = nil; self:changed()
  elseif self.tool == "spline" and self.pick_path and m.paths[self.pick_path] then
    self:begin_edit(); table.remove(m.paths, self.pick_path); self.pick_path, self.building = nil, nil; self:changed()
  end
end
local function props_text(props)                  -- { team = 2 } <-> "team = 2, boss = true"
  local ks = {}
  for k in pairs(props or {}) do ks[#ks + 1] = k end
  table.sort(ks)
  local out = {}
  for _, k in ipairs(ks) do
    local v = props[k]
    out[#out + 1] = k .. " = " .. (type(v) == "string" and string.format("%q", v) or tostring(v))
  end
  return table.concat(out, ", ")
end
local function props_parse(text)
  local out = {}
  for part in (text .. ","):gmatch("([^,]*),") do
    local k, v = part:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k then
      if v == "true" or v == "false" then out[k] = v == "true"
      elseif tonumber(v) then out[k] = tonumber(v)
      else out[k] = (v:match('^"(.*)"$') or v:match("^'(.*)'$") or v) end
    end
  end
  return next(out) and out or nil
end
function TileView:draw_shapes_panel(ui)
  local m = self.map
  local list = self.tool == "area" and (m.areas or {}) or (m.paths or {})
  local pick = self.tool == "area" and self.pick_area or self.pick_path
  ui:head(self.tool == "area" and "Areas" or "Splines")
  local rows = {}
  for i, x in ipairs(list) do
    rows[#rows + 1] = { text = x.name, info = x.points and (self.tool == "area" and (#x.points / 2 .. " points") or (#x.points / 2 .. (x.closed and " closed" or " points"))) or (x.w and (x.w .. " x " .. x.h)),
                        selected = i == pick, press = function() if self.tool == "area" then self.pick_area = i else self.pick_path = i end; core.redraw = true end }
  end
  if #rows == 0 then ui:text(self.tool == "area" and "Drag on the map: an area" or "Click points on the map; Enter: done", style.dim)
  else ui:list(rows) end
  local cur = pick and list[pick]
  if cur then
    ui:field("Name", cur.name, function(t) if t:match("%S") then self:begin_edit(); cur.name = t; self:changed() end end,
             { key = self.tool .. "name" .. pick, tip = "its name: what a game asks for (tmap.area(map, name))" })
    ui:field("Props", props_text(cur.props), function(t) self:begin_edit(); cur.props = props_parse(t); self:changed() end,
             { key = self.tool .. "props" .. pick, tip = "yours: key = value, key = value (numbers, true / false, text)" })
    if self.tool == "spline" then
      ui:check("Closed", cur.closed == true, function() self:begin_edit(); cur.closed = not cur.closed or nil; self:changed() end)
      ui:label("Length", string.format("%.0f px", Tmap.length(Tmap.spline(cur, 10))))
    elseif cur.w then ui:label("At", string.format("%g, %g", cur.x, cur.y)) end
    ui:buttons({ { "Delete", function() self:delete_shape() end, tip = "Delete" } })
  end
  ui:space()
end

function TileView:draw_left(r)
  local ui = self.left
  ui:begin(r[1], r[2], r[3], r[4], { divider_right = true })
  ui:head("Tools")
  local list = {}
  for _, t in ipairs(TOOLS) do list[#list + 1] = { TOOL_NAMES[t], function() self.tool = t end, on = self.tool == t } end
  ui:buttons(list)
  ui:head("Layers")
  local rows = {}                                  -- (canvas.ui's list: the one edited lit; hover: show / hide it)
  for i, l in ipairs(self.map.layers) do
    rows[#rows + 1] = { text = i .. "  " .. l.name, info = (not l.visible) and "hidden" or nil, selected = i == self.layer,
                        press = function() self.layer = i end, tip = "the layer to edit (keys 1..9)",
                        button = { l.visible and "hide" or "show", function() l.visible = not l.visible; self:changed() end } }
  end
  ui:list(rows)
  local cur = self.map.layers[self.layer]
  ui:field("Name", cur.name, function(t)
    if t:match("%S") then self:begin_edit(); cur.name = t; self:changed() end
  end, { key = "layer" .. self.layer, tip = "click to rename this layer; Enter keeps it" })
  ui:buttons({ { "+ layer", function()
      self:begin_edit()
      table.insert(self.map.layers, Map.new_layer("layer " .. (#self.map.layers + 1), self.map.w, self.map.h))
      self.layer = #self.map.layers
      self:changed()
    end },
    { "- layer", #self.map.layers > 1 and function()
      self:begin_edit()
      table.remove(self.map.layers, self.layer)
      self.layer = math.min(self.layer, #self.map.layers)
      self:changed()
    end or nil } })
  ui:head("Tiles")
  local st = self:stamp()
  ui:label(st.w * st.h > 1 and string.format("%d x %d tiles", st.w, st.h) or self:tile_name(self.sel[1]))
  if self.img then
    local rows = (self.map.tileset == Map.DEFAULTS.tileset and NAMED_ROWS > 0) and NAMED_ROWS or nil
    local hov = ui:tiles(self.img, self.map.tile, self.sel, function(i, j) self.sel = { i, j }; if self.tool == "erase" then self.tool = "paint" end end, { rows = rows })
    if hov then self.hover_tile = hov end
  else ui:text("no tileset: " .. tostring(self.ts_err), style.error) end
  ui:finish()
end

function TileView:draw_right(r)
  local ui, m = self.right, self.map
  ui:begin(r[1], r[2], r[3], r[4])
  ui:head("Map")
  self.new_w, self.new_h = self.new_w or m.w, self.new_h or m.h
  ui:slider("Width", self.new_w, 1, 256, function(v) self.new_w = v end, { fmt = "%d", int = true, step = 1, def = m.w })
  ui:slider("Height", self.new_h, 1, 256, function(v) self.new_h = v end, { fmt = "%d", int = true, step = 1, def = m.h })
  if self.new_w ~= m.w or self.new_h ~= m.h then
    ui:buttons({ { "Resize", function() self:begin_edit(); Map.resize(m, self.new_w, self.new_h); self:changed(); self:fit() end, accent = true },
                 { "Cancel", function() self.new_w, self.new_h = m.w, m.h end } })
  end
  if m.tileset == Map.DEFAULTS.tileset then
    ui:check("Auto-tiles", self.auto ~= false, function() self.auto = self.auto == false end)   -- (water shores, wall edges: picked from the neighbours as you paint)
    if self.auto ~= false then
      ui:buttons({ { "Auto-tile this layer", function() self:begin_edit(); self:autotile() end, tip = "every water and stone-wall cell of the layer re-picked from its neighbours" } })
    end
  end
  if m.made_by and not self.untitled then          -- (another plugin made it: plugins/chain)
    local chain = require "plugins.chain"
    local src = chain.source(m.made_by, self.filename)
    ui:space()
    ui:head("Made by")
    ui:label("Source", base_of(m.made_by))
    ui:buttons({ { "Regenerate", function() self:regenerate(src) end, tip = "Make it again from its source (your edits here go)" },
                 { "Open source", function() chain.open_source(src) end } })
    ui:space()
  end
  if self.tool == "area" or self.tool == "spline" then self:draw_shapes_panel(ui) end
  if self.tool == "path" then                      -- the Path tool: how it searches, what it found
    ui:head("Path")
    local o = self.path_opts
    ui:check("Diagonals", o.diagonal, function() o.diagonal = not o.diagonal; self:find_path() end)
    ui:check("Jump point search", o.jps, function() o.jps = not o.jps; self:find_path() end)
    ui:check("Smooth", o.smooth, function() o.smooth = not o.smooth; self:find_path() end)
    ui:text("Walls: any tile of this layer", style.dim)
    local r = self.path_result
    if r then
      if r.cells then
        ui:label("Cells", tostring(#r.cells))
        ui:label("Cost", string.format("%.1f", r.info.cost or 0))
      else ui:label("Way", "none") end
      ui:label("Looked at", r.info.visited .. " cells")
    else ui:text("Click a start, then a goal", style.dim) end
    ui:space()
  end
  ui:label("Tile", m.tile .. " px")
  ui:label("Tileset", base_of(m.tileset:gsub("^plugin:", "")))
  ui:check("Grid", cfg.grid, function() cfg.grid = not cfg.grid; core.redraw = true end)
  ui:space()
  ui:head("Layer " .. self.layer)
  ui:label("Name", m.layers[self.layer].name)
  ui:label("Tiles", Map.count(m, self.layer))
  if self.hover then
    ui:space()
    ui:head("Cell")
    ui:label("At", self.hover[1] .. ", " .. self.hover[2])
    local v = Map.get(m, self.layer, self.hover[1], self.hover[2])
    if v ~= nil then ui:label("Tile", self:tile_name(v or nil)) end
  end
  ui:space()
  ui:buttons({ { self.dirty and "Save  CTRL+S" or "Saved", function() self:save() end, accent = self.dirty } })
  ui:finish()
end

function TileView:draw_canvas()
  local m, img, ts = self.map, self.img, self.map.tile
  local z = self:z()
  local cs = ts * z                                -- a cell, px on screen
  local ox, oy = self:to_screen(0, 0)
  local r = self:rects().mid
  renderer.draw_rect(ox, oy, m.w * cs, m.h * cs, { 0, 0, 0, 60 })
  local x0 = math.max(0, math.floor((r[1] - ox) / cs))   -- (only the cells on screen)
  local y0 = math.max(0, math.floor((r[2] - oy) / cs))
  local x1 = math.min(m.w - 1, math.floor((r[1] + r[3] - ox) / cs))
  local y1 = math.min(m.h - 1, math.floor((r[2] + r[4] - oy) / cs))
  if img then
    for li, l in ipairs(m.layers) do
      if l.visible then
        local tint = (li > self.layer) and { 255, 255, 255, 150 } or nil   -- (the layers above the one edited: faded)
        for y = y0, y1 do
          local row = y * m.w
          for x = x0, x1 do
            local c = l.cells[row + x + 1]
            if c then
              renderer.draw_image(img, math.floor(ox + x * cs), math.floor(oy + y * cs), math.ceil(cs), math.ceil(cs), tint,
                                  (c % self.cols) * ts, math.floor(c / self.cols) * ts, ts, ts)
            end
          end
        end
      end
    end
  end
  if cfg.grid and cs >= 6 then                     -- the grid
    local gc = { 255, 255, 255, 22 }
    for x = x0, x1 + 1 do renderer.draw_rect(ox + x * cs, oy + y0 * cs, 1, (y1 - y0 + 1) * cs, gc) end
    for y = y0, y1 + 1 do renderer.draw_rect(ox + x0 * cs, oy + y * cs, (x1 - x0 + 1) * cs, 1, gc) end
  end
  local edge = style.dim                           -- the map's edge
  renderer.draw_rect(ox, oy, m.w * cs, 1, edge); renderer.draw_rect(ox, oy + m.h * cs, m.w * cs, 1, edge)
  renderer.draw_rect(ox, oy, 1, m.h * cs, edge); renderer.draw_rect(ox + m.w * cs, oy, 1, m.h * cs + 1, edge)
  self:draw_shapes(ox, oy, z)
  local pr = self.path_result                      -- the Path tool: what it looked at (faint), the way, its ends
  if self.tool == "path" then
    if pr and pr.info and pr.info.closed then
      local lc = { 90, 160, 255, 40 }
      for i in pairs(pr.info.closed) do
        local cx, cy = i % m.w, math.floor(i / m.w)
        if cx >= x0 and cx <= x1 and cy >= y0 and cy <= y1 then renderer.draw_rect(ox + cx * cs + 1, oy + cy * cs + 1, cs - 2, cs - 2, lc) end
      end
    end
    local D = canvas.draw
    if pr and pr.cells then
      for i = 2, #pr.cells do
        local p, q = pr.cells[i - 1], pr.cells[i]
        D.line(ox + (p[1] + 0.5) * cs, oy + (p[2] + 0.5) * cs, ox + (q[1] + 0.5) * cs, oy + (q[2] + 0.5) * cs, style.accent, math.max(2, cs * 0.15))
      end
    end
    for k, e in ipairs({ self.path_a, self.path_b }) do
      if e then D.disc(ox + (e[1] + 0.5) * cs, oy + (e[2] + 0.5) * cs, math.max(6, cs * 0.6), k == 1 and { 90, 220, 120, 255 } or { 240, 90, 90, 255 }) end
    end
  end
  local h = self.hover                             -- where the tool goes: the stamp, faint, or the rectangle
  if h then
    local hx, hy = ox + h[1] * cs, oy + h[2] * cs
    if self.dragrect then
      local a, b = self.dragrect, h
      local rx, ry = ox + math.min(a[1], b[1]) * cs, oy + math.min(a[2], b[2]) * cs
      local rw, rh = (math.abs(a[1] - b[1]) + 1) * cs, (math.abs(a[2] - b[2]) + 1) * cs
      renderer.draw_rect(rx, ry, rw, rh, { style.accent[1], style.accent[2], style.accent[3], 50 })
    elseif self.tool == "paint" and img then
      local st = self:stamp()
      for j = 0, st.h - 1 do for i = 0, st.w - 1 do
        local c = st[j * st.w + i + 1]
        renderer.draw_image(img, hx + i * cs, hy + j * cs, math.ceil(cs), math.ceil(cs), { 255, 255, 255, 140 },
                            (c % self.cols) * ts, math.floor(c / self.cols) * ts, ts, ts)
      end end
    end
    local st = (self.tool == "paint") and self:stamp() or { w = 1, h = 1 }
    local fc = self.tool == "erase" and (style.error or style.accent) or style.accent
    local fw, fh = st.w * cs, st.h * cs
    renderer.draw_rect(hx, hy, fw, 1, fc); renderer.draw_rect(hx, hy + fh, fw, 1, fc)
    renderer.draw_rect(hx, hy, 1, fh, fc); renderer.draw_rect(hx + fw, hy, 1, fh + 1, fc)
  end
end

function TileView:draw_overlay()
  local r = self:rects()
  local m = r.mid
  renderer.draw_text(style.font, self:get_name() .. "   " .. TOOL_NAMES[self.tool] .. "   layer " .. self.layer
                     .. (self.err and ("   can't read: " .. self.err) or ""),
                     m[1] + S(12), m[2] + S(10), self.err and (style.error or style.text) or style.dim)
  self:draw_left(r.left)
  self:draw_right(r.right)
end

-- the mouse: the panels first; on the map, the tool
function TileView:cell_at(wx, wy)
  return math.floor(wx / self.map.tile), math.floor(wy / self.map.tile)
end
function TileView:apply(button, cx, cy, first)
  local m, L = self.map, self.layer
  if button == "right" or self.tool == "erase" then
    if Map.set(m, L, cx, cy, false) then self:changed(); self:autotile(cx - 1, cy - 1, cx + 1, cy + 1) end
  elseif self.tool == "paint" then
    local st = self:stamp()
    if Map.paint(m, L, cx, cy, st) then self:changed(); self:autotile(cx - 1, cy - 1, cx + st.w, cy + st.h) end
  elseif self.tool == "fill" and first then
    local st = self:stamp()
    if Map.fill(m, L, cx, cy, st[1]) > 0 then self:changed(); self:autotile() end
  end
end
function TileView:takes_right(x, y)               -- (contextmenu.lua: RMB on the map erases; CTRL+RMB, or off the map: the menu)
  if keymap.modkeys["ctrl"] or self.left:inside(x, y) or self.right:inside(x, y) then return false end
  if self.tool == "area" or self.tool == "spline" then return false end
  local cx, cy = self:cell_at(self:to_world(x, y))
  return Map.get(self.map, self.layer, cx, cy) ~= nil
end
function TileView:on_mouse_pressed(button, x, y, clicks)
  if self.left:pressed(button, x, y, clicks) or self.right:pressed(button, x, y, clicks) then return true end
  if button == "right" and not keymap.modkeys["ctrl"] and self.tool ~= "area" and self.tool ~= "spline" then   -- (RMB on the map erases; CTRL+RMB: the menu)
    local wx, wy = self:to_world(x, y)
    local cx, cy = self:cell_at(wx, wy)
    if Map.get(self.map, self.layer, cx, cy) ~= nil then
      self:begin_edit()
      self.painting = "right"
      self:apply("right", cx, cy, true)
      return true
    end
  end
  return TileView.super.on_mouse_pressed(self, button, x, y, clicks)
end
function TileView:on_canvas_pressed(button, wx, wy, clicks)
  if button ~= "left" then return false end
  if self.tool == "area" or self.tool == "spline" then return self:shape_press(wx, wy, clicks) end
  local cx, cy = self:cell_at(wx, wy)
  if Map.get(self.map, self.layer, cx, cy) == nil then return false end   -- (off the map: pans)
  if keymap.modkeys["alt"] then                    -- pick the tile under it
    local v = Map.get(self.map, self.layer, cx, cy)
    if v then self.sel = { v, v }; self.tool = "paint" end
    return true
  end
  if self.tool == "path" then                      -- (a start, then a goal; a third click starts again)
    if not self.path_a or self.path_b then self.path_a, self.path_b = { cx, cy }, nil
    else self.path_b = { cx, cy } end
    self:find_path()
    return true
  end
  self:begin_edit()
  if self.tool == "rect" then self.dragrect = { cx, cy } return true end
  self.painting = "left"
  self:apply("left", cx, cy, true)
  return true
end
function TileView:on_mouse_moved(x, y, dx, dy)
  if self.left:moved(x, y) or self.right:moved(x, y) then self.hover = nil return end
  local r = self:rects().mid
  if x >= r[1] and x < r[1] + r[3] then
    local cx, cy = self:cell_at(self:to_world(x, y))
    local was = self.hover
    self.hover = Map.get(self.map, self.layer, cx, cy) ~= nil and { cx, cy } or nil
    if (was and self.hover and (was[1] ~= cx or was[2] ~= cy)) or (was == nil) ~= (self.hover == nil) then core.redraw = true end
    if self.painting and self.hover then self:apply(self.painting, cx, cy, false) end
  else self.hover = nil end
  if self.shape_drag then self:shape_move(self:to_world(x, y)) return end
  if self.painting or self.dragrect then return end
  TileView.super.on_mouse_moved(self, x, y, dx, dy)
end
function TileView:on_mouse_released(button, x, y)
  if self.left:released(button) or self.right:released(button) then return end
  if self.dragrect and self.hover then
    local a, b = self.dragrect, self.hover
    if Map.rect(self.map, self.layer, a[1], a[2], b[1], b[2], self:stamp()) then
      self:changed()
      self:autotile(math.min(a[1], b[1]) - 1, math.min(a[2], b[2]) - 1, math.max(a[1], b[1]) + 1, math.max(a[2], b[2]) + 1)
    end
  end
  self.painting, self.dragrect = nil, nil
  if self.shape_drag then self:shape_release() end
  TileView.super.on_mouse_released(self, button, x, y)
end
function TileView:on_mouse_wheel(dy, dx)
  if self.right:wheel(dy) or self.left:wheel(dy) then return true end
  return TileView.super.on_mouse_wheel(self, dy, dx)
end

function TileView:menu_items()                     -- (CTRL+RMB on the map; its source, reload, settings: "Plugin: tilemap", last)
  local DIV = require("plugins.contextmenu").DIVIDER
  local items = {}
  for _, t in ipairs(TOOLS) do items[#items + 1] = { text = TOOL_NAMES[t], info = TOOL_KEYS[t], command = function() self.tool = t end } end
  items[#items + 1] = DIV
  items[#items + 1] = { text = "Undo", info = "CTRL+Z", command = function() self:undo_step(true) end }
  items[#items + 1] = { text = "Redo", info = "CTRL+Y", command = function() self:undo_step(false) end }
  items[#items + 1] = { text = "Save", info = "CTRL+S", command = function() self:save() end }
  items[#items + 1] = { text = "Fit", info = "dbl-click", command = function() self:fit() end }
  return items
end

local function active() return core.active_view and core.active_view:is(TileView) and core.active_view end
command.add(function() return active() and true or false end, {
  ["tilemap:undo"] = function() active():undo_step(true) end,
  ["tilemap:redo"] = function() active():undo_step(false) end,
  ["tilemap:paint"] = function() active().tool = "paint"; core.redraw = true end,
  ["tilemap:rect"] = function() active().tool = "rect"; core.redraw = true end,
  ["tilemap:fill"] = function() active().tool = "fill"; core.redraw = true end,
  ["tilemap:erase"] = function() active().tool = "erase"; core.redraw = true end,
  ["tilemap:path"] = function() active().tool = "path"; core.redraw = true end,
  ["tilemap:area"] = function() local v = active(); if v.building then v:finish_spline() end; v.tool = "area"; core.redraw = true end,
  ["tilemap:spline"] = function() active().tool = "spline"; core.redraw = true end,
})
command.add(function() local v = active() return v and (v.tool == "area" and v.pick_area or v.tool == "spline" and v.pick_path) and true or false end, {
  ["tilemap:delete"] = function() active():delete_shape() end,
})
command.add(function() local v = active() return v and v.building ~= nil end, {
  ["tilemap:spline-done"] = function() active():finish_spline() end,
  ["tilemap:spline-drop"] = function()
    local v = active()
    if v.building then table.remove(v.map.paths, v.building); v.building, v.pick_path = nil, nil; table.remove(v.undo); v:changed() end
  end,
})
for i = 1, 9 do
  command.add(function() local v = active() return v and v.map.layers[i] ~= nil end,
    { ["tilemap:layer-" .. i] = function() active().layer = i; core.redraw = true end })
end
if not package.loaded["tilemap.keys"] then
  package.loaded["tilemap.keys"] = true
  local keys = { ["ctrl+z"] = "tilemap:undo", ["ctrl+y"] = "tilemap:redo", ["b"] = "tilemap:paint", ["r"] = "tilemap:rect",
                 ["f"] = "tilemap:fill", ["e"] = "tilemap:erase", ["p"] = "tilemap:path", ["a"] = "tilemap:area", ["c"] = "tilemap:spline",
                 ["delete"] = "tilemap:delete", ["return"] = "tilemap:spline-done", ["escape"] = "tilemap:spline-drop" }
  for i = 1, 9 do keys[tostring(i)] = "tilemap:layer-" .. i end
  keymap.add(keys)
end

load_config()
P.open_with(P.read("files") or {}, TileView)
P.commands = { { "Paint", "tilemap:paint" }, { "Rect", "tilemap:rect" }, { "Fill", "tilemap:fill" }, { "Erase", "tilemap:erase" },
               { "Area", "tilemap:area" }, { "Spline", "tilemap:spline" },
               { "Undo", "tilemap:undo" }, { "Redo", "tilemap:redo" }, { "Save", "canvas:save" } }
P.tab = function() return TileView({}) end         -- (the main menu's <category> > <plugin> > New tab: a new map, untitled)
return TileView
