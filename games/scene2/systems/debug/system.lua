-- debug: debugdraw on the dev overlay (does nothing in a standalone game).
-- Velocity arrows on everything that moves, and its name next to it.
return { requires = { "transform", "vel" }, run = function(w, n, dt)
  local x, v = n.c.transform, n.c.vel
  dd.arrow(x.x, x.y, x.x + v.x * 0.5, x.y + v.y * 0.5, "#ffd04080")
  dd.text(x.x + 8, x.y - 14, n.name, { 150, 220, 255, 160 })
end }
