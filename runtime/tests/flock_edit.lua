-- flock_edit.lua - the flock editor (plugins/flock): it flies, settings change it,
-- a kind of flock, undo, save.
--   replay games/pong.lua --stopped --lite "dofile('runtime/tests/flock_edit.lua')@3" --frames 100000 --shot x.bmp
local core = require "core"
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local path = "flock_edit_test.flock"
  do
    local f = io.open("plugins/flock/samples/fish.flock", "rb"); local s = f:read("*a"); f:close()
    f = io.open(path, "wb"); f:write(s); f:close()
  end
  local v = require("plugins.openwith").open("flock", path)
  coroutine.yield(0.3)
  check(v and v.st and #v.st.b == 90, "the fish: 90 boids")
  if v and v.st then
    local x0 = v.st.b[1][1]
    coroutine.yield(0.3)
    check(v.st.b[1][1] ~= x0, "they fly")
    v:edit(function(d) d.count = 30 end)
    check(#v.st.b == 30 and v.dirty, "fewer: 30")
    v:use_preset("bees")
    check(v.def.count == 70 and v.def.size == 3, "bees")
    v:undo_step(true)
    check(v.def.count == 30, "undo")
    v.goal = { 100, 50 }
    coroutine.yield(0.5)
    v.goal = nil
    v:save()
    local f = io.open(path, "rb"); local s = f:read("*a"); f:close()
    check(s:find("count = 30", 1, true) and not v.dirty, "saved")
    check(#v.left.hits > 0 and #v.right.hits > 5, "the panels drawn")
  end
  os.remove(path)
  print(string.format("flock edit: %d checks ok, %d failed", ok_n, fail_n))
  if os.getenv("NG_EXIT") then os.exit(0) end
end)
