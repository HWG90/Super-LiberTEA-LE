-- Actual Controller/Policy/Layout/Composition; native presenters are boundaries.
local Support = assert(loadfile("tests/support.lua"))()
local mod = Support.project()
local Controller = mod.require("hud/controller.lua")
local Schema = mod.require("settings/schema.lua")
local Screen = mod.require("render/screen_gui.lua")
local checks = 0
local function eq(a, b, why)
    checks = checks + 1
    assert(a == b, (why or "different") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, why)
    checks = checks + 1
    assert(math.abs(a - b) < 1e-6, (why or "different") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function fixture()
    local f = { events = {}, samples = 0, metrics = 0, packets = 0, renders = 0, clears = 0, viewports = 0, draws = {} }
    function f:event(name)
        self.events[#self.events + 1] = name
    end
    f.values = {}
    for _, row in ipairs(Schema.definitions) do
        f.values[row.id] = row.default
    end
    f.values["hud.density"], f.values["hud.anchor_damping_ms"] = 2, 0
    f.model = {
        known = true,
        identity = 65536,
        generation = 7,
        context = 777,
        in_mission = true,
        alive = true,
        hud_visible = true,
        menu_open = false,
        blocked = false,
        aim = { known = true, first_person = false, aiming = false, switching = false },
        reticle = { known = true, x = 960, y = 540 },
        anchors = {},
        health = 0.8,
        stamina = 0.6,
        stims = 2,
        throwables = 3,
        font = {},
        weapon = {
            known = true,
            count = 17,
            reserve = 5,
            reloading = false,
            changeable = { fire_mode = false, rpm = false, ammo_mode = false, zoom = false },
        },
        supply_icons = {},
    }
    for _, key in ipairs({ "stims", "throwables" }) do
        f.model.supply_icons[key] = {
            known = true,
            texture = "1234567890abcdef",
            width = 16,
            height = 12,
            identity = f.model.identity,
            generation = f.model.generation,
            context = f.model.context,
        }
    end
    f.core = {
        set_presentation = function()
            f:event("presentation")
            return true
        end,
        clear_layout = function(self)
            f:event("core.clear")
            f.clears = f.clears + 1
            if f.clear_throw then
                error("cooldown restore threw")
            end
            if f.clear_fail then
                return false, "cooldown retained"
            end
            self.layout_request = nil
            return true
        end,
        weapon_metrics = function()
            f.metrics = f.metrics + 1
            local cells = f.cells or 1
            return {
                ready = true,
                count = cells,
                width = cells * 22 + (cells - 1) * 5,
                height = 22,
                edge = 22,
                gap = 5,
                root = f.foreign_metrics and 1 or f.model.identity,
                generation = f.foreign_generation and 1 or f.model.generation,
                source_revision = 4,
            }
        end,
        cooldown_layout = function(_, options)
            f.packets = f.packets + 1
            local center = (options.combat_bounds.left + options.combat_bounds.right) / 2
            local top = options.combat_bounds.bottom - 12 * options.scale
            return {
                valid = true,
                identity = options.identity,
                generation = options.generation,
                has_content = f.cooldown_content == true,
                bounds = { left = center - 35, right = center + 35, bottom = top - 40, top = top },
                tiles = {},
                primitives = f.cooldown_content and {
                    {
                        key = "timer",
                        kind = "text",
                        x = center - 10,
                        y = top - 20,
                        size = 11,
                        text = "00:12",
                        tone = "text",
                        alpha = 1,
                        z = 951,
                    },
                } or {},
            }
        end,
        set_layout = function(self, spec, packet)
            f:event("core.place")
            f.placed_packet, f.placed_spec = packet, spec
            if f.place_fail then
                self.layout_request = { restore_pending = true, cooldowns = true }
                f.lease = self.layout_request
            end
            return not f.place_fail, "native placement refused"
        end,
    }
    f.supply = {
        prepare = function(self, model)
            f:event("supply.prepare")
            eq(model, f.model)
            self.ready = not f.unavailable
            return not f.prepare_fail, "old sprite owner retained"
        end,
        render = function(_, model, layout)
            f:event("supply.render")
            eq(model, f.model)
            f.icon_count = #(layout.supplies or {})
            return not f.icon_fail, "picture refused"
        end,
        hide = function()
            f:event("supply.hide")
            return not f.hide_fail, "sprite hide refused"
        end,
        close = function()
            f:event("supply.close")
            return not f.close_fail, "sprite release refused"
        end,
    }
    f.renderer = {
        viewport = function()
            f.viewports = f.viewports + 1
            return { width = 1920, height = 1080 }
        end,
        prepare = function()
            f:event("gui.prepare")
            return true
        end,
        measure = function(_, _, text, size)
            if f.measure_fail_after_restore and f.clears > 0 then
                return nil, "fallback measure unavailable"
            end
            return {
                left = 0,
                bottom = 0,
                right = #text * size * 0.5,
                top = size,
                width = #text * size * 0.5,
                height = size,
            }
        end,
        render = function(_, model, view, layout)
            f:event("gui.render")
            f.renders = f.renders + 1
            f.text = {}
            local draw = { model = model, view = view, primitives = {}, supplies = {} }
            for _, p in ipairs(layout.primitives) do
                f.text[p.key] = p.text
                local q = {}
                for key, value in pairs(p) do
                    q[key] = value
                end
                draw.primitives[#draw.primitives + 1] = q
            end
            for _, p in ipairs(layout.supplies or {}) do
                local q = {}
                for key, value in pairs(p) do
                    q[key] = value
                end
                draw.supplies[#draw.supplies + 1] = q
            end
            f.draws[#f.draws + 1] = draw
            return true
        end,
        hide = function()
            f:event("gui.hide")
            return true
        end,
        close = function()
            f:event("gui.close")
            return true
        end,
    }
    f.sampler = {
        sample = function()
            f.samples = f.samples + 1
            return f.model
        end,
        close = function()
            f:event("sampler.close")
            return true
        end,
    }
    local original_new = Screen.new
    Screen.new = function(deps)
        f.renderer.before_change = deps.before_change
        return f.renderer
    end
    f.hud = Controller.new({
        core = f.core,
        globals = {},
        sampler = f.sampler,
        supply_icons = f.supply,
        settings = {
            get = function(_, key)
                return f.values[key]
            end,
        },
    })
    Screen.new = original_new
    return f
end
local f = fixture()
eq(f.hud:update(0.016), true)
eq(f.icon_count, 2, "actual final Layout exports both sprites")
eq(f.text.stims, "2")
eq(f.text.throwables, "3")
eq(table.concat(f.events, ","), "presentation,supply.prepare,gui.prepare,gui.render,supply.render,core.place")
local owner = f.hud.supply_icons
f.events = {}
eq(f.hud:update(0.016), true)
eq(f.hud.supply_icons, owner, "unchanged frames retain the same native presenter")
eq(f.samples, 2)
eq(f.metrics, 2)
eq(f.packets, 2)
f = fixture()
f.unavailable = true
eq(f.hud:update(0.016), true)
eq(f.icon_count, 0)
eq(f.text.stims:find("STIM", 1, true) ~= nil, true)
f = fixture()
f.icon_fail = true
eq(f.hud:update(0.016), true, "native image refusal redraws descriptive count labels")
eq(f.renders, 2)
eq(f.text.stims:find("STIM", 1, true) ~= nil, true)
eq(f.samples, 1, "text fallback never samples again")
eq(f.metrics, 1, "text fallback reuses captured native metrics")
eq(f.packets, 1, "text fallback never recollects cooldowns")
eq(f.hud.supply_icons, f.supply)
f = fixture()
f.icon_fail, f.hide_fail = true, true
eq(f.hud:update(0.016), false)
eq(f.renders, 1, "refused sprite hide fences destructive label fallback")
eq(f.text.stims, "2")
eq(f.hud.supply_icons, f.supply, "refusal retains exact native owner")
f.hide_fail = false
eq(f.hud:update(0.016), true)
eq(f.text.stims:find("STIM", 1, true) ~= nil, true)
f = fixture()
f.prepare_fail = true
eq(f.hud:update(0.016), false)
eq(f.renders, 0)
eq(table.concat(f.events, ","), "presentation,supply.prepare")
f = fixture()
f.core.layout_request = { cooldowns = true }
eq(f.renderer.before_change(), true)
eq(table.concat(f.events, ","), "core.clear,supply.hide", "cooldowns restore before Gui dependency changes")
f.events, f.hide_fail = {}, true
eq(f.renderer.before_change(), false)
eq(table.concat(f.events, ","), "supply.hide")
f = fixture()
f.hide_fail = true
eq(f.hud:fallback("menu"), false)
eq(table.concat(f.events, ","), "core.clear,supply.hide", "failed hide retains Gui")
f = fixture()
f.clear_fail = true
eq(f.hud:close(), false)
eq(table.concat(f.events, ","), "core.clear")
f.clear_fail, f.close_fail, f.events = false, true, {}
eq(f.hud:close(), false)
eq(table.concat(f.events, ","), "core.clear,supply.close")
eq(f.hud.supply_icons, f.supply)
f.close_fail, f.events = false, {}
eq(f.hud:close(), true)
eq(table.concat(f.events, ","), "core.clear,supply.close,gui.close,sampler.close")
f.events = {}
eq(f.hud:close(), true)
eq(#f.events, 0)
for _, key in ipairs({ "foreign_metrics", "foreign_generation" }) do
    f = fixture()
    f[key] = true
    eq(f.hud:update(0.016), true)
    eq(f.placed_spec, nil, "foreign strip dimensions never reflow current Layout")
end
local function tfp_stack(q)
    local m = q.model
    q.values["hud.tfp_ammo_placement"], q.values["hud.anchor_damping_ms"] = 2, 80
    m.follow_token, m.anchor_context, m.anchor_camera = "actor/weapon", 80000, 90000
    m.aim.true_first_person, m.aim.true_first_person_token = true, "provider/1"
    m.aim.viewmodel_active, m.aim.viewmodel_unit, m.aim.weapon_unit = true, 42, 84
    m.anchors.tfp_vitals = {
        known = true,
        x = 740,
        y = 460,
        identity = m.identity,
        generation = m.generation,
        context = m.anchor_context,
        camera = m.anchor_camera,
        unit = 42,
        unit_domain = "fps",
        actor_id = 7,
        node = 8,
        token = "fps/current",
    }
    q.cells, q.cooldown_content, q.place_fail = 4, true, true
    local update = q.hud.layout.update
    q.hud.layout.update = function(self, ...)
        q:event("pure.layout")
        return update(self, ...)
    end
end
local function visual_center(q, draw, role)
    local left, right = math.huge, -math.huge
    for _, p in ipairs(draw.primitives) do
        if p.group == role and p.key:sub(1, 9) ~= "cooldown/" then
            local low, high = p.x, p.x + (p.width or 0)
            if p.kind == "text" then
                local ink = assert(q.renderer:measure(q.model.font, p.text, p.size))
                low, high = p.x + ink.left, p.x + ink.right
            end
            left, right = math.min(left, low), math.max(right, high)
        end
    end
    for _, p in ipairs(draw.supplies) do
        if (p.key == "heat" and "weapon" or "vitals") == role then
            left, right = math.min(left, p.x), math.max(right, p.x + p.width)
        end
    end
    assert(left < math.huge, "Missing visible column " .. role)
    return (left + right) / 2
end
local function event_index(events, name, nth)
    nth = nth or 1
    for i, event in ipairs(events) do
        if event == name then
            nth = nth - 1
            if nth == 0 then
                return i
            end
        end
    end
end
f = fixture()
tfp_stack(f)
local source_model, source_sampler, source_supply = f.model, f.sampler, f.supply
eq(f.hud:update(0.016), true)
eq(f.renders, 2)
eq(f.samples, 1, "handoff fallback never samples again")
eq(f.metrics, 1, "handoff fallback never obtains new native metrics")
eq(f.packets, 1, "handoff fallback never recollects cooldowns")
eq(f.viewports, 1, "handoff fallback reuses the captured viewport")
eq(f.hud.model, source_model)
eq(f.hud.sampler, source_sampler)
eq(f.hud.supply_icons, source_supply)
eq(f.hud.composition.has_strip, false, "recomposed text-only layout has no rejected native row")
eq(f.hud.composition.has_cooldowns, false, "restored native countdowns have no duplicate screen packet")
local first, final = f.draws[1], f.draws[2]
eq(first.model, source_model)
eq(final.model, source_model)
eq(
    math.abs(visual_center(f, first, "weapon") - visual_center(f, first, "vitals")) > 1,
    true,
    "fixture reproduces the strip-influenced visible-only center before handoff"
)
near(
    visual_center(f, final, "weapon"),
    visual_center(f, final, "vitals"),
    "refused four-cell103px row recomposes a square visible-only stack"
)
eq(f.text["cooldown/timer"], nil)
eq(f.icon_count, 2, "same captured native supplies move with the final recomposed bracket")
eq(
    event_index(f.events, "core.clear") < event_index(f.events, "pure.layout", 3),
    true,
    "positive restore ACK precedes every fallback geometry change"
)
eq(event_index(f.events, "pure.layout", 4) < event_index(f.events, "gui.render", 2), true)
eq(event_index(f.events, "gui.render", 2) < event_index(f.events, "supply.render", 2), true)
eq(event_index(f.events, "gui.prepare", 2), nil)
eq(event_index(f.events, "supply.prepare", 2), nil)
f = fixture()
tfp_stack(f)
f.place_fail = false
eq(f.hud:update(0.016), true)
f.model.anchors.tfp_vitals.x, f.model.anchors.tfp_vitals.y, f.place_fail = 840, 510, true
eq(f.hud:update(0.08), true)
local animated = f.draws[#f.draws]
for _, p in ipairs(animated.primitives) do
    if p.key == "health_track" then
        near(
            p.x + p.width / 2,
            644 + 100 * (1 - math.exp(-1)),
            "fallback composition cannot advance health damping twice"
        )
        near(p.y + p.height / 2, 460 + 50 * (1 - math.exp(-1)))
    end
end
near(visual_center(f, animated, "weapon"), visual_center(f, animated, "vitals"))
eq(f.samples, 2)
eq(f.metrics, 2)
eq(f.packets, 2)
eq(f.viewports, 2)
for _, failure in ipairs({ "clear_fail", "clear_throw" }) do
    f = fixture()
    tfp_stack(f)
    f[failure] = true
    eq(f.hud:update(0.016), false)
    eq(f.renders, 1, "unacknowledged native restore fences fallback redraw")
    eq(event_index(f.events, "pure.layout", 3), nil, "unacknowledged restore fences pure geometry mutation too")
    eq(f.core.layout_request, f.lease, "exact failed native placement ledger stays owned")
    eq(f.hud.supply_icons, f.supply)
    eq(f.hud.sampler, f.sampler)
    eq(f.hud.renderer, f.renderer)
    eq(f.hud.composition.has_strip, true, "original screen/native-dependent layout remains retained for retry")
    eq(event_index(f.events, "gui.hide"), nil)
    eq(f.samples, 1)
    eq(f.metrics, 1)
    eq(f.packets, 1)
end
f = fixture()
tfp_stack(f)
f.measure_fail_after_restore = true
eq(f.hud:update(0.016), true, "unknown recomposition safely returns to Original after positive restoration")
eq(f.renders, 1, "unknown fallback measurement never redraws stale strip-influenced geometry")
eq(event_index(f.events, "gui.hide") ~= nil, true)
eq(f.core.layout_request, nil)
eq(f.hud.status:find("fallback measure unavailable", 1, true) ~= nil, true)
eq(f.samples, 1)
eq(f.metrics, 1)
eq(f.packets, 1)
f = fixture()
tfp_stack(f)
f.icon_fail = true
eq(f.hud:update(0.016), true)
eq(f.icon_count, 0, "handoff fallback preserves the effective descriptive-supply state")
eq(f.text.stims:find("STIM", 1, true) ~= nil, true)
eq(f.samples, 1)
eq(f.metrics, 1)
eq(f.packets, 1)
print("Supply controller: " .. checks .. " checks passed")
