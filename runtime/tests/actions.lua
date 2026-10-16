-- actions.lua - input actions (runtime/ecs.lua): names for keys, held /
-- pressed / released, axes (a pad's stick too), on_action, rebinding saved
-- for this machine.   cd runtime/tests && luajit actions.lua   (or lua5.4)
package.path = "../?.lua;" .. package.path
local ecs = require "ecs"
local n, fails = 0, 0
local function check(c, m) n = n + 1; if not c then fails = fails + 1; print("  FAIL: " .. m) end end

local store = {}
ecs.saves = { read = function(k) return store[k] end, write = function(k, t) store[k] = t; return true end }
local w = ecs.world()
w:spawn("/config", { actions = { jump = { "space", "pad a" }, left = { "a", "left", "pad left" }, right = { "d", "right", "pad right" } } })
local heard = {}
w:spawn("/systems/act", { system = ecs.system(function()
  return { on_action = function(w, name, down, player) w:node("/data").c.log[#w:node("/data").c.log + 1] = name .. (down and "+" or "-") .. player end }
end) })
w:spawn("/data", { log = {} })
w:tick("/**", 1 / 60)

check(not w:action("jump") and not w:pressed("jump"), "nothing held")
w:key("space", true)
w:tick("/**", 1 / 60)
check(w:action("jump") and w:pressed("jump"), "space: jump held, pressed this tick")
w:tick("/**", 1 / 60)
check(w:action("jump") and not w:pressed("jump"), "the next tick: held, not pressed")
w:key("pad a", true)
w:key("space", false)
w:tick("/**", 1 / 60)
check(w:action("jump") and not w:released("jump"), "two keys on one action: still held while one is")
w:key("pad a", false)
w:tick("/**", 1 / 60)
check(not w:action("jump") and w:released("jump"), "both up: released")
local log = table.concat(w:node("/data").c.log, ",")
check(log == "jump+1,jump-1", "on_action: once down, once up (" .. log .. ")")

w:key("left", true, 2)
check(w:axis("left", "right", 2) == -1 and w:axis("left", "right", 1) == 0, "axis: player 2's left; player 1's nothing")
w:key("left", false, 2)
w.pads = { { lx = 0.4, ly = 0 } }
check(math.abs(w:axis("left", "right") - 0.4) < 1e-9, "axis: the stick's own value when bound (0.4)")
w:key("d", true)
check(w:axis("left", "right") == 1, "a key wins over a smaller stick")
w:key("d", false)

w:bind("jump", { "w" })
check(w:bindings().jump[1] == "w" and store.bindings and store.bindings:find('"w"', 1, true), "bind: rebound, saved for this machine")
w:key("space", true); w:tick("/**", 1 / 60)
check(not w:action("jump"), "the old key no longer jumps")
w:key("space", false)
local w2 = ecs.world()
w2:spawn("/config", { actions = { jump = { "space" } } })
check(w2:bindings().jump[1] == "w", "another world (a restart) reads the saved binding")
w2:bind("jump")
check(w2:bindings().jump[1] == "space", "bind(name): back to the game's")

print(string.format("actions: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
