-- spriteanim_edit.lua - the sprite animator (plugins/spriteanim): a .anim opens
-- with its sheet, the preview plays (a jump to another animation), frames
-- dragged out, moved, sized (the anchor along), the anchor dragged, hitboxes
-- (the tool, a digit held, moved, deleted), save (version 2), an older file
-- read, Import... (a picture, an Aseprite file); an Aseprite file opens as a
-- sheet + .anim, CTRL+S writes both; the image formats written and read back.
--   replay games/pong.lua --stop --lite "dofile('runtime/tests/spriteanim_edit.lua')@3" --frames 100000 --shot x.bmp
local core = require "core"
local function A_check_name(v) local A = dofile("runtime/anim.lua"); return A.check(v.def).hit_index.attack end
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local function cp(from, to) local f = io.open(from, "rb"); local s = f:read("*a"); f:close(); f = io.open(to, "wb"); f:write(s); f:close() end
  local dir = "spriteanim_test_tmp"
  require("plugins.fsutils").mkdir(dir)
  cp("plugins/spriteanim/samples/slime.anim", dir .. "/slime.anim")
  cp("plugins/spriteanim/samples/slime.png", dir .. "/slime.png")
  local v = require("plugins.openwith").open("spriteanim", dir .. "/slime.anim")
  coroutine.yield(0.3)
  check(v and v.img and #v.def.anims == 2, "opened: its sheet and two animations")
  if v and v.def then
    local w, h = v.img:get_size()
    check(w == 128 and h == 64, "the sheet: 128 x 64")
    local f0, moved = v.st.frame, false
    for _ = 1, 12 do coroutine.yield(0.05); if v.st.frame ~= f0 then moved = true end end
    check(moved, "the preview plays")
    v.ai, v.fi = 2, 4                              -- hop's last frame: it jumps to idle
    coroutine.yield(0.1)
    v.preview_for = 2
    v.st = { anim = "hop", frame = 4, t = 0, done = false, vars = {} }
    v.playing = true
    coroutine.yield(0.3)
    check(v.st.anim == "idle", "a jump in the preview: hop's last frame -> idle (" .. tostring(v.st.anim) .. ")")
    v.ai, v.fi = 2, 1
    v:edit(function() v:frame().pause = 333 end)
    check(v.dirty and v.def.anims[2].frames[1].pause == 333, "a frame's pause")
    v:undo_step(true)
    check(v.def.anims[2].frames[1].pause == 90, "undo")
    local function press(wx, wy) v:on_canvas_pressed("left", wx, wy, 1) end
    local function move(wx, wy) v:drag_to(wx, wy) end
    local function release() v:on_mouse_released("left", 0, 0) end
    -- Frames: drag on nothing: a new frame after the one picked, its anchor in its middle
    local n0 = #v:anim().frames
    v.tool = "frames"
    press(0, 72); move(32, 104); release()
    local nf = v:frame()
    check(#v:anim().frames == n0 + 1 and v.fi == 2 and nf.rect[1] == 0 and nf.rect[2] == 72 and nf.rect[3] == 32 and nf.rect[4] == 104 and nf.pivot == nil, "a new frame dragged out (snapped): " .. table.concat(nf.rect, ","))
    -- drag it: moved, its anchor (pivot) along; its edge: sized
    v:edit(function() nf.pivot = { 3, 4 }; nf.hits = { { 1, 1, 5, 5 } } end)
    press(16, 80); move(32, 80); release()
    check(nf.rect[1] == 16 and nf.rect[3] == 48 and nf.pivot[1] == 3 and nf.hits[1][1] == 1, "moved 16 px: its anchor and hitbox from its rect, along")
    press(48, 90); move(64, 90); release()
    check(nf.rect[3] == 64 and nf.rect[1] == 16, "its right edge dragged: wider")
    -- the mouse's shape: the anchor a hand, an edge a resize arrow, a corner a diagonal one, moving four arrows
    check(v:cursor_at(16 + 3, 72 + 4) == "hand" and v:cursor_at(64, 90) == "sizeh" and v:cursor_at(40, 104) == "sizev" and v:cursor_at(64, 104) == "sizenwse" and v:cursor_at(64, 72) == "sizenesw",
          "cursors: the anchor, edges, corners: " .. v:cursor_at(16 + 3, 72 + 4) .. " " .. v:cursor_at(64, 90) .. " " .. v:cursor_at(64, 104))
    press(40, 90)
    check(v:cursor_at(40, 90) == "move", "cursors: moving a frame: four arrows")
    release()
    -- the anchor: dragged, outside the rect too
    local ax, ay = 16 + 3, 72 + 4
    press(ax, ay); move(10, 60); release()
    check(nf.pivot[1] == 10 - 16 and nf.pivot[2] == 60 - 72, "the anchor dragged outside its rect: " .. table.concat(nf.pivot, ","))
    -- Hitboxes: drag: the next free one; 3 held: that one
    v.tool = "hits"
    press(20, 80); move(36, 96); release()
    check(nf.hits[2] and nf.hits[2][1] == 24 - 16 and v.hit == 2, "Hitboxes: drag: hitbox 2 (snapped, from the rect): " .. (nf.hits[2] and table.concat(nf.hits[2], ",") or "none"))
    package.loaded["spriteanim.held"]["5"] = true
    press(40, 80); move(56, 88); release()
    package.loaded["spriteanim.held"]["5"] = nil
    check(nf.hits[5] and nf.hits[3] == false and nf.hits[4] == false, "5 held: hitbox 5 (3 and 4: none)")
    press(32, 88); move(40, 88); release()                -- (inside 2: moved)
    check(nf.hits[2][1] == 16, "a hitbox dragged: moved")
    v.hit = 5; v:delete_hit()
    check(nf.hits[5] == nil and #nf.hits == 2, "Delete: hitbox 5 gone (the holes after it too)")
    -- hitbox names: the same in every frame, saved at the file's top
    v.hit = 2
    v:draw_right(v:rects().right)                         -- (its Name field: set through the same function the field calls)
    v:edit(function(x) x.hit_names = { false, "attack" } end)
    check(A_check_name(v) == 2, "a hitbox's name: attack is hitbox 2")
    -- the strip: a click picks a frame (the preview shows it, paused); , and . step
    local cells = v:strip_cells()
    v:strip_pressed(cells[1][1] + 2, cells[1][2] + 2)
    check(v.fi == 1 and not v.playing and v.st.frame == 1, "the strip: frame 1 picked, the preview on it")
    v:step_preview(1)
    check(v.st.frame == 2 and v.fi == 2, "> : the next frame")
    v:step_preview(-1); v:step_preview(-1)
    check(v.st.frame == #v:anim().frames, "< from the first: the last")
    v.fi = 2
    v.onion = true
    v:draw_preview(v:rects().right)
    check(v.onion, "onion skin drawn")
    -- Jump to: blank, a frame, another animation
    v:edit(function() nf.jump = "idle 2" end)
    v:save()
    local f = io.open(dir .. "/slime.anim", "rb"); local s = f:read("*a"); f:close()
    check(not v.dirty and s:find("version = 2", 1, true) and s:find('"attack"', 1, true) and s:find('jump = "idle 2"', 1, true) and s:find("pivot = { -6, -12 }", 1, true) and not s:find("loop", 1, true), "saved: version 2, the jump, the anchor from the rect, no loop")
    check(#v.left.hits > 5 and #v.right.hits > 5, "the panels drawn")
    -- outlines: the preview draws its silhouette (lite: img:silhouette)
    local o2 = v:outline_img({ 0, 0, 32, 32 }, 2)
    local ow, oh = 0, 0
    if o2 then ow, oh = o2:get_size() end
    check(o2 and ow == 36 and oh == 36, "an outline: its part, 2 px round it (lite: img:outline)")
    -- an older file: read as version 2
    local old = dir .. "/old.anim"
    f = io.open(old, "wb"); f:write('return { sheet = "slime.png", anims = { { name = "a", loop = true, frames = { { rect = { 32, 0, 64, 32 }, anchor = { 48, 29 }, hit2 = { 37, 14, 59, 30 } } } } } }'); f:close()
    local ov = require("plugins.openwith").open("spriteanim", old)
    coroutine.yield(0.1)
    local of = ov and ov.def.anims[1].frames[1]
    check(of and of.pivot[1] == 16 and of.hits[2][1] == 5 and of.jump == 1 and ov.def.version == 2, "an older .anim: its anchor, hit2 and loop read as version 2")
    -- Import...: a picture beside it becomes the sheet
    cp("plugins/spriteanim/samples/slime.png", dir .. "/other.png")
    v:import(dir .. "/other.png")
    check(v.def.sheet == "other.png" and v.img, "Import...: a picture beside it: the sheet")
    v:undo_step(true)
    check(v.def.sheet == "slime.png", "undo: the sheet before")
    v:import("plugins/spriteanim/samples/slime.aseprite")
    check(#v.def.anims == 2 and v.pending_sheet and v.def.anims[1].frames[4].jump == 1, "Import...: an Aseprite file: its animations, its sheet (written on save)")
    v.dirty = false; ov.dirty = false
  end
  -- an Aseprite file: its frames as a sheet (beside it, on save) and its tags as animations
  local sample = os.getenv("ASE_SAMPLE") or "plugins/spriteanim/samples/slime.aseprite"
  do
    cp(sample, dir .. "/sample.aseprite")
    local a = require("plugins.openwith").open("spriteanim", dir .. "/sample.aseprite")
    coroutine.yield(0.3)
    check(a and a.def and a.filename:match("sample%.anim$") and a.dirty and a.img, "an .aseprite opened: as sample.anim, its sheet shown")
    if a and a.def then
      a:save()
      check(system.get_file_info(dir .. "/sample.anim") and system.get_file_info(dir .. "/sample.png"), "CTRL+S: sample.anim and sample.png beside it")
    end
  end
  -- the image formats: written from a picture, read back
  for _, ext in ipairs({ "qoi", "pug", "jpg", "png" }) do
    local out = dir .. "/slime." .. ext
    local ok = renderer.image.convert(dir .. "/slime.png", out, 90)
    local img = ok and renderer.image.load(out)
    local w, h = 0, 0
    if img then w, h = img:get_size() end
    check(img and w == 128 and h == 64, "." .. ext .. ": written and read back (" .. w .. "x" .. h .. ")")
  end
  for _, e in ipairs(system.list_dir(dir) or {}) do os.remove(dir .. "/" .. e) end
  os.remove(dir)
  print(string.format("spriteanim edit: %d checks ok, %d failed", ok_n, fail_n))
  if os.getenv("NG_EXIT") then os.exit(0) end
end)
