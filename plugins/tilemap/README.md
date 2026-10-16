# tilemap

A tilemap editor: `.tmap` maps of 16 x 16 tiles, in layers.

- `map.lua`: the model (cells, layers, areas, splines, paint / rect / fill /
  resize; no Lite in it: a game can read a `.tmap` with it)
- `tmx.lua`: Tiled's `.tmx` / `.tsx` read into a map (no Lite in it either)
- `editor.lua`: the tab (runs in Lite)
- `tiles.png`: the tileset, 256 x 256, 16 x 16 tiles (250 of them: ground,
  water, lava, wood, bricks, glass, wool, ores, plants, furniture..., and four
  kinds of auto-tiles); `tiles.lua`: their names and the auto-tile kinds. Ours, drawn by code (`tools/make_tiles.py`), CC0:
  `LICENSE-tiles.txt`
- `files.lua`: the extensions it opens (`tmap`); `config.lua`: `grid`, the
  size of a new map (`w`, `h`)
- `templates/map.tmap` (the tree's *New tmap*), `samples/island.tmap`;
  `samples/island.tmx` + `island.tsx`: the same island as a Tiled map and
  its external tileset (CC0), to try the importer with (layers in base64 +
  zlib, CSV and base64; areas as a rectangle, a polygon, a point and an
  ellipse; the patrol as a polyline)

In a tab: the tools, the layers and the tileset on the left (click a tile, or
drag over several: a stamp); the map in the middle; its size and the cell
under the mouse on the right.

| Mouse / key | |
|---|---|
| LMB | the tool: **Paint** (the stamp), **Rect** (drag: the stamp over it), **Fill** (the cells like it, touching), **Erase** |
| RMB | erases (CTRL+RMB: the menu) |
| ALT+LMB | picks the tile under it |
| MMB drag, LMB off the map | pans; CTRL+wheel zooms; double-click off the map fits |
| B R F E P A C | the tools (P the Path finder, A Area, C Spline); 1..9 the layer |
| Delete, Enter, ESC | the picked area / spline goes; a spline being clicked: done, dropped |
| CTRL+Z / CTRL+Y, CTRL+S | undo / redo, save |

**Auto-tiles**: from tile 64 the tileset has four kinds of 47 tiles ("blob"
sets): water with shores (64..), stone walls with edges (111..), lava with a
crust (158..), grass with ragged edges (205..). A cell's mask sums its
neighbours of the same kind (N 1, NE 2, E 4, SE 8, S 16, SW 32, W 64, NW
128; a corner only when both its sides count; off the map counts as the
same), and the tile is first + the mask's place among the 47 that can be
(`M.BLOB`): inner corners too. Paint with any of a kind and every
cell about the edit picks the one that fits (`map.lua` `M.autotile`);
*Auto-tiles* on the right turns it off (paint exactly what you picked),
*Auto-tile this layer* redoes a layer. The terrain generator's shores and
the dungeon generator's stone walls are made the same way.

**Areas** (A): drag out a rectangle on the map: a named area (spawn zones,
triggers, camera bounds, music regions). Drag one to move it, its corner to
size it; a polygon's points (a Tiled import's) drag too. **Splines** (C):
click points (a road, a rail, a patrol route); Enter or a double-click ends
it, ESC drops it; drag a point to move it. A spline is a Catmull-Rom curve
through its points (*Closed* on the right: back to its start). Both snap to
the half-cell grid (SHIFT: free); the panel on the right lists them, names
them and gives them props (`team = 2, boss = true, say = "hi"`). In the file:

    areas = { { name = "spawn", x = 32, y = 32, w = 80, h = 48, props = { team = 2 } },
              { name = "pond", points = { x1, y1, x2, y2, ... } } },
    paths = { { name = "patrol", points = { x1, y1, ... }, closed = true } },

(map pixels: the map's top left is 0, 0).

**Tiled maps**: a `.tmx` opens here (`files.lua`): read into a map
(`tmx.lua`): orthogonal tile layers (in groups too; CSV, base64, zlib, gzip
data; an infinite map's chunks), the first tileset's picture (embedded or a
`.tsx` beside it) and its tile size, object layers as areas (rectangles,
ellipses, points, polygons) and splines (polylines), an object's type and
properties as its props. What can't come along (a second tileset's cells,
flips, image layers, text objects) is in the log. Ctrl+S saves it as a
`.tmap` beside the `.tmx` (never over a `.tmap` already there). A tileset of
more than 256 tiles: `digits = 4` in the file (four hex digits a cell).

The layers above the one being edited show faded. A map's `tileset` can be a
picture beside it (`tileset = "my_tiles.png"`, `tile = 16`); the default,
`"plugin:tiles.png"`, is this folder's.

A `.tmap` is Lua data: `tileset`, `tile`, `w`, `h`, and `layers`, each with a
`name`, `visible` and `rows`: a string per row, two hex digits a cell (the
tile's index in the tileset, 16 a row), `..` for none.

## In a game

A node with a `tilemap` component draws a map (from its top left):

    -- objects/level/ground/tilemap.lua
    return { "/assets/level1.tmap", layer = "ground" }   -- (a layer's name or number; none: all)

The tileset is looked up beside the `.tmap` (copy `tiles.png` into the
game's `assets/`). The map reloads when its file changes. A game reads the
cells with `w:asset("level1.tmap")`: games/hop does (solid ground, lava,
gems). Its areas and splines with the global `tmap` (runtime/tmap.lua):

    local map = w:asset("level1.tmap")
    for _, a in ipairs(tmap.areas_at(map, px, py)) do ... end   -- (map pixels)
    local road = tmap.spline(tmap.path(map, "patrol"))          -- { x1, y1, ... } along it
    local x, y, angle = tmap.at(road, distance)
