-- canvas_graph.lua: plugins/canvas headless - a GraphView's model (connect,
-- an input reads one wire, delete, duplicate, typed pins), the camera's
-- maths, and canvas.to_lua (what a plugin saves) reading back the same.
-- Run from runtime/tests: luajit canvas_graph.lua (or lua5.4)
local dir = "../../editor/3rd/lite/data/plugins/canvas/"
SCALE, DATADIR = 1, "."
local View = {}; View.__index = View              -- (lite stubs)
function View:extend() local c = setmetatable({}, { __index = self }); c.__index = c; c.super = self; return c end
function View:new() self.position, self.size = { x = 0, y = 0 }, { x = 800, y = 600 } end
function View:is(c) local m = getmetatable(self) while m do if m == c then return true end m = m.super end return false end
function View:update() end
setmetatable(View, { __call = function(c, ...) local o = setmetatable({}, c); o:new(...); return o end })
local function callable(c) return setmetatable(c, { __index = c.super, __call = getmetatable(View).__call }) end
local stubs = {
  ["core"] = { redraw = false, add_thread = function() end, log = function() end },
  ["core.command"] = { add = function() end },
  ["core.keymap"] = { add = function() end, modkeys = {} },
  ["core.rootview"] = {},
  ["core.style"] = { error = { 1, 2, 3, 255 }, warn = { 1, 2, 3, 255 } },
  ["core.view"] = View,
  ["plugins.contextmenu"] = { DIVIDER = {}, register = function() end },
}
for k, v in pairs(stubs) do package.preload[k] = function() return v end end
for _, m in ipairs({ "theme", "draw", "view", "graph", "field", "scrollbar", "tip", "picker", "menu", "ui", "ties" }) do
  package.preload["plugins.canvas." .. m] = function() return dofile(dir .. m .. ".lua") end
end
system = { get_display_size = function() return 1920, 1080 end }
local canvas = dofile(dir .. "init.lua")

local ok, bad = 0, 0
local function check(c, what) if c then ok = ok + 1 else bad = bad + 1; print("FAIL: " .. what) end end

-- a view of two kinds
local G = canvas.GraphView:extend()
G.kinds = {
  col = { title = "Color", outs = { { "color", "color" } } },
  num = { title = "Value", outs = { { "value", "float" } } },
  mix = { title = "Mix", ins = { { "a", "color" }, { "b", "color" }, { "t", "float" } }, outs = { { "out", "color" } } },
}
callable(G)
local changes = 0
function G:on_change() changes = changes + 1 end
local v = G()
local c = v:add_node("col", 0, 0)
local m = v:add_node("mix", 200, 0)
local n = v:add_node("num", 0, 100)
check(c.id == 1 and m.id == 2 and n.id == 3, "ids count up")
v:connect(c.id, "color", m.id, "a")
v:connect(c.id, "color", m.id, "b")
check(#v.graph.links == 2, "an output feeds two inputs")
v:connect(c.id, "color", m.id, "a")
check(#v.graph.links == 2, "an input reads one wire (connecting again replaces)")
check(v:can_connect("float", "float") and not v:can_connect("float", "color") and v:can_connect("any", "color"), "pin types")
-- pins: outs first, then ins; x at the edges
local x, y = v:pin_xy(m, "out", 1)
check(x == m.x + v.node_w and y == m.y + v.head_h + 0.5 * v.row_h, "an output's pin")
x, y = v:pin_xy(m, "in", 2)
check(x == m.x and y == m.y + v.head_h + 2.5 * v.row_h, "an input's pin (after the outputs)")
local pn, side, i = v:pin_at(v:pin_xy(m, "in", 3))
check(pn == m and side == "in" and i == 3, "pin_at finds it")
check(v:node_at(m.x + 5, m.y + 5) == m, "node_at")
-- dragging a wire from Value's output to Mix's t, then a wrong type
v:on_canvas_pressed("left", v:pin_xy(n, "out", 1))
v:on_canvas_released("left", v:pin_xy(m, "in", 3))
check(v:link_into(m.id, "t") ~= nil, "a wire dragged out -> in")
v:on_canvas_pressed("left", v:pin_xy(n, "out", 1))
v:on_canvas_released("left", v:pin_xy(m, "in", 1))
local l = v:link_into(m.id, "a")
check(l and l.from == c.id, "a float can't feed a colour (the old wire stays)")
-- picking up a connected input's wire and dropping it on nothing
v:on_canvas_pressed("left", v:pin_xy(m, "in", 3))
v:on_canvas_released("left", -1000, -1000)
check(v:link_into(m.id, "t") == nil, "a wire picked up and dropped: gone")
-- moving a node drags the selection
v.sel = {}
v:on_canvas_pressed("left", m.x + 20, m.y + 5)
v:on_canvas_moved(m.x + 30, m.y + 15)
v:on_canvas_released("left", m.x + 30, m.y + 15)
check(m.x == 210 and m.y == 10, "a node dragged")
-- duplicate, delete
v:duplicate({ [c] = true })
check(#v.graph.nodes == 4 and v.graph.nodes[4].x == c.x + 24 and v.graph.nodes[4].id == 4, "duplicate")
v:remove_nodes({ [c] = true })
check(#v.graph.nodes == 3 and #v.graph.links == 0, "delete takes its wires")
check(changes > 0 and v.dirty, "edits mark it changed")

-- ties: a line dragged from a wire across two wires ties them; drag the tie; ALT+click unties
local tv = G()
local c1 = tv:add_node("col", 0, 0)
local c2 = tv:add_node("col", 0, 120)
local mx = tv:add_node("mix", 400, 40)
tv:connect(c1.id, "color", mx.id, "a")
tv:connect(c2.id, "color", mx.id, "b")
local la, lb = tv:link_into(mx.id, "a"), tv:link_into(mx.id, "b")
local ax1, ay1, ax2, ay2 = tv:wire_ends(la)
local bx1, by1, bx2, by2 = tv:wire_ends(lb)
local gx = (ax1 + ax2) / 2                         -- (a line across both, halfway)
local segs = tv:wire_segs(la)
local px, py = canvas.ties.at(segs[1], 0.5)
check(tv:wire_at(px, py) == la, "ties: the wire under a point")
tv.sel = {}
check(tv:on_canvas_pressed("left", tv:to_world(px, py)) and tv.drag and tv.drag.tieline, "ties: pressed on a wire: a tie line (no pan)")
tv:on_canvas_moved(tv:to_world(px, math.max(ay2, by2) + 200))
check(tv.drag.hint == "Tie 2 wires", "ties: the hint: " .. tostring(tv.drag.hint))
tv:on_canvas_released("left", tv:to_world(px, math.max(ay2, by2) + 200))
check(#tv.graph.ties == 1 and la.via and la.via[1] == 1 and lb.via and lb.via[1] == 1, "ties: both wires through tie 1")
local info = tv:tie_info()
local t1 = tv.graph.ties[1]
check(info.of[la] and #info.of[la] == 3 and info.count[t1] == 2, "ties: routed: in, through the tie, out")
local cxs, cys = info.centre[t1][1], info.centre[t1][2]
local ox, oy = t1.x, t1.y
tv:on_canvas_pressed("left", tv:to_world(cxs, cys))
tv:on_canvas_moved(tv:to_world(cxs + 30, cys + 10))
tv:on_canvas_released("left", tv:to_world(cxs + 30, cys + 10))
check(t1.x == ox + 30 and t1.y == oy + 10, "ties: dragged (" .. t1.x - ox .. ", " .. t1.y - oy .. ")")
local saved = canvas.to_lua({ nodes = tv.graph.nodes, links = tv.graph.links, ties = tv.graph.ties })
local back = load("return " .. saved)()
check(back.ties[1].id == 1 and back.links[1].via[1] == 1, "ties: saved with the graph")
info = tv:tie_info()
canvas_keymap = require "core.keymap"
canvas_keymap.modkeys.alt = true
tv:on_canvas_pressed("left", tv:to_world(info.centre[t1][1], info.centre[t1][2]))
canvas_keymap.modkeys.alt = false
check(#tv.graph.ties == 0 and not la.via and not lb.via, "ties: ALT+click unties")

-- a wire is under the mouse all along it, zoomed in too (its curve as drawn: the bend at the zoom)
tv.cam.zoom = 2.5
local all = true
for i = 0, 40 do
  local s2 = tv:wire_segs(la)
  local qx, qy = canvas.ties.at(s2[1], i / 40)
  local d = math.max(math.abs(s2[1][7] - s2[1][1]) * 0.5, 40 * tv:z())
  check(math.abs(s2[1][3] - s2[1][1] - d) < 1e-6, "wire hit: its bend at the zoom")
  if tv:wire_at(qx, qy + 3) ~= la then all = false end
end
check(all, "wire hit: everywhere along it, 3 px off, at 250%")
tv.cam.zoom = 1

-- ties select: a click, CTRL+click, the box; Align; DELETE (untie_ties) keeps the wires
local function line(x1, y1, x2, y2)
  tv:on_canvas_pressed("left", tv:to_world(x1, y1)); tv:on_canvas_moved(tv:to_world(x2, y2)); tv:on_canvas_released("left", tv:to_world(x2, y2))
end
segs = tv:wire_segs(la)
px, py = canvas.ties.at(segs[1], 0.4)
line(px, py, px, py + 300)                         -- tie 1: both wires
segs = tv:wire_segs(la, tv:tie_info())
local qx, qy = canvas.ties.at(segs[#segs], 0.6)
local dwx, dwy = tv:to_world(qx, qy + 2)
tv:on_canvas_pressed("left", dwx, dwy, 1); tv:on_canvas_released("left", dwx, dwy)
tv:on_canvas_pressed("left", dwx, dwy, 2)   -- tie 2: a double-click on a's wire: a control point there
tv:on_canvas_released("left", tv:to_world(qx, qy + 2))
check(#tv.graph.ties == 2, "ties select: two ties (a double-click on a wire: a control point): " .. #tv.graph.ties)
local tw = tv.graph.ties[2]
local twx, twy = tv:to_world(qx, qy)
check(tw and math.abs(tw.x - twx) <= 2 and math.abs(tw.y - twy) <= 2, "the control point: where it was clicked")
local cx0, cy0, cz0 = tv.cam.x, tv.cam.y, tv.cam.zoom
local fx, fy = tv:to_world(-3000, -3000)
tv:on_canvas_pressed("left", fx, fy, 2)
check(tv.cam.x == cx0 and tv.cam.y == cy0 and tv.cam.zoom == cz0, "a double-click on nothing: the camera stays")
local T1, T2 = tv.graph.ties[1], tv.graph.ties[2]
info = tv:tie_info()
local p1, p2 = info.centre[T1], info.centre[T2]
tv:on_canvas_pressed("left", tv:to_world(p1[1], p1[2])); tv:on_canvas_released("left", tv:to_world(p1[1], p1[2]))
check(tv.sel_ties[T1] and not tv.sel_ties[T2] and next(tv.sel) == nil, "ties select: a click selects it")
canvas_keymap.modkeys.ctrl = true
tv:on_canvas_pressed("left", tv:to_world(p2[1], p2[2])); tv:on_canvas_released("left", tv:to_world(p2[1], p2[2]))
canvas_keymap.modkeys.ctrl = false
check(#tv:selected_ties() == 2, "ties select: CTRL+click adds")
tv:on_canvas_pressed("left", tv:to_world(-3000, -3000)); tv:on_canvas_released("left", tv:to_world(-3000, -3000))
check(#tv:selected_ties() == 0, "ties select: a click on nothing clears")
local bx0, by0, bx1, by1
for m = 5, 40, 5 do                                -- (a corner off the wires: a press there boxes)
  local a0, b0 = math.min(p1[1], p2[1]) - m, math.min(p1[2], p2[2]) - m
  if not tv:wire_at(a0, b0) and not tv:node_at(tv:to_world(a0, b0)) and not canvas.ties.tie_at(tv:tie_info(), tv.graph.ties, a0, b0, tv:z()) then
    bx0, by0 = a0, b0
    bx1, by1 = math.max(p1[1], p2[1]) + m, math.max(p1[2], p2[2]) + m
    break
  end
end
tv:on_canvas_pressed("left", tv:to_world(bx0, by0))
check(tv.drag and tv.drag.box, "ties select: LMB on nothing: the box")
tv:on_canvas_moved(tv:to_world(bx1, by1)); tv:on_canvas_released("left", tv:to_world(bx1, by1))
check(#tv:selected_ties() == 2, "ties select: the box holds both: " .. #tv:selected_ties())
tv.mx, tv.my = p1[1], p1[2]
local names = {}
for _, it in ipairs(tv:menu_items()) do names[#names + 1] = it.text end
names = table.concat(names, ",")
check(names == "Align,Untie 2", "ties select: RMB on one: " .. names)
tv:align("middle")
check(T1.y == T2.y, "ties select: aligned: a row (" .. T1.y .. ", " .. T2.y .. ")")
local nl = #tv.graph.links
tv:untie_ties(tv:selected_ties())
check(#tv.graph.ties == 0 and #tv.graph.links == nl and not la.via, "ties select: untied, the wires stay")

-- the camera
local cv = callable(canvas.View:extend())()
cv.position, cv.size = { x = 100, y = 50 }, { x = 400, y = 300 }
cv.cam = { x = 10, y = 20, zoom = 2 }
local sx, sy = cv:to_screen(5, 5)
check(sx == 120 and sy == 80, "to_screen")
local wx, wy = cv:to_world(sx, sy)
check(wx == 5 and wy == 5, "to_world")
cv:zoom_at(2, 300, 200)
local ax, ay = cv:to_world(300, 200)
check(math.abs(ax - (300 - 110) / 2) < 1e-9 and cv.cam.zoom == 4, "zoom_at keeps the point under the mouse")
function cv:bounds() return 0, 0, 100, 50 end
cv:fit(1)
local x1, y1 = cv:to_screen(0, 0)
local x2, y2 = cv:to_screen(100, 50)
check(math.abs((x2 - x1) - 400) < 1e-9 and math.abs((x1 + x2) / 2 - 300) < 1e-9 and math.abs((y1 + y2) / 2 - 200) < 1e-9, "fit: the bounds fill the view, centred")
check(cv.fitting, "fit: fitting (it fits again when resized)")
cv:pan_by(1, 1)
check(not cv.fitting, "a pan stops fitting")
check(canvas.draw.vh(10) == 108 and canvas.draw.vw(50) == 960, "vh / vw: a share of the monitor")

-- to_lua reads back the same
local data = { nodes = { { id = 1, kind = "col", x = -3, y = 0.35, data = { 0.95, 0.55, 0.2 } } },
               links = { { from = 1, out = "color", to = 2, input = "a" } }, ["end"] = true, [10] = "x" }
local src = canvas.to_lua(data)
local back = load("return " .. src, "=to_lua", "t", {})()
local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, x in pairs(a) do if not same(x, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
check(same(data, back), "to_lua reads back the same")
check(src:find("0.35", 1, true) and not src:find("0.3499", 1, true), "to_lua: short numbers")

print(bad == 0 and ("canvas graph: " .. ok .. " checks ok") or ("canvas graph: " .. bad .. " failed"))
os.exit(bad == 0 and 0 or 1)
