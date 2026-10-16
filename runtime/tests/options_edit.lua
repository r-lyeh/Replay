-- options_edit.lua - editing an .options in its tab (plugins/options): the
-- outline, adding tabs / sections / items, fields, moving, deleting, the flat
-- form, the preview (keys, clicks), undo, saving; all through the text.
--   replay games/pong.lua --stopped --lite "dofile('runtime/tests/options_edit.lua')@3" --frames 100000 --shot x.bmp
-- Prints a line per failed check, then the count; NG_EXIT exits.
local core = require "core"
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local path = "options_edit_test.options"
  do
    local f = io.open("games/hop/assets/settings.options", "rb"); local s = f:read("*a"); f:close()
    f = io.open(path, "wb"); f:write(s); f:close()
  end
  local Opt = dofile("runtime/options.lua")
  local v = require("plugins.openwith").open("options", path)
  coroutine.yield(0.2)
  check(v and v.o and #v.o.list == 13, "the menu is open: " .. tostring(v and v.o and #v.o.list))
  if not (v and v.o) then print(string.format("options edit: %d checks ok, %d failed", ok_n, fail_n)); if os.getenv("NG_EXIT") then os.exit(0) end return end
  local function text() return v:edit_doc():get_text(1, 1, math.huge, math.huge) end
  local function now() return Opt.decode(text()) end
  coroutine.yield(0.3)

  -- drawn: the panels and the preview
  check(v.left.hits and #v.left.hits > 5 and #v.right.hits > 0, "the panels drawn")

  -- add an item after the selected one
  v:select({ kind = "item", t = 1, s = 2, i = 1 })
  check(v.pst.tab == 1 and v.pst.focus == 3, "selecting an item: the preview's focus there: " .. v.pst.focus)
  v:add_item("slider")
  local r = now()
  local it = r.tabs[1].sections[2].items[2]
  check(it and it.type == "slider" and it.id == "slider1" and v.sel.i == 2, "a slider added after it: " .. tostring(it and it.id))
  check(v.dirty, "unsaved")
  v:set_field("label", "Gravity"); v:set_field("min", 0.5); v:set_field("max", 2); v:set_field("deadzone", 0.1)
  r = now()
  it = r.tabs[1].sections[2].items[2]
  check(it.label == "Gravity" and it.min == 0.5 and it.max == 2 and it.deadzone == 0.1, "its fields written")
  check(v.o.by_id.slider1.default == 0.5, "its default fits the new range: " .. tostring(v.o.by_id.slider1.default))
  coroutine.yield(0.5)                             -- (edits close in time undo together)

  -- move, delete
  v:move(-1)
  r = now()
  check(r.tabs[1].sections[2].items[1].id == "slider1" and v.sel.i == 1, "moved up")
  v:delete()
  r = now()
  check(r.tabs[1].sections[2].items[1].id == "jump" and #r.tabs[1].sections[2].items == 3, "deleted")
  -- a tab, a section
  v:select({ kind = "tab", t = 2 })
  v:add_tab()
  r = now()
  check(#r.tabs == 4 and r.tabs[3].name == "Tab 3" and v.sel.kind == "tab" and v.sel.t == 3, "a tab added")
  v:add_section()
  r = now()
  check(#r.tabs[3].sections == 2 and v.sel.kind == "section", "a section added")
  v:add_item("enum")
  r = now()
  check(r.tabs[3].sections[2].items[1].type == "enum" and #r.tabs[3].sections[2].items[1].values == 3, "a list in it")
  coroutine.yield(0.5)

  -- the preview: keys and the mouse
  v:select({ kind = "tab", t = 1 })
  v.pst.focus = 1
  v:preview_key("down"); v:preview_key("down")
  check(v.sel.kind == "item" and v.sel.s == 2 and v.sel.i == 1, "preview: down twice: the selection follows")
  v:preview_key("right")
  check(v.pst.edit.jump == "High", "preview: right changes it")
  check(now().tabs[1].sections[2].items[1].default == "Normal", "...only the preview: the file's the same")
  v:preview_key("e")
  check(v.pst.tab == 2 and v.sel.t == 2, "preview: E: the next tab")
  local px, py, k, lw, lh = v:preview_rect()
  local _, hits = v.o:layout(v.pst, v:look())
  local tab1
  for _, h in ipairs(hits) do if h.tab == 1 then tab1 = h end end
  v:on_mouse_pressed("left", px + (tab1[1] + lw / 2 + 2) * k, py + (tab1[2] + lh / 2 + 2) * k, 1)
  v:on_mouse_released("left", 0, 0)
  check(v.pst.tab == 1, "preview: a click on a tab")
  v.pst.focus = 1
  v:preview_key("return")
  check(v.pst.typing == "name", "preview: typing in a text box")
  v:on_text_input("Zed")
  v:preview_key("return")
  check(v.pst.edit.name == "HopperZed", "preview: typed: " .. tostring(v.pst.edit.name))

  -- sections only, and back
  v:set_flat(true)
  r = now()
  check(r.sections and not r.tabs and #r.sections == 8, "sections only: all of them: " .. tostring(r.sections and #r.sections))
  check(v.o.flat, "the preview: no tab bar")
  coroutine.yield(0.5)
  v:set_flat(false)
  r = now()
  check(r.tabs and #r.tabs == 1 and r.tabs[1].name == "General", "tabs again: one, General")
  coroutine.yield(0.5)

  -- undo, through the doc
  local doc = v:edit_doc()
  doc:undo(); v:changed()
  check(now().sections ~= nil, "undo: sections only again")
  doc:redo(); v:changed()
  check(now().tabs ~= nil, "redo")

  -- the text typed by hand: the tab follows
  doc:remove(1, 1, math.huge, math.huge)
  doc:insert(1, 1, 'return { title = "Hi", sections = { { name = "A", items = { { id = "x", type = "bool", label = "X" } } } } }\n')
  coroutine.yield(0.4)
  check(v.o.title == "Hi" and #v.o.list == 1, "typed in the text: shown")
  doc:insert(1, 1, "{{{")
  coroutine.yield(0.4)
  check(v.err and v.o.title == "Hi", "broken text: the error, the last menu kept")
  doc:remove(1, 1, 1, 4)
  coroutine.yield(0.4)
  check(not v.err, "fixed")

  -- the menu
  local names = {}
  for _, m in ipairs(v:menu_items()) do if m.text then names[#names + 1] = m.text end end
  check(table.concat(names, ","):find("Add slider", 1, true) and table.concat(names, ","):find("Edit as text", 1, true), "its menu")

  -- save
  v:save()
  check(v.dirty == false, "saved")
  local f = io.open(path, "rb"); local disk = f:read("*a"); f:close()
  check(disk:gsub("\r", ""):gsub("%s+$", "") == text():gsub("\r", ""):gsub("%s+$", ""), "saved: the disk has it")
  os.remove(path)
  print(string.format("options edit: %d checks ok, %d failed", ok_n, fail_n))
  if os.getenv("NG_EXIT") then os.exit(0) end
end)
