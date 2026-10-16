# Replay's game APIs

Every API a game sees, subsystem by subsystem: the world and its nodes,
components the host draws, systems and their callbacks, input, sound,
assets, savegames, the editor's hooks, and the modules (`collide`, `path`,
`tmap`, `anim`, `loc`, `dialog`, `options`, `bullets`, `flock`, `dd`). It is a
reference to review the API by, not a tutorial: [HELP.md](HELP.md) explains
how to use them, with examples. The last two sections are the review: what
reads oddly today, and what another engine of r-lyeh's (`c:\prj\game\src`:
an SDL_gpu C engine, Lua gameplay) has that Replay doesn't.

Conventions (all of Replay unless a line says otherwise):

- Coordinates are world units, origin the middle, +y down; angles radians
  (`transform.r`) except where a plugin's file says degrees (`deg` in tilemap
  decals, bullet patterns).
- Colours are `{ r, g, b [, a] }`, 0..255 (or `"#rrggbb"` where noted).
- Paths are node paths (`/objects/ship`); patterns take `*` (one level) and
  `**` (any depth).
- Asset names: `"ship.png"` or `"/assets/ship.png"` (both work everywhere a
  name is read from `assets/`; a script game's assets are `games/common/`).
- Errors: functions that can fail return `nil, err` (or `false`); none
  throws on bad data from a file.
- `w` is the world (`ecs.world()`); `n` a node (`n.path`, `n.name`, `n.c` its
  components).

Where each lives: `runtime/ecs.lua` (the world), `runtime/boot.lua` (the
host's Lua: input, hooks), `editor/render.h` (what draws), and the module of
each section.

---

## 1. The world and its nodes (ecs.lua)

```lua
local ecs = require("ecs")
local w = ecs.world()                    -- a new, empty world (a script returns it)

w:node(path) -> n | nil                  -- the node at a path
w:spawn(path [, components]) -> n        -- make it (and missing parents: mkdir -p) or merge components onto it
w:remove(path)                           -- it and its subtree
w:children(n | path) -> { n... }         -- in order (rank, then name)
w:walk(n | path, fn(n, depth) [, depth]) -- depth first, parents first; fn returns false: skip its subtree
w:select(pattern) -> { n... }            -- "/entities/rocks/*", "/objects/**"
w:query(comp1, comp2, ...) -> { n... }   -- the nodes with every one of these components (sorted by path)
w:set(n | path, name, value)             -- a component (spawns the node if missing)
w:get(n | path, name) -> value
w:unset(n | path, name)
w:refresh()                              -- components added by hand (n.c.x = ...) join the systems' lists now
w:live(path) -> bool                     -- simulated and drawn: under /objects or /entities
w:layout() -> bool                       -- the world follows the layout (/systems, /objects... at its root)
w:rank_of() -> fn                        -- (the tree's order: ranks)
w:dump([n | path])                       -- (debug: prints the subtree)
```

The tree's roots (HELP 4.1): `/config` (settings), `/docs`, `/assets`,
`/data` (rules, state, `/data/lib/<name>` modules), `/classes`, `/objects`
(placed, saved), `/systems` (code), `/entities` (spawned while playing,
never saved), `/saves`, `/tmp`, `/plugins`.

Saving, loading, comparing (what the editor, the timeline and the network
use; a game rarely does):

```lua
w:save(pattern [, disk]) -> ok, blob     -- text (Lua data); disk = true: what goes to disk only (no /entities, /tmp)
w:load(blob [, at]) -> ok | false, err   -- validated first: a bad blob changes nothing; its scope replaced exactly
w:capture(pattern) -> data               -- as save, but tables: { version, scope, nodes = { [path] = components } }
w:put(data [, at])                       -- capture's data back (copied)
ecs.diff(a, b [, fine]) -> ok, patch     -- blob a -> b; fine: only the components that changed
ecs.load(blob [, at, world]) -> ok, world
ecs.encode(v) -> text | nil, err         -- plain data as Lua text;  ecs.decode(text [, name]) -> v | nil, err (sandboxed)
ecs.copy(v)                              -- a deep copy of plain data
ecs.match(pattern, path) -> bool
ecs.overrides(base, edited) / ecs.apply_overrides(w, text)   -- a script game's property edits (name.overrides.lua)
w:upgrade_class(name, before) -> n       -- a class changed: its nodes that kept the old value take the new
```

## 2. Classes (ecs.lua)

`/classes/<name>` describes a component: each member `{ type, value, min,
max, step, options }`. Types: `int number angle string key asset node bool
vec2 vec3 vec4 quat rect color3 color4`. A node with that component gets
the members it lacks (`ecs.start_value(member)`, `ecs.member(d)`);
`w:builtins()` adds the host's components as classes (no members).

## 3. Components the host draws (render.h)

| Component | Shape |
|---|---|
| `transform` | `{ x, y, r, s | sx, sy, shear, shear_y }`: children follow |
| `color` | `{ r, g, b, a }`: children inherit |
| `rect` | `{ w, h, fill }` (centred) |
| `circle` | `{ r, fill }` |
| `lines` / `tris` | `{ x1, y1, x2, y2, ..., loop }` / triangles |
| `text` | `"hi"` or `{ "hi", size, font = "sans" | "sans-bold" | "mono" | "x.ttf", align, width, fallback }` |
| `sprite` | `{ "..##..", palette = { ["#"] = {...} }, px }` (ASCII art) |
| `image` | `{ name, w, h, color, smooth, src = { x, y, w, h }, ax, ay, outline1, outline2, frame, at = "sheet" }` |
| `bullets` | `{ name, size, xy, s, rgb, a, o, color }` (one batch) |
| `tilemap` | `{ name, layer = "ground" | n | "*", size, color }` or `{ rows, tileset, tile, size, digits }` |
| `ref` | `"/path"`: draw that subtree here |
| `camera3d` | `{ w, h, eye, at, up, fov, near, far, clear, ambient, sun = { dir, color }, shadows, res }`: a 3D viewport (its subtree's 3D nodes, as its picture) |
| `transform3d` | `{ x, y, z, rx, ry, rz, s | sx, sy, sz }`: meters, y up, radians (y, x, z) |
| `mesh` | `{ name, color, texture }`: `.gltf` / `.glb` / `.fbx` / `.vox`, or `"cube"`, `"plane"`, `"sphere"` |
| `animator` | `{ clip = "walk" | n, t = seconds, loop = true, morphs = { mouthO = 1 } }`: a skinned `mesh` posed at its clip's time (the game moves `t`); `morphs`: blend shapes' weights over the clip's; `blend = { clip, t, w }`: a second clip mixed in |
| `bounds3d` | `{ w, h, d }` (a box) or `{ r }` (a sphere), `x, y, z`: a 3D node's pick shape (in its own space) |
| `w:project3d(camera, point | node)` | -> x, y, depth, visible: a 3D point's place in a `camera3d`'s picture, in 2D world units (runtime/view3d.lua) |
| `bounds` | `{ w, h }` or `{ r }`: what a right-click picks |
| `hidden` | `true` |
| `layer` | `"fx"`: draw order by `/data/layers` `order` |

Pictures: PNG, JPG, BMP, TGA, GIF, QOI, WebP, PUG. A file read again when it
changes on disk.

## 4. Systems (ecs.lua)

```lua
-- a code leaf (/systems/<name>/system): runs in the sandbox (math, string, table, utf8, safe base; no io, os, load)
return function(w, dt) ... end                               -- once a tick
return { requires = { "transform", "vel" },                     -- once a tick per live node that has them
  filter = { any = { ... }, none = { ... } },
  run = function(w, n, dt) end,
  interval = 0.5, active = false,
  on_add = function(w, n) end, on_remove = function(w, n) end,
  on_key = function(w, key, down, player) end,
  on_action = function(w, name, down, player) end,
  on_event = function(w, name, data, player) end,
  on_editor = function(w, what, data) end }

ecs.system(function() ... end)           -- a script's system: the function's own text becomes the code leaf
w:system(name, requires, fn [, opts])    -- a system from a plain function (no code leaf)
w:unsystem(name)
w:require(name) / require "space"        -- /data/lib/space's module (in systems)
w:tick(pattern, dt) / w:step(dt)         -- run the systems once (the host does it)
w:rerun(pattern, dt)                     -- replay a tick (the network's reconciliation; w.replaying meanwhile)
```

Languages: Lua, Hurdy (`.hurdy`), Teal (`.tl`; `ecs.compile`,
`ecs.loadscript`, `ecs.check_script`, warnings once each).

Globals in every system: `collide`, `path`, `tmap`, `anim`, `dd` (§12).

## 5. Events and the editor's hooks

```lua
w:event(name, data)                      -- every on_event (and w.on_event) gets it; online: the host's, to everyone, once
w:deliver(name, data, player)            -- (the network's side of it)
w:hear_editor(what, data)                -- (the host: on_editor's source)
w:point_at(name [, note])                -- the editor points at a part of itself: "play", "stop", "rewind", "save", "eye", "props", "timeline", "game"...
w:panic(title [, text])                  -- the game's own fatal screen (modal); then w.on_panic_closed(w)
```

`on_editor` hears: `"start"`, `"playing"` / `"paused"` / `"stopped"`
(`data.from`), `"stopping"` (before Stop puts the world back: save here),
`"select"`, `"edit"`, `"seek"`, `"save"`, `"view"`, `"picking"`, `"tab"`,
`"code"`, `"cursor"`, `"window"`. `w.editor` holds the same to read any
time: `mode`, `view`, `picking`, `selected`, `tab`, `unsaved`, `line`,
`maximized`.

Where it runs: `w.in_editor`, `w.is_retail` (neither: `--headless`).

## 6. Input (ecs.lua, boot.lua)

```lua
w.on_key = function(w, key, down, player) end   -- keys ("space", "a", "left"), pad buttons ("pad a", "pad dpup"),
                                                 -- the left stick ("pad left"...), triggers ("pad lt", "pad rt")
w:key(key, down [, player])              -- (the host feeds them; a test can too)
w:action(name [, player]) -> held        -- /config actions = { jump = { "space", "pad a" } }
w:pressed(name [, player]) / w:released(name [, player])   -- this tick
w:axis(neg, pos [, player]) -> -1..1     -- two actions (a stick bound to them: in between)
w:bind(name, keys) / w:bind(name)        -- rebind on this machine (saves/bindings.sav) / back to the game's
w:bindings() -> { [name] = { keys } }
w.mouse  -- { x, y, inside, left, middle, right }: world units; /config window = { mouse = true } to get the buttons
w.pads   -- { { lx, ly, rx, ry, lt, rt }... }: sticks -1..1, triggers 0..1
```

`/config` `window = { w, h, title, mouse, cursor = false, grab = false }`;
`keys = { fullscreen = false, quit = false }` (the host's keys a standalone
game gives up).

## 7. Time and clock

```lua
w.frame, w.time                          -- ticks, game seconds (dt added up) since the world was made; not saved state
w:wall_time() -> seconds since 1970      -- the computer's clock (not world data)
w:wall_date([fmt, t]) -> text            -- os.date's formats ("%H:%M")
```

## 8. Sound (ecs.lua, sound.lua; the host: editor/sound.h)

```lua
w:sound(name [, volume | { volume, pan, pitch, loop, bus }]) -> handle | false   -- .sfx, .soundgraph, .wav/.ogg/.mp3/.flac
w:sound_set(h, { volume, pitch }) -> still playing?
w:sound_stop(h)
w:music(name [, { volume, fade, loop }]) / w:music(false [, { fade }])
w:bus(name [, volume]) -> volume         -- "sfx", "music", "voice"
```

Nothing plays while rewinding or on a peer's copy (`w.silent`). Sixteen voices.

## 9. Assets and generators

```lua
w:asset(name) -> data | nil, err         -- a data file of assets/ (Lua data: .tmap, .sfx, .anim...)
w:generate(kind, settings) -> map, info  -- "dungeon", "terrain" (plugins/<kind>/gen.lua)
w:anim(name)   w:dialog(name)   w:bullets(name)   w:options(name)   w:flock(name)   w:foliage(name)   -- §12
w:tr_file(name) -> "/assets/<language>/name" | "/assets/name"
```

## 10. Savegames and memory

```lua
w:savegame(name, value) -> true | nil, err   -- saves/<name>.sav (a script game: .saves/<script>/<name>.sav)
w:loadgame(name) -> value | nil              -- works while the script builds its world
w:memo(name, value) / w:memo(name) -> value  -- in memory while the program runs (Stop, reloads, rewinds), never on disk
```

## 11. Text and languages (ecs.lua, loc.lua)

```lua
w:text_size(text [, font, size, width]) -> w, h
w:tr(key [, n] [, vars]) -> text         -- strings.loc; plural forms (CLDR), {name} filled in
w:language([code]) -> code               -- set: saved for this machine
w:languages() -> { codes }
```

## 12. Modules

**collide** (global; `require "collide"`): boxes are centre + half sizes.
`circle_circle`, `circle_box`, `box_box` -> hit, nx, ny, depth;
`point_box`, `point_circle`; `ray_box`, `ray_circle` -> t, nx, ny;
`sweep_circle_box`, `sweep_circle_circle`, `sweep_box_box` -> t, nx, ny;
`reflect(vx, vy, nx, ny [, bounce])`, `slide(...)`; `shape(node)`,
`test(a, b)`; `grid(cell)` -> `g:add(key, x, y, hw, hh)`, `g:near(...)`,
`g:clear()`.

**path** (global; `w:path(from, to, opts)` -> world points): `path.grid(w,
h, solid [, cost])`, `path.find(g, sx, sy, tx, ty [, opts])` (diagonal,
jps, max, smooth) -> cells, info; `path.smooth`, `path.flow(g, tx, ty)` ->
field (`f:dir(x, y)`), `path.search(start, goal, neighbours, heuristic)`,
`path.from_map(map, opts)`.

**tmap** (global): `tmap.cell(map, layer, x, y)`, `tmap.area(map, name)`,
`tmap.areas_at(map, x, y)`, `tmap.contains(area, x, y)`, `tmap.path(map,
name)`, `tmap.spline(p [, per, closed])`, `tmap.length(points)`,
`tmap.at(points, d)` -> x, y, angle; `tmap.decals(map, layer)`,
`tmap.order(map)`.

**anim** (global; `w:anim(name)` -> a with methods): `a:new(name [, frame])`
-> st; `a:step(st, dt [, on_event])` -> st, events; `a:play(st, name [,
frame])`; `a:frame(st)`; `a:image(st [, img])` -> an `image` component;
`a:hitbox(st, which | name, x, y [, sx, sy])`; `a:hitboxes(st, x, y [, sx,
sy])`; `anim.upgrade(def)`, `anim.check(def)`, `anim.parse_event(text)`,
`anim.parse_jump(text)`.

**dialog** (`w:dialog(name)` -> d): `d:begin(st)`, `d:update(st, dt)`,
`d:typed(st)`, `d:choices(st)`, `d:advance(st [, choice])`.

**options** (`w:options(name)` -> o): `o:state(w, node)`, `o:open(w, st)`,
`o:close(w, st)`, `o:key(w, st, key, down)` -> took it, `o:update(w, st,
dt [, n])`, `o:draw(w, st, n [, look])`, `o:events(st)`, `o:value(st, id)`.

**bullets** (`w:bullets(name)` -> d): `d:new(seed)`, `d:emit(st, pattern, x,
y, owner)`, `d:step(st, dt, tx, ty)`, `d:hit(st, x, y, r)`, `d:clear(st [,
fade])`, `d:look(st)`, `d:path(...)`; stages: `d:stage_new(seed)`,
`d:stage_step(...)` (runtime/bullets.lua lists them).

**flock** (`w:flock(name)` -> f): `f:new(seed [, count])`, `f:step(st, dt,
{ goal, predators, obstacles, solid, leader })`, `f:look(st [, out])`,
`f:dots(st [, out])`, `f:preset(kind)`.

**foliage** (`w:foliage(name | settings [, overrides])` -> items, info): where
each copy of a `.foliage`'s layers goes: `items.n`, and arrays `layer`, `x`,
`y`, `z`, `rx`, `ry`, `rz`, `sx`, `sy`, `sz`, `r`, `g`, `b`, `items.meshes`;
`info.count`, `info.per[layer]`. Made once per settings (an asset: again when
it changes). Drawn by a node's `foliage3d` (runtime/foliage.lua).

**dd** (debug draw, global in systems; editor/overlay.h): `dd.line(x1, y1,
x2, y2 [, color])`, `dd.arrow`, `dd.rect(x, y, w, h [, color, fill])`,
`dd.circle`, `dd.cross`, `dd.tri`, `dd.text`, `dd.screen` (screen
coordinates), `dd.log`, `dd.warn`, `dd.error` (to the log). Shown in the
editor only.

## 13. Online (players.lua, net.lua: on hold)

`host(port)`, `join(addr)`, `leave()`, `online()` (the console);
`w:owns(n)` (this player decides it), `w.players`, `w.peer`; events from the
host only. The design is in [NETWORK.md](NETWORK.md).

---

## 14. Review: what reads oddly today

Notes to decide on, not changes made:

1. **Two shapes for "a thing from assets"**: `w:anim`, `w:dialog`,
   `w:bullets`, `w:options`, `w:flock` return an object with methods (`a:step`);
   `tmap`, `path`, `collide` are globals of functions taking the data
   (`tmap.cell(map, ...)`); `anim` is both. Pick one: objects for every
   asset kind, globals for stateless math only (`collide`, `path`).
2. **Handles for sounds** are bare values with `w:sound_set(h, ...)` /
   `w:sound_stop(h)`; everything else of that kind is an object (`h:stop()`,
   `h:set { pitch = 2 }` would match). Also missing: pause / resume one, a
   sound's duration, mute.
3. **Getter / setter styles**: `w:memo(name)` / `w:memo(name, v)`,
   `w:language()` / `w:language(code)`, `w:bus(name)` / `w:bus(name, v)` (one
   function both ways) against `w:savegame` / `w:loadgame` and
   `w:get` / `w:set` (two). Either is fine; mixed reads as an accident.
4. **Fields and methods**: `w.mouse`, `w.pads`, `w.editor`, `w.in_editor`,
   `w.is_retail`, `w.frame`, `w.time` are fields; input otherwise is methods
   (`w:action`). The fields are written by the host each frame: say so in
   their names, or move them under one table (`w.host.mouse`...).
5. **Colours** are 0..255 tables here, `"#rrggbb"` in some plugin files
   (bullets), 0..1 in the other engine. Accepting all three everywhere
   (render.h's `read_color` already takes `#rrggbb`) would end the question.
6. **Degrees and radians**: radians in `transform`, degrees in tilemap decals
   (`deg`) and bullet files. Files authored by hand favour degrees; code
   favours radians. Name the unit in the key (`deg`, `r`) everywhere, as
   decals do.
7. **`w:pressed` / `w:released`** read like actions, not keys: fine, but
   `w:action` (held) is the odd name out (`w:held`?).
8. **Results**: most return `nil, err`; `w:sound` returns `false`;
   `w:savegame` returns `nil, err` but `true` on success. One rule: `value |
   nil, err`.
9. **`w:spawn`** both makes and merges; `w:set` spawns a missing node. Fine,
   but nothing makes a node only if it's absent (`w:spawn_new`?), so systems
   test `w:node(p)` first.

## 15. Review: what the other engine (c:\prj\game\src) has

Read for this review (engine.h, lua_api.c, gfx.c, cam3d.h, app.c, main.c):
an SDL_gpu batch renderer (Vulkan / D3D12; shaders precompiled to SPIR-V and
DXIL), a Lua script with `init` / `tick` / `draw` / `event` / `quit`, C
structs reflected to Lua by a field table (`REFLECT(vec2, FIELD(...))`: one
generic metatable reads and writes them). What it offers that Replay could
take:

| There | Here | To borrow |
|---|---|---|
| `app.stats`: time, dt, fps, frame, draw calls, vertices, voices, and where the frame went (`ms_wait`, `ms_tick`, `ms_draw`, `ms_acquire`, `ms_submit`) | the editor's profiler (in the tree tab); nothing a game reads | `w.stats` read-only, the same fields: a game's own debug HUD, and tests |
| `key_text()`: UTF-8 typed this frame | keys only (the options menu's text items build text from keys) | `w.typed` (SDL_EVENT_TEXT_INPUT), for name entry, chat |
| `mouse_state`: dx, dy, wheel_x, wheel_y | `w.mouse` x, y, buttons | the motion and the wheel in `w.mouse` |
| `mouse_cursor("hand" / "move" / "crosshair" ...)` | `/config window.cursor = false` only | `w:cursor(name)` while over the game |
| `pad_name`, `pad_connected`, `pad_rumble(pad, low, high, seconds)` | sticks, triggers, buttons | `w:rumble(pad, low, high, s)` (SDL_RumbleGamepad), pad names |
| `window_title`, `window_size`, `window_fullscreen` at run time | `/config window` at start; full screen through the host's keys | `w:window { title, fullscreen }` (the host already has `l_host_window` for full screen) |
| `voice_pause` / `voice_resume`, `sound_duration`, `audio_mute` | play, set, stop | as §14.2 |
| `gfx_clip(rect)`: scissor | none | a `clip = { w, h }` component: its subtree drawn inside (scroll panes, minimaps) |
| `gfx_screenshot(path)` | `--shot` (the host) | `w:screenshot(name)` into saves/ (photo modes, tests) |
| `gfx_camera3d` + `gfx_project3d`, spheres, cylinders, capsules, convex polygons in 3D (instanced), depth-tested over a pre-rendered background's depth image (`DPT1`: half floats, meters) | 2D only | the 3D plan ([3D.md](3D.md)): its depth backgrounds are exactly the "pre-rendered rooms" plugin idea (LBA, Alone in the Dark) |
| `gfx_mode3d`: x-ray (hidden parts seen through), silhouette mask, outline (inflated meshes after a stencil mask), decal (on the ground, no depth write) | outlines for 2D images only | the same modes for 3D meshes in the plan |
| struct reflection (`REFLECT`) | Lua tables everywhere (components are plain data) | not needed: Replay's data is Lua already; worth it only for C-side hot structs (the 3D path's) |

What Replay has that it doesn't (so not to lose in a merge of ideas): the
world tree with live editing, the timeline and rewinds, systems as data,
the network model, classes, the asset plugins.
