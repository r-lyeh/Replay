-- sim.lua - the particles' simulation: runtime/particles.lua's (games play the same effects: a node's particles /
-- particles3d). Kept here so the editor's P.require("sim") finds it.
return dofile((rawget(_G, "REPLAY_ROOT") or (DATADIR .. "/../../..")) .. "/runtime/particles.lua")
