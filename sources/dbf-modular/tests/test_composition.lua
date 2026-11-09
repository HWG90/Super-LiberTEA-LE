-- Real Policy + Bracket Layout + Composition; only native presenter measurements
-- and font extents are fixture data. No GUI/game/installed settings access.
local Support = assert(loadfile("tests/support.lua"))()
local project = Support.project()
local Policy, Layout, Composition =
    project.require("hud/policy.lua"), project.require("hud/bracket_layout.lua"), project.require("hud/composition.lua")
local Anchor = project.require("hud/anchor.lua")
local checks, cases = 0, 0
local function eq(actual, expected, why)
    checks = checks + 1
    assert(actual == expected, (why or "different") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function check(value, why)
    eq(not not value, true, why)
end
local function near(actual, expected, why)
    check(math.abs(actual - expected) < 0.000001, why or (tostring(actual) .. " ~= " .. tostring(expected)))
end
local function case(name, test)
    local okay, why = pcall(test)
    assert(okay, name .. ": " .. tostring(why))
    cases = cases + 1
end
local function measure(_, text, size)
    return {
        left = -size * 0.05,
        bottom = -size * 0.2,
        right = #text * size * 0.55,
        top = size * 0.8,
        width = #text * size * 0.55 + size * 0.05,
        height = size,
    }
end
local function rectangle_polygon(b)
    return {
        { x = b.left, y = b.bottom },
        { x = b.right, y = b.bottom },
        { x = b.left, y = b.top },
        { x = b.right, y = b.top },
        { x = b.left, y = b.bottom },
        { x = b.right, y = b.bottom },
        { x = b.left, y = b.top },
        { x = b.right, y = b.top },
    }
end
local function fixture(width, height)
    local f = {
        policy = Policy.new(),
        layout = Layout.new(),
        composition = Composition.new(),
        values = { ["hud.anchor"] = 2, ["hud.anchor_damping_ms"] = 0 },
        measure = measure,
    }
    f.settings = {
        get = function(_, id)
            return f.values[id]
        end,
    }
    f.viewport = { width = width or 1920, height = height or 1080 }
    f.model = {
        known = true,
        identity = 90000,
        generation = 1,
        in_mission = true,
        alive = true,
        hud_visible = true,
        menu_open = false,
        blocked = false,
        aim = { known = true, first_person = false, aiming = false, switching = false },
        reticle = { known = true, x = f.viewport.width / 2, y = f.viewport.height / 2 },
        anchors = { body = { known = true, x = 800, y = 500 }, weapon = { known = true, x = 1000, y = 450 } },
        weapon = { known = true, count = 32, capacity = 45, reserve = 3, reloading = false },
        health = 0.75,
        stamina = 0.5,
        stims = 2,
        throwables = 3,
        cooldowns = {},
        font = { font = "0123456789abcdef", atlas = "1111111111111111", material = "2222222222222222" },
    }
    function f:metrics(count)
        local scale = self.viewport.height / 1080 * (self.values["hud.scale"] or 100) / 100
        local edge, gap = 22 * scale, 5 * scale
        return {
            ready = true,
            count = count or 4,
            root = self.model.identity,
            source_revision = "strip/1",
            edge = edge,
            gap = gap,
            width = (count or 4) * edge + math.max(0, (count or 4) - 1) * gap,
            height = edge,
        }
    end
    function f:set_sight(b)
        self.model.aim.first_person = true
        self.model.follow_token = self.model.follow_token or "current-actor-and-weapon"
        self.model.anchor_context, self.model.anchor_camera = 81000, 80000
        self.model.sight_clearance = {
            known = true,
            identity = self.model.identity,
            generation = self.model.generation,
            context = 81000,
            camera = 80000,
            follow_token = self.model.follow_token,
            source = "weapon_bounds",
            bounds = b or { left = 700, right = 1200, bottom = 490, top = 590 },
        }
        self.model.sight_clearance.unit_count = 1
        self.model.sight_clearance.polygons = { rectangle_polygon(self.model.sight_clearance.bounds) }
        return self.model.sight_clearance
    end
    function f:set_polygons(polygons)
        local b = { left = math.huge, right = -math.huge, bottom = math.huge, top = -math.huge }
        for _, polygon in ipairs(polygons) do
            for _, p in ipairs(polygon) do
                b.left, b.right = math.min(b.left, p.x), math.max(b.right, p.x)
                b.bottom, b.top = math.min(b.bottom, p.y), math.max(b.top, p.y)
            end
        end
        local d = self:set_sight(b)
        d.polygons, d.unit_count = polygons, #polygons
        return d
    end
    function f:begin(metrics, inspect, dt)
        self.last_metrics = metrics
        self.view = self.policy:update(self.model, self.settings, 0.016, inspect)
        self.base = self.layout:update(self.view, self.settings, self.viewport, nil, self.measure, nil, metrics)
        local okay, why = self.composition:begin(
            self.base,
            self.model,
            self.view,
            self.settings,
            self.viewport,
            metrics,
            self.measure,
            dt
        )
        check(okay, why)
        return self.composition
    end
    function f:packet(b)
        local scale = self.viewport.height / 1080
        local shelf = self.composition.combat_bounds
        local center = (shelf.left + shelf.right) / 2
        local top = shelf.bottom - 28 * scale
        return {
            valid = true,
            eligible = true,
            identity = self.model.identity,
            generation = self.model.generation,
            has_content = true,
            tile_count = 1,
            sourceRevision = 1,
            revision = 1,
            bounds = b
                or { left = center - 80 * scale, right = center + 80 * scale, bottom = top - 50 * scale, top = top },
            tiles = { { x = center, y = top - 20 * scale } },
            primitives = {
                {
                    key = "timer/1",
                    kind = "text",
                    text = "0:12",
                    size = 12 * scale,
                    x = center - 16 * scale,
                    y = top - 45 * scale,
                    z = 951,
                    tone = "text",
                    alpha = 0.5,
                    width = 0,
                    height = 0,
                },
            },
        }
    end
    function f:assemble()
        local translated = self.layout:update(
            self.view,
            self.settings,
            self.viewport,
            self.composition.anchors,
            self.measure,
            nil,
            self.last_metrics
        )
        return self.composition:assemble(translated)
    end
    return f
end
local function inside(f, geometry)
    check(geometry.bounds.left >= 0 and geometry.bounds.bottom >= 0, "complete lower envelope fits viewport")
    check(
        geometry.bounds.right <= f.viewport.width and geometry.bounds.top <= f.viewport.height,
        "complete upper envelope fits viewport"
    )
end
local function contains_primitives(f, geometry)
    local b = geometry.bounds
    for _, p in ipairs(geometry.primitives) do
        local m = p.kind == "text" and f.measure(f.view.font, p.text, p.size)
            or { left = 0, right = p.width, bottom = 0, top = p.height }
        check(
            p.x + m.left >= b.left - 0.000001
                and p.x + m.right <= b.right + 0.000001
                and p.y + m.bottom >= b.bottom - 0.000001
                and p.y + m.top <= b.top + 0.000001,
            "complete composition bounds include " .. p.key
        )
    end
end
case("normal strip and original cooldowns fit one group", function()
    local f = fixture()
    local c = f:begin(f:metrics())
    check(c.has_strip)
    eq(c:include_cooldowns(f:packet()), true)
    check(c.has_cooldowns)
    local spec = assert(c:weapon_placement())
    eq(spec.root, f.model.identity)
    eq(spec.generation, 1)
    eq(spec.source_revision, "strip/1")
    eq(spec.edge, 22)
    eq(spec.gap, 5)
    eq(spec.opacity, 0.94)
    eq(spec.x, c.anchors.weapon.x + c.strip_bounds.left)
    eq(spec.y, c.anchors.weapon.y + c.strip_bounds.bottom)
    local g, v = f:assemble()
    check(g.visible)
    check(v.visible)
    eq(v.weapon_options, false)
    inside(f, g)
    check(g.bounds.bottom <= c.cooldown_anchor.y + c.cooldown_packet.bounds.bottom)
end)
case("zero strip roles never invent a placement", function()
    local f = fixture()
    local metrics = f:metrics(0)
    metrics.width = 0
    local c = f:begin(metrics)
    eq(c.has_strip, false)
    eq(c:weapon_placement(), nil)
    local g = f:assemble()
    check(g.visible)
    inside(f, g)
end)
case("pending strip leaves existing viewport owner alone", function()
    local f = fixture()
    local metrics = f:metrics()
    metrics.ready = false
    local c = f:begin(metrics)
    eq(c.has_strip, false)
    eq(c:weapon_placement(), nil)
    inside(f, f:assemble())
end)
case("foreign strip root is not joined", function()
    local f = fixture()
    local metrics = f:metrics()
    metrics.root = metrics.root + 1
    local c = f:begin(metrics)
    eq(c.has_strip, false)
    eq(c:weapon_placement(), nil)
end)
case("quiet empty combat still accepts native strip", function()
    local f = fixture()
    f.model.health, f.model.stamina = 1, 1
    f.model.weapon.known = false
    local c = f:begin(f:metrics())
    eq(f.view.eligible, true)
    eq(f.view.visible, false)
    eq(#f.base.primitives, 0)
    check(c.has_strip)
    local g, v = f:assemble()
    check(g.visible)
    check(v.visible)
    eq(#g.primitives, 0)
    check(c:weapon_placement() ~= nil)
    inside(f, g)
end)
case("quiet empty combat accepts original cooldowns alone", function()
    local f = fixture()
    f.model.health, f.model.stamina = 1, 1
    f.model.weapon.known = false
    local c = f:begin()
    eq(f.view.visible, false)
    eq(c:include_cooldowns(f:packet()), true)
    local g, v = f:assemble()
    check(v.visible)
    eq(#g.primitives, 1)
    eq(g.primitives[1].key, "cooldown/timer/1")
    inside(f, g)
end)
case("quiet empty without native content stays hidden", function()
    local f = fixture()
    f.model.health, f.model.stamina = 1, 1
    f.model.weapon.known = false
    f:begin()
    local g, v = f:assemble()
    eq(g.visible, false)
    eq(v.visible, false)
end)
case("inspected ADS at 4K shows known details with coherent scale", function()
    local f = fixture(3840, 2160)
    f.model.aim.aiming = true
    local c = f:begin(f:metrics(), true)
    eq(f.view.profile, "aim")
    check(f.view.details)
    eq(c:include_cooldowns(f:packet()), true)
    local spec = c:weapon_placement()
    eq(spec.edge, 44)
    eq(spec.gap, 10)
    eq(c.cooldown_options.scale, 1.5)
    eq(c.cooldown_options.pixel, 2)
    eq(c.cooldown_options.font, f.model.font)
    eq(c.cooldown_options.measure, measure)
    local g = f:assemble()
    check(f.layout.slots.capacity ~= nil)
    check(f.layout.slots.reserve ~= nil)
    inside(f, g)
end)
case("first person remains pinned under Body choice", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    f.model.aim.first_person = true
    local c = f:begin(f:metrics())
    eq(f.view.profile, "first_person")
    eq(c.anchor.source, "reticle")
    eq(c.anchor.x, f.model.reticle.x)
    eq(c.anchor.y, f.model.reticle.y)
    inside(f, f:assemble())
end)
case("Model weapon vitals and central anchors remain distinct", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    local c = f:begin(f:metrics())
    eq(c.anchors.vitals.source, "body")
    eq(c.anchors.vitals.x, 800)
    eq(c.anchors.weapon.source, "body")
    eq(c.anchors.weapon.x, 800, "hip ammo follows the proven player head")
    eq(c.anchor.source, "reticle")
    f.model.aim.aiming = true
    c = f:begin(f:metrics())
    eq(c.anchors.weapon.source, "weapon")
    eq(c.anchors.weapon.x, 1000)
    eq(c.anchors.vitals.x, 800)
    eq(c.anchor.x, 960)
    inside(f, f:assemble())
end)
case("Beside retains reticle-relative clearance", function()
    local f = fixture()
    f.values["hud.anchor"] = 3
    local c = f:begin(f:metrics())
    eq(c.anchor.source, "reticle")
    eq(c.anchor.x, f.model.reticle.x)
    eq(c.anchors.weapon.source, "beside")
    eq(c.anchors.weapon.x, f.model.reticle.x + 120)
    eq(c.anchors.vitals.source, "beside")
    eq(c:include_cooldowns(f:packet()), true)
    inside(f, f:assemble())
end)
case("user scale and additional ADS offsets compose once", function()
    local f = fixture()
    f.model.aim.aiming = true
    f.values["hud.scale"], f.values["hud.offset_x"], f.values["hud.offset_y"] = 125, 20, 30
    f.values["hud.ads_offset_x"], f.values["hud.ads_offset_y"] = 10, 5
    local c = f:begin(f:metrics(), true)
    eq(c.anchor.x, 990)
    eq(c.anchor.y, 505)
    eq(c:weapon_placement().edge, 27.5)
    inside(f, f:assemble())
end)
case("dense cooldown fallback retains strip and combat", function()
    local f = fixture()
    local c = f:begin(f:metrics())
    local x, y = c.anchor.x, c.anchor.y
    eq(c:include_cooldowns(f:packet({ left = -1500, right = 1500, bottom = -300, top = -170 })), false)
    eq(c.has_cooldowns, false)
    check(c.has_strip)
    eq(c.anchor.x, x)
    eq(c.anchor.y, y)
    eq(c.cooldown_packet, nil)
    check(type(c.cooldown_reason) == "string")
    local g = f:assemble()
    eq(#g.primitives, #f.base.primitives)
    inside(f, g)
end)
case("fit requiring more than 8 pixels never drags combat HUD", function()
    local f = fixture()
    local c = f:begin(f:metrics())
    local y = c.anchor.y
    eq(c:include_cooldowns(f:packet({ left = -80, right = 80, bottom = -550, top = -170 })), false)
    eq(c.cooldown_reason, "presenter requires moving combat HUD")
    eq(c.anchor.y, y)
    check(c.has_strip)
end)
case("small permitted adjustment still clamps complete envelope", function()
    local f = fixture()
    local c = f:begin(f:metrics())
    local y = c.cooldown_anchor.y
    eq(c:include_cooldowns(f:packet({ left = -80, right = 80, bottom = -542, top = -170 })), true)
    eq(c.cooldown_anchor.y - y, 7)
    eq(c.anchor.y, 540, "central cues do not move with cooldown clamp")
    inside(f, f:assemble())
end)
case("reticle exclusion rejects only offending presenter", function()
    local f = fixture()
    local c = f:begin(f:metrics())
    eq(c:include_cooldowns(f:packet({ left = -20, right = 20, bottom = -10, top = 10 })), false)
    eq(c.cooldown_reason, "presenter overlaps reticle clearance")
    check(c.has_strip)
    inside(f, f:assemble())
end)
case("edge anchors keep all joined content in viewport", function()
    for _, position in ipairs({ { 5, 540 }, { 1915, 540 }, { 960, 5 }, { 960, 1075 } }) do
        local f = fixture()
        f.model.reticle.x, f.model.reticle.y = position[1], position[2]
        local c = f:begin(f:metrics())
        c:include_cooldowns(f:packet())
        inside(f, f:assemble())
        if not c.has_strip then
            eq(c:weapon_placement(), nil)
        end
    end
end)
case("stale cooldown generation is refused", function()
    local f = fixture()
    local c = f:begin(f:metrics())
    local packet = f:packet()
    packet.generation = 0
    eq(c:include_cooldowns(packet), false)
    eq(c.has_cooldowns, false)
    check(c.has_strip)
end)
case("foreign cooldown identity is refused", function()
    local f = fixture()
    local c = f:begin(f:metrics())
    local packet = f:packet()
    packet.identity = packet.identity + 1
    eq(c:include_cooldowns(packet), false)
    eq(c.has_cooldowns, false)
end)
case("empty native packet contributes no phantom geometry", function()
    local f = fixture()
    local c = f:begin()
    local packet = f:packet()
    packet.has_content = false
    eq(c:include_cooldowns(packet), true)
    eq(c.has_cooldowns, false)
    eq(c.cooldown_packet, nil)
    local g = f:assemble()
    eq(#g.primitives, #f.base.primitives)
end)
case("alpha namespacing and copy keep native packet immutable", function()
    local f = fixture()
    f.values["hud.opacity"] = 60
    local c = f:begin(f:metrics())
    local packet = f:packet()
    packet.primitives[1].key = "ammo"
    local original = packet.primitives[1]
    local ox, oy = original.x, original.y
    eq(c:include_cooldowns(packet), true)
    local g = f:assemble()
    local copy = g.primitives[#g.primitives]
    eq(copy.key, "cooldown/ammo")
    check(copy ~= original)
    eq(copy.x, ox + c.cooldown_anchor.x)
    eq(copy.y, oy + c.cooldown_anchor.y)
    eq(copy.alpha, 0.3)
    eq(original.key, "ammo")
    eq(original.x, ox)
    eq(original.y, oy)
    eq(original.alpha, 0.5)
    local count = #g.primitives
    original.text, original.alpha = "0:11", 0.25
    local next_geometry = f:assemble()
    eq(next_geometry.primitives[count], copy, "owned output slot reused")
    eq(copy.text, "0:11")
    eq(copy.alpha, 0.15)
    eq(original.alpha, 0.25)
end)
case("next frame clears old native content and rejects invalid envelope", function()
    local f = fixture()
    local c = f:begin(f:metrics())
    eq(c:include_cooldowns(f:packet()), true)
    local first = f:assemble()
    local count = #first.primitives
    f.model.generation = 2
    f:begin()
    eq(c.has_cooldowns, false)
    eq(c.has_strip, false)
    local invalid = f:packet()
    invalid.bounds.top = 0 / 0
    eq(c:include_cooldowns(invalid), false)
    local next_geometry = f:assemble()
    check(#next_geometry.primitives < count)
    for _, primitive in ipairs(next_geometry.primitives) do
        check(not primitive.key:find("^cooldown/"))
    end
    inside(f, next_geometry)
end)
case("quiet logical shelves stay fixed across digits vitals and icon counts", function()
    local f = fixture()
    local c = f:begin(f:metrics())
    local left, right, bottom = c.combat_bounds.left, c.combat_bounds.right, c.combat_bounds.bottom
    check(left <= -145)
    eq(right, -53, "logical health shelf reserves the open bracket padding even when Quiet hides it")
    eq(bottom, -100)
    for _, step in ipairs({
        { count = 9, health = 1, stamina = 1, icons = 1 },
        { count = 99, health = 0.25, stamina = 0.3, icons = 2 },
        { count = 9999, health = 0.75, stamina = 1, icons = 4 },
        { count = 0, health = 1, stamina = 1, icons = 0 },
    }) do
        f.model.weapon.count, f.model.health, f.model.stamina = step.count, step.health, step.stamina
        c = f:begin(f:metrics(step.icons))
        eq(c.combat_bounds.left, left)
        eq(c.combat_bounds.right, right)
        eq(c.combat_bounds.bottom, bottom, "cooldown shelf does not follow contextual combat height")
    end
    f.model.weapon.known = false
    f.model.health, f.model.stamina = 1, 1
    -- Let contextual recovery holds finish before measuring empty Quiet.
    for _ = 1, 5 do
        f.policy:update(f.model, f.settings, 0.2)
    end
    c = f:begin(f:metrics(0))
    eq(f.view.visible, false)
    eq(c.combat_bounds.left, left)
    eq(c.combat_bounds.right, right)
    eq(c.combat_bounds.bottom, bottom)
end)
case("ADS logical shelf reservations scale with viewport without digit motion", function()
    local f = fixture(3840, 2160)
    f.model.aim.aiming = true
    f.values["hud.scale"] = 125
    f.values["hud.density"] = 2
    f.values["hud.cooldown_anchor"] = 2
    local c = f:begin(f:metrics())
    local left, right, bottom = c.combat_bounds.left, c.combat_bounds.right, c.combat_bounds.bottom
    check(left <= 60 * 2.5)
    check(right >= 173 * 2.5)
    check(bottom <= -142 * 2.5)
    for _, amount in ipairs({ 1, 32, 9999 }) do
        f.model.weapon.count = amount
        c = f:begin(f:metrics(1))
        eq(c.combat_bounds.left, left)
        eq(c.combat_bounds.right, right)
        eq(c.combat_bounds.bottom, bottom)
        eq(c:include_cooldowns(f:packet()), true)
        inside(f, f:assemble())
    end
end)
case("moving gun and actor translate only their own measured flat groups", function()
    local f = fixture()
    f.values["hud.anchor"], f.values["hud.density"] = 1, 2
    f.model.aim.aiming = true
    f.model.weapon.count, f.model.weapon.reloading = 0, true
    local c = f:begin(f:metrics())
    check(c:include_cooldowns(f:packet()))
    local initial = f:assemble()
    local weapon_group, vitals_group, central_group =
        f.layout.group_bounds.weapon, f.layout.group_bounds.vitals, f.layout.group_bounds.central
    local ammo, health, reserve, reload =
        f.layout.slots.ammo, f.layout.slots.health, f.layout.slots.reserve, f.layout.slots.reload
    eq(ammo.group, "weapon")
    eq(reserve.group, "weapon")
    eq(health.group, "vitals")
    eq(f.layout.slots.stamina.group, "vitals")
    eq(f.layout.slots.stims.group, "vitals")
    eq(f.layout.slots.throwables.group, "vitals")
    eq(reload.group, "weapon")
    check(reload.y + measure(nil, reload.text, reload.size).top < ammo.y, "reload notice sits below ammo")
    check(reserve.y + measure(nil, reserve.text, reserve.size).top < reload.y, "reserve clears reload notice")
    eq(f.layout.slots.ammo_shadow.group, "weapon")
    local ax, ay, hx, hy, rx, ry = ammo.x, ammo.y, health.x, health.y, reload.x, reload.y
    local native = c:weapon_placement()
    local nx, ny = native.x, native.y
    local timer = initial.primitives[#initial.primitives]
    local tx, ty = timer.x, timer.y
    local shelfleft, shelfright, shelfbottom = c.combat_bounds.left, c.combat_bounds.right, c.combat_bounds.bottom
    local localleft, localbottom = weapon_group.left, vitals_group.bottom
    for _, motion in ipairs({ { 25, -14, -35, 18 }, { -44, 29, 22, -31 }, { 0, 0, 0, 0 } }) do
        f.model.anchors.weapon.x, f.model.anchors.weapon.y = 1000 + motion[1], 450 + motion[2]
        f.model.anchors.body.x, f.model.anchors.body.y = 800 + motion[3], 500 + motion[4]
        c = f:begin(f:metrics())
        check(c:include_cooldowns(f:packet()))
        local g = f:assemble()
        eq(f.layout.group_bounds.weapon, weapon_group, "weapon local envelope retained")
        eq(f.layout.group_bounds.vitals, vitals_group, "vitals local envelope retained")
        eq(f.layout.group_bounds.central, central_group, "central local envelope retained")
        eq(weapon_group.left, localleft, "translation cannot mutate local weapon extent")
        eq(vitals_group.bottom, localbottom, "translation cannot mutate local vitals extent")
        eq(ammo.x - ax, motion[1])
        eq(ammo.y - ay, motion[2])
        eq(health.x - hx, motion[3])
        eq(health.y - hy, motion[4])
        eq(reload.x - rx, motion[1], "reload notice follows ammo")
        eq(reload.y - ry, motion[2])
        eq(c:weapon_placement().x - nx, motion[1])
        eq(c:weapon_placement().y - ny, motion[2])
        eq(timer.x - tx, motion[3], "native cooldown labels follow selected vitals group")
        eq(timer.y - ty, motion[4])
        eq(c.combat_bounds.left, shelfleft)
        eq(c.combat_bounds.right, shelfright)
        eq(c.combat_bounds.bottom, shelfbottom)
        eq(c.anchor, c.anchors.central)
        inside(f, g)
    end
end)
case("default model anchoring falls back from gun to body then reticle", function()
    local f = fixture()
    f.values["hud.anchor"] = nil
    f.model.aim.aiming = true
    local c = f:begin()
    eq(c.anchors.weapon.source, "weapon")
    eq(c.anchors.vitals.source, "body")
    f.model.anchors.weapon.known = false
    c = f:begin()
    eq(c.anchors.weapon.source, "body")
    eq(c.anchors.weapon.x, 800)
    eq(c.anchors.vitals.source, "body")
    f.model.anchors.body.known = false
    c = f:begin()
    eq(c.anchors.weapon.source, "reticle")
    eq(c.anchors.vitals.source, "reticle")
    eq(c.anchor.source, "reticle")
    inside(f, f:assemble())
end)
case("unknown body does not detach a known gun or shift central content", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    f.values["hud.density"], f.model.aim.aiming = 2, true
    f.model.anchors.body.clipped = true
    local c = f:begin(f:metrics())
    eq(c.anchors.weapon.x, 1000)
    eq(c.anchors.weapon.source, "weapon")
    eq(c.anchors.vitals.x, 960)
    eq(c.anchors.vitals.source, "reticle")
    eq(c.anchor.x, 960)
    eq(c.anchor.y, 540)
    check(c.has_strip)
    inside(f, f:assemble())
end)
case("stale projected point generation and identity cannot be reused", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    f.model.aim.aiming = true
    f.model.anchors.weapon.generation = 0
    local c = f:begin()
    eq(c.anchors.weapon.source, "body")
    f.model.anchors.body.identity = 90001
    c = f:begin()
    eq(c.anchors.weapon.source, "reticle")
    eq(c.anchors.vitals.source, "reticle")
    f.model.anchors.weapon.generation = nil
    c = f:begin()
    eq(c.anchors.weapon.source, "weapon")
    eq(c.anchors.vitals.source, "reticle")
end)
case("heat and unknown reload state never invalidate a known body", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    f.model.anchors.weapon.known = false
    f.model.weapon.count, f.model.weapon.reloading = nil, nil
    f.model.weapon.ammo_kind, f.model.weapon.heat = "heat", nil
    f.model.aim.switching = nil
    local c = f:begin(f:metrics())
    eq(c.anchors.weapon.source, "body")
    eq(c.anchors.vitals.source, "body")
    eq(c.anchors.weapon.x, 800)
    eq(c.anchors.vitals.y, 500)
    f.model.weapon.reloading, f.model.aim.switching = true, true
    c = f:begin()
    eq(c.anchors.weapon.source, "body")
    eq(c.anchors.vitals.source, "body")
end)
case("first person uses sights for all anchor choices", function()
    for _, choice in ipairs({ 1, 2, 3 }) do
        local f = fixture()
        f.values["hud.anchor"] = choice
        f.model.aim.first_person = true
        local c = f:begin(f:metrics(), true)
        for _, role in ipairs({ "weapon", "vitals", "central" }) do
            eq(c.anchors[role].source, role == "central" and "reticle" or "sights")
            eq(
                c.anchors[role].x,
                role == "central" and 960
                    or (role == "weapon" and c.sight_clearance.bounds.right or c.sight_clearance.bounds.left)
                        - c.inward_edges[role]
            )
            eq(c.anchors[role].y, role == "central" and 540 or 540 - c.primary_centers[role])
        end
        check(c:include_cooldowns(f:packet()))
        inside(f, f:assemble())
    end
end)
case("Quiet ADS deliberately omits native groups without fallback geometry", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    f.model.aim.aiming = true
    local c = f:begin(f:metrics())
    eq(f.view.quiet_aim, true)
    eq(f.view.native_options, false)
    eq(f.view.native_cooldowns, false)
    eq(c.has_strip, false)
    eq(c:weapon_placement(), nil)
    eq(c.cooldown_options.enabled, false)
    eq(c:include_cooldowns(f:packet()), true)
    eq(c.has_cooldowns, false)
    eq(c.cooldown_packet, nil)
    eq(c.strip_reason, nil, "intentional hiding is not a failed placement")
    eq(c.cooldown_reason, nil)
    local g = f:assemble()
    eq(#g.primitives, 2, "only ammo and its shadow remain")
    eq(g.primitives[1].group, "weapon")
    c = f:begin(f:metrics(), true)
    check(c.has_strip)
    check(c:include_cooldowns(f:packet()))
    check(c.has_cooldowns)
    inside(f, f:assemble())
end)
case("absent native visibility flags retain compatibility", function()
    local f = fixture()
    f.view = f.policy:update(f.model, f.settings, 0.016)
    f.view.native_options, f.view.native_cooldowns = nil, nil
    local base = f.layout:update(f.view, f.settings, f.viewport, nil, measure)
    local c = f.composition
    check(c:begin(base, f.model, f.view, f.settings, f.viewport, f:metrics(), measure))
    check(c.has_strip)
    eq(c.cooldown_options.enabled, true)
    check(c:include_cooldowns(f:packet()))
    check(c.has_cooldowns)
end)
case("each model group clamps whole contents without moving its peers", function()
    local f = fixture()
    f.values["hud.anchor"], f.values["hud.density"] = 1, 2
    for _, position in ipairs({ { -200, -100 }, { 2200, 1200 }, { -200, 1200 }, { 2200, -100 } }) do
        f.model.anchors.weapon.x, f.model.anchors.weapon.y = position[1], position[2]
        f.model.anchors.body.x, f.model.anchors.body.y = position[1], position[2]
        local c = f:begin(f:metrics())
        eq(c.anchor.x, 960)
        eq(c.anchor.y, 540)
        local wx, wy, vx, vy = c.anchors.weapon.x, c.anchors.weapon.y, c.anchors.vitals.x, c.anchors.vitals.y
        c:include_cooldowns(f:packet())
        eq(c.anchors.weapon.x, wx)
        eq(c.anchors.weapon.y, wy)
        check(math.abs(c.anchors.vitals.x - vx) <= 8)
        check(math.abs(c.anchors.vitals.y - vy) <= 8)
        inside(f, f:assemble())
    end
end)
case("oversized weapon presenter leaves vitals and central placement available", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    f.values["hud.density"], f.model.aim.aiming = 2, true
    local metrics = f:metrics()
    metrics.width = 3000
    local c = f:begin(metrics)
    eq(c.has_strip, false)
    eq(c:weapon_placement(), nil)
    eq(c.anchors.weapon.x, 1000)
    eq(c.anchors.vitals.x, 800)
    eq(c.anchor.x, 960)
    check(c:include_cooldowns(f:packet()))
    check(c.has_cooldowns)
    inside(f, f:assemble())
end)
case("weapon reticle collision refuses only that native presenter", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    f.values["hud.density"], f.model.aim.aiming = 2, true
    f.model.weapon.capacity, f.model.weapon.reserve = nil, nil
    f.model.anchors.weapon.x, f.model.anchors.weapon.y = 800, 625
    local c = f:begin(f:metrics())
    eq(c.has_strip, false)
    eq(c.strip_reason, "presenter overlaps reticle clearance")
    eq(c.anchors.weapon.x, 800)
    check(c:include_cooldowns(f:packet()))
    check(c.has_cooldowns)
    eq(c.anchors.vitals.x, 800)
    inside(f, f:assemble())
end)
case("role resolver preserves legacy API and rejects invalid role inputs", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    local b = { left = -10, right = 10, bottom = -10, top = 10 }
    f.model.weapon.reloading = nil
    eq(Anchor.resolve(f.model, f.settings, f.viewport, b).source, "reticle")
    eq(Anchor.resolve_role(f.model, f.settings, f.viewport, b, "vitals").source, "body")
    eq(Anchor.resolve_role(f.model, f.settings, f.viewport, b, "unknown"), nil)
    local invalid = { left = -2000, right = 2000, bottom = -10, top = 10 }
    eq(Anchor.resolve_role(f.model, f.settings, f.viewport, invalid, "weapon"), nil)
    f.model.aim.known = false
    eq(Anchor.resolve_role(f.model, f.settings, f.viewport, b, "central"), nil)
end)
case("animated role envelopes clear the reticle without moving peers or vanishing", function()
    local f = fixture()
    f.values["hud.anchor"], f.values["hud.density"] = 1, 2
    f.model.aim.aiming = true
    local c = f:begin(f:metrics())
    local vx, vy, cx, cy = c.anchors.vitals.x, c.anchors.vitals.y, c.anchor.x, c.anchor.y
    -- Projected gun motion puts its complete ammo/capacity/reserve group across
    -- the reticle; only that role may be nudged to the nearest safe edge.
    f.model.anchors.weapon.x, f.model.anchors.weapon.y = 885, 600
    c = f:begin(f:metrics())
    check(c.anchors.weapon.clearance)
    eq(c.anchors.vitals.x, vx)
    eq(c.anchors.vitals.y, vy)
    eq(c.anchor.x, cx)
    eq(c.anchor.y, cy)
    local g = f:assemble()
    check(g.visible)
    check(f.layout.group_bounds.weapon.count > 0)
    local function safe_role(role)
        local b, a = c.group_bounds[role], c.anchors[role]
        check(
            b.right + a.x <= 914 or b.left + a.x >= 1006 or b.top + a.y <= 518 or b.bottom + a.y >= 562,
            role .. " complete group clears reticle"
        )
    end
    safe_role("weapon")
    inside(f, g)
    local wx, wy = c.anchors.weapon.x, c.anchors.weapon.y
    f.model.anchors.body.x, f.model.anchors.body.y = 1060, 595
    c = f:begin(f:metrics())
    check(c.anchors.vitals.clearance)
    eq(c.anchors.weapon.x, wx)
    eq(c.anchors.weapon.y, wy)
    eq(c.anchor.x, cx)
    eq(c.anchor.y, cy)
    safe_role("weapon")
    safe_role("vitals")
    inside(f, f:assemble())
    f.model.anchors.weapon.x, f.model.anchors.weapon.y = 1000, 450
    f.model.anchors.body.x, f.model.anchors.body.y = 800, 500
    c = f:begin(f:metrics())
    eq(c.anchors.weapon.clearance, false)
    eq(c.anchors.vitals.clearance, false)
    eq(c.anchors.weapon.x, 1000)
    eq(c.anchors.vitals.x, 800)
end)
case("empty model groups cannot fail reticle clearance or shift cooldown shelf", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    f.model.weapon.known, f.model.health, f.model.stamina = false, 1, 1
    f.model.anchors.weapon.x, f.model.anchors.weapon.y = 960, 540
    f.model.anchors.body.x, f.model.anchors.body.y = 960, 540
    local c = f:begin()
    eq(f.view.visible, false)
    eq(c.group_bounds.weapon.count, 0)
    eq(c.group_bounds.vitals.count, 0)
    eq(c.anchors.weapon.clearance, false)
    eq(c.anchors.vitals.clearance, false)
    check(c:include_cooldowns(f:packet()))
    local g = f:assemble()
    check(g.visible)
    eq(c.anchor.x, 960)
    eq(c.anchor.y, 540)
    eq(#g.primitives, 1)
    inside(f, g)
end)
case("production attachment owner metadata is complete and current", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    f.model.aim.aiming = true
    local weapon, body = f.model.anchors.weapon, f.model.anchors.body
    for _, p in ipairs({ weapon, body }) do
        p.identity, p.generation, p.context, p.camera, p.actor_id =
            f.model.identity, f.model.generation, 81000, 80000, 7
        p.unit, p.node, p.token = 12, 4, "current-attachment"
    end
    weapon.unit, weapon.node, weapon.token = 21, 8, "current-gun"
    local c = f:begin()
    eq(c.anchors.weapon.source, "weapon")
    eq(c.anchors.vitals.source, "body")
    for _, field in ipairs({ "identity", "generation", "context", "camera", "actor_id", "unit", "node", "token" }) do
        local previous = weapon[field]
        weapon[field] = nil
        c = f:begin()
        eq(c.anchors.weapon.source, "body", "incomplete gun owner falls back: " .. field)
        eq(c.anchors.vitals.source, "body")
        weapon[field] = previous
    end
    for _, mutation in ipairs({
        { "identity", 90001 },
        { "generation", 0 },
        { "context", 1 },
        { "camera", 1 },
        { "unit", 4294967295 },
        { "unit", 0 },
        { "unit", 1.5 },
        { "actor_id", -1 },
        { "node", 4096 },
        { "node", -1 },
        { "token", "" },
    }) do
        local field, value = mutation[1], mutation[2]
        local previous = weapon[field]
        weapon[field] = value
        c = f:begin()
        eq(c.anchors.weapon.source, "body", "invalid gun owner falls back: " .. field)
        eq(c.anchors.vitals.source, "body")
        weapon[field] = previous
    end
    -- Both points claiming the same current frame but different cameras/actors
    -- cannot be composed. Stale gun unit/node changes alone never detach vitals.
    weapon.camera = 80001
    c = f:begin()
    eq(c.anchors.weapon.source, "reticle")
    eq(c.anchors.vitals.source, "reticle")
    weapon.camera, weapon.actor_id = 80000, 8
    c = f:begin()
    eq(c.anchors.weapon.source, "reticle")
    eq(c.anchors.vitals.source, "reticle")
    weapon.actor_id, weapon.context = 7, 81001
    c = f:begin()
    eq(c.anchors.weapon.source, "reticle")
    eq(c.anchors.vitals.source, "reticle")
    weapon.context = 81000
    weapon.actor_id, weapon.unit, weapon.node, weapon.token = 7, 23, 16, "new-gun"
    c = f:begin()
    eq(c.anchors.weapon.source, "weapon")
    eq(c.anchors.vitals.source, "body")
    eq(c.anchors.vitals.x, 800)
end)
case("default cooldown shelf is under health and supplies", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    local c = f:begin(f:metrics())
    eq(c.cooldown_role, "vitals")
    eq(c.cooldown_anchor, c.anchors.vitals)
    eq(c.anchor, c.anchors.central)
    eq((c.combat_bounds.left + c.combat_bounds.right) / 2, -105)
    eq(c.combat_bounds.bottom, -100)
    local packet = f:packet()
    check(packet.bounds.top < f.layout.group_bounds.vitals.bottom)
    check(c:include_cooldowns(packet))
    local g = f:assemble()
    local label = g.primitives[#g.primitives]
    eq(label.group, "vitals")
    eq(label.x, packet.primitives[1].x + c.anchors.vitals.x)
    eq(label.y, packet.primitives[1].y + c.anchors.vitals.y)
    check(g.bounds.bottom <= packet.bounds.bottom + c.cooldown_anchor.y)
    contains_primitives(f, g)
    inside(f, g)
end)
case("cooldowns under ammo reserve the original option strip shelf", function()
    local f = fixture()
    f.values["hud.anchor"], f.values["hud.cooldown_anchor"], f.values["hud.density"] = 1, 2, 2
    local c = f:begin(f:metrics())
    eq(c.cooldown_role, "weapon")
    eq(c.cooldown_anchor, c.anchors.weapon)
    eq((c.combat_bounds.left + c.combat_bounds.right) / 2, 116.5)
    eq(c.combat_bounds.bottom, -142)
    local packet = f:packet()
    check(packet.bounds.top < c.strip_bounds.bottom)
    check(c:include_cooldowns(packet))
    local g = f:assemble()
    local p = c:weapon_placement()
    eq(p.x, c.cooldown_anchor.x + c.strip_bounds.left)
    eq(p.y, c.cooldown_anchor.y + c.strip_bounds.bottom)
    eq(g.primitives[#g.primitives].group, "weapon")
    eq(g.primitives[#g.primitives].x, packet.primitives[1].x + c.cooldown_anchor.x)
    contains_primitives(f, g)
    inside(f, g)
end)
case("both cooldown choices follow only their selected moving model", function()
    for _, choice in ipairs({ 1, 2 }) do
        local f = fixture()
        f.values["hud.anchor"], f.values["hud.cooldown_anchor"] = 1, choice
        f.values["hud.density"], f.model.aim.aiming = 2, true
        local c = f:begin(f:metrics())
        check(c:include_cooldowns(f:packet()))
        local g = f:assemble()
        local label = g.primitives[#g.primitives]
        local lx, ly, cx, cy = label.x, label.y, c.anchor.x, c.anchor.y
        for _, motion in ipairs({ { 13, -7, -27, 18 }, { -32, 12, 44, -21 } }) do
            f.model.anchors.body.x, f.model.anchors.body.y = 800 + motion[1], 500 + motion[2]
            f.model.anchors.weapon.x, f.model.anchors.weapon.y = 1000 + motion[3], 450 + motion[4]
            c = f:begin(f:metrics())
            local packet = f:packet()
            local tx, ty = packet.tiles[1].x, packet.tiles[1].y
            local px, py = packet.primitives[1].x, packet.primitives[1].y
            check(c:include_cooldowns(packet))
            g = f:assemble()
            local offset = choice == 1 and 0 or 2
            eq(label.x - lx, motion[1 + offset])
            eq(label.y - ly, motion[2 + offset])
            near((tx + c.cooldown_anchor.x) - label.x, tx - px, "icon/label relative X is preserved")
            near((ty + c.cooldown_anchor.y) - label.y, ty - py, "icon/label relative Y is preserved")
            eq(c.anchor.x, cx)
            eq(c.anchor.y, cy)
            contains_primitives(f, g)
            inside(f, g)
        end
    end
end)
case("switching health and ammo reuses labels without mutating native packets", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    local label
    for _, choice in ipairs({ 1, 2, 1 }) do
        f.values["hud.cooldown_anchor"] = choice
        local c = f:begin(f:metrics())
        local packet = f:packet()
        local original = packet.primitives[1]
        local x, y, alpha = original.x, original.y, original.alpha
        check(c:include_cooldowns(packet))
        local g = f:assemble()
        local next_label = g.primitives[#g.primitives]
        if label then
            eq(next_label, label, "the same retained label changes groups")
        end
        label = next_label
        eq(label.group, choice == 1 and "vitals" or "weapon")
        eq(c.cooldown_anchor, choice == 1 and c.anchors.vitals or c.anchors.weapon)
        eq(label.x, x + c.cooldown_anchor.x)
        eq(label.y, y + c.cooldown_anchor.y)
        eq(original.x, x)
        eq(original.y, y)
        eq(original.alpha, alpha)
        eq(c.anchor.x, 960)
        eq(c.anchor.y, 540)
        contains_primitives(f, g)
    end
end)
case("both logical shelves stay centered through Quiet emptiness and actual outliers", function()
    for _, choice in ipairs({ 1, 2 }) do
        local f = fixture()
        f.values["hud.cooldown_anchor"] = choice
        local center, bottom = choice == 1 and -105 or 116.5, choice == 1 and -100 or -142
        local c = f:begin(f:metrics())
        local left, right = c.combat_bounds.left, c.combat_bounds.right
        for _, amount in ipairs({ 0, 9, 9999 }) do
            f.model.weapon.count = amount
            f.model.health, f.model.stamina = 1, 1
            for _ = 1, 5 do
                f.policy:update(f.model, f.settings, 0.2)
            end
            c = f:begin(f:metrics(amount == 0 and 0 or 4))
            eq(c.combat_bounds.left, left)
            eq(c.combat_bounds.right, right)
            eq(c.combat_bounds.bottom, bottom)
        end
        f.model.weapon.known = false
        c = f:begin(f:metrics(0))
        eq(f.view.visible, false)
        eq(c.combat_bounds.left, left)
        eq(c.combat_bounds.right, right)
        eq((left + right) / 2, center)
        -- A measured outlier expands the complete shelf without recentering it.
        local role = choice == 1 and "vitals" or "weapon"
        local group = f.base.group_bounds[role]
        group.left, group.right, group.bottom, group.top, group.count = -300, 400, -220, -20, 1
        check(c:begin(f.base, f.model, f.view, f.settings, f.viewport, nil, measure))
        eq((c.combat_bounds.left + c.combat_bounds.right) / 2, center)
        check(c.combat_bounds.left <= -300 and c.combat_bounds.right >= 400)
        eq(c.combat_bounds.bottom, -220)
    end
end)
case("Quiet aiming hides either cooldown choice and inspection restores it", function()
    for _, choice in ipairs({ 1, 2 }) do
        local f = fixture()
        f.values["hud.anchor"], f.values["hud.cooldown_anchor"] = 1, choice
        f.model.aim.aiming = true
        local c = f:begin(f:metrics())
        check(c:include_cooldowns(f:packet()))
        eq(c.has_cooldowns, false)
        eq(c.cooldown_packet, nil)
        eq(c.cooldown_reason, nil)
        eq(c.cooldown_options.enabled, false)
        c = f:begin(f:metrics(), true)
        check(c:include_cooldowns(f:packet()))
        check(c.has_cooldowns)
        eq(c.cooldown_options.enabled, true)
        eq(c.cooldown_anchor, choice == 1 and c.anchors.vitals or c.anchors.weapon)
        contains_primitives(f, f:assemble())
    end
end)
case("both choices preserve complete viewport and reticle guards", function()
    for _, choice in ipairs({ 1, 2 }) do
        local f = fixture()
        f.values["hud.anchor"], f.values["hud.cooldown_anchor"] = 1, choice
        local c = f:begin(f:metrics())
        local peer = choice == 1 and c.anchors.weapon or c.anchors.vitals
        local px, py, cx, cy = peer.x, peer.y, c.anchor.x, c.anchor.y
        local selected = c.cooldown_anchor
        local x, y = selected.x, selected.y
        local exclusion = { left = 914 - x, right = 1006 - x, bottom = 518 - y, top = 562 - y }
        eq(c:include_cooldowns(f:packet(exclusion)), false)
        eq(c.cooldown_reason, "presenter overlaps reticle clearance")
        eq(selected.x, x)
        eq(selected.y, y)
        eq(peer.x, px)
        eq(peer.y, py)
        eq(c.anchor.x, cx)
        eq(c.anchor.y, cy)
        c = f:begin(f:metrics())
        eq(c:include_cooldowns(f:packet({ left = -2000, right = 2000, bottom = -300, top = -170 })), false)
        eq(c.cooldown_packet, nil)
        check(c.has_strip)
        contains_primitives(f, f:assemble())
        for _, position in ipairs({ { 5, 5 }, { 1915, 1075 } }) do
            local point = choice == 1 and f.model.anchors.body or f.model.anchors.weapon
            point.x, point.y = position[1], position[2]
            c = f:begin(f:metrics())
            c:include_cooldowns(f:packet())
            inside(f, f:assemble())
        end
    end
end)
case("4K user scale and aim offsets apply once to either cooldown role", function()
    for _, choice in ipairs({ 1, 2 }) do
        local f = fixture(3840, 2160)
        f.values["hud.anchor"], f.values["hud.cooldown_anchor"], f.values["hud.scale"] = 1, choice, 125
        f.values["hud.offset_x"], f.values["hud.offset_y"] = 10, 20
        f.values["hud.ads_offset_x"], f.values["hud.ads_offset_y"] = 5, 7
        f.model.aim.aiming = true
        f.model.anchors.body.x, f.model.anchors.body.y = 1600, 1000
        f.model.anchors.weapon.x, f.model.anchors.weapon.y = 2000, 900
        local c = f:begin(f:metrics(), true)
        local x, y = choice == 1 and 1630 or 2030, choice == 1 and 946 or 846
        eq(c.cooldown_anchor.x, x)
        eq(c.cooldown_anchor.y, y)
        eq((c.combat_bounds.left + c.combat_bounds.right) / 2, (choice == 1 and -105 or 116.5) * 2.5)
        eq(c.combat_bounds.bottom, (choice == 1 and -100 or -142) * 2.5)
        local packet = f:packet()
        check(c:include_cooldowns(packet))
        local g = f:assemble()
        local label = g.primitives[#g.primitives]
        eq(label.x, packet.primitives[1].x + x)
        eq(label.y, packet.primitives[1].y + y)
        contains_primitives(f, g)
        inside(f, g)
    end
end)
case("actual Original cooldown layouts join either role without changing modes", function()
    local Original = project.require("src/cooldown_dock.lua")
    for _, choice in ipairs({ 1, 2 }) do
        for mode = 1, 3 do
            local f = fixture()
            f.values["hud.anchor"], f.values["hud.cooldown_anchor"] = 1, choice
            local c = f:begin(f:metrics())
            eq(c.cooldown_options.ready, f.view.ready, "ready cue uses the selected cooldown group")
            f.view.ready.visible, f.view.ready.text = true, "STRATAGEM READY"
            local native_model = Original.cooldown_dock_model()
            native_model.sample({
                identity = f.model.identity,
                rows = {
                    {
                        entry = 1,
                        kind = 101,
                        timer_kind = "cooldown",
                        timer_seconds = 25,
                        dock_payload = 444,
                        dock_source = 555,
                    },
                    {
                        entry = 2,
                        kind = 102,
                        timer_kind = "incoming",
                        timer_seconds = 4,
                        dock_payload = 444,
                        dock_source = 555,
                    },
                },
            }, 0, true)
            local config = {
                cooldown_display = mode,
                cooldown_timer = 2,
                short_timer_style = 2,
                short_status_placement = 3,
                brief_timer_limit = 10,
                balance_separated_dock = true,
            }
            local layout = Original.cooldown_dock_bracket(native_model, config)
            c.cooldown_options.native_badges = {
                { left = -32, bottom = -32, right = 40, top = 40, icon_width = 64, icon_height = 64 },
                { left = -32, bottom = -32, right = 40, top = 40, icon_width = 64, icon_height = 64 },
            }
            local packet = layout.update(400, c.cooldown_options)
            eq(packet.valid, true, "original packet: " .. tostring(packet.reason))
            eq(packet.tile_count, 2)
            check(packet.bounds.top <= c.combat_bounds.bottom)
            local accepted, problem = c:include_cooldowns(packet)
            check(accepted, "original mode " .. mode .. " choice " .. choice .. ": " .. tostring(problem))
            local g = f:assemble()
            local ready
            for _, p in ipairs(g.primitives) do
                if p.key == "cooldown/ready" then
                    ready = p
                end
            end
            check(ready ~= nil, "ready notice joins every cooldown display mode")
            eq(ready.group, c.cooldown_role, "ready notice follows health/ammo cooldown anchor")
            eq(f.layout.slots.ready, nil, "ready notice is not duplicated at the crosshair")
            eq(config.cooldown_display, mode)
            eq(packet.tile_count, 2, "no mode or native row was dropped to fit")
            eq(g.primitives[#g.primitives].group, c.cooldown_role)
            contains_primitives(f, g)
            for _, tile in ipairs(packet.tiles) do
                check(tile.x + c.cooldown_anchor.x >= g.bounds.left and tile.x + c.cooldown_anchor.x <= g.bounds.right)
                check(tile.y + c.cooldown_anchor.y >= g.bounds.bottom and tile.y + c.cooldown_anchor.y <= g.bounds.top)
            end
            inside(f, g)
        end
    end
end)
case("first-person sights carry both flat columns and selected cooldowns", function()
    for _, choice in ipairs({ 1, 2 }) do
        local f = fixture()
        f.values["hud.anchor"], f.values["hud.cooldown_anchor"] = 1, choice
        f.model.follow_token, f.model.aim.first_person = "current-actor-and-weapon", true
        f.model.anchors.viewmodel = {
            known = true,
            x = 1100,
            y = 500,
            identity = f.model.identity,
            context = 81000,
            generation = f.model.generation,
            camera = 80000,
            actor_id = 7,
            unit = 21,
            node = 8,
            token = "current-fpv",
        }
        local c = f:begin(f:metrics(), true)
        eq(c.anchors.weapon.source, "sights")
        eq(c.anchors.vitals.source, "sights")
        eq(c.anchors.weapon.x, 996)
        eq(c.anchors.vitals.x, 917, "stable open-trim reservation clears the sight aperture")
        eq(c.anchor.x, 960)
        eq(c.anchor.y, 540)
        local packet = f:packet()
        check(c:include_cooldowns(packet))
        local g = f:assemble()
        check(f.layout.slots.health.x + f.layout.slots.health.width < 960, "vitals flank the sights on the left")
        check(f.layout.slots.ammo.x > 960, "ammo flanks the sights on the right")
        near(f.layout.slots.health_track.y + f.layout.slots.health_track.height / 2, 540)
        local ink = measure(f.view.font, f.layout.slots.ammo.text, f.layout.slots.ammo.size)
        near(f.layout.slots.ammo.y + (ink.bottom + ink.top) / 2, 540)
        eq(c.cooldown_anchor, choice == 1 and c.anchors.vitals or c.anchors.weapon)
        local p = g.primitives[#g.primitives]
        eq(p.x, packet.primitives[1].x + c.cooldown_anchor.x)
        eq(p.y, packet.primitives[1].y + c.cooldown_anchor.y)
        eq(p.group, c.cooldown_role)
        contains_primitives(f, g)
        inside(f, g)
        f.model.anchors.viewmodel.known = false
        c = f:begin(f:metrics(), true)
        eq(c.anchors.weapon.source, "sights")
        eq(c.anchors.vitals.source, "sights")
        eq(c.anchors.weapon.x, 996, "unknown projected rig keeps current known sights and fallback padding")
        near(c.anchors.weapon.y + c.primary_centers.weapon, 540)
    end
end)
case("Composition filters current head then gun once before native inclusion", function()
    local f = fixture()
    f.values["hud.anchor"], f.values["hud.anchor_damping_ms"], f.values["hud.density"] = 1, 80, 2
    f.model.follow_token = "same-actor-and-gun"
    local c = f:begin(f:metrics(), true, 0)
    eq(c.anchors.weapon.x, 800)
    eq(c.anchors.weapon.source, "body")
    f.model.aim.aiming = true
    c = f:begin(f:metrics(), true, 0.08)
    near(c.anchors.weapon.x, 800 + 200 * (1 - math.exp(-1)))
    near(c.anchors.weapon.y, 500 - 50 * (1 - math.exp(-1)))
    eq(c.anchors.weapon.source, "weapon")
    local x, y = c.motion.roles.weapon.output.x, c.motion.roles.weapon.output.y
    check(c:include_cooldowns(f:packet()))
    f:assemble()
    f:assemble()
    eq(c.motion.roles.weapon.output.x, x, "native/include and second layout do not filter again")
    eq(c.motion.roles.weapon.output.y, y)
    eq(c.anchor.x, 960)
    eq(c.anchor.y, 540)
    eq(c:weapon_placement().x, c.anchors.weapon.x + c.strip_bounds.left)
end)
case("raw motion is damped before complete viewport clamping", function()
    local f = fixture()
    f.values["hud.anchor"], f.values["hud.anchor_damping_ms"] = 1, 80
    f.model.follow_token = "same-actor-and-gun"
    f:begin(nil, false, 0)
    f.model.anchors.body.x = 4000
    local c = f:begin(nil, false, 0.08)
    local filtered = 800 + (4000 - 800) * (1 - math.exp(-1))
    near(c.motion.roles.weapon.output.x, filtered + c.inward_edges.weapon)
    check(filtered > c.anchors.weapon.x)
    near(c.anchors.weapon.x, f.viewport.width - 5 - f.base.group_bounds.weapon.right)
    local g = f:assemble()
    contains_primitives(f, g)
    inside(f, g)
end)
case("hidden Quiet vitals track current motion before an urgent reveal", function()
    local f = fixture()
    f.values["hud.anchor"], f.values["hud.anchor_damping_ms"] = 1, 80
    f.model.follow_token, f.model.aim.aiming = "same-actor-and-gun", true
    f.model.health, f.model.stamina = 1, 1
    local c = f:begin(nil, false, 0)
    eq(f.view.health.visible, false)
    eq(c.group_bounds.vitals.count, 0)
    eq(c.anchors.vitals.x, 800)
    f.model.anchors.body.x = 1000
    c = f:begin(nil, false, 0.08)
    local previous = 800 + 200 * (1 - math.exp(-1))
    near(c.anchors.vitals.x, previous)
    eq(f.view.health.visible, false)
    f.model.health, f.model.stims, f.model.anchors.body.x = 0.2, 0, 1100
    c = f:begin(nil, false, 0.08)
    eq(f.view.health.visible, true)
    eq(f.view.stims.visible, true)
    near(c.anchors.vitals.x, previous + (1100 - previous) * (1 - math.exp(-1)))
    local g = f:assemble()
    eq(f.layout.slots.health.x, c.anchors.vitals.x - 145)
    contains_primitives(f, g)
    inside(f, g)
end)
case("fallback reset and invalid composition retire motion history", function()
    local f = fixture()
    f.values["hud.anchor"], f.values["hud.anchor_damping_ms"] = 1, 80
    f.model.follow_token = "same-actor-and-gun"
    local c = f:begin(nil, false, 0)
    f.model.anchors.body.x = 1000
    c = f:begin(nil, false, 0.016)
    check(c.anchors.weapon.x < 1000)
    c:reset_motion()
    f.model.anchors.body.x = 1200
    c = f:begin(nil, false, 0)
    eq(c.anchors.weapon.x, 1200)
    eq(c:begin({ valid = false }, f.model, f.view, f.settings, f.viewport, nil, measure, 0.016), false)
    eq(c.motion.follow_token, nil)
    f.model.anchors.body.x = 1300
    c = f:begin(nil, false, 0)
    eq(c.anchors.weapon.x, 1300)
end)
case("FP aligns current main glyph metrics while supporting rows hang below", function()
    local f = fixture()
    f.values["hud.anchor"], f.values["hud.anchor_damping_ms"] = 1, 80
    f.model.follow_token, f.model.aim.first_person = "same-owner", true
    f.measure = function(font, text, size)
        local m = measure(font, text, size)
        if text == "17" then
            m.bottom, m.top = -0.4 * size, 0.2 * size
        elseif text == "88%" then
            m.bottom, m.top = -0.1 * size, 0.9 * size
        elseif text == "-" then
            m.bottom, m.top = 0.1 * size, 0.2 * size
        end
        m.height = m.top - m.bottom
        return m
    end
    for _, state in ipairs({ "count", "heat", "reload" }) do
        f.model.weapon.ammo_kind, f.model.weapon.heat, f.model.weapon.reloading = nil, nil, false
        f.model.weapon.count, f.model.weapon.reserve = 17, 999999
        if state == "heat" then
            f.model.weapon.ammo_kind, f.model.weapon.heat = "heat", 0.88
        elseif state == "reload" then
            f.model.weapon.reloading = true
        end
        local c = f:begin(f:metrics(), true, 0.016)
        check(c:include_cooldowns(f:packet()))
        local g = f:assemble()
        local ammo, track = f.layout.slots.ammo, f.layout.slots.health_track
        local m = f.measure(f.view.font, ammo.text, ammo.size)
        near(ammo.y + (m.bottom + m.top) / 2, 540, state .. " ink aligns current sights without metric lag")
        near(track.y + track.height / 2, 540)
        eq(ammo.text, state == "heat" and "88%" or state == "reload" and "-" or "17")
        check(f.layout.slots.reserve.y < ammo.y)
        check(c:weapon_placement().y + c.weapon.edge < 540)
        contains_primitives(f, g)
        inside(f, g)
    end
end)
case("hidden FP references ignore stale retained slots and reveal at the sight line", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    f.model.aim.first_person = true
    f:begin(nil, true)
    -- Old retained slots remain allocated, but none are a current primitive in
    -- the next Quiet frame. A virtual measured zero is geometry, never a count.
    f.layout.slots.ammo.y, f.layout.slots.ammo.size, f.layout.slots.ammo.text = -9000, 999, "STALE"
    f.layout.slots.health_track.y, f.layout.slots.health_track.height = -8000, 500
    f.model.weapon.known, f.model.health, f.model.stamina = false, 1, 1
    local c = f:begin()
    eq(f.view.visible, false)
    eq(#f.base.primitives, 0)
    near(c.primary_centers.weapon, -51)
    near(c.primary_centers.vitals, -54.5)
    near(c.anchors.weapon.y + c.primary_centers.weapon, 540)
    near(c.anchors.vitals.y + c.primary_centers.vitals, 540)
    eq(f.view.weapon.text, nil, "virtual reference never fabricates a displayed zero")
    f.model.weapon.known, f.model.weapon.count, f.model.health, f.model.stims = true, 9, 0.2, 0
    c = f:begin()
    local g = f:assemble()
    eq(f.layout.slots.ammo.text, "9")
    local m = f.measure(f.view.font, "9", f.layout.slots.ammo.size)
    near(f.layout.slots.ammo.y + (m.bottom + m.top) / 2, 540)
    near(f.layout.slots.health_track.y + f.layout.slots.health_track.height / 2, 540)
    contains_primitives(f, g)
end)
case("FP sight alignment scales once and selected cooldowns retain complete bounds", function()
    for _, choice in ipairs({ 1, 2, 3 }) do
        for _, side in ipairs({ 1, 2 }) do
            local f = fixture(3840, 2160)
            f.values["hud.anchor"], f.values["hud.cooldown_anchor"], f.values["hud.scale"] = choice, side, 125
            f.values["hud.offset_x"], f.values["hud.offset_y"] = 10, 20
            f.values["hud.ads_offset_x"], f.values["hud.ads_offset_y"] = 5, 7
            f.model.aim.first_person, f.model.aim.aiming = false, true
            f.model.aim.viewmodel_active = true
            f.model.anchors.viewmodel = { known = false, x = 999999, y = -999999 }
            local c = f:begin(f:metrics(), true)
            eq(c.anchors.weapon.source, "sights")
            eq(c.anchors.vitals.source, "sights")
            eq(c.anchors.weapon.x, 2040)
            eq(c.anchors.vitals.x, 1842.5)
            check(c:include_cooldowns(f:packet()))
            local g = f:assemble()
            local ammo, health = f.layout.slots.ammo, f.layout.slots.health_track
            local m = f.measure(f.view.font, ammo.text, ammo.size)
            near(ammo.y + (m.bottom + m.top) / 2, 1026)
            near(health.y + health.height / 2, 1026)
            eq(c.cooldown_anchor, side == 1 and c.anchors.vitals or c.anchors.weapon)
            local label = g.primitives[#g.primitives]
            eq(label.y, c.cooldown_packet.primitives[1].y + c.cooldown_anchor.y)
            contains_primitives(f, g)
            inside(f, g)
        end
    end
end)
case("damped FP entry blends the displayed reference rather than jumping by its lift", function()
    local f = fixture()
    f.values["hud.anchor"], f.values["hud.anchor_damping_ms"] = 1, 80
    f.model.follow_token = "same-actor-and-gun"
    for name, p in pairs(f.model.anchors) do
        p.identity, p.generation, p.context, p.camera = f.model.identity, f.model.generation, 81000, 80000
        p.actor_id, p.unit, p.node, p.token = 7, name == "body" and 12 or 13, 4, name
    end
    f.model.anchors.body.x = 960
    f.model.anchors.viewmodel = {
        known = true,
        x = 1919,
        y = 65,
        identity = f.model.identity,
        context = 81000,
        generation = f.model.generation,
        camera = 80000,
        actor_id = 7,
        unit = 14,
        node = 8,
        token = "current-fpv",
    }
    local c = f:begin(nil, true, 0)
    local initial = c.motion.roles.weapon.output.y
    near(initial, 449)
    f.model.aim.first_person = true
    c = f:begin(nil, true, 0.08)
    local filtered = initial + (540 - initial) * (1 - math.exp(-1))
    near(c.motion.roles.weapon.output.y, filtered)
    local g = f:assemble()
    local ammo = f.layout.slots.ammo
    local m = f.measure(f.view.font, ammo.text, ammo.size)
    near(ammo.y + (m.bottom + m.top) / 2, filtered, "entering FPS has no undamped 51px lift")
    for _ = 1, 30 do
        c = f:begin(nil, true, 0.08)
    end
    g = f:assemble()
    ammo = f.layout.slots.ammo
    near(ammo.y + (m.bottom + m.top) / 2, 540)
    near(f.layout.slots.health_track.y + f.layout.slots.health_track.height / 2, 540)
    contains_primitives(f, g)
    inside(f, g)
end)
case("FP horizontal clearance preserves primary sight height and outward sides", function()
    for _, dx in ipairs({ -100, 100 }) do
        local f = fixture()
        f.values["hud.anchor"], f.values["hud.offset_x"] = 1, dx
        f.model.aim.first_person = true
        f.model.health, f.model.stims = 0.2, 0
        local c = f:begin(nil, false)
        local g = f:assemble()
        local ammo, health = f.layout.slots.ammo, f.layout.slots.health_track
        local m = f.measure(f.view.font, ammo.text, ammo.size)
        near(ammo.y + (m.bottom + m.top) / 2, 540)
        near(health.y + health.height / 2, 540)
        check(health.x + health.width <= 914, "vitals clear outward to the left")
        check(ammo.x + m.left >= 1006, "ammo clears outward to the right")
        eq(c.anchors[dx < 0 and "weapon" or "vitals"].clearance, true)
        contains_primitives(f, g)
        inside(f, g)
    end
end)
local function aperture_clear(f, c)
    local s = c.sight_clearance
    check(c.anchors.vitals.x + c.inward_edges.vitals <= s.bounds.left + 0.000001)
    check(c.anchors.weapon.x + c.inward_edges.weapon >= s.bounds.right - 0.000001)
    local g = f:assemble()
    contains_primitives(f, g)
    inside(f, g)
    return g
end
case("FP adapts measured small large and asymmetric geometry with physical padding", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    for _, box in ipairs({ { 920, 1000, 864, 1056 }, { 700, 1200, 682, 1218 }, { 500, 1050, 482, 1068 } }) do
        local source = f:set_sight({ left = box[1], right = box[2], bottom = 490, top = 590 })
        local c = f:begin(f:metrics(), true)
        eq(c.sight_clearance.known, true)
        eq(c.sight_clearance.source, "weapon_bounds")
        eq(c.sight_clearance.status, "weapon_bounds")
        eq(c.sight_clearance.bounds.left, box[3])
        eq(c.sight_clearance.bounds.right, box[4])
        eq(source.bounds.left, box[1], "input native geometry is immutable")
        check(c.sight_clearance.raw_bounds ~= source.bounds)
        eq(c.sight_clearance.raw_bounds.right, box[2])
        check(c:include_cooldowns(f:packet()))
        aperture_clear(f, c)
    end
end)
case("FP rejects stale malformed unsupported and unreasonable clearance", function()
    local mutations = {
        function(f, d)
            d.identity = f.model.identity + 1
        end,
        function(f, d)
            d.generation = 0
        end,
        function(f, d)
            d.context = 81001
        end,
        function(f, d)
            d.camera = 80001
        end,
        function(f, d)
            d.follow_token = "foreign-weapon"
        end,
        function(f, d)
            d.known = false
        end,
        function(f, d)
            d.source = "guessed-zoom"
        end,
        function(f, d)
            d.bounds.left = 0 / 0
        end,
        function(f, d)
            d.bounds.left, d.bounds.right = 1200, 700
        end,
        function(f, d)
            d.bounds.top = d.bounds.bottom
        end,
        function(f, d)
            d.bounds.left, d.bounds.right = 2000, 2200
        end,
        function(f, d)
            d.bounds.left = -100000
        end,
        function(f, d)
            d.bounds.bottom, d.bounds.top = 100, 200
        end,
        function(f, d)
            f.model.anchor_context = nil
        end,
        function(f, d)
            f.model.anchor_camera = nil
        end,
        function(f, d)
            f.model.anchors.viewmodel = { known = true, context = 99999, camera = 80000 }
        end,
    }
    for _, mutate in ipairs(mutations) do
        local f = fixture()
        local d = f:set_sight()
        mutate(f, d)
        local c = f:begin(nil, true)
        eq(c.sight_clearance.known, false)
        eq(c.sight_clearance.source, "fallback")
        check(c.sight_clearance.status:find("fallback:", 1, true) == 1)
        eq(c.sight_clearance.bounds.left, 864)
        eq(c.sight_clearance.bounds.right, 1056)
        aperture_clear(f, c)
    end
end)
case("FP accepts complete projected boxes crossing the bottom viewport edge", function()
    local f = fixture()
    f:set_sight({ left = 650, right = 1180, bottom = -500, top = 600 })
    local c = f:begin(nil, true)
    eq(c.sight_clearance.known, true)
    eq(c.sight_clearance.bounds.left, 632)
    eq(c.sight_clearance.bounds.right, 1198)
    eq(c.sight_clearance.raw_bounds.bottom, -500)
    aperture_clear(f, c)
end)
case("FP uses an explicit fallback when conservative boxes leave no viewport columns", function()
    local f = fixture()
    f:set_sight({ left = -100, right = 1500, bottom = -500, top = 600 })
    local c = f:begin(nil, true)
    eq(c.sight_clearance.known, false)
    eq(c.sight_clearance.status, "fallback: geometry leaves no column room")
    eq(c.sight_clearance.bounds.left, 864)
    eq(c.sight_clearance.bounds.right, 1056)
    aperture_clear(f, c)
    f.model.reticle.x = 10
    c = f:begin(nil, true)
    eq(c.sight_clearance.status, "fallback: aperture cannot fit viewport")
    inside(f, f:assemble())
end)
case("FP geometry is physical while padding and hidden minimum rails scale", function()
    local f = fixture(3840, 2160)
    f.values["hud.scale"], f.values["hud.anchor"] = 125, 1
    f:set_sight({ left = 1450, right = 2350, bottom = -200, top = 1200 })
    local c = f:begin(nil, true)
    eq(c.sight_clearance.known, true)
    eq(c.sight_clearance.bounds.left, 1405, "1450 physical minus18*2.5, never1450*2.5")
    eq(c.sight_clearance.bounds.right, 2395)
    aperture_clear(f, c)
    f.model.sight_clearance = nil
    c = f:begin(nil, true)
    eq(c.sight_clearance.bounds.left, 1680)
    eq(c.sight_clearance.bounds.right, 2160)
    aperture_clear(f, c)
end)
case("FP actual geometry stays fixed while configured root offsets apply once", function()
    local f = fixture()
    f.values["hud.offset_x"], f.values["hud.ads_offset_x"] = 100, 20
    f.values["hud.offset_y"], f.values["hud.ads_offset_y"] = 5, 10
    f:set_sight({ left = 500, right = 1400, bottom = 480, top = 620 })
    local c = f:begin(nil, true)
    eq(c.sight_clearance.bounds.left, 482)
    eq(c.sight_clearance.bounds.right, 1418)
    eq(c.sight_clearance.bounds.bottom, 503)
    eq(c.sight_clearance.bounds.top, 547)
    aperture_clear(f, c)
    near(c.anchors.weapon.y + c.primary_centers.weapon, 525)
    near(c.anchors.vitals.y + c.primary_centers.vitals, 525)
end)
case("FP expands immediately for geometry and damps the inward return from displayed rails", function()
    local f = fixture()
    f.values["hud.anchor"], f.values["hud.anchor_damping_ms"] = 1, 80
    local d = f:set_sight({ left = 920, right = 1000, bottom = 490, top = 590 })
    local c = f:begin(nil, true, 0)
    local left, right = c.anchors.vitals.x + c.inward_edges.vitals, c.anchors.weapon.x + c.inward_edges.weapon
    eq(left, 864)
    eq(right, 1056)
    d.bounds.left, d.bounds.right = 600, 1300
    d.polygons[1] = rectangle_polygon(d.bounds)
    c = f:begin(nil, true, 0.001)
    aperture_clear(f, c)
    local wide_left, wide_right = c.anchors.vitals.x + c.inward_edges.vitals, c.anchors.weapon.x + c.inward_edges.weapon
    eq(wide_left, 582)
    eq(wide_right, 1318)
    d.bounds.left, d.bounds.right = 920, 1000
    d.polygons[1] = rectangle_polygon(d.bounds)
    c = f:begin(nil, true, 0.016)
    local alpha = 1 - math.exp(-0.016 / 0.08)
    near(c.anchors.vitals.x + c.inward_edges.vitals, wide_left + (left - wide_left) * alpha)
    near(c.anchors.weapon.x + c.inward_edges.weapon, wide_right + (right - wide_right) * alpha)
    aperture_clear(f, c)
end)
case("FP quiet reveal and native presenters keep their selected adaptive anchor", function()
    for _, side in ipairs({ 1, 2 }) do
        local f = fixture()
        f.values["hud.cooldown_anchor"] = side
        f:set_sight()
        f.model.health, f.model.stamina = 1, 1
        local c = f:begin(nil, false)
        eq(f.view.health.visible, false)
        local x = c.anchors.vitals.x
        f.model.health, f.model.stims = 0.2, 0
        c = f:begin(f:metrics(), true)
        eq(c.anchors.vitals.x, x, "revealed health keeps its reserved inward edge")
        check(c:include_cooldowns(f:packet()))
        eq(c.cooldown_anchor, side == 1 and c.anchors.vitals or c.anchors.weapon)
        local g = aperture_clear(f, c)
        local label = g.primitives[#g.primitives]
        eq(label.x, c.cooldown_packet.primitives[1].x + c.cooldown_anchor.x)
        eq(c:weapon_placement().x, c.anchors.weapon.x + c.strip_bounds.left)
    end
end)
case("FP native component cannot drag a primary rail through its aperture", function()
    local f = fixture()
    f:set_sight()
    local c = f:begin(f:metrics(), true)
    local x, y = c.cooldown_anchor.x, c.cooldown_anchor.y
    local b = {
        left = c.sight_clearance.bounds.left - x + 1,
        right = c.sight_clearance.bounds.right - x - 1,
        bottom = c.sight_clearance.bounds.bottom - y + 1,
        top = c.sight_clearance.bounds.top - y - 1,
    }
    eq(c:include_cooldowns(f:packet(b)), false)
    check(
        c.cooldown_reason == "presenter overlaps sight aperture"
            or c.cooldown_reason == "presenter overlaps reticle clearance"
    )
    eq(c.cooldown_anchor.x, x)
    eq(c.cooldown_anchor.y, y)
    check(c.has_strip)
    aperture_clear(f, c)
end)
case("hip and third-person ignore FP geometry and keep current bone anchors", function()
    local f = fixture()
    f.values["hud.anchor"] = 1
    f:set_sight()
    f.model.aim.first_person = false
    local c = f:begin(nil, true)
    eq(c.sight_clearance.active, false)
    eq(c.anchors.weapon.x, 800)
    eq(c.anchors.vitals.x, 800)
    f.model.aim.aiming = true
    c = f:begin(nil, true)
    eq(c.sight_clearance.active, false)
    eq(c.anchors.weapon.x, 1000)
    eq(c.anchors.vitals.x, 800)
    c:reset_motion()
    eq(c.sight_clearance.source, "inactive")
end)
case("FP measured inward glyph bearings expand rails without clipping values", function()
    local f = fixture()
    f.measure = function(font, text, size)
        local m = measure(font, text, size)
        if text == "32" then
            m.left = -0.7 * size
        end
        return m
    end
    f:set_sight()
    local c = f:begin(nil, true)
    check(c.inward_edges.weapon < 60, "actual negative bearing replaces the virtual inward minimum")
    local g = aperture_clear(f, c)
    local ammo = f.layout.slots.ammo
    local ink = f.measure(f.view.font, ammo.text, ammo.size)
    check(ammo.x + ink.left >= c.sight_clearance.bounds.right)
    near(ammo.y + (ink.bottom + ink.top) / 2, 540)
    contains_primitives(f, g)
end)
case("convex sight-band clipping ignores the broad lower stock", function()
    local f = fixture()
    local polygon = {
        { x = 100, y = -500 },
        { x = 1800, y = -500 },
        { x = 900, y = 600 },
        { x = 1000, y = 600 },
        { x = 200, y = -400 },
        { x = 1700, y = -400 },
        { x = 910, y = 590 },
        { x = 990, y = 590 },
    }
    local d = f:set_polygons({ polygon })
    local c = f:begin(f:metrics(), true)
    eq(c.sight_clearance.known, true, "wide stock bbox no longer forces the proportional fallback")
    eq(c.sight_clearance.raw_bounds.left, 100)
    eq(c.sight_clearance.raw_bounds.right, 1800)
    local left, right = 100 + 800 * 1018 / 1100, 1800 - 800 * 1018 / 1100
    near(c.sight_clearance.band_left, left)
    near(c.sight_clearance.band_right, right)
    near(c.sight_clearance.bounds.left, left - 18)
    near(c.sight_clearance.bounds.right, right + 18)
    eq(c.sight_clearance.units_in_band, 1)
    eq(d.polygons[1], polygon)
    eq(polygon[1].x, 100)
    check(c:include_cooldowns(f:packet()))
    aperture_clear(f, c)
end)
case("per-unit hulls ignore vertical and horizontal misses before union", function()
    local f = fixture()
    local polygons = {
        rectangle_polygon({ left = 700, right = 800, bottom = 500, top = 580 }),
        rectangle_polygon({ left = -500, right = 1800, bottom = -900, top = 400 }),
        rectangle_polygon({ left = 1100, right = 1200, bottom = 520, top = 560 }),
        rectangle_polygon({ left = -900, right = -100, bottom = 500, top = 580 }),
        rectangle_polygon({ left = 2000, right = 2300, bottom = 500, top = 580 }),
    }
    f:set_polygons(polygons)
    local c = f:begin(nil, true)
    eq(c.sight_clearance.known, true)
    eq(c.sight_clearance.units_in_band, 2)
    eq(c.sight_clearance.band_left, 700)
    eq(c.sight_clearance.band_right, 1200)
    eq(c.sight_clearance.bounds.left, 682)
    eq(c.sight_clearance.bounds.right, 1218)
    aperture_clear(f, c)
    f:set_polygons({ polygons[2], rectangle_polygon({ left = 100, right = 1800, bottom = 650, top = 900 }) })
    c = f:begin(nil, true)
    eq(c.sight_clearance.known, false)
    eq(c.sight_clearance.units_in_band, 0)
    eq(c.sight_clearance.status, "fallback: projected hull misses sight band")
end)
case("hulls are order independent and retain scratch without changing corners", function()
    local f = fixture()
    local p = {
        { x = 700, y = 480 },
        { x = 950, y = 470 },
        { x = 1200, y = 500 },
        { x = 1220, y = 560 },
        { x = 1000, y = 610 },
        { x = 760, y = 590 },
        { x = 900, y = 500 },
        { x = 1100, y = 560 },
    }
    local d = f:set_polygons({ p })
    local c = f:begin(nil, true)
    local left, right, sorted, hull =
        c.sight_clearance.band_left, c.sight_clearance.band_right, c.sight_sorted, c.sight_hull
    local reordered = { p[8], p[2], p[6], p[4], p[1], p[7], p[5], p[3] }
    d.polygons[1] = reordered
    c = f:begin(nil, true)
    near(c.sight_clearance.band_left, left)
    near(c.sight_clearance.band_right, right)
    eq(c.sight_sorted, sorted)
    eq(c.sight_hull, hull)
    eq(reordered[1], p[8], "sorting never reorders the producer array")
    eq(p[1].x, 700)
    aperture_clear(f, c)
end)
case("any malformed or clipped unit rejects the complete projected payload", function()
    local mutations = {
        function(d)
            d.polygons = nil
        end,
        function(d)
            d.unit_count = 2
        end,
        function(d)
            d.polygons[1][8] = nil
        end,
        function(d)
            d.polygons[1][2].x = 0 / 0
        end,
        function(d)
            d.polygons[1][3].clipped = true
        end,
        function(d)
            d.polygons[1][4].y = -100000
        end,
        function(d)
            for i = 1, 8 do
                d.polygons[1][i] = { x = 900, y = 540 }
            end
        end,
        function(d)
            for i = 1, 8 do
                d.polygons[1][i] = { x = 900 + i, y = 500 + i }
            end
        end,
        function(d)
            for i = 2, 9 do
                d.polygons[i] = rectangle_polygon(d.bounds)
            end
            d.unit_count = 9
        end,
    }
    for _, mutate in ipairs(mutations) do
        local f = fixture()
        local d = f:set_sight()
        mutate(d)
        local c = f:begin(nil, true)
        eq(c.sight_clearance.known, false)
        eq(c.sight_clearance.source, "fallback")
        eq(c.sight_clearance.bounds.left, 864)
        eq(c.sight_clearance.bounds.right, 1056)
        aperture_clear(f, c)
    end
    local f = fixture()
    local d = f:set_polygons({
        rectangle_polygon({ left = 700, right = 1200, bottom = 500, top = 580 }),
        rectangle_polygon({ left = 200, right = 300, bottom = 100, top = 200 }),
    })
    d.polygons[2][8] = nil
    local c = f:begin(nil, true)
    eq(c.sight_clearance.known, false, "invalid unit below band is not silently dropped")
    local f = fixture()
    local d = f:set_sight()
    d.polygons = {
        rectangle_polygon(d.bounds),
        rectangle_polygon(d.bounds),
        rectangle_polygon(d.bounds),
        rectangle_polygon(d.bounds),
    }
    d.polygons[2], d.unit_count = nil, 4
    eq(#d.polygons, 4, "interior unit hole retains the trailing unit")
    c = f:begin(nil, true)
    eq(c.sight_clearance.known, false, "numeric outer traversal cannot drop units after an interior hole")
    eq(c.sight_clearance.status, "fallback: malformed projected hull")
end)
case("4K configured sight band clips perspective edges without rescaling geometry", function()
    local f = fixture(3840, 2160)
    f.values["hud.scale"], f.values["hud.offset_y"] = 125, 10
    f:set_polygons({
        {
            { x = 200, y = -1000 },
            { x = 3600, y = -1000 },
            { x = 1800, y = 1200 },
            { x = 2000, y = 1200 },
            { x = 400, y = -800 },
            { x = 3400, y = -800 },
            { x = 1820, y = 1180 },
            { x = 1980, y = 1180 },
        },
    })
    local c = f:begin(nil, true)
    local low = 1080 - 20 - 44
    local left, right = 200 + 1600 * (low + 1000) / 2200, 3600 - 1600 * (low + 1000) / 2200
    near(c.sight_clearance.band_left, left)
    near(c.sight_clearance.band_right, right)
    near(c.sight_clearance.bounds.left, math.min(1920 - 240, left - 45))
    near(c.sight_clearance.bounds.right, math.max(1920 + 240, right + 45))
    aperture_clear(f, c)
end)
case("unknown geometry holds only measured relative insets for the current FP owner", function()
    local f = fixture()
    f.values["hud.anchor"], f.values["hud.anchor_damping_ms"] = 1, 80
    local d = f:set_sight({ left = 600, right = 1300, bottom = 490, top = 590 })
    f.model.aim.viewmodel_unit = 12345
    local c = f:begin(nil, true, 0)
    eq(c.held_sight.valid, true)
    d.known = false
    f.model.reticle.x = 980
    c = f:begin(nil, true, 0.016)
    eq(c.sight_clearance.known, false)
    eq(c.sight_clearance.held, true)
    eq(c.sight_clearance.source, "fallback")
    eq(c.sight_clearance.status, "fallback: held measured spacing")
    eq(c.sight_clearance.bounds.left, 602)
    eq(c.sight_clearance.bounds.right, 1338)
    aperture_clear(f, c)
end)
case("unknown geometry cannot continue a pending inward shrink", function()
    local f = fixture()
    f.values["hud.anchor"], f.values["hud.anchor_damping_ms"] = 1, 80
    f.model.aim.viewmodel_unit = 12345
    f:set_sight({ left = 600, right = 1300, bottom = 490, top = 590 })
    local c = f:begin(nil, true, 0)
    local d = f:set_sight({ left = 920, right = 1000, bottom = 490, top = 590 })
    c = f:begin(nil, true, 0.016)
    local left, right = c.filtered.vitals.x, c.filtered.weapon.x
    check(left > 582 and left < 864)
    check(right < 1318 and right > 1056)
    d.known = false
    c = f:begin(nil, true, 0.1)
    eq(c.sight_clearance.held, true)
    near(c.filtered.vitals.x, left)
    near(c.filtered.weapon.x, right)
    aperture_clear(f, c)
end)
case("held spacing retires on every FP owner viewport scale and manual offset change", function()
    for _, change in ipairs({
        "identity",
        "generation",
        "context",
        "camera",
        "token",
        "rig",
        "viewport",
        "scale",
        "ox",
        "oy",
        "ax",
        "ay",
        "reset",
        "leave",
    }) do
        local f = fixture()
        local d = f:set_sight({ left = 600, right = 1300, bottom = 490, top = 590 })
        f.model.aim.viewmodel_unit = 12345
        local c = f:begin(nil, true)
        eq(c.held_sight.valid, true)
        d.known = false
        if change == "identity" then
            f.model.identity = f.model.identity + 1
        elseif change == "generation" then
            f.model.generation = f.model.generation + 1
        elseif change == "context" then
            f.model.anchor_context = 81001
        elseif change == "camera" then
            f.model.anchor_camera = 80001
        elseif change == "token" then
            f.model.follow_token = "another-gun"
        elseif change == "rig" then
            f.model.aim.viewmodel_unit = 12346
        elseif change == "viewport" then
            f.viewport.width = 2000
        elseif change == "scale" then
            f.values["hud.scale"] = 105
        elseif change == "ox" then
            f.values["hud.offset_x"] = 1
        elseif change == "oy" then
            f.values["hud.offset_y"] = 1
        elseif change == "ax" then
            f.values["hud.ads_offset_x"] = 1
        elseif change == "ay" then
            f.values["hud.ads_offset_y"] = 1
        elseif change == "reset" then
            c:reset_motion()
        elseif change == "leave" then
            f.model.aim.first_person = false
        end
        c = f:begin(nil, true)
        eq(c.sight_clearance.held, false, change)
        eq(c.held_sight.valid, false, change)
    end
end)
case("a foreign known payload invalidates held spacing before later unknown frames", function()
    local f = fixture()
    local d = f:set_sight({ left = 600, right = 1300, bottom = 490, top = 590 })
    f.model.aim.viewmodel_unit = 12345
    local c = f:begin(nil, true)
    eq(c.held_sight.valid, true)
    d.context = 81001
    c = f:begin(nil, true)
    eq(c.sight_clearance.held, false)
    eq(c.held_sight.valid, false)
    d.known = false
    c = f:begin(nil, true)
    eq(c.sight_clearance.held, false)
    eq(c.sight_clearance.status, "fallback: geometry unavailable")
end)
case("original controls sit below ammo while complete heat and support cells remain separate", function()
    for _, height in ipairs({ 1080, 2160 }) do
        for _, display in ipairs({ 0, 1, 2, 3 }) do
            for _, vertical in ipairs({ false, true }) do
                for _, count in ipairs({ 1, 4 }) do
                    local f = fixture(height / 1080 * 1920, height)
                    f.values["hud.density"], f.values["hud.scale"] = 2, 125
                    f.model.aim.first_person = true
                    if display > 0 then
                        f.model.weapon = {
                            known = true,
                            heat_weapon = true,
                            ammo_kind = "heat",
                            heat = 0.6,
                            reserve = 3,
                            reloading = false,
                        }
                        f.values["hud.heat_display"], f.values["hud.heat_bar_vertical"] = display, vertical
                    end
                    local c = f:begin(f:metrics(count), true)
                    check(c.has_strip)
                    local b, slots, scale = c.strip_bounds, f.layout.slots, f.layout.scale
                    if display == 0 or display == 1 or display == 3 then
                        local ammo = slots.ammo
                        local expected = ammo.local_y + ammo.ink_bottom - 8 * scale
                        if display == 3 and not vertical then
                            expected = math.min(expected, slots.heat_track.local_y - f.layout.pixel - 8 * scale)
                        end
                        near(b.top, expected, "controls follow the current primary instead of a distant shelf")
                    end
                    if display == 3 and vertical then
                        check(
                            slots.heat_track.local_x >= b.right + 8 * scale,
                            "vertical Hybrid meter clears all original controls"
                        )
                    elseif display == 2 then
                        check(b.top < slots.heat_track.local_y, "bar-only controls clear the entire meter")
                    end
                    for _, p in ipairs(f.layout.primitives) do
                        if p.key == "reserve" then
                            check(
                                p.local_y + p.ink_top <= b.bottom - 6 * scale,
                                "reserve remains below the complete original controls"
                            )
                        end
                    end
                    local geometry = f:assemble()
                    contains_primitives(f, geometry)
                    inside(f, geometry)
                    near(c:weapon_placement().y, c.anchors.weapon.y + b.bottom)
                end
            end
        end
    end
end)
print("composition: " .. cases .. " cases / " .. checks .. " checks passed")
