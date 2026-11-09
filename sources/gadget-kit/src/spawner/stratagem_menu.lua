-- DBF-MCM sections provide mouse, keyboard and controller navigation.
local M = {}

function M.append(controls, groups, add)
    -- Read the numeric preference saved by kits through 0.5.22 once.
    controls[#controls + 1] = {id='spawner_stratagem', type='slider', label='Previous stratagem',
        min=0, max=57, step=1, default=0, visible_if=function() return false end}
    controls[#controls + 1] = {type='text', text_role='title', label='Fifth stratagem'}
    controls[#controls + 1] = {id='spawner_stratagem_status', type='text',
        label='Status: Choose a stratagem', description='One extra call-in per solo mission.'}
    for _, group in ipairs(groups) do
        local id = 'spawner_stratagem_' .. group.name:lower()
        local choices, indices = {}, {}
        for i, entry in ipairs(group.entries) do
            choices[i], indices[i] = entry.name, entry.index
        end
        controls[#controls + 1] = {id=id .. '_section', type='section', label=group.name, collapsed=true, children={
            {id=id, type='choice', label='Stratagem', presentation='dropdown', choices=choices, default=1},
            {id=id .. '_add', type='button', label='Add to mission', require_confirmation=false,
                on_activate=function() return add(id, indices) end},
        }}
    end
end

-- Store the correct category selection and consume the old index in one MCM save.
function M.restore_choice(handle, groups)
    local previous = handle.get('spawner_stratagem')
    if not previous or previous == 0 then return true end
    for _, group in ipairs(groups) do
        for position, entry in ipairs(group.entries) do
            if entry.index == previous then
                return handle.set_many({['spawner_stratagem_' .. group.name:lower()]=position,
                    spawner_stratagem=0})
            end
        end
    end
    return true
end

return M
