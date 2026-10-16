-- editor.lua - the sprite animator: .anim files (runs in Lite). Per spritesheet,
-- its animations; per animation its frames; per frame its rect in the sheet, its
-- anchor (from the rect's top left), pause, events, up to 10 hitboxes, two
-- outline colours and a jump (the frame it goes to next). The sheet in the
-- middle (a canvas: MMB pans, the wheel zooms):
--   Frames tool    drag on nothing: a new frame (its anchor in its middle);
--                  drag the frame picked: move it, its edges / corners: size it
--                  (its anchor and hitboxes come along); click another: pick it
--   Hitboxes tool  drag on nothing: the next hitbox; drag one: move it, its
--                  edges: size it; Delete removes the one picked
--   1..9, 0 held   while dragging, any tool: that hitbox (1..10), drawn anew
--   the anchor     (the cross) drags in either tool, anywhere (outside its rect too)
-- Animations and frames on the left (Import...: a picture or an Aseprite
-- file); the frame's settings and a preview that plays (outlines drawn) on
-- the right. The runtime is runtime/anim.lua (games: w:anim("hero.anim")).
local P = ...
P.title = "Sprite animator"                        -- (its name in menus: Open with, the main menu's Graphics >)
P.category = "Graphics"
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local canvas = require "plugins.canvas"
local D = canvas.draw
local ROOT = rawget(_G, "REPLAY_ROOT") or (DATADIR .. "/../../..")
local A = dofile(ROOT .. "/runtime/anim.lua")
rawset(_G, "ASE_TMX", ROOT .. "/plugins/tilemap/tmx.lua")
local Ase = dofile(P.dir .. "/ase.lua")

local function S(n) return math.floor(n * SCALE + 0.5) end
local function base_of(f) return (f:match("[^/\\]*$")) end
local function dir_of(f) return f:match("^(.*)[/\\][^/\\]*$") or "." end
local function is_abs(p) return p:match("^/") or p:match("^%a:[/\\]") end
local function same_dir(a, b)                      -- (relative or not, either slash)
  local function norm(d) return ((system.absolute_path(d) or d):gsub("\\", "/"):gsub("/+$", "")) end
  return norm(a) == norm(b)
end
local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end
local function read(file)
  local f = io.open(file, "rb")
  if not f then return nil, "can't read" end
  local src = f:read("*a")
  f:close()
  local fn, err = load(src, "=" .. file, "t", {})
  if not fn then return nil, err end
  local ok, v = pcall(fn)
  if not ok or type(v) ~= "table" then return nil, ok and "not a table" or v end
  return v
end
local function cp(from, to)
  local f = io.open(from, "rb"); if not f then return false end
  local s = f:read("*a"); f:close()
  f = io.open(to, "wb"); if not f then return false end
  f:write(s); f:close()
  return true
end
local function free_name(dir, name)                -- (never over a file there: _2, _3 ...)
  if not system.get_file_info(dir .. "/" .. name) then return name end
  local stem, ext = name:match("^(.-)(%.[^%.]*)$")
  stem, ext = stem or name, ext or ""
  for k = 2, 999 do local n = stem .. "_" .. k .. ext; if not system.get_file_info(dir .. "/" .. n) then return n end end
  return name
end
local cfg = P.read("config") or {}
local IMPORT_EXTS = { "png", "webp", "qoi", "jpg", "jpeg", "bmp", "tga", "gif", "pug", "ase", "aseprite" }
local MAX_HITS = A.MAX_HITS or 10
local HIT_COLORS = {                               -- hitboxes 1..10: each its own tint
  { 235, 80, 80 }, { 80, 150, 245 }, { 90, 210, 110 }, { 240, 200, 60 }, { 200, 100, 230 },
  { 60, 215, 215 }, { 245, 140, 60 }, { 240, 120, 180 }, { 170, 200, 90 }, { 200, 200, 210 } }
local function hit_color(n, a) local c = HIT_COLORS[(n - 1) % #HIT_COLORS + 1]; return { c[1], c[2], c[3], a or 255 } end

-- keys held (1..9, 0 while dragging: a hitbox); lite tells only the modifiers
local HELD = package.loaded["spriteanim.held"]
if not HELD then
  HELD = {}
  package.loaded["spriteanim.held"] = HELD
  local kp, kr = keymap.on_key_pressed, keymap.on_key_released
  keymap.on_key_pressed = function(k, ...) HELD[k] = true; return kp(k, ...) end
  keymap.on_key_released = function(k, ...) HELD[k] = nil; return kr(k, ...) end
end
local function digit_held()                        -- -> 1..10 | nil
  for n = 1, 9 do if HELD[tostring(n)] then return n end end
  if HELD["0"] then return 10 end
end

local AView = canvas.View:extend()
AView.grid = false
AView.zoom_min, AView.zoom_max = 0.25, 32
AView.wheel_zooms = true

function AView:new(state)
  AView.super.new(self)
  self.filename = state and state.filename or ""
  self.untitled = state and state.untitled or self.filename == ""
  self.left, self.right = canvas.ui.new(), canvas.ui.new()
  self.undo, self.redo = {}, {}
  self.tool, self.ai, self.fi = "frames", 1, 1
  self.playing = true
  local t, err
  if self.untitled then t = read(P.dir .. "/templates/sprite.anim")
  elseif self.filename:lower():match("%.ase$") or self.filename:lower():match("%.aseprite$") then t, err = self:import_ase(self.filename)
  else t, err = read(self.filename) end
  self.err = not t and err or nil
  self.def = A.upgrade(t or { version = 2, sheet = "", anims = {} })   -- (an older file: read as version 2, saved so)
  self:normalize()
  self:load_sheet()
  self.st = A.new(A.check(self.def), self:anim().name)
  if state and state.cam then self:set_camera(state.cam) end
end
function AView:normalize()                         -- (at least one animation with one frame)
  local d = self.def
  d.version = 2
  d.anims = type(d.anims) == "table" and d.anims or {}
  if #d.anims == 0 then d.anims[1] = { name = "idle", frames = {} } end
  for _, a in ipairs(d.anims) do
    a.frames = type(a.frames) == "table" and a.frames or {}
    if #a.frames == 0 then a.frames[1] = { rect = { 0, 0, 32, 32 }, pause = 100, jump = 1 } end
    a.loop = nil
  end
  self.ai = math.max(1, math.min(#d.anims, self.ai or 1))
  self.fi = math.max(1, math.min(#d.anims[self.ai].frames, self.fi or 1))
end
function AView:anim() return self.def.anims[self.ai] end
function AView:frame() return self:anim().frames[self.fi] end
function AView:get_name() return (self.untitled and "untitled.anim" or base_of(self.filename)) .. (self.dirty and "*" or "") end
function AView:get_state() return { filename = self.filename, untitled = self.untitled, cam = self:camera_state() } end
function AView:bounds()
  local w, h = 128, 128
  if self.img then w, h = self.img:get_size() end
  return -8, -8, w + 16, h + 16
end
-- a frame's anchor (pivot: from its rect's top left; default its middle) and hitboxes, in the sheet
local function rect_of(f) return f.rect or { 0, 0, 32, 32 } end
local function pivot_of(f)
  local r = rect_of(f)
  return f.pivot and f.pivot[1] or (r[3] - r[1]) / 2, f.pivot and f.pivot[2] or (r[4] - r[2]) / 2
end
local function anchor_of(f) local r = rect_of(f); local px, py = pivot_of(f); return r[1] + px, r[2] + py end
local function hit_abs(f, n)
  local h = f.hits and f.hits[n]
  if not h then return nil end
  local r = rect_of(f)
  return { r[1] + h[1], r[2] + h[2], r[1] + h[3], r[2] + h[4] }
end
local set_hit_name
local function set_hit(f, n, abs)                  -- abs: sheet pixels | nil (removed)
  f.hits = f.hits or {}
  local r = rect_of(f)
  f.hits[n] = abs and { abs[1] - r[1], abs[2] - r[2], abs[3] - r[1], abs[4] - r[2] } or false
  for k = 1, MAX_HITS do if k < n and f.hits[k] == nil then f.hits[k] = false end end
  local last = 0
  for k = 1, MAX_HITS do if f.hits[k] then last = k end end
  for k = last + 1, MAX_HITS do f.hits[k] = nil end
  if last == 0 then f.hits = nil end
end

set_hit_name = function(def, n, name)               -- hitbox n's name (the same in every frame) | nil
  def.hit_names = def.hit_names or {}
  def.hit_names[n] = name or false
  for k = 1, MAX_HITS do if k < n and def.hit_names[k] == nil then def.hit_names[k] = false end end
  local last = 0
  for k = 1, MAX_HITS do if def.hit_names[k] then last = k end end
  for k = last + 1, MAX_HITS do def.hit_names[k] = nil end
  if last == 0 then def.hit_names = nil end
end
-- the preview, a frame at a time (paused): the animation's frames, round
function AView:step_preview(d)
  self.playing = false
  local a = A.check(self.def).by_name[self.st.anim] or A.check(self.def).anims[1]
  local n = #a.frames
  self.st.frame = ((self.st.frame - 1 + d) % n) + 1
  self.st.t, self.st.done, self.st.fired = 0, false, nil
  if self.st.anim == self:anim().name then self.fi = self.st.frame end
  core.redraw = true
end
function AView:sheet_path()
  if not self.def.sheet or self.def.sheet == "" then return nil end
  if is_abs(self.def.sheet) then return self.def.sheet end
  local base = self.untitled and "." or dir_of(self.filename)
  return base .. "/" .. self.def.sheet
end
function AView:load_sheet()
  self.img, self.sil, self.sheet_err, self.outlines = nil, nil, nil, nil
  if self.pending_sheet then                       -- (an Aseprite file's frames: shown before they're written)
    self.img = renderer.image.load(self.pending_sheet.tmp)
  else
    local p = self:sheet_path()
    if not p then return end
    local img, err = renderer.image.load(p)
    self.img, self.sheet_err = img, not img and err or nil
  end
end

-- an Aseprite file: its frames as a sheet (written on save, as <name>.png) and its tags as animations
function AView:read_ase(file, out_dir)
  local f = io.open(file, "rb")
  if not f then return nil, "can't read" end
  local bytes = f:read("*a")
  f:close()
  local doc, err = Ase.read(bytes)
  if not doc then return nil, err end
  local sheet = Ase.sheet(doc, (cfg.ase_cols or 0) > 0 and cfg.ase_cols or nil)
  local stem = base_of(file):gsub("%.[Aa][Ss][Ee][Pp]?[Rr]?[Ii]?[Tt]?[Ee]?$", "")
  local png = system.get_file_info(out_dir .. "/" .. stem .. ".png") and free_name(out_dir, stem .. "_ase.png") or stem .. ".png"
  local tmp = (os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp") .. "/replay_ase_" .. tostring(os.time()) .. "_" .. math.random(1000, 9999) .. ".png"
  renderer.image.write_rgba(tmp, sheet.w, sheet.h, sheet.rgba)
  self.pending_sheet = { file = out_dir .. "/" .. png, w = sheet.w, h = sheet.h, rgba = sheet.rgba, tmp = tmp }
  for _, n in ipairs(doc.notes) do core.log("sprite animator: %s: %s", base_of(file), n) end
  core.log("sprite animator: %s read (%d frames, %d tags); CTRL+S writes %s", base_of(file), #doc.frames, #doc.tags, png)
  return Ase.anim(doc, sheet, png)
end
function AView:import_ase(file)                    -- (opened: as <name>.anim beside it)
  local stem = base_of(file):gsub("%.[Aa][Ss][Ee][Pp]?[Rr]?[Ii]?[Tt]?[Ee]?$", "")
  local out = dir_of(file) .. "/" .. stem .. ".anim"
  if system.get_file_info(out) then out = dir_of(file) .. "/" .. stem .. "_ase.anim" end   -- (not over an .anim there)
  local def, err = self:read_ase(file, dir_of(file))
  if not def then return nil, err end
  self.imported, self.filename, self.dirty = file, out, true
  return def
end
-- Import...: a picture becomes the sheet (copied beside the .anim when it's
-- elsewhere); an Aseprite file, the sheet and its animations (undo brings back
-- what was there)
function AView:import(path)
  local ext = (path:match("%.([^%.]+)$") or ""):lower()
  local here = (not self.untitled) and dir_of(self.filename) or nil
  if ext == "ase" or ext == "aseprite" then
    local def, err = self:read_ase(path, here or dir_of(path))
    if not def then core.error("sprite animator: %s: %s", base_of(path), tostring(err)) return end
    if self.untitled then self.pending_sheet.file = dir_of(path) .. "/" .. base_of(self.pending_sheet.file); def.sheet = self.pending_sheet.file end
    self:edit(function(x) x.sheet, x.anims = def.sheet, def.anims end)
    self.ai, self.fi = 1, 1
    self:load_sheet()
    self:flash("Imported " .. base_of(path))
    return
  end
  local sheet = path
  if here then
    if same_dir(dir_of(path), here) then sheet = base_of(path)
    else
      local name = free_name(here, base_of(path))
      if not cp(path, here .. "/" .. name) then core.error("sprite animator: can't copy %s beside %s", path, self:get_name()) return end
      sheet = name
    end
  end
  self.pending_sheet = nil
  self:edit(function(x)
    x.sheet = sheet
    local a = x.anims[1]
    local f = a and #x.anims == 1 and #a.frames == 1 and a.frames[1]
    if f and f.rect and f.rect[1] == 0 and f.rect[2] == 0 and f.rect[3] == 32 and f.rect[4] == 32 then   -- (a new file: its one frame, the whole picture)
      local img = renderer.image.load(path)
      if img then local w, h = img:get_size(); f.rect = { 0, 0, w, h }; f.pivot = nil end
    end
  end)
  self:load_sheet()
  self:flash("Sheet: " .. base_of(path))
end

-- edits: one undo step each (a drag, a slider held: one)
function AView:edit(fn, held)
  if not held or not self.holding then
    self.undo[#self.undo + 1] = { def = copy(self.def), ai = self.ai, fi = self.fi }
    if #self.undo > 200 then table.remove(self.undo, 1) end
    self.redo = {}
  end
  self.holding = held
  fn(self.def)
  self:normalize()
  self.dirty = true
  core.redraw = true
end
function AView:undo_step(back)
  local from, to = back and self.undo or self.redo, back and self.redo or self.undo
  if #from == 0 then return end
  to[#to + 1] = { def = copy(self.def), ai = self.ai, fi = self.fi }
  local u = table.remove(from)
  self.def, self.ai, self.fi = u.def, u.ai, u.fi
  self:normalize()
  self:load_sheet()
  self.dirty = true
  core.redraw = true
end
function AView:save()
  if self.untitled then
    return canvas.save_as("anim", function(path) self.filename, self.untitled = path, nil; self:save() end)
  end
  local ps = self.pending_sheet
  if ps then
    local ok, err = renderer.image.write_rgba(ps.file, ps.w, ps.h, ps.rgba)
    if not ok then core.error("sprite animator: %s", tostring(err)) return end
    os.remove(ps.tmp)
    self.pending_sheet = nil
    self.def.sheet = base_of(ps.file)
    if not same_dir(dir_of(ps.file), dir_of(self.filename)) then   -- (written elsewhere: beside the .anim too)
      local name = free_name(dir_of(self.filename), base_of(ps.file))
      cp(ps.file, dir_of(self.filename) .. "/" .. name)
      self.def.sheet = name
    end
  end
  if self.def.sheet ~= "" and is_abs(self.def.sheet) then   -- (a picture picked before the first save: beside it now)
    local here = dir_of(self.filename)
    if same_dir(dir_of(self.def.sheet), here) then self.def.sheet = base_of(self.def.sheet)
    else
      local name = free_name(here, base_of(self.def.sheet))
      if cp(self.def.sheet, here .. "/" .. name) then self.def.sheet = name end
    end
  end
  local f = io.open(self.filename, "wb")
  if not f then core.error("can't write %s", self.filename) return end
  f:write("-- a sprite animation (plugins/spriteanim): ", self.def.sheet ~= "" and self.def.sheet or "a sheet", "'s frames (runtime/anim.lua)\nreturn ", canvas.to_lua(self.def), "\n")
  f:close()
  self.dirty = false
  self:load_sheet()
  self:flash("Saved")
end

-- the preview plays
function AView:update()
  AView.super.update(self)
  local now = system.get_time()
  local dt = math.min(0.1, now - (self.last or now))
  self.last = now
  self.cdef = A.check(self.def)
  if not self.cdef.by_name[self.st.anim] or self.preview_for ~= self.ai then   -- (another animation picked: it plays from its start; a jump may then go elsewhere)
    self.preview_for = self.ai
    self.st = A.new(self.cdef, self:anim().name)
  end
  if self.playing and dt > 0 then
    A.step(self.cdef, self.st, dt)
    if self.st.done then self.st = A.new(self.cdef, self:anim().name) end   -- (it ended: the preview plays it again)
    core.redraw = true
  end
  if now >= (AView.next_check or 0) then
    AView.next_check = now + 0.5
    if P.changed("files") then P.open_with(P.read("files") or {}, AView) end
  end
end

-- the panels ---------------------------------------------------------------
function AView:rects()
  local x, y, w, h = self.position.x, self.position.y, self.size.x, self.size.y
  local lw = math.floor(math.min(S(220), w * 0.25))
  local rw = math.floor(math.min(S(300), w * 0.34))
  return { left = { x, y, lw, h }, right = { x + w - rw, y, rw, h }, mid = { x + lw, y, w - lw - rw, h } }
end
local TOOLS = { { "frames", "Frames" }, { "hits", "Hitboxes" } }
local function jump_text(j) return j == nil and "" or tostring(j) end
local function loops(a) local l = a.frames[#a.frames]; return l and A.parse_jump(l.jump) == 1 end
function AView:draw_left(r)
  local ui = self.left
  local d = self.def
  ui:begin(r[1], r[2], r[3], r[4], { divider_right = true })
  ui:head("Sheet")
  ui:field("Picture", d.sheet, function(t) self.pending_sheet = nil; self:edit(function(x) x.sheet = t end); self:load_sheet() end, { key = "sheet" })
  if self.sheet_err then ui:text("can't read it", style.error or style.text) end
  ui:buttons({ { "Import...", function()
      require("plugins.projectplugins").pick_file("Import a picture or an Aseprite file", IMPORT_EXTS, function(p) self:import(p) end,
        (not self.untitled) and (dir_of(self.filename) .. PATHSEP) or nil)
    end, tip = "a picture (png, webp, qoi, jpg...): the sheet; an Aseprite file: the sheet and its animations" } })
  ui:space()
  ui:head("Draw on the sheet")
  local row = {}
  for _, t in ipairs(TOOLS) do row[#row + 1] = { t[2], function() self.tool = t[1] end, accent = self.tool == t[1] } end
  ui:buttons(row)
  ui:text(self.tool == "frames" and "drag: a new frame; drag it: move, size" or "drag: a hitbox; hold 1..9, 0: that one", style.dim)
  ui:space()
  ui:head("Animations")
  local rows = {}
  for i, a in ipairs(d.anims) do
    rows[#rows + 1] = { text = a.name, info = #a.frames .. (loops(a) and " loop" or ""), selected = i == self.ai,
                        press = function() self.ai, self.fi, self.hit = i, 1, nil; self.st = A.new(A.check(self.def), a.name) end }
  end
  ui:list(rows)
  ui:buttons({ { "+ New", function() self:edit(function(x)
                   local k = #x.anims + 1
                   local f = copy(self:frame()); f.jump = 1
                   x.anims[k] = { name = "anim" .. k, frames = { f } }
                   self.ai, self.fi = k, 1 end) end },
               { "Delete", function() if #d.anims > 1 then self:edit(function(x) table.remove(x.anims, self.ai) end) end end } })
  local a = self:anim()
  ui:field("Name", a.name, function(t) if t ~= "" then self:edit(function() a.name = t end) end end, { key = "aname" .. self.ai })
  ui:space()
  ui:head("Frames")
  local fr = {}
  for i, f in ipairs(a.frames) do
    local rc = rect_of(f)
    fr[#fr + 1] = { text = i .. "   " .. rc[1] .. "," .. rc[2] .. "  " .. (rc[3] - rc[1]) .. "x" .. (rc[4] - rc[2]),
                    info = (f.pause or 100) .. " ms" .. (f.jump ~= nil and ("  > " .. jump_text(f.jump)) or ""), selected = i == self.fi,
                    press = function() self.fi, self.hit = i, nil end }
  end
  ui:list(fr)
  ui:buttons({ { "+ Add", function() self:edit(function()
                   local f = copy(self:frame()); f.jump = nil
                   table.insert(a.frames, self.fi + 1, f); self.fi = self.fi + 1 end) end },
               { "Delete", function() if #a.frames > 1 then self:edit(function() table.remove(a.frames, self.fi) end) end end } })
  ui:buttons({ { "Up", function() if self.fi > 1 then self:edit(function() a.frames[self.fi], a.frames[self.fi - 1] = a.frames[self.fi - 1], a.frames[self.fi]; self.fi = self.fi - 1 end) end end },
               { "Down", function() if self.fi < #a.frames then self:edit(function() a.frames[self.fi], a.frames[self.fi + 1] = a.frames[self.fi + 1], a.frames[self.fi]; self.fi = self.fi + 1 end) end end } })
  ui:space()
  ui:buttons({ { self.dirty and "Save  CTRL+S" or "Saved", function() self:save() end, accent = self.dirty } })
  ui:finish()
end
local function nums(t) return t and table.concat(t, ", ") or "" end
local function parse_nums(s, n)
  local out = {}
  for v in tostring(s):gmatch("-?[%d%.]+") do out[#out + 1] = tonumber(v) end
  if #out == 0 then return nil end
  if #out < n then return false end
  return { table.unpack(out, 1, n) }
end
function AView:draw_right(r)
  local ui = self.right
  local f = self:frame()
  ui:begin(r[1], r[2], r[3], r[4])
  ui:head("Preview")                               -- (first: it plays above the frame's settings, never under them)
  ui:buttons({ { "<", function() self:step_preview(-1) end, tip = "the frame before (paused)  ,"},
               { self.playing and "Pause" or "Play", function() self.playing = not self.playing end, accent = not self.playing },
               { ">", function() self:step_preview(1) end, tip = "the next frame (paused)  ." },
               { "Restart", function() self.st = A.new(A.check(self.def), self:anim().name) end } })
  ui:check("Onion skin", self.onion == true, function() self.onion = not self.onion; core.redraw = true end)
  ui:label("Showing", self.st.anim .. " " .. self.st.frame)
  self.preview_y = ui.cy                           -- (its box: drawn by draw_preview, in this room)
  ui:space(self:preview_room(r))
  ui:space()
  ui:head("Frame " .. self.fi .. " of " .. self:anim().name)
  ui:field("Rect", nums(f.rect), function(t) local v = parse_nums(t, 4); if v then self:edit(function() f.rect = v end) end end, { key = "rect", tip = "x0, y0, x1, y1 in the sheet (x1, y1: past its last pixel); or drag it" })
  local px, py = pivot_of(f)
  ui:field("Anchor", px .. ", " .. py, function(t) local v = parse_nums(t, 2); self:edit(function() f.pivot = v or nil end) end,
           { key = "pivot", tip = "its point on the node, from the rect's top left (empty: the middle); or drag the cross" })
  ui:slider("Pause", f.pause or 100, 10, 2000, function(v) self:edit(function() f.pause = math.floor(v) end, true) end,
            { fmt = "%d ms", int = true, step = 10, def = 100, done = function() self.holding = false end })
  ui:field("Jump to", jump_text(f.jump), function(t)
    local v = t:match("^%s*(.-)%s*$")
    self:edit(function() f.jump = v ~= "" and (tonumber(v) or v) or nil end)
  end, { key = "jump", tip = "after its pause: empty, the next frame (after the last: it ends); 1: the first (a loop); idle / idle 2: another animation" })
  if f.jump ~= nil then
    local ja, jb = A.parse_jump(f.jump)
    local bad = type(ja) == "number" and (ja < 1 or ja > #self:anim().frames) or (type(ja) == "string" and not A.check(self.def).by_name[ja])
    if bad then ui:text("no such frame or animation", style.error or style.text) end
  end
  ui:field("Events", table.concat(f.events or {}, "; "), function(t)
    local ev = {}
    for e in (t .. ";"):gmatch("%s*(.-)%s*;") do if e ~= "" then ev[#ev + 1] = e end end
    self:edit(function() f.events = #ev > 0 and ev or nil end)
  end, { key = "events", tip = 'sent when it shows: sound("step"); fx("dust")' })
  ui:space()
  ui:head("Hitboxes")
  local hr = {}
  for n = 1, MAX_HITS do
    local h = f.hits and f.hits[n]
    if h then
      local nm = self.def.hit_names and self.def.hit_names[n]
      hr[#hr + 1] = { text = n .. (nm and ("  " .. nm) or "") .. "   " .. h[1] .. "," .. h[2] .. "  " .. (h[3] - h[1]) .. "x" .. (h[4] - h[2]), selected = self.hit == n,
                      icon = function(x, y, sz) renderer.draw_rect(x, y, sz, sz, hit_color(n)) end,
                      press = function() self.hit = n; self.tool = "hits" end,
                      button = { "x", function() self:edit(function() set_hit(f, n, nil) end); if self.hit == n then self.hit = nil end end } }
    end
  end
  if #hr == 0 then ui:text("Hitboxes tool: drag on the sheet", style.dim) else ui:list(hr) end
  if self.hit and f.hits and f.hits[self.hit] then
    local h = f.hits[self.hit]
    ui:field("Hitbox " .. self.hit, nums(h), function(t) local v = parse_nums(t, 4); if v then self:edit(function() f.hits[self.hit] = v end) end end,
             { key = "hitf" .. self.hit, tip = "x0, y0, x1, y1 from the rect's top left" })
    local n = self.hit
    ui:field("Name", self.def.hit_names and self.def.hit_names[n] or "", function(t)
      local v = t:match("^%s*(.-)%s*$")
      self:edit(function(x) set_hit_name(x, n, v ~= "" and v or nil) end)
    end, { key = "hitn" .. n, tip = "hitbox " .. n .. "'s name, in every frame: a game asks for it so (a:hitbox(st, \"attack\", x, y))" })
  end
  ui:space()
  for _, k in ipairs({ "outline1", "outline2" }) do
    ui:check(k == "outline1" and "Outline 1 (1 px)" or "Outline 2 (1 px more)", f[k] ~= nil, function()
      self:edit(function() f[k] = f[k] == nil and (k == "outline1" and { 255, 255, 255, 255 } or { 0, 0, 0, 255 }) or nil end)
    end)
    if f[k] then ui:color("Colour", f[k], function(c) self:edit(function() f[k] = { c[1], c[2], c[3], c[4] or 255 } end, true) end, { done = function() self.holding = false end }) end
  end
  if f.flow then ui:text("(a flow of Lua, from an older file: it still runs; a Jump to wins)", style.dim) end
  ui:finish()
end
-- a frame drawn at x, y (its rect's top left on screen), k px a sheet pixel: its
-- outlines first (lite's img:outline: solid round its solid pixels, cached a rect)
function AView:outline_img(rc, r)
  if not (self.img and self.img.outline) then return nil end
  self.outlines = self.outlines or {}
  local key = rc[1] .. "," .. rc[2] .. "," .. rc[3] .. "," .. rc[4] .. "/" .. r
  local o = self.outlines[key]
  if o == nil then o = self.img:outline(rc[1], rc[2], rc[3] - rc[1], rc[4] - rc[2], r) or false; self.outlines[key] = o end
  return o or nil
end
function AView:draw_sprite(fr, x, y, k)
  local rc = fr.rect
  local sw, sh = rc[3] - rc[1], rc[4] - rc[2]
  for _, o in ipairs({ { fr.outline2, 2 }, { fr.outline1, 1 } }) do   -- (outline 2 first: 2 px round it, outline 1 over its inner px)
    local c, r = o[1], o[2]
    local oi = c and self:outline_img(rc, r)
    if oi then renderer.draw_image(oi, x - r * k, y - r * k, (sw + 2 * r) * k, (sh + 2 * r) * k, c) end
  end
  renderer.draw_image(self.img, x, y, sw * k, sh * k, nil, rc[1], rc[2], sw, sh)
end
function AView:preview_scale(r)                   -- px a sheet pixel: the config's, smaller when the frames are big
  local k = (cfg.preview_scale or 3) * SCALE
  local mh = 1
  for _, f in ipairs(self:anim().frames) do local rc = rect_of(f); mh = math.max(mh, rc[4] - rc[2]) end
  local room = math.max(S(60), r[4] * 0.3)
  return math.max(SCALE * 0.5, math.min(k, room / mh)), mh
end
function AView:preview_room(r) local k, mh = self:preview_scale(r); return math.floor(mh * k + S(24)) end
function AView:draw_preview(r)                     -- the animation playing, at its anchor
  if not self.img or not self.cdef or not self.preview_y then return end
  local fr = A.frame(self.cdef, self.st)
  if not fr then return end
  local k = self:preview_scale(r)
  local room = self:preview_room(r)
  local top = self.preview_y                       -- (the panel's y: scrolled already)
  if top + room < r[2] or top > r[2] + r[4] then return end   -- (scrolled away)
  core.push_clip_rect(r[1], r[2], r[3], r[4])
  renderer.draw_rect(r[1] + S(8), top, r[3] - S(16), room - S(4), style.background3)
  local px = r[1] + r[3] / 2
  local py = top + S(10) + fr.pivot[2] * k + (room - S(24) - (fr.rect[4] - fr.rect[2]) * k) / 2
  if self.onion then                               -- the frames before and after it, faint, at their own anchors
    local an = self.cdef.by_name[self.st.anim]
    for _, o in ipairs({ { -1, { 255, 120, 120, 70 } }, { 1, { 120, 170, 255, 70 } } }) do
      local of = an and an.frames[((self.st.frame - 1 + o[1]) % #an.frames) + 1]
      if of and of ~= fr then
        local rc = of.rect
        renderer.draw_image(self.img, px - of.pivot[1] * k, py - of.pivot[2] * k, (rc[3] - rc[1]) * k, (rc[4] - rc[2]) * k, o[2], rc[1], rc[2], rc[3] - rc[1], rc[4] - rc[2])
      end
    end
  end
  self:draw_sprite(fr, px - fr.pivot[1] * k, py - fr.pivot[2] * k, k)
  for n, hb in pairs(fr.hits or {}) do             -- (its hitboxes, faint)
    local x0, y0 = px + (hb[1] - fr.pivot[1]) * k, py + (hb[2] - fr.pivot[2]) * k
    local x1, y1 = px + (hb[3] - fr.pivot[1]) * k, py + (hb[4] - fr.pivot[2]) * k
    local c = hit_color(n, 150)
    renderer.draw_rect(x0, y0, x1 - x0, 1, c); renderer.draw_rect(x0, y1 - 1, x1 - x0, 1, c)
    renderer.draw_rect(x0, y0, 1, y1 - y0, c); renderer.draw_rect(x1 - 1, y0, 1, y1 - y0, c)
  end
  renderer.draw_rect(px - S(4), py, S(9), 1, style.accent); renderer.draw_rect(px, py - S(4), 1, S(9), style.accent)
  core.pop_clip_rect()
end
local function box(x0, y0, x1, y1, c, w)
  w = w or 1
  renderer.draw_rect(x0, y0, x1 - x0, w, c); renderer.draw_rect(x0, y1 - w, x1 - x0, w, c)
  renderer.draw_rect(x0, y0, w, y1 - y0, c); renderer.draw_rect(x1 - w, y0, w, y1 - y0, c)
end
function AView:draw_canvas()
  local z = self:z()
  local iw, ih = 128, 128
  if self.img then iw, ih = self.img:get_size() end
  local x0, y0 = self:to_screen(0, 0)
  D.checker(x0, y0, iw * z, ih * z, math.max(4, 8 * z), { 60, 60, 66, 255 }, { 74, 74, 80, 255 })
  if self.img then renderer.draw_image(self.img, x0, y0, iw * z, ih * z) end
  local a = self:anim()
  local f = self:frame()
  if self.img and self.cdef and (f.outline1 or f.outline2) then   -- (the frame picked: drawn again with its outlines)
    local cf = A.check({ version = 2, sheet = "", anims = { { name = "x", frames = { f } } } }).anims[1].frames[1]
    local fx, fy = self:to_screen(cf.rect[1], cf.rect[2])
    self:draw_sprite(cf, fx, fy, z)
  end
  for i, fr in ipairs(a.frames) do                 -- the animation's frames: dim boxes; the one picked: bright, its handles
    local rc = fr.rect
    if rc then
      local ax0, ay0 = self:to_screen(rc[1], rc[2])
      local ax1, ay1 = self:to_screen(rc[3], rc[4])
      box(ax0, ay0, ax1, ay1, i == self.fi and style.accent or { style.dim[1], style.dim[2], style.dim[3], 200 }, i == self.fi and 2 or 1)
      if i ~= self.fi then renderer.draw_text(style.font, tostring(i), ax0 + S(3), ay0 + S(2), style.dim)
      elseif self.tool == "frames" then
        local hs = S(3)
        for _, p in ipairs({ { ax0, ay0 }, { ax1, ay0 }, { ax0, ay1 }, { ax1, ay1 } }) do renderer.draw_rect(p[1] - hs, p[2] - hs, hs * 2, hs * 2, style.accent) end
      end
    end
  end
  for n = 1, MAX_HITS do                           -- the frame's hitboxes, each its colour, its number
    local h = hit_abs(f, n)
    if h then
      local hx0, hy0 = self:to_screen(h[1], h[2])
      local hx1, hy1 = self:to_screen(h[3], h[4])
      renderer.draw_rect(hx0, hy0, hx1 - hx0, hy1 - hy0, hit_color(n, self.hit == n and 70 or 35))
      box(hx0, hy0, hx1, hy1, hit_color(n), self.hit == n and 2 or 1)
      renderer.draw_text(style.font, tostring(n), hx0 + S(3), hy0 + S(1), hit_color(n))
    end
  end
  local ax, ay = anchor_of(f)
  local sx, sy = self:to_screen(ax, ay)
  D.line(sx - S(7), sy, sx + S(7), sy, style.caret, 2); D.line(sx, sy - S(7), sx, sy + S(7), style.caret, 2)
  D.disc(sx, sy, S(3), style.caret)
  local d = self.drag
  if d and d.box then
    local b = d.box
    local dx0, dy0 = self:to_screen(math.min(b[1], b[3]), math.min(b[2], b[4]))
    local dx1, dy1 = self:to_screen(math.max(b[1], b[3]), math.max(b[2], b[4]))
    box(dx0, dy0, dx1, dy1, d.hit and hit_color(d.hit) or style.accent, 2)
  end
end
function AView:draw_overlay()
  local r = self:rects()
  local held = digit_held()
  renderer.draw_text(style.font, self:get_name() .. (self.err and ("   can't read: " .. self.err) or "") .. "   " .. (held and ("hitbox " .. held) or (self.tool == "frames" and "Frames" or "Hitboxes")),
                     r.mid[1] + S(12), r.mid[2] + S(10), self.err and (style.error or style.text) or style.dim)
  self:draw_strip(self:strip_rect())
  self:draw_left(r.left)
  self:draw_right(r.right)
  self:draw_preview(r.right)
end
-- the strip: the animation's frames along the bottom of the sheet's area
-- (click: pick one, the preview shows it; the one playing marked)
function AView:strip_rect()
  local m = self:rects().mid
  local h = S(64)
  return { m[1], m[2] + m[4] - h, m[3], h }
end
function AView:strip_cells()
  local r = self:strip_rect()
  local a = self:anim()
  local pad, cw = S(6), S(52)
  local out = {}
  local x = r[1] + pad - (self.strip_scroll or 0)
  for i = 1, #a.frames do out[i] = { x, r[2] + pad, cw, r[4] - 2 * pad }; x = x + cw + pad end
  return out, r
end
function AView:draw_strip(r)
  if not self.img then return end
  renderer.draw_rect(r[1], r[2], r[3], r[4], style.background2 or style.background)
  renderer.draw_rect(r[1], r[2], r[3], 1, style.divider or style.dim)
  core.push_clip_rect(r[1], r[2], r[3], r[4])
  local a = self:anim()
  local cells = self:strip_cells()
  for i, c in ipairs(cells) do
    local f = a.frames[i]
    local rc = rect_of(f)
    local sw, sh = rc[3] - rc[1], rc[4] - rc[2]
    local k = math.min((c[3] - S(6)) / math.max(1, sw), (c[4] - S(14)) / math.max(1, sh))
    renderer.draw_rect(c[1], c[2], c[3], c[4], i == self.fi and (style.selection or style.background3) or style.background3)
    renderer.draw_image(self.img, c[1] + (c[3] - sw * k) / 2, c[2] + S(2) + (c[4] - S(14) - sh * k) / 2, sw * k, sh * k, nil, rc[1], rc[2], sw, sh)
    local playing = self.st.anim == a.name and self.st.frame == i
    if playing then renderer.draw_rect(c[1], c[2] + c[4] - 2, c[3], 2, style.accent) end
    if i == self.fi then box(c[1], c[2], c[1] + c[3], c[2] + c[4], style.accent, 1) end
    renderer.draw_text(style.font, tostring(i) .. (f.jump ~= nil and (">" .. tostring(f.jump)) or ""), c[1] + S(4), c[2] + c[4] - S(15),
                       playing and style.accent or (i == self.fi and style.text or style.dim))
  end
  core.pop_clip_rect()
end
function AView:strip_pressed(x, y)
  local cells, r = self:strip_cells()
  if not (x >= r[1] and x < r[1] + r[3] and y >= r[2] and y < r[2] + r[4]) then return false end
  for i, c in ipairs(cells) do
    if x >= c[1] and x < c[1] + c[3] and y >= c[2] and y < c[2] + c[4] then
      self.fi, self.hit = i, nil
      self.playing = false
      self.st = { anim = self:anim().name, frame = i, t = 0, done = false, vars = {} }
      core.redraw = true
    end
  end
  return true
end

-- the mouse: on the sheet, the tool -----------------------------------------
local function snap(v) local g = cfg.grid or 1; if g <= 1 then return math.floor(v + 0.5) end return math.floor(v / g + 0.5) * g end
local function sides(rc, wx, wy, tol)              -- which edges of rc are under the point (a corner: two) -> { l, t, r, b } | nil
  local inx, iny = wx >= rc[1] - tol and wx <= rc[3] + tol, wy >= rc[2] - tol and wy <= rc[4] + tol
  if not (inx and iny) then return nil end
  local s = { l = math.abs(wx - rc[1]) <= tol, r = math.abs(wx - rc[3]) <= tol, t = math.abs(wy - rc[2]) <= tol, b = math.abs(wy - rc[4]) <= tol }
  if s.l or s.r or s.t or s.b then return s end
end
local function inside(rc, wx, wy) return wx >= rc[1] and wx < rc[3] and wy >= rc[2] and wy < rc[4] end
function AView:on_mouse_pressed(button, x, y, clicks)
  if self.left:pressed(button, x, y, clicks) or self.right:pressed(button, x, y, clicks) then return true end
  if button == "left" and self:strip_pressed(x, y) then return true end
  local r = AView.super.on_mouse_pressed(self, button, x, y, clicks)
  if self.drag then self.cursor = self:cursor_at(self:to_world(x, y)) end
  return r
end
function AView:on_canvas_pressed(button, wx, wy, clicks)
  if button ~= "left" then return false end
  local f = self:frame()
  local tol = S(5) / self:z()
  local ax, ay = anchor_of(f)
  local n = digit_held()
  if not n and math.abs(wx - ax) <= tol and math.abs(wy - ay) <= tol then   -- the anchor: dragged anywhere
    self.drag = { kind = "pivot" }
    return true
  end
  local sx, sy = snap(wx), snap(wy)
  if n then                                        -- 1..9, 0 held: that hitbox, drawn anew
    self.drag = { kind = "hnew", hit = n, box = { sx, sy, sx, sy } }
    self.hit = n
    return true
  end
  if self.tool == "hits" then
    local order = { self.hit }                     -- (the picked one first, then the last drawn)
    for k = MAX_HITS, 1, -1 do if k ~= self.hit then order[#order + 1] = k end end
    for _, m in ipairs(order) do
      local h = hit_abs(f, m)
      if h then
        local sd = sides(h, wx, wy, tol)
        if sd then self.hit = m; self.drag = { kind = "hsize", hit = m, sides = sd, from = h }; return true end
        if inside(h, wx, wy) then self.hit = m; self.drag = { kind = "hmove", hit = m, from = h, x = sx, y = sy }; return true end
      end
    end
    local free
    for k = 1, MAX_HITS do if not (f.hits and f.hits[k]) then free = k break end end
    if not free then self:flash("10 hitboxes: the most (Delete one)", true) return true end
    self.drag = { kind = "hnew", hit = free, box = { sx, sy, sx, sy } }
    self.hit = free
    return true
  end
  local rc = rect_of(f)                            -- Frames: the one picked (its edges, inside it), another one, or a new one
  local sd = sides(rc, wx, wy, tol)
  if sd then self.drag = { kind = "size", sides = sd, from = copy(rc) } return true end
  if inside(rc, wx, wy) then self.drag = { kind = "move", from = copy(rc), x = sx, y = sy } return true end
  for i, fr in ipairs(self:anim().frames) do
    if i ~= self.fi and fr.rect and inside(fr.rect, wx, wy) then
      self.fi, self.hit = i, nil
      self.drag = { kind = "move", from = copy(fr.rect), x = sx, y = sy }
      core.redraw = true
      return true
    end
  end
  self.drag = { kind = "new", box = { sx, sy, sx, sy } }
  return true
end
function AView:drag_to(wx, wy)
  local d = self.drag
  local f = self:frame()
  local sx, sy = snap(wx), snap(wy)
  if d.kind == "pivot" then
    local rc = rect_of(f)
    self:edit(function() f.pivot = { math.floor(wx + 0.5) - rc[1], math.floor(wy + 0.5) - rc[2] } end, true)
  elseif d.box then d.box[3], d.box[4] = sx, sy
  elseif d.kind == "move" then
    local dx, dy = sx - d.x, sy - d.y
    self:edit(function() f.rect = { d.from[1] + dx, d.from[2] + dy, d.from[3] + dx, d.from[4] + dy } end, true)
  elseif d.kind == "size" then
    local r = { d.from[1], d.from[2], d.from[3], d.from[4] }
    if d.sides.l then r[1] = math.min(sx, r[3] - 1) end
    if d.sides.r then r[3] = math.max(sx, r[1] + 1) end
    if d.sides.t then r[2] = math.min(sy, r[4] - 1) end
    if d.sides.b then r[4] = math.max(sy, r[2] + 1) end
    self:edit(function() f.rect = r end, true)     -- (its anchor and hitboxes: from its top left, so they come along)
  elseif d.kind == "hmove" then
    local dx, dy = sx - d.x, sy - d.y
    self:edit(function() set_hit(f, d.hit, { d.from[1] + dx, d.from[2] + dy, d.from[3] + dx, d.from[4] + dy }) end, true)
  elseif d.kind == "hsize" then
    local r = { d.from[1], d.from[2], d.from[3], d.from[4] }
    if d.sides.l then r[1] = math.min(sx, r[3] - 1) end
    if d.sides.r then r[3] = math.max(sx, r[1] + 1) end
    if d.sides.t then r[2] = math.min(sy, r[4] - 1) end
    if d.sides.b then r[4] = math.max(sy, r[2] + 1) end
    self:edit(function() set_hit(f, d.hit, r) end, true)
  end
  core.redraw = true
end
-- the mouse's shape: a hand over the anchor, a resize arrow over an edge it
-- would size, four arrows while moving one (or the anchor), a cross drawing anew
local function side_cursor(sd)
  if (sd.l and sd.t) or (sd.r and sd.b) then return "sizenwse" end
  if (sd.r and sd.t) or (sd.l and sd.b) then return "sizenesw" end
  if sd.l or sd.r then return "sizeh" end
  return "sizev"
end
function AView:cursor_at(wx, wy)
  local d = self.drag
  if d then
    if d.kind == "pivot" or d.kind == "move" or d.kind == "hmove" then return "move" end
    if d.sides then return side_cursor(d.sides) end
    return "crosshair"
  end
  local f = self:frame()
  local tol = S(5) / self:z()
  local ax, ay = anchor_of(f)
  if digit_held() then return "crosshair" end
  if math.abs(wx - ax) <= tol and math.abs(wy - ay) <= tol then return "hand" end
  if self.tool == "hits" then
    local order = { self.hit }
    for k = MAX_HITS, 1, -1 do if k ~= self.hit then order[#order + 1] = k end end
    for _, m in ipairs(order) do
      local h = hit_abs(f, m)
      if h then
        local sd = sides(h, wx, wy, tol)
        if sd then return side_cursor(sd) end
        if inside(h, wx, wy) then return "arrow" end
      end
    end
    return "crosshair"
  end
  local sd = sides(rect_of(f), wx, wy, tol)
  if sd then return side_cursor(sd) end
  return "arrow"
end
function AView:on_mouse_moved(x, y, dx, dy)
  if self.left:moved(x, y) or self.right:moved(x, y) then self.cursor = "arrow" return end
  if self.drag then self:drag_to(self:to_world(x, y)); self.cursor = self:cursor_at(self:to_world(x, y)) return end
  AView.super.on_mouse_moved(self, x, y, dx, dy)
  if not self.panning then
    local r = self:rects().mid
    local sr = self:strip_rect()
    self.cursor = (x >= r[1] and x < r[1] + r[3] and y < sr[2]) and self:cursor_at(self:to_world(x, y)) or "arrow"
  end
end
function AView:on_mouse_released(button, x, y)
  if self.left:released(button) or self.right:released(button) then return end
  local d = self.drag
  if d and button == "left" then
    self.drag = nil
    self.cursor = self:cursor_at(self:to_world(x, y))
    self.holding = false
    if d.box then
      local b = d.box
      local r = { math.min(b[1], b[3]), math.min(b[2], b[4]), math.max(b[1], b[3]), math.max(b[2], b[4]) }
      if r[3] > r[1] and r[4] > r[2] then
        if d.kind == "new" then                    -- a new frame after the one picked: its anchor in its middle
          local a = self:anim()
          self:edit(function()
            local cur = self:frame()
            table.insert(a.frames, self.fi + 1, { rect = r, pause = cur.pause or 100 })
            if cur.jump ~= nil and self.fi == #a.frames - 1 then a.frames[self.fi + 1].jump, cur.jump = cur.jump, nil end   -- (the last frame's jump stays on the last)
            self.fi = self.fi + 1
          end)
          self.hit = nil
        else
          local f = self:frame()
          self:edit(function() set_hit(f, d.hit, r) end)
        end
      end
    end
    core.redraw = true
    return
  end
  AView.super.on_mouse_released(self, button, x, y)
end
function AView:on_mouse_wheel(dy, dx)
  if self.right:wheel(dy) or self.left:wheel(dy) then return true end
  local sr = self:strip_rect()
  if self.mx and self.my and self.my >= sr[2] and self.mx >= sr[1] and self.mx < sr[1] + sr[3] then   -- (the strip scrolls sideways)
    local n = #self:anim().frames
    local total = n * (S(52) + S(6)) + S(6)
    self.strip_scroll = math.max(0, math.min(math.max(0, total - sr[3]), (self.strip_scroll or 0) - dy * S(40)))
    core.redraw = true
    return true
  end
  return AView.super.on_mouse_wheel(self, dy, dx)
end
function AView:delete_hit()
  local f = self:frame()
  if self.hit and f.hits and f.hits[self.hit] then
    local n = self.hit
    self:edit(function() set_hit(f, n, nil) end)
    self.hit = nil
  end
end
function AView:menu_items()
  local DIV = require("plugins.contextmenu").DIVIDER
  local items = {
    { text = self.playing and "Pause" or "Play", info = "SPACE", command = function() self.playing = not self.playing end },
    { text = "Save", info = "CTRL+S", command = function() self:save() end },
    DIV,
  }
  for _, t in ipairs(TOOLS) do items[#items + 1] = { text = "Draw: " .. t[2], checked = self.tool == t[1], command = function() self.tool = t[1] end } end
  items[#items + 1] = { text = "Delete the hitbox", info = "Delete", command = function() self:delete_hit() end }
  items[#items + 1] = DIV
  items[#items + 1] = { text = "Undo", info = "CTRL+Z", command = function() self:undo_step(true) end }
  items[#items + 1] = { text = "Redo", info = "CTRL+Y", command = function() self:undo_step(false) end }
  items[#items + 1] = { text = "Fit", info = "dbl-click", command = function() self:fit() end }
  return items
end

command.add(function() return core.active_view and core.active_view:is(AView) end, {
  ["spriteanim:play"] = function() local v = core.active_view; v.playing = not v.playing end,
  ["spriteanim:undo"] = function() core.active_view:undo_step(true) end,
  ["spriteanim:redo"] = function() core.active_view:undo_step(false) end,
  ["spriteanim:frames"] = function() core.active_view.tool = "frames"; core.redraw = true end,
  ["spriteanim:hits"] = function() core.active_view.tool = "hits"; core.redraw = true end,
  ["spriteanim:prev"] = function() core.active_view:step_preview(-1) end,
  ["spriteanim:next"] = function() core.active_view:step_preview(1) end,
  ["spriteanim:onion"] = function() local v = core.active_view; v.onion = not v.onion; core.redraw = true end,
})
command.add(function() local v = core.active_view return v and v:is(AView) and v.hit ~= nil end, {
  ["spriteanim:delete-hit"] = function() core.active_view:delete_hit() end,
})
if not package.loaded["spriteanim.keys"] then
  package.loaded["spriteanim.keys"] = true
  keymap.add { ["space"] = "spriteanim:play", ["ctrl+z"] = "spriteanim:undo", ["ctrl+y"] = "spriteanim:redo",
               ["delete"] = "spriteanim:delete-hit", ["f"] = "spriteanim:frames", ["h"] = "spriteanim:hits",
               [","] = "spriteanim:prev", ["."] = "spriteanim:next", ["o"] = "spriteanim:onion" }
end

P.open_with(P.read("files") or {}, AView)
P.commands = { { "Play / pause", "spriteanim:play" }, { "Frame before", "spriteanim:prev" }, { "Next frame", "spriteanim:next" }, { "Onion skin", "spriteanim:onion" }, { "Frames tool", "spriteanim:frames" }, { "Hitboxes tool", "spriteanim:hits" },
               { "Undo", "spriteanim:undo" }, { "Redo", "spriteanim:redo" }, { "Save", "canvas:save" } }
P.tab = function() return AView({}) end            -- (the main menu's Graphics > Sprite animator > New: untitled)
return AView
