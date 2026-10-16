-- editor.lua - the model viewer: glTF 2.0 (.gltf, .glb), FBX, MagicaVoxel in a Lite tab. The
-- model turns in the middle (LMB drag: orbit; MMB or SHIFT+LMB drag: pan; the wheel: zoom;
-- double-click or Alt+F: fit; RMB held: fly, the mouse looks and W A S D Q E move, Shift
-- faster; a right-click: its menu), what it's made of on the right (vertices, triangles,
-- parts, textures, its size). A floor under it and the sun's shadows (Alt+G, Alt+S). A
-- skinned model's clips: a click plays one, faded in over the one before (Blend: 0.25 s at
-- first; 0: none), SPACE plays / pauses, Time scrubs. Its + adds it to the Sequence: clips
-- and pauses played in that order (once each; Loop: again from the first), each one moved
-- up, down or out (a click on a pause: 0.5, 1, 2, 3 s). Blend shapes (face expressions): a
-- slider each, over what the clip sets ("From the clip" gives them back). Over the picture,
-- in x-ray: the skeleton (Alt+K), the wireframe (Alt+W), the normals (Alt+N). Alt+M hides
-- the model itself (its bones alone, say), Alt+O outlines it (off at first). Letters
-- alone are the fly camera's (and lite's): the viewer's keys take Alt.
--
-- The 3D picture isn't Lite's: Lite leaves a hole in its own (renderer.clear_rect)
-- and the host draws the model there, under Lite's picture (host_view3d: the GPU,
-- else the CPU rasterizer; docs/3D.md, phase 7). Menus and tooltips over it stay on
-- top. The file is read again when it changes on disk.
local P = ...
P.title = "Model viewer"                           -- (its name in menus: Open with, the main menu's Plugins)
P.category = "Graphics"                            -- (the main menu: Graphics >)
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"
local canvas = require "plugins.canvas"

local function S(n) return math.floor(n * SCALE + 0.5) end
local function base_of(f) return (f:match("[^/\\]*$")) end

-- which views were drawn in a frame of Lite's: the others (a tab behind another,
-- closed) are taken away from the host's list, so their pictures don't stay
local shown = package.loaded["modelview.shown"]
if not shown then
  shown = { now = {}, last = {} }
  package.loaded["modelview.shown"] = shown
  local begin_frame, end_frame = renderer.begin_frame, renderer.end_frame
  renderer.begin_frame = function(...) shown.now = {}; return begin_frame(...) end
  renderer.end_frame = function(...)
    for key in pairs(shown.last) do if not shown.now[key] then host_view3d { key = key, remove = true } end end
    shown.last = shown.now
    return end_frame(...)
  end
end

local MView = View:extend()
local next_id = 0

function MView:new(state)
  MView.super.new(self)
  next_id = next_id + 1
  self.key = "modelview" .. next_id
  self.filename = state and state.filename or ""
  self.ui = canvas.ui.new()
  self.yaw, self.pitch, self.dist = 0.6, 0.35, 3
  self.at = { 0, 0, 0 }
  self.ground, self.shadows = true, true
  self.skeleton, self.wireframe, self.normals = false, false, false
  self.model_on = true
  self.clip, self.t, self.playing = 0, 0, false
  self.blend_s, self.prev, self.fade = 0.25, nil, 0   -- (a new clip fades in over the last one, blend_s seconds)
  self.seq, self.seq_loop, self.seq_on, self.seq_i, self.hold = {}, true, false, 0, 0   -- the sequence: { clip = n } | { pause = s }
  self.outline = false                             -- (O: its outline, off at first)
  self.morph = {}                                  -- [k] = weight: the panel's, over the clip's
  self.fov, self.znear, self.zfar = 45, 0.01, 1000  -- (the camera: View > Camera)
  self.copies = 1                                  -- (the benchmark: the model this many times, each its clip from its own time)
  self.lod, self.lod_tint, self.stats = true, false, true   -- (levels of detail on, untinted; the numbers over the picture)
  self.lod_levels, self.lod_first, self.lod_mul = 4, nil, 2   -- (4 levels (the model's and 3 simpler), the first simpler one 5 radii
                                                   --  away (nil: from its size), each next twice as far)
  self.lod_colors = { { 90, 230, 90 }, { 250, 220, 50 }, { 255, 130, 40 }, { 240, 60, 60 } }   -- (level 1's first: green, yellow, orange, red)
  if state and state.cam then
    local c = state.cam
    self.yaw, self.pitch, self.dist, self.at = c.yaw or self.yaw, c.pitch or self.pitch, c.dist or self.dist, c.at or self.at
    self.placed = true
    if state.ground ~= nil then self.ground = state.ground end
    if state.shadows ~= nil then self.shadows = state.shadows end
    self.skeleton, self.wireframe, self.normals = state.skeleton or false, state.wireframe or false, state.normals or false
    if state.model_on ~= nil then self.model_on = state.model_on end
    if state.outline ~= nil then self.outline = state.outline end
    if type(state.blend_s) == "number" then self.blend_s = state.blend_s end
    if state.seq_loop ~= nil then self.seq_loop = state.seq_loop end
    self.seq_names = state.seq                     -- (clip names: matched once the model is read)
  end
  self:reload()
end
function MView:get_name() return base_of(self.filename) end
function MView:get_state()
  return { filename = self.filename, cam = { yaw = self.yaw, pitch = self.pitch, dist = self.dist, at = self.at },
           ground = self.ground, shadows = self.shadows, skeleton = self.skeleton, wireframe = self.wireframe, normals = self.normals, model_on = self.model_on,
           outline = self.outline, blend_s = self.blend_s, seq_loop = self.seq_loop, seq = self:seq_state() }
end
function MView:try_close(do_close)
  host_view3d { key = self.key, remove = true }
  shown.last[self.key] = nil
  do_close()
end

function MView:reload()
  local info = system.get_file_info(self.filename)
  self.mtime = info and info.modified
  self.info, self.err = host_model_info(self.filename)
  self.version = (self.version or 0) + 1
  if self.info and not self.placed then self:fit() end
  if self.info and self.clip > #(self.info.clips or {}) then self.clip, self.t = 0, 0 end
  if self.info and self.clip == 0 and #(self.info.clips or {}) > 0 then self.clip, self.t, self.playing = 1, 0, true end   -- (its first clip, playing)
  if self.info and self.seq_names then             -- (the sequence kept with the tab: by its clips' names)
    self.seq = {}
    for _, e in ipairs(self.seq_names) do
      if e.pause then self.seq[#self.seq + 1] = { pause = e.pause }
      else for n, c in ipairs(self.info.clips or {}) do if c.name == e.clip then self.seq[#self.seq + 1] = { clip = n }; break end end end
    end
    self.seq_names = nil
  end
  core.redraw = true
end

function MView:radius()
  local i = self.info
  if not i then return 1 end
  local dx, dy, dz = i.max[1] - i.min[1], i.max[2] - i.min[2], i.max[3] - i.min[3]
  return math.max(0.01, math.sqrt(dx * dx + dy * dy + dz * dz) / 2)
end
function MView:set_copies(n)                       -- the benchmark: n copies; the camera back so the grid fits, the clip playing
  n = math.max(1, math.min(2000, n))
  if n == self.copies then return end
  self.copies = n
  if self.info then
    local i = self.info
    if n > 1 and self.clip == 0 and #i.clips > 0 then self.clip, self.playing = 1, true end
  end
  self:fit()                                       -- (Fit: all of them in sight)
end
function MView:lod_dist()                          -- where each simpler level begins (m): the first, then each next lod_mul times as far
  local d, at = {}, self.lod_first or self:radius() * 5
  for k = 1, self.lod_levels - 1 do d[k] = at; at = at * self.lod_mul end
  return d
end
function MView:fit()                                -- the whole model in sight (the benchmark's copies too), its middle in the middle
  local i = self.info
  if not i then return end
  self.at = { (i.min[1] + i.max[1]) / 2, (i.min[2] + i.max[2]) / 2, (i.min[3] + i.max[3]) / 2 }
  local r = self:radius()
  if self.copies > 1 then                          -- (the grid: rings of copies round it, 1.6 x its width apart (render.h))
    local side = 1
    while side * side < self.copies do side = side + 2 end
    local half = math.max(i.max[1] - i.min[1], i.max[3] - i.min[3]) * 1.6 * (side - 1) / 2
    r = half * 1.15 + r                            -- (its corners nearer than a sphere round them: seen from above, at an angle)
  end
  self.dist = r / math.sin(math.rad(self.fov) / 2) * 1.1
  self.placed = true
  core.redraw = true
end

function MView:eye()
  local cp = math.cos(self.pitch)
  return { self.at[1] + self.dist * cp * math.sin(self.yaw), self.at[2] + self.dist * math.sin(self.pitch),
           self.at[3] + self.dist * cp * math.cos(self.yaw) }
end
function MView:rects()
  local x, y, w, h = self.position.x, self.position.y, self.size.x, self.size.y
  local rw = math.floor(math.min(S(260), w * 0.35))
  return { mid = { x, y, w - rw, h }, right = { x + w - rw, y, rw, h } }
end

-- playing: a clip (faded in over the one before), the sequence (its entries in order)
function MView:seq_state()
  local out = {}
  for _, e in ipairs(self.seq) do
    if e.pause then out[#out + 1] = { pause = e.pause }
    elseif self.info and self.info.clips[e.clip] then out[#out + 1] = { clip = self.info.clips[e.clip].name } end
  end
  return out
end
function MView:play(n, keep_seq)                   -- clip n now: the last one fades out under it (blend_s)
  if not keep_seq then self.seq_on = false end
  if self.clip > 0 and self.blend_s > 0 and self.playing then self.prev, self.fade = { clip = self.clip, t = self.t }, self.blend_s
  else self.prev, self.fade = nil, 0 end
  self.clip, self.t, self.playing, self.hold = n, 0, true, 0
  core.redraw = true
end
function MView:seq_next()                          -- the sequence's next entry (the end: again from the first, or stop)
  self.seq_i = self.seq_i + 1
  if self.seq_i > #self.seq then
    if not self.seq_loop or #self.seq == 0 then self.seq_on, self.playing = false, false; return end
    self.seq_i = 1
  end
  local e = self.seq[self.seq_i]
  if e.pause then self.hold = e.pause else self:play(e.clip, true) end
end
function MView:seq_play()
  if #self.seq == 0 then return end
  self.seq_on, self.seq_i = true, 0
  self:seq_next()
end
function MView:step(dt)
  if not (self.playing and self.info) then return end
  if self.prev then self.prev.t = self.prev.t + dt end
  if self.fade > 0 then self.fade = math.max(0, self.fade - dt); if self.fade == 0 then self.prev = nil end end
  if self.seq_on and self.hold > 0 then            -- (a pause: the last pose held)
    self.hold = self.hold - dt
    if self.hold <= 0 then self.hold = 0; self:seq_next() end
    return
  end
  if self.clip <= 0 then return end
  local len = self.info.clips[self.clip] and self.info.clips[self.clip].duration or 0
  self.t = self.t + dt
  if self.seq_on then                              -- (in the sequence: once, then the next)
    if self.t >= len then self.t = len; self:seq_next() end
  elseif len > 0 then self.t = self.t % len end
end
function MView:update()
  MView.super.update(self)
  if self.err == "no viewer yet" then self:reload() end   -- (the host's 3D wasn't up when the tab opened)
  local now = system.get_time()
  if self.playing and self.info then
    self:step(math.min(0.1, now - (self.last_t or now)))
    core.redraw = true
  end
  self:fly_step(math.min(0.1, now - (self.last_t or now)))
  self.last_t = now
  if now >= (self.next_check or 0) then
    self.next_check = now + 0.5                    -- the file changed on disk: read it again
    local info = system.get_file_info(self.filename)
    if info and info.modified ~= self.mtime then self:reload() end
    if now >= (MView.next_files or 0) then
      MView.next_files = now + 0.5
      if P.changed("files") then P.open_with(P.read("files") or {}, MView) end
    end
  end
end

local function hex(c) return string.format("#%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) end
function MView:draw_right(r)
  local ui, i = self.ui, self.info
  ui:begin(r[1], r[2], r[3], r[4], { divider_left = true })
  ui:head("Model")
  ui:text(self:get_name())
  if not i then
    ui:text("can't show it: " .. tostring(self.err), style.error or style.text)
    ui:finish()
    return
  end
  ui:label("Vertices", tostring(i.vertices))
  ui:label("Triangles", tostring(math.floor(i.indices / 3)))
  ui:label("Size (m)", string.format("%.2f x %.2f x %.2f", i.max[1] - i.min[1], i.max[2] - i.min[2], i.max[3] - i.min[3]))
  ui:head("Parts (" .. #i.parts .. ")")
  for n, p in ipairs(i.parts) do
    ui:label(string.format("%d: %d tris", n, p.triangles), (p.texture > 0 and ("tex " .. p.texture .. "  ") or "") .. hex(p.base))
  end
  if i.joints > 0 or #(i.clips or {}) > 0 then
    ui:head("Animation")
    if i.joints > 0 then ui:label("Joints", tostring(i.joints)) end
    if #i.clips == 0 then ui:text("no clips", style.dim) end
    ui:slider("Blend", self.blend_s, 0, 1, function(v) self.blend_s = v end, { fmt = self.blend_s > 0 and "%.2f s" or "off", step = 0.05, def = 0.25 })
    if self.clip > 0 then
      local len = i.clips[self.clip].duration
      ui:buttons({ { self.playing and "Pause  SPACE" or "Play  SPACE", function() self.playing = not self.playing end, accent = not self.playing },
                   { "Rest pose", function() self.clip, self.playing = 0, false end } })
      ui:slider("Time", self.t, 0, math.max(len, 0.001), function(v) self.t, self.playing = v, false end, { fmt = "%.2f s", step = 0.01, def = 0 })
    end
    ui:head("Sequence (" .. #self.seq .. ")")
    if #self.seq == 0 then ui:text("+ on a clip adds it here", style.dim) end
    for k, e in ipairs(self.seq) do                -- (each: up, down, out)
      local y = ui.cy
      local label = e.pause and string.format("%d  pause %g s", k, e.pause) or string.format("%d  %s", k, i.clips[e.clip] and i.clips[e.clip].name or "?")
      ui:check(label, self.seq_on and self.seq_i == k, function()   -- (a clip: played; a pause: longer, 0.5 .. 3 s, round)
        if e.clip then self:play(e.clip) else e.pause = ({ [0.5] = 1, [1] = 2, [2] = 3, [3] = 0.5 })[e.pause] or 1 end
      end)
      local bx = ui.x + ui.w - ui.pad
      bx = bx - S(26); ui:button_at(bx, y + S(1), "x", function() table.remove(self.seq, k); self.seq_on = false end, false, false, "take it out")
      bx = bx - S(26); ui:button_at(bx, y + S(1), "v", k < #self.seq and function() self.seq[k], self.seq[k + 1] = self.seq[k + 1], self.seq[k] end or nil, false, false, "down")
      bx = bx - S(26); ui:button_at(bx, y + S(1), "^", k > 1 and function() self.seq[k], self.seq[k - 1] = self.seq[k - 1], self.seq[k] end or nil, false, false, "up")
    end
    ui:buttons({ { self.seq_on and "Stop sequence" or "Play sequence", function() if self.seq_on then self.seq_on = false else self:seq_play() end end, accent = self.seq_on },
                 { "+ Pause 1 s", function() self.seq[#self.seq + 1] = { pause = 1 } end },
                 { "Clear", function() self.seq, self.seq_on = {}, false end } })
    ui:check("Loop the sequence", self.seq_loop, function() self.seq_loop = not self.seq_loop end)
    ui:head("Clips (" .. #i.clips .. ")")
    for n, c in ipairs(i.clips) do                 -- (a click plays it; + adds it to the sequence)
      local y = ui.cy
      ui:check(string.format("%s  (%.2f s)%s", c.name, c.duration, c.loops and "  loop" or ""), self.clip == n, function() self:play(n) end)
      ui:button_at(ui.x + ui.w - ui.pad - S(26), y + S(1), "+", function() self.seq[#self.seq + 1] = { clip = n } end, false, false, "add to the sequence")
    end
  end
  if #(i.morphs or {}) > 0 then
    ui:head("Blend shapes (" .. #i.morphs .. ")")
    for k, name in ipairs(i.morphs) do
      local short = name:match("_([^_]+)$") or name
      ui:slider(short, self.morph[k] or 0, 0, 1, function(v) self.morph[k] = v; core.redraw = true end, { fmt = self.morph[k] and "%.2f" or "clip", step = 0.05, def = 0 })
    end
    if next(self.morph) then ui:buttons({ { "From the clip", function() self.morph = {}; core.redraw = true end } }) end
  end
  ui:head("Textures (" .. #i.textures .. ")")
  if #i.textures == 0 then ui:text("none", style.dim) end
  for n, t in ipairs(i.textures) do ui:label(tostring(n), t.w .. " x " .. t.h) end
  ui:head("View")
  ui:check("Model  Alt+M", self.model_on, function() self.model_on = not self.model_on end)
  ui:check("Outline  Alt+O", self.outline, function() self.outline = not self.outline end)
  ui:check("Floor  Alt+G", self.ground, function() self.ground = not self.ground end)
  ui:check("Shadows  Alt+S", self.shadows, function() self.shadows = not self.shadows end)
  if i.joints > 0 then ui:check("Skeleton  Alt+K", self.skeleton, function() self.skeleton = not self.skeleton end) end
  ui:check("Wireframe  Alt+W", self.wireframe, function() self.wireframe = not self.wireframe end)
  ui:check("Normals  Alt+N", self.normals, function() self.normals = not self.normals end)
  ui:buttons({ { "Fit  Alt+F", function() self:fit() end } })
  ui:head("Camera")
  ui:slider("Field of view", self.fov, 10, 120, function(v) self.fov = v; core.redraw = true end, { fmt = "%.0f°", step = 1, def = 45 })
  ui:slider("Near", self.znear, 0.001, 10, function(v) self.znear = v; core.redraw = true end, { fmt = "%.3f m", step = 0.001, def = 0.01 })
  ui:slider("Far", self.zfar, 1, 100000, function(v) self.zfar = math.max(v, self.znear * 2); core.redraw = true end, { fmt = "%.0f m", step = 1, def = 1000 })
  ui:head("Benchmark")
  ui:slider("Copies", self.copies, 1, 2000, function(v) self:set_copies(math.floor(v + 0.5)) end, { fmt = "%d", int = true, step = 1, def = 1 })
  ui:buttons({ { "1", function() self:set_copies(1) end }, { "10", function() self:set_copies(10) end },
               { "100", function() self:set_copies(100) end }, { "1000", function() self:set_copies(1000) end } })
  ui:check("Levels of detail", self.lod, function() self.lod = not self.lod; core.redraw = true end)
  if self.lod then                                 -- (how many, where each begins, its colour)
    ui:slider("Levels", self.lod_levels, 1, 5, function(v) self.lod_levels = math.floor(v + 0.5); core.redraw = true end, { fmt = "%d", int = true, step = 1, def = 4 })
    if self.lod_levels > 1 then
      ui:slider("Level 1 from", self:lod_dist()[1], 0.1, math.max(50, self:radius() * 40), function(v) self.lod_first = v; core.redraw = true end, { fmt = "%.1f m", step = 0.1, def = self:radius() * 5 })
      ui:slider("Each next", self.lod_mul, 1.1, 4, function(v) self.lod_mul = v; core.redraw = true end, { fmt = "x %.2f", step = 0.05, def = 2 })
    end
    ui:check("Tint the levels", self.lod_tint, function() self.lod_tint = not self.lod_tint; core.redraw = true end)
    local d = self:lod_dist()
    for k = 1, self.lod_levels - 1 do
      ui:color(string.format("Level %d  from %.1f m", k, d[k]), self.lod_colors[k], function(c) self.lod_colors[k] = { c[1], c[2], c[3] }; core.redraw = true end)
    end
    if self.wireframe then ui:text("Wireframe: the nearest copy at each level too", style.dim) end
  end
  ui:check("Stats", self.stats, function() self.stats = not self.stats; core.redraw = true end)
  if i.joints > 0 and #i.clips > 0 then ui:text("Each copy loops the clip from its own time", style.dim) end
  ui:text("LMB: orbit   MMB: pan   wheel: zoom", style.dim)
  ui:text("RMB held: fly (W A S D Q/C E)", style.dim)
  ui:finish()
end

function MView:draw()
  self:draw_background(style.background)
  local r = self:rects()
  local m = r.mid
  if self.info and m[3] > 2 and m[4] > 2 then
    renderer.clear_rect(m[1], m[2], m[3], m[4])    -- (the hole: the host's 3D shows through)
    local bg = style.background
    host_view3d { key = self.key, file = self.filename, x = m[1], y = m[2], w = m[3], h = m[4],
                  eye = self:eye(), at = self.at, fov = self.fov, near = self.znear, far = self.zfar, copies = self.copies, lod = self.lod and self.lod_levels > 1, lod_tint = self.lod_tint, lod_dist = self:lod_dist(), lod_colors = self.lod_colors, clear = { bg[1], bg[2], bg[3], 255 },
                  ground = self.ground, shadows = self.shadows, clip = self.clip,
                  skeleton = self.skeleton, wireframe = self.wireframe, normals = self.normals, hide_model = not self.model_on, t = self.t, loop = not self.seq_on, morphs = self.morph,
                  outline = self.outline and self.model_on,
                  blend = self.prev and self.fade > 0 and self.blend_s > 0 and { clip = self.prev.clip, t = self.prev.t, w = self.fade / self.blend_s } or nil }
    shown.now[self.key] = true
  end
  renderer.draw_text(style.font, self:get_name() .. (self.info and "" or ("   can't show it: " .. tostring(self.err))),
                     m[1] + S(12), m[2] + S(10), self.info and style.dim or (style.error or style.text))
  if self.info and self.stats and rawget(_G, "host_view3d_stats") then   -- (the numbers, bottom left: Stats on)
    local now = system.get_time()
    self.fps_t = self.fps_t or {}
    table.insert(self.fps_t, now)
    while #self.fps_t > 1 and now - self.fps_t[1] > 1 do table.remove(self.fps_t, 1) end
    local items, culled, tris, draws, ms, _, skin = host_view3d_stats(self.key)
    if items then
      local lines = {
        string.format("copies %d   drawn %d / %d (culled %d)", self.copies, items - culled, items, culled),
        string.format("triangles %s   draw calls %s%s", tostring(tris), draws and draws >= 0 and tostring(draws) or "cpu",
                      skin == 1 and "   skinning: GPU" or skin == 0 and "   skinning: CPU (no GPU skinning here: see the log)" or ""),
        string.format("%.2f ms to draw (CPU)   %d fps   GPU: no timer in SDL_gpu", ms, #self.fps_t - 1),
      }
      local lh = style.font:get_height() + S(2)
      local bw = 0
      for _, t in ipairs(lines) do bw = math.max(bw, style.font:get_width(t)) end
      renderer.draw_rect(m[1] + S(6), m[2] + m[4] - S(14) - #lines * lh, bw + S(12), #lines * lh + S(8), { 0, 0, 0, 170 })
      for k, t in ipairs(lines) do renderer.draw_text(style.font, t, m[1] + S(12), m[2] + m[4] - S(10) - (#lines - k + 1) * lh, { 235, 235, 240, 255 }) end
    end
    core.redraw = true                             -- (counting frames: drawn every one while it runs)
  end
  self:draw_right(r.right)
end

function MView:in_mid(x, y) local m = self:rects().mid; return x >= m[1] and x < m[1] + m[3] and y >= m[2] and y < m[2] + m[4] end
-- the fly camera: RMB held in the picture (a click without moving: the menu): the mouse looks, W A S D Q E
-- move, Shift faster; the orbit goes on from where it ends (its target: ahead, as far as it was)
local fly = package.loaded["modelview.fly"] or {}
package.loaded["modelview.fly"] = fly
if not fly.patched then                            -- (the keys while it flies: its own, not lite's)
  fly.patched = true
  local kp, kr = keymap.on_key_pressed, keymap.on_key_released
  keymap.on_key_pressed = function(k, ...) local v = fly.view; if v and v.flying and v:fly_key(k, true) then return true end return kp(k, ...) end
  keymap.on_key_released = function(k, ...) local v = fly.view; if v and v.flying and v:fly_key(k, false) then return true end return kr(k, ...) end
end
local FLY_KEYS = { w = true, a = true, s = true, d = true, q = true, c = true, e = true, ["left shift"] = true, ["right shift"] = true }
function MView:fly_key(k, down)
  if not FLY_KEYS[k] then return false end
  self.fly_keys = self.fly_keys or {}
  self.fly_keys[(k == "left shift" or k == "right shift") and "shift" or k] = down or nil
  self.flying = "flying"
  return true
end
function MView:fly_look(dx, dy)                    -- (the eye stays: the target turns round it)
  local e = self:eye()
  self.yaw = self.yaw - dx * 0.005
  self.pitch = math.max(-1.55, math.min(1.55, self.pitch + dy * 0.005))
  local cp = math.cos(self.pitch)
  local o = { self.dist * cp * math.sin(self.yaw), self.dist * math.sin(self.pitch), self.dist * cp * math.cos(self.yaw) }
  self.at = { e[1] - o[1], e[2] - o[2], e[3] - o[3] }
  self.placed = true
  core.redraw = true
end
function MView:fly_step(dt)                        -- (W A S D Q E held: the eye and its target move together)
  local k = self.fly_keys
  if not (self.flying and k and next(k)) then return end
  local cp = math.cos(self.pitch)
  local f = { -cp * math.sin(self.yaw), -math.sin(self.pitch), -cp * math.cos(self.yaw) }   -- (where it looks)
  local r = { math.cos(self.yaw), 0, -math.sin(self.yaw) }
  local v = self:radius() * 1.5 * (k.shift and 4 or 1) * dt
  local fw = (k.w and 1 or 0) - (k.s and 1 or 0)
  local rt = (k.d and 1 or 0) - (k.a and 1 or 0)
  local up = (k.e and 1 or 0) - ((k.q or k.c) and 1 or 0)   -- (C: down too, as Q)
  for i = 1, 3 do self.at[i] = self.at[i] + v * (f[i] * fw + r[i] * rt) end
  self.at[2] = self.at[2] + v * up
  self.placed = true
  core.redraw = true
end
function MView:on_mouse_pressed(button, x, y, clicks)
  if self.ui:pressed(button, x, y, clicks) then return true end
  if not self:in_mid(x, y) then return MView.super.on_mouse_pressed(self, button, x, y, clicks) end
  if button == "right" then                        -- (held: it flies; a click: the menu, when let go)
    self.flying, self.fly_from, self.fly_keys = "held", { x, y }, {}
    fly.view = self
    return true
  end
  if button == "left" and clicks >= 2 then self:fit(); return true end
  local shift = keymap.modkeys and keymap.modkeys["shift"]
  self.drag = (button == "middle" or (button == "left" and shift)) and "pan" or button == "left" and "orbit" or nil
  return self.drag ~= nil
end
function MView:on_mouse_moved(x, y, dx, dy)
  if self.flying then
    local f = self.fly_from
    if self.flying == "held" and f and math.abs(x - f[1]) + math.abs(y - f[2]) > 4 then
      self.flying = "flying"
      if host_call then host_call("mouse_relative on") end   -- (looking: the cursor hidden, kept in the window)
    end
    if self.flying == "flying" then self:fly_look(dx, dy) end
    return
  end
  if self.ui:moved(x, y) then return end
  if self.drag == "orbit" then
    self.yaw = self.yaw - dx * 0.01
    self.pitch = math.max(-1.55, math.min(1.55, self.pitch + dy * 0.01))
    core.redraw = true
  elseif self.drag == "pan" then
    local m = self:rects().mid
    local k = 2 * self.dist * math.tan(math.rad(self.fov) / 2) / math.max(1, m[4])   -- (meters a pixel, at the target)
    local cy, sy = math.cos(self.yaw), math.sin(self.yaw)
    local sp, cp = math.sin(self.pitch), math.cos(self.pitch)
    local right = { cy, 0, -sy }                   -- (the camera's right and up)
    local up = { -sp * sy, cp, -sp * cy }
    for i = 1, 3 do self.at[i] = self.at[i] - right[i] * dx * k + up[i] * dy * k end
    core.redraw = true
  end
  MView.super.on_mouse_moved(self, x, y, dx, dy)
end
function MView:on_mouse_released(button, x, y)
  if button == "right" and self.flying then
    local was = self.flying
    self.flying, self.fly_keys = nil, nil
    if host_call then host_call("mouse_relative off") end   -- (the cursor back)
    if fly.view == self then fly.view = nil end
    if was == "held" then require("plugins.contextmenu"):show_items(x, y, self:menu_items()) end   -- (a click: its menu)
    return
  end
  if self.ui:released(button) then return end
  self.drag = nil
  MView.super.on_mouse_released(self, button, x, y)
end
function MView:on_mouse_wheel(dy, dx)
  if self.ui:wheel(dy) then return true end
  self.dist = math.max(self:radius() * 0.05, math.min(self:radius() * 200, self.dist * (dy > 0 and 1 / 1.15 or 1.15)))
  core.redraw = true
  return true
end
function MView:menu_items()
  return {
    { text = "Fit", info = "Alt+F / dbl-click", command = function() self:fit() end },
    { text = "Front", command = function() self.yaw, self.pitch = 0, 0; core.redraw = true end },
    { text = "Side", command = function() self.yaw, self.pitch = math.pi / 2, 0; core.redraw = true end },
    { text = "Top", command = function() self.yaw, self.pitch = 0, 1.55; core.redraw = true end },
    require("plugins.contextmenu").DIVIDER,
    { text = "Floor", info = "Alt+G", checked = self.ground, command = function() self.ground = not self.ground; core.redraw = true end },
    { text = "Shadows", info = "Alt+S", checked = self.shadows, command = function() self.shadows = not self.shadows; core.redraw = true end },
    { text = "Outline", info = "Alt+O", checked = self.outline, command = function() self.outline = not self.outline; core.redraw = true end },
    { text = "Model", info = "Alt+M", checked = self.model_on, command = function() self.model_on = not self.model_on; core.redraw = true end },
    { text = "Skeleton", info = "Alt+K", checked = self.skeleton, command = function() self.skeleton = not self.skeleton; core.redraw = true end },
    { text = "Wireframe", info = "Alt+W", checked = self.wireframe, command = function() self.wireframe = not self.wireframe; core.redraw = true end },
    { text = "Normals", info = "Alt+N", checked = self.normals, command = function() self.normals = not self.normals; core.redraw = true end },
    { text = "Reload model", command = function() self:reload() end },
  }
end

command.add(function() return core.active_view and core.active_view:is(MView) end, {
  ["modelview:fit"] = function() core.active_view:fit() end,
  ["modelview:outline"] = function() local v = core.active_view; v.outline = not v.outline; core.redraw = true end,
  ["modelview:model"] = function() local v = core.active_view; v.model_on = not v.model_on; core.redraw = true end,
  ["modelview:skeleton"] = function() local v = core.active_view; v.skeleton = not v.skeleton; core.redraw = true end,
  ["modelview:wireframe"] = function() local v = core.active_view; v.wireframe = not v.wireframe; core.redraw = true end,
  ["modelview:normals"] = function() local v = core.active_view; v.normals = not v.normals; core.redraw = true end,
  ["modelview:play"] = function() local v = core.active_view; if v.clip > 0 then v.playing = not v.playing end; core.redraw = true end,
  ["modelview:floor"] = function() local v = core.active_view; v.ground = not v.ground; core.redraw = true end,
  ["modelview:shadows"] = function() local v = core.active_view; v.shadows = not v.shadows; core.redraw = true end,
})
if not package.loaded["modelview.keys2"] then       -- (Alt+letter: plain letters are the fly camera's, and lite's)
  package.loaded["modelview.keys2"] = true
  keymap.add { ["alt+f"] = "modelview:fit", ["alt+g"] = "modelview:floor", ["alt+s"] = "modelview:shadows", ["space"] = "modelview:play",
               ["alt+m"] = "modelview:model", ["alt+o"] = "modelview:outline", ["alt+k"] = "modelview:skeleton", ["alt+w"] = "modelview:wireframe",
               ["alt+n"] = "modelview:normals" }
end

P.open_with(P.read("files") or {}, MView)
P.commands = { { "Fit", "modelview:fit" }, { "Floor", "modelview:floor" }, { "Shadows", "modelview:shadows" }, { "Play / pause", "modelview:play" },
              { "Model on / off", "modelview:model" }, { "Outline", "modelview:outline" }, { "Skeleton", "modelview:skeleton" }, { "Wireframe", "modelview:wireframe" }, { "Normals", "modelview:normals" } }
return MView
