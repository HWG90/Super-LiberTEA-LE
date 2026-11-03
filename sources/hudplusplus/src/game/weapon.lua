local Weapon = {}
Weapon.__index = Weapon
function Weapon.new(read, judge, n)
    local self = setmetatable({
        read = read,
        judge = judge,
        n = n,
        layout = { capacity = n.map_capacity },
        out = assert(judge:buffer("uint32_t", 1)),
    }, Weapon)
    self.game = assert(read:module("game"))
    for _, name in ipairs({
        "avatar_of_player",
        "item_of_slot",
        "wielder_get",
        "entity_record",
        "book_entry_of",
        "open_map_find",
        "weapon_data_find",
    }) do
        self[name] = assert(judge:routine(name))
    end
    self.invalid_local = read:value(self.game + n.hud_local_invalid, "u32")
    self.invalid_avatar = read:value(self.game + n.stratagem_invalid_avatar, "u32")
    self.invalid_player = read:value(self.game + n.invalid_id, "u32")
    self.invalid_entity = read:value(self.game + n.entity_lookup_invalid, "u32")
    return self
end
function Weapon:manager(offset)
    return self.read:ptr(self.game + offset)
end
function Weapon:frame()
    self.key_read, self.key_value = false, nil
    self.map_read, self.map_value = false, nil
end
function Weapon:map_open(manager)
    if not self.map_read then
        self.map_read = true
        manager = manager or self:manager(self.n.roots_hud_manager_rva)
        if manager ~= nil then
            self.map_value = self.read:value(manager + self.n.hud_map_open_at, "bool")
        end
    end
    return self.map_value
end
function Weapon:local_key(players)
    if not self.key_read then
        self.key_read = true
        local n = self.n
        players = players or self:manager(n.roots_player_manager_rva)
        if players ~= nil then
            local present = self.read:value(players + n.roster_local_count, "u32")
            if present ~= nil and present > 0 then
                self.key_value = self.read:value(players + n.stratagem_slots_key_from_at, "key64")
            end
        end
    end
    return self.key_value
end
function Weapon:find(at, key, invalid)
    if at == nil or key == nil or invalid == nil then
        return nil
    end
    local row = self.judge:find(at, self.layout, key, self.open_map_find, invalid)
    if row ~= nil and row ~= self.n.map_missing % 4294967296 then
        return row
    end
end
function Weapon:record(id)
    if id == nil then
        return nil
    end
    local value = self.judge:call(self.entity_record, id)
    if value ~= 0 then
        return value
    end
end
function Weapon:key(record)
    if record ~= nil then
        return self.read:value(record, "key64")
    end
end
function Weapon:item(manager, avatar, slot)
    if manager == nil or avatar == nil or slot == nil then
        return nil
    end
    if self.judge:call(self.item_of_slot, manager, self.out, avatar, slot) ~= nil then
        return tonumber(self.out[0])
    end
end
function Weapon:avatar(panel)
    if not panel.ready then
        return nil
    end
    local read, n = self.read, self.n
    local camera = self:manager(n.camera_manager)
    if camera == nil then
        return nil
    end
    local head = read:value(camera + n.camera_head, "u32")
    local tail = read:value(camera + n.camera_tail, "u32")
    if head == nil or tail == nil then
        return nil
    end
    local current = camera + n.camera_fallback
    if head ~= tail then
        current = camera + n.camera_entries + ((head - 1) % (n.camera_mask + 1)) * n.camera_stride
    end
    local mode = read:value(current, "u16")
    if mode == nil or mode == n.camera_spectator then
        return nil
    end
    if read:value(panel.mission + n.hud_local_pause, "u8") ~= 0 then
        return nil
    end
    local players = self:manager(n.roots_player_manager_rva)
    if players == nil then
        return nil
    end
    local count = read:value(players + n.roster_local_count, "u32")
    if count == nil or count == 0 then
        return nil
    end
    local first = read:ptr(players + n.roster_pointers)
    if first == nil then
        return nil
    end
    local player = read:value(first + n.roster_id, "u32")
    if
        player == nil
        or self.invalid_local == nil
        or self.invalid_avatar == nil
        or player == self.invalid_local
        or player == self.invalid_avatar
    then
        return nil
    end
    if self.judge:call(self.avatar_of_player, players, self.out, player) == nil then
        return nil
    end
    local avatar = tonumber(self.out[0])
    if avatar ~= self.invalid_local then
        return avatar, player, players
    end
end
local function wield(self, avatar, flag)
    if avatar == nil then
        return nil
    end
    local manager, n = self:manager(self.n.weapon_wielder_manager), self.n
    if
        manager ~= nil
        and self.judge:call(self.wielder_get, manager, self.out, avatar, n.wield_slot_zero, flag) ~= nil
    then
        return tonumber(self.out[0])
    end
end
function Weapon:wield(avatar)
    return wield(self, avatar, self.n.wield_flag_plain)
end
function Weapon:fire(avatar)
    return wield(self, avatar, self.n.wield_flag_fire)
end
function Weapon:seated(avatar)
    if avatar == nil then
        return nil
    end
    local read, n = self.read, self.n
    local seater = self:manager(n.seater_manager)
    if seater ~= nil then
        local row = self:find(seater + n.seater_map, avatar, self.invalid_player)
        if row ~= nil then
            local rows = read:ptr(seater + n.seater_rows_at)
            local vehicle
            if rows ~= nil then
                vehicle = read:value(rows + row * n.seater_row_shift, "u32")
            end
            local on = vehicle ~= nil and self.invalid_avatar ~= nil and vehicle ~= self.invalid_avatar
            return on, rows ~= nil and rows + row * n.seater_row_shift or nil
        end
    end
end
function Weapon:heat_index(panel, avatar, seated, wield, options, equipment)
    if avatar == nil then
        return nil
    end
    local read, judge, n = self.read, self.judge, self.n
    local slot = read:value(panel.base + n.hud_self_last_slot, "u32")
    local inventory = self:manager(n.inventory_manager)
    local picked, record, wield_record
    if equipment ~= nil then
        wield_record = equipment.record
    end
    if seated then
        if equipment == nil then
            wield_record = self:record(wield)
        end
        local entry = wield_record
        if entry ~= nil then
            local key = read:value(entry, "key64")
            if key ~= nil then
                if key == false then
                    key = "0000000000000000"
                end
                local book = judge:call(self.book_entry_of, judge:uint64_of(key))
                if book ~= nil and book ~= 0 then
                    picked = wield
                end
            end
        end
    end
    if picked == nil then
        picked = self:item(inventory, avatar, slot)
    end
    if slot ~= n.throwable_slot then
        local data
        if options ~= nil then
            data = options.manager
        else
            data = self:manager(n.weapon_data_manager)
        end
        if data ~= nil and self:find(data + n.weapon_data_map, picked, self.invalid_entity) ~= nil then
            if picked == wield and (seated or equipment ~= nil) then
                record = wield_record
            else
                record = self:record(picked)
            end
        end
    end
    if record == nil then
        picked = nil
        local avatars = self:manager(n.roots_avatar_manager_rva)
        if avatars ~= nil then
            local row = self:find(avatars + n.roots_avatar_manager_map, avatar, self.invalid_player)
            if row ~= nil then
                local last = read:value(
                    avatars + n.avatar_last_weapon_slot + row * n.roots_avatar_manager_controller_stride,
                    "u32"
                )
                picked = self:item(inventory, avatar, last)
            end
        end
        if picked ~= nil and self.invalid_entity ~= nil and picked ~= self.invalid_entity then
            if picked == wield and (seated or equipment ~= nil) then
                record = wield_record
            else
                record = self:record(picked)
            end
        end
    end
    if picked == nil or self.invalid_entity == nil or picked == self.invalid_entity then
        return nil
    end
    if record == nil then
        return nil, picked
    end
    local heat
    if equipment ~= nil and equipment.record ~= nil and equipment.charge.share == nil then
        heat = equipment.charge.heat_manager
    else
        heat = self:manager(n.weapon_heat_manager)
    end
    local index
    if heat ~= nil then
        index = self:find(heat + n.weapon_heat_map, picked, self.invalid_entity)
    end
    return index, picked, record
end
function Weapon:ammo_icons(record)
    local key = self:key(record)
    if key == nil then
        return nil
    end
    if key == false then
        key = "0000000000000000"
    end
    local book = self.judge:call(self.weapon_data_find, self.judge:uint64_of(key))
    if book == nil or book == 0 then
        return nil
    end
    return self.read:value(book + self.n.weapon_data_instance_ammo_icon_empty, "hex64"),
        self.read:value(book + self.n.weapon_data_instance_ammo_icon, "hex64")
end
return Weapon
