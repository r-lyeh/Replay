-- follow: once she's your friend (her talks start at the rules' `friend`
-- line: you said yes), the fairy flies after you round the walls and
-- furniture (w:path: runtime/path.lua, over the room's solid layers),
-- staying a little way off; she waits while you talk. Till then she stays
-- where she is. Her way is looked for again twice a second.
local room = require "room"
return function(w, dt)
  local st, rl = w:node("/data/state"), w:node("/data/rules")
  local f = w:node("/objects/fairy")
  if not (st and rl and f) then return end
  local s, talk, R = st.c.walk, st.c.talk, rl.c.room
  local fs = st.c.follow or { t = 0 }
  st.c.follow = fs
  if not fs.friend then                            -- (once friends, always: the dialog can move on past that line)
    if R.friend == nil or talk.start == R.friend then fs.friend = true else return end
  end
  local x, y = f.c.xform.x, f.c.xform.y
  local dx, dy = s.x - x, s.y - y
  local far = math.sqrt(dx * dx + dy * dy)
  if talk.on or far < (R.follow_near or (R.reach or 30) * 0.8) then fs.way = nil return end   -- (near enough to talk to)
  fs.t = (fs.t or 0) - dt
  if not fs.way or fs.t <= 0 then
    fs.t = 0.5
    fs.way = w:path({ x = x, y = y }, { x = s.x, y = s.y }, { map = R.map, layer = R.solid, tile = room.TILE, ox = room.OX, oy = room.OY })
    fs.next = 2
  end
  local way = fs.way
  local p = way and way[fs.next or 2]
  if not p then return end
  local ex, ey = p.x - x, p.y - y
  local d = math.sqrt(ex * ex + ey * ey)
  local step = (R.fairy_speed or 70) * math.min(dt, 1 / 30)
  if d <= step then
    f.c.xform.x, f.c.xform.y = p.x, p.y
    fs.next = (fs.next or 2) + 1
  else
    f.c.xform.x, f.c.xform.y = x + ex / d * step, y + ey / d * step
  end
end
