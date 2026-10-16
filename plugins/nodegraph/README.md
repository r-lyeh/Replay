# Node graph

A plugin of Replay's editor (`plugins/nodegraph`): a Lua (or Teal: `.tl`) file as a node
graph, in a tab beside (or instead of) its text. The text stays the truth:
the graph is rebuilt from it, and edits in the graph rewrite only the text
they touch.

- `editor.lua`: starts it (`require "plugins.nodegraph"`: `init.lua`) and applies `config.lua`
- `config.lua`: its settings (grid, rebuild delay, the flow's colour and fade, zoom, header colours), applied at once when saved
- `init.lua`: commands, the flip (text <-> graph, via `plugins/tabflip.lua`)
- `view.lua`, `input.lua`, `draw.lua`, `edits.lua`: the tab
- `luaparse.lua`, `graph.lua`, `resolve.lua`, `class.lua`: parsing (Lua, and Teal's types skipped and kept: pins' types), layout, scopes, LuaLS classes
- `breaks.lua`, `diff.lua`, `theme.lua`, `util.lua`: breakpoints, graph diffs, colours
- `ties.lua`: wires tied together (LMB from a wire, or ALT+RMB / SHIFT+RMB, drag across them), control points

It used to live in `editor/3rd/lite/data/plugins/nodegraph`. Its modules are still
`plugins.nodegraph.<mod>`; the editor's C side (the probe, breakpoints,
Play's compile check) talks to it by those names. It doesn't reload live:
restart the editor after changing it. docs/FEATURES.md has what it does.
