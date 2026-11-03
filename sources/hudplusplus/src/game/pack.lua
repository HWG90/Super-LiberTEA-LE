local ratio = require("game.ratio")
local Pack = {}
Pack.__index = Pack
function Pack.new(weapon)
    local judge, n = weapon.judge, weapon.n
    local self = setmetatable(
        { weapon = weapon, read = weapon.read, judge = judge, n = n, out = assert(judge:buffer("uint32_t", 1)) },
        Pack
    )
    for _, name in ipairs({
        "worn_pack",
        "deposit_open",
        "drone_of_deposit",
        "minigame_settings",
        "shield_open",
        "entity_of_goid",
        "linked_ammo_target",
    }) do
        self[name] = assert(judge:routine(name))
    end
    self.one = self.read:value(weapon.game + n.fire_speed_unit, "f32")
    return self
end
function Pack:countdown(id)
    local weapon, read, judge, n = self.weapon, self.read, self.judge, self.n
    local manager = weapon:manager(n.minigame_manager)
    if manager == nil then
        return nil
    end
    local index = weapon:find(manager + n.minigame_map, id, weapon.invalid_player)
    if index == nil then
        return nil
    end
    local rows = read:ptr(manager + n.minigame_rows_at)
    local entities = read:ptr(manager + n.minigame_entities_at)
    if rows == nil or entities == nil then
        return self.one
    end
    local row = rows + index * n.minigame_rows_stride
    local entry = read:ptr(entities + index * n.minigame_entity_stride)
    local key
    if entry ~= nil then
        key = read:value(entry, "key64")
    end
    local book
    if key then
        book = judge:call(self.minigame_settings, judge:uint64_of(key))
    end
    local step = read:value(row + n.minigame_step, "u32")
    if book == nil or book == 0 or step == nil then
        return self.one
    end
    local authored = book + step * n.minigame_entry_stride
    if read:value(authored, "u32") ~= n.minigame_kind_countdown then
        return self.one
    end
    local left = read:value(row + n.minigame_countdown_left, "f32")
    if left == nil or left <= 0 then
        return self.one
    end
    local result = ratio(left, read:value(authored + n.minigame_countdown_info, "u32"))
    if result == nil then
        result = self.one
    end
    return result, true
end
function Pack:drone(id, deposits, index)
    local weapon, read, judge, n = self.weapon, self.read, self.judge, self.n
    if deposits == nil or index == nil then
        return nil
    end
    if judge:call(self.drone_of_deposit, deposits, self.out, id) == nil then
        return nil
    end
    local drone = tonumber(self.out[0])
    if drone == weapon.invalid_avatar then
        return nil
    end
    local gun = weapon:wield(drone)
    local manager = weapon:manager(n.arc_weapon_manager)
    if manager == nil then
        return nil
    end
    local found = weapon:find(manager + n.arc_weapon_map, gun, weapon.invalid_entity)
    if found == nil then
        return nil
    end
    local rows = read:ptr(manager + n.arc_weapon_rows_at)
    if rows == nil then
        return found
    end
    local row = rows + found * n.arc_weapon_rows_stride
    local wait = read:value(row + n.arc_weapon_wait, "f32")
    return found, ratio(wait, read:value(row + n.arc_weapon_interval, "f32")), wait ~= nil and wait > 0
end
function Pack:shield(id)
    local weapon, read, judge, n = self.weapon, self.read, self.judge, self.n
    local manager = weapon:manager(n.shield_manager)
    if manager == nil then
        return nil
    end
    local index = weapon:find(manager + n.shield_map, id, weapon.invalid_player)
    if index == nil then
        local links = weapon:manager(n.shield_link_manager)
        local link
        if links ~= nil then
            link = weapon:find(links + n.shield_link_map, id, weapon.invalid_entity)
        end
        local rows
        if link ~= nil then
            rows = read:ptr(links + n.shield_link_goids)
        end
        local goid
        if rows ~= nil then
            goid = read:value(rows + link * n.shield_link_goid_stride + n.shield_link_goid_at, "u32")
        end
        if goid ~= nil and judge:call(self.entity_of_goid, self.out, goid) ~= nil then
            index = weapon:find(manager + n.shield_map, tonumber(self.out[0]), weapon.invalid_player)
        end
    end
    if index == nil then
        return nil
    end
    local rows = read:ptr(manager + n.shield_rows_at)
    if rows == nil then
        return nil
    end
    local broken = read:value(rows + index * n.shield_rows_stride + n.shield_broken, "bool")
    if broken ~= true then
        return broken
    end
    local waits = read:ptr(manager + n.shield_waits_at)
    local wait
    if waits ~= nil then
        wait = read:value(waits + index * n.shield_wait_stride + n.shield_wait_left, "f32")
    end
    if wait == nil or wait <= 0 then
        return true
    end
    local records = read:ptr(manager + n.shield_records)
    local record
    if records ~= nil then
        record = read:ptr(records + index * n.shield_records_stride)
    end
    local book
    if record ~= nil then
        book = judge:call(self.shield_open, record)
    end
    local total
    if book ~= nil and book ~= 0 then
        total = read:value(book + n.shield_wait_total, "f32")
    end
    return true, ratio(wait, total), true
end
function Pack:observe(avatar, wield_key, spare_on, worn, gauge, reserve_shown)
    self.share, self.left, self.remaining, self.busy, self.covered, self.linked = nil, nil, nil, nil, nil, nil
    if worn then
        self.share = gauge
    end
    if not worn and spare_on then
        return
    end
    local weapon, read, judge, n = self.weapon, self.read, self.judge, self.n
    local inventory = weapon:manager(n.inventory_manager)
    if inventory == nil or avatar == nil then
        return
    end
    if judge:call(self.worn_pack, inventory, self.out, avatar) == nil then
        return
    end
    local id = tonumber(self.out[0])
    if id == weapon.invalid_entity then
        return
    end
    local record = weapon:record(id)
    local book
    if record ~= nil then
        book = judge:call(self.deposit_open, record)
    end
    if book == 0 then
        book = nil
    end
    local deposits, index
    if book ~= nil then
        deposits = weapon:manager(n.deposit_manager)
        if deposits ~= nil then
            index = weapon:find(deposits + n.deposit_map, id, weapon.invalid_entity)
        end
        if not spare_on and wield_key ~= nil then
            local feeds = read:value(book + n.deposit_instance_feeds_resource, "hex64")
            if feeds ~= nil and feeds == wield_key then
                local rows
                if index ~= nil then
                    rows = read:ptr(deposits + n.deposit_rows_at)
                end
                if rows ~= nil then
                    self.remaining = read:value(rows + index * n.deposit_rows_stride + n.deposit_remaining, "u32")
                end
                self.covered = reserve_shown == true and self.remaining ~= nil
            end
        end
        if worn and not spare_on and self.covered == nil then
            self.linked = id
        end
    end
    if not worn or self.covered then
        return
    end
    local arc, broken, alternate, busy
    if book ~= nil then
        if read:value(book + n.deposit_drone_path, "hex64") ~= nil then
            arc, self.left, busy = self:drone(id, deposits, index)
        else
            alternate, busy = self:countdown(id)
        end
    elseif gauge == nil or gauge <= 0 then
        broken, self.left, busy = self:shield(id)
    end
    if arc == nil and broken ~= true then
        self.share = alternate
        if self.share == nil then
            self.share = gauge
        end
    else
        self.share = nil
    end
    if busy == true then
        self.busy = true
    end
end
function Pack:hides(wield)
    if self.covered ~= nil then
        return self.covered
    end
    if self.linked == nil or wield == nil then
        return false
    end
    if self.judge:call(self.linked_ammo_target, 0, self.out, wield) == nil then
        return false
    end
    return tonumber(self.out[0]) == self.linked
end
return Pack
