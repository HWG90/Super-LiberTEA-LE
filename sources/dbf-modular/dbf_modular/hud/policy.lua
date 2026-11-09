-- Pure contextual policy. Reuses view/slot records; all times are seconds.
-- view: visible,profile(hip/aim/first_person),details,opacity,font;
-- weapon{visible,text,kind,fill,tone,heat_bar,capacity,reserve,options,options_complete}.
-- Heat is displayed only from explicit native classification + normalized heat;
-- generic remaining is never reinterpreted as heat or a reload instruction.
-- health/stamina{visible,fill,text,tone}, stims/throwables{visible,text,tone},
-- reload{visible,text,tone},ready{visible,text,tone},weapon_options,cooldowns.
local Policy = {}
Policy.__index = Policy
local SLOTS = { "weapon", "health", "stamina", "stims", "throwables", "reload", "ready" }
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function ratio(value)
    return finite(value) and value >= 0 and value <= 1 and value or nil
end
local function count(value)
    return finite(value) and value >= 0 and value <= 1000000 and value % 1 == 0 and value or nil
end
local function get(settings, id, default)
    local value = settings and settings:get(id)
    if value == nil then
        return default
    end
    return value
end
local function slot()
    return { visible = false, tone = "text" }
end
function Policy.new()
    return setmetatable({
        view = {
            weapon = slot(),
            health = slot(),
            stamina = slot(),
            stims = slot(),
            throwables = slot(),
            reload = slot(),
            ready = slot(),
        },
        clock = 0,
        heat_warning = { phase = 0, active = false },
        previous_rows = {},
        current_rows = {},
    }, Policy)
end
function Policy:reset_heat_warning()
    local state = self.heat_warning
    state.phase, state.active, state.entity, state.resource, state.follow = 0, false, nil, nil, nil
end
function Policy:reset()
    self:reset_heat_warning()
    self.health_on, self.stamina_on, self.critical = false, false, false
    self.health_hold, self.stamina_hold = 0, 0
    self.last_stamina, self.last_stims, self.last_throwables = nil, nil, nil
    self.last_health, self.damage_until = nil, 0
    self.stim_until, self.throwable_until, self.ready_until, self.ready_count = 0, 0, 0, 0
    for key in pairs(self.previous_rows) do
        self.previous_rows[key] = nil
    end
    for key in pairs(self.current_rows) do
        self.current_rows[key] = nil
    end
end
function Policy:update_heat_warning(model, weapon, heat, dt)
    local state = self.heat_warning
    local entity, resource, follow = weapon.entity or weapon.id, weapon.identity, model.follow_token
    if not state.active or state.entity ~= entity or state.resource ~= resource or state.follow ~= follow then
        state.phase = 0
    end
    state.active, state.entity, state.resource, state.follow = true, entity, resource, follow
    local progress = math.max(0, math.min(1, (heat - 0.6) / 0.4))
    local frequency = 1.5 + 4.5 * progress
    state.phase = (state.phase + dt * frequency) % 1
    self.view.weapon.heat_warning_mix = 0.15 + 0.85 * progress
    self.view.weapon.heat_pulse = 0.625 + 0.375 * math.cos(state.phase * math.pi * 2)
end
function Policy:ready(model)
    local rows = model.cooldowns
    if type(rows) ~= "table" then
        for key in pairs(self.previous_rows) do
            self.previous_rows[key] = nil
        end
        return
    end
    rows = rows.rows or rows
    local current, previous, newly_ready = self.current_rows, self.previous_rows, 0
    for key in pairs(current) do
        current[key] = nil
    end
    for _, row in ipairs(rows) do
        if row.kind ~= nil and row.entry ~= nil then
            local key = tostring(row.entry) .. ":" .. tostring(row.kind)
            local cooling = row.timer_kind == "cooldown" and finite(row.timer_seconds) and row.timer_seconds > 0
            local ready = row.timer_kind == nil and row.unavailable == false
            if ready and previous[key] == true then
                newly_ready = newly_ready + 1
            end
            current[key] = cooling == true
        end
    end
    self.previous_rows, self.current_rows = current, previous
    if newly_ready > 0 then
        self.ready_count = (self.ready_until > self.clock and self.ready_count or 0) + newly_ready
        self.ready_until = self.clock + 1.6
    end
end
function Policy:update(model, settings, dt, inspect)
    dt = finite(dt) and math.max(0, math.min(dt, 1)) or 0
    self.clock = self.clock + dt
    local view = self.view
    view.visible, view.details, view.weapon_options, view.cooldowns, view.eligible = false, false, false, false, false
    view.quiet_aim, view.native_options, view.native_cooldowns = false, true, true
    for _, name in ipairs(SLOTS) do
        local item = view[name]
        item.visible, item.text, item.fill, item.tone = false, nil, nil, "text"
    end
    view.weapon.capacity, view.weapon.reserve, view.weapon.options, view.weapon.options_complete, view.weapon.kind =
        nil, nil, nil, false, nil
    view.weapon.heat_bar = false
    view.weapon.heat_warning_mix, view.weapon.heat_pulse = 0, 1
    view.profile, view.font = nil, model and model.font
    local aim = model and model.aim
    if
        not model
        or model.known ~= true
        or model.in_mission ~= true
        or model.alive ~= true
        or model.hud_visible ~= true
        or model.menu_open ~= false
        or model.blocked ~= false
        or get(settings, "hud.enabled", true) ~= true
        or not aim
        or aim.known ~= true
        or type(aim.first_person) ~= "boolean"
        or type(aim.aiming) ~= "boolean"
    then
        self:reset()
        return view
    end
    view.eligible = true
    if self.generation ~= model.generation or self.identity ~= model.identity then
        self:reset()
        self.generation, self.identity = model.generation, model.identity
    end
    view.profile = (aim.first_person or (aim.aiming and aim.viewmodel_active == true)) and "first_person"
        or aim.aiming and "aim"
        or "hip"
    view.details = get(settings, "hud.density", 1) == 2 or inspect == true
    view.quiet_aim = view.profile ~= "hip" and not view.details and get(settings, "hud.ads_minimal", true) == true
    view.native_options, view.native_cooldowns = not view.quiet_aim, not view.quiet_aim
    local opacity = get(settings, "hud.opacity", 94)
    view.opacity = finite(opacity) and math.max(0, math.min(1, opacity / 100)) or 0.94
    local health, stamina = ratio(model.health), ratio(model.stamina)
    if health and self.last_health and self.last_health - health > 0.003 then
        self.damage_until = self.clock + 1.2
    end
    self.last_health = health
    if health == nil then
        self.health_on, self.critical, self.health_hold = false, false, 0
    else
        if health <= 0.25 then
            self.critical = true
        elseif health > 0.30 then
            self.critical = false
        end
        if health < 0.995 then
            self.health_on, self.health_hold = true, 0
        elseif self.health_on and health >= 0.999 then
            self.health_hold = self.health_hold + dt
            if self.health_hold >= 0.6 then
                self.health_on = false
            end
        else
            self.health_hold = 0
        end
        view.health.visible, view.health.fill = self.health_on or self.critical or view.details, health
        view.health.text = (self.critical or view.details) and tostring(math.floor(health * 100 + 0.5)) or nil
        view.health.tone = self.critical and "danger" or "text"
    end
    if stamina == nil then
        self.stamina_on, self.stamina_hold = false, 0
    else
        local draining = self.last_stamina ~= nil and self.last_stamina - stamina >= 0.004
        if stamina < 0.97 or draining then
            self.stamina_on, self.stamina_hold = true, 0
        elseif self.stamina_on and stamina >= 0.995 then
            self.stamina_hold = self.stamina_hold + dt
            if self.stamina_hold >= 0.6 then
                self.stamina_on = false
            end
        else
            self.stamina_hold = 0
        end
        view.stamina.visible, view.stamina.fill, view.stamina.tone =
            self.stamina_on or view.details, stamina, "text_dim"
    end
    self.last_stamina = stamina
    local stims, throwables = count(model.stims), count(model.throwables)
    if stims ~= nil and self.last_stims ~= nil and stims ~= self.last_stims then
        self.stim_until = self.clock + 2
    end
    if throwables ~= nil and self.last_throwables ~= nil and throwables ~= self.last_throwables then
        self.throwable_until = self.clock + 2
    end
    view.stims.visible = stims ~= nil and (view.details or self.health_on or stims <= 1 or self.stim_until > self.clock)
    view.stims.text, view.stims.tone = stims and "STIM " .. stims or nil, stims == 0 and "danger" or "text_dim"
    view.throwables.visible = throwables ~= nil
        and not (model.weapon and model.weapon.throwing == true and model.weapon.known == true and count(
            model.weapon.count
        ) ~= nil)
        and (view.details or throwables <= 1 or self.throwable_until > self.clock)
    view.throwables.text = throwables and "G " .. throwables or nil
    view.throwables.tone = throwables == 0 and "yellow" or "text_dim"
    self.last_stims, self.last_throwables = stims, throwables
    local weapon, item = model.weapon or {}, view.weapon
    local heat_warning = false
    if weapon.known == true then
        local amount, remaining = count(weapon.count), ratio(weapon.remaining)
        local throwing = weapon.throwing == true
        local heat_weapon = not throwing and (weapon.ammo_kind == "heat" or weapon.heat_weapon == true)
        if heat_weapon then
            local heat = ratio(weapon.heat)
            item.kind, item.fill = "heat", heat
            if heat ~= nil then
                local display = get(settings, "hud.heat_display", 1)
                item.heat_bar = display == 2 or display == 3
                if display ~= 2 then
                    item.text = tostring(math.floor(heat * 100 + 0.5)) .. "%"
                end
                item.tone = (weapon.heat_locked == true or heat == 1) and "yellow" or "text"
                if heat >= 0.6 then
                    self:update_heat_warning(model, weapon, heat, dt)
                    heat_warning = true
                end
            end
        elseif weapon.reloading == true and not throwing then
            item.text, item.kind = "-", "reload"
            view.reload.visible, view.reload.text, view.reload.tone = true, "RELOADING", "text_dim"
        elseif amount ~= nil then
            item.text, item.kind = tostring(amount), "count"
        elseif remaining ~= nil then
            item.text, item.kind = tostring(math.floor(remaining * 100 + 0.5)) .. "%", "remaining"
        end
        item.visible = item.text ~= nil or item.heat_bar
        if not heat_weapon then
            item.fill = remaining
        end
        if view.details and not throwing then
            local capacity, reserve = count(weapon.capacity), count(weapon.reserve)
            item.capacity = not heat_weapon and capacity and "/ " .. capacity or nil
            item.reserve = reserve and "RESERVE " .. reserve or nil
            item.visible = item.visible or item.capacity ~= nil or item.reserve ~= nil
        end
        local low_count = amount ~= nil
            and (amount == 0 or count(weapon.capacity) and weapon.capacity > 0 and amount / weapon.capacity <= 0.2)
        if not heat_weapon and (low_count or remaining ~= nil and remaining <= 0.2) then
            item.tone = "yellow"
            -- Generic native depletion does not prove a magazine or reload action.
            if low_count and not throwing and weapon.reloading ~= true then
                view.reload.visible, view.reload.text, view.reload.tone =
                    true, amount == 0 and "RELOAD - EMPTY" or "RELOAD", "yellow"
            end
        end
    end
    if not heat_warning then
        self:reset_heat_warning()
    end
    self:ready(model)
    view.ready.visible = self.ready_until > self.clock
    view.ready.text = view.ready.visible
            and (self.ready_count == 1 and "STRATAGEM READY" or self.ready_count .. " STRATAGEMS READY")
        or nil
    if view.quiet_aim then
        -- Aim is the quietest state. Keep the weapon readout and urgent damage,
        -- critical health/no-stim and reload cues; inspection reveals everything.
        view.health.visible = health ~= nil and (self.critical or self.damage_until > self.clock)
        view.stamina.visible, view.throwables.visible, view.ready.visible = false, false, false
        view.stims.visible = stims == 0 and health ~= nil and (self.health_on or self.critical)
    end
    -- Original Core retains sole presentation ownership of options/cooldowns.
    view.cooldowns = false
    for _, name in ipairs(SLOTS) do
        view.visible = view.visible or view[name].visible
    end
    view.visible = view.visible == true and view.opacity > 0
    return view
end
return Policy
