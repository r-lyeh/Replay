-- sound.lua - the game's sounds and music (w:sound, w:music, w:bus: runtime/ecs.lua
-- says how to call them), played through the host (editor/sound.h: sixteen
-- voices and a music track, mixed by SDL3; .wav / .ogg / .mp3 / .flac decoded
-- there). An .sfx (a sound effect made with the sfxr plugin: plain data,
-- sfxr's parameters) is rendered here by runtime/sfxr.lua once, again when
-- its file changes; a .soundgraph (a sound graph, plugins/soundgraph) the same way, by
-- runtime/soundgraph.lua. Without the host (headless, a test) nothing plays: they
-- return false. Files come from the game's assets/ (a script game's:
-- games/common/), by name: "jump" (jump.sfx, else jump.soundgraph), "theme.ogg".
local sfxr = require('sfxr')
local soundgraph = require('soundgraph')
local ecs = require('ecs')

local M = { cache = {}, volume = 1 }
local FILES = { wav = true, ogg = true, mp3 = true, flac = true }

local function clean(name)
  name = tostring(name):gsub('^/assets/', ''):gsub('^/', '')
  if not name:find('%.%w+$') then                   -- (no extension: an .sfx, else a .soundgraph)
    name = (ecs.assets.read and not ecs.assets.read(name .. '.sfx') and ecs.assets.read(name .. '.soundgraph')) and (name .. '.soundgraph') or (name .. '.sfx')
  end
  return name
end
local function opts_of(o)                          -- a number: the volume; a table: its fields
  if type(o) == 'number' then return { volume = o } end
  return type(o) == 'table' and o or {}
end

function M.play(w, name, o)
  if M.muted then return false end
  name = clean(name)
  o = opts_of(o)
  local vol, pan, pitch, bus, loop = (o.volume or 1) * M.volume, o.pan or 0, o.pitch or 1, o.bus or 'sfx', o.loop and true or false
  local ext = name:match('%.(%w+)$'):lower()
  if FILES[ext] then
    local path = host_sound_file and ecs.assets.path(name)
    if not path then return false end
    return host_sound_file(path, vol, pan, pitch, bus, loop) or false
  end
  if not host_sound then return false end
  local text = ecs.assets.read(name)
  if not text then return false end
  local c = M.cache[name]
  if not c or c.text ~= text then                  -- (rendered once; again when it changed)
    local p = ecs.decode(text, name)
    if type(p) ~= 'table' then return false end
    if ext == 'soundgraph' then c = { text = text, pcm = soundgraph.pcm16((soundgraph.render(p, nil, { read = ecs.assets.read }))) }
    else c = { text = text, pcm = sfxr.pcm16(sfxr.render(sfxr.check(p))) } end
    M.cache[name] = c
  end
  return host_sound(c.pcm, sfxr.RATE, vol, pan, pitch, bus, loop) or false
end

function M.set(w, h, o)
  if not (host_sound_set and h) then return false end
  o = opts_of(o)
  return host_sound_set(h, o.volume and o.volume * M.volume, o.pitch) and true or false
end
function M.stop(w, h)
  if host_sound_kill and h then host_sound_kill(h) end
end
function M.music(w, name, o)
  if not host_music then return false end
  o = opts_of(o)
  if not name then return host_music(nil, 0, o.fade or 0) and true or false end
  name = tostring(name):gsub('^/assets/', ''):gsub('^/', '')
  local path = ecs.assets.path(name)
  if not path then return false end
  local loop = o.loop
  if loop == nil then loop = true end
  local ok, err = host_music(path, (o.volume or 1) * M.volume, o.fade or 0, loop)
  if not ok and err then print('music: ' .. name .. ': ' .. tostring(err)) end
  return ok and true or false
end
function M.bus(w, name, volume)
  if not host_bus then return 1 end
  return host_bus(tostring(name), volume)
end

ecs.sound = M.play
ecs.audio.set, ecs.audio.stop, ecs.audio.music, ecs.audio.bus = M.set, M.stop, M.music, M.bus
return M
