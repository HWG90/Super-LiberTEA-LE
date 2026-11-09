-- Original DBF import is data-only and ends with the first own versioned save.
local Schema = mod.require("settings/schema.lua")
local Migrate = {}
local PREFIX = "native_stratagem_radial."
function Migrate.key(id)
    return type(id) == "string" and #id > 0 and #id <= 96 and id:match("^[%w_.%-]+$") ~= nil
end
function Migrate.parse(text)
    local values = {}
    if type(text) ~= "string" or #text > 1048576 then
        return values
    end
    text = text:gsub("^\239\187\191", "")
    for line in text:gmatch("[^\r\n]+") do
        line = line:gsub("//.*$", ""):gsub("#.*$", "")
        local id, raw = line:match("^%s*([%w_.%-]+)%s*[=\t]%s*(.-)%s*$")
        if Migrate.key(id) then
            if raw == "true" or raw == "false" then
                values[id] = raw == "true"
            else
                local value = tonumber(raw)
                if value and value == value and math.abs(value) < math.huge then
                    values[id] = value
                end
            end
        end
    end
    return values
end
function Migrate.run(sources, preferences, old_to_current)
    sources, preferences, old_to_current = sources or {}, preferences or {}, old_to_current or {}
    local owned, menu, blacklist = Migrate.parse(sources.owned), {}, {}
    local values, unknown, origins = Schema.defaults(), {}, {}
    if owned.schema_version ~= nil and owned.schema_version ~= Schema.version then
        return nil, "Unsupported DBF Modular schema: " .. tostring(owned.schema_version)
    end
    local current = owned.schema_version == Schema.version
    local function put(id, value, origin)
        local checked = Schema.validate(id, value)
        if checked ~= nil then
            values[id], origins[id] = checked, origin
            return true
        end
        return false
    end
    if not current then
        menu, blacklist = Migrate.parse(sources.menu), Migrate.parse(sources.blacklist)
        for _, key in ipairs(Schema.dbf_keys) do
            local id = PREFIX .. key
            if not put(id, menu[id], "original menu") then
                put(id, preferences[key], "original preferences")
            end
        end
        if Schema.validate(PREFIX .. "selection_mode_ordered", menu[PREFIX .. "selection_mode_ordered"]) == nil then
            local mode = menu[PREFIX .. "selection_mode"]
            if mode == 1 or mode == 2 or mode == 3 then
                put(PREFIX .. "selection_mode_ordered", 4 - mode, "historical mode")
            elseif mode == 4 then
                put(PREFIX .. "selection_mode_ordered", 1, "historical expanded wheel")
                put(PREFIX .. "experimental_layout", 2, "historical expanded wheel")
            end
        end
        if
            Schema.validate(PREFIX .. "release_selection_mode", menu[PREFIX .. "release_selection_mode"]) == nil
            and type(menu[PREFIX .. "select_on_release"]) == "boolean"
        then
            put(
                PREFIX .. "release_selection_mode",
                menu[PREFIX .. "select_on_release"] and 2 or 1,
                "historical release"
            )
        end
        local complete = blacklist.version == 1 or blacklist.version == 2 or blacklist.version == 3
        local excluded = {}
        if blacklist.version == 1 then
            for index = 1, 3 do
                local kind = old_to_current[blacklist[tostring(index)]]
                if kind then
                    excluded[kind] = true
                end
            end
        elseif blacklist.version == 2 or blacklist.version == 3 then
            for id, value in pairs(blacklist) do
                local kind = tonumber(id)
                if blacklist.version == 2 then
                    kind = old_to_current[kind]
                end
                if kind and value == true then
                    excluded[kind] = true
                end
            end
        else
            for index = 1, 8 do
                local kind = old_to_current[menu[PREFIX .. "blacklist_kind_" .. index]]
                if kind then
                    excluded[kind] = true
                end
            end
        end
        for _, row in ipairs(Schema.exclusions) do
            if complete then
                -- Original DBF's versioned blacklist is authoritative for all37.
                put(row.id, excluded[row.kind] == true, "original blacklist")
            else
                local value = menu[PREFIX .. "mission_kind_" .. row.kind]
                if row.kind == 149 then
                    value = menu[PREFIX .. "hide_sos"]
                end
                if row.kind == 51 then
                    value = menu[PREFIX .. "hide_eagle_rearm"]
                end
                if not put(row.id, value, "original menu") then
                    put(row.id, excluded[row.kind] == true, "historical exclusions")
                end
            end
        end
    end
    -- Own-file data wins, including explicit false/zero. Unknown own numeric and
    -- boolean fields survive; foreign HUD/merger files are never import sources.
    for id, value in pairs(owned) do
        local canonical = Schema.resolve(id)
        if canonical and (id == canonical or owned[canonical] == nil) then
            put(canonical, value, "owned settings")
        elseif not canonical and id ~= "schema_version" and Migrate.key(id) then
            unknown[id] = value
        end
    end
    return values, { origins = origins, current = current }, unknown
end
return Migrate
