# Flock

A plugin of Replay's editor (`plugins/flock`): `.flock` files, boids:
flocks, schools, swarms, herds.

- `files.lua`: which extensions open here (`flock`)
- `editor.lua`: the tab (runs in Lite)
- `templates/birds.flock`: what *+ flock* in the tree's `/assets` starts from
- `samples/*.flock`: birds, fish, bats, bees, sheep
- the simulation, for the tab and for games: `runtime/flock.lua`

## Using it

The flock flies in the middle, inside its field (the box). Hold LMB: a goal
where the mouse is. On the left: kinds of flocks (birds, fish, bats, bees,
sheep: each a set of the settings), Play / Pause (Space), Restart, a
predator after the mouse, rocks to fly round. On the right, every setting
as a slider; the flock changes as you drag: how far a boid sees, its three
rules (separation and its personal space, alignment, cohesion), a goal and a
leader to head for, wander, avoid (obstacles, walls, the field's edges),
flee (predators, and how near), speeds and turning, the field (bounce off its
edges, or wrap round), the look (size, two colours). Ctrl+Z / Ctrl+Y,
Ctrl+S.

## In a game

```lua
local f = w:flock("birds.flock")              -- from assets/ (read again when it changes)
st = st or f:new(seed)                        -- the boids: plain data, keep it in the world
f:step(st, dt, { goal = { x, y }, predators = { { x, y } }, obstacles = { { x, y, r } },
                 solid = function(x, y) return wall_at(x, y) end })
f:look(st, node.c)                            -- a node's tris: a triangle a boid
f:dots(st, node.c.bullets)                    -- or a bullets batch (pictures, turned)
f:preset("fish")                              -- another kind, in this one's field
```

`games/flocking.lua` is a demo: the birds keep together round rocks, flee
a hawk, follow the mouse while it's held; 1..5 switch the kind.
