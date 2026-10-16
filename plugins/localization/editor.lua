-- editor.lua - the localization plugin's tab: a .loc file (a game's texts,
-- keys x languages, CSV: runtime/loc.lua) as a table (runs in Lite).
-- The table in the middle (click a cell: that key, that language; red: missing;
-- orange: much longer than the first language's), the selected key on the
-- right (its text in each language, its plural forms), the languages, import
-- and export (.po, .csv). Every edit rewrites the file's text (the doc: Ctrl+Z
-- / Ctrl+Y, Ctrl+S); the tab's icon flips to the text.
local P = ...
P.title = "Localization"                           -- (its name in menus: Open with, the main menu's Plugins)
P.category = "Gameplay"                            -- (the main menu: Gameplay >)
P.commands = { { "Edit as text", "localization:edit-as-text" }, { "Save", "canvas:save" } }
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local common = require "core.common"
local canvas = require "plugins.canvas"
local DocView = require "core.docview"
local L = dofile((rawget(_G, "REPLAY_ROOT") or (DATADIR .. "/../../..")) .. "/runtime/loc.lua")

local function S(n) return math.floor(n * SCALE + 0.5) end
local function base_of(f) return (f:match("[^/\\]*$")) end
local function doc_of(filename)
  local abs = system.absolute_path(filename) or filename
  for _, d in ipairs(core.docs) do
    if d.filename and (system.absolute_path(d.filename) or d.filename) == abs then return d end
  end
end
local MISSING, LONG = { 120, 40, 48, 255 }, { 200, 120, 30, 255 }

local LView = canvas.View:extend()
LView.grid = false
LView.wants_ctrl_wheel = false

function LView:new(state)
  LView.super.new(self)
  self.filename = state and state.filename or ""
  self.right = canvas.ui.new()
  self.sel = state and state.sel or nil            -- the selected key
  self.sel_lang = nil
  self.scroll_y = 0
  self.filter = ""
  self:reload()
end
function LView:get_name() return base_of(self.filename) .. (self.dirty and "*" or "") end
function LView:get_state() return { filename = self.filename, sel = self.sel } end
function LView:source()
  local d = self.doc or doc_of(self.filename)
  if d then return d:get_text(1, 1, math.huge, math.huge) end
  local f = io.open(self.filename, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return s
end
function LView:edit_doc()
  self.doc = self.doc or doc_of(self.filename) or core.open_doc(self.filename)
  return self.doc
end
function LView:reload()
  local src = self:source()
  self.src = src
  if not src then self.err = "can't read " .. self.filename; return end
  self.err = nil
  self.t = L.parse(src)
  self.missing, self.long = L.check(self.t)
  self.miss_at, self.long_at = {}, {}
  for _, m in ipairs(self.missing) do self.miss_at[m[1] .. "\0" .. m[2]] = true end
  for _, m in ipairs(self.long) do self.long_at[m[1] .. "\0" .. m[2]] = m[3] end
  if self.sel and not self.t.rows[self.sel] then self.sel = nil end
  core.redraw = true
end
function LView:changed() self:reload(); self.dirty = self.doc and self.doc:is_dirty() or false end
function LView:commit()                            -- the table, written again (one undo step)
  local text = L.encode(self.t)
  local doc = self:edit_doc()
  if doc:get_text(1, 1, math.huge, math.huge) == text then return end
  doc:remove(1, 1, math.huge, math.huge)
  doc:insert(1, 1, text)
  self:changed()
end
function LView:save() self:edit_doc():save(); self.dirty = false; self:flash("Saved") end

-- edits ---------------------------------------------------------------------
function LView:set_text(key, lang, text)
  local e = self.t.rows[key]
  if not e then return end
  e[lang] = text ~= "" and text or nil
  self:commit()
end
function LView:add_key(key)
  key = tostring(key or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if key == "" then
    local i = 1
    repeat key = "key" .. i; i = i + 1 until not self.t.rows[key]
  end
  if self.t.rows[key] then self.sel = key; return self:flash("there's a " .. key .. " already") end
  local at = #self.t.keys + 1
  for i, k in ipairs(self.t.keys) do if k == self.sel then at = i + 1 end end
  table.insert(self.t.keys, at, key)
  self.t.rows[key] = {}
  self.sel = key
  self:commit()
  return key
end
function LView:rename_key(old, new)
  new = tostring(new or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if new == "" or new == old then return end
  if self.t.rows[new] then return self:flash("there's a " .. new .. " already", true) end
  for i, k in ipairs(self.t.keys) do if k == old then self.t.keys[i] = new end end
  self.t.rows[new], self.t.rows[old] = self.t.rows[old], nil
  self.sel = new
  self:commit()
end
function LView:delete_key(key)
  for i, k in ipairs(self.t.keys) do if k == key then table.remove(self.t.keys, i) break end end
  self.t.rows[key] = nil
  self.sel = nil
  self:commit()
end
-- the plural forms of a key: key|one, key|other... (every form any language needs)
function LView:add_plurals(key)
  local base = key:match("^(.-)|%a+$") or key
  local need, seen = {}, {}
  for _, l in ipairs(self.t.langs) do
    for _, c in ipairs(L.categories(l)) do if not seen[c] then seen[c] = true; need[#need + 1] = c end end
  end
  local order = {}
  for _, c in ipairs(L.CATEGORIES) do if seen[c] then order[#order + 1] = c end end
  local at = #self.t.keys + 1
  for i, k in ipairs(self.t.keys) do if k == key then at = i end end
  local old = self.t.rows[base]
  if old and base == key then                      -- (the key itself becomes key|other)
    table.remove(self.t.keys, at)
    self.t.rows[base] = nil
  else at = at + 1 end
  for _, c in ipairs(order) do
    local k = base .. "|" .. c
    if not self.t.rows[k] then
      table.insert(self.t.keys, at, k)
      self.t.rows[k] = (c == "other" and old) and old or {}
      at = at + 1
    end
  end
  self.sel = base .. "|other"
  self:commit()
end
function LView:add_language(code)
  code = tostring(code or ""):lower():gsub("[^%w%-_]", "")
  if code == "" then return end
  for _, l in ipairs(self.t.langs) do if l == code then return self:flash("there's " .. code .. " already") end end
  self.t.langs[#self.t.langs + 1] = code
  self:commit()
end
function LView:remove_language(code)
  for i, l in ipairs(self.t.langs) do if l == code then table.remove(self.t.langs, i) end end
  for _, e in pairs(self.t.rows) do e[code] = nil end
  self:commit()
end
local function read_file(p) local f = io.open(p, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end
local function write_file(p, s) local f = io.open(p, "wb"); if not f then return false end; f:write(s); f:close(); return true end
function LView:import(path)                        -- a .po (one language) or a .csv / .loc (its columns): merged in
  local text = read_file(path)
  if not text then return self:flash("can't read " .. path, true) end
  if path:lower():match("%.po$") then
    local n, lang = L.po_import(self.t, text, path:match("%.([%w%-_]+)%.po$"))
    self:commit()
    return self:flash("imported " .. n .. " texts in " .. lang)
  end
  local o, n = L.parse(text), 0
  for _, l in ipairs(o.langs) do
    local has = false
    for _, m in ipairs(self.t.langs) do if m == l then has = true end end
    if not has then self.t.langs[#self.t.langs + 1] = l end
  end
  for _, k in ipairs(o.keys) do
    if not self.t.rows[k] then self.t.rows[k] = {}; self.t.keys[#self.t.keys + 1] = k end
    for l, v in pairs(o.rows[k]) do self.t.rows[k][l] = v; n = n + 1 end
  end
  self:commit()
  self:flash("imported " .. n .. " texts")
end
function LView:export(kind)                        -- beside it: name.csv, or name.<lang>.po for each language
  local stem = self.filename:gsub("%.[^%./\\]*$", "")
  if kind == "csv" then
    local p = stem .. ".csv"
    if not write_file(p, L.encode(self.t)) then return self:flash("can't write " .. p, true) end
    return self:flash("exported " .. base_of(p))
  end
  local n = 0
  for _, l in ipairs(self.t.langs) do
    if write_file(stem .. "." .. l .. ".po", L.po_export(self.t, l)) then n = n + 1 end
  end
  self:flash("exported " .. n .. " .po files")
end
function LView:ask(what, fn, text)
  if text then core.command_view:set_text(text) end
  core.command_view:enter(what, fn, what:find("Import") and common.path_suggest or nil)
end

-- layout ----------------------------------------------------------------------
function LView:rects()
  local x, y, w, h = self.position.x, self.position.y, self.size.x, self.size.y
  local rw = math.floor(math.min(S(300), w * 0.35))
  return { mid = { x, y, w - rw, h }, right = { x + w - rw, y, rw, h } }
end
function LView:visible_keys()
  local out, f = {}, self.filter:lower()
  for _, k in ipairs(self.t.keys) do
    local hit = f == "" or k:lower():find(f, 1, true)
    if not hit then for _, v in pairs(self.t.rows[k]) do if tostring(v):lower():find(f, 1, true) then hit = true break end end end
    if hit then out[#out + 1] = k end
  end
  return out
end
function LView:grid_geom()
  local r = self:rects().mid
  local pad, rh = S(10), style.font:get_height() + S(10)
  local kw = math.floor(math.min(S(200), r[3] * 0.3))
  local n = math.max(1, #self.t.langs)
  local cw = math.floor((r[3] - pad * 2 - kw) / n)
  return { x = r[1] + pad, y = r[2] + pad, w = r[3] - pad * 2, h = r[4] - pad * 2 - S(24), kw = kw, cw = cw, rh = rh }
end
local function cut(f, s, w)
  s = tostring(s or ""):gsub("\n", " / ")
  if f:get_width(s) <= w then return s end
  while #s > 1 and f:get_width(s .. "...") > w do s = s:sub(1, -2) end
  return s .. "..."
end
function LView:draw_canvas()
  local r = self:rects().mid
  if not self.t then
    renderer.draw_text(style.font, self.err or "...", r[1] + S(16), r[2] + S(16), style.error or style.text)
    return
  end
  local g, f = self:grid_geom(), style.font
  renderer.draw_rect(g.x, g.y, g.w, g.rh, style.background2)
  renderer.draw_text(f, "key", g.x + S(6), g.y + S(5), style.dim)
  for i, l in ipairs(self.t.langs) do
    local x = g.x + g.kw + (i - 1) * g.cw
    local miss = 0
    for _, m in ipairs(self.missing) do if m[2] == l then miss = miss + 1 end end
    renderer.draw_text(f, cut(f, l .. (i == 1 and "  (source)" or "") .. (miss > 0 and ("  " .. miss .. " missing") or ""), g.cw - S(8)),
                       x + S(6), g.y + S(5), i == 1 and style.accent or (miss > 0 and (style.error or style.text) or style.text))
  end
  local keys = self:visible_keys()
  local rows = math.max(1, math.floor((g.h - g.rh) / g.rh))
  self.scroll_y = math.max(0, math.min(self.scroll_y, math.max(0, #keys - rows)))
  core.push_clip_rect(g.x, g.y + g.rh, g.w, g.h - g.rh)
  for i = self.scroll_y + 1, math.min(#keys, self.scroll_y + rows) do
    local k = keys[i]
    local y = g.y + (i - self.scroll_y) * g.rh
    local on = k == self.sel
    if on then renderer.draw_rect(g.x, y, g.w, g.rh, style.selection or style.background3)
    elseif i % 2 == 0 then renderer.draw_rect(g.x, y, g.w, g.rh, { 255, 255, 255, 6 }) end
    local plural = k:match("|(%a+)$")
    renderer.draw_text(f, cut(f, k, g.kw - S(10)), g.x + S(6), y + S(5), (plural and not on) and style.dim or style.text)
    for j, l in ipairs(self.t.langs) do
      local x = g.x + g.kw + (j - 1) * g.cw
      local id = k .. "\0" .. l
      local v = self.t.rows[k][l]
      if self.miss_at[id] then renderer.draw_rect(x + 1, y + 1, g.cw - 2, g.rh - 2, MISSING) end
      if self.long_at[id] then renderer.draw_rect(x + g.cw - S(5), y + S(3), S(3), g.rh - S(6), LONG) end
      if on and l == self.sel_lang then
        local c = style.caret
        renderer.draw_rect(x, y, g.cw, 1, c); renderer.draw_rect(x, y + g.rh - 1, g.cw, 1, c)
      end
      renderer.draw_text(f, cut(f, v or "", g.cw - S(14)), x + S(6), y + S(5), style.text)
    end
  end
  core.pop_clip_rect()
  local line = string.format("%s   %d keys, %d languages, %d missing, %d long   click a cell; the wheel scrolls",
    self:get_name(), #self.t.keys, #self.t.langs, #self.missing, #self.long)
  renderer.draw_text(f, cut(f, line, r[3] - S(20)), r[1] + S(10), r[2] + r[4] - S(22), style.dim)
end
function LView:cell_at(x, y)
  if not self.t then return nil end
  local g = self:grid_geom()
  if x < g.x or x >= g.x + g.w or y < g.y + g.rh or y >= g.y + g.h then return nil end
  local i = self.scroll_y + math.floor((y - g.y) / g.rh)
  local keys = self:visible_keys()
  local k = keys[i]
  if not k then return nil end
  local j = math.floor((x - g.x - g.kw) / g.cw) + 1
  return k, self.t.langs[j]
end

function LView:draw_right(r)
  local ui, t = self.right, self.t
  ui:begin(r[1], r[2], r[3], r[4])
  ui:field("Find", self.filter, function(v) self.filter = v; self.scroll_y = 0 end, { key = "filter", tip = "keys and texts with this in them" })
  ui:buttons({ { "+ Key", function() self:add_key() end }, { "+ Language", function() self:ask("Language code (es, fr, pt-br...)", function(c) self:add_language(c) end) end } })
  local k = self.sel
  if k and t.rows[k] then
    ui:space()
    ui:head("Key")
    local skey = "k:" .. k .. ":"
    ui:field("Name", k, function(v) self:rename_key(k, v) end, { key = skey .. "name" })
    for i, l in ipairs(t.langs) do
      ui:field(l, t.rows[k][l] or "", function(v) self:set_text(k, l, v) end,
               { key = skey .. l, tip = i == 1 and "the source: the others translate it; {n} {name}: filled in" or nil })
    end
    local plural = k:match("|(%a+)$")
    if plural then
      ui:text("A plural form: " .. plural .. "  (w:tr(\"" .. k:gsub("|%a+$", "") .. "\", n))", style.dim)
      local per = {}
      for _, l in ipairs(t.langs) do per[#per + 1] = l .. ": " .. table.concat(L.categories(l), " ") end
      ui:text(table.concat(per, "   "), style.dim)
    end
    ui:buttons({ { plural and "Plural forms" or "Make plural", function() self:add_plurals(k) end }, { "Delete", function() self:delete_key(k) end } })
  end
  ui:space()
  ui:head("Languages")
  for i, l in ipairs(t.langs) do
    local miss = 0
    for _, m in ipairs(self.missing) do if m[2] == l then miss = miss + 1 end end
    ui:label(l .. (i == 1 and " (source)" or ""), miss > 0 and (miss .. " missing") or "complete")
  end
  if #t.langs > 1 then
    ui:buttons({ { "Remove " .. t.langs[#t.langs], function() self:remove_language(t.langs[#t.langs]) end } })
  end
  ui:space()
  ui:head("Files")
  ui:buttons({ { "Import...", function() self:ask("Import (.po or .csv)", function(p) self:import(p) end) end },
               { "Export .po", function() self:export("po") end }, { "Export .csv", function() self:export("csv") end } })
  ui:buttons({ { self.dirty and "Save  CTRL+S" or "Saved", function() self:save() end, accent = self.dirty } })
  if #self.long > 0 then
    ui:space()
    ui:head("Long (may not fit)")
    for i = 1, math.min(8, #self.long) do
      local m = self.long[i]
      ui:label(m[1] .. " (" .. m[2] .. ")", string.format("x%.1f", m[3]))
    end
  end
  if #t.errors > 0 then
    ui:space()
    ui:head("Problems")
    for _, e in ipairs(t.errors) do ui:text("row " .. e[1] .. ": " .. e[2], style.error or style.text) end
  end
  ui:finish()
end
function LView:draw_overlay()
  if not self.t then return end
  self:draw_right(self:rects().right)
end
function LView:draw_background_color() return style.background end

function LView:on_mouse_pressed(button, x, y, clicks)
  if self.right:pressed(button, x, y, clicks) then return true end
  local k, l = self:cell_at(x, y)
  if k then
    require("plugins.canvas.ui").commit_edit()
    self.sel, self.sel_lang = k, l
    core.redraw = true
    return true
  end
  return true
end
function LView:on_mouse_moved(x, y) self.right:moved(x, y) end
function LView:on_mouse_released(button) self.right:released(button) end
function LView:on_mouse_wheel(dy)
  if self.right:wheel(dy) then return true end
  self.scroll_y = math.max(0, self.scroll_y - (dy > 0 and 3 or -3))
  core.redraw = true
  return true
end

function LView:edit_text()
  local node = core.root_view.root_node:get_node_for_view(self)
  if node then require("plugins.tabflip").flip(node, self) end
end
function LView:menu_items()
  local DIV = require("plugins.contextmenu").DIVIDER
  return {
    { text = "Add key", command = function() self:add_key() end },
    { text = "Add language...", command = function() self:ask("Language code (es, fr, pt-br...)", function(c) self:add_language(c) end) end },
    DIV,
    { text = "Import .po / .csv...", command = function() self:ask("Import (.po or .csv)", function(p) self:import(p) end) end },
    { text = "Export .po (each language)", command = function() self:export("po") end },
    { text = "Export .csv", command = function() self:export("csv") end },
    DIV,
    { text = "Save", info = "CTRL+S", command = function() self:save() end },
    { text = "Edit as text", command = function() self:edit_text() end, tags = "source;code;flip" },
    { text = "Undo", info = "CTRL+Z", command = function() self:edit_doc():undo(); self:changed() end },
    { text = "Redo", info = "CTRL+Y", command = function() self:edit_doc():redo(); self:changed() end },
  }
end

local function active() return core.active_view and core.active_view:is(LView) and not require("plugins.canvas.ui").editing end
command.add(active, {
  ["localization:edit-as-text"] = function() core.active_view:edit_text() end,
  ["localization:undo"] = function() local v = core.active_view; v:edit_doc():undo(); v:changed() end,
  ["localization:redo"] = function() local v = core.active_view; v:edit_doc():redo(); v:changed() end,
})
if not package.loaded["localization.keys"] then
  package.loaded["localization.keys"] = true
  keymap.add { ["ctrl+z"] = "localization:undo", ["ctrl+y"] = "localization:redo", ["ctrl+shift+z"] = "localization:redo" }
end

local next_check = 0
function LView:update()
  LView.super.update(self)
  local now = system.get_time()
  if now < (self.next_check or 0) then return end
  self.next_check = now + 0.25
  local src = self:source()
  if src ~= self.src then self:reload() end
  self.dirty = self.doc ~= nil and self.doc:is_dirty() or false
  if now >= next_check then
    next_check = now + 0.5
    if P.changed("files") then P.open_with(P.read("files") or {}, LView) end
  end
end

local function exts()
  local set = {}
  for _, e in ipairs(P.read("files") or {}) do if type(e) == "string" then set[(e:lower():gsub("^%.", ""))] = true end end
  return set
end
require("plugins.tabflip").register {
  key = "localization",
  name = "localization",
  text = function(view)
    local fn = view:is(DocView) and view.doc and view.doc.filename
    local e = fn and fn:match("%.([^%./\\]+)$")
    return e ~= nil and exts()[e:lower()] == true
  end,
  alt = function(view) return view:is(LView) end,
  to_alt = function(view)
    local v = LView({ filename = system.absolute_path(view.doc.filename) or view.doc.filename })
    v.doc = view.doc
    v:reload()
    return v
  end,
  to_text = function(view) return DocView(view.doc or core.open_doc(view.filename)) end,
  icon = function(x, y, s, c)                      -- a grid of cells
    local t = math.max(1, math.floor(s / 7))
    for i = 0, 2 do renderer.draw_rect(x, y + math.floor(s * i / 2.2), s, t, c) end
    for i = 0, 2 do renderer.draw_rect(x + math.floor(s * i / 2.2), y, t, s, c) end
  end,
  tip = "Show as a table",
  menu = "Toggle table / text",
}

P.open_with(P.read("files") or {}, LView)
return LView
