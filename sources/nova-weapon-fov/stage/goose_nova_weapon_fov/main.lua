-- Nova Weapon FOV: the LAS-44 Nova keeps its 3.5x weapon look at 2.5x and 1x (game.dll 6AF322C1).
-- Twice a second it sets the presentation terms of every newly spawned Nova (src/nova.lua);
-- disabling the mod puts the game's own terms back on every Nova it changed.
local PERIOD = 0.5
local nova, clock, last_note, stopped

local function note(message)
    if message ~= last_note then mod.log(message); last_note = message end
end

return {
    live_lua_api = 1,
    name = 'Nova Weapon FOV',
    version = '0.1.0-26568081',
    author = 'Goose',
    on_enable = function()
        local Memory = mod.require('src/memory.lua')
        local Nova = mod.require('src/nova.lua')
        nova, clock, last_note, stopped = Nova.new(Memory.new()), PERIOD, nil, false
        mod.log('Loaded 0.1.0-26568081')
    end,
    on_update = function(dt)
        if not nova or stopped then return end
        clock = clock + (tonumber(dt) or 0)
        if clock < PERIOD then return end
        clock = 0
        local ok, result = pcall(nova.apply, nova)
        if ok then
            if result > 0 then note(('Set the Nova terms on %d weapon row(s)'):format(result)); last_note = nil end
        elseif tostring(result):find('Unsupported game build', 1, true) then
            stopped = true
            mod.log(tostring(result) .. '; Nova Weapon FOV stays off')
        else
            note('Waiting: ' .. tostring(result))
        end
    end,
    on_disable = function()
        if nova then
            local ok, result = pcall(nova.restore, nova)
            mod.log(ok and ('Restored the game terms on %d weapon row(s)'):format(result)
                or ('Restore skipped: ' .. tostring(result)))
        end
        nova = nil
        return true
    end,
}
