-- soundgraph.lua - runtime/soundgraph.lua: the samples render, the same in
-- every Lua; tones at their pitch, filters keep what they should, envelopes,
-- echoes, a loop that feeds back doesn't hang, settings kept to their range.
--   cd runtime/tests && luajit soundgraph.lua   (or lua5.4)
package.path = "../?.lua;" .. package.path
local SG = require "soundgraph"
local n, fails = 0, 0
local function check(c, m) n = n + 1; if not c then fails = fails + 1; print("  FAIL: " .. m) end end
local R = SG.RATE

local function graph(nodes, links)                 -- nodes: { kind, data } in order (ids 1..), links: { from, out, to, input }
  local g = { nodes = {}, links = {} }
  for i, x in ipairs(nodes) do g.nodes[i] = { id = i, kind = x[1], x = 0, y = 0, data = x[2] } end
  for _, l in ipairs(links) do g.links[#g.links + 1] = { from = l[1], out = l[2], to = l[3], input = l[4] } end
  return g
end
local function rms(s, a, b)
  a, b = math.floor(a or 1), math.floor(b or #s)
  local sum = 0
  for i = a, b do sum = sum + s[i] * s[i] end
  return math.sqrt(sum / (b - a + 1))
end
local function crossings(s, a, b)                  -- upward zero crossings
  local c = 0
  for i = math.floor(a or 1) + 1, math.floor(b or #s) do if s[i - 1] < 0 and s[i] >= 0 then c = c + 1 end end
  return c
end

-- the samples: they render, not silent, not clipped
local function beside(name)                        -- (the samples' files: beside them)
  local f = io.open("../../plugins/soundgraph/samples/" .. name, "rb")
  if not f then return nil end
  local b = f:read("*a"); f:close(); return b
end
for _, f in ipairs({ "laser", "explosion", "bell", "robot", "pad" }) do
  local g = dofile("../../plugins/soundgraph/samples/" .. f .. ".soundgraph")
  local s, info = SG.render(g, nil, { read = beside })
  check(#s > R * 0.2 and info.peak > 0.1 and info.peak <= 1 and info.clipped == 0, f .. ": " .. #s .. " samples, peak " .. info.peak .. ", clipped " .. info.clipped)
end
check(SG.render(dofile("../../plugins/soundgraph/templates/soundgraph.soundgraph"))[1] ~= nil, "the template renders")

-- a sine at 440 Hz: 440 crossings a second
local s = SG.render(graph({ { "osc", { wave = 1, freq = 440, level = 0.9 } }, { "output", { length = 1, volume = 1 } } }, { { 1, "out", 2, "in" } }))
check(#s == R, "an Output's length: " .. #s)
local c = crossings(s)
check(math.abs(c - 440) <= 1, "440 Hz: " .. c .. " crossings")
check(math.abs(rms(s, 1, R - 400) - 0.9 / math.sqrt(2)) < 0.01, "a sine's loudness: " .. rms(s, 1, R - 400))

-- pitch +1 octave (a Value into pitch): 880
s = SG.render(graph({ { "number", { value = 1 } }, { "osc", { wave = 1, freq = 440, level = 1 } }, { "output", { length = 1, volume = 1 } } },
                    { { 1, "out", 2, "pitch" }, { 2, "out", 3, "in" } }))
c = crossings(s)
check(math.abs(c - 880) <= 1, "an octave up: " .. c)

-- a lowpass at 500 Hz keeps 100 Hz, cuts 5000 Hz
local function through(freq, ftype)
  local x = SG.render(graph({ { "osc", { wave = 1, freq = freq, level = 0.9 } }, { "filter", { type = ftype, cutoff = 500, q = 0.707 } }, { "output", { length = 0.5, volume = 1 } } },
                            { { 1, "out", 2, "in" }, { 2, "out", 3, "in" } }))
  return rms(x, R * 0.1, R * 0.45)
end
check(through(100, 1) > 0.6 and through(5000, 1) < 0.01, "lowpass: 100 Hz kept (" .. through(100, 1) .. "), 5 kHz gone (" .. through(5000, 1) .. ")")
check(through(5000, 2) > 0.6 and through(100, 2) < 0.05, "highpass: the other way round")

-- an envelope: nothing after attack + hold + release
s = SG.render(graph({ { "osc", { wave = 2, freq = 200, level = 1 } }, { "env", { attack = 0.01, decay = 0.05, sustain = 0.5, hold = 0.2, release = 0.1 } },
                      { "gain", { gain = 1 } }, { "output", { length = 0.6, volume = 1 } } },
                    { { 1, "out", 3, "in" }, { 2, "out", 3, "amount" }, { 3, "out", 4, "in" } }))
check(rms(s, R * 0.12, R * 0.18) > 0.4 and rms(s, R * 0.12, R * 0.18) < 0.6, "sustain: half")
check(rms(s, R * 0.35, R * 0.55) == 0, "after the release: silence")

-- an echo: a click comes back `time` later
s = SG.render(graph({ { "env", { attack = 0, decay = 0, sustain = 1, hold = 0.01, release = 0 } }, { "number", { value = 0 } },
                      { "osc", { wave = 2, freq = 1000, level = 1 } }, { "gain", { gain = 1 } }, { "delay", { time = 0.2, feedback = 0, mix = 0.5 } },
                      { "output", { length = 0.5, volume = 1 } } },
                    { { 3, "out", 4, "in" }, { 1, "out", 4, "amount" }, { 4, "out", 5, "in" }, { 5, "out", 6, "in" } }))
check(rms(s, R * 0.205, R * 0.208) > 0.3 and rms(s, R * 0.1, R * 0.19) == 0, "an echo 0.2 s later, nothing between")

-- noise: the same every time, and in every Lua (a checksum of the first samples)
local a = SG.render(graph({ { "noise", { color = 2, level = 1, seed = 5 } }, { "output", { length = 0.1, volume = 1 } } }, { { 1, "out", 2, "in" } }))
local b = SG.render(graph({ { "noise", { color = 2, level = 1, seed = 5 } }, { "output", { length = 0.1, volume = 1 } } }, { { 1, "out", 2, "in" } }))
local same, sum = true, 0
for i = 1, #a do if a[i] ~= b[i] then same = false end end
for i = 1, 100 do sum = sum + math.floor(a[i] * 1e6) end
check(same and rms(a) > 0.05, "noise: the same twice")
check(sum == -1298307, "noise: the same in every Lua: " .. sum)

-- a loop (a gain feeding a mix that feeds it) renders, and doesn't hang
s = SG.render(graph({ { "osc", { wave = 1, freq = 300, level = 0.5 } }, { "mix", { a = 1, b = 0.5, c = 0 } }, { "gain", { gain = 0.9 } }, { "output", { length = 0.2, volume = 1 } } },
                    { { 1, "out", 2, "a" }, { 3, "out", 2, "b" }, { 2, "out", 3, "in" }, { 2, "out", 4, "in" } }))
check(#s == math.floor(0.2 * R) and rms(s) > 0.1, "a feedback loop: read a sample late")

-- no Output: says so; settings kept to their range, lists by name too
local e, info = SG.render(graph({ { "osc", {} } }, {}))
check(#e == 0 and info.err == "no Output node", "no Output: " .. tostring(info.err))
local spec = SG.KINDS.osc.params[2]
check(SG.param(spec, 1e9) == 8000 and SG.param(spec, nil) == 440, "freq kept to 20..8000, default 440")
check(SG.param(SG.KINDS.filter.params[1], "highpass") == 2 and SG.param(SG.KINDS.osc.params[1], 9) == 4, "lists: by name, kept in range")
check(SG.wav(s):sub(1, 4) == "RIFF" and #SG.pcm16(s) == 2 * #s, "wav, pcm16")

-- files: a .wav read back the same; a Sample node plays it (faster: an octave up); an .sfx; a graph in a graph
local tone = SG.render(graph({ { "osc", { wave = 1, freq = 300, level = 0.8 } }, { "output", { length = 0.5, volume = 1 } } }, { { 1, "out", 2, "in" } }))
local back = SG.decode_wav(SG.wav(tone))
local worst = 0
for i = 1, #tone do worst = math.max(worst, math.abs(back[i] - tone[i])) end
check(#back == #tone and worst < 1 / 16000, "a .wav read back: " .. #back .. " samples, off by " .. worst)
local files = { ["tone.wav"] = SG.wav(tone), ["inner.soundgraph"] = "return " .. "{ nodes = { { id = 1, kind = 'osc', data = { wave = 1, freq = 500, level = 0.5 } }, { id = 2, kind = 'output', data = { length = 0.3, volume = 1 } } }, links = { { from = 1, out = 'out', to = 2, input = 'in' } } }" }
do local f = io.open("../../plugins/sfxr/samples/coin.sfx", "rb"); files["coin.sfx"] = f:read("*a"); f:close() end
local function read(name) return files[name] end
local function one(kind, data, len)
  return SG.render(graph({ { kind, data }, { "output", { length = len or 0.5, volume = 1 } } }, { { 1, "out", 2, "in" } }), nil, { read = read })
end
local played = one("sample", { file = "tone.wav", level = 1, speed = 1 })
check(math.abs(crossings(played, 1, R * 0.45) - 135) <= 2, "a Sample: the file's tone: " .. crossings(played, 1, R * 0.45))
local fast = one("sample", { file = "tone.wav", level = 1, speed = 2 })
check(math.abs(crossings(fast, 1, R * 0.2) - 120) <= 2 and rms(fast, R * 0.3, R * 0.45) == 0, "speed 2: an octave up, over in half the time")
check(rms(one("sample", { file = "coin.sfx", level = 1 }), 1, R * 0.1) > 0.05, "an .sfx as a sample (sfxr)")
check(math.abs(crossings(one("sample", { file = "inner.soundgraph", level = 1 }), 1, R * 0.25) - 125) <= 2, "a graph in a graph")
check(rms((one("sample", { file = "missing.wav", level = 1 }))) == 0, "no such file: silence")
-- an FFT and back; Paulstretch: longer, not silent
local re, im = {}, {}
for i = 1, 64 do re[i] = math.sin(i * 0.3) + (i % 5) * 0.1; im[i] = 0 end
local keep = {}
for i = 1, 64 do keep[i] = re[i] end
SG.fft(re, im, 64, 1); SG.fft(re, im, 64, -1)
local off = 0
for i = 1, 64 do off = math.max(off, math.abs(re[i] - keep[i])) end
check(off < 1e-9, "fft and back: " .. off)
local st = one("stretch", { file = "tone.wav", stretch = 4, window = 0.1, level = 1 }, 2)
check(#st == 2 * R and rms(st, R * 0.5, R * 1.5) > 0.1, "Paulstretch: the tone, 4 times as long")
-- effects: they sound, nothing blows up; the compressor turns a loud tone down
local function through2(kind, data)
  return SG.render(graph({ { "osc", { wave = 3, freq = 220, level = 0.9 } }, { kind, data }, { "output", { length = 0.5, volume = 1 } } },
                         { { 1, "out", 2, "in" }, { 2, "out", 3, "in" } }))
end
for _, k in ipairs({ "chorus", "flanger", "phaser", "compress" }) do
  local x = (through2(k, {}))
  local ok = rms(x) > 0.05
  for i = 1, #x do if x[i] ~= x[i] then ok = false end end
  check(ok, k .. ": sounds")
end
local loud = through2("compress", { threshold = -30, ratio = 10, makeup = 0 })
check(rms(loud, R * 0.1, R * 0.4) < rms(through2("gain", { gain = 1 }), R * 0.1, R * 0.4) * 0.5, "the compressor turns it down")

print(string.format("soundgraph: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
