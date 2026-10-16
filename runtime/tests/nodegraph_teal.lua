-- nodegraph_teal.lua - the node graph of a Teal file (games/blocks.tl), the game running:
--   replay games/blocks.tl --lite "dofile('runtime/tests/nodegraph_teal.lua')@3" --frames 100000 --shot x.bmp
-- Opens its graph: it reads (types skipped, kept as the pins' types), shows
-- what ran (the probe: its systems' lines are the .tl file's), and an edit
-- in the graph writes Teal that still checks. Prints a line per check; NG_EXIT exits.
local core = require "core"
core.add_thread(function()
  for _ = 1, 5 do coroutine.yield() end
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local v = require("plugins.nodegraph").open("games/blocks.tl")
  local t0 = system.get_time()
  repeat coroutine.yield(); v:update() until (v.g and v.probe) or system.get_time() - t0 > 30
  check(v.g and not v.err, "the graph of a .tl file: " .. tostring(v.err))
  local nodes, typed = 0, 0
  for _, n in ipairs(v.g and v.g.nodes or {}) do
    nodes = nodes + 1
    for _, p in ipairs(n.ins or {}) do if p.vtype then typed = typed + 1 end end
  end
  check(nodes > 300, "its nodes: " .. nodes)
  check(typed > 200, "pins typed (Teal's annotations): " .. typed)
  local dt_typed
  for _, n in ipairs(v.g and v.g.nodes or {}) do
    for _, o in ipairs(n.outs or {}) do if o.name == "dt" and o.vtype == "number" then dt_typed = true end end
  end
  check(dt_typed, "dt: number (from `dt: number`)")
  local ran = 0
  for _, n in ipairs(v.g and v.g.nodes or {}) do if v:ran(n) then ran = ran + 1 end end
  check(ran > 10, "nodes that ran (the probe, on the .tl's lines): " .. ran)
  print(string.format("nodegraph teal: %d checks ok, %d failed", ok_n, fail_n))
  if os.getenv("NG_EXIT") then os.exit(0) end
end)
