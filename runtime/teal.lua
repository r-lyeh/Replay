-- teal.lua - Teal (typed Lua: https://teal-language.org, tl.lua by Hisham
-- Muhammad, MIT: runtime/tl.lua, LICENSE-teal.txt) for code leaves and
-- scripts: `name.tl` files, ecs.code(src, "tl"), ecs.languages.tl.
--
--   local lua, map, warnings = teal.compile(src, name [, resolve])
--     lua: the Lua it becomes, line for line (map[lua line] = the same line);
--     warnings: { "name:12: got number, expected integer", ... }: the type
--     checker's findings. They don't stop the code: it runs as it is (a
--     syntax error does: nil, "name:3: ..." as Lua's own). resolve(module
--     name) -> its source, language: the world's modules (ecs.compile's).
--
-- The checker knows what a system's sandbox has: Lua's math / string /
-- table / utf8 and the safe base functions, our globals (dd, collide, path,
-- tmap: their functions take and give `any`), the types World and Node (a
-- system's `w` and what w:node() gives: their common methods typed, the
-- rest `any`), and the module "ecs" for scripts (ecs.world(), ecs.system...).
-- A system's body is a chunk of its own (ecs.system keeps only its text): the
-- types it uses are declared in it (a local record, a local enum), not in the
-- script around it, or in a module: a world's Teal module (a `module` leaf,
-- /data/lib/<name>) is checked first, and what require("<name>") gives is
-- its type, nested types too (local B = require "blocks"; local p: B.Piece).
-- A Lua module (or none): `any`.
local M = {}

-- what code leaves see, as Teal declarations
M.declarations = [[
global record Fn                                   -- a bag of functions (dd, collide, path, tmap)
  metamethod __index: function(Fn, string): function(...: any): any...
end
-- the components the viewer draws (docs/HELP.md 4.2), typed; any other: any
global record Xform
  x: number
  y: number
  r: number
  s: number
  sx: number
  sy: number
  shear: number
  shear_y: number
end
global record Rect
  w: number
  h: number
  fill: boolean
end
global record Circle
  r: number
  fill: boolean
end
global record Text is {string}                     -- { "hello", size = 2 } (a plain "hello": as any)
  size: number
  font: string
  align: string
  width: number
  shear: number
  shadow: any
end
global record Components
  xform: Xform
  color: {number}
  rect: Rect
  circle: Circle
  text: Text
  hidden: boolean
  layer: string
  metamethod __index: function(Components, string): any
end
global record Node
  path: string
  name: string
  c: Components                                    -- its components
  parent: Node
  metamethod __index: function(Node, string): any
end
global type Visit = function(Node, integer): any
global record World
  nodes: {string:Node}
  time: number
  node: function(World, string): Node
  spawn: function(World, string, ? {string:any}): Node
  remove: function(World, string)
  get: function(World, string | Node, string): any
  set: function(World, string | Node, string, any)
  unset: function(World, string | Node, string)
  children: function(World, string | Node): {Node}
  select: function(World, string): {Node}
  query: function(World, ...: string): {Node}
  walk: function(World, string | Node, Visit, ? integer)
  key: function(World, string, ? boolean, ? integer): boolean
  pressed: function(World, string, ? integer): boolean
  released: function(World, string, ? integer): boolean
  action: function(World, string, ? integer): boolean
  axis: function(World, string, string, ? integer): number
  bind: function(World, string, {string})
  event: function(World, string, ? any)
  sound: function(World, string, ? {string:any}): any
  sound_set: function(World, any, {string:any})
  sound_stop: function(World, any)
  music: function(World, string, ? {string:any}): any
  tr: function(World, string, ? number, ? {string:any}): string
  text_size: function(World, string, ? string, ? number, ? number): number, number
  asset: function(World, string): any
  panic: function(World, string, ? string)
  point_at: function(World, string, ? string)
  savegame: function(World, string, any)
  loadgame: function(World, string): any
  owns: function(World, string | Node): boolean
  -- the rest: untyped
  bindings: function(World, ...: any): any...
  bullets: function(World, ...: any): any...
  bus: function(World, ...: any): any...
  capture: function(World, ...: any): any...
  deliver: function(World, ...: any): any...
  dialog: function(World, ...: any): any...
  dump: function(World, ...: any): any...
  flock: function(World, ...: any): any...
  generate: function(World, ...: any): any...
  hear_editor: function(World, ...: any): any...
  language: function(World, ...: any): any...
  languages: function(World, ...: any): any...
  layout: function(World, ...: any): any...
  live: function(World, ...: any): any...
  load: function(World, ...: any): any...
  options: function(World, ...: any): any...
  path: function(World, ...: any): any...
  put: function(World, ...: any): any...
  rank_of: function(World, ...: any): any...
  refresh: function(World, ...: any): any...
  require: function(World, ...: any): any...
  rerun: function(World, ...: any): any...
  save: function(World, ...: any): any...
  step: function(World, ...: any): any...
  sync_code: function(World, ...: any): any...
  system: function(World, ...: any): any...
  tick: function(World, ...: any): any...
  tr_file: function(World, ...: any): any...
  unsystem: function(World, ...: any): any...
  upgrade_class: function(World, ...: any): any...
  metamethod __index: function(World, string): any
end
global dd: Fn
global collide: Fn
global path: Fn
global tmap: Fn
global unpack: function<T>({T}, ? integer, ? integer): T...
]]
-- the module scripts require (a script: builds the world, returns it)
M.modules = {
  ecs = [[
local record ecs
  world: function(): World
  system: function(function(): any...): any
  code: function(string, ? string): any
  copy: function<T>(T): T
  metamethod __index: function(ecs, string): any
end
return {} as ecs
]],
}

local tl, env, base_globals
local function target()
  if _VERSION == "Lua 5.4" then return "5.4" elseif _VERSION == "Lua 5.3" then return "5.3" end
  return "5.1"                                     -- (LuaJIT, 5.1, 5.2: // becomes math.floor(a / b))
end
local function setup()
  if env then return true end
  local ok, t = pcall(require, "tl")
  if not ok then return nil, "Teal's compiler not found (runtime/tl.lua): " .. tostring(t) end
  tl = t
  local e, err = tl.new_env({ defaults = { gen_target = target(), gen_compat = "off", feat_lax = "off", feat_arity = "on" } })
  if not e then return nil, "Teal: " .. tostring(err) end
  local r = tl.check_string(M.declarations, e, "@replay.d.tl")
  if #r.syntax_errors + #r.type_errors > 0 then
    local x = r.syntax_errors[1] or r.type_errors[1]
    return nil, "Teal: replay.d.tl:" .. x.y .. ": " .. x.msg
  end
  for name, decl in pairs(M.modules) do
    local m = tl.check_string(decl, e, "@" .. name .. ".d.tl")
    e.modules[name] = m.type
  end
  base_globals = {}
  for k in pairs(e.globals) do base_globals[k] = true end
  env = e
  return true
end

local QUIET = {                                    -- (findings that aren't about this chunk)
  "^module not found",                             -- (a game's module: required at run time)
}
-- the names a chunk requires: require("x") / require "x"
local function requires(src)
  local out, seen = {}, {}
  for q, n in src:gmatch("require%s*%(?%s*([\"'])([^\"'\n]+)%1") do
    if not seen[n] then seen[n] = true; out[#out + 1] = n end
  end
  return out
end
-- a world's Teal module: its type, as its users see it (its record, its
-- nested types: blocks.Piece). Checked once per source (cached).
local cache_by, cached = {}, 0                     -- name .. "\0" .. src -> type (its old sources: dropped now and then)
local function check(src, file)
  env.loaded[file] = nil
  for i = #env.loaded_order, 1, -1 do if env.loaded_order[i] == file then table.remove(env.loaded_order, i) end end
  local res = tl.check_string(src, env, file, "tl")
  env.loaded[file] = nil
  for k in pairs(env.globals) do if not base_globals[k] then env.globals[k] = nil end end   -- (a chunk's own globals: its own)
  return res
end
local function with_modules(src, resolve, depth, fn)   -- fn() with env.modules set for what src requires
  local set = {}
  if resolve and depth < 8 then
    for _, n in ipairs(requires(src)) do
      if not M.modules[n] then
        local ok, msrc, mlang = pcall(resolve, n)
        if ok and type(msrc) == "string" and mlang == "tl" then
          local key = n .. "\0" .. msrc
          local t = cache_by[key]
          if t == nil then
            cached = cached + 1
            if cached > 256 then cache_by, cached = {}, 1 end
            cache_by[key] = false                  -- (a cycle: any)
            with_modules(msrc, resolve, depth + 1, function()
              local r = check(msrc, "@module:" .. n)
              if #(r.syntax_errors or {}) == 0 then t = r.type end
            end)
            cache_by[key] = t or false
          end
          if t then set[n] = env.modules[n] == nil; env.modules[n] = t end
        end
      end
    end
  end
  local r = { pcall(fn) }
  for n, fresh in pairs(set) do if fresh then env.modules[n] = nil end end
  if not r[1] then error(r[2], 0) end
  return (table.unpack or unpack)(r, 2)
end
M.requires = requires
function M.reset_cache() cache_by = {} end

function M.compile(src, name, resolve)
  local ok, err = setup()
  if not ok then return nil, name .. ": " .. err end
  local res = with_modules(src, resolve, 0, function() return check(src, "@" .. name) end)
  local se = res.syntax_errors or {}
  if #se > 0 then
    table.sort(se, function(a, b) return a.y < b.y or (a.y == b.y and a.x < b.x) end)
    return nil, string.format("%s:%d: %s", name, se[1].y, se[1].msg)
  end
  local warnings = {}
  local errs = res.type_errors or {}
  table.sort(errs, function(a, b) return a.y < b.y or (a.y == b.y and a.x < b.x) end)
  for _, e in ipairs(errs) do
    local quiet = false
    for _, q in ipairs(QUIET) do if tostring(e.msg):match(q) then quiet = true end end
    if not quiet then warnings[#warnings + 1] = string.format("%s:%d: %s", name, e.y, e.msg) end
  end
  local lua, gerr = tl.generate(res.ast, target(), { preserve_indent = true, preserve_newlines = true, preserve_hashbang = false })
  if not lua then return nil, name .. ": " .. tostring(gerr) end
  local map, n = {}, 0
  for _ in (lua .. "\n"):gmatch("[^\n]*\n") do n = n + 1; map[n] = n end   -- (line for line)
  return lua, map, warnings
end
M.target = target
return M
