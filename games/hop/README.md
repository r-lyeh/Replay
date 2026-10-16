# Hop

A very small platform game: one screen, six gems, a door. Its level is a
tile map (`assets/level1.tmap`: open it in the tilemap editor, change it,
save: the game shows it at once) and its sounds are sfxr's (`assets/*.sfx`:
open one in the sfxr editor, change it, save: the next jump sounds so).

- Left / right (or A / D) run, Space / Up / W / Z jump (hold it: higher).
  A gamepad: dpad or left stick to run, A to jump.
- Take the gems; with all of them the door opens: go through it.
- Lava and falling off: back to the start. After a win it starts again in 5 s (space or A: at once).
- ESC, O or the pad's Start: the options menu (your name, jump height, run
  speed, the gems' count, the keys, full screen, the sound's volume;
  Restart). The mouse (click, drag a slider), arrows / dpad / stick, Enter /
  A, Q / E or LB / RB for its tabs, Escape / B / Home back. In the editor a
  long ESC stops the game.

How it's made:

- `objects/level/*`: a node per layer of the map, each drawing it with the
  `tilemap` component (`{ "/assets/level1.tmap", layer = "ground" }`).
  `ground` is solid, `decor` isn't, `items` holds the gems (a crystal tile)
  and the door: the level system turns them into nodes when a round starts
  (`/entities/gem*`, `/entities/door`), so taking one is a change to the world
  (it saves, rewinds, travels).
- `data/lib/hop/module.lua`: the map as the game reads it (`w:asset`), what's
  solid, what hurts.
- `systems/*`: input (the keys, as data), level (a round: the gems), player
  (running, jumping, colliding, sounds: `w:sound("jump")`), hud.
- `data/layers`: the draw order (map, items, player, HUD).
- `config/actions.lua`: jump, left, right and their keys (the menu rebinds them).
- `data/rules`: the numbers (gravity, jump, run speed); `data/state`: the
  round.
- `assets/settings.options`: the options menu (open it in the options
  plugin, change it, save: the menu changes at once); `objects/hud/menu`
  places it, `systems/menu` runs it (runtime/options.lua) and copies what's
  applied to `/data/state`'s `prefs`, which the player and the HUD read.
