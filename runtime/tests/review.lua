-- review.lua - games have authors, changes are proposals, admins review
-- (runtime/review.lua), on a copy of games/pong. run.lua: "review".
--   cd runtime/tests && luajit review.lua [scratch dir]   (or lua5.4; from the root too)
local ROOT = io.open('games/pong/README.md') and '' or '../../'
package.path = ROOT .. 'runtime/?.lua;' .. package.path
local R = require 'review'
local E = require 'ed25519'
local fs = require 'fs'
local disk = require 'disk'
local ecs = require 'ecs'
local ok_n, bad = 0, 0
local function check(c, what) if c then ok_n = ok_n + 1 else bad = bad + 1; print('FAIL: ' .. what) end end

local tmp = (arg and arg[1]) or ((os.getenv('TMPDIR') or '/tmp') .. '/replay_review_test')
local game = fs.join(tmp, 'pong')
local function copy(from, to)                      -- (games/pong, file by file: no shell)
  fs.mkdir(to)
  for _, e in ipairs(fs.list(from)) do
    if e.dir then copy(fs.join(from, e.name), fs.join(to, e.name))
    else fs.write(fs.join(to, e.name), fs.read(fs.join(from, e.name))) end
  end
end
local function wipe(d)
  for _, e in ipairs(fs.list(d)) do
    local p = fs.join(d, e.name)
    if e.dir then wipe(p); fs.rmdir(p) else fs.rmfile(p) end
  end
end
fs.mkdir(tmp); wipe(tmp)
copy(ROOT .. 'games/pong', game)
local function blob() return select(2, disk.new(game):read('/**')) end
local function set(file, src) fs.write(fs.join(game, file), src) end

local AUTH = E.sha512('author seed'):sub(1, 32)
local ADM1 = E.sha512('admin one'):sub(1, 32)
local ADM2 = E.sha512('admin two'):sub(1, 32)
local OTHER = E.sha512('somebody'):sub(1, 32)
local admins = { R.public(ADM1), R.public(ADM2), R.public(AUTH) }   -- (the author an admin too: still never of its own game)
local dir = R.dir_of(game .. '/')
check(dir == game .. '.review', 'the review folder beside the game: ' .. dir)

-- the version: a hash of the authored world
local b0 = blob()
check(#R.version(b0) == 32 and R.version(b0) == R.version(b0:gsub('\n', '\r\n')), 'a version: 32 hex digits, CR LF read as LF')
local ok, w = ecs.load(b0, '/')
check(R.version(select(2, w:save('/**', true))) == R.version(b0), 'the same world saved again: the same version')

-- an author proposes
set('data/rules/win.lua', 'return 5\n')
local b1 = blob()
local p, path = R.propose(dir, 'pong', b1, AUTH, 'shorter games', b0)
check(p and path and p.from == R.version(b0) and p.to == R.version(b1), 'proposed: from the first version to the new one ' .. tostring(path))
local m = R.manifest(dir)
check(m and m.name == 'pong' and m.authors[1] == R.public(AUTH) and m.version == R.version(b0), 'the manifest: its author, the first version')
check(R.check(dir, p), 'the proposal checks: signed, and its patch makes the new version')
check(select(2, R.propose(dir, 'pong', b1, OTHER, 'mine')):find('not an author'), 'someone else can\'t propose')
check(select(2, R.propose(dir, 'pong', b0, AUTH)):find('nothing to propose'), 'the accepted version again: nothing to propose')

-- tampering
local forged = {}; for k, v in pairs(p) do forged[k] = v end
forged.note = 'longer games'
check(not R.check(dir, forged), 'a changed note: the signature fails')
forged.note = p.note; forged.patch = p.patch:gsub('win = 5', 'win = 50')
check(not R.check(dir, forged), 'a changed patch: it doesn\'t make the signed version')
local mf = fs.read(fs.join(dir, 'manifest.lua'))
fs.write(fs.join(dir, 'manifest.lua'), (mf:gsub(R.public(AUTH), R.public(OTHER))))
check(not R.manifest(dir), 'a manifest with another author: its signature fails')
fs.write(fs.join(dir, 'manifest.lua'), mf)

-- headless run, and what it changes
check(R.test(dir, p, 60), 'the patched world runs 60 ticks, no errors')
local sum = R.summary(dir, p)
check(#sum == 1 and sum[1][1] == '/data/rules' and sum[1][2] == 'changed', 'its summary: the changed node ' .. tostring(sum[1] and sum[1][1]))

-- reviews
check(R.state(p, m, admins) == 'waiting', 'nobody reviewed: waiting')
local okr, why = R.review(dir, path, AUTH, 'accept', 'lgtm', admins)
check(not okr and why:find('own game'), 'the author (an admin) can\'t review its own game: ' .. tostring(why))
okr, why = R.review(dir, path, OTHER, 'accept', '', admins)
check(not okr and why:find('not an admin'), 'not an admin: no review')
check(not R.review(dir, path, ADM1, 'maybe', '', admins), 'the verdict: accept or reject')
check(R.review(dir, path, ADM1, 'accept', 'ran it, fine', admins), 'an admin accepts')
local list = R.list(dir, admins)
check(#list == 1 and list[1].state == 'accepted' and list[1].acc == 1, 'accepted (one admin is enough for now)')
check(R.state(list[1].p, m, { R.public(ADM2) }) == 'waiting', 'a review by a key that isn\'t an admin there doesn\'t count')
-- a forged review: someone else's key in it
local raw = fs.read(path)
fs.write(path, (raw:gsub('ran it, fine', 'ran it, great')))
check(R.list(dir, admins)[1].state == 'waiting', 'a review whose note changed: no longer counts')
fs.write(path, raw)
check(R.review(dir, path, ADM2, 'reject', 'too short', admins), 'another admin rejects')
check(R.list(dir, admins)[1].state == 'rejected', 'a reject: rejected')
check(R.review(dir, path, ADM2, 'accept', 'ok then', admins), 'it changes its mind (its review replaced)')
list = R.list(dir, admins)
check(list[1].state == 'accepted' and list[1].acc == 2 and #list[1].p.reviews == 2, 'accepted by both: one review each')

-- a peer at the first version updates
set('data/rules/win.lua', 'return 7\n')                -- (the world back as it was: version 0)
local nx, mm = R.next(dir, R.version(blob()), admins)
check(nx and nx.p.to == R.version(b1), 'next for the first version: the accepted proposal')
local okw, pw = ecs.load(blob(), '/')
assert(ecs.load(nx.p.patch, '/', pw))
check(R.version(select(2, pw:save('/**', true))) == nx.p.to, 'applied to the live world: the new version')
check(disk.new(game):flush(pw, '/**') and R.version(blob()) == nx.p.to, 'flushed to the folder: the same version from disk')
check(R.manifest(dir).version == nx.p.to and R.manifest(dir).history[1] == R.version(b0), 'the manifest moves on, its history kept')
check(not R.next(dir, R.version(blob()), admins), 'up to date: nothing next')

-- the next proposal builds on it
set('data/rules/serve_speed.lua', 'return 300\n')
local p2 = R.propose(dir, 'pong', blob(), AUTH, 'faster serve', nil, admins)
check(p2 and p2.from == nx.p.to and R.check(dir, p2), 'the next proposal: over the accepted version')
local l2 = R.list(dir, admins)
check(#l2 == 2 and not l2[1].current and l2[2].current and l2[2].p.to == p2.to, 'two proposals listed in order, the current one marked')

-- a broken change: it fails the headless run
local sys = fs.join(game, 'systems/ball/system.lua')
fs.write(sys, 'error("boom")\n' .. fs.read(sys))
local p3 = R.propose(dir, 'pong', blob(), AUTH, 'oops', nil, admins)
local okt, err = R.test(dir, p3, 30)
check(p3 and not okt and tostring(err):find('boom'), 'a broken system fails the headless run: ' .. tostring(err))

wipe(tmp); fs.rmdir(tmp)
print(string.format('review: %d checks ok, %d failed', ok_n, bad))
os.exit(bad == 0 and 0 or 1)
