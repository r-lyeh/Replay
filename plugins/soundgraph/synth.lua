-- synth.lua - the sound graph's renderer: runtime/soundgraph.lua (games play
-- the same sounds: runtime/sound.lua, w:sound). Loaded from there: one copy.
local here = (debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or ".")
return dofile(here .. "/../../runtime/soundgraph.lua")
