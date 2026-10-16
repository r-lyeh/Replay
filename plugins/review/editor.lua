-- editor.lua - the Review tab: a game's proposals, and an admin's reviews
-- (runtime/review.lua; docs/ROADMAP.md "Admin nodes"). The main menu's
-- Online > Review opens it, on the game being edited (a world folder).
--
-- Left: who you are (your key, an author of this game, an admin), Propose
-- (the world as saved, over the accepted version) and Update (to the
-- accepted version, if one is over yours), then the proposals. Right: the
-- one picked: its note, author, what it changes (the nodes), its reviews,
-- Run headless (the patched world ticked, no errors), Accept / Reject with
-- a note: signed with your key. Admins review others' games only.
--
-- Everything goes through the viewer: host_world("viewer_review", cmd, ...).
-- Proposals travel as files for now: <game>.review/ beside the game.
local P = ...
P.title = "Review"
P.category = "Online"                         -- (the main menu: Online >)
local core = require "core"
local style = require "core.style"
local View = require "core.view"
local canvas = require "plugins.canvas"

local function S(n) return math.floor(n * SCALE + 0.5) end
local function short(h) return tostring(h or "?"):sub(1, 8) end
local function call(...)
  if not host_world then return nil, "no viewer here" end
  return host_world("viewer_review", ...)
end

local ReviewView = View:extend()

function ReviewView:new()
  ReviewView.super.new(self)
  self.left, self.right = canvas.ui.new(), canvas.ui.new()
  self.note, self.rnote, self.ticks = "", "", 300
  self.sel = nil
  self.msg, self.msg_ok = nil, true
  self:refresh()
end
function ReviewView:get_name() return "Review" .. (self.info and self.info.game and (": " .. self.info.game) or "") end
function ReviewView:get_state() return {} end
function ReviewView:scroll_to_line() end
function ReviewView:draw_background_color() return style.background end

function ReviewView:refresh()
  self.info = call("info") or { rows = {}, err = "no game" }
  self.info.rows = self.info.rows or {}
  self.next_refresh = system.get_time() + 5
  if self.sel and not self.info.rows[self.sel] then self.sel = nil end
  if not self.sel and #self.info.rows > 0 then
    for i, r in ipairs(self.info.rows) do if r.current then self.sel = i end end
    self.sel = self.sel or #self.info.rows
  end
  self.diff = nil
  core.redraw = true
end
function ReviewView:say(ok, msg)
  self.msg, self.msg_ok = tostring(msg or (ok and "done" or "failed")), ok and true or false
  core.log("Review: %s", self.msg)
end
function ReviewView:act(...)
  local ok, msg = call(...)
  self:say(ok, msg)
  self:refresh()
  return ok
end

function ReviewView:update()
  ReviewView.super.update(self)
  if system.get_time() >= (self.next_refresh or 0) and not canvas.ui.editing then self:refresh() end
end

function ReviewView:draw_left(x, y, w, h)
  local ui, t = self.left, self.info
  ui:begin(x, y, w, h, { divider_right = true })
  ui:head("Review" .. (t.game and (": " .. t.game) or ""))
  if t.err then ui:text(t.err, style.error or style.text); ui:finish() return end
  ui:label("Accepted version", t.version and short(t.version) or "none yet")
  ui:label("Yours (on disk)", short(t.mine))
  ui:label("Your key", t.key and short(t.key) or "none")
  local roles = {}
  if t.author then roles[#roles + 1] = "author" end
  if t.admin then roles[#roles + 1] = "admin" end
  ui:label("You", #roles > 0 and table.concat(roles, ", ") or "a player")
  ui:space()
  ui:head("Propose")
  ui:field("Note", self.note, function(v) self.note = v end, { key = "note", tip = "what this change does (signed with it)" })
  ui:buttons({
    { t.version and "Propose" or "Author it", function() self:act("propose", self.note) end, accent = true,
      tip = t.version and "the world as saved, over the accepted version (authors only)" or "you author this game: its version now is the first one" },
    { "Update", function() self:act("update") end, tip = "to the accepted version over yours (onto the folder)" },
    { "Refresh", function() self:refresh() end },
  })
  if self.msg then ui:text(self.msg, self.msg_ok and style.dim or (style.error or style.text)) end
  ui:space()
  ui:head("Proposals")
  local rows = {}
  for i, r in ipairs(t.rows) do
    rows[#rows + 1] = {
      text = string.format("%s -> %s  %s", short(r.from), short(r.to), r.note ~= "" and r.note or "(no note)"),
      info = r.valid and r.state or "invalid",
      kind = r.current and "item" or "dim",
      selected = self.sel == i,
      tip = r.valid and nil or r.why,
      press = function() self.sel = i; self.diff = nil; core.redraw = true end,
    }
  end
  if #rows == 0 then ui:text("none yet") else ui:list(rows) end
  ui:finish()
end

function ReviewView:draw_right(x, y, w, h)
  local ui, t = self.right, self.info
  ui:begin(x, y, w, h)
  local r = self.sel and t.rows[self.sel]
  if not r then ui:text(t.err and "" or "Pick a proposal (left)."); ui:finish() return end
  ui:head(string.format("%s -> %s", short(r.from), short(r.to)))
  ui:label("Note", r.note ~= "" and r.note or "(none)")
  ui:label("By", short(r.author) .. (r.author == t.key and " (you)" or ""))
  if r.valid then ui:label("State", r.state) else ui:label("State", "invalid: " .. tostring(r.why), style.error or style.text) end
  ui:label("Over", r.current and "the accepted version" or "another version")
  ui:label("Patch", string.format("%d bytes", r.size or 0))
  ui:space()
  ui:head("Changes")
  if not self.diff then
    local ok, d = call("diff", self.sel)
    self.diff = ok and d or {}
  end
  local rows = {}
  for _, d in ipairs(self.diff) do rows[#rows + 1] = { text = d[1], info = d[2], kind = d[2] == "removed" and "dim" or "item" } end
  if #rows == 0 then ui:text("(none listed)") else ui:list(rows) end
  ui:space()
  ui:head("Reviews")
  local rv = {}
  for _, v in ipairs(r.reviews or {}) do
    rv[#rv + 1] = { text = short(v.by) .. (v.by == t.key and " (you)" or "") .. "  " .. (v.note ~= "" and v.note or ""), info = v.verdict }
  end
  if #rv == 0 then ui:text("none yet") else ui:list(rv) end
  ui:space()
  ui:head("Check")
  ui:slider("Ticks", self.ticks, 30, 3600, function(v) self.ticks = math.floor(v) end, { step = 30, fmt = "%.0f", def = 300 })
  ui:buttons({ { "Run headless", function() self:act("test", self.sel, self.ticks) end, tip = "the patched world, ticked: no errors" } })
  if t.admin and not t.author then
    ui:space()
    ui:head("Your review")
    ui:field("Note", self.rnote, function(v) self.rnote = v end, { key = "rnote" })
    ui:buttons({
      { "Accept", function() self:act("review", self.sel, "accept", self.rnote) end, accent = true },
      { "Reject", function() self:act("review", self.sel, "reject", self.rnote) end },
    })
  elseif t.author then
    ui:text("Your game: admins review it, not you.")
  else
    ui:text("Only admins review (runtime/admins.lua).")
  end
  ui:finish()
end

function ReviewView:draw()
  self:draw_background(style.background)
  local x, y, w, h = self.position.x, self.position.y, self.size.x, self.size.y
  local lw = math.floor(math.max(S(240), w * 0.42))
  self:draw_left(x, y, lw, h)
  self:draw_right(x + lw, y, w - lw, h)
end

function ReviewView:on_mouse_pressed(button, x, y, clicks)
  if self.left:pressed(button, x, y, clicks) or self.right:pressed(button, x, y, clicks) then return true end
  return ReviewView.super.on_mouse_pressed(self, button, x, y, clicks)
end
function ReviewView:on_mouse_moved(x, y, dx, dy)
  ReviewView.super.on_mouse_moved(self, x, y, dx, dy)
  self.left:moved(x, y); self.right:moved(x, y)
end
function ReviewView:on_mouse_released(button, x, y)
  ReviewView.super.on_mouse_released(self, button, x, y)
  self.left:released(button); self.right:released(button)
end
function ReviewView:on_mouse_wheel(dy) return self.left:wheel(dy) or self.right:wheel(dy) or true end

P.view(ReviewView)
P.tab = function() return ReviewView() end         -- (the main menu's Online > Review)
return ReviewView
