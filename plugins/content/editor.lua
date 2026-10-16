-- editor.lua - the content browser: a folder as a gallery (runs in Lite), after UE5's
-- Content Browser. `replay some/folder/` opens one (a folder that is no game; a game
-- folder opens as the game), and so does the main menu's Assets > Content browser.
--
-- Folders first, then files, as tiles: a picture when there is one (pictures, models:
-- the host draws those, host_model_thumb), else the file's kind; a strip in its kind's
-- colour under it (types.lua: UE5's colours). Double-click opens (a folder: inside;
-- a file: in its plugin, or as text), RMB: what can be done with it.
--
-- The search bar: what's typed filters as it's typed, Enter keeps it as a tag (a
-- [x] takes it away); tags add up. A tag is
--   type:texture   a kind (texture, mesh, skeletal, anim, material, sound, cue, code,
--                  particles, map, data, font, doc, folder, game, other; and model,
--                  image, audio, script, level, as other names)
--   **.jpg  *.png  a mask: with "/" or "**" against the path under this folder, else
--                  against the name ("*", "?"; "**" across folders)
--   ship           a fuzzy match on the name (its letters in that order)
--   -tag  !tag     leaves out what matches
-- Kinds add up among themselves (type:texture type:mesh: both); the rest must all
-- match. With any filter, every folder below is searched.
local P = ...
P.title = "Content browser"                        -- (its name in menus)
P.category = "Assets"                              -- (the main menu: Assets >)
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"
local canvas = require "plugins.canvas"
local Field = canvas.field
local D = canvas.draw
local openwith = require "plugins.openwith"

local function S(n) return math.floor(n * SCALE + 0.5) end
local PATHSEP_ = "/"
local function norm(p) return (tostring(p):gsub("\\", "/"):gsub("/+$", "")) end
local function join(a, b) return norm(a) .. "/" .. b end
local function base_of(p) return norm(p):match("[^/]*$") end
local function dir_of(p) return norm(p):match("^(.*)/[^/]*$") or "." end

-- the kinds ------------------------------------------------------------------
local TYPES, BY_EXT, BY_KEY = {}, {}, {}
local ALIAS = { image = "texture", picture = "texture", model = "mesh", audio = "sound", script = "code", level = "map", file = "other" }
local cfg = { size = 96, hidden = false }
local function load_types()
  TYPES, BY_EXT, BY_KEY = P.read("types") or {}, {}, {}
  for _, t in ipairs(TYPES) do
    BY_KEY[t.key] = t
    for _, e in ipairs(t.exts or {}) do if not BY_EXT[e:lower()] then BY_EXT[e:lower()] = t end end
  end
  if not BY_KEY.other then BY_KEY.other = { key = "other", name = "File", color = { 110, 110, 120 } }; TYPES[#TYPES + 1] = BY_KEY.other end
  if not BY_KEY.folder then BY_KEY.folder = { key = "folder", name = "Folder", color = { 200, 160, 90 } }; TYPES[#TYPES + 1] = BY_KEY.folder end
  if not BY_KEY.game then BY_KEY.game = { key = "game", name = "Game", color = { 255, 156, 0 } }; TYPES[#TYPES + 1] = BY_KEY.game end
end
local function load_config()
  local c = P.read("config")
  cfg = { size = 96, hidden = false }
  if type(c) == "table" then
    if type(c.size) == "number" then cfg.size = math.max(32, math.min(256, c.size)) end
    if type(c.hidden) == "boolean" then cfg.hidden = c.hidden end
  end
end
local function ext_of(name)                        -- (two parts first: "ui.atlas.lua")
  local e2 = name:match("[^/]%.([^%./]+%.[^%./]+)$")
  if e2 and BY_EXT[e2:lower()] then return e2:lower() end
  return (name:match("%.([^%./]+)$") or ""):lower()
end

-- the files ------------------------------------------------------------------
local SKIP = { [".trash"] = true, [".git"] = true, [".saves"] = true, [".history"] = true, ["__pycache__"] = true }
local function hidden(name) return SKIP[name] or name:sub(1, 1) == "." end
local games = {}                                   -- path -> is it a game? (the host knows: replay.c is_game_dir)
local function is_game(path)
  if games[path] == nil then games[path] = host_call and host_call("is_game " .. path) == "yes" or false end
  return games[path]
end
local THUMBS = {}                                  -- path -> { img, mtime, skeletal, failed, size }
local function type_of(e)
  if e.dir then return is_game(e.path) and BY_KEY.game or BY_KEY.folder end
  local t = BY_EXT[ext_of(e.name)] or BY_KEY.other
  if t.key == "mesh" then local th = THUMBS[e.path]; if th and th.skeletal and BY_KEY.skeletal then return BY_KEY.skeletal end end
  return t
end
local function entry(dir, name)
  local path = join(dir, name)
  local info = system.get_file_info(path)
  if not info then return nil end
  return { name = name, path = path, dir = info.type == "dir", size = info.size or 0, modified = info.modified or 0 }
end
local function list(dir)                           -- a folder's entries: folders first, then files, by name
  local out = {}
  for _, name in ipairs(system.list_dir(dir) or {}) do
    if cfg.hidden or not hidden(name) then
      local e = entry(dir, name)
      if e then out[#out + 1] = e end
    end
  end
  table.sort(out, function(a, b) if a.dir ~= b.dir then return a.dir end return a.name:lower() < b.name:lower() end)
  return out
end
local WALK_MAX = 6000
local function walk(root)                          -- every entry below root (rel: its path under root), at most WALK_MAX
  local out = {}
  local function go(dir, rel, depth)
    if #out >= WALK_MAX or depth > 16 then return end
    for _, e in ipairs(list(dir)) do
      if #out >= WALK_MAX then return end
      e.rel = rel == "" and e.name or rel .. "/" .. e.name
      out[#out + 1] = e
      if e.dir and not is_game(e.path) then go(e.path, e.rel, depth + 1) end   -- (a game's own folders: not)
    end
  end
  go(root, "", 0)
  return out
end

-- the filter -------------------------------------------------------------------
local function glob(mask)                          -- "*", "?", "**" -> a Lua pattern, whole
  local out = mask:gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0")
  out = out:gsub("%*%*", "\1"):gsub("%*", "[^/]*"):gsub("%?", "[^/]"):gsub("\1", ".*")
  return "^" .. out .. "$"
end
local function fuzzy(hay, needle)                  -- its letters in that order
  hay, needle = hay:lower(), needle:lower()
  local i = 1
  for c in needle:gmatch(".") do
    i = hay:find(c, i, true)
    if not i then return false end
    i = i + 1
  end
  return true
end
local function parse(text)                         -- -> a tag
  local neg = false
  if text:sub(1, 1) == "-" or text:sub(1, 1) == "!" then neg, text = true, text:sub(2) end
  if text == "" then return nil end
  local kind = text:match("^type:(.+)$") or text:match("^t:(.+)$")
  if kind then kind = kind:lower(); kind = ALIAS[kind] or kind; return { text = (neg and "-" or "") .. "type:" .. kind, kind = "type", value = kind, neg = neg } end
  if text:find("[%*%?]") then
    return { text = (neg and "-" or "") .. text, kind = "mask", value = glob(text:lower()), path = text:find("/") or text:find("%*%*"), neg = neg }
  end
  return { text = (neg and "-" or "") .. text, kind = "fuzzy", value = text, neg = neg }
end
local function one(tag, e)
  if tag.kind == "type" then
    local t = type_of(e).key
    return t == tag.value or (tag.value == "mesh" and t == "skeletal") or (tag.value == "sound" and t == "cue")
  elseif tag.kind == "mask" then
    return ((tag.path and (e.rel or e.name) or e.name):lower()):match(tag.value) ~= nil
  end
  return fuzzy(e.name, tag.value)
end
local function passes(tags, e)
  local types, any_type = false, false
  for _, tag in ipairs(tags) do
    local hit = one(tag, e)
    if tag.neg then if hit then return false end
    elseif tag.kind == "type" then any_type = true; types = types or hit
    elseif not hit then return false end
  end
  return not any_type or types
end

-- the view ---------------------------------------------------------------------
local CView = View:extend()
CView.context = "session"

function CView:new(state)
  CView.super.new(self)
  state = state or {}
  self.dir = norm(state.filename or state.dir or system.absolute_path(".") or ".")
  self.filename = self.dir                         -- (openwith: the tab showing this folder)
  self.root = norm(state.root or self.dir)          -- (where it started: its .trash)
  self.tsize = state.size or cfg.size
  self.back, self.fwd = {}, {}
  self.field = Field.new("")
  self.tags = {}
  for _, t in ipairs(state.tags or {}) do local tag = parse(t); if tag then self.tags[#self.tags + 1] = tag end end
  self.scroll_y = 0
  self.hits = {}
  self:refresh()
end
function CView:get_name() return "Content: " .. (base_of(self.dir) ~= "" and base_of(self.dir) or self.dir) end
function CView:get_state()
  local tags = {}
  for _, t in ipairs(self.tags) do tags[#tags + 1] = t.text end
  return { filename = self.dir, root = self.root, size = self.tsize, tags = tags }
end

function CView:filters()                           -- the tags, and what's being typed (as a tag, not kept yet)
  local all = {}
  for _, t in ipairs(self.tags) do all[#all + 1] = t end
  local live = parse(self.field.text:match("^%s*(.-)%s*$") or "")
  if live then all[#all + 1] = live end
  return all
end
function CView:refresh()
  local tags = self:filters()
  local info = system.get_file_info(self.dir)
  self.dir_mtime = info and info.modified
  self.searching = #tags > 0
  local items = {}
  if self.searching then                           -- every folder below: files (folders when asked for)
    local want_dirs = false
    for _, t in ipairs(tags) do if t.kind == "type" and not t.neg and (t.value == "folder" or t.value == "game") then want_dirs = true end end
    for _, e in ipairs(walk(self.dir)) do
      if (want_dirs or not e.dir) and passes(tags, e) then items[#items + 1] = e end
    end
    self.truncated = #items >= WALK_MAX
  else
    items = list(self.dir)
    self.truncated = false
  end
  self.items = items
  if self.sel then                                 -- (the selection: kept if still there)
    local still = false
    for _, e in ipairs(items) do if e.path == self.sel then still = true end end
    if not still then self.sel = nil end
  end
  core.redraw = true
end
function CView:go(dir, no_history)
  dir = norm(dir)
  if dir == self.dir then return end
  if not no_history then self.back[#self.back + 1] = self.dir; self.fwd = {} end
  self.dir, self.filename = dir, dir
  self.scroll_y, self.sel = 0, nil
  self:refresh()
end
function CView:go_back() if #self.back > 0 then self.fwd[#self.fwd + 1] = self.dir; self:go(table.remove(self.back), true) end end
function CView:go_forward() if #self.fwd > 0 then self.back[#self.back + 1] = self.dir; self:go(table.remove(self.fwd), true) end end
function CView:go_up() local up = dir_of(self.dir); if up ~= self.dir and up ~= "." then self:go(up) end end

function CView:add_tag(text)
  local tag = parse(text)
  if not tag then return end
  for _, t in ipairs(self.tags) do if t.text == tag.text then return end end
  self.tags[#self.tags + 1] = tag
  self:refresh()
end
function CView:remove_tag(i) table.remove(self.tags, i); self:refresh() end

function CView:open(e)
  e = e or self:selected()
  if not e then return end
  if e.dir then self:go(e.path) return end
  local pp = package.loaded["plugins.projectplugins"]
  if pp and pp.view_for(e.path) then core.root_view:open_doc(core.open_doc(e.path)) return end   -- (its plugin's tab)
  for _, o in ipairs(openwith.list(e.path)) do if o.key == "text" then openwith.open("text", e.path) return end end
  core.log("Nothing here opens %s (no plugin takes .%s)", e.name, ext_of(e.name))
end
function CView:selected()
  for _, e in ipairs(self.items) do if e.path == self.sel then return e end end
end

-- what a file / folder can do (RMB) ---------------------------------------------
local function trash_dir(self)                     -- (deleting: into <root>/.trash/, never for good)
  local t = join(self.root, ".trash")
  if not system.get_file_info(t) then system.mkdir(t) end
  return t
end
local function unique(dir, name)
  local stem, ext = name:match("^(.-)(%.[^.]*)$")
  if not stem or stem == "" then stem, ext = name, "" end
  local p, k = join(dir, name), 1
  while system.get_file_info(p) do k = k + 1; p = join(dir, stem .. " " .. k .. ext) end
  return p
end
function CView:trash(e)
  local to = unique(trash_dir(self), e.name)
  local ok, err = os.rename(e.path, to)
  if ok then core.log("Moved %s to %s", e.name, to) else core.error("Can't move %s to the trash: %s", e.name, tostring(err)) end
  self:refresh()
end
function CView:rename(e)
  core.command_view:enter("Rename " .. e.name .. " to", function(text)
    if text == "" or text == e.name or text:find("[/\\]") then return end
    local to = join(dir_of(e.path), text)
    if system.get_file_info(to) then core.error("%s is there already", text) return end
    local ok, err = os.rename(e.path, to)
    if not ok then core.error("Can't rename %s: %s", e.name, tostring(err)) end
    if ok and self.sel == e.path then self.sel = to end
    self:refresh()
  end)
  core.command_view:set_text(e.name, true)
end
function CView:duplicate(e)
  local f = io.open(e.path, "rb")
  if not f then return end
  local data = f:read("*a")
  f:close()
  local stem, ext = e.name:match("^(.-)(%.[^.]*)$")
  local to = unique(dir_of(e.path), (stem and stem ~= "" and stem or e.name) .. " copy" .. (stem and stem ~= "" and ext or ""))
  local o = io.open(to, "wb")
  if o then o:write(data); o:close(); self.sel = to end
  self:refresh()
end
function CView:new_folder()
  core.command_view:enter("New folder in " .. base_of(self.dir), function(text)
    if text == "" or text:find("[/\\]") then return end
    local p = join(self.dir, text)
    if system.get_file_info(p) then core.error("%s is there already", text) return end
    system.mkdir(p)
    self.sel = p
    self:refresh()
  end)
end
local function reveal(path)                        -- its folder in the system's file manager
  local isdir = (system.get_file_info(path) or {}).type == "dir"
  if PLATFORM == "Windows" then system.exec(string.format('explorer %s"%s"', isdir and "" or "/select,", path:gsub("/", "\\")))
  elseif PLATFORM == "Mac OS X" then system.exec(string.format('open %s"%s"', isdir and "" or "-R ", path))
  else system.exec(string.format('xdg-open "%s"', isdir and path or dir_of(path))) end
end
function CView:menu_items()
  local DIV = require("plugins.contextmenu").DIVIDER
  local e = self.hover and self:entry_at(self.hover) or nil
  local items = {}
  if e then
    self.sel = e.path
    local t = type_of(e)
    items[#items + 1] = { text = e.dir and "Open folder" or "Open", info = "dbl-click", command = function() self:open(e) end }
    if e.dir and t.key == "game" then items[#items + 1] = { text = "Open as game", info = "a new editor", command = function() if host_call then host_call("open_game " .. e.path) end end } end
    if not e.dir then
      local w = openwith.item(e.path)
      if w then items[#items + 1] = w end
      if self.searching then items[#items + 1] = { text = "Show its folder", command = function() self.field = Field.new(""); self.tags = {}; self:go(dir_of(e.path)); self.sel = e.path end } end
    end
    items[#items + 1] = DIV
    items[#items + 1] = { text = "Copy path", command = function() system.set_clipboard(e.path) end }
    items[#items + 1] = { text = "Copy path under " .. base_of(self.dir), command = function() system.set_clipboard(e.rel or e.name) end }
    items[#items + 1] = { text = "Show in file manager", command = function() reveal(e.path) end }
    items[#items + 1] = DIV
    items[#items + 1] = { text = "Rename...", info = "F2", command = function() self:rename(e) end }
    if not e.dir then items[#items + 1] = { text = "Duplicate", command = function() self:duplicate(e) end } end
    items[#items + 1] = { text = "Move to trash", info = "DEL", command = function() self:trash(e) end }
    items[#items + 1] = DIV
    items[#items + 1] = { text = "Filter: " .. t.name .. " only", command = function() self:add_tag("type:" .. t.key) end }
  end
  items[#items + 1] = { text = "New folder...", command = function() self:new_folder() end }
  items[#items + 1] = { text = "Up a folder", info = "BACKSPACE", command = function() self:go_up() end }
  items[#items + 1] = { text = "Refresh", info = "F5", command = function() THUMBS = {}; games = {}; self:refresh() end }
  items[#items + 1] = { text = "Hidden files", checked = cfg.hidden, command = function() cfg.hidden = not cfg.hidden; self:refresh() end }
  items[#items + 1] = { text = "Bigger pictures", info = "CTRL+wheel", command = function() self:resize(1.25) end }
  items[#items + 1] = { text = "Smaller pictures", info = "CTRL+wheel", command = function() self:resize(0.8) end }
  return items
end
function CView:resize(k) self.tsize = math.max(32, math.min(256, math.floor(self.tsize * k + 0.5))); core.redraw = true end

-- the pictures (a few a frame, the ones on screen first) -------------------------
local function make_thumb(e, px)
  local th = { mtime = e.modified, size = px }
  local t = BY_EXT[ext_of(e.name)]
  if t and t.key == "texture" then
    if e.size > 32 * 1024 * 1024 then th.failed = true return th end
    local img = renderer.image.load(e.path)
    if img then
      local w, h = img:get_size()
      local k = math.min(1, px / math.max(w, h))
      th.img = k < 1 and img:resized(math.max(1, math.floor(w * k)), math.max(1, math.floor(h * k))) or img
      th.w, th.h = w, h
    else th.failed = true end
  elseif t and t.key == "mesh" then
    local w, h, rgba
    if host_model_thumb then w, h, rgba = host_model_thumb(e.path, px) end   -- (not `a and f()`: that keeps one value)
    if w then th.img = renderer.image.from_rgba(w, h, rgba) else th.failed = true end
    local info = host_model_info and host_model_info(e.path)
    th.skeletal = info and (info.joints or 0) > 0
    if info then th.info = string.format("%d tris", math.floor((info.indices or 0) / 3)) end
  else th.none = true end
  return th
end
local function wants_thumb(e)
  if e.dir then return false end
  local t = BY_EXT[ext_of(e.name)]
  return t and (t.key == "texture" or t.key == "mesh")
end
function CView:update()
  CView.super.update(self)
  local now = system.get_time()
  local t0 = now
  for _, e in ipairs(self.visible or {}) do        -- (up to ~6 ms a frame)
    if system.get_time() - t0 > 0.006 then break end
    local th = THUMBS[e.path]
    local px = math.floor(self.tsize * SCALE)
    if wants_thumb(e) and (not th or th.mtime ~= e.modified or (th.size < px and not th.failed)) then
      THUMBS[e.path] = make_thumb(e, px)
      core.redraw = true
    end
  end
  if now >= (self.next_check or 0) then            -- (the folder changed on disk: read again; settings, kinds)
    self.next_check = now + 1
    local info = system.get_file_info(self.dir)
    if not self.searching and info and info.modified ~= self.dir_mtime then self:refresh() end
    if P.changed("types") then load_types(); self:refresh() end
    if P.changed("config") then load_config(); self:refresh() end
  end
end

-- drawing ------------------------------------------------------------------------
local function fit(font, s, w)
  if font:get_width(s) <= w then return s end
  while #s > 1 and font:get_width(s .. "…") > w do s = s:sub(1, -2) end
  return s .. "…"
end
local function rgb(c, a) return { c[1], c[2], c[3], a or 255 } end
local function mix(c, k) return { math.floor(c[1] * k), math.floor(c[2] * k), math.floor(c[3] * k), 255 } end
function CView:hit(x, y, w, h, what, data) self.hits[#self.hits + 1] = { x = x, y = y, w = w, h = h, what = what, data = data } end
function CView:hit_at(mx, my)
  for i = #self.hits, 1, -1 do
    local h = self.hits[i]
    if mx >= h.x and mx < h.x + h.w and my >= h.y and my < h.y + h.h then return h end
  end
end
function CView:entry_at(path) for _, e in ipairs(self.items) do if e.path == path then return e end end end
function CView:button(x, y, text, what, data, on)
  local f = style.font
  local w, h = f:get_width(text) + S(14), S(24)
  local hot = self.mouse and self.mouse[1] >= x and self.mouse[1] < x + w and self.mouse[2] >= y and self.mouse[2] < y + h
  D.rrect(x, y, w, h, S(4), (on ~= false and hot) and style.line_highlight or style.background2)
  renderer.draw_text(f, text, x + S(7), y + math.floor((h - f:get_height()) / 2), on == false and style.dim or style.text)
  self:hit(x, y, w, h, what, data)
  return x + w + S(4)
end
function CView:layout()
  local x, y, w, h = self.position.x, self.position.y, self.size.x, self.size.y
  local bar = S(34)
  return { top = { x, y, w, bar }, search = { x, y + bar, w, bar }, grid = { x, y + bar * 2, w, h - bar * 3 }, status = { x, y + h - bar, w, bar } }
end
function CView:tile_size()
  local px = math.floor(self.tsize * SCALE)
  local f = style.font
  return px, px + S(12), px + S(12) + f:get_height() * 2 + S(10)
end
function CView:draw_top(r)
  local x, y = r[1] + S(8), r[2] + S(5)
  renderer.draw_rect(r[1], r[2], r[3], r[4], style.background2)
  x = self:button(x, y, "<", "back", nil, #self.back > 0)
  x = self:button(x, y, ">", "forward", nil, #self.fwd > 0)
  x = self:button(x, y, "^", "up", nil, dir_of(self.dir) ~= self.dir)
  x = x + S(6)
  local parts, acc = {}, ""                        -- the breadcrumbs: each folder up to here, clickable
  for part in self.dir:gmatch("[^/]+") do
    acc = (acc == "" and (self.dir:sub(1, 1) == "/" and "/" or "") or acc .. "/") .. part
    parts[#parts + 1] = { part, acc }
  end
  local f = style.font
  local first = 1
  local function width(i) local w = 0 for k = i, #parts do w = w + f:get_width(parts[k][1]) + S(22) end return w end
  while first < #parts and x + width(first) > r[1] + r[3] - S(10) do first = first + 1 end   -- (too long: its first ones left out)
  if first > 1 then renderer.draw_text(f, "…", x, y + S(4), style.dim); x = x + f:get_width("…") + S(8) end
  for i = first, #parts do
    local p = parts[i]
    local last = i == #parts
    local tw = f:get_width(p[1])
    local hot = self.mouse and self.mouse[1] >= x and self.mouse[1] < x + tw and self.mouse[2] >= y and self.mouse[2] < y + S(24)
    renderer.draw_text(f, p[1], x, y + S(4), last and style.text or (hot and style.accent or style.dim))
    if not last then self:hit(x, y, tw, S(24), "crumb", p[2]) end
    x = x + tw
    if not last then renderer.draw_text(f, " / ", x, y + S(4), style.dim); x = x + f:get_width(" / ") end
  end
end
function CView:draw_search(r)
  local f = style.font
  local x, y, h = r[1] + S(8), r[2] + S(5), S(24)
  local add_w = f:get_width("+ Type") + S(14)
  local bw = r[3] - S(16) - add_w - S(6)
  local focused = Field.focused(self.field)
  renderer.draw_rect(x, y, bw, h, style.background)
  renderer.draw_rect(x, y + h - 1, bw, 1, focused and style.caret or style.dim)
  self:hit(x, y, bw, h, "field")
  local cx = x + S(6)
  for i, t in ipairs(self.tags) do                 -- the tags: chips, a [x] each
    local col = t.kind == "type" and BY_KEY[t.value] and BY_KEY[t.value].color
    local label = t.text
    local tw = f:get_width(label) + S(26)
    if cx + tw > x + bw - S(80) then break end
    D.rrect(cx, y + S(3), tw, h - S(6), S(8), col and mix(col, 0.45) or style.background3)
    if t.neg then renderer.draw_rect(cx + S(6), y + math.floor(h / 2), f:get_width(label), 1, style.dim) end
    renderer.draw_text(f, label, cx + S(7), y + math.floor((h - f:get_height()) / 2), style.text)
    local xx = cx + tw - S(15)
    local hot = self.mouse and self.mouse[1] >= xx - S(3) and self.mouse[1] < xx + S(12) and self.mouse[2] >= y and self.mouse[2] < y + h
    renderer.draw_text(f, "x", xx, y + math.floor((h - f:get_height()) / 2), hot and style.accent or style.text)
    self:hit(xx - S(3), y, S(15), h, "untag", i)
    cx = cx + tw + S(4)
  end
  local fx = cx + S(2)
  self.field_rect = { fx, y, x + bw - fx, h }
  core.push_clip_rect(fx, y, x + bw - fx - S(4), h)
  if self.field.text == "" and not focused then
    renderer.draw_text(f, #self.tags == 0 and "Search: name, *.png, **.jpg, type:texture, -tag (Enter keeps it)" or "more...", fx, y + math.floor((h - f:get_height()) / 2), style.dim)
  else
    Field.draw(self.field, f, fx, y + math.floor((h - f:get_height()) / 2), style.text, focused and style.caret or nil)
  end
  core.pop_clip_rect()
  self:button(x + bw + S(6), y, "+ Type", "types")
end
function CView:draw_tile(e, x, y, tw, th, px)
  local t = type_of(e)
  local f = style.font
  local sel = e.path == self.sel
  local hot = self.hover == e.path
  D.rrect(x, y, tw, th, S(5), sel and style.selection or (hot and style.line_highlight or style.background2))
  local ix, iy = x + S(6), y + S(6)
  local th2 = THUMBS[e.path]
  if e.dir then                                    -- a folder: its shape, in its colour
    local c = rgb(t.color)
    local fw, fh = math.floor(px * 0.8), math.floor(px * 0.6)
    local fx, fy = ix + math.floor((px - fw) / 2), iy + math.floor((px - fh) / 2) + S(4)
    D.rrect(fx, fy - math.floor(fh * 0.12), math.floor(fw * 0.4), math.floor(fh * 0.2), S(3), mix(t.color, 0.75))
    D.rrect(fx, fy, fw, fh, S(4), c)
    if t.key == "game" then renderer.draw_text(f, "game", fx + math.floor((fw - f:get_width("game")) / 2), fy + math.floor((fh - f:get_height()) / 2), { 40, 30, 10, 255 }) end
  elseif th2 and th2.img then                      -- its picture, fitted
    renderer.draw_rect(ix, iy, px, px, style.background)
    local w, h = th2.img:get_size()
    local k = math.min(px / w, px / h)
    if k > 1 then k = math.max(1, math.floor(k)) end
    local dw, dh = math.floor(w * k), math.floor(h * k)
    renderer.draw_image(th2.img, ix + math.floor((px - dw) / 2), iy + math.floor((px - dh) / 2), dw, dh)
  else                                             -- its kind: a card in its colour, its extension on it
    D.rrect(ix, iy, px, px, S(4), mix(t.color, 0.35))
    local label = ext_of(e.name):upper()
    if label == "" then label = "FILE" end
    label = fit(f, label, px - S(8))
    renderer.draw_text(f, label, ix + math.floor((px - f:get_width(label)) / 2), iy + math.floor((px - f:get_height()) / 2), rgb(t.color))
  end
  renderer.draw_rect(ix, iy + px + S(2), px, S(3), rgb(t.color))   -- (the strip: UE's kind colour)
  local ny = iy + px + S(8)
  local name = e.dir and e.name or (e.name:match("^(.+)%.[^.]+$") or e.name)
  renderer.draw_text(f, fit(f, name, px), ix, ny, sel and style.accent or style.text)
  local sub = self.searching and (e.rel and dir_of(e.rel) ~= "." and dir_of(e.rel)) or t.name
  renderer.draw_text(f, fit(f, sub or t.name, px), ix, ny + f:get_height(), style.dim)
  self:hit(x, y, tw, th, "tile", e.path)
end
function CView:draw()
  self:draw_background(style.background)
  self.hits = {}
  local r = self:layout()
  local g = r.grid
  local px, tw, th = self:tile_size()
  local gap = S(8)
  local cols = math.max(1, math.floor((g[3] - gap) / (tw + gap)))
  self.cols = cols
  local rows = math.ceil(#self.items / cols)
  local total = rows * (th + gap) + gap
  self.scroll_max = math.max(0, total - g[4])
  self.scroll_y = math.max(0, math.min(self.scroll_y, self.scroll_max))
  self.visible = {}
  core.push_clip_rect(g[1], g[2], g[3], g[4])
  local x0 = g[1] + gap + math.floor((g[3] - gap - cols * (tw + gap)) / 2)
  for i, e in ipairs(self.items) do
    local c, rr = (i - 1) % cols, math.floor((i - 1) / cols)
    local x, y = x0 + c * (tw + gap), g[2] + gap + rr * (th + gap) - math.floor(self.scroll_y)
    if y + th >= g[2] and y < g[2] + g[4] then
      self:draw_tile(e, x, y, tw, th, px)
      self.visible[#self.visible + 1] = e
    end
  end
  if #self.items == 0 then
    local msg = self.searching and "Nothing matches." or "This folder is empty."
    renderer.draw_text(style.font, msg, g[1] + S(16), g[2] + S(16), style.dim)
  end
  if self.scroll_max > 0 then                      -- (a thin scroll bar)
    local bh = math.max(S(20), g[4] * g[4] / total)
    local by = g[2] + (g[4] - bh) * (self.scroll_y / self.scroll_max)
    renderer.draw_rect(g[1] + g[3] - S(5), by, S(4), bh, style.scrollbar)
  end
  core.pop_clip_rect()
  self:draw_top(r.top)
  self:draw_search(r.search)
  local s = r.status                               -- the status line: how many, the selected one
  renderer.draw_rect(s[1], s[2], s[3], s[4], style.background2)
  local nd, nf = 0, 0
  for _, e in ipairs(self.items) do if e.dir then nd = nd + 1 else nf = nf + 1 end end
  local text = string.format("%d folders, %d files%s", nd, nf, self.truncated and " (the first " .. WALK_MAX .. " looked at)" or "")
  local e = self:selected()
  if e then
    local t = type_of(e)
    local size = e.dir and "" or (e.size >= 1048576 and string.format("   %.1f MB", e.size / 1048576) or string.format("   %.1f KB", e.size / 1024))
    local thx = THUMBS[e.path]
    local more = thx and (thx.w and string.format("   %d x %d", thx.w, thx.h) or thx.info and "   " .. thx.info) or ""
    text = text .. "      " .. e.name .. "   " .. t.name .. size .. more .. "   " .. os.date("%Y-%m-%d %H:%M", math.floor(e.modified))
  end
  renderer.draw_text(style.font, fit(style.font, text, s[3] - S(16)), s[1] + S(8), s[2] + math.floor((s[4] - style.font:get_height()) / 2), style.dim)
end

-- the mouse, the keys ---------------------------------------------------------------
function CView:focus_field()
  Field.focus(self.field, { font = style.font,
    on_key = function(k)
      if k == "return" then local t = self.field.text; Field.set(self.field, ""); self:add_tag(t); return true end
      if k == "escape" then Field.set(self.field, ""); Field.blur(self.field); self:refresh(); return true end
      if k == "backspace" and self.field.text == "" and #self.tags > 0 then self:remove_tag(#self.tags); return true end
      return false
    end,
    on_change = function() self:refresh() end })
end
function CView:on_mouse_pressed(button, x, y, clicks)
  self.mouse = { x, y }
  local h = self:hit_at(x, y)
  if button == "right" then self.hover = h and h.what == "tile" and h.data or nil; return false end   -- (the menu: plugins/contextmenu)
  if button ~= "left" then return CView.super.on_mouse_pressed(self, button, x, y, clicks) end
  if h and h.what ~= "field" and Field.focused(self.field) then Field.blur(self.field) end
  if not h then self.sel = nil; core.redraw = true; return true end
  if h.what == "back" then self:go_back()
  elseif h.what == "forward" then self:go_forward()
  elseif h.what == "up" then self:go_up()
  elseif h.what == "crumb" then self:go(h.data)
  elseif h.what == "untag" then self:remove_tag(h.data)
  elseif h.what == "field" then
    if Field.focused(self.field) then Field.mouse(self.field, "pressed", x, y, clicks) else self:focus_field() end
  elseif h.what == "types" then
    local items = {}
    for _, t in ipairs(TYPES) do items[#items + 1] = { text = t.name, info = "type:" .. t.key, command = function() self:add_tag("type:" .. t.key) end } end
    require("plugins.contextmenu"):show_items(h.x, h.y + h.h, items)
  elseif h.what == "tile" then
    self.sel = h.data
    if clicks >= 2 then self:open(self:entry_at(h.data)) end
  end
  core.redraw = true
  return true
end
function CView:on_mouse_moved(x, y, dx, dy)
  CView.super.on_mouse_moved(self, x, y, dx, dy)
  self.mouse = { x, y }
  if Field.focused(self.field) and Field.mouse(self.field, "moved", x, y) then return end
  local h = self:hit_at(x, y)
  local hov = h and h.what == "tile" and h.data or nil
  if hov ~= self.hover then self.hover = hov end
  core.redraw = true
end
function CView:on_mouse_released(button, x, y)
  CView.super.on_mouse_released(self, button, x, y)
  if Field.focused(self.field) then Field.mouse(self.field, "released", x, y) end
end
CView.wants_ctrl_wheel = true
function CView:on_mouse_wheel(dy)
  if keymap.modkeys["ctrl"] then self:resize(dy > 0 and 1.15 or 1 / 1.15) return true end
  local _, _, th = self:tile_size()
  self.scroll_y = self.scroll_y - dy * (th + S(8)) * 0.5
  core.redraw = true
  return true
end
function CView:move_sel(d)                         -- (arrows: across, a row up / down)
  local n = #self.items
  if n == 0 then return end
  local at = 0
  for i, e in ipairs(self.items) do if e.path == self.sel then at = i end end
  local step = (d == "left" and -1) or (d == "right" and 1) or (d == "up" and -(self.cols or 1)) or (self.cols or 1)
  at = math.max(1, math.min(n, at == 0 and 1 or at + step))
  self.sel = self.items[at].path
  local px, tw, th = self:tile_size()             -- (scrolled to it)
  local row = math.floor((at - 1) / (self.cols or 1))
  local g = self:layout().grid
  local top, bottom = row * (th + S(8)), row * (th + S(8)) + th + S(16)
  if top < self.scroll_y then self.scroll_y = top elseif bottom > self.scroll_y + g[4] then self.scroll_y = bottom - g[4] end
  core.redraw = true
end

local function active() return core.active_view and core.active_view:is(CView) and not Field.focused(core.active_view.field) end
command.add(active, {
  ["content:open"] = function() core.active_view:open() end,
  ["content:up"] = function() core.active_view:go_up() end,
  ["content:back"] = function() core.active_view:go_back() end,
  ["content:forward"] = function() core.active_view:go_forward() end,
  ["content:refresh"] = function() THUMBS = {}; games = {}; core.active_view:refresh() end,
  ["content:find"] = function() core.active_view:focus_field() end,
  ["content:rename"] = function() local v = core.active_view; local e = v:selected(); if e then v:rename(e) end end,
  ["content:trash"] = function() local v = core.active_view; local e = v:selected(); if e then v:trash(e) end end,
  ["content:left"] = function() core.active_view:move_sel("left") end,
  ["content:right"] = function() core.active_view:move_sel("right") end,
  ["content:previous-row"] = function() core.active_view:move_sel("up") end,
  ["content:next-row"] = function() core.active_view:move_sel("down") end,
})
if not package.loaded["content.keys"] then
  package.loaded["content.keys"] = true
  keymap.add {
    ["return"] = "content:open", ["backspace"] = "content:up", ["alt+left"] = "content:back", ["alt+right"] = "content:forward",
    ["f5"] = "content:refresh", ["ctrl+f"] = "content:find", ["f2"] = "content:rename", ["delete"] = "content:trash",
    ["left"] = "content:left", ["right"] = "content:right", ["up"] = "content:previous-row", ["down"] = "content:next-row",
  }
end

-- where it comes from: `replay some/folder/` (data/replay.lua: lite_open), the main menu, Open tab with
openwith.register {
  key = "content", name = "Content browser", order = 5,
  can = function(path) local i = system.get_file_info(path); return i and i.type == "dir" end,
  open = function(path) return CView({ dir = path }) end,
  is = function(v) return v.is and v:is(CView) end,
}
P.menu(CView, function() return core.active_view:menu_items() end)
P.view(CView)
P.commands = { { "Open", "content:open" }, { "Up a folder", "content:up" }, { "Refresh", "content:refresh" }, { "Search", "content:find" } }
P.tab = function()                                 -- (the main menu: the game's folder, else where the editor started)
  local wf = host_world_file and host_world_file()
  local dir = wf and wf ~= "" and ((system.get_file_info(wf) or {}).type == "dir" and wf or dir_of(wf)) or system.absolute_path(".")
  return CView({ dir = dir })
end
CView.parse, CView.passes, CView.glob, CView.THUMBS = parse, passes, glob, function() return THUMBS end   -- (tests)
load_types()
load_config()
return CView
