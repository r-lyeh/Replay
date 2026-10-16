-- teal.lua - Teal code (runtime/teal.lua, runtime/tl.lua): compiled line for
-- line, type errors as warnings (it runs anyway), syntax errors as errors
-- with their line; code leaves, modules, ecs.system in a .tl script, a
-- folder world's name.tl files; and games/blocks.tl's rules module.
--   cd runtime/tests && luajit teal.lua   (or lua5.4)
local here = (arg and arg[0] or ""):match("^(.*[/\\])") or ""
package.path = here .. "../?.lua;" .. here .. "?.lua;" .. package.path
local ecs = require("ecs")
local teal = require("teal")
local fs, disk = require("fs"), require("disk")
local n, fails = 0, 0
local function check(c, m) n = n + 1; if not c then fails = fails + 1; io.write("  FAIL: ", m, "\n") end end
local printed = {}
local print0 = print
print = function(...) local t = { ... }; printed[#printed + 1] = tostring(t[1]); end   -- (warnings: printed once)

-- compile: Lua line for line, warnings, errors
do
  local lua, map, warns = teal.compile("local record P\n  x: integer\nend\nlocal p: P = { x = 1 }\nlocal s: string = p.x\nreturn p.x // 2\n", "a.tl")
  check(lua and map[6] == 6 and lua:find("x = 1", 1, true), "compiled: " .. tostring(lua and lua:sub(1, 60) or map))
  check(warns and #warns == 1 and warns[1]:find("^a.tl:5: "), "a type error is a warning, at its line: " .. tostring(warns and warns[1]))
  local nl = 0
  for _ in (lua .. "\n"):gmatch("\n") do nl = nl + 1 end
  check(nl >= 6, "the lines kept")
  local bad, err = teal.compile("local x: = 1\n\nreturn x\n", "b.tl")
  check(not bad and tostring(err):find("^b.tl:1: "), "a syntax error stops it, at its line: " .. tostring(err))
  local _, _, w2 = teal.compile("return function(w: World, dt: number)\n  local n = w:node('/a')\n  n.c.xform.x = n.c.xform.x + dt\n  n.c.text[1] = 'hi'\n  dd.log('x')\n  local m = collide.circle_circle(0, 0, 1, 1, 1, 1)\n  w:nope(1)\nend\n", "c.tl")
  check(#w2 == 1 and w2[1]:find("^c.tl:7: "), "the sandbox's globals and World / Node / components are known (w:nope isn't): " .. table.concat(w2, "; "))
  local _, _, w3 = teal.compile("return function(w: World)\n  w:node(3)\n  local r = w:node('/a').c.rect\n  r.w = 'wide'\nend\n", "d.tl")
  check(#w3 == 2 and w3[1]:find("^d.tl:2:") and w3[2]:find("^d.tl:4:"), "typed: w:node's argument, rect.w: " .. table.concat(w3, "; "))
  local _, _, w4 = teal.compile("local m = require('space')\nreturn m.k\n", "e.tl")
  check(#w4 == 0, "a game's module: any (not a warning): " .. table.concat(w4, "; "))
end

-- code leaves in Teal: run, warnings kept and printed, errors at their line
do
  local w = ecs.world()
  w:spawn("/n", { x = 0 })
  w:spawn("/data/lib/half", { module = ecs.code("local record M\n  half: function(number): number\nend\nlocal m: M = {} as M\nfunction m.half(x: number): number return x / 2 end\nreturn m\n", "tl") })
  w:spawn("/sys", { inc = ecs.code("local h = require('half')\nreturn function(w: World, dt: number)\n  local c = w:node('/n').c\n  c.x = (c.x as number) + h.half(dt)\nend\n", "tl") })
  w:tick("/**", 2)
  check(next(w.code_err) == nil and w:node("/n").c.x == 1, "a Teal system and a Teal module ran: " .. tostring(w:node("/n").c.x) .. " " .. tostring((select(2, next(w.code_err)))))
  check(not ecs.warnings["/sys/inc"], "h.half known: no warning")
  -- a module's types, seen by its users (checked across)
  w:spawn("/data/lib/geo", { module = ecs.code("local record Geo\n  record Pt\n    x: number\n    y: number\n  end\n  len: function(Pt): number\nend\nlocal G: Geo = {} as Geo\nfunction G.len(p: Geo.Pt): number return math.sqrt(p.x * p.x + p.y * p.y) end\nreturn G\n", "tl") })
  w:spawn("/sys2", { use = ecs.code("local G = require('geo')\nlocal p: G.Pt = { x = 3, y = 4 }\nreturn function(w: World, dt: number)\n  w:node('/n').c.len = G.len(p)\n  G.len({ x = 'a' })\nend\n", "tl") })
  w:tick("/**", 0)
  local ws = ecs.warnings["/sys2/use"] or {}
  check(w:node("/n").c.len == 5, "a module's record type used by a system (G.Pt)")
  check(#ws == 1 and ws[1]:find("^/sys2/use:5: "), "and checked against it: " .. table.concat(ws, "; "))
  w:node("/data/lib/geo").c.module = ecs.code("local record Geo\n  record Pt\n    x: number\n  end\n  len: function(Pt): number\nend\nlocal G: Geo = {} as Geo\nfunction G.len(p: Geo.Pt): number return p.x end\nreturn G\n", "tl")
  w:tick("/**", 0)
  ws = ecs.warnings["/sys2/use"] or {}
  check(#ws >= 1 and ws[1]:find("^/sys2/use:2: "), "the module changed (no y): its users checked again: " .. table.concat(ws, "; "))
  w:node("/sys").c.inc = ecs.code("return function(w: World, dt: number)\n  local k: integer = 'many'\n  w:node('/n').c.x = 5\nend\n", "tl")
  printed = {}
  w:tick("/**", 1)
  check(w:node("/n").c.x == 5, "a type error: it runs anyway")
  check(ecs.warnings["/sys/inc"] and ecs.warnings["/sys/inc"][1]:find(":2: "), "its warning kept (ecs.warnings)")
  check(printed[1] and printed[1]:find("^warning: /sys/inc:2: "), "and printed: " .. tostring(printed[1]))
  w:node("/sys").c.inc = ecs.code("return function(w: World, dt: number)\n  local k: integer = 'many'\n  w:node('/n').c.x = 6\nend\n", "tl")
  printed = {}
  w:tick("/**", 1)
  check(#printed == 0, "the same warning: printed once")
  w:node("/sys").c.inc = ecs.code("return function(w: World, dt: number)\n  w:node('/n').c.x = 7\nend\n", "tl")
  w:tick("/**", 1)
  check(ecs.warnings["/sys/inc"] == nil and w:node("/n").c.x == 7, "fixed: no warning")
  w:node("/sys").c.inc = ecs.code("return function(w: World, dt: number)\n\n  local t: {string} = nil\n  t[1] = 'x'\nend\n", "tl")
  w:tick("/**", 1)
  check(tostring(w.code_err["/sys/inc"]):find("^/sys/inc:4:"), "a runtime error: at its Teal line: " .. tostring(w.code_err["/sys/inc"]))
  w:node("/sys").c.inc = ecs.code("return function(w: World, dt: number)\n  local = 1\nend\n", "tl")
  w:tick("/**", 1)
  check(tostring(w.code_err["/sys/inc"]):find("^/sys/inc:2:"), "a syntax error: at its line: " .. tostring(w.code_err["/sys/inc"]))
end

-- a .tl script: ecs.system(function(): any ... end) keeps a Teal body
do
  local src = "local ecs = require('ecs')\nlocal w = ecs.world()\nw:spawn('/n', { x = 0 })\n"
           .. "local s = ecs.system(function(): any\n  local record N\n    x: number\n  end\n  return function(w: World, dt: number)\n"
           .. "    local c = w:node('/n').c as N\n    c.x = c.x + dt\n  end\nend)\n"
           .. "w:spawn('/systems/s', { system = s })\nreturn w\n"
  local chunk, map = ecs.loadscript(src, "s.tl", "tl", "/tmp/s.tl")
  check(chunk, "the script compiles: " .. tostring(map))
  local w = chunk()
  local leaf = w:node("/systems/s").c.system
  local body, lang = ecs.code_source(leaf)
  check(lang == "tl" and body:find("local record N", 1, true) and not body:find("ecs.system", 1, true), "its system: the body, in Teal")
  w:tick("/**", 3)
  check(w:node("/n").c.x == 3 and next(w.code_err) == nil, "and it runs: " .. tostring(w:node("/n").c.x))
  local o = ecs.code_origins[body]
  check(o and o.file == "/tmp/s.tl" and o.line == 5, "its lines: in the script's file (from line 5): " .. tostring(o and o.line))
end

-- a folder world: name.tl files
do
  local dir = here .. "test_teal_tmp"
  local function rmtree(p)
    for _, e in ipairs(fs.list(p)) do
      local q = fs.join(p, e.name)
      if e.dir then rmtree(q) else fs.rmfile(q) end
    end
    fs.rmdir(p)
  end
  rmtree(dir) fs.mkdir(dir)
  local w = ecs.world()
  w:spawn("/sys", { inc = ecs.code("return function(w: World, dt: number) end\n", "tl") })
  local d = disk.new(dir)
  check(d:flush(w), "flushed")
  check(fs.read(dir .. "/sys/inc.tl") == "return function(w: World, dt: number) end\n", "written as .tl")
  local ok, blob = d:read()
  local w2 = ecs.world()
  check(ok and w2:load(blob, "/"), "read back")
  check(select(2, ecs.code_source(w2:node("/sys").c.inc)) == "tl", "as Teal")
  rmtree(dir)
end

-- games/blocks.tl: its rules module (pieces, turning, clearing rows)
do
  local f = io.open(here .. "../../games/blocks.tl", "rb")
  local src = f and f:read("*a")
  if f then f:close() end
  check(src, "games/blocks.tl is there")
  local chunk, err = ecs.loadscript(src or "", "blocks.tl", "tl", "blocks.tl")
  check(chunk, "blocks.tl compiles: " .. tostring(err))
  local w = chunk()
  ecs.check_script("blocks.tl", w)
  check(not ecs.warnings["blocks.tl"], "with no type warnings (its module's types known): " .. table.concat(ecs.warnings["blocks.tl"] or {}, "; "))
  w:tick("/**", 1 / 60)
  check(next(w.code_err) == nil, "its systems build: " .. tostring((select(2, next(w.code_err)))))
  local B = w:require("blocks")
  local cells = B.cells({ kind = 1, turn = 0, x = 3, y = 0 })
  check(#cells == 4 and cells[1][2] == 1, "an I: four cells in a row")
  local t = B.cells({ kind = 1, turn = 1, x = 3, y = 0 })
  check(t[1][1] == t[4][1] and t[4][2] - t[1][2] == 3, "turned: a column")
  local board = {}
  for i = 1, 20 do board[i] = string.rep("0", 10) end
  board[20] = "1111111111"; board[19] = "1111111110"
  check(B.clear_full(board, 10) == 1 and board[20] == "1111111110" and board[1] == string.rep("0", 10), "a full row clears, the rest falls")
  check(not B.fits(board, { kind = 2, turn = 0, x = 8, y = 18 }, 10, 20) and B.fits(board, { kind = 2, turn = 0, x = 3, y = 17 }, 10, 20), "fits: the well's sides and blocks")
  local s = w:node("/data/state").c
  check(s.piece.kind > 0 and s.next > 0 and #s.board == 20, "a game started: a piece, the next one, the board")
  s.board[20] = "1111011111"
  s.piece = { kind = 1, turn = 1, x = 2, y = -1 }   -- (an I, upright, over the gap: column 4)
  local K = w.systems["/systems/input/system"]
  K.on_key(w, "space", true)
  w:tick("/**", 1 / 60)
  check(s.lines == 1 and s.score == 100, "dropped in the gap: a row cleared, 100 points: " .. s.lines .. " " .. s.score)
end

-- the node graph's parser (plugins/nodegraph/luaparse.lua) reads Teal, Lua as before
do
  local lp = dofile(here .. "../../plugins/nodegraph/luaparse.lua")
  local lua = "local type = 1\nlocal record = {}\nrecord.x = type\nlocal y = record\nas = 2\nglobal = 3\nis = y\n"
  local a = lp.parse(lua)
  check(a and #a.body.stmts == 7 and #a.types == 0, "Lua that looks like Teal (type, record, as, global, is as names): Lua")
  local t = lp.parse("local record P\n  x: integer\n  record Q\n    y: number\n  end\nend\nlocal enum E\n  \"a\" \"b\"\nend\nlocal type F = function(integer, ? string): (boolean, string)\n"
    .. "local p: P = { x = 1 } as P\nlocal function f<T>(a: T, b?: {string:T}, ...: any): T, integer\n  return a, 1\nend\nglobal g: number = 2\nif p is P then g = 3 end\nreturn f(p)\n")
  check(t ~= nil, "Teal reads")
  if t then
    check(#t.types == 3 and t.types[1].kind == "record" and t.types[2].kind == "enum" and t.types[3].name == "F", "its declarations: not statements, listed")
    local l = t.body.stmts[1]
    check(l.tag == "Local" and l.types[1] == "P" and l.exprs[1].tag == "Paren" and l.exprs[1].cast == "P", "local p: P = ... as P")
    local f = t.body.stmts[2].func
    check(f.param_types[1] == "T" and f.param_types[2] == "{string:T}" and f.vararg_type == "any" and f.ret_type == "T, integer", "a function's types")
    check(t.body.stmts[3].global and t.body.stmts[4].clauses[1].cond.op == "is", "global, is")
  end
  local src = io.open(here .. "../../games/blocks.tl", "rb"):read("*a")
  check(lp.parse(src) ~= nil, "games/blocks.tl reads")
end

print = print0
print(string.format("teal: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
