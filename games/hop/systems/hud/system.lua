-- hud: the gems taken, and a word when the door's been reached
return function(w, dt)
  local st = w:node("/data/state")
  if not st then return end
  local s = st.c.round
  local score, banner = w:node("/objects/hud/score"), w:node("/objects/hud/banner")
  local pref = st.c.prefs or {}                    -- (the options menu's: systems/menu)
  if score then
    local t = w:tr("hud_gems", { name = pref.name or "Hopper", got = s.gems, total = s.total })   -- (assets/strings.loc)
    if pref.hud == false then t = "" end
    if s.total > 0 and s.gems >= s.total and not s.won then t = t .. w:tr("door_open") end
    score.c.text[1] = t
  end
  local rl = w:node("/data/rules")
  local again = rl and rl.c.level.restart_after or 5
  if banner then banner.c.text[1] = s.won and w:tr("won", math.max(1, math.ceil(again - s.time))) or "" end
  local hint = w:node("/objects/hud/hint")
  if hint then hint.c.text[1] = pref.paused and "" or w:tr("hint") end
end
