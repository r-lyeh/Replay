-- arrange.lua - NodeGraphView: align / space / tidy the selected nodes, and
-- snippets (a selection saved as a file, added again from the Add menu).
-- Moving nodes is writing their tags' dx / dy (as a drag does): one undo step.
-- Selected ties align too (points: no size), Tidy leaves them be.
--
--   v:arrange("left" | "centre" | "right" | "top" | "middle" | "bottom" | "across" | "down" | "tidy")
--   v:save_snippet(name) / v:snippets() -> { { name, file } } / v:add_snippet(file, gx, gy)
local core = require "core"
local NodeGraphView = require "plugins.nodegraph.class"
local U = require "plugins.nodegraph.util"
local drag_roots = U.drag_roots

local GAP = 30                                     -- (tidy / space: graph units between nodes)

-- each root's box: { it = { node, el }, x, y, w, h }
local function boxes(sel)
  local out = {}
  for _, it in ipairs(drag_roots(sel)) do
    local el = it[2]
    local x, y, w, h = el.x or it[1].x, el.y or it[1].y, el.w or it[1].w or 0, el.h or it[1].h or 0
    out[#out + 1] = { it = it, x = x, y = y, w = w, h = h }
  end
  return out
end

-- the moves (b.nx, b.ny: where each box goes) written as one change of the text
local function write_moves(self, list)
  local tags, extra, src = {}, {}, nil
  for _, b in ipairs(list) do
    local ddx, ddy = math.floor((b.nx or b.x) - b.x + 0.5), math.floor((b.ny or b.y) - b.y + 0.5)
    if b.tie then                                  -- (a tie: its --@tie line)
      if ddx ~= 0 or ddy ~= 0 then
        src = src or self.doc:get_text(1, 1, math.huge, math.huge)
        extra[#extra + 1] = self.tie_edit(src, b.tie, ddx, ddy)
      end
    elseif ddx ~= 0 or ddy ~= 0 then
      tags[#tags + 1] = { b.it[1], function(t)
        local nx = (tonumber(t.vals.dx) or 0) + ddx
        local ny = (tonumber(t.vals.dy) or 0) + ddy
        self.set_val(t, "dx", nx ~= 0 and tostring(nx) or nil)
        self.set_val(t, "dy", ny ~= 0 and tostring(ny) or nil)
      end }
    end
  end
  if #tags + #extra == 0 then return 0 end
  self:write_tags(tags, extra)
  return #tags + #extra
end

-- tidy: columns by how far along the wires each node is (among the selected:
-- a node after the ones it reads), rows in each column by where they were
local function tidy(self, list)
  local of, ids = {}, {}
  for _, b in ipairs(list) do of[b.it[1]] = b; if b.it[1].id then ids[b.it[1].id] = b end end
  local feeds = {}                                 -- box -> the selected boxes it reads from
  local function link(from, to)
    local a, c = ids[from], ids[to]
    if a and c and a ~= c then feeds[c] = feeds[c] or {}; feeds[c][a] = true end
  end
  for _, l in ipairs(self.g and self.g.links or {}) do link(l.from, l.to) end
  for _, e in ipairs(self.g and self.g.exec or {}) do if not e.back and not e.jump then link(e.from, e.to) end end
  local depth, busy = {}, {}
  local function d(b)
    if depth[b] then return depth[b] end
    if busy[b] then return 0 end                   -- (a loop: cut there)
    busy[b] = true
    local m = 0
    for a in pairs(feeds[b] or {}) do m = math.max(m, d(a) + 1) end
    busy[b] = nil
    depth[b] = m
    return m
  end
  local cols, x0, y0 = {}, math.huge, math.huge
  for _, b in ipairs(list) do
    local k = d(b) + 1
    cols[k] = cols[k] or {}
    table.insert(cols[k], b)
    x0, y0 = math.min(x0, b.x), math.min(y0, b.y)
  end
  local x = x0
  for k = 1, #list do
    local col = cols[k]
    if col then
      table.sort(col, function(p, q) if p.y ~= q.y then return p.y < q.y end return p.x < q.x end)
      local y, w = y0, 0
      for _, b in ipairs(col) do
        b.nx, b.ny = x, y
        y = y + b.h + GAP
        w = math.max(w, b.w)
      end
      x = x + w + GAP * 2
    end
  end
end

function NodeGraphView:arrange(how)
  if self.doc:get_change_id() ~= self.change_id then return self:flash("the text changed meanwhile: try again") end
  local list = boxes(self:selection())
  if how ~= "tidy" and self.selected_ties then
    for _, t in ipairs(self:selected_ties()) do list[#list + 1] = { tie = t, x = t.x, y = t.y, w = 0, h = 0 } end
  end
  if #list < (how == "tidy" and 1 or 2) then return self:flash("select the nodes or ties to arrange (two or more)") end
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, b in ipairs(list) do x0, y0, x1, y1 = math.min(x0, b.x), math.min(y0, b.y), math.max(x1, b.x + b.w), math.max(y1, b.y + b.h) end
  if how == "left" then for _, b in ipairs(list) do b.nx = x0 end
  elseif how == "right" then for _, b in ipairs(list) do b.nx = x1 - b.w end
  elseif how == "centre" then local c = (x0 + x1) / 2; for _, b in ipairs(list) do b.nx = c - b.w / 2 end
  elseif how == "top" then for _, b in ipairs(list) do b.ny = y0 end
  elseif how == "bottom" then for _, b in ipairs(list) do b.ny = y1 - b.h end
  elseif how == "middle" then local c = (y0 + y1) / 2; for _, b in ipairs(list) do b.ny = c - b.h / 2 end
  elseif how == "across" or how == "down" then     -- (the same gap between each, in their order; the ends stay)
    local ax = how == "across"
    table.sort(list, function(p, q) if ax then return p.x < q.x end return p.y < q.y end)
    local total = 0
    for _, b in ipairs(list) do total = total + (ax and b.w or b.h) end
    local gap = ((ax and (x1 - x0) or (y1 - y0)) - total) / (#list - 1)
    if gap < GAP then gap = GAP end                -- (too tight: spread out, from the first)
    local at = ax and x0 or y0
    for _, b in ipairs(list) do
      if ax then b.nx = at; at = at + b.w + gap else b.ny = at; at = at + b.h + gap end
    end
  elseif how == "tidy" then tidy(self, list)
  else return end
  local n = write_moves(self, list)
  self:flash(n == 0 and "already so" or (how == "tidy" and "tidied" or "aligned") .. " (" .. n .. ")")
end

-- snippets: plugins/nodegraph/snippets/<name>.lua, the selection's code (as
-- Copy has it), its own locals written $name so a clash is renamed when added
local function snippet_dir()
  local root = rawget(_G, "REPLAY_ROOT") or (DATADIR .. "/../../..")
  return root .. "/plugins/nodegraph/snippets"
end
NodeGraphView.snippet_dir = snippet_dir
local function placeholders(text)                  -- its locals -> $name (renamed if the file has them already)
  local names = {}
  for list in text:gmatch("%f[%w_]local%s+function%s+([%a_][%w_]*)") do names[list] = true end
  for list in text:gmatch("%f[%w_]local%s+([%a_][%w_]*%s*[,%a_%w%s]*)") do
    for nm in list:gmatch("[%a_][%w_]*") do if nm ~= "function" then names[nm] = true end end
  end
  for nm in pairs(names) do                        -- (not after a dot or colon: a field of that name stays)
    text = text:gsub("()%f[%w_]" .. nm .. "%f[^%w_]", function(at)
      local before = text:sub(at - 1, at - 1)
      if before == "." or before == ":" or before == "$" then return nil end
      return "$" .. nm
    end)
  end
  return text
end
NodeGraphView.snippet_placeholders = placeholders
function NodeGraphView:save_snippet(name)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local file = name:gsub("[^%w_%- ]", ""):gsub("%s+", "_"):lower()
  if file == "" then return self:flash("a snippet needs a name", true) end
  local list = self:selection()
  if #list == 0 then return self:flash("select the nodes to keep") end
  local text = self:selection_text(list)
  if text == "" then return self:flash("nothing to keep there") end
  local dir = snippet_dir()
  if rawget(system, "mkdir") then pcall(system.mkdir, dir) end   -- (the folder ships with the plugin)
  local path = dir .. "/" .. file .. ".lua"
  local f = io.open(path, "wb")
  if not f then return self:flash("can't write " .. path, true) end
  f:write("-- snippet: ", name, "\n", placeholders(text), "\n")
  f:close()
  self:flash("snippet saved: " .. name)
  return path
end
function NodeGraphView:snippets()
  local out, dir = {}, snippet_dir()
  for _, f in ipairs(system.list_dir(dir) or {}) do
    if f:match("%.lua$") then
      local fh = io.open(dir .. "/" .. f, "rb")
      local first = fh and fh:read("*l") or ""
      if fh then fh:close() end
      out[#out + 1] = { name = first:match("^%-%- snippet: (.+)$") or f:gsub("%.lua$", ""):gsub("_", " "), file = dir .. "/" .. f }
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end
function NodeGraphView:add_snippet(file, gx, gy)
  local fh = io.open(file, "rb")
  if not fh then return self:flash("can't read " .. file, true) end
  local text = fh:read("*a"):gsub("\r\n?", "\n"):gsub("^%-%- snippet:[^\n]*\n", ""):gsub("%s+$", "")
  fh:close()
  local name = file:match("([^/\\]+)%.lua$") or "snippet"
  return self:add_node({ name = "Snippet " .. name:gsub("_", " "), text = text }, gx, gy)
end
function NodeGraphView:ask_snippet()
  core.command_view:enter("Snippet name", function(text) self:save_snippet(text) end)
end

-- the Add menu's Snippets (and the selection's menu: Align > (Tidy last), Save as snippet)
function NodeGraphView:snippet_items(gx, gy)
  local items = {}
  for _, s in ipairs(self:snippets()) do
    items[#items + 1] = { text = s.name, tags = "snippet", fn = function() self:add_snippet(s.file, gx, gy) end }
  end
  if #items == 0 then items[1] = { text = "(none yet: select nodes, RMB > Save as snippet)", dim = true } end
  return items
end
function NodeGraphView:arrange_items()
  local function a(text, how) return { text = text, fn = function() self:arrange(how) end } end
  return {
    { text = "Align", sub = { a("Left edges", "left"), a("Centres", "centre"), a("Right edges", "right"),
                              a("Tops", "top"), a("Middles", "middle"), a("Bottoms", "bottom"),
                              a("Space across", "across"), a("Space down", "down"), a("Tidy", "tidy") } },
    { text = "Save as snippet...", fn = function() self:ask_snippet() end },
  }
end

return NodeGraphView
