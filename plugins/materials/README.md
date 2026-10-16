# materials

A material editor: `.mat` files open as node graphs. The example of a plugin
built on the canvas (`editor/3rd/lite/data/plugins/canvas`, docs/PLUGINS.md):
`editor.lua` lists the kinds of node and their typed pins, reads and writes
the file, and draws a swatch / a value inside some nodes. The canvas does the
rest: drawing, camera, selecting, moving, wiring, the menu.

- `files.lua`: the extensions it opens (`mat`)
- `templates/material.mat`: what `+ material` in the tree's `/assets` makes
- `sample.mat`: a material to try (`sample.png` is its texture)

In a tab: LMB selects and drags, drag on nothing: the selection box (nodes
and ties), drag from a pin to a pin of the same type to wire them (from a
wired input: pick its wire up), RMB: add a node (type to find it), align,
duplicate, delete. DELETE, CTRL+D, CTRL+S. The wheel scrolls, MMB drags,
CTRL+wheel zooms; Fit is in the RMB menu. Wires tie as in the node graph
(drag across them; double-click one: a control point; ties select, align and
untie with DELETE).

Not yet: editing the values inside nodes (a colour picker, a slider), a
preview.
