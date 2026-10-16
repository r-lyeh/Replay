-- blocks.tl
-- Falling blocks in Teal (typed Lua: https://teal-language.org). The whole
-- file is Teal: this script builds the world and returns it; the module
-- and the systems below are Teal code leaves, type-checked as they load.
--   edit.exe games\blocks.tl
--
-- Type errors don't stop the game: they're warnings (the console, and the
-- node in amber in the tree; a click opens the line). Try it: in step,
-- write  s.score = "lots"  and save.
--
-- Each system's body is a chunk of its own (it saves, rewinds and hot-swaps
-- like any other component). The game's types and rules live in one Teal
-- module, /data/lib/blocks: require("blocks") gives its functions and its
-- types (B.State, B.Piece), checked across: declared once.
--
-- Press play: left / right move, up or X turns, Z turns back, down drops
-- faster, space drops it all the way. A full row clears; ten rows, a level
-- (faster). After a game over a new one starts in a few seconds (space
-- skips the countdown).

local ecs = require("ecs")
local w = ecs.world()

-- rules: tuning ---------------------------------------------------------------
w:spawn("/data/rules", {
  cols          = 10,
  rows          = 20,
  cell          = 18,
  fall          = 0.8,      -- seconds a row, at level 1
  faster        = 0.85,     -- each level: fall times this
  per_level     = 10,       -- rows cleared for a level
  lock          = 0.5,      -- seconds on the ground before it locks
  repeat_after  = 0.17,     -- held left / right: moves again after this,
  repeat_every  = 0.05,     --   then every this
  restart_after = 4,
})

-- state: the game as data (saves, rewinds and replicates) ----------------------
w:spawn("/data/state", {
  board   = {},             -- rows of cols digits: "0000000000" (0 empty, 1..7 a piece)
  piece   = { kind = 0, turn = 0, x = 0, y = 0 },
  next    = 0,
  bag     = {},
  seed    = 20261029,
  timer   = 0,
  ground  = 0,              -- seconds on the ground (lock when >= rules.lock)
  move    = 0,              -- held: -1 left, 1 right, 0 none
  held    = 0,              -- seconds it's been held
  soft    = false,          -- down held
  score   = 0,
  lines   = 0,
  level   = 1,
  best    = 0,
  over    = false,
  timeout = 0,
})

-- objects: what you see; /entities/cells/*, the blocks, are spawned by draw
w:spawn("/objects/well", { color = { 70, 76, 100 }, rect = { w = 184, h = 364 } })
for i, name in ipairs({ "score", "rows", "level", "best" }) do
  w:spawn("/objects/hud/" .. name, {
    xform = { x = 112, y = -190 + i * 24 },
    color = i == 1 and { 255, 230, 120 } or { 200, 205, 220 },
    text = { "", size = 2 },
  })
end
w:spawn("/objects/hud/info", {
  xform = { x = 112, y = -60 },
  color = { 120, 126, 150 },
  text = "next",
})
w:spawn("/objects/hud/banner", {
  xform = { x = 0, y = -20 },
  color = { 255, 230, 120 },
  text = { "", size = 2 },
  hidden = true,
})
w:spawn("/objects/hud/help", {
  xform = { x = -196, y = 200 },
  color = { 90, 96, 120 },
  text = "arrows move & turn, Z back, space drops. In Teal!",
})

-- the rules of the game, as a module: pieces, turning, fitting, clearing -------
local blocks = ecs.system(function(): any
  -- blocks: what a piece is and what it can do, typed. A module (a code
  -- leaf named `module`): systems get it with require("blocks"), its types
  -- too (B.State, B.Piece): declared once, here.
  local record Blocks
    record Piece
      kind: integer         -- 1..7: I O T S Z J L
      turn: integer         -- 0..3, a quarter turn each
      x: integer            -- its box's top left, in cells
      y: integer
    end
    type Board = {string}   -- rows of cols digits: "0000000000"
    record Rules            -- /data/rules
      cols: integer
      rows: integer
      cell: number
      fall: number
      faster: number
      per_level: integer
      lock: number
      repeat_after: number
      repeat_every: number
      restart_after: number
    end
    record State            -- /data/state
      board: Board
      piece: Piece
      next: integer
      bag: {integer}
      seed: integer
      timer: number
      ground: number
      move: integer
      held: number
      soft: boolean
      score: integer
      lines: integer
      level: integer
      best: integer
      over: boolean
      timeout: number
    end

    SHAPES: {{string}}
    COLORS: {{integer}}
    cells: function(Piece): {{integer}}
    fits: function(Board, Piece, integer, integer): boolean
    try_turn: function(Board, Piece, integer, integer): boolean
    clear_full: function(Board, integer): integer
    empty_row: function(integer): string
    at: function(Board, integer, integer): integer
    state: function(World): State, Rules
  end
  local type Piece = Blocks.Piece
  local type Board = Blocks.Board
  local M: Blocks = {} as Blocks

  -- each piece in its box (4 x 4 for I, 2 x 2 for O, 3 x 3 the rest): # a block
  M.SHAPES = {
    { "....", "####", "....", "...." },   -- I
    { "##", "##" },                       -- O
    { ".#.", "###", "..." },              -- T
    { ".##", "##.", "..." },              -- S
    { "##.", ".##", "..." },              -- Z
    { "#..", "###", "..." },              -- J
    { "..#", "###", "..." },              -- L
  }
  M.COLORS = {
    { 90, 220, 230 }, { 240, 220, 90 }, { 180, 110, 230 }, { 110, 220, 110 },
    { 235, 90, 90 }, { 90, 130, 235 }, { 240, 160, 70 },
  }
  -- the cells a piece covers: { {x, y}, ... } on the board
  function M.cells(p: Piece): {{integer}}
    local out: {{integer}} = {}
    local rows = M.SHAPES[p.kind]
    local n = #rows                                  -- (the box it turns in)
    for r = 0, n - 1 do
      for c = 0, n - 1 do
        if rows[r + 1]:sub(c + 1, c + 1) == "#" then
          local x, y = c, r
          for _ = 1, p.turn % 4 do x, y = n - 1 - y, x end   -- a quarter turn clockwise
          table.insert(out, { p.x + x, p.y + y })
        end
      end
    end
    return out
  end

  function M.at(b: Board, x: integer, y: integer): integer
    local row = b[y + 1]
    if not row then return 0 end
    return math.floor(tonumber(row:sub(x + 1, x + 1)) or 0)
  end

  -- does it fit there: inside the well, on empty cells (above the top is fine)
  function M.fits(b: Board, p: Piece, cols: integer, rows: integer): boolean
    for _, c in ipairs(M.cells(p)) do
      local x, y = c[1], c[2]
      if x < 0 or x >= cols or y >= rows then return false end
      if y >= 0 and M.at(b, x, y) ~= 0 then return false end
    end
    return true
  end

  -- turn it by dir (1 or -1) if it fits, nudged sideways if it must be
  function M.try_turn(b: Board, p: Piece, dir: integer, cols: integer): boolean
    local was, wx = p.turn, p.x
    p.turn = (p.turn + dir) % 4
    for _, dx in ipairs({ 0, -1, 1, -2, 2 }) do
      p.x = wx + dx
      if M.fits(b, p, cols, #b) then return true end
    end
    p.turn, p.x = was, wx
    return false
  end

  -- the game's state and rules, as their records
  function M.state(w: World): Blocks.State, Blocks.Rules
    return w:node("/data/state").c as Blocks.State, w:node("/data/rules").c as Blocks.Rules
  end

  function M.empty_row(cols: integer): string
    return string.rep("0", cols)
  end

  -- remove the full rows, new empty ones on top: how many went
  function M.clear_full(b: Board, cols: integer): integer
    local n = 0
    local y = #b
    while y >= 1 do
      if not b[y]:find("0", 1, true) then
        table.remove(b, y)
        table.insert(b, 1, M.empty_row(cols))
        n = n + 1
      else
        y = y - 1
      end
    end
    return n
  end

  return M
end)

-- systems ------------------------------------------------------------------------
local input = ecs.system(function(): any
  -- input: a press moves or turns the piece at once; left / right held
  -- repeat (step does that, from state.move and state.held).
  local B = require("blocks")
  local KEYS: {string:string} = {
    left = "left", a = "left", ["pad dpleft"] = "left", ["pad left"] = "left",
    right = "right", d = "right", ["pad dpright"] = "right", ["pad right"] = "right",
    up = "turn", x = "turn", w = "turn", ["pad a"] = "turn", ["pad dpup"] = "turn",
    z = "back", ["pad b"] = "back",
    down = "soft", s = "soft", ["pad dpdown"] = "soft", ["pad down"] = "soft",
    space = "drop", ["return"] = "drop", ["pad y"] = "drop", ["pad start"] = "drop",
  }

  return {
    on_key = function(w: World, key: string, down: boolean)
      local s, r = B.state(w)
      local what = KEYS[key]
      if not what then return end
      if s.over then
        if down and what == "drop" then s.timeout = 0 end
        return
      end
      if what == "soft" then s.soft = down return end
      if what == "left" or what == "right" then
        local dir = what == "left" and -1 or 1
        if down then
          s.move, s.held = dir, 0
          local p = s.piece
          p.x = p.x + dir
          if not B.fits(s.board, p, r.cols, r.rows) then p.x = p.x - dir end
        elseif s.move == dir then
          s.move = 0
        end
        return
      end
      if not down then return end
      local p = s.piece
      if what == "turn" or what == "back" then
        if B.try_turn(s.board, p, what == "turn" and 1 or -1, r.cols) then s.ground = 0 end
      elseif what == "drop" then
        while B.fits(s.board, p, r.cols, r.rows) do p.y = p.y + 1 end
        p.y = p.y - 1
        s.ground = r.lock                          -- (locks in the next step)
      end
    end,
  }
end)

local step = ecs.system(function(): any
  -- step: gravity (faster with the level), the lock, the rows cleared and
  -- the score, the next piece from a bag of seven (its randomness is
  -- state.seed: world data, so the timeline rewinds it exactly).
  local B = require("blocks")
  local type State = B.State
  local type Rules = B.Rules
  local POINTS: {integer} = { 100, 300, 500, 800 }   -- 1, 2, 3, 4 rows at once (times the level)

  local function rand(s: State, n: integer): integer
    s.seed = (s.seed * 16807) % 2147483647           -- Park-Miller
    return s.seed % n
  end
  local function draw_bag(s: State): integer
    if #s.bag == 0 then
      s.bag = { 1, 2, 3, 4, 5, 6, 7 }
      for i = 7, 2, -1 do                            -- shuffled
        local j = rand(s, i) + 1
        s.bag[i], s.bag[j] = s.bag[j], s.bag[i]
      end
    end
    return table.remove(s.bag)
  end
  local function spawn(s: State, r: Rules)
    s.piece = { kind = s.next, turn = 0, x = r.cols // 2 - 2, y = -1 }
    s.next = draw_bag(s)
    s.timer, s.ground = 0, 0
    if not B.fits(s.board, s.piece, r.cols, r.rows) then   -- no room: the game's over
      s.over, s.timeout = true, r.restart_after
      s.best = math.max(s.best, s.score)
      dd.log("blocks: game over, score " .. s.score)
    end
  end
  local function reset(s: State, r: Rules)
    s.board = {}
    for i = 1, r.rows do s.board[i] = B.empty_row(r.cols) end
    s.bag, s.score, s.lines, s.level, s.over = {}, 0, 0, 1, false
    s.next = draw_bag(s)
    spawn(s, r)
  end
  local function lock(s: State, r: Rules)
    for _, c in ipairs(B.cells(s.piece)) do
      local x, y = c[1], c[2]
      if y >= 0 then
        local row = s.board[y + 1]
        s.board[y + 1] = row:sub(1, x) .. tostring(s.piece.kind) .. row:sub(x + 2)
      end
    end
    local n = B.clear_full(s.board, r.cols)
    if n > 0 then
      s.score = s.score + POINTS[math.min(n, 4)] * s.level
      s.lines = s.lines + n
      s.level = s.lines // r.per_level + 1
    end
    spawn(s, r)
  end

  return function(w: World, dt: number)
    local s, r = B.state(w)
    if #s.board ~= r.rows or s.piece.kind == 0 then reset(s, r) end
    if s.over then                                   -- game over: count down, then play again
      s.timeout = s.timeout - dt
      if s.timeout <= 0 then reset(s, r) end
      return
    end
    local p = s.piece
    if s.move ~= 0 then                              -- left / right held: repeat
      local before = s.held
      s.held = s.held + dt
      local function ticks(t: number): integer
        if t < r.repeat_after then return 0 end
        return math.floor((t - r.repeat_after) / r.repeat_every) + 1
      end
      for _ = 1, ticks(s.held) - ticks(before) do
        p.x = p.x + s.move
        if not B.fits(s.board, p, r.cols, r.rows) then p.x = p.x - s.move break end
      end
    end
    local period = r.fall * r.faster ^ (s.level - 1)
    if s.soft then period = math.min(period, 0.04) end
    p.y = p.y + 1                                    -- on the ground?
    local grounded = not B.fits(s.board, p, r.cols, r.rows)
    p.y = p.y - 1
    if grounded then
      s.ground = s.ground + dt
      if s.ground >= r.lock then lock(s, r) end
      return
    end
    s.ground = 0
    s.timer = s.timer + dt
    while s.timer >= period do
      s.timer = s.timer - period
      p.y = p.y + 1
      if not B.fits(s.board, p, r.cols, r.rows) then p.y = p.y - 1 break end
      if s.soft then s.score = s.score + 1 end
    end
  end
end)

local draw = ecs.system(function(): any
  -- draw: the state is cells; the objects are pixels. One entity per block
  -- under /entities/cells (spawned and removed as the board changes:
  -- /entities is never saved): the board's, the piece's, its ghost (where
  -- it would land, dim) and the next piece beside the well.
  local B = require("blocks")
  local type Piece = B.Piece
  local shown: {string:boolean} = {}                 -- (the cells drawn this frame)

  local function block(w: World, name: string, x: number, y: number, size: number, color: {integer})
    local path = "/entities/cells/" .. name
    local n = w:node(path) or w:spawn(path, { rect = { w = size, h = size, fill = true } })
    n.c.xform = { x = x, y = y }
    n.c.color = color
    shown[path] = true
  end

  return function(w: World, dt: number)
    local s, r = B.state(w)
    local cols, rows, c = r.cols, r.rows, r.cell
    local ox, oy = (1 - cols) * c / 2, (1 - rows) * c / 2
    local board = s.board
    shown = {}
    for y = 0, rows - 1 do                           -- the board
      for x = 0, cols - 1 do
        local k = B.at(board, x, y)
        if k > 0 then block(w, x .. "_" .. y, ox + x * c, oy + y * c, c - 2, B.COLORS[k]) end
      end
    end
    local p = s.piece
    if p.kind > 0 and not s.over then
      local col = B.COLORS[p.kind]
      local ghost: Piece = { kind = p.kind, turn = p.turn, x = p.x, y = p.y }
      while B.fits(board, ghost, cols, rows) do ghost.y = ghost.y + 1 end
      ghost.y = ghost.y - 1
      for i, q in ipairs(B.cells(ghost)) do
        if q[2] >= 0 then block(w, "ghost" .. i, ox + q[1] * c, oy + q[2] * c, c - 8, { col[1] // 2, col[2] // 2, col[3] // 2 }) end
      end
      for i, q in ipairs(B.cells(p)) do
        if q[2] >= 0 then block(w, "piece" .. i, ox + q[1] * c, oy + q[2] * c, c - 2, col) end
      end
    end
    local nk = s.next                                -- the next one, beside the well
    if nk > 0 then
      for i, q in ipairs(B.cells({ kind = nk, turn = 0, x = 0, y = 0 })) do
        block(w, "next" .. i, 120 + q[1] * 14, -30 + q[2] * 14, 12, B.COLORS[nk])
      end
    end
    for _, n in ipairs(w:children("/entities/cells")) do   -- the rest: gone
      if not shown[n.path] then w:remove(n.path) end
    end
    local well = w:node("/objects/well").c.rect
    well.w, well.h = cols * c + 4, rows * c + 4
  end
end)

local hud = ecs.system(function(): any
  -- hud: score, rows, level; the banner with the countdown after a game over
  local B = require("blocks")
  return function(w: World, dt: number)
    local s = B.state(w)
    w:node("/objects/hud/score").c.text[1] = "score " .. tostring(s.score)
    w:node("/objects/hud/rows").c.text[1] = "rows  " .. tostring(s.lines)
    w:node("/objects/hud/level").c.text[1] = "level " .. tostring(s.level)
    w:node("/objects/hud/best").c.text[1] = "best  " .. tostring(s.best)
    local b = w:node("/objects/hud/banner").c
    b.hidden = not s.over or nil                     -- nil: shown
    if s.over then
      local text = "game over - again in " .. math.ceil(s.timeout)
      b.text[1] = text
      b.xform.x = -#text * 8 * 2 / 2                 -- debug font: 8 px per char, size 2
    end
  end
end)

-- the module and the systems: a node each; /systems' order is the run order
w:spawn("/data/lib/blocks", { module = blocks })
w:spawn("/systems", { order = { "input", "step", "draw", "hud" } })
w:spawn("/systems/input", { system = input })
w:spawn("/systems/step", { system = step })
w:spawn("/systems/draw", { system = draw })
w:spawn("/systems/hud", { system = hud })

return w
