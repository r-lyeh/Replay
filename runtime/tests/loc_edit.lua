-- loc_edit.lua - editing a .loc in its tab (plugins/localization): keys,
-- texts, languages, plural forms, import / export, undo, save; all through the text.
--   replay games/pong.lua --stopped --lite "dofile('runtime/tests/loc_edit.lua')@3" --frames 100000 --shot x.bmp
local core = require "core"
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local L = dofile("runtime/loc.lua")
  local path = "loc_edit_test.loc"
  do
    local f = io.open("games/hop/assets/strings.loc", "rb"); local s = f:read("*a"); f:close()
    f = io.open(path, "wb"); f:write(s); f:close()
  end
  local v = require("plugins.openwith").open("localization", path)
  coroutine.yield(0.3)
  check(v and v.t and #v.t.langs == 3 and #v.t.keys == 5, "the table is open: " .. tostring(v and v.t and #v.t.keys))
  if not (v and v.t) then print(string.format("loc edit: %d checks ok, %d failed", ok_n, fail_n)); if os.getenv("NG_EXIT") then os.exit(0) end return end
  local function now() return L.parse(v:edit_doc():get_text(1, 1, math.huge, math.huge)) end
  check(#v.right.hits > 0, "the panel drawn")

  -- a cell click selects
  local g = v:grid_geom()
  v:on_mouse_pressed("left", g.x + g.kw + g.cw + 4, g.y + g.rh + 4, 1)
  check(v.sel == "hud_gems" and v.sel_lang == "es", "a click on a cell: that key, that language: " .. tostring(v.sel) .. " " .. tostring(v.sel_lang))

  v:add_key("pause")
  check(now().rows.pause and v.sel == "pause", "a key added")
  v:set_text("pause", "en", "Paused")
  v:set_text("pause", "es", "Pausa")
  check(now().rows.pause.en == "Paused" and v.missing and #v.missing >= 1, "texts written; fr missing")
  coroutine.yield(0.5)
  v:add_language("ru")
  check(#now().langs == 4, "a language added")
  v:add_plurals("pause")
  local r = now()
  check(r.rows["pause|one"] and r.rows["pause|few"] and r.rows["pause|many"] and r.rows["pause|other"] and not r.rows.pause, "plural forms: Russian's too; the key is pause|other now")
  check(r.rows["pause|other"].en == "Paused", "its texts kept in |other")
  coroutine.yield(0.5)
  v:rename_key("hint", "help")
  check(now().rows.help and not now().rows.hint, "renamed")
  -- export / import
  v:export("po")
  local stem = path:gsub("%.loc$", "")
  local f = io.open(stem .. ".es.po", "rb")
  check(f ~= nil, ".po exported")
  if f then f:close() end
  v:set_text("help", "es", "")
  check(not now().rows.help.es, "a text emptied")
  v:import(stem .. ".es.po")
  check(now().rows.help.es == "O / Start: opciones", "imported back from the .po")
  v:export("csv")
  check(io.open(stem .. ".csv", "rb") ~= nil, ".csv exported")
  coroutine.yield(0.5)
  -- undo
  local before = v:edit_doc():get_text(1, 1, math.huge, math.huge)
  v:delete_key("help")
  check(not now().rows.help, "deleted")
  v:edit_doc():undo(); v:changed()
  check(v:edit_doc():get_text(1, 1, math.huge, math.huge) == before, "undo: back")
  -- typed by hand: follows
  local doc = v:edit_doc()
  doc:insert(#doc.lines, math.huge, "\nextra,Extra,,,,\n")
  coroutine.yield(0.4)
  check(v.t.rows.extra, "typed in the text: shown")
  v:save()
  check(not v.dirty, "saved")
  for _, ext in ipairs({ ".loc", ".csv", ".en.po", ".es.po", ".fr.po", ".ru.po" }) do os.remove(stem .. ext) end
  print(string.format("loc edit: %d checks ok, %d failed", ok_n, fail_n))
  if os.getenv("NG_EXIT") then os.exit(0) end
end)
