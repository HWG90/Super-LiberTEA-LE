-- Equip a catalogue weapon with its native defaults in the local player's mission inventory. The request path is Bridge Combat's
-- (src/spawner/support_weapons.lua): menu callbacks only queue intent, on_update performs the
-- guarded native steps, and an unknown native result is never replayed.
local M = {}
local SCENE = 4         -- game state: in a mission
-- Inventory delivery spawns at the player; the module still validates a ground anchor.
local ANCHOR = {x=0, y=0, z=0, facing_x=1, facing_y=0, radius=1, vertical=1}

function M.new(log, options)
    options = options or {}
    local self = {enabled=false}
    local catalogue = options.catalogue or mod.require('src/spawner/catalogue.lua')
    if options.extra_weapons then
        -- Append so existing saved Spawner dropdown indices keep their meaning.
        local combined = {}
        for _, row in ipairs(catalogue) do combined[#combined+1] = row end
        for _, row in ipairs(options.extra_weapons) do combined[#combined+1] = row end
        catalogue = combined
    end
    local backend = options.backend or mod.require('src/spawner/backend.lua').new(log)
    local io = options.io or mod.require('src/spawner/io.lua').new(backend)
    local observe = options.observe or mod.require('src/spawner/observer.lua').observer(backend, io, _G, SCENE)
    local support = (options.support_module or mod.require('src/spawner/support_weapons.lua')).new({
        io=io, load=mod.require, catalogue=catalogue, anchor=ANCHOR, scene=SCENE, observe=observe,
        delivery='inventory', can_equip=function() return self.enabled end, log=log, now=options.now,
        -- "Pickup component count owner" (game 0x4D4190) guards ground-pickup zones, which inventory
        -- delivery never uses; it can stay packed until the game first runs it.
        optional_guards={[0x4D4190]=true},
    })
    local items = {}
    for i, row in ipairs(catalogue) do
        if row.kind==2 then items[row.id] = i end
    end
    local slot = (options.slot_module or mod.require('src/spawner/stratagem_slot.lua')).new({
        io=io, observe=observe, support=support, items=items, now=options.now,
        stratagems=options.stratagems or mod.require('src/spawner/stratagems.lua'),
        write=options.write or function(at, bytes) return backend:write(at, bytes) end,
    })
    local adapter
    function self:loadout_editor()
        local parts=mod.require('src/loadout_parts.lua')
        local attachments=mod.require('src/loadout_attachments.lua').new(parts)
        adapter=mod.require('src/loadout_backend.lua').new(backend,io,observe,support,attachments)
        return mod.require('src/loadout_editor.lua').new(adapter,mod.require('src/loadout_catalogue.lua'))
    end
    function self:choices() return support:choices() end
    function self:set_enabled(value)
        if self.enabled and value ~= true then slot:cancel() end
        self.enabled = value == true
        return support:set_enabled(self.enabled)
    end
    -- index into choices(); returns true or false and why
    function self:queue(index) return support:queue(index) end
    function self:update(dt)
        support:update()
        slot:update(self.enabled)
        if adapter and adapter.retained then
            local ok,why=pcall(adapter.reinforce,adapter,math.min(1,math.max(0,tonumber(dt) or 0)))
            if not ok and why~=self.restore_problem and log then log('Loadout reinforcement: '..tostring(why)) end
            self.restore_problem=not ok and why or nil
        end
    end
    function self:stratagem_choices() return slot:choices() end
    function self:stratagem_groups() return slot:groups() end
    function self:queue_stratagem(index)
        if not self.enabled then return false, 'Spawner is disabled' end
        return slot:queue(index)
    end
    function self:stratagem_status() return slot:status() end
    function self:status() return support:status() end
    function self:shutdown() self.enabled = false; slot:cancel(); return support:shutdown() end
    return self
end
return M
