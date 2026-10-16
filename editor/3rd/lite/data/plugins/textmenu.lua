-- textmenu.lua - the main menu's Code > Text editor (Replay, ours): lite
-- itself, as the plugins are there (plugins/projectplugins.lua: a built-in
-- entry). Its menu:
--   New file, Open file..., Command Palette...
--   Edit >      what a right-click in a text offers (plugins/contextmenu.lua's
--               text menu: cut, copy, paste, open with / beside...), then
--               undo, redo, select all, find, replace, go to line, comment
--   Settings >  lite's: indent with spaces / tabs, indent size, line height,
--               the line guide, the current line highlighted, whitespace
--               shown, the minimap, zoom; kept in the editor's
--               .preferences.lua (`text = { ... }`: host_call "text_settings")
--   Commands >  lite's own commands (its core's and stock plugins', not the
--               project plugins' nor Replay's additions), a submenu per kind
--               (Core, Doc, Find Replace, Root, Tree View...), with its key
-- A command runs on the text tab in view (or the last one shown). The tab
-- of a text in view tints Code > Text editor in the menu (its owner).
local core = require "core"
local config = require "core.config"
local command = require "core.command"
local keymap = require "core.keymap"
local DocView = require "core.docview"
local CommandView = require "core.commandview"
local pp = require "plugins.projectplugins"

local M = {}

local function is_text(v)                          -- a text tab (not lite's command line, not a plugin's own view)
  return v and v.doc and v.is and v:is(DocView) and not v:is(CommandView) and pp.plugin_of(v) == nil
end
local last_text                                    -- (the last text shown: a command from the menu runs there)
local set_active_view = core.set_active_view
function core.set_active_view(view)
  if is_text(view) then last_text = view end
  return set_active_view(view)
end
local function text_view()                         -- -> node, view: the text tab to run on
  local root = core.root_view.root_node
  for _, v in ipairs({ core.active_view, last_text }) do
    local node = is_text(v) and root:get_node_for_view(v)
    if node then return node, v end
  end
  local hit
  local function walk(n)
    if hit or not n then return end
    if n.type == "leaf" then if is_text(n.active_view) then hit = { n, n.active_view } end
    else walk(n.a); walk(n.b) end
  end
  walk(root)
  if hit then return hit[1], hit[2] end
end
local function key(cmd)
  local k = keymap.get_binding(cmd)
  return k and (k:gsub("[^+]+", function(s) return s:upper() end)) or nil
end
local function run_on_text(cmd)                    -- a command, on the text tab
  return function()
    local node, v = text_view()
    if v then node:set_active_view(v); core.set_active_view(v) end
    if not command.perform(cmd) then core.log("Text editor: %s can't run here now", command.prettify_name(cmd)) end
  end
end
local function cmd_item(text, cmd, on_text)
  if not command.map[cmd] then return nil end
  return { text = text, info = key(cmd), run = on_text == false and function() command.perform(cmd) end or run_on_text(cmd) }
end

-- the settings: lite's config, as the editor keeps them
local KEYS = { tab_type = "string", indent_size = "number", line_height = "number", line_limit = "number",
               highlight_current_line = "boolean", draw_whitespace = "boolean", minimap_enabled = "boolean" }
local ORDER = { "tab_type", "indent_size", "line_height", "line_limit", "highlight_current_line", "draw_whitespace", "minimap_enabled" }
local function save()
  local t = {}
  for _, k in ipairs(ORDER) do
    local v = config[k]
    if type(v) == KEYS[k] then t[#t + 1] = k .. " = " .. (type(v) == "string" and string.format("%q", v) or tostring(v)) end
  end
  if host_call then host_call("text_settings { " .. table.concat(t, ", ") .. " }") end
end
local function set(k, v)
  config[k] = v
  save()
  core.redraw = true
end
rawset(_G, "lite_text_settings", function(t)       -- (the host, at start: what .preferences.lua keeps)
  if type(t) ~= "table" then return end
  for k, ty in pairs(KEYS) do if type(t[k]) == ty then config[k] = t[k] end end
  core.redraw = true
end)

local function choice(k, values, label)            -- a submenu of values, the current one checked
  local sub = {}
  for _, v in ipairs(values) do
    local val, text = v, tostring(v)
    if type(v) == "table" then val, text = v[1], v[2] end
    sub[#sub + 1] = { text = text, checked = config[k] == val, run = function() set(k, val) end }
  end
  local cur = config[k]
  for _, v in ipairs(values) do if type(v) == "table" and v[1] == cur then cur = v[2] end end
  return { text = label, info = tostring(cur), sub = sub }
end
local function toggle(k, label)
  return { text = label, checked = config[k] == true, run = function() set(k, not config[k]) end }
end
local function settings()
  local items = {
    choice("tab_type", { { "soft", "spaces" }, { "hard", "tabs" } }, "Indent with"),
    choice("indent_size", { 1, 2, 3, 4, 8 }, "Indent size"),
    choice("line_height", { 1.0, 1.1, 1.2, 1.3, 1.5 }, "Line height"),
    choice("line_limit", { 72, 80, 100, 120 }, "Line guide at"),
    { sep = true },
    toggle("highlight_current_line", "Highlight the current line"),
  }
  if config.draw_whitespace ~= nil then items[#items + 1] = toggle("draw_whitespace", "Show whitespace") end
  if config.minimap_enabled ~= nil then items[#items + 1] = toggle("minimap_enabled", "Minimap") end
  local zoom = {}
  for _, z in ipairs({ { "Zoom in", "scale:increase" }, { "Zoom out", "scale:decrease" }, { "Reset zoom", "scale:reset" } }) do
    zoom[#zoom + 1] = cmd_item(z[1], z[2], false)
  end
  if #zoom > 0 then items[#items + 1] = { sep = true }; for _, it in ipairs(zoom) do items[#items + 1] = it end end
  return items
end

-- what a right-click in a text offers (built as it would be there), then the usual edits
local function convert(list)
  local out = {}
  for _, it in ipairs(list or {}) do
    if type(it) ~= "table" or not it.text then
      if #out > 0 and not out[#out].sep then out[#out + 1] = { sep = true } end
    elseif it.text ~= "Command Palette..." then
      local o = { text = it.text, info = it.info, checked = it.checked }
      if it.sub then
        local ok, s = pcall(function() return type(it.sub) == "function" and it.sub() or it.sub end)
        o.sub = convert(ok and s or {})
      elseif type(it.command) == "string" then o.run = run_on_text(it.command); o.info = o.info or key(it.command)
      elseif type(it.command) == "function" then
        local fn = it.command
        o.run = function() local node, v = text_view(); if v then node:set_active_view(v); core.set_active_view(v) end; fn() end
      end
      if o.run or o.sub then out[#out + 1] = o end
    end
  end
  while #out > 0 and out[#out].sep do out[#out] = nil end
  return out
end
local function edit()
  local items = {}
  local ok, menu = pcall(require, "plugins.contextmenu")
  local _, v = text_view()
  if ok and menu and v then
    for _, e in ipairs(menu.itemset or {}) do
      if e.class == DocView then
        local was = core.active_view
        core.active_view = v                       -- (as if right-clicked there)
        local ok2, list = pcall(function() return type(e.items) == "function" and e.items() or e.items end)
        core.active_view = was
        items = convert(ok2 and list or {})
        break
      end
    end
  end
  local more = {}
  for _, c in ipairs({ { "Undo", "doc:undo" }, { "Redo", "doc:redo" }, { "Select all", "doc:select-all" },
                       { "Find...", "find-replace:find" }, { "Replace...", "find-replace:replace" },
                       { "Go to line...", "doc:go-to-line" }, { "Comment / uncomment", "doc:toggle-line-comments" } }) do
    more[#more + 1] = cmd_item(c[1], c[2])
  end
  if #items > 0 and #more > 0 then items[#items + 1] = { sep = true } end
  for _, it in ipairs(more) do items[#items + 1] = it end
  return items
end

-- lite's own commands (its core's, its stock plugins'), a submenu per kind;
-- not ours: the project plugins' (their own menus have them), nor Replay's
-- additions to lite (a plugin file that says "(Replay" at its top)
local function pretty(s) return (s:gsub("%-", " "):gsub("%f[%w]%l", string.upper)) end
local ours_cache = {}
local function norm(p) return (tostring(p or ""):gsub("\\", "/"):lower()) end
local function lites(fn)                           -- is this command's code lite's own?
  local info = type(fn) == "function" and debug.getinfo(fn, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) ~= "@" then return false end
  local file = norm(src:sub(2))
  local data = norm(DATADIR) .. "/"
  if file:sub(1, #data) ~= data then return false end          -- (a project plugin's: plugins/<name>/)
  local rel = file:sub(#data + 1):gsub("^data/", "")   -- (DATADIR: lite's folder or its data/)
  if rel:match("^core/") then return true end
  if not rel:match("^plugins/[^/]+%.lua$") then return false end   -- (a folder of plugins/: Replay's, canvas...)
  if ours_cache[rel] == nil then
    local f = io.open(src:sub(2), "rb")
    local head = f and f:read(400) or ""
    if f then f:close() end
    ours_cache[rel] = head:find("(Replay", 1, true) ~= nil and not head:find("lite's, extended", 1, true)
  end
  return not ours_cache[rel]
end
M.lites = lites
local function commands()
  local kinds = {}
  for name, cmd in pairs(command.map) do
    local kind, rest = name:match("^([^:]+):(.+)$")
    if kind and kind ~= "context" and lites(cmd.perform) then   -- (context: a menu's own keys)
      kinds[kind] = kinds[kind] or {}
      table.insert(kinds[kind], { name = name, text = pretty(rest) })
    end
  end
  local names = {}
  for k in pairs(kinds) do names[#names + 1] = k end
  table.sort(names)
  local out = {}
  for _, k in ipairs(names) do
    table.sort(kinds[k], function(a, b) return a.text < b.text end)
    local sub = {}
    for _, c in ipairs(kinds[k]) do sub[#sub + 1] = { text = c.text, info = key(c.name), run = run_on_text(c.name) } end
    out[#out + 1] = { text = pretty(k), info = tostring(#sub), sub = sub }
  end
  return out
end

function M.menu()
  local items = {}
  for _, it in ipairs({ cmd_item("New file", "core:new-doc", false), cmd_item("Open file...", "core:open-file", false),
                        cmd_item("Command Palette...", "core:find-command") }) do items[#items + 1] = it end
  items[#items + 1] = { sep = true }
  items[#items + 1] = { text = "Edit", sub = edit() }
  items[#items + 1] = { text = "Settings", sub = settings() }
  items[#items + 1] = { text = "Commands", sub = commands() }
  return items
end

pp.add_builtin("texteditor", {
  title = "Text editor", category = "Code",
  menu = M.menu,
  owns = function(v) return is_text(v) end,
  open = function() command.perform("core:new-doc") end,
})

M.is_text, M.text_view = is_text, text_view
return M
