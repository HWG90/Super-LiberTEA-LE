local Addons = require("core.addons")
local Dependencies = require("core.dependencies")
local Settings = require("core.settings")
local Product = {}
Product.__index = Product
Product.blocked = Dependencies.blocked
function Product.new(access, n, settings, report, parts, graph)
    local okay, why = access.read:status()
    assert(okay, why)
    parts = parts or {}
    report = report or function() end
    local blocked, off = Product.blocked(graph), {}
    local function need(module, ...)
        if blocked[module] then
            error("core-missing:" .. module, 0)
        end
        return require(module).new(...)
    end
    local function make(module, ...)
        for i = 1, select("#", ...) do
            if select(i, ...) == off then
                return off
            end
        end
        if blocked[module] then
            report({ event = "feature", id = module:match("[%w_]+$"), action = "off" })
            return off
        end
        return require(module).new(...)
    end
    local function on(value)
        if value ~= off then
            return value
        end
    end
    settings = settings or Settings.new(Addons.options(require("game.options"), parts))
    local panel = need("game.panel", access.read, n)
    local ui = need("game.ui", access, n)
    local weapon = need("game.weapon", access.read, access.call.judge, n)
    local options = need("game.weapon_options", weapon)
    local equipment = need("game.equipment", weapon, options)
    local inputs = need("game.world_inputs", weapon)
    local trajectory = make("features.trajectory", weapon, equipment, panel)
    local delivery = make("game.delivery", weapon)
    local choice = {}
    local approach = make("game.eagle_heading", access, weapon)
    local maps = not blocked["game.resource_inputs"]
    local addons = Addons.new(parts, {
        widgets = function(resources)
            return ui:public(resources)
        end,
        map = maps and function(wrap)
            return require("game.resource_inputs").new(weapon, panel):public(wrap)
        end or false,
        approach = approach ~= off and function()
            return approach:public()
        end or false,
    }, report)
    local comms = make("game.comms_row", access, n, ui)
    local ring = make("game.comms_inputs", weapon)
    local pick = on(make("game.stratagem_pick", ui, weapon))
    return setmetatable({
        panel = panel,
        weapon = weapon,
        settings = settings,
        options = options,
        equipment = equipment,
        menu = on(make("features.menu", ui, settings, report, parts)),
        addons = addons,
        ring = on(ring),
        squad = on(make("features.squad", ui, weapon, ring)),
        call_colour = on(make("features.call_colour", ui, weapon, ring)),
        kill_pulse = on(make("features.kill_pulse", ui, panel)),
        corpse = on(make("features.corpse", comms, weapon, report)),
        reinforce = on(make("features.reinforce", comms, weapon, report)),
        reticle = on(make("features.reticle", access, n)),
        attack = on(make("features.attack", weapon, panel, trajectory, delivery)),
        ground = on(make("game.decal", access, n)),
        ground_rows = {},
        delivery = on(delivery),
        choice = choice,
        approach = on(approach),
        report = report,
        inputs = inputs,
        trajectory = on(trajectory),
        distance = on(make("features.throw_distance", ui, access.call.judge, panel, trajectory, inputs)),
        slots = { {}, {}, {} },
        pick = pick,
        world_hud = on(
            make(
                "features.world_hud",
                ui,
                access.call.world,
                panel,
                weapon,
                equipment,
                inputs,
                addons:slot("stratagem"),
                pick
            )
        ),
        weapon_hud = on(make("features.weapon_hud", panel, make("game.weapon_line", ui))),
    }, Product)
end
function Product:step(dt)
    -- Synchronize frame caches, settings and menu state before sampling game data.
    self.dt = dt
    self.weapon:frame()
    if self.ring ~= nil then
        self.ring:frame()
    end
    self.settings:poll()
    local menu = self.menu
    if menu ~= nil then
        menu:before()
        self.menu_outermost = menu.outermost
    end
    local values = self.settings.values
    if self.pick ~= nil then
        self.pick:frame(values["hud.stratagem3d.pick_remember"] == 1)
    end
    if self.reticle ~= nil then
        self.reticle:step(values["game.reticle"] == 1, self.report)
    end
    local needs = self.addons:prepare(values)

    -- Determine feature demand and handle mission entry, exit or map-only frames.
    local hud, world, weapon = self.weapon_hud, self.world_hud, self.weapon
    local ammo, functions =
        hud ~= nil and values["hud.ammo.ammo"] == 1, hud ~= nil and values["hud.ammo.functions"] == 1
    local fire_mode, zeroing =
        hud ~= nil and values["hud.ammo.fire_mode"] == 1, hud ~= nil and values["hud.ammo.zeroing"] == 1
    local world_on = world ~= nil and world:wanted(values)
    local trajectory, inputs, attack = self.trajectory, self.inputs, self.attack
    local trajectory_on = trajectory ~= nil and trajectory:wanted(values)
    local attack_on = attack ~= nil and values["hud.attack_area"] ~= 0
    local delivery = self.delivery
    local delivery_on = delivery ~= nil and needs.delivery == true
    local squad, pulse, corpse, reinforce = self.squad, self.kill_pulse, self.corpse, self.reinforce
    local squad_on = squad ~= nil and values["hud.squad"] == 1
    local pulse_on = pulse ~= nil and values["hud.kill_pulse"] == 1
    local corpse_on = corpse ~= nil and values["hud.corpse"] == 1
    local reinforce_on = reinforce ~= nil and values["hud.reinforce"] == 1
    local call_colour = self.call_colour
    local colour_on = call_colour ~= nil and values["hud.call_colour"] == 1
    local hud_wanted = ammo
        or functions
        or fire_mode
        or zeroing
        or world_on
        or trajectory_on
        or attack_on
        or delivery_on
        or squad_on
        or pulse_on
        or corpse_on
        or reinforce_on
        or colour_on
    local wanted = hud_wanted or needs.map == true
    local restoring = hud ~= nil and hud.width_state ~= nil
    local colour_held = call_colour ~= nil and call_colour:held()
    self.panel:observe(wanted or restoring or colour_held, hud_wanted or restoring or colour_held)
    local previous = self.mission_active
    local active = wanted and (self.panel.in_mission == true or (self.panel.in_mission == nil and previous ~= nil))
    if active then
        self.mission_active = hud_wanted and "hud" or "map"
        if not hud_wanted and previous ~= "hud" then
            local choice = self.choice
            choice.mission, choice.editable = self.panel.ready, self.panel.editable
            choice.holding, choice.id, choice.avatar, choice.eligible, choice.degrees, choice.world =
                nil, nil, nil, nil, nil, nil
            choice.kind = nil
            self.addons:sample(choice)
            self.addons:finish(choice)
            if restoring then
                hud:restore()
            end
            return
        end
        if not hud_wanted and self.approach ~= nil then
            self.approach:clear()
        end
    else
        if previous == nil then
            if restoring then
                hud:restore()
            end
            return
        end
        self.mission_active = nil
        self.addons:leave()
        if self.pick ~= nil then
            self.pick:leave()
        end
        if self.approach ~= nil then
            self.approach:clear()
        end
        if previous ~= "hud" then
            if restoring then
                hud:restore()
            end
            return
        end
    end
    -- Share avatar and scene samples across the independent HUD features.
    if pulse ~= nil then
        pulse:step(pulse_on)
    end
    local due = hud ~= nil and hud:prepare(ammo, functions, fire_mode, zeroing)
    local avatar, seated, seat_row, wield, player, players
    if due or world_on or trajectory_on or attack_on or delivery_on or corpse_on then
        avatar, player, players = weapon:avatar(self.panel)
        if world_on or (due and ammo) then
            seated, seat_row = weapon:seated(avatar)
        end
    end
    inputs:observe(
        self.panel,
        avatar,
        world_on or trajectory_on or attack_on or delivery_on,
        squad_on or corpse_on,
        corpse_on and corpse:pending()
    )
    if squad ~= nil then
        squad:step(self.panel, squad_on, avatar, player, players, inputs.dead)
    end
    if call_colour ~= nil then
        call_colour:step(colour_on, self.panel.editable)
    end
    if corpse ~= nil then
        corpse:step(corpse_on, self.panel.in_mission, avatar, players, inputs.dead, inputs.landed)
    end
    if reinforce ~= nil then
        reinforce:step(reinforce_on, self.panel, players)
    end
    inputs:scene((trajectory_on or attack_on or delivery_on) and self.panel.ready)
    local flight_due = trajectory_on and trajectory:awake(inputs)
    local weapon_world, action_world
    if world ~= nil then
        weapon_world, action_world = world:begin(values)
    end
    -- Resolve equipment and addon guide demand before sampling weapon content.
    self.equipment:select(
        avatar,
        weapon_world
            or flight_due
            or (world ~= nil and world.ball_needed)
            or ((attack_on or delivery_on) and inputs.holding)
    )
    local choice = self.choice
    local cell
    if (attack_on or delivery_on) and inputs.holding then
        cell = self.equipment.cell
    end
    if delivery ~= nil then
        delivery:observe(cell, inputs.world)
    end
    local guide
    if attack ~= nil then
        guide = attack:prepare(attack_on, inputs)
        attack:observe(values["hud.attack_area"], self.panel.dt)
    end
    choice.mission, choice.editable = self.panel.ready, self.panel.editable
    choice.holding, choice.id, choice.avatar = inputs.holding, self.equipment.cell, avatar
    choice.eligible, choice.degrees, choice.world =
        delivery and delivery.eagle, delivery and delivery.degrees, inputs.world
    choice.kind = delivery and delivery.kind
    if active then
        self.addons:sample(choice)
    end
    guide = guide or needs.guide
    inputs:view((trajectory_on or attack_on or guide) and self.panel.ready)
    flight_due = flight_due or guide
    inputs:sample(action_world, trajectory ~= nil and flight_due and self.panel.ready and inputs.world ~= nil)
    if world_on or flight_due or (due and (seated or functions or fire_mode or zeroing)) then
        wield = weapon:wield(avatar)
    end
    local options_input, equipment_input
    if weapon_world or flight_due or (due and (functions or fire_mode or zeroing)) then
        options_input = self.options
        options_input:observe(wield)
    elseif hud == nil or not hud.visible then
        self.options:clear()
    end
    self.equipment:observe(inputs, wield, weapon_world or flight_due)
    if weapon_world or flight_due then
        equipment_input = self.equipment
    end
    local aim_reload = world_on and inputs.ready == true and inputs.third_person == true and inputs.aiming == true
    local fired = weapon_world or aim_reload
    local reloading
    if fired then
        self.equipment:firing(avatar)
        reloading = world.weapon_view.reload:select(self.equipment.fire)
    end
    local slots = self.slots
    if (due and functions) or (weapon_world and values["hud.weapon3d.functions"] == 1) then
        slots[1][1], slots[1][2], slots[1][3] = self.options:sample(1, equipment_input)
    end
    if (due and fire_mode) or (weapon_world and values["hud.weapon3d.fire_mode"] == 1) then
        slots[2][1], slots[2][2], slots[2][3] = self.options:sample(2)
    end
    if (due and zeroing) or (weapon_world and values["hud.weapon3d.zeroing"] == 1) then
        slots[3][1], slots[3][2], slots[3][3] = self.options:sample(3)
    end
    -- Build both HUD presentations from the same ammunition and equipment samples.
    local count, picked, record, heat
    if due and ammo then
        heat, picked, record = weapon:heat_index(self.panel, avatar, seated, wield, options_input, equipment_input)
    end
    local sample = self.panel:events(values, world ~= nil and world.ready, due and ammo and heat == nil)
    local content = world ~= nil
        and world:prepare(values, avatar, seated, seat_row, wield, player, players, reloading, slots, sample)
    if content and not (due and ammo) then
        heat, picked, record = weapon:heat_index(self.panel, avatar, seated, wield, options_input, equipment_input)
    end
    local ammunition = sample and sample.ammo
    local fuse
    if (content and values["hud.weapon3d.arc"] == 1 and ammunition.throwing) or (flight_due and inputs.holding) then
        fuse = self.equipment.throwable:remaining(self.equipment.cell)
    end
    if flight_due and not fired then
        self.equipment:firing(avatar)
    end
    if content then
        if heat ~= nil then
            ammunition.count = nil
        end
        ammunition.text = ammunition.throwables
        if ammunition.text == nil then
            ammunition.text = ammunition.count
        end
    end
    if due and ammo then
        if ammunition ~= nil and heat == nil then
            count = ammunition.count
        end
    end
    if content then
        world.weapon_view:content(values, inputs, picked, record, ammunition, slots, fuse, reloading)
    end
    if due then
        hud:put(count, slots)
    end
    if hud ~= nil then
        hud:finish()
    end
    if world ~= nil then
        world:finish(values)
    end
    -- Update ground previews, then complete addon work for the current frame.
    local ground = self.ground
    local drawn = ground ~= nil
        and self.panel.ready
        and inputs.world ~= nil
        and ((trajectory ~= nil and trajectory:draws(values)) or attack_on)
    local clock = drawn and self.panel:clock() or nil
    if trajectory ~= nil then
        trajectory:step(values, inputs, fuse, guide, clock)
    end
    if attack ~= nil then
        attack:step(inputs, needs.heading)
    end
    if drawn then
        self:draw(inputs, clock)
    elseif ground ~= nil then
        ground:close()
    end
    if self.distance ~= nil then
        self.distance:step(values)
    end
    if self.approach ~= nil then
        if needs.pending then
            self.approach:track(
                inputs.world,
                inputs.holding,
                self.equipment.cell,
                trajectory and trajectory.flight and trajectory.flight.finish,
                players ~= nil and weapon:local_key(players) or nil
            )
        else
            self.approach:clear()
        end
    end
    if active then
        self.addons:finish(choice)
    end
end
function Product:draw(inputs, clock)
    local rows, trajectory, attack = self.ground_rows, self.trajectory, self.attack
    for index = #rows, 1, -1 do
        rows[index] = nil
    end
    if trajectory ~= nil then
        rows[1] = trajectory.row
    end
    if attack ~= nil then
        for _, row in ipairs(attack.rows) do
            rows[#rows + 1] = row
        end
    end
    self.ground:step(
        inputs.world,
        clock,
        trajectory and trajectory.observer,
        rows,
        trajectory and trajectory.shot,
        inputs.eye
    )
end
function Product:after(completed)
    if self.menu == nil then
        return
    end
    self.menu:after(self.dt, completed)
    self.menu_outermost = self.menu.outermost
end
function Product:close()
    local failures = {}
    local function finish(owner, method, ...)
        if owner == nil then
            return true
        end
        local okay, why = pcall(owner[method], owner, ...)
        if not okay then
            failures[#failures + 1] = tostring(why)
        end
        return okay
    end
    finish(self.menu, "close")
    finish(self.pick, "reset")
    finish(self.reticle, "step", false, self.report)
    finish(self.addons, "close")
    finish(self.squad, "close")
    finish(self.kill_pulse, "close")
    finish(self.corpse, "close")
    finish(self.reinforce, "close")
    if finish(self.panel, "observe") then
        finish(self.weapon_hud, "close")
        finish(self.world_hud, "close")
        finish(self.call_colour, "step", false, self.panel.editable)
    end
    finish(self.trajectory, "close")
    finish(self.attack, "close")
    finish(self.ground, "close")
    finish(self.delivery, "clear")
    finish(self.distance, "close")
    finish(self.options, "clear")
    finish(self.approach, "clear")
    if #failures > 0 then
        error(table.concat(failures, "\n"), 0)
    end
end
return Product
