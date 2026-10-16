-- snippet: Play a sound and spawn sparks
w:sound("hit")
w:spawn("/entities/sparks/" .. w.frame, { xform = { x = 0, y = 0 }, color = { 255, 200, 80 }, circle = { r = 2, fill = true } })
