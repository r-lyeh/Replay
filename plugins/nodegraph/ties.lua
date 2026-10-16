-- ties.lua - NodeGraphView: wires tied together (part of the nodegraph
-- plugin, ours; the geometry and the look: plugins/canvas/ties.lua, shared
-- with the material editor). Drag a line across wires, starting on one (LMB:
-- on empty space it's the selection box, as always) or anywhere with
-- SHIFT+RMB: across one wire, a control point it bends through; across
-- several, a tie: they run side by side through it, like a cable tie holds
-- them, in the order that crosses least; across a tie as well: the wires
-- crossed join it. Data wires and flow wires alike. Drag a tie (or a point)
-- to move them all; ALT+click one to remove it. Ties select like nodes: a
-- click (SHIFT / CTRL: toggle), or the selection box; dragging a selected
-- one moves them all, DELETE unties them (the wires stay), RMB: Align.
-- self.sel_ties = { [id] = true } (ids: kept across rebuilds).
--
-- In the text (graph.lua): `--@tie id=t1 dx= dy=` at the top of the function
-- the first wire ends in (from its header, like a comment box), and on the
-- tag of each wire's input node `via=<input>:t1/t2` (its flow wires:
-- `@flow:t1`): the ties it passes, in order. Undo, diffs and the text view
-- see them like any other edit.
local core = require "core"
local keymap = require "core.keymap"
local graph = require "plugins.nodegraph.graph"
local resolve = require "plugins.nodegraph.resolve"
local NodeGraphView = require "plugins.nodegraph.class"
local U = require "plugins.nodegraph.util"
local TI = require "plugins.canvas.ties"
local indent_at, frame_of, frame_of_node = U.indent_at, U.frame_of, U.frame_of_node

local FLOW = "@flow"                               -- (the via key of a node's flow wires)

-- the screen point of a tie (its drag shown live)
local function tie_xy(self, t, ox, oy)
  local z = self.zoom
  local d = self.tie_drag
  local dx, dy = 0, 0
  if d and (d.tie == t or (d.group and d.group[t.id])) then dx, dy = d.dx, d.dy end
  return ox + (t.x + dx) * z, oy + (t.y + dy) * z
end

-- every wire the ties route, worked out once a frame
local function flow_ends(self, e, ox, oy)
  local a, b = self.by_id[e.from], self.by_id[e.to]
  if e.jump or not (a and b and a.xouts and a.xouts[e.out] and b.xin) then return nil end
  local x1, y1 = self:exec_xy(a, "out", e.out, ox, oy)
  local x2, y2 = self:exec_xy(b, "in", 1, ox, oy)
  return x1, y1, x2, y2
end
function NodeGraphView:tie_routes(ox, oy)
  local g = self.g
  if not g or not g.ties or #g.ties == 0 then return nil end
  local wires, of, sig = {}, {}, { ox, oy, self.zoom, tostring(g) }
  for _, l in ipairs(g.links) do
    if l.via then
      local a, b = self.by_id[l.from], self.by_id[l.to]
      local x1, y1 = self:socket_xy(a, "out", l.out, ox, oy)
      local x2, y2 = self:socket_xy(b, "in", l.inp, ox, oy)
      local w = { x1, y1, x2, y2, via = l.via }
      wires[#wires + 1] = w; of[l] = w
      sig[#sig + 1] = x1; sig[#sig + 1] = y1; sig[#sig + 1] = x2; sig[#sig + 1] = y2
    end
  end
  for _, e in ipairs(g.exec) do
    if e.via then
      local x1, y1, x2, y2 = flow_ends(self, e, ox, oy)
      if x1 then
        local w = { x1, y1, x2, y2, via = e.via }; wires[#wires + 1] = w; of[e] = w
        sig[#sig + 1] = x1; sig[#sig + 1] = y1; sig[#sig + 1] = x2; sig[#sig + 1] = y2
      end
    end
  end
  for _, t in ipairs(g.ties) do local x, y = tie_xy(self, t, ox, oy); sig[#sig + 1] = x; sig[#sig + 1] = y end
  local key = table.concat(sig, "|")               -- (the ends and the ties where they are now: a node dragged, a tie moved)
  if self.tie_cache and self.tie_cache.key == key then return self.tie_cache end
  local info = TI.route(wires, function(t) return tie_xy(self, t, ox, oy) end, self.zoom)
  local segs = {}
  for obj, w in pairs(of) do segs[obj] = info.segs[w] end
  info.of = segs
  info.key = key
  self.tie_cache = info
  return info
end

-- a wire's curves (screen space): its route through its ties, or none (nil)
function NodeGraphView:link_segs(l, ox, oy)
  local r = l.via and self:tie_routes(ox, oy)
  if r and r.of[l] then return r.of[l] end
  local a, b = self.by_id[l.from], self.by_id[l.to]
  local x1, y1 = self:socket_xy(a, "out", l.out, ox, oy)
  local x2, y2 = self:socket_xy(b, "in", l.inp, ox, oy)
  return TI.plain(x1, y1, x2, y2, self.zoom * SCALE)   -- (as drawn: its bend at the zoom)
end
function NodeGraphView:flow_segs(e, ox, oy)       -- (a flow wire through ties; nil: it has none)
  local r = e.via and self:tie_routes(ox, oy)
  return r and r.of[e]
end
NodeGraphView.seg_at = TI.at
NodeGraphView.near_segs = TI.near
NodeGraphView.segs_mid = TI.mid

function NodeGraphView:draw_ties(ox, oy)
  local r = self:tie_routes(ox, oy)
  if not r then return end
  local shown = {}
  for _, t in ipairs(self.g.ties) do if #t.links > 0 then shown[#shown + 1] = t end end   -- (its wires gone: nothing to show)
  local sel
  for _, t in ipairs(shown) do if self.sel_ties and self.sel_ties[t.id] then sel = sel or {}; sel[t] = true end end
  TI.draw(r, shown, self.hover_tie or (self.tie_drag and self.tie_drag.tie), self.zoom, nil, sel)
end

-- the selected ties (of the graph shown), in the file's order
function NodeGraphView:selected_ties()
  local out = {}
  if not (self.g and self.sel_ties) then return out end
  for _, t in ipairs(self.g.ties or {}) do if self.sel_ties[t.id] and #t.links > 0 then out[#out + 1] = t end end
  return out
end
function NodeGraphView:select_ties(list, add)      -- (add: to the selection; else they're all of it, nodes too)
  if not add then self.sel_ties = {}; self.sel = {}; self.selected = nil end
  self.sel_ties = self.sel_ties or {}
  for _, t in ipairs(list) do self.sel_ties[t.id] = true end
  core.redraw = true
end
function NodeGraphView:ties_in_box(x1, y1, x2, y2)  -- (screen)
  local ox, oy = self:origin()
  local r = self:tie_routes(ox, oy)
  local shown = {}
  for _, t in ipairs(self.g and self.g.ties or {}) do if #t.links > 0 then shown[#shown + 1] = t end end
  return TI.in_box(r, shown, x1, y1, x2, y2)
end
function NodeGraphView:tie_at(x, y)
  local ox, oy = self:origin()
  local r = self:tie_routes(ox, oy)
  if not r then return nil end
  local shown = {}
  for _, t in ipairs(self.g.ties) do if #t.links > 0 then shown[#shown + 1] = t end end
  return TI.tie_at(r, shown, x, y, self.zoom)
end

-- a wire's curves (screen): a data wire (a link) or a flow wire (exec)
function NodeGraphView:wire_item_segs(item)
  local ox, oy = self:origin()
  if item.inp then return self:link_segs(item, ox, oy) end
  local segs = self:flow_segs(item, ox, oy)
  if segs then return segs end
  local a, b = self.by_id[item.from], self.by_id[item.to]
  local x1, y1, x2, y2 = flow_ends(self, item, ox, oy)
  if not x1 then return nil end
  local ym = item.wrap and x2 < x1 and self:wrap_y(b, oy) or nil
  return U.exec_path(x1, y1, x2, y2, ym, self.zoom * SCALE)
end

-- the wires a drawn line crosses (data and flow), and a tie it crosses
function NodeGraphView:gesture_hits(x1, y1, x2, y2)
  local ox, oy = self:origin()
  local list = {}
  for _, l in ipairs(self.g and self.g.links or {}) do
    local a, b = self.by_id[l.from], self.by_id[l.to]
    if not l.chip and not l.pending and not (self:shown(a) == self:shown(b) and (a.proxy or b.proxy)) then
      list[#list + 1] = { item = l, segs = self:link_segs(l, ox, oy) }
    end
  end
  for _, e in ipairs(self.g and self.g.exec or {}) do
    local a, b = self.by_id[e.from], self.by_id[e.to]
    if not e.back and not e.jump and a and b and self:shown(a) ~= self:shown(b) then
      local segs = self:flow_segs(e, ox, oy)
      if not segs then
        local fx1, fy1, fx2, fy2 = flow_ends(self, e, ox, oy)
        if fx1 then
          local ym = e.wrap and fx2 < fx1 and self:wrap_y(b, oy) or nil
          segs = U.exec_path(fx1, fy1, fx2, fy2, ym, self.zoom * SCALE)
        end
      end
      if segs then list[#list + 1] = { item = e, segs = segs } end
    end
  end
  local hits = TI.hits(list, x1, y1, x2, y2)
  local r = self:tie_routes(ox, oy)
  local tie = r and TI.crosses_tie(r, self.g.ties, x1, y1, x2, y2, self.zoom)
  return hits, tie
end
function NodeGraphView:gesture_hint(g)
  local hits, tie = self:gesture_hits(g.x, g.y, g.lx, g.ly)
  if tie then
    local new = 0
    for _, h in ipairs(hits) do
      local already = false
      for _, v in ipairs(h.item.via or {}) do if v == tie then already = true end end
      if not already then new = new + 1 end
    end
    if new > 0 then return TI.hint(new, true) end
  end
  return TI.hint(#hits)
end

-- the text ---------------------------------------------------------------------

local function via_key(self, item)                 -- a wire's name in its input node's via: its input, or @flow
  if item.inp then local b = self.by_id[item.to]; return b and b.ins[item.inp] and b.ins[item.inp].name end
  return FLOW
end
local function tag_of(n) return n.edit and (n.edit.kind == "frame" and n.frame and n.frame.tag or n.edit.tag) end

-- the via lists of these nodes, changed by fn(node, lists) -> write_tags items
local function via_items(self, nodes, fn)
  local items = {}
  for n in pairs(nodes) do
    local tag = tag_of(n)
    local lists = graph.via_parse(tag and tag.vals.via)
    fn(n, lists)
    local text = graph.via_text(lists)
    items[#items + 1] = { n, function(t)
      if text and t.vals.via == nil then t.keys[#t.keys + 1] = "via" end
      t.vals.via = text
    end }
  end
  return items
end

local function new_id(self)                        -- a tie id unused in the file
  local used = {}
  for _, t in ipairs(self.g.ties or {}) do used[t.id] = true end
  local src = self.doc:get_text(1, 1, math.huge, math.huge)
  for id in src:gmatch("%-%-@tie id=([%w_]+)") do used[id] = true end
  local k = 1
  while used["t" .. k] do k = k + 1 end
  return "t" .. k
end

-- the line a new --@tie goes on, in the frame of node n: pos, indent, the frame
local function tie_place(self, src, n)
  local fr = n and frame_of_node(n)
  while fr do                                      -- a function on one line has no room: the one around it
    local nl = src:find("\n", fr.func.params_epos or fr.func.pos, true)
    if nl and nl < fr.func.epos then break end
    fr = frame_of(fr)
  end
  if not fr then return 1, "", nil end
  local nl = src:find("\n", fr.func.params_epos or fr.func.pos, true)
  local first = fr.func.body.stmts[1]
  return nl + 1, first and indent_at(src, first.pos) or (indent_at(src, fr.func.pos) .. "  "), fr
end

-- the line let go: tie the wires crossed (or add them to the tie crossed)
function NodeGraphView:tie_gesture(x1, y1, x2, y2)
  if not self.g or self.doc:get_change_id() ~= self.change_id then return end
  local hits, tie = self:gesture_hits(x1, y1, x2, y2)
  if #hits == 0 then return self:flash("draw across wires to tie them") end
  local ox, oy = self:origin()
  local z = self.zoom
  local id, place
  if tie then id = tie.id
  else
    local sx, sy = 0, 0
    for _, h in ipairs(hits) do sx, sy = sx + h.x, sy + h.y end
    place = { (sx / #hits - ox) / z, (sy / #hits - oy) / z }
    id = new_id(self)
  end
  local nodes, add = {}, {}
  for _, h in ipairs(hits) do
    local already = false
    for _, v in ipairs(h.item.via or {}) do if v.id == id then already = true end end
    if not already then
      nodes[self.by_id[h.item.to]] = true
      add[#add + 1] = h
    end
  end
  if #add == 0 then return self:flash("those wires are in that tie already") end
  local items = via_items(self, nodes, function(n, lists)
    for _, h in ipairs(add) do
      if self.by_id[h.item.to] == n then
        local list = {}
        for _, v in ipairs(h.item.via or {}) do list[#list + 1] = v.id end   -- (as the graph has it)
        local k, c = #list + 1, 0                  -- (crossed in its curve h.k: before the first tie whose curves reach it)
        local r = h.item.via and self:tie_routes(ox, oy)
        for i, v in ipairs(h.item.via or {}) do
          c = c + ((r and r.count[v] or 1) > 1 and 2 or 1)   -- (a tie: the curve into it, and the stretch through it)
          if h.k <= c then k = i break end
        end
        table.insert(list, k, id)
        lists[via_key(self, h.item)] = list
      end
    end
  end)
  local extra = {}
  if place then
    local src = self.doc:get_text(1, 1, math.huge, math.huge)
    local pos, indent, fr = tie_place(self, src, self.by_id[add[1].item.to])
    local hx, hy = fr and fr.head.x or 0, fr and fr.head.y or 0
    local t = { kind = "tie", keys = { "id", "dx", "dy" },
                vals = { id = id, dx = tostring(math.floor(place[1] - hx + 0.5)), dy = tostring(math.floor(place[2] - hy + 0.5)) } }
    extra[1] = { pos = pos, epos = pos - 1, text = indent .. graph.tag_text(t) .. "\n", seq = -1 }
  end
  self:write_tags(items, extra)
  self:flash(tie and ("tied " .. #add .. " more") or (#add == 1 and "a control point: drag it, ALT+click removes it"
             or ("tied " .. #add .. " wires: drag the tie, ALT+click unties")))
end

local function tie_edit(src, t, ddx, ddy)          -- a tie's line: moved (dx, dy added) or removed (nil)
  local ls = 1
  for _ = 2, t.tag.line do ls = (src:find("\n", ls, true) or #src) + 1 end
  local le = (src:find("\n", ls, true) or (#src + 1)) - 1
  if not ddx then return { pos = ls, epos = math.min(#src, le + 1), text = "", seq = -1 } end
  local tag = { kind = "tie", keys = {}, vals = {} }
  for _, k in ipairs(t.tag.keys) do tag.keys[#tag.keys + 1] = k; tag.vals[k] = t.tag.vals[k] end
  tag.vals.dx = tostring((tonumber(tag.vals.dx) or 0) + ddx)
  tag.vals.dy = tostring((tonumber(tag.vals.dy) or 0) + ddy)
  return { pos = ls, epos = le, text = src:match("^[ \t]*", ls) .. graph.tag_text(tag), seq = -1 }
end
NodeGraphView.tie_edit = tie_edit                  -- (arrange.lua: ties aligned)
function NodeGraphView:move_tie(t, ddx, ddy) return self:move_ties({ t }, ddx, ddy) end
function NodeGraphView:move_ties(list, ddx, ddy)   -- (one change of the text: one undo)
  if self.doc:get_change_id() ~= self.change_id then return end
  ddx, ddy = math.floor(ddx + 0.5), math.floor(ddy + 0.5)
  if ddx == 0 and ddy == 0 or #list == 0 then return end
  local src = self.doc:get_text(1, 1, math.huge, math.huge)
  local edits = {}
  for _, t in ipairs(list) do edits[#edits + 1] = tie_edit(src, t, ddx, ddy) end
  self:replace_text(src, resolve.apply(src, edits))
end
function NodeGraphView:remove_tie(t) return self:remove_ties({ t }) end
function NodeGraphView:remove_ties(list)           -- untie: their lines go, and their ids from every via (the wires stay)
  if self.doc:get_change_id() ~= self.change_id or #list == 0 then return end
  local nodes, ids, lines, points = {}, {}, {}, 0
  local src = self.doc:get_text(1, 1, math.huge, math.huge)
  for _, t in ipairs(list) do
    ids[t.id] = true
    if #t.links <= 1 then points = points + 1 end
    for _, l in ipairs(t.links) do nodes[self.by_id[l.to]] = true end
    lines[#lines + 1] = tie_edit(src, t)
    if self.sel_ties then self.sel_ties[t.id] = nil end
  end
  local items = via_items(self, nodes, function(n, lists)
    for _, l in pairs(lists) do
      for i = #l, 1, -1 do if ids[l[i]] then table.remove(l, i) end end
    end
  end)
  self:write_tags(items, lines)
  if #list > 1 then self:flash("untied " .. #list)
  else self:flash(points == 0 and "untied" or "control point removed") end
end

-- the mouse: ALT+RMB (or SHIFT+RMB) draws the line anywhere; LMB on a tie drags it, ALT+LMB
-- removes it; LMB on a wire and a drag: the line (input.lua turns its press into one)
function NodeGraphView:wire_near(x, y)            -- a wire (data or flow) within a few pixels: where a drag ties
  local l = self:wire_at(x, y)
  if l and (l.chip or l.pending) then l = nil end  -- (chips: no wire drawn)
  return l or self:exec_wire_at(x, y)
end
function NodeGraphView:ties_pressed(button, x, y, clicks)
  if button == "right" and (keymap.modkeys["alt"] or keymap.modkeys["shift"]) then   -- (ALT+RMB, or SHIFT+RMB: the line anywhere)
    self.gesture = { x = x, y = y, lx = x, ly = y }
    core.redraw = true
    return true
  end
  if button ~= "left" then return false end
  local t = self:tie_at(x, y)
  if not t then return false end
  if keymap.modkeys["alt"] then self:remove_tie(t); return true end
  local group                                      -- (a selected one: they all move)
  if self.sel_ties and self.sel_ties[t.id] then group = {}; for id in pairs(self.sel_ties) do group[id] = true end end
  self.tie_drag = { tie = t, x = x, y = y, dx = 0, dy = 0, group = group,
                    add = keymap.modkeys["shift"] or keymap.modkeys["ctrl"] }
  return true
end
function NodeGraphView:ties_moved(x, y)
  local g = self.gesture
  if g then
    g.lx, g.ly = x, y
    g.hint = self:gesture_hint(g)
    core.redraw = true
    return true
  end
  local d = self.tie_drag
  if d then
    d.dx, d.dy = (x - d.x) / self.zoom, (y - d.y) / self.zoom
    core.redraw = true
    return true
  end
  if self.press or self.rpress or self.menu then return false end
  local t = self.g and self:tie_at(x, y)
  if t ~= self.hover_tie then self.hover_tie = t; core.redraw = true end
  if t then self.cursor = "hand" return true end
  local w = self.g and not self:node_at(x, y) and not self:socket_at(x, y) and self:wire_near(x, y)   -- (a wire: drag across to tie)
  if (w and true or nil) ~= self.wire_hover then self.wire_hover = w and true or nil; core.redraw = true end
  if w then
    self.cursor = "crosshair"
    local t0 = self.wire_hint and self.wire_hint.t or system.get_time()
    self.wire_hint = { x = x, y = y, t = t0 }      -- (its hint once the mouse rests a moment)
    return true
  end
  self.wire_hint = nil
  return false
end
function NodeGraphView:ties_released(button, x, y)
  local g = self.gesture
  if g and (button == "right" or button == "left") then
    self.gesture = nil
    core.redraw = true
    if math.abs(g.lx - g.x) + math.abs(g.ly - g.y) > 4 then self:tie_gesture(g.x, g.y, g.lx, g.ly) end
    return true
  end
  local d = self.tie_drag
  if d and button == "left" then
    self.tie_drag = nil
    core.redraw = true
    if math.abs(d.dx) + math.abs(d.dy) < 0.5 then   -- a click: select it (SHIFT / CTRL: toggle)
      if d.add then
        self.sel_ties = self.sel_ties or {}
        self.sel_ties[d.tie.id] = not self.sel_ties[d.tie.id] or nil
        core.redraw = true
      else self:select_ties({ d.tie }) end
      return true
    end
    if d.group then self:move_ties(self:selected_ties(), d.dx, d.dy)
    else self:move_tie(d.tie, d.dx, d.dy) end
    return true
  end
  return false
end

function NodeGraphView:draw_gesture()
  local g = self.gesture
  if g then return TI.draw_line(g.x, g.y, g.lx, g.ly, g.hint) end
  local h = self.wire_hint                         -- (hovering a wire: what a drag from here does, after a moment)
  if h and self.wire_hover and not self.press and not self.menu then
    if system.get_time() - h.t >= 0.8 then TI.draw_line(h.x, h.y, h.x, h.y, "drag across wires to tie them")
    else core.redraw = true end
  end
end
