local Flight = require("game.flight")
local Eagles = {}
Eagles.__index = Eagles
function Eagles.new(weapon, numbers)
    local judge = weapon.judge
    return setmetatable({
        weapon = weapon,
        numbers = numbers,
        cache = {},
        rows = {},
        keys = {},
        owner_of = assert(judge:routine("attack_owner_of")),
        settings_of = assert(judge:routine("eagle_default_of")),
        weapon_of = assert(judge:routine("projectile_weapon_default_of")),
        modifier_of = assert(judge:routine("explosion_modifier_of")),
    }, Eagles)
end
function Eagles:shape(record, id, replica)
    local weapon = self.weapon
    local read, judge, n = weapon.read, weapon.judge, weapon.n
    local target = read:vector(replica + n.eagle_plan_target, 3)
    if target == nil then
        return {}
    end
    local origin = read:vector(replica + n.eagle_pattern_origin, 2)
    local hash, settings, blob = read:value(record, "key64"), nil, nil
    local entities = weapon:manager(n.roots_entity_owner_rva)
    if hash and entities ~= nil and read:ptr(entities + n.eagle_default_table) ~= nil then
        settings = judge:call(self.settings_of, judge:uint64_of(hash))
        if settings == 0 then
            settings = nil
        end
        if
            settings ~= nil
            and read:value(settings + n.eagle_mode_at, "u32") == n.eagle_strafing_mode
            and read:ptr(entities + n.projectile_registry_table) ~= nil
        then
            blob = judge:call(self.weapon_of, judge:uint64_of(hash))
            if blob == 0 then
                blob = nil
            end
        end
    end
    local modifiers = weapon:manager(n.explosion_modifier_table)
    if modifiers == nil then
        return {}
    end
    local outer = judge:call(self.modifier_of, modifiers, id, n.explosion_scale_key)
    local inner = judge:call(self.modifier_of, modifiers, id, n.explosion_inner_scale_key)
    if outer == nil or inner == nil then
        return {}
    end
    local row = Flight.blast(read, {
        at = target,
        origin = origin,
        eagle = settings,
        weapon = blob,
        explosions = weapon.game + n.explosion_info_table,
        infos = weapon.game + n.projectile_info_table,
        patterns = weapon.game + n.eagle_pattern_table,
        scale_outer = outer,
        scale_inner = inner,
    }, self.numbers) or {}
    row.at = target
    return row
end
function Eagles:observe(mode)
    local weapon = self.weapon
    local read, judge, n = weapon.read, weapon.judge, weapon.n
    local manager = weapon:manager(n.eagle_manager)
    local count, capacity, array, runtime, replicas
    if manager ~= nil then
        count, capacity = read:value(manager + n.eagle_count, "u32"), read:value(manager + n.eagle_capacity, "u32")
        array = read:ptr(manager + n.eagle_records)
    end
    if count == nil or capacity == nil or count > capacity or array == nil then
        self:clear()
        return
    end
    local records = {}
    for index = 0, count - 1 do
        local record = read:ptr(array + index * 8)
        if record == nil then
            self:clear()
            return
        end
        records[#records + 1] = record
    end
    if count > 0 then
        runtime = read:ptr(manager + n.eagle_runtime)
        replicas = read:ptr(manager + n.eagle_replica_rows)
    end
    local owner_manager, own
    if mode == 1 and count > 0 then
        owner_manager = weapon:manager(n.attack_owner_manager)
        own = weapon:local_key()
    end
    local next_cache, rows, keys = {}, {}, {}
    for index, record in ipairs(records) do
        local id = read:value(record + n.eagle_entity_id, "u32")
        if id ~= nil then
            keys[id] = true
            local item = self.cache[id] or {}
            next_cache[id] = item
            if mode == 1 and item.owner == nil and owner_manager ~= nil then
                item.owner = judge:call(self.owner_of, owner_manager, id) or false
            end
            if runtime ~= nil and (mode ~= 1 or (item.owner and item.owner == own)) then
                local at = runtime + (index - 1) * n.eagle_runtime_stride
                local started, progressing =
                    read:value(at + n.eagle_started, "bool"), read:value(at + n.eagle_progressing, "bool")
                if progressing == true or started == false then
                    if item.row == nil and replicas ~= nil then
                        item.row = self:shape(record, id, replicas + (index - 1) * n.eagle_replica_stride)
                    end
                    if item.row ~= nil and item.row.at ~= nil then
                        item.row.key = record
                        rows[#rows + 1] = item.row
                    end
                end
            end
        end
    end
    self.cache, self.rows, self.keys = next_cache, rows, keys
end
function Eagles:clear()
    self.cache, self.rows, self.keys = {}, {}, {}
end
return Eagles
