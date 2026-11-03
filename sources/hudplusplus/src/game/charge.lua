local ratio = require("game.ratio")
local Charge = {}
Charge.__index = Charge
function Charge.new(weapon)
    return setmetatable({
        weapon = weapon,
        read = weapon.read,
        judge = weapon.judge,
        n = weapon.n,
        charge_open = assert(weapon.judge:routine("charge_open")),
        heat_open = assert(weapon.judge:routine("heat_open")),
    }, Charge)
end
function Charge:observe(id, record, mode)
    self.heat_manager = nil
    self.index, self.charging, self.elapsed, self.full, self.share, self.ready_share, self.settings =
        nil, nil, nil, nil, nil, nil, nil
    if record == nil then
        return
    end
    local weapon, read, judge, n = self.weapon, self.read, self.judge, self.n
    local manager = weapon:manager(n.weapon_charge_manager)
    if manager ~= nil then
        self.index = weapon:find(manager + n.weapon_charge_map, id, weapon.invalid_entity)
    end
    if self.index ~= nil then
        local rows = read:ptr(manager + n.weapon_charge_rows_at)
        if rows ~= nil then
            local row = rows + self.index * n.weapon_charge_rows_stride
            self.charging = read:value(row + n.weapon_charge_charging, "bool")
            if self.charging == true then
                self.elapsed = read:value(row + n.weapon_charge_elapsed, "f32")
                local book = judge:call(self.charge_open, record)
                if book ~= nil and book ~= 0 then
                    self.settings = book
                    self.full = read:value(book + n.charge_full_at, "f32")
                    local top
                    if mode == n.charge_unbound_mode then
                        if
                            read:value(book + n.charge_explodes_flag, "bool") ~= true
                            and read:value(book + n.charge_burst_stage, "u32") == n.charge_over_stage
                        then
                            local late = read:value(book + n.charge_burst_value, "f32")
                            if late ~= nil and late > 0 then
                                top = late
                            end
                        end
                        if top == nil then
                            top = read:value(book + n.charge_limit, "f32")
                        end
                    elseif mode ~= nil then
                        top = self.full
                    end
                    self.share = ratio(self.elapsed, top)
                    if self.full ~= nil and self.elapsed ~= nil and not (self.full > self.elapsed) then
                        self.ready_share = self.share
                    end
                end
            end
        end
    end
    if self.share ~= nil then
        return
    end
    local heat = weapon:manager(n.weapon_heat_manager)
    self.heat_manager = heat
    if heat == nil then
        return
    end
    local index = weapon:find(heat + n.weapon_heat_map, id, weapon.invalid_entity)
    if index == nil then
        return
    end
    local book = judge:call(self.heat_open, record)
    if book == nil or book == 0 or read:value(book + n.weapon_heat_charge_resets, "bool") ~= true then
        return
    end
    local rows = read:ptr(heat + n.weapon_heat_charge_at)
    if rows == nil then
        return
    end
    local value = read:value(rows + index * n.weapon_heat_charge_stride + n.weapon_heat_charge, "f32")
    if value == nil or value <= 0 then
        return
    end
    self.share = ratio(value, read:value(book + n.weapon_heat_firing_charge, "f32"))
end
function Charge:projectile()
    local book, n, read = self.settings, self.n, self.read
    if self.charging ~= true or book == nil then
        return nil, nil
    end
    local floor = read:value(book + n.charge_floor_at, "f32")
    local limit = read:value(book + n.charge_limit, "f32")
    local elapsed, full = self.elapsed, self.full
    local short
    if floor ~= nil and elapsed ~= nil then
        short = floor > elapsed
    end
    local at = n.charge_type_full_at
    if floor ~= nil and full ~= nil and elapsed ~= nil and full > floor and elapsed >= floor and elapsed < full then
        at = n.charge_type_low_at
    elseif limit ~= nil and full ~= nil and elapsed ~= nil and limit > full and elapsed >= limit then
        at = n.charge_type_over_at
    end
    return read:value(book + at, "u32"), short
end
return Charge
