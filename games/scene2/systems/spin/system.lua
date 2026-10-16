-- spin: nodes with transform + spin rotate (spin = radians per second)
return { requires = { "transform", "spin" }, run = function(w, n, dt)
  n.c.transform.r = (n.c.transform.r or 0) + n.c.spin * dt
end }
