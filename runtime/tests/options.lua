-- options.lua - an options menu (runtime/options.lua): the file checked, keys
-- moving and changing values, a slider's steps and dead zone, text boxes,
-- Reset / Apply / Discard, Back asking, saved values read back, buses set
-- live, the layout, the mouse, nodes drawn.   cd runtime/tests && luajit options.lua
package.path = "../?.lua;" .. package.path
local ecs = require "ecs"
local Opt = require "options"
local n, fails = 0, 0
local function check(c, m) n = n + 1; if not c then fails = fails + 1; print("  FAIL: " .. m) end end

local FILE = [[
return {
  title = "Options",
  tabs = {
    { name = "Game", sections = {
      { name = "Player", items = {
        { id = "name", type = "text", label = "Name", default = "Hopper", maxlen = 6 },
        { id = "code", type = "text", label = "Code", default = "", password = true, maxlen = 4 },
      } },
      { name = "Controls", items = {
        { id = "jump", type = "enum", label = "Jump", values = { "Low", "Normal", "High" }, default = "Normal" },
        { id = "hud", type = "bool", label = "Show HUD", default = true },
        { id = "speed", type = "slider", label = "Speed", min = 0.5, max = 1.5, step = 0.1, deadzone = 0.05, default = 1 },
        { id = "pan", type = "slider", label = "Pan", min = -1, max = 1, step = 0.25, deadzone = 0.1, default = 0 },
        { id = "restart", type = "button", label = "Restart", action = "restart" },
      } },
    } },
    { name = "Audio", sections = {
      { name = "Volume", items = {
        { id = "sfx", type = "slider", label = "Effects", min = 0, max = 1, step = 0.1, percent = true, default = 1, bus = "sfx" },
      } },
    } },
  },
}
]]

-- the file
local raw = assert(Opt.decode(FILE, "t.options"))
local o = Opt.new(raw, "settings.options")
check(#o.errors == 0, "no problems: " .. table.concat(o.errors, "; "))
check(#o.tabs == 2 and not o.flat and #o.list == 8, "two tabs, eight items")
check(o.by_id.speed.default == 1 and o.by_id.jump.default == "Normal", "defaults")
local flat = Opt.new({ sections = { { name = "S", items = { { id = "a", type = "bool" } } } } })
check(flat.flat and #flat.tabs == 1 and flat.by_id.a, "sections only: one tab, no bar")
local bad = Opt.new({ sections = { { items = { { id = "x", type = "wheel" }, { id = "x", type = "bool" } } } } })
check(#bad.errors == 2, "an unknown type and a repeated id: told")
local back = Opt.new(assert(Opt.decode(Opt.encode(raw))))
check(#back.list == 8 and back.by_id.pan.deadzone == 0.1 and back.by_id.code.password == true and back.tabs[2].name == "Audio",
      "encode -> decode: the same menu")
check(Opt.decode("return os.exit()") == nil, "data only: no os")

-- snapping
local sp = o.by_id.speed
check(Opt.snap(sp, 1.04) == 1 and Opt.snap(sp, 0.53) == 0.5 and Opt.snap(sp, 1.47) == 1.5 and Opt.snap(sp, 9) == 1.5, "slider: steps, range, dead zone at the ends")
check(Opt.snap(o.by_id.pan, 0.08) == 0 and Opt.snap(o.by_id.pan, -0.95) == -1, "slider -1..1: the dead zone snaps to 0 too")
check(Opt.show(o.by_id.sfx, 0.5) == "50%" and Opt.show(o.by_id.hud, false) == "Off" and Opt.show(o.by_id.code, "ab") == "**", "shown")

-- a world
local store, buses = {}, {}
ecs.saves = { read = function(k) return store[k] end, write = function(k, t) store[k] = t; return true end }
ecs.audio.bus = function(w, name, v) if v then buses[name] = v end return buses[name] or 1 end
local w = ecs.world()
local node = w:spawn("/objects/hud/menu", { options = { file = "settings.options" }, xform = { x = 0, y = 0 } })
w:spawn("/objects/hud", { layer = "hud" })
local st = o:state(w, node)
check(st.path == "/entities/options_menu" and w:node(st.path), "its state: under /entities")
check(st.values.name == "Hopper" and st.edit.hud == true, "values: the defaults")
check(buses.sfx == 1, "a bus: set when loaded")
local function key(k) o:key(w, st, k, true); o:key(w, st, k, false) end
check(not o:key(w, st, "down", true), "closed: keys go to the game")
o:open(w, st)
check(st.open and o:events(st)[1][1] == "open", "open")

-- moving, changing
check(o:focused(st).id == "name", "the first item has the focus")
key("down"); key("down")
check(o:focused(st).id == "jump", "down twice: jump (sections skipped)")
key("right")
check(st.edit.jump == "High", "right: the next value")
key("right")
check(st.edit.jump == "Low", "...and round")
key("down"); key("return")
check(st.edit.hud == false, "enter: a bool toggles")
key("down"); key("left")
check(st.edit.speed == 0.9, "left: a step down")
for _ = 1, 10 do key("left") end
check(st.edit.speed == 0.5, "...to the minimum")
key("down"); key("right")
check(st.edit.pan == 0.25, "pan: out of the dead zone in one press")
o:key(w, st, "left shift", true); key("left"); o:key(w, st, "left shift", false)
check(math.abs(st.edit.pan - 0.225) < 1e-9, "shift: finely")
key("down"); o:events(st); key("return")
local ev = o:events(st)
check(ev[1] and ev[1][1] == "button" and ev[1][2] == "restart", "a button: its event")
key("down")
check(st.focus == 8, "below the items: the buttons")
check(o:dirty(st), "edited: not applied yet")

-- typing
st.focus = 1
key("return")
check(st.typing == "name", "enter on a text box: typing")
key("backspace"); key("backspace")
o:key(w, st, "left shift", true); key("x"); o:key(w, st, "left shift", false)
key("y"); key("z"); key("q")
check(st.edit.name == "HoppXy" , "typed (shift: capitals), cut at maxlen: " .. tostring(st.edit.name))
key("escape")
check(st.typing == nil and st.edit.name == "Hopper", "escape: dropped")
key("return"); key("a"); key("return")
check(st.typing == nil and st.edit.name == "Hopper", "full: nothing more")
key("return"); key("backspace"); key("a"); key("return")
check(st.typing == nil and st.edit.name == "Hoppea", "enter: kept")

-- tabs, live
key("e")
check(st.tab == 2 and o:focused(st).id == "sfx", "E: the next tab")
key("left")
check(st.edit.sfx == 0.9 and buses.sfx == 0.9, "a bus slider: heard as it moves")
key("q")
check(st.tab == 1, "Q: back")

-- discard, apply, reset
o:discard(w, st)
check(not o:dirty(st) and st.edit.name == "Hopper" and buses.sfx == 1, "discard: the applied values, the bus back")
st.edit.hud = false
o:set(w, st, "speed", 1.2)
local changed = o:apply(w, st)
check(#changed == 2 and st.values.speed == 1.2 and not o:dirty(st), "apply: " .. #changed .. " changed")
check(store.settings and store.settings:find("speed"), "saved: saves/settings")
o:reset(w, st)
check(st.edit.speed == 1 and st.values.speed == 1.2 and o:dirty(st), "reset: the defaults, to apply")
o:discard(w, st)

-- back asks
o:set(w, st, "hud", true)
key("escape")
check(st.open and st.confirm, "back with changes: asks")
key("escape")
check(st.open and not st.confirm, "back again: cancelled")
key("escape"); key("right"); key("return")       -- (Apply, Discard, Cancel: Discard)
check(not st.open and st.values.hud == false and st.edit.hud == false, "discard and close")
o:open(w, st)
o:set(w, st, "hud", true)
key("escape"); key("return")
check(not st.open and st.values.hud == true, "apply and close")
o:open(w, st)
key("escape")
check(not st.open, "back with nothing to apply: closes")

-- read back
local w2 = ecs.world()
local st2 = o:state(w2, w2:spawn("/objects/menu", { options = {} }))
check(st2.values.speed == 1.2 and st2.values.hud == true and st2.values.name == "Hopper", "the saved values, next time")
store.settings = ecs.encode({ speed = 99, jump = "Huge", hud = "yes", gone = 1 })
local w3 = ecs.world()
local st3 = o:state(w3, w3:spawn("/objects/menu", { options = {} }))
check(st3.values.speed == 1.5 and st3.values.jump == "Normal" and st3.values.hud == true, "saved values that don't fit: fixed or the defaults")

-- held keys repeat
o:open(w, st)
st.tab, st.focus = 1, 5
o:key(w, st, "right", true)
local v0 = st.edit.speed
o:update(w, st, 0.3)
check(st.edit.speed == v0, "held: not yet")
o:update(w, st, 0.2)
check(st.edit.speed > v0, "held: repeats")
o:key(w, st, "right", false)

-- the layout, the mouse
local ops, hits = o:layout(st)
check(#ops > 20 and #hits >= 8, "layout: " .. #ops .. " ops, " .. #hits .. " hits")
local tab2
for _, h in ipairs(hits) do if h.tab == 2 then tab2 = h end end
o:click(w, st, tab2[1] + 2, tab2[2] + 2)
check(st.tab == 2, "click a tab")
local row
for _, h in ipairs(select(2, o:layout(st))) do if h.n == 1 then row = h end end
o:click(w, st, row.vx + 1, row[2] + 2)
check(st.edit.sfx == 0, "click a slider at its left end: the minimum")
local foot
for _, h in ipairs(select(2, o:layout(st))) do if h.foot == 3 then foot = h end end
o:click(w, st, foot[1] + 2, foot[2] + 2)
check(st.edit.sfx == st.values.sfx, "click Discard")
-- a long tab scrolls
local many = { sections = { { name = "S", items = {} } } }
for i = 1, 40 do many.sections[1].items[i] = { id = "b" .. i, type = "bool", label = "B" .. i } end
local om = Opt.new(many, "many.options")
local sm = om:state(w, w:spawn("/objects/many", {}))
om:open(w, sm)
for _ = 1, 30 do om:key(w, sm, "down", true); om:key(w, sm, "down", false) end
om:layout(sm)
check(sm.scroll > 0, "a long list scrolls to the focus: " .. sm.scroll)

-- nodes
o:draw(w, st, node)
local ui = w:node(st.path .. "_ui")
check(ui and ui.c.layer == "hud" and not ui.c.hidden, "drawn: a node under /entities, in the menu's layer")
check(w:node(st.path .. "_ui/r001").c.rect.w == 440 and w:node(st.path .. "_ui/t001").c.text[1] == "Options", "its rects and texts")
o:close(w, st)
o:draw(w, st, node)
check(ui.c.hidden, "closed: hidden")
check(ecs.options ~= nil, "w:options is set")

-- round 2: key bindings, the window, the mouse, the pad
do
  local wins = {}
  rawset(_G, "host_window", function(t) wins[#wins + 1] = t.fullscreen; return true end)
  local K = Opt.new({ sections = { { name = "Keys", items = {
    { id = "kj", type = "key", label = "Jump", action = "jump" },
    { id = "fs", type = "bool", label = "Full screen", window = "fullscreen" },
    { id = "vol", type = "slider", label = "Volume", min = 0, max = 1, step = 0.1, default = 0.5 },
  } } } }, "keys.options")
  local wk = ecs.world()
  wk:spawn("/config", { actions = { jump = { "space", "pad a" } } })
  local nk = wk:spawn("/objects/km", { xform = { x = 100, y = 50 } })
  local sk = K:state(wk, nk)
  check(wk.wants_escape == true, "a menu: the viewer gives the game a short ESC")
  check(sk.keys.jump == "space,pad a" and Opt.show(K.by_id.kj, "", false, sk.keys.jump) == "space, pad a", "a key item shows the game's keys")
  K:open(wk, sk)
  K:key(wk, sk, "return", true); K:key(wk, sk, "return", false)
  check(sk.capture == "kj", "enter: waiting for a key")
  K:key(wk, sk, "pad y", true); K:key(wk, sk, "pad y", false)
  check(sk.capture == nil and sk.edit.kj == "pad y", "the key pressed: its binding")
  K:key(wk, sk, "return", true); K:key(wk, sk, "escape", true)
  check(sk.edit.kj == "pad y" and not sk.capture, "escape while waiting: unchanged")
  K:set(wk, sk, "fs", true)
  K:apply(wk, sk)
  check(wk:bindings().jump[1] == "pad y" and wins[#wins] == true, "applied: rebound (w:bind), full screen (host_window)")
  K:set(wk, sk, "kj", ""); K:apply(wk, sk)
  check(wk:bindings().jump[1] == "space", "back to the game's keys")
  -- the mouse: hover, click, drag a slider (w.mouse, in the world; the node at 100, 50)
  local _, hits = K:layout(sk)
  local row3
  for _, h in ipairs(hits) do if h.n == 3 then row3 = h end end
  wk.mouse = { x = 100 + row3[1] + 4, y = 50 + row3[2] + 4, inside = true, left = false }
  K:update(wk, sk, 0.016, nk)
  check(wk.wants_mouse == true and sk.focus == 3, "hover: the focus follows; the menu takes the mouse")
  wk.mouse = { x = 100 + row3.vx + 1, y = 50 + row3[2] + 4, inside = true, left = true }
  K:update(wk, sk, 0.016, nk)
  check(sk.edit.vol == 0 and sk.drag == "vol", "press on the slider's left end: 0, dragging")
  local bw = row3.vw - 7 * 8
  wk.mouse = { x = 100 + row3.vx + bw * 0.7, y = 50 + row3[2] + 4, inside = true, left = true }
  K:update(wk, sk, 0.016, nk)
  check(math.abs(sk.edit.vol - 0.7) < 1e-9, "dragged: 0.7: " .. tostring(sk.edit.vol))
  wk.mouse.left = false
  K:update(wk, sk, 0.016, nk)
  check(sk.drag == nil, "let go")
  -- the pad: Home / B back
  K:discard(wk, sk)
  K:key(wk, sk, "pad guide", true)
  check(not sk.open, "pad Home: back (closed)")
  K:update(wk, sk, 0.016, nk)
  check(wk.wants_mouse == nil, "closed: the mouse is the game's again")
  rawset(_G, "host_window", nil)
end

-- a look in a TrueType font: read, written back, its texts in that font, its rows taller
do
  local raw = { title = "Fonts", look = { font = "sans-bold", font_size = 15, tab_shear = 0.25 }, tabs = { { name = "T1", sections = { { name = "A", items = { { id = "on", type = "bool", label = "On" } } } } } } }
  local F = Opt.new(raw, "fonts.options")
  check(F.look and F.look.font == "sans-bold" and F.look.font_size == 15, "look: read")
  check(Opt.encode(raw):find('look = { font = "sans-bold", font_size = 15 }', 1, true) or Opt.encode(raw):find("look =", 1, true), "look: written back")
  local wf = ecs.world()
  local nf = wf:spawn("/objects/menu", { xform = { x = 0, y = 0 } })
  local sf = F:state(wf, nf)
  F:open(wf, sf)
  local ops, _, L = F:layout(sf)
  local t
  for _, op in ipairs(ops) do if op[1] == "text" then t = op break end end
  check(t and t.font == "sans-bold" and t.font_size == 15 and L.row > 14, "look: texts in its font, rows taller: " .. tostring(L.row))
  local tabop
  for _, op in ipairs(ops) do if op[1] == "text" and op[4] == "T1" then tabop = op end end
  check(tabop and tabop.shear == 0.25, "look: the tab in view slanted (tab_shear)")
  F:draw(wf, sf, nf)
  local tn = wf:node(sf.path .. "_ui/t001")
  check(tn and tn.c.text.font == "sans-bold" and tn.c.text.size == 15, "look: its nodes' text in the font")
  local plain = Opt.new({ title = "P", sections = {} }, "p.options")
  local ops2 = plain:layout(plain:state(wf, wf:spawn("/objects/m2", { xform = {} })))
  check(ops2[3] and ops2[3].font == nil, "no look: the 8 x 8 font")
end
-- w:text_size: wrapped to a width (an estimate without a host): taller, no wider than it
do
  local w2 = ecs.world()
  local tw, th = w2:text_size("one two three four five six seven", "sans", 16)
  local ww, wh = w2:text_size("one two three four five six seven", "sans", 16, 60)
  check(ww <= 60 + 1 and wh > th and tw > 60, "text_size: wrapped to 60: " .. ww .. " x " .. wh .. " (one line: " .. tw .. " x " .. th .. ")")
end

print(string.format("options: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
