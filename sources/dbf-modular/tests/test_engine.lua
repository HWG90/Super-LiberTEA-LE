-- Actual App and HUD controller, pure policy/placement/layout, real console schema.
local Support = assert(loadfile("tests/support.lua"))()
local context, globals = Support.project()
local App = context.require("engine/app.lua")
local HUD = context.require("hud/controller.lua")
local Schema = context.require("settings/schema.lua")
-- Native supply sprites are an external boundary in these existing engine
-- fixtures. Their real controller lifecycle/refusal cases live in the focused
-- test_supply_controller suite; the presenter has its own actual-backend suite.
local function new_hud(deps)
    deps.supply_icons = deps.supply_icons
        or {
            ready = false,
            prepare = function()
                return true
            end,
            render = function()
                return true
            end,
            hide = function()
                return true
            end,
            close = function()
                return true
            end,
        }
    return HUD.new(deps)
end
local checks = 0
local function eq(a, b, why)
    checks = checks + 1
    assert(a == b, (why or "different") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function fixture(fail)
    local events, settings = {}, {}
    for _, row in ipairs(Schema.definitions) do
        settings[row.id] = row.default
    end
    local store = {
        get = function(_, id)
            return settings[id]
        end,
        set = function(_, id, v)
            settings[id] = v
            return true
        end,
    }
    local function event(name)
        events[#events + 1] = name
    end
    local core = {
        enable = function()
            event("core.enable")
            if fail == "enable" then
                return false, "native declined"
            end
            return true
        end,
        update = function()
            event("core.update")
            if fail == "update" then
                error("native unavailable")
            end
        end,
        services = function()
            return {}
        end,
    }
    local menu = {
        update = function()
            event("menu.update")
        end,
    }
    local hud = {
        update = function()
            event("hud.update")
        end,
        fallback = function()
            event("hud.fallback")
        end,
    }
    for name, owner in pairs({ store = store, menu = menu, core = core, hud = hud }) do
        owner.close = function()
            event(name .. ".close")
            return fail ~= name, fail == name and "refused" or nil
        end
    end
    local deps = {}
    for name, owner in pairs({ Store = store, Menu = menu, Core = core, HUD = hud }) do
        deps[name] = {
            new = function()
                return owner
            end,
        }
    end
    local c, g = Support.project()
    local released = 0
    local commands = assert(loadfile("reference/lll/commands.lua"))
    setfenv(
        commands,
        setmetatable({
            LLL_METADATA = {
                decode = function(v)
                    return v
                end,
            },
        }, { __index = _G })
    )
    local bus = commands().new()
    c.expose = function(namespace, fields)
        local release = bus.register(namespace, c, fields)
        return function()
            released = released + 1
            return release()
        end
    end
    return App.new(c, g, deps), events, g, bus, function()
        return released
    end
end
local app, events, g, bus, releases = fixture()
eq(app:enable(), true)
eq(g.DBFModular, app)
eq(#bus.list(), 93, "91settings, one compatibility alias and status use nested console schema")
local ok = bus.execute("dbf_modular.settings.hud.ads_expand = false")
eq(ok, true)
eq(app.store:get("hud.ads_minimal"), false)
app:update(0.016)
eq(table.concat(events, ","), "menu.update,core.enable,menu.update,core.update,hud.update", "single order")
eq(app:close(), true)
eq(table.concat(events, ",", 6), "hud.close,core.close,menu.close,store.close")
eq(g.DBFModular, nil)
eq(releases(), 1)
eq(#bus.list(), 0)
eq(app:close(), true)
eq(releases(), 1)
for _, name in ipairs({ "hud", "core", "menu", "store" }) do
    local a, e, gg = fixture(name)
    eq(a:enable(), true)
    local owner = a[name]
    eq(a:close(), false, name .. " refusal")
    eq(a[name], owner, "keep required owner")
    eq(gg.DBFModular, a, "keep global retention")
    local before = #e
    a:update(0.016)
    eq(#e, before, "no update during retirement")
    owner.close = function()
        return true
    end
    eq(a:close(), true, "retry cleanup")
end
local rejected, _, gg = fixture("enable")
eq(rejected:enable(), false)
eq(rejected.state, "closed")
eq(gg.DBFModular, nil)
local stopped, ee = fixture("update")
eq(stopped:enable(), true)
stopped:update(0.1)
eq(ee[#ee], "hud.fallback", "Core exception hides prior HUD")
eq(stopped:close(), true)
local collision, _, cg = fixture()
cg.DiversBestFriend = {}
eq(collision:enable(), false)
eq(cg.DBFModular, nil)
-- Actual HUD controller with native rendering/sampling as the external boundaries.
local values = {}
for _, row in ipairs(Schema.definitions) do
    values[row.id] = row.default
end
local settings = {
    get = function(_, id)
        return values[id]
    end,
}
values["hud.anchor_damping_ms"] = 0
local model = {
    known = true,
    identity = 1,
    generation = 1,
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
    weapon = {
        known = true,
        count = 17,
        reserve = 5,
        reloading = false,
        fire_mode = "AUTO",
        changeable = { fire_mode = true, rpm = false, ammo_mode = false, zoom = false },
    },
    font = {},
}
local sample_count, prepare_count, render_count = 0, 0, 0
local render_fail, prepare_fail, measure_fail, close_fail = false, false, false, false
local replacement_claims = false
local renderer = {
    viewport = function()
        return { width = 1920, height = 1080 }
    end,
    prepare = function()
        prepare_count = prepare_count + 1
        return not prepare_fail, "font unavailable"
    end,
    measure = function(_, _, text, size)
        if measure_fail then
            return nil, "measure unavailable"
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
    render = function(_, _, view, layout)
        render_count = render_count + 1
        eq(layout.valid, true)
        return not render_fail,
            render_fail and "draw refused" or { weapon_options = replacement_claims, cooldowns = replacement_claims }
    end,
    hide = function()
        return true
    end,
    close = function()
        return not close_fail, "live GUI"
    end,
}
local sampled_options
local sampler = {
    sample = function(_, _, options)
        sampled_options = { options.tfp_vitals_bone, options.tfp_ammo_bone, options.tfp_ammo_placement }
        sample_count = sample_count + 1
        return model
    end,
    close = function(self)
        self.closed = true
        return true
    end,
}
local last
local core = {
    set_presentation = function(_, p)
        last = { weapon_options = p.weapon_options, cooldowns = p.cooldowns }
    end,
}
local h = new_hud({ core = core, settings = settings, globals = globals, renderer = renderer, sampler = sampler })
eq(h:update(0.016), true)
eq(render_count, 1)
eq(last.weapon_options, true, "Quiet remains additive")
eq(last.cooldowns, true, "Quiet keeps Original cooldown settings")
eq(table.concat(sampled_options, ","), "1,1,1", "selected TrueFP defaults reach the one sampler")
values["hud.tfp_vitals_bone"], values["hud.tfp_ammo_bone"], values["hud.tfp_ammo_placement"] = 3, 2, 2
model.aim.aiming = true
eq(h:update(0.016), true)
eq(table.concat(sampled_options, ","), "3,2,2", "current independent selections reach the next frame")
values["hud.tfp_vitals_bone"], values["hud.tfp_ammo_bone"], values["hud.tfp_ammo_placement"] = 1, 1, 1
eq(h.view.details, false)
eq(h.view.quiet_aim, true)
eq(last.weapon_options, false)
eq(last.cooldowns, false)
replacement_claims = true
eq(h:update(0.016), true)
eq(last.weapon_options, false, "Quiet aiming intentionally hides routine strip information")
eq(last.cooldowns, false, "Quiet aiming intentionally hides routine cooldown information")
replacement_claims = false
model.weapon.changeable.zoom = true
model.weapon.zoom = nil
model.weapon.zoom_index = nil
h:update(0.016)
eq(last.weapon_options, false, "intentional Quiet hiding never falls back into viewport")
render_fail = true
h:update(0.016)
eq(last.weapon_options, true)
eq(last.cooldowns, true, "draw failure restores views")
render_fail = false
prepare_fail = true
h:update(0.016)
eq(last.weapon_options, true)
prepare_fail = false
measure_fail = true
local before = render_count
h:update(0.016)
eq(render_count, before, "invalid measurements never render")
measure_fail = false
model.menu_open = true
before = prepare_count
h:update(0.016)
eq(prepare_count, before, "selection supersedes HUD")
model.menu_open = false
values["hud.enabled"] = false
before = sample_count
h:update(0.016)
eq(sample_count, before, "disabled sampler idle")
close_fail = true
eq(h:close(), false)
eq(sampler.closed, nil, "retain sampler on GUI refusal")
close_fail = false
eq(h:close(), true)
eq(sampler.closed, true)
-- Inspect only registers its own optional unbound MBM action.
local ids = {}
local opts
globals.ModBindingsMenu = {
    api = 1,
    version = 4,
    register_binding = function(id, _, default, options)
        ids[#ids + 1] = id
        opts = options
        eq(default, nil)
        return true
    end,
    is_down = function(id)
        return id == "dbf_modular.inspect"
    end,
}
local hh = new_hud({ core = core, settings = settings, globals = globals, renderer = renderer, sampler = sampler })
eq(hh:inspect(), true)
eq(ids[1], "dbf_modular.inspect")
eq(#ids, 1)
eq(opts.backend, "native")
eq(hh:inspect(), true)
eq(#ids, 1)
local hides = 0
local broken = new_hud({
    core = {
        set_presentation = function()
            error("original view unavailable")
        end,
    },
    settings = settings,
    globals = globals,
    renderer = {
        hide = function()
            hides = hides + 1
            return true
        end,
    },
    sampler = sampler,
})
eq(broken:fallback("test"), false)
eq(hides, 1, "original fallback exception must not skip own GUI hide")
-- A second-pass validation failure must not claim suppression after a hide.
values["hud.enabled"] = true
local twice = new_hud({ core = core, settings = settings, globals = globals, renderer = renderer, sampler = sampler })
local real_layout = twice.layout
local passes = 0
twice.layout = {
    update = function(_, ...)
        passes = passes + 1
        local result = real_layout:update(...)
        if passes == 2 then
            result.valid = false
            result.reason = "translation refused"
        end
        return result
    end,
}
before = render_count
twice:update(0.016)
eq(render_count, before, "second-pass failure cannot become render success")
eq(last.weapon_options, true)
-- Actual descriptor acknowledges cleanup through the same retained owner on poll.
local polling, poll_events = fixture("hud")
local saved_new = App.new
App.new = function()
    return polling
end
local descriptor = App.descriptor(context, globals)
eq(descriptor.on_enable(), true)
App.new = saved_new
eq(descriptor.on_disable(), false)
eq(polling.state, "retiring")
local kept = polling.hud
eq(descriptor.on_cleanup_poll(), false)
eq(polling.hud, kept, "poll refusal retains actual HUD owner")
polling.hud.close = function()
    return true
end
eq(descriptor.on_cleanup_poll(), true)
eq(polling.state, "closed")
eq(descriptor.on_cleanup_poll(), true, "retired descriptor polling idempotent")
-- Actual composition/controller integrates native presenters, not copied readers.
model.menu_open = false
model.aim.aiming = false
model.health, model.stamina, model.stims, model.throwables = 1, 1, 4, 4
model.weapon.known, model.weapon.count = false, nil
values["hud.enabled"] = true
values["hud.density"] = 1
local native_calls, restores, collects = 0, 0, 0
local fail_native, dense = false, false
local last_packet, last_spec, last_keys, last_visible, last_positions, last_native_anchor
local old_render = renderer.render
renderer.render = function(self, m, v, g)
    last_keys, last_positions = {}, {}
    last_visible = v.visible
    for _, p in ipairs(g.primitives) do
        last_keys[p.key] = true
        last_positions[p.key] = {
            x = p.x,
            y = p.y,
            group = p.group,
            width = p.width,
            height = p.height,
            alpha = p.alpha,
            danger_mix = p.danger_mix,
        }
    end
    return old_render(self, m, v, g)
end
local integrated_core = {
    set_presentation = core.set_presentation,
    weapon_metrics = function(_, edge, gap)
        return {
            ready = true,
            count = 3,
            width = 3 * edge + 2 * gap,
            height = edge,
            edge = edge,
            gap = gap,
            root = 1,
            source_revision = 4,
        }
    end,
    cooldown_layout = function(_, options)
        collects = collects + 1
        local top = options.combat_bounds.bottom - 12 * options.scale
        return {
            valid = true,
            identity = options.identity,
            generation = options.generation,
            has_content = true,
            tile_count = 1,
            bounds = { left = -30, right = 30, top = top, bottom = top - (dense and 1500 or 60) },
            tiles = { {} },
            primitives = {
                {
                    key = "timer",
                    kind = "text",
                    x = 0,
                    y = top - 20,
                    text = "2:01",
                    size = 11,
                    tone = "text",
                    alpha = 0.5,
                    z = 951,
                    width = 0,
                    height = 0,
                },
            },
        }
    end,
    set_layout = function(_, spec, packet, anchor, opacity)
        native_calls = native_calls + 1
        last_packet, last_spec = packet, spec
        last_native_anchor = { x = anchor.x, y = anchor.y }
        eq(opacity, 0.94)
        if spec then
            eq(spec.root, 1)
            eq(spec.source_revision, 4)
        end
        return not fail_native, "native owner changed"
    end,
    clear_layout = function()
        restores = restores + 1
        return true
    end,
}
local integrated =
    new_hud({ core = integrated_core, settings = settings, globals = {}, renderer = renderer, sampler = sampler })
eq(integrated:update(0.016), true)
eq(integrated.view.visible, false, "healthy Quiet combat can be empty")
eq(integrated.view.eligible, true)
eq(last_visible, true, "original native content still participates")
eq(last_keys["cooldown/timer"], true)
eq(last_spec.x > 960, true)
eq(last_spec.y < 540, true)
eq(native_calls, 1)
eq(collects, 1, "one cached cooldown layout request")
model.aim.aiming = true
before = collects
local before_restore = restores
eq(integrated:update(0.016), true)
eq(integrated.view.quiet_aim, true)
eq(last.weapon_options, false)
eq(last.cooldowns, false)
eq(last_packet, nil)
eq(last_spec, nil)
eq(last_keys["cooldown/timer"], nil)
eq(collects, before, "hidden routine cooldowns do not request another layout")
eq(restores > before_restore, true, "native placement restored before Quiet hiding")
integrated.inspect = function()
    return true
end
eq(integrated:update(0.016), true)
eq(last.weapon_options, true)
eq(last.cooldowns, true)
eq(last_keys["cooldown/timer"], true, "inspection reveals existing native data")
integrated.inspect = function()
    return false
end
model.aim.aiming = false
integrated:update(0.016)
-- Actual controller: head in hipfire, weapon in TP aim, shared viewmodel in FP.
model.weapon.known, model.weapon.count = true, 17
model.health = 0.5
model.anchors = { body = { known = true, x = 800, y = 500 }, weapon = { known = true, x = 1100, y = 700 } }
values["hud.anchor"] = 1
eq(integrated:update(0.016), true)
eq(last_positions.ammo.x, 865, "hip ammo follows the head")
eq(last_positions.health_track.x, 655)
eq(last_positions.ammo.group, "weapon")
eq(last_positions.health_track.group, "vitals")
local old_ammo_y, old_vital_y = last_positions.ammo.y, last_positions.health_track.y
local old_timer_x, old_timer_y = last_positions["cooldown/timer"].x, last_positions["cooldown/timer"].y
local old_strip_x = last_spec.x
model.anchors.weapon.x, model.anchors.weapon.y = 1150, 730
eq(integrated:update(0.016), true)
eq(last_positions.ammo.x, 865, "hip ignores separate gun movement")
eq(last_positions.ammo.y, old_ammo_y)
eq(last_spec.x, old_strip_x)
eq(last_positions["cooldown/timer"].x, old_timer_x)
eq(last_native_anchor.x, 800)
eq(last_native_anchor.y, 500)
model.anchors.body.x, model.anchors.body.y = 770, 460
eq(integrated:update(0.016), true)
eq(last_positions.health_track.x, 625)
eq(last_positions.health_track.y, old_vital_y - 40)
eq(last_positions.ammo.x, 835)
eq(last_positions["cooldown/timer"].x, old_timer_x - 30)
eq(last_positions["cooldown/timer"].y, old_timer_y - 40)
values["hud.density"] = 2
model.aim.aiming = true
eq(integrated:update(0.016), true)
eq(last_positions.ammo.x, 1215, "TP aim moves ammo to the weapon bone")
eq(last_native_anchor.x, 770, "health-attached cooldowns still follow the player")
values["hud.cooldown_anchor"] = 2
eq(integrated:update(0.016), true)
eq(last_positions["cooldown/timer"].group, "weapon")
eq(last_native_anchor.x, 1150)
eq(last_native_anchor.y, 730)
local ammo_timer_x, ammo_timer_y = last_positions["cooldown/timer"].x, last_positions["cooldown/timer"].y
model.anchors.body.x, model.anchors.body.y = 750, 440
eq(integrated:update(0.016), true)
eq(last_positions["cooldown/timer"].x, ammo_timer_x)
eq(last_positions["cooldown/timer"].y, ammo_timer_y)
model.anchors.weapon.x, model.anchors.weapon.y = 1170, 720
eq(integrated:update(0.016), true)
eq(last_positions["cooldown/timer"].x, ammo_timer_x + 20)
eq(last_positions["cooldown/timer"].y, ammo_timer_y - 10)
eq(last_spec.x, last_native_anchor.x + 65)
model.aim.first_person = true
model.anchors.viewmodel = { known = true, x = 960, y = 900 }
eq(integrated:update(0.016), true)
eq(last_positions.ammo.x, 1061, "FP ammo has the wider fallback sight padding")
eq(last_positions.health_track.x, 772, "FP padding clears the stable open vitals bracket reservation")
eq(last_native_anchor.x, 996)
eq(last_native_anchor.y, 585, "native cooldowns share the sight-aligned ammo origin")
eq(last_positions.ammo.y + 15, model.reticle.y, "actual controller aligns measured ammo center with sights")
eq(
    last_positions.health_track.y + last_positions.health_track.height / 2,
    model.reticle.y,
    "actual controller aligns health bar center with sights"
)
local clearance_record = integrated.composition.sight_clearance
eq(clearance_record.source, "fallback")
model.follow_token, model.anchor_context, model.anchor_camera = "current-engine-owner", 81000, 80000
model.sight_clearance = {
    known = true,
    identity = model.identity,
    generation = model.generation,
    context = 81000,
    camera = 80000,
    follow_token = model.follow_token,
    source = "weapon_bounds",
    bounds = { left = 700, right = 1200, bottom = -500, top = 620 },
    unit_count = 1,
    polygons = {
        {
            { x = 700, y = -500 },
            { x = 1200, y = -500 },
            { x = 700, y = 620 },
            { x = 1200, y = 620 },
            { x = 700, y = -500 },
            { x = 1200, y = -500 },
            { x = 700, y = 620 },
            { x = 1200, y = 620 },
        },
    },
}
before = collects
eq(integrated:update(0.016), true)
eq(integrated.composition.sight_clearance, clearance_record, "live diagnostic record is retained")
eq(clearance_record.source, "weapon_bounds")
eq(clearance_record.known, true)
eq(last_positions.ammo.x, 1223)
eq(last_positions.health_track.x, 590)
eq(last_native_anchor.x, 1158, "native cooldown owner shares the adaptive ammo rail")
eq(last_positions["cooldown/timer"].x, last_native_anchor.x)
eq(last_spec.x, last_native_anchor.x + 65)
eq(collects, before + 1, "adaptive spacing never creates another cooldown collector")
eq(last_positions.ammo.y + 15, model.reticle.y)
eq(last_positions.health_track.y + last_positions.health_track.height / 2, model.reticle.y)
model.sight_clearance.generation = 0
eq(integrated:update(0.016), true)
eq(clearance_record.source, "fallback", "stale native geometry cannot move current readouts")
eq(last_positions.ammo.x, 1061)
eq(last_positions.health_track.x, 772)
model.sight_clearance.generation = model.generation
model.weapon.ammo_kind, model.weapon.heat, model.weapon.count = "heat", 0.5, nil
values["hud.heat_display"] = 2
eq(integrated:update(0.016), true)
eq(last_keys.ammo, nil, "bar-only mode removes the percentage primitive")
eq(last_keys.heat_track, true)
eq(last_positions.heat_track.y + 4, model.reticle.y, "actual controller aligns bar-only primary with sights")
eq(clearance_record.source, "weapon_bounds")
eq(last_spec.x, integrated.composition.anchors.weapon.x + 65, "heat modes retain the Original option strip")
eq(last_native_anchor.x, integrated.composition.anchors.weapon.x)
eq(last_native_anchor.y, integrated.composition.anchors.weapon.y)
values["hud.heat_display"] = 3
eq(integrated:update(0.016), true)
eq(last_keys.ammo, true)
eq(last_keys.heat_track, true)
eq(last_positions.ammo.y + 15, model.reticle.y, "hybrid retains the percentage as primary")
eq(last_positions.heat_track.y + 8 < model.reticle.y, true, "hybrid bar hangs below the primary")
values["hud.heat_bar_vertical"], values["hud.heat_display"] = true, 2
for _, heat in ipairs({ 0, 0.6, 1 }) do
    model.weapon.heat = heat
    eq(integrated:update(0.016), true)
    eq(last_keys.ammo, nil)
    eq(last_positions.heat_track.width, 8)
    eq(last_positions.heat_track.height, 80)
    eq(last_positions.heat_fill.width, 8)
    eq(last_positions.heat_fill.height, 80 * heat)
    eq(last_positions.heat_fill.y, last_positions.heat_track.y, "portrait heat fills bottom to top")
    eq(last_positions.heat_track.y + 40, model.reticle.y, "portrait primary stays sight centered")
    eq(clearance_record.source, "weapon_bounds")
    eq(last_native_anchor.x, integrated.composition.anchors.weapon.x)
    eq(last_native_anchor.y, integrated.composition.anchors.weapon.y)
    eq(last_positions["cooldown/timer"].y, last_packet.primitives[1].y + last_native_anchor.y)
end
values["hud.heat_display"] = 3
eq(integrated:update(0.016), true)
eq(last_keys.ammo, true)
eq(last_positions.ammo.y + 15, model.reticle.y)
eq(last_positions.heat_track.y + 40, model.reticle.y, "portrait Hybrid is beside the percentage")
eq(last_positions.heat_track.x > last_positions.ammo.x + 60, true)
eq(last_positions.heat_label.y > last_positions.heat_track.y + 80, true)
eq(last_positions.reserve.y + 11 < last_positions.heat_track.y, true)
values["hud.heat_display"] = 1
eq(integrated:update(0.016), true)
eq(last_keys.heat_track, nil, "portrait toggle never changes Percentage mode")
values["hud.heat_bar_vertical"], values["hud.heat_display"] = false, 3
model.weapon.heat = nil
eq(integrated:update(0.016), true)
eq(last_keys.ammo, nil)
eq(last_keys.heat_track, nil, "unknown heat cannot retain a stale bar")
model.weapon.ammo_kind, model.weapon.heat, model.weapon.count = nil, nil, 17
values["hud.heat_display"] = 1
model.sight_clearance, model.follow_token, model.anchor_context, model.anchor_camera = nil, nil, nil, nil
values["hud.cooldown_anchor"], values["hud.density"] = 1, 1
model.aim.aiming, model.aim.first_person = false, false
model.anchors = {}
model.weapon.known, model.weapon.count = false, nil
model.health = 1
fail_native = true
before = render_count
eq(integrated:update(0.016), true)
eq(render_count, before + 2, "native refusal immediately rerenders main HUD without exported labels")
eq(last_keys["cooldown/timer"], nil)
eq(restores > 0, true, "original placement restored after native refusal")
fail_native = false
dense = true
before = native_calls
eq(integrated:update(0.016), true)
eq(last_packet, nil, "oversized original overview keeps viewport placement")
eq(last_keys["cooldown/timer"], nil)
eq(native_calls, before + 1)
dense = false
render_fail = true
before = native_calls
integrated:update(0.016)
eq(native_calls, before, "screen GUI failure never moves native presenters")
render_fail = false
values["hud.enabled"] = false
before = restores
integrated:update(0.016)
eq(restores, before + 1, "HUD Off returns original placement immediately")
-- Shared labels cannot retire while native icons still depend on them.
local released_gui, released_sampler = 0, 0
local allow_restore = false
local dependent = new_hud({
    core = {
        clear_layout = function()
            return allow_restore, "native placement retained"
        end,
    },
    settings = settings,
    globals = {},
    renderer = {
        close = function()
            released_gui = released_gui + 1
            return true
        end,
    },
    sampler = {
        close = function()
            released_sampler = released_sampler + 1
            return true
        end,
    },
})
eq(dependent:close(), false)
eq(released_gui, 0, "native restore refusal retains shared labels")
eq(released_sampler, 0, "native restore refusal retains dependencies")
allow_restore = true
eq(dependent:close(), true)
eq(released_gui, 1)
eq(released_sampler, 1)
eq(dependent:close(), true)
eq(released_gui, 1, "successful close remains idempotent")
-- Refused viewport restoration also retains labels on fallback/update paths.
local hidden_pending, prepared_pending = 0, 0
local pending_core = {
    layout_request = { restore_pending = true },
    clear_layout = function()
        return false, "held owner"
    end,
}
local pending = new_hud({
    core = pending_core,
    settings = settings,
    globals = {},
    sampler = sampler,
    renderer = {
        hide = function()
            hidden_pending = hidden_pending + 1
            return true
        end,
        viewport = function()
            prepared_pending = prepared_pending + 1
            return { width = 1920, height = 1080 }
        end,
    },
})
eq(pending:fallback("unknown"), false)
eq(hidden_pending, 0, "fallback retains labels while native restore refuses")
eq(pending:update(0.016), false)
eq(prepared_pending, 0, "pending restore fences all new screen geometry")
print("Engine and controller: " .. checks .. " checks passed")
