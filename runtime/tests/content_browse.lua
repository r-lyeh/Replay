-- content_browse.lua - the content browser (plugins/content): a folder as tiles, its
-- kinds, pictures (textures, models), going in and up, search tags (fuzzy, masks,
-- kinds, leaving out), rename, duplicate, the trash; `replay <folder>` opens it.
--   replay games/common --frames 100000 --shot x.bmp  (NG_EXIT=1, CONTENT_TEST=1)
local core = require "core"
core.add_thread(function()
  local ok_n, fail_n = 0, 0
  local function check(c, m) if c then ok_n = ok_n + 1 else fail_n = fail_n + 1; print("  FAIL: " .. m) end end
  local function wait(t) local e = system.get_time() + t; repeat core.redraw = true; coroutine.yield() until system.get_time() >= e end
  local root = (rawget(_G, "REPLAY_ROOT") or "."):gsub("\\", "/")
  wait(0.5)
  local v = core.active_view                       -- (`replay games/common`: the browser, in front)
  check(v and v.dir and v.items, "replay <folder>: the content browser (" .. tostring(v and v.get_name and v:get_name()) .. ")")
  if not (v and v.items) then print(string.format("content browse: %d checks ok, %d failed", ok_n, fail_n)); if os.getenv("NG_EXIT") then os.exit(0) end return end
  local names = {}
  for _, e in ipairs(v.items) do names[e.name] = e end
  check(names.kgirl and names.kgirl.dir and v.items[1].dir, "folders first: kgirl/")
  check(names["ship.glb"] and names["crate.png"] and names["house.vox"], "its files")
  wait(1.5)                                        -- (the pictures: a few a frame)
  local TH = v.THUMBS()
  check(TH[names["crate.png"].path] and TH[names["crate.png"].path].img, "a texture's picture")
  check(TH[names["arm.glb"].path] and TH[names["arm.glb"].path].img, "a model's picture (the host's; the ones on screen)")
  check(TH[names["arm.glb"].path] and TH[names["arm.glb"].path].skeletal, "arm.glb: a skeletal mesh (its kind once read)")
  v:open(names.kgirl)
  check(v.dir:match("kgirl$") and #v.items == 5, "in kgirl/: 5 files (" .. #v.items .. ")")
  v:go_back()
  check(v.dir:match("common$"), "back")
  v:add_tag("type:texture")
  local all_tex = #v.items > 0
  for _, e in ipairs(v.items) do if not (e.name:match("%.png$") or e.name:match("%.webp$")) then all_tex = false end end
  check(all_tex and v.searching, "type:texture: pictures only, the folders below too (" .. #v.items .. ")")
  local deep = false
  for _, e in ipairs(v.items) do if e.rel == "kgirl/g01_texture.png" then deep = true end end
  check(deep, "kgirl/g01_texture.png found below")
  v:add_tag("type:mesh")
  local kinds = {}
  for _, e in ipairs(v.items) do kinds[(e.name:match("%.(%w+)$") or "")] = true end
  check(kinds.png and kinds.glb and kinds.fbx, "kinds add up: texture and mesh")
  v:remove_tag(1); v:remove_tag(1)
  v:add_tag("**.glb")
  check(#v.items >= 4 and v.items[1].name:match("%.glb$"), "a mask: **.glb (" .. #v.items .. ")")
  v:add_tag("-ship*")
  local ship = false
  for _, e in ipairs(v.items) do if e.name == "ship.glb" then ship = true end end
  check(not ship, "-ship*: left out")
  v.tags = {}
  v:add_tag("kgrl")
  local fz = false
  for _, e in ipairs(v.items) do if e.name == "kgirls01.fbx" then fz = true end end
  check(fz, "fuzzy: kgrl finds kgirls01.fbx")
  v.tags = {}; v:refresh()
  check(not v.searching and #v.items > 10, "no tags: the folder again")
  -- a scratch folder: rename, duplicate, trash, a new folder
  local tmp = root .. "/content_test_tmp"
  system.mkdir(tmp)
  local f = io.open(tmp .. "/a.txt", "wb"); f:write("hello"); f:close()
  v:go(tmp)
  v.root = tmp
  check(#v.items == 1 and v.items[1].name == "a.txt", "a scratch folder")
  v:duplicate(v.items[1])
  check(#v.items == 2, "duplicate: a copy")
  v:trash(v:entry_at(tmp .. "/a.txt"))
  check(system.get_file_info(tmp .. "/.trash/a.txt") ~= nil and #v.items == 1, "trash: into .trash/, not gone")
  local mi = v:menu_items()
  check(#mi > 5, "its menu")
  wait(0.2)
  check(type(v.hits) == "table" and #v.hits > 3, "drawn (" .. #v.hits .. " hit areas)")
  for _, n in ipairs(system.list_dir(tmp .. "/.trash") or {}) do os.remove(tmp .. "/.trash/" .. n) end
  for _, n in ipairs(system.list_dir(tmp) or {}) do os.remove(tmp .. "/" .. n) end
  os.remove(tmp .. "/.trash"); os.remove(tmp)
  print(string.format("content browse: %d checks ok, %d failed", ok_n, fail_n))
  if os.getenv("NG_EXIT") then os.exit(0) end
end)
