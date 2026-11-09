-- Native-value availability determines which features can be constructed.
local Dependencies = {}

function Dependencies.blocked(graph)
    local out = {}
    if graph == nil or graph.missing == nil or next(graph.missing) == nil then
        return out
    end
    local uses, requires, state = graph.uses or {}, graph.requires or {}, {}
    local function visit(module)
        if state[module] ~= nil then
            return state[module]
        end
        state[module] = false
        local hit = false
        for _, name in ipairs(uses[module] or {}) do
            if graph.missing[name] ~= nil then
                hit = true
                break
            end
        end
        if not hit then
            for _, other in ipairs(requires[module] or {}) do
                if visit(other) then
                    hit = true
                    break
                end
            end
        end
        state[module] = hit
        return hit
    end
    for module in pairs(uses) do
        if visit(module) then
            out[module] = true
        end
    end
    return out
end

return Dependencies
