# Options menu

A plugin of Replay's editor (`plugins/options`): `.options` files, a game's
options menu (its settings screen), in the style of the one in Epic's Lyra
sample (UE5): tabs along the top, sections of settings under them, a line
saying what the focused one does, and Reset / Apply / Discard at the bottom.

- `files.lua`: which extensions open here (`options`)
- `config.lua`: its settings (the preview's size)
- `editor.lua`: the tab (runs in Lite)
- `templates/options.options`: what *+ options* in the tree's `/assets` starts from
- the format, and how a game shows one: `runtime/options.lua` (one file for both:
  the tab's preview is the game's own layout)

## Using it

- An `.options` opens as three panels: the menu's **outline** on the left
  (its tabs, sections and items; click one to select it), the menu **as the
  game shows it** in the middle, and the selected thing's **fields** on the
  right (an item's type, id, label, tip; a slider's min, max, step, dead
  zone, default, format, sound bus; a list's values; a text box's length,
  password; a button's action).
- **Add**: Tab, Section, and an item of each kind (On/off, List, Slider,
  Text, Button) after what's selected. **Up** / **Down** / **Delete** the
  selected one. *Tabs* (select the menu) turns the tab bar on or off: off,
  the menu is its sections only.
- **Try it** in the middle: click a tab, a value, a slider; or the keys
  (arrows, Enter, Q / E for tabs, Backspace for back, typing in a text box).
  What you try there only changes the preview: the file's defaults are the
  right panel's.
- Every edit is a text edit: Ctrl+Z / Ctrl+Y undo and redo, Ctrl+S saves.
  The tab's icon (or *Edit as text*) flips to the text; the menu follows
  the text as you type. The tab writes the file in its own layout (one
  item a line): comments of yours in it aren't kept.

## The format

Lua data, two levels at most: `tabs`, then `sections`; or `sections` only.

```lua
return {
  title = "Options",
  tabs = {
    { name = "Audio", sections = {
      { name = "Volume", items = {
        { id = "sfx", type = "slider", label = "Sound effects", default = 1, min = 0, max = 1,
          step = 0.05, deadzone = 0.02, percent = true, bus = "sfx", tip = "Heard as you move it" },
      } },
    } },
  },
}
```

Item types: `bool` (On / Off; `window = "fullscreen"`: the game's window),
`key` (a key binding: `action = "jump"`, one of the game's `/config` actions;
Enter, then the key or pad button; Backspace: the game's own keys; applied
with `w:bind`), `enum` (`values = { ... }`), `slider` (`min`,
`max`, `step`, `deadzone`: near either end it snaps to it, and to 0 when 0
is in between; `percent`, `fmt`), `text` (`maxlen`, `password`), `button`
(`action`: an event for the game; `close`, `reset`, `apply`, `discard` do
those; `text`: its button's word). `bus = "sfx" | "music" | "voice"` makes a
slider a sound bus's volume, heard as it moves (`live`).

## In a game

`games/hop` has one (O or the pad's Start): `objects/hud/menu` holds
`options = { file = "settings.options" }` and an `xform`; `systems/menu`
runs it:

```lua
return {
  requires = { "options" },
  on_key = function(w, key, down)                -- keys: the menu's while it's open
    local n = w:node("/objects/hud/menu")
    local o = w:options(n.c.options.file)
    local st = o:state(w, n)
    if not o:key(w, st, key, down) and down and key == "o" then o:open(w, st) end
  end,
  run = function(w, n, dt)
    local o = w:options(n.c.options.file)
    local st = o:state(w, n)
    o:update(w, st, dt, n)                       -- (held keys repeat; n: the mouse too)
    for _, e in ipairs(o:events(st)) do          -- { "apply", changed = { ids } }, { "button", action } ...
    end
    o:draw(w, st, n)                             -- its nodes, under /entities
  end,
}
```

`o:value(st, id)` (or `st.values`) has what's applied. Applied values are
saved for this machine (`saves/<the file's name>.sav`) and read back next
time. The menu's look: `o:draw(w, st, n, { w = 440, h = 240, accent = { ... } })`
(`runtime/options.lua`'s `LOOK`: its sizes and colours).

In the game: the mouse (hover, click, drag a slider; the menu takes the
game area's mouse only while it's open), pad 1 (LB / RB tabs, dpad or
stick, A, B / Home back, Y apply, X reset) and the keys. In the editor a
game with a menu gets a short ESC (its menu on / off); a long ESC stops.

## Open questions (for mario)

- A language list, once the localization plugin exists.
- More window settings (a size, the scale) when the host has them.
- Fonts: the 8 x 8 font for now; SDL3_ttf later (no `font =`: still this one).
