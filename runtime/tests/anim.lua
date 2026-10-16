-- anim.lua - sprite animations (runtime/anim.lua): frames, pauses, loops,
-- the flow lambdas, events, hitboxes, the image it gives; and Aseprite files
-- (plugins/spriteanim/ase.lua): a file made here from the spec (RGBA: layers,
-- cels raw / zlib / linked, tags forward and ping-pong, slices: a hitbox and a
-- pivot) read into a sheet and a .anim, and indexed colour.
--   cd runtime/tests && luajit anim.lua   (or lua5.4)
local here = (arg and arg[0] or ""):match("^(.*[/\\])") or ""
package.path = here .. "../?.lua;" .. here .. "?.lua;" .. package.path
local A = dofile(here .. "../anim.lua")
local Ase = dofile(here .. "../../plugins/spriteanim/ase.lua")
local n, fails = 0, 0
local function check(c, m) n = n + 1; if not c then fails = fails + 1; print("  FAIL: " .. m) end end

-- the runtime
local def = A.check({ sheet = "hero.png", anims = {
  { name = "idle", loop = true, frames = {
    { rect = { 0, 0, 16, 16 }, pause = 100, events = { 'sound("blink")' } },
    { rect = { 16, 0, 32, 16 }, pause = 50, anchor = { 24, 16 }, hit1 = { 18, 2, 30, 14 }, outline1 = { 255, 255, 255 } } } },
  { name = "jump", loop = false, frames = {
    { rect = { 0, 16, 16, 32 }, pause = 100, events = { 'fx("dust")', "land" } },
    { rect = { 16, 16, 32, 32 }, pause = 100, flow = "s.vars.n = (s.vars.n or 0) + 1\nif s.vars.n < 3 then return 2 end\nreturn 'idle', 2" } } },
  { name = "once", loop = false, frames = { { rect = { 0, 0, 8, 8 }, pause = 10 } } },
} })
check(#def.anims == 3 and def.by_name.jump and def.anims[1].frames[1].anchor[1] == 8, "checked: anims by name, a default anchor (the middle)")
local s = A.new(def, "idle")
local _, ev = A.step(def, s, 0)
check(s.frame == 1 and #ev == 1 and ev[1][1] == "sound" and ev[1][2] == "blink", "frame 1 shows: its event (sound, blink)")
A.step(def, s, 0.1)
check(s.frame == 2, "after its pause (100 ms): frame 2")
A.step(def, s, 0.05)
check(s.frame == 1 and not s.done, "looping: back to frame 1")
local heard = {}
A.play(def, s, "jump")
A.step(def, s, 0, function(name, arg) heard[#heard + 1] = name .. ":" .. tostring(arg) end)
check(heard[1] == "fx:dust" and heard[2] == "land:nil", "on_event: fx(\"dust\"), land")
A.step(def, s, 0.1)                                -- frame 2: its flow sends it back to itself twice, then to idle 2
A.step(def, s, 0.1); A.step(def, s, 0.1)
check(s.anim == "jump" and s.frame == 2 and s.vars.n == 2, "a flow: frame 2 again (twice)")
A.step(def, s, 0.1)
check(s.anim == "idle" and s.frame == 2, "then another animation: idle, frame 2")
local o = A.new(def, "once")
A.step(def, o, 0.02)
check(o.done, "not looping: done after its last frame")
local img = A.image(def, s)
check(img[1] == "/assets/hero.png" and img.src.x == 16 and img.w == 16 and img.ax == 8 and img.ay == 16, "its image: the sheet, the frame's part, the anchor in it")
check(img.outline1 and img.outline1[4] == 255 and img.outline2 == nil, "its image: the frame's outline colours (render.h draws them)")
local x0, y0, x1, y1 = A.hitbox(def, s, 1, 100, 50)
check(x0 == 100 - 6 and y0 == 50 - 14 and x1 == 100 + 6 and y1 == 50 - 2, "a hitbox in the world (from the anchor): " .. tostring(x0) .. "," .. tostring(y0))
check(A.hitbox(def, s, 2, 0, 0) == nil, "no hit2: nil")
check(select(1, A.parse_event("sound('x')")) == "sound" and select(2, A.parse_event("shake(3)")) == 3, "events parsed: names, quoted and number args")
do                                                 -- version 2: pivot from the rect, hitboxes 1..10 from it, jumps
  local d2 = A.check({ version = 2, sheet = "s.png", hit_names = { false, "body", [10] = "attack" }, anims = {
    { name = "run", frames = { { rect = { 32, 0, 48, 16 }, pivot = { 8, 20 }, pause = 50, hits = { false, { 0, 0, 4, 4 }, [10] = { 2, 2, 6, 6 } } },
                               { rect = { 48, 0, 64, 16 }, pause = 50, jump = "idle 2" } } },
    { name = "idle", frames = { { rect = { 0, 0, 16, 16 }, pause = 50 }, { rect = { 16, 0, 32, 16 }, pause = 50, jump = 1 } } } } })
  local s2 = A.new(d2, "run")
  local f1 = A.frame(d2, s2)
  check(f1.anchor[1] == 40 and f1.anchor[2] == 20 and f1.hits[1] == nil and f1.hits[2] and f1.hits[10], "v2: the pivot from the rect (outside it too), hitboxes 2 and 10")
  local hx0, hy0 = A.hitbox(d2, s2, 10, 0, 0)
  check(hx0 == -6 and hy0 == -18, "v2: hitbox 10 in the world, from the pivot: " .. tostring(hx0) .. "," .. tostring(hy0))
  local all = A.hitboxes(d2, s2, 0, 0)
  check(all[2] and all[10] and not all[1], "v2: hitboxes(): 2 and 10")
  check(all.body == all[2] and all.attack == all[10] and select(1, A.hitbox(d2, s2, "attack", 0, 0)) == -6, "hitbox names: by name too")
  local img2 = A.image(d2, s2)
  check(img2.ax == 8 and img2.ay == 20, "v2: the image's anchor: the pivot")
  A.step(d2, s2, 0.05); A.step(d2, s2, 0.05)
  check(s2.anim == "idle" and s2.frame == 2, "v2: jump = \"idle 2\": another animation, its frame 2")
  A.step(d2, s2, 0.05)
  check(s2.anim == "idle" and s2.frame == 1 and not s2.done, "v2: jump = 1: it loops")
  local s3 = A.new(d2, "idle"); A.step(d2, s3, 0.05)
  check(s3.frame == 2, "v2: no jump: the next frame")
  local up = A.upgrade({ sheet = "x.png", anims = { { name = "a", frames = { { rect = { 10, 10, 20, 20 }, anchor = { 15, 22 }, hit2 = { 12, 12, 14, 14 } } } } } })
  local uf = up.anims[1].frames[1]
  check(up.version == 2 and uf.pivot[1] == 5 and uf.pivot[2] == 12 and uf.hits[1] == false and uf.hits[2][1] == 2 and uf.jump == 1, "upgrade: anchor and hit2 from the rect; loop (the default) -> jump 1")
  check(A.parse_jump("3") == 3 and select(2, A.parse_jump("run 2")) == 2 and A.parse_jump("") == nil and A.parse_jump("idle") == "idle", "parse_jump")
end
local big = A.new(def, "idle")
A.step(def, big, 1.0)
check(big.frame >= 1 and big.frame <= 2 and not big.done, "a long dt: several frames, still in it")

-- an Aseprite file, built here from the spec
local function W(v) return string.char(v % 256, math.floor(v / 256) % 256) end
local function D(v) return W(v % 65536) .. W(math.floor(v / 65536)) end
local function S(v) if v < 0 then v = v + 65536 end return W(v) end
local function L(v) if v < 0 then v = v + 4294967296 end return D(v) end
local function STR(t) return W(#t) .. t end
local function adler(s) local a, b = 1, 0; for i = 1, #s do a = (a + s:byte(i)) % 65521; b = (b + a) % 65521 end return b * 65536 + a end
local function zlib_stored(s)                      -- zlib with one stored block (no compression: the reader's inflate reads it)
  local len = #s
  local be = function(v) return string.char(math.floor(v / 16777216) % 256, math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256) end
  return "\120\1" .. "\1" .. W(len) .. W(65535 - len) .. s .. be(adler(s))
end
local function chunk(t, data) return D(#data + 6) .. W(t) .. data end
local function px(r, g, b, a, n) return string.rep(string.char(r, g, b, a), n) end
local Wd, Ht = 4, 4
local function frame(dur, chunks)
  local body = table.concat(chunks)
  return D(16 + #body) .. W(0xF1FA) .. W(#chunks) .. W(dur) .. "\0\0" .. D(#chunks) .. body
end
local layer = function(name, vis) return chunk(0x2004, W(vis and 1 or 0) .. W(0) .. W(0) .. W(0) .. W(0) .. W(0) .. string.char(255) .. "\0\0\0" .. STR(name)) end
local cel_head = function(li, x, y, kind) return W(li) .. S(x) .. S(y) .. string.char(255) .. W(kind) .. S(0) .. string.rep("\0", 5) end
local red, blue = px(255, 0, 0, 255, 4), px(0, 0, 255, 128, 4)
local f1 = frame(80, {
  layer("bg", true), layer("top", true), layer("hidden", false),
  chunk(0x2005, cel_head(0, 0, 0, 2) .. W(2) .. W(2) .. zlib_stored(red)),          -- bg: 2x2 red at 0,0, zlib
  chunk(0x2005, cel_head(1, 1, 1, 0) .. W(2) .. W(2) .. blue),                       -- top: 2x2 half blue at 1,1, raw
  chunk(0x2005, cel_head(2, 0, 0, 0) .. W(4) .. W(4) .. px(0, 255, 0, 255, 16)),     -- hidden: green everywhere (not drawn)
  chunk(0x2018, W(2) .. string.rep("\0", 8)
        .. W(0) .. W(2) .. string.char(2) .. W(0) .. string.rep("\0", 10) .. STR("walk")    -- frames 1-3 ping-pong, looping
        .. W(0) .. W(0) .. string.char(0) .. W(1) .. string.rep("\0", 10) .. STR("hit")),  -- frame 1 once
  chunk(0x2022, D(1) .. D(2) .. D(0) .. STR("hit1") .. D(0) .. L(1) .. L(1) .. D(2) .. D(2) .. L(1) .. L(2)),   -- a box and a pivot
})
local f2 = frame(120, { chunk(0x2005, cel_head(0, 2, 2, 0) .. W(2) .. W(2) .. red) })
local f3 = frame(40, { chunk(0x2005, cel_head(0, 0, 0, 1) .. W(0)) })             -- linked to frame 1's bg cel
local body = f1 .. f2 .. f3
local head = D(128 + #body) .. W(0xA5E0) .. W(3) .. W(Wd) .. W(Ht) .. W(32) .. D(1) .. W(100) .. D(0) .. D(0) .. string.char(0) .. "\0\0\0" .. W(0) .. string.char(1, 1) .. S(0) .. S(0) .. W(16) .. W(16)
head = head .. string.rep("\0", 128 - #head)
local doc, err = Ase.read(head .. body)
check(doc, "the made file reads: " .. tostring(err))
if doc then
  check(doc.w == 4 and #doc.frames == 3 and #doc.layers == 3 and #doc.tags == 2 and #doc.slices == 1, "its size, frames, layers, tags, slices")
  local f = doc.frames[1].rgba
  local function at(fr, x, y) return doc.frames[fr].rgba:byte((y * 4 + x) * 4 + 1, (y * 4 + x) * 4 + 4) end
  local r, g, b, a = at(1, 0, 0)
  check(r == 255 and g == 0 and a == 255, "frame 1, 0,0: red (bg, its zlib cel)")
  r, g, b, a = at(1, 1, 1)
  check(r < 255 and b > 0 and a == 255, "1,1: blue over red, half (top over bg)")
  r, g, b, a = at(1, 3, 3)
  check(a == 0, "3,3: nothing (the hidden layer's green not drawn)")
  check(select(4, at(2, 3, 3)) == 255 and select(4, at(2, 0, 0)) == 0, "frame 2: its own cel, elsewhere")
  check(at(3, 0, 0) == 255, "frame 3: linked to frame 1's cel")
  local sh = Ase.sheet(doc)
  check(sh.w == 8 and sh.h == 8 and #sh.rgba == 8 * 8 * 4 and sh.rects[3][1] == 0 and sh.rects[3][2] == 4, "a sheet: 2 x 2 cells, frame 3 below frame 1")
  local d = A.check(Ase.anim(doc, sh, "made.png"))
  local walk = d.by_name.walk
  check(walk and #walk.frames == 4 and walk.frames[4].jump_frame == 1, "walk: ping-pong 1 2 3 2, looping (its last frame: jump to 1)")
  check(walk.frames[1].pause == 80 and walk.frames[2].pause == 120 and walk.frames[4].rect[1] == 4, "pauses from durations; the 4th frame is frame 2 again")
  local hit = d.by_name.hit
  check(hit and not hit.frames[1].jump_frame and #hit.frames == 1, "hit: once (repeat 1)")
  local fr = walk.frames[1]
  check(fr.hits[1] and fr.hits[1][1] == 1 and fr.hits[1][3] == 3 and fr.anchor[1] == 2 and fr.anchor[2] == 3, "slice hit1: a hitbox, its pivot the anchor")
end

-- the plugin's sample, slime.aseprite (zlib cels: its own writer, tools/make_slime_ase.py)
do
  local f = io.open(here .. "../../plugins/spriteanim/samples/slime.aseprite", "rb")
  local d3, e3 = Ase.read(f and f:read("*a") or "")
  if f then f:close() end
  check(d3 and #d3.frames == 8 and #d3.tags == 2 and d3.tags[2].name == "hop", "samples/slime.aseprite: 8 frames, idle and hop: " .. tostring(e3))
  if d3 then
    local pf = io.open(here .. "../../plugins/spriteanim/samples/slime.png", "rb")
    local sh3 = Ase.sheet(d3, 4)
    local an = A.check(Ase.anim(d3, sh3, "slime.png"))
    check(sh3.w == 128 and sh3.h == 64 and an.by_name.idle.frames[4].jump_frame == 1 and not an.by_name.hop.frames[4].jump_frame and an.by_name.idle.frames[1].hits[1], "its sheet 4 x 2, idle loops, hop once, hit1 from the slice")
    if pf then pf:close() end
  end
end

-- indexed colour: the sample from npm's ase-parser, when it's there (else skipped)
local sample = os.getenv("ASE_SAMPLE")
if sample then
  local f = io.open(sample, "rb")
  local d2 = f and Ase.read(f:read("*a"))
  if f then f:close() end
  check(d2 and d2.depth == 8 and d2.w == 256, "an indexed sample: read")
end

-- in a game: w:anim(name) from the assets, the sheet beside it; the global anim in systems
do
  local ecs = require("ecs")
  package.loaded["anim"] = nil
  local AA = require("anim")
  local files = { ["chars/slime.anim"] = io.open(here .. "../../plugins/spriteanim/samples/slime.anim", "rb"):read("*a") }
  local was = ecs.assets.read
  ecs.assets.read = function(name) return files[name] end
  local w = ecs.world()
  local d = w:anim("chars/slime")
  check(d and d.sheet == "chars/slime.png" and d.by_name.hop, "w:anim: read from the assets, its sheet beside it")
  local st = d:new("hop")
  d:step(st, 0.5)
  check(st.anim == "idle", "methods: d:new, d:step (hop's flow: to idle)")
  local img = d:image(st)
  check(img[1] == "/assets/chars/slime.png" and img.ax and img.src.w == 32, "d:image: the component to draw")
  check(ecs.code_globals.anim == AA, "the global anim in systems")
  ecs.assets.read = was
end

print(string.format("anim: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
