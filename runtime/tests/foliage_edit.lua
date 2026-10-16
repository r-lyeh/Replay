-- foliage_edit.lua - the foliage editor (plugins/foliage): a sample read, a layer's settings change the
-- scatter, a layer added and removed, the seed, undo, save; the scatter the same as a game's (runtime/foliage.lua);
-- trees by rules (variants), the brush: copies put along a stroke (spacing, erase, undo), the density painted.
--   replay games/pong.lua --stop --lite "dofile('runtime/tests/foliage_edit.lua')@3" --frames 100000 --shot x.bmp
local core = require "core"
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local path = "foliage_edit_test.foliage"
  do
    local f = io.open("plugins/foliage/samples/meadow.foliage", "rb"); local s = f:read("*a"); f:close()
    f = io.open(path, "wb"); f:write(s); f:close()
  end
  local v = require("plugins.openwith").open("foliage", path)
  coroutine.yield(0.3)
  check(v and v.s and #v.s.layers == 4 and v.s.seed == 11, "the meadow: 4 layers, seed 11")
  if v and v.items then
    local n0 = v.info.count
    check(n0 > 4000 and v.info.per[1] > 3000, "thousands of copies: " .. tostring(n0))
    local same = v.F.generate(v.s)
    check(same.n == v.items.n and same.x[10] == v.items.x[10], "the same seed, the same scatter")
    v.sel = 1
    v:edit(function(t) t.layers[1].density = 1 end)
    check(v.info.per[1] < v.info.count and v.info.per[1] <= 24 * 24 and v.dirty, "less grass: " .. tostring(v.info.per[1]))
    v:edit(function(t) t.layers[#t.layers + 1] = { name = "trees", mesh = "cube", density = 0.01, spacing = 3 } end)
    check(#v.s.layers == 5 and v.info.per[5] > 0, "a layer added: trees")
    v:edit(function(t) table.remove(t.layers, 5) end)
    check(#v.s.layers == 4, "and removed")
    local x10 = v.items.x[10]
    v:edit(function(t) t.seed = 12 end)
    check(v.items.x[10] ~= x10, "another seed: another scatter")
    v:undo_step(true)
    check(v.s.seed == 11 and v.items.x[10] == x10, "undo: the seed back")
    v:save()
    local f = io.open(path, "rb"); local s = f:read("*a"); f:close()
    check(s:find("density = 1,", 1, true) and not v.dirty, "saved")
    coroutine.yield(0.2)
    check(#v.left.hits > 0 and #v.right.hits > 5, "the panels drawn")
    if rawget(_G, "host_view3d_pixel") and v.in3d then   -- (3D: the host draws every copy, instanced)
      v:undo_step(false); v:undo_step(true)          -- (the scatter as saved)
      core.redraw = true
      coroutine.yield(0.4)
      local w, h, tris = host_view3d_pixel(v.key)
      check(w and w > 50 and tris and tris > 20000, "in 3D: the copies drawn: " .. tostring(tris) .. " triangles")
      v.in3d = false; core.redraw = true
      coroutine.yield(0.3)
      check(v.items and v.items.n > 0, "and from above")
    end
    -- trees by rules, a few of each kind; the brush (copies put by hand, where the scatter grows), a stroke one undo step
    v:edit(function(t) t.layers[#t.layers + 1] = { name = "trees", mesh = "tree", variants = 3, density = 0, size = { 4, 6, 4 }, spacing = 2 } end)
    v.sel = #v.s.layers
    check(v.items.meshes[#v.items.meshes] == "tree:3" and v.items.of[#v.items.meshes] == v.sel and v.info.per[v.sel] == 0, "a layer of trees: 3 variants, none yet")
    v.in3d = true
    local m = v:rects().mid
    local cx, cy = m[1] + m[3] / 2, m[2] + m[4] * 0.6
    local gx, gz = v:ground_at(cx, cy)
    local sx, sy
    if gx then sx, sy = v:project({ gx, v.s.y, gz }) end
    check(sx and math.abs(gx) < 12 and math.abs(sx - cx) < 1 and math.abs(sy - cy) < 1, "the ground under the mouse, and back: " .. tostring(sx) .. "," .. tostring(sy))
    check(v:ground_at(cx, m[2] + 2) == nil, "the sky: no ground")
    v.brush.mode, v.brush.radius, v.brush.density, v.brush.strength = "copies", 4, 0.4, 1
    local undos = #v.undo
    v:on_mouse_pressed("left", cx, cy, 1)
    v:on_mouse_moved(cx + m[3] * 0.15, cy, 1, 0)
    v:on_mouse_moved(cx + m[3] * 0.3, cy, 1, 0)
    v:on_mouse_released("left", cx + m[3] * 0.3, cy)
    local L = v.s.layers[v.sel]
    local put = L.points and #L.points or 0
    check(put > 3 and v.info.per[v.sel] == put and #v.undo == undos + 1, "a stroke of trees: " .. put .. " put, one undo step")
    local close = false
    for i = 1, put do for j = i + 1, put do if (L.points[i][1] - L.points[j][1]) ^ 2 + (L.points[i][2] - L.points[j][2]) ^ 2 < 4 - 1e-6 then close = true end end end
    check(not close, "no two nearer than the layer's spacing")
    local parts = {}
    for i = 1, v.items.n do if v.items.layer[i] == v.sel then parts[v.items.part[i]] = true end end
    local np = 0; for _ in pairs(parts) do np = np + 1 end
    check(np >= 2, "the variants mixed: " .. np)
    local keymap_shift = require("core.keymap").modkeys
    keymap_shift["shift"] = true
    v.brush.radius = 30
    v:on_mouse_pressed("left", cx, cy, 1); v:on_mouse_released("left", cx, cy)
    keymap_shift["shift"] = nil
    check(#v.s.layers[v.sel].points == 0, "SHIFT: erased")
    v:undo_step(true)
    check(#v.s.layers[v.sel].points == put, "undo: back")
    v.sel = 1                                      -- (the grass: painted only round one place)
    local grass = v.info.per[1]
    v.brush.mode, v.brush.radius, v.brush.strength = "density", 3, 1
    v:edit(function(t) local mm = {}; for i = 1, v.F.MASK do mm[i] = string.rep("0", v.F.MASK) end; t.layers[1].mask = mm end)
    check(v.info.per[1] == 0, "the grass: nowhere")
    v:on_mouse_pressed("left", cx, cy, 1); v:on_mouse_released("left", cx, cy)
    check(v.info.per[1] > 0 and v.info.per[1] < grass / 4, "painted in round the mouse: " .. v.info.per[1] .. " of " .. grass)
    v:save()
    local back = v.F.check(dofile(path))
    check(back.layers[1].mask and #back.layers[1].mask == v.F.MASK and #back.layers[#back.layers].points == put, "saved: the mask and the copies put")
    v.brush.mode = nil
  end
  os.remove(path)
  -- on a landscape (its ground): the hills found beside it, every copy on them, its rules kept, the brush on them
  local g = require("plugins.openwith").open("foliage", "plugins/landscape/samples/hills_meadow.foliage")
  coroutine.yield(0.3)
  check(g and g.land and g.land.nx == 97 and g.items and g.items.n > 3000, "on hills.land: found beside it, grown on it: " .. tostring(g and g.items and g.items.n))
  if g and g.land then
    local LS, it, bad = g.LS, g.items, 0
    for i = 1, it.n, 5 do
      local L = g.s.layers[it.layer[i]]
      local _, ny = LS.normal_at(g.land, it.x[i], it.z[i])
      if math.abs(it.y[i] + L.sink - LS.height_at(g.land, it.x[i], it.z[i])) > 1e-4 then bad = bad + 1 end
      if ny < math.cos(math.rad(L.slope[2])) - 1e-6 or ny > math.cos(math.rad(L.slope[1])) + 1e-6 then bad = bad + 1 end
      if L.altitude and (it.y[i] + L.sink < L.altitude[1] - 1e-6 or it.y[i] + L.sink > L.altitude[2] + 1e-6) then bad = bad + 1 end
    end
    check(bad == 0, "every copy on the ground, where its layer's rules let it grow: " .. bad .. " not")
    local m = g:rects().mid
    local gx, gz = g:ground_at(m[1] + m[3] / 2, m[2] + m[4] / 2)
    check(gx and math.abs(gx) < 64 and math.abs(gz) < 64, "the brush: the mouse's ray onto the hills")
    local function flat_rocks()                    -- (rocks on ground gentler than 14°)
      local n = 0
      for i = 1, g.items.n do
        if g.items.layer[i] == 3 then local _, ny = LS.normal_at(g.land, g.items.x[i], g.items.z[i]); if ny > math.cos(math.rad(14)) then n = n + 1 end end
      end
      return n
    end
    local f0 = flat_rocks()
    g:edit(function(t) t.layers[3].slope = { 0, 90 } end)
    local f1 = flat_rocks()
    check(f0 == 0 and f1 > 20, "rocks: only on slopes past 14°, then anywhere (" .. f0 .. " -> " .. f1 .. " on gentle ground)")
    g:edit(function(t) t.ground = nil end)
    check(not g.land and g.items.y[1] == -g.s.layers[g.items.layer[1]].sink, "flat again")
    g.dirty = false
  end
  print(string.format("foliage edit: %d checks ok, %d failed", ok_n, fail_n))
  if os.getenv("NG_EXIT") then os.exit(0) end
end)
