-- tilemap_decals.lua - the tilemap editor's decals layers (plugins/tilemap):
-- + decals adds one (its z after the others), a click places the picked tile
-- (no grid), a drag moves it, , / . turn it, H flips it, = scales it, undo,
-- RMB removes; saved, read back (map.lua), as a game reads it (runtime/tmap.lua:
-- decals, order); a layer's z changes the order.
--   replay games/pong.lua --stop --lite "dofile('runtime/tests/tilemap_decals.lua')@3" --frames 100000 --shot x.bmp
local core = require "core"
local command = require "core.command"
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local function done()
    print(string.format("tilemap decals: %d checks ok, %d failed", ok_n, fail_n))
    if os.getenv("NG_EXIT") then os.exit(0) end
  end
  local ok, err = xpcall(function()
    local path = "tilemap_decals_test.tmap"
    do
      local f = io.open("plugins/tilemap/samples/island.tmap", "rb"); local s = f:read("*a"); f:close()
      f = io.open(path, "wb"); f:write(s); f:close()
    end
    local v = require("plugins.openwith").open("tilemap", path)
    coroutine.yield(0.3)
    check(v and v.map, "the map is open")
    if not (v and v.map) then return end
    local n = #v.map.layers
    v:add_layer("decals")
    local l = v.map.layers[v.layer]
    check(v.layer == n + 1 and l.kind == "decals" and l.z == n + 1, "+ decals: a decals layer, z after the others (" .. tostring(l.z) .. ")")
    v.sel = { 37, 37 }
    v:on_canvas_pressed("left", 40.4, 21.6, 1)
    v:on_mouse_released("left", 0, 0)
    local d = l.decals[1]
    check(d and d.tile == 37 and d.x == 40 and d.y == 22 and v.decal == 1, "a click: the picked tile placed there, no grid")
    v:on_canvas_pressed("left", 41, 22, 1)                    -- (on it: picked, dragged)
    local sx, sy = v:to_screen(61, 52)
    v:on_mouse_moved(sx, sy, 0, 0)
    v:on_mouse_released("left", sx, sy)
    check(#l.decals == 1 and d.x == 60 and d.y == 52, "dragged: " .. d.x .. "," .. d.y)
    core.set_active_view(v)
    command.perform("tilemap:decal-right"); command.perform("tilemap:decal-right")
    command.perform("tilemap:decal-flip"); command.perform("tilemap:decal-bigger")
    check(d.deg == 30 and d.flip == true and math.abs(d.scale - 1.25) < 1e-6, "turned 30, flipped, 1.25 x")
    v:undo_step(true)
    l = v.map.layers[v.layer]; d = l.decals[1]
    check(math.abs((d.scale or 1) - 1) < 1e-6 and d.flip == true, "undo: the scale back")
    v.sel = { 5, 5 }
    v:on_canvas_pressed("left", 100, 100, 1); v:on_mouse_released("left", 0, 0)
    check(#l.decals == 2, "a second one")
    local sx2, sy2 = v:to_screen(100, 100)
    v:on_mouse_pressed("right", sx2, sy2, 1)
    check(#l.decals == 1, "RMB: removed")
    -- a picture of its own (beside the map): placed instead of a tile
    do
      local f = io.open("plugins/tilemap/tiles.png", "rb"); local data = f:read("*a"); f:close()
      f = io.open("decal_pic_tmp.png", "wb"); f:write(data); f:close()
      v:use_decal_picture((system.absolute_path(".") or ".") .. "/decal_pic_tmp.png")
      v:on_canvas_pressed("left", 200, 120, 1); v:on_mouse_released("left", 0, 0)
      local dp = l.decals[#l.decals]
      check(dp and dp.image == "decal_pic_tmp.png" and dp.tile == nil and v:decal_at(200, 120) == #l.decals, "a picture as a decal: placed, picked by its own size")
      table.remove(l.decals)
      os.remove("decal_pic_tmp.png")
      v.sel = { 5, 5 }; v.decal_pic = nil
    end
    l.z = 0                                                    -- (under the others now)
    coroutine.yield(0.2)                                       -- (drawn: turned, flipped)
    v:save()
    local f = io.open(path, "rb"); local src = f:read("*a"); f:close()
    check(src:find('kind = "decals"', 1, true) and src:find("deg = 30", 1, true), "saved: its kind, the decal turned")
    local t = load(src, "=tmap", "t", {})()
    local Map = dofile("plugins/tilemap/map.lua")
    local m = Map.from_data(t)
    local back = m.layers[#m.layers]
    check(back.kind == "decals" and back.z == 0 and #back.decals == 1 and back.decals[1].x == 60 and back.decals[1].flip, "read back (map.lua)")
    check(Map.order(m)[1] == #m.layers, "z = 0: drawn first")
    local T = dofile("runtime/tmap.lua")
    check(#T.decals(t, back.name) == 1 and T.decals(t, 1)[1] == nil and T.order(t)[1].kind == "decals", "a game: tmap.decals, tmap.order")
    v.dirty = false
    os.remove(path)
  end, debug.traceback)
  if not ok then fail_n = fail_n + 1; print("  FAIL: " .. tostring(err)) end
  done()
end)
