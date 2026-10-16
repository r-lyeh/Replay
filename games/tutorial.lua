-- tutorial.lua
-- Light the beacon: a little game you finish by using the editor.
--   replay.exe games\tutorial.lua
--
-- A keeper, a dark beacon, a ship lost at sea. Each step is a card that says
-- what to do (Play, walk, picking on, pick the beacon, picking off; while it
-- runs: its intensity lights it, its pulse speed; rewind time; the window
-- maximized; the eye; then the code: a line of this file (CTRL+G), its node
-- graph beside the text, a number changed in either (the other follows), two
-- nodes wired (speed = fast), Restart (or Pause and Play) to run it) and
-- waits until it sees you do it.
-- The editor's part to use pulses yellow, and the card is beside it, in the
-- editor's own font (w:point_at(name, note)): readable over the game and the
-- code alike. Nothing asks you to save: the game on disk stays as it is, for
-- the next time (and the next person). Quiet on purpose: no sounds.
--
-- How it hears the editor: a system's on_editor(w, what, data) is called as
-- things happen there, playing or not ("playing", "paused", "stopped",
-- "select", "edit", "seek", "view", "picking", "tab", "code", "cursor",
-- "window", "start"), and w:point_at("play", note) makes the editor point at
-- its Play button, the card beside it (runtime/ecs.lua: hear_editor). Where
-- you are is a savegame (w:savegame: a one-file game's are kept while the
-- editor runs: through Stop and reloads); R at the end starts over.
--
-- The cards' words are in assets tutorial.loc (games/common/: English,
-- Spanish, French; the localization plugin edits it; L changes the language).
-- The steps are data: /data/tutorial (an id each, and what to point at).

local ecs = require("ecs")
local w = ecs.world()

-- the steps: `id` is what the tutorial system waits for, `point` the part of the
-- editor it points at; their words: assets tutorial.loc (<id>.title, <id>.1,
-- <id>.2, in English, Spanish and French: the localization plugin edits it)
w:spawn("/config", { language = { file = "tutorial.loc", default = "en" } })
w:spawn("/data/tutorial", {
  steps = {
    { id = "play", point = "play" }, { id = "walk", point = "game" },
    { id = "picking", point = "picking" }, { id = "pick", point = "game" }, { id = "unpick", point = "picking" },
    { id = "bright", point = "props" }, { id = "pulse", point = "props" }, { id = "rewind", point = "timeline" },
    { id = "maximize" }, { id = "eye", point = "eye" }, { id = "code", point = "game" }, { id = "beside", point = "game" },
    { id = "speed", point = "game" }, { id = "wire", point = "game" }, { id = "run", point = "rewind" }, { id = "done" },
  },
})
-- the line of this file the code steps go to (the keeper's speed: CTRL+G there)
local speed_line = 110
do
  local src = debug and debug.getinfo and debug.getinfo(1, "S").source
  local f = type(src) == "string" and src:sub(1, 1) == "@" and io.open(src:sub(2), "rb")
  if f then
    local k = 0
    for l in f:lines() do k = k + 1; if l:find("^%s*local speed = %d") then speed_line = k break end end
    f:close()
  end
end
w:spawn("/data/input", { held = {} })
w:spawn("/data/state", { lit_at = false, ship_x = 300, t = 0, speed_line = speed_line })

-- the beacon: how bright it shines (0: dark), how fast its light pulses, its
-- fire's colour, as a class (the properties show sliders, a swatch)
w:spawn("/classes/beacon", {
  intensity   = { type = "int", value = 0, min = 0, max = 100 },
  pulse_speed = { type = "int", value = 50, min = 1, max = 100 },
  fire        = { type = "color", value = { 255, 170, 60 } },
})

-- the scene -----------------------------------------------------------------------
w:spawn("/objects/sky", { xform = { x = 0, y = 0 }, color = { 16, 22, 44 }, rect = { fill = true, w = 900, h = 600 }, layer = "bg" })
for i, s in ipairs({ { -250, -90 }, { -170, -40 }, { -60, -110 }, { 20, -70 }, { 90, -120 }, { 210, -60 }, { 260, -110 }, { -120, -10 } }) do
  w:spawn("/objects/stars/" .. i, { xform = { x = s[1], y = s[2] }, color = { 200, 210, 255 }, circle = { fill = true, r = 1.5 }, layer = "bg" })
end
w:spawn("/objects/sea", { xform = { x = 330, y = 175 }, color = { 24, 52, 100 }, rect = { fill = true, w = 300, h = 110 } })
w:spawn("/objects/ground", { xform = { x = -120, y = 175 }, color = { 34, 60, 40 }, rect = { fill = true, w = 600, h = 110 } })
w:spawn("/objects/hill", { color = { 40, 70, 46 }, tris = { 60, 122, 120, 70, 172, 122 } })
w:spawn("/objects/beacon", {                       -- the tower (what you click)
  xform = { x = 120, y = 40 },
  color = { 120, 120, 135 },
  rect = { fill = true, w = 18, h = 64 },
  beacon = {},                                     -- (intensity, pulse_speed, fire: from /classes/beacon)
})
w:spawn("/objects/beacon/cage", { xform = { x = 0, y = -40 }, color = { 80, 80, 92 }, rect = { fill = false, w = 26, h = 18 } })
w:spawn("/objects/beacon/lamp", { xform = { x = 0, y = -40 }, color = { 255, 170, 60 }, circle = { fill = true, r = 7 }, hidden = true })
w:spawn("/objects/beacon/halo", { xform = { x = 0, y = -40 }, color = { 255, 170, 60, 30 }, circle = { fill = true, r = 30 }, hidden = true })
w:spawn("/objects/beacon/light", { xform = { x = 0, y = -40 }, color = { 255, 170, 60, 70 }, circle = { fill = false, r = 30 }, hidden = true })
w:spawn("/objects/keeper", {
  xform = { x = -230, y = 108 },
  sprite = { "..##..", "..##..", ".####.", "#.##.#", "..##..", ".#..#.", ".#..#." , palette = { ["#"] = { 240, 210, 170 } }, px = 3 },
})
w:spawn("/objects/ship", {
  xform = { x = 300, y = 132 },
  sprite = { "...#....", "...##...", "...###..", "...#....", "########", ".######.", palette = { ["#"] = { 230, 230, 240 } }, px = 3 },
})

-- the card: the editor shows it beside the yellow ring (w:point_at(name,
-- note): in its own font, readable over the game and the code alike); this
-- node only runs the tutorial system
w:spawn("/objects/tutorial", { tutorial = {} })
w:spawn("/data/layers", { order = { "bg", "default" } })

-- systems ---------------------------------------------------------------------------

-- the keys the game hears (while playing): kept in /data/input
local input = ecs.system(function()
  return {
    on_key = function(w, key, down)
      local n = w:node("/data/input")
      if n then n.c.held[key] = down or nil end
    end
  }
end)

-- the keeper walks (arrows, A / D)
local keeper = ecs.system(function()
  return function(w, dt)
    local fast = 300                               -- (the tutorial wires this into speed, in the node graph)
    local speed = 120                              -- (pixels a second: the tutorial changes it, in the text or its node graph)
    local k = w:node("/objects/keeper")
    local held = w:node("/data/input").c.held
    local dir = ((held.right or held.d) and 1 or 0) - ((held.left or held.a) and 1 or 0)
    k.c.xform.x = math.max(-280, math.min(100, k.c.xform.x + dir * speed * dt))
    w:node("/data/state").c.speed = speed
  end
end)

-- the beacon: lit while its intensity is over 0; its light pulses (its pulse
-- speed: 50 = once a second); the ship comes in
local beacon = ecs.system(function()
  return function(w, dt)
    local b = w:node("/objects/beacon")
    local st = w:node("/data/state").c
    st.t = (st.t or 0) + dt
    local i = math.max(0, math.min(100, b.c.beacon.intensity or 0)) / 100
    st.lit_at = i > 0
    local lamp = w:node("/objects/beacon/lamp").c  -- (its colour: the beacon's fire, as bright as its intensity, every tick)
    lamp.hidden = not st.lit_at or nil
    local c = b.c.beacon.fire or { 255, 170, 60 }
    local k = 0.35 + 0.65 * i
    lamp.color = { math.floor(c[1] * k), math.floor(c[2] * k), math.floor(c[3] * k) }
    local hz = math.max(1, math.min(100, b.c.beacon.pulse_speed or 50)) / 50
    local beat = 1 + 0.3 * math.sin(st.t * hz * 2 * math.pi)   -- (the radius pulses)
    local light = w:node("/objects/beacon/light").c
    light.hidden = lamp.hidden
    light.color = { c[1], c[2], c[3], math.floor(40 + 200 * i) }
    light.circle.r = (14 + 40 * i) * beat
    local halo = w:node("/objects/beacon/halo").c
    halo.hidden = lamp.hidden
    halo.color = { c[1], c[2], c[3], math.floor(8 + 40 * i) }
    halo.circle.r = (18 + 52 * i) * beat
    if st.lit_at and st.ship_x > 205 then st.ship_x = st.ship_x - 18 * dt end   -- (it sees the light: home)
    w:node("/objects/ship").c.xform.x = st.ship_x
  end
end)


-- the tutorial: the card, the editor's part to point at, each step's check
local tutorial = ecs.system(function()
  local function steps(w) return w:node("/data/tutorial").c.steps end
  local function progress(w)
    local p = w:loadgame("tutorial")
    if type(p) ~= "table" then p = { step = 1 } end
    return p
  end
  local lang_held = false
  local stopped = false                           -- (stopped: the authored world shows; its card stays as written: the ring's note says it)
  local function note_of(tr, id, foot)            -- the card: the ring's note (a title, its lines, a dim footer)
    local t = { tr(id .. ".title") }
    for _, l in ipairs({ tr(id .. ".1"), tr(id .. ".2") }) do if l ~= "" then t[#t + 1] = l end end
    if foot then t[#t + 1] = "\t" .. foot end
    return table.concat(t, "\n")
  end
  local function show(w, p)
    local list = steps(w)
    local k = math.max(1, math.min(#list, p.step))
    local s = list[k]
    local line = tostring(w:node("/data/state").c.speed_line or 110)
    local function tr(key) local t = w:tr(key); return t ~= key and (t:gsub("{line}", line)) or "" end   -- (a key with no text: nothing)
    local foot = k .. " / " .. #list .. "   " .. tr("language") .. "   " .. tr("keys")
    if stopped then
      if k > 1 then w:point_at("play", note_of(tr, "stopped", foot)) else w:point_at(s.point, note_of(tr, s.id, foot)) end
      return
    end
    local point, view = s.point, w.editor and w.editor.view   -- (the code hidden by the game: the eye first)
    if (s.id == "code" or s.id == "beside" or s.id == "speed") and view == "game" then point = "eye" end
    w:point_at(point, note_of(tr, s.id, foot))
  end
  local function current(w, p) local s = steps(w)[p.step]; return s and s.id end
  local function advance(w, p, id)                -- step `id` done: the next one
    if current(w, p) ~= id then return false end
    p.step = p.step + 1
    w:savegame("tutorial", p)
    show(w, p)
    return true
  end
  return {
    requires = { "tutorial" },
    on_editor = function(w, what, data)
      if what == "start" then stopped = data.mode == "stopped"
      elseif what == "stopped" or what == "playing" or what == "paused" then stopped = what == "stopped" end
      local p = progress(w)
      local b = w:node("/objects/beacon").c.beacon
      if what == "playing" then advance(w, p, "play")
      elseif what == "view" and data.view ~= "game" then advance(w, p, "eye")
      elseif what == "picking" and data.on then advance(w, p, "picking")
      elseif what == "picking" and not data.on then advance(w, p, "unpick")
      elseif what == "select" and tostring(data.path):find("^/objects/beacon") then advance(w, p, "pick")
      elseif what == "edit" and data.keys and data.keys[1] == "beacon" then
        if data.keys[2] == "intensity" and (b.intensity or 0) >= 100 then advance(w, p, "bright")
        elseif data.keys[2] == "pulse_speed" and b.pulse_speed ~= 50 then advance(w, p, "pulse") end
      elseif what == "edit" and data.keys and data.keys[1] == "color" then   -- (the lamp's or the light's own colour: it's the beacon's fire)
        for _, path in ipairs(data.paths or {}) do
          local n = path:find("^/objects/beacon/") and w:node(path)
          local c = n and n.c.color
          if type(c) == "table" then
            b.fire = { c[1], c[2], c[3] }
          end
        end
      elseif what == "seek" and data.back and w:node("/data/state").c.lit_at == false then advance(w, p, "rewind")
      elseif what == "cursor" and data.line == w:node("/data/state").c.speed_line then advance(w, p, "code")   -- (CTRL+G: the speed's line)
      elseif what == "window" and data.maximized then advance(w, p, "maximize")
      elseif what == "tab" and data.tab == "both" then advance(w, p, "beside")   -- (this file: its text and its node graph, side by side)
      elseif what == "code" and type(data.text) == "string" then            -- (its text as the editor has it: changed in the text or the graph)
        local n = data.text:match("\n%s*local speed = (%w+)")
        if n and n ~= "120" and n ~= "fast" then advance(w, p, "speed") end
        if n == "fast" then advance(w, p, "speed"); advance(w, p, "wire") end   -- (wired: speed = fast)
      end
      show(w, p)
    end,
    run = function(w, n, dt)
      local p = progress(w)
      local id = current(w, p)
      local st = w:node("/data/state").c
      local held = w:node("/data/input").c.held
      local b = w:node("/objects/beacon").c.beacon
      if id == "play" then advance(w, p, "play")
      elseif id == "walk" and math.abs(w:node("/objects/keeper").c.xform.x - 120) < 50 then advance(w, p, "walk")
      elseif id == "eye" and w.editor and w.editor.view and w.editor.view ~= "game" then advance(w, p, "eye")   -- (the code in sight already: done)
      elseif id == "picking" and w.editor and w.editor.picking then advance(w, p, "picking")
      elseif id == "unpick" and w.editor and w.editor.picking == false then advance(w, p, "unpick")
      elseif id == "bright" and (b.intensity or 0) >= 100 then advance(w, p, "bright")
      elseif id == "pulse" and b.pulse_speed ~= 50 then advance(w, p, "pulse")
      elseif id == "maximize" and w.editor and w.editor.maximized then advance(w, p, "maximize")
      elseif id == "code" and w.editor and w.editor.line == st.speed_line then advance(w, p, "code")
      elseif id == "beside" and w.editor and w.editor.tab == "both" then advance(w, p, "beside")
      elseif id == "run" and st.speed and st.speed ~= 120 then advance(w, p, "run")   -- (Restart, or Pause and Play: the code as edited runs)
      elseif id == "done" and held.r then
        p = { step = 1 }
        w:savegame("tutorial", p)
        b.intensity, b.pulse_speed = 0, 50
      end
      if held.l and not lang_held then             -- L: the next language (tutorial.loc's)
        local list, cur = w:languages(), w:language()
        for k, code in ipairs(list) do if code == cur then w:language(list[k % #list + 1]) break end end
      end
      lang_held = held.l
      local lit = 0                               -- (past the rewind: the keeper keeps it lit, even after one more)
      for k, s in ipairs(steps(w)) do if s.id == "rewind" then lit = k end end
      if p.step > lit and (b.intensity or 0) <= 0 then b.intensity = 100 end
      show(w, p)
    end,
  }
end)

w:spawn("/systems", { order = { "input", "keeper", "beacon", "tutorial" } })
w:spawn("/systems/input", { system = input })
w:spawn("/systems/keeper", { system = keeper })
w:spawn("/systems/beacon", { system = beacon })
w:spawn("/systems/tutorial", { system = tutorial })

return w
