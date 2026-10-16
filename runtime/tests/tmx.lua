-- tmx.lua - Tiled's maps into a .tmap (plugins/tilemap/tmx.lua): CSV, base64,
-- zlib and gzip data (inflated here: fixed and dynamic codes), an external
-- tileset, two tilesets (the second's tiles dropped), flips, objects as
-- areas and paths with their properties, an infinite map's chunks; and the
-- areas / splines a game reads (runtime/tmap.lua).
--   cd runtime/tests && luajit tmx.lua   (or lua5.4)
package.path = "../?.lua;../../plugins/tilemap/?.lua;" .. package.path
local Tmx = dofile("../../plugins/tilemap/tmx.lua")
local Map = dofile("../../plugins/tilemap/map.lua")
local tmap = require "tmap"
local n, fails = 0, 0
local function check(c, m) n = n + 1; if not c then fails = fails + 1; print("  FAIL: " .. m) end end
local FX = { z = "eJx1y8EJwCAQAMG5iB9NtBHt0dLFr5CFeS4EHiRkFhRUvPjQ0DGCeYar+LEBTQYBOA==", gz = "H4sIAFCX42oC/2NgYGBgBGImIGYGYlYGhgYgxcAFxNxAzAPEvEDMB8T8QKwDVKwL0oAGGHFgADxp2wFgAAAA", b = "AAAAAAEAAAACAAAAAwAAAAUAAIAAAAAACgAAAAsAAAAMAAAADQAAAA4AAAAPAAAALAEAAC0BAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA", csv = "0,1,2,3,2147483653,0,10,11,12,13,14,15,300,301,0,0,0,0,1,1,1,1,1,1", big = "eNp1mAGu7CAIRQF1L+r+F/jm52tycmInadraVgQul+u0iNi/o37H+B3rd2T8//277ud5O8c69/tcz/NtO+d9xuLMU+e643y/u8eC/Wu7zng730ycr42B63bur43C88Q8/dznmf/6e21Prfmu8a4rZJvxoZ/Xxj73DT502Bg4SjHZ8Ddhbz7iwrUMrTPk183ztXtzwh/HO9bH84A/U7ljXDryU3g3MU8DDlJj9/s7/9Z8HfmjDcbl+juV1xCG4xF7jzPOd10dOAutc2JsoS42fAvUFetnKJ4L+WmwvzFvE8YW5ux4bnsLeAl8nzgvXJMHhmp4IMYdWGl4xjiExojTrVwZw6yZQFw28jKRC9ce31vwbcKXLV4s5XYD07bh+JGHmHfncuP5QG002F+KsXkxheOJ+tjw5Y6XuJHvFHJYqoEtPmofnN+Ak4Y8FnLIPsOaIU6JfXIMsV/qB/HBQYka7g98hfBCvKXywLik8JfikMS744GNAWzwW/e5evTvVF+fsFvIb0fOWY/ssSmeD3ELeWwrTgvrH+K/rvizpojHibk3xpu4JaQthvh/q9c11CX7zxbGtjh6ISaFeKaw0h65c89nXYd6XyIeDXhM8WVT/ZjD2EcD71B7LWBqiHsH5gnFvfBeUx8lzxTGUhgsaSvyekg/xQfXp/jDvSjhH3XNEn85P451PM4lrgrVAnO3pMmonbq4iRqEnF4aL9VbQ2wH5t2KXamOU/gL4WVg7cRmwk6KF9vD1ouz94e/1oWOf3to+glMLMUmH/0olb/+oU1T9ZDaGw3Vvm1Ss3o/NR/fTdVlKA4lHRePuujSf0P7qpIucV8rPbO+XtoTNu0L4rHXaFgv64d1VKr9Jb1mHRZaY4h7O2xbM4W0ZYlTicdSLkJxdzzm49tSr028t7Re7sG5/9riQnP8kP8lbcG6ZV9bD36fiiv3LOOhL0IYofZ57VnIzfnAVn/gvMQNpV48tY740LAF/0s6OaVFuMaSjinppSa9ueD3kI4Y2tdt1f+Wdim9w1rmfx/0M7TXTfHJ/NgLeX/XHtrAR9f/HClu8H8X1CBDudjac05h7Q+JG0jd", bigsum = 18652, W = 6, H = 4 }

local function tmx(data_attr, data_text, extra)
  return '<?xml version="1.0" encoding="UTF-8"?>\n<map version="1.10" orientation="orthogonal" width="6" height="4" tilewidth="16" tileheight="16" infinite="0">\n'
    .. ' <tileset firstgid="1" name="t" tilewidth="16" tileheight="16" tilecount="256" columns="16"><image source="art/tiles.png" width="256" height="256"/></tileset>\n'
    .. ' <tileset firstgid="300" source="more.tsx"/>\n'
    .. ' <layer id="1" name="ground" width="6" height="4"><data ' .. data_attr .. '>' .. data_text .. '</data></layer>\n'
    .. (extra or '') .. '</map>\n'
end
local function read(p) if p == "more.tsx" then return '<tileset name="more" tilewidth="16" tileheight="16"><image source="more.png"/></tileset>' end end
local want = { "..", "00", "01", "02", "04", "..", "09", "0a", "0b", "0c", "0d", "0e", "..", "..", "..", "..", "..", "..", "00", "00", "00", "00", "00", "00" }
local function same(d, label)
  local r = table.concat(d.layers[1].rows)
  check(r == table.concat(want), label .. ": the cells: " .. r)
end
for _, case in ipairs({ { 'encoding="csv"', FX.csv, "csv" }, { 'encoding="base64"', FX.b, "base64" },
                        { 'encoding="base64" compression="zlib"', FX.z, "zlib" }, { 'encoding="base64" compression="gzip"', FX.gz, "gzip" } }) do
  local d, notes = Tmx.import(tmx(case[1], case[2]), read)
  check(d and d.w == 6 and d.h == 4 and d.tile == 16 and d.tileset == "art/tiles.png", case[3] .. ": the map")
  if d then same(d, case[3]) end
  local all = table.concat(notes, " | ")
  check(all:find("2 cells of other tilesets dropped", 1, true) and all:find("1 flipped", 1, true), case[3] .. ": the notes: " .. all)
end
-- a bigger layer: zlib with dynamic codes; more than 256 tiles: 4 digits
do
  local t = '<map orientation="orthogonal" width="40" height="30" tilewidth="8" tileheight="8"><tileset firstgid="1"><image source="s.png"/></tileset>'
         .. '<layer name="a" width="40" height="30"><data encoding="base64" compression="zlib">' .. FX.big .. '</data></layer></map>'
  local d = Tmx.import(t)
  local sum, cells = 0, 0
  local m = Map.from_data(d)
  for _, c in ipairs(m.layers[1].cells) do if c then sum = sum + c + 1; cells = cells + 1 end end
  check(d.tile == 8 and m.w == 40 and sum == FX.bigsum, "dynamic codes: the cells add up: " .. sum .. " / " .. FX.bigsum)
  local t2 = '<map width="2" height="1" tilewidth="16" tileheight="16"><tileset firstgid="1"><image source="big.png"/></tileset><layer name="a"><data encoding="csv">1,700</data></layer></map>'
  local d2 = Tmx.import(t2)
  check(d2.digits == 4 and d2.layers[1].rows[1] == "000002bb", "4 digits a cell past 255: " .. tostring(d2.layers[1].rows[1]))
  local m2 = Map.from_data(d2)
  check(m2.layers[1].cells[2] == 699 and Map.to_data(m2).digits == 4, "4 digits: read and written back")
  check(tmap.cell(d2, "a", 1, 0) == 699 and tmap.cell(d2, 1, 0, 0) == 0, "tmap.cell: 4 digits")
end
-- objects: a rectangle, a polygon, a polyline, a point, an ellipse, a tile object; properties
do
  local objs = [[<objectgroup name="things">
  <object id="1" name="spawn" type="start" x="16" y="32" width="48" height="16"><properties><property name="team" type="int" value="2"/><property name="boss" type="bool" value="true"/><property name="say" value="hi"/></properties></object>
  <object id="2" name="pond" x="10" y="10"><polygon points="0,0 20,0 20,20 0,20"/></object>
  <object id="3" name="patrol" x="0" y="0"><polyline points="0,0 32,0 32,32"/></object>
  <object id="4" x="5" y="6"><point/></object>
  <object id="5" name="ring" x="40" y="40" width="10" height="10"><ellipse/></object>
  <object id="6" name="chest" gid="3" x="64" y="48" width="16" height="16"/>
 </objectgroup>]]
  local d = Tmx.import(tmx('encoding="csv"', FX.csv, objs), read)
  local a = d.areas or {}
  check(#a == 5 and #(d.paths or {}) == 1, "objects: 5 areas, 1 path: " .. #a)
  check(a[1].name == "spawn" and a[1].x == 16 and a[1].w == 48 and a[1].props.team == 2 and a[1].props.boss == true and a[1].props.say == "hi" and a[1].props.type == "start", "a rectangle and its properties")
  check(#a[2].points == 8 and a[2].points[3] == 30, "a polygon: its points, absolute")
  check(d.paths[1].name == "patrol" and #d.paths[1].points == 6, "a polyline: a path")
  check(a[3].name == "object 4" and a[3].props.shape == "point" and a[4].props.shape == "ellipse", "a point, an ellipse")
  check(a[5].name == "chest" and a[5].y == 32 and a[5].props.tile == 2, "a tile object: its top, its tile")
  -- what a game reads: the areas at a point, a spline through the path
  local m = Map.from_data(d)
  local back = Map.to_data(m)
  check(#back.areas == 5 and back.areas[1].props.team == 2 and #back.paths == 1, "areas and paths: kept by map.lua")
  check(#tmap.areas_at(back, 20, 40) == 1 and tmap.areas_at(back, 20, 40)[1].name == "spawn", "tmap.areas_at: in the rectangle")
  check(tmap.contains(tmap.area(back, "pond"), 15, 15) and not tmap.contains(tmap.area(back, "pond"), 35, 15), "tmap.contains: in the polygon, not out of it")
  local s = tmap.spline(tmap.path(back, "patrol"), 4)
  check(#s == 2 * (2 * 4 + 1) and s[1] == 0 and s[#s - 1] == 32 and s[#s] == 32, "tmap.spline: through the ends: " .. #s)
  local len = tmap.length(s)
  check(len > 60 and len < 70, "tmap.length: about 64: " .. len)
  local x, y = tmap.at(s, len)
  check(math.abs(x - 32) < 1e-6 and math.abs(y - 32) < 1e-6, "tmap.at: the end")
  local cl = tmap.spline({ 0, 0, 10, 0, 10, 10, 0, 10 }, 3, true)
  check(#cl == 2 * (4 * 3 + 1) and cl[#cl - 1] == 0 and cl[#cl] == 0, "a closed spline: back to its start")
end
-- an infinite map: its chunks
do
  local t = '<map orientation="orthogonal" width="2" height="2" tilewidth="16" tileheight="16" infinite="1"><tileset firstgid="1"><image source="s.png"/></tileset>'
         .. '<layer name="a"><data encoding="csv"><chunk x="-16" y="0" width="2" height="1">1,2</chunk><chunk x="16" y="0" width="2" height="1">3,4</chunk></data></layer></map>'
  local d, notes = Tmx.import(t)
  check(d.w == 34 and d.h == 1 and d.layers[1].rows[1]:sub(1, 4) == "0001" and d.layers[1].rows[1]:sub(-4) == "0203", "an infinite map: its chunks placed: " .. d.w .. " " .. d.layers[1].rows[1])
end
check(Tmx.import("<nothing/>") == nil, "not a map: nil")
-- the samples: plugins/tilemap/samples/island.tmx (+ island.tsx) is island.tmap
do
  local S = "../../plugins/tilemap/samples/"
  local function file(p) local h = io.open(S .. p, "rb"); if h then local s = h:read("*a"); h:close(); return s end end
  local d, notes = Tmx.import(file("island.tmx"), file)
  local m = dofile(S .. "island.tmap")
  check(d and #notes == 0, "the sample: read with no notes: " .. table.concat(notes or {}, "; "))
  check(d.w == m.w and d.h == m.h and #d.layers == #m.layers and d.tileset == "../tiles.png", "the sample: its size, layers and the .tsx's picture")
  local same_rows = true
  for i, l in ipairs(m.layers) do
    for r = 1, m.h do if (d.layers[i] or { rows = {} }).rows[r] ~= l.rows[r] then same_rows = false end end
  end
  check(same_rows, "the sample: its cells (csv, base64, base64 + zlib layers) are island.tmap's")
  check(#d.areas == 5 and #d.paths == 1 and tmap.path(d, "patrol") and #tmap.path(d, "patrol").points == 8, "the sample: 5 areas and the patrol path")
  local spawn = tmap.area(d, "spawn")
  check(spawn and spawn.props and spawn.props.team == 1 and #tmap.areas_at(d, 170, 200) >= 1, "the sample: spawn's props, a point in it")
end

print(string.format("tmx: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
