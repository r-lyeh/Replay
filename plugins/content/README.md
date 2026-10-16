# content

A content browser, after UE5's: a folder as a gallery of tiles.

- `replay some/folder/` opens one (a folder that's no game: a game folder,
  with `systems/`, `objects/`, `config/`, `data/` or `order.lua` in it, opens
  as the game). So does the main menu's Assets > Content browser (the game's
  folder), and Open tab with > Content browser on a folder.
- Folders first, then files. A tile shows a picture when there is one (the
  texture itself; a model drawn by the host) or the file's kind, with a strip
  in its kind's colour under it (`types.lua`: UE5's colours — textures red,
  static meshes cyan, skeletal meshes pink, materials green, sounds purple,
  scripts blue, levels orange, folders tan, games orange).
- Double-click: a folder goes in, a file opens in its plugin (or as text).
  RMB: open, open with, show its folder (when searching), copy its path,
  show in the file manager, rename (F2), duplicate, move to trash (DEL: into
  `.trash/` where the browser started, never deleted), filter by its kind,
  new folder, refresh (F5), hidden files, picture size.
- The top bar: back / forward (Alt+Left / Alt+Right), up (Backspace), the
  path's folders (a click goes there).
- The search bar (Ctrl+F): what's typed filters at once; Enter keeps it as a
  tag, its [x] takes it away (Backspace in an empty bar: the last one).
  `type:texture` (or + Type), `*.png`, `**.jpg` (a path below), `ship`
  (fuzzy: its letters in that order), `-tag` / `!tag` (left out). Kinds add
  up among themselves; the rest must all match. With any filter every folder
  below is searched (the first 6000 entries), each tile saying where.
- CTRL+wheel: bigger or smaller pictures; the arrows move the selection,
  Enter opens it.

- `editor.lua`: the tab (runs in Lite)
- `types.lua`: the kinds, their colours and extensions
- `config.lua`: `size` (a picture, px), `hidden` (dot files)
