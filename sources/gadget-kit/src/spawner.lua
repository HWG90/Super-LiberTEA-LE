-- Spawner: equip a catalogue support weapon, with its default attachments, into the local
-- player's support slot during a mission. The request path is Bridge Combat's
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
    for i, row in ipairs(catalogue) do items[row.id] = i end
    local slot = (options.slot_module or mod.require('src/spawner/stratagem_slot.lua')).new({
        io=io, observe=observe, support=support, items=items,
        stratagems=options.stratagems or mod.require('src/spawner/stratagems.lua'),
        write=options.write or function(at, bytes) return backend:write(at, bytes) end,
    })
    function self:choices() return support:choices() end
    function self:set_enabled(value)
        self.enabled = value == true
        return support:set_enabled(self.enabled)
    end
    -- index into choices(); returns true or false and why
    function self:queue(index) return support:queue(index) end
    function self:update() support:update(); slot:update(self.enabled) end
    function self:stratagem_choices() return slot:choices() end
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
