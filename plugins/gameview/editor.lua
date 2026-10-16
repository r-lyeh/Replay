-- editor.lua - the game view: the game in a Lite tab, docked like any other (split it beside the code,
-- drag it to another pane). The main menu's Game > Game view opens it (one at a time: again, it's
-- brought to the front).
--
-- The picture isn't Lite's: the tab leaves a hole in Lite's own (renderer.clear_rect) and tells the host
-- where it is each time Lite draws (host_call "gameview x y w h active"); the host draws the game there,
-- under Lite's picture, at that size (its layout, picking, the gizmo: all in that rect). While the tab
-- is open and shown, Lite stays opaque round it (no fade). The mouse over the tab is the game's; a click
-- there (or the tab made Lite's active view, or Play) gives the game the keys too; a click elsewhere in
-- Lite gives them back. Open, the editor is docked: Lite always shows (no fade over it), and the game
-- only in this tab (behind another tab: not at all, "gameview off"). Closed ("gameview closed"): the
-- game behind Lite again, the eye's fade. docs/HELP.md: The game view.
local P = ...
P.title = "Game view"                              -- (its name in menus)
P.category = "Game"                                -- (the main menu: Game >)
local core = require "core"
local View = require "core.view"
local style = require "core.style"

local function host(cmd) local h = rawget(_G, "host_call"); if h then return h(cmd) end end

-- was the tab drawn in a frame of Lite's? Not drawn (behind another tab, closed): the host is told
local state = package.loaded["gameview.state"]
if not state then
  state = { drawn = false, was = false, view = nil }
  package.loaded["gameview.state"] = state
  local begin_frame, end_frame = renderer.begin_frame, renderer.end_frame
  renderer.begin_frame = function(...) state.drawn = false; return begin_frame(...) end
  renderer.end_frame = function(...)
    if state.was and not state.drawn then host("gameview off") end
    state.was = state.drawn
    return end_frame(...)
  end
end

local GView = View:extend()

function GView:new()
  GView.super.new(self)
  state.view = self
  host("gameview open")                            -- (the editor docked: Lite always shown, opaque)
end
function GView:get_name() return "Game" end
function GView:try_close(do_close)
  if state.view == self then state.view = nil end
  host("gameview closed")
  state.was = false
  return GView.super.try_close(self, do_close)
end
function GView:update()
  GView.super.update(self)
  local active = core.active_view == self
  if active ~= self.was_active then self.was_active = active; core.redraw = true end   -- (Lite's focus moved: the host hears so)
end
function GView:draw()
  local x, y, w, h = self.position.x, self.position.y, self.size.x, self.size.y
  if w < 2 or h < 2 then return end
  renderer.clear_rect(x, y, w, h)                  -- (the hole: the game shows through)
  state.drawn = true
  host(string.format("gameview %d %d %d %d %d", math.floor(x), math.floor(y), math.floor(w), math.floor(h), core.active_view == self and 1 or 0))
end
-- the mouse over the tab is the host's (the game's), so Lite hears no click there: the host asks for the focus
rawset(_G, "lite_gameview_focus", function()      -- (also Play, Rewind, a step, the timeline, the tab behind another: to the front)
  local v = state.view
  if not v then return end
  local node = core.root_view.root_node:get_node_for_view(v)
  if node and node.active_view ~= v then node:set_active_view(v) end
  if core.active_view ~= v then core.set_active_view(v) end
  core.redraw = true
end)

P.view(GView)
P.tab = function()                                 -- (the main menu: one game view; again: to the front)
  local v = state.view
  if v then
    local node = core.root_view.root_node:get_node_for_view(v)
    if node then node:set_active_view(v); core.set_active_view(v); return nil end
    state.view = nil
  end
  return GView()
end
GView.state = state                                -- (tests)
return GView
