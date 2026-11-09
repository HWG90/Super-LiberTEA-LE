-- One post-Core HUD pass. No selection, wheel, pointer or gameplay input.
local Session = mod.require("sampling/session.lua")
local Policy = mod.require("hud/policy.lua")
local Layout = mod.require("hud/bracket_layout.lua")
local Renderer = mod.require("render/screen_gui.lua")
local Composition = mod.require("hud/composition.lua")
local Supply = mod.require("render/supply_icons.lua")
local Controller = {}
Controller.__index = Controller
local INSPECT = "dbf_modular.inspect"
function Controller.new(deps)
    local self = setmetatable({
        core = assert(deps.core),
        settings = assert(deps.settings),
        globals = deps.globals or _G,
        report = deps.report or function() end,
        policy = Policy.new(),
        layout = Layout.new(),
        composition = Composition.new(),
        status = "waiting for mission",
        presentation = { weapon_options = true, cooldowns = true },
        clock = 0,
    }, Controller)
    self.supply_icons = deps.supply_icons
        or Supply.new({ core = self.core, globals = self.globals, report = self.report })
    self.renderer = deps.renderer
        or Renderer.new({
            globals = self.globals,
            report = self.report,
            before_change = function()
                if self.core.layout_request and self.core.layout_request.cooldowns then
                    local restored, why = self.core:clear_layout()
                    if restored ~= true then
                        return false, why
                    end
                end
                return self:supply_call("hide")
            end,
        })
    self.sampler = deps.sampler or Session.new(deps)
    self.measure = function(font, text, size)
        return self.renderer:measure(font, text, size)
    end
    self.sample_options = {}
    return self
end
function Controller:supply_call(method, ...)
    local called, accepted, why = pcall(self.supply_icons[method], self.supply_icons, ...)
    if not called or accepted ~= true then
        return false, tostring(called and why or accepted)
    end
    return true
end
function Controller:inspect()
    local menu = rawget(self.globals, "ModBindingsMenu")
    if
        type(menu) ~= "table"
        or menu.api ~= 1
        or type(menu.version) ~= "number"
        or menu.version < 2
        or type(menu.register_binding) ~= "function"
        or type(menu.is_down) ~= "function"
    then
        return false
    end
    if self.binding_owner ~= menu and self.clock >= (self.binding_retry or 0) then
        local options = { category = "DBF Modular" }
        if menu.version >= 4 then
            options.backend = "native"
        end
        -- No default key and no alternate input poll. ADS/Detailed work unbound.
        local called, accepted = pcall(menu.register_binding, INSPECT, "Inspect combat HUD", nil, options)
        if called and accepted then
            self.binding_owner = menu
        end
        self.binding_retry = self.clock + 1
    end
    if self.binding_owner == menu then
        local okay, down = pcall(menu.is_down, INSPECT)
        return okay and down == true
    end
    return false
end
function Controller:fallback(reason)
    if type(self.composition.reset_motion) == "function" then
        self.composition:reset_motion()
    end
    self.presentation.weapon_options, self.presentation.cooldowns = true, true
    -- Keep shared timer labels until the native presenter has returned home.
    local placed, placement_ok, placement_reason = true, true, nil
    if type(self.core.clear_layout) == "function" then
        placed, placement_ok, placement_reason = pcall(self.core.clear_layout, self.core)
    end
    if not placed or placement_ok ~= true then
        self.status = tostring(reason or "waiting for mission")
            .. "; DBF placement restore pending: "
            .. tostring(placed and placement_reason or placement_ok)
        return false, self.status
    end
    local icons_hidden, icons_reason = self:supply_call("hide")
    if not icons_hidden then
        self.status = tostring(reason or "waiting for mission") .. "; supply cleanup pending: " .. icons_reason
        return false, self.status
    end
    local called, hidden, hide_reason = pcall(self.renderer.hide, self.renderer)
    local restored, accepted, restore_reason = pcall(self.core.set_presentation, self.core, self.presentation)
    self.status = tostring(reason or "waiting for mission")
    if not called or hidden == false then
        self.status = self.status .. "; HUD cleanup: " .. tostring(called and hide_reason or hidden)
    end
    if not restored or accepted == false then
        self.status = self.status .. "; DBF fallback: " .. tostring(restored and restore_reason or accepted)
    end
    if not placed or placement_ok ~= true then
        self.status = self.status .. "; DBF placement: " .. tostring(placed and placement_reason or placement_ok)
    end
    return called and hidden ~= false and restored and accepted ~= false and placed and placement_ok == true,
        self.status
end
-- A fallback repeats only pure placement, using this frame's already-collected
-- strip metrics/cooldown packet. Native sampling remains one pass per frame.
function Controller:compose(model, view, viewport, metrics, supplies, packet, collect, dt)
    local geometry = self.layout:update(view, self.settings, viewport, nil, self.measure, supplies, metrics)
    if not geometry.valid then
        return nil, geometry.reason
    end
    local composition = self.composition
    local composed, why = composition:begin(geometry, model, view, self.settings, viewport, metrics, self.measure, dt)
    if not composed then
        return nil, why
    end
    local bounds = composition.combat_bounds
    if collect then
        self.packet_left, self.packet_right, self.packet_bottom, self.packet_top =
            bounds.left, bounds.right, bounds.bottom, bounds.top
        packet = view.native_cooldowns ~= false
                and type(self.core.cooldown_layout) == "function"
                and self.core:cooldown_layout(composition.cooldown_options)
            or nil
    elseif
        bounds.left ~= self.packet_left
        or bounds.right ~= self.packet_right
        or bounds.bottom ~= self.packet_bottom
        or bounds.top ~= self.packet_top
    then
        -- An unusually wide fallback label must not reuse a packet measured
        -- against another shelf. Original DBF retains that presenter instead.
        packet = nil
    end
    composition:include_cooldowns(packet)
    geometry = self.layout:update(
        view,
        self.settings,
        viewport,
        composition.anchors or composition.anchor,
        self.measure,
        supplies,
        metrics
    )
    if not geometry.valid then
        return nil, geometry.reason
    end
    local merged, render_view = composition:assemble(geometry)
    return geometry, merged, render_view, packet
end
function Controller:text_supplies(model, view, viewport, metrics, packet)
    local hidden, why = self:supply_call("hide")
    if not hidden then
        return nil, "Supply cleanup pending: " .. tostring(why)
    end
    if type(self.core.clear_layout) == "function" then
        local called, restored, why = pcall(self.core.clear_layout, self.core)
        if not called or restored ~= true then
            return nil, "DBF placement restore pending: " .. tostring(called and why or restored)
        end
    end
    local geometry, merged, render_view = self:compose(model, view, viewport, metrics, nil, packet, false, 0)
    if not geometry then
        return nil, merged
    end
    local rendered, why = self.renderer:render(model, render_view, merged)
    if not rendered then
        return nil, why
    end
    return geometry
end
function Controller:update(dt)
    if self.retiring then
        return
    end
    if self.core.layout_request and self.core.layout_request.restore_pending then
        local called, accepted, why = pcall(self.core.clear_layout, self.core)
        if not called or accepted ~= true then
            self.status = "DBF placement restore pending: " .. tostring(called and why or accepted)
            return false, self.status
        end
    end
    self.clock = self.clock + (type(dt) == "number" and dt == dt and math.max(0, math.min(dt, 1)) or 0)
    if self.settings:get("hud.enabled") == false then
        return self:fallback("disabled")
    end
    local viewport, why = self.renderer:viewport()
    if not viewport then
        return self:fallback(why)
    end
    local options = self.sample_options
    options.viewport, options.anchor = viewport, self.settings:get("hud.anchor")
    options.tfp_vitals_bone = self.settings:get("hud.tfp_vitals_bone") or 1
    options.tfp_ammo_bone = self.settings:get("hud.tfp_ammo_bone") or 1
    options.tfp_ammo_placement = self.settings:get("hud.tfp_ammo_placement") or 1
    options.sight_clearance = true
    options.heat_icon = (self.settings:get("hud.heat_display") or 1) ~= 1
    local model = self.sampler:sample(dt, options)
    self.model = model
    local view = self.policy:update(model, self.settings, dt, self:inspect())
    self.view = view
    if view.eligible ~= true then
        return self:fallback(self.sampler.reason or "context hidden")
    end
    local show_options, show_cooldowns = view.native_options ~= false, view.native_cooldowns ~= false
    if self.presentation.weapon_options ~= show_options or self.presentation.cooldowns ~= show_cooldowns then
        -- Restore the old placement before changing its visibility. Intentional
        -- Quiet-ADS hiding must never become a viewport-placement fallback.
        if type(self.core.clear_layout) == "function" then
            local cleared, why = self.core:clear_layout()
            if cleared ~= true then
                self.status = "DBF placement restore pending: " .. tostring(why)
                return false, self.status
            end
        end
    end
    self.presentation.weapon_options, self.presentation.cooldowns = show_options, show_cooldowns
    local accepted, reason = self.core:set_presentation(self.presentation)
    if accepted == false then
        self.status = "DBF visibility pending: " .. tostring(reason)
        return false, self.status
    end
    local icons_prepared, icons_problem = self:supply_call("prepare", model)
    if not icons_prepared then
        self.status = "Supply cleanup pending: " .. icons_problem
        return false, self.status
    end
    local prepared, problem = self.renderer:prepare(model)
    if not prepared then
        return self:fallback(problem)
    end
    local pixel = viewport.height / 1080
    local scale = pixel * (self.settings:get("hud.scale") or 100) / 100
    local metrics = show_options
            and type(self.core.weapon_metrics) == "function"
            and self.core:weapon_metrics(22 * scale, 5 * scale)
        or nil
    if
        metrics
        and (metrics.root ~= model.identity or (metrics.generation ~= nil and metrics.generation ~= model.generation))
    then
        metrics = nil
    end
    local composition = self.composition
    local supplies = self.supply_icons.ready and model.supply_icons or nil
    local geometry, merged, render_view, packet = self:compose(model, view, viewport, metrics, supplies, nil, true, dt)
    if not geometry then
        return self:fallback(merged)
    end
    local rendered, problem = self.renderer:render(model, render_view, merged)
    if not rendered then
        return self:fallback(problem)
    end
    local icons_drawn, icon_reason = self:supply_call("render", model, geometry, view.opacity, true)
    if not icons_drawn then
        local why
        geometry, why = self:text_supplies(model, view, viewport, metrics, packet)
        if not geometry then
            self.status = tostring(why)
            return false, self.status
        end
        supplies = nil
    end
    local anchor = composition.anchor
    if type(self.core.set_layout) == "function" then
        local placed, why = self.core:set_layout(
            composition:weapon_placement(),
            composition.cooldown_packet,
            composition.cooldown_anchor or anchor,
            view.opacity
        )
        if not placed then
            -- Screen labels cannot remain at a Bracket position after their
            -- original native icon presenter refused the spatial handover.
            local called, restored, restore_reason = pcall(self.core.clear_layout, self.core)
            if not called or restored ~= true then
                self.status = "DBF placement restore pending: "
                    .. tostring(called and (restore_reason or why) or restored)
                return false, self.status
            end
            -- The rejected native strip influenced width, flow and stacked
            -- alignment. Rebuild from the same captured facts after restoration
            -- ACK, without that strip or packet and without advancing damping.
            local base_geometry, base_merged, base_view =
                self:compose(model, view, viewport, nil, supplies, nil, false, 0)
            if not base_geometry then
                return self:fallback(base_merged or why)
            end
            geometry = base_geometry
            local base_drawn, base_reason = self.renderer:render(model, base_view, base_merged)
            self.status = "Bracket active; DBF placement fallback: " .. tostring(why)
            if not base_drawn then
                return self:fallback(tostring(restore_reason or base_reason or why))
            end
            -- A destructive GUI redraw hides native supplies through the same
            -- dependency guard. Reveal them only after that redraw completes.
            local supplies_drawn, supply_reason = self:supply_call("render", model, geometry, view.opacity, true)
            if not supplies_drawn then
                local text_geometry, text_reason = self:text_supplies(model, view, viewport, nil, nil)
                if not text_geometry then
                    self.status = tostring(text_reason or supply_reason)
                    return false, self.status
                end
            end
            return true
        end
    end
    -- Original DBF still owns these presenters and all their controls. Quiet
    -- aiming hides routine detail temporarily; inspection restores it.
    self.status = "ready: "
        .. tostring(view.profile)
        .. " / "
        .. tostring(anchor.source)
        .. (composition.anchors and (" / gun:" .. tostring(composition.anchors.weapon.source) .. " / vitals:" .. tostring(
            composition.anchors.vitals.source
        )) or "")
        .. (composition.has_strip and " / DBF strip" or "")
        .. (composition.has_cooldowns and " / DBF cooldowns" or "")
        .. (composition.has_cooldowns and composition.cooldown_role and (" under " .. composition.cooldown_role) or "")
        .. (view.quiet_aim and " / Quiet aim" or "")
        .. (not icons_drawn and (" / supply text: " .. tostring(icon_reason)) or "")
    self.placement_status = composition.cooldown_reason or composition.strip_reason
    return true
end
function Controller:close()
    if self.closed then
        return true
    end
    self.retiring = true
    -- Native cooldowns consume labels from this GUI. Restore their complete
    -- original presentation before retiring the shared label/font owner.
    if type(self.core.clear_layout) == "function" then
        local called, accepted, why = pcall(self.core.clear_layout, self.core)
        if not called or accepted ~= true then
            return false, tostring(called and why or accepted)
        end
    end
    local icons_closed, icons_reason = self:supply_call("close")
    if not icons_closed then
        return false, icons_reason
    end
    -- Refusal retains renderer, sampler, buffers and Core dependencies for retry.
    local closed, why = self.renderer:close()
    if closed == false then
        return false, why
    end
    local sampled, reason = self.sampler:close()
    if sampled == false then
        return false, reason
    end
    self.closed = true
    return true
end
return Controller
