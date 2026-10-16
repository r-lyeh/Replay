-- editor.lua - the options plugin's tab: an .options file (a game's options
-- menu, in the style of Lyra's settings screen) edited as a tree (runs in
-- Lite; see editor/3rd/lite/data/plugins/projectplugins.lua for what P gives).
-- Left: the menu's tabs, sections and items (add, move, delete); middle: the
-- menu as the game shows it (runtime/options.lua: the same layout), to try
-- with the mouse and the keys; right: what's selected. Every edit rewrites
-- the file's text (the doc: Ctrl+Z / Ctrl+Y undo and redo, Ctrl+S saves); the
-- tab's icon (or *Edit as text*) flips to that text and back.
local P = ...
P.title = "Options menu"                           -- (its name in menus: Open with, the main menu's Plugins)
P.category = "Gameplay"                            -- (the main menu: Gameplay >)
P.commands = { { "Edit as text", "options:edit-as-text" }, { "Save", "canvas:save" } }
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local syntax = require "core.syntax"
local canvas = require "plugins.canvas"
local DocView = require "core.docview"
local Opt = dofile((rawget(_G, "REPLAY_ROOT") or (DATADIR .. "/../../..")) .. "/runtime/options.lua")

local DEFAULTS = { preview_w = 440, preview_h = 240 }
local cfg = {}
local function load_config()
  local c = P.read("config")
  cfg = {}
  for k, v in pairs(DEFAULTS) do cfg[k] = v end
  if type(c) == "table" then for k, v in pairs(c) do if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then cfg[k] = v end end end
  cfg.preview_w = math.max(240, math.min(1200, cfg.preview_w))
  cfg.preview_h = math.max(140, math.min(900, cfg.preview_h))
end

for _, s in ipairs(syntax.items) do                -- (.options files are Lua data: coloured as Lua)
  if s.files == "%.lua$" then s.files = { "%.lua$", "%.options$" } end
end

local function S(n) return math.floor(n * SCALE + 0.5) end
local function base_of(f) return (f:match("[^/\\]*$")) end
local function doc_of(filename)                    -- an open doc of that file (its text, unsaved too)
  local abs = system.absolute_path(filename) or filename
  for _, d in ipairs(core.docs) do
    if d.filename and (system.absolute_path(d.filename) or d.filename) == abs then return d end
  end
end

local OView = canvas.View:extend()
OView.grid = false
OView.wants_ctrl_wheel = false

function OView:new(state)
  OView.super.new(self)
  self.filename = state and state.filename or ""
  self.left, self.right = canvas.ui.new(), canvas.ui.new()
  self.sel = state and state.sel or { kind = "menu" }
  self.pst = { tab = 1, focus = 1, col = 2, scroll = 0, events = {}, open = true }   -- (the preview's state)
  self:reload()
end
function OView:get_name() return base_of(self.filename) .. (self.dirty and "*" or "") end
function OView:get_state() return { filename = self.filename, sel = self.sel } end

function OView:source()
  local d = self.doc or doc_of(self.filename)
  if d then return d:get_text(1, 1, math.huge, math.huge), d end
  local f = io.open(self.filename, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return s
end
function OView:edit_doc()                          -- the doc edits go to (opened if no tab has it)
  self.doc = self.doc or doc_of(self.filename) or core.open_doc(self.filename)
  return self.doc
end

-- the file as the tab edits it: { title, save, flat, tabs = { { name, sections = { { name, items } } } } }
local function editable(raw)
  local e = { title = raw.title or "Options", save = raw.save, tabs = {} }
  if type(raw.tabs) ~= "table" then
    e.flat = true
    e.tabs[1] = { name = "", sections = type(raw.sections) == "table" and raw.sections or {} }
  else
    for _, t in ipairs(raw.tabs) do
      if type(t) == "table" then
        local secs = type(t.sections) == "table" and t.sections or {}
        if type(t.items) == "table" then secs = { { name = "", items = t.items } } end
        e.tabs[#e.tabs + 1] = { name = t.name or "", sections = secs }
      end
    end
  end
  for _, t in ipairs(e.tabs) do
    for i, s in ipairs(t.sections) do
      if type(s) ~= "table" then s = {}; t.sections[i] = s end
      s.name = s.name or ""
      s.items = type(s.items) == "table" and s.items or {}
    end
  end
  return e
end
local function raw_of(e)
  local r = { title = e.title, save = e.save }
  if e.flat then r.sections = e.tabs[1] and e.tabs[1].sections or {} else r.tabs = e.tabs end
  return r
end

function OView:reload()
  local src = self:source()
  self.src = src
  if not src then self.err = "can't read " .. self.filename; self.e = nil; return end
  local raw, err = Opt.decode(src, base_of(self.filename))
  if not raw then self.err = err; return end      -- (the last good one stays shown, the error over it)
  self.err = nil
  self.e = editable(raw)
  self.o = Opt.new(raw_of(self.e), base_of(self.filename))
  local st = self.pst                              -- (the preview keeps its place; values: the defaults)
  local keep = st.values and { values = st.values, edit = st.edit } or nil
  Opt.methods.load(self.o, {}, st)
  if keep then                                     -- (what was tried in the preview, while it still fits)
    for id, v in pairs(keep.edit) do if self.o.by_id[id] and type(v) == type(st.edit[id]) then st.edit[id] = v end end
  end
  st.tab = math.max(1, math.min(#self.o.tabs, st.tab))
  self:check_sel()
  core.redraw = true
end
function OView:changed() self:reload(); self.dirty = self.doc and self.doc:is_dirty() or false; core.redraw = true end

-- an edit: the whole text written again (one undo step)
function OView:commit()
  local text = Opt.encode(raw_of(self.e))
  local doc = self:edit_doc()
  if doc:get_text(1, 1, math.huge, math.huge) == text then return end
  doc:remove(1, 1, math.huge, math.huge)
  doc:insert(1, 1, text)
  self:changed()
end
function OView:save()
  local doc = self:edit_doc()
  doc:save()
  self.dirty = false
  self:flash("Saved")
end

-- the selection: { kind = "menu" | "tab" | "section" | "item", t, s, i }
function OView:check_sel()
  local s, e = self.sel, self.e
  if not e then return end
  local t = s.t and e.tabs[s.t]
  if s.kind ~= "menu" and not t then self.sel = { kind = "menu" } return end
  if (s.kind == "section" or s.kind == "item") and not (t and t.sections[s.s]) then self.sel = { kind = "tab", t = s.t } return end
  if s.kind == "item" and not t.sections[s.s].items[s.i] then self.sel = { kind = "section", t = s.t, s = s.s } end
end
function OView:sel_item()
  local s = self.sel
  if s.kind ~= "item" then return nil end
  return self.e.tabs[s.t].sections[s.s].items[s.i]
end
function OView:select(sel)
  self.sel = sel
  require("plugins.canvas.ui").commit_edit()
  local st = self.pst                              -- (the preview follows: that tab, that item)
  if sel.t then
    if st.tab ~= sel.t then st.tab, st.scroll = sel.t, 0 end
    if sel.kind == "item" then
      local n = 0
      for si, sec in ipairs(self.e.tabs[sel.t].sections) do
        for ii in ipairs(sec.items) do
          n = n + 1
          if si == sel.s and ii == sel.i then st.focus = n end
        end
      end
    end
  end
  st.typing, st.confirm = nil, nil
  core.redraw = true
end
function OView:select_focus()                      -- the preview's focus -> the selection
  local st, n = self.pst, 0
  local t = self.e.tabs[st.tab]
  if not t then return end
  for si, sec in ipairs(t.sections) do
    for ii in ipairs(sec.items) do
      n = n + 1
      if n == st.focus then self.sel = { kind = "item", t = st.tab, s = si, i = ii } return end
    end
  end
  self.sel = { kind = "tab", t = st.tab }
end

-- making things -----------------------------------------------------------
local NEW = {
  bool = { type = "bool", default = false },
  enum = { type = "enum", values = { "Low", "Medium", "High" }, default = "Medium" },
  slider = { type = "slider", default = 0.5, min = 0, max = 1, step = 0.05, percent = true },
  text = { type = "text", default = "", maxlen = 16 },
  key = { type = "key", action = "jump", default = "" },
  language = { type = "language" },
  button = { type = "button", action = "go", text = "Go" },
}
function OView:unique_id(base)
  local used = {}
  for _, t in ipairs(self.e.tabs) do for _, s in ipairs(t.sections) do for _, it in ipairs(s.items) do used[tostring(it.id)] = true end end end
  local i = 1
  while used[base .. i] do i = i + 1 end
  return base .. i
end
function OView:add_tab()
  if self.e.flat then return end
  local at = (self.sel.t or #self.e.tabs) + 1
  table.insert(self.e.tabs, at, { name = "Tab " .. at, sections = { { name = "Section", items = {} } } })
  self:commit()
  self:select({ kind = "tab", t = at })
end
function OView:add_section()
  local t = self.sel.t or 1
  local tab = self.e.tabs[t]
  if not tab then return end
  local at = (self.sel.s or #tab.sections) + 1
  table.insert(tab.sections, at, { name = "Section " .. at, items = {} })
  self:commit()
  self:select({ kind = "section", t = t, s = at })
end
function OView:add_item(kind)
  local t = self.sel.t or 1
  local tab = self.e.tabs[t]
  if not tab then return end
  if #tab.sections == 0 then tab.sections[1] = { name = "", items = {} } end
  local s = self.sel.s or #tab.sections
  local sec = tab.sections[s]
  local at = (self.sel.kind == "item" and self.sel.i or #sec.items) + 1
  local it = {}
  for k, v in pairs(NEW[kind]) do it[k] = type(v) == "table" and { table.unpack(v) } or v end
  it.id = self:unique_id(kind)
  it.label = "New " .. kind
  table.insert(sec.items, at, it)
  self:commit()
  self:select({ kind = "item", t = t, s = s, i = at })
end
function OView:list_of(sel)                        -- the list it's in, its index
  local e = self.e
  if sel.kind == "tab" then return e.tabs, sel.t end
  if sel.kind == "section" then return e.tabs[sel.t].sections, sel.s end
  if sel.kind == "item" then return e.tabs[sel.t].sections[sel.s].items, sel.i end
end
function OView:move(dir)
  local sel = self.sel
  local list, i = self:list_of(sel)
  if not list or not list[i + dir] then return end
  list[i], list[i + dir] = list[i + dir], list[i]
  local n = {}
  for k, v in pairs(sel) do n[k] = v end
  if sel.kind == "tab" then n.t = i + dir elseif sel.kind == "section" then n.s = i + dir else n.i = i + dir end
  self:commit()
  self:select(n)
end
function OView:delete()
  local sel = self.sel
  local list, i = self:list_of(sel)
  if not list then return end
  if sel.kind == "tab" and #list == 1 then self:flash("A menu keeps one tab", true) return end
  table.remove(list, i)
  self:commit()
  local n = {}
  for k, v in pairs(sel) do n[k] = v end
  if sel.kind == "tab" then n.t = math.max(1, i - 1)
  elseif sel.kind == "section" then n.s = i - 1; if n.s < 1 then n = { kind = "tab", t = sel.t } end
  else n.i = i - 1; if n.i < 1 then n = { kind = "section", t = sel.t, s = sel.s } end end
  self.sel = n
  self:check_sel()
end
function OView:set_flat(flat)                      -- sections only <-> tabs
  local e = self.e
  if flat == (e.flat == true) then return end
  if flat then
    local all = {}
    for _, t in ipairs(e.tabs) do for _, s in ipairs(t.sections) do all[#all + 1] = s end end
    e.tabs = { { name = "", sections = all } }
    e.flat = true
  else
    e.tabs[1].name = "General"
    e.flat = nil
  end
  self:commit()
  self:select({ kind = "menu" })
end
-- one field of the selected item: v nil removes it
function OView:set_field(k, v)
  local it = self:sel_item()
  if not it then return end
  if it[k] == v then return end
  it[k] = v
  self:commit()
end

-- the panels ----------------------------------------------------------------
function OView:rects()
  local x, y, w, h = self.position.x, self.position.y, self.size.x, self.size.y
  local lw = math.floor(math.min(S(240), w * 0.28))
  local rw = math.floor(math.min(S(290), w * 0.32))
  return { left = { x, y, lw, h }, right = { x + w - rw, y, rw, h }, mid = { x + lw, y, w - lw - rw, h } }
end

local KIND_TAG = { bool = "on/off", enum = "list", slider = "slider", text = "text", key = "key", button = "button", language = "language" }
function OView:draw_left(r)
  local ui, e = self.left, self.e
  ui:begin(r[1], r[2], r[3], r[4], { divider_right = true })
  ui:head("Menu")
  local rows = {}
  local s = self.sel
  rows[#rows + 1] = { text = e.title, info = e.flat and "sections" or (#e.tabs .. " tabs"), kind = "head", selected = s.kind == "menu",
                      press = function() self:select({ kind = "menu" }) end }
  for ti, t in ipairs(e.tabs) do
    if not e.flat then
      rows[#rows + 1] = { text = t.name ~= "" and t.name or "(tab)", info = "tab", indent = 1, selected = s.kind == "tab" and s.t == ti,
                          press = function() self:select({ kind = "tab", t = ti }) end }
    end
    local ind = e.flat and 1 or 2
    for si, sec in ipairs(t.sections) do
      rows[#rows + 1] = { text = sec.name ~= "" and sec.name or "(section)", info = "section", indent = ind, kind = "dim",
                          selected = s.kind == "section" and s.t == ti and s.s == si,
                          press = function() self:select({ kind = "section", t = ti, s = si }) end }
      for ii, it in ipairs(sec.items) do
        rows[#rows + 1] = { text = tostring(it.label or it.id), info = KIND_TAG[tostring(it.type)] or tostring(it.type), indent = ind + 1,
                            selected = s.kind == "item" and s.t == ti and s.s == si and s.i == ii,
                            press = function() self:select({ kind = "item", t = ti, s = si, i = ii }) end }
      end
    end
  end
  ui:list(rows)
  ui:space()
  ui:head("Add")
  local adds = {}
  if not e.flat then adds[#adds + 1] = { "Tab", function() self:add_tab() end } end
  adds[#adds + 1] = { "Section", function() self:add_section() end }
  ui:buttons(adds)
  ui:buttons({ { "On/off", function() self:add_item("bool") end }, { "List", function() self:add_item("enum") end },
               { "Slider", function() self:add_item("slider") end } })
  ui:buttons({ { "Text", function() self:add_item("text") end }, { "Key", function() self:add_item("key") end },
               { "Button", function() self:add_item("button") end } })
  ui:buttons({ { "Language", function() self:add_item("language") end } })
  if s.kind ~= "menu" then
    ui:space()
    ui:head("Selected")
    ui:buttons({ { "Up", function() self:move(-1) end }, { "Down", function() self:move(1) end },
                 { "Delete", function() self:delete() end } })
  end
  ui:space()
  ui:buttons({ { self.dirty and "Save  CTRL+S" or "Saved", function() self:save() end, accent = self.dirty } })
  ui:finish()
end

local function num_field(ui, label, v, set, key)
  ui:field(label, v ~= nil and tostring(v) or "", function(t)
    if t:match("^%s*$") then set(nil) return end
    local n = tonumber(t)
    if n then set(n) end
  end, { key = key })
end
function OView:draw_right(r)
  local ui, e, s = self.right, self.e, self.sel
  ui:begin(r[1], r[2], r[3], r[4])
  local key = (s.kind or "") .. ":" .. (s.t or 0) .. ":" .. (s.s or 0) .. ":" .. (s.i or 0) .. ":"
  if s.kind == "menu" then
    ui:head("Menu")
    ui:field("Title", e.title, function(t) e.title = t; self:commit() end, { key = key .. "title" })
    ui:field("Saved as", e.save or "", function(t) e.save = t ~= "" and t or nil; self:commit() end,
             { key = key .. "save", tip = "saves/<this>.sav (empty: the file's name)" })
    ui:check("Tabs", not e.flat, function() self:set_flat(not e.flat) end)
    ui:space()
    ui:text("Two levels at most: tabs, then", style.dim)
    ui:text("sections; or sections only.", style.dim)
  elseif s.kind == "tab" then
    local t = e.tabs[s.t]
    ui:head("Tab")
    ui:field("Name", t.name, function(v) t.name = v; self:commit() end, { key = key .. "name" })
    ui:label("Sections", tostring(#t.sections))
  elseif s.kind == "section" then
    local sec = e.tabs[s.t].sections[s.s]
    ui:head("Section")
    ui:field("Name", sec.name, function(v) sec.name = v; self:commit() end, { key = key .. "name" })
    ui:label("Items", tostring(#sec.items))
  else
    local it = self:sel_item()
    local chk = self.o and self.o.by_id[tostring(it.id)]
    ui:head("Item")
    ui:choice("Type", it.type or "bool", Opt.TYPES, function(v)
      for k in pairs(NEW.slider) do if k ~= "type" then it[k] = nil end end
      for _, k in ipairs({ "values", "maxlen", "password", "action", "text", "bus", "deadzone", "fmt", "live", "window" }) do it[k] = nil end
      for k, x in pairs(NEW[v]) do it[k] = type(x) == "table" and { table.unpack(x) } or x end
      self:commit()
    end)
    ui:field("Id", tostring(it.id or ""), function(v) if v:match("^[%w_]+$") then self:set_field("id", v) else self:flash("an id: letters, digits, _", true) end end,
             { key = key .. "id", tip = "the value's name: o:value(st, id)" })
    ui:field("Label", tostring(it.label or ""), function(v) self:set_field("label", v) end, { key = key .. "label" })
    ui:field("Tip", tostring(it.tip or ""), function(v) self:set_field("tip", v ~= "" and v or nil) end, { key = key .. "tip", tip = "a line under the list while it has the focus" })
    ui:space()
    if it.type == "language" then
      ui:text("The game's languages (its strings.loc: w:languages),", style.dim)
      ui:text("set with w:language when applied.", style.dim)
    end
    local ty = chk and chk.type or it.type
    if ty == "bool" then
      ui:check("Default", it.default == true, function() self:set_field("default", not (it.default == true)) end)
      local wins = { "none" }
      for _, x in ipairs(Opt.WINDOW) do wins[#wins + 1] = x end
      ui:choice("Window", it.window or "none", wins, function(v) self:set_field("window", v ~= "none" and v or nil) end)
    elseif ty == "enum" and it.type ~= "language" then
      local vals = {}
      for _, v in ipairs(type(it.values) == "table" and it.values or {}) do vals[#vals + 1] = tostring(v) end
      ui:field("Values", table.concat(vals, ", "), function(t)
        local list = {}
        for raw in t:gmatch("[^,]+") do local v = raw:gsub("^%s+", ""):gsub("%s+$", ""); if v ~= "" then list[#list + 1] = v end end
        if #list > 0 then it.values = list; self:commit() end
      end, { key = key .. "values", tip = "comma separated" })
      if #vals > 0 then ui:choice("Default", chk and chk.default or vals[1], vals, function(v) self:set_field("default", v) end) end
    elseif ty == "slider" then
      local c = chk or it
      num_field(ui, "Min", it.min, function(v) self:set_field("min", v) end, key .. "min")
      num_field(ui, "Max", it.max, function(v) self:set_field("max", v) end, key .. "max")
      num_field(ui, "Step", it.step, function(v) self:set_field("step", v) end, key .. "step")
      num_field(ui, "Dead zone", it.deadzone, function(v) self:set_field("deadzone", v) end, key .. "dz")
      ui:slider("Default", c.default or 0, c.min or 0, c.max or 1, function(v)
        it.default = Opt.snap(c, v); self:commit()
      end, { def = c.min or 0, step = c.step, fmt = "%.3f" })
      ui:check("Percent", it.percent == true, function() self:set_field("percent", not it.percent or nil) end)
      ui:field("Format", tostring(it.fmt or ""), function(v) self:set_field("fmt", v ~= "" and v or nil) end,
               { key = key .. "fmt", tip = "string.format's: %.1f, x%.2f (empty: the step's)" })
      local buses = { "none" }
      for _, b in ipairs(Opt.BUSES) do buses[#buses + 1] = b end
      ui:choice("Sound bus", it.bus or "none", buses, function(v) self:set_field("bus", v ~= "none" and v or nil) end)
    elseif ty == "text" then
      ui:field("Default", tostring(it.default or ""), function(v) self:set_field("default", v) end, { key = key .. "default" })
      num_field(ui, "Max length", it.maxlen, function(v) self:set_field("maxlen", v and math.max(1, math.floor(v)) or nil) end, key .. "maxlen")
      ui:check("Password", it.password == true, function() self:set_field("password", not it.password or nil) end)
    elseif ty == "key" then
      ui:field("Action", tostring(it.action or ""), function(v) self:set_field("action", v ~= "" and v or nil) end,
               { key = key .. "kaction", tip = "an action of the game's /config actions: w:bind rebinds it" })
      ui:field("Default", tostring(it.default or ""), function(v) self:set_field("default", v) end,
               { key = key .. "kdefault", tip = "empty: the game's own keys; else space,pad a" })
    elseif ty == "button" then
      ui:field("Action", tostring(it.action or ""), function(v) self:set_field("action", v ~= "" and v or nil) end,
               { key = key .. "action", tip = "the event's name; close, reset, apply, discard: those" })
      ui:field("Button", tostring(it.text or ""), function(v) self:set_field("text", v ~= "" and v or nil) end, { key = key .. "text" })
    end
    if ty ~= "button" and ty ~= "key" then
      ui:check("Live", it.live == true or (it.live == nil and it.bus ~= nil), function()
        local on = it.live == true or (it.live == nil and it.bus ~= nil)
        self:set_field("live", not on)
      end)
      ui:text("Live: changes heard as they're made", style.dim)
    end
  end
  if self.o and #self.o.errors > 0 then
    ui:space()
    ui:head("Problems")
    for _, m in ipairs(self.o.errors) do ui:text(m, style.error or style.text) end
  end
  ui:finish()
end

-- the preview: the runtime's layout, drawn here (scaled to fit the middle)
function OView:preview_rect()
  local r = self:rects().mid
  local pad = S(16)
  local lw, lh = cfg.preview_w, cfg.preview_h
  local k = math.min((r[3] - pad * 2) / lw, (r[4] - pad * 4) / lh)
  k = math.max(0.25, k)
  if k > 1 then k = math.floor(k * 2) / 2 end      -- (sharper: half steps when it's bigger)
  local w, h = lw * k, lh * k
  return r[1] + math.floor((r[3] - w) / 2), r[2] + math.floor((r[4] - h) / 2), k, lw, lh
end
function OView:look() return { w = cfg.preview_w, h = cfg.preview_h } end
-- a monospace font whose letters are as wide as the game's (8 px, times the preview's scale)
local fonts, unit = {}, nil
local ttfs = {}                                   -- (a look's TrueType font, at a size: the preview's)
local function ttf_for(name, px)
  local key = tostring(name) .. ":" .. px
  if ttfs[key] == nil then
    local root = rawget(_G, "REPLAY_ROOT") or (DATADIR .. "/../../..")
    local path = (name == "sans" or name == "sans-bold" or name == "mono") and (root .. "/runtime/fonts/" .. name .. ".ttf") or tostring(name)
    local ok, f = pcall(renderer.font.load, path, px)
    ttfs[key] = ok and f or false
  end
  return ttfs[key] or nil
end
local function font_for(k)
  local path = DATADIR .. "/data/fonts/monospace.ttf"
  if not unit then
    local ok, f = pcall(renderer.font.load, path, 40)
    unit = ok and f and f:get_width("M") / 40 or 0.6
  end
  local size = math.max(4, math.floor(8 * k / unit + 0.5))
  if fonts[size] == nil then
    local ok, f = pcall(renderer.font.load, path, size)
    fonts[size] = ok and f or false
  end
  return fonts[size] or style.code_font
end
function OView:draw_canvas()
  local r = self:rects().mid
  if not self.o then
    renderer.draw_text(style.font, self.err or "...", r[1] + S(16), r[2] + S(16), style.error or style.text)
    return
  end
  local x, y, k, lw, lh = self:preview_rect()
  local ops = self.o:layout(self.pst, self:look())
  local f = font_for(k)                            -- (the game's font is 8 x 8 px: a monospace one as wide)
  for _, op in ipairs(ops) do
    if op[1] == "rect" then
      local rx, ry = x + (op[2] + lw / 2) * k, y + (op[3] + lh / 2) * k
      local rw, rh = op[4] * k, op[5] * k
      local c = op[6]
      if op.fill then renderer.draw_rect(rx, ry, math.max(1, rw), math.max(1, rh), c)
      else
        local t = math.max(1, math.floor(k))
        renderer.draw_rect(rx, ry, rw, t, c); renderer.draw_rect(rx, ry + rh - t, rw, t, c)
        renderer.draw_rect(rx, ry, t, rh, c); renderer.draw_rect(rx + rw - t, ry, t, rh, c)
      end
    else
      local tx, ty = x + (op[2] + lw / 2) * k, y + (op[3] + lh / 2) * k
      local tf = op.font and ttf_for(op.font, math.max(4, math.floor((op.font_size or 14) * k + 0.5)))
      if tf then renderer.draw_text(tf, op[4], tx, ty, op[5])
      else renderer.draw_text(f, op[4], tx, ty + (8 * k - f:get_height()) / 2, op[5]) end
    end
  end
  local line = self.err and ("can't read: " .. self.err) or "Try it: the mouse, arrows, Enter, Q / E, Backspace"
  local tf = style.font                            -- (under the preview, in the middle)
  while #line > 1 and tf:get_width(line) > r[3] - S(16) do line = line:sub(1, -2) end
  renderer.draw_text(tf, line, r[1] + math.floor((r[3] - tf:get_width(line)) / 2), y + lh * k + S(10), self.err and (style.error or style.text) or style.dim)
end
function OView:draw_overlay()
  if not self.e then return end
  local r = self:rects()
  self:draw_left(r.left)
  self:draw_right(r.right)
end
function OView:draw_background_color() return style.background end

-- trying it: the preview's own state (nothing applied to a game)
local STUB = {}
function OView:preview_key(k)
  if not self.o then return end
  local st = self.pst
  if not st.open then Opt.methods.open(self.o, STUB, st) end
  self.o:key(STUB, st, k, true)
  self.o:key(STUB, st, k, false)
  self.o:events(st)
  if not st.open then Opt.methods.open(self.o, STUB, st); self.o:events(st) end   -- (closed: shown again)
  self:select_focus()
  core.redraw = true
end
function OView:in_preview(x, y)
  if not self.o then return false end
  local px, py, k, lw, lh = self:preview_rect()
  return x >= px and y >= py and x < px + lw * k and y < py + lh * k
end
function OView:on_mouse_pressed(button, x, y, clicks)
  if self.left:pressed(button, x, y, clicks) or self.right:pressed(button, x, y, clicks) then return true end
  if self:in_preview(x, y) then
    local px, py, k, lw, lh = self:preview_rect()
    if button == "left" then                       -- (as the game's mouse: a press, a slider dragged)
      self.pdown = true
      self.pst.mdown = nil
      self.o:mouse(STUB, self.pst, (x - px) / k - lw / 2, (y - py) / k - lh / 2, true, self:look())
    else self.o:click(STUB, self.pst, (x - px) / k - lw / 2, (y - py) / k - lh / 2, self:look(), button) end
    self.o:events(self.pst)
    if not self.pst.open then Opt.methods.open(self.o, STUB, self.pst); self.o:events(self.pst) end
    self:select_focus()
    core.set_active_view(self)
    return true
  end
  return OView.super.on_mouse_pressed(self, button, x, y, clicks)
end
function OView:on_mouse_moved(x, y, dx, dy)
  self.left:moved(x, y)
  self.right:moved(x, y)
  if self.pdown and self.o then
    local px, py, k, lw, lh = self:preview_rect()
    self.o:mouse(STUB, self.pst, (x - px) / k - lw / 2, (y - py) / k - lh / 2, true, self:look())
    self.o:events(self.pst)
    core.redraw = true
  end
end
function OView:on_mouse_released(button, x, y)
  self.left:released(button)
  self.right:released(button)
  if self.pdown and self.o then
    self.pdown = nil
    self.o:mouse(STUB, self.pst, self.pst.mx or 0, self.pst.my or 0, false, self:look())
  end
end
function OView:on_mouse_wheel(dy, dx)
  return self.right:wheel(dy) or self.left:wheel(dy) or true
end
function OView:on_text_input(text)
  if require("plugins.canvas.ui").editing then return end
  if not self.o then return end
  if self.pst.capture then self:preview_key(text == " " and "space" or text:lower())
  elseif self.pst.typing then self.o:type(STUB, self.pst, text); core.redraw = true
  elseif text == "q" or text == "e" then self:preview_key(text) end   -- (the tabs, as in the game)
end

function OView:edit_text()
  local node = core.root_view.root_node:get_node_for_view(self)
  if node then require("plugins.tabflip").flip(node, self) end
end
function OView:menu_items()
  local DIV = require("plugins.contextmenu").DIVIDER
  return {
    { text = "Save", info = "CTRL+S", command = function() self:save() end },
    { text = "Edit as text", command = function() self:edit_text() end, tags = "source;code;flip" },
    DIV,
    { text = "Add tab", command = function() self:add_tab() end },
    { text = "Add section", command = function() self:add_section() end },
    { text = "Add on/off", command = function() self:add_item("bool") end },
    { text = "Add list", command = function() self:add_item("enum") end },
    { text = "Add slider", command = function() self:add_item("slider") end },
    { text = "Add text box", command = function() self:add_item("text") end },
    { text = "Add key binding", command = function() self:add_item("key") end },
    { text = "Add language list", command = function() self:add_item("language") end },
    { text = "Add button", command = function() self:add_item("button") end },
    DIV,
    { text = "Undo", info = "CTRL+Z", command = function() self:edit_doc():undo(); self:changed() end },
    { text = "Redo", info = "CTRL+Y", command = function() self:edit_doc():redo(); self:changed() end },
    { text = "Reset the preview", command = function() self.pst = { tab = 1, focus = 1, col = 2, scroll = 0, events = {}, open = true }; self:reload() end },
    { text = "Reload", command = function() self:reload() end },
  }
end

local function active() return core.active_view and core.active_view:is(OView) and not require("plugins.canvas.ui").editing end
local PREVIEW_KEYS = { "up", "down", "left", "right", "return", "keypad enter", "escape", "backspace", "tab", "shift+tab",
                       "shift+left", "shift+right", "pageup", "pagedown" }
local cmds = {
  ["options:edit-as-text"] = function() core.active_view:edit_text() end,
  ["options:undo"] = function() local v = core.active_view; v:edit_doc():undo(); v:changed() end,
  ["options:redo"] = function() local v = core.active_view; v:edit_doc():redo(); v:changed() end,
}
local KEYNAME = { ["shift+tab"] = "tab", ["shift+left"] = "left", ["shift+right"] = "right", pageup = "page up", pagedown = "page down" }
for _, k in ipairs(PREVIEW_KEYS) do
  cmds["options:key-" .. k] = function()
    local v = core.active_view
    local shift = k:match("^shift%+") ~= nil
    v.pst.shift = shift or nil
    v:preview_key(KEYNAME[k] or k)
    v.pst.shift = nil
  end
end
command.add(active, cmds)
if not package.loaded["options.keys"] then         -- (once: a reload keeps them)
  package.loaded["options.keys"] = true
  local map = { ["ctrl+z"] = "options:undo", ["ctrl+y"] = "options:redo", ["ctrl+shift+z"] = "options:redo" }
  for _, k in ipairs(PREVIEW_KEYS) do map[k] = "options:key-" .. k end
  keymap.add(map)
end

local next_check = 0
function OView:update()
  OView.super.update(self)
  local now = system.get_time()
  if now < (self.next_check or 0) then return end
  self.next_check = now + 0.25                     -- the text changed (typed, undone, on disk): read again
  local src = self:source()
  if src ~= self.src then self:reload() end
  self.dirty = self.doc ~= nil and self.doc:is_dirty() or false
  if now >= next_check then
    next_check = now + 0.5
    if P.changed("config") then load_config() end
    if P.changed("files") then P.open_with(P.read("files") or {}, OView) end
  end
end

-- a tab flips between the text and this view (the icon left of its name)
local function exts()
  local set = {}
  for _, e in ipairs(P.read("files") or {}) do if type(e) == "string" then set[(e:lower():gsub("^%.", ""))] = true end end
  return set
end
require("plugins.tabflip").register {
  key = "options",
  name = "options menu",
  text = function(view)
    local f = view:is(DocView) and view.doc and view.doc.filename
    local e = f and f:match("%.([^%./\\]+)$")
    return e ~= nil and exts()[e:lower()] == true
  end,
  alt = function(view) return view:is(OView) end,
  to_alt = function(view)
    local v = OView({ filename = system.absolute_path(view.doc.filename) or view.doc.filename })
    v.doc = view.doc
    v:reload()
    return v
  end,
  to_text = function(view) return DocView(view.doc or core.open_doc(view.filename)) end,
  icon = function(x, y, s, c)                      -- three rows: a label, a slider
    local t = math.max(1, math.floor(s / 7))
    for i = 0, 2 do
      local ry = y + math.floor(s * (0.15 + i * 0.33))
      renderer.draw_rect(x, ry, math.floor(s * 0.35), t, c)
      renderer.draw_rect(x + math.floor(s * 0.5), ry, math.floor(s * 0.5), t, c)
      renderer.draw_rect(x + math.floor(s * (0.55 + i * 0.15)), ry - t, t * 2, t * 3, c)
    end
  end,
  tip = "Show as a menu",
  menu = "Toggle menu / text",
}

load_config()
P.open_with(P.read("files") or {}, OView)
return OView
