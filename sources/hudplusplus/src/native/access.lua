local NativeChannel = require("native.channel").channel
local NativeMemory = require("native.memory")
local Core = {}
local function declarations(baked)
    local out, numbers = {}, baked.numbers or {}
    for name, source in pairs(baked.calls or {}) do
        local row = { kind = source.kind, ctype = source.ctype, result = source.result }
        row.valid = source.kind == "judge" or source.kind == "ui" or source.kind == "world"
        if source.at ~= nil then
            row.at, row.module = numbers[source.at], source.module
            row.valid = row.valid and row.at ~= nil and (row.module == "game" or row.module == "exe")
        else
            row.valid = false
        end
        if source.on ~= nil and numbers[source.on] == nil then
            row.valid = false
        end
        out[name] = row
    end
    return out
end
local READS = { "ptr", "value" }
local VECTOR_CELLS = {}
local function vector_cells(count)
    local cells = VECTOR_CELLS[count]
    if cells == nil then
        cells = NativeChannel.strided(count, 4, "f32")
        VECTOR_CELLS[count] = cells
    end
    return cells
end
local huge = math.huge
function Core.open(baked, core, options)
    baked = baked or {}
    core = core or NativeChannel
    options = options or {}
    local clock, remember = options.clock, options.remember
    local Signatures
    local job, job_key, deadline, spent, slices = nil, nil, nil, 0, 0
    local pin = baked.pin and { exe = baked.pin.exe, game = baked.pin.game } or nil
    local calls = {}
    local started, okay, why, report, channel, mem = false, false, nil, nil, nil, nil
    local bytes = {}
    for name, method in pairs(NativeMemory.bytes) do
        if type(method) == "function" then
            bytes[name] = method
        end
    end
    local read, write = { bytes = bytes, layout = NativeChannel.layout, strided = NativeChannel.strided }, {}
    local ports = {}
    local function open_doors()
        local load = channel.load
        read.value = function(_, address, form, extra)
            return load(channel, address, form or "u32", extra)
        end
        read.ptr = function(_, address)
            return load(channel, address, "ptr")
        end
        read.loads = channel.counted
        local swap = mem.swap
        write.swap = function(_, address, want, to)
            return swap(mem, address, want, to)
        end
        local call = mem.call
        for _, port in pairs(ports) do
            port.call = function(_, token, ...)
                return call(mem, token, ...)
            end
        end
        read.module = function(_, which)
            return channel:module(which)
        end
    end
    local function pause()
        if deadline ~= nil and clock() >= deadline then
            coroutine.yield()
        end
    end
    local function settle(found, missing, source)
        for _, source_call in pairs(baked.calls or {}) do
            local at = found[source_call.at]
            if at ~= nil then
                local head, base = NativeMemory.head_of(source_call), channel:module(source_call.module)
                if head == nil or base == nil or not NativeMemory.head_matches(channel, base + at, head) then
                    found[source_call.at], missing[source_call.at] = nil, "call-head"
                end
            end
        end
        Signatures.close(baked, found, missing)
        for name in pairs(baked.numbers) do
            baked.numbers[name] = found[name]
        end
        report.resolve, report.missing = source, missing
        okay, why = true, nil
    end
    local function opened()
        if channel:module("game") == nil then
            okay, why = false, "no-module"
        end
        if okay then
            calls = declarations(baked)
            open_doors()
        end
        return okay, why, report
    end
    local function status()
        if started then
            return okay, why, report
        end
        started = true
        if pin == nil then
            why = "spec"
            return false, why
        end
        channel, why = core.open()
        if channel == nil then
            why = why or "open"
            return false, why
        end
        mem = NativeMemory.bind(channel)
        okay, report = channel:pinned(pin)
        -- 26251122 port: values that could not be resolved for this build switch their features off
        if okay and baked.unresolved ~= nil and next(baked.unresolved) ~= nil then
            report.missing = baked.unresolved
        end
        -- and no scan on any other build: it would read code pages the protection runtime has not decrypted
        if not okay and baked.refuse_unpinned then
            why = "unsupported-build"
            return false, why, report
        end
        if not okay then
            why = "pin"
            if
                type(report) ~= "table"
                or type(report.exe) ~= "table"
                or type(report.game) ~= "table"
                or report.exe.sha == nil
                or report.game.sha == nil
            then
                return false, why, report
            end
            -- Pinned builds use baked values and do not need the signature resolver.
            Signatures = require("native.signatures")
            local key = report.exe.sha .. " " .. report.game.sha .. " " .. tostring(baked.digest)
            local read_ok, text = false, nil
            if remember ~= nil then
                read_ok, text = pcall(remember.read)
            end
            local found, missing = Signatures.decode(read_ok and text or nil, key, baked)
            if found == nil then
                job, job_key, why =
                    coroutine.create(function()
                        return Signatures.resolve(channel, baked, pause)
                    end), key, "resolving"
                return false, why, report
            end
            settle(found, missing, "remembered")
        end
        return opened()
    end
    function read:status()
        return status()
    end
    function read:resolve(budget)
        if job == nil then
            return true, status()
        end
        local start = clock and clock() or nil
        deadline = start and start + budget or nil
        local resumed, found, missing = coroutine.resume(job)
        if start ~= nil then
            spent = spent + (clock() - start)
        end
        slices = slices + 1
        if resumed and coroutine.status(job) ~= "dead" then
            return false
        end
        job, report.spent, report.slices = nil, spent, slices
        if not resumed or found == nil then
            why = resumed and (missing or "resolve") or "resolve-error"
            return true, false, why, report
        end
        settle(found, missing, "scanned")
        local text = remember ~= nil and Signatures.encode(job_key, found, missing) or nil
        if text ~= nil then
            pcall(remember.write, text)
        end
        return true, opened()
    end
    function read:module(which)
        status()
        return channel ~= nil and channel:module(which) or nil
    end
    function read:vector(address, count)
        local got = self:value(address, vector_cells(count), {})
        if got == nil then
            return nil
        end
        for index = 1, count do
            local part = got[index]
            if part == nil or part ~= part or part == huge or part == -huge then
                return nil
            end
        end
        return got
    end
    function read:counts()
        return { reads = channel and channel.reads or 0, calls = channel and channel.calls or 0 }
    end
    function read:text(address, size)
        status()
        if mem == nil then
            return nil
        end
        return mem:text(address, size)
    end
    function read:head(address, spec)
        status()
        if channel == nil then
            return nil, "open"
        end
        local head, reason = NativeMemory.head_of(spec)
        if head == nil then
            return nil, reason
        end
        return NativeMemory.head_matches(channel, address, head)
    end
    read.loads = setmetatable({}, {
        __index = function(pending, form)
            local load = function(address, extra)
                if not status() then
                    return nil
                end
                return read.loads[form](address, extra)
            end
            pending[form] = load
            return load
        end,
    })
    for _, name in ipairs(READS) do
        local method = name
        read[method] = function(self, a, b, c)
            if not status() then
                return nil
            end
            return self[method](self, a, b, c)
        end
    end
    function write:swap(address, want, to)
        if not status() then
            return false, why
        end
        return self:swap(address, want, to)
    end
    local function calling(kind)
        local port = {}
        ports[kind] = port
        local bound, refused = {}, {}
        function port:routine(name)
            local hit = bound[name]
            if hit ~= nil then
                return hit
            end
            local reason = refused[name]
            if reason ~= nil then
                return nil, reason
            end
            if not status() then
                return nil, why
            end
            local row, token = calls[name], nil
            if row == nil or not row.valid then
                reason = "spec"
            elseif row.kind ~= kind then
                reason = "kind"
            else
                local base = channel:module(row.module)
                if base == nil then
                    reason = "unread"
                else
                    token, reason = mem:routine({ at = base + row.at, ctype = row.ctype, result = row.result })
                end
            end
            if token ~= nil then
                bound[name] = token
            else
                refused[name] = reason
            end
            return token, reason
        end
        function port:arm()
            local names = {}
            for name, row in pairs(calls) do
                if row.valid and row.kind == kind then
                    names[#names + 1] = name
                end
            end
            table.sort(names)
            for _, name in ipairs(names) do
                self:routine(name)
            end
        end
        function port:call(token, ...)
            if token == nil or not status() then
                return nil
            end
            return self:call(token, ...)
        end
        function port:buffer(form, size, align)
            if form ~= "uint64_t" and form ~= "uint32_t" and form ~= "float" then
                return nil
            end
            if
                type(size) ~= "number"
                or not (size >= 1 and size <= NativeMemory.COUNT_LIMIT and size % 1 == 0)
                or (align ~= nil and align ~= 16)
                or not status()
            then
                return nil
            end
            if align == 16 then
                return mem.ffi.new(form .. " __attribute__((aligned(16)))[?]", size)
            end
            return mem.ffi.new(form .. "[?]", size)
        end
        function port:hex64(value)
            if not status() then
                return nil
            end
            return NativeMemory.hex64_of(mem.ffi, value)
        end
        function port:uint64(high, low)
            if not status() then
                return nil
            end
            return mem.ffi.new("uint64_t", high) * 4294967296 + low
        end
        function port:uint64_of(text)
            if not status() then
                return nil
            end
            return NativeMemory.uint64_of(mem.ffi, text)
        end
        function port:bits(value)
            if not status() then
                return nil
            end
            return mem:bits(value)
        end
        if kind == "ui" then
            function port:status()
                local ready, reason = status()
                if not ready then
                    return false, reason
                end
                return true
            end
            function port:own(text)
                if not status() then
                    return nil
                end
                return mem:own(text)
            end
            function port:pair(x, y)
                if not status() then
                    return nil
                end
                local low, high = mem:bits(x), mem:bits(y)
                if low == nil or high == nil then
                    return nil
                end
                return self:uint64(high, low)
            end
        end
        if kind == "judge" then
            function port:find(base, layout, key, finder, invalid)
                if finder == nil or not status() then
                    return nil, "uncalled"
                end
                return mem:find(base, layout, key, finder, invalid)
            end
            local numbers, opening = baked.numbers or {}, nil
            function port:app()
                local exe = read:module("exe")
                if exe == nil or numbers.resource_global == nil or numbers.resource_owner == nil then
                    return nil
                end
                local root = read:ptr(exe + numbers.resource_global)
                if root == nil or root == 0 then
                    return nil
                end
                return read:ptr(root + numbers.resource_owner)
            end
            function port:open(manager, kind_hash, name)
                local routine = self:routine("resource_open")
                if routine == nil or type(manager) ~= "number" or manager == 0 then
                    return nil
                end
                if opening == nil then
                    opening = {
                        kind = self:buffer("uint64_t", 1),
                        name = self:buffer("uint64_t", 1),
                        result = self:buffer("uint64_t", 1),
                    }
                    if opening.kind == nil or opening.name == nil or opening.result == nil then
                        opening = nil
                        return nil
                    end
                end
                local k, n = self:uint64_of(kind_hash), self:uint64_of(name)
                if k == nil or n == nil then
                    return nil
                end
                opening.kind[0], opening.name[0], opening.result[0] = k, n, 0
                local found = self:call(routine, manager, opening.kind, opening.name, opening.result)
                if found == nil then
                    return nil
                end
                return found ~= 0
            end
        end
        return port
    end
    local access = {
        read = read,
        call = { judge = calling("judge"), ui = calling("ui"), world = calling("world") },
        write = write,
    }
    status()
    return access
end
return Core
