local Heading = {}
Heading.__index = Heading
function Heading.new(access, weapon)
    local mouse = stingray.Mouse
    return setmetatable({
        weapon = weapon,
        write = access.write,
        targets = {},
        mouse = mouse,
        vector = stingray.Vector3,
        wheel_id = mouse ~= nil and mouse.axis_id("wheel") or nil,
    }, Heading)
end
function Heading:clear()
    if self.world ~= nil then
        self.targets = {}
    end
    self.world, self.player = nil, nil
end
function Heading:track(world, holding, id, target, player)
    if world ~= nil and world ~= self.world then
        self:clear()
        self.world = world
    end
    self.player = player
    if world == nil then
        return
    end
    if not holding or id == nil then
        return
    end
    if target == nil then
        self.targets[id] = nil
        return
    end
    local saved = self.targets[id] or {}
    saved[1], saved[2] = target[1], target[2]
    self.targets[id] = saved
end
local function rotate(x, y, target, degrees)
    local radians = degrees * math.pi / 180
    local c, s = math.cos(radians), math.sin(radians)
    local dx, dy = x - target[1], y - target[2]
    return target[1] + dx * c - dy * s, target[2] + dx * s + dy * c
end
function Heading:once(id, angle)
    if type(angle) ~= "number" or angle ~= angle or angle == math.huge or angle == -math.huge then
        return true, "angle"
    end
    local weapon = self.weapon
    local read, judge, n = weapon.read, weapon.judge, weapon.n
    if id == weapon.invalid_entity then
        return true, "identity"
    end
    local throws = weapon:manager(n.throwable_manager)
    if throws == nil then
        return false
    end
    local thrown_index = weapon:find(throws + n.throwable_map, id, weapon.invalid_entity)
    if thrown_index == nil then
        return true, "throw_gone"
    end
    local thrown_rows = read:ptr(throws + n.lab_eagle_replica_rows)
    if thrown_rows == nil then
        return false
    end
    local released = read:value(thrown_rows + thrown_index * n.lab_eagle_replica_stride + n.lab_eagle_released, "bool")
    if not released then
        return false
    end
    local player = self.player
    local manager = weapon:manager(n.beacon_manager)
    if player == nil or manager == nil then
        return false
    end
    local index = weapon:find(manager + n.beacon_map, id, weapon.invalid_entity)
    if index == nil then
        return true, "beacon_gone"
    end
    local entries, runtime = read:ptr(manager + n.beacon_entries), read:ptr(manager + n.lab_eagle_beacon_runtime)
    if entries == nil or runtime == nil then
        return false
    end
    local replica = entries + index * n.beacon_entry_size
    local origin = runtime + index * n.lab_eagle_beacon_stride + n.lab_eagle_beacon_origin
    local key = read:value(replica + n.beacon_key, "hex64")
    if key == nil then
        return false
    end
    if key ~= player then
        return true, "call_identity"
    end
    local entity = weapon:record(id)
    if entity == nil then
        return true, "entity"
    end
    local flags = read:value(entity + n.lab_eagle_owner_at, "u8")
    if flags == nil then
        return false
    end
    if flags % (n.lab_eagle_owner_mask * 2) < n.lab_eagle_owner_mask then
        return true, "not_owner"
    end
    local ready = read:value(replica + n.lab_eagle_beacon_ready, "bool")
    if ready == nil then
        return false
    end
    if ready then
        return true, "already_prepared"
    end
    local target = self.targets[id]
    if target == nil then
        return true, "no_target"
    end
    local current, old = read:text(origin, 8), read:vector(origin, 2)
    if current == nil or old == nil then
        return false
    end
    local x, y = rotate(old[1], old[2], target, angle)
    local saved = read.bytes.pack(judge:bits(x), 4) .. read.bytes.pack(judge:bits(y), 4)
    local okay, why = self.write:swap(origin, current, saved)
    if not okay then
        return true, why
    end
    return true, true
end
function Heading:apply(id, angle)
    local done, why = self:once(id, angle)
    if done then
        self.targets[id] = nil
    end
    return done, why
end
function Heading:public()
    local owner = self
    return {
        wheel = function()
            if owner.wheel_id == nil then
                return 0
            end
            return owner.vector.y(owner.mouse.axis(owner.wheel_id))
        end,
        apply = function(_, id, angle)
            return owner:apply(id, angle)
        end,
    }
end
return Heading
