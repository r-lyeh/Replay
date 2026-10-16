# Roadmap

The list of what's open, grouped by area, the ones I'd do first at the top of each group; to become the
planning document (what's next, in what order). What's built moved to FEATURES.md.

> **p2p is for the games, not the editor** (r-lyeh, 2026-10). Nobody edits a shared
> world together with confidence (privacy, stress, competition, stalkers, bullying), unless it is a game rather than a job.
> Editing stays solo; what travels between players is the game. Admin review of other
> games' patches is the one exception: a reviewer looks at a patch, never a live session.



## Next, in this order (r-lyeh, 2026-10)

1. ~~**Error overlay**~~: built (2026-10, FEATURES.md: editor/fatal.h, `w:panic`).
2. ~~**Fonts, round 2**~~: built (2026-10, FEATURES.md: wrapped, turned, sheared; the
   options menu in a font).
3. ~~**Map editor, round 2**~~: built (2026-10, FEATURES.md: areas, splines, the Tiled
   `.tmx` / `.tsx` importer; auto-tiles were there already). Still open from it:
   heightmap brushes, stamping tiles along a spline.

On hold: the **Sequencer** (r-lyeh, 2026-10). Networking: on hold too.



## Done since the first list (details in FEATURES.md)

- LOD
- Splits
- Breakpoints
- Doc tooltips
- Flow pulse
- Autoconversion
- Find references
- Values on wires
- Property editor
- Collapsible nodes
- Go to definition
- Collapse to function
- Snapshots on a timeline
- Profiler in the tree tab
- Graph diff, session sketch
- Play with unsaved editor files
- Load-time breakpoints (main script)
- Relative paths, `/` everywhere
- Players: 1..4 in split views, replication by tags
- Replicas over net.sim (scoped ownership, snapshot deltas)



## Open: editing loop

1. Create / delete / rename / duplicate nodes from the tree (RMB menu). For folder worlds
   these are folder and file operations; for script worlds, an edit of the script's text.
2. Drag nodes in the game view to move them (ALT = rotate, wheel = scale), written back to disk.
3. Search / filter box on the tree: `ship*`, `/scene/**` (the patterns `ecs.select` has).
4. Undo per node across saves: each save keeps its reverse patch.
5. ~~Error overlay per node~~: built (2026-10; FEATURES.md).
6. ~~Step mode~~: built (2026-10: a tick back / on while paused, held: repeated, the wheel
   over the timeline, the tick in the time label; FEATURES.md).



## Open: node graph

1. Reroute knots, align / tidy selected.
2. vec3 / vec4 types.
3. Snippets: a selection saved as a menu item.
4. Breakpoints on nodes (today: on lines, shown on nodes).
5. Load-time breakpoints in modules other than the main script (they run once, at require).
6. Probe hook cost: only files with an open graph are hooked; measure on big games.
7. A module map: the files of a game as nodes, `require` as wires.
8. Ties with LMB (r-lyeh, 2026-10) — *built 2026-10* (a press on a wire, or SHIFT+RMB; flow wires
   too; the material editor too). Still open: a modifier swapping line / box while dragging. Ties exist (SHIFT+RMB drag a line across
   wires, plugins/nodegraph/ties.lua; they're also the reroute knots of 1: a tie of one
   wire is a control point). Later, plain LMB: decide at the press, not from the drag's
   shape. A press on a wire (or within ~6 px of one) draws a tie line; a press on empty
   space draws the selection box, as now. "Near two wires" alone is too loose in a dense
   graph (box selecting would become hard). Hovering a wire: a crosshair and a "drag
   across to tie" hint, so it's learnt, not guessed. A modifier while dragging swaps
   line / box (which one: SHIFT / CTRL already add to a selection). SHIFT+RMB stays as
   the explicit way; a click (no drag) on a wire does what it does today.



## Open: graph diffs (r-lyeh's spec, 2026-10; session part sketched)

Built: a history per document ("N changes", teal, top-right), undo / redo aware; a click
diffs that state against now on the current graph (added green, changed amber, removed
red ghosts, moved at 25%). Left:

- **The git half of the list**: `git log --follow` of the file under the session's states.
- **Pick a range** (click + shift-click) and diff its two ends, not only "that state vs now".
- **A 2-way view in its own tab**: old left, new right, scroll and zoom in step; a text
  2-way view as the fallback (and for non-Lua files). This is the first editor plugin.
- **Later**: the same view reviews a peer's patch (admin nodes), and "revert this hunk".
- **Open questions**: git from where (a `git` on PATH, or reading `.git`); a moved node's
  pairing when its title changed.



## Open: editor plugins, each in its own tab (r-lyeh, 2026-10)

- A plugin is Lua that runs and renders in its own Lite tab, like the node graph (a View:
  update / draw / input, get_state for the workspace). Candidates: the graph diff,
  animation graphs, mesh viewer, terrain tools.
- What it needs from us, kept small: a folder (`plugins/<name>/init.lua`), a way to open its
  tab for a file or a node (RMB menus, a file type), the host bridges (probe, breakpoints,
  world file, the world's tree).
- Open question: drawing beyond Lite's 2D, i.e. a texture from the game renderer drawn
  into the tab (meshes, terrain).
- Built 2026-10: `hexedit` (any size, 1 MiB chunks), `particles` (.pfx, presets),
  `sfxr` (.sfx, the original synth ported to Lua, presets). Their tabs share
  `canvas.ui` (a side panel: sliders, checkboxes, choices, colours, buttons).

### Next plugins (annotated, r-lyeh 2026-10)

Built 2026-10: a simple **tilemap editor** (`plugins/tilemap`: tiles, layers, a stamp,
rect, fill, a CC0 tileset of our own), then auto-tiles, areas, splines and the TMX
importer. Still open from the map editor below: heightmap brushes, tiles stamped along a
spline.


**Map editor** (`.map`; inspiration: Sean Barrett's stb_tilemap_editor.h, public domain:
its layers, the palette on the side, properties per tile, its undo buffer).
- Tiles: a tileset (an atlas or one picture cut in N x N cells), layers, paint / erase /
  fill / pick / rectangle, flip and rotate per cell, a property bag per tile kind
  (solid, damage, a class to spawn: `/classes/...`).
- Auto-tiles: a tile kind that picks its picture from its neighbours (the 4-bit and 8-bit
  47-tile "blob" rules; Wang tiles later), so walls, water and paths draw themselves.
- Splines: Catmull-Rom / Bezier paths as nodes (roads, rails, patrol routes), sampled into
  the game as points; tiles can be stamped along one.
- Areas: polygons and rectangles with a name and properties (spawn zones, triggers,
  camera bounds, music regions): the game gets them as nodes with a `shape`.
- TMX importer: Tiled's `.tmx` / `.tsx` (XML; CSV, base64 and zlib/gzip layer data;
  object layers -> areas; tile properties) into a `.map`.
- Heightmap brushes, even though the view is 2D: a height per cell (raise, lower, smooth,
  flatten, noise; brush size and strength), drawn as shading / contour lines, and kept for
  a 3D view, lighting, or line-of-sight later.
- Predefined tiles: a 256 x 256 sheet of 16 x 16 tiles in the layout of Minecraft
  classic's terrain.png (grass, stone, dirt, wood, water, lava, sand, leaves, glass ...).
  Not Minecraft's own pictures (Mojang's, not ours to ship): our own, or a CC0 set
  (Kenney's), drawn to the same grid so its slots and auto-tile rules match.
- The game side: a `tilemap` component that draws a `.map` (one draw per visible chunk,
  the atlas's sheet) and answers `solid(x, y)` / areas for systems.

**Sequencer** (`.seq`): a timeline of tracks (a node's property keyed over time with
curves; events: play a `.sfx`, emit a `.pfx`, call a system; camera moves), scrubbed with
the game paused, played by a `sequence` component. Cutscenes, attract modes, a level's
scripted moments. Shares the timeline's look with the editor's own bar.
*Queued (r-lyeh, 2026-10)*: after the network work and peer IDs. *Someday* (r-lyeh, 2026-10).

**Viewers that edit**: meshes (`.obj`, `.gltf`/`.glb`: wireframe and flat shaded in Lite's
2D for now, orbit, the bounds, the counts; LODs listed, generated by simplification, the
distance each switches at), animated meshes (skeletons, clips: play, scrub, rename, trim,
loop, blend times) and Aseprite files (`.ase`/`.aseprite`: layers, frames, tags as clips,
durations; edit tags and timing, export to an atlas with the frames named for the game).
All need the open question above for a real 3D view: a texture from the game renderer.


### More plugins (annotated, r-lyeh 2026-10)

**Voice generator** (text-to-speech): a tab where a line of text becomes a sound file
for the game. In: a character (male / female; child / mid / elder; human, robot, ent,
orc...), a mood, a free description, the text, and optionally a sample voice to mimic.
Out: `.wav` (PCM or IMA ADPCM) or `.flac` in the game's assets, played like any `.sfx`.
How hard: the tab itself is small (the sfxr editor is the pattern: fields, Generate,
Play, Save). The work is elsewhere:
- Who speaks. Third-party AIs (cloud TTS services with voice design and cloning; local
  models such as Piper or an XTTS-like one) each have their own API, keys, prices and
  terms. A provider layer (`provider.lua`: one per service) keeps them swappable.
- Getting there. Lite and the runtime speak UDP / plain TCP, not HTTPS: either call
  `curl` as a process (it's on Windows 10+, macOS, Linux) or a local model's own
  server on localhost. No TLS of our own.
- Non-human voices: a human voice from the service, then our own effects in Lua (pitch
  and formant shift, ring modulation for robots, a slow low pitch and reverb for an
  ent, distortion / growl for an orc): presets on top, also usable on recorded lines.
- Files: WAV and IMA ADPCM writers are a page of Lua each; FLAC needs an encoder (a
  simple one: fixed predictors + Rice codes, no LPC search, is a few hundred lines).
- Mimicking a voice: only with the speaker's consent (most services require it too);
  the tab should say so and keep the sample out of exports.
Estimate: one provider via curl, the tab, the effects and WAV / ADPCM: a few days; FLAC
and more providers after.

**Text generator** (prompt-to-text): narration or dialog from a prompt (a scene, who's
in it, their moods, the length), by an LLM (a cloud API, or a local one, e.g. a
llama.cpp server). Out: a `.dialog` file the dialog editor opens (lines, choices,
topics), or plain narration text; then the voice generator can speak it. Shares the
provider layer and the curl transport with the voice generator. The game's own facts
(names, places, the rules data) can go in the prompt so lines fit the world.

**Localization** — *built 2026-10* (plugins/localization, runtime/loc.lua; `.mo` and per-key
stale marks still open): (`.po`/`.mo`, `.csv`): a table of keys x languages; text with plurals
(gettext's plural forms per language), and per-language assets: textures and sounds
(a key that names a file, e.g. a sign's picture, a voiced line). The game asks
`w:tr("key", n)` / `w:asset` resolves the localized file first; the language comes from
the settings. The tab: missing / stale entries, the longest translation per key (to
check it fits), import / export of PO and CSV.

**Navigation meshes** — *someday* (r-lyeh, 2026-10; after pathfinding, which is in) (Recast-like, our own take): sample the scene's height on a
regular grid along each of the 3 axes separately (X, Y, Z); voxelize the result; slice
the voxels into walkable horizontal 2D surfaces; simplify each slice so it encodes as
closed polygons; drop polygons too small for the player's radius; merge slices a step
apart into one walkable level when the step is within the player's max foot elevation
(stairs, ledges). Out: polygons per level and their links (steps, drops), drawn over the
map in the editor, saved as data for the game. Settings: cell size, the player's
radius, height and max step, max slope.

**Pathfinding** — *built 2026-10* (runtime/path.lua, the tilemap's Path tool; nav meshes: above,
someday): A* over a grid (a tilemap's solid cells), a nav mesh (above: polygons,
then string-pulling / funnel for straight paths) or any graph of nodes; jump point search
for big grids; flow fields for many units heading one way; path smoothing. Runtime
`w:path(from, to, opts)`; the editor draws a path between two picked points, and the
costs.

**Boids, swarms, flocks** — *built 2026-10* (plugins/flock, runtime/flock.lua, games/flocking.lua): separation, alignment, cohesion, plus goals, obstacles
(the tilemap's solids, the nav mesh's edges), leaders, predators and fleeing; a
spatial grid so hundreds stay cheap. A component (`flock = { ... }`) with its weights,
edited live with sliders in a tab that previews a flock (like the particle editor).

**Options menu** — *built 2026-10* (plugins/options, runtime/options.lua, games/hop;
round two: mouse, pad, key bindings, full screen, ESC; still open: a language item, more window settings).
(In the style of UE5's Lyra settings screen, or similar): data
describes a tree two levels deep at most: sections only, or tabs then sections. Widgets:
bool, enum (a list), button (an action), float slider (min, max, dead zone), text box
(editable, max length, passwords too). Three global buttons: Reset (defaults), Apply,
Discard. Values saved with the game's settings (config/, savegames), applied live
where they can be (volume, language, key bindings). The plugin edits the tree; the
game draws it with its own look (a component + a system, gamepad and keyboard friendly).

**Procedural materials** (annotated, r-lyeh 2026-10; inspiration: Rodolphe Suescun's
Material Maker, MIT, on Godot; Substance Designer's way of working): textures made from
nodes, no pictures needed: noises (value, Perlin, Voronoi / cells, fbm), patterns
(bricks, tiles, weaves, gradients, shapes), filters (blur, warp, blend modes, levels,
colourize by a gradient, edge detect, slope blur), and from a height map the PBR set:
albedo, normal, roughness, metallic, ambient occlusion. Everything tiles seamlessly.
Built on our material editor (`plugins/materials`: canvas.GraphView, ties, Align):
a node shows its picture in itself (a thumbnail), the result on a lit sphere or a
plane; rendered per pixel in Lua at small sizes (128..512, in a thread, like the sound
graph), later as a shader. Export: the maps as `.png` beside the file (feeds the
tilemap's tileset, a sprite, texture synthesis); a seed per node for variations.

**Texture synthesis** (annotated, r-lyeh 2026-10): more of a picture from a small
sample: a seamless, tileable texture of any size, variations of a tile, holes filled
(inpainting). The classics, all from their papers: Efros & Leung (1999: pixel by pixel,
the best match of its neighbourhood), Wei & Levoy (2000: the same, multi-resolution and
fast), image quilting (Efros & Freeman 2001: patches overlapped, cut along the
least-difference seam: the one to start with), PatchMatch (Barnes et al. 2009: random
search for matching patches, fast enough to be interactive). Embark Studios'
texture-synthesis (Rust, MIT / Apache-2.0) as a reference. A `.texsynth` tab: the sample,
the output size, patch size, overlap, seed, tileable; the result as a `.png` beside it
(a plugin that feeds others: a tileset, a material's texture).

**Markov chains** (annotated, r-lyeh 2026-10): generators trained on examples: names
from a list of names (letters, order 2-4), barks and short lines from a dialog's lines
(words), level rows or rooms from painted ones (tiles), melodies from a few tunes (notes).
An `.markov` tab: the training file(s), the order, what a token is (letter, word, tile,
note), a seed, how many; outputs kept as a list, a `.loc` / `.dialog` / `.tmap` / `.seq`
(feeds other plugins); games use them too (`w:generate("markov", ...)`, seeded:
deterministic for replays and peers). Backoff to a lower order when a context was never
seen; never output an example as it was (an option).

**Wave function collapse** (annotated, r-lyeh 2026-10): maps that look like a sample.
Maxim Gumin's WaveFunctionCollapse (2016, MIT): the overlapping model (every N x N
pattern of a sample image or a painted `.tmap`, and which may sit next to which) and the
simple tiled model (tiles and their allowed neighbours, by hand); each cell starts as
every pattern, the one with the least choices is collapsed (weighted by how often it
appears), the constraints propagate; a contradiction restarts (or backtracks). Paul
Merrell's model synthesis is the earlier, related work. A `.wfc` tab on the tilemap:
the sample map, N, symmetry, periodic edges, fixed cells (a border of walls, an
entrance), seed; the result a `.tmap` (a plugin that feeds others, like dungeon and
terrain; auto-tiles after it).

### Backlog (r-lyeh, 2026-10)

- **Tutorial**: built (2026-10, games/tutorial.lua, FEATURES.md): sixteen cards, English,
  Spanish, French, each card beside the editor's ring (w:point_at's note), live edits,
  the node graph beside the text, a value changed and two nodes wired (speed = fast),
  Restart to run it.
  Next (annotated, r-lyeh 2026-10; *on hold*, r-lyeh 2026-10): **a card per plugin**, each opened from the main
  menu's category, its card waiting for one small thing done in it: paint a few tiles
  (Levels > Tilemap editor), write a line of dialog (Gameplay > Dialog), make a sound
  (Audio > sfxr or Sound graph), add a language (Gameplay > Localization), a particle
  effect (Graphics > Particles); a short side tour after the main one (cards 17+), or
  its own `games/tutorial_plugins.lua`, so the first one stays short.
- **Step mode**: built (2026-10; FEATURES.md).
- **Networking**: on hold (r-lyeh, 2026-10: "not now").
- **Fade setting**: dropped (r-lyeh, 2026-10).

- **Fonts**: built (2026-10: `text = { font = "sans" | "x.ttf", size, align, fallback,
  shadow }`, w:text_size). The tutorial no longer draws text in the game (its cards are
  the editor's notes). Round 2 built (2026-10): wrapped, turned and sheared with its
  node, `xform.shear`, the options menu in a font.
- **Sequencer** (above): on hold (r-lyeh, 2026-10).

## Open: other languages (annotated 2026-10)

- **Hurdy**: stays as it is (code leaves, `.hurdy` files, syntax highlighting). Not
  integrated further for now: no graph, no breakpoints in hurdy.
- **Teal**: built (2026-10, FEATURES.md: `.tl` scripts, leaves and modules; type
  errors as warnings; games/blocks.tl). Then (2026-10): types across modules
  (a world's Teal module checked first, its users see its records) and the
  node graph of a `.tl` (types on the pins). Open: Teal's declarations as
  nodes in the graph (a record's fields), an edit in the graph writing types
  (a new local's `: T`), the types of a folder world's modules across
  files, a console in Teal.
- **TypeScript → Lua, at some point** (r-lyeh). Likely TypeScriptToLua (tstl). It's a Node
  tool, so it's a build step outside the process, not an in-process compiler like hurdy:
  `.ts` saved → tstl → `.lua` next to it (or in a cache) → our hot reload picks it up.
- What any language needs, per language:
  1. a compiler to Lua (in-process via `ecs.languages[ext]`, or external as above);
  2. a line map (Lua line → source line) for errors, breakpoints, the probe;
  3. a rule for an `ecs.system` body in that language;
  4. Lite syntax highlighting.
- The node graph stays Lua-only; a transpiled file could be shown as the Lua it became,
  read-only.
- **The graph for other languages** (discussed 2026-10, r-lyeh asked: Hurdy, Teal, and
  others later; not built). One graph, a front end per language: the graph, its layout,
  drawing, wires and selection work on our node kinds (statements, expressions, their
  text ranges in the file); each language gives `parse(text) -> those, with ranges`
  and `emit(kind, parts) -> its text` (a local, an assignment, a call, a value: what
  an edit in the graph writes), and its comment syntax for our tags (`--@node`, ties).
  Edits keep rewriting only the text they touch, in that language. Today
  plugins/nodegraph/luaparse.lua is the Lua front end and edits.lua writes Lua: the work
  is that boundary (edits.lua through `emit`), then a front end each. Teal first: a
  superset of Lua (type annotations, records, enums, generics), so luaparse extended to
  read them (or Teal's own tl.lua parser, MIT), its types shown as the pins' types; it
  compiles keeping its lines, so breakpoints and the probe map 1:1. Hurdy after: its own
  parser, its line map for breakpoints and the probe. TypeScript (tstl) later the same
  way.



## Open: multiplayer, still simulated

Built (2026-10): the Players button (1..4, RMB quarters toggle anyone, player 1
too: a server alone), split views by quarter over net.sim, the Network button (0..100%,
5 presets blended), ownership by tags that changes hands (`by = 2`: player 2's while it
plays), prediction per node (`predict = true`, corrected by the owner's states).

### Network plan (after Gabriel Gambetta's "Fast-Paced Multiplayer", 2026-10)

His series, in one line each: (I) the server is the authority, clients send inputs and
draw what it says; (II) the client predicts its own player from its inputs, numbers them,
and when the server's state comes back (with "the last input I applied") resets to it and
replays the inputs not yet applied; (III) everyone else is drawn in the past, interpolated
between the two last server states, never guessed; (IV) the server judges an action (a
shot) against the world as the shooter saw it: rewound by its lag and interpolation delay.

Where we are against that: (I) yes, the host is authoritative for `by = 1`, and a player
for what it owns. (II) partly: we predict, but by comparing with our own guess from "half a
round trip ago" (a guess of the age), with no input numbers and no replay; inputs travel as
held-key *state*, so a tap shorter than one send can be lost. (III) no: what isn't
predicted snaps to each new state. (IV) no, but the timeline already keeps the past.

The plan, easiest first:

1. ~~**Ghosts**~~ (built 2026-10: the Network menu, RMB): in each peer's view, the owner's last state drawn faint (Gambetta's demo
   "show server positions"), toggled from the Network tooltip / RMB. Needed to see
   everything below.
2. ~~**Per-player links**~~ (built 2026-10: P1..P4 line in the Network menu; `sim:link`): each player's own quality (one on a bad link), and cut / heal a
   link (net.sim has `cut` / `heal`). The quarter of the Network icon under the mouse?
3. ~~**Send rate**~~ (built 2026-10: default 20/s, the Network menu; `replica.rate`): owners send at N Hz (default 20), not every tick; the Network tooltip
   shows it. Makes (5) visible and saves bandwidth.
4. ~~**Frame stamps**~~ (built 2026-10: times and the clock offsets; fixed 60 Hz ticks in a session, numbered by each peer's commands; "clock" messages say which time of yours I show and my latest command): every patch carries the owner's tick number and game time; each peer
   keeps the offset to every other peer's clock (from patch / ack pairs). The base for 5-8.
5. ~~**Interpolation**~~ (built 2026-10: `interp = true`, by the sender's time, `snap`; pong and asteroids use it for other players) (`replicate = { interpolate = true }`): non-owners keep the last
   timestamped states and show the node between two of them, one send interval (+ jitter)
   in the past. For what isn't predicted (others' paddles in a game with free movement).
6. ~~**Inputs as numbered commands**~~ (built 2026-10: `{ by = N, cmd = true }`, resent until acked, one a tick on the host, `ack` in each state) **Inputs as numbered commands**: a player's input node becomes a short list of
   `{ seq, held }` since the owner's last ack, applied by the owner one per tick in order;
   the owner's states say the last seq it applied per player. No tap is lost.
7. ~~**Reconciliation**~~ (built 2026-10: `{ by = 1, input = N }`, `w:rerun`; pong's paddles, asteroids' ships) **Reconciliation** (`predict = "inputs"`): for nodes driven by my inputs but owned by
   the host: on the owner's state, reset to it and re-run the node's per-node systems for
   my inputs it hasn't applied (needs a `w:tick` that runs per-node systems only, on one
   subtree: no once-systems, no side effects). Deterministic enough for pong; documented
   limits (randomness, other players' interference).
8. ~~**Exact age for the rest**~~ (built 2026-10: the sender's stamp on our clock; plus the star) **Exact age for the rest**: `predict = true` (the ball) compares with our guess at the
   owner's stamped frame instead of half the round trip: no bias at bounces.
9. ~~**Events, not state**~~ (built 2026-10: `w:event`, `on_event`, net `events`; asteroids' sparks) **Events, not state**: one-shot reliable messages (a sound, "left wins", a hit) from the
   owner only, so peers don't predict them (today a peer that simulates the ball would log
   its own "wins"). Irreversible things (a score, a death) wait for the owner (they do now).
10. ~~**Bandwidth**~~ (built 2026-10: component deltas, interest per scope, priorities + budget, lean commands; field-level and per-node interest not yet) **Bandwidth**: send only the scopes a peer cares about (interest: distance, view),
    priorities per scope, field-level deltas (now: node-level), measured in the tooltip.
11. ~~**Lag compensation**~~ (built 2026-10: `w.net:as_seen`, `seen`, `hold`; pong's ball judged by what player 2 saw) **Lag compensation**: an action carries the player's view time (its frame minus its
    interpolation delay); the host rewinds the nodes involved to that time (from the
    timeline's snapshots), judges the action there, applies the result now. Favors the
    shooter, as he notes.
12. **Real transport**: UDP sockets, then WebRTC data channels, behind net.sim's endpoint
    interface (id, send, recv); a relay for NATs that refuse.
13. **Host migration**: the host leaves, another player takes `by = 1` (it has the world:
    it predicted it), the others reconnect to it. The p2p step: no server to keep.
14. **Trust**: the host validates inputs (speeds, rates), patches are signed, admin nodes
    review other games' patches (never their own): the proposal queue below.

**Next (decided 2026-10): classic multiplayer first, p2p much later.** (6) numbered
inputs and (7) reconciliation are built (2026-10), on fixed 60 Hz ticks; (8) exact
ages for the rest (the ball) is next, with a real star (below). With them the topology becomes a star: players send inputs to the host
only, the host simulates and sends everyone the state (today: a mesh, each owner sends
its own nodes to all). p2p (host migration, trust, no host) comes after, when lag
compensation, interpolation, reconciliation and prediction are solid.

Later, apart from the plan:
- Proposal queue for admin nodes: edits to shared nodes become pending patches; an admin
  (never one of that game's own) views the diff and accepts or rejects it.
- Ownership colouring in the tree (mine / peer / shared / admin-reviewed): game data,
  not live co-editing.
- Peers' debug draw in their own views (now: the host's only).
- Enforce reloads every received scope each tick, and prediction keeps a copy per tick:
  fine for pong, measure on big games.



## The layout (agreed 2026-10; long names 2026-10)

`/assets` asset folders, `/data` everything else, `/classes` components' defaults,
`/objects` (saved), `/systems` (a node each, its order), `/entities` (spawned while
playing, never on disk), `/tmp` temporaries (never saved / sent). Built: the engine
rules, pong, snake, scene1 and scene2 (script and folder; the ships shoot: /entities/shots),
the tests, the new-project template, the tree (every root, in that order; +/-
branches; /classes dimmed, /entities /tmp marked). Next:
1. The property panel and /classes: inherited fields, differs, types kept, "used by",
   members described ({ type, value, min, max, options, container, values }: no
   more `meta`), the class panel (a block per member: rename / remove, type, kind,
   values drop-downs, default, min / max, options), + member (a name: a bool),
   + class, built-in int/number/string/bool/color, collections (+ item, + key, RMB
   out), the graph reading /classes, nodes' own typed fields (meta), + object /
   + data / + child, + system, the tree's menu (rename / duplicate / delete), the
   graph reading a node's meta. Next: node-typed fields following a renamed node
   (today they keep the old path), drag a node onto another parent (re-parent), keys of a class type (sets / maps),
   member order (today: by name; UE keeps the order you made them in), a member's
   tooltip / description text, a class extending another live (today "boss ship"
   copies once; a `base = "ship"` could keep boss following ship's upgrades), LuaLS
   annotations generated from /classes (editor autocomplete for students), a colour picker
   (the graph has one: share it once the tab is a Lite view), a vec2 type (x, y as
   one row), a class's fields edited apply to nodes that don't override them
   (done: never-overridden values upgrade), "remove this component", overrides
   tracked explicitly (today: "differs from the class" decides, so setting the very
   same value doesn't pin it). Asset folders
   (`/assets/player`: one item, its files and their kinds listed; nodes refer to
   them by path, later by hash).
2. Draw order (see below).

"Classes" for students (r-lyeh, 2026-10): a class here is a component's defaults
(`/classes/shot` = what every `shot` starts with), data only, no functions, and a
node can have several. Close enough to what students expect from a class (a
blueprint) to be the friendlier word; the docs say "a class = a component's
defaults" once, and the code keeps `n.c` (components).

### Draw order (discussed 2026-10; built 2026-10 without y-sort and /classes defaults)

Today: tree order (the live roots /entities then /objects, then each subtree by rank
and name), so /entities (bullets) draws under /objects. Proposal, like /systems' order:
- A `layer` component (a name), inherited down the tree (a ship's flame is in its
  ship's layer unless it says otherwise). Unset: "default".
- One list gives the layers' order: `/data/layers = { "bg", "default", "fx", "hud" }`,
  shown in the tree and dragged to reorder like /systems. Unlisted layers after, by name.
- Within a layer: tree order. Later, per layer: `{ "units", sort = "y" }` (2D y-sort)
  or `z` for the odd exception.
- /classes gives defaults, not the order: `/classes/bullet { layer = "fx" }` and every
  spawned bullet is in fx. Sorting /classes or /assets themselves would tie order to
  types, but one type can need two layers (a ship and its shadow) and two of its
  instances can differ.
- Picking follows for free: after `bounds` (smallest first), it takes the last drawn.

### scene2 as an Asteroids clone (r-lyeh, 2026-10: later; built 2026-10 as games/asteroids, see FEATURES.md)

The solar system as the background; the player's ship against other ships and
asteroids that split at every shot (big -> 2 medium -> 2 small -> gone). Fits the
layout: `/classes/asteroid` (size, hp), `/entities/rocks/*` and `/entities/shots/*`,
systems `collide` (shots vs rocks / ships), `split`, `wrap` (leave one edge, come
back at the other). A good first multiplayer game too (two ships, `by = N`).

### The left tab as a Lite view (asked 2026-10; built 2026-10)

Built (r-lyeh: "the earlier the better"): Lite draws the tree (its filter box, the
lines, fold boxes, thumbnails, the profiler's bars) and the properties (scrubbing,
sliders, typing a value, drop-downs as Lite's menus, Save / Undo, drag to reorder,
the split line) in editor/3rd/lite/data/plugins/sidetab.lua, on Lite's surface left of
its pane (`core.side`, drawn every frame, whatever the view). The data stays in the
viewer's Lua state: `host_world(fn, ...)` calls `viewer_outline`, `viewer_props`,
`viewer_tree_*` there (values copied between the two states), `host_tab(cmd, ...)`
does the host's part (select, Save / Undo, open a source, the profiler, the split,
the font) (editor/side.h). editor/tab.h went from about 1360 lines to 300 (what's left:
selection outlines, the tree's actions, opening a source). Still C: the toolbar above
the tab, the bottom bar, the project launcher, the dev overlays. Not done: docking the
tab like Lite's own views (it stays where it is), and the game-only view still has no
tree.

## Open: ECS core, worth taking from tiny-ecs (compared 2026-10)

tiny-ecs (bakpakin/tiny-ecs, MIT, one file): entities are plain tables, systems
pick them with filters and keep their own cached lists. Ours is a world model
first (paths, folders on disk, snapshots, diffs, replication, live code); its
speed and its system API are what's worth borrowing, on top of our paths,
without changing the file format:

1. ~~**Filters with cached lists.**~~ (built 2026-10) A system may declare
   `filter = { all = { "xform", "vel" }, none = { "frozen" } }` (and `any`);
   the world keeps each such system's matching nodes, updated when a node
   gains or loses a component (spawn, remove, a component set to nil), so a
   tick walks a list instead of `w:select` + checks. Path globs stay for
   what's about place (`/objects/*`). Measure first: asteroids' AI vs AI
   test (runtime/tests/asteroids.lua) as the benchmark, then a stress world
   of a few thousand entities.
2. ~~**onAdd / onRemove per system.**~~ (built: on_add / on_remove) Called when a node enters / leaves its
   filter (an explosion when a rock is removed, a sound when a ship spawns).
   Must be deterministic (p2p, the timeline): in the cached list's order.
3. ~~**Deferred structure changes.**~~ (built: lists worked out between systems) Spawns and removes during a tick are
   queued and applied between systems (or at the tick's end), so a system
   can remove what it's iterating. Today that works by luck (w:children
   copies); make it a rule, and say which: between systems is what tiny-ecs
   does (world:refresh).
4. ~~**interval.**~~ (built) `interval = 0.5` on a system: it runs every 0.5 s of game
   time, with the time since its last run as dt (spawners, AI thinking,
   autosave). Game time, not wall time: replays and peers agree.
5. ~~**active = false.**~~ (built: in code, or an `active` component) A system kept but not run (debug systems, pause
   menus), toggled from its props row.

Not worth taking: entities without identity (we need paths for saving,
diffs and the network), systems as free tables outside the world (ours are
nodes: saved, edited, hot-reloaded), its metatable-free classes (we have
/classes).

## The node graph as a project plugin (done 2026-10)

It's `plugins/nodegraph/` now, a project plugin like the texture viewer:
1. Done: `editor/3rd/lite/data/plugins/tabflip.lua`: the flip icon, its tooltip and
   click, for any kind (the graph's, the markdown preview's).
2. Done: `editor/3rd/lite/data/plugins/tabmenu.lua`: every tab's right-click menu
   (close, copy path, browse, the kind's toggle).
3. Done: a plugin may be a folder of modules: `P.require(mod)` and `require
   "plugins.<name>.<mod>"` find `plugins/<name>/<mod>.lua` (a searcher in
   `data/replay.lua`, ahead of Lite's own: a stale copy left in Lite's
   folder loses). The graph doesn't take `.lua` over: Lua opens as text and
   flips to its graph.
4. Done: the folder moved; its modules keep their names, so the C side's
   hooks (probe, breakpoints, Play's compile check) and the tests' requires
   didn't change; tests.lua / nodegraph_moves / theme_colors read its files
   at their new place. `P.reloadable = false`: it patches Lite too deeply
   to reload live; saving its code says to restart.
5. Done: its settings are `plugins/nodegraph/config.lua` (grid, rebuild
   delay, the flow's colour and fade, the far zoom, the most zoom, header
   colours per kind), edited in the tree or as text, applied at once.

## Open: annotated 2026-10 (r-lyeh)

**A shmup / bullet-hell editor** (inspiration: gerlogu's Bullet Hell Editor,
https://gerlogu.com/documentation/bullet-hell-editor-overview/). Emitters as nodes
(rings, spirals, aimed bursts, waves), patterns as data: count, spread, speed, spin,
acceleration and their curves over time; nested emitters (a bullet that spawns
bullets); a timeline of waves for a stage; previewed live in the tab, scrubbed, and
played by a `bullets` component in the game (pooled, drawn in one batch).
*Started 2026-10*: plugins/bullets (patterns, ships, waves, a boss; previews),
runtime/bullets.lua, the `bullets` component, games/starfall.lua. Not yet: patterns as
nodes (a graph), curves over time (speed, spin), nested emitters beyond one split,
a timeline view of the waves, a path editor (paths are named, built in).
*Queued (r-lyeh, 2026-10)*: next for it: speed / spin curves over time and the
waves' timeline view.

**Plugins that feed other plugins** (procedural generation): a plugin's output is
another plugin's input, a tree of plugins. A dungeon generator writes a `.tmap` that the
tilemap plugin (with auto-tiles) draws; a Minecraft-like generator turns a seed into
blocks (chunks, biomes, noise layers). Each step is a file, so a chain can be cut at
any link, edited by hand and fed on.
*Started 2026-10*: plugins/dungeon (a `.dungeon` makes a `.tmap`) and plugins/chain
(makers, `made_by`, Regenerate / Open source in the tilemap editor). *Then*: auto-tiles
(two kinds: shores, wall edges), plugins/terrain (a second maker: value noise), and
plugins/genview (a generator's tab, shared). *Then*: 47-tile blob auto-tiles (inner
corners; lava and grass too), `w:generate` (games run the generators), and
games/deepisle.lua (a roguelite on a generated island and its dungeons). Not yet: the
Minecraft-like generator (chunks, biomes), chains of more than one link in the UI.
*Deepisle, annotated (r-lyeh, 2026-10)*: co-op multiplayer (2-4 on the island, each
their own hero; the dungeons shared, loot split), or more content (monsters with their
own moves, items and their effects, a boss per dungeon). Not started.

**A SCUMM plugin** (inspiration: Liquidream's SCUMM-8, https://github.com/Liquidream/scumm-8):
rooms, objects, actors, verbs (Look at, Pick up, Use...), an inventory and cutscenes as
data, and the verb-object sentence line; point-and-click adventures. Its dialogs could
come from the dialog plugin.
*Queued (r-lyeh, 2026-10)*: one of this or the quests plugin, after peer IDs.

**A quests plugin** (Ron Gilbert's puzzle dependency charts,
https://grumpygamer.com/puzzle_dependency_charts/): a graph from the end back to the
start, acts, puzzles (boxes) and what they need, the diamonds where branches meet; a
check that every puzzle can be reached and no act can lock you out. The game reads the
chart to know what's open.
*Queued (r-lyeh, 2026-10)*: with the SCUMM plugin (they go together).

**Sound graphs**: a node graph that modulates audio sources (an `.sfx`, a loop): gain,
pitch, filters, envelopes, driven by game values; attached to hitboxes (entering one
plays or fades a graph).
*Started (2026-10)*: `plugins/soundgraph` (`.soundgraph`, rendered offline by
`runtime/soundgraph.lua`; games play them with `w:sound`): oscillators, noise, envelope,
slide, LFO, value, gain, mix, ring mod, RBJ filters, echo, Freeverb, distortion,
bitcrush, a channel vocoder (ours, not voclib: pure Lua); round two: Sample (.wav, .sfx,
.soundgraph), Paulstretch (our FFT), chorus, flanger, phaser, compressor. Then: sources from files
(`.wav`, an `.sfx`), paulstretch and a phase vocoder (an FFT), chorus / flanger /
phaser, compressor, a graph played live in a game (inputs driven by game values,
streamed), hitboxes.
Nodes to have (annotated, r-lyeh 2026-10; licences to check again when built):
- **Paulstretch** (extreme time-stretch: overlapping FFT windows, phases randomized, an
  ambient pad from any clip). Paul Nasca's C++ program is GPL; his Python version says
  public domain. The algorithm is short (window, FFT, random phases, inverse, overlap-add):
  our own Lua / C from the description, with an FFT of our own.
- **Vocoders**: a channel vocoder (two banks of band-pass biquads, envelope followers on
  the modulator's bands driving the carrier's: robot voices, the voice generator's orcs
  and robots), and a phase vocoder (FFT: pitch shift without the speed, time stretch).
  Our own code, from the textbook designs. Or the channel one ready-made:
  [voclib](https://github.com/blastbay/voclib) (Philip Bennefall; MIT-0 or Unlicense, so
  no credit needed; one ANSI C89 header, no dependencies): mono / stereo, bands and filters
  per band to set, how fast it follows the voice, formant shift; real time.
- **Reverbs**: Freeverb (Jezar at Dreampoint: public domain; 8 comb + 4 all-pass filters
  a channel; also as verblib, a public-domain C version), Schroeder / Moorer reverbs,
  Dattorro's plate (from his 1997 paper), a convolution reverb (an impulse response file,
  FFT; slower, the best rooms).
- **Public-domain filters and effects**: the Audio EQ Cookbook's biquads (Robert
  Bristow-Johnson's formulas: low / high / band pass, notch, all pass, peaking, shelves;
  now a W3C note) and their Linkwitz-Riley crossovers; sndfilter (velipso, 0BSD: biquads,
  a compressor, a reverb); one-pole smoothers, DC blockers, a state variable filter, a
  Moog-style ladder (from the published papers), distortion / waveshapers, bit crusher,
  chorus / flanger / phaser (modulated delays and all-passes), echo with feedback, a
  limiter / gate / compressor (envelope followers), pitch-shifting granular delays.
- **From miniaudio** (miniaud.io: public domain, Unlicense, or MIT-0, your choice): its
  low / high / band pass filters (1st, 2nd and Nth order), notch, peaking EQ, low / high
  shelves, biquad, delay with decay and wet / dry, splitter, gainer / fader, panner, the
  3D spatializer (distance attenuation, Doppler, cones), resampler, and its generators
  (sine, square, triangle, sawtooth, pulse; white, pink and brownian noise). Their code
  can be copied as it is (with a line saying where it's from).

**Native C plugins with libtcc**: a plugin written in C, compiled at load with TinyCC
and reloaded live like Lua; first use, a renderer plugin.

**Debugger watches**: right-click a name, *Add watch* / *Remove watch*; the watches
listed as one-liner links in a corner of the code view (click: go to where it's
defined), each value shown, tables expandable.

**Emoji from a font** (the markdown viewer, then everywhere): embed a colour emoji
TrueType font (a COLR or bitmap one, with a licence that lets us ship it) and cache
the glyphs used into an atlas texture; today a handful are pictures of our own
(`plugins/markdown/emoji/`).

**A file browser of our own** (a canvas widget, modal): files and folders, a path bar,
filters by extension, keyboard and gamepad; for the systems where SDL3 has no file
dialog (Ctrl+O falls back to Lite's prompt there today), and for in-game use.

## Open: viewer and tooling

Settings for later (r-lyeh, 2026-10):
- FPS limit values beyond 0 / multiples of 6: -1 unlimited, 1 vsync, 2 adaptive vsync.
- Budgets: the most disk the log may use (MiB: `.output.txt` and its rolls), the most RAM
  the timeline's snapshots may use (MiB: older snapshots dropped, or thinned, past it).

Plain Lua comments in the graph (discussed 2026-10, not built):
- A comment block right above a statement (no blank line between) belongs to it: its
  node shows it as a note above the title (dim, wrapped, clipped to N lines, the rest on
  hover); a comment at the end of a line shows in that node's tooltip (or as a 2nd line).
- A comment alone (blank lines around it) becomes a note node: a box with the text, no
  pins, placed by the layout like a floating block; double-click edits it in place.
- Our own tags (`--@node`, `--@comment`, `--@float`, widget hints) aren't notes.
- The work: the parser keeps comments with their lines; a statement's range grows to
  its leading comments so that every graph edit (move, delete, collapse to function,
  float, split) carries them along; the text edits keep their order with our tags (the
  comment, then the tag, then the statement, or the other way round: pick one).
- Problems ahead: comments inside an expression (`f(a, -- why` / `b)`), several
  statements on a line, `--[[ ]]` blocks of commented-out code (big: collapsed by
  default), a file's license header (a note for the file, not the first statement),
  comment-only edits counted as changes in the diff list (they are text: fine).
- Cost: showing them read-only is small (a day); carried through every edit, more.

1. ~~Headless runs (`--headless --ticks N`) for CI~~: done (2026-10).
2. Textures by content hash: the first real binary asset, p2p-friendly.
3. Layers / draw order, toggled from the tree.
4. Grid and snap for positioning in the game view.
5. Camera follow (double-click a node).
6. A cost bar per tree item (solid background 0..100%), from the profiler.



## Testing like an author (r-lyeh, 2026-10)

Most UI tests start from code already wired; people start from an empty canvas where
everything they add floats.
- `scratch:` tests in nodegraph_ui.lua: an empty file, nodes added from the menu, wired,
  each feature used on them. Add one for every new feature.
- `NG_FLOAT=1|2` on the UI suite: every test's code floats as one block (1) or a block per
  statement (2). Worth a pass after big changes.

## Export: free disk space (2026-10)

Checking the destination's free space before packaging isn't possible with SDL3
as it is: `SDL_GetStorageSpaceRemaining` exists, but for plain folders
(`SDL_OpenFileStorage`) its generic backend returns `SDL_MAX_UINT64` (a TODO in
SDL's src/storage/generic/SDL_genericstorage.c). So the exporter doesn't check.
Later, if wanted: our own few lines per platform (`GetDiskFreeSpaceExW` on
Windows, `statvfs` elsewhere), compared with the export's size (the files are
known before copying: sum them first), and a gentle "needs 12 MB, 3 MB free"
before anything is written. Or when SDL implements it: no code of ours.

## A Game & Watch game, with the atlas (r-lyeh, 2026-10) — done: games/lcd (Parcels), 2026-10

A demo in the style of Nintendo's Game & Watch: an LCD screen with fixed
segments that are either on or off.

- Two full-screen pictures: the LCD **off** (the background, every segment
  faint or invisible) and the LCD **on** (every segment drawn, dark).
- An atlas (plugins/atlaspacker) over the "on" picture says where each segment
  is: frames named `man/left`, `man/middle`, `ball/1`..`ball/12`, `miss/1`...
  Packing isn't the point here; the frames are rectangles cut from one
  picture, so the atlas needs a mode that takes the rects from a source
  image (or a hand-made frames list) instead of packing many files.
- The game draws the "off" picture, then blits only the segments that are
  lit this tick: `image = { "/assets/lcd.atlas.lua", frame = "man/left" }`
  per lit segment, all at the same place as in the "on" picture (each
  frame keeps its x, y: drawn at its own spot, not centred).
- Game logic is a tiny state machine on a fixed tick (a beat: 2..4 steps a
  second, faster as the score goes up), the segments just a set of names.
- Nice for the editor too: a segment editor (click a rect on the "on"
  picture, name it) would be a canvas plugin on top of the atlas.
- Needs: image frames drawn at their own place (an `anchor = "frame"` or
  `at = "sheet"` option), the atlas taking rects from one image, a beat
  helper. Sounds (beeps) would be the first audio.

## Admin nodes: a plan (2026-10)

*Queued (r-lyeh, 2026-10)*: after peer IDs (an ID that is a public key's hash is
what lets an admin node sign a review).

From the project's brief: some peers are privileged and supervise others
(a server-ish role, but they're clients like anyone). They can play, but
never administer their own games: they only review external ones. Online
play (net.udp, players.lua) is in; this is what could come next, in steps:

1. **Identity.** Each editor gets a key pair (Ed25519: monocypher, one C
   file, public domain-ish), kept next to the exe. A peer says who it is in
   `hello` and signs it; the host checks. Player numbers stay per session;
   keys are who you are across sessions.
2. **Games have authors.** A game's `config/` gets a manifest: its name,
   its authors' public keys, its version (the hash of its authored world,
   `w:save('/**', true)`), the previous version's hash.
3. **Changes are proposals.** A new version of an external game is a patch
   (ecs.diff between two saves: we have it) plus the author's signature.
   Peers keep the version they have until a proposal is accepted.
4. **Admins review.** An admin's editor gets a Review tab (a plugin): the
   queue of proposals for games it doesn't author; each shown as a diff
   (the tree, the node graph's diff view), run headless (`--headless
   --ticks N`: no errors, the game's own asserts), then signed: accepted or
   rejected with a note. A peer takes a proposal with enough signatures
   (1 to start; later N of M) from admins who aren't among its authors.
5. **Admins watch sessions.** An admin can join a session as an observer
   (no player, no keys sent): it gets every peer's states like anyone, and
   checks them against the game's rules (a paddle faster than its speed,
   a score that jumped): a report, not a ban, at first.
6. **Who's an admin.** A signed list (keys) shipped with the editor, or
   granted by existing admins (a few signatures). Never your own games:
   the review tab refuses proposals whose authors include your key.

The first useful slice: 1 + 2 + 3 + a review tab that shows and signs (4
without the network): proposals travel later, as files first.

*Built (2026-10)*: that slice. runtime/review.lua and plugins/review
(the Review tab); the keys are the peer keys (Ed25519 in plain Lua,
runtime/ed25519.lua, not monocypher). The manifest lives beside the game,
`<game>.review/`, not in its `config/` (it isn't part of the world, so
proposing doesn't change what it hashes). Admins: runtime/admins.lua and
`REPLAY_ADMINS`. Accepting: 1 admin, any reject blocks. Next here: send
proposals and reviews over the network (a peer asks the host, or an
introducer keeps a queue), more authors (signed by the current ones), N of
M, the observers (5), and a signed admin list (6). Script games: their
changes are source, a proposal would carry the script's text.

## Kept for when we do p2p for real (r-lyeh, 2026-10)

Two pieces to pick up whenever the peer-to-peer work goes on; not now.

1. **The game travels with the joiner.** Today everyone needs the same game
   folder: only the world is sent. The host should send the game's files
   too (assets, modules, systems): named by a hash of their content, so a
   joiner asks only for the ones it lacks; then zipped deltas between two
   snapshots of the tree (both older ideas: "textures by content hash",
   "zip the world, send deltas"). Then anyone can join, not just people
   with a copy.
2. **The first admin-nodes slice** (the plan above, steps 1-3 and a review
   tab): a key pair per editor, a game's authors in its manifest, new
   versions as signed patches, a Review tab that shows the diff, runs it
   headless and signs (refused for games you author). Proposals as files
   first; the network later.

## Ticket: peer IDs instead of addresses (r-lyeh, 2026-10) — started

*Started 2026-10*: 7-character IDs (random, a check character; kept in
`.network.lua`), `join("TJHJDJX")` nearby then through the introducers set
(`introducers(...)`), hosts registered at their introducer by ID. Not yet:
several introducers sharing a directory, a DHT.
*Then (2026-10, [3])*: the ID is the public key's hash (Ed25519 in plain
Lua: runtime/ed25519.lua; the key in `.network.lua`), and it's proven: the
introducer registers an ID only with its key's signature, and a host found
nearby by ID signs the seeker's challenge. Not yet: remembering a peer's
whole key once met (7 characters are 30 bits: someone with a few days of
computing could make a key with the same short ID; a friends list keeping
the full key closes that), the ID in the joiner's welcome (the host proves
itself at the start of a session too), admin nodes signing reviews.

Ports are gone from addresses (ports by name: `join("1.2.3.4")`). Next:
the IP too. Many apps connect to a peer by a short ID (`TJHJDJX`) rather
than `ip:port`. What it would take:

- **An ID per node**: short, typeable, read aloud without mistakes
  (Crockford base32: no I/L/O/U, case-insensitive; 7 characters = 35 bits;
  a check character). Ideally the hash of the node's public key, so the ID
  also proves who answers (no one else can claim it): the start of trust
  between nodes, and admin nodes signing reviews.
- **A directory**: the ID -> where it is now (its candidates, as the
  introducer already hands out). First the introducer itself (rooms are
  already names: `den@1.2.3.4` is an ID with a directory); then several
  privileged nodes sharing it; later a DHT among them (no address for
  anyone to type at all: a few well-known entry nodes built in).
- **Then**: `join("TJHJDJX")`; IDs in the Players tooltip; friends lists.
- To decide: IDs per node or per game session; how long one lives; what
  happens when two privileged nodes disagree.

## Ticket: NAT traversal (r-lyeh, 2026-10) — apart, later

*Started 2026-10*: runtime/nat.lua: an introducer (rooms, what's-my-address,
introductions with candidates, a relay), hole punching from the game's socket,
`--introducer`, `--via`, `join("room@intro")`; NETWORK.md 2.1. From the notes below:
1 (every candidate, at once), 3 (one socket throughout), 4 (what's-my-address).
Not yet: 2 (the host names the primary), 5, 6.
*Then (2026-10)*: port prediction (symmetric routers that count up: the next 12
ports punched) and runtime/portmap.lua (the host's router asked: PCP, NAT-PMP,
UPnP-IGD; TCP in editor/udp.h). pwnat (samyk) looked at: ICMP tricks that need
raw sockets (admin), many networks drop them; not taken. Not yet: the joiner's
router asked too, the birthday trick for random-port routers.

Online play works on a LAN, and over the internet when the host forwards
its UDP port. Getting through home routers without that is its own rabbit
hole: UDP hole punching with the host as introducer (half there: peers
already ping each other as soon as the roster says where they are), a
rendezvous for when the host itself is behind a NAT, STUN to learn one's
public address, TURN-like relaying as the last resort, symmetric NATs,
port prediction, keep-alives tuned to routers' timeouts. IPv6 (supported
now) needs none of it where both ends have it. To be scoped as a ticket.

**Read: [SimpleMatchmaker](https://github.com/thomashenry79/SimpleMatchmaker)**
(C++ on ENet, MIT, 2022-23, ~3000 lines: a lobby server and a client that
gets two players into a peer-to-peer game, then hands the socket to GGPO).
No auth, two players only, no relay. What's worth taking:

1. **The introducer hands out every candidate address.** Each client tells
   the server its LAN addresses (all adapters, skipping loopback and
   169.254.x); the server already sees its public address:port. At start,
   each side gets the other's list (public first, then the LAN ones) and
   **connects to all of them at once**. Both ends sending to each other is
   what opens the routers (hole punching); on the same LAN a local address
   wins instead. For us: the roster could carry `{ public, lan... }` a
   player, and players would ping every candidate, not just the one the
   host saw.
2. **One connection wins, the host says which.** Several candidates can
   connect; the first one player 1 sees becomes the primary and it sends
   `PRIMARY` over it; player 2 swaps its list to match, and the extra
   connections are reset. Connections from addresses that weren't
   candidates are dropped. No guessing on both sides.
3. **The same local port, all the way.** The client binds one port (the
   first free of 6000..6009, so several copies run on one machine), talks
   to the server from it, punches from it, and the game reuses it. A
   router's mapping is per port, so the hole the server saw is the hole the
   peer uses. For us: `net.udp` should keep one socket from the
   rendezvous to the game, not open a new one.
4. **A tiny "what's my address" service** (their IPServer, about 60 lines):
   answers a connect with the address it came from, then disconnects. That's
   STUN without STUN. Any privileged node of ours could answer this; no
   server to run.
5. **A start in two steps.** Both players flag ready (any change aborts a
   start under way); player 1 sends Start, player 2 confirms, both close
   the lobby connections, and the game begins only when every connection
   has closed (so the port is free for the handoff). Neither side starts
   alone.
6. **The lobby as a state machine a connection.** Each connection on the
   server is in one state (waiting for version, local IPs, login; logged in;
   opened a game; pending; joined; kicked), and a message a state doesn't
   expect kicks the client. The version comes first: a client of another
   game or version never gets further. Games carry an opaque blob from their
   creator (rules, map), joiners wait for the creator's approve or eject.
   Close to what our admin nodes will need: a short, explicit protocol a
   reviewer can check.
7. **Ping: one in flight, smoothed, outliers out.** A ping only when the
   last pong came back, an exponential average, samples over 1 s ignored;
   shown in the lobby before the match. (Ours smooths round trips the same
   way, 0.9 / 0.1; the outlier cut is the new bit.)

Not for us: its text protocol (`HEADER:` plus a payload; we have
MessagePack), the C++ variant machinery, and it stops where symmetric NATs
start (no relay: the last resort we still need).
