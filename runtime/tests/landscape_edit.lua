-- landscape_edit.lua - the landscape editor (plugins/landscape): a sample read (the hills), drawn by the host
-- (its picture: the ground's colours), the mouse's ray onto it, the brushes (sculpt up and SHIFT down, smooth,
-- flatten, erase: back to the generator's), a stroke one undo step, the generator changed under the edits (kept),
-- another grid size (the edits stretched), save and read back the same as a game builds it (runtime/landscape.lua).
--   replay games/pong.lua --stop --lite "dofile('runtime/tests/landscape_edit.lua')@3" --frames 100000 --shot x.bmp
local core = require "core"
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local function wait(t) local e = system.get_time() + t; repeat core.redraw = true; coroutine.yield() until system.get_time() >= e end
  local path = "landscape_edit_test.land"
  local fpath = "landscape_edit_test.foliage"     -- (foliage growing on it: found beside it, shown on it)
  do
    local f = io.open("plugins/landscape/samples/hills.land", "rb"); local s = f:read("*a"); f:close()
    f = io.open(path, "wb"); f:write(s); f:close()
    f = io.open("plugins/landscape/samples/hills_meadow.foliage", "rb"); s = f:read("*a"); f:close()
    f = io.open(fpath, "wb"); f:write((s:gsub('ground = "hills.land"', 'ground = "landscape_edit_test.land"'))); f:close()
  end
  local v = require("plugins.openwith").open("landscape", path)
  wait(0.5)
  local M = v and v.M
  check(v and v.land and v.land.nx == 97 and v.land.nz == 97 and v.s.base.seed == 4, "the hills: 97 x 97 points, seed 4")
  if v and v.land then
    local L = v.land
    check(L.top > 3 and L.top <= v.s.base.height + 1e-6, "hills: up to its height: " .. string.format("%.2f", L.top))
    local m = v:rects().mid
    local cx, cy = math.floor(m[1] + m[3] / 2), math.floor(m[2] + m[4] / 2)
    local gx, gy, gz = v:ground_at(cx, cy)
    check(gx and math.abs(gy - M.height_at(L, gx, gz)) < 0.05, "the mouse's ray: on the ground under it")
    if rawget(_G, "host_view3d_pixel") then
      local w, h = host_view3d_pixel(v.key)
      local _, _, _, r, g, b = host_view3d_pixel(v.key, math.floor(w / 2), math.floor(h / 2))
      check(r and g > r and g > b, "drawn by the host: green in the middle (" .. tostring(r) .. "," .. tostring(g) .. "," .. tostring(b) .. ")")
    end
    -- the foliage on it: found, on the ground
    local it = v.fol_items
    check(v.fol and #v.fol == 1 and it and it.n > 3000, "its foliage found beside it, grown on it: " .. tostring(it and it.n))
    local function on_ground(it)
      local bad, sx = 0, 0
      local layers = v.fol[1].s.layers
      for i = 1, it.n, 7 do if math.abs(it.y[i] + layers[it.layer[i]].sink - M.height_at(v.land, it.x[i], it.z[i])) > 1e-4 then bad = bad + 1 end end
      return bad
    end
    check(it and on_ground(it) == 0, "every copy on the ground")
    -- sculpt: a stroke from the middle, one undo step
    local h0 = M.height_at(L, 0, 0)
    v.brush.tool, v.brush.radius, v.brush.strength = "sculpt", 5, 1
    local sx, sy = v:project({ 0, h0, 0 })
    v:on_mouse_pressed("left", sx, sy, 1)
    v:on_mouse_moved(sx + 30, sy, 30, 0)
    v:on_mouse_released("left", sx + 30, sy)
    local h1 = M.height_at(v.land, 0, 0)
    check(h1 > h0 + 0.2 and v.dirty and #v.undo == 1, "sculpt: up (" .. string.format("%.2f -> %.2f", h0, h1) .. "), one undo step")
    check(v.edited > 10 and v.s.edits and #v.s.edits == 97, "its edits packed: " .. tostring(v.edited) .. " points")
    check(v.fol_items and on_ground(v.fol_items) == 0, "the foliage: on the new ground (grown again at the stroke's end)")
    v:stroke_begin(0, nil, 0)                      -- (during a stroke: the copies under the brush follow, dab by dab)
    for _ = 1, 3 do v:dab(0, 0) end
    check(v.fol_items and on_ground(v.fol_items) == 0, "and dab by dab")
    v:stroke_end()
    h1 = M.height_at(v.land, 0, 0)
    -- SHIFT lowers
    v:stroke_begin(0, nil, 0, true)
    for _ = 1, 2 do v:dab(0, 0) end
    v:stroke_end()
    check(M.height_at(v.land, 0, 0) < h1 - 0.5, "SHIFT: down")
    -- flatten: to the height where it began
    v.brush.tool = "flatten"
    v:stroke_begin(10, 2, 10)
    for _ = 1, 5 do v:dab(10, 10) end
    v:stroke_end()
    check(math.abs(M.height_at(v.land, 10, 10) - 2) < 0.05, "flatten: to 2 m: " .. string.format("%.3f", M.height_at(v.land, 10, 10)))
    -- smooth: a spike evened out
    local k = (48 - 1) * v.land.nx + 30
    v.land.h[k] = v.land.h[k] + 5
    local spike = v.land.h[k]
    local px, pz = M.pos(v.land, 30, 48)
    v.brush.tool = "smooth"
    v:stroke_begin(px, nil, pz); v:stroke_end()
    check(v.land.h[k] < spike - 1, "smooth: the spike lower")
    -- erase: back to the generator's
    v.brush.tool, v.brush.radius = "erase", 30
    v:stroke_begin(0, nil, 0)
    for _ = 1, 20 do v:dab(0, 0); v:dab(10, 10) end
    v:stroke_end()
    check(math.abs(M.height_at(v.land, 0, 0) - h0) < 0.02, "erase: back to the hills' " .. string.format("%.2f", h0))
    -- undo, redo
    local n_undo = #v.undo
    v:undo_step(true)
    check(#v.undo == n_undo - 1 and math.abs(M.height_at(v.land, 0, 0) - h0) > 0.02, "undo: the erase undone")
    v:undo_step(false)
    check(math.abs(M.height_at(v.land, 0, 0) - h0) < 0.02, "redo")
    -- the generator changed: the edits stay on top
    v.brush.tool, v.brush.radius = "sculpt", 5
    v:stroke_begin(-15, nil, 5)
    for _ = 1, 3 do v:dab(-15, 5) end
    v:stroke_end()
    local up = M.height_at(v.land, -15, 5) - M.base_at(v.s.base, -15, 5)
    v:edit(function(t) t.base.seed = 77 end)
    local up2 = M.height_at(v.land, -15, 5) - M.base_at(v.s.base, -15, 5)
    check(up > 0.5 and math.abs(up - up2) < 0.05, "another seed: the edit still on top (" .. string.format("%.2f, %.2f", up, up2) .. ")")
    -- another grid size: the edits stretched over it
    v:edit(function(t) t.cells = 48 end)
    check(v.land.nx == 49 and math.abs((M.height_at(v.land, -15, 5) - M.base_at(v.s.base, -15, 5)) - up) < 0.6, "48 cells: the edit kept")
    -- colours: rock where steep
    v:edit(function(t) t.colors.rock_slope = 0; t.colors.rock = { 255, 0, 0 } end)
    local reds = 0
    for i = 1, #v.land.c do if math.floor(v.land.c[i] / 65536) > 200 then reds = reds + 1 end end
    check(reds > #v.land.c / 4, "rock from any slope: red over much of it: " .. reds)
    -- save, read back as a game would
    v:save()
    local f = io.open(path, "rb"); local src = f:read("*a"); f:close()
    local t = load(src, "=x", "t", {})()
    local G = M.build(M.check(t))
    check(G.nx == v.land.nx and math.abs(M.height_at(G, -15, 5) - M.height_at(v.land, -15, 5)) < 0.011 and not v.dirty, "saved: a game builds the same")
  end
  os.remove(path); os.remove(fpath)
  print(string.format("landscape edit: %d checks ok, %d failed", ok_n, fail_n))
  if os.getenv("NG_EXIT") then os.exit(0) end
end)
