-- menu: the options menu (assets/settings.options: open it in the options
-- editor, change it, save: the menu changes at once; runtime/options.lua
-- runs it). ESC, O or the pad's Start opens it (a long ESC: back to the
-- editor); the mouse and pad 1 work it; the game waits while it's open.
-- What's applied goes to /data/state's prefs, which the player and the HUD read.
local OPEN = { o = true, escape = true, ["pad start"] = true, ["pad guide"] = true }
local function menu(w)
  local n = w:node("/objects/hud/menu")
  local o = n and n.c.options and w:options(n.c.options.file)
  if not o then return end
  return o, o:state(w, n)
end
return {
  requires = { "options" },
  on_key = function(w, key, down)
    local o, st = menu(w)
    if not o then return end
    if o:key(w, st, key, down) then return end
    if down and OPEN[key] then o:open(w, st) end
  end,
  run = function(w, n, dt)
    local o = w:options(n.c.options.file)
    if not o then return end
    local st = o:state(w, n)
    o:update(w, st, dt, n)                         -- (n: the mouse too, in its place)
    for _, e in ipairs(o:events(st)) do
      if e[1] == "button" and e[2] == "restart" then
        local s = w:node("/data/state").c.round
        s.started = false                          -- (the level system starts it again)
        o:close(w, st)
      end
    end
    local state = w:node("/data/state")
    if state then
      local p = state.c.prefs or {}
      for k, v in pairs(st.values) do p[k] = v end
      p.paused = (st.open or p.was_open) or nil         -- (and the tick after it closes: its last key isn't a jump)
      p.was_open = st.open or nil
      state.c.prefs = p
    end
    o:draw(w, st, n)
  end,
}
