-- review.lua - games have authors, changes are proposals, admins review them
-- (docs/ROADMAP.md "Admin nodes: a plan", steps 1-4 without the network:
-- proposals travel as files for now). Pure Lua: ecs, ed25519, fs.
--
-- A game's review folder sits beside it: games/pong/ -> games/pong.review/
--   manifest.lua            { name, authors = { pk hex, ... }, version = hash,
--                             history = { hash, ... }, need = 1, sig }
--   versions/<hash>.world   the authored world at that version (w:save, disk)
--   proposals/<from>-<to>.lua
--     { name, from, to, patch, note, author = pk hex, sig,
--       reviews = { { by = pk hex, verdict = "accept" | "reject", note, sig } } }
--
-- A version is a hash of the authored world: the first 32 hex digits of the
-- SHA-512 of its save blob (the same in LuaJIT and Lua 5.4; CR LF read as LF;
-- empty nodes, such as the folders the editor makes, left out).
-- What's signed (Ed25519, the peer key in .network.lua):
--   "replay authors <name> <pk>,<pk>..."              the manifest
--   "replay propose <name> <from> <to> <note hash>"   a proposal (the patch is
--                                                     checked by its result: to)
--   "replay review <name> <from> <to> <verdict> <note hash>"
-- An admin is a key in runtime/admins.lua (or REPLAY_ADMINS: pks, commas),
-- never one of the game's authors. A proposal with `need` accepts (1 for now)
-- from such admins, and no author's own, is accepted: update() takes it.
local ecs = require("ecs")
local E = require("ed25519")
local fs = require("fs")
local R = {}

local function nhash(s) return E.hex(E.sha512(s or "")):sub(1, 32) end
function R.version(blob)                          -- (empty nodes left out: the editor makes /docs, /assets folders)
  local keep = {}
  for line in (blob:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
    if not line:match('^  %["[^"]*"%] = {},?$') then keep[#keep + 1] = line end
  end
  return nhash(table.concat(keep, "\n"))
end
function R.public(seed) return E.hex((E.keypair(seed))) end
function R.short(pk) return tostring(pk):sub(1, 8) end

function R.dir_of(game_path)                      -- games/pong/ -> games/pong.review
  return (tostring(game_path):gsub("[/\\]+$", "")) .. ".review"
end

-- data files: Lua tables, read with nothing to call
local function read_data(path)
  local src = fs.read(path)
  if not src then return nil end
  local ok, v = pcall(ecs.decode, src, path)
  if ok and type(v) == "table" then return v end
  return nil
end
local function write_data(path, t, head)
  local s = assert(ecs.encode(t))
  return fs.write(path, (head and ("-- " .. head .. "\n") or "") .. s .. "\n")
end

-- who's an admin: runtime/admins.lua (return { "pk hex", ... }) and REPLAY_ADMINS
function R.admins()
  local out, seen = {}, {}
  local function add(pk)
    pk = tostring(pk):lower()
    if #pk == 64 and not pk:find("[^%x]") and not seen[pk] then seen[pk] = true; out[#out + 1] = pk end
  end
  local f = package.searchpath and package.searchpath("admins", package.path)
  local t = f and read_data(f)
  for _, pk in ipairs(t or {}) do add(pk) end
  for pk in (os.getenv("REPLAY_ADMINS") or ""):gmatch("[^,%s]+") do add(pk) end
  return out, seen
end

local function has(list, pk) for _, k in ipairs(list or {}) do if k == pk then return true end end return false end
local function verify(pk, text, sig)
  if type(pk) ~= "string" or type(sig) ~= "string" or #pk ~= 64 or #sig ~= 128 then return false end
  local ok, good = pcall(E.verify, E.unhex(pk), text, E.unhex(sig))
  return ok and good and true or false
end
local function sign(seed, text) return E.hex(E.sign(seed, text)) end

function R.authors_text(m) return "replay authors " .. m.name .. " " .. table.concat(m.authors, ",") end
function R.propose_text(p) return string.format("replay propose %s %s %s %s", p.name, p.from, p.to, nhash(p.note)) end
function R.review_text(p, verdict, note) return string.format("replay review %s %s %s %s %s", p.name, p.from, p.to, verdict, nhash(note)) end

-- the manifest: read and checked (signed by its first author)
function R.manifest(dir)
  local m = read_data(fs.join(dir, "manifest.lua"))
  if not m then return nil, "no manifest (nobody proposed yet)" end
  if type(m.name) ~= "string" or type(m.authors) ~= "table" or not m.authors[1] then return nil, "manifest: not one" end
  if not verify(m.authors[1], R.authors_text(m), m.sig) then return nil, "manifest: its signature doesn't hold" end
  m.need = math.max(1, tonumber(m.need) or 1)
  m.history = type(m.history) == "table" and m.history or {}
  return m
end
local function save_manifest(dir, m)
  return write_data(fs.join(dir, "manifest.lua"), m, "a game's authors and its accepted version (runtime/review.lua)")
end
function R.base(dir, hash)                        -- the world blob at a version
  return fs.read(fs.join(dir, "versions", hash .. ".world"))
end

-- an author proposes the world as it is now (blob) over the accepted version.
-- The first proposal makes the manifest: its author authors the game, and
-- the world before it (base_blob, or blob itself) is the first version.
-- -> proposal, path | false, what happened (authored, no proposal yet) | nil, err
function R.propose(dir, name, blob, seed, note, base_blob, admins)
  note = tostring(note or "")
  local pk = R.public(seed)
  fs.mkdir(dir); fs.mkdir(fs.join(dir, "versions")); fs.mkdir(fs.join(dir, "proposals"))
  local m = R.manifest(dir)
  if not m then
    if fs.read(fs.join(dir, "manifest.lua")) then return nil, select(2, R.manifest(dir)) end
    base_blob = base_blob or blob
    m = { name = name, authors = { pk }, version = R.version(base_blob), history = {}, need = 1 }
    m.sig = sign(seed, R.authors_text(m))
    fs.write(fs.join(dir, "versions", m.version .. ".world"), base_blob)
    save_manifest(dir, m)
    if m.version == R.version(blob) then           -- (the first time: the game as it is, now authored)
      return false, string.format("you author %s now: version %s (change it, save, propose again)", name, m.version:sub(1, 8))
    end
  end
  R.catch_up(dir, m, admins)
  if not has(m.authors, pk) then return nil, "not an author of " .. m.name .. " (its authors propose; others ask them)" end
  local base = R.base(dir, m.version)
  if not base then return nil, "version " .. m.version .. " missing (versions/)" end
  local to = R.version(blob)
  if to == m.version then return nil, "nothing to propose: the world is the accepted version" end
  local ok, patch = ecs.diff(base, blob)
  if not ok then return nil, "diff: " .. tostring(patch) end
  local p = { name = m.name, from = m.version, to = to, patch = patch, note = note, author = pk, reviews = {} }
  p.sig = sign(seed, R.propose_text(p))
  fs.write(fs.join(dir, "versions", to .. ".world"), blob)
  local path = fs.join(dir, "proposals", p.from .. "-" .. p.to .. ".lua")
  write_data(path, p, "a proposed change to " .. m.name .. " (runtime/review.lua)")
  return p, path
end

-- the patched world: base + patch -> ok, blob | nil, err
function R.result(base, patch)
  local ok, w = ecs.load(base, "/")
  if not ok then return nil, w end
  local ok2, err = ecs.load(patch, "/", w)
  if not ok2 then return nil, err end
  local ok3, b = w:save("/**", true)
  if not ok3 then return nil, b end
  return b, w
end

-- a proposal checked: the author's, signed, and its patch makes `to` from `from`
-- -> true | nil, why
function R.check(dir, p, m)
  m = m or R.manifest(dir)
  if not m then return nil, "no manifest" end
  if p.name ~= m.name then return nil, "for another game (" .. tostring(p.name) .. ")" end
  if not has(m.authors, p.author) then return nil, "not by an author" end
  if not verify(p.author, R.propose_text(p), p.sig) then return nil, "its signature doesn't hold" end
  local base = R.base(dir, p.from)
  if not base then return nil, "its base version is missing" end
  local b, err = R.result(base, p.patch)
  if not b then return nil, "the patch: " .. tostring(err) end
  if R.version(b) ~= p.to then return nil, "the patch doesn't make " .. p.to end
  return true
end

-- run it headless: the patched world, ticked n times (60 a second), no errors
function R.test(dir, p, n)
  local base = R.base(dir, p.from)
  if not base then return nil, "no base" end
  local b, w = R.result(base, p.patch)
  if not b then return nil, w end
  n = n or 120
  for i = 1, n do
    local ok, err = pcall(w.tick, w, "/**", 1 / 60)
    if not ok then return nil, string.format("tick %d: %s", i, tostring(err)) end
    for name, e in pairs(w.code_err or {}) do       -- (a system's error: it broke, the world goes on without it)
      return nil, string.format("tick %d: %s: %s", i, name, tostring(e))
    end
  end
  return true, n
end

-- the reviews that count: by admins, not authors, signed; -> accepts, rejects
function R.tally(p, m, admins)
  local _, is_admin = R.admins()
  if admins then is_admin = {}; for _, k in ipairs(admins) do is_admin[k] = true end end
  local acc, rej, seen = 0, 0, {}
  for _, r in ipairs(p.reviews or {}) do
    if is_admin[r.by] and not has(m.authors, r.by) and not seen[r.by]
       and verify(r.by, R.review_text(p, r.verdict, r.note), r.sig) then
      seen[r.by] = true
      if r.verdict == "accept" then acc = acc + 1 elseif r.verdict == "reject" then rej = rej + 1 end
    end
  end
  return acc, rej
end
function R.state(p, m, admins)                    -- "accepted" | "rejected" | "waiting"
  local acc, rej = R.tally(p, m, admins)
  if rej > 0 then return "rejected", acc, rej end
  if acc >= m.need then return "accepted", acc, rej end
  return "waiting", acc, rej
end

-- the accepted version follows the accepted proposals: from the manifest's
-- version, the one accepted over it, and on (the manifest saved so)
function R.catch_up(dir, m, admins)
  local moved = true
  while moved do
    moved = false
    for _, f in ipairs(fs.list(fs.join(dir, "proposals"))) do
      if f.name:sub(1, #m.version + 1) == m.version .. "-" then
        local p = read_data(fs.join(dir, "proposals", f.name))
        if p and type(p.reviews) == "table" and p.from == m.version and R.state(p, m, admins) == "accepted" and R.check(dir, p, m) then
          R.advance(dir, m, p.to); moved = true; break
        end
      end
    end
  end
  return m
end

-- every proposal of a game, oldest version first -> list of { p, path, state, acc, rej }
function R.list(dir, admins)
  local m, err = R.manifest(dir)
  if not m then return {}, err end
  R.catch_up(dir, m, admins)
  local out = {}
  for _, f in ipairs(fs.list and fs.list(fs.join(dir, "proposals")) or {}) do
    local name = type(f) == "table" and f.name or f
    if tostring(name):match("%.lua$") then
      local path = fs.join(dir, "proposals", name)
      local p = read_data(path)
      if p and type(p.reviews) == "table" then
        local st, acc, rej = R.state(p, m, admins)
        out[#out + 1] = { p = p, path = path, state = st, acc = acc, rej = rej, current = p.from == m.version }
      end
    end
  end
  local rank = { [m.version] = #m.history + 1 }      -- (in the order of the versions they build on)
  for i, h in ipairs(m.history) do rank[h] = i end
  table.sort(out, function(a, b)
    local ra, rb = rank[a.p.from] or 1e9, rank[b.p.from] or 1e9
    if ra ~= rb then return ra < rb end
    return a.path < b.path
  end)
  return out, m
end

-- an admin reviews: verdict "accept" | "reject" -> true | nil, err
function R.review(dir, path, seed, verdict, note, admins)
  if verdict ~= "accept" and verdict ~= "reject" then return nil, 'the verdict: "accept" or "reject"' end
  note = tostring(note or "")
  local m, err = R.manifest(dir)
  if not m then return nil, err end
  local pk = R.public(seed)
  local _, is_admin = R.admins()
  if admins then is_admin = {}; for _, k in ipairs(admins) do is_admin[k] = true end end
  if not is_admin[pk] then return nil, "you're not an admin (runtime/admins.lua lists their keys)" end
  if has(m.authors, pk) then return nil, "not your own game: admins review others' games only" end
  local p = read_data(path)
  if not p then return nil, "can't read " .. tostring(path) end
  local ok, why = R.check(dir, p, m)
  if not ok then return nil, "the proposal: " .. why end
  local keep = {}
  for _, r in ipairs(p.reviews or {}) do if r.by ~= pk then keep[#keep + 1] = r end end
  keep[#keep + 1] = { by = pk, verdict = verdict, note = note, sig = sign(seed, R.review_text(p, verdict, note)) }
  p.reviews = keep
  write_data(path, p, "a proposed change to " .. m.name .. " (runtime/review.lua)")
  return true
end

-- what update() takes: the accepted proposal over this version -> entry | nil
function R.next(dir, version, admins)
  local list, m = R.list(dir, admins)
  if not m then return nil end
  for _, e in ipairs(list) do
    if e.p.from == version and e.state == "accepted" and R.check(dir, e.p, m) then return e, m end
  end
  return nil, m
end
-- that version is now the accepted one (its history kept)
function R.advance(dir, m, to)
  if m.version == to then return true end
  m.history[#m.history + 1] = m.version
  m.version = to
  return save_manifest(dir, m)
end

-- the viewer's console: propose(note), proposals(), review(i, verdict, note),
-- update(), key()  (players.lua loads this; its key is .network.lua's)
if viewer_console_cmds then
  local function me() return viewer_peer_key and viewer_peer_key() end
  local function here()                          -- -> the review folder | nil, why
    local f = viewer_game_path and viewer_game_path()
    if not f then return nil, "no game" end
    if viewer_savable() ~= "folder" then return nil, "world folders only, for now (a script game: make it a folder)" end
    return R.dir_of(f)
  end
  function viewer_review(w, cmd, a, b, c)        -- (the Review tab: host_world("viewer_review", ...))
    local dir, err = here()
    if cmd == "info" then
      local seed = me()
      local pk = seed and R.public(seed)
      local _, is_admin = R.admins()
      local out = { key = pk, admin = pk and is_admin[pk] or false, game = viewer_game_name(), err = err, rows = {} }
      if not dir then return out end
      local list, m = R.list(dir)
      out.version = m and m.version
      out.author = m and pk and has(m.authors, pk) or false
      out.authors = m and m.authors
      out.mine = viewer_disk_blob and R.version(viewer_disk_blob() or "") or nil
      for i, e in ipairs(list) do
        local ok, why = R.check(dir, e.p, m)
        out.rows[i] = { from = e.p.from, to = e.p.to, note = e.p.note, author = e.p.author, state = e.state,
                        acc = e.acc, rej = e.rej, current = e.current, valid = ok or false, why = why,
                        reviews = e.p.reviews, size = #e.p.patch, path = e.path }
      end
      return out
    end
    if not dir then return nil, err end
    local seed = me()
    if not seed then return nil, "no key here (signatures need runtime/ed25519.lua)" end
    if cmd == "propose" then                       -- (the world as saved: unsaved changes aren't in it)
      local p, path = R.propose(dir, viewer_game_name(), viewer_disk_blob(), seed, a)
      if p == false then return true, path end
      if not p then return nil, path end
      return true, string.format("proposed %s -> %s (%d bytes of patch)", p.from:sub(1, 8), p.to:sub(1, 8), #p.patch)
    end
    local list = R.list(dir)
    local e = list[tonumber(a) or 0]
    if cmd == "test" then
      if not e then return nil, "no proposal " .. tostring(a) end
      local ok, n = R.test(dir, e.p, tonumber(b) or 120)
      if not ok then return nil, n end
      return true, string.format("ran %d ticks: no errors", n)
    end
    if cmd == "review" then
      if not e then return nil, "no proposal " .. tostring(a) end
      local ok, why = R.review(dir, e.path, seed, b, c)
      if not ok then return nil, why end
      return true, b .. "ed"
    end
    if cmd == "diff" then                          -- what it changes: the nodes, added / changed / removed
      if not e then return nil, "no proposal " .. tostring(a) end
      return true, R.summary(dir, e.p)
    end
    if cmd == "update" then                        -- (onto the folder; the live world takes it as any change on disk)
      local now = R.version(viewer_disk_blob())
      local nx, m = R.next(dir, now)
      if not nx then return nil, m and (m.version == now and "up to date: " .. now:sub(1, 8) or "no accepted proposal over this version (" .. now:sub(1, 8) .. ")") or "no manifest" end
      local b, nw = R.result(viewer_disk_blob(), nx.p.patch)
      if not b then return nil, nw end
      if R.version(b) ~= nx.p.to then return nil, "the patch doesn't make " .. nx.p.to:sub(1, 8) .. " here" end
      local ok, err2 = viewer_disk_write(nw)
      if not ok then return nil, err2 end
      viewer_poll(w)
      local got = R.version(viewer_disk_blob())
      if got ~= nx.p.to then return nil, "updated, but the world on disk is " .. got:sub(1, 8) .. ", not " .. nx.p.to:sub(1, 8) end
      return true, "updated to " .. got:sub(1, 8) .. (nx.p.note ~= "" and (": " .. nx.p.note) or "")
    end
    return nil, "review: " .. tostring(cmd) .. "?"
  end
  local function say(ok, msg) return ok and msg or ("! " .. tostring(msg)) end
  viewer_console_cmds.key = function()           -- key(): this computer's public key (admins.lua lists admins' keys)
    local seed = me()
    return seed and ("your public key: " .. R.public(seed)) or "no key here"
  end
  viewer_console_cmds.propose = function(w, note) return say(viewer_review(w, "propose", note)) end
  viewer_console_cmds.proposals = function(w)
    local t = viewer_review(w, "info")
    if t.err then return "! " .. t.err end
    local lines = { string.format("%s: version %s%s", t.game, t.version and t.version:sub(1, 8) or "none yet", t.admin and "   (you: admin)" or "") }
    for i, r in ipairs(t.rows) do
      lines[#lines + 1] = string.format("%d. %s -> %s  %s  by %s  %s%s", i, r.from:sub(1, 8), r.to:sub(1, 8), r.state,
        R.short(r.author), r.note, r.valid and "" or ("   [" .. tostring(r.why) .. "]"))
    end
    if #t.rows == 0 then lines[#lines + 1] = "no proposals" end
    return table.concat(lines, "\n")
  end
  viewer_console_cmds.review = function(w, i, verdict, note) return say(viewer_review(w, "review", i, verdict, note)) end
  viewer_console_cmds.update = function(w) return say(viewer_review(w, "update")) end
end

-- what a proposal changes, node by node: { { path, "added" | "changed" | "removed" } }
function R.summary(dir, p)
  local base = R.base(dir, p.from)
  local after = R.base(dir, p.to) or (base and R.result(base, p.patch))
  if not base or not after then return {} end
  local function nodes(blob)
    local ok, w = ecs.load(blob, "/")
    local t = {}
    if not ok then return t end
    for _, n in ipairs(w:select("/**")) do
      local ok2, b = w:save(n.path, true)
      if ok2 then t[n.path] = b end
    end
    return t
  end
  local a, b = nodes(base), nodes(after)
  local out = {}
  for k, v in pairs(b) do
    if a[k] == nil then out[#out + 1] = { k, "added" } elseif a[k] ~= v then out[#out + 1] = { k, "changed" } end
  end
  for k in pairs(a) do if b[k] == nil then out[#out + 1] = { k, "removed" } end end
  table.sort(out, function(x, y) return x[1] < y[1] end)
  return out
end

return R
