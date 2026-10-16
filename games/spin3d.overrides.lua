-- overrides for spin3d.lua: property edits saved by the viewer.
-- The script builds the world, then this is applied on top. Delete it to undo all.
return { overrides = 1,
nodes = {
  ["/classes"] = {},
  ["/objects/view/arm"] = { xform3d = { x = 2, z = -1.25 } },
  ["/objects/view/ball"] = { xform3d = { z = 0.75 } },
},
}
