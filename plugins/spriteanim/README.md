# Sprite animator

A plugin of Replay's editor (`plugins/spriteanim`): `.anim` files, a
spritesheet's animations frame by frame, and Aseprite files read into them.

- `files.lua`: which extensions open here (`anim`, `ase`, `aseprite`)
- `editor.lua`: the tab (runs in Lite); `ase.lua`: the Aseprite reader (plain Lua)
- `config.lua`: `grid` (px a drag snaps to; 1: none), `preview_scale`, `ase_cols`
  (an Aseprite file's frames a row in its sheet; 0: square-ish)
- `templates/sprite.anim`: what *+ anim* in the tree's `/assets` starts from
- `samples/slime.png`, `slime.anim`, `slime.aseprite`: a slime (idle, hop), CC0,
  drawn by `tools/make_slime.py`, its Aseprite file by `tools/make_slime_ase.py`
- the runtime, for the tab and for games: `runtime/anim.lua`

## Using it

**Import...** (left): a picture (png, webp, qoi, jpg...) becomes the sheet
(copied beside the `.anim` when it's elsewhere); an Aseprite file, the sheet
and its animations. The sheet is in the middle (MMB pans, the wheel zooms).

- **Frames** tool (F): drag on nothing: a new frame after the one picked,
  its anchor in its middle; drag the frame picked to move it, its edges or
  corners to size it (its anchor and hitboxes come along: they're kept from
  the rect's top left); click another frame: pick it.
- **Hitboxes** tool (H): drag on nothing: the next hitbox (up to 10); drag
  one to move it, its edges to size it; Delete removes the one picked.
- **1..9, 0 held** while dragging, in either tool: that hitbox (1..10), drawn
  anew. Each hitbox has its own colour, here and in the list on the right.
- **The anchor** (the cross): drag it anywhere, outside its rect too.

On the right: the preview (Space: play / pause), playing at its anchor with
its outlines; then the frame: its rect and anchor (typed, or dragged), its
pause (ms), **Jump to**, its events, its hitboxes, two outline colours (1 px,
then 1 px more). Ctrl+Z / Ctrl+Y, Ctrl+S.

**Jump to** is where the animation goes after the frame's pause: empty, the
next frame (after the last, it ends); `1`, the first (a loop: a new
animation's last frame has it); `idle` or `idle 2`, another animation and its
frame. **Events** are sent when the frame shows: `sound("step"); fx("dust")`.

**Aseprite** (`.ase`, `.aseprite`): opening one, or importing it, reads it
into a sheet and animations (RGBA, grayscale, indexed; visible layers, their
opacity; tags as animations: forward, reverse, ping-pong, repeat 0 loops;
each frame's duration as its pause; slices named `hit1` / `hit2` as
hitboxes 1 and 2, other slices as hitboxes 3.. with their names (not
`pivot` / `anchor` / `origin`), a slice's pivot as the anchor, else the
frame's bottom middle).
Ctrl+S writes the `.anim` and its `.png` beside it (never over files already
there: `_ase` is added).

A `.anim` is version 2 (`version = 2`: `pivot`, `hits`, `jump`); older ones
(an anchor in sheet pixels, `hit1` / `hit2`, `loop`, a `flow` of Lua) open as
version 2 and are saved so (a flow still runs, shown as a note).

## In a game

```lua
local a = w:anim("slime.anim")                -- from assets/ (read again when it changes)
st = st or a:new("idle")                      -- what plays: plain data, keep it in the world
a:step(st, dt, function(name, arg) if name == "sound" then w:sound(arg) end end)
n.c.image = a:image(st, n.c.image)            -- the frame to draw: its part of the sheet, its anchor, its outlines
local x0, y0, x1, y1 = a:hitbox(st, 1, n.c.transform.x, n.c.transform.y)   -- hitbox 1 in the world (nil: none)
for which, b in pairs(a:hitboxes(st, n.c.transform.x, n.c.transform.y)) do ... end   -- all of them
```
