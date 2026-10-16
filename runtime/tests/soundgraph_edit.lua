-- soundgraph_edit.lua - a .soundgraph in its tab (plugins/soundgraph): it renders,
-- a setting's slider dragged, a list clicked, double-click: its default,
-- undo / redo, a node added and wired, saved, a .wav exported.
--   replay games/pong.lua --stopped --lite "dofile('runtime/tests/soundgraph_edit.lua')@3" --frames 100000 --shot x.bmp
-- Prints a line per failed check, then the count; NG_EXIT exits.
local core = require "core"
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local function done()
    print(string.format("soundgraph edit: %d checks ok, %d failed", ok_n, fail_n))
    if os.getenv("NG_EXIT") then os.exit(0) end
  end
  local path = "soundgraph_edit_test.soundgraph"
  do
    local f = io.open("plugins/soundgraph/samples/laser.soundgraph", "rb"); local s = f:read("*a"); f:close()
    f = io.open(path, "wb"); f:write(s); f:close()
  end
  local v = require("plugins.openwith").open("soundgraph", path)
  local function settle()
    local t0 = system.get_time()
    repeat coroutine.yield(0.05) until (v.samples and not v.rendering) or system.get_time() - t0 > 10
  end
  settle()
  check(v and v.graph and #v.graph.nodes == 6, "the graph is open")
  if not (v and v.graph) then return done() end
  v.play = function(self) self.plays = (self.plays or 0) + 1 end   -- (no sound in a test: counted)
  check(v.samples and #v.samples == math.floor(0.35 * 44100), "rendered: " .. tostring(v.samples and #v.samples))
  local function node(kind) for _, n in ipairs(v.graph.nodes) do if n.kind == kind then return n end end end

  -- a slider: the oscillator's freq, dragged right
  local osc = node("osc")
  local x, y, w, h = v:node_rect(osc)
  local top = y + h - (v:node_extra(osc) + 3)
  local fy = top + 2 + 18 * 1 + 9                  -- (its 2nd row: freq)
  local n, spec = v:param_at(x + w / 2, fy)
  check(n == osc and spec and spec[1] == "freq", "the freq row under the mouse: " .. tostring(spec and spec[1]))
  local f0 = osc.data.freq
  v:on_canvas_pressed("left", x + w / 2, fy, 1)
  v:on_canvas_moved(x + w / 2 + 30, fy)
  v:on_canvas_released("left", x + w / 2 + 30, fy)
  check(osc.data.freq > f0, "dragged right: higher (" .. f0 .. " -> " .. osc.data.freq .. ")")
  settle()
  check(v.plays == 1, "let go: it rendered and played: " .. tostring(v.plays))
  -- a list: the wave, clicked
  local wy = top + 2 + 9
  local w0 = osc.data.wave
  v:on_canvas_pressed("left", x + w / 2, wy, 1); v:on_canvas_released("left", x + w / 2, wy)
  check(osc.data.wave == w0 % 4 + 1, "a click: the next wave (" .. w0 .. " -> " .. osc.data.wave .. ")")
  -- double-click: the default
  v:on_canvas_pressed("left", x + w / 2, fy, 2); v:on_canvas_released("left", x + w / 2, fy)
  check(osc.data.freq == 440, "double-click: its default: " .. osc.data.freq)
  settle()
  -- undo / redo
  v:undo()
  check(osc ~= node("osc") and node("osc").data.freq > f0, "undo: the dragged value back")
  v:undo()
  v:undo()
  check(node("osc").data.freq == f0 and node("osc").data.wave == w0, "undo to the start")
  v:redo()
  check(node("osc").data.freq > f0, "redo")
  settle()
  -- a node added and wired: a reverb between the gain and the output
  local gain, out = node("gain"), node("output")
  local rv = v:add_node("reverb", gain.x + 100, gain.y + 120)
  check(rv and rv.data and rv.data.room == 0.6, "a reverb, its settings written")
  v:connect(gain.id, "out", rv.id, "in")
  v:connect(rv.id, "out", out.id, "in")
  settle()
  check(#v.samples == math.floor(0.35 * 44100) and v.info and v.info.peak > 0.1, "rendered with the reverb")
  -- save, export
  v:save()
  local f = io.open(path, "rb"); local text = f:read("*a"); f:close()
  local g = load(text, "=sfg", "t", {})()
  check(g and #g.nodes == 7 and #g.links == 6, "saved: 7 nodes, 6 wires")
  v:export_wav()
  local wf = io.open("soundgraph_edit_test.wav", "rb")
  local wav = wf and wf:read("*a")
  if wf then wf:close() end
  check(wav and wav:sub(1, 4) == "RIFF" and #wav > 44 + 2 * 10000, "exported a .wav")
  -- a Sample node: its file setting picks one beside it (a click), and it plays
  local SG = dofile("runtime/soundgraph.lua")
  local tone = SG.render({ nodes = { { id = 1, kind = "osc", data = { wave = 1, freq = 330, level = 0.8 } }, { id = 2, kind = "output", data = { length = 0.3 } } },
                           links = { { from = 1, out = "out", to = 2, input = "in" } } })
  local tf = io.open("soundgraph_edit_tone.wav", "wb"); tf:write(SG.wav(tone)); tf:close()
  local sm = v:add_node("sample", out.x - 200, out.y + 200)
  v:connect(sm.id, "out", out.id, "in")
  local sx, sy, sw, sh = v:node_rect(sm)
  local stop = sy + sh - (v:node_extra(sm) + 3)
  v:on_canvas_pressed("left", sx + sw / 2, stop + 2 + 9, 1); v:on_canvas_released("left", sx + sw / 2, stop + 2 + 9)
  check(sm.data.file:match("%.wav$") or sm.data.file:match("%.soundgraph$") or sm.data.file:match("%.sfx$"), "a click: a file beside it: " .. tostring(sm.data.file))
  local guard = 0                                  -- (the tone: the one picked)
  while sm.data.file ~= "soundgraph_edit_tone.wav" and guard < 50 do
    v:on_canvas_pressed("left", sx + sw / 2, stop + 2 + 9, 1); v:on_canvas_released("left", sx + sw / 2, stop + 2 + 9)
    guard = guard + 1
  end
  check(sm.data.file == "soundgraph_edit_tone.wav", "clicked through to the tone")
  settle()
  check(v.samples and v.info and v.info.peak > 0.3, "the sample plays: peak " .. tostring(v.info and v.info.peak))
  os.remove("soundgraph_edit_tone.wav")
  os.remove(path); os.remove("soundgraph_edit_test.wav")
  done()
end)
