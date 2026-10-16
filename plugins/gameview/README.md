# gameview

The game in a Lite tab: dock it, split it beside the code, drag it to
another pane. The main menu's **Game > Game view** opens it (one at a time).

- The tab leaves a hole in Lite's picture and tells the host where it is
  (`host_call("gameview x y w h active")`, Lite's pixels); the host draws
  the game there, at that size: its layout, picking and the transform
  gizmo all work in that rect.
- While it's open and shown, Lite stays opaque round it (no fade). The
  mouse over it is the game's. A click there, the tab becoming Lite's
  active view, or Play gives the game the keys. A click elsewhere in Lite
  gives them back.
- Behind another tab, or closed (`gameview off`): the game goes back
  behind Lite, as before.

- `editor.lua`: the tab (runs in Lite)

Later: the game in a window of its own (docs/ROADMAP.md).
