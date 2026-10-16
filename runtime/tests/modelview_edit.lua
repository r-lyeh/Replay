-- modelview_edit.lua - the model viewer (plugins/modelview): a .glb in a tab, what it's
-- made of, its picture drawn by the host under lite's hole (GPU or CPU), orbit, fit,
-- another tab in front takes it away, closing it too.
--   replay games/pong.lua --stop --lite "dofile('runtime/tests/modelview_edit.lua')@3" --frames 100000 --shot x.bmp
local core = require "core"
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function wait(t) local e = system.get_time() + t; repeat core.redraw = true; coroutine.yield() until system.get_time() >= e end   -- (frames drawn: lite draws only when something changed)
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local root = rawget(_G, "REPLAY_ROOT") or "."
  local v = require("plugins.openwith").open("modelview", root .. "/games/common/crate.glb")
  wait(0.5)
  check(v and v.info, "read: " .. tostring(v and v.err))
  if v and v.info then
    local i = v.info
    check(i.vertices == 24 and i.indices == 36 and #i.parts == 1 and #i.textures == 1 and i.textures[1].w == 32, "the crate: 24 / 36, a part, a 32 x 32 texture")
    check(math.abs(i.max[1] - i.min[1] - 1) < 1e-4, "a meter wide")
    local w, h, tris, r, g, b = host_view3d_pixel(v.key)
    local m = v:rects().mid
    check(w == math.floor(m[3]) and h == math.floor(m[4]), "its picture: the middle's size (" .. tostring(w) .. " x " .. tostring(h) .. ")")
    check(tris and tris >= 6 and tris <= 14, "triangles drawn (the floor's 2 too): " .. tostring(tris))
    local _, _, _, cr, cg, cb = host_view3d_pixel(v.key, math.floor(w / 2), math.floor(h / 2))
    check(cr and cr > cb + 20, "the crate in the middle: wood (" .. tostring(cr) .. "," .. tostring(cg) .. "," .. tostring(cb) .. ")")
    local _, _, _, er, eg, eb = host_view3d_pixel(v.key, 1, 1)
    local bg = require("core.style").background
    check(er == bg[1] and eg == bg[2] and eb == bg[3], "the corner: the background")
    local function lum(x, y) local _, _, _, r, g, b = host_view3d_pixel(v.key, x, y); return (r or 0) + (g or 0) + (b or 0) end
    local below = math.floor(h * 0.8)              -- (under the crate: the floor, its shadow on it somewhere)
    local a = 0; for x = 0, w - 1, 2 do a = a + lum(x, below) end
    v.shadows = false; wait(0.3)
    local b2 = 0; for x = 0, w - 1, 2 do b2 = b2 + lum(x, below) end
    check(b2 > a, "shadows: the floor darker with them (" .. a .. " < " .. b2 .. ")")
    v.ground = false; wait(0.3)
    local _, _, _, fr, fg, fb = host_view3d_pixel(v.key, 2, h - 3)
    check(fr == bg[1] and fg == bg[2] and fb == bg[3], "no floor: the background under it")
    v.ground, v.shadows = true, true
    local yaw = v.yaw
    v:on_mouse_pressed("left", m[1] + m[3] / 2, m[2] + m[4] / 2, 1)
    v:on_mouse_moved(m[1] + m[3] / 2 + 40, m[2] + m[4] / 2, 40, 0)
    v:on_mouse_released("left", m[1] + m[3] / 2 + 40, m[2] + m[4] / 2)
    check(v.yaw ~= yaw, "orbit")
    v.dist = 100; v:fit()
    check(v.dist < 3 and v.dist > 1, "fit: " .. v.dist)
    wait(0.3)
    check(host_view3d_pixel(v.key) ~= nil, "still shown")
    core.root_view:open_doc(core.open_doc(root .. "/games/pong.lua"))
    wait(0.4)
    check(host_view3d_pixel(v.key) == nil, "another tab in front: gone")
    core.set_active_view(v)
    local node = core.root_view.root_node:get_node_for_view(v)
    if node then node:set_active_view(v) end
    wait(0.4)
    check(host_view3d_pixel(v.key) ~= nil, "back")
    local av = require("plugins.openwith").open("modelview", root .. "/games/common/arm.glb")
    wait(0.4)
    check(av and av.info and av.info.joints == 2 and #av.info.clips == 1 and av.info.clips[1].name == "bend", "the arm: 2 joints, its clip")
    check(av and av.clip == 1 and av.playing, "its clip plays")
    if av and av.info then
      av.playing = false; av.t = 0; wait(0.3)
      local w2, h2 = host_view3d_pixel(av.key)
      local function sum()                         -- (the picture's colour, all of it: it moves when the arm does)
        local n = 0
        for y = 0, h2 - 1, 4 do for x = 0, w2 - 1, 4 do local _, _, _, r, g, b = host_view3d_pixel(av.key, x, y); n = n + r * 3 + g * 5 + b * 7 end end
        return n
      end
      local s0 = sum()
      av.t = 0.9; wait(0.3)
      check(sum() ~= s0, "scrubbed to 0.9 s: the arm bent")
      av.model_on, av.shadows = false, false; av.t = 0; wait(0.3)   -- (the floor alone: it stays where the model stands as read)
      local f0 = sum()
      av.t = 0.9; wait(0.3)
      check(sum() == f0, "the floor doesn't move with the clip")
      av.model_on, av.shadows = true, true
      av:try_close(function() end)
    end
    local kg = host_model_info(root .. "/games/common/kgirl/kgirls01.fbx")   -- (FBX: ufbx)
    check(kg and #kg.parts == 4 and #kg.textures == 1 and kg.joints == 34 and #kg.clips == 27, "kgirl.fbx: parts, a texture, joints, clips")
    check(kg and #kg.morphs == 10 and kg.morphs[10] == "Face01_mouthO", "kgirl: her 10 blend shapes")
    check(kg and kg.max[2] - kg.min[2] > 0.5 and kg.max[2] - kg.min[2] < 3 and kg.clips[4].name == "Run", "kgirl: meters, y up; the animlist's clips")
    local hv = host_model_info(root .. "/games/common/house.vox")   -- (MagicaVoxel: our reader)
    check(hv and hv.vertices > 1000 and #hv.parts == 1 and math.abs(hv.min[2]) < 1e-4 and hv.max[2] > 1, "house.vox: voxels, stood on y = 0")
    local bl = host_model_info(root .. "/games/common/blob.glb")    -- (glTF morph targets)
    check(bl and #bl.morphs == 2 and bl.morphs[1] == "puff" and #bl.clips == 1, "blob.glb: its morph targets, its clip")
    local tw, th, tpx = host_model_thumb(root .. "/games/common/crate.glb", 48)
    local solid, clear = 0, 0
    for k = 4, (tpx and #tpx or 0), 4 do if tpx:byte(k) == 255 then solid = solid + 1 elseif tpx:byte(k) == 0 then clear = clear + 1 end end
    check(tw == 48 and th == 48 and solid > 200 and clear > 200, "a thumbnail: the crate, its background clear (" .. solid .. " / " .. clear .. ")")
    check(renderer.image.from_rgba(tw or 1, th or 1, tpx or "") ~= nil, "renderer.image.from_rgba")
    local ov = require("plugins.openwith").open("modelview", root .. "/games/common/arm.glb")
    wait(0.3)
    if ov then
      local function lines() return select(4, host_view3d_pixel(ov.key)) or 0 end
      check(lines() == 0, "no overlays at first")
      ov.skeleton = true; wait(0.3)
      local sk = lines()
      check(sk == 3, "the skeleton: a bone and two joints (" .. sk .. ")")
      ov.wireframe = true; wait(0.3)
      check(lines() == sk + 36 * 3, "the wireframe: 3 edges a triangle (" .. lines() .. ")")
      ov.normals = true; wait(0.3)
      check(lines() == sk + 36 * 3 + 48, "the normals: one a vertex (" .. lines() .. ")")
      local _, _, tris = host_view3d_pixel(ov.key)
      ov.model_on = false; wait(0.3)
      local _, _, tris2, n2 = host_view3d_pixel(ov.key)
      check(tris2 < tris and n2 == sk + 36 * 3 + 48, "M: the model off, its overlays kept (" .. tostring(tris) .. " -> " .. tostring(tris2) .. ")")
      check(ov.outline == false, "the outline: off at first")
      ov.model_on = true; ov.outline = true; ov.skeleton, ov.wireframe, ov.normals = false, false, false; wait(0.3)
      local _, _, _, _, outl = host_view3d_pixel(ov.key)
      ov.outline = false; wait(0.3)
      local _, _, _, _, outl2 = host_view3d_pixel(ov.key)
      check(outl and outl > 50 and outl2 == 0, "the outline: on, then off (" .. tostring(outl) .. ", " .. tostring(outl2) .. ")")
      ov.outline = true
      -- the sequence: bend, half a second's pause, bend; once (no loop)
      ov.seq, ov.seq_loop = { { clip = 1 }, { pause = 0.5 }, { clip = 1 } }, false
      ov:seq_play()
      check(ov.seq_on and ov.seq_i == 1 and ov.clip == 1 and ov.t == 0, "the sequence starts")
      for _ = 1, 21 do ov:step(0.05) end           -- (1.05 s: the first bend done, the pause begun)
      check(ov.seq_i == 2 and ov.hold > 0 and ov.t == 1, "then the pause, the last pose held (t " .. ov.t .. ")")
      for _ = 1, 11 do ov:step(0.05) end
      check(ov.seq_i == 3 and ov.t < 0.1 and ov.prev and ov.fade > 0, "then bend again, faded in over the last (blend " .. ov.blend_s .. " s)")
      wait(0.3)
      check(host_view3d_pixel(ov.key) ~= nil, "drawn with the blend")
      for _ = 1, 25 do ov:step(0.05) end
      check(not ov.seq_on and not ov.playing, "the end: no loop, it stops")
      ov.seq_loop = true; ov:seq_play()
      for _ = 1, 60 do ov:step(0.05) end
      check(ov.seq_on and ov.seq_i >= 1, "Loop: again from the first")
      ov.blend_s = 0; ov:play(1)
      check(not ov.prev and ov.fade == 0 and not ov.seq_on, "Blend off: no fade; a click stops the sequence")
      -- the fly camera: RMB held, moved: the eye stays, the view turns; W: forward; a click alone: the menu
      local m = ov:rects().mid
      local cx, cy = m[1] + m[3] / 2, m[2] + m[4] / 2
      local e0 = ov:eye()
      ov:on_mouse_pressed("right", cx, cy, 1)
      ov:on_mouse_moved(cx + 30, cy, 30, 0)
      local e1 = ov:eye()
      check(ov.flying == "flying" and math.abs(e1[1] - e0[1]) + math.abs(e1[2] - e0[2]) + math.abs(e1[3] - e0[3]) < 1e-6, "flying: the eye stays while it looks")
      check(host_call("mouse_relative?") == "on", "flying: the cursor hidden, kept in the window")
      local keymap = require "core.keymap"
      keymap.on_key_pressed("w")
      ov:fly_step(0.2)
      keymap.on_key_released("w")
      local e2 = ov:eye()
      check(math.abs(e2[1] - e1[1]) + math.abs(e2[3] - e1[3]) > 0.01, "W: forward")
      ov:on_mouse_released("right", cx + 30, cy)
      check(not ov.flying and not require("plugins.contextmenu").show_context_menu and host_call("mouse_relative?") == "off", "let go: no more flying, no menu, the cursor back")
      ov:on_mouse_pressed("right", cx, cy, 1)
      ov:on_mouse_released("right", cx, cy)
      check(require("plugins.contextmenu").show_context_menu, "a right-click alone: its menu")
      require("plugins.contextmenu"):hide()
      ov:try_close(function() end)
    end
    local _, err = host_model_info(root .. "/games/common/nope.glb")
    check(err and #err > 0, "a missing model: why (" .. tostring(err) .. ")")
  end
  print(string.format("modelview edit: %d checks ok, %d failed", ok_n, fail_n))
  if os.getenv("NG_EXIT") then os.exit(0) end
end)
