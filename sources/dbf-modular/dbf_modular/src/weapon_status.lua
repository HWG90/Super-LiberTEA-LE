local M = {}
local FIELDS = {
    "id",
    "unit_ref",
    "avatar_unit_ref",
    "resource_hex",
    "lowered",
    "alternate",
    "reloadable",
    "ammo_resource_hex",
    "alternate_fire",
    "fire_mode",
    "ammo_mode",
    "safety_mode",
    "rpm",
    "rpm_index",
    "rpm_selectable",
    "zoom",
    "zoom_index",
    "options_error",
    "mode_error",
    "rpm_error",
}
function M.new(factories)
    local memory = mod.require("src/weapon_status_memory.lua")
    local layouts = mod.require("src/weapon_status_layouts.lua")
    local ammo = mod.require("src/weapon_status_ammo.lua")
    local backend, reader, renderer, b, root, sampled
    local clock, next_poll = 0, 0
    local source_revision = 0
    local placement, placement_active, metrics = {}, false, {}
    local self = { status = "waiting_native", show = true }
    local api = rawget(_G, "DiversBestFriend")
    local dto = { changeable = {}, binding = {} }
    local function publish()
        if api then
            api.weapon_status, api.weapon_readout = self.status, self.last
        end
    end
    local function expose(model)
        for _, name in ipairs(FIELDS) do
            dto[name] = model[name]
        end
        for _, name in ipairs({ "fire_mode", "rpm", "ammo_mode", "zoom" }) do
            dto.changeable[name] = model.changeable and model.changeable[name] == true or false
        end
        for _, name in ipairs({ "module_base", "record", "avatar_id", "avatar_record" }) do
            dto.binding[name] = model.binding and model.binding[name] or nil
        end
        -- The original identity-checked driver sample already contains this
        -- native ammunition discriminator; expose its value, never raw bytes.
        local driver = model.binding and model.binding.driver_state
        dto.ammo_kind = nil
        if type(driver) == "string" and #driver == 40 then
            local a, b, c, d = driver:byte(1, 4)
            local flags = a + b * 256 + c * 65536 + d * 16777216
            dto.ammo_kind = math.floor(flags / 0x80) % 2 == 1 and "magazine"
                or math.floor(flags / 0x100) % 2 == 1 and "rounds"
                or math.floor(flags / 0x200) % 2 == 1 and "heat"
                or nil
        end
        dto.root, dto.sampled_at = root, clock
        self.model = dto
    end
    -- Present only the original validated sample; never create another reader.
    function self.present(show)
        if show ~= nil then
            self.show = show ~= false
        end
        if not renderer then
            return
        end
        if not self.show or not root or not sampled or not b.valid(root) then
            local hidden, why = renderer.hide()
            return hidden ~= false, why
        end
        if placement_active and placement.source_revision ~= source_revision then
            return false, "Weapon layout sample changed"
        end
        local hud_plus = factories.hud_compat
        local drawn, why =
            renderer.draw(root, sampled, hud_plus and hud_plus.weapon_cells, placement_active and placement or nil)
        self.status = renderer.status
        return drawn ~= false, why
    end
    -- Layout-only seam: all choices still come from the original single reader.
    function self.metrics(edge, gap)
        if self.closed or not root or not sampled then
            return nil, "Weapon sample unavailable"
        end
        local value, why = mod.require("src/weapon_status_strip.lua").metrics(sampled, edge, gap, metrics)
        if value then
            value.root, value.source_revision = root, source_revision
        end
        return value, why
    end
    function self.place(spec)
        if self.closed then
            return false, "Weapon status closed"
        end
        if spec ~= nil then
            if
                type(spec) ~= "table"
                or spec.root ~= root
                or not root
                or not sampled
                or spec.source_revision ~= source_revision
                or type(spec.generation) ~= "number"
                or spec.generation ~= spec.generation
                or spec.generation < 0
                or spec.generation % 1 ~= 0
            then
                return false, "Weapon layout source changed"
            end
            for _, name in ipairs({ "x", "y", "edge", "gap", "opacity", "root", "generation", "source_revision" }) do
                placement[name] = spec[name]
            end
        end
        placement_active = spec ~= nil
        local called, accepted, why = pcall(self.present)
        if not called then
            self.status, self.reason = "refused", tostring(accepted)
            return false, self.reason
        end
        return accepted ~= false, why
    end
    function self.update(dt)
        if self.closed then
            return
        end
        clock = clock + (type(dt) == "number" and math.max(0, math.min(dt, 1)) or 1 / 60)
        if clock < next_poll then
            return
        end
        next_poll = clock + 0.1
        if not b then
            local okay, value = pcall(factories.native_backend)
            if not okay then
                self.status, self.reason, next_poll = "waiting_native", tostring(value), clock + 1
                publish()
                return
            end
            b = value
            local ready, why = pcall(function()
                backend = backend or memory.native()
                reader = reader or mod.require("src/weapon_status_reader.lua").new(backend, memory, layouts, ammo)
                renderer = mod.require("src/weapon_status_strip.lua").new(b, factories.duplicate_cards(b))
            end)
            if not ready then
                b, self.status, self.reason, next_poll = nil, "waiting_native", tostring(why), clock + 1
                publish()
                return
            end
        end
        local okay, why = pcall(function()
            root, sampled, self.model = nil, nil, nil
            local candidate = b.pointer(b.base + 0x2e28788)
            if not candidate or not b.valid(candidate) then
                renderer.hide()
                self.status = "no_gameplay_hud"
                return
            end
            local model = reader.poll()
            if not model then
                renderer.hide()
                self.status, self.last = reader.status, nil
                return
            end
            root, sampled = candidate, model
            source_revision = source_revision + 1
            expose(model)
            self.last = {
                weapon = model.resource_hex,
                fire_mode = model.fire_mode,
                rpm = model.rpm,
                rpm_index = model.rpm_index,
                ammo_mode = model.ammo_mode,
                zoom = model.zoom,
                zoom_index = model.zoom_index,
            }
            self.present()
        end)
        if not okay then
            self.status, self.reason, next_poll = "refused", tostring(why), clock + 1
            if renderer then
                pcall(renderer.hide)
            end
        end
        publish()
    end
    function self.close()
        if self.closed then
            return true
        end
        if renderer then
            local okay, why = renderer.close()
            if not okay then
                return false, why
            end
        end
        if backend then
            backend.close()
        end
        self.closed, self.model, self.status = true, nil, "closed"
        publish()
        return true
    end
    return self
end
return M
