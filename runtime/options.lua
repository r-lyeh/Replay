-- options.lua - a game's options menu (settings screen), in the style of
-- Lyra's (UE5): an .options file of assets/ (plugins/options edits it) says
-- what's in it; the game shows it with a node and a system, keyboard and
-- gamepad friendly. One file for both: the editor's tab previews it with the
-- same code.
--
-- The file (Lua data), two levels at most: tabs, then sections; or sections
-- only (no tab bar):
--   return {
--     title = "Options",
--     tabs = {
--       { name = "Audio", sections = {
--         { name = "Volume", items = {
--           { id = "sfx", type = "slider", label = "Sound effects", default = 1, min = 0, max = 1,
--             step = 0.05, deadzone = 0.02, percent = true, bus = "sfx", tip = "..." },
--         } },
--       } },
--     },
--   }
--   (or: return { title = "Options", sections = { { name = "Volume", items = { ... } } } })
-- An item: id (its value's name), type, label, default, tip (a line shown
-- under the list while it's focused), and by type:
--   bool     default true / false
--   enum     values = { "Low", "High" }, default = "High"
--   slider   min, max, step, deadzone (near min, max, or 0 when 0 is in
--            between, it snaps there), percent = true (shown 0..100%), fmt = "%.1f"
--   text     maxlen, password = true (shown as *)
--   key      action = "jump" (a key binding: Enter, then the key or pad
--            button; Backspace: the game's own; applied with w:bind, saved
--            for this machine; default "": the game's /config actions)
--   button   action = "restart" (an event for the game), text = "Go" (its
--            button); action = "close" closes the menu, "reset" / "apply" /
--            "discard" do what those do
-- look = { font = "sans-bold", font_size = 15, tab_shear = 0.25 } (top level,
-- optional): the menu in that TrueType font (tab_shear: the tab in view
-- slanted, a cursive) ("sans", "sans-bold", "mono" built in, or a .ttf of
-- assets/; its rows as tall as the font wants), and any of M.LOOK's colours
-- and sizes; a game's own look (o:draw's) goes over it. None: the 8 x 8 font.
-- window = "fullscreen" on a bool: the game's window, full screen when applied
-- (host_window; in the editor, Stop undoes it).
-- bus = "sfx" | "music" | "voice" on a slider: that sound bus's volume, set
-- as it moves (live = true: any item reports its changes as it moves, not
-- only on Apply). Reset (defaults), Apply, Discard: the three buttons at the
-- bottom. Applied values are saved (w:savegame: saves/<file's name>.sav, this
-- machine's) and read back next time.
--
-- In a game (games/hop shows it):
--   objects/hud/menu: options = { file = "settings.options" }, xform, (a layer)
--   systems/menu: local o = w:options(n.c.options.file); local st = o:state(w, n)
--     o:open(w, st) / o:close(w, st) / st.open
--     o:key(w, st, key, down) -> true when the menu took it (on_key)
--     o:update(w, st, dt, n)  (held keys repeat; with n: the mouse, w.mouse, while it's open:
--                             hover, click, drag a slider) ; o:draw(w, st, n [, look]) (nodes under /entities)
--     for _, e in ipairs(o:events(st)) do ... end   { "apply", changed = { ids } } { "button", action }
--       { "change", id, value } (live items) { "reset" } { "discard" } { "open" } { "close" }
--     o:value(st, id) -> the applied value
-- Keys: arrows / WASD / dpad / left stick move; left / right change a value
-- (Shift: finely); Enter / Space / pad A press (a text box: type, Enter
-- keeps, Escape drops); Q / E / Tab / pad shoulders (LB / RB): tabs;
-- Escape / pad B / Home / Start: back (with changes not applied: Apply /
-- Discard / Cancel); pad Y applies, pad X resets. In the editor, a game with
-- a menu takes a short ESC (its menu on / off); a long one stops.
local M = {}

local TYPES = { bool = "bool", check = "bool", enum = "enum", list = "enum", slider = "slider", float = "slider",
                text = "text", button = "button", key = "key", binding = "key", language = "enum" }
M.TYPES = { "bool", "enum", "slider", "text", "key", "language", "button" }
-- (a language item: a list of the game's languages, runtime/loc.lua: w:languages(); applied with w:language)
M.LANG_NAMES = { en = "English", es = "Espanol", fr = "Francais", de = "Deutsch", it = "Italiano", pt = "Portugues",
                 ["pt-br"] = "Portugues (Brasil)", ca = "Catala", nl = "Nederlands", sv = "Svenska", pl = "Polski",
                 ru = "Russkiy", uk = "Ukrainska", ja = "Nihongo", zh = "Zhongwen", ko = "Hangugeo", ar = "Arabiya",
                 tr = "Turkce", cs = "Cestina", ro = "Romana", eu = "Euskara", gl = "Galego" }
M.WINDOW = { "fullscreen" }                         -- (a bool's window = "fullscreen": the game's window, host_window)
M.BUSES = { "sfx", "music", "voice" }

local function num(v, d) v = tonumber(v); if v == nil or v ~= v then return d end; return v end
local function copy(t) local o = {}; for k, v in pairs(t) do o[k] = v end; return o end

-- a raw table (the file's) -> a checked one: o = { title, flat, tabs = { { name,
-- sections = { { name, items } } } }, list (items in order), by_id }, problems
function M.check(t)
  local errs = {}
  if type(t) ~= "table" then t = {}; errs[#errs + 1] = "not a table" end
  local o = { title = type(t.title) == "string" and t.title or "Options", save = type(t.save) == "string" and t.save or nil,
              tabs = {}, list = {}, by_id = {} }
  if type(t.look) == "table" then                  -- (its look: plain values only)
    o.look = {}
    for k, v in pairs(t.look) do
      if type(k) == "string" and (type(v) == "string" or type(v) == "number" or type(v) == "boolean") then o.look[k] = v
      elseif type(k) == "string" and type(v) == "table" then o.look[k] = copy(v) end
    end
  end
  local raw_tabs = t.tabs
  if type(raw_tabs) ~= "table" then o.flat = true; raw_tabs = { { name = "", sections = t.sections or {} } } end
  for ti, rt in ipairs(raw_tabs) do
    if type(rt) ~= "table" then rt = {} end
    local tab = { name = tostring(rt.name or ("Tab " .. ti)), sections = {} }
    local secs = rt.sections
    if type(secs) ~= "table" then secs = {} end
    if type(rt.items) == "table" then secs = { { name = "", items = rt.items } } end   -- (items right in a tab: one section, unnamed)
    for _, rs in ipairs(secs) do
      if type(rs) ~= "table" then rs = {} end
      local sec = { name = tostring(rs.name or ""), items = {} }
      for _, ri in ipairs(type(rs.items) == "table" and rs.items or {}) do
        if type(ri) == "table" then
          local it = copy(ri)
          it.type = TYPES[tostring(ri.type or "")] or (ri.values and "enum") or "bool"
          if ri.type == "language" then it.language = true end
          if ri.type and not TYPES[tostring(ri.type)] then errs[#errs + 1] = ("%s: no type %s"):format(tostring(ri.id), tostring(ri.type)) end
          it.id = tostring(ri.id or ("item" .. (#o.list + 1)))
          if o.by_id[it.id] then errs[#errs + 1] = "two items " .. it.id; it.id = it.id .. "_" .. (#o.list + 1) end
          it.label = tostring(ri.label or it.id)
          if it.type == "bool" then it.default = ri.default == true
          elseif it.type == "enum" then
            local vals = {}
            for _, v in ipairs(type(ri.values) == "table" and ri.values or {}) do vals[#vals + 1] = tostring(v) end
            if #vals == 0 then vals = { "-" } end
            it.values = vals
            local d = ri.default ~= nil and tostring(ri.default) or vals[1]
            local found = false
            for _, v in ipairs(vals) do if v == d then found = true end end
            it.default = found and d or vals[1]
          elseif it.type == "slider" then
            it.min, it.max = num(ri.min, 0), num(ri.max, 1)
            if it.max < it.min then it.min, it.max = it.max, it.min end
            it.step = math.max(0, num(ri.step, (it.max - it.min) / 20))
            it.deadzone = math.max(0, num(ri.deadzone, 0))
            it.default = M.snap(it, num(ri.default, it.min))
          elseif it.type == "text" then
            it.maxlen = math.max(1, math.floor(num(ri.maxlen, 24)))
            it.default = tostring(ri.default or ""):sub(1, it.maxlen)
          elseif it.type == "key" then                 -- (a key binding: "" the game's own keys, else "space,pad a")
            it.action = tostring(ri.action or it.id)
            it.default = type(ri.default) == "string" and ri.default or ""
          else
            it.action = tostring(ri.action or it.id)
            it.default = nil
          end
          if it.bus ~= nil and it.live == nil then it.live = true end
          sec.items[#sec.items + 1] = it
          o.list[#o.list + 1] = it
          o.by_id[it.id] = it
        end
      end
      tab.sections[#tab.sections + 1] = sec
    end
    o.tabs[#o.tabs + 1] = tab
  end
  if #o.tabs == 0 then o.tabs[1] = { name = "", sections = {} }; o.flat = true end
  return o, errs
end

-- a slider's value, as it may be: in range, on a step, snapped in a dead zone
function M.snap(it, v)
  v = math.max(it.min, math.min(it.max, num(v, it.min)))
  if it.step and it.step > 0 then
    v = it.min + math.floor((v - it.min) / it.step + 0.5) * it.step
    v = math.max(it.min, math.min(it.max, v))
    v = math.floor(v * 1e6 + 0.5) / 1e6            -- (0.1 * 3 is 0.3)
  end
  local dz = it.deadzone or 0
  if dz > 0 then
    if v - it.min <= dz then v = it.min elseif it.max - v <= dz then v = it.max
    elseif it.min < 0 and it.max > 0 and math.abs(v) <= dz then v = 0 end
  end
  return v
end

-- a value as it shows
function M.show(it, v, typing, game)               -- (game: a key item's game keys, shown while it's "")
  if it.type == "key" then
    if typing then return "press a key..." end
    local s = (v ~= nil and v ~= "") and v or (game or "")
    return s ~= "" and s:gsub(",", ", ") or "-"
  end
  if it.type == "bool" then return v and "On" or "Off" end
  if it.type == "enum" then
    if it.language then return M.LANG_NAMES[tostring(v)] or tostring(v) end
    return it.labels and it.labels[v] or tostring(v)
  end
  if it.type == "slider" then
    v = num(v, it.min)
    if it.fmt then return string.format(it.fmt, v) end
    if it.percent then
      local span = it.max - it.min
      return string.format("%d%%", math.floor((span > 0 and (v - it.min) / span or 0) * 100 + 0.5))
    end
    if (it.step or 0) >= 1 and math.floor(v) == v then return string.format("%d", v) end
    return string.format("%.2f", v)
  end
  if it.type == "text" then
    local s = tostring(v or "")
    if it.password then s = string.rep("*", #s) end
    return s .. (typing and "_" or "")
  end
  return it.text or "Go"
end

-- the file's text, written back (plugins/options): its keys in a fixed order
local ITEM_KEYS = { "id", "type", "label", "default", "values", "min", "max", "step", "deadzone", "percent", "fmt",
                    "maxlen", "password", "action", "text", "bus", "live", "tip" }
local function lua_value(v)
  if type(v) == "string" then return string.format("%q", v):gsub("\\\n", "\\n") end
  if type(v) == "number" then
    if math.floor(v) == v and math.abs(v) < 1e15 then return string.format("%d", v) end
    return (string.format("%.6g", v))
  end
  if type(v) == "table" then
    local p = {}
    for _, x in ipairs(v) do p[#p + 1] = lua_value(x) end
    return "{ " .. table.concat(p, ", ") .. " }"
  end
  return tostring(v)
end
local function item_text(it)
  local p, seen = {}, {}
  for _, k in ipairs(ITEM_KEYS) do
    seen[k] = true
    if it[k] ~= nil then p[#p + 1] = k .. " = " .. lua_value(it[k]) end
  end
  local extra = {}
  for k in pairs(it) do if not seen[k] and type(k) == "string" and k:match("^[%a_][%w_]*$") then extra[#extra + 1] = k end end
  table.sort(extra)
  for _, k in ipairs(extra) do p[#p + 1] = k .. " = " .. lua_value(it[k]) end
  return "{ " .. table.concat(p, ", ") .. " }"
end
-- t: the raw form ({ title, tabs | sections, ... }) -> the file's text
function M.encode(t)
  local out = { "-- an options menu (plugins/options; runtime/options.lua: how a game shows it)", "return {" }
  local function add(s) out[#out + 1] = s end
  add("  title = " .. lua_value(t.title or "Options") .. ",")
  if t.save then add("  save = " .. lua_value(t.save) .. ",") end
  if type(t.look) == "table" and next(t.look) then add("  look = " .. lua_value(t.look) .. ",") end
  local function sections(list, ind)
    for _, s in ipairs(list or {}) do
      add(ind .. "{ name = " .. lua_value(s.name or "") .. ", items = {")
      for _, it in ipairs(s.items or {}) do add(ind .. "  " .. item_text(it) .. ",") end
      add(ind .. "} },")
    end
  end
  if t.tabs then
    add("  tabs = {")
    for _, tab in ipairs(t.tabs) do
      add("    { name = " .. lua_value(tab.name or "") .. ", sections = {")
      sections(tab.sections, "      ")
      add("    } },")
    end
    add("  },")
  else
    add("  sections = {")
    sections(t.sections, "    ")
    add("  },")
  end
  add("}")
  return table.concat(out, "\n") .. "\n"
end

-- text -> the raw table (data only: nothing runs with any power) | nil, err
function M.decode(text, name)
  if type(text) ~= "string" then return nil, "no text" end
  if text:match("^%s*$") then return {} end
  local ls, sf = rawget(_G, "loadstring"), rawget(_G, "setfenv")   -- (rawget: Lite's globals are strict)
  local fn, err = (ls or load)(text, "=" .. (name or "options"), "t", {})
  if fn and sf then sf(fn, {}) end
  if not fn then return nil, err end
  local ok, v = pcall(fn)
  if not ok then return nil, v end
  if type(v) ~= "table" then return nil, "not a table" end
  return v
end

-- state ------------------------------------------------------------------
local O = {}
O.__index = O

local function defaults(o)
  local v = {}
  for _, it in ipairs(o.list) do if it.default ~= nil then v[it.id] = it.default end end
  return v
end
local function valid(it, v)                         -- a saved value that still fits the item (else nil)
  if it.type == "bool" then if type(v) == "boolean" then return v end; return nil end
  if it.type == "enum" then for _, x in ipairs(it.values) do if x == v then return v end end; return nil end
  if it.type == "slider" then return type(v) == "number" and M.snap(it, v) or nil end
  if it.type == "text" then return type(v) == "string" and v:sub(1, it.maxlen) or nil end
  if it.type == "key" then return type(v) == "string" and v or nil end
end
local function save_name(o) return o.save or (o.name or "options"):gsub("%.%w+$", ""):gsub("[^%w_%-]", "_") end

-- the menu's state: plain data, kept in the world (/entities/options_<node's
-- name>: never written to disk), so it saves, rewinds and travels
function O:state(w, node)
  local name = type(node) == "table" and (node.path or ""):match("[^/]*$") or tostring(node or "menu")
  local path = "/entities/options_" .. (name ~= "" and name or "menu")
  if not w:node("/entities") then w:spawn("/entities", {}) end
  local n = w:node(path)
  if not n then n = w:spawn(path, { options_state = {} }) end
  if type(n.c.options_state) ~= "table" then n.c.options_state = {} end
  local st = n.c.options_state
  st.path = path
  st.tab, st.focus, st.col, st.scroll = st.tab or 1, st.focus or 1, st.col or 2, st.scroll or 0
  st.events = st.events or {}
  w.wants_escape = true                            -- (the viewer: a short ESC is the game's, for this menu; a long one stops)
  if not st.values then self:load(w, st) end
  return st
end
local function split_keys(s)
  local out = {}
  for raw in tostring(s or ""):gmatch("[^,]+") do local k = raw:gsub("^%s+", ""):gsub("%s+$", ""); if k ~= "" then out[#out + 1] = k end end
  return out
end
local function game_keys(w, action)                -- the game's own keys for an action (/config actions)
  local cfg = w.node and w:node("/config")
  local acts = cfg and type(cfg.c.actions) == "table" and cfg.c.actions or {}
  return table.concat(type(acts[action]) == "table" and acts[action] or {}, ",")
end
function O:host(w, st)                             -- the applied values that set things outside the menu: keys, the window
  for _, it in ipairs(self.list) do
    local v = st.values[it.id]
    if it.type == "key" and w.bind then
      if v == "" then w:bind(it.action) else w:bind(it.action, split_keys(v)) end
    elseif it.language and w.language then
      if v and v ~= "-" and v ~= w:language() then w:language(v) end
    elseif it.window == "fullscreen" and rawget(_G, "host_window") then
      rawget(_G, "host_window")({ fullscreen = v == true })
    end
  end
end
function O:load(w, st)                             -- the defaults, then this machine's saved values
  for _, it in ipairs(self.list) do                -- (a language item: the game's languages, the current one)
    if it.language and w.languages then
      local L = w:languages()
      if #L > 0 then it.values, it.default = L, L[1] end
    end
  end
  local v = defaults(self)
  for _, it in ipairs(self.list) do if it.language and w.language then v[it.id] = w:language() end end
  local saved = w.loadgame and w:loadgame(save_name(self))
  if type(saved) == "table" then
    for id, x in pairs(saved) do
      local it = self.by_id[id]
      if it then local ok = valid(it, x); if ok ~= nil then v[id] = ok end end
    end
  end
  st.values, st.edit = v, copy(v)
  st.keys = {}                                     -- (each key item's game keys: shown while it's "")
  for _, it in ipairs(self.list) do if it.type == "key" then st.keys[it.action] = game_keys(w, it.action) end end
  for _, it in ipairs(self.list) do if it.bus then self:live(w, st, it) end end
  if type(saved) == "table" then self:host(w, st) end
end
function O:value(st, id) return st.values and st.values[id] end
function O:dirty(st)
  for _, it in ipairs(self.list) do if it.default ~= nil and st.edit[it.id] ~= st.values[it.id] then return true end end
  return false
end
local function emit(st, e) st.events[#st.events + 1] = e end
function O:events(st) local e = st.events or {}; st.events = {}; return e end

function O:live(w, st, it)                         -- a value as it is being edited: heard now
  if it.bus and w.bus then w:bus(it.bus, st.edit[it.id]) end
end
function O:set(w, st, id, v)                       -- an edit (not applied yet; a live one is heard now)
  local it = self.by_id[id]
  if not it or it.default == nil then return end
  if it.type == "slider" then v = M.snap(it, v) end
  if st.edit[id] == v then return end
  st.edit[id] = v
  if it.live then self:live(w, st, it); emit(st, { "change", id, v }) end
end
function O:apply(w, st)
  local changed = {}
  for _, it in ipairs(self.list) do
    if it.default ~= nil and st.edit[it.id] ~= st.values[it.id] then changed[#changed + 1] = it.id end
  end
  st.values = copy(st.edit)
  if w.savegame then w:savegame(save_name(self), st.values) end
  if #changed > 0 then self:host(w, st) end
  emit(st, { "apply", changed = changed })
  return changed
end
function O:discard(w, st)
  st.edit = copy(st.values)
  for _, it in ipairs(self.list) do if it.live then self:live(w, st, it) end end
  st.typing, st.typed = nil, nil
  emit(st, { "discard" })
end
function O:reset(w, st)                            -- the defaults, to Apply (or Discard)
  st.edit = defaults(self)
  for _, it in ipairs(self.list) do if it.live then self:live(w, st, it) end end
  emit(st, { "reset" })
end
function O:open(w, st)
  if st.open then return end
  st.open, st.confirm, st.typing = true, nil, nil
  st.held = nil
  emit(st, { "open" })
end
function O:close(w, st)
  if not st.open then return end
  st.open, st.confirm, st.typing, st.held = false, nil, nil, nil
  emit(st, { "close" })
end

-- the rows of a tab: { kind = "section", text } | { kind = "item", item, n (its focus index) }
function O:rows(tab)
  local t = self.tabs[tab] or self.tabs[1]
  local rows, n = {}, 0
  for _, s in ipairs(t.sections) do
    if s.name ~= "" then rows[#rows + 1] = { kind = "section", text = s.name } end
    for _, it in ipairs(s.items) do n = n + 1; rows[#rows + 1] = { kind = "item", item = it, n = n } end
  end
  return rows, n
end
function O:focused(st)                             -- the item with the focus | nil (the buttons at the bottom)
  local rows = self:rows(st.tab)
  for _, r in ipairs(rows) do if r.n == st.focus then return r.item end end
end
local FOOT = { "Reset", "Apply", "Discard" }
local CONFIRM = { "Apply", "Discard", "Cancel" }
M.FOOT, M.CONFIRM = FOOT, CONFIRM

local function press_foot(self, w, st, which)
  if st.confirm then
    st.confirm = nil
    if which == "Apply" then self:apply(w, st); self:close(w, st)
    elseif which == "Discard" then self:discard(w, st); self:close(w, st) end
    return
  end
  if which == "Reset" then self:reset(w, st)
  elseif which == "Apply" then self:apply(w, st)
  elseif which == "Discard" then self:discard(w, st) end
end
function O:back(w, st)
  if st.typing then st.edit[st.typing] = st.typed; st.typing, st.typed = nil, nil return end
  if st.confirm then st.confirm = nil return end
  if self:dirty(st) then
    st.confirm = true
    local _, n = self:rows(st.tab)
    st.focus, st.col = n + 1, 1
    return
  end
  self:close(w, st)
end
function O:activate(w, st)                         -- Enter / A on what has the focus
  local _, n = self:rows(st.tab)
  if st.focus > n or st.confirm then return press_foot(self, w, st, (st.confirm and CONFIRM or FOOT)[st.col]) end
  local it = self:focused(st)
  if not it then return end
  if it.type == "bool" then self:set(w, st, it.id, not st.edit[it.id])
  elseif it.type == "enum" then self:change(w, st, 1)
  elseif it.type == "text" then st.typing, st.typed = it.id, st.edit[it.id]
  elseif it.type == "key" then st.capture = it.id    -- (the next key pressed: its key)
  elseif it.type == "button" then
    local a = it.action
    if a == "close" then self:back(w, st)
    elseif a == "reset" or a == "apply" or a == "discard" then press_foot(self, w, st, a:sub(1, 1):upper() .. a:sub(2))
    else emit(st, { "button", a }) end
  end
end
function O:change(w, st, dir, fine)                -- left / right on what has the focus
  local _, n = self:rows(st.tab)
  if st.focus > n or st.confirm then st.col = math.max(1, math.min(3, st.col + dir)) return end
  local it = self:focused(st)
  if not it then return end
  local v = st.edit[it.id]
  if it.type == "bool" then self:set(w, st, it.id, not v)
  elseif it.type == "enum" then
    local i = 1
    for k, x in ipairs(it.values) do if x == v then i = k end end
    i = (i - 1 + dir) % #it.values + 1
    self:set(w, st, it.id, it.values[i])
  elseif it.type == "slider" then
    local step = it.step > 0 and it.step or (it.max - it.min) / 20
    if fine and it.step > 0 then                    -- (finely: a tenth of a step, kept off the step grid)
      local raw = math.max(it.min, math.min(it.max, v + dir * step / 10))
      st.edit[it.id] = math.floor(raw * 1e6 + 0.5) / 1e6
      if it.live then self:live(w, st, it); emit(st, { "change", it.id, st.edit[it.id] }) end
      return
    end
    local nv = M.snap(it, v + dir * step)
    if nv == v and it.deadzone > 0 then nv = M.snap(it, v + dir * (step + it.deadzone)) end   -- (out of a dead zone in one press)
    self:set(w, st, it.id, nv)
  end
end
function O:move(st, dir)                           -- up / down
  local _, n = self:rows(st.tab)
  if st.confirm then return end
  st.focus = math.max(1, math.min(n + 1, st.focus + dir))
end
function O:switch(st, dir)                         -- the tab before / after
  if st.typing or st.confirm or #self.tabs < 2 then return end
  st.tab = (st.tab - 1 + dir) % #self.tabs + 1
  st.focus, st.scroll = 1, 0
end

local UP = { up = true, w = true, ["pad dpup"] = true, ["pad up"] = true }
local DOWN = { down = true, s = true, ["pad dpdown"] = true, ["pad down"] = true }
local LEFT = { left = true, a = true, ["pad dpleft"] = true, ["pad left"] = true }
local RIGHT = { right = true, d = true, ["pad dpright"] = true, ["pad right"] = true }
local OK = { ["return"] = true, space = true, ["keypad enter"] = true, ["pad a"] = true }
local BACK = { escape = true, ["pad b"] = true, backspace = true, ["pad guide"] = true, ["pad back"] = true, ["pad start"] = true }
local PREV = { q = true, ["pad leftshoulder"] = true, ["page up"] = true }
local NEXT = { e = true, ["pad rightshoulder"] = true, ["page down"] = true, tab = true }
local SHIFTED = { ["1"] = "!", ["2"] = "@", ["3"] = "#", ["4"] = "$", ["5"] = "%", ["6"] = "^", ["7"] = "&", ["8"] = "*",
                  ["9"] = "(", ["0"] = ")", ["-"] = "_", ["="] = "+", ["["] = "{", ["]"] = "}", [";"] = ":", ["'"] = "\"",
                  [","] = "<", ["."] = ">", ["/"] = "?", ["\\"] = "|", ["`"] = "~" }
local REPEATS = function(k) return UP[k] or DOWN[k] or LEFT[k] or RIGHT[k] end

local function typed_key(self, w, st, key)         -- a key while typing in a text box
  local it = self.by_id[st.typing]
  local s = tostring(st.edit[st.typing] or "")
  if key == "return" or key == "keypad enter" or key == "pad a" then st.typing, st.typed = nil, nil
    if it and it.live then emit(st, { "change", it.id, s }) end
    return
  end
  if key == "escape" or key == "pad b" then return self:back(w, st) end
  if key == "backspace" then st.edit[st.typing] = s:sub(1, -2) return end
  local ch = key == "space" and " " or (#key == 1 and key) or nil
  if not ch then return end
  if st.shift then ch = SHIFTED[ch] or ch:upper() end
  if it and #s < it.maxlen then st.edit[st.typing] = s .. ch end
end

-- text typed (a host's text input: the editor's preview) into the text box being typed in
function O:type(w, st, text)
  local it = st.typing and self.by_id[st.typing]
  if not it then return false end
  local s = tostring(st.edit[it.id] or "") .. tostring(text):gsub("[%c]", "")
  st.edit[it.id] = s:sub(1, it.maxlen)
  return true
end

-- a key (on_key): true when the menu took it (it's open)
function O:key(w, st, key, down)
  if key == "left shift" or key == "right shift" then st.shift = down or nil end
  if not st.open then return false end
  if not down then
    if st.held and st.held.key == key then st.held = nil end
    return true
  end
  if st.typing then typed_key(self, w, st, key) return true end
  if st.capture then                               -- a key binding: the key pressed (Escape: cancelled; Backspace: the game's)
    local id = st.capture
    st.capture = nil
    if key == "escape" or key == "pad guide" then return true end
    if key == "backspace" then self:set(w, st, id, "") return true end
    self:set(w, st, id, key)
    return true
  end
  local fine = st.shift
  if key == "tab" and st.shift then self:switch(st, -1)
  elseif UP[key] then self:move(st, -1)
  elseif DOWN[key] then self:move(st, 1)
  elseif LEFT[key] then self:change(w, st, -1, fine)
  elseif RIGHT[key] then self:change(w, st, 1, fine)
  elseif OK[key] then self:activate(w, st)
  elseif BACK[key] then self:back(w, st)
  elseif PREV[key] then self:switch(st, -1)
  elseif NEXT[key] then self:switch(st, 1)
  elseif key == "pad y" then press_foot(self, w, st, "Apply")
  elseif key == "pad x" then press_foot(self, w, st, "Reset") end
  if REPEATS(key) then st.held = { key = key, t = 0 } end
  return true
end
function O:update(w, st, dt, node, look)           -- held keys repeat (0.4 s, then every 0.08 s); node: the mouse too
  if node ~= nil then
    w.wants_mouse = st.open or nil                 -- (the viewer: the game area's mouse is the menu's while it's open)
    local m = w.mouse
    if st.open and type(m) == "table" and m.x then
      local x, y, s = 0, 0, 1
      local xf = type(node) == "table" and node.c and node.c.xform
      if type(xf) == "table" then x, y, s = xf.x or 0, xf.y or 0, tonumber(xf.s) or 1 end
      self:mouse(w, st, (m.x - x) / s, (m.y - y) / s, m.left == true and m.inside ~= false, look)
    end
  end
  local h = st.held
  if not (st.open and h) then return end
  h.t = h.t + (dt or 0)
  if h.t >= 0.4 then
    h.t = h.t - 0.08
    local k = h.key
    if UP[k] then self:move(st, -1) elseif DOWN[k] then self:move(st, 1)
    elseif LEFT[k] then self:change(w, st, -1, st.shift) elseif RIGHT[k] then self:change(w, st, 1, st.shift) end
  end
end

-- the mouse, in the menu's space (its centre 0, 0): hovering a row focuses it,
-- a press presses it (o:click), a slider follows a held drag
function O:mouse(w, st, x, y, down, look)
  if not st.open then st.mdown = nil return end
  local moved = x ~= st.mx or y ~= st.my
  st.mx, st.my = x, y
  if down and not st.mdown then                    -- (pressed)
    st.mdown = true
    self:click(w, st, x, y, look)
    local it = self:focused(st)
    if it and it.type == "slider" and not st.confirm then st.drag = it.id end
    return
  end
  if not down then st.mdown, st.drag = nil, nil end
  if st.drag and moved then                        -- (a slider held: where the mouse is)
    local _, hits, L = self:layout(st, look)
    local it = self.by_id[st.drag]
    for _, h in ipairs(hits) do
      if h.n == st.focus and it then
        local bw = h.vw - 7 * 8 * L.size
        local f = math.max(0, math.min(1, (x - h.vx) / math.max(1, bw)))
        self:set(w, st, it.id, it.min + f * (it.max - it.min))
      end
    end
    return
  end
  if moved and not down and not st.typing and not st.capture and not st.confirm then   -- (hovering: the focus follows)
    local _, hits = self:layout(st, look)
    for _, h in ipairs(hits) do
      if h.n and x >= h[1] and x < h[1] + h[3] and y >= h[2] and y < h[2] + h[4] then st.focus = h.n end
    end
  end
end

-- the look ---------------------------------------------------------------
M.LOOK = {
  w = 440, h = 240, pad = 10, row = 14, size = 1,
  panel = { 18, 20, 32, 235 }, edge = { 90, 96, 128, 255 }, text = { 225, 228, 240, 255 }, dim = { 130, 136, 160, 255 },
  accent = { 255, 196, 72, 255 }, focus = { 52, 62, 98, 255 }, bar = { 60, 64, 84, 255 }, section = { 150, 170, 230, 255 },
}
local function look_of(own, look)                -- M.LOOK, then the file's look, then the game's
  local l = copy(M.LOOK)
  for _, x in ipairs({ own, look }) do if type(x) == "table" then for k, v in pairs(x) do l[k] = v end end end
  if l.font then                                   -- (a TrueType font: its rows as tall as it is, unless given)
    l.font_size = tonumber(l.font_size) or 14
    if not (type(look) == "table" and look.row) and not (type(own) == "table" and own.row) then l.row = math.floor(l.font_size * 1.35 + 0.5) end
  end
  return l
end
local function fit(s, chars) s = tostring(s); if #s > chars then return s:sub(1, math.max(0, chars - 1)) .. "~" end; return s end

-- what to draw, top left at (-w/2, -h/2) of the menu's centre: { "rect", x, y,
-- w, h, color [, fill = false] } / { "text", x, y, s, color, size }, and where
-- the mouse can press: hits = { { x, y, w, h, tab = i | n = focus | foot = col } }.
-- The game's nodes (o:draw) and the editor's preview draw the same list.
function O:layout(st, look)
  local L = look_of(self.look, look)
  local ops, hits = {}, {}
  local cw, ch = 8 * L.size, 8 * L.size
  if L.font then cw, ch = math.floor(L.font_size * 0.58 + 0.5), L.font_size end   -- (a character's room: about as wide as a TrueType one)
  local x0, y0, W, H, pad = -L.w / 2, -L.h / 2, L.w, L.h, L.pad
  local function rect(x, y, w, h, c, fill) ops[#ops + 1] = { "rect", x, y, w, h, c, fill = fill ~= false } end
  local function text(x, y, s, c) ops[#ops + 1] = { "text", x, y, s, c, L.size, font = L.font, font_size = L.font_size } end
  rect(x0, y0, W, H, L.panel)
  rect(x0, y0, W, H, L.edge, false)
  local tx = x0 + pad
  text(tx, y0 + pad, self.title, L.accent)
  tx = tx + (#self.title + 3) * cw
  if not self.flat then                            -- the tabs
    for i, t in ipairs(self.tabs) do
      local tw = #t.name * cw
      local on = i == st.tab
      text(tx, y0 + pad, t.name, on and L.text or L.dim)
      if on and L.tab_shear and L.font then ops[#ops].shear = L.tab_shear end   -- (the tab in view: slanted, a TrueType look's tab_shear)
      if on then rect(tx, y0 + pad + ch + 2, tw, 2, L.accent) end
      hits[#hits + 1] = { tx - 4, y0 + pad - 3, tw + 8, ch + 8, tab = i }
      tx = tx + tw + 2 * cw
    end
  end
  local top = y0 + pad + ch + 8
  rect(x0 + pad, top, W - 2 * pad, 1, L.bar)
  local foot_y = y0 + H - pad - ch - 4
  local tip_y = foot_y - L.row
  local rows, n = self:rows(st.tab)
  local first_y = top + 6
  local visible = math.max(1, math.floor((tip_y - 4 - first_y) / L.row))
  local frow                                       -- (the focused row: kept in view)
  for i, r in ipairs(rows) do if r.n == st.focus then frow = i end end
  if frow then
    if frow - 1 < st.scroll then st.scroll = math.max(0, frow - 1 - (rows[frow - 1] and rows[frow - 1].kind == "section" and 1 or 0)) end
    if frow > st.scroll + visible then st.scroll = frow - visible end
  end
  st.scroll = math.max(0, math.min(st.scroll, math.max(0, #rows - visible)))
  local vx = x0 + math.floor(W * 0.55)
  local vw = x0 + W - pad - vx
  local label_chars = math.floor((vx - x0 - pad - 2 * cw) / cw)
  for i = st.scroll + 1, math.min(#rows, st.scroll + visible) do
    local r = rows[i]
    local y = first_y + (i - st.scroll - 1) * L.row
    local ty = y + math.floor((L.row - ch) / 2)
    if r.kind == "section" then
      text(x0 + pad, ty, fit(r.text, label_chars + 2), L.section)
    else
      local it = r.item
      local on = r.n == st.focus and not st.confirm
      if on then rect(x0 + pad - 4, y, W - 2 * pad + 8, L.row, L.focus) end
      hits[#hits + 1] = { x0 + pad - 4, y, W - 2 * pad + 8, L.row, n = r.n, vx = vx, vw = vw }
      local changed = it.default ~= nil and st.edit[it.id] ~= st.values[it.id]
      if changed then text(x0 + pad, ty, "*", L.accent) end
      text(x0 + pad + 2 * cw, ty, fit(it.label, label_chars), on and L.text or L.dim)
      local v = st.edit[it.id]
      if it.type == "slider" then
        local nw = 6 * cw
        local bw = vw - nw - cw
        local span = it.max - it.min
        local f = span > 0 and (num(v, it.min) - it.min) / span or 0
        local by = y + math.floor(L.row / 2) - 2
        rect(vx, by, bw, 4, L.bar)
        if f > 0 then rect(vx, by, math.max(1, math.floor(bw * f)), 4, on and L.accent or L.dim) end
        rect(vx + math.floor((bw - 4) * f), by - 3, 4, 10, on and L.text or L.dim)
        local s = M.show(it, v)
        text(x0 + W - pad - #s * cw, ty, s, on and L.text or L.dim)
      elseif it.type == "text" then
        local typing = st.typing == it.id
        rect(vx, y + 1, vw, L.row - 2, typing and L.accent or (on and L.dim or L.bar), false)
        local s = M.show(it, v, typing)
        local room = math.floor((vw - cw) / cw)
        if #s > room then s = typing and s:sub(-room) or fit(s, room) end
        text(vx + cw / 2, ty, s, (typing or on) and L.text or L.dim)
      elseif it.type == "key" then
        local cap = st.capture == it.id
        local s = M.show(it, v, cap, st.keys and st.keys[it.action])
        text(vx, ty, fit(s, math.floor(vw / cw)), cap and L.accent or (on and L.text or L.dim))
      elseif it.type == "button" then
        local s = "[ " .. M.show(it, v) .. " ]"
        text(vx, ty, fit(s, math.floor(vw / cw)), on and L.accent or L.dim)
      else
        local s = M.show(it, v)
        if on then s = "< " .. s .. " >" end
        text(vx, ty, fit(s, math.floor(vw / cw)), on and L.text or L.dim)
      end
    end
  end
  if #rows > visible then                          -- (more than fits: a scroll bar)
    local th = visible * L.row
    local bh = math.max(6, math.floor(th * visible / #rows))
    local by = first_y + math.floor((th - bh) * st.scroll / math.max(1, #rows - visible))
    rect(x0 + W - 4, by, 2, bh, L.bar)
  end
  local it = self:focused(st)                      -- the focused item's tip / what's asked
  local tip = st.confirm and "Changes not applied:" or (st.typing and "Type; Enter keeps it, Escape drops it")
              or (st.capture and "Press a key or pad button (Esc: cancel)")
              or (it and it.tip) or ""
  rect(x0 + pad, tip_y - 2, W - 2 * pad, 1, L.bar)
  text(x0 + pad, tip_y + 2, fit(tip, math.floor((W - 2 * pad) / cw)), st.confirm and L.accent or L.dim)
  local names = st.confirm and CONFIRM or FOOT     -- the buttons, right aligned
  local fx = x0 + W - pad
  local dirty = self:dirty(st)
  for c = #names, 1, -1 do
    local s = names[c]
    local bw = (#s + 2) * cw
    fx = fx - bw
    local on = st.focus > n or st.confirm
    on = on and st.col == c
    local live = st.confirm or s == "Reset" or dirty
    if on then rect(fx, foot_y - 2, bw, ch + 6, L.focus) end
    rect(fx, foot_y - 2, bw, ch + 6, on and L.accent or L.bar, false)
    text(fx + cw, foot_y + 1, s, on and L.text or (live and L.text or L.dim))
    hits[#hits + 1] = { fx, foot_y - 2, bw, ch + 6, foot = c }
    fx = fx - cw
  end
  if dirty and not st.confirm then text(x0 + pad, foot_y + 1, "* not applied", L.accent) end
  return ops, hits, L
end

-- the mouse at x, y (menu coordinates: its centre is 0, 0): focus there, and
-- press it (a slider: set where pressed; a value: the next one)
function O:click(w, st, x, y, look, button)
  if not st.open then return false end
  st.capture = nil                                 -- (a key binding waiting: a click elsewhere drops it)
  local _, hits, L = self:layout(st, look)
  for _, h in ipairs(hits) do
    if x >= h[1] and x < h[1] + h[3] and y >= h[2] and y < h[2] + h[4] then
      if h.tab then
        if st.typing then st.typing, st.typed = nil, nil end
        st.confirm = nil
        if st.tab ~= h.tab then st.tab, st.focus, st.scroll = h.tab, 1, 0 end
      elseif h.foot then
        local _, n = self:rows(st.tab)
        if not st.confirm then st.focus = n + 1 end
        st.col = h.foot
        self:activate(w, st)
      elseif h.n then
        if st.confirm then return true end
        if st.typing and st.typing ~= (self:focused(st) or {}).id then st.typing, st.typed = nil, nil end
        st.focus = h.n
        local it = self:focused(st)
        if it and it.type == "slider" and x >= h.vx then
          local bw = h.vw - 7 * 8 * L.size
          local f = math.max(0, math.min(1, (x - h.vx) / math.max(1, bw)))
          self:set(w, st, it.id, it.min + f * (it.max - it.min))
        elseif it and (x >= h.vx or it.type == "bool" or it.type == "button") then
          if it.type == "enum" then self:change(w, st, button == "right" and -1 or 1) else self:activate(w, st) end
        end
      end
      return true
    end
  end
  return true
end

-- the game's nodes: the layout as rects and texts under /entities (never on
-- disk), placed and layered as the node (its xform; its or a parent's layer)
function O:draw(w, st, node, look)
  local root = st.path .. "_ui"
  local r = w:node(root)
  local layer, x, y, s = nil, 0, 0, 1
  if type(node) == "table" then
    local p = node.path or ""
    while p ~= "" and not layer do
      local nn = w:node(p)
      if nn and type(nn.c.layer) == "string" then layer = nn.c.layer end
      p = p:match("^(.*)/[^/]*$") or ""
    end
    local xf = node.c and node.c.xform
    if type(xf) == "table" then x, y, s = xf.x or 0, xf.y or 0, xf.s or 1 end
  end
  if not r then r = w:spawn(root, { xform = { x = x, y = y, s = s } }) end
  r.c.xform.x, r.c.xform.y, r.c.xform.s = x, y, s
  r.c.layer = layer
  r.c.hidden = not st.open or nil
  if not st.open then return end
  local ops = self:layout(st, look)
  local nr, nt = 0, 0
  for _, op in ipairs(ops) do
    if op[1] == "rect" then
      nr = nr + 1
      local path = string.format("%s/r%03d", root, nr)
      local n = w:node(path) or w:spawn(path, { xform = {}, rect = {}, color = {} })
      local xf, rc, c = n.c.xform, n.c.rect, n.c.color
      xf.x, xf.y = op[2] + op[4] / 2, op[3] + op[5] / 2
      rc.w, rc.h, rc.fill = op[4], op[5], op.fill
      c[1], c[2], c[3], c[4] = op[6][1], op[6][2], op[6][3], op[6][4] or 255
      n.c.hidden = nil
    else
      nt = nt + 1
      local path = string.format("%s/t%03d", root, nt)
      local n = w:node(path) or w:spawn(path, { xform = {}, text = { "" }, color = {} })
      local xf, c = n.c.xform, n.c.color
      xf.x, xf.y = op[2], op[3]
      n.c.text[1] = op[4]
      if op.font then n.c.text.font, n.c.text.size = op.font, op.font_size   -- (TrueType: the file's look)
      else n.c.text.font, n.c.text.size = nil, op[6] ~= 1 and op[6] or nil end
      n.c.text.shear = op.shear                    -- (the tab in view: slanted)
      c[1], c[2], c[3], c[4] = op[5][1], op[5][2], op[5][3], op[5][4] or 255
      n.c.hidden = nil
    end
  end
  for _, kind in ipairs({ "r", "t" }) do           -- (the ones not needed this time: hidden)
    local i = (kind == "r" and nr or nt) + 1
    while true do
      local n = w:node(string.format("%s/%s%03d", root, kind, i))
      if not n then break end
      n.c.hidden = true
      i = i + 1
    end
  end
end

-- a parsed file with its methods (o:state, o:key ...); name: its file's
function M.new(raw, name)
  local o, errs = M.check(raw)
  o.name, o.errors = name, errs
  return setmetatable(o, O)
end
M.methods = O

-- games: w:options("settings.options") -> the parsed file (assets/), read again when it changes
local ok, ecs = pcall(require, "ecs")
if ok and type(ecs) == "table" and ecs.assets then
  local cache = {}
  ecs.options = function(w, name)
    name = tostring(name):gsub("^/assets/", ""):gsub("^/", "")
    if not name:find("%.%w+$") then name = name .. ".options" end
    local text = ecs.assets.read(name)
    if not text then return nil, "no asset " .. name end
    local c = cache[name]
    if not c or c.text ~= text then
      local raw, err = M.decode(text, name)
      if not raw then return nil, err end
      c = { text = text, o = M.new(raw, name) }
      cache[name] = c
    end
    return c.o
  end
end
return M
