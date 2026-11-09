-- Actual pure Anchor/Policy/Layout/Composition. No provider, native API or game.
local Support = assert(loadfile("tests/support.lua"))()
local mod = Support.project()
local Anchor = mod.require("hud/anchor.lua")
local Policy = mod.require("hud/policy.lua")
local Layout = mod.require("hud/bracket_layout.lua")
local Composition = mod.require("hud/composition.lua")
local checks, cases = 0, 0
local function eq(actual, expected, why)
    checks = checks + 1
    assert(actual == expected, (why or "different") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, why)
    checks = checks + 1
    assert(
        math.abs(actual - expected) < 1e-6,
        (why or "different") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected)
    )
end
local function case(name, run)
    local okay, why = pcall(run)
    assert(okay, name .. ": " .. tostring(why))
    cases = cases + 1
end
local function measure(_, text, size)
    return {
        left = 0,
        bottom = 0,
        right = #text * size * 0.5,
        top = size,
        width = #text * size * 0.5,
        height = size,
    }
end
local function fixture()
    local f = {
        policy = Policy.new(),
        layout = Layout.new(),
        composition = Composition.new(),
        viewport = { width = 1920, height = 1080 },
        values = { ["hud.anchor"] = 1, ["hud.anchor_damping_ms"] = 0, ["hud.density"] = 2, ["hud.tfp_vitals_bone"] = 2 },
        measure = measure,
    }
    f.settings = {
        get = function(_, key)
            return f.values[key]
        end,
    }
    f.model = {
        known = true,
        identity = 90000,
        generation = 3,
        anchor_context = 81000,
        anchor_camera = 82000,
        follow_token = "actor/current-weapon/camera",
        in_mission = true,
        alive = true,
        hud_visible = true,
        menu_open = false,
        blocked = false,
        health = 0.75,
        stamina = 0.5,
        stims = 2,
        throwables = 3,
        font = {},
        cooldowns = {},
        aim = {
            known = true,
            first_person = false,
            aiming = false,
            switching = false,
            true_first_person = true,
            true_first_person_token = "provider/1",
            viewmodel_active = true,
            viewmodel_unit = 42,
            weapon_unit = 84,
        },
        reticle = { known = true, x = 960, y = 540 },
        weapon = { known = true, entity = 8, count = 32, reserve = 4, reloading = false },
        anchors = {
            body = { known = true, x = 700, y = 400 },
            weapon = { known = true, x = 1000, y = 450 },
            tfp_vitals = {
                known = true,
                x = 740,
                y = 460,
                identity = 90000,
                generation = 3,
                context = 81000,
                camera = 82000,
                unit = 42,
                unit_domain = "fps",
                actor_id = 7,
                entity = 8,
                node = 12,
                token = "fps/current-unit/left-hand",
            },
            viewmodel = {
                known = true,
                x = 900,
                y = 500,
                identity = 90000,
                generation = 3,
                context = 81000,
                camera = 82000,
                unit = 42,
                unit_domain = "fps",
                actor_id = 7,
                entity = 8,
                node = 8,
                token = "fps/current-unit/current-node",
            },
        },
    }
    f.metrics = {
        ready = true,
        count = 4,
        root = f.model.identity,
        generation = f.model.generation,
        source_revision = 1,
        edge = 22,
        gap = 5,
        width = 103,
        height = 22,
    }
    function f:tick(dt, packet_bounds)
        local view = self.policy:update(self.model, self.settings, dt or 0.016, false)
        local geometry =
            self.layout:update(view, self.settings, self.viewport, nil, self.measure, self.supplies, self.metrics)
        assert(geometry.valid, geometry.reason)
        local okay, why = self.composition:begin(
            geometry,
            self.model,
            view,
            self.settings,
            self.viewport,
            self.metrics,
            self.measure,
            dt or 0.016
        )
        assert(okay, why)
        local top = self.composition.combat_bounds.bottom - 12 * self.composition.cooldown_options.scale
        local combat = self.composition.combat_bounds
        local center = (combat.left + combat.right) / 2
        local packet = {
            valid = true,
            identity = self.model.identity,
            generation = self.model.generation,
            has_content = true,
            tile_count = 1,
            tiles = { {} },
            bounds = packet_bounds or { left = center - 35, right = center + 35, top = top, bottom = top - 40 },
            primitives = {
                {
                    key = "timer",
                    kind = "text",
                    x = center - 10,
                    y = top - 20,
                    width = 0,
                    height = 0,
                    text = "2:01",
                    size = 11,
                    tone = "text",
                    alpha = 1,
                    z = 951,
                },
            },
        }
        self.packet = packet
        self.before_cooldown = {
            vx = self.composition.anchors.vitals.x,
            vy = self.composition.anchors.vitals.y,
            wx = self.composition.anchors.weapon.x,
            wy = self.composition.anchors.weapon.y,
        }
        self.composition:include_cooldowns(packet)
        geometry = self.layout:update(
            view,
            self.settings,
            self.viewport,
            self.composition.anchors,
            self.measure,
            self.supplies,
            self.metrics
        )
        assert(geometry.valid, geometry.reason)
        local merged = self.composition:assemble(geometry)
        self.view, self.geometry = view, merged
        return self.composition
    end
    function f:primitive(key)
        for _, p in ipairs(self.geometry.primitives) do
            if p.key == key then
                return p
            end
        end
        error("Missing current primitive " .. key)
    end
    function f:health_center()
        local p = self:primitive("health_track")
        return p.x + p.width / 2, p.y + p.height / 2
    end
    function f:weapon_center()
        local heat
        for _, p in ipairs(self.geometry.primitives) do
            if p.key == "ammo" then
                local ink = self.measure(self.view.font, p.text, p.size)
                return p.x + (ink.left + ink.right) / 2, p.y + (ink.bottom + ink.top) / 2
            elseif p.key == "heat_track" then
                heat = p
            end
        end
        assert(heat, "Missing current weapon primary")
        return heat.x + heat.width / 2, heat.y + heat.height / 2
    end
    return f
end
local function check_split(f)
    local c = f.composition
    eq(c.anchors.vitals.source, "tfp_vitals")
    eq(c.anchors.weapon.source, "weapon_sight")
    eq(c.anchors.central.source, "reticle")
    near(c.anchor.x, f.model.reticle.x)
    near(c.anchor.y, f.model.reticle.y)
    local x, y = f:health_center()
    near(x, f.model.anchors.tfp_vitals.x - 96 * c.scale, "health CENTER stays left of selected bone")
    near(y, f.model.anchors.tfp_vitals.y)
    local p = f:primitive("ammo")
    local vm = f.model.anchors.viewmodel
    near(p.x + #p.text * p.size * 0.25, vm.x + 96 * c.scale, "ammo primary CENTER sits right of model attachment")
    near(p.y + p.size / 2, vm.y, "ammo primary Y follows the model even in TFP hip")
    eq(c.sight_clearance.active, false, "model-bound weapon is independent of screen optic spread")
end
case("all choices preserve raw profile while splitting arm and model references", function()
    for _, choice in ipairs({ 1, 2, 3 }) do
        for _, state in ipairs({
            { false, false, "hip" },
            { false, true, "first_person" },
            { true, true, "first_person" },
        }) do
            local f = fixture()
            f.values["hud.anchor"] = choice
            f.model.aim.first_person, f.model.aim.aiming = state[1], state[2]
            local c = f:tick()
            check_split(f)
            for _, role in ipairs({ "weapon", "vitals", "central" }) do
                eq(c.anchors[role].profile, state[3], "TFP does not rewrite native/Quiet profile")
            end
            eq(c.has_strip, true)
            eq(c.has_cooldowns, true)
            near(c:weapon_placement().x, c.anchors.weapon.x + c.strip_bounds.left)
            eq(c.cooldown_anchor, c.anchors.vitals)
        end
    end
end)
case("independent arm and weapon motion carry their own supports and selected cooldowns", function()
    local f = fixture()
    local c = f:tick()
    local ammo_x, ammo_y = f:primitive("ammo").x, f:primitive("ammo").y
    local strip_x, strip_y = c:weapon_placement().x, c:weapon_placement().y
    local cd_x, cd_y = f:primitive("cooldown/timer").x, f:primitive("cooldown/timer").y
    f.model.anchors.tfp_vitals.x, f.model.anchors.tfp_vitals.y = 800, 490
    c = f:tick()
    check_split(f)
    near(f:primitive("ammo").x, ammo_x)
    near(f:primitive("ammo").y, ammo_y)
    near(c:weapon_placement().x, strip_x)
    near(c:weapon_placement().y, strip_y)
    near(f:primitive("cooldown/timer").x, cd_x + 60)
    near(f:primitive("cooldown/timer").y, cd_y + 30)
    f.values["hud.cooldown_anchor"] = 2
    c = f:tick()
    eq(c.cooldown_anchor, c.anchors.weapon)
    cd_x, cd_y = f:primitive("cooldown/timer").x, f:primitive("cooldown/timer").y
    f.model.anchors.viewmodel.x, f.model.anchors.viewmodel.y = 930, 520
    c = f:tick()
    check_split(f)
    near(f:primitive("ammo").x, ammo_x + 30)
    near(f:primitive("ammo").y, ammo_y + 20)
    near(c:weapon_placement().x, strip_x + 30)
    near(c:weapon_placement().y, strip_y + 20)
    near(f:primitive("cooldown/timer").x, cd_x + 30)
    near(f:primitive("cooldown/timer").y, cd_y + 20)
    -- Reticle movement is not an attachment animation and must not move ammo.
    f.model.reticle.x, f.model.reticle.y = 1000, 620
    c = f:tick()
    near(f:primitive("ammo").x, ammo_x + 30)
    near(f:primitive("ammo").y, ammo_y + 20)
    near(c.anchor.x, 1000)
    near(c.anchor.y, 620)
end)
case("invalid or missing arm falls back without stale coordinates or hidden ammo", function()
    for key, bad in pairs({
        known = false,
        identity = 1,
        generation = 2,
        context = 83000,
        camera = 84000,
        unit = 43,
        actor_id = 9,
        token = "",
        node = -1,
        x = 0 / 0,
        clipped = true,
    }) do
        local f = fixture()
        f:tick()
        f.model.anchors.tfp_vitals[key] = bad
        eq(Anchor.vitals_point(f.model), nil, key)
        local c = f:tick()
        eq(c.anchors.vitals.source, "body")
        near(c.anchors.vitals.x, f.model.anchors.body.x)
        near(c.anchors.vitals.y, f.model.anchors.body.y)
        eq(c.anchors.weapon.source == "weapon_sight" or c.anchors.weapon.source == "sights", true)
        eq(f:primitive("ammo").text, "32")
        eq(f.view.visible, true)
    end
    local f = fixture()
    f.model.anchors.tfp_vitals = { known = true, x = 740, y = 460 }
    f.model.anchors.body.known = false
    local c = f:tick()
    eq(Anchor.vitals_point(f.model), nil, "a bare point cannot authorize arm placement")
    eq(c.anchors.vitals.source, "reticle")
    eq(c.anchors.weapon.source, "weapon_sight")
    eq(c.valid, true)
end)
case("unproven provider preserves ordinary hip third-person aim and native first-person", function()
    for _, mutation in ipairs({
        function(m)
            m.aim.true_first_person = false
        end,
        function(m)
            m.aim.true_first_person_token = ""
        end,
        function(m)
            m.aim.viewmodel_active = false
        end,
        function(m)
            m.anchor_context = nil
        end,
        function(m)
            m.anchor_camera = nil
        end,
        function(m)
            m.aim.viewmodel_unit = nil
        end,
    }) do
        local f = fixture()
        mutation(f.model)
        eq(Anchor.true_first_person(f.model), false)
        local c = f:tick()
        eq(c.anchors.weapon.source, "body")
        eq(c.anchors.vitals.source, "body")
        eq(c.sight_clearance.active, false)
    end
    local f = fixture()
    f.model.aim.true_first_person, f.model.aim.viewmodel_active, f.model.aim.aiming = false, false, true
    local c = f:tick()
    eq(c.anchors.weapon.source, "weapon")
    eq(c.anchors.vitals.source, "body")
    f.model.aim.first_person = true
    c = f:tick()
    eq(c.anchors.weapon.source, "sights")
    eq(c.anchors.vitals.source, "sights")
    eq(c.anchors.central.source, "reticle")
    eq(c.sight_clearance.active, true)
end)
case("TFP leaves Quiet visibility policy unchanged", function()
    local f = fixture()
    f.values["hud.density"] = 1
    f.model.aim.aiming = true
    local c = f:tick()
    eq(c.anchors.vitals.source, "tfp_vitals")
    eq(c.anchors.weapon.source, "weapon_sight")
    eq(c.anchors.weapon.profile, "first_person")
    eq(f.view.quiet_aim, true)
    eq(f.view.native_options, false)
    eq(f.view.native_cooldowns, false)
    eq(c.has_strip, false)
    eq(c.has_cooldowns, false)
end)
case("arm damping is independent and resets on provider or attachment replacement", function()
    local f = fixture()
    f.values["hud.anchor_damping_ms"] = 80
    f:tick()
    local arm = f.model.anchors.tfp_vitals
    arm.x, arm.y = 800, 490
    local c = f:tick(0.08)
    local x, y = f:health_center()
    near(x, 644 + 60 * (1 - math.exp(-1)))
    near(y, 460 + 30 * (1 - math.exp(-1)))
    near(c.anchor.x, 960)
    near(f:primitive("ammo").y + 15, 500)
    arm.token, arm.x = "fps/replaced-left-hand", 820
    f:tick()
    near(f:health_center(), 724, "new attachment cannot reuse old screen history")
    f.model.aim.true_first_person_token, arm.x = "provider/reloaded", 840
    f:tick()
    near(f:health_center(), 744, "provider reload resets role histories")
    f.model.aim.true_first_person = false
    c = f:tick()
    eq(c.anchors.vitals.source, "body")
    f.model.aim.true_first_person, arm.x = true, 780
    f:tick()
    near(f:health_center(), 684, "mode re-entry never resumes old arm history")
end)
case("viewport clamps and native fallback never drag unrelated groups", function()
    local f = fixture()
    local c = f:tick()
    local ammo_x, ammo_y = f:primitive("ammo").x, f:primitive("ammo").y
    f.model.anchors.tfp_vitals.x, f.model.anchors.tfp_vitals.y = 0, 0
    c = f:tick()
    eq(c.anchors.vitals.source, "tfp_vitals")
    local g, a = c.group_bounds.vitals, c.anchors.vitals
    eq(g.left + a.x >= 5, true)
    eq(g.bottom + a.y >= 5, true)
    near(f:primitive("ammo").x, ammo_x)
    near(f:primitive("ammo").y, ammo_y)
    near(c.anchor.x, 960)
    near(c.anchor.y, 540)
    eq(c.has_cooldowns, false, "Original fallback if row would drag health more than 8px")
    local before_x, before_y = a.x, a.y
    local okay = c:include_cooldowns({
        valid = true,
        identity = f.model.identity,
        generation = f.model.generation,
        has_content = true,
        bounds = { left = -3000, right = 3000, bottom = -100, top = 0 },
    })
    eq(okay, false)
    near(a.x, before_x)
    near(a.y, before_y)
    near(c.anchors.weapon.x + 65, ammo_x)
end)
case("reticle clearance moves arm group only and preserves internal spacing", function()
    local f = fixture()
    f.model.anchors.tfp_vitals.x, f.model.anchors.tfp_vitals.y = 1056, 540
    local c = f:tick()
    local a, g, e = c.anchors.vitals, c.group_bounds.vitals, c:reticle_clearance()
    local overlap = g.left + a.x < e.right
        and g.right + a.x > e.left
        and g.bottom + a.y < e.top
        and g.top + a.y > e.bottom
    eq(overlap, false)
    near(c.anchor.x, 960)
    near(c.anchor.y, 540)
    near(f:primitive("ammo").y + 15, 500)
    local health, stamina = f:primitive("health_track"), f:primitive("stamina_track")
    near(health.x, stamina.x)
    near(health.y - stamina.y, 7)
end)
case("weapon attachment damping resets independently after missing or replaced model points", function()
    local f = fixture()
    f.values["hud.anchor_damping_ms"] = 80
    local vm = f.model.anchors.viewmodel
    vm.x, vm.y = 1200, 500
    f:tick()
    vm.x, vm.y = 1300, 450
    f:tick(0.08)
    near(f:primitive("ammo").x + 15, 1296 + 100 * (1 - math.exp(-1)))
    near(f:primitive("ammo").y + 15, 500 - 50 * (1 - math.exp(-1)))
    local x, y = f:health_center()
    near(x, 644)
    near(y, 460)
    vm.known = false
    f:tick()
    near(f:primitive("ammo").y + 15, 540)
    vm.known, vm.x, vm.y = true, 1400, 450
    f:tick()
    near(f:primitive("ammo").x + 15, 1496, "fresh point never resumes pre-fallback history")
    near(f:primitive("ammo").y + 15, 450)
    vm.token, vm.x, vm.y = "fps/new-weapon-attachment", 1450, 430
    f:tick()
    near(f:primitive("ammo").x + 15, 1546, "new native attachment resets only its current role")
    near(f:primitive("ammo").y + 15, 430)
end)
case("nonzero damping filters the physical primary before current digits modes and font metrics", function()
    local f = fixture()
    f.values["hud.anchor_damping_ms"] = 80
    local vm = f.model.anchors.viewmodel
    vm.x, vm.y = 1200, 450
    f:tick()
    for _, count in ipairs({ 9, 9999, 32, 0 }) do
        f.model.weapon.count = count
        f:tick(0.016)
        local x, y = f:weapon_center()
        near(x, 1296, "stationary model cannot drift when digits change")
        near(y, 450)
    end
    f.model.weapon.ammo_kind, f.model.weapon.heat_weapon = "heat", true
    f.model.weapon.count, f.model.weapon.heat = nil, 0.5
    for _, display in ipairs({ 2, 3, 1, 3, 2 }) do
        for _, vertical in ipairs({ true, false }) do
            f.values["hud.heat_display"], f.values["hud.heat_bar_vertical"] = display, vertical
            f:tick(0.016)
            local x, y = f:weapon_center()
            near(x, 1296, "Text/Bar/Hybrid orientation cannot change the filtered physical primary")
            near(y, 450)
        end
    end
    f.values["hud.heat_display"] = 1
    f.measure = function(font, text, size)
        local ink = measure(font, text, size)
        ink.left, ink.right, ink.bottom, ink.top = -7, ink.right + 13, -4, ink.top + 8
        return ink
    end
    f.model.font = { changed_font = true }
    f:tick(0.016)
    local x, y = f:weapon_center()
    near(x, 1296, "changed font bearings do not enter the filter history")
    near(y, 450)
    local hx, hy = f:health_center()
    near(hx, 644)
    near(hy, 460)
    -- Actual model motion still advances exactly once, independently of shape.
    vm.x, vm.y = 1300, 400
    f.values["hud.heat_display"] = 2
    f:tick(0.08)
    x, y = f:weapon_center()
    near(x, 1296 + 100 * (1 - math.exp(-1)))
    near(y, 450 - 50 * (1 - math.exp(-1)))
    hx, hy = f:health_center()
    near(hx, 644)
    near(hy, 460)
end)
case("font-size scale changes damp only the intentional right gap", function()
    local f = fixture()
    f.values["hud.anchor_damping_ms"] = 80
    local vm = f.model.anchors.viewmodel
    vm.x, vm.y = 1200, 450
    f:tick()
    f.values["hud.scale"] = 150
    f:tick(0.016)
    local x, y = f:weapon_center()
    near(f:primitive("ammo").size, 45)
    near(x, 1296 + (144 - 96) * (1 - math.exp(-0.016 / 0.08)))
    near(y, 450, "new font size cannot add a second vertical filter transform")
end)
case("missing weapon point uses current screen fallback and never reuses a prior model position", function()
    for key, bad in pairs({
        known = false,
        identity = 1,
        generation = 2,
        context = 83000,
        camera = 84000,
        unit = 43,
        actor_id = 9,
        token = "",
        node = -1,
        x = 0 / 0,
        clipped = true,
    }) do
        local f = fixture()
        f.values["hud.anchor_damping_ms"] = 80
        f:tick()
        f.model.anchors.viewmodel[key] = bad
        eq(Anchor.weapon_sight_point(f.model), nil, key)
        local c = f:tick()
        eq(c.anchors.weapon.source, "sights")
        eq(c.sight_clearance.active, true)
        near(f:primitive("ammo").y + 15, 540, "fallback uses the current reticle, not the old model Y")
        eq(f:primitive("ammo").text, "32")
        eq(f.view.visible, true)
    end
    local f = fixture()
    f.model.anchors.viewmodel.known = false
    local c = f:tick()
    eq(c.anchors.vitals.source, "tfp_vitals", "unavailable weapon projection does not discard the arm")
    f.model.anchors.viewmodel.known = true
    f.model.anchors.viewmodel.x, f.model.anchors.viewmodel.y = 1150, 450
    c = f:tick()
    eq(c.anchors.weapon.source, "weapon_sight")
    near(f:primitive("ammo").x + 15, 1246)
    near(f:primitive("ammo").y + 15, 450)
end)
case("model reference remains the measured primary center across digits heat layouts and scale", function()
    for _, display in ipairs({ 1, 2, 3 }) do
        for _, vertical in ipairs({ false, true }) do
            local f = fixture()
            f.model.weapon.ammo_kind, f.model.weapon.heat_weapon = "heat", true
            f.model.weapon.count, f.model.weapon.heat = nil, 0.5
            f.model.anchors.viewmodel.x = 1200
            f.values["hud.heat_display"], f.values["hud.heat_bar_vertical"] = display, vertical
            local c = f:tick()
            local p = f:primitive(display == 2 and "heat_track" or "ammo")
            local x, y = p.x + p.width / 2, p.y + p.height / 2
            if p.kind == "text" then
                local ink = measure(f.view.font, p.text, p.size)
                x, y = p.x + (ink.left + ink.right) / 2, p.y + (ink.bottom + ink.top) / 2
            end
            near(x, 1296)
            near(y, 500)
            eq(c.anchors.weapon.source, "weapon_sight")
            eq(c.sight_clearance.active, false)
        end
    end
    local f = fixture()
    f.values["hud.scale"] = 150
    f.model.anchors.viewmodel.x = 1200
    for _, count in ipairs({ 0, 9, 32, 9999 }) do
        f.model.weapon.count = count
        f:tick()
        local p = f:primitive("ammo")
        local ink = measure(f.view.font, p.text, p.size)
        near(p.x + (ink.left + ink.right) / 2, 1200 + 96 * 1.5)
        near(p.y + (ink.bottom + ink.top) / 2, 500)
    end
end)
case("TFP hip missing-point screen fallback needs no unused left column room", function()
    local f = fixture()
    f.model.reticle.x = 140
    f.model.anchors.viewmodel.known = false
    local c = f:tick()
    eq(c.anchors.weapon.profile, "hip")
    eq(c.sight_clearance.active, true)
    eq(c.sight_clearance.fits, true, "independent left-arm needs no left sight column")
    eq(c.sight_clearance.source, "fallback")
    near(f:primitive("ammo").y + 15, 540)
    eq(f:primitive("ammo").x > 236, true)
    local x, y = f:health_center()
    near(x, 644)
    near(y, 460)
    f.model.aim.true_first_person, f.model.aim.first_person = false, true
    c = f:tick()
    eq(c.sight_clearance.fits, false, "ordinary FP still needs both side rails")
end)
local function column_bounds(f, role)
    local b = { left = math.huge, right = -math.huge, bottom = math.huge, top = -math.huge }
    local function include(l, r, bottom, top)
        b.left, b.right, b.bottom, b.top =
            math.min(b.left, l), math.max(b.right, r), math.min(b.bottom, bottom), math.max(b.top, top)
    end
    for _, p in ipairs(f.geometry.primitives) do
        if p.group == role and p.key:sub(1, 9) ~= "cooldown/" then
            if p.kind == "text" then
                local ink = f.measure(f.view.font, p.text, p.size)
                include(p.x + ink.left, p.x + ink.right, p.y + ink.bottom, p.y + ink.top)
            else
                include(p.x, p.x + p.width, p.y, p.y + p.height)
            end
        end
    end
    for _, icon in ipairs(f.geometry.supplies or {}) do
        if (icon.key == "heat" and "weapon" or "vitals") == role then
            include(icon.x, icon.x + icon.width, icon.y, icon.y + icon.height)
        end
    end
    local c = f.composition
    if role == "weapon" and c.has_strip then
        local strip = c:weapon_placement()
        include(
            strip.x,
            strip.x + c.strip_bounds.right - c.strip_bounds.left,
            strip.y,
            strip.y + c.strip_bounds.top - c.strip_bounds.bottom
        )
    end
    if b.left == math.huge then
        local a = c.anchors[role]
        b.left, b.right =
            a.x + (role == "vitals" and -157 or 60) * c.scale, a.x + (role == "vitals" and -53 or 173) * c.scale
        b.bottom, b.top = a.y - 100 * c.scale, a.y - 46 * c.scale
    end
    return b
end
local function column_center(f, role)
    local b = column_bounds(f, role)
    return (b.left + b.right) / 2
end
local function check_stack(f)
    local c = f.composition
    eq(c.stacked, true)
    eq(c.anchors.weapon.source, "above_health")
    eq(c.anchors.central.source, "reticle")
    eq(c.sight_clearance.active, false)
    local x, y = f:weapon_center()
    local va, wa = c.anchors.vitals, c.anchors.weapon
    near(
        column_center(f, "weapon"),
        column_center(f, "vitals") + (f.values["hud.tfp_ammo_offset_x"] or 0) * c.pixel,
        "ammo X tuning is relative to square complete-column alignment"
    )
    eq(y > va.y + c.primary_centers.vitals, true)
    if (f.values["hud.tfp_ammo_offset_y"] or 0) == 0 then
        near(wa.y + c.stack_local_weapon.bottom - va.y - c.stack_local_vitals.top, 12 * c.scale)
    end
    local vg, wg = c.group_bounds.vitals, c.group_bounds.weapon
    if vg.count > 0 and wg.count > 0 then
        eq(
            wg.bottom + wa.y >= vg.top + va.y + 12 * c.scale - 1e-6,
            true,
            "complete ammo/options/cooldown envelope cannot overlap health/supplies"
        )
    end
    near(c.anchor.x, f.model.reticle.x)
    near(c.anchor.y, f.model.reticle.y)
end
case("selected chassis wrist and elbow use the same left-gap rule", function()
    for bone, coords in ipairs({ { 900, 500, 8 }, { 740, 460, 12 }, { 680, 430, 13 } }) do
        local f = fixture()
        f.values["hud.tfp_vitals_bone"] = bone
        local vital = f.model.anchors.tfp_vitals
        vital.x, vital.y, vital.node, vital.token = coords[1], coords[2], coords[3], "selected-vitals/" .. bone
        f.model.anchors.viewmodel.x, f.model.anchors.viewmodel.y = 1200, 450
        f:tick()
        local x, y = f:health_center()
        near(x, coords[1] - 96)
        near(y, coords[2])
        near(f:weapon_center(), 1296)
        eq(f.composition.anchors.vitals.source, "tfp_vitals")
        local old = f.model.anchors.tfp_vitals
        f.model.anchors.tfp_vitals, f.model.anchors.left_arm = nil, old
        f:tick()
        eq(
            f.composition.anchors.vitals.source,
            "body",
            "retired internal left_arm DTO cannot authorize a selected bone"
        )
    end
end)
case("Above health ignores ammo bone and advances only the health motion filter", function()
    local f = fixture()
    f.values["hud.tfp_ammo_placement"], f.values["hud.anchor_damping_ms"] = 2, 80
    f.model.anchors.viewmodel.known = false
    f:tick()
    check_stack(f)
    local primary_delta = f:weapon_center() - f:health_center()
    f.model.anchors.viewmodel.x, f.model.anchors.viewmodel.y = 1700, 300
    f.model.anchors.tfp_vitals.x, f.model.anchors.tfp_vitals.y = 840, 510
    f:tick(0.08)
    check_stack(f)
    local x, y = f:health_center()
    near(x, 644 + 100 * (1 - math.exp(-1)))
    near(y, 460 + 50 * (1 - math.exp(-1)))
    near(f:weapon_center(), x + primary_delta, "stacked column does not receive a second damping step")
    f.model.anchors.viewmodel.known = true
    f.model.anchors.viewmodel.x, f.model.anchors.viewmodel.y = 1400, 380
    f.values["hud.tfp_ammo_placement"] = 1
    f:tick()
    near(f:weapon_center(), 1496, "return to right placement cannot resume old independent history")
    f.values["hud.tfp_ammo_placement"] = 2
    f:tick()
    check_stack(f)
end)
case("stack includes heat variants font metrics options and either cooldown section", function()
    for _, cooldown in ipairs({ 1, 2 }) do
        for _, display in ipairs({ 1, 2, 3 }) do
            for _, vertical in ipairs({ false, true }) do
                local f = fixture()
                f.values["hud.tfp_ammo_placement"], f.values["hud.cooldown_anchor"] = 2, cooldown
                f.values["hud.heat_display"], f.values["hud.heat_bar_vertical"] = display, vertical
                f.model.weapon.ammo_kind, f.model.weapon.heat_weapon, f.model.weapon.heat = "heat", true, 0.75
                f.model.weapon.count = nil
                f.measure = function(font, text, size)
                    local ink = measure(font, text, size)
                    ink.left, ink.right, ink.bottom, ink.top = -3, ink.right + 7, -5, ink.top + 11
                    return ink
                end
                local c = f:tick()
                check_stack(f)
                eq(c.has_strip, true)
                eq(c.has_cooldowns, true)
                eq(c.cooldown_anchor, c.anchors[cooldown == 2 and "weapon" or "vitals"])
                if cooldown == 2 then
                    eq(
                        c.anchors.weapon.y > f.before_cooldown.wy,
                        true,
                        "ammo cooldown expansion raises ammo before overlap"
                    )
                    near(c.anchors.vitals.y, f.before_cooldown.vy)
                end
            end
        end
    end
end)
case("Quiet health reveal and icon fallback retain the stack reference without another damping step", function()
    local f = fixture()
    f.values["hud.tfp_ammo_placement"], f.values["hud.density"], f.values["hud.anchor_damping_ms"] = 2, 1, 80
    f.model.health, f.model.stamina = 1, 1
    f:tick()
    eq(f.view.health.visible, false)
    check_stack(f)
    local x, y = f:weapon_center()
    f.model.health = 0.20
    f:tick(0)
    eq(f.view.health.visible, true)
    eq(f.view.health.tone, "danger")
    check_stack(f)
    local wx, wy = f:weapon_center()
    near(wx, x)
    near(wy, y, "critical reveal keeps the virtual health shelf reference")
    f.supplies = {
        stims = { known = true, width = 32, height = 32, texture = "0123456789abcdef" },
        throwables = { known = true, width = 24, height = 16, texture = "fedcba9876543210" },
    }
    f:tick(0)
    check_stack(f)
    x, y = f:weapon_center()
    f.supplies = nil
    f:tick(0)
    check_stack(f)
    wx, wy = f:weapon_center()
    near(wx, x)
    near(wy, y, "descriptive fallback cannot add another smoothing step")
end)
case("stack clamps the pair coherently and refuses oversized native expansion without partial movement", function()
    for _, cooldown in ipairs({ 1, 2 }) do
        local f = fixture()
        f.values["hud.tfp_ammo_placement"], f.values["hud.cooldown_anchor"] = 2, cooldown
        f.model.anchors.tfp_vitals.x, f.model.anchors.tfp_vitals.y = 20, 1060
        local c = f:tick()
        check_stack(f)
        eq(f.geometry.bounds.left >= 5, true)
        eq(f.geometry.bounds.right <= 1915, true)
        eq(f.geometry.bounds.bottom >= 5, true)
        eq(f.geometry.bounds.top <= 1075, true)
        local va, wa = c.anchors.vitals, c.anchors.weapon
        local vx, vy, wx, wy = va.x, va.y, wa.x, wa.y
        local okay = c:include_cooldowns({
            valid = true,
            identity = f.model.identity,
            generation = f.model.generation,
            has_content = true,
            bounds = { left = -3000, right = 3000, bottom = -300, top = -160 },
        })
        eq(okay, false)
        near(va.x, vx)
        near(va.y, vy)
        near(wa.x, wx)
        near(wa.y, wy)
    end
end)
case("stack follows displayed health fallback and remains TFP-only", function()
    local f = fixture()
    f.values["hud.tfp_ammo_placement"] = 2
    f.model.anchors.tfp_vitals.known = false
    local c = f:tick()
    eq(c.anchors.vitals.source, "body")
    check_stack(f)
    f.model.anchors.body.known = false
    c = f:tick()
    eq(c.anchors.vitals.source, "reticle")
    check_stack(f)
    f.model.aim.true_first_person = false
    c = f:tick()
    eq(c.stacked, false)
    eq(c.anchors.weapon.source, "reticle")
    f.model.aim.first_person = true
    c = f:tick()
    eq(c.stacked, false)
    eq(c.anchors.weapon.source, "sights")
end)
case("TFP role offsets use viewport pixels once with independent HUD scale and global ADS offsets", function()
    for _, height in ipairs({ 1080, 2160 }) do
        for _, percent in ipairs({ 50, 150 }) do
            for _, aiming in ipairs({ false, true }) do
                local f = fixture()
                local pixel = height / 1080
                f.viewport.width, f.viewport.height = 1920 * pixel, height
                f.model.reticle.x, f.model.reticle.y = 960 * pixel, 540 * pixel
                f.model.anchors.tfp_vitals.x, f.model.anchors.tfp_vitals.y = 700 * pixel, 400 * pixel
                f.model.anchors.viewmodel.x, f.model.anchors.viewmodel.y = 1250 * pixel, 450 * pixel
                f.values["hud.scale"], f.model.aim.aiming = percent, aiming
                f.values["hud.offset_x"], f.values["hud.offset_y"] = 10, 20
                f.values["hud.ads_offset_x"], f.values["hud.ads_offset_y"] = 5, -7
                f.values["hud.tfp_vitals_offset_x"], f.values["hud.tfp_vitals_offset_y"] = -25, 30
                f.values["hud.tfp_ammo_offset_x"], f.values["hud.tfp_ammo_offset_y"] = 40, -15
                local c = f:tick()
                local gx, gy = aiming and 15 or 10, aiming and 13 or 20
                local hx, hy = f:health_center()
                local wx, wy = f:weapon_center()
                near(hx, 700 * pixel - 96 * c.scale + (gx - 25) * pixel)
                near(hy, 400 * pixel - (gy + 30) * pixel)
                near(wx, 1250 * pixel + 96 * c.scale + (gx + 40) * pixel)
                near(wy, 450 * pixel - (gy - 15) * pixel)
                near(c.anchor.x, (960 + gx) * pixel, "central receives global/ADS offsets but no role tuning")
                near(c.anchor.y, (540 - gy) * pixel)
            end
        end
    end
end)
case("each new slider bone and placement setting resets TFP motion at zero dt", function()
    for _, key in ipairs({
        "hud.tfp_vitals_offset_x",
        "hud.tfp_vitals_offset_y",
        "hud.tfp_ammo_offset_x",
        "hud.tfp_ammo_offset_y",
        "hud.tfp_vitals_bone",
        "hud.tfp_ammo_bone",
        "hud.tfp_ammo_placement",
    }) do
        local f = fixture()
        f.values["hud.anchor_damping_ms"] = 80
        f.model.anchors.viewmodel.x, f.model.anchors.viewmodel.y = 1200, 450
        f:tick()
        f.model.anchors.tfp_vitals.x, f.model.anchors.tfp_vitals.y = 800, 430
        f.model.anchors.viewmodel.x, f.model.anchors.viewmodel.y = 1300, 420
        f.values[key] = key == "hud.tfp_ammo_placement" and 2 or key:find("bone", 1, true) and 10 or 20
        f:tick(0)
        local hx, hy = f:health_center()
        near(hx, 800 - 96 + (f.values["hud.tfp_vitals_offset_x"] or 0), key)
        near(hy, 430 - (f.values["hud.tfp_vitals_offset_y"] or 0), key)
        if f.values["hud.tfp_ammo_placement"] == 2 then
            check_stack(f)
        else
            local wx, wy = f:weapon_center()
            near(wx, 1300 + 96 + (f.values["hud.tfp_ammo_offset_x"] or 0), key)
            near(wy, 420 - (f.values["hud.tfp_ammo_offset_y"] or 0), key)
        end
    end
end)
case("missing selected bones retain role tuning without moving reticle or screen optic band", function()
    local f = fixture()
    f.values["hud.anchor_damping_ms"] = 80
    f.model.anchors.tfp_vitals.known, f.model.anchors.viewmodel.known = false, false
    local c = f:tick()
    local hx, hy = f:health_center()
    local wx, wy = f:weapon_center()
    local sl, sr, sb, st =
        c.sight_clearance.bounds.left,
        c.sight_clearance.bounds.right,
        c.sight_clearance.bounds.bottom,
        c.sight_clearance.bounds.top
    f.values["hud.tfp_vitals_offset_x"], f.values["hud.tfp_vitals_offset_y"] = 25, -10
    f.values["hud.tfp_ammo_offset_x"], f.values["hud.tfp_ammo_offset_y"] = 20, 30
    c = f:tick(0)
    eq(c.anchors.vitals.source, "body")
    eq(c.anchors.weapon.source, "sights")
    local x, y = f:health_center()
    near(x, hx + 25)
    near(y, hy + 10)
    x, y = f:weapon_center()
    near(x, wx + 20)
    near(y, wy - 30)
    near(c.anchor.x, 960)
    near(c.anchor.y, 540)
    near(c.sight_clearance.bounds.left, sl)
    near(c.sight_clearance.bounds.right, sr)
    near(c.sight_clearance.bounds.bottom, sb)
    near(c.sight_clearance.bounds.top, st)
    f.model.anchors.body.known = false
    c = f:tick(0)
    eq(c.anchors.vitals.source, "reticle")
    near(c.anchors.vitals.x, 985)
    near(c.anchors.vitals.y, 550)
end)
case("stacked health offset moves the pair once and ammo offsets use measured gap slack", function()
    local f = fixture()
    f.values["hud.tfp_ammo_placement"], f.values["hud.anchor_damping_ms"] = 2, 80
    f:tick()
    local hx, hy = f:health_center()
    local wx, wy = f:weapon_center()
    f.values["hud.tfp_vitals_offset_x"], f.values["hud.tfp_vitals_offset_y"] = 10, -20
    f:tick(0)
    local x, y = f:health_center()
    near(x, hx + 10)
    near(y, hy + 20)
    x, y = f:weapon_center()
    near(x, wx + 10)
    near(y, wy + 20)
    f.values["hud.tfp_ammo_offset_x"], f.values["hud.tfp_ammo_offset_y"] = 30, -15
    f:tick(0)
    check_stack(f)
    x, y = f:weapon_center()
    near(x, wx + 40)
    near(y, wy + 35)
    f.values["hud.tfp_ammo_offset_y"] = 5
    f:tick(0)
    check_stack(f)
    x, y = f:weapon_center()
    near(y, wy + 15, "positive Y consumes real extra shelf spacing")
    f.values["hud.tfp_ammo_offset_y"] = 600
    local c = f:tick(0)
    check_stack(f)
    local va, wa = c.anchors.vitals, c.anchors.weapon
    near(
        c.group_bounds.weapon.bottom + wa.y - c.group_bounds.vitals.top - va.y,
        12 * c.scale,
        "stored down preference stops at actual complete group safety gap"
    )
    eq(f.values["hud.tfp_ammo_offset_y"], 600, "clamping presentation never rewrites settings")
end)
case("stack offsets remain safe across cooldown sections heat modes metrics and viewport edges", function()
    for _, cooldown in ipairs({ 1, 2 }) do
        for _, display in ipairs({ 1, 2, 3 }) do
            local f = fixture()
            f.values["hud.tfp_ammo_placement"], f.values["hud.cooldown_anchor"] = 2, cooldown
            f.values["hud.heat_display"], f.values["hud.heat_bar_vertical"] = display, display ~= 1
            f.values["hud.tfp_vitals_offset_x"], f.values["hud.tfp_vitals_offset_y"] = -600, 600
            f.values["hud.tfp_ammo_offset_x"], f.values["hud.tfp_ammo_offset_y"] = 600, 600
            f.model.weapon.ammo_kind, f.model.weapon.heat_weapon, f.model.weapon.heat = "heat", true, 0.75
            f.model.weapon.count = nil
            f.measure = function(font, text, size)
                local ink = measure(font, text, size)
                ink.left, ink.right, ink.bottom, ink.top = -5, ink.right + 11, -6, ink.top + 13
                return ink
            end
            local c = f:tick()
            check_stack(f)
            eq(c.has_cooldowns, true)
            eq(f.geometry.bounds.left >= 5 and f.geometry.bounds.right <= 1915, true)
            eq(f.geometry.bounds.bottom >= 5 and f.geometry.bounds.top <= 1075, true)
        end
    end
end)
case("constant role offsets remain inside stable physical damping across glyph and heat changes", function()
    local f = fixture()
    f.values["hud.anchor_damping_ms"] = 80
    f.values["hud.tfp_ammo_offset_x"], f.values["hud.tfp_ammo_offset_y"] = 30, -20
    local vm = f.model.anchors.viewmodel
    vm.x, vm.y = 1200, 450
    f:tick()
    vm.x, vm.y, f.model.weapon.count = 1300, 400, 9
    f:tick(0.08)
    local wx, wy = f:weapon_center()
    near(wx, 1326 + 100 * (1 - math.exp(-1)))
    near(wy, 470 - 50 * (1 - math.exp(-1)))
    f.model.weapon.ammo_kind, f.model.weapon.heat_weapon, f.model.weapon.heat = "heat", true, 0.5
    f.model.weapon.count, f.values["hud.heat_display"] = nil, 2
    f:tick(0)
    local x, y = f:weapon_center()
    near(x, wx)
    near(y, wy)
end)
case("role preferences disappear outside proven TFP and malformed offsets fail closed", function()
    local f = fixture()
    f.model.aim.true_first_person = false
    f:tick()
    local hx, hy = f:health_center()
    local wx, wy = f:weapon_center()
    for _, key in ipairs({
        "hud.tfp_vitals_offset_x",
        "hud.tfp_vitals_offset_y",
        "hud.tfp_ammo_offset_x",
        "hud.tfp_ammo_offset_y",
    }) do
        f.values[key] = 600
    end
    f:tick()
    local x, y = f:health_center()
    near(x, hx)
    near(y, hy)
    x, y = f:weapon_center()
    near(x, wx)
    near(y, wy)
    f.model.aim.true_first_person = true
    for _, bad in ipairs({ -601, 601, 0 / 0, math.huge, "25" }) do
        f.values["hud.tfp_ammo_offset_x"] = bad
        local target, why = Anchor.target_role(f.model, f.settings, f.viewport, f.composition.base, "weapon")
        eq(target, nil)
        eq(why, "TFP offset unavailable")
    end
end)
case("both selected sections accept independently stamped FPS and weapon unit domains", function()
    for _, vital_domain in ipairs({ "fps", "weapon" }) do
        for _, ammo_domain in ipairs({ "fps", "weapon" }) do
            local f = fixture()
            local vital, ammo = f.model.anchors.tfp_vitals, f.model.anchors.viewmodel
            vital.unit_domain, vital.unit = vital_domain, vital_domain == "fps" and 42 or 84
            ammo.unit_domain, ammo.unit = ammo_domain, ammo_domain == "fps" and 42 or 84
            vital.token, ammo.token = vital_domain .. "/selected-vitals", ammo_domain .. "/selected-ammo"
            ammo.x, ammo.y = 1200, 450
            f.values["hud.tfp_vitals_bone"] = vital_domain == "fps" and 2 or 11
            f.values["hud.tfp_ammo_bone"] = ammo_domain == "fps" and 1 or 13
            local c = f:tick()
            eq(Anchor.vitals_point(f.model), vital)
            eq(Anchor.weapon_sight_point(f.model), ammo)
            check_split(f)
            eq(c.has_strip, true)
            eq(c.has_cooldowns, true)
            -- Stacked placement uses the same stamped health point; the ammo
            -- selection remains persisted but no coordinate authorizes it.
            f.values["hud.tfp_ammo_placement"] = 2
            ammo.known = false
            c = f:tick(0)
            eq(c.anchors.vitals.source, "tfp_vitals")
            check_stack(f)
        end
    end
end)
case("weapon points require the independent fresh weapon stamp and cannot self-authorize", function()
    for _, role in ipairs({ "vitals", "weapon" }) do
        for _, mutation in ipairs({
            function(m, p)
                m.aim.weapon_unit = nil
                p.weapon_unit = 84
            end,
            function(m, p)
                m.aim.weapon_unit = 85
                p.weapon_unit = 84
            end,
            function(m, p)
                m.aim.weapon_unit = 0
            end,
            function(m, p)
                m.aim.weapon_unit = 0 / 0
            end,
            function(m, p)
                m.aim.weapon_unit = 84.5
            end,
            function(m, p)
                m.aim.weapon_unit = 4294967295
            end,
            function(m, p)
                p.unit_domain = nil
            end,
            function(m, p)
                p.unit_domain = "body"
            end,
            function(m, p)
                p.unit_domain = true
            end,
            function(m, p)
                p.unit_domain = "fps"
            end,
            function(m, p)
                p.unit = 42
                p.weapon_unit = 42
            end,
            function(m, p)
                p.clipped = true
            end,
        }) do
            local f = fixture()
            local point = f.model.anchors[role == "vitals" and "tfp_vitals" or "viewmodel"]
            point.unit_domain, point.unit, point.weapon_unit = "weapon", 84, 84
            point.token = "weapon/strict-current-owner"
            point.x, point.y = role == "vitals" and 740 or 1200, 450
            f:tick()
            mutation(f.model, point)
            local current
            if role == "vitals" then
                current = Anchor.vitals_point(f.model)
            else
                current = Anchor.weapon_sight_point(f.model)
            end
            eq(current, nil)
            local c = f:tick(0)
            eq(c.anchors[role].source, role == "vitals" and "body" or "sights")
            eq(f.view.visible, true)
            eq(f:primitive("ammo").text, "32")
        end
    end
end)
case("weapon-domain anchors never substitute for the FPS mode ownership proof", function()
    for _, mutation in ipairs({
        function(m)
            m.aim.viewmodel_unit = nil
        end,
        function(m)
            m.aim.viewmodel_active = false
        end,
        function(m)
            m.aim.true_first_person = false
        end,
        function(m)
            m.aim.true_first_person_token = ""
        end,
    }) do
        local f = fixture()
        for _, p in ipairs({ f.model.anchors.tfp_vitals, f.model.anchors.viewmodel }) do
            p.unit_domain, p.unit, p.token = "weapon", 84, "weapon/current-owner"
        end
        mutation(f.model)
        eq(Anchor.true_first_person(f.model), false)
        eq(Anchor.vitals_point(f.model), nil)
        eq(Anchor.weapon_sight_point(f.model), nil)
        local c = f:tick()
        eq(c.anchors.vitals.source, "body")
        eq(c.anchors.weapon.source, "body")
        eq(f:primitive("ammo").text, "32")
    end
end)
case("Above health centers the complete heat coil and native options column over the bracket", function()
    for _, display in ipairs({ 1, 2, 3 }) do
        for _, vertical in ipairs({ false, true }) do
            for _, coil in ipairs({ false, true }) do
                for _, wide in ipairs({ false, true }) do
                    local f = fixture()
                    f.values["hud.tfp_ammo_placement"], f.values["hud.anchor_damping_ms"] = 2, 80
                    f.values["hud.heat_display"], f.values["hud.heat_bar_vertical"] = display, vertical
                    f.model.weapon.ammo_kind, f.model.weapon.heat_weapon, f.model.weapon.heat = "heat", true, 0.61
                    f.model.weapon.count = nil
                    f.measure = function(font, text, size)
                        local ink = measure(font, text, size)
                        ink.left, ink.right, ink.bottom, ink.top = -3.25, ink.right + 8.75, -4.125, ink.top + 7.5
                        return ink
                    end
                    if coil then
                        f.supplies = { heat = { known = true, width = 17, height = 34, texture = "fb6b3350a1645aa8" } }
                    end
                    if wide then
                        f.metrics.edge, f.metrics.gap, f.metrics.width, f.metrics.height = 40, 12, 196, 40
                    end
                    local c = f:tick()
                    check_stack(f)
                    near(
                        column_center(f, "weapon"),
                        column_center(f, "vitals"),
                        "default0 squares actual complete visible columns"
                    )
                    eq(c.has_strip, true)
                    -- Mode/font updates use current envelopes AFTER the single
                    -- health filter; they must not wait for glyph-center easing.
                    f.model.weapon.heat = 0.99
                    f:tick(0.016)
                    check_stack(f)
                    near(column_center(f, "weapon"), column_center(f, "vitals"))
                end
            end
        end
    end
end)
case("changing cooldown width never recenters either visual column", function()
    for _, side in ipairs({ 1, 2 }) do
        local f = fixture()
        f.values["hud.tfp_ammo_placement"], f.values["hud.cooldown_anchor"] = 2, side
        f.model.anchors.tfp_vitals.y = 200
        local c = f:tick()
        local hx, wx = column_center(f, "vitals"), column_center(f, "weapon")
        for _, width in ipairs({ 160, 600, 240 }) do
            local center = (c.combat_bounds.left + c.combat_bounds.right) / 2
            local top = c.combat_bounds.bottom - 12 * c.cooldown_options.scale
            local packet = {
                valid = true,
                identity = f.model.identity,
                generation = f.model.generation,
                has_content = true,
                bounds = { left = center - width / 2, right = center + width / 2, top = top, bottom = top - 45 },
                primitives = {
                    {
                        key = "wide-countdown",
                        kind = "text",
                        x = center - width / 2,
                        y = top - 20,
                        text = "00:01 WIDE COOLDOWN",
                        size = 11,
                        tone = "text",
                        alpha = 1,
                        z = 951,
                    },
                },
            }
            eq(c:include_cooldowns(packet), true)
            local geometry =
                f.layout:update(f.view, f.settings, f.viewport, c.anchors, f.measure, f.supplies, f.metrics)
            f.geometry = c:assemble(geometry)
            check_stack(f)
            near(column_center(f, "vitals"), hx)
            near(column_center(f, "weapon"), wx)
        end
    end
end)
case("ammo X remains explicit fine tuning relative to the square column at both resolutions", function()
    for _, height in ipairs({ 1080, 2160 }) do
        for _, offset in ipairs({ -35, 0, 35 }) do
            local f = fixture()
            local pixel = height / 1080
            f.viewport.width, f.viewport.height = 1920 * pixel, height
            f.model.reticle.x, f.model.reticle.y = 960 * pixel, 540 * pixel
            f.values["hud.scale"], f.values["hud.tfp_ammo_placement"], f.values["hud.tfp_ammo_offset_x"] =
                150, 2, offset
            f.model.weapon.ammo_kind, f.model.weapon.heat_weapon, f.model.weapon.heat = "heat", true, 0.5
            f.model.weapon.count = nil
            f.values["hud.heat_display"], f.values["hud.heat_bar_vertical"] = 3, true
            f.supplies = { heat = { known = true, width = 17, height = 34, texture = "fb6b3350a1645aa8" } }
            f:tick()
            check_stack(f)
            near(column_center(f, "weapon") - column_center(f, "vitals"), offset * pixel)
            eq(f.values["hud.tfp_ammo_offset_x"], offset)
        end
    end
end)
case("refused oversized native options do not contaminate the base visual center", function()
    local f = fixture()
    f.values["hud.tfp_ammo_placement"] = 2
    f.metrics.width = 3000
    local c = f:tick()
    eq(c.valid, true)
    eq(c.has_strip, false)
    eq(type(c.strip_reason), "string")
    check_stack(f)
    near(column_center(f, "weapon"), column_center(f, "vitals"))
    eq(f:primitive("ammo").text, "32")
end)
print("TrueFP split anchors: " .. cases .. " cases / " .. checks .. " checks passed")
