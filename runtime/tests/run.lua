-- run.lua - runs every test suite: the Lua ones (runtime/tests/*.lua, with
-- each interpreter given) and the editor's (replay run on its demos: the
-- graph, breakpoints, the text debugger, plugins, headless games, online
-- play over localhost). It copies the project to a temporary folder first,
-- so the tests never touch your files.
--
--   lua runtime/tests/run.lua                         (from the project's folder)
--   lua runtime/tests/run.lua --exe build/replay --lua luajit,lua5.4 --only break,dialog
--
--   --exe PATH     the replay to test (default: replay.exe / replay here)
--   --lua A,B      the interpreters for the Lua suites (default: the one running this)
--   --only A,B     just the suites whose names contain one of these
--   --list         the suites' names
--   --keep         leave the temporary copy (its path is printed)
--   --jobs N       suites at once (default: the computer's cores, at most 8; 1: one
--                  after another). Each runs in a copy of its own (and its own copy
--                  of the exe: its .preferences.lua apart); the suites that use the
--                  network run one after another (their ports), and so do the two
--                  review ones (the second reads what the first made)
-- Prints "== name: result" a suite (in the order they finish) and a summary;
-- exits 1 if any failed.
local WIN = package.config:sub(1, 1) == "\\"
local opt = { lua = {}, only = nil }
do
  local i = 1
  while arg[i] do
    local a, v = arg[i], arg[i + 1]
    if a == "--exe" then opt.exe = v; i = i + 1
    elseif a == "--lua" then for x in v:gmatch("[^,]+") do opt.lua[#opt.lua + 1] = x end i = i + 1
    elseif a == "--only" then opt.only = {}; for x in v:gmatch("[^,]+") do opt.only[#opt.only + 1] = x end i = i + 1
    elseif a == "--list" then opt.list = true
    elseif a == "--keep" then opt.keep = true
    elseif a == "--jobs" then opt.jobs = tonumber(v); i = i + 1
    elseif a == "--child" then opt.child = {}; for x in v:gmatch("%d+") do opt.child[#opt.child + 1] = tonumber(x) end i = i + 1   -- (a worker: these suites, here)
    elseif a == "--tmp" then opt.tmp = v; i = i + 1
    else io.stderr:write("run.lua: what is " .. a .. "? (see the top of runtime/tests/run.lua)\n"); os.exit(2) end
    i = i + 1
  end
end
if #opt.lua == 0 then
  local i, interp = -1, nil                        -- (the interpreter running this: the lowest negative arg)
  while arg[i] do interp = arg[i]; i = i - 1 end
  opt.lua[1] = interp or "lua"
end

local function q(s) return '"' .. s .. '"' end
local function exists(p) local f = io.open(p, "rb"); if f then f:close() return true end return false end
local SRC = "."
if not exists("replay.c") then io.stderr:write("run.lua: run it from the project's folder (where replay.c is)\n"); os.exit(2) end
local TMP = opt.tmp or ((os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("[/\\]$", "") .. "/replay-tests")
local OUT = TMP .. "/.test_out"                     -- (screenshots and logs the suites leave)
local function abs(p)                              -- the exe given, as a path that works from the copy
  if p:match("^/") or p:match("^%a:[/\\]") then return p end
  local cwd = WIN and io.popen("cd"):read("*l") or io.popen("pwd"):read("*l")
  return cwd .. "/" .. p
end
local EXE = opt.exe and abs(opt.exe) or nil

-- a command in the copy (dir: a folder of it), with the test settings; -> its output
local ENV = { NG_EXIT = "1", SDL_VIDEODRIVER = "offscreen", SDL_AUDIODRIVER = "dummy", REPLAY_PORTMAP = "0" }   -- (tests never ask your router to open ports)
local nbat = 0
local function shell(cmd, dir, background, log)
  dir = TMP .. (dir and ("/" .. dir) or "")
  if WIN then                                      -- (cmd.exe: the settings and the command in a batch file)
    nbat = nbat + 1
    local bat = OUT .. "/run" .. nbat .. ".bat"
    local f = assert(io.open(bat, "w"))
    f:write("@echo off\r\n")
    for k, v in pairs(ENV) do f:write("set " .. k .. "=" .. v .. "\r\n") end
    f:write("cd /d " .. q((dir:gsub("/", "\\"))) .. "\r\n", cmd, "\r\n")
    f:close()
    if background then os.execute('start /b "" cmd /c ' .. q(bat) .. " > " .. q(log) .. " 2>&1"); return "" end
    local p = io.popen(q(bat) .. " 2>&1")
    local s = p:read("*a"); p:close()
    return s
  end
  local env = {}
  for k, v in pairs(ENV) do env[#env + 1] = k .. "=" .. v end
  local line = "cd " .. q(dir) .. " && " .. table.concat(env, " ") .. " " .. cmd
  if background then os.execute("(" .. line .. " > " .. q(log) .. " 2>&1 &)"); return "" end
  local p = io.popen("(" .. line .. ") 2>&1")
  local s = p:read("*a"); p:close()
  return s
end
local function sleep(s) if WIN then os.execute("ping -n " .. (s + 1) .. " 127.0.0.1 > nul") else os.execute("sleep " .. s) end end
local function last(s, n)                          -- its last n lines
  local t = {}
  for l in s:gmatch("[^\r\n]+") do t[#t + 1] = l end
  return table.concat(t, " | ", math.max(1, #t - (n or 1) + 1))
end
local function grep(s, pats, n)                    -- the lines holding one of "a|b|c" (any case), the last n
  local t = {}
  for l in s:gmatch("[^\r\n]+") do
    local low = l:lower()
    for pat in pats:gmatch("[^|]+") do if low:find(pat, 1, true) then t[#t + 1] = l; break end end
  end
  return table.concat(t, " | ", math.max(1, #t - (n or 1) + 1))
end

-- the suites: { name, run = function() -> result text }
local suites = {}
local function add(name, f) suites[#suites + 1] = { name = name, run = f } end
local LUA_TESTS = { "tests", "net_players", "net_demo", "classes_props", "theme_colors", "plugins_mount", "canvas_graph",
  "assets_mount", "config_saves", "tree_undo", "asteroids", "modules", "net_links", "net_ghosts", "net_udp", "net_smooth",
  "net_lag_comp", "net_reconcile", "ecs_systems", "net_events", "net_bandwidth", "net_bundle", "hexedit_file", "dialog", "bullets", "nat", "autotile", "review", "actions", "collide", "options", "ties_order", "loc", "path", "flock", "soundgraph", "tmx", "teal" }
for _, t in ipairs(LUA_TESTS) do
  for _, L in ipairs(opt.lua) do
    add(t .. (#opt.lua > 1 and (" (" .. L .. ")") or ""), function() return last(shell(q(L) .. " " .. t .. ".lua", "runtime/tests")) end)
  end
end
local function exe() return q(EXE) end
local SHOT = function() return q(OUT .. "/x.bmp") end
-- in the editor: a script run in lite (dofile ...@3), events, then its checks' lines
local function lite(name, game, test, extra, pat, frames)
  add(name, function()
    local s = shell(exe() .. " " .. game .. ' --stopped --lite "dofile(REPLAY_ROOT .. \'/runtime/tests/' .. test .. '.lua\')@3" ' .. (extra or "")
                    .. " --frames " .. (frames or 100000) .. " --shot " .. SHOT())
    return grep(s, pat or "checks", 3)
  end)
end
local function play(name, test, extra)              -- (not stopped: the game plays from the start)
  add(name, function()
    local s = shell(exe() .. ' games/pong.lua --lite "dofile(REPLAY_ROOT .. \'/runtime/tests/' .. test .. '.lua\')@3" ' .. (extra or "") .. " --frames 100000 --shot " .. SHOT())
    return grep(s, "checks|ok|fail|passed", 2)
  end)
end
local function headless(name, args) add(name, function() return last(shell(exe() .. " " .. args)) end) end

lite("ui", "games/pong.lua", "nodegraph_ui", "", "passed|failed|fail", 900000)
lite("text boxes", "games/pong.lua", "textproxy", "", "text boxes|FAIL")
lite("tab typing", "games/pong.lua", "sidetab_typing", '--events "l60,43@20 k112,0@40 K112,0@41" --type "p@40"', "sidetab typing")
play("break", "nodegraph_break", '--events "l16,494@300 l16,494@500"')
play("probe", "nodegraph_probe", '--events "l16,494@240 l44,494@600"')
add("graph of Teal", function()                    -- (games/blocks.tl's graph: read, typed pins, the probe on its lines)
  local s = shell(exe() .. ' games/blocks.tl --lite "dofile(REPLAY_ROOT .. \'/runtime/tests/nodegraph_teal.lua\')@3" --events "l16,494@240" --frames 100000 --shot ' .. SHOT())
  return grep(s, "checks|ok|fail|passed", 2)
end)
add("graph moves (Teal)", function()                -- (every node of games/blocks.tl moved and back: the text as it was)
  return last(shell(q(opt.lua[1]) .. " runtime/tests/nodegraph_moves.lua games/blocks.tl"))
end)
play("late", "nodegraph_probe_late", '--events "l16,494@60"')
play("mixed", "nodegraph_probe_mixed", '--events "l80,14@30 l80,14@40"')
play("release", "nodegraph_release", '--events "W520,240@20 W520,240@21 W520,240@22 W520,240@23 W520,240@24 W520,240@25 W520,240@26 W520,240@27 l16,494@40 x230,100@200 m300,120@205 m520,240@210 X520,240@215"')
play("boot", "nodegraph_break_boot", '--events "l72,494@200 l16,494@400"')
lite("play_unsaved", "games/pong.lua", "play_unsaved", '--events "l16,494@120"')
lite("play_check", "games/pong.lua", "play_check", '--events "l16,494@400 l16,494@1000"')
lite("plugins_new", "games/pong.lua", "plugins_new", "", "plugins new|error", 6000)
lite("plugins_more", "games/pong.lua", "plugins_more", "", "plugins more|fail|error", 6000)
lite("text_debug", "games/pong.lua", "text_debug", '--events "l16,494@60"')
lite("dialog_edit", "games/pong.lua", "dialog_edit", "", "dialog edit|fail|error", 6000)
lite("break_load", "games/asteroids", "break_load", '--events "l16,574@60"')
lite("bullets_edit", "games/pong.lua", "bullets_edit", "", "bullets edit|fail|error", 6000)
lite("options_edit", "games/pong.lua", "options_edit", "", "options edit|fail|error", 6000)
lite("nodegraph_arrange", "games/pong.lua", "nodegraph_arrange", "", "nodegraph arrange|fail|error", 6000)
lite("loc_edit", "games/pong.lua", "loc_edit", "", "loc edit|fail|error", 6000)
lite("tilemap_path", "games/pong.lua", "tilemap_path", "", "tilemap path|fail|error", 6000)
lite("tilemap_shapes", "games/pong.lua", "tilemap_shapes", "", "tilemap shapes|fail|error", 6000)
lite("flock_edit", "games/pong.lua", "flock_edit", "", "flock edit|fail|error", 6000)
lite("dungeon_chain", "games/pong.lua", "dungeon_chain", "", "dungeon chain|fail|error", 6000)
lite("soundgraph_edit", "games/pong.lua", "soundgraph_edit", "", "soundgraph edit|fail|error", 6000)
play("values", "nodegraph_values")
headless("flocking", "games/flocking.lua --headless --ticks 300 --key \"2@150\" --type \"local s = w:node('/data/state').c; assert(s.kind == 'fish' and #s.flock.b == 90 and #w:node('/objects/flock').c.tris == 540)@299\"")
headless("hop options", "games/hop --headless --ticks 130 --key \"o@10-11\" --key \"down@20-21\" --key \"down@30-31\" --key \"right@40-41\""
  .. " --key \"escape@70-71\" --key \"return@80-81\" --type \"assert(w:node('/data/state').c.prefs.jump == 'High' and not w:node('/data/state').c.prefs.paused)@120\"")
headless("blocks (Teal)", "games/blocks.tl --headless --ticks 400 --key \"space@60-61\" --key \"left@100-101\" --key \"up@140-141\" --key \"space@150-151\" --type \"local s = w:node('/data/state').c; assert(next(w.code_err) == nil and not ecs.warnings['blocks.tl'] and s.piece.kind > 0 and #ls('/entities/cells') >= 8)@399\"")
headless("headless", "games/asteroids --headless --ticks 300 --key \"space@10-200\" --type \"assert(#ls('/entities') > 0)@299\"")
add("headless fails", function()                    -- (a failed check: exit 1)
  local s = shell(exe() .. ' games/pong.lua --headless --ticks 5 --type "assert(false)@3"' .. (WIN and "\r\necho exit %errorlevel%" or "; echo exit $?"))
  return s:find("exit 1", 1, true) and "exit 1 (ok)" or ("expected exit 1: " .. last(s))
end)
-- online suites: processes started one after the other, each once the one
-- before says it's up (its log), not after a fixed wait: slow starts (a
-- cold Windows) no longer make them flaky. Each host outlives its joiner.
local function read(f) local h = io.open(f, "rb"); local t = h and h:read("*a") or ""; if h then h:close() end; return t end
local function wait_log(f, pat, secs)               -- -> true once the log has pat (a Lua pattern), false after secs
  local t0 = os.time()
  repeat
    if read(f):find(pat) then return true end
    if WIN then sleep(1) else os.execute("sleep 0.25") end
  until os.time() - t0 > (secs or 15)
  return read(f):find(pat) ~= nil
end
local function online(name, port, host_args, join_args, host_ticks)
  add(name, function()
    local log = OUT .. "/" .. name .. ".log"
    os.remove(log)
    shell(exe() .. " games/pong --headless --ticks " .. (host_ticks or 720) .. " --host " .. port .. " " .. host_args, nil, true, log)
    if not wait_log(log, "online: hosting") then return "the host never started: " .. last(read(log)) end
    local s = last(shell(exe() .. " games/pong --headless --join 127.0.0.1:" .. port .. " " .. join_args))
    wait_log(log, "headless: %d+ ticks", 20)
    return s .. " / host: " .. last(read(log))
  end)
end
-- (the joiner: 600 ticks, there from the host's ~1 s to ~11 s; the host checks at 8 s)
online("online", 47777, "--type \"assert(w.players[2])@480\" --type \"assert(w:node('/objects/right').c.xform.y < -100)@480\"",
  "--ticks 600 --key \"w@60-250\" --type \"assert(viewer_online_player() == 2)@200\"")
-- (the joiner is in by its 150th tick; the host lets player 3 go at its 320th; the joiner sees it by its 490th)
online("seats", 47787, "--type \"assert(w.players[3] and not w.players[2])@300\" --type \"viewer_players_click(w, 3)@320\" --type \"assert(not w.players[3] and viewer_online_mask() == 1)@400\"",
  "--ticks 500 --type \"viewer_online_set(true, 'join'); viewer_players_click(w, 3); assert(viewer_online_player() == nil)@1\" --type \"assert(viewer_online_player() == 3)@150\" --type \"assert(viewer_online_mask() == 0)@490\"", 480)
add("routers", function()                         -- (an introducer, a host known to it as a room, a joiner by the room: nat.lua)
  local ilog, hlog = OUT .. "/routers_intro.log", OUT .. "/routers_host.log"
  os.remove(ilog); os.remove(hlog)
  shell(exe() .. " games/pong --headless --ticks 1200 --introducer", nil, true, ilog)   -- (no ports anywhere: by name)
  if not wait_log(ilog, "online: introducing") then return "the introducer never started: " .. last(read(ilog)) end
  shell(exe() .. " games/pong --headless --ticks 720 --via room1@127.0.0.1 --type \"assert(w.players[2] and viewer_online_info():find('room1@', 1, true))@480\"", nil, true, hlog)
  if not wait_log(hlog, "online: hosting") then return "the host never started: " .. last(read(hlog)) end
  local s = last(shell(exe() .. " games/pong --headless --ticks 600 --join room1@127.0.0.1 --type \"assert(viewer_online_player() == 2)@240\""))
  wait_log(hlog, "headless: %d+ ticks", 20)
  return s .. " / host: " .. last(read(hlog))
end)
add("lobby", function()                           -- (two hosts on this computer; a scan lists both; join() with no address takes one)
  local la, lb = OUT .. "/lobby_a.log", OUT .. "/lobby_b.log"
  os.remove(la); os.remove(lb)
  shell(exe() .. " games/pong --headless --ticks 600 --host", nil, true, la)
  if not wait_log(la, "online: hosting") then return "host A never started: " .. last(read(la)) end
  shell(exe() .. " games/pong --headless --ticks 600 --host", nil, true, lb)
  if not wait_log(lb, "online: hosting") then return "host B never started: " .. last(read(lb)) end
  local s = last(shell(exe() .. " games/pong --headless --ticks 260 --type \"viewer_lobby_scan()@1\" --type \"assert(#viewer_lobby() == 2, #viewer_lobby())@90\""
    .. " --type \"assert(select(2, viewer_lobby_items():gsub('1 in, 3 free', '')) == 2)@92\""   -- (the Players button's lobby menu: both, who's in)
    .. " --type \"assert(select(2, viewer_lobby_pick(w, 4, 3)):find('joins', 1, true) and viewer_lobby_pick(w, 1) == true)@94\""   -- (a host picked for seat 3; Type an address: asks)
    .. " --type \"assert(viewer_console_cmds.join(w, '*'):find('joining', 1, true))@100\" --type \"assert(viewer_online_player() == 3)@240\""))
  wait_log(la, "headless: %d+ ticks", 20); wait_log(lb, "headless: %d+ ticks", 20)
  return s
end)
local function with_env(vars, cmd)                 -- (environment variables for one command)
  local pre = {}
  for k, v in pairs(vars) do pre[#pre + 1] = WIN and ('set "' .. k .. "=" .. v .. '" & ') or (k .. "=" .. v .. " ") end
  return table.concat(pre) .. cmd
end
add("peer id", function()                         -- (a host known by its peer ID, its key's hash: joined by the ID nearby, and through an introducer, both proven)
  local il, hl = OUT .. "/peer_intro.log", OUT .. "/peer_host.log"
  os.remove(il); os.remove(hl)
  local HOST, JOINER = string.rep("11", 32), string.rep("22", 32)   -- (keys: their IDs WD4GYN3, XWBB58J)
  shell(exe() .. " games/pong --headless --ticks 1200 --introducer", nil, true, il)
  if not wait_log(il, "online: introducing") then return "the introducer never started: " .. last(read(il)) end
  shell(with_env({ REPLAY_PEER_KEY = HOST, REPLAY_INTRODUCERS = "127.0.0.1" }, exe() .. " games/pong --headless --ticks 900 --host"), nil, true, hl)
  if not wait_log(hl, "online: hosting") then return "the host never started: " .. last(read(hl)) end
  if not read(hl):find('join("WD4GYN3")', 1, true) then return "the host doesn't say its ID (its key's): " .. last(read(hl)) end
  local a = last(shell(with_env({ REPLAY_PEER_KEY = JOINER }, exe() .. " games/pong --headless --ticks 240 --join wd4g-yn3 --type \"assert(viewer_online_player() == 2)@200\"")))
  local b = last(shell(with_env({ REPLAY_PEER_KEY = JOINER }, exe() .. " games/pong --headless --ticks 360 --join WD4GYN3@127.0.0.1 --type \"assert(viewer_online_player() == 2)@300\"")))
  wait_log(hl, "headless: %d+ ticks", 20)
  return "nearby: " .. a .. " / introduced: " .. b .. " / host: " .. last(read(hl))
end)
add("review (editor)", function()                          -- (games have authors, changes are proposals, admins review: runtime/review.lua, on copies of pong)
  local AUTH, ADMIN = string.rep("11", 32), string.rep("22", 32)
  local APK = "a09aa5f47a6759802ff955f8dc2d2a14a5c99d23be97f864127ff9383455a4f0"   -- (ADMIN's public key; the author's d04ab232...: an admin too, never of its own game)
  local function cp(a, b)
    if WIN then os.execute('xcopy "' .. (TMP .. "/" .. a):gsub("/", "\\") .. '" "' .. (TMP .. "/" .. b):gsub("/", "\\") .. '\\" /e /i /q /y > nul')
    else os.execute("cp -r " .. q(TMP .. "/" .. a) .. " " .. q(TMP .. "/" .. b)) end
  end
  cp("games/pong", "games/rv_author"); cp("games/pong", "games/rv_peer")
  local W = "local f = io.open('games/rv_author/data/rules/win.lua', 'wb'); f:write('return 5'); f:close(); viewer_poll(w)"
  local a = shell(with_env({ REPLAY_PEER_KEY = AUTH, REPLAY_ADMINS = APK .. ",d04ab232742bb4ab3a1368bd4615e4e6d0224ab71a016baf8520a332c9778737" }, exe() .. " games/rv_author --headless --ticks 5"
    .. " --type \"assert(propose():find('you author'))@1\" --type \"" .. W .. "@2\""
    .. " --type \"assert(propose('shorter games'):find('proposed'))@3\" --type \"assert(review(1, 'accept'):find('own game'))@4\""))
  local b = shell(with_env({ REPLAY_PEER_KEY = ADMIN, REPLAY_ADMINS = APK }, exe() .. " games/rv_author --headless --ticks 4"
    .. " --type \"assert(proposals():find('waiting'))@1\" --type \"assert(review(1, 'accept', 'fine') == 'accepted')@2\""
    .. " --type \"assert(proposals():find('accepted'))@3\""))
  cp("games/rv_author.review", "games/rv_peer.review")
  local c = shell(with_env({ REPLAY_ADMINS = APK }, exe() .. " games/rv_peer --headless --ticks 4"
    .. " --type \"assert(update():find('updated to'))@1\" --type \"assert(w:node('/data/rules').c.win == 5)@2\" --type \"assert(update():find('up to date'))@3\""))
  return "author: " .. last(a) .. " / admin: " .. last(b) .. " / peer: " .. last(c)
end)
add("review tab", function()                      -- (the Review tab on the author's copy: its proposal, picked, run; run after "review (editor)")
  local s = shell(with_env({ REPLAY_PEER_KEY = string.rep("11", 32), REPLAY_ADMINS = "a09aa5f47a6759802ff955f8dc2d2a14a5c99d23be97f864127ff9383455a4f0" }, exe() .. ' games/rv_author --stopped --lite "dofile(REPLAY_ROOT .. \'/runtime/tests/review_tab.lua\')@3" --frames 100000 --shot ' .. SHOT()))
  return grep(s, "review tab|FAIL", 3)
end)
add("auto fade", function()                     -- (the eye: one opacity. Play: 100% in a short fade, the keys the game's; the eye: 75% / 0%; Pause: 75%; the wheel keeps its value; Stop: 0%; a click in the editor takes the keys)
  local H = "local f, on, keys, b = host_fade(); "
  local s = shell(exe() .. " games/pong.lua --stopped --events \"l 16,494@20 l 70,14@70 l 70,14@80 l 70,14@90 l 16,494@100 W 70,14@110 w 70,14@115 l 44,494@120 l 16,494@160 l 70,14@205 l 500,300@215 l 16,494@230\""
    .. " --type \"" .. H .. "assert(f == 0 and not on and b == 0.75, 'stopped: ' .. f)@10\""
    .. " --type \"" .. H .. "assert(f == 1 and not on and keys, 'play: ' .. f)@60\""
    .. " --type \"" .. H .. "assert(f == 0.75 and keys, 'the eye: ' .. f)@72\""
    .. " --type \"" .. H .. "assert(f == 0, 'the eye again: ' .. f)@82\""
    .. " --type \"" .. H .. "assert(f == 0.75, 'and again: ' .. f)@92\""
    .. " --type \"" .. H .. "assert(f == 0.75 and not keys, 'pause: ' .. f)@105\""
    .. " --type \"" .. H .. "assert(math.abs(f - 0.7) < 0.001 and math.abs(b - 0.7) < 0.001, 'the wheel: ' .. f .. ' ' .. b)@112\""
    .. " --type \"" .. H .. "assert(math.abs(f - 0.75) < 0.001 and math.abs(b - 0.75) < 0.001, 'wheel back: ' .. f)@117\""
    .. " --type \"" .. H .. "assert(f == 0, 'stop: ' .. f)@150\""
    .. " --type \"" .. H .. "assert(f == 1 and keys, 'play again: ' .. f)@200\""
    .. " --type \"" .. H .. "assert(f == 0.75 and keys, 'the eye, playing: ' .. f)@210\""
    .. " --type \"" .. H .. "assert(f == 0.75 and not keys, 'a click in the editor: the keys its')@225\""
    .. " --type \"" .. H .. "assert(math.abs(f - 0.75) < 0.001 and not on, 'pause at 75%: ' .. f); print('auto fade: ok')@270\""
    .. " --frames 280 --shot " .. SHOT())
  return grep(s, "auto fade: ok|error|! console", 3)
end)
add("error overlay", function()                  -- (a system fails: the overlay, modal, paused, its line; Enter: on, the rest still run; w:panic too)
  local F = "local on, title, n, paused = host_fatal(); "
  local s = shell(exe() .. " runtime/tests/fatal_game.lua --key \"return@60\" --key \"escape@120\""
    .. " --type \"" .. F .. "assert(on and paused and n == 1 and title:find('failed', 1, true), 'failed: ' .. tostring(on) .. ' ' .. tostring(title)); local _, _, list = viewer_errors(w); assert(list[1].file:find('fatal_game.lua', 1, true) and list[1].line == 11, 'its line: ' .. tostring(list[1].file) .. ':' .. tostring(list[1].line))@40\""
    .. " --type \"local src = viewer_source(w, '/systems/boom'); assert(src[1].line == 11, 'the red row opens its line: ' .. tostring(src[1].line)); w.f0 = w:node('/data/count').c.fine@41\""
    .. " --type \"" .. F .. "assert(not on and not paused, 'Enter: on'); assert(w:node('/data/count').c.fine > w.f0, 'the rest go on'); w:panic('Out of fuel', 'one\\ntwo')@80\""
    .. " --type \"" .. F .. "assert(on and paused and title == 'Out of fuel' and n == 2, 'a panic: ' .. tostring(title) .. ' ' .. tostring(n)); w.on_panic_closed = function(w) w.closed = true end@100\""
    .. " --type \"" .. F .. "assert(not on and w.closed and not w.panicked, 'ESC: closed'); print('the overlay: ok')@140\""
    .. " --frames 150 --shot " .. SHOT())
  return grep(s, "= the overlay: ok|! console", 3)
end)
add("step mode", function()                      -- (paused: a tick on, played; a tick back, from the snapshots; the wheel over the timeline replays it)
  local X = "w:node('/objects/ball').c.xform.x"
  local s = shell(exe() .. " games/pong.lua --events \"l 16,494@60 l 233,494@80 l 212,494@100 w 400,494@110\""
    .. " --type \"w.x0 = " .. X .. "@70\""
    .. " --type \"w.x1 = " .. X .. "; assert(w.x1 ~= w.x0, 'a tick on: moved')@90\""
    .. " --type \"assert(math.abs(" .. X .. " - w.x0) < 1e-6, 'a tick back: as before')@105\""
    .. " --type \"local a, b = w:text_size('one two three four five six', 'sans', 16); local c, d = w:text_size('one two three four five six', 'sans', 16, 60); assert(c <= 60 and d > b and a > 60, 'text_size wrapped (host)')@112\""
    .. " --type \"assert(math.abs(" .. X .. " - w.x1) < 1e-6, 'the wheel: a tick on again'); print('step mode: ok')@115\""
    .. " --frames 120 --shot " .. SHOT())
  return grep(s, "step mode: ok|error|! console", 3)
end)
headless("audio", "games/pong.lua --headless --ticks 20 --type \"dofile('runtime/tests/audio.lua')@2\"")
local AK = "local b = w:node('/objects/ball').c; local d = w:node('/data/game').c"
headless("arkanoid", "games/arkanoid.lua --headless --ticks 60"   -- (the ball waits; a fast ball can't pass the paddle; a brick from below)
  .. " --type \"" .. AK .. "; assert(not d.started and b.xform.y == 145)@5\""
  .. " --type \"" .. AK .. "; d.started = true; b.xform.x, b.xform.y = 30, 100; b.vel.x, b.vel.y = 0, 3000@10\""
  .. " --type \"" .. AK .. "; assert(b.vel.y < 0 and b.xform.y < 160 and math.abs(math.sqrt(b.vel.x ^ 2 + b.vel.y ^ 2) - 300) < 1)@12\""
  .. " --type \"" .. AK .. "; b.xform.x, b.xform.y = -75, 20; b.vel.x, b.vel.y = 0, -300@20\""
  .. " --type \"" .. AK .. "; assert(d.score == 10 and b.vel.y > 0)@24\"")
local D = "local s = w:node('/data/state').c"
headless("deepisle", "games/deepisle.lua --headless --ticks 160"
  .. " --type \"" .. D .. "; local n = 0; for _ in pairs(s.levels) do n = n + 1 end; assert(n == 9 and s.left == s.total and s.total > 20 and #s.levels.isle.stairs == 3, n)@2\""
  .. " --type \"" .. D .. "; local st = s.levels.isle.stairs[1]; s.p.x, s.p.y, s.p.lock = st.x, st.y, nil@5\""   -- (onto a stair: down)
  .. " --type \"" .. D .. "; assert(s.level == 'd1-1' and s.p.lock, s.level)@8\""
  .. " --type \"" .. D .. "; local m = s.levels[s.level].monsters[1]; m.x, m.y, m.hp, m.stun = s.p.x + 20, s.p.y, 1, 99@10\" --key \"d@12-50\""   -- (walked into: killed)
  .. " --type \"" .. D .. "; assert(s.p.kills == 1 and s.left == s.total - 1, s.p.kills)@55\""
  .. " --type \"" .. D .. "; s.left = 1; local m = s.levels[s.level].monsters[1]; m.x, m.y, m.hp, m.stun = s.p.x - 20, s.p.y, 1, 99@60\" --key \"a@62-100\""
  .. " --type \"" .. D .. "; assert(s.mode == 'won', s.mode)@105\" --key \"r@110\""   -- (the last one: won; R: a new island)
  .. " --type \"" .. D .. "; assert(s.mode == 'play' and s.level == 'isle' and s.p.kills == 0)@115\""
  .. " --type \"" .. D .. "; s.p.hp = 1; s.levels.isle.monsters[1] = { kind = 'slime', x = s.p.x + 6, y = s.p.y, hp = 3, max = 3, dmg = 2, speed = 0, sight = 0, cool = 0, stun = 0, wx = 0, wy = 0, wt = 9, flash = 0 }@120\""
  .. " --type \"" .. D .. "; assert(s.mode == 'dead', s.mode)@150\"")   -- (bitten: dead)
headless("portmap", "games/pong.lua --headless --ticks 2 --type \"dofile('runtime/tests/portmap.lua')@1\"")
add("by name", function()                         -- (ports by name: two hosts on one computer take the game's 1st and 2nd ports; a joiner finds one by the address alone)
  local la, lb = OUT .. "/byname_a.log", OUT .. "/byname_b.log"
  local P = "local P = require('net').ports('replay:' .. viewer_game_name()); "
  os.remove(la); os.remove(lb)
  shell(exe() .. " games/pong --headless --ticks 720 --host --type \"" .. P .. "assert(viewer_online_info():find('port ' .. P[1], 1, true))@60\"", nil, true, la)
  if not wait_log(la, "online: hosting") then return "host A never started: " .. last(read(la)) end
  shell(exe() .. " games/pong --headless --ticks 660 --host --type \"" .. P .. "assert(viewer_online_info():find('port ' .. P[2], 1, true))@60\"", nil, true, lb)
  if not wait_log(lb, "online: hosting") then return "host B never started: " .. last(read(lb)) end
  local s = last(shell(exe() .. " games/pong --headless --ticks 300 --join 127.0.0.1 --type \"assert(viewer_online_player() == 2)@200\""))
  wait_log(la, "headless: %d+ ticks", 20); wait_log(lb, "headless: %d+ ticks", 20)
  return s .. " / hosts: " .. last(read(la)) .. " ; " .. last(read(lb))
end)
headless("lcd", "games/lcd --headless --ticks 300 --key \"right@50\" --type \"assert(w:node('/data/game').c.state.man == 3)@100\"")
headless("tree+layers", "games/asteroids --headless --ticks 2 --type \"assert(table.concat(viewer_layers(w), ',') == 'default,fx,hud')@1\" --type \"assert(viewer_tree_menu(w, '/classes'):find('New class', 1, true))@1\"")
headless("power", "games/pong --headless --ticks 20 --type \"assert(not viewer_online_mode() and viewer_online_mask() == -1)@2\" --type \"assert(viewer_console_cmds.host(w, 47781):find('hosting on port 47781'))@5\" --type \"assert(viewer_online_mode() and viewer_online_info():find('hosting') and viewer_online_mask() == 1)@8\" --type \"assert(viewer_console_cmds.leave() == 'offline' and not viewer_online_mode() and not viewer_online_info())@12\"")
add("power (play hosts)", function()
  local s = shell(exe() .. " games/pong.lua --stopped --host 47786 --events \"l16,494@20\" --frames 90 --shot " .. SHOT())
  return s:find("hosting pong.lua on port 47786", 1, true) and "hosted on Play (ok)" or ("not hosted: " .. last(s))
end)
local S = "local s=w:node('/data/state').c.round; local function items() local n = 0; for _, c in ipairs(w:children('/entities')) do if c.c.gem or c.c.door then n = n + 1 end end; return n end"   -- (items: the gems and the door; the options menu's state is there too)
headless("hop", "games/hop --headless --ticks 340 --type \"" .. S .. "; assert(s.started and s.total == 6 and s.on_ground and items() == 7)@100\" --key \"right@120-200\" --type \"" .. S .. "; assert(s.deaths >= 1 and s.x < -190)@220\" --type \"" .. S .. "; s.x, s.y, s.vx, s.vy = -136, 32, 0, 0@230\" --type \"" .. S .. "; assert(s.gems == 1 and items() == 6, s.gems)@236\" --type \"" .. S .. "; s.gems = s.total@240\" --type \"assert(w:node('/entities/door').c.door.open)@244\" --type \"" .. S .. "; local d = w:node('/entities/door').c.xform; s.x, s.y = d.x, d.y@246\" --type \"" .. S .. "; assert(s.won)@250\" --key \"space@320\" --type \"" .. S .. "; assert(not s.won and s.gems == 0 and items() == 7)@330\"")
local O = "local s = w:node('/data/state').c"
headless("orbitbreak", "games/orbitbreak.lua --headless --ticks 1530 --key \"space@50\" --type \"" .. O .. "; assert(s.energy < 0.1 and s.pulse > 0)@52\" --type \"" .. O .. "; assert(#s.rings > 0 and s.score > 0)@300\" --type \"" .. O .. "; assert(s.dead and s.best > 0)@1500\" --key \"r@1510\" --type \"" .. O .. "; assert(not s.dead and s.score < 5 and #s.rings == 0)@1515\"")
headless("pad", "games/starfall.lua --headless --ticks 100 --key \"pad left@10-90\" --type \"assert(w:node('/data/state').c.x < -300)@95\"")
local F = "local s = w:node('/data/state').c"
headless("starfall", "games/starfall.lua --headless --ticks 1100 --type \"w.mouse = { x = -200, y = 150, inside = true, left = true }; " .. F .. "; s.lives = 99@2\""
  .. " --type \"" .. F .. "; assert(s.score > 0 and #s.sg.ships > 0, s.score)@400\""
  .. " --type \"" .. F .. "; s.sg.t = 60; for _, e in ipairs(s.sg.ships) do e.hp = 0 end@410\""
  .. " --type \"" .. F .. "; assert(s.sg.mode == 'boss' and s.sg.boss and s.sg.boss.in_ and #s.sg.bul.bullets > 20, s.sg.mode)@900\""
  .. " --type \"" .. F .. "; s.sg.boss.hp = 1; w.mouse.x = s.sg.boss.x@910\""
  .. " --type \"" .. F .. "; assert(s.mode == 'won', s.mode); assert(s.boss_done == 1 and s.score >= 50 and s.score <= 100, s.score); w.mouse.left = false@1000\""
  .. " --type \"w.mouse.left = true@1010\""
  .. " --type \"" .. F .. "; assert(s.mode == 'play' and s.score == 0, s.mode)@1020\"")
local T = "local p = w:loadgame('tutorial') or {step=1}"
headless("tutorial", "games/tutorial.lua --headless --ticks 440 --key \"right@5-330\" --key \"l@370-371\" --type \"" .. T .. "; assert(p.step == 3, 'played, walked: ' .. p.step)@330\" --type \"local f = viewer_editor_frame; assert(f(w, 'playing', '', 5.5, 1, false) == 'picking', 'the picking card'); assert(f(w, 'playing', '', 5.5, 1, true) == 'game', 'picking on'); assert(f(w, 'playing', '/objects/beacon', 5.5, 1, true) == 'picking', 'picked: picking off next'); assert(f(w, 'playing', '/objects/beacon', 5.5, 1, false) == 'props', 'picking off'); local b = w:node('/objects/beacon').c.beacon; assert(b.intensity == 0 and b.pulse_speed == 50, 'the class: ' .. tostring(b.intensity)); b.intensity = 60; w:hear_editor('edit', { paths = { '/objects/beacon' }, keys = { 'beacon', 'intensity' } }); " .. T .. "; assert(p.step == 6, 'not 100 yet: ' .. p.step); b.intensity = 100; w:hear_editor('edit', { paths = { '/objects/beacon' }, keys = { 'beacon', 'intensity' } }); " .. T .. "; assert(p.step == 7 and w.pointing == 'props', 'intensity: ' .. p.step); b.pulse_speed = 80; w:hear_editor('edit', { paths = { '/objects/beacon' }, keys = { 'beacon', 'pulse_speed' } }); " .. T .. "; assert(p.step == 8 and w.pointing == 'timeline', 'pulse: ' .. p.step)@340\" --type \"" .. T .. "; assert(p.step == 8 and w:node('/data/state').c.lit_at and w.pointing_note:find('Time travel', 1, true) and w.pointing_note:find('8 / 16', 1, true) and not w:node('/objects/beacon/light').c.hidden, 'lit: ' .. p.step .. ' ' .. tostring(w.pointing_note)); w.r1 = w:node('/objects/beacon/light').c.circle.r@360\" --type \"assert(w.pointing_note:find('Viaje en el tiempo', 1, true), 'L: Spanish: ' .. tostring(w.pointing_note)); assert(w:node('/objects/beacon/light').c.circle.r ~= w.r1, 'it pulses'); w:language('en')@380\" --type \"local f = viewer_editor_frame; w:node('/data/state').c.lit_at = false; w:hear_editor('seek', { t = 1, back = true }); " .. T .. "; assert(p.step == 9 and w.pointing == nil and w.pointing_note:find('Maximize', 1, true), 'rewound: ' .. p.step .. ' ' .. tostring(w.pointing)); local L = w:node('/data/state').c.speed_line; assert(L > 100 and L < 200, 'the speed line: ' .. L); f(w, 'playing', '', 5.5, 1, false, 'text', false, 1, true); " .. T .. "; assert(p.step == 10 and w.pointing == 'eye', 'maximized: ' .. p.step .. ' ' .. tostring(w.pointing)); f(w, 'playing', '', 5.5, 0.75, false, 'text', false, 1, true); " .. T .. "; assert(p.step == 11 and w.pointing == 'game', 'the eye: ' .. p.step); local _, note = f(w, 'playing', '', 5.5, 0.75, false, 'text', false, L, true); " .. T .. "; assert(p.step == 12 and w.pointing == 'game' and note and note:find('CTRL+', 1, true), 'on its line: ' .. p.step .. ' ' .. tostring(note)); f(w, 'playing', '', 5.5, 0.75, false, 'both', false, L, true); " .. T .. "; assert(p.step == 13 and w.pointing == 'game', 'beside: ' .. p.step); w:hear_editor('code', { unsaved = true, text = '\\n    local speed = 200' }); " .. T .. "; assert(p.step == 14 and w.pointing == 'game', 'edited: ' .. p.step); w:hear_editor('code', { unsaved = true, text = '\\n    local speed = fast' }); " .. T .. "; assert(p.step == 15 and w.pointing == 'rewind', 'wired: ' .. p.step); local fp = viewer_game_path(); local fh = io.open(fp, 'rb'); local src = fh:read('*a'); fh:close(); assert(viewer_unsaved_take(w, { [viewer_unsaved_key(fp)] = (src:gsub('local speed = 120', 'local speed = fast', 1)) }), 'the edited text taken')@400\" --type \"" .. T .. "; assert(p.step == 16 and w:node('/data/state').c.speed == 300 and w.pointing_note:find('You lit the beacon!', 1, true), 'ran: ' .. p.step .. ' ' .. tostring(w:node('/data/state').c.speed)); w:hear_editor('stopped', { from = 'playing' }); assert(w.pointing == 'play' and w.pointing_note:find('Press Play', 1, true), 'stopped: ' .. tostring(w.pointing_note)); local tw, th = w:text_size('Hello', 'sans', 20); assert(tw > 20 and th >= 15, 'text_size')@420\"")
headless("fairyland", "games/fairyland --headless --ticks 400 --key \"right@10-40\" --type \"" .. O .. "; assert(s.walk.x > -110); local f = w:node('/objects/fairy').c.xform; assert(f.x == 40 and f.y == -40, 'not friends yet: she stays put')@45\" --type \"" .. O .. "; local f = w:node('/objects/fairy').c.xform; s.walk.x, s.walk.y = f.x, f.y + 10@50\" --key \"space@60\" --type \"" .. O .. "; assert(s.talk.on and s.talk.at == 0)@100\" --key \"space@110\" --key \"space@120\" --type \"" .. O .. "; assert(s.talk.at == 3, s.talk.at)@200\" --key \"space@210\" --type \"" .. O .. "; assert(not s.talk.on and s.talk.start == 5)@220\" --key \"space@230\" --key \"down@300\" --type \"" .. O .. "; assert(s.talk.on and s.talk.at == 5 and s.talk.pick == 2, tostring(s.talk.at) .. ' ' .. s.talk.pick)@320\"")

-- a result: passed? (no failure named, and something to read)
local function passed(r)
  local l = r:lower()
  if r == "" then return false end
  if l:find("[c]:", 1, true) or l:find("traceback", 1, true) then return false end   -- (a Lua error's last line)
  if l:find("! console", 1, true) then return false end   -- (a --type line that failed: its assert)
  if l:find("fail:", 1, true) or l:find("error", 1, true) or l:find("expected", 1, true) or l:find("not hosted", 1, true) then return false end
  for n in l:gmatch("(%d+) failed") do if n ~= "0" then return false end end
  if l:find("headless:", 1, true) and not l:find(" ok ", 1, true) then return false end
  return true
end

local chosen = {}
for _, s in ipairs(suites) do
  local ok = not opt.only
  for _, o in ipairs(opt.only or {}) do if s.name:find(o, 1, true) then ok = true end end
  if ok then chosen[#chosen + 1] = s end
end
if opt.list then for _, s in ipairs(chosen) do print(s.name) end return end

-- a worker (--child): the suites by their index, one after another, in this
-- copy (the parent made it); each result's line, then a mark that it's done
if opt.child then
  EXE = opt.exe
  for _, k in ipairs(opt.child) do
    local s = suites[k]
    local ok, r = pcall(s.run)
    r = ok and (r or "") or ("error: " .. tostring(r))
    local good = ok and passed(r)
    print(string.format("== %s: %s%s", s.name, good and "" or "FAILED  ", r:gsub("[\r\n]+", " ")))
    io.stdout:flush()
  end
  print("##done")
  return
end

if not EXE then
  for _, c in ipairs(WIN and { "replay.exe" } or { "replay", "replay.exe" }) do if exists(c) then EXE = abs(c) break end end
  if not EXE then io.stderr:write("run.lua: no replay here: build it, or --exe PATH\n"); os.exit(2) end
end
local function cores()
  local n = tonumber(os.getenv("NUMBER_OF_PROCESSORS") or "")
  if not n and not WIN then
    for _, c in ipairs({ "nproc 2>/dev/null", "sysctl -n hw.ncpu 2>/dev/null" }) do
      local p = io.popen(c); n = p and tonumber(p:read("*l") or ""); if p then p:close() end
      if n then break end
    end
  end
  return n or 2
end
local JOBS = math.max(1, math.min(8, opt.jobs or cores()))
local function copy_to(dir)
  if WIN then
    local t = dir:gsub("/", "\\")
    os.execute('if exist "' .. t .. '" rmdir /s /q "' .. t .. '"')
    os.execute('xcopy . "' .. t .. '\\" /e /i /q /y > nul')
    os.execute('mkdir "' .. (t .. "\\.test_out") .. '" 2> nul')
  else
    os.execute("rm -rf " .. q(dir) .. " && mkdir -p " .. q(dir) .. " && cp -r ./. " .. q(dir) .. "/ && mkdir -p " .. q(dir .. "/.test_out"))
  end
end
local function remove(dir)
  if WIN then os.execute('rmdir /s /q "' .. dir:gsub("/", "\\") .. '"') else os.execute("rm -rf " .. q(dir)) end
end
local bad, t0 = {}, os.time()

if JOBS == 1 then                                  -- one after another, in one copy (as it always was)
  print("copying the project to " .. TMP)
  copy_to(TMP)
  for _, s in ipairs(chosen) do
    local ok, r = pcall(s.run)
    r = ok and (r or "") or ("error: " .. tostring(r))
    local good = ok and passed(r)
    print(string.format("== %s: %s%s", s.name, good and "" or "FAILED  ", r))
    io.stdout:flush()
    if not good then bad[#bad + 1] = s.name end
  end
else
  -- the jobs: a suite each, but the ones that must not overlap chained
  local NET = { online = true, seats = true, routers = true, lobby = true, ["peer id"] = true, ["by name"] = true,
                ["power (play hosts)"] = true, portmap = true, net_udp = true, nat = true }
  local REVIEW = { review = true, ["review (editor)"] = true, ["review tab"] = true }   -- (the Lua ones first: the editor's leave proposals behind)
  local index, jobs, chain = {}, {}, {}
  for k, s in ipairs(suites) do index[s] = k end
  for _, s in ipairs(chosen) do
    local base = s.name:gsub(" %(lua[%w.]*%)$", ""):gsub(" %(luajit%)$", "")
    local key = NET[base] and "net" or (REVIEW[s.name] or REVIEW[base]) and "review" or nil
    if key then
      if not chain[key] then chain[key] = {}; jobs[#jobs + 1] = chain[key] end
      table.insert(chain[key], index[s])
    else jobs[#jobs + 1] = { index[s] } end
  end
  table.sort(jobs, function(a, b) return #a > #b end)   -- (the long chains first)
  local interp = (function() local i, x = -1, nil; while arg[i] do x = arg[i]; i = i - 1 end return x or "lua" end)()
  local ext = EXE:match("%.exe$") and ".exe" or ""
  print(string.format("copying the project to %s (%d copies: %d suites, %d at once)", TMP, math.min(JOBS, #jobs), #chosen, JOBS))
  local slots = {}
  remove(TMP)
  if WIN then os.execute('mkdir "' .. (OUT:gsub("/", "\\")) .. '" 2> nul') else os.execute("mkdir -p " .. q(OUT)) end   -- (the workers' logs; Windows: their batch files)
  for k = 1, math.min(JOBS, #jobs) do
    local dir = TMP .. "/s" .. k
    copy_to(dir)
    local exe = dir .. "/" .. (EXE:match("[^/\\]+$") or ("replay" .. ext))   -- (its own exe, in the copy's root as in the project's: its preferences beside it, apart)
    if not exists(exe) then
      if WIN then os.execute('copy /y "' .. EXE:gsub("/", "\\") .. '" "' .. exe:gsub("/", "\\") .. '" > nul')
      else os.execute("cp " .. q(EXE) .. " " .. q(exe)) end
    end
    slots[k] = { dir = dir, exe = exe }
  end
  local next_job, running, n = 1, 0, 0
  local function start(sl)
    local job = jobs[next_job]; next_job = next_job + 1
    n = n + 1
    sl.log, sl.job = TMP .. "/job" .. n .. ".log", job
    local ids = {}
    for _, k in ipairs(job) do ids[#ids + 1] = tostring(k) end
    local lua = {}
    for _, x in ipairs(opt.lua) do lua[#lua + 1] = x end
    local cmd = q(interp) .. " runtime/tests/run.lua --child " .. table.concat(ids, ",") .. " --tmp " .. q(sl.dir)
                .. " --exe " .. q(sl.exe) .. " --lua " .. table.concat(lua, ",")
    local was = TMP
    TMP = sl.dir                                   -- (shell: in that copy)
    shell(cmd, nil, true, sl.log)
    TMP = was
    running = running + 1
  end
  for _, sl in ipairs(slots) do if next_job <= #jobs then start(sl) end end
  while running > 0 do
    sleep(1)
    for _, sl in ipairs(slots) do
      if sl.job then
        local f = io.open(sl.log, "rb")
        local text = f and f:read("*a") or ""
        if f then f:close() end
        if text:find("##done", 1, true) then
          for line in text:gmatch("[^\r\n]+") do
            if line:sub(1, 3) == "== " then
              print(line)
              local name = line:match("^== (.-): FAILED")
              if name then bad[#bad + 1] = name end
            end
          end
          io.stdout:flush()
          sl.job = nil
          running = running - 1
          if next_job <= #jobs then start(sl) end
        end
      end
    end
  end
end
print(string.format("\n%d suites, %d failed%s (%d s)", #chosen, #bad, #bad > 0 and (": " .. table.concat(bad, ", ")) or "", os.time() - t0))
if not opt.keep then remove(TMP) else print("kept " .. TMP) end
os.exit(#bad > 0 and 1 or 0)
