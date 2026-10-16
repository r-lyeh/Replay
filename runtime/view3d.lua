-- view3d.lua - 3D for game code (no host needed: the same numbers headless):
--   w:project3d(camera, what) -> x, y, depth, visible
--     camera: a camera3d node (or its path); what: { x, y, z } in its 3D space, or a
--     node (path) under it: its transform3d's place. x, y: the 2D world point where that
--     shows in the camera's picture (a name tag over a head: put the 2D node there);
--     depth 0..1 (near..far); visible: in front of the camera and inside its picture.
-- The same projection as the host's (editor/raster3d.h: look-at, perspective, depth
-- 0..1; the picture w x h centred on the camera node, its transform's place, turn, scale).
local M = {}

local function norm(v) local l = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]); if l < 1e-12 then return v end return { v[1] / l, v[2] / l, v[3] / l } end
local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function v3(t, d) if type(t) ~= "table" then return d end return { tonumber(t[1] or t.x) or d[1], tonumber(t[2] or t.y) or d[2], tonumber(t[3] or t.z) or d[3] } end

-- an transform3d (x, y, z, rx, ry, rz, s | sx, sy, sz) applied to a point: R = Ry * Rx * Rz, as m4_trs
local function trs(x, p)
  local s = x.s or 1
  local sx, sy, sz = (x.sx or s) * p[1], (x.sy or s) * p[2], (x.sz or s) * p[3]
  local rx, ry, rz = x.rx or 0, x.ry or 0, x.rz or 0
  local cz, szr = math.cos(rz), math.sin(rz)
  local ax, ay, az = cz * sx - szr * sy, szr * sx + cz * sy, sz            -- Rz
  local cx, sxr = math.cos(rx), math.sin(rx)
  ax, ay, az = ax, cx * ay - sxr * az, sxr * ay + cx * az                  -- Rx
  local cy, syr = math.cos(ry), math.sin(ry)
  ax, ay, az = cy * ax + syr * az, ay, -syr * ax + cy * az                 -- Ry
  return { ax + (x.x or 0), ay + (x.y or 0), az + (x.z or 0) }
end
local function path_of(n) return type(n) == "table" and n.path or n end
local function parent_path(p) return p:match("^(.*)/[^/]+$") end

function M.project(w, camera, what)
  local cpath = path_of(camera)
  local cn = w:node(cpath)
  local c = cn and cn.c.camera3d
  if not c then return nil, "not a camera3d: " .. tostring(cpath) end
  local p
  if type(what) == "table" and not what.path then p = v3(what, { 0, 0, 0 })
  else                                             -- a node under the camera: its place, through every transform3d from it up
    local np = path_of(what)
    if type(np) ~= "string" or np:sub(1, #cpath + 1) ~= cpath .. "/" then return nil, "not under " .. cpath end
    p = { 0, 0, 0 }
    local at = np
    while at and at ~= cpath do
      local n = w:node(at)
      local x = n and n.c.transform3d
      if type(x) == "table" then p = trs(x, p) end
      at = parent_path(at)
    end
  end
  local eye, at, up = v3(c.eye, { 0, 2, 6 }), v3(c.at, { 0, 0, 0 }), v3(c.up, { 0, 1, 0 })
  local f = norm({ at[1] - eye[1], at[2] - eye[2], at[3] - eye[3] })
  local s = norm(cross(f, up))
  local u = cross(s, f)
  local d = { p[1] - eye[1], p[2] - eye[2], p[3] - eye[3] }
  local vx, vy, vz = dot(s, d), dot(u, d), -dot(f, d)   -- (view space: looking down -z)
  local res = c.res or 1
  local cw, ch = c.w or 320, c.h or 180
  local aspect = (math.floor(cw * res)) / math.max(1, math.floor(ch * res))
  local t = math.tan((c.fov or 60) * math.pi / 360)
  local zn, zf = c.near or 0.1, c.far or 100
  local front = -vz > 1e-6
  local wclip = -vz
  if not front then wclip = 1e-6 end
  local nx, ny = (vx / (aspect * t)) / wclip, (vy / t) / wclip
  local zc = (vz * zf / (zn - zf) - (zf * zn) / (zf - zn)) / wclip
  local lx, ly = nx * 0.5 * cw, -ny * 0.5 * ch       -- (in the picture: its middle 0, y down)
  local x2, y2 = lx, ly                           -- the camera node's 2D place: its transform and its parents'
  local at2 = cpath
  while at2 and at2 ~= "" do
    local n = w:node(at2)
    local x = n and (n.c.transform or n.c.pos)
    if type(x) == "table" then
      local r, sc = x.r or 0, x.s or 1
      local sx, sy = (x.sx or sc) * x2, (x.sy or sc) * y2
      x2, y2 = math.cos(r) * sx - math.sin(r) * sy + (x.x or 0), math.sin(r) * sx + math.cos(r) * sy + (x.y or 0)
    end
    at2 = parent_path(at2)
  end
  local visible = front and math.abs(nx) <= 1 and math.abs(ny) <= 1 and zc >= 0 and zc <= 1
  return x2, y2, zc, visible
end

local ok, ecs = pcall(require, "ecs")
if ok and type(ecs) == "table" then
  local World = ecs.World or (ecs.world and getmetatable(ecs.world()).__index)
  if World then function World:project3d(camera, what) return M.project(self, camera, what) end end
end
return M
