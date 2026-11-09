local CATALOG = mod.require("src/stratagems.lua")
local mission_blacklist_names = {
    [5] = "ORBITAL ILLUMINATION FLARE",
    [7] = "EXTRACTION BEACON",
    [11] = "RAISE FLAG",
    [17] = "BUG THUMPER",
    [19] = "SEISMIC PROBE",
    [29] = "SEAF Artillery",
    [30] = "DARK FLUID BACKPACK",
    [34] = "Resupply",
    [37] = "OIL RIG EXTRACT",
    [43] = "HELLBOMB",
    [49] = "DATA JACK",
    [51] = "Eagle Rearm",
    [67] = "TCS 03 THUMPER",
    [73] = "PROSPECTING DRILL",
    [74] = "CARGO CONTAINER",
    [75] = "BUG PLUG",
    [79] = "Cyborg Carry Data",
    [81] = "SHOULDER MOUNTED CAMERA",
    [82] = "Carry Data",
    [87] = "JAMMED PINATA",
    [88] = "RAISE FLAG NO CLEAR AREA",
    [89] = "REMOTE EXPLOSIVES",
    [97] = "POISON DRILL",
    [101] = "EMERGENCY EXTRACTION BEACON",
    [105] = "MOBILE COMMS RELAY",
    [106] = "Carpet Bombing Run",
    [111] = "Scrambler",
    [114] = "IMMEDIATE EXTRACTION BEACON",
    [125] = "SPIRE STERILIZER",
    [126] = "CALL IN DESTROYER",
    [127] = "Reinforce",
    [131] = "Upload Discovery",
    [132] = "DRILLING CHARGE",
    [135] = "Nuke",
    [141] = "CARGO CONTAINER",
    [149] = "SOS Beacon",
    [152] = "EXTRACTION",
}
-- Settings migration and persistence belong to the one Store. Availability
-- remains the original native reader's equipped-protected kind list.
local kinds = {}
for kind in pairs(mission_blacklist_names) do
    kinds[#kinds + 1] = kind
end
table.sort(kinds)
local function mission_blacklist_settings(menu, state, available)
    if state.owner ~= menu then
        state.owner = menu
        state.registered = {}
        state.enabled = {}
        state.dirty = true
        state.ready = false
    end
    local valid = type(menu) == "table"
        and menu.unified == true
        and type(menu.get) == "function"
        and type(menu.register_option) == "function"
        and type(menu.on_change) == "function"
    if valid and (state.dirty or not state.ready) then
        state.ready = true
        for _, kind in ipairs(kinds) do
            local id = "native_stratagem_radial."
                .. (kind == 149 and "hide_sos" or kind == 51 and "hide_eagle_rearm" or "mission_kind_" .. kind)
            if not state.registered[kind] then
                local accepted = menu.register_option(
                    id,
                    { type = "toggle", label = mission_blacklist_names[kind], default = false }
                )
                if accepted == true then
                    state.registered[kind] = menu.on_change(id, function()
                        if state.owner == menu then
                            state.dirty = true
                        end
                    end) == true
                end
            end
            local value = state.registered[kind] and menu.get(id)
            if type(value) == "boolean" then
                state.enabled[kind] = value
            else
                state.enabled[kind] = nil
            end
            if not state.registered[kind] or type(value) ~= "boolean" then
                state.ready = false
            end
        end
        state.dirty = false
    elseif not valid then
        state.ready = false
        for kind in pairs(state.enabled or {}) do
            state.enabled[kind] = nil
        end
    end
    local excluded = {}
    for _, kind in ipairs(available or {}) do
        if valid and mission_blacklist_names[kind] and state.enabled[kind] and state.registered[kind] then
            excluded[kind] = true
        end
    end
    local prior = state.excluded
    local same = prior ~= nil
    for kind in pairs(excluded) do
        if not prior or not prior[kind] then
            same = false
            break
        end
    end
    if same then
        for kind in pairs(prior) do
            if not excluded[kind] then
                same = false
                break
            end
        end
    end
    state.excluded = same and prior or excluded
    state.available_input = available
    return state.excluded
end
return { mission_blacklist_names = mission_blacklist_names, mission_blacklist_settings = mission_blacklist_settings }
