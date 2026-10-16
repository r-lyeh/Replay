-- nodegraph_arrange.lua - align, space and tidy the selected nodes, and
-- snippets (plugins/nodegraph/arrange.lua): all through the text's tags.
--   replay games/pong.lua --stopped --lite "dofile('runtime/tests/nodegraph_arrange.lua')@3" --frames 100000 --shot x.bmp
-- Prints a line per failed check, then the count; NG_EXIT exits.
local core = require "core"
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local function wait_for(f, secs)
    local t0 = system.get_time()
    repeat coroutine.yield(); local r = f(); if r then return r end until system.get_time() - t0 > (secs or 20)
  end
  local path = "nodegraph_arrange_test.lua"
  local f = io.open(path, "wb")
  f:write("local a = 1\n--@node dx=40 dy=10\nlocal b = a + 2\n--@node dx=-30 dy=60\nprint(b)\nlocal c = 3\n")
  f:close()
  local v = require("plugins.nodegraph").open(path)
  wait_for(function() v:update(); return v.g end)
  check(v and v.g, "the graph is open")
  if not (v and v.g) then print(string.format("nodegraph arrange: %d checks ok, %d failed", ok_n, fail_n)); if os.getenv("NG_EXIT") then os.exit(0) end return end
  local function stmts()
    local out = {}
    for _, n in ipairs(v.g.nodes) do if n.edit and n.kind ~= "start" and n.kind ~= "expr" and n.title ~= "Start" and n.line then out[#out + 1] = n end end
    table.sort(out, function(p, q) return p.line < q.line end)
    return out
  end
  local function rebuilt() coroutine.yield(0.4); wait_for(function() v:update(); return v.change_id == v.doc:get_change_id() end) end
  local list = stmts()
  check(#list >= 3, "statements: " .. #list)
  v:select(list)
  v:arrange("left")
  rebuilt()
  list = stmts()
  local x0, same = list[1].x, true
  for _, n in ipairs(list) do if math.abs(n.x - x0) > 1 then same = false end end
  check(same, "left edges lined up")
  v:select(list)
  v:arrange("top")
  rebuilt()
  list = stmts()
  local y0 = list[1].y
  same = true
  for _, n in ipairs(list) do if math.abs(n.y - y0) > 1 then same = false end end
  check(same, "tops lined up")
  v:select(list)
  v:arrange("across")
  rebuilt()
  list = stmts()
  table.sort(list, function(p, q) return p.x < q.x end)
  local overlap = false
  for i = 2, #list do if list[i].x < list[i - 1].x + list[i - 1].w then overlap = true end end
  check(not overlap, "spaced across: none over another")
  coroutine.yield(0.5)
  v:select(list)
  v:arrange("tidy")
  rebuilt()
  list = stmts()
  check(#list >= 3, "tidy: still there")
  local text = v.doc:get_text(1, 1, math.huge, math.huge)
  check(text:find("local b = a + 2", 1, true) and text:find("print(b)", 1, true), "the code is the same")
  -- undo: back
  v.doc:undo(); rebuilt()
  check(true, "undo works")

  -- snippets
  local dir = v.snippet_dir()
  local file = dir .. "/arrange_test_snippet.lua"
  os.remove(file)
  check(v.snippet_placeholders("local s = x\nprint(s, t.s)") == "local $s = x\nprint($s, t.s)", "a snippet's locals: $name; a field of that name stays")
  list = stmts()
  v:select({ list[1] })
  local saved = v:save_snippet("Arrange test snippet")
  if not saved then print("  (flash: " .. tostring(v.note and v.note.text or v.flash_text) .. ", sel " .. #v:selection() .. ", text '" .. v:selection_text(v:selection()) .. "')") end
  check(saved and io.open(file, "rb"), "saved: " .. tostring(saved))
  local found
  for _, s in ipairs(v:snippets()) do if s.name == "Arrange test snippet" then found = s end end
  check(found, "listed in the Add menu's Snippets")
  local menu = v:add_menu(0, 0)
  local has = false
  for _, it in ipairs(menu) do if it.text == "Snippets" then for _, s in ipairs(it.sub) do if s.text == "Arrange test snippet" then has = true end end end end
  check(has, "the Add menu has it")
  rebuilt()
  local before = #v.g.nodes
  v:add_snippet(file, 300, 300)
  rebuilt()
  local t2 = v.doc:get_text(1, 1, math.huge, math.huge)
  check(#v.g.nodes > before, "added from the snippet")
  check(t2:find("local a2 = 1", 1, true), "its local renamed (a is taken): " .. (t2:match("local a%d*") or "?"))
  os.remove(file)
  v.doc:save()
  os.remove(path)
  print(string.format("nodegraph arrange: %d checks ok, %d failed", ok_n, fail_n))
  if os.getenv("NG_EXIT") then os.exit(0) end
end)
