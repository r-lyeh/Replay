-- tilemap_shapes.lua - the tilemap editor's Area and Spline tools, and a Tiled
-- map opened in it (plugins/tilemap: editor.lua, tmx.lua): an area dragged out,
-- moved, sized, renamed, given props; a spline clicked, finished, a point
-- dragged; undo; saved and read back (areas, paths); a .tmx read into a map,
-- saved as a .tmap beside it.
--   replay games/pong.lua --stopped --lite "dofile('runtime/tests/tilemap_shapes.lua')@3" --frames 100000 --shot x.bmp
local core = require "core"
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local function done()
    print(string.format("tilemap shapes: %d checks ok, %d failed", ok_n, fail_n))
    if os.getenv("NG_EXIT") then os.exit(0) end
  end
  local path = "tilemap_shapes_test.tmap"
  do
    local f = io.open("plugins/tilemap/samples/island.tmap", "rb"); local s = f:read("*a"); f:close()
    f = io.open(path, "wb"); f:write(s); f:close()
  end
  local v = require("plugins.openwith").open("tilemap", path)
  coroutine.yield(0.3)
  check(v and v.map, "the map is open")
  if not (v and v.map) then return done() end
  local T = v.map.tile
  -- an area: dragged out (on the half-cell grid), moved, sized
  v.tool = "area"
  local n0 = #(v.map.areas or {})
  v:on_canvas_pressed("left", 2 * T + 1, 2 * T + 1, 1)
  v:shape_move(6 * T + 2, 4 * T + 3)
  v:shape_release()
  local a = v.map.areas[n0 + 1]
  check(a and a.x == 2 * T and a.y == 2 * T and a.w == 4 * T and a.h == 2 * T and a.name == "area " .. (n0 + 1), "an area dragged out: " .. tostring(a and (a.x .. "," .. a.y .. " " .. a.w .. "x" .. a.h)))
  v:on_canvas_pressed("left", 3 * T, 3 * T, 1)               -- (inside it: picked, moved by whole steps)
  v:shape_move(4 * T, 3 * T)
  v:shape_release()
  check(a.x == 3 * T and a.y == 2 * T, "moved a cell right")
  v:on_canvas_pressed("left", a.x + a.w, a.y + a.h, 1)       -- (its corner: sized)
  v:shape_move(a.x + 6 * T, a.y + 3 * T)
  v:shape_release()
  check(a.w == 6 * T and a.h == 3 * T, "sized by its corner")
  local before = #v.map.areas
  v:on_canvas_pressed("left", 20 * T, 15 * T, 1)              -- (a click, no drag: no area)
  v:shape_release()
  check(#v.map.areas == before, "a click: no area")
  a.name = "spawn"; a.props = { team = 2 }
  -- a spline: points clicked, Enter ends it; a point dragged
  v.tool = "spline"
  v:on_canvas_pressed("left", 1 * T, 1 * T, 1)
  v:on_canvas_pressed("left", 8 * T, 1 * T, 1)
  v:on_canvas_pressed("left", 8 * T, 8 * T, 1)
  check(v.building and #v.map.paths[v.building].points == 6, "a spline: three points")
  core.set_active_view(v)
  require("core.command").perform("tilemap:spline-done")   -- (Enter)
  check(not v.building and #v.map.paths == 1, "Enter: done")
  local p = v.map.paths[1]
  v:on_canvas_pressed("left", 8 * T, 1 * T, 1)                -- (its 2nd point: dragged)
  v:shape_move(9 * T, 2 * T)
  v:shape_release()
  check(p.points[3] == 9 * T and p.points[4] == 2 * T, "a point dragged")
  -- undo / redo
  v:undo_step(true)
  check(v.map.paths[1] and v.map.paths[1].points[3] == 8 * T, "undo: the point back")
  v:undo_step(false)
  check(v.map.paths[1].points[3] == 9 * T, "redo")
  -- saved, read back
  v:save()
  local f = io.open(path, "rb"); local text = f:read("*a"); f:close()
  local t = load(text, "=tmap", "t", {})()
  check(t.areas and t.areas[#t.areas].name == "spawn" and t.areas[#t.areas].props.team == 2 and t.paths and #t.paths[1].points == 6, "saved: areas and paths")
  local Tmap = dofile("runtime/tmap.lua")
  check(#Tmap.areas_at(t, 4 * T, 3 * T) >= 1 and Tmap.area(t, "spawn") ~= nil, "a game reads them (runtime/tmap.lua)")
  os.remove(path)
  -- a Tiled map, opened here: read, saved as a .tmap beside it
  local tmx = "tilemap_shapes_test.tmx"
  f = io.open(tmx, "wb")
  f:write('<?xml version="1.0"?><map orientation="orthogonal" width="3" height="2" tilewidth="16" tileheight="16">'
    .. '<tileset firstgid="1" columns="16"><image source="plugin_tiles.png"/></tileset>'
    .. '<layer name="g" width="3" height="2"><data encoding="csv">1,2,3,0,0,4</data></layer>'
    .. '<objectgroup name="o"><object id="1" name="door" x="16" y="0" width="16" height="16"/></objectgroup></map>')
  f:close()
  local tv = require("plugins.openwith").open("tilemap", tmx)
  coroutine.yield(0.2)
  check(tv and tv.map and tv.map.w == 3 and tv.map.h == 2 and tv.map.layers[1].cells[3] == 2, "a .tmx: read")
  check(tv and tv.filename:match("tilemap_shapes_test%.tmap$") and tv.dirty and tv.map.areas[1].name == "door", "a .tmx: to be saved as a .tmap, its objects areas")
  if tv then tv:save() end
  check(io.open("tilemap_shapes_test.tmap", "rb") ~= nil, "a .tmx: saved as a .tmap beside it")
  os.remove(tmx); os.remove("tilemap_shapes_test.tmap")
  done()
end)
