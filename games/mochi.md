# Mochi ♡ — Replay virtual pet

A cozy red-panda companion game for [Replay](https://github.com/r-lyeh/replay).

## Install
Copy the `games/mochi.lua` file into Replay's `games/` directory and copy
`games/common/mochi_room.png` plus `games/common/mochi_red_panda.png` into
Replay's `games/common/` directory. Keep the directory structure.

Run from the Replay repository root:

```sh
replay games/mochi.lua
```

## Controls
- `1` Feed
- `2` Play
- `3` Clean
- `4` Sleep
- `5` Cuddle
- `6` Berry treat
- Or click the six on-screen buttons.

## Save data
Replay's `w:savegame("mochi", table)` / `w:loadgame("mochi")` API stores
`{ pet = { ... } }` in `saves/mochi.sav`. Needs, affection, care count,
age-days and play time are saved after actions and every 15 seconds.

## Art notes
- `mochi_room.png`: static 16:9 room background.
- `mochi_red_panda.png`: 4×4 sprite sheet, 384×256 source cells.
  Frame selection is in `games/mochi.lua` and can be retimed there.

The generated sprite sheet has a dark preview backdrop around the character
art in some cells; the PNG's alpha channel is retained. Review the sheet in
Replay's asset viewer if you want to adjust individual frame crops.
