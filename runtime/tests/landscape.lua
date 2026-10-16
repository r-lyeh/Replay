-- landscape.lua - runtime/landscape.lua on its own (any Lua): the generator (the same seed, the same hills; flat
-- is flat), heights between points, the ray onto it, the brushes, the edits packed and read back, another grid
-- size keeping them; and a checksum of the heights (LuaJIT and Lua 5.4 must agree: run.lua compares them).
--   luajit runtime/tests/landscape.lua
package.path = "runtime/?.lua;" .. package.path
local L = require("landscape")
local ok_n, fail_n = 0, 0
local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
local s = L.check({ w = 40, d = 20, cells = 40, base = { kind = "hills", seed = 3, height = 6, scale = 12, octaves = 4, ridges = 0.3 } })
local A, B = L.build(s), L.build(L.check(s))
check(A.nx == 41 and A.nz == 21 and #A.h == 41 * 21, "40 x 20 m, 40 cells: 41 x 21 points")
local same, top = true, 0
for k = 1, #A.h do if A.h[k] ~= B.h[k] then same = false end; top = math.max(top, A.h[k]) end
check(same and top > 1 and top <= 6, "the same seed, the same hills, up to its height: " .. top)
local F = L.build(L.check({ base = { kind = "flat" } }))
check(F.top == 0 and L.height_at(F, 3, -7) == 0, "flat: flat")
local x0, z0 = L.pos(A, 11, 6)
check(math.abs(L.height_at(A, x0, z0) - A.h[5 * 41 + 11]) < 1e-9, "a point's height: its own")
local mid = L.height_at(A, x0 + 0.5, z0)
local a, b = A.h[5 * 41 + 11], A.h[5 * 41 + 12]
check(math.abs(mid - (a + b) / 2) < 1e-9, "half way between two points: the mean")
local t, hx, hy, hz = A:ray(0, 30, 25, 0, -1, -1.2)
check(t and math.abs(hy - A:height_at(hx, hz)) < 1e-3, "a ray from above meets it, on it")
check(L.ray(A, 0, 30, 25, 0, 1, 0) == nil and L.ray(A, 100, 30, 0, 0, -1, 0) == nil, "up, or past its edge: no hit")
local h0 = A:height_at(0, 0)
L.brush(A, s, "sculpt", 0, 0, 3, 1)
check(A:height_at(0, 0) > h0 and A.ver > B.ver, "sculpt: up, its version up")
L.brush(A, s, "flatten", 8, 4, 3, 1, { target = 1 }); L.brush(A, s, "flatten", 8, 4, 3, 1, { target = 1 })
check(math.abs(A:height_at(8, 4) - 1) < 1e-6, "flatten: to 1 m")
L.pack(A, s)
local C = L.build(s)
check(math.abs(C:height_at(0, 0) - A:height_at(0, 0)) < 0.006 and math.abs(C:height_at(8, 4) - 1) < 0.006, "packed (cm) and read back")
local s2 = L.copy(s); s2.cells = 80
local D = L.rebuild(s2, A)
check(D.nx == 81 and math.abs((D:height_at(8, 4) - L.base_at(s2.base, 8, 4)) - (A:height_at(8, 4) - L.base_at(s.base, 8, 4))) < 0.05, "80 cells: the edits kept")
for _ = 1, 40 do L.brush(A, s, "erase", 0, 0, 12, 1) end
check(math.abs(A:height_at(0, 0) - h0) < 1e-6 and math.abs(A:height_at(8, 4) - L.base_at(s.base, 8, 4)) < 1e-6, "erase: back to the generator's")
local sum = 0
for k = 1, #B.h do sum = (sum + math.floor(B.h[k] * 1e6 + 0.5) * k) % 1000000007 end
print("landscape checksum " .. string.format("%d", sum))
print(string.format("landscape: %d checks ok, %d failed", ok_n, fail_n))
