# foliage

A plugin of Replay's editor (`plugins/foliage`): `.foliage` files, what's
scattered over an area in 3D: grass, flowers, bushes, rocks, trees. A layer
for each kind, each with its mesh.

- `files.lua`: which extensions open here (`foliage`)
- `editor.lua`: the tab (runs in Lite)
- `templates/foliage.foliage`: what a new one starts from (the main menu's Levels > Foliage editor > New)
- `samples/meadow.foliage`, `samples/rocks.foliage`
- the scatter, for the tab, the renderer and games: `runtime/foliage.lua`

## Using it

The middle shows the scatter in 3D, as the game draws it: LMB drag orbits,
the wheel zooms, double-click resets the view. **Above** (left panel) shows
the area from above instead: a dot for each copy, in its colour and the size
of its footprint (MMB pans, CTRL+wheel zooms, double-click fits); **3D**
goes back.

- **Left:** the layers with their counts. A click picks one; Up / Down /
  Remove; Add a layer (grass, flowers, bushes, rocks, trees); Start from a
  sample (meadow, rocks); Save. It also shows how many copies there are and
  how long the scatter took.
- **Right:** the area (width, depth, height, seed, New seed). Then the
  picked layer:
  - its name and mesh (Grass: a tuft of blades, Cube, Sphere, or A model...
    from the game's files);
  - its size before scaling, density (copies per m²), smallest and biggest
    scale;
  - turned at random, tilt, sink (into the ground; negative raises it);
  - colour and shade (each copy darker or lighter at random);
  - clumps (0 even, 1 only the noise's peaks) and clump size;
  - spacing (no two copies nearer than that) and a cap;
  - wind (how much it sways; grass bends by its tips) and "whole up to"
    (metres from the camera before it thins out; none past 1.5x; 0: never).

The scatter changes as you drag. Ctrl+Z / Ctrl+Y, Ctrl+S.

## In a game

A node under a `camera3d` gets the whole scatter:

```lua
w:spawn("/objects/view/meadow", { transform3d = {}, foliage3d = { "meadow.foliage" } })   -- an asset (assets/, or common/ for a script)
w:spawn("/objects/view/patch", { transform3d = { x = 4 }, foliage3d = { "meadow.foliage", seed = 3, w = 6, d = 6 } })   -- its fields over the file's
w:spawn("/objects/view/inline", { transform3d = {}, foliage3d = { w = 10, d = 10, layers = { { mesh = "sphere", density = 1 } } } })
local items, info = w:foliage("meadow.foliage")   -- where each copy goes (info.count, info.per[layer])
```

The GPU draws each layer's copies instanced: one draw for each part of the
mesh, however many copies. The copies' places are worked out once, until the
settings change. Copies aren't picked one by one; the node is. See
games/meadow3d.lua.
