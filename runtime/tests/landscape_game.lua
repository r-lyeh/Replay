-- landscape_game.lua - in games/landscape3d.lua (run.lua's "landscape", typed in at a frame): the meadow
-- (hills_meadow.foliage, its ground hills.land) on the hills; the hills changed by a brush: grown again on them.
return function(w)                                 -- (the console's world: dofile(...)(w))
local L = w:landscape('hills.land')
local F, LS = require('foliage'), require('landscape')
local s = F.check(dofile('games/common/hills_meadow.foliage'))
local function on(it)
  for i = 1, it.n, 3 do
    if math.abs(it.y[i] + s.layers[it.layer[i]].sink - L:height_at(it.x[i], it.z[i])) > 1e-4 then return false end
  end
  return true
end
local a = w:foliage('hills_meadow.foliage')
assert(a and a.n > 3000 and on(a), 'the meadow on the hills')
LS.brush(L, LS.check(dofile('games/common/hills.land')), 'sculpt', 0, 0, 10, 1)
local b = w:foliage('hills_meadow.foliage')
assert(b ~= a and on(b), 'the hills changed: grown again on them')
print('meadow on hills: ok ' .. b.n)
end
