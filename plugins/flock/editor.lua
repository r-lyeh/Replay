-- editor.lua - the flock editor: .flock files, boids (runs in Lite). The flock
-- flies in the middle (a canvas: its field; LMB held: a goal where the mouse
-- is; MMB pans, CTRL+wheel zooms), kinds of flocks on the left (birds, fish,
-- bats, bees, sheep) and what's in the preview (a predator after the mouse,
-- rocks); its settings on the right, as sliders: the flock changes as they move.
--
-- The simulation is runtime/flock.lua (no Lite there: games fly the same with
-- w:flock(name)). A .flock is Lua data: return { count = 60, radius = 40, ... }.
local P = ...
P.title = "Flock editor"                           -- (its name in menus: Open with, the main menu's Plugins)
P.category = "Gameplay"                            -- (the main menu: Gameplay >)
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local canvas = require "plugins.canvas"
local D = canvas.draw
local F = dofile((rawget(_G, "REPLAY_ROOT") or (DATADIR .. "/../../..")) .. "/runtime/flock.lua")

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

local ROCKS = { { -120, -40, 30 }, { 90, 60, 40 }, { 30, -110, 22 } }

local FView = canvas.View:extend()
FView.grid = 40
FView.zoom_min, FView.zoom_max = 0.1, 8

function FView:new(state)
  FView.super.new(self)
  self.filename = state and state.filename or ""
  self.untitled = state and state.untitled or self.filename == ""
  self.left, self.right = canvas.ui.new(), canvas.ui.new()
  self.undo, self.redo = {}, {}
  self.playing, self.predator, self.rocks = true, false, false
  local t, err = read(self.untitled and (P.dir .. "/templates/birds.flock") or self.filename)
  self.err = not t and err or nil
  self.def = F.check(t)
  self:restart()
  if state and state.cam then self:set_camera(state.cam) end
end
function FView:get_name() return (self.untitled and "untitled.flock" or base_of(self.filename)) .. (self.dirty and "*" or "") end
function FView:get_state() return { filename = self.filename, untitled = self.untitled, cam = self:camera_state() } end
function FView:bounds() local f = self.def.field; return -f.w / 2 - 20, -f.h / 2 - 20, f.w + 40, f.h + 40 end

function FView:restart()
  self.st = F.new(self.def, 1)
  self.last = nil
  core.redraw = true
end
function FView:edit(fn, held)                      -- fn(def) changes a copy; held: a slider still dragged (one undo step)
  if not held or not self.holding then
    self.undo[#self.undo + 1] = F.copy(self.def)
    if #self.undo > 200 then table.remove(self.undo, 1) end
    self.redo = {}
  end
  self.holding = held
  local d = F.copy(self.def)
  fn(d)
  local count = self.def.count
  self.def = F.check(d)
  if self.def.count ~= count then                  -- (more or fewer: the flock made again, the same seed)
    local was = self.st
    self.st = F.new(self.def, 1)
    for i = 1, math.min(#was.b, #self.st.b) do self.st.b[i] = was.b[i] end
  end
  self.dirty = true
  core.redraw = true
end
function FView:undo_step(back)
  local from, to = back and self.undo or self.redo, back and self.redo or self.undo
  if #from == 0 then return end
  to[#to + 1] = F.copy(self.def)
  self.def = F.check(table.remove(from))
  self.dirty = true
  self:restart()
end
function FView:use_preset(name)
  self:edit(function(d) for k, v in pairs(F.preset(name)) do d[k] = v end end)
  self:restart()
end
function FView:save()
  if self.untitled then
    return canvas.save_as("flock", function(path) self.filename, self.untitled = path, nil; self:save() end)
  end
  local f = io.open(self.filename, "wb")
  if not f then core.error("can't write %s", self.filename) return end
  f:write("-- a flock (plugins/flock): boids' settings (runtime/flock.lua)\nreturn ", canvas.to_lua(self.def), "\n")
  f:close()
  self.dirty = false
  self:flash("Saved")
end

function FView:sim_opts()
  local o = {}
  if self.goal then o.goal = self.goal end
  if self.predator and self.mouse_w then o.predators = { self.mouse_w } end
  if self.rocks then o.obstacles = ROCKS end
  return o
end
function FView:update()
  FView.super.update(self)
  local now = system.get_time()
  if self.playing then
    local dt = math.min(0.05, now - (self.last or now))
    self.last = now
    if dt > 0 then F.step(self.def, self.st, dt, self:sim_opts()) end
    core.redraw = true
  else self.last = nil end
  if now >= (FView.next_check or 0) then
    FView.next_check = now + 0.5
    if P.changed("files") then P.open_with(P.read("files") or {}, FView) end
  end
end

-- the panels --------------------------------------------------------------
function FView:rects()
  local x, y, w, h = self.position.x, self.position.y, self.size.x, self.size.y
  local lw = math.floor(math.min(S(170), w * 0.22))
  local rw = math.floor(math.min(S(300), w * 0.38))
  return { left = { x, y, lw, h }, right = { x + w - rw, y, rw, h }, mid = { x + lw, y, w - lw - rw, h } }
end
function FView:fit()
  local r = self:rects().mid
  local f = self.def.field
  local z = math.min(r[3] / (f.w + 60), r[4] / (f.h + 60)) / SCALE
  self.cam.zoom = math.max(self.zoom_min, math.min(self.zoom_max, z))
  self.cam.x = r[1] - self.position.x + r[3] / 2
  self.cam.y = r[2] - self.position.y + r[4] / 2
  self.fitting = true
  self.fit_w, self.fit_h = self.size.x, self.size.y
  core.redraw = true
end
function FView:draw_left(r)
  local ui = self.left
  ui:begin(r[1], r[2], r[3], r[4], { divider_right = true })
  ui:head("Flocks")
  for _, k in ipairs(F.PRESETS) do ui:buttons({ { F.PRESET_NAMES[k], function() self:use_preset(k) end } }) end
  ui:space()
  ui:head("Preview")
  ui:buttons({ { self.playing and "Pause" or "Play", function() self.playing = not self.playing end, accent = not self.playing },
               { "Restart", function() self:restart() end } })
  ui:check("Predator (the mouse)", self.predator, function() self.predator = not self.predator end)
  ui:check("Rocks", self.rocks, function() self.rocks = not self.rocks end)
  ui:text("LMB held: a goal there", style.dim)
  ui:space()
  ui:buttons({ { self.dirty and "Save  CTRL+S" or "Saved", function() self:save() end, accent = self.dirty } })
  ui:label("Boids", tostring(#self.st.b))
  ui:finish()
end
function FView:draw_right(r)
  local ui, d = self.right, self.def
  ui:begin(r[1], r[2], r[3], r[4])
  local function num(label, k, min, max, o)
    o = o or {}
    o.done = function() self.holding = false end
    o.def = o.def == nil and F.DEFAULTS[k] or o.def
    ui:slider(label, d[k], min, max, function(v) self:edit(function(t) t[k] = v end, true) end, o)
  end
  ui:head("Flock")
  num("Boids", "count", 1, 500, { fmt = "%d", int = true, step = 5 })
  num("Sees (radius)", "radius", 5, 150, { fmt = "%.0f px", step = 1 })
  ui:head("Rules")
  num("Separation", "separation", 0, 5, { fmt = "%.2f", step = 0.05 })
  num("Personal space", "separation_radius", 2, 80, { fmt = "%.0f px", step = 1 })
  num("Alignment", "alignment", 0, 5, { fmt = "%.2f", step = 0.05 })
  num("Cohesion", "cohesion", 0, 5, { fmt = "%.2f", step = 0.05 })
  num("Goal", "goal", 0, 5, { fmt = "%.2f", step = 0.05 })
  num("Leader", "leader", 0, 5, { fmt = "%.2f", step = 0.05 })
  num("Wander", "wander", 0, 5, { fmt = "%.2f", step = 0.05 })
  num("Avoid", "avoid", 0, 10, { fmt = "%.2f", step = 0.1 })
  num("Flee", "flee", 0, 10, { fmt = "%.2f", step = 0.1 })
  num("Flee radius", "flee_radius", 0, 300, { fmt = "%.0f px", step = 5 })
  ui:head("Motion")
  num("Min speed", "min_speed", 0, 400, { fmt = "%.0f", step = 5 })
  num("Max speed", "max_speed", 1, 600, { fmt = "%.0f", step = 5 })
  num("Turning", "max_force", 10, 2000, { fmt = "%.0f", step = 10 })
  ui:head("Field")
  ui:slider("Width", d.field.w, 50, 2000, function(v) self:edit(function(t) t.field.w = v end, true) end, { fmt = "%.0f px", step = 10, def = 640, done = function() self.holding = false end })
  ui:slider("Height", d.field.h, 50, 2000, function(v) self:edit(function(t) t.field.h = v end, true) end, { fmt = "%.0f px", step = 10, def = 400, done = function() self.holding = false end })
  ui:choice("Edges", d.edges, { "bounce", "wrap" }, function(v) self:edit(function(t) t.edges = v end) end)
  ui:head("Look")
  num("Size", "size", 1, 40, { fmt = "%.1f px", step = 0.5 })
  ui:color("Colour", d.color, function(c) self:edit(function(t) t.color = c end, true) end, { done = function() self.holding = false end })
  ui:color("Colour 2", d.color2, function(c) self:edit(function(t) t.color2 = c end, true) end, { done = function() self.holding = false end })
  ui:finish()
end
function FView:draw_canvas()
  local z = self:z()
  local f = self.def.field
  local x0, y0 = self:to_screen(-f.w / 2, -f.h / 2)
  local c = { style.dim[1], style.dim[2], style.dim[3], 160 }
  local w, h = f.w * z, f.h * z
  renderer.draw_rect(x0, y0, w, 1, c); renderer.draw_rect(x0, y0 + h, w, 1, c)
  renderer.draw_rect(x0, y0, 1, h, c); renderer.draw_rect(x0 + w, y0, 1, h, c)
  if self.rocks then
    for _, r in ipairs(ROCKS) do
      local sx, sy = self:to_screen(r[1], r[2])
      D.disc(sx, sy, r[3] * 2 * z, { 90, 84, 76, 255 })
    end
  end
  local L = F.look(self.def, self.st, self._look)
  self._look = L
  local t = L.tris
  local c1, c2 = self.def.color, self.def.color2
  for i = 1, #t, 6 do
    local k = self.st.b[(i + 5) / 6][5]
    local col = { c1[1] + (c2[1] - c1[1]) * k, c1[2] + (c2[2] - c1[2]) * k, c1[3] + (c2[3] - c1[3]) * k, 255 }
    local ax, ay = self:to_screen(t[i], t[i + 1])
    local bx, by = self:to_screen(t[i + 2], t[i + 3])
    local cx, cy = self:to_screen(t[i + 4], t[i + 5])
    local lw = math.max(1, z * 1.2)
    D.line(ax, ay, bx, by, col, lw); D.line(bx, by, cx, cy, col, lw); D.line(cx, cy, ax, ay, col, lw)
  end
  if self.goal then
    local gx, gy = self:to_screen(self.goal[1], self.goal[2])
    D.line(gx - S(8), gy, gx + S(8), gy, style.accent, 2); D.line(gx, gy - S(8), gx, gy + S(8), style.accent, 2)
  end
  if self.predator and self.mouse_w then
    local px, py = self:to_screen(self.mouse_w[1], self.mouse_w[2])
    D.disc(px, py, S(12), { 230, 80, 80, 200 })
  end
end
function FView:draw_overlay()
  local r = self:rects()
  renderer.draw_text(style.font, self:get_name() .. (self.err and ("   can't read: " .. self.err) or ""),
                     r.mid[1] + S(12), r.mid[2] + S(10), self.err and (style.error or style.text) or style.dim)
  self:draw_left(r.left)
  self:draw_right(r.right)
end

function FView:on_mouse_pressed(button, x, y, clicks)
  if self.left:pressed(button, x, y, clicks) or self.right:pressed(button, x, y, clicks) then return true end
  return FView.super.on_mouse_pressed(self, button, x, y, clicks)
end
function FView:on_canvas_pressed(button, wx, wy, clicks)
  if button == "left" and clicks == 1 then self.goal = { wx, wy }; return true end
  return false
end
function FView:on_mouse_moved(x, y, dx, dy)
  if self.left:moved(x, y) or self.right:moved(x, y) then return end
  local wx, wy = self:to_world(x, y)
  self.mouse_w = { wx, wy }
  if self.goal then self.goal = { wx, wy } return end
  FView.super.on_mouse_moved(self, x, y, dx, dy)
end
function FView:on_mouse_released(button, x, y)
  if self.left:released(button) or self.right:released(button) then return end
  if button == "left" then self.goal = nil end
  FView.super.on_mouse_released(self, button, x, y)
end
function FView:on_mouse_wheel(dy, dx)
  if self.right:wheel(dy) or self.left:wheel(dy) then return true end
  return FView.super.on_mouse_wheel(self, dy, dx)
end
function FView:menu_items()
  local DIV = require("plugins.contextmenu").DIVIDER
  local items = {
    { text = self.playing and "Pause" or "Play", info = "SPACE", command = function() self.playing = not self.playing end },
    { text = "Restart", command = function() self:restart() end },
    { text = "Save", info = "CTRL+S", command = function() self:save() end },
    DIV,
  }
  for _, k in ipairs(F.PRESETS) do items[#items + 1] = { text = "Flock: " .. F.PRESET_NAMES[k], command = function() self:use_preset(k) end } end
  items[#items + 1] = DIV
  items[#items + 1] = { text = "Undo", info = "CTRL+Z", command = function() self:undo_step(true) end }
  items[#items + 1] = { text = "Redo", info = "CTRL+Y", command = function() self:undo_step(false) end }
  items[#items + 1] = { text = "Fit", info = "dbl-click", command = function() self:fit() end }
  return items
end

command.add(function() return core.active_view and core.active_view:is(FView) end, {
  ["flock:play"] = function() local v = core.active_view; v.playing = not v.playing end,
  ["flock:undo"] = function() core.active_view:undo_step(true) end,
  ["flock:redo"] = function() core.active_view:undo_step(false) end,
})
if not package.loaded["flock.keys"] then
  package.loaded["flock.keys"] = true
  keymap.add { ["space"] = "flock:play", ["ctrl+z"] = "flock:undo", ["ctrl+y"] = "flock:redo" }
end

P.open_with(P.read("files") or {}, FView)
P.commands = { { "Play / pause", "flock:play" }, { "Undo", "flock:undo" }, { "Redo", "flock:redo" }, { "Save", "canvas:save" } }
P.tab = function() return FView({}) end            -- (the main menu's <category> > <plugin> > New tab: a new flock, untitled)
return FView
