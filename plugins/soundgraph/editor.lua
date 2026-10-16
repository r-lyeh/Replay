-- editor.lua - the sound graph editor: .soundgraph sound effects as node graphs (runs
-- in lite). Built on canvas.GraphView (like the material editor): it draws,
-- wires, selects, ties; this file says what nodes there are (from the
-- renderer, runtime/soundgraph.lua), draws each node's settings as sliders
-- inside it, renders the sound as you change it (in a thread: the editor
-- doesn't stop) and plays it, draws it in a strip at the bottom, keeps an
-- undo history, saves the file and exports a .wav. Saving this file reloads
-- the plugin.
--
-- The mouse: a setting's row is a slider (drag sideways; SHIFT: finely;
-- double-click: its default; a list (wave, filter type): a click picks the
-- next, SHIFT+click the one before). The strip at the bottom plays it.
-- SPACE plays, CTRL+Z / CTRL+Y undo and redo, CTRL+S saves.
local P = ...
P.title = "Sound graph"                            -- (its name in menus: Open with, the main menu's Plugins)
P.category = "Audio"                               -- (the main menu: Audio >)
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local canvas = require "plugins.canvas"
local D, C = canvas.draw, canvas.C
local SG = P.require("synth")

local DEFAULTS = { autoplay = true }
local cfg = {}
local function load_config()
  local c = P.read("config")
  cfg = {}
  for k, v in pairs(DEFAULTS) do cfg[k] = v end
  if type(c) == "table" then for k, v in pairs(c) do if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then cfg[k] = v end end end
end

local ROW = 18                                     -- (world units: a setting's row)
local STRIP = 64                                   -- (pixels, unscaled: the sound's strip at the bottom)
local function S(n) return math.floor(n * SCALE + 0.5) end

local SGView = canvas.GraphView:extend()
SGView.types = SG.TYPES
SGView.node_w = 170
SGView.kinds = {}
for name, k in pairs(SG.KINDS) do
  local ins, outs = {}, {}
  for _, p in ipairs(k.ins) do ins[#ins + 1] = { p[1], p[2] } end
  for _, p in ipairs(k.outs) do outs[#outs + 1] = { p[1], p[2] } end
  SGView.kinds[name] = { title = k.title, color = k.color, ins = ins, outs = outs, w = 170 }
end
function SGView:can_connect(a, b) return true end  -- (a sound is a number: an envelope into a filter's input is allowed, a tone into a pitch too)

local function read(file)
  local f = io.open(file, "rb")
  if not f then return nil, "can't read" end
  local src = f:read("*a")
  f:close()
  if src:match("^%s*$") then return {} end         -- (a new, empty file)
  local fn, err = load(src, "=" .. file, "t", {})  -- (data: nothing runs with any power)
  if not fn then return nil, err end
  local ok, v = pcall(fn)
  if not ok or type(v) ~= "table" then return nil, ok and "not a table" or v end
  return v
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end
local function plain(g)                            -- what's kept and undone: nodes, links, ties
  return copy({ nodes = g.nodes, links = g.links, ties = g.ties })
end
local function sound_key(g)                        -- what the sound depends on (not where nodes are)
  local parts = {}
  for _, n in ipairs(g.nodes) do
    local d = {}
    for k, v in pairs(n.data or {}) do d[#d + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(d)
    parts[#parts + 1] = tostring(n.id) .. n.kind .. "{" .. table.concat(d, ",") .. "}"
  end
  table.sort(parts)
  local ls = {}
  for _, l in ipairs(g.links) do ls[#ls + 1] = table.concat({ l.from, l.out, l.to, l.input }, ":") end
  table.sort(ls)
  return table.concat(parts, ";") .. "|" .. table.concat(ls, ";")
end

function SGView:new(state)
  self.filename = state and state.filename or ""
  local g, err = read(self.filename)
  self.err = not g and err or nil
  SGView.super.new(self, g)
  if state then self:set_camera(state.cam) end
  if #self.graph.nodes == 0 and not self.err then  -- (a new file: an Output to start from)
    self.graph.nodes[1] = { id = 1, kind = "output", x = 0, y = 0, data = { length = 0.6, volume = 0.8 } }
  end
  self.history, self.hpos = { plain(self.graph) }, 1
  self.gen = 0
  self.key = sound_key(self.graph)
  self:render(false)
end

function SGView:get_name() return (self.filename:match("[^/\\]*$") or "?") .. (self.dirty and "*" or "") end
function SGView:get_state() return { filename = self.filename, cam = self:camera_state() } end

function SGView:save()
  local f = io.open(self.filename, "wb")
  if not f then core.error("can't write %s", self.filename) return end
  f:write("-- a sound graph (plugins/soundgraph): its nodes and the wires between them\nreturn ",
          canvas.to_lua({ nodes = self.graph.nodes, links = self.graph.links, ties = #(self.graph.ties or {}) > 0 and self.graph.ties or nil }), "\n")
  f:close()
  self.dirty = false
  core.log("Saved %s", self:get_name())
end

-- the sound ----------------------------------------------------------------

-- render it again (in a thread, a little at a time; a newer change drops it), then play it (play)
-- its folder (files a Sample / Paulstretch node reads: beside it)
function SGView:dir() return (self.filename:match("^(.*)[/\\][^/\\]*$") or ".") end
function SGView:read_file(name)
  local f = io.open(self:dir() .. "/" .. name, "rb")
  if not f then return nil end
  local b = f:read("*a"); f:close()
  return b
end
function SGView:files_for(spec)                    -- the files a file setting can pick: beside it, by extension (not itself)
  local out, ok = {}, {}
  for _, e in ipairs(spec.file) do ok[e] = true end
  local me = self.filename:match("[^/\\]*$")
  for _, f in ipairs(system.list_dir(self:dir()) or {}) do
    local e = (f:match("%.([%w]+)$") or ""):lower()
    if ok[e] and f ~= me then out[#out + 1] = f end
  end
  table.sort(out)
  return out
end
function SGView:render(play)
  self.gen = self.gen + 1
  local gen = self.gen
  local graph = plain(self.graph)
  self.rendering = true
  local function work()
    local ok, s, info = pcall(SG.render, graph, function()
      coroutine.yield()
      if self.gen ~= gen then error("stale", 0) end
    end, { read = function(name) return self:read_file(name) end })
    if self.gen ~= gen then return end
    self.rendering = false
    if not ok then self.render_err = tostring(s); core.redraw = true; return end
    self.samples, self.info, self.render_err = s, info, info.err
    self.pcm = nil
    core.redraw = true
    if play then self:play() end
  end
  if core.add_thread then core.add_thread(work)
  else                                             -- (no lite threads: at once)
    local co = coroutine.create(work)
    while coroutine.status(co) ~= "dead" do assert(coroutine.resume(co)) end
  end
end
function SGView:play()
  if not self.samples or #self.samples == 0 then return end
  if not host_audio_play then core.error("sound graph: no sound here") return end
  self.pcm = self.pcm or SG.pcm16(self.samples)
  if host_audio_stop then host_audio_stop() end
  host_audio_play(self.pcm, SG.RATE)
  self.played_at = system.get_time()
  core.redraw = true
end
function SGView:export_wav()
  if not self.samples then return end
  local out = self.filename:gsub("%.[^%./\\]*$", "") .. ".wav"
  local f = io.open(out, "wb")
  if not f then core.error("can't write %s", out) return end
  f:write(SG.wav(self.samples))
  f:close()
  core.log("Exported %s", out:match("[^/\\]*$"))
end

-- every change: kept for undo; the sound again when it changed (not a move)
function SGView:on_change()
  if self.restoring then return end
  for i = #self.history, self.hpos + 1, -1 do self.history[i] = nil end
  self.history[#self.history + 1] = plain(self.graph)
  if #self.history > 200 then table.remove(self.history, 1) end
  self.hpos = #self.history
  local key = sound_key(self.graph)
  if key ~= self.key then self.key = key; self:render(cfg.autoplay and not self.scrub) end
end
function SGView:restore(k)
  local h = self.history[k]
  if not h then return end
  self.hpos = k
  self.restoring = true
  self.graph.nodes, self.graph.links, self.graph.ties = copy(h.nodes), copy(h.links), copy(h.ties or {})
  self.sel, self.sel_ties = {}, {}
  self:changed()
  self.restoring = false
  self.key = sound_key(self.graph)
  self:render(cfg.autoplay)
end
function SGView:undo() if self.hpos > 1 then self:restore(self.hpos - 1) end end
function SGView:redo() if self.hpos < #self.history then self:restore(self.hpos + 1) end end

function SGView:add_node(kind, wx, wy, data)       -- (new ones: every setting written, its default)
  if not data then
    data = {}
    for _, s in ipairs(SG.KINDS[kind] and SG.KINDS[kind].params or {}) do data[s[1]] = SG.default(s) end
  end
  return SGView.super.add_node(self, kind, wx, wy, data)
end

-- the settings: a row each, below the pins ---------------------------------

function SGView:node_extra(n)
  local k = SG.KINDS[n.kind]
  return k and #k.params > 0 and (#k.params * ROW + 4) or 0
end
local function frac(spec, v)                       -- where v sits on its slider, 0..1
  if spec.file then return 0 end
  if spec.options then return (v - 1) / math.max(1, #spec.options - 1) end
  if spec.log and spec[2] > 0 then return math.log(v / spec[2]) / math.log(spec[3] / spec[2]) end
  return (v - spec[2]) / (spec[3] - spec[2])
end
local function from_frac(spec, f)
  f = math.max(0, math.min(1, f))
  if spec.log and spec[2] > 0 then return spec[2] * (spec[3] / spec[2]) ^ f end
  return spec[2] + (spec[3] - spec[2]) * f
end
local function show(spec, v)
  if spec.file then return v ~= "" and v or "(a file: click)" end
  if spec.options then return spec.options[v] or "?" end
  local t
  if spec.int then t = string.format("%d", v)
  elseif math.abs(v) >= 100 then t = string.format("%.0f", v)
  elseif math.abs(v) >= 10 then t = string.format("%.1f", v)
  else t = string.format("%.2f", v) end
  return spec.unit and (t .. " " .. spec.unit) or t
end
function SGView:param_at(wx, wy)                   -- the setting under a world point: node, its spec, index
  for j = #self.graph.nodes, 1, -1 do
    local n = self.graph.nodes[j]
    local k = SG.KINDS[n.kind]
    if k and #k.params > 0 then
      local x, y, w, h = self:node_rect(n)
      local top = y + h - (self:node_extra(n) + 3)
      if wx >= x and wx < x + w and wy >= top and wy < y + h then
        local i = math.floor((wy - top - 2) / ROW) + 1
        if k.params[i] then return n, k.params[i], i end
        return nil
      end
    end
  end
end
function SGView:draw_node_extra(n, x, y, w, h, z)
  local k = SG.KINDS[n.kind]
  if not k then return end
  local F = D.font(11 * z)
  local pad = 8 * z
  local d = n.data or {}
  for i, spec in ipairs(k.params) do
    local ry = y + (2 + (i - 1) * ROW) * z
    local rh = (ROW - 3) * z
    local v = SG.param(spec, d[spec[1]])
    local hot = self.hover_param and self.hover_param[1] == n and self.hover_param[3] == i
    D.rrect(x + pad, ry, w - 2 * pad, rh, 3 * z, C.field)
    local f = frac(spec, v)
    if not spec.options and not spec.file then     -- (a slider: filled to its value)
      D.rrect(x + pad, ry, math.max(2 * z, (w - 2 * pad) * f), rh, 3 * z, hot and { 90, 120, 170, 255 } or { 64, 84, 120, 255 })
    end
    D.text(F, spec[1], x + pad + 5 * z, ry, C.blabel or C.text, rh)
    local t = show(spec, v)
    if spec.options or spec.file then t = "< " .. t .. " >" end
    D.text(F, t, x + w - pad - 5 * z - F:get_width(t), ry, C.text, rh)
  end
end

-- the mouse: settings first, then the graph --------------------------------

function SGView:strip_rect()
  local h = S(STRIP)
  return self.position.x, self.position.y + self.size.y - h, self.size.x, h
end
function SGView:on_mouse_pressed(button, x, y, clicks)
  local sx, sy, sw, sh = self:strip_rect()
  if button == "left" and y >= sy and x >= sx and x < sx + sw then self:play() return true end
  return SGView.super.on_mouse_pressed(self, button, x, y, clicks)
end
function SGView:on_canvas_pressed(button, wx, wy, clicks)
  if button == "left" and not keymap.modkeys["alt"] then
    local n, spec = self:param_at(wx, wy)
    if n then
      n.data = n.data or {}
      local v = SG.param(spec, n.data[spec[1]])
      if spec.file then                            -- a file: the next one beside it (SHIFT: the one before; none: the first)
        local list = self:files_for(spec)
        if #list == 0 then core.log("sound graph: no %s files beside it", table.concat(spec.file, " / ")) return true end
        local at = 0
        for k, f in ipairs(list) do if f == v then at = k end end
        local step = keymap.modkeys["shift"] and -1 or 1
        n.data[spec[1]] = list[(at - 1 + step) % #list + 1]
        self:changed()
        return true
      end
      if (clicks or 1) >= 2 and not spec.options then
        n.data[spec[1]] = SG.default(spec)
        self:changed()
        return true
      end
      if spec.options then
        local step = keymap.modkeys["shift"] and -1 or 1
        n.data[spec[1]] = (v - 1 + step) % #spec.options + 1
        self:changed()
        return true
      end
      local x, _, w = self:node_rect(n)
      self.scrub = { n = n, spec = spec, wx = wx, f = frac(spec, v), width = w - 16 }
      return true
    end
  end
  return SGView.super.on_canvas_pressed(self, button, wx, wy, clicks)
end
function SGView:on_canvas_moved(wx, wy)
  local s = self.scrub
  if s then
    local k = keymap.modkeys["shift"] and 0.1 or 1
    local f = s.f + (wx - s.wx) / s.width * k
    local v = from_frac(s.spec, f)
    s.n.data[s.spec[1]] = SG.param(s.spec, v)
    if math.abs(f - s.f) > 0 then s.moved = true end
    core.redraw = true
    return
  end
  local n, _, i = self:param_at(wx, wy)
  local hp = n and { n, nil, i } or nil
  if (hp and (not self.hover_param or self.hover_param[1] ~= n or self.hover_param[3] ~= i)) or (not hp and self.hover_param) then
    self.hover_param = hp
    core.redraw = true
  end
  SGView.super.on_canvas_moved(self, wx, wy)
  if hp then self.cursor = "sizeh" end
end
function SGView:on_canvas_released(button, wx, wy)
  local s = self.scrub
  if s then
    self.scrub = nil
    if s.moved then self:changed() end
    return
  end
  return SGView.super.on_canvas_released(self, button, wx, wy)
end

-- the menu, the strip ------------------------------------------------------

function SGView:menu_items()
  local items = SGView.super.menu_items(self)
  local DIV = require("plugins.contextmenu").DIVIDER
  table.insert(items, 1, { text = "Play", info = "SPACE", command = function() self:play() end })
  table.insert(items, 2, { text = "Play on change", checked = cfg.autoplay, command = function() cfg.autoplay = not cfg.autoplay end })
  table.insert(items, 3, { text = "Export .wav", command = function() self:export_wav() end })
  table.insert(items, 4, DIV)
  return items
end

function SGView:draw_overlay()
  SGView.super.draw_overlay(self)
  local x, y, w, h = self:strip_rect()
  renderer.draw_rect(x, y, w, h, { 20, 21, 26, 235 })
  renderer.draw_rect(x, y, w, math.max(1, SCALE), { 60, 62, 70, 255 })
  local s = self.samples
  local mid, amp = y + h / 2, h / 2 - S(6)
  local c = { 79, 163, 224, 255 }
  if s and #s > 0 then                             -- (min / max per column)
    local per = #s / w
    for col = 0, w - 1 do
      local a, b = math.floor(col * per) + 1, math.floor((col + 1) * per)
      local lo, hi = 0, 0
      for i = a, math.min(b, #s), math.max(1, math.floor((b - a) / 64)) do
        local v = s[i]
        if v < lo then lo = v elseif v > hi then hi = v end
      end
      local top, bot = mid - hi * amp, mid - lo * amp
      renderer.draw_rect(x + col, top, 1, math.max(1, bot - top), c)
    end
    if self.played_at then                         -- (the playhead)
      local t = (system.get_time() - self.played_at) * SG.RATE / #s
      if t < 1 then
        renderer.draw_rect(x + t * w, y, math.max(1, SCALE), h, { 255, 255, 255, 200 })
        core.redraw = true
      else self.played_at = nil end
    end
  end
  local info = self.info or {}
  local t = self.err and ("can't read: " .. tostring(self.err))
         or self.render_err and ("can't play it: " .. tostring(self.render_err))
         or (self.rendering and "rendering..."
         or string.format("%.2f s   peak %d%%%s   SPACE or a click here plays", s and #s / SG.RATE or 0,
                          math.floor((info.peak or 0) * 100 + 0.5), (info.clipped or 0) > 0 and "  (too loud: rounded off)" or ""))
  renderer.draw_text(style.font, t, x + S(8), y + S(4), (self.err or self.render_err) and (style.error or style.text) or style.dim)
end

-- commands, keys --------------------------------------------------------------

command.add(function() return core.active_view and core.active_view:is(SGView) end, {
  ["soundgraph:play"] = function() core.active_view:play() end,
  ["soundgraph:undo"] = function() core.active_view:undo() end,
  ["soundgraph:redo"] = function() core.active_view:redo() end,
  ["soundgraph:export-wav"] = function() core.active_view:export_wav() end,
})
keymap.add { ["space"] = "soundgraph:play", ["ctrl+z"] = "soundgraph:undo", ["ctrl+y"] = "soundgraph:redo", ["ctrl+shift+z"] = "soundgraph:redo" }

local next_check = 0
local update = SGView.update
function SGView:update()
  update(self)
  local now = system.get_time()
  if now >= next_check then
    next_check = now + 0.5
    if P.changed("config") then load_config() end
    if P.changed("files") then P.open_with(P.read("files") or {}, SGView) end
  end
end

load_config()
P.open_with(P.read("files") or {}, SGView)
P.commands = { { "Play", "soundgraph:play" }, { "Undo", "soundgraph:undo" }, { "Redo", "soundgraph:redo" },
               { "Export .wav", "soundgraph:export-wav" }, { "Save", "canvas:save" } }
return SGView
