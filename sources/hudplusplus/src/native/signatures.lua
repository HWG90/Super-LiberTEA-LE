local B = require("native.bytes")
local M = {}
local CHUNK = 1048576
local floor, byte = math.floor, string.byte
local function binary(hex)
    return (hex:gsub("..", function(pair)
        return string.char(tonumber(pair, 16))
    end))
end
local function prepared(row)
    local raw, mask = binary(row.hex), binary(row.mask)
    local start, length, best, longest = 1, 0, 1, 0
    for i = 1, #raw do
        if byte(mask, i) == 255 then
            if length == 0 then
                start = i
            end
            length = length + 1
            if length > longest then
                best, longest = start, length
            end
        else
            length = 0
        end
    end
    return { row = row, raw = raw, mask = mask, lead = best - 1, anchor = raw:sub(best, best + longest - 1) }
end
local function matches(p, raw, at)
    if raw == nil or at < 1 or at + #p.raw - 1 > #raw then
        return false
    end
    for i = 1, #p.raw do
        if byte(p.mask, i) == 255 and byte(raw, at + i - 1) ~= byte(p.raw, i) then
            return false
        end
    end
    return true
end
local FACTORS = {
    scale = function(v)
        return 2 ^ floor(v / 64)
    end,
    lea = function(v)
        return 1 + 2 ^ floor(v / 64)
    end,
    shl = function(v)
        return 2 ^ v
    end,
}
function M.take(raw, rva, spec)
    if spec[1] ~= nil then
        local factor = FACTORS[spec[1].kind] ~= nil
        local value = factor and 1 or 0
        for _, part in ipairs(spec) do
            local piece = M.take(raw, rva, part)
            if piece == nil then
                return nil
            end
            if factor then
                value = value * piece
            else
                value = value + piece
            end
        end
        return value
    end
    local at, size, kind = spec.offset, spec.size, spec.kind
    if at + size > #raw then
        return nil
    end
    if size == 8 then
        return B.hex64(raw, at)
    end
    if FACTORS[kind] then
        return FACTORS[kind](byte(raw, at + 1))
    end
    if kind == "here" then
        return rva + at
    end
    if kind == "f" then
        return B.f32(raw, at)
    end
    local value, place = 0, 1
    for i = 1, size do
        value, place = value + byte(raw, at + i) * place, place * 256
    end
    if (kind == "s" or kind == "rip") and value >= place / 2 then
        value = value - place
    end
    if kind == "rip" then
        return rva + spec["end"] + value
    end
    return value
end
local function sections(channel, module)
    local base = channel:module(module)
    if base == nil then
        return nil
    end
    local dos = channel:text(base, 64)
    if dos == nil or dos:sub(1, 2) ~= "MZ" then
        return nil
    end
    local pe = B.u32(dos, 60)
    local head = channel:text(base + pe, 24)
    if head == nil or head:sub(1, 4) ~= "PE\0\0" then
        return nil
    end
    local count, size = B.u16(head, 6), B.u16(head, 20)
    local optional = channel:text(base + pe + 24, size)
    if optional == nil or B.u16(optional, 0) ~= 0x20b then
        return nil
    end
    local image_size = B.u32(optional, 56)
    local table_at = pe + 24 + size
    if image_size == nil or table_at + count * 40 > image_size then
        return nil
    end
    local rows = channel:text(base + table_at, count * 40)
    if rows == nil then
        return nil
    end
    local spans = {}
    for i = 0, count - 1 do
        local at = i * 40
        local length, rva, flags = B.u32(rows, at + 8), B.u32(rows, at + 12), B.u32(rows, at + 36)
        if length == nil or rva == nil or flags == nil or rva + length > image_size then
            return nil
        end
        if floor(flags / 0x40000000) % 2 == 1 and length > 0 then
            spans[#spans + 1] = { at = rva, size = length, code = floor(flags / 0x20000000) % 2 == 1 }
        end
    end
    return { base = base, spans = spans }
end
local function containing(image, at, size)
    for _, span in ipairs(image.spans) do
        if at >= span.at and at + size <= span.at + span.size then
            return span
        end
    end
end
local function chunks(channel, image, span, overlap, visit, pause)
    local offset = 0
    while offset < span.size do
        local count = math.min(CHUNK + overlap, span.size - offset)
        local raw = channel:text(image.base + span.at + offset, count)
        if raw == nil or #raw ~= count then
            return false
        end
        visit(raw, span.at + offset)
        pause()
        offset = offset + CHUNK
    end
    return true
end
local function nothing() end
local LEANS = { consts = { "from" }, cases = { "table", "bias", "limit", "to" }, rows = { "table", "stride" } }
function M.resolve(channel, baked, pause)
    pause = pause or nothing
    if type(baked.patterns) ~= "table" or next(baked.patterns) == nil then
        return nil, "no-signatures"
    end
    local images, list, hits, out, bad, conflicted = {}, {}, {}, {}, {}, {}
    for name, row in pairs(baked.patterns) do
        if images[row.module] == nil then
            images[row.module] = sections(channel, row.module)
            if images[row.module] == nil then
                return nil, "image"
            end
        end
        list[name] = prepared(row)
    end
    local function lose(p, why)
        for key in pairs(p.row.take) do
            bad[key] = bad[key] or why
        end
    end
    local function put(key, value, why)
        if conflicted[key] then
            return
        end
        if value == nil then
            bad[key] = bad[key] or why
        elseif out[key] ~= nil and out[key] ~= value then
            out[key], conflicted[key], bad[key] = nil, true, "conflict"
        else
            out[key] = value
        end
    end
    for module, image in pairs(images) do
        local overlap = 0
        for _, p in pairs(list) do
            if p.row.module == module and p.row["in"] == nil then
                overlap = math.max(overlap, #p.raw - 1)
            end
        end
        for _, span in ipairs(image.spans) do
            if span.code then
                local okay = chunks(channel, image, span, overlap, function(raw, base)
                    for name, p in pairs(list) do
                        if p.row.module == module and p.row["in"] == nil and hits[name] ~= false then
                            local pos = 1
                            while #p.anchor > 0 do
                                local found = raw:find(p.anchor, pos, true)
                                if found == nil then
                                    break
                                end
                                local at = found - p.lead
                                if matches(p, raw, at) then
                                    local rva = base + at - 1
                                    if hits[name] ~= nil and hits[name].at ~= rva then
                                        hits[name] = false
                                        break
                                    end
                                    hits[name] = { at = rva, raw = raw:sub(at, at + #p.raw - 1) }
                                end
                                pos = found + 1
                            end
                            pause()
                        end
                    end
                end, pause)
                if not okay then
                    return nil, "unread"
                end
            end
        end
    end
    local pending = list
    repeat
        local rest, moved = {}, false
        for name, p in pairs(pending) do
            local follow, hit = p.row["in"], hits[name]
            if follow ~= nil and out[follow[1]] ~= nil then
                local at, image = out[follow[1]] + follow[2], images[p.row.module]
                local raw = containing(image, at, #p.raw) ~= nil and channel:text(image.base + at, #p.raw) or nil
                if matches(p, raw, 1) then
                    hit = { at = at, raw = raw }
                else
                    hit = false
                end
            end
            if hit then
                for key, spec in pairs(p.row.take) do
                    put(key, M.take(hit.raw, hit.at, spec), "take")
                end
                moved = true
            elseif follow == nil or hit == false then
                lose(p, follow ~= nil and "anchor" or (hits[name] == false and "not-unique" or "not-found"))
                moved = true
            else
                rest[name] = p
            end
        end
        pending = rest
    until next(pending) == nil or not moved
    for _, p in pairs(pending) do
        lose(p, "dependency")
    end
    local function text(module, at, size)
        local image = images[module]
        if type(at) ~= "number" or size < 0 or containing(image, at, size) == nil then
            return nil
        end
        local raw = channel:text(image.base + at, size)
        if raw ~= nil and #raw == size then
            return raw
        end
    end
    local function constant(module, spec)
        local raw = spec.form == "f32" and text(module, out[spec.from], spec.count * 4) or nil
        if raw == nil then
            return nil, "const"
        end
        local values = {}
        for i = 1, spec.count do
            values[i] = B.f32(raw, (i - 1) * 4)
            if values[i] == nil then
                return nil, "const"
            end
        end
        return values
    end
    local function case(module, spec)
        local limit, bias, target = out[spec.limit], out[spec.bias], out[spec.to]
        if limit == nil or bias == nil or target == nil or limit < 0 then
            return nil, "case"
        end
        local raw = text(module, out[spec.table], (limit + 1) * 4)
        if raw == nil then
            return nil, "case"
        end
        local slot
        for i = 0, limit do
            if B.u32(raw, i * 4) == target then
                if slot ~= nil then
                    return nil, "case-many"
                end
                slot = i
            end
        end
        if slot == nil then
            return nil, "case-none"
        end
        return slot - bias
    end
    local fields = {}
    local function row_of(module, spec)
        local image, at, stride = images[module], out[spec.table], out[spec.stride]
        if at == nil or stride == nil or stride <= 0 then
            return nil, "row"
        end
        local span = containing(image, at, 1)
        if span == nil then
            return nil, "row-span"
        end
        local targets, want = {}, "\0" .. spec.text .. "\0"
        for _, section in ipairs(image.spans) do
            if
                not chunks(channel, image, section, #want - 1, function(raw, base)
                    local pos = 1
                    while true do
                        local found = raw:find(want, pos, true)
                        if found == nil then
                            break
                        end
                        targets[image.base + base + found] = true
                        pos = found + 1
                    end
                end, pause)
            then
                return nil, "row-unread"
            end
        end
        local selected
        if
            not chunks(channel, image, { at = at, size = span.at + span.size - at }, 7, function(raw, base)
                for pointer in pairs(targets) do
                    local key, pos = B.pack(pointer, 8), 1
                    while true do
                        local found = raw:find(key, pos, true)
                        if found == nil then
                            break
                        end
                        local slot = base + found - 1
                        if slot % 8 == 0 and (selected == nil or slot < selected) then
                            selected = slot
                        end
                        pos = found + 1
                    end
                end
            end, pause)
        then
            return nil, "row-unread"
        end
        if selected == nil then
            return nil, "row-none"
        end
        local offset = (selected - at) % stride
        local key = module .. ":" .. spec.table
        if fields[key] ~= nil and fields[key] ~= offset then
            return nil, "row-field"
        end
        fields[key] = offset
        return floor((selected - at) / stride)
    end
    for _, p in pairs(list) do
        local row, module = p.row, p.row.module
        for name, spec in pairs(row.consts or {}) do
            local value, why = constant(module, spec)
            put(name, value, why)
        end
        for name, spec in pairs(row.cases or {}) do
            local value, why = case(module, spec)
            put(name, value, why)
        end
        for name, spec in pairs(row.rows or {}) do
            local value, why = row_of(module, spec)
            put(name, value, why)
        end
    end
    for name, value in pairs(baked.identities or {}) do
        out[name] = value
    end
    for _, name in ipairs(baked.asset_numbers or {}) do
        local expected, actual, same = baked.numbers[name], out[name], true
        if type(expected) == "table" then
            same = type(actual) == "table" and #actual == #expected
            for i, value in ipairs(expected) do
                same = same and actual[i] == value
            end
        else
            same = actual == expected
        end
        if not same then
            out[name], bad[name] = nil, "asset"
        end
    end
    local missing = {}
    for name in pairs(baked.numbers) do
        if out[name] == nil then
            missing[name] = bad[name] or "missing"
        end
    end
    M.close(baked, out, missing)
    return out, missing
end
function M.close(baked, found, missing)
    local identities = baked.identities or {}
    repeat
        local changed = false
        local function drop(name)
            if found[name] ~= nil and identities[name] == nil then
                found[name], missing[name], changed = nil, "dependency", true
            end
        end
        for _, row in pairs(baked.patterns or {}) do
            local follow = row["in"]
            if follow ~= nil and found[follow[1]] == nil then
                for key in pairs(row.take or {}) do
                    drop(key)
                end
            end
            for kind, keys in pairs(LEANS) do
                for name, spec in pairs(row[kind] or {}) do
                    for _, key in ipairs(keys) do
                        if found[spec[key]] == nil then
                            drop(name)
                            break
                        end
                    end
                end
            end
        end
    until not changed
end
local HEAD = "hd2-hud-resolved 1 "
local function finite(number)
    return type(number) == "number" and number == number and number - number == 0
end
local function text_of(value)
    if type(value) == "string" then
        if value:match("^%x+$") then
            return "s", value
        end
    elseif type(value) == "table" then
        local parts, count = {}, 0
        for _ in pairs(value) do
            count = count + 1
        end
        if count == 0 or count ~= #value then
            return nil
        end
        for i = 1, #value do
            if not finite(value[i]) then
                return nil
            end
            parts[i] = string.format("%.17g", value[i])
        end
        return "l", table.concat(parts, ",")
    elseif finite(value) then
        return "n", string.format("%.17g", value)
    end
end
local function value_of(kind, text, expected)
    if kind == "s" then
        if type(expected) == "string" and #text == #expected and text:match("^%x+$") then
            return text
        end
    elseif kind == "l" then
        if
            type(expected) ~= "table"
            or text == ""
            or text:find(",,", 1, true)
            or text:sub(1, 1) == ","
            or text:sub(-1) == ","
        then
            return nil
        end
        local list = {}
        for item in (text .. ","):gmatch("([^,]*),") do
            local number = tonumber(item)
            if not finite(number) then
                return nil
            end
            list[#list + 1] = number
        end
        if #list == #expected then
            return list
        end
    elseif kind == "n" then
        local number = tonumber(text)
        if type(expected) == "number" and finite(number) then
            return number
        end
    end
end
function M.encode(key, found, missing)
    local names = {}
    for name in pairs(found) do
        names[#names + 1] = name
    end
    for name in pairs(missing) do
        names[#names + 1] = name
    end
    table.sort(names)
    local lines = { HEAD .. key }
    for _, name in ipairs(names) do
        if found[name] == nil then
            lines[#lines + 1] = name .. "\tm\t" .. missing[name]
        else
            local kind, text = text_of(found[name])
            if kind == nil then
                return nil
            end
            lines[#lines + 1] = name .. "\t" .. kind .. "\t" .. text
        end
    end
    return table.concat(lines, "\n") .. "\n"
end
function M.decode(text, key, baked)
    if type(text) ~= "string" or text:sub(1, #HEAD + #key + 1) ~= HEAD .. key .. "\n" then
        return nil
    end
    local found, missing = {}, {}
    for line in text:sub(#HEAD + #key + 2):gmatch("[^\n]+") do
        local name, kind, value = line:match("^([%w_]+)\t([nslm])\t(.*)$")
        if name == nil then
            return nil
        end
        local expected = baked.numbers[name]
        if expected ~= nil then
            if kind == "m" then
                missing[name] = value
            else
                found[name] = value_of(kind, value, expected)
                if found[name] == nil then
                    return nil
                end
            end
        end
    end
    for name in pairs(baked.numbers) do
        if found[name] == nil and missing[name] == nil then
            return nil
        end
    end
    return found, missing
end
return M
