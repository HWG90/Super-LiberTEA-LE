-- Original R46 composition under one application lifecycle. Native algorithms
-- remain in src/; this module supplies explicit settings and presentation seams.
local Core = {}
Core.__index = Core
local MODULES = {
    "layout",
    "guards",
    "native",
    "native_startup",
    "menu_latch",
    "mission_blacklist",
    "input",
    "pointing",
    "camera",
    "icon_colors",
    "duplicate",
    "emote",
    "expanded",
    "cooldown_gui",
    "cooldown_dock",
    "binding_warning",
    "binding_defaults",
    "selection",
    "release",
    "blacklist",
    "settings",
    "feedback",
    "hud_plus",
    "foliage_compat",
}
function Core.new(context, dependencies)
    local deps = dependencies or {}
    assert(deps.settings and type(deps.settings.dbf_options) == "function", "DBF settings service required")
    return setmetatable({
        context = context,
        settings = deps.settings,
        globals = deps.globals or _G,
        report = deps.report or function() end,
        heat_limiter_factory = deps.heat_limiter_factory,
        presentation = { weapon_options = true, cooldowns = true },
        current = {},
    }, Core)
end
function Core:enable()
    assert(not self.started and not self.retiring and not self.closed, "DBF Core already enabled or retiring")
    local globals, context = self.globals, self.context
    assert(rawget(globals, "DiversBestFriend") == nil, "Another DBF provider is active")
    assert(rawget(globals, "NativeStratagemRadial") == nil, "Another DBF provider owns native selection")
    local scope, cache = setmetatable({ _G = globals }, { __index = globals }), {}
    local private = setmetatable({ scope = scope }, { __index = context })
    scope.mod = private
    local function load(path)
        if cache[path] ~= nil then
            return cache[path]
        end
        local source = assert(context.read(path), "DBF source unavailable: " .. path)
        local chunk = assert(loadstring(source, "@DBF-Modular/" .. path))
        setfenv(chunk, scope)
        local value = chunk()
        if value == nil then
            value = true
        end
        cache[path] = value
        return value
    end
    private.require = function(path, ...)
        if path:sub(1, 4) == "src/" then
            return load(path)
        end
        return context.require(path, ...)
    end
    scope.dbf_options_menu = function()
        return self.settings:dbf_options()
    end
    scope.dbf_presentation = function()
        return self.presentation
    end
    scope.dbf_layout = function()
        return self.layout_request
    end
    self.scope, self.modules = scope, cache
    local okay, why = pcall(function()
        for _, name in ipairs(MODULES) do
            for key, value in pairs(load("src/" .. name .. ".lua")) do
                scope[key] = value
            end
        end
        local create_backend = assert(scope.native_backend)
        scope.native_backend = function()
            if not self.backend then
                self.backend = create_backend()
            end
            return self.backend
        end
        local canary = assert(scope.canary_settings)
        scope.canary_settings = function(_, ...)
            return canary(self.settings:dbf_options(), ...)
        end
        self.entry = load("src/entry.lua")
        for key, value in pairs(self.entry) do
            scope[key] = value
        end
        assert(type(scope.update) == "function", "DBF update callback unavailable")
        self.callback, self.api, self.started = scope.update, assert(self.entry.api), true
        rawset(globals, "DiversBestFriend", self.api)
        rawset(globals, "NativeStratagemRadial", self.api)
        -- Preserve Original Main's construction and update order.
        self.weapon_status = load("src/weapon_status.lua").new(scope)
        self.terminal = load("src/terminal.lua").new(scope)
        local limiter_new = self.heat_limiter_factory or context.require("core/heat_limiter.lua").new
        self.heat_limiter = limiter_new(context, {
            settings = self.settings,
            globals = self.globals,
            report = self.report,
        })
    end)
    if not okay then
        self.error = tostring(why)
        local cleaned, problem = self:close()
        return false, self.error .. (cleaned and "" or "; cleanup refused: " .. tostring(problem))
    end
    return true
end
function Core:update(dt)
    if not self.started or self.retiring then
        return
    end
    self.callback(dt)
    self.weapon_status.update(dt)
    self.terminal.update(dt)
    if self.heat_limiter then
        local okay, why = pcall(self.heat_limiter.update, self.heat_limiter, self:services())
        if not okay then
            self.report("Heat limiter suspended: " .. tostring(why))
            -- An adapter exception never abandons a native generation. Its
            -- acknowledged close remains retryable through Core cleanup.
            local closed, accepted, reason = pcall(self.heat_limiter.close, self.heat_limiter)
            if not closed or accepted ~= true then
                self.report("Heat limiter cleanup pending: " .. tostring(closed and reason or accepted))
            end
        end
    end
end
function Core:services()
    local out, entry = self.current, self.entry
    local live = entry and entry.dbf_services()
    out.backend, out.api = live and live.backend or nil, self.api
    out.snapshot, out.cooldowns = live and live.snapshot or nil, live and live.cooldowns or nil
    out.weapon = self.weapon_status and self.weapon_status.model or nil
    out.presentation = self.presentation
    out.layout = self.layout_request
    out.heat_limiter = self.heat_limiter and self.heat_limiter:snapshot() or nil
    out.initialized, out.failed, out.recovering =
        live and live.initialized, live and live.failed, live and live.recovering
    return out
end
function Core:set_presentation(policy)
    if self.retiring or self.closed then
        return false, "DBF Core is retiring"
    end
    policy = policy or {}
    local weapon, cooldowns = policy.weapon_options ~= false, policy.cooldowns ~= false
    local changed_weapon, changed_cooldowns =
        weapon ~= self.presentation.weapon_options, cooldowns ~= self.presentation.cooldowns
    self.presentation.weapon_options, self.presentation.cooldowns = weapon, cooldowns
    self.presentation_pending = self.presentation_pending or {}
    local pending, problem = self.presentation_pending, nil
    if (changed_weapon or pending.weapon) and self.weapon_status then
        local called, accepted, why = pcall(self.weapon_status.present, weapon)
        pending.weapon = not called or accepted == false
        if pending.weapon then
            problem = tostring(called and why or accepted)
        end
    end
    if (changed_cooldowns or pending.cooldowns) and self.entry then
        local called, accepted, why = pcall(self.entry.dbf_present)
        pending.cooldowns = not called or accepted == false
        if pending.cooldowns then
            problem = (problem and problem .. "; " or "") .. tostring(called and why or accepted)
        end
    end
    return problem == nil, problem
end
-- Placement-only bridge to the SAME original presenters and sampled facts.
function Core:weapon_metrics(edge, gap)
    if not self.weapon_status or type(self.weapon_status.metrics) ~= "function" then
        return
    end
    return self.weapon_status.metrics(edge, gap)
end
function Core:cooldown_layout(options)
    if not self.entry or type(self.entry.dbf_bracket_layout) ~= "function" then
        return
    end
    options.enabled = self.api and self.api.enabled and self.api.cooldown_icons or false
    return self.entry.dbf_bracket_layout(self.backend and self.backend.milliseconds() or 0, options)
end
function Core:clear_layout()
    if not self.layout_request then
        return true
    end
    local okay, why = true, nil
    if self.weapon_status and type(self.weapon_status.place) == "function" then
        local called, accepted, reason = pcall(self.weapon_status.place, nil)
        if not called or accepted ~= true then
            okay, why = false, tostring(called and reason or accepted)
        end
    end
    if self.entry and type(self.entry.dbf_bracket_draw) == "function" then
        local called, accepted, reason =
            pcall(self.entry.dbf_bracket_draw, self.backend and self.backend.milliseconds() or 0, nil)
        if not called or accepted ~= true then
            okay, why = false, (why and why .. "; " or "") .. tostring(called and reason or accepted)
        end
    end
    if not okay then
        self.layout_request.restore_pending = true
        return false, why
    end
    self.layout_request = nil
    return true
end
function Core:set_layout(weapon, packet, anchor, opacity)
    if self.retiring or self.closed then
        return false, "DBF Core is retiring"
    end
    if self.layout_request and self.layout_request.restore_pending then
        local restored, why = self:clear_layout()
        if not restored then
            return false, "DBF placement restore still pending: " .. tostring(why)
        end
    end
    if not weapon and not packet then
        return self:clear_layout()
    end
    local request = self.layout_request or {}
    -- Retain a retry marker before native changes; clear only after restore ack.
    self.layout_request = request
    request.weapon = request.weapon or weapon ~= nil
    request.cooldowns = request.cooldowns or packet ~= nil
    local called, accepted, why = true, true, nil
    if self.weapon_status and type(self.weapon_status.place) == "function" then
        called, accepted, why = pcall(self.weapon_status.place, weapon)
    elseif weapon then
        called, accepted, why = true, false, "Weapon placement unavailable"
    end
    if called and accepted == true and self.entry and type(self.entry.dbf_bracket_draw) == "function" then
        called, accepted, why = pcall(
            self.entry.dbf_bracket_draw,
            self.backend and self.backend.milliseconds() or 0,
            packet,
            anchor,
            opacity
        )
    elseif called and accepted == true and packet then
        called, accepted, why = true, false, "Cooldown placement unavailable"
    end
    if not called or accepted ~= true then
        local problem = tostring(called and why or accepted)
        request.restore_pending = true
        local restored, reason = self:clear_layout()
        return false, problem .. (restored and "" or "; original placement restore: " .. tostring(reason))
    end
    request.weapon, request.cooldowns, request.restore_pending = weapon ~= nil, packet ~= nil, false
    request.identity, request.generation =
        packet and packet.identity or weapon and weapon.root,
        packet and packet.generation or weapon and weapon.generation
    return true
end
function Core:close()
    if self.closed then
        return true
    end
    self.retiring = true
    if self.heat_limiter then
        local okay, accepted, why = pcall(self.heat_limiter.close, self.heat_limiter)
        if not okay or accepted ~= true then
            return false, "Heat limiter cleanup pending: " .. tostring(okay and why or accepted)
        end
    end
    if self.weapon_status then
        local okay, why = self.weapon_status.close()
        if okay == false then
            return false, why
        end
    end
    if self.api then
        if rawget(self.globals, "DiversBestFriend") ~= self.api or type(self.api.shutdown) ~= "function" then
            return false, "DBF cleanup owner unavailable"
        end
        local okay, why = self.api.shutdown()
        if okay == false then
            return false, why
        end
    elseif self.entry and self.entry.api then
        return false, "DBF partial startup owner unavailable"
    end
    self.started, self.closed, self.callback = false, true, nil
    self.scope, self.modules, self.entry, self.weapon_status, self.terminal = nil, nil, nil, nil, nil
    self.api = nil
    self.backend = nil
    self.heat_limiter = nil
    self.layout_request = nil
    for key in pairs(self.current) do
        self.current[key] = nil
    end
    return true
end
return Core
