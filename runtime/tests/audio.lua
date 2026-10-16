-- audio.lua - the game's sounds and music (runtime/sound.lua, editor/sound.h):
-- every format decodes, sounds play with pan / pitch / loop / a bus, music
-- streams and crossfades, Stop silences it all. Runs in the game's VM:
--   replay games/pong.lua --headless --ticks 30 --type "dofile('runtime/tests/audio.lua')@2"
-- (SDL_AUDIODRIVER=dummy is enough: nothing needs to be heard). run.lua: "audio".
local ecs = require('ecs')
local fs = require('fs')
local ok_n, bad = 0, 0
local function check(c, what) if c then ok_n = ok_n + 1 else bad = bad + 1; print('FAIL: ' .. what) end end
local dir = (rawget(_G, 'REPLAY_ROOT') or '.') .. '/runtime/tests/audio'
if not fs.read(dir .. '/tone.wav') then dir = 'runtime/tests/audio' end
for _, ext in ipairs({ 'wav', 'ogg', 'mp3', 'flac' }) do
  local secs, ch, rate = host_audio_info(dir .. '/tone.' .. ext)
  check(secs and secs > 0.4 and secs < 0.65 and ch == 1 and rate == 22050, ext .. ': decoded, 0.5 s mono 22050 (' .. tostring(secs) .. ', ' .. tostring(ch) .. ', ' .. tostring(rate) .. ')')
end
check(host_audio_info(dir .. '/nope.wav') == nil, 'a missing file: nil')
local old_path = ecs.assets.path
ecs.assets.path = function(name) return dir .. '/' .. name end   -- (the test's files as the game's assets)
local w = ecs.world()
local h = w:sound('tone.ogg', { volume = 0.5, pan = -1, pitch = 1.5 })
check(type(h) == 'number', 'w:sound(file, { volume, pan, pitch }): a handle: ' .. tostring(h))
check(w:sound_set(h, { volume = 0.2, pitch = 0.8 }) == true, 'w:sound_set: still playing')
w:sound_stop(h)
check(w:sound_set(h, { volume = 1 }) == false, 'w:sound_stop: gone')
local hl = w:sound('tone.wav', { loop = true, bus = 'voice' })
check(type(hl) == 'number' and w:sound_set(hl, {}) == true, 'a loop: playing')
local hs = {}
for i = 1, 20 do hs[i] = w:sound('tone.mp3') end
check(hs[20] and w:sound_set(hl, {}) == true, 'twenty sounds: the loop keeps its voice')
check(w:bus('voice', 0.5) == 0.5 and w:bus('voice') == 0.5 and w:bus('sfx') == 1, 'w:bus: set and read')
check(w:music('music.ogg', { volume = 0.8 }) == true, 'w:music: streams an .ogg')
check(w:music('tone.flac', { fade = 0.5 }) == true, 'w:music: another, crossfading')
check(w:music('nope.ogg') == false, 'w:music: a missing file: false')
check(w:music(false, { fade = 0.2 }) == true, 'w:music(false): stops it')
w.replaying = true
check(w:sound('tone.wav') == false and w:music('music.ogg') == false, 'replaying: silent')
w.replaying = nil
host_sound_stop()
check(w:sound_set(hl, {}) == false, 'host_sound_stop: the loop too')
ecs.assets.path = old_path
print(string.format('audio: %d checks ok, %d failed', ok_n, bad))
assert(bad == 0, 'audio: ' .. bad .. ' failed')
