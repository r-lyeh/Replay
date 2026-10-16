# landscape

A plugin of Replay's editor (`plugins/landscape`): `.land` files, a landscape
in 3D: a height field over an area, as UE5's. Its base is made by rules (the
generator: hills, or flat), then edited by hand with brushes.

- `files.lua`: which extensions open here (`land`)
- `editor.lua`: the tab (runs in Lite)
- `templates/landscape.land`: what a new one starts from (flat; the main menu's Levels > Landscape editor > New)
- `samples/hills.land`, `samples/peaks.land`, `samples/dunes.land`
- the height field, for the tab, the renderer and games: `runtime/landscape.lua`

## Using it

The middle shows it in 3D as a game draws it (shadows, coloured by height and
slope). RMB drag turns round it, MMB drag pans, the wheel zooms,
double-click puts the view back.

- **Brush** (left): **Sculpt** raises the ground where you paint (SHIFT
  lowers it), **Smooth** evens out bumps, **Flatten** brings it to the height
  where the stroke began, **Erase** takes it back to the generator's. Radius
  and Strength set how much a dab does; the ring on the ground shows where.
  LMB paints; a stroke is one undo step (Ctrl+Z / Ctrl+Y).
- **Start from**: Flat, Hills, Peaks, Dunes. **Save** (Ctrl+S). It shows the
  grid, how many points the brushes moved (and Clear the edits), how long it
  took to build and a dab.
- **Right**: the **Area** (width, depth, cells along the longer side: a
  point every so many metres), the **Generator** (flat or hills: seed, New
  seed, height, the hills' size, detail, ridges, sea level), the **Colours**
  (low and high ground, rock on slopes steeper than *Rock from*, snow above
  *Snow above* of the highest point; 1: none).

Changing the generator keeps your edits on top of it; another grid size
stretches them over the new one.

**Foliage on it** (left): the `.foliage` files whose `ground` is this
landscape (beside it, or in the game's assets/ or common/) grow on it, as a
game shows them. As you sculpt, the copies under the brush follow the ground;
at the end of the stroke the foliage grows again by its rules (the slopes
and heights each layer grows on). A .foliage saved anew shows at once. See
samples/hills_meadow.foliage (on samples/hills.land).

## In a game

A node under a `camera3d` gets the landscape:

```lua
w:spawn("/objects/view/land", { transform3d = {}, landscape3d = { "hills.land" } })   -- an asset (assets/, or common/)
w:spawn("/objects/view/small", { transform3d = { x = 80 }, landscape3d = { "hills.land", cells = 32 } })   -- its fields over the file's
local land = w:landscape("hills.land")
local y = land:height_at(x, z)                      -- the ground's height there (things stand on it)
local t, hx, hy, hz = land:ray(ox, oy, oz, dx, dy, dz)   -- where a ray meets it
```

It's one mesh, made again only when it changes. See games/landscape3d.lua.
