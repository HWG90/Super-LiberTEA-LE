-- Actual pure Policy and retained screen Renderer; no game/native input/data access.
local Support = assert(loadfile("tests/support.lua"))()
local project = Support.project()
local Policy, Renderer, Style =
    project.require("hud/policy.lua"), project.require("render/screen_gui.lua"), project.require("ui/style.lua")
local checks = 0
local function eq(actual, expected, why)
    checks = checks + 1
    assert(actual == expected, (why or "different") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, why)
    checks = checks + 1
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-9, why or "different warning scalar")
end
local function model(heat)
    return {
        known = true,
        in_mission = true,
        alive = true,
        hud_visible = true,
        menu_open = false,
        blocked = false,
        identity = 100000,
        generation = 1,
        follow_token = "player/weapon-A",
        world = "world",
        font = { font = "0123456789abcdef", atlas = "1111111111111111", material = "2222222222222222" },
        aim = { known = true, first_person = false, aiming = false },
        weapon = {
            known = true,
            ammo_kind = "heat",
            heat_weapon = true,
            heat = heat,
            identity = "heat-resource-A",
            entity = 42,
        },
    }
end
local settings = {
    get = function(_, key)
        if key == "hud.heat_display" then
            return 2
        end
    end,
}
do
    local p, m = Policy.new(), model(0.59)
    local v = p:update(m, settings, 0.1)
    eq(v.weapon.heat_warning_mix, 0)
    eq(v.weapon.heat_pulse, 1)
    m.weapon.heat = 0.6
    v = p:update(m, settings, 0)
    near(v.weapon.heat_warning_mix, 0.15)
    near(v.weapon.heat_pulse, 1)
    v = p:update(m, settings, 1 / 6)
    near(v.weapon.heat_pulse, 0.625, "60% warning runs at1.5Hz quarter cycle")
    v = p:update(m, settings, 1 / 6)
    near(v.weapon.heat_pulse, 0.25)
    m.weapon.heat = 0.8
    v = p:update(m, settings, 0)
    near(v.weapon.heat_warning_mix, 0.575, "red shift increases continuously with accumulated heat")
    m.weapon.heat = 1
    v = p:update(m, settings, 0)
    near(v.weapon.heat_warning_mix, 1)
    m.weapon.heat, m.weapon.heat_locked = 0.5, true
    v = p:update(m, settings, 1)
    eq(v.weapon.heat_warning_mix, 0, "locked cooling under60% does not bypass threshold")
    eq(v.weapon.heat_pulse, 1)
    m.weapon.heat = 1
    v = p:update(m, settings, 0)
    near(v.weapon.heat_pulse, 1, "cooling reset starts the next warning from a fresh phase")
    v = p:update(m, settings, 1 / 12)
    near(v.weapon.heat_pulse, 0.25, "maximum heat runs at6Hz half cycle")
end
do
    local function pulse(heat, frames, dt)
        local p, m = Policy.new(), model(heat)
        local value
        for _ = 1, frames do
            value = p:update(m, settings, dt).weapon.heat_pulse
        end
        return value
    end
    near(pulse(0.73, 100, 0.01), pulse(0.73, 10, 0.1), "phase integrates dt independently of frame subdivision")
    local function dips(heat)
        local p, m, previous, total = Policy.new(), model(heat), false, 0
        for _ = 1, 480 do
            local low = p:update(m, settings, 1 / 240).weapon.heat_pulse < 0.26
            if low and not previous then
                total = total + 1
            end
            previous = low
        end
        return total
    end
    eq(dips(0.6), 3)
    eq(dips(1), 12, "overheat flashes four times as fast as initial threshold")
    for _, dt in ipairs({ -1, 0 / 0, math.huge, 1e30 }) do
        local v = Policy.new():update(model(0.95), settings, dt)
        eq(v.weapon.heat_warning_mix >= 0 and v.weapon.heat_warning_mix <= 1, true)
        eq(v.weapon.heat_pulse >= 0.25 and v.weapon.heat_pulse <= 1, true, "invalid/large dt stays finite and bounded")
    end
end
do
    for _, change in ipairs({ "entity", "resource", "follow", "generation", "identity" }) do
        local p, m = Policy.new(), model(0.9)
        p:update(m, settings, 0.1)
        if change == "entity" then
            m.weapon.entity = 43
        elseif change == "resource" then
            m.weapon.identity = "heat-resource-B"
        elseif change == "follow" then
            m.follow_token = "player/weapon-B"
        elseif change == "generation" then
            m.generation = 2
        else
            m.identity = 100001
        end
        near(p:update(m, settings, 0).weapon.heat_pulse, 1, change .. " replaces warning owner/phase")
    end
    for _, bad in ipairs({ "unknown", "negative", "overrange", "nan", "nonheat", "throwable", "notknown", "hidden" }) do
        local p, m = Policy.new(), model(0.9)
        p:update(m, settings, 0.1)
        if bad == "unknown" then
            m.weapon.heat = nil
        elseif bad == "negative" then
            m.weapon.heat = -1
        elseif bad == "overrange" then
            m.weapon.heat = 2
        elseif bad == "nan" then
            m.weapon.heat = 0 / 0
        elseif bad == "nonheat" then
            m.weapon.ammo_kind = nil
            m.weapon.heat_weapon = false
            m.weapon.remaining = 0.9
        elseif bad == "throwable" then
            m.weapon.throwing = true
            m.weapon.count = 0
        elseif bad == "notknown" then
            m.weapon.known = false
        else
            m.hud_visible = false
        end
        local v = p:update(m, settings, 0.1)
        eq(v.weapon.heat_warning_mix, 0, bad .. " has no red shift")
        eq(v.weapon.heat_pulse, 1, bad .. " has no pulse")
    end
end
local function renderer()
    local state = { creates = 0, updates = 0, destroys = 0, colours = {} }
    local sr = {
        Application = {
            worlds = function()
                return { "world" }
            end,
        },
        World = {},
        Gui = {},
        Material = {},
    }
    sr.World.create_screen_gui = function()
        return "gui"
    end
    sr.Gui.set_visible = function()
        return true
    end
    sr.Gui.material = function()
        return "material"
    end
    sr.Gui.create_material = function()
        return "material"
    end
    sr.Material.set_texture = function()
        return true
    end
    sr.IdString64 = {
        from_hex = function(v)
            return v
        end,
    }
    sr.Vector2 = function(x, y)
        return { x, y }
    end
    sr.Vector3 = function(x, y, z)
        return { x, y, z }
    end
    sr.Color = function(a, r, g, b)
        return { a, r, g, b }
    end
    sr.Gui.rect = function(_, position, size, colour)
        state.creates = state.creates + 1
        local id = state.creates
        state.colours[id] = colour
        return id
    end
    sr.Gui.update_rect = function(_, id, position, size, colour)
        state.updates = state.updates + 1
        state.colours[id] = colour
    end
    sr.Gui.destroy_rect = function()
        state.destroys = state.destroys + 1
    end
    sr.Gui.reset = function()
        return true
    end
    local r = Renderer.new({ globals = { stingray = sr } })
    local m = model(0.7)
    local p = {
        key = "heat_fill",
        kind = "rect",
        x = 20,
        y = 30,
        z = 950,
        width = 80,
        height = 8,
        tone = "text",
        alpha = 0.8,
    }
    local geometry = { valid = true, visible = true, primitives = { p } }
    local function draw()
        return r:render(m, { visible = true }, geometry)
    end
    return state, r, p, draw
end
local function expected_colour(base, mix, alpha)
    local danger = Style.tokens.colors.danger
    local out = { math.floor((base[4] + (danger[4] - base[4]) * mix) * alpha + 0.5) }
    for i = 1, 3 do
        out[i + 1] = math.floor(base[i] + (danger[i] - base[i]) * mix + 0.5)
    end
    return table.concat(out, ",")
end
do
    local s, r, p, draw = renderer()
    eq(draw(), true)
    local entry = r.entries.heat_fill
    eq(s.creates, 1)
    eq(table.concat(s.colours[1], ","), expected_colour(Style.tokens.colors.text, 0, 0.8))
    for _, mix in ipairs({ 0.15, 0.575, 1 }) do
        local before = s.updates
        p.danger_mix = mix
        eq(draw(), true)
        eq(r.entries.heat_fill, entry, "warning changes retain the same primitive")
        eq(s.updates, before + 1, "mix-only change updates retained colour")
        eq(s.creates, 1)
        eq(table.concat(s.colours[1], ","), expected_colour(Style.tokens.colors.text, mix, 0.8))
        eq(draw(), true)
        eq(s.updates, before + 1, "unchanged warning issues no redundant setter")
    end
    p.tone, p.alpha = "yellow", 0.25
    eq(draw(), true)
    eq(
        table.concat(s.colours[1], ","),
        expected_colour(Style.tokens.colors.yellow, 1, 0.25),
        "full warning derives danger token including alpha"
    )
    p.danger_mix = nil
    eq(draw(), true)
    eq(entry.danger_mix, nil, "removing optional mix clears the retained field")
    eq(table.concat(s.colours[1], ","), expected_colour(Style.tokens.colors.yellow, 0, 0.25))
    local updates = s.updates
    eq(draw(), true)
    eq(s.updates, updates, "cleared mix does not cause perpetual updates")
    p.width, p.height = 8, 0
    eq(draw(), true)
    eq(entry.height, 0, "vertical cold fill keeps exact zero height")
    eq(s.creates, 1)
    updates = s.updates
    eq(draw(), true)
    eq(s.updates, updates)
    p.height = 40
    eq(draw(), true)
    eq(s.creates, 1, "vertical heat growth reuses zero-height primitive")
    eq(s.destroys, 0)
    eq(r:close(), true)
end
for _, mix in ipairs({ -0.1, 1.1, 0 / 0, math.huge, false, "0.5" }) do
    local s, r, p, draw = renderer()
    p.danger_mix = mix
    local okay, why = draw()
    eq(okay, false, "invalid danger mix is refused")
    eq(tostring(why):find("danger mix", 1, true) ~= nil, true)
    eq(s.creates, 0, "invalid mix never constructs a native primitive")
    eq(r:close(), true)
end
print("heat warning: " .. checks .. " checks passed")
