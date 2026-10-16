-- snippet: Clamp a value
local $lo, $hi = 0, 1
local $clamped = math.max($lo, math.min($hi, 0.5))
