-- anim.lua - sprite animations: a spritesheet's animations, frame by frame
-- (plugins/spriteanim edits them in a .anim file; games play them). Plain
-- Lua, no world needed; games: local a = w:anim("hero.anim"), and in systems
-- the global `anim`.
--
-- A .anim is Lua data (version 2):
--   return { version = 2, sheet = "hero.png",     -- the picture (beside the .anim, in assets/)
--     hit_names = { "body", "attack" },           -- hitboxes' names, for every frame (optional; a hole: false)
--     anims = { { name = "run", frames = {
--       { rect = { x0, y0, x1, y1 },              -- the frame in the sheet, pixels (x1, y1: past its last)
--         pivot = { x, y },                       -- its anchor: the point on the node, from the rect's top left
--                                                 --   (default: its middle; may be outside it)
--         pause = 100,                            -- ms it shows
--         events = { 'sound("step")', 'fx("dust")' },   -- sent when it shows
--         hits = { { x0, y0, x1, y1 }, ... },     -- hitboxes 1..10, from the rect's top left (a hole: false)
--         outline1 = { r, g, b, a }, outline2 = { r, g, b, a },   -- 1 px outline, then 1 px more (nil: none)
--         jump = 1 },                             -- after its pause: frame 1 (a loop); "idle" / "idle 3": another animation
--       ... } }, ... } }
-- The next frame, after a frame's pause: its jump, else the next one; after
-- the last with no jump the animation ends (s.done). Older files (no
-- version: anchor and hit1 / hit2 in sheet pixels, loop, a flow of Lua) are
-- read as version 2 (M.upgrade); a legacy flow still runs.
--
--   anim.upgrade(def) -> def in version 2 (plain data: what the editor edits)
--   anim.check(def) -> def, with defaults and its anims by name (def.by_name)
--   anim.new(def, name [, frame]) -> s: what plays ({ anim, frame, t, done, vars })
--   anim.step(def, s, dt [, on_event]) -> s, events fired ({ { name, arg, text }... });
--     on_event(name, arg, text) for each too (sound("x") -> "sound", "x")
--   anim.play(def, s, name [, frame]): another animation, from frame (1)
--   anim.frame(def, s) -> the frame showing (its table: rect, pivot, anchor in the sheet, hits...)
--   anim.image(def, s [, image]) -> an `image` component for it: { sheet, src =
--     { x, y, w, h }, w, h, ax, ay, outline1, outline2 } (reuses `image`)
--   anim.hitbox(def, s, which, x, y [, sx, sy]) -> x0, y0, x1, y1 in the world
--     (which: 1..10, or its name: "attack"; x, y: the node's place, sx, sy its scale) | nil
--   anim.hitboxes(def, s, x, y [, sx, sy]) -> { [which] = { x0, y0, x1, y1 } } in the world
--     (by number, and by name too when it has one)
--   anim.parse_event(text) -> name, arg ('sound("hit")' -> "sound", "hit")
--   anim.parse_jump(text) -> frame | name, frame | nil ("3" -> 3; "run 2" -> "run", 2)
local M = {}

local function num(v, d) v = tonumber(v); return v == nil and d or v end
local function rect(r)
  if type(r) ~= "table" then return nil end
  return { num(r[1], 0), num(r[2], 0), num(r[3], num(r[1], 0) + 1), num(r[4], num(r[2], 0) + 1) }
end
local function color(c)
  if type(c) ~= "table" then return nil end
  return { num(c[1], 0), num(c[2], 0), num(c[3], 0), num(c[4], 255) }
end

M.MAX_HITS = 10
function M.parse_jump(j)
  if type(j) == "number" then return math.floor(j) end
  if type(j) ~= "string" then return nil end
  local t = j:match("^%s*(.-)%s*$")
  if t == "" then return nil end
  if t:match("^%d+$") then return tonumber(t) end
  local name, f = t:match("^([^%s]+)%s+(%d+)$")
  if name then return name, tonumber(f) end
  return t, 1
end
-- older files -> version 2: anchor, hit1 / hit2 in sheet pixels become the
-- rect's; loop (default true) becomes the last frame's jump = 1
function M.upgrade(def)
  def = type(def) == "table" and def or {}
  if def.version == 2 then return def end
  local out = { version = 2, sheet = type(def.sheet) == "string" and def.sheet or "", anims = {}, hit_names = def.hit_names }
  for i, a in ipairs(type(def.anims) == "table" and def.anims or {}) do
    local A = { name = type(a.name) == "string" and a.name ~= "" and a.name or ("anim" .. i), frames = {} }
    local frames = type(a.frames) == "table" and a.frames or {}
    for k, f in ipairs(frames) do
      local r = rect(f.rect) or { 0, 0, 16, 16 }
      local F = { rect = r, pause = f.pause, events = f.events, outline1 = f.outline1, outline2 = f.outline2, flow = f.flow }
      if type(f.anchor) == "table" then F.pivot = { num(f.anchor[1], 0) - r[1], num(f.anchor[2], 0) - r[2] } end
      local hits = {}
      for w = 1, 2 do local h = rect(f["hit" .. w]); if h then hits[w] = { h[1] - r[1], h[2] - r[2], h[3] - r[1], h[4] - r[2] } end end
      if hits[2] and not hits[1] then hits[1] = false end
      if next(hits) then F.hits = hits end
      A.frames[k] = F
    end
    local last = A.frames[#A.frames]
    if last and a.loop ~= false and not last.flow then last.jump = 1 end
    out.anims[#out.anims + 1] = A
  end
  return out
end

function M.check(def)
  def = M.upgrade(def)
  local out = { sheet = type(def.sheet) == "string" and def.sheet or "", anims = {}, by_name = {}, hit_names = {}, hit_index = {} }
  for w = 1, M.MAX_HITS do                         -- (hitboxes' names: the same for every frame)
    local n = type(def.hit_names) == "table" and def.hit_names[w]
    if type(n) == "string" and n ~= "" then out.hit_names[w] = n; if not out.hit_index[n] then out.hit_index[n] = w end end
  end
  for i, a in ipairs(type(def.anims) == "table" and def.anims or {}) do
    local name = type(a.name) == "string" and a.name ~= "" and a.name or ("anim" .. i)
    local A = { name = name, frames = {} }
    for k, f in ipairs(type(a.frames) == "table" and a.frames or {}) do
      local r = rect(f.rect) or { 0, 0, 16, 16 }
      local pv = type(f.pivot) == "table" and { num(f.pivot[1], (r[3] - r[1]) / 2), num(f.pivot[2], (r[4] - r[2]) / 2) }
                 or { (r[3] - r[1]) / 2, (r[4] - r[2]) / 2 }
      local ev = {}
      for _, e in ipairs(type(f.events) == "table" and f.events or {}) do if type(e) == "string" and e ~= "" then ev[#ev + 1] = e end end
      local hits = {}
      for w = 1, M.MAX_HITS do local h = type(f.hits) == "table" and rect(f.hits[w]); if h then hits[w] = h end end
      local ja, jb = M.parse_jump(f.jump)
      A.frames[k] = { rect = r, pivot = pv, anchor = { r[1] + pv[1], r[2] + pv[2] }, pause = math.max(1, num(f.pause, 100)), events = ev,
                      hits = hits, outline1 = color(f.outline1), outline2 = color(f.outline2),
                      jump_frame = type(ja) == "number" and ja or jb, jump_anim = type(ja) == "string" and ja or nil,
                      flow = type(f.flow) == "string" and f.flow ~= "" and f.flow or nil }
    end
    if #A.frames == 0 then A.frames[1] = { rect = { 0, 0, 16, 16 }, pivot = { 8, 8 }, anchor = { 8, 8 }, pause = 100, events = {}, hits = {} } end
    out.anims[#out.anims + 1] = A
    if not out.by_name[name] then out.by_name[name] = A end
  end
  return out
end

-- a frame's flow, compiled once (its text the key): function(f, a, s) -> next
local flows = setmetatable({}, { __mode = "k" })
local FLOW_ENV = { math = math, string = string, table = table, tonumber = tonumber, tostring = tostring, type = type,
                   pairs = pairs, ipairs = ipairs, select = select }
local function flow_fn(text)
  local c = flows[text]
  if c ~= nil then return c or nil end
  local src = "return function(f, a, s)\n" .. text .. "\nend"
  local chunk
  local setfenv_, loadstring_ = rawget(_G, "setfenv"), rawget(_G, "loadstring")   -- (rawget: lite's globals are strict)
  if setfenv_ and loadstring_ then
    chunk = loadstring_(src, "=flow")
    if chunk then setfenv_(chunk, FLOW_ENV) end
  else
    chunk = load(src, "=flow", "t", FLOW_ENV)
  end
  local ok, fn = false, nil
  if chunk then ok, fn = pcall(chunk) end
  c = ok and type(fn) == "function" and fn or false
  flows[text] = c
  return c or nil
end
M.flow_fn = flow_fn

function M.new(def, name, frame)
  local A = def.by_name[name] or def.anims[1]
  return { anim = A and A.name or "", frame = math.max(1, math.floor(num(frame, 1))), t = 0, done = false, vars = {} }
end
function M.play(def, s, name, frame)
  local A = def.by_name[name]
  if not A then return s end
  s.anim, s.frame, s.t, s.done, s.fired = A.name, math.max(1, math.min(#A.frames, math.floor(num(frame, 1)))), 0, false, nil
  return s
end
function M.frame(def, s)
  local A = def.by_name[s.anim] or def.anims[1]
  return A and A.frames[math.max(1, math.min(#A.frames, s.frame))], A
end

function M.parse_event(text)
  local name, arg = tostring(text):match("^%s*([%w_]+)%s*%(%s*(.-)%s*%)%s*$")
  if not name then return tostring(text):match("^%s*(.-)%s*$"), nil end
  local q = arg:match('^"(.*)"$') or arg:match("^'(.*)'$")
  if q then arg = q elseif arg == "" then arg = nil else arg = tonumber(arg) or arg end
  return name, arg
end

-- the next frame after f (its jump, a legacy flow, or the next) -> anim name, frame (frame 0: it ends)
local function next_of(def, A, f, s)
  local fr = A.frames[f]
  if fr and fr.jump_anim and def.by_name[fr.jump_anim] then return fr.jump_anim, fr.jump_frame or 1 end
  if fr and fr.jump_frame and not fr.jump_anim then return A.name, fr.jump_frame end
  if fr and fr.flow then
    local fn = flow_fn(fr.flow)
    if fn then
      local ok, a, b = pcall(fn, f, A.name, s)
      if ok and type(a) == "string" and def.by_name[a] then return a, math.floor(num(b, 1)) end
      if ok and type(a) == "number" then return A.name, math.floor(a) end
    end
  end
  if f >= #A.frames then return A.name, 0 end
  return A.name, f + 1
end

function M.step(def, s, dt, on_event)
  local fired = {}
  local function fire(fr)                          -- (a frame shown: its events, once)
    for _, e in ipairs(fr.events) do
      local name, arg = M.parse_event(e)
      fired[#fired + 1] = { name, arg, e }
      if on_event then pcall(on_event, name, arg, e) end
    end
  end
  if s.done then return s, fired end
  local fr, A = M.frame(def, s)
  if not fr then s.done = true return s, fired end
  if not s.fired then s.fired = true; fire(fr) end
  s.t = s.t + math.max(0, num(dt, 0)) * 1000
  local guard = 0
  while s.t >= fr.pause and guard < 64 do          -- (a long dt: several frames, each fired)
    guard = guard + 1
    s.t = s.t - fr.pause
    local an, f = next_of(def, A, s.frame, s)
    if f <= 0 then s.done = true; s.t = 0; return s, fired end
    A = def.by_name[an] or A
    s.anim, s.frame = A.name, math.max(1, math.min(#A.frames, f))
    fr = A.frames[s.frame]
    fire(fr)
  end
  return s, fired
end

function M.image(def, s, img)
  local fr = M.frame(def, s)
  img = type(img) == "table" and img or {}
  if not fr then return img end
  local r = fr.rect
  img[1] = img[1] or ("/assets/" .. def.sheet)
  img.src = { x = r[1], y = r[2], w = r[3] - r[1], h = r[4] - r[2] }
  img.w, img.h = r[3] - r[1], r[4] - r[2]
  img.ax, img.ay = fr.pivot[1], fr.pivot[2]         -- (its anchor, in the frame: render.h places it on the node)
  if img.smooth == nil then img.smooth = false end
  img.outline1, img.outline2 = fr.outline1, fr.outline2   -- (render.h draws them round its opaque pixels)
  return img
end

function M.hitbox(def, s, which, x, y, sx, sy)
  local fr = M.frame(def, s)
  if type(which) == "string" then which = def.hit_index and def.hit_index[which] or tonumber(which) end
  local h = fr and fr.hits and which and fr.hits[math.floor(num(which, 1))]
  if not h then return nil end
  sx, sy = num(sx, 1), num(sy, 1)
  local px, py = fr.pivot[1], fr.pivot[2]
  return num(x, 0) + (h[1] - px) * sx, num(y, 0) + (h[2] - py) * sy, num(x, 0) + (h[3] - px) * sx, num(y, 0) + (h[4] - py) * sy
end
function M.hitboxes(def, s, x, y, sx, sy)
  local out = {}
  local fr = M.frame(def, s)
  for w in pairs(fr and fr.hits or {}) do
    out[w] = { M.hitbox(def, s, w, x, y, sx, sy) }
    local name = def.hit_names and def.hit_names[w]
    if name then out[name] = out[w] end
  end
  return out
end

-- a .anim read with w:anim has these as methods: a:new(name), a:step(s, dt, on_event),
-- a:play(s, name), a:frame(s), a:image(s, img), a:hitbox(s, which, x, y, sx, sy), a:hitboxes(s, x, y, sx, sy)
M.methods = { __index = {
  new = function(d, name, frame) return M.new(d, name, frame) end,
  step = function(d, s, dt, on_event) return M.step(d, s, dt, on_event) end,
  play = function(d, s, name, frame) return M.play(d, s, name, frame) end,
  frame = function(d, s) return M.frame(d, s) end,
  image = function(d, s, img) return M.image(d, s, img) end,
  hitbox = function(d, s, which, x, y, sx, sy) return M.hitbox(d, s, which, x, y, sx, sy) end,
  hitboxes = function(d, s, x, y, sx, sy) return M.hitboxes(d, s, x, y, sx, sy) end,
} }

-- in games: w:anim(name) reads assets/<name>(.anim), again when it changes; the global anim in systems
local ok, ecs = pcall(require, "ecs")
if ok and type(ecs) == "table" then
  if ecs.code_globals then ecs.code_globals.anim = M end
  local World = ecs.World or (ecs.world and getmetatable(ecs.world()).__index)
  local cache = {}
  if World and ecs.assets then
    function World:anim(name)
      name = tostring(name):gsub("^/assets/", ""):gsub("^/", "")
      if not name:find("%.%w+$") then name = name .. ".anim" end
      local text = ecs.assets.read(name)
      if not text then return nil, "no asset " .. name end
      local c = cache[name]
      if not c or c.text ~= text then
        local raw = ecs.decode(text, name)
        local d = M.check(raw)
        if d.sheet ~= "" and not d.sheet:find("/") then   -- (the sheet beside the .anim)
          local dir = name:match("^(.*)/[^/]*$")
          if dir then d.sheet = dir .. "/" .. d.sheet end
        end
        c = { text = text, d = setmetatable(d, M.methods) }
        cache[name] = c
      end
      return c.d
    end
  end
end
return M
