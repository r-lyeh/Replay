-- kgirls3d.lua - an animated FBX character
-- about: 3D demo: an animated FBX character (ufbx), its clips from @animlist.txt, shadows
--
-- games/common/kgirl/kgirls01.fbx: one take of 507 frames, cut into clips by the
-- animlist.txt beside it ("frame: 66-85 Run (Loop)"): the importer reads them as
-- clips of their own (docs/3D.md). The `animator` poses her; t is ours to move.
-- A new clip fades in over the last one (animator.blend, a quarter of a second);
-- her name tag is a 2D text kept over her head (w:project3d).
-- Keys: left / right: the clip; up / down: nearer / further; A / D: turn round.
--
-- The model: "kgirls01" by nanofactory, CC BY-NC-ND 4.0
-- (https://sketchfab.com/3d-models/kgirls01-d2f946f58a8040ae993cda70c97b302c).
-- Not for commercial games, and not to be changed: kgirls01.license beside it.

local ecs = require("ecs")
local w = ecs.world()

local CLIPS = { "Idle", "Run Intro", "Run", "Run Outro", "Punch Loop", "Punch Low", "Punch Up", "Punch Mid", "Jump",
                "Kick", "Kick x3", "Fall Loop", "Land", "Air attack In", "Air attack Out", "Dash In", "Dash",
                "Punch reverse", "Punch super", "Charge", "Hit1", "Hit2", "Die", "Get up", "Walk intro", "Walk" }

w:spawn("/config", { window = { w = 640, h = 400, title = "kgirls3d" } })
w:spawn("/data/state", { clip = 1, t = 0, orbit = 0.4, dist = 4.2, prev = 1, prev_t = 0, fade = 0 })
w:spawn("/data/clips", { names = CLIPS })            -- (the systems read them here: they run on their own)
w:spawn("/data/input", { held = {} })
w:spawn("/objects/view", {
  transform = { x = 0, y = -4 },
  camera3d = { w = 640, h = 348, fov = 40, eye = { 0, 1.2, 3.2 }, at = { 0, 0.75, 0 },
               clear = { 40, 44, 60 }, ambient = { 96, 96, 112 },
               sun = { dir = { -0.4, -1, -0.5 }, color = { 255, 244, 228 } }, shadows = true },
})
w:spawn("/objects/view/floor", { transform3d = { s = 8 }, mesh = { "plane", color = { 110, 120, 140 } } })
w:spawn("/objects/view/girl", { transform3d = {}, mesh = { "/assets/kgirl/kgirls01.fbx" }, animator = { clip = CLIPS[1], t = 0 } })
w:spawn("/objects/title", { transform = { x = 0, y = 186 }, text = { "", font = "sans", size = 16, align = "center" }, color = { 230, 230, 240 } })
w:spawn("/objects/tag", { transform = { x = 0, y = 0 }, layer = "hud", text = { "kgirl", font = "sans", size = 14, align = "center" }, color = { 255, 230, 140 } })   -- (the hud layer: over the 3D picture)
w:spawn("/objects/credit", { transform = { x = 0, y = -190 }, text = { "kgirls01 by nanofactory (CC BY-NC-ND 4.0)", font = "sans", size = 12, align = "center" }, color = { 170, 170, 190 } })

w:spawn("/systems/input", { system = ecs.system(function()
  return {
    on_key = function(w, key, down)
      w:node("/data/input").c.held[key] = down or nil
      if not down then return end
      local st, CLIPS = w:node("/data/state").c, w:node("/data/clips").c.names
      if key == "right" or key == "left" then      -- (the clip it leaves: faded out over the new one)
        st.prev, st.prev_t, st.fade = st.clip, st.t, 0.25
        st.clip = key == "right" and st.clip % #CLIPS + 1 or (st.clip - 2) % #CLIPS + 1
        st.t = 0
      end
    end,
  }
end) })
w:spawn("/systems/play", { system = ecs.system(function()
  return function(w, dt)
    local st, CLIPS = w:node("/data/state").c, w:node("/data/clips").c.names
    local held = w:node("/data/input").c.held
    st.t = st.t + dt
    st.prev_t = st.prev_t + dt
    st.fade = math.max(0, st.fade - dt)
    if held.a then st.orbit = st.orbit - dt * 1.5 end
    if held.d then st.orbit = st.orbit + dt * 1.5 end
    if held.up then st.dist = math.max(1.5, st.dist - dt * 2) end
    if held.down then st.dist = math.min(8, st.dist + dt * 2) end
    local cam = w:node("/objects/view").c.camera3d
    cam.eye = { math.sin(st.orbit) * st.dist, 0.7 + st.dist * 0.15, math.cos(st.orbit) * st.dist }
    local an = w:node("/objects/view/girl").c.animator
    an.clip, an.t, an.loop = CLIPS[st.clip], st.t, true
    an.blend = st.fade > 0 and { clip = CLIPS[st.prev], t = st.prev_t, w = st.fade / 0.25 } or nil
    local tx, ty, _, vis = w:project3d("/objects/view", { 0, 1.98, 0 })   -- (over her head, in the 2D world)
    local tag = w:node("/objects/tag").c
    tag.transform.x, tag.transform.y, tag.hidden = tx or 0, (ty or 0) - 10, not vis
    w:node("/objects/title").c.text[1] = string.format("%d / %d  %s   left / right: clip, A / D: turn, up / down: zoom", st.clip, #CLIPS, CLIPS[st.clip])
  end
end) })
w:spawn("/systems", { order = { "input", "play" } })
return w
