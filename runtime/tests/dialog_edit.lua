-- dialog_edit.lua - editing a .dialog in its chart (plugins/dialog): move
-- boxes, link lines, add answers and lines, delete, undo; all through the text.
--   replay games/pong.lua --stopped --lite "dofile('runtime/tests/dialog_edit.lua')@3" --frames 100000 --shot x.bmp
-- Prints a line per failed check, then the count; NG_EXIT exits.
local core = require "core"
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local path = "dialog_edit_test.dialog"
  do
    local f = io.open("plugins/dialog/sample.dialog", "rb"); local s = f:read("*a"); f:close()
    f = io.open(path, "wb"); f:write(s); f:close()
  end
  local v = require("plugins.openwith").open("dialog", path)
  coroutine.yield(0.2)
  check(v and v.boxes and #v.boxes > 10, "the chart is open")
  if not (v and v.boxes) then print(string.format("dialog edit: %d checks ok, %d failed", ok_n, fail_n)); if os.getenv("NG_EXIT") then os.exit(0) end return end
  local function text() return v:edit_doc():get_text(1, 1, math.huge, math.huge) end
  local function row_of(n) return v.by[n] and v:get_row(v.by[n].row) end

  -- ties: a line drawn across two arrows ties them (written in the text)
  do
    local TI = require("plugins.canvas").ties
    local l1, l2
    for _, l in ipairs(v.links) do if l.from == 0 and l.to == 1 then l1 = l elseif l.from == 0 and l.to == 2 then l2 = l end end
    check(l1 and l2, "0's two answers: arrows")
    local ax, ay = TI.at(v:wire_segs(l1)[1], 0.5)
    local bx, by = TI.at(v:wire_segs(l2)[1], 0.5)
    local dx, dy = bx - ax, by - ay
    local n = v:tie_gesture(ax - dx * 0.05, ay - dy * 0.05, bx + dx * 0.05, by + dy * 0.05)
    check(n == 2, "a line across them: 2 tied: " .. tostring(n))
    check(row_of(0):find("//@via=1:1,2:1", 1, true), "the vias on line 0: " .. tostring(row_of(0)))
    check(text():find("\n//@tie 1 %-?%d+ %-?%d+"), "the tie's row")
    check(v.ties[1] and #v.links > 0 and v.links[1].via, "read back")
    local Dl = dofile("runtime/dialog.lua")
    local pd = Dl.parse(text())
    check(#pd.errors == 0 and pd.lines[0].choices[2] == 2, "games read it as before (the tags are comments)")
    local tie = v.ties[1]
    local tx0 = tie.x
    local isx, isy = v:to_screen(tie.x, tie.y)
    v:on_mouse_pressed("left", isx, isy, 1)        -- (drag the tie)
    v:on_mouse_moved(isx + 30, isy + 10, 30, 10)
    v:on_mouse_released("left", isx + 30, isy + 10)
    check(v.ties[1] and v.ties[1].x ~= tx0 and text():find("//@tie 1 " .. v.ties[1].x, 1, true), "a tie dragged: moved, written")
    v:untie(v.ties[1])
    check(not text():find("//@tie", 1, true) and not row_of(0):find("via", 1, true), "untied: its rows gone")
    coroutine.yield(0.5)
    -- a double-click on an arrow: a control point there; ties select (a click, CTRL+click, the box), Align, DELETE
    for _, l in ipairs(v.links) do if l.from == 0 and l.to == 1 then l1 = l elseif l.from == 0 and l.to == 2 then l2 = l end end
    local px, py = TI.at(v:wire_segs(l1)[1], 0.3)
    local wx, wy = v:to_world(px, py)
    v:on_canvas_pressed("left", wx, wy, 1); v:on_canvas_released("left", wx, wy)
    v:on_canvas_pressed("left", wx, wy, 2); v:on_canvas_released("left", wx, wy)
    check(#v.ties == 1 and text():find("//@tie", 1, true), "double-click on an arrow: a control point")
    local qx, qy = TI.at(v:wire_segs(l2)[1], 0.7)
    wx, wy = v:to_world(qx, qy)
    v:on_canvas_pressed("left", wx, wy, 1); v:on_canvas_released("left", wx, wy)
    v:on_canvas_pressed("left", wx, wy, 2); v:on_canvas_released("left", wx, wy)
    check(#v.ties == 2, "a second one: " .. #v.ties)
    local cam = { v.cam.x, v.cam.y, v.cam.zoom }
    v:on_canvas_pressed("left", -5000, -5000, 2)
    check(v.cam.x == cam[1] and v.cam.y == cam[2] and v.cam.zoom == cam[3], "a double-click on nothing: the camera stays")
    v:on_canvas_released("left", -5000, -5000)
    local info = v:tie_info()
    local A, B = v.ties[1], v.ties[2]
    local pa, pb = info.centre[A], info.centre[B]
    wx, wy = v:to_world(pa[1], pa[2])
    v:on_canvas_pressed("left", wx, wy, 1); v:on_canvas_released("left", wx, wy)
    check(v.sel_ties[A.id] and not v.sel_ties[B.id], "a click on a tie: selected")
    v:on_canvas_pressed("left", -5000, -5000, 1); v:on_canvas_released("left", -5000, -5000)
    check(#v:selected_ties() == 0, "a click on nothing: none")
    local m = 60
    local x0, y0 = v:to_world(math.min(pa[1], pb[1]) - m, math.min(pa[2], pb[2]) - m)
    local x1, y1 = v:to_world(math.max(pa[1], pb[1]) + m, math.max(pa[2], pb[2]) + m)
    v:on_canvas_pressed("left", x0, y0, 1)
    check(v.boxsel ~= nil or v.tieline ~= nil or v.dragging ~= nil, "pressed")
    if v.boxsel then
      v:on_canvas_moved(x1, y1); v:on_canvas_released("left", x1, y1)
      check(#v:selected_ties() == 2, "the box: both ties: " .. #v:selected_ties())
    else v:on_canvas_released("left", x0, y0); v.sel_ties = { [A.id] = true, [B.id] = true } end
    v:align_ties("middle")
    check(v.ties[1] and v.ties[2] and v.ties[1].y == v.ties[2].y, "aligned: a row")
    require("core.command").perform("dialog:delete")
    check(not text():find("//@tie", 1, true) and #v.links > 0 and v.by[0] and v.by[1], "DELETE: untied, the arrows and lines stay")
    coroutine.yield(0.5)
  end
  -- the row helpers keep comments, arrows and tags
  local t = v.row_parts("5 Do you want? [6,7] // why  //@10,-4")
  check(t.n == 5 and t.body == "Do you want?" and #t.choices == 2 and t.comment == "// why" and t.dx == 10 and t.dy == -4, "row_parts")
  t.dx, t.dy = 0, 0
  check(v.row_text(t) == "5 Do you want? [6,7]  // why", "row_text: a 0,0 tag dropped: " .. v.row_text(t))

  -- move a box by dragging it: the tag written, the others stay
  local b3 = v.by[3]
  local x0, y0, other = b3.x, b3.y, v.by[4].y
  v:on_canvas_pressed("left", b3.x + 20, b3.y + 5, 1)
  v:on_canvas_moved(b3.x + 60, b3.y + 35)
  v:on_canvas_released("left", b3.x + 60, b3.y + 35)
  check(row_of(3) == "3 Awesome! Have fun! -> 5  //@40,30", "moved: its tag: " .. tostring(row_of(3)))
  check(v.by[3].x == x0 + 40 and v.by[3].y == y0 + 30 and v.by[4].y == other, "moved: there; line 4 stays")
  check(v.dirty == true, "the chart has unsaved changes")

  -- link from a socket (the right edge) to another box
  local b11 = v.by[11]
  v:on_canvas_pressed("left", b11.x + b11.w, b11.y + b11.h / 2, 1)
  check(v.wiring and v.wiring.from == 11, "a press on the right edge: a link starts")
  local tgt = v.by[14]
  v:on_canvas_moved(tgt.x + 10, tgt.y + 5)
  v:on_canvas_released("left", tgt.x + 10, tgt.y + 5)
  check(row_of(11) == "11 Awwww -> 14", "linked 11 -> 14: " .. tostring(row_of(11)))
  -- onto a line with choices: one more choice
  local b0 = v.by[0]
  v:on_canvas_pressed("left", b0.x + b0.w, b0.y + b0.h / 2, 1)
  v:on_canvas_released("left", v.by[8].x + 10, v.by[8].y + 5)
  check(row_of(0):find("[1,2,8]", 1, true), "0's choices gain 8: " .. tostring(row_of(0)))
  -- dropped on nothing: a new line, linked, where it was dropped
  local b14 = v.by[14]
  v:on_canvas_pressed("left", b14.x + b14.w, b14.y + b14.h / 2, 1)
  local dropx, dropy = b14.x + b14.w + 200, b14.y + 100
  v:on_canvas_moved(dropx, dropy)
  v:on_canvas_released("left", dropx, dropy)
  check(row_of(14):find("-> 15$"), "a new line from 14: " .. tostring(row_of(14)))
  check(v.by[15] and v.by[15].x == dropx and v.by[15].row == v.by[14].row + 1, "line 15: after 14, at the drop")

  -- the menu on a box, and its commands
  v.hot = 5
  local names = {}
  for _, it in ipairs(v:menu_items()) do if it.text then names[#names + 1] = it.text end end
  local ns = table.concat(names, ",")
  check(ns:find("Add answer", 1, true) and ns:find("Unlink", 1, true) and ns:find("Delete line", 1, true), "the menu on line 5: " .. ns)
  local n = v:new_line(5, "answer")
  check(n == 16 and row_of(5):find("[6,7,8,9,16]", 1, true) and v.by[16].kind == "answer", "Add answer: 16, an answer of 5")
  check(v.by[16].row == v.by[9].row + 1, "after the last answer")
  n = v:new_line(10, "next")
  check(row_of(10):find("-> 17$") and row_of(17) == "17 ... -> 13", "Add next line: in the chain (10 -> 17 -> 13)")
  v:unlink(17)
  check(row_of(17) == "17 ...", "Unlink")
  v:delete(16)
  check(not v.by[16] and row_of(5):find("[6,7,8,9]", 1, true), "Delete line: gone, and from 5's choices: " .. tostring(row_of(5)))
  v:delete(12)
  check(not v.by[12] and row_of(8) == "8 Maybe" and row_of(9) == "9 Not sure", "deleted 12: the arrows to it gone")
  coroutine.yield(0.5)                             -- (edits close in time undo together)
  local before = text()
  local name = v:new_topic(10, 2000)
  check(name == "topic" and v.d.topics.topic and text():find("\n#topic ...  //@", 1, true), "New #topic")
  v.hot = nil
  names = {}
  for _, it in ipairs(v:menu_items()) do if it.text then names[#names + 1] = it.text end end
  check(table.concat(names, ","):find("New line", 1, true), "the menu on the background: New line")

  -- undo: back to the text before the topic
  local doc = v:edit_doc()
  doc:undo(); v:changed()
  check(text() == before and not v.d.topics.topic, "undo: the topic gone, the rest kept")
  -- save
  v:save()
  check(v.dirty == false, "saved")
  local f = io.open(path, "rb"); local disk = f:read("*a"); f:close()
  check(disk:gsub("\r", ""):gsub("%s+$", "") == text():gsub("\r", ""):gsub("%s+$", ""), "saved: the disk has it")
  os.remove(path)
  print(string.format("dialog edit: %d checks ok, %d failed", ok_n, fail_n))
  if os.getenv("NG_EXIT") then os.exit(0) end
end)
