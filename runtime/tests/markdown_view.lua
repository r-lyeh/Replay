-- markdown_view.lua - the markdown viewer (plugins/markdown): find (CTRL+F: matches, next / previous round, typing
-- and Backspace, closed), the minimap (beside the scroll bar; a click there scrolls; off from its menu).
--   replay games/pong.lua --stop --lite "dofile('runtime/tests/markdown_view.lua')@3" --frames 100000
local core = require "core"
local command = require "core.command"
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local v = require("plugins.openwith").open("markdown", "docs/HELP.md")
  coroutine.yield(0.4)
  check(v and v.map_on and v:map_w() > 0, "the minimap: on")
  command.perform("markdown:find")
  check(v.find ~= nil, "CTRL+F: the find box")
  v:on_text_input("gizm")
  v:on_text_input("o")
  local n = #v.find.hits
  check(n >= 5 and v.find.cur >= 1, "typed: every match: " .. n)
  local y1 = v.scroll.to.y
  command.perform("markdown:find-next")
  check(v.find.cur == (v.find.cur > 1 and v.find.cur or 1) and v.scroll.to.y >= y1, "next: further down")
  v.find.cur = n
  command.perform("markdown:find-next")
  check(v.find.cur == 1, "past the last: the first")
  command.perform("markdown:find-prev")
  check(v.find.cur == n, "and back round")
  command.perform("markdown:find-backspace")
  check(v.find.text == "gizm" and #v.find.hits >= n, "Backspace: one letter fewer, as many or more")
  v:find_run(true)
  v.find.text = "zzzqqq"; v:find_run()
  check(#v.find.hits == 0, "nothing: none")
  command.perform("markdown:find")
  check(v.find == nil, "CTRL+F again: closed")
  coroutine.yield(0.1)
  local mx, my, mw = v:map_geom()
  v.scroll.y, v.scroll.to.y = 0, 0
  v:on_mouse_pressed("left", mx + mw / 2, my + v.size.y - 4, 1)
  v:on_mouse_released("left", mx + mw / 2, my + v.size.y - 4)
  check(v.scroll.to.y > v.size.y, "a click low on the minimap: scrolled down: " .. math.floor(v.scroll.to.y))
  local w0 = v:layout().w
  command.perform("markdown:minimap")
  check(not v.map_on and v:map_w() == 0 and v:layout().w >= w0, "off: the text as wide or wider")
  command.perform("markdown:minimap")
  local a = require("plugins.openwith").open("markdown", "docs/APIs.md")   -- (docs/APIs.md's contents: every link to a section of it)
  coroutine.yield(0.3)
  local f = io.open("docs/APIs.md"); local src = f:read("*a"); f:close()
  local n, miss = 0, {}
  for id in src:gmatch("%]%(#([^)]+)%)") do n = n + 1; if not a:layout().anchors[id] then miss[#miss + 1] = id end end
  check(n >= 20 and #miss == 0, "APIs.md: its contents' links all land: " .. n .. ", missing: " .. table.concat(miss, " "))
  print(string.format("markdown view: %d checks ok, %d failed", ok_n, fail_n))
  if os.getenv("NG_EXIT") then os.exit(0) end
end)
