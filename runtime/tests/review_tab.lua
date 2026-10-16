-- review_tab.lua - the Review tab (plugins/review) on a copy of pong: the
-- author's proposal listed, picked, its changes shown. run.lua: "review tab".
local core = require "core"
local ok, bad = 0, 0
local function check(c, what) if c then ok = ok + 1 else bad = bad + 1; print("FAIL: " .. what) end end
core.add_thread(function()
  coroutine.yield(0.3)
  local PP = require "plugins.projectplugins"
  PP.open_tab("review")
  local v = core.active_view
  check(v and v:get_name():find("Review"), "the tab opens: " .. tostring(v and v:get_name()))
  check(v.info and not v.info.err and v.info.author, "the game, you its author: " .. tostring(v.info and v.info.err))
  check(#v.info.rows == 1 and v.info.rows[1].state == "accepted" and v.info.rows[1].valid, "the proposal listed, accepted (by the admin), valid")
  check(v.sel == 1, "picked: the last one")
  coroutine.yield(0.2)
  check(v.diff and v.diff[1] and v.diff[1][1] == "/data/rules", "its changes: /data/rules")
  check(not v:act("review", 1, "accept", "mine"), "the author can't accept its own")
  check(v:act("test", 1, 60) and v.msg:find("ticks"), "run headless: " .. tostring(v.msg))
  print(string.format("review tab: %d checks ok, %d failed", ok, bad))
  os.exit(0)
end)
