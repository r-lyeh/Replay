-- foliage_edit.lua - the foliage editor (plugins/foliage): a sample read, a layer's settings change the
-- scatter, a layer added and removed, the seed, undo, save; the scatter the same as a game's (runtime/foliage.lua).
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
  end
  os.remove(path)
  print(string.format("foliage edit: %d checks ok, %d failed", ok_n, fail_n))
  if os.getenv("NG_EXIT") then os.exit(0) end
end)
