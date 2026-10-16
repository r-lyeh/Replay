# Changelog

What changed in Replay, month by month (Year.Month), oldest first within a
month. What exists today, in detail: [FEATURES.md](FEATURES.md); what's next:
[ROADMAP.md](ROADMAP.md).

## 2026.09

The first steps, in order:

- The world is a tree of nodes addressed by paths (`/game/players/luigi`),
  components are plain data, systems are named and hot-swappable. Save / load /
  tick by path patterns (`/a/*`, `/a/**`), byte-identical saves, diffs and patches
  with removals.
- A simulated network (latency, jitter, loss, duplicates) and a replica
  that sends snapshot deltas between peers.
- The viewer: SDL3, loads a script, a saved blob or a world folder, ticks,
  hot-reloads, pans and zooms, takes screenshots.
- A world on disk: a node is a folder, a component a `.lua` file returning
  data; edit a file while it runs and the world follows.
- The Lite text editor embedded in the viewer (ported to SDL3), behind the
  game area.
- Inspect: a click on a node in the tree or in the game opens its source
  in the editor at its line. Right-click picks; Alt+right-click picks the class.
- Layout: the tree tab on the left, the game area on the right.
- Picking by `bounds` (boxes, circles), outlines only near their stroke.

## 2026.10

- The bottom bar: Play / Pause, Rewind, Speed, and a **timeline** of the
  session (snapshots every 0.5 s, drag to scrub, values blended in between; the
  frame rate drawn as an equalizer). Our own frame limiter.
- A Lua **console** in the bar (runs on the live world: `w`, `sel`, `ls`).
- **Systems are code leaves**: code is data in the world, so it saves,
  diffs, rewinds and replicates; sandboxed; a broken system stops alone.
- Demos `scene1.lua` and `scene2/` (the same world as a folder).
- A dev overlay (stats, messages, the input pressed), `dd` debug drawing
  from Lua, and `--standalone` (just the game).
- The **property editor** below the tree: scrub numbers, toggle booleans,
  type values, multi-selection.
- **Play / Stop / Save**, play-in-editor style: Stop goes back to the
  authored world; edits made while stopped can be saved, per node too (Save / Undo).
- Script worlds keep their edits as an overrides file beside the script.
- **Pong**, as a folder game and as one script; text components, a
  game-over banner, swept collisions.
- The window's title and icon come from the game; a renamed exe opens
  its own game; a package without sources starts standalone.
- The Log: every message with where it came from (click: go there), Lua
  tracebacks; Lite's tabs get close buttons.
- `order.lua`: the run and draw order of systems and nodes; drag rows in
  the tree to reorder.
- **Hurdy** code leaves (a language that compiles to Lua); `games/snake/`
  and `snake.hurdy`. `ecs.system(function() ... end)` writes systems inline in a
  script. The project launcher: the games in `games/` to pick from.
- The **node graph**: a Lua file shown as a graph, Blender-like, in a tab
  of its own; layout tags (`--@node dx= dy=`) keep where you put nodes; edit
  expressions, rename variables, rewire inputs, add and delete nodes, box select,
  zoom, left-to-right layout; a tab flips between the text and its graph.
- The graph grows: expression nodes and pins as in Unreal, floating code,
  a Start node, table nodes as property sheets (sliders, enums, colour pickers),
  `---@class` / `---@param` / `---@return` annotations for pin names and types,
  typed wires, an Add menu with search, comment boxes, copy / paste / undo, find
  (CTRL+F), variable chips for widely read locals, getters, concat nodes, removable
  pins; every node movable and deletable without losing its neighbours.
- The project is named **Replay**. Settings in `.preferences.lua`, Lite's
  tabs in `.workspace.lua`; the main menu (Log window, settings); a rolling
  `.log.txt`.
- Go to definition, collapsible nodes and functions, collapse a selection
  into a function, pinned references.
- **The probe**: while paused (or in the mixed view), the graph shows which
  wires ran (orange, with beads) and the values they carried; a profiler bar per
  tree item.
- **Breakpoints** (graph and text gutter, F9) with stepping (F5, F10, F11,
  Shift+F11); stops in system setup and in a script's top level too; a banner in
  the game view.
- Split / merge table pins, automatic type conversion on wiring, New project
  in the launcher.
- Input follows the view: the game gets the keys only at 100% opacity.
  `--profile` for frame timings.
- Graph diffs: "N changes" since the file was opened, shown as added,
  changed, moved and removed nodes; follows undo / redo.
- Play uses the editor's unsaved files (they win over the disk).
- **Players** 1-4 over a simulated network, each in a view of its own;
  ownership tags (`replicate`), prediction; the Network button sets how good the
  network is.
- The main menu gains FPS limits, Confirm close, tooltips by the cursor;
  a tab's right-click menu.
- The **layout** of a world: `/assets /data /classes /objects /systems
  /entities /tmp`; class defaults; the tree drawn with lines and folds; Play checks
  that the code compiles first and shows the error.
- **Classes** as a data editor: members with types (int, number, angle,
  vec2..4, color, key, asset, node, ...), kinds (var, array, set, map), ranges and
  options; nodes upgrade when their class changes; New / Rename / Duplicate /
  Delete in the tree.
- The left tab draggable; **Export** (a folder with the exe, runtime and
  game); drop-downs with search; the tab drawn with Lite's font and theme; a light
  theme.
- **Project plugins** (`plugins/<name>/`): the texture viewer, the
  material editor; every right-click menu with a search line; a shared canvas
  API for plugin views.
- Startup rules: no file = the launcher; an asset file opens in its
  plugin. Assets in the tree.
- **Asteroids** (two ships, textures, split rocks) and the `image` component.
- Game modules (`require "name"` from `/data/lib`), `w:owns`, a tree filter.
- Ghosts, per-player network lines, send rate; `/config` and `/saves`
  (savegames); layering of the game and the editor; no console window on Windows.
- Undo for the tree (across sessions too); thumbnails in `/assets`.
- `docs/HELP.md` (how to use Replay); the **markdown viewer**; F1 opens the
  help.
- `/docs` in the tree; tabs that flip between text and a view; the node
  graph became a project plugin; graph settings; a Plugin submenu in every menu.
- The **atlas packer**; panes side by side (Open beside); markdown links,
  images and GitHub's HTML; move nodes in the game view; `--headless` runs for CI.
- **Online play** over real UDP (`--host`, `--join`, the power switch,
  seats); IPv6.
- **Parcels**, a Game & Watch-like LCD game; cut atlases.
- Networking: interpolation by the sender's clock, lag compensation,
  numbered input commands with reconciliation, events, MessagePack and field
  deltas (asteroids: 75 to 14 KB/s), bundles, `config/net.lua`.
- Faster queries and ticks (cached sorted nodes); ECS systems with
  requires / any / none, on_add / on_remove, intervals; draw layers.
- Plugins: hex editor, particle editor, sfxr sound editor, tilemap editor;
  a shared colour picker; Main menu > Plugins; Open tab with.
- A `Makefile` (Linux, macOS, MinGW).
- **Hop**, a one-screen platformer: the `tilemap` component, game sounds
  (`w:sound`), `w:asset`.
- Right-click menus normalized (Open tab with / Open beside with), drawn
  like the node graph's, scroll when long; the Help item shows the version.
- `docs/ISSUES.md`, `docs/LICENSES.md`, a recoloured light theme, the
  gallery (`docs/gallery/`).
- Folders moved: `editor/3rd/`, `plugins/markdown`, `docs/HELP.md`; the
  main file is `replay.c`. `docs/SUGGESTIONS.md`, `docs/CMDLINE.md`; `replay --help`.
- The launcher with arrows, Enter and a gamepad; a new project gets its
  icon; Ctrl+O uses the system's file dialog; `make tidy` cleans everywhere.
- Gamepads in every demo (dpad, left stick, triggers); hop restarts after a
  win; the opacity button is an eye; F1 in a plugin's tab opens its own help.
- Debugging in the text: lines that ran tinted, values of locals on hover,
  "N breakpoints" (click: the next); breakpoints move with their lines; output pin
  values in the graph.
- The graph's Load (code) node; menu items found by aliases; double-click a
  separator to reset it; built-in emoji in the markdown viewer.
- **Orbitbreak**, a Super Hexagon-like game in one file.
- The **dialog plugin** (`.dialog` files as a chart, `w:dialog` for games)
  and **Fairyland**, a room with a fairy to talk to.
- The graph works out values it can: calls of functions that only compute
  (`math.max(...)`), the pins they feed, marked "not run yet" on the stop's line.
- `hidpi = true` (`.preferences.lua`): the editor sharp on Retina displays.
- Orbitbreak: a faster player, slower rings at first, a spark in the middle of every gap; only the rings throb.
- Orbitbreak: the throb is off (`shake` in its state, for music to drive later).
- The opacity eye drawn as a brush-stroke eye.
- `retina` (was `hidpi`), on by default: macOS Retina displays get the sharp editor at once (`retina = false` turns it off).
- Debugging in the text: hovering a variable also says where it got its value (`dt = 0.016   (at line 29)`); watches (RMB > Add watch) top right of the code, tables unfold.
- Dialog charts are editable: move boxes, link lines, add answers and lines, delete, undo (`//@dx,dy` keeps a box's place).
- Dialogs: a line leading back up (`12 -> 5`) ends the talk; the next one starts there.
- Debugging in the text: `v.x` under the mouse shows the field (the letter under the mouse, not the caret's column); a hand over the watches.
- Breakpoints in code that runs when its file loads (a system file's or a module's top level) stop at Play / Rewind.
- Debugging in the text: "at line N" finds the line that assigned a field (`x.y`) before the stop; a dot counts as the field after it (hover, Add watch).
- `runtime/tests/run.lua` (and `make test`): every test suite in one go, on a copy of the project.
- Test files renamed to snake_case (`net_players.lua`, `disk_demo.lua`, `hello_world.lua`...).
- Retina: the game area, the launcher and games played on their own are sharp too (not only the editor).
- Games get the mouse and analog pads (`w.mouse`, `w.pads`), and a `bullets` component (hundreds of small pictures in one batch).
- Single-file games share their art in `games/common/`.
- The **bullet editor** (`.bullets`: patterns, ships, waves, a boss) and **Starfall**, rewritten as a shoot'em up flown with the mouse.
- Starfall: our ship drawn over everything, then the bullets, the boss, the enemy ships; the boss flies down to its place before it attacks (no jump) and moves smoothly.
- Starfall: when you're hit (or the boss changes phase) the bullets fade out, harmless, instead of vanishing; the boss's small aimed shots are slower.
- Starfall: every enemy bullet is a round dot (at least 11 px) with a white glint, so none is hard to see.
- Bullet editor: Import from... (another file's patterns and ships), the play field's size per file, new files saved where the open game reads them; the stage runs from one shared runner (the preview plays exactly what the game does). Starfall plays the stage named in `/data/rules`, its window the stage's field.
- The **dungeon generator** (`.dungeon`): rooms, corridors, doors, torches and clutter from a seed, previewed live; Ctrl+S writes a `.tmap` the tilemap editor opens.
- Plugins can feed other plugins: a generated map remembers what made it, and the tilemap editor offers *Regenerate* and *Open source*.
- Online play through home routers, no port forwarding: run an introducer (`--introducer`, or `introducer()` in the console), host with `--via room@introducer`, join with `join("room@introducer")`. Hole punching finds a direct path; when a router won't allow one, the introducer relays.
- Hosting asks your router to open the game's port (PCP, NAT-PMP or UPnP), so others can often join your address directly; `portmap(false)` turns it off. The port is closed again when you stop.
- Routers that give each destination a new port (symmetric) are predicted: when their ports go up in steps, the other player aims at the next ones, and a direct path opens instead of the relay.
- No more ports to type: each game's ports come from its name (several hosts on one computer take the next ones), and `join("1.2.3.4")` finds the host; the introducer's ports come from its name too.
- On the same network, no address at all: `join()` takes the first host of this game nearby, and `lobby()` lists them.
- Joining through an introducer asks your router to open a port too.
- Peer IDs: every computer has a short ID (`id()`), and `join("TJHJDJX")` finds that host nearby or through your introducers (`introducers("1.2.3.4")`).
- Auto-tiles in the tilemap editor: water gets sandy shores and stone walls get edges as you paint (two new rows of tiles).
- The **terrain generator** (`.terrain`): islands and land from noise, with beaches, hills, snow, bushes and flowers; it writes a `.tmap` like the dungeon generator, whose stone walls now have edges.
- The project launcher no longer lists `games/common/` (the script games' shared art), and a new project can't be named `common`.
- The project launcher lists folder projects first, then single-file ones, each in alphabetical order.
- Games can use the tilemap plugin's own tileset (`plugin:tiles.png`): no copy needed, and Export takes it along.
- The Players button: with the power on, right-click P2-P4 for the hosts nearby (address, ID, who's in) and pick one; the tooltip shows your ID.
- Auto-tiles now have inner corners (47 tiles a kind), and two more kinds: lava and grass.
- Games can run the editor's generators: `w:generate("dungeon", ...)`, `w:generate("terrain", ...)`, and draw a map they made with `tilemap = { rows = ... }`.
- **Deepisle**, a small roguelite: an island and three dungeons made from a seed each game; walk into monsters to fight, weapons wear out, loot chests and bones, clear every dungeon to win.
- Every popup menu now looks and works the same: the main menu, the Network and lobby menus, the tree's menu and the properties' drop-downs open over the whole window, with a search box and submenus, and scroll when the window is small.
- The tree's right-click menu on an asset has *Open beside with >* too.
- Popup menus no longer show bits of a hidden editor tab around them while the game plays.
- The tree and the properties are drawn by the editor itself now (Lite): the same fonts, colours and scrollbars as the code; drop-downs are the same menus as everywhere.
- Every text box (the tree filter, property values, menu searches, the Lua prompt, node graph edit boxes and comments, generator fields) edits like the code editor: Shift selects, Ctrl+arrows jump words, Ctrl+A / C / X / V, undo and redo, click and drag with the mouse.
- Pasting in the code editor pastes what was copied last, even when it was copied in another program.
- The colour picker's hex box and the launcher's new project name edit the same way too; the tree filter's clear button shows a hand.
- Peer IDs are now made from a secret key each computer keeps in `.network.lua`: only that computer can answer to its ID (it signs), nearby and through an introducer. Your ID changes once, to the key's (the log says).
- Games can have authors, and changes become proposals that admins review: `propose("note")` (or the new Review tab) signs a change, admins `review()` it after running it headless, and everyone else `update()`s to the accepted version, even while playing. Admins never review their own games. Proposals travel as files for now (`<game>.review/`).
- Fixed: saving a world loaded from a save file (`return { version = ... }`) wrote nothing.
- Node graph: tie wires together. Shift+right-drag a line across several wires and they run side by side through a tie you can drag around; across a single wire it adds a control point. Alt+click a tie to undo it. Ties are saved in the file.
- A volume button (a speaker) in the toolbar, after the eye: click for 0% / 50% / 100%, the wheel for 5% steps. It sets every sound, the game's and the editor's, and is remembered.
- Markdown preview: `<!-- comments -->` are hidden (also across lines), `&nbsp;` keeps its spaces (indents), and links can have a tooltip: `[text](url "tooltip")`.
- Starfall's score is now how much of the stage you cleared, 0.00% to 100.00%: every ship shot down and the boss beaten (half of it) is 100%.
- The main menu starts with the plugins, grouped by category (Audio, Code, Docs, Gameplay, Graphics, Levels, Online); the editor's own settings (log window, confirm close, theme, thumbnails, FPS) moved into an Editor submenu, then Help and Reset editor.
- Arkanoid: the ball waits on the paddle until Space, can't pass through the paddle or bricks at high speed, bounces off bricks as a round ball, and its angle off the paddle depends on where it lands (and the paddle's motion).
- Markdown preview: links are read as GitHub reads them: several on one line with titles, parentheses inside addresses, and an image inside a link (`[![alt](picture)](address)`).
- The game and the editor fade into each other by themselves: Pause fades the game out over the editor in 2 seconds, Play fades the editor out (the game takes the keys at once), Stop goes back to the editor quickly. Moving the mouse or typing speeds it up; touching the eye stops it.
- Games can play `.wav`, `.ogg`, `.mp3` and `.flac` sounds, with volume, pan, pitch and loops: `w:sound("hit.wav", { pan = -0.5, pitch = 1.2 })`. Up to sixteen at once.
- Music: `w:music("theme.ogg", { fade = 2 })` streams a track and crossfades to the next; `w:music(false)` stops it. Sound effects, music and voices each have their own volume (`w:bus("music", 0.5)`). Sounds pause with the game and stop with Stop.
- Input actions: name your controls in `/config` (`actions = { jump = { "space", "pad a" } }`) and ask `w:action("jump")`, `w:pressed("jump")` or `w:axis("left", "right")`; players can rebind them (`w:bind`), kept on their computer.
- `collide`, ready in every system: overlap tests that say which way to push, sweeps so fast objects can't pass through walls, rays, bounces and a spatial grid.
- The docs and comments now say `replay.exe` (it was `play.exe`).
- Node graph ties, round two: press on a wire and drag across others to tie them (no Shift needed; on empty space it's still the selection box), flow wires can be tied too, and the material editor has ties as well. Tied wires now behave more like real cables: they lie side by side through the tie and ease in and out of it, and the tie turns with the way they pull.
- New options menu plugin: make a game's settings screen (tabs, sections, switches, lists, sliders with a dead zone, text boxes and password boxes, buttons, and Reset / Apply / Discard), try it right in its tab, and show it in a game with `w:options`. Volume sliders are heard as they move, and the choices are saved on your machine. Hop has one: press O or Start.
- Tied wires no longer cross between two ties when you move one of them.
- Ties in the dialog chart too, and Alt+right-drag draws a tie line anywhere in every node editor.
- Options menu, round two: works with the mouse (click, hover, drag sliders) and the gamepad (LB / RB for tabs, A, B or Home to go back), key binding settings, and a full screen setting. In games with an options menu, a short ESC opens and closes it and a long ESC goes back to the editor. Hop's keys can be rebound in its menu.
- Node editors: scrolling or zooming with the mouse still now updates the cursor and the hints under it.
- A tie line started a few pixels inside a wire ties that wire too.
- Full screen (options menu) now scales the game up to fill the screen, and works in exported games.
- Node graph: align, space out and tidy the selected nodes, and save a selection as a snippet to add again from the Add menu.
- New localization plugin: your game's texts in several languages, with plural forms, missing and too-long texts shown, and .po / .csv import and export. Games use `w:tr`, and files in `assets/<language>/` are used first. Options menus can list the languages. Hop speaks English, Spanish and French.
- Pathfinding: `w:path` finds the way around walls (A*, jump point search, flow fields). The tilemap editor has a Path tool to try it, and fairyland's fairy now follows you.
- New flock editor: birds, fish, bats, bees and sheep that flock, flee and avoid obstacles, tuned with sliders as they fly. Try games/flocking.lua.
- Replay now builds with SDL3_ttf (TrueType fonts, used next): Windows ships its DLL, macOS `brew install sdl3_ttf`, Linux `libsdl3-ttf-dev`.
- The project's log file is now `.output.txt` (was `.log.txt`).
- Node graph: *Tidy* moved into the *Align* menu. Pasting a saved snippet no longer leaves stray wires to variables it can't see.
- Ties: wires run straight between two ties, follow nodes and ties while you drag them, and no longer show gaps or beads where their pieces meet.
- Node graph colours: arithmetic is known to give a number (even `speed + gap`), so more pins and wires take their type's colour, and wires blend from the output's colour to the input's (a number going into a string parameter fades yellow to green). The material editor's wires blend too.
- Fairyland: the fairy stays put until you become her friend; then she follows you.
- Node graph ties can be selected: click them or catch them in the selection box, then move them together, nudge them with the arrow keys, align them (RMB > Align) or press Delete to untie them and keep the wires.
- Ties in the material editor and the dialog chart select the same way, and there a drag on empty space is now the selection box (pan with the middle button or the wheel).
- Double-click a wire to add a control point there, in every node editor. Double-clicking empty space no longer re-centres the view (Fit is in the right-click menu).
- Wires are easier to hover and click: the whole length of a long or zoomed-in wire responds, not just spots along it.
- Wires tied through two ties on a slope no longer swap sides and cross.
- New tutorial, games/tutorial.lua ("Light the beacon"): a little game you finish by using the editor. Each step waits until you've done it (Play, pause, pick the beacon, change its oil and its colour, rewind time, change its code, stop and save), and the part of the editor to use pulses yellow.
- Games can hear what you do in the editor (`on_editor` in a system) and point at a part of it (`w:point_at("play")`).
- With Picking on (the toolbar's dashed box), a plain click in the game picks what's under it, in any view; the game doesn't get those clicks.
- The tutorial now also teaches the eye (playing in the mixed view) and picking, and its last step stops the game before saving (saving works when stopped).
- The test runner runs several suites at once (`--jobs`, one per core by default), and catches Lua errors it used to miss.
- Games can draw text in TrueType fonts: the built-in sans, sans-bold and mono, or any font in their assets, with a fallback font for emoji and symbols, centred or right-aligned; `w:text_size` measures it.
- Sound graphs, round two: Sample (a .wav, an .sfx or another sound graph as a source), Paulstretch, Chorus, Flanger, Phaser and Compressor nodes, and a pad sample.
- The tutorial speaks English, Spanish and French (L switches), uses TrueType text, and no longer asks you to change its code or save: it plays the same every time.
- Fixed an error when a text box in the editor (the menus' search, the properties) closed with no other view to go back to.
- New sound graph editor (`.soundgraph` files): build sound effects from nodes (oscillators, noise, envelopes, slides, LFOs, filters, echo, reverb, distortion, bitcrush, a vocoder), with sliders inside the nodes, every change played, and Export .wav. Games play them with `w:sound`, like sfxr sounds. Four samples to start from.
- Turning Picking on while only the editor shows brings the game in (mixed), and Pause / Stop keep it in view while Picking is on; with only the editor showing, clicks go to the editor.
- Flipping a Lua file's tab to its node graph lands on the statement under the text cursor, at a readable zoom.
- TrueType text can have a shadow (`shadow = true`), to read over anything.
- The tutorial: the beacon has an intensity (one 0..1 slider instead of a colour's three values), its cards are bigger and bold, and it has new steps on code: go to a line, see it as a node graph, change a number there, run it, and see the text has changed too.
- The eye is simpler: one opacity for the game over the editor. A click shows the game at your blend value (75%) or hides it; the wheel changes that value by 5% and remembers it. Play goes to 100%, Pause to your blend value, Stop to 0%, each with a short fade. In the mixed view while playing, the keys go to the game until you click in the editor.
- The tutorial teaches live changes: no pause step; the beacon's intensity (to 100) lights it and its pulse speed makes the light pulse, both changed while the game runs. Then it asks for a maximized window and the node graph beside the code, and the speed changed in either one.
- When the game is hidden (the eye, or stopped), a game's pointer can carry its instructions: `w:point_at(name, note)` shows them beside the yellow ring.
- The main menu tints the plugin of the tab you're in and its category (Code > Hex editor), like the ☰ icon while the menu is open.
- New main menu entry Code > Text editor: the text editor's settings (spaces or tabs, indent size, line height, line guide, whitespace, minimap, zoom; remembered), its right-click actions, and every command of the palette in submenus with their keys.
- Code changed while a game runs, saved or not, now takes effect on Restart or on Play after a pause; no need to stop.
- The tutorial's cards are all shown beside the yellow ring now (none drawn in the game), and its steps are reordered: picking on and off before the live edits, the eye before the code, Restart to run the change.
- Step mode: while paused, two buttons at the start of the timeline go one tick back or on (hold them to keep going), and so does the wheel over the timeline; the time label shows the tick.
- The tutorial has a wiring step: connect two nodes in the graph (speed = fast) and Restart to see it run.
- The markdown preview, the atlas packer and the texture viewer no longer repeat "Edit as text" and "Copy path" in their right-click menus (the tab's icon and its menu have them).
- When a system fails while the game runs, an error overlay opens over the game: what failed and where, a click opens the line. It's modal (the game pauses and nothing reads the keyboard, mouse or pads) until you continue. The failing system's rows in the tree turn red. Games can show their own fatal screen there with `w:panic(title, text)`.
- TrueType text now turns, scales and slants with its node, wraps to a width (`width`), and can be slanted on its own (`shear`, for a cursive look). Any node can be sheared too (`transform.shear`). `w:text_size` measures wrapped text.
- An options menu can use a TrueType font: `look = { font = "sans-bold", font_size = 15 }` in its file (Hop's does).
- The tilemap editor has named areas (rectangles, polygons) and splines (curved paths: roads, rails, patrols), each with your own properties; games read them with `tmap` (areas at a point, points along a spline).
- Tiled maps (`.tmx`, with `.tsx` tilesets) open in the tilemap editor and save as `.tmap`: tile layers (CSV, base64, zlib, gzip), infinite maps, and objects as areas and splines.
- A sample Tiled map to try it with: `plugins/tilemap/samples/island.tmx` and its tileset `island.tsx` (CC0).
- Hop's options menu slants the tab you're on (`tab_shear` in an options look).
- Teal (typed Lua) works for games: `.tl` scripts, `system.tl` files in folder games, Teal code leaves and modules. Type errors are warnings (in the console, and the node in amber in the tree: a click opens the line); the code runs anyway. A syntax error stops it, as in Lua.
- A new game in Teal: `games/blocks.tl`, falling blocks.
- Teal modules share their types: `local B = require("blocks")` gives the module's records too (`B.Piece`, `B.State`), checked across; editing the module checks its users again. blocks.tl declares its types once, in its module.
- The node graph opens Teal files (`Ctrl+\` on a `.tl` tab: its graph beside the text): the types colour the pins, and what ran shows on the wires as in Lua.

## 2026.11

- The tree's filter takes patterns: `ship*`, `r?ck` for names, `/objects/*` or `/systems/**` for paths.
- Earlier saves: right-click a node > Earlier saves lists the saves that changed it; pick one to get the node back as it was then. Each save keeps what it changed in the game's `.history` folder (the last 100 saves).
- In a Teal file's node graph, records, enums and type declarations show as nodes, and a local or a function made in the graph gets its types written when they're known.
- Pictures in QOI, WebP and PUG work everywhere PNG does (games, the texture viewer, the atlas packer), and QOI and PUG can be written too.
- New plugin: the sprite animator (Graphics > Sprite animator). Animations frame by frame on a spritesheet: rects, anchors, pauses, events, hitboxes, outline colours, and a line of Lua per frame to pick the next one. Aseprite files open in it. Games play them with `w:anim`.
- Script games' savegames are kept on disk now (`.saves/` beside the script); before, they were lost when the game closed.
- Alt+click on Play plays the game on its own again. Alt+Enter or F11 toggles full screen, and Editor > Full screen keeps it for the next run. Games played on their own get Alt+Enter / F11 for full screen and Cmd+Q / Alt+F4 to quit (a game can take these keys), and keep the mouse inside their window if they're steered by it.
- Games can read the computer's clock (`w:wall_time()`), and whether they run in the editor or on their own (`w.in_editor`, `w.is_retail`).
- The launcher's window can be resized (the list scrolls when it doesn't fit), Teal games have their own colour, and each game's line says what it shows.
- Mochi (new): loads its WebP pictures, starts where it should, saves to disk, and counts the time you were away.
- Arkanoid's paddle follows the mouse too.
- The tutorial's last steps: rewind the timeline, then Resume (no more restart key). It starts from the first card every run, and doesn't ask to pause after a rewind.
- `w:memo(name, value)` keeps a value while the program runs, without writing it to disk.
- Mochi's hearts and flowers are plain text now (`<3`, `*`).
- Every plugin's menu has New and Open... (Open shows only its files).
- Tilemap layers have a draw order (Z), and a new kind: decals, pictures placed anywhere, turned, scaled and flipped.
- Sprite animator: Import... (a picture or an Aseprite file); drag out frames, move and size them (the anchor comes along); drag the anchor anywhere; up to 10 hitboxes, each its own colour (the Hitboxes tool, or hold 1..9 / 0 while dragging); *Jump to* replaces the Flow and Loops fields; the preview shows the outlines. Older `.anim` files open as before.
- After the tutorial ends, Play starts it again. Stopping Mochi no longer marks the game as changed (it saves when Stop is pressed: `"stopping"`).
- The node graph opens without the long pause the first time.
- Sprite animator: a strip of the animation's frames under the sheet, the preview a frame at a time (`,` and `.`), onion skin (O), and hitbox names (a game can ask for `"attack"`). Aseprite slices with other names become named hitboxes.
- Tilemap decals can be any picture, not only a tile.
- Games can read `w.time`, the game seconds so far.
- New docs: APIs.md (every game API, with a review) and 3D.md (the plan for 3D).
- The editor and games draw through SDL's GPU API when the machine has one (Vulkan, Metal), the first step towards 3D; `--gpu off` goes back to the old renderer.
- First 3D: a `camera3d` node draws 3D models (glTF `.gltf` / `.glb`, or a cube, plane or sphere) placed with `transform3d`, lit by a sun and ambient light, as a picture in the 2D world. New demo: spin3d. Drawn on the GPU (Vulkan, Metal) when there's one, else on the CPU, the same picture.
- Sprite outlines are solid lines round the sprite (no dark halo from soft pixels such as shadows). In the sprite animator the mouse shows what a drag does: a hand on the anchor, resize arrows on edges and corners, four arrows while moving.
- Pictures can have outlines (`outline1`, `outline2` in `image`): a sprite animation's frames draw theirs.
- Model viewer: `.gltf` and `.glb` files open in a tab (Graphics > Model viewer): drag to orbit, the middle button pans, the wheel zooms, double-click or F fits. Its panel lists vertices, triangles, size, parts and textures. Changes on disk show at once.
- 3D shadows: a `camera3d` with `shadows = true` lets the sun cast them (GPU and CPU alike). spin3d has them (S toggles), and the model viewer shows the model on a floor with its shadow (G, S).
- Animated 3D models: glTF files with a skeleton play their clips through a new `animator` component (`clip`, `t`, `loop`). spin3d has a bending arm; the model viewer lists a model's clips, plays them (Space) and scrubs them.
- FBX models (`.fbx`) load like glTF ones: meshes, textures, skeletons and their animations. An `animlist.txt` beside a model (`frame: 66-85 Run (Loop)` a line) cuts its animation into named clips. New demo: kgirl3d, an animated character with 26 clips. The model viewer opens FBX files too.
- Blend shapes: FBX face expressions now play with the clips, and games can set them (`animator.morphs = { mouthO = 1 }`). The model viewer has a slider for each.
- MagicaVoxel models (`.vox`) load in games and the model viewer, scene and all. glTF morph targets work like FBX blend shapes. The model viewer can show the skeleton (K), the wireframe (W) and the normals (N), and models show as pictures in the tree's `/assets`.
- The shader build script moved to `editor/tools/shaders.sh`.
- New: a content browser (`replay some/folder/`, or Assets > Content browser) shows a folder's files as tiles with pictures of textures and models and UE5-style colours per kind, a search bar with tags, and actions on each file.
- 3D: clips can cross-fade (`animator.blend`), games can find where a 3D point shows on screen (`w:project3d`), and a right-click picks 3D nodes. In kgirl3d she now blends between clips and has a name tag. The model viewer's M hides the model, to see the bones alone.
- 3D in the editor: hold the right button on a 3D view to fly its camera (WASD, Q/E, Shift, the wheel; R goes back to the game's camera), and the selected 3D object gets a yellow outline.
- Model viewer: clips cross-fade when you click them (Blend, 0.25 s by default), a Sequence plays clips and pauses in order (and loops), and the model has an outline (O).
- 3D picking is exact: a right-click hits what's under the mouse (its triangles), or a `bounds3d` shape (box or sphere) when a node has one. Model viewer: hold the right button to fly (WASD, Q/E), its toggles moved to Alt+letter, the outline starts off.
- Model viewer: the floor no longer moves and grows with an animated model (it's placed where the model stands as read).
- Flying a 3D view (the game view or the model viewer) hides the cursor and keeps it in the window until the right button is let go.
- A transform gizmo in the game view (stopped or paused): W moves, E turns and R scales the selected node with handles (Ctrl snaps), for 2D nodes and 3D ones alike; each drag is one undo step.
- Gizmo: Space steps through move, rotate and scale; 3D gets plane squares between two axes, an orange outer ring that turns about the line to the camera, and a white middle box that scales evenly. A right-click picks only when the game is stopped or paused, and only if you didn't drag (a right-drag on a 3D view flies its camera).
- The game can live in an editor tab: Game > Game view docks it like any other tab (split it beside the code, move it to another pane), with the game fitted to it. While it's open the editor no longer fades out on Play.
- Picking moved to the left button: while stopped or paused, a click selects what's under the mouse, Alt+click its class part, a double-click opens its source. The right button never picks, and while the game plays it never moves the camera.
- Renamed: the `xform` and `xform3d` components are now `transform` and `transform3d` (old games still load; saving writes the new names), and the flags `--stopped` and `--prof` are now `--stop` and `--profile` (the old ones still work).
- Games opened from the launcher keep its flags (`replay --profile` profiles every game you open from it).
- macOS: 3D models were drawn grey and untextured (Metal read the shadow map as the model's texture). Fixed.
- The game view tab: while the game plays, the other editor tabs no longer disappear.
- The game view tab comes to the front on Play, Rewind, a frame step or a timeline click, and the eye button is off while it's open.
- A plugin's New (Dialog, Options, Markdown...) makes the new file right away, beside the game's files, instead of first showing a dialog that looked like an Open prompt.
- The first Pause after starting (a fresh editor) flashed the editor in fully instead of fading it in. Fixed.
- Dragging the timeline's playhead now follows the mouse's X wherever the pointer goes (over the game, the editor, out of the window) until you let go.
- `--profile` now reports each hiccup (a frame of 25 ms or more) with what took the time, and whether the timeline took a snapshot on that frame. The timeline's storage is made up front, and the editor's file scan no longer reads a whole big folder in one frame.
- 3D: animated models are skinned on the GPU (60 animated characters: about 7x faster), and copies of the same mesh are drawn together (instancing).
- New: the foliage editor (Levels > Foliage editor, `.foliage` files): grass, flowers, bushes, rocks scattered over an area in layers, each with its mesh, density, size, clumps and spacing. In a game: `foliage3d = { "meadow.foliage" }`. New demo: meadow3d.
- The editor no longer spends most of each frame on background work while the game plays: its file scan and the node graph's background reading wait until the game is stopped or paused, and a text box's timer no longer spins. This fixes the hiccups after starting a game.
- Foliage in 3D: the foliage editor now shows the scatter in 3D (drag to orbit, wheel to zoom; Above for the old map). A new built-in mesh, `grass` (tufts of real blades), sways in the wind (a layer's Wind) and thins out with distance (Whole up to). The samples and meadow3d use it.
