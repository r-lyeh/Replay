---@meta
-- collide.lua - the collision helpers (global `collide` in a system), for the
-- editor: the node graph names call pins after these parameters. Implemented
-- in plain Lua: runtime/collide.lua (it says what each returns).
collide = {}

---@return boolean hit
---@return number nx
---@return number ny
---@return number depth
function collide.circle_circle(ax, ay, ar, bx, by, br) end
---@return boolean hit
---@return number nx
---@return number ny
---@return number depth
function collide.circle_box(cx, cy, r, bx, by, hw, hh) end
---@return boolean hit
---@return number nx
---@return number ny
---@return number depth
function collide.box_box(ax, ay, ahw, ahh, bx, by, bhw, bhh) end
---@return boolean inside
function collide.point_box(px, py, bx, by, hw, hh) end
---@return boolean inside
function collide.point_circle(px, py, cx, cy, r) end
---@return number? t
---@return number nx
---@return number ny
function collide.ray_box(x1, y1, x2, y2, bx, by, hw, hh) end
---@return number? t
---@return number nx
---@return number ny
function collide.ray_circle(x1, y1, x2, y2, cx, cy, r) end
---@return number? t
---@return number nx
---@return number ny
function collide.sweep_circle_box(cx, cy, r, dx, dy, bx, by, hw, hh) end
---@return number? t
---@return number nx
---@return number ny
function collide.sweep_circle_circle(ax, ay, ar, dx, dy, bx, by, br) end
---@return number? t
---@return number nx
---@return number ny
function collide.sweep_box_box(ax, ay, ahw, ahh, dx, dy, bx, by, bhw, bhh) end
---@param bounce? number
---@return number vx
---@return number vy
function collide.reflect(vx, vy, nx, ny, bounce) end
---@return number vx
---@return number vy
function collide.slide(vx, vy, nx, ny) end
---@return string? kind
---@return number x
---@return number y
---@return number hw_or_r
---@return number hh
function collide.shape(node) end
---@return boolean hit
---@return number nx
---@return number ny
---@return number depth
function collide.test(a, b) end
---@param cell? number
---@return table grid
function collide.grid(cell) end
