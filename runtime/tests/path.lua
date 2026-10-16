-- path.lua - pathfinding (runtime/path.lua): A* 4 / 8 ways, corners, costs,
-- jump point search (the same lengths as A*, less work), smoothing, flow
-- fields, any graph, a tilemap's layer, w:path.   cd runtime/tests && luajit path.lua
package.path = "../?.lua;" .. package.path
local ecs = require "ecs"
local path = require "path"
local n, fails = 0, 0
local function check(c, m) n = n + 1; if not c then fails = fails + 1; print("  FAIL: " .. m) end end

local MAZE = {
  "..........",
  ".####.###.",
  ".#......#.",
  ".#.##.#.#.",
  "...#..#...",
  "####..####",
  "..........",
}
local function grid_of(rows)
  return path.grid(#rows[1], #rows, function(x, y) return rows[y + 1]:sub(x + 1, x + 1) == "#" end)
end
local g = grid_of(MAZE)
local cells, info = path.find(g, 0, 0, 9, 6)
check(cells and cells[1][1] == 0 and cells[#cells][1] == 9 and cells[#cells][2] == 6, "found, start to end")
local ok = true
for i = 2, #(cells or {}) do
  local a, b = cells[i - 1], cells[i]
  if math.abs(a[1] - b[1]) > 1 or math.abs(a[2] - b[2]) > 1 or g.blocked(b[1], b[2]) then ok = false end
end
check(ok, "every step to a free neighbour")
local c4 = path.find(g, 0, 0, 9, 6, { diagonal = false })
check(c4 and #c4 >= #cells, "4 ways: no shorter")
local corner = path.grid(2, 2, function(x, y) return (x == 1 and y == 0) end)
local cc = path.find(corner, 0, 0, 1, 1)
check(cc and #cc == 3, "no cutting a corner: round it (" .. (cc and #cc or 0) .. " cells)")
check(path.find(g, 0, 0, 1, 1) == nil, "into a wall: nil")
local closed_in = grid_of({ ".#.", "##.", "..." })
check(path.find(closed_in, 0, 0, 2, 2) == nil, "no way: nil")

-- costs: a swamp it goes round
local sw = path.grid(5, 3, nil, function(x, y) return (y == 1 and x >= 1 and x <= 3) and 10 or 1 end)
local cs = path.find(sw, 0, 1, 4, 1)
local through = false
for _, c in ipairs(cs) do if c[2] == 1 and c[1] >= 1 and c[1] <= 3 then through = true end end
check(not through, "dear cells: round them")

-- jump point search: the same cost, fewer cells looked at
local big, seed = {}, 12345
local function rnd() seed = (seed * 16807) % 2147483647; return seed / 2147483647 end   -- (exact in doubles and integers)
for y = 0, 59 do
  local r = {}
  for x = 0, 59 do r[#r + 1] = (rnd() < 0.22 and not (x < 2 and y < 2) and not (x > 57 and y > 57)) and "#" or "." end
  big[#big + 1] = table.concat(r)
end
local G = grid_of(big)
local a1, i1 = path.find(G, 0, 0, 59, 59)
local a2, i2 = path.find(G, 0, 0, 59, 59, { jps = true })
check(a1 and a2 and math.abs(i1.cost - i2.cost) < 1e-6, "JPS: the same cost as A* (" .. tostring(i1 and i1.cost) .. " / " .. tostring(i2 and i2.cost) .. ")")
check(i2.visited < i1.visited, "JPS looked at fewer: " .. i2.visited .. " < " .. i1.visited)
local steps_ok = true
for i = 2, #(a2 or {}) do if math.abs(a2[i][1] - a2[i - 1][1]) > 1 or math.abs(a2[i][2] - a2[i - 1][2]) > 1 or G.blocked(a2[i][1], a2[i][2]) then steps_ok = false end end
check(steps_ok, "JPS: filled in, a cell a step")
local same = true
for _, p in ipairs({ { 3, 2, 50, 40 }, { 58, 1, 2, 57 }, { 10, 30, 47, 8 } }) do
  local _, x1 = path.find(G, p[1], p[2], p[3], p[4])
  local _, x2 = path.find(G, p[1], p[2], p[3], p[4], { jps = true })
  if (x1.cost == nil) ~= (x2.cost == nil) or (x1.cost and math.abs(x1.cost - x2.cost) > 1e-6) then same = false end
end
check(same, "JPS = A* on more trips")

-- smoothing
local open = path.grid(20, 20, function() return false end)
local s = path.smooth(open, path.find(open, 0, 0, 19, 7))
check(#s == 2, "smooth on open ground: a straight line")
local sm = path.smooth(g, cells)
check(#sm < #cells and sm[1][1] == 0 and sm[#sm][1] == 9, "smooth in the maze: fewer points, the same ends")
check(not path.sees(g, 0, 0, 9, 6) and path.sees(open, 0, 0, 19, 7), "line of sight")

-- a flow field
local f = path.flow(g, 9, 6)
local x, y, steps = 0, 0, 0
while (x ~= 9 or y ~= 6) and steps < 100 do
  local dx, dy = f:dir(x, y)
  if dx == 0 and dy == 0 then break end
  x, y, steps = x + dx, y + dy, steps + 1
end
check(x == 9 and y == 6, "the flow field leads there (" .. steps .. " steps)")
check(f:distance(9, 6) == 0 and f:distance(0, 0) > 0, "its distances")

-- any graph
local edges = { a = { { "b", 1 }, { "c", 5 } }, b = { { "c", 1 }, { "d", 7 } }, c = { { "d", 1 } }, d = {} }
local route, cost = path.search("a", "d", function(k) return edges[k] end)
check(route and table.concat(route, "") == "abcd" and cost == 3, "a graph: a b c d, 3")

-- a tilemap's layer, w:path
local map = { w = 4, h = 3, tile = 16, layers = { { name = "ground", rows = { "........", "..0001..", "........" } } } }
local mg = path.from_map(map, { layer = "ground" })
check(mg.blocked(1, 1) and mg.blocked(2, 1) and not mg.blocked(0, 1), "a map: its tiles are walls")
local mg2 = path.from_map(map, { solid = { 1 } })
check(not mg2.blocked(1, 1) and mg2.blocked(2, 1), "solid = { tiles }")
local w = ecs.world()
local pts = w:path({ x = 8, y = 24 }, { x = 56, y = 24 }, { map = map, layer = "ground" })
check(pts and #pts >= 2 and pts[1].x == 8 and pts[#pts].x == 56, "w:path: world points, cell centres")
check(ecs.code_globals.path == path, "the global path in systems")

print(string.format("path: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
