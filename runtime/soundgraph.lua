-- soundgraph.lua - sound effects made as node graphs (.soundgraph files): oscillators,
-- noise, envelopes, slides and LFOs into filters, delays, a reverb, a
-- vocoder... into one Output. Rendered here, offline, to samples: the editor
-- (plugins/soundgraph) plays them as you change them, and games play them by
-- name like any sound: w:sound("boom") plays assets/boom.soundgraph (runtime/sound.lua).
-- Plain Lua: no Lite, no host.
--
--   local SG = require("soundgraph")
--   local s = SG.render(graph)        -- graph: a .soundgraph's table -> samples (-1..1), 44100 a second, mono
--   local pcm = SG.pcm16(s)           -- 16-bit little-endian (host_sound, host_audio_play)
--   local wav = SG.wav(s)             -- a .wav file (a string)
--
-- A .soundgraph file is canvas.GraphView's graph, as Lua data:
--   return { nodes = { { id = 1, kind = "osc", x = 0, y = 0, data = { freq = 440 } }, ... },
--            links = { { from = 1, out = "out", to = 2, input = "in" }, ... } }
-- A node's data holds its settings (what's missing: its default, M.KINDS).
-- Two kinds of wire: audio (a sound, -1..1) and control (a value that moves:
-- an envelope 0..1, a slide or an LFO in octaves...). Control inputs say
-- what they do: an oscillator's `pitch` adds octaves, its `amp` multiplies;
-- unwired, they do nothing (pitch 0, amp 1). Wires that would loop back are
-- read a sample late (a feedback path works, as a delay of one sample).
--
-- The filters are Robert Bristow-Johnson's Audio EQ Cookbook biquads; the
-- reverb is Jezar's Freeverb (public domain); the vocoder a channel vocoder
-- (band-pass pairs and envelope followers); everything else textbook. Ours.
local M = {}
M.RATE = 44100
M.MAX_LENGTH = 10                                  -- (seconds: the most an Output renders)

local sin, cos, pi, floor, abs, exp, log, sqrt = math.sin, math.cos, math.pi, math.floor, math.abs, math.exp, math.log, math.sqrt
local TAU = 2 * pi
local function tanh(x)                             -- (math.tanh is gone in 5.3+)
  if x > 20 then return 1 elseif x < -20 then return -1 end
  local e = exp(2 * x)
  return (e - 1) / (e + 1)
end
M.tanh = tanh

-- the kinds of node: title, header colour, pins ({ name, type, default when
-- unwired }), settings ({ name, min, max, default, unit, log = scale,
-- int = whole, options = { names } }), what it is (a line for the tooltip)
local WAVES = { "sine", "square", "saw", "triangle" }
M.KINDS = {
  output = { title = "Output", color = "#8a2b2b", order = 1, about = "what you hear: its length and loudness",
    ins = { { "in", "audio", 0 } }, outs = {},
    params = { { "length", 0.05, M.MAX_LENGTH, 0.6, unit = "s", log = true }, { "volume", 0, 1, 0.8 } } },
  osc = { title = "Oscillator", color = "#3c3c83", order = 2, about = "a tone: pitch (octaves) and amp wired move it",
    ins = { { "pitch", "control", 0 }, { "amp", "control", 1 } }, outs = { { "out", "audio" } },
    params = { { "wave", options = WAVES, 1 }, { "freq", 20, 8000, 440, unit = "Hz", log = true }, { "duty", 0.05, 0.95, 0.5 }, { "level", 0, 1, 0.8 } } },
  noise = { title = "Noise", color = "#3c3c83", order = 3, about = "hiss: white, pink (softer) or brown (a rumble)",
    ins = { { "amp", "control", 1 } }, outs = { { "out", "audio" } },
    params = { { "color", options = { "white", "pink", "brown" }, 1 }, { "level", 0, 1, 0.8 }, { "seed", 1, 999, 1, int = true } } },
  env = { title = "Envelope", color = "#6a5a20", order = 4, about = "attack, decay, sustain, release: 0..1 over time (wire it into an amp)",
    ins = {}, outs = { { "out", "control" } },
    params = { { "attack", 0, 2, 0.01, unit = "s" }, { "decay", 0, 2, 0.15, unit = "s" }, { "sustain", 0, 1, 0.5 },
               { "hold", 0, 5, 0.2, unit = "s" }, { "release", 0, 3, 0.25, unit = "s" } } },
  slide = { title = "Slide", color = "#6a5a20", order = 5, about = "from one value to another (octaves, for a pitch)",
    ins = {}, outs = { { "out", "control" } },
    params = { { "from", -4, 4, 1 }, { "to", -4, 4, -1 }, { "time", 0.01, 5, 0.3, unit = "s", log = true }, { "curve", -1, 1, 0 } } },
  lfo = { title = "LFO", color = "#6a5a20", order = 6, about = "a slow wave: vibrato (into pitch), tremolo (into amp), wah (into cutoff)",
    ins = {}, outs = { { "out", "control" } },
    params = { { "wave", options = WAVES, 1 }, { "rate", 0.1, 40, 6, unit = "Hz", log = true }, { "depth", 0, 2, 0.1 }, { "offset", -2, 2, 0 } } },
  number = { title = "Value", color = "#6a5a20", order = 7, about = "a constant",
    ins = {}, outs = { { "out", "control" } }, params = { { "value", -4, 4, 1 } } },
  gain = { title = "Gain", color = "#2e5470", order = 8, about = "louder or softer; amount wired (an envelope) shapes it",
    ins = { { "in", "audio", 0 }, { "amount", "control", 1 } }, outs = { { "out", "audio" } },
    params = { { "gain", 0, 4, 1 } } },
  mix = { title = "Mix", color = "#2e5470", order = 9, about = "three sounds into one",
    ins = { { "a", "audio", 0 }, { "b", "audio", 0 }, { "c", "audio", 0 } }, outs = { { "out", "audio" } },
    params = { { "a", 0, 1, 0.7 }, { "b", 0, 1, 0.7 }, { "c", 0, 1, 0.7 } } },
  ring = { title = "Ring mod", color = "#2e5470", order = 10, about = "two sounds multiplied: metallic, robotic",
    ins = { { "a", "audio", 0 }, { "b", "audio", 0 } }, outs = { { "out", "audio" } }, params = {} },
  filter = { title = "Filter", color = "#2f5b5b", order = 11, about = "keeps some frequencies (RBJ biquad); cutoff wired adds octaves",
    ins = { { "in", "audio", 0 }, { "cutoff", "control", 0 } }, outs = { { "out", "audio" } },
    params = { { "type", options = { "lowpass", "highpass", "bandpass", "notch", "peak", "lowshelf", "highshelf" }, 1 },
               { "cutoff", 20, 18000, 1200, unit = "Hz", log = true }, { "q", 0.1, 20, 0.707, log = true }, { "gain", -24, 24, 0, unit = "dB" } } },
  delay = { title = "Echo", color = "#2f5b5b", order = 12, about = "repeats: time apart, feedback how many",
    ins = { { "in", "audio", 0 } }, outs = { { "out", "audio" } },
    params = { { "time", 0.01, 1, 0.18, unit = "s" }, { "feedback", 0, 0.95, 0.4 }, { "mix", 0, 1, 0.35 } } },
  reverb = { title = "Reverb", color = "#2f5b5b", order = 13, about = "a room (Freeverb): its size, how dull its walls",
    ins = { { "in", "audio", 0 } }, outs = { { "out", "audio" } },
    params = { { "room", 0, 1, 0.6 }, { "damp", 0, 1, 0.4 }, { "mix", 0, 1, 0.3 } } },
  distort = { title = "Distortion", color = "#83314a", order = 14, about = "overdrive: rounds the peaks off",
    ins = { { "in", "audio", 0 } }, outs = { { "out", "audio" } },
    params = { { "drive", 1, 50, 4, log = true }, { "mix", 0, 1, 1 } } },
  crush = { title = "Bitcrush", color = "#83314a", order = 15, about = "fewer bits, fewer samples: 8-bit grit",
    ins = { { "in", "audio", 0 } }, outs = { { "out", "audio" } },
    params = { { "bits", 1, 16, 6, int = true }, { "rate", 0.02, 1, 0.3 } } },
  sample = { title = "Sample", color = "#3c3c83", order = 17, about = "a sound file: a .wav, an .sfx (sfxr) or another .soundgraph; speed and loop",
    ins = { { "amp", "control", 1 } }, outs = { { "out", "audio" } },
    params = { { "file", file = { "wav", "sfx", "soundgraph" } }, { "level", 0, 2, 1 }, { "speed", 0.25, 4, 1, log = true },
               { "start", 0, 10, 0, unit = "s" }, { "loop", options = { "once", "loop" }, 1 } } },
  stretch = { title = "Paulstretch", color = "#3c3c83", order = 18, about = "a sound file stretched many times slower, smeared into a pad (Paul Nasca's algorithm)",
    ins = {}, outs = { { "out", "audio" } },
    params = { { "file", file = { "wav", "sfx", "soundgraph" } }, { "stretch", 1, 50, 8, log = true },
               { "window", 0.05, 0.75, 0.25, unit = "s", log = true }, { "level", 0, 2, 1 } } },
  chorus = { title = "Chorus", color = "#2f5b5b", order = 19, about = "three copies a little late and wavering: wide, thick",
    ins = { { "in", "audio", 0 } }, outs = { { "out", "audio" } },
    params = { { "rate", 0.05, 5, 0.8, unit = "Hz", log = true }, { "depth", 0.5, 15, 4, unit = "ms" }, { "mix", 0, 1, 0.5 } } },
  flanger = { title = "Flanger", color = "#2f5b5b", order = 20, about = "a very short echo sweeping: a jet passing",
    ins = { { "in", "audio", 0 } }, outs = { { "out", "audio" } },
    params = { { "rate", 0.05, 5, 0.3, unit = "Hz", log = true }, { "depth", 0.2, 8, 2.5, unit = "ms" },
               { "feedback", -0.95, 0.95, 0.6 }, { "mix", 0, 1, 0.5 } } },
  phaser = { title = "Phaser", color = "#2f5b5b", order = 21, about = "all-pass stages sweeping: notches moving through the sound",
    ins = { { "in", "audio", 0 } }, outs = { { "out", "audio" } },
    params = { { "rate", 0.05, 5, 0.5, unit = "Hz", log = true }, { "low", 50, 2000, 300, unit = "Hz", log = true },
               { "high", 500, 10000, 3000, unit = "Hz", log = true }, { "stages", 2, 12, 6, int = true },
               { "feedback", 0, 0.9, 0.5 }, { "mix", 0, 1, 0.5 } } },
  compress = { title = "Compressor", color = "#83314a", order = 22, about = "loud parts turned down (above the threshold, by the ratio): even, punchy",
    ins = { { "in", "audio", 0 } }, outs = { { "out", "audio" } },
    params = { { "threshold", -60, 0, -18, unit = "dB" }, { "ratio", 1, 20, 4, log = true },
               { "attack", 0.0005, 0.2, 0.005, unit = "s", log = true }, { "release", 0.01, 1, 0.15, unit = "s", log = true },
               { "makeup", 0, 24, 6, unit = "dB" } } },
  vocoder = { title = "Vocoder", color = "#83314a", order = 16, about = "the carrier (a buzz) speaks with the modulator's shape (a voice, noise)",
    ins = { { "carrier", "audio", 0 }, { "modulator", "audio", 0 } }, outs = { { "out", "audio" } },
    params = { { "bands", 4, 32, 16, int = true }, { "low", 60, 1000, 120, unit = "Hz", log = true },
               { "high", 1500, 12000, 6000, unit = "Hz", log = true }, { "release", 0.005, 0.3, 0.03, unit = "s", log = true },
               { "gain", 0, 8, 2 } } },
}
M.TYPES = { audio = "#4fa3e0", control = "#e8d44d" }

-- a setting's value: n.data's, kept to its range (an options' index, whole numbers)
function M.param(spec, v)
  if spec.file then return type(v) == "string" and v or "" end   -- (a file's name, beside the .soundgraph / in assets/)
  if spec.options then
    if type(v) == "string" then for i, o in ipairs(spec.options) do if o == v then return i end end end
    v = floor(tonumber(v) or spec[2] or 1)
    return math.max(1, math.min(#spec.options, v))
  end
  v = tonumber(v)
  if v == nil then v = spec[4] end
  if v < spec[2] then v = spec[2] elseif v > spec[3] then v = spec[3] end
  if spec.int then v = floor(v + 0.5) end
  return v
end
function M.default(spec) return spec.file and "" or spec.options and (spec[2] or 1) or spec[4] end
function M.settings(n)                             -- a node's settings, all of them: { name = value }
  local k = M.KINDS[n.kind]
  local p = {}
  for _, s in ipairs(k and k.params or {}) do p[s[1]] = M.param(s, (n.data or {})[s[1]]) end
  return p
end

-- the waves, phase 0..1
local function wave(kind, ph, duty)
  if kind == 1 then return sin(TAU * ph)
  elseif kind == 2 then return ph < duty and 1 or -1
  elseif kind == 3 then return 2 * ph - 1
  else return ph < 0.5 and (4 * ph - 1) or (3 - 4 * ph) end
end

-- RBJ cookbook: a biquad's coefficients (normalized: a0 = 1)
local function biquad(kind, f, q, db)
  f = math.max(10, math.min(M.RATE * 0.49, f))
  local w0 = TAU * f / M.RATE
  local cw, sw = cos(w0), sin(w0)
  local alpha = sw / (2 * math.max(0.05, q))
  local A = 10 ^ (db / 40)
  local b0, b1, b2, a0, a1, a2
  if kind == 1 then b0, b1, b2, a0, a1, a2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2, 1 + alpha, -2 * cw, 1 - alpha
  elseif kind == 2 then b0, b1, b2, a0, a1, a2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2, 1 + alpha, -2 * cw, 1 - alpha
  elseif kind == 3 then b0, b1, b2, a0, a1, a2 = alpha, 0, -alpha, 1 + alpha, -2 * cw, 1 - alpha
  elseif kind == 4 then b0, b1, b2, a0, a1, a2 = 1, -2 * cw, 1, 1 + alpha, -2 * cw, 1 - alpha
  elseif kind == 5 then b0, b1, b2, a0, a1, a2 = 1 + alpha * A, -2 * cw, 1 - alpha * A, 1 + alpha / A, -2 * cw, 1 - alpha / A
  else
    local sa = 2 * sqrt(A) * alpha
    if kind == 6 then
      b0, b1, b2 = A * ((A + 1) - (A - 1) * cw + sa), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - sa)
      a0, a1, a2 = (A + 1) + (A - 1) * cw + sa, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - sa
    else
      b0, b1, b2 = A * ((A + 1) + (A - 1) * cw + sa), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - sa)
      a0, a1, a2 = (A + 1) - (A - 1) * cw + sa, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sa
    end
  end
  return b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
end
M.biquad = biquad

-- each kind's maker: (settings) -> step(inputs, t) -> its output (one, all kinds have one at most)
local MAKE = {}
function MAKE.output(p) return function(i) return i[1] * p.volume end end
function MAKE.osc(p)
  local ph, wv, duty = 0, p.wave, p.duty
  return function(i)
    local f = p.freq * 2 ^ i[1]
    ph = ph + f / M.RATE
    ph = ph - floor(ph)
    return wave(wv, ph, duty) * p.level * i[2]
  end
end
function MAKE.noise(p)
  local seed = floor(p.seed) * 7919 % 2147483646 + 1
  local b0, b1, b2, last = 0, 0, 0, 0
  local col = p.color
  return function(i)
    seed = seed * 16807 % 2147483647               -- (Park-Miller: exact in doubles and integers alike: the same hiss in every Lua)
    local white = seed / 1073741823.5 - 1
    local v = white
    if col == 2 then                               -- pink: Paul Kellet's economy filter
      b0 = 0.99765 * b0 + white * 0.0990460
      b1 = 0.96300 * b1 + white * 0.2965164
      b2 = 0.57000 * b2 + white * 1.0526913
      v = (b0 + b1 + b2 + white * 0.1848) * 0.2
    elseif col == 3 then                           -- brown: integrated, leaking
      last = (last + 0.02 * white) / 1.02
      v = last * 3.5
    end
    return v * p.level * i[1]
  end
end
function MAKE.env(p)
  local a, d, s, h, r = p.attack, p.decay, p.sustain, p.hold, p.release
  local at_release
  local function before(t)                         -- the level while held
    if t < a then return a > 0 and t / a or 1 end
    t = t - a
    if t < d then return 1 + (s - 1) * (d > 0 and t / d or 1) end
    return s
  end
  return function(i, t)
    if t < h then return before(t) end
    at_release = at_release or before(h)
    local u = t - h
    if r <= 0 or u >= r then return 0 end
    return at_release * (1 - u / r)
  end
end
function MAKE.slide(p)
  local from, to, time, c = p.from, p.to, p.time, p.curve
  local k = c >= 0 and (1 + c * 4) or 1 / (1 - c * 4)   -- (curve: -1 fast at first .. 1 slow at first)
  return function(i, t)
    local u = t >= time and 1 or t / time
    return from + (to - from) * u ^ k
  end
end
function MAKE.lfo(p)
  local wv, rate, depth, off = p.wave, p.rate, p.depth, p.offset
  return function(i, t)
    local ph = t * rate
    return off + depth * wave(wv, ph - floor(ph), 0.5)
  end
end
function MAKE.number(p) return function() return p.value end end
function MAKE.gain(p) return function(i) return i[1] * p.gain * i[2] end end
function MAKE.mix(p) return function(i) return i[1] * p.a + i[2] * p.b + i[3] * p.c end end
function MAKE.ring() return function(i) return i[1] * i[2] end end
function MAKE.filter(p)
  local kind, q, db = p.type, p.q, p.gain
  local b0, b1, b2, a1, a2 = biquad(kind, p.cutoff, q, db)
  local last = 0
  local x1, x2, y1, y2 = 0, 0, 0, 0
  return function(i)
    local mod = i[2]
    if mod ~= last then                            -- (cutoff moving: new coefficients)
      last = mod
      b0, b1, b2, a1, a2 = biquad(kind, p.cutoff * 2 ^ mod, q, db)
    end
    local x = i[1]
    local y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
    if y ~= y or abs(y) > 1e6 then y = 0 end       -- (blown up: start again quiet)
    x2, x1, y2, y1 = x1, x, y1, y
    return y
  end
end
function MAKE.delay(p)
  local n = math.max(1, floor(p.time * M.RATE))
  local buf, w = {}, 1
  for k = 1, n do buf[k] = 0 end
  local fb, mix = p.feedback, p.mix
  return function(i)
    local x = i[1]
    local d = buf[w]
    buf[w] = x + d * fb
    w = w % n + 1
    return x * (1 - mix) + d * mix
  end
end
function MAKE.reverb(p)                            -- Freeverb (Jezar at Dreampoint, public domain), mono
  local COMBS, ALLS = { 1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617 }, { 556, 441, 341, 225 }
  local fbk = p.room * 0.28 + 0.7
  local damp = p.damp * 0.4
  local mix = p.mix
  local cb, cw, cs, cl = {}, {}, {}, {}
  for k, len in ipairs(COMBS) do
    local b = {}
    for j = 1, len do b[j] = 0 end
    cb[k], cw[k], cs[k], cl[k] = b, 1, 0, len
  end
  local ab, aw, al = {}, {}, {}
  for k, len in ipairs(ALLS) do
    local b = {}
    for j = 1, len do b[j] = 0 end
    ab[k], aw[k], al[k] = b, 1, len
  end
  return function(i)
    local x = i[1]
    local inp = x * 0.015
    local out = 0
    for k = 1, 8 do
      local b, w = cb[k], cw[k]
      local y = b[w]
      cs[k] = y * (1 - damp) + cs[k] * damp
      b[w] = inp + cs[k] * fbk
      cw[k] = w % cl[k] + 1
      out = out + y
    end
    for k = 1, 4 do
      local b, w = ab[k], aw[k]
      local bo = b[w]
      local y = -out + bo
      b[w] = out + bo * 0.5
      aw[k] = w % al[k] + 1
      out = y
    end
    return x * (1 - mix) + out * 3 * mix
  end
end
function MAKE.distort(p)
  local drive, mix = p.drive, p.mix
  local norm = 1 / tanh(drive)
  return function(i)
    local x = i[1]
    return x * (1 - mix) + tanh(x * drive) * norm * mix
  end
end
function MAKE.crush(p)
  local steps = 2 ^ (p.bits - 1)
  local rate = p.rate
  local acc, held = 1, 0
  return function(i)
    acc = acc + rate
    if acc >= 1 then
      acc = acc - 1
      held = floor(i[1] * steps + 0.5) / steps
    end
    return held
  end
end
function MAKE.vocoder(p)                           -- a channel vocoder: band-pass pairs, the modulator's loudness per band on the carrier's
  local n = p.bands
  local lo, hi = p.low, p.high
  local ratio = (hi / lo) ^ (1 / math.max(1, n - 1))
  local q = sqrt(ratio) / (ratio - 1) * 1.4        -- (a band as wide as the step to the next)
  local rel = exp(-1 / (p.release * M.RATE))
  local att = exp(-1 / (0.002 * M.RATE))
  local bands = {}
  for k = 1, n do
    local f = lo * ratio ^ (k - 1)
    local b0, b1, b2, a1, a2 = biquad(3, f, q, 0)
    bands[k] = { b0, b1, b2, a1, a2, 0, 0, 0, 0, 0, 0, 0, 0, 0 }   -- coefs, carrier x1 x2 y1 y2, modulator x1 x2 y1 y2, env
  end
  local g = p.gain
  return function(i)
    local c, m = i[1], i[2]
    local out = 0
    for k = 1, n do
      local B = bands[k]
      local b0, b1, b2, a1, a2 = B[1], B[2], B[3], B[4], B[5]
      local yc = b0 * c + b1 * B[6] + b2 * B[7] - a1 * B[8] - a2 * B[9]
      B[7], B[6], B[9], B[8] = B[6], c, B[8], yc
      local ym = b0 * m + b1 * B[10] + b2 * B[11] - a1 * B[12] - a2 * B[13]
      B[11], B[10], B[13], B[12] = B[10], m, B[12], ym
      local e = abs(ym)
      local env = B[14]
      if e > env then env = att * env + (1 - att) * e else env = rel * env + (1 - rel) * e end
      B[14] = env
      out = out + yc * env
    end
    return out * g * 8
  end
end

-- files (ctx.load(name) -> samples at RATE, or nil: the Sample and Paulstretch nodes)
local function sample_at(buf, pos)                 -- linear between samples
  local i = floor(pos)
  local a, b = buf[i + 1], buf[i + 2]
  if not a then return 0 end
  return a + ((b or 0) - a) * (pos - i)
end
function MAKE.sample(p, ctx)
  local buf = ctx.load(p.file) or {}
  local n = #buf
  local pos = floor(p.start * M.RATE)
  local speed, level, loop = p.speed, p.level, p.loop == 2
  return function(i)
    if n == 0 then return 0 end
    if pos >= n then if loop then pos = pos % n else return 0 end end
    local v = sample_at(buf, pos)
    pos = pos + speed
    return v * level * i[1]
  end
end

-- an FFT (radix 2, in place: re, im of size n, a power of two; inverse: dir -1)
local function fft(re, im, n, dir)
  local j = 0
  for i = 0, n - 2 do                              -- (bit reversal)
    if i < j then re[i + 1], re[j + 1] = re[j + 1], re[i + 1]; im[i + 1], im[j + 1] = im[j + 1], im[i + 1] end
    local m = n / 2
    while m >= 1 and j >= m do j = j - m; m = m / 2 end
    j = j + m
  end
  local len = 2
  while len <= n do
    local ang = dir * TAU / len
    local wr, wi = cos(ang), sin(ang)
    local half = len / 2
    for st = 0, n - 1, len do
      local cr, ci = 1, 0
      for k = 0, half - 1 do
        local a, b = st + k + 1, st + k + half + 1
        local xr, xi = re[b] * cr - im[b] * ci, re[b] * ci + im[b] * cr
        re[b], im[b] = re[a] - xr, im[a] - xi
        re[a], im[a] = re[a] + xr, im[a] + xi
        cr, ci = cr * wr - ci * wi, cr * wi + ci * wr
      end
    end
    len = len * 2
  end
  if dir < 0 then for i = 1, n do re[i] = re[i] / n; im[i] = im[i] / n end end
end
M.fft = fft
-- Paulstretch (Paul Nasca's algorithm, his public-domain Python version's
-- steps, written here): windows of the sound, each one's phases randomized
-- (its magnitudes kept), overlapped at half a window, the read position moving
-- 1/stretch as fast. -> the stretched samples, up to `want` of them
function M.paulstretch(buf, stretch, window_s, want, pause, seed)
  local n = 2
  while n < window_s * M.RATE do n = n * 2 end
  local half = n / 2
  local win = {}
  for i = 1, n do local x = (i - 1) / (n - 1) * 2 - 1; win[i] = (1 - x * x) ^ 1.25 end
  local out, old = {}, {}
  for i = 1, half do old[i] = 0 end
  local pos, step = 0, half / stretch
  local rnd = (seed or 1) * 7919 % 2147483646 + 1
  local re, im = {}, {}
  local len = #buf
  while #out < want do
    local p0 = floor(pos)
    for i = 1, n do re[i] = (buf[p0 + i] or 0) * win[i]; im[i] = 0 end
    fft(re, im, n, 1)
    for i = 1, n do
      local mag = sqrt(re[i] * re[i] + im[i] * im[i])
      rnd = rnd * 16807 % 2147483647
      local ph = rnd / 2147483647 * TAU
      re[i], im[i] = mag * cos(ph), mag * sin(ph)
    end
    fft(re, im, n, -1)
    for i = 1, half do
      out[#out + 1] = (old[i] + re[i] * win[i]) * 0.9
      old[i] = re[half + i] * win[half + i]
    end
    pos = pos + step
    if pos >= len then break end
    if pause then pause() end
  end
  local peak = 0                                   -- (as loud as the sound was)
  for i = 1, #out do if abs(out[i]) > peak then peak = abs(out[i]) end end
  local p1 = 0
  for i = 1, len do if abs(buf[i]) > p1 then p1 = abs(buf[i]) end end
  if peak > 0 then local k = p1 / peak; for i = 1, #out do out[i] = out[i] * k end end
  return out
end
function MAKE.stretch(p, ctx)
  local buf = ctx.load(p.file) or {}
  local out = #buf > 0 and M.paulstretch(buf, p.stretch, p.window, ctx.length, ctx.pause) or {}
  local x, level = 0, p.level
  return function()
    x = x + 1
    return (out[x] or 0) * level
  end
end
function MAKE.chorus(p)
  local N = floor(0.05 * M.RATE) + 2
  local buf, w = {}, 0
  for k = 1, N do buf[k] = 0 end
  local rate, depth, mix = p.rate, p.depth / 1000 * M.RATE, p.mix
  local base = 0.015 * M.RATE
  return function(i, t)
    local x = i[1]
    buf[w % N + 1] = x
    local wet = 0
    for v = 0, 2 do                                -- (three voices, a third of a turn apart)
      local d = base + depth * (0.5 + 0.5 * sin(TAU * (rate * t + v / 3)))
      local r = w - d
      local i0 = floor(r)
      local f = r - i0
      local a, b = buf[i0 % N + 1], buf[(i0 + 1) % N + 1]
      wet = wet + a + (b - a) * f
    end
    w = w + 1
    return x * (1 - mix) + wet / 3 * mix * 1.2
  end
end
function MAKE.flanger(p)
  local N = floor(0.02 * M.RATE) + 2
  local buf, w = {}, 0
  for k = 1, N do buf[k] = 0 end
  local rate, depth, fb, mix = p.rate, p.depth / 1000 * M.RATE, p.feedback, p.mix
  return function(i, t)
    local x = i[1]
    local d = 1 + depth * (0.5 + 0.5 * sin(TAU * rate * t))
    local r = w - d
    local i0 = floor(r)
    local f = r - i0
    local a, b = buf[i0 % N + 1], buf[(i0 + 1) % N + 1]
    local y = a + (b - a) * f
    buf[w % N + 1] = x + y * fb
    w = w + 1
    return x * (1 - mix) + y * mix
  end
end
function MAKE.phaser(p)
  local n, rate, lo, hi, fb, mix = p.stages, p.rate, p.low, p.high, p.feedback, p.mix
  local x1, y1 = {}, {}
  for k = 1, n do x1[k], y1[k] = 0, 0 end
  local last = 0
  return function(i, t)
    local f = lo * (hi / lo) ^ (0.5 + 0.5 * sin(TAU * rate * t))   -- (swept on a log scale, as ears hear)
    local tn = math.tan(pi * math.min(f, M.RATE * 0.45) / M.RATE)
    local a = (tn - 1) / (tn + 1)
    local v = i[1] + last * fb
    for k = 1, n do                                -- (first-order all-passes)
      local y = a * v + x1[k] - a * y1[k]
      x1[k], y1[k] = v, y
      v = y
    end
    last = v
    return i[1] * (1 - mix) + v * mix
  end
end
function MAKE.compress(p)
  local thr, ratio, makeup = p.threshold, p.ratio, p.makeup
  local att, rel = exp(-1 / (p.attack * M.RATE)), exp(-1 / (p.release * M.RATE))
  local env = 0
  return function(i)
    local x = i[1]
    local e = abs(x)
    if e > env then env = att * env + (1 - att) * e else env = rel * env + (1 - rel) * e end
    local db = env > 1e-6 and 20 * log(env) / log(10) or -120
    local gr = db > thr and (db - thr) * (1 - 1 / ratio) or 0
    return x * 10 ^ ((makeup - gr) / 20)
  end
end

-- the graph's nodes in the order they run (each after what it reads),
-- from the Output back; what doesn't reach it isn't run
local function plan(graph)
  local byid, out = {}, nil
  for _, n in ipairs(graph.nodes or {}) do
    if M.KINDS[n.kind] then byid[n.id] = n end
    if n.kind == "output" and not out then out = n end
  end
  if not out then return nil, "no Output node" end
  local into = {}                                  -- node id -> input name -> { from node, its out }
  for _, l in ipairs(graph.links or {}) do
    if byid[l.from] and byid[l.to] then
      into[l.to] = into[l.to] or {}
      into[l.to][l.input] = l
    end
  end
  local order, state = {}, {}
  local function visit(n)
    if state[n] then return end                    -- (done, or on the way: a loop, read a sample late)
    state[n] = 1
    for _, l in pairs(into[n.id] or {}) do visit(byid[l.from]) end
    state[n] = 2
    order[#order + 1] = n
  end
  visit(out)
  return order, into, byid, out
end

-- a .wav file's bytes -> its samples at RATE, mono (PCM 8 / 16 / 24 / 32 bit or
-- 32-bit float, any channels: mixed; any rate: resampled), or nil and why
function M.decode_wav(b)
  if type(b) ~= "string" or b:sub(1, 4) ~= "RIFF" or b:sub(9, 12) ~= "WAVE" then return nil, "not a .wav" end
  local function u16(i) local x, y = b:byte(i, i + 1); return x + y * 256 end
  local function u32(i) local a, c, d, e = b:byte(i, i + 3); return a + c * 256 + d * 65536 + e * 16777216 end
  local pos, fmt, ch, rate, bits, data, dlen = 13, nil, 1, M.RATE, 16, nil, 0
  while pos + 8 <= #b do
    local id, len = b:sub(pos, pos + 3), u32(pos + 4)
    if id == "fmt " then fmt, ch, rate, bits = u16(pos + 8), u16(pos + 10), u32(pos + 12), u16(pos + 22)
      if fmt == 65534 then fmt = u16(pos + 32) end   -- (WAVE_FORMAT_EXTENSIBLE: its sub-format)
    elseif id == "data" then data, dlen = pos + 8, math.min(len, #b - pos - 7) end
    pos = pos + 8 + len + (len % 2)
  end
  if not (fmt and data) then return nil, "a .wav without its format or data" end
  if not ((fmt == 1 and (bits == 8 or bits == 16 or bits == 24 or bits == 32)) or (fmt == 3 and bits == 32)) then
    return nil, "a .wav kind not read here (PCM or 32-bit float only)"
  end
  local bps = bits / 8
  local frames = floor(dlen / (bps * ch))
  local raw = {}
  local function sample(i)                         -- (one sample at byte i: -1..1)
    if fmt == 3 then
      local a, c, d, e = b:byte(i, i + 3)
      local sign = e >= 128 and -1 or 1
      local ex = (e % 128) * 2 + floor(d / 128)
      local man = (d % 128) * 65536 + c * 256 + a
      if ex == 0 then return 0 end
      return sign * (1 + man / 8388608) * 2 ^ (ex - 127)
    end
    if bits == 8 then return (b:byte(i) - 128) / 128 end
    local v, scale = 0, 2 ^ (bits - 1)
    for k = bps - 1, 0, -1 do v = v * 256 + b:byte(i + k) end
    if v >= scale then v = v - 2 * scale end
    return v / scale
  end
  for f = 0, frames - 1 do
    local sum = 0
    for c = 0, ch - 1 do sum = sum + sample(data + (f * ch + c) * bps) end
    raw[f + 1] = sum / ch
  end
  if rate == M.RATE then return raw end
  local out, k = {}, rate / M.RATE                 -- (linear resampling)
  for x = 1, floor(frames / k) do out[x] = sample_at(raw, (x - 1) * k) end
  return out
end
local here = (debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or ".")
local sfxr_mod
local function sfxr()                              -- (runtime/sfxr.lua: beside this file)
  if sfxr_mod == nil then
    local ok, m = pcall(require, "sfxr")
    if not ok then ok, m = pcall(dofile, here .. "/sfxr.lua") end
    sfxr_mod = ok and m or false
  end
  return sfxr_mod or nil
end
-- a file's samples (ctx: read(name) -> bytes, the depth of graphs in graphs)
local function load_file(name, ctx)
  if name == "" or not ctx.read then return nil end
  ctx.cache = ctx.cache or {}
  if ctx.cache[name] ~= nil then return ctx.cache[name] or nil end
  local bytes = ctx.read(name)
  local ext = (name:match("%.([%w]+)$") or ""):lower()
  local s
  if bytes and ext == "wav" then s = M.decode_wav(bytes)
  elseif bytes and (ext == "sfx" or ext == "soundgraph") then
    local fn = load(bytes, "=" .. name, "t", {})
    local ok, t = false, nil
    if fn then ok, t = pcall(fn) end
    if ok and type(t) == "table" then
      if ext == "sfx" then local S = sfxr(); s = S and S.render(S.check(t))
      elseif (ctx.depth or 0) < 4 then s = M.render(t, ctx.pause, { read = ctx.read, depth = (ctx.depth or 0) + 1 }) end
    end
  end
  ctx.cache[name] = s or false
  return s
end

-- render a graph: its samples (-1..1) and what happened ({ peak, clipped });
-- pause(): called every few thousand samples (the editor renders in a thread);
-- opts.read(name) -> a file's bytes (a Sample / Paulstretch node's: a .wav, an
-- .sfx, another .soundgraph; the editor's: beside the file; a game's: its assets)
function M.render(graph, pause, opts)
  opts = opts or {}
  local order, into, byid, out = plan(graph)
  if not order then return {}, { err = into } end
  local length = floor(math.max(0.01, math.min(M.MAX_LENGTH, M.settings(out).length)) * M.RATE)
  local ctx = { read = opts.read, depth = opts.depth, pause = pause, length = length }
  ctx.load = function(name) return load_file(name, ctx) end
  local nodes, of = {}, {}
  for j, n in ipairs(order) do
    local k = M.KINDS[n.kind]
    local p = M.settings(n)
    local nd = { step = MAKE[n.kind](p, ctx), v = 0, inp = {}, src = {}, def = {}, nin = #k.ins }
    for x, pin in ipairs(k.ins) do nd.def[x] = pin[3] or 0; nd.inp[x] = nd.def[x] end
    nodes[j], of[n] = nd, nd
  end
  for j, n in ipairs(order) do
    local k, nd = M.KINDS[n.kind], nodes[j]
    for x, pin in ipairs(k.ins) do
      local l = into[n.id] and into[n.id][pin[1]]
      if l then nd.src[x] = of[byid[l.from]] or false end
    end
  end
  local N = length
  local s, peak, clipped = {}, 0, 0
  local count = #nodes
  local fade = floor(0.004 * M.RATE)               -- (a few ms faded out at the end: no click)
  for x = 1, N do
    local t = (x - 1) / M.RATE
    local v = 0
    for j = 1, count do
      local nd = nodes[j]
      local inp, src = nd.inp, nd.src
      for q = 1, nd.nin do
        local sn = src[q]
        if sn then inp[q] = sn.v end
      end
      v = nd.step(inp, t)
      if v ~= v then v = 0 end                     -- (NaN: silence)
      nd.v = v
    end
    if v > 0.98 or v < -0.98 then clipped = clipped + 1; v = tanh(v) end
    if x > N - fade then v = v * (N - x) / fade end
    if abs(v) > peak then peak = abs(v) end
    s[x] = v
    if pause and x % 4096 == 0 then pause() end
  end
  return s, { peak = peak, clipped = clipped, nodes = count }
end

function M.pcm16(s)
  local parts, chunk = {}, {}
  local char = string.char
  for i = 1, #s do
    local v = floor(math.max(-1, math.min(1, s[i])) * 32767 + 0.5)
    if v < 0 then v = v + 65536 end
    chunk[#chunk + 1] = char(v % 256, floor(v / 256))
    if #chunk == 4096 then parts[#parts + 1] = table.concat(chunk); chunk = {} end
  end
  parts[#parts + 1] = table.concat(chunk)
  return table.concat(parts)
end
local function u32(n) return string.char(n % 256, floor(n / 256) % 256, floor(n / 65536) % 256, floor(n / 16777216) % 256) end
local function u16(n) return string.char(n % 256, floor(n / 256) % 256) end
function M.wav(s, rate)                            -- a mono 16-bit .wav file, as a string
  rate = rate or M.RATE
  local data = M.pcm16(s)
  return "RIFF" .. u32(36 + #data) .. "WAVE" .. "fmt " .. u32(16) .. u16(1) .. u16(1) .. u32(rate)
      .. u32(rate * 2) .. u16(2) .. u16(16) .. "data" .. u32(#data) .. data
end

return M
