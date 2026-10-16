-- ties_order.lua - wires tied through two ties in a row (plugins/canvas/ties.lua)
-- keep their order between them, wherever the ties are moved: no crossing in
-- the bundle (they cross, if they must, where they fan out).
--   cd runtime/tests && luajit ties_order.lua   (or lua5.4)
package.preload["core.style"] = function() return {} end
package.preload["plugins.canvas.draw"] = function() return {} end
package.preload["plugins.canvas.theme"] = function() return { rgb = function() return {} end, alpha = function() end, C = {} } end
local TI = dofile("../../editor/3rd/lite/data/plugins/canvas/ties.lua")
local n, fails = 0, 0
local function check(c, m) n = n + 1; if not c then fails = fails + 1; print("  FAIL: " .. m) end end
local bad, tried = 0, 0
for _, ends in ipairs({ { 0, 30 }, { 30, 0 }, { -40, 80 }, { 200, -100 } }) do
  for x2 = 300, 900, 150 do
    for dy = -20, 20 do
      local A, B = {}, {}
      local cen = { [A] = { 200, 50 }, [B] = { 320, 50 + dy } }
      local wires = { { 0, 40, x2, 40 + ends[1], via = { A, B } }, { 0, 60, x2 + 100, 60 + ends[2], via = { A, B } } }
      local info = TI.route(wires, function(t) return cen[t][1], cen[t][2] end, 1)
      local s1, s2 = info.segs[wires[1]][3], info.segs[wires[2]][3]   -- (the stretch from A to B)
      local a0 = select(2, TI.at(s1, 0.02)) - select(2, TI.at(s2, 0.02))
      local a1 = select(2, TI.at(s1, 0.98)) - select(2, TI.at(s2, 0.98))
      tried = tried + 1
      if a0 * a1 < 0 then bad = bad + 1 end
    end
  end
end
check(bad == 0, "a bundle between two ties crossed itself " .. bad .. " times in " .. tried)
-- three wires, three ties in a row
local A, B, C = {}, {}, {}
local cen = { [A] = { 100, 0 }, [B] = { 200, 12 }, [C] = { 300, -9 } }
local wires = { { 0, -30, 500, 90, via = { A, B, C } }, { 0, 0, 450, -60, via = { A, B, C } }, { 0, 40, 520, 10, via = { A, B, C } } }
local info = TI.route(wires, function(t) return cen[t][1], cen[t][2] end, 1)
local ok = true
for k = 3, 5, 2 do                                 -- (A -> B, B -> C)
  local ys0, ys1 = {}, {}
  for i, w in ipairs(wires) do local s = info.segs[w][k]; ys0[i] = select(2, TI.at(s, 0.02)); ys1[i] = select(2, TI.at(s, 0.98)) end
  for i = 1, 3 do for j = i + 1, 3 do if (ys0[i] - ys0[j]) * (ys1[i] - ys1[j]) < 0 then ok = false end end end
end
check(ok, "three ties in a row: no crossing between them")
-- two ties on a slope (one moved a few pixels down): a long wire from far
-- away, level with them, stays on the side it comes from (above the one
-- coming up from below), at both ties
do
  local A, B = {}, {}
  local cen = { [A] = { 110, 80 }, [B] = { 300, 80 } }
  local ok, tried = true, 0
  for dy = -40, 40, 5 do
    cen[B][2] = 80 + dy
    local L = { -1500, 60 + dy * 0.2, 1900, 100 + dy, via = { A, B } }   -- (far: left and right, along them)
    local F = { 20, 230, 420, 230, via = { A, B } }                     -- (from below, back down)
    local info = TI.route({ L, F }, function(t) return cen[t][1], cen[t][2] end, 1)
    local s = info.segs
    for _, k in ipairs({ 2, 4 }) do                -- (through A, through B)
      local _, ly = TI.at(s[L][k], 0.5)
      local _, fy = TI.at(s[F][k], 0.5)
      tried = tried + 1
      if ly >= fy then ok = false end
    end
  end
  check(ok, "tilted ties: the far wire stays above the one from below (" .. tried .. " tried)")
end
-- a line started a few pixels inside a wire (pressed on it) and drawn away: that wire counts
SCALE = SCALE or 1
local wa = { item = "a", segs = { { 0, 100, 100, 100, 200, 100, 300, 100 } } }   -- (a straight wire at y 100)
local wb = { item = "b", segs = { { 0, 140, 100, 140, 200, 140, 300, 140 } } }
local h = TI.hits({ wa, wb }, 150, 103, 150, 160)   -- (from 3 px below a, down across b)
check(#h == 2 and h[1].item == "a", "the wire pressed on is tied too: " .. #h)
print(string.format("ties order: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
