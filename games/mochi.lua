-- Mochi <3 a cozy little red-panda companion for Replay
-- about: Virtual pet demo: WebP pictures, draw layers, drag and drop, savegames
--
-- Assets (shared script-game assets):
--   games/common/mochi_room.webp
--   games/common/mochi_red_panda.webp
--
-- Save data: w:savegame("mochi", ...) writes games/.saves/mochi/mochi.sav
-- (Replay keeps a script game's savegames there); loaded as the world is
-- built, so Mochi is as you left her. Saved with the computer's clock
-- (w:wall_time): the time you were away counts, and the header shows when
-- it was last saved.
--
-- Controls: 1 Feed | 2 Play | 3 Clean | 4 Sleep | 5 Cuddle | 6 Treat
-- Mouse: click one of the six buttons along the bottom.
--
-- Replay docs: https://github.com/r-lyeh/Replay/blob/main/docs/HELP.md

local ecs = require("ecs")
local w = ecs.world()

-- ------------------------------------------------------------
-- Window and explicit draw order
-- ------------------------------------------------------------

w:spawn("/config", {
    window = {
        w = 800,
        h = 560,
        title = "Mochi",
        mouse = true
    }
})

-- Layers are drawn bottom-to-top.
w:spawn("/data/layers", {
    order = { "background", "pet", "hud" }
})

-- ------------------------------------------------------------
-- Persistent state
-- ------------------------------------------------------------

local defaults = {
    hunger = 78,
    happiness = 88,
    energy = 82,
    cleanliness = 96,
    affection = 12,

    age_days = 1,
    care_count = 0,
    play_seconds = 0,

    mood = "idle",
    mood_time = 0,
    clock = 0,
    save_clock = 0,

    -- The computer's clock (seconds since 1970): when Mochi first came
    -- home and when this was last saved (0: never).
    born_at = 0,
    saved_at = 0,

    display_frame = -1,
    message = "A little red panda is happy you're here. <3",

    -- Saved location; default is the carpet.
    anchor = "carpet",

    -- Drag state is transient (not meaningful after loading).
    dragging = false,
    drag_offset_x = 0,
    drag_offset_y = 0,
    mouse_was_down = false
}

local saved = w:loadgame("mochi")
local pet = {}

for k, v in pairs(defaults) do
    pet[k] = v
end

if type(saved) == "table" and type(saved.pet) == "table" then
    for k, v in pairs(saved.pet) do
        if defaults[k] ~= nil and type(v) == type(defaults[k]) then
            pet[k] = v
        end
    end
end

if type(pet.anchor) ~= "string" then
    pet.anchor = "carpet"
end
pet.dragging = false
pet.drag_offset_x = 0
pet.drag_offset_y = 0
pet.mouse_was_down = false

-- Wall time: the hours away count (needs drain, capped at 12 h so a
-- long holiday doesn't leave her starving), and her age is in real days.
local now = w:wall_time()
if pet.born_at == 0 then pet.born_at = now end
if pet.saved_at > 0 and now > pet.saved_at then
    local away = math.min(now - pet.saved_at, 12 * 3600)
    local function drop(v, rate) return math.max(0, math.min(100, v - away * rate)) end
    pet.hunger = drop(pet.hunger, 0.12 / 60)          -- (a sixtieth of the awake rates: she naps)
    pet.happiness = drop(pet.happiness, 0.045 / 60)
    pet.cleanliness = drop(pet.cleanliness, 0.035 / 60)
    local mins = math.floor((now - pet.saved_at) / 60)
    if mins >= 1 then
        pet.message = mins < 60 and ("Mochi missed you for " .. mins .. (mins == 1 and " minute! <3" or " minutes! <3"))
            or ("Welcome back! " .. math.floor(mins / 60) .. " h away, Mochi waited. <3")
    end
end
pet.age_days = 1 + math.floor((now - pet.born_at) / 86400)
pet.mood, pet.mood_time, pet.display_frame = "idle", 0, -1

-- Where Mochi can sit (the centre of her sprite), shared by her start and
-- by the care system's snap (one table: they used to disagree, so she
-- started a bit off and jumped on the first drop).
w:spawn("/data/rules", {
    anchors = {
        carpet = { x = 0, y = 100, label = "the carpet" },
        bed = { x = -342, y = 10, label = "the bed" },
        table = { x = 0, y = -40, label = "the table" },
        cushion = { x = 242, y = 65, label = "the panda cushion" },
        left_edge = { x = -282, y = 125, label = "the left edge" },
        right_edge = { x = 282, y = 125, label = "the right edge" },
        plant = { x = -70, y = 60, label = "the plant" },
    }
})

-- IMPORTANT: create the data node before any system tries to read it.
-- /data nodes are state/configuration nodes, not live drawable objects.
w:spawn("/data/state", {
    pet = pet
})

-- A dedicated marker means the system runs exactly once per tick.
-- Without a requires filter, a table-form system can run once for
-- every matching live node, which was multiplying Mochi's clock.
w:spawn("/objects/tick", { mochi_tick = true })

-- ------------------------------------------------------------
-- Background
-- Replay's world origin is the centre; positive Y points down.
-- ------------------------------------------------------------

w:spawn("/objects/room", {
    layer = "background",
    transform = { x = 0, y = 0 },
    image = {
        "/assets/mochi_room.webp",
        w = 800,
        h = 450,
        smooth = false
    }
})

-- ------------------------------------------------------------
-- Pet
-- Sprite sheet: 4 columns × 4 rows, each frame 384 × 256.
-- ------------------------------------------------------------

local anchors = w:node("/data/rules").c.anchors

local start_anchor = anchors[pet.anchor] and pet.anchor or "carpet"
pet.anchor = start_anchor
local start_pos = anchors[start_anchor]

w:spawn("/objects/mochi", {
    layer = "pet",
    transform = { x = start_pos.x, y = start_pos.y, s = 1 },
    image = {
        "/assets/mochi_red_panda.webp",
        w = 230,
        h = 154,
        src = { x = 0, y = 0, w = 384, h = 256 },
        smooth = false
    }
})

-- ------------------------------------------------------------
-- HUD header (top edge)
-- ------------------------------------------------------------

w:spawn("/objects/hud/header", {
    layer = "hud",
    transform = { x = 0, y = -246 },
    color = { 255, 244, 239 },
    rect = { w = 760, h = 58, fill = true }
})

w:spawn("/objects/hud/title", {
    layer = "hud",
    transform = { x = -350, y = -246 },
    color = { 133, 76, 76 },
    text = { "MOCHI", font = "sans-bold", size = 24 }
})

w:spawn("/objects/hud/tagline", {
    layer = "hud",
    transform = { x = -265, y = -246 },
    color = { 154, 105, 105 },
    text = { "your tiny red-panda friend", font = "sans", size = 13 }
})

w:spawn("/objects/hud/saved", {
    layer = "hud",
    transform = { x = -265, y = -232 },
    color = { 190, 150, 150 },
    text = {
        pet.saved_at > 0 and ("saved " .. w:wall_date("%H:%M:%S", pet.saved_at)) or "not saved yet",
        font = "sans",
        size = 11
    }
})

w:spawn("/objects/hud/stats", {
    layer = "hud",
    transform = { x = 105, y = -246 },
    color = { 133, 76, 76 },
    text = {
        "HUNGER 78  <3  HAPPY 88\nENERGY 82  *  CLEAN 96",
        font = "sans-bold",
        size = 12
    }
})

-- ------------------------------------------------------------
-- Speech line, placed over the lower part of the room
-- ------------------------------------------------------------

w:spawn("/objects/hud/speech", {
    layer = "hud",
    transform = { x = 0, y = 166 },
    color = { 133, 76, 76 },
    text = {
        "A little red panda is happy you're here. <3",
        font = "sans-bold",
        size = 13,
        align = "center"
    }
})

-- ------------------------------------------------------------
-- Six bottom buttons
-- Child labels use LOCAL x=0,y=0. Do not repeat the parent's
-- coordinates here: child transforms are relative to the parent.
-- ------------------------------------------------------------

local buttons = {
    { "FEED",   "1", -300 },
    { "PLAY",   "2", -180 },
    { "CLEAN",  "3",  -60 },
    { "SLEEP",  "4",   60 },
    { "CUDDLE", "5",  180 },
    { "TREAT",  "6",  300 }
}

for i, b in ipairs(buttons) do
    local path = "/objects/hud/buttons/" .. i

    w:spawn(path, {
        layer = "hud",
        transform = { x = b[3], y = 240 },
        color = { 255, 229, 226 },
        rect = { w = 104, h = 46, fill = true }
    })

    w:spawn(path .. "/label", {
        transform = { x = 0, y = 0 },
        color = { 133, 76, 76 },
        text = {
            b[1] .. "  [" .. b[2] .. "]",
            font = "sans-bold",
            size = 12,
            align = "center"
        }
    })
end

-- ------------------------------------------------------------
-- Care and simulation system
-- ------------------------------------------------------------

local care = ecs.system(function()
    -- This system is deliberately self-contained. Replay compiles
    -- system bodies separately from the outer game script.
    local button_x = { -300, -180, -60, 60, 180, 300 }

    -- Where she can sit: /data/rules' anchors (the same table her start uses).
    local function anchors(w) return w:node("/data/rules").c.anchors end

    local function clamp(v)
        return math.max(0, math.min(100, v))
    end

    local function save(w)
        local p = w:node("/data/state").c.pet
        p.saved_at = w:wall_time()                  -- (the computer's clock: when, for real)
        w:savegame("mochi", { pet = p })
        w:node("/objects/hud/saved").c.text[1] = "saved " .. w:wall_date("%H:%M:%S", p.saved_at)
    end

    local function say(w, message)
        local p = w:node("/data/state").c.pet
        p.message = message
        w:node("/objects/hud/speech").c.text[1] = message
    end

    local function act(w, action)
        local p = w:node("/data/state").c.pet

        p.mood_time = 0
        p.care_count = p.care_count + 1

        if action == 1 then
            p.hunger = clamp(p.hunger + 24)
            p.happiness = clamp(p.happiness + 3)
            p.mood = "eat"
            say(w, "Crunch crunch! A very tasty snack! <3")

        elseif action == 2 then
            p.happiness = clamp(p.happiness + 20)
            p.energy = clamp(p.energy - 13)
            p.mood = "play"
            say(w, "Wheee! Mochi is having the best time!")

        elseif action == 3 then
            p.cleanliness = clamp(p.cleanliness + 35)
            p.happiness = clamp(p.happiness + 4)
            p.mood = "groom"
            say(w, "Squeaky clean and extra fluffy. *")

        elseif action == 4 then
            p.mood = "sleep"
            say(w, "Tucking in... sweet dreams, Mochi. zZ")

        elseif action == 5 then
            p.affection = p.affection + 1
            p.happiness = clamp(p.happiness + 12)
            p.mood = "love"
            say(w, "Mochi nuzzles your hand. So much love! <3")

        elseif action == 6 then
            p.hunger = clamp(p.hunger + 12)
            p.affection = p.affection + 2
            p.happiness = clamp(p.happiness + 10)
            p.mood = "treat"
            say(w, "A special berry treat! You're Mochi's favourite.")
        end

        save(w)
    end

    return {
        requires = { "mochi_tick" },

        on_key = function(w, key, down, player)
            if not down then return end

            local keys = {
                ["1"] = 1, ["2"] = 2, ["3"] = 3,
                ["4"] = 4, ["5"] = 5, ["6"] = 6
            }

            if keys[key] then
                act(w, keys[key])
            end
        end,

        -- Runs once per tick because requires matches the single /objects/tick node.
        run = function(w, n, dt)
            local p = w:node("/data/state").c.pet

            -- Clamp long pauses/stalls so one delayed frame cannot
            -- drain needs or jump the animation forward dramatically.
            dt = math.min(dt, 0.05)

            p.clock = p.clock + dt
            p.save_clock = p.save_clock + dt
            p.play_seconds = p.play_seconds + dt

            -- At these rates hunger takes about 14 minutes to drain
            -- from full; happiness and cleanliness decay more slowly.
            p.hunger = clamp(p.hunger - dt * 0.12)
            p.happiness = clamp(p.happiness - dt * 0.045)
            p.cleanliness = clamp(p.cleanliness - dt * 0.035)

            if p.mood == "sleep" then
                p.energy = clamp(p.energy + dt * 4.0)

                if p.energy >= 99 then
                    p.mood = "idle"
                    p.mood_time = 0
                    say(w, "Good morning, sleepy paws! ^_^")
                end
            else
                p.energy = clamp(p.energy - dt * 0.055)
            end

            p.mood_time = p.mood_time + dt

            -- Frame animation is intentionally slow and frame-based.
            -- The source rectangle is changed only when the frame
            -- changes, not on every 60 Hz update.
            local frame
            local animation_fps = 7

            if p.mood == "sleep" then
                frame = 15

            elseif p.mood == "eat" then
                local sequence = { 8, 9, 8, 10 }
                frame = sequence[math.floor(p.mood_time * animation_fps) % #sequence + 1]

            elseif p.mood == "groom" then
                frame = 12

            elseif p.mood == "play" then
                local sequence = { 4, 5, 6, 7 }
                frame = sequence[math.floor(p.mood_time * animation_fps) % #sequence + 1]

            elseif p.mood == "love" then
                frame = 11

            elseif p.mood == "treat" then
                frame = 10

            else
                -- Four-frame idle loop at 3 frames per second.
                frame = math.floor(p.clock * 3) % 4
            end

            if p.mood ~= "idle"
                and p.mood ~= "sleep"
                and p.mood_time >= 1.8 then
                p.mood = "idle"
                p.mood_time = 0
            end

            if frame ~= p.display_frame then
                p.display_frame = frame

                local col = frame % 4
                local row = math.floor(frame / 4)

                w:node("/objects/mochi").c.image.src = {
                    x = col * 384,
                    y = row * 256,
                    w = 384,
                    h = 256
                }
            end

            -- Refresh the stat display.
            w:node("/objects/hud/stats").c.text[1] =
                string.format(
                    "HUNGER %.0f  <3  HAPPY %.0f\nENERGY %.0f  *  CLEAN %.0f",
                    p.hunger, p.happiness, p.energy, p.cleanliness
                )

            -- Drag Mochi. While held, she follows the pointer with the
            -- original grab offset. On release she snaps to the nearest
            -- predefined spot and that spot is saved.
            local m = w.mouse or {}
            local mx, my = m.x or 9999, m.y or 9999
            local mochi_node = w:node("/objects/mochi")
            local transform = mochi_node.c.transform

            if m.left and not p.mouse_was_down and m.inside then
                -- Don't start a drag if the pointer is on a care button.
                local on_button = false
                for i = 1, 6 do
                    if math.abs(mx - button_x[i]) <= 52
                        and math.abs(my - 240) <= 23 then
                        on_button = true
                        act(w, i)
                        break
                    end
                end

                if not on_button
                    and math.abs(mx - transform.x) <= 115
                    and math.abs(my - transform.y) <= 77 then
                    p.dragging = true
                    p.drag_offset_x = transform.x - mx
                    p.drag_offset_y = transform.y - my
                    p.anchor = "custom"
                    say(w, "You can move Mochi anywhere, then let go! <3")
                end
            end

            if m.left and p.dragging then
                transform.x = math.max(-285, math.min(285, mx + p.drag_offset_x))
                transform.y = math.max(-175, math.min(175, my + p.drag_offset_y))
            end

            if not m.left and p.mouse_was_down and p.dragging then
                local nearest_name = "carpet"
                local nearest_distance = math.huge

                for name, a in pairs(anchors(w)) do
                    local dx = transform.x - a.x
                    local dy = transform.y - a.y
                    local distance = dx * dx + dy * dy

                    if distance < nearest_distance then
                        nearest_distance = distance
                        nearest_name = name
                    end
                end

                p.anchor = nearest_name
                transform.x = anchors(w)[nearest_name].x
                transform.y = anchors(w)[nearest_name].y
                p.dragging = false

                say(w, "Mochi is comfy on " .. anchors(w)[nearest_name].label .. ". <3")
                save(w)
            end

            p.mouse_was_down = m.left and true or false

            -- Autosave every 15 seconds of actual game time.
            if p.save_clock >= 15 then
                p.save_clock = 0
                p.age_days = 1 + math.floor((w:wall_time() - p.born_at) / 86400)   -- (real days since she came home)
                save(w)
            end
        end,

        on_editor = function(w, what, data)
            if what == "save" or what == "stopping" then   -- (stopping: the world as played, before Stop puts it back; "stopped" would save the authored one, and mark it changed)
                save(w)
            end
        end
    }
end)

w:spawn("/systems", { order = { "care" } })
w:spawn("/systems/care", { system = care })

return w
