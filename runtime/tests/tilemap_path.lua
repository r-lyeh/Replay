-- tilemap_path.lua - the tilemap editor's Path tool (plugins/tilemap, runtime/path.lua):
-- a start and a goal clicked, the way drawn; an edit finds it again.
--   replay games/pong.lua --stopped --lite "dofile('runtime/tests/tilemap_path.lua')@3" --frames 100000 --shot x.bmp
local core = require "core"
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local v = require("plugins.openwith").open("tilemap", "games/hop/assets/level1.tmap")
  coroutine.yield(0.3)
  check(v and v.map, "the map is open")
  if v and v.map then
    v.tool = "path"
    v.layer = 1
    local T = v.map.tile
    v:on_canvas_pressed("left", 2 * T + 1, 13 * T + 1, 1)      -- (start: near the player's start)
    check(v.path_a and not v.path_b, "a start")
    v:on_canvas_pressed("left", 27 * T + 1, 13 * T + 1, 1)
    local r = v.path_result
    check(v.path_b and r and r.info and r.info.visited > 0, "a goal: searched (" .. tostring(r and r.info and r.info.visited) .. " cells)")
    check(r and (r.cells == nil or (r.cells[1][1] == 2 and r.cells[#r.cells][1] == 27)), "the way from start to goal, or none")
    v.path_opts.jps = true
    v:find_path()
    local r2 = v.path_result
    check((r.cells == nil) == (r2.cells == nil) and (not r.cells or math.abs(r.info.cost - r2.info.cost) < 1e-6), "JPS: the same")
    v:on_canvas_pressed("left", 4 * T + 1, 4 * T + 1, 1)
    check(v.path_a[1] == 4 and not v.path_b and not v.path_result, "a third click: a new start")
  end
  print(string.format("tilemap path: %d checks ok, %d failed", ok_n, fail_n))
  if os.getenv("NG_EXIT") then os.exit(0) end
end)
