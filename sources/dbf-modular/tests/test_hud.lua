-- Run from repository root: luajit tests/test_hud.lua
local checks = 0
local function check(value, why)
    checks = checks + 1
    assert(value, why or ("check " .. checks))
end
local function eq(actual, expected, why)
    check(actual == expected, (why or "mismatch") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local cache = {}
mod = {
    require = function(name)
        if cache[name] == nil then
            cache[name] = assert(loadfile("dbf_modular/" .. name))()
        end
        return cache[name]
    end,
}
local Policy, Anchor, Layout =
    mod.require("hud/policy.lua"), mod.require("hud/anchor.lua"), mod.require("hud/bracket_layout.lua")
local Renderer, Pool = mod.require("render/screen_gui.lua"), mod.require("render/pool.lua")
local Composition, Style = mod.require("hud/composition.lua"), mod.require("ui/style.lua")
local function settings()
    return {
        values = {},
        get = function(self, id)
            return self.values[id]
        end,
    }
end
local function model()
    return {
        known = true,
        identity = 1,
        generation = 1,
        in_mission = true,
        alive = true,
        hud_visible = true,
        menu_open = false,
        blocked = false,
        aim = { known = true, first_person = false, aiming = false, switching = false },
        viewport = { width = 1920, height = 1080 },
        reticle = { known = true, x = 960, y = 540 },
        anchors = { body = { known = true, x = 800, y = 500 }, weapon = { known = true, x = 1100, y = 700 } },
        weapon = {
            known = true,
            count = 32,
            remaining = 0.7,
            capacity = 45,
            reserve = 3,
            reloading = false,
            fire_mode = "AUTO",
            rpm = 900,
            rpm_index = 2,
            zoom = 100,
            zoom_index = 1,
            ammo_mode = "FLAK",
            changeable = { fire_mode = true, rpm = true, zoom = true, ammo_mode = true },
        },
        health = 1,
        stamina = 1,
        stims = 2,
        throwables = 3,
        cooldowns = {},
        world = "world",
        font = { font = "0123456789abcdef", atlas = "123456789abcdef0", material = "23456789abcdef01" },
    }
end
do
    local p, s, m = Policy.new(), settings(), model()
    local v = p:update(m, s, 0.016)
    eq(v.profile, "hip")
    eq(v.details, false)
    eq(v.weapon.text, "32")
    eq(v.health.visible, false)
    eq(v.weapon.options, nil)
    eq(v.weapon.options_complete, false, "Original DBF retains sole option-strip ownership")
    m.aim.aiming = true
    eq(p:update(m, s, 0.016), v, "view reused")
    eq(v.profile, "aim")
    eq(v.details, false)
    eq(v.quiet_aim, true)
    eq(v.native_options, false)
    eq(v.native_cooldowns, false)
    eq(v.weapon.capacity, nil)
    eq(v.weapon.reserve, nil)
    eq(v.weapon.options, nil, "ADS does not copy original weapon-option information")
    eq(v.weapon_options, false)
    eq(v.cooldowns, false, "Bracket never proposes a replacement cooldown view")
    m.aim.viewmodel_active = true
    p:update(m, s, 0.016)
    eq(v.profile, "first_person", "proven custom FPS camera while aiming uses FP presentation")
    m.aim.aiming = false
    p:update(m, s, 0.016)
    eq(v.profile, "hip", "FPS camera alone does not turn hipfire into ADS")
    m.aim.aiming, m.aim.viewmodel_active = true, false
    m.aim.first_person = true
    p:update(m, s, 0.016)
    eq(v.profile, "first_person")
    eq(v.details, false)
    s.values["hud.ads_minimal"] = false
    m.health, m.stims, m.stamina, m.throwables = 0.2, 0, 0.4, 0
    p:update(m, s, 0.016)
    eq(v.details, false)
    eq(v.health.visible, true)
    eq(v.health.tone, "danger")
    eq(v.stims.text, "STIM 0")
    eq(v.stims.tone, "danger")
    eq(v.throwables.visible, true)
    eq(v.stamina.visible, true)
    m.health = 0
    p:update(m, s, 0.016)
    eq(v.health.fill, 0)
    eq(v.health.text, "0")
    m.weapon.count, m.weapon.capacity, m.weapon.remaining = nil, nil, 0.25
    p:update(m, s, 0.016)
    eq(v.weapon.text, "25%")
    eq(v.weapon.kind, "remaining")
    m.weapon.remaining = 0.1
    p:update(m, s, 0.016)
    eq(v.weapon.text, "10%")
    eq(v.weapon.tone, "yellow")
    eq(v.reload.visible, false, "generic low remaining does not imply reloading is applicable")
    m.weapon.remaining = 2
    p:update(m, s, 0.016)
    eq(v.weapon.visible, false)
    m.weapon.reloading = true
    p:update(m, s, 0.016)
    eq(v.weapon.text, "-")
    eq(v.reload.text, "RELOADING")
    m.weapon.reloading = false
    m.weapon.count = 0
    p:update(m, s, 0.016)
    eq(v.weapon.text, "0")
    eq(v.reload.text, "RELOAD - EMPTY")
    s.values["hud.density"] = 2
    p:update(m, s, 0.016)
    eq(v.weapon.options_complete, false)
    m.weapon.throwing = true
    p:update(m, s, 0.016)
    eq(v.weapon.text, "0", "held grenade count remains truthful")
    eq(v.weapon.tone, "yellow")
    eq(v.reload.visible, false, "empty grenade is not a reload request")
    eq(v.reload.text, nil)
    eq(v.weapon.options_complete, false, "wielded gun metadata cannot claim a held grenade option strip")
    eq(v.weapon.options, nil)
    eq(v.weapon_options, false)
    m.weapon.reloading = true
    p:update(m, s, 0.016)
    eq(v.weapon.text, "0")
    eq(v.reload.visible, false, "throwable context overrides stale gun reload metadata")
    eq(v.throwables.visible, false, "held count has one display owner")
    m.weapon.known = false
    p:update(m, s, 0.016)
    eq(v.throwables.visible, true, "unknown primary count preserves supply fallback")
    m.weapon.known = true
    p:update(m, s, 0.016)
    eq(v.weapon_options, false)
    m.weapon.throwing, m.weapon.reloading = false, false
    p:update(m, s, 0.016)
    eq(v.reload.text, "RELOAD - EMPTY", "return to known gun restores normal reload policy")
    eq(v.weapon.options_complete, false, "return to gun keeps its original option presenter")
    eq(v.throwables.visible, true, "unheld supply returns without moving its slot")
    m.weapon.zoom_index = nil
    p:update(m, s, 0.016)
    eq(v.weapon.options_complete, false)
    eq(v.weapon_options, false)
    m.weapon.zoom_index = 1
    m.weapon.changeable.rpm = nil
    p:update(m, s, 0.016)
    eq(v.weapon.options_complete, false, "unknown role never claims full replacement")
    m.weapon.changeable.rpm, m.weapon.rpm_index = true, 9
    p:update(m, s, 0.016)
    eq(v.weapon.options_complete, false, "RPM selector must match original bounded icon contract")
    local invalids = { "known", "in_mission", "alive", "hud_visible", "menu_open", "blocked" }
    for _, field in ipairs(invalids) do
        local before = m[field]
        m[field] = nil
        p:update(m, s, 0.016)
        eq(v.visible, false, "unknown context " .. field)
        eq(v.weapon.visible, false)
        m[field] = before
    end
    m.aim.aiming = nil
    p:update(m, s, 0.016)
    eq(v.visible, false)
    eq(v.profile, nil)
    m.aim.aiming = false
    s.values["hud.enabled"] = false
    p:update(m, s, 0.016)
    eq(v.visible, false)
end
do
    -- A native driver classification and calibrated heat are distinct from the
    -- generic depletion gauge. Cold heat must never look like an empty magazine.
    local p, s, m = Policy.new(), settings(), model()
    m.weapon.ammo_kind, m.weapon.heat_weapon = "heat", true
    m.weapon.count, m.weapon.remaining, m.weapon.heat = 0, 0, 0
    local v = p:update(m, s, 0.016)
    eq(v.weapon.text, "0%")
    eq(v.weapon.kind, "heat")
    eq(v.weapon.fill, 0)
    eq(v.weapon.tone, "text")
    eq(v.reload.visible, false)
    eq(v.weapon_options, false)
    m.weapon.heat = 0.5
    p:update(m, s, 0.016)
    eq(v.weapon.text, "50%")
    m.weapon.heat = 1
    p:update(m, s, 0.016)
    eq(v.weapon.text, "100%")
    eq(v.weapon.fill, 1)
    eq(v.weapon.tone, "yellow")
    eq(v.reload.visible, false)
    m.weapon.heat, m.weapon.heat_locked = 0.4, true
    p:update(m, s, 0.016)
    eq(v.weapon.text, "40%")
    eq(v.weapon.tone, "yellow", "known native cooling lock stays visible")
    m.weapon.reloading = true
    p:update(m, s, 0.016)
    eq(v.weapon.text, "40%")
    eq(v.reload.visible, false, "heat does not reuse magazine reload instructions")
    m.weapon.heat, m.weapon.heat_locked, m.weapon.reloading = nil, false, false
    p:update(m, s, 0.016)
    eq(v.weapon.text, nil, "unknown calibration never falls back to stale zero count")
    eq(v.weapon.visible, false)
    eq(v.reload.visible, false)
    m.weapon.heat = 2
    p:update(m, s, 0.016)
    eq(v.weapon.text, nil, "invalid normalized heat stays unknown")
    m.weapon.heat, m.weapon.throwing = 1, true
    p:update(m, s, 0.016)
    eq(v.weapon.text, "0", "held throwable wins over old heat metadata")
    eq(v.weapon.kind, "count")
    eq(v.reload.visible, false)
    eq(v.weapon_options, false)
    m.weapon.ammo_kind, m.weapon.heat_weapon, m.weapon.throwing = nil, nil, false
    m.weapon.count, m.weapon.remaining, m.weapon.capacity = nil, 0.1, nil
    p:update(m, s, 0.016)
    eq(v.weapon.text, "10%")
    eq(v.weapon.kind, "remaining", "generic gauge remains generic despite stale heat value")
    eq(v.reload.visible, false)
end
do
    local p, s, m = Policy.new(), settings(), model()
    m.aim.aiming = true
    m.health, m.stamina, m.stims, m.throwables = 0.8, 0.4, 2, 0
    local v = p:update(m, s, 0.016)
    eq(v.details, false, "Quiet ADS never expands")
    eq(v.quiet_aim, true)
    eq(v.weapon.text, "32")
    eq(v.weapon.reserve, nil)
    eq(v.native_options, false, "routine native options intentionally hidden")
    eq(v.native_cooldowns, false, "routine cooldowns intentionally hidden")
    eq(v.health.visible, false, "old noncritical injury is supporting detail")
    eq(v.stamina.visible, false)
    eq(v.throwables.visible, false)
    eq(v.stims.visible, false)
    m.health = 0.7
    p:update(m, s, 0.016)
    eq(v.health.visible, true, "fresh damage interrupts Quiet ADS")
    for _ = 1, 14 do
        p:update(m, s, 0.1)
    end
    eq(v.health.visible, false, "damage hold expires during aim")
    m.health, m.stims = 0.2, 0
    p:update(m, s, 0.016)
    eq(v.health.visible, true)
    eq(v.health.text, "20")
    eq(v.stims.visible, true, "critical no-stim cue remains")
    m.weapon.count = 0
    p:update(m, s, 0.016)
    eq(v.reload.visible, true)
    eq(v.reload.text, "RELOAD - EMPTY")
    p:update(m, s, 0.016, true)
    eq(v.details, true, "explicit inspection reveals details while aiming")
    eq(v.weapon.reserve, "RESERVE 3")
    eq(v.native_options, true)
    eq(v.native_cooldowns, true)
    s.values["hud.density"] = 2
    p:update(m, s, 0.016, false)
    eq(v.details, true, "Detailed is an explicit full-information mode")
    eq(v.quiet_aim, false)
    s.values["hud.density"] = 1
    m.aim.first_person = true
    m.weapon.ammo_kind, m.weapon.heat, m.weapon.heat_weapon = "heat", 0, true
    p:update(m, s, 0.016)
    eq(v.profile, "first_person")
    eq(v.quiet_aim, true)
    eq(v.weapon.text, "0%")
    eq(v.reload.visible, false, "cold laser is never an empty gun")
    m.aim.first_person, m.aim.aiming = false, false
    p:update(m, s, 0.016)
    eq(v.native_options, true, "hipfire restores all original feature settings")
    eq(v.native_cooldowns, true)
end
do
    local p, s, m = Policy.new(), settings(), model()
    local rows = {
        { entry = 1, kind = 43, timer_kind = "cooldown", timer_seconds = 1, unavailable = false },
        { entry = 2, kind = 51, timer_kind = "cooldown", timer_seconds = 1, unavailable = false },
    }
    m.cooldowns = rows
    local v = p:update(m, s, 0.016)
    eq(v.ready.visible, false, "no initial ready event")
    for _, row in ipairs(rows) do
        row.timer_kind, row.timer_seconds = nil, nil
    end
    p:update(m, s, 0.016)
    eq(v.ready.text, "2 STRATAGEMS READY")
    for _ = 1, 20 do
        p:update(m, s, 0.1)
    end
    eq(v.ready.visible, false, "one held/coalesced cue expires")
    rows[1].timer_kind, rows[1].timer_seconds = "cooldown", 1
    p:update(m, s, 0.016)
    m.cooldowns = nil
    p:update(m, s, 0.016)
    rows[1].timer_kind, rows[1].timer_seconds = nil, nil
    m.cooldowns = rows
    p:update(m, s, 0.016)
    eq(v.ready.visible, false, "unknown interval cannot manufacture ready")
    m.stims = 3
    p:update(m, s, 0.016)
    eq(v.stims.visible, true, "supply change is contextual")
    for _ = 1, 21 do
        p:update(m, s, 0.1)
    end
    eq(v.stims.visible, false)
    m.health = 0.4
    p:update(m, s, 0.016)
    eq(v.health.visible, true)
    m.health = 1
    p:update(m, s, 0.2)
    eq(v.health.visible, true, "recovery hold")
    for _ = 1, 4 do
        p:update(m, s, 0.2)
    end
    eq(v.health.visible, false)
end
local function measure(_, text, size)
    return { left = -size * 0.1, bottom = -size * 0.2, right = #text * size * 0.6, top = size * 0.8 }
end
local function active(layout, key)
    for _, p in ipairs(layout.primitives) do
        if p.key == key then
            return p
        end
    end
end
local function near(a, b, why)
    check(math.abs(a - b) < 0.000001, why or (tostring(a) .. " ~= " .. tostring(b)))
end
do
    local p, s, m = Policy.new(), settings(), model()
    m.weapon.ammo_kind, m.weapon.heat_weapon = "heat", true
    m.weapon.count, m.weapon.remaining = 0, 0
    for display = 1, 3 do
        s.values["hud.heat_display"] = display
        for _, heat in ipairs({ 0, 0.25, 1 }) do
            m.weapon.heat = heat
            local v = p:update(m, s, 0.016)
            eq(v.weapon.kind, "heat")
            eq(v.weapon.fill, heat)
            local percentage
            if display ~= 2 then
                percentage = tostring(math.floor(heat * 100 + 0.5)) .. "%"
            end
            eq(v.weapon.text, percentage)
            eq(v.weapon.heat_bar, display ~= 1)
            eq(v.weapon.visible, true, "a cold known bar remains meaningful")
            eq(v.weapon.tone, heat == 1 and "yellow" or "text")
            eq(v.reload.visible, false)
        end
        for _, unknown in ipairs({ false, -1, 2, 0 / 0 }) do
            m.weapon.heat = unknown
            if unknown == false then
                m.weapon.heat = nil
            end
            local v = p:update(m, s, 0.016)
            eq(v.weapon.text, nil)
            eq(v.weapon.heat_bar, false)
            eq(v.weapon.visible, false)
        end
        m.weapon.heat, m.weapon.heat_locked = 0.4, true
        eq(p:update(m, s, 0.016).weapon.tone, "yellow")
        m.weapon.heat_locked, m.weapon.throwing = false, true
        local v = p:update(m, s, 0.016)
        eq(v.weapon.kind, "count")
        eq(v.weapon.text, "0")
        eq(v.weapon.heat_bar, false)
        m.weapon.throwing, m.weapon.ammo_kind, m.weapon.heat_weapon = false, nil, false
        m.weapon.count, m.weapon.remaining = nil, 0.1
        v = p:update(m, s, 0.016)
        eq(v.weapon.kind, "remaining")
        eq(v.weapon.text, "10%")
        eq(v.weapon.heat_bar, false, "generic gauges are never heat bars")
        eq(v.reload.visible, false)
        m.weapon.ammo_kind, m.weapon.heat_weapon, m.weapon.count, m.weapon.remaining = "heat", true, 0, 0
    end
end
do
    local p, s, m, layout, composition = Policy.new(), settings(), model(), Layout.new(), Composition.new()
    m.weapon.ammo_kind, m.weapon.heat_weapon, m.weapon.heat = "heat", true, 0.5
    m.weapon.count, m.aim.first_person = nil, true
    for _, height in ipairs({ 1080, 2160 }) do
        m.viewport.width, m.viewport.height = height / 1080 * 1920, height
        m.reticle.x, m.reticle.y = m.viewport.width / 2, height / 2
        s.values["hud.scale"] = height == 1080 and 100 or 125
        local scale = height / 1080 * s.values["hud.scale"] / 100
        for display = 1, 3 do
            s.values["hud.heat_display"] = display
            local v = p:update(m, s, 0.016, true)
            local local_layout = layout:update(v, s, m.viewport, nil, measure)
            eq(local_layout.valid, true)
            eq(active(layout, "ammo") ~= nil, display ~= 2)
            eq(active(layout, "heat_track") ~= nil, display ~= 1)
            if display ~= 1 then
                local track, fill, label =
                    active(layout, "heat_track"), active(layout, "heat_fill"), active(layout, "heat_label")
                eq(track.width, 80 * scale)
                eq(track.height, 8 * scale)
                eq(fill.width, 40 * scale)
                eq(fill.tone, "text")
                eq(label.text, "HEAT")
                eq(label.group, "weapon")
                check(Style.tokens.colors[track.tone] ~= nil)
                check(Style.tokens.colors[fill.tone] ~= nil)
                if display == 3 then
                    local reserve = active(layout, "reserve")
                    local metrics = measure(v.font, reserve.text, reserve.size)
                    check(reserve.y + metrics.top < track.y, "hybrid reserve hangs below the bar")
                end
            end
            local function reference(font, text, size)
                check(display ~= 2 or text ~= "0", "known bar primary needs no virtual text measurement")
                return measure(font, text, size)
            end
            check(composition:begin(local_layout, m, v, s, m.viewport, nil, reference, 0.016))
            layout:update(v, s, m.viewport, composition.anchors, measure)
            local primary = display == 2 and active(layout, "heat_track") or active(layout, "ammo")
            local center = display == 2 and primary.y + primary.height / 2
                or primary.y
                    + (measure(v.font, primary.text, primary.size).bottom + measure(v.font, primary.text, primary.size).top) / 2
            near(center, m.reticle.y, "selected primary stays on the first-person sight line")
            if display == 3 then
                local track = active(layout, "heat_track")
                check(track.y + track.height < m.reticle.y, "hybrid bar supports the percentage below sights")
            end
            for _, primitive in ipairs(layout.primitives) do
                check(Style.tokens.colors[primitive.tone] ~= nil)
                check(primitive.tone ~= "hud_plate", "resource bar has no background plate")
            end
        end
    end
end
do
    local s, m, p, layout = settings(), model(), Policy.new(), Layout.new()
    local v = p:update(m, s, 0.016)
    local local_layout = layout:update(v, s, m.viewport, nil, measure)
    check(local_layout.valid)
    eq(local_layout.slots.ammo.x, 65)
    eq(local_layout.slots.ammo.y, -60)
    eq(local_layout.slots.ammo_shadow.x, 66)
    eq(local_layout.slots.ammo_shadow.y, -61)
    eq(local_layout.slots.ammo_shadow.tone, "hud_shadow")
    eq(local_layout.slots.ammo_shadow.z, 950)
    eq(local_layout.slots.ammo_plate_1, nil, "Bracket has no label background plates")
    for _, primitive in ipairs(local_layout.primitives) do
        check(primitive.tone ~= "hud_plate", "no background plate token")
        check(not primitive.key:find("_plate_", 1, true), "no background plate primitive")
    end
    check(local_layout.bounds.left <= local_layout.slots.ammo_shadow.x)
    check(local_layout.bounds.bottom <= local_layout.slots.ammo_shadow.y)
    local a = assert(Anchor.resolve(m, s, m.viewport, local_layout.bounds))
    eq(a.x, 960)
    eq(a.y, 540)
    eq(a.source, "reticle")
    local final = layout:update(v, s, m.viewport, a, measure)
    eq(final, local_layout)
    eq(final.slots.ammo.x, 1025)
    eq(final.slots.ammo.y, 480)
    local ammo_slot = final.slots.ammo
    m.health, m.stamina, m.stims, m.throwables = 0.2, 0.5, 0, 0
    v = p:update(m, s, 0.016)
    layout:update(v, s, m.viewport, nil, measure)
    eq(layout.slots.ammo, ammo_slot)
    eq(layout.slots.health.x, -145)
    eq(layout.slots.health.y, -57)
    eq(layout.slots.health.width, 16)
    eq(layout.slots.health.height, 5)
    eq(active(layout, "health_text"), nil)
    eq(layout.slots.stamina.y, -64)
    s.values["hud.anchor"] = 1
    a = assert(Anchor.resolve(m, s, m.viewport, layout.bounds))
    eq(a.source, "body")
    eq(a.x, 800)
    m.weapon.reloading = true
    a = assert(Anchor.resolve(m, s, m.viewport, layout.bounds))
    eq(a.source, "reticle", "hip reload falls back from body")
    m.weapon.reloading = nil
    a = assert(Anchor.resolve(m, s, m.viewport, layout.bounds))
    eq(a.source, "reticle", "unknown hip reload cannot follow body")
    m.weapon.reloading, m.aim.switching = false, nil
    a = assert(Anchor.resolve(m, s, m.viewport, layout.bounds))
    eq(a.source, "reticle", "unknown switch cannot follow body")
    m.aim.switching = false
    m.aim.aiming = true
    a = assert(Anchor.resolve(m, s, m.viewport, layout.bounds))
    eq(a.source, "weapon")
    eq(a.x, 1100)
    m.weapon.reloading = true
    a = assert(Anchor.resolve(m, s, m.viewport, layout.bounds))
    eq(a.source, "reticle", "reload pins proven reticle")
    m.weapon.reloading = false
    m.aim.switching = true
    a = assert(Anchor.resolve(m, s, m.viewport, layout.bounds))
    eq(a.source, "reticle")
    m.aim.switching = false
    m.anchors.weapon.clipped = true
    a = assert(Anchor.resolve(m, s, m.viewport, layout.bounds))
    eq(a.source, "reticle", "clipped anchor falls back")
    m.anchors.weapon.clipped = false
    m.aim.first_person = true
    a = assert(Anchor.resolve(m, s, m.viewport, layout.bounds))
    eq(a.source, "reticle", "first-person screen pinned")
    s.values["hud.ads_offset_x"], s.values["hud.ads_offset_y"] = 20, 30
    a = assert(Anchor.resolve(m, s, m.viewport, layout.bounds))
    eq(a.x, 980)
    eq(a.y, 510)
    s.values["hud.offset_x"], s.values["hud.offset_y"] = 5, 7
    a = assert(Anchor.resolve(m, s, m.viewport, layout.bounds))
    eq(a.x, 985)
    eq(a.y, 503, "ADS offsets add to general offsets")
    m.reticle.known = false
    eq(Anchor.resolve(m, s, m.viewport, layout.bounds), nil)
    m.reticle.known = true
    for _, viewport in ipairs({
        { width = 1920, height = 1080 },
        { width = 3840, height = 2160 },
        { width = 3440, height = 1440 },
    }) do
        m.aim.first_person, m.aim.aiming = false, true
        m.viewport = viewport
        v = p:update(m, s, 0.016)
        layout:update(v, s, viewport, nil, measure)
        for _, reticle in ipairs({ { -5000, -5000 }, { 99999, 99999 }, { 0, viewport.height } }) do
            m.reticle.x, m.reticle.y = reticle[1], reticle[2]
            a = assert(Anchor.resolve(m, s, viewport, layout.bounds))
            layout:update(v, s, viewport, a, measure)
            check(layout.bounds.left >= 0 and layout.bounds.bottom >= 0, "complete measured lower bounds")
            check(
                layout.bounds.right <= viewport.width and layout.bounds.top <= viewport.height,
                "complete measured upper bounds"
            )
            layout:update(v, s, viewport, nil, measure)
        end
    end
    eq(Anchor.resolve(m, s, { width = 10, height = 10 }, layout.bounds), nil, "oversized measured text fails closed")
    local bad = layout:update(v, s, m.viewport, nil, function()
        return nil, "font unavailable"
    end)
    eq(bad.valid, false)
    eq(bad.reason, "font unavailable")
end
do
    local p, s, m, layout, composition = Policy.new(), settings(), model(), Layout.new(), Composition.new()
    m.weapon.ammo_kind, m.weapon.heat_weapon, m.weapon.count = "heat", true, nil
    m.aim.first_person = true
    for _, height in ipairs({ 1080, 2160 }) do
        m.viewport.width, m.viewport.height = height / 1080 * 1920, height
        m.reticle.x, m.reticle.y = m.viewport.width / 2, height / 2
        s.values["hud.scale"] = height == 1080 and 100 or 125
        local scale = height / 1080 * s.values["hud.scale"] / 100
        for display = 2, 3 do
            s.values["hud.heat_display"] = display
            for _, vertical in ipairs({ false, true }) do
                s.values["hud.heat_bar_vertical"] = vertical
                for _, fraction in ipairs({ 0, 0.6, 1 }) do
                    m.weapon.heat = fraction
                    local v = p:update(m, s, 0.016, true)
                    v.weapon.heat_warning_mix, v.weapon.heat_pulse = 0.75, 0.5
                    local local_layout = layout:update(v, s, m.viewport, nil, measure)
                    eq(local_layout.valid, true)
                    local track, fill, label =
                        active(layout, "heat_track"), active(layout, "heat_fill"), active(layout, "heat_label")
                    eq(track.width, (vertical and 8 or 80) * scale)
                    eq(track.height, (vertical and 80 or 8) * scale)
                    near(fill.width, (vertical and 8 or 80 * fraction) * scale)
                    near(fill.height, (vertical and 80 * fraction or 8) * scale)
                    eq(fill.x, track.x)
                    eq(fill.y, track.y, "vertical heat grows upward from the same bottom edge")
                    eq(fill.danger_mix, 0.75)
                    eq(fill.alpha, v.opacity * 0.5)
                    eq(track.alpha, v.opacity, "warning pulse never dims the stable track")
                    eq(label.alpha, v.opacity)
                    eq(track.tone, "line_strong")
                    if vertical then
                        local reserve = active(layout, "reserve")
                        local rm = measure(v.font, reserve.text, reserve.size)
                        check(reserve.y + rm.top < track.y - 4 * scale, "reserve clears the complete vertical bar")
                        if display == 3 then
                            local ammo = active(layout, "ammo")
                            local am = measure(v.font, ammo.text, ammo.size)
                            check(track.x >= ammo.x + am.right + 12 * scale, "vertical Hybrid sits beside percentage")
                            local lm = measure(v.font, label.text, label.size)
                            check(
                                label.y + lm.bottom >= track.y + track.height + 5 * scale,
                                "HEAT label clears the bar top"
                            )
                        end
                    end
                    check(composition:begin(local_layout, m, v, s, m.viewport, nil, measure, 0.016))
                    layout:update(v, s, m.viewport, composition.anchors, measure)
                    track, fill = active(layout, "heat_track"), active(layout, "heat_fill")
                    local primary = display == 2 and track or active(layout, "ammo")
                    local mid = display == 2 and primary.y + primary.height / 2
                        or primary.y
                            + (measure(v.font, primary.text, primary.size).bottom + measure(
                                v.font,
                                primary.text,
                                primary.size
                            ).top) / 2
                    near(mid, m.reticle.y, "portrait and landscape primaries keep FP sight height")
                    if vertical then
                        near(track.y + track.height / 2, m.reticle.y, "vertical Hybrid aligns beside primary")
                    end
                    for _, primitive in ipairs(layout.primitives) do
                        local ext = primitive.kind == "text" and measure(v.font, primitive.text, primitive.size)
                            or { left = 0, right = primitive.width, bottom = 0, top = primitive.height }
                        check(
                            primitive.x + ext.left >= layout.bounds.left - 0.000001
                                and primitive.x + ext.right <= layout.bounds.right + 0.000001
                                and primitive.y + ext.bottom >= layout.bounds.bottom - 0.000001
                                and primitive.y + ext.top <= layout.bounds.top + 0.000001,
                            "complete bounds include portrait label/shadow/track/fill"
                        )
                        check(Style.tokens.colors[primitive.tone] ~= nil)
                        check(primitive.tone ~= "hud_plate")
                    end
                end
            end
        end
    end
end
do
    local p, s, m, layout = Policy.new(), settings(), model(), Layout.new()
    s.values["hud.heat_display"] = 1
    m.weapon.ammo_kind, m.weapon.heat, m.weapon.count = "heat", 0.4, nil
    local v = p:update(m, s, 0.016, true)
    layout:update(v, s, m.viewport, nil, measure)
    local before, bounds = {}, {}
    for _, primitive in ipairs(layout.primitives) do
        before[primitive.key] = {
            x = primitive.x,
            y = primitive.y,
            width = primitive.width,
            height = primitive.height,
            text = primitive.text,
        }
    end
    for key, value in pairs(layout.bounds) do
        bounds[key] = value
    end
    s.values["hud.heat_bar_vertical"] = true
    v = p:update(m, s, 0.016, true)
    layout:update(v, s, m.viewport, nil, measure)
    eq(active(layout, "heat_track"), nil)
    for _, primitive in ipairs(layout.primitives) do
        local old = assert(before[primitive.key])
        eq(primitive.x, old.x)
        eq(primitive.y, old.y)
        eq(primitive.width, old.width)
        eq(primitive.height, old.height)
        eq(primitive.text, old.text)
    end
    for key, value in pairs(bounds) do
        eq(layout.bounds[key], value, "Percentage geometry ignores orientation")
    end
end
do
    local s, m, p, layout = settings(), model(), Policy.new(), Layout.new()
    s.values["hud.heat_display"], s.values["hud.heat_bar_vertical"] = 2, true
    m.weapon.ammo_kind, m.weapon.heat, m.weapon.count = "heat", 0.6, nil
    local function wide_label(font, text, size)
        local metrics = measure(font, text, size)
        if text == "HEAT" then
            metrics.right = 7 * size
        end
        return metrics
    end
    local view = p:update(m, s, 0.016, true)
    layout:update(view, s, m.viewport, nil, wide_label)
    local track, label = active(layout, "heat_track"), active(layout, "heat_label")
    local metrics = wide_label(view.font, label.text, label.size)
    check(track.x >= label.x + metrics.right + 12, "wide native label metrics cannot overlap the portrait bar")
    eq(track.width, 8)
    eq(track.height, 80)
end
local function renderer_fixture()
    local state =
        { worlds = { "world" }, calls = 0, creates = 0, updates = 0, destroys = 0, bindings = 0, gui_creates = 0 }
    local function vector(x, y, z)
        return { x = x, y = y, z = z }
    end
    local function vec()
        return setmetatable({
            x = function(v)
                return v.x
            end,
            y = function(v)
                return v.y
            end,
        }, {
            __call = function(_, ...)
                return vector(...)
            end,
        })
    end
    local sr =
        { Vector2 = vec(), Vector3 = vec(), Gui = {}, Application = {}, World = {}, IdString64 = {}, Material = {} }
    sr.Color = function(a, r, g, b)
        return { a, r, g, b }
    end
    sr.IdString64.from_hex = function(hex)
        return { hex = hex }
    end
    sr.Application.worlds = function()
        if state.world_throw then
            error("unknown worlds")
        end
        return state.worlds
    end
    sr.World.create_screen_gui = function(world, mode, x, y)
        eq(world, "world")
        eq(mode, "scale")
        eq(x, 1)
        eq(y, 1)
        state.gui_creates = state.gui_creates + 1
        return "gui"
    end
    local G = sr.Gui
    G.resolution = function(...)
        eq(select("#", ...), 0)
        return 1920, 1080
    end
    G.set_visible = function(_, shown)
        state.calls = state.calls + 1
        if state.fail_hide and not shown then
            return false
        end
        state.shown = shown
    end
    G.material = function(_, id)
        check(type(id.hex) == "string")
        return "material"
    end
    G.create_material = function()
        error("existing original font material should be used")
    end
    sr.Material.set_texture = function(material, key, atlas)
        eq(material, "material")
        eq(key.hex, "88BAC99B00000000")
        check(type(atlas.hex) == "string")
        state.bindings = state.bindings + 1
        return not state.fail_bind
    end
    G.text_extents = function(_, text, font, size)
        check(type(font.hex) == "string")
        local metrics = measure(nil, text, size)
        return vector(metrics.left, metrics.bottom), vector(metrics.right, metrics.top)
    end
    local function created(kind, ...)
        if state.fail_create then
            error("primitive construction failed")
        end
        state.calls, state.creates = state.calls + 1, state.creates + 1
        return kind .. state.creates
    end
    G.text = function(gui, text, font, size, material, position, colour)
        check(type(font.hex) == "string" and type(material.hex) == "string", "HEX ids resolved at immediate draw call")
        local valid = false
        for _, token in pairs(mod.require("ui/style.lua").tokens.colors) do
            if colour[2] == token[1] and colour[3] == token[2] and colour[4] == token[3] then
                valid = true
            end
        end
        check(valid, "fixed GUI colour derives from kit token")
        return created("text", gui, text, font, size, material, position, colour)
    end
    G.rect = function(...)
        return created("rect", ...)
    end
    for _, kind in ipairs({ "text", "rect", "bitmap" }) do
        G["destroy_" .. kind] = function()
            state.calls = state.calls + 1
            if state.fail_destroy then
                return false
            end
            state.destroys = state.destroys + 1
        end
        G["update_" .. kind] = function()
            state.calls = state.calls + 1
            if state.fail_update then
                return false
            end
            state.updates = state.updates + 1
        end
    end
    G.reset = function()
        state.calls = state.calls + 1
        if state.fail_reset then
            return false
        end
    end
    local globals = { stingray = sr }
    local r, m, s, p, layout = Renderer.new({ globals = globals }), model(), settings(), Policy.new(), Layout.new()
    local function pipeline()
        local v = p:update(m, s, 0.016)
        local okay, why = r:prepare(m)
        if not okay then
            return false, why
        end
        local viewport = assert(r:viewport())
        local mf = function(...)
            return r:measure(...)
        end
        layout:update(v, s, viewport, nil, mf)
        local a = assert(Anchor.resolve(m, s, viewport, layout.bounds))
        layout:update(v, s, viewport, a, mf)
        return r:render(m, v, layout)
    end
    return state, sr, globals, r, m, s, p, layout, pipeline
end
do
    local state, sr, globals, r, m, s, p, layout, tick = renderer_fixture()
    s.values["hud.heat_display"] = 2
    m.weapon.ammo_kind, m.weapon.heat_weapon, m.weapon.count, m.weapon.heat = "heat", true, nil, 0
    check(tick())
    eq(r.entries.ammo, nil)
    eq(r.entries.heat_fill.width, 0, "cold accumulated heat has a zero fill")
    local track, fill = r.entries.heat_track, r.entries.heat_fill
    local calls, creates, measures = state.calls, state.creates, r.stats.measures
    for _ = 1, 20 do
        check(tick())
    end
    eq(state.calls, calls, "unchanged heat bars issue no native writes")
    eq(state.creates, creates)
    eq(r.stats.measures, measures)
    local updates = state.updates
    m.weapon.heat = 0.5
    check(tick())
    eq(r.entries.heat_track, track)
    eq(r.entries.heat_fill, fill)
    eq(fill.width, 40)
    eq(state.creates, creates)
    eq(state.updates, updates + 1, "a heat change updates only the retained fill")
    s.values["hud.heat_display"] = 3
    check(tick())
    eq(r.entries.ammo.text, "50%")
    eq(r.entries.heat_track, track)
    eq(state.creates, creates + 2, "hybrid adds only percentage and its shadow")
    s.values["hud.heat_display"] = 2
    check(tick())
    eq(r.entries.ammo, nil)
    eq(r.entries.heat_track, track)
    eq(r:close(), true)
end
do
    local state, sr, globals, r, m, s, p, layout, tick = renderer_fixture()
    check(tick())
    eq(state.gui_creates, 1)
    eq(state.bindings, 1)
    eq(state.shown, true)
    local calls, creates, measures = state.calls, state.creates, r.stats.measures
    for _ = 1, 100 do
        check(tick())
    end
    eq(state.calls, calls, "unchanged native write count")
    eq(state.creates, creates)
    eq(r.stats.measures, measures)
    s.values["hud.density"] = 2
    local okay, claims = tick()
    check(okay)
    eq(claims.weapon_options, false, "successful Bracket draw remains additive")
    eq(claims.cooldowns, false)
    eq(state.bindings, 1, "atlas bound once per descriptor/GUI lifetime")
    m.weapon.count = 31
    local old_creates = state.creates
    check(tick())
    check(state.updates > 0)
    eq(state.creates, old_creates, "changed ammo updates retained text ID")
    state.worlds = nil
    calls = state.calls
    local closed, why = r:close()
    eq(closed, false)
    check(why:find("unknown", 1, true))
    eq(state.calls, calls)
    check(globals.DBFModularScreenGuiPool.records.world.owner ~= nil)
    state.world_throw = true
    eq(r:close(), false)
    eq(state.calls, calls, "throwing world query is unknown, not retirement")
    state.world_throw = false
    state.worlds = { "world" }
    state.fail_destroy = true
    eq(r:close(), false)
    eq(state.shown, false, "hide before destroy failure")
    check(next(globals.DBFModularScreenGuiPool.records.world.primitives) ~= nil, "failed ID retained")
    state.fail_destroy = false
    eq(r:close(), true)
    eq(globals.DBFModularScreenGuiPool.records.world.owner, nil)
    check(tick())
    eq(state.gui_creates, 1, "same live GUI parked and reused")
    state.worlds = {}
    calls = state.calls
    eq(r:close(), true)
    eq(state.calls, calls, "proven retired world gets no stale calls")
    eq(globals.DBFModularScreenGuiPool.records.world, nil)
end
do
    local state, sr, globals, r, m, s, p, layout, tick = renderer_fixture()
    s.values["hud.heat_display"], s.values["hud.heat_bar_vertical"] = 2, true
    m.weapon.ammo_kind, m.weapon.heat_weapon, m.weapon.count, m.weapon.heat = "heat", true, nil, 0
    check(tick())
    local track, fill = r.entries.heat_track, r.entries.heat_fill
    eq(track.width, 8)
    eq(track.height, 80)
    eq(fill.width, 8)
    eq(fill.height, 0, "cold vertical heat retains an exact zero-height fill")
    local calls, creates, measures = state.calls, state.creates, r.stats.measures
    for _ = 1, 10 do
        check(tick())
    end
    eq(state.calls, calls)
    eq(state.creates, creates)
    eq(r.stats.measures, measures)
    for _, heat in ipairs({ 0.6, 1, 0 }) do
        m.weapon.heat = heat
        check(tick())
        eq(r.entries.heat_track, track)
        eq(r.entries.heat_fill, fill)
        eq(fill.height, 80 * heat)
        eq(fill.y, track.y)
        eq(state.creates, creates, "heat/orientation changes reuse the fill rectangle")
    end
    s.values["hud.heat_bar_vertical"] = false
    check(tick())
    eq(r.entries.heat_track, track)
    eq(r.entries.heat_fill, fill)
    eq(fill.width, 0)
    eq(fill.height, 8)
    eq(state.creates, creates)
    eq(r:close(), true)
end
do
    local state, sr, globals, r, m, s, p, layout, tick = renderer_fixture()
    state.fail_hide = true
    eq(tick(), false)
    eq(state.gui_creates, 1)
    check(globals.DBFModularScreenGuiPool.records.world.owner ~= nil, "creation failure publishes GUI owner")
    eq(r:close(), false, "failed acquire still has retryable cleanup")
    state.fail_hide = false
    eq(r:close(), true)
    check(tick())
    state.fail_update = true
    m.weapon.count = 30
    eq(tick(), false)
    eq(state.shown, false)
    eq(r.claims.weapon_options, false)
    state.fail_update = false
    check(tick(), "retry retained primitive update")
    eq(r:close(), true)
end
do
    local state, sr, globals, r, m, s, p, layout, tick = renderer_fixture()
    state.fail_bind = true
    eq(tick(), false)
    eq(state.shown, false)
    check(globals.DBFModularScreenGuiPool.records.world ~= nil)
    state.fail_bind = false
    check(tick())
    eq(r:close(), true)
    local pool, owner, other = Pool.new(sr, globals), {}, {}
    local lease = assert(pool:acquire("world", owner))
    eq(pool:acquire("world", other), nil, "second owner cannot steal ledger")
    lease.record.owner = other
    local calls = state.calls
    eq(lease:hide(), false)
    eq(state.calls, calls, "foreign owner not hidden")
    lease.record.owner = owner
    check(lease:release())
end
do
    -- Actual retained renderer: bone motion updates existing IDs in place;
    -- anything that can retire an ID/GUI/font still requires native restoration.
    local state, sr, globals, r, m, s, p, layout, tick = renderer_fixture()
    check(tick())
    local v = p:update(m, s, 0.016)
    local dep = {
        key = "cooldown/retained",
        kind = "text",
        text = "12",
        x = 960,
        y = 400,
        z = 951,
        size = 12,
        width = 0,
        height = 0,
        tone = "text",
        alpha = 0.94,
    }
    layout.primitives[#layout.primitives + 1] = dep
    check(r:render(m, v, layout))
    local allow, guards = false, 0
    r.before_change = function()
        guards = guards + 1
        return allow, "native restore refused"
    end
    local creates, destroys, gui, updates, lease =
        state.creates, state.destroys, state.gui_creates, state.updates, r.lease
    dep.text = "11"
    for i = 1, 60 do
        dep.x, dep.y = 960 + i * 0.5, 400 + i * 0.25
        check(r:render(m, v, layout))
    end
    eq(guards, 0, "moving existing labels never restores the Original GUI")
    eq(state.creates, creates)
    eq(state.destroys, destroys)
    eq(state.gui_creates, gui)
    eq(state.updates, updates + 60)
    eq(r.lease, lease)
    eq(r.entries[dep.key].text, "11")
    local calls = state.calls
    local extra = {}
    for k, x in pairs(dep) do
        extra[k] = x
    end
    extra.key = "cooldown/new"
    layout.primitives[#layout.primitives + 1] = extra
    eq(r:render(m, v, layout), false, "new dependency requires restore")
    eq(state.calls, calls, "complete preflight precedes all GUI mutation")
    layout.primitives[#layout.primitives] = nil
    local updater = sr.Gui.update_text
    sr.Gui.update_text = nil
    dep.text = "10"
    eq(r:render(m, v, layout), false, "missing updater would recreate an owned ID")
    eq(state.calls, calls)
    eq(r.entries[dep.key].text, "11")
    sr.Gui.update_text = updater
    check(r:render(m, v, layout))
    calls = state.calls
    dep.kind, dep.width, dep.height = "rect", 20, 1
    eq(r:render(m, v, layout), false, "kind change waits for restore")
    eq(state.calls, calls)
    dep.kind, dep.width, dep.height = "text", 0, 0
    layout.primitives[#layout.primitives] = nil
    eq(r:render(m, v, layout), false, "removing a dependency waits for restore")
    eq(state.calls, calls)
    layout.primitives[#layout.primitives + 1] = dep
    local font = m.font.font
    m.font.font = "1010101010101010"
    eq(r:prepare(m), false, "font replacement retains the current dependency")
    eq(state.calls, calls)
    m.font.font = font
    eq(r:hide(), false)
    eq(state.shown, true)
    m.generation = m.generation + 1
    eq(r:prepare(m), false)
    eq(r.lease, lease)
    eq(state.calls, calls, "generation rebuild waits for native restore")
    m.generation = m.generation - 1
    check(r:prepare(m))
    state.fail_update = true
    dep.x = dep.x + 1
    eq(r:render(m, v, layout), false, "failed in-place update retains dependency on restore refusal")
    eq(state.shown, true)
    eq(r.lease, lease)
    eq(r.entries[dep.key].text, "10")
    eq(state.destroys, destroys)
    state.fail_update = false
    allow = true
    eq(r:close(), true)
    check(guards >= 7)
end
do
    -- Health remains a measured critical indicator without a redundant number.
    for _, height in ipairs({ 1080, 2160 }) do
        local p, s, m, layout = Policy.new(), settings(), model(), Layout.new()
        m.viewport.width, m.viewport.height = height / 1080 * 1920, height
        s.values["hud.scale"] = 125
        local scale = height / 1080 * 1.25
        for _, health in ipairs({ 0, 0.2, 0.8, 1 }) do
            m.health, m.stamina = health, 0.5
            local view = p:update(m, s, 0.016, true)
            layout:update(view, s, m.viewport, nil, measure)
            eq(view.health.fill, health, "native health data is retained")
            eq(active(layout, "health_text"), nil)
            eq(active(layout, "health_text_shadow"), nil)
            eq(active(layout, "health_track").height, 5 * scale)
            eq(active(layout, "health").height, 5 * scale)
            near(active(layout, "health_track").y + active(layout, "health_track").height / 2, -54.5 * scale)
            eq(active(layout, "stamina_track").height, 2 * scale)
            if health <= 0.25 then
                eq(active(layout, "health").tone, "danger")
            end
        end
        m.health, m.stims, m.throwables = 0.2, 4, 5
        local view = p:update(m, s, 0.016, true)
        local data = {
            stims = { known = true, texture = "93b43ada76587340", width = 64, height = 32 },
            throwables = { known = true, texture = "123456789abcdef0", width = 32, height = 64 },
        }
        layout:update(view, s, m.viewport, nil, measure, data)
        eq(#layout.supplies, 2)
        eq(active(layout, "stims").text, "4")
        eq(active(layout, "throwables").text, "5")
        near(layout.supplies[1].width / layout.supplies[1].height, 2)
        near(layout.supplies[2].width / layout.supplies[2].height, 0.5)
        for _, icon in ipairs(layout.supplies) do
            local b = layout.group_bounds.vitals
            check(icon.x >= b.left and icon.x + icon.width <= b.right)
            check(icon.y >= b.bottom and icon.y + icon.height <= b.top)
            local text = active(layout, icon.key)
            local ink = measure(view.font, text.text, text.size)
            check(icon.x + icon.width + 3 * scale <= text.x + ink.left, "native sprite and count do not overlap")
        end
        data.throwables.known = false
        layout:update(view, s, m.viewport, nil, measure, data)
        eq(#layout.supplies, 1)
        eq(active(layout, "throwables").text, "G 5", "unknown icon keeps its descriptive fallback")
        layout:update(view, s, m.viewport, nil, measure)
        eq(#layout.supplies, 0)
        eq(active(layout, "stims").text, "STIM 4")
        eq(active(layout, "throwables").text, "G 5")
        m.aim.aiming = true
        view = p:update(m, s, 0.016)
        layout:update(view, s, m.viewport, nil, measure, data)
        eq(#layout.supplies, 0, "Quiet aiming preserves contextual supply visibility")
    end
end
do
    -- The open trim surrounds only current vitals, including native images.
    local p, s, m, layout = Policy.new(), settings(), model(), Layout.new()
    s.values["hud.scale"] = 125
    local view = p:update(m, s, 0.016, true)
    local data = { stims = { known = true, texture = "93b43ada76587340", width = 64, height = 32 } }
    layout:update(view, s, m.viewport, nil, measure, data)
    local left, right, bottom, top = math.huge, -math.huge, math.huge, -math.huge
    for _, primitive in ipairs(layout.primitives) do
        if primitive.group == "vitals" and not primitive.key:find("^vitals_bracket") then
            left, right =
                math.min(left, primitive.x + primitive.ink_left), math.max(right, primitive.x + primitive.ink_right)
            bottom, top =
                math.min(bottom, primitive.y + primitive.ink_bottom), math.max(top, primitive.y + primitive.ink_top)
        end
    end
    for _, icon in ipairs(layout.supplies) do
        left, right = math.min(left, icon.x), math.max(right, icon.x + icon.width)
        bottom, top = math.min(bottom, icon.y), math.max(top, icon.y + icon.height)
    end
    local l, r = active(layout, "vitals_bracket_left"), active(layout, "vitals_bracket_right")
    near(l.x, left - 7 * layout.scale)
    near(r.x + r.width, right + 7 * layout.scale)
    near(l.y, bottom - 6 * layout.scale)
    near(l.y + l.height, top + 6 * layout.scale)
    local strokes = 0
    for _, primitive in ipairs(layout.primitives) do
        if primitive.key:find("^vitals_bracket") then
            strokes = strokes + 1
            eq(primitive.kind, "rect")
            eq(primitive.group, "vitals")
            eq(primitive.tone, "text")
            near(primitive.alpha, view.opacity * 0.7)
        end
    end
    eq(strokes, 6, "two open rails with four short inward caps")
    check(active(layout, "vitals_bracket_left_top").width < (right - left) / 2)
    m.aim.aiming = true
    view = p:update(m, s, 0.016)
    layout:update(view, s, m.viewport, nil, measure, data)
    eq(layout.group_bounds.vitals.count, 0)
    eq(active(layout, "vitals_bracket_left"), nil, "Quiet ADS hides trim with its empty role")
    eq(active(layout, "vitals_bracket_right"), nil)
end
do
    -- The current native coil replaces only the bar's descriptive label. Its
    -- rotated visual bounds belong to the same weapon anchor as the meter.
    for _, height in ipairs({ 1080, 2160 }) do
        for _, display in ipairs({ 1, 2, 3 }) do
            for _, vertical in ipairs({ false, true }) do
                local p, s, m, layout, composition = Policy.new(), settings(), model(), Layout.new(), Composition.new()
                local scale = height / 1080 * 1.25
                m.viewport.width, m.viewport.height = height / 1080 * 1920, height
                m.reticle.x, m.reticle.y = m.viewport.width / 2, height / 2
                m.aim.first_person = true
                m.weapon.ammo_kind, m.weapon.heat_weapon, m.weapon.heat = "heat", true, 0.6
                m.weapon.count, m.weapon.reserve = nil, nil
                s.values["hud.scale"], s.values["hud.anchor_damping_ms"] = 125, 0
                s.values["hud.heat_display"], s.values["hud.heat_bar_vertical"] = display, vertical
                local data = { heat = { known = true, texture = "123456789abcdef0", width = 32, height = 64 } }
                local view = p:update(m, s, 0.016, true)
                layout:update(view, s, m.viewport, nil, measure, data)
                eq(layout.valid, true)
                eq(#layout.supplies, display == 1 and 0 or 1)
                eq(active(layout, "heat_label"), nil)
                if display ~= 1 then
                    local icon, track = layout.supplies[1], active(layout, "heat_track")
                    eq(icon.key, "heat")
                    eq(icon.rotation, vertical and 0 or 90, "the proven native setter takes degrees")
                    near(icon.width / icon.height, vertical and 0.5 or 2, "rotation preserves source aspect")
                    near(icon.width, (vertical and 14 or 28) * scale)
                    near(icon.height, (vertical and 28 or 14) * scale)
                    if vertical then
                        near(icon.x + icon.width, track.x - 6 * scale, "upright coil sits left of the vertical meter")
                        near(icon.y, track.y, "upright coil and vertical meter share their bottom edge")
                    else
                        check(icon.x + icon.width <= track.x - 6 * scale, "coil leaves clear space before its meter")
                        near(icon.y + icon.height / 2, track.y + track.height / 2)
                    end
                    if not vertical and display == 3 then
                        local ammo = active(layout, "ammo")
                        local ink = measure(view.font, ammo.text, ammo.size)
                        check(
                            icon.y + icon.height <= ammo.y + ink.bottom - layout.pixel - 4 * scale,
                            "horizontal coil and meter clear the measured percentage and shadow"
                        )
                    end
                    local reserve = active(layout, "reserve")
                    if reserve then
                        local ink = measure(view.font, reserve.text, reserve.size)
                        check(reserve.y + ink.top <= icon.y - 6 * scale, "support text stays below the complete coil")
                    end
                    local group = layout.group_bounds.weapon
                    check(icon.x >= group.left and icon.x + icon.width <= group.right)
                    check(icon.y >= group.bottom and icon.y + icon.height <= group.top)
                    eq(composition:begin(layout, m, view, s, m.viewport, nil, measure, 0), true)
                    layout:update(view, s, m.viewport, composition.anchors, measure, data)
                    local merged = composition:assemble(layout)
                    eq(merged.supplies, layout.supplies, "the measured native image travels with the composed group")
                    icon, track = layout.supplies[1], active(layout, "heat_track")
                    check(icon.x >= merged.bounds.left and icon.x + icon.width <= merged.bounds.right)
                    check(icon.y >= merged.bounds.bottom and icon.y + icon.height <= merged.bounds.top)
                    local ammo = active(layout, "ammo")
                    if ammo then
                        local ink = measure(view.font, ammo.text, ammo.size)
                        near(ammo.y + (ink.bottom + ink.top) / 2, m.reticle.y)
                    else
                        near(track.y + track.height / 2, m.reticle.y, "bar-only primary remains sight-centered")
                    end
                    local saved = icon
                    layout:update(view, s, m.viewport, composition.anchors, measure, data)
                    eq(layout.supplies[1], saved, "coil image specification is retained")
                    data.heat.known = false
                    layout:update(view, s, m.viewport, composition.anchors, measure, data)
                    eq(#layout.supplies, 0)
                    eq(active(layout, "heat_label").text, "HEAT", "cold native image keeps its descriptive fallback")
                    data.heat.known, data.heat.texture = true, "invalid"
                    layout:update(view, s, m.viewport, composition.anchors, measure, data)
                    eq(#layout.supplies, 0)
                    eq(active(layout, "heat_label").text, "HEAT")
                end
            end
        end
    end
end
do
    -- The upright coil must clear both the widest percentage and every original
    -- option cell, including where the row overlaps its lower vertical span.
    for _, height in ipairs({ 1080, 2160 }) do
        for _, display in ipairs({ 2, 3 }) do
            for count = 1, 4 do
                local p, s, m, layout, composition = Policy.new(), settings(), model(), Layout.new(), Composition.new()
                local scale = height / 1080 * 1.25
                m.viewport.width, m.viewport.height = height / 1080 * 1920, height
                m.reticle.x, m.reticle.y = m.viewport.width / 2, height / 2
                m.aim.first_person = true
                m.weapon.ammo_kind, m.weapon.heat_weapon, m.weapon.count = "heat", true, nil
                s.values["hud.scale"], s.values["hud.anchor_damping_ms"] = 125, 0
                s.values["hud.heat_display"], s.values["hud.heat_bar_vertical"] = display, true
                local data = { heat = { known = true, texture = "fb6b3350a1645aa8", width = 17, height = 34 } }
                local metrics = {
                    ready = true,
                    count = count,
                    width = (22 * count + 5 * (count - 1)) * scale,
                    height = 22 * scale,
                    root = m.identity,
                    generation = m.generation,
                }
                local previous_x
                for _, fraction in ipairs({ 0, 0.6, 1 }) do
                    m.weapon.heat = fraction
                    local view = p:update(m, s, 0.016, true)
                    layout:update(view, s, m.viewport, nil, measure, data, metrics)
                    local icon, track = layout.supplies[1], active(layout, "heat_track")
                    near(icon.y, track.y)
                    near(icon.x + icon.width + 6 * scale, track.x)
                    check(icon.x >= layout.strip_bounds.right + 8 * scale, "coil clears all native controls")
                    if display == 3 then
                        local maximum = measure(view.font, "100%", 30 * scale)
                        check(icon.x >= math.max(145 * scale, 65 * scale + maximum.right) + 8 * scale)
                    end
                    if previous_x then
                        near(track.x, previous_x, "zero-to-full percentage changes cannot move the coil or bar")
                    end
                    previous_x = track.x
                    eq(composition:begin(layout, m, view, s, m.viewport, metrics, measure, 0), true)
                    layout:update(view, s, m.viewport, composition.anchors, measure, data, metrics)
                    local merged = composition:assemble(layout)
                    icon, track = layout.supplies[1], active(layout, "heat_track")
                    near(icon.y, track.y)
                    check(icon.x >= merged.bounds.left and icon.x + icon.width <= merged.bounds.right)
                    check(icon.y >= merged.bounds.bottom and icon.y + icon.height <= merged.bounds.top)
                    local ammo = active(layout, "ammo")
                    if ammo then
                        local ink = measure(view.font, ammo.text, ammo.size)
                        near(ammo.y + (ink.bottom + ink.top) / 2, m.reticle.y)
                    else
                        near(track.y + track.height / 2, m.reticle.y)
                    end
                end
            end
        end
    end
end
print("hud policy/anchor/layout/renderer: " .. checks .. " checks passed")
