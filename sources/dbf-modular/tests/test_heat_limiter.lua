-- Actual Lua ownership component with an injected native ABI transport. No game,
-- native loading, HUD, input writer or thermal simulator substitutes for the C++ tests.
local Support = assert(loadfile("tests/support.lua"))()
local project = Support.project()
local Limiter = project.require("core/heat_limiter.lua")
local ffi = require("ffi")
local cases, checks = 0, 0
local function eq(a, b, why)
    checks = checks + 1
    assert(a == b, (why or "different") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function case(name, run)
    local okay, why = pcall(run)
    assert(okay, name .. ": " .. tostring(why))
    cases = cases + 1
end
local function fixture()
    local f = {
        enabled = true,
        loads = 0,
        validates = 0,
        begins = 0,
        binds = 0,
        ends = 0,
        reads = 0,
        token = 31,
        events = {},
        reports = {},
        state = 2,
        armed = 1,
        fault = 0,
    }
    f.services = {
        initialized = true,
        failed = false,
        recovering = false,
        backend = { base = 0x140000000 },
        weapon = {
            id = 18,
            unit_ref = 22,
            avatar_unit_ref = 9,
            ammo_kind = "heat",
            binding = { module_base = 0x140000000, record = 0x220000, avatar_record = 0x210000, avatar_id = 7 },
        },
    }
    f.helper = {
        new_token = function()
            return { [0] = 0 }
        end,
        validate = function(config)
            f.validates = f.validates + 1
            eq(config.game, f.services.backend.base)
            eq(config.avatar, f.services.weapon.binding.avatar_id)
            eq(config.avatar_record, f.services.weapon.binding.avatar_record)
            eq(config.weapon_record, f.services.weapon.binding.record)
            eq(config.avatar_unit, f.services.weapon.avatar_unit_ref)
            eq(config.weapon, f.services.weapon.id)
            eq(config.weapon_unit, f.services.weapon.unit_ref)
            eq(config.ceiling, 0.99)
            eq(config.resume, 0.8)
            eq(config.enforce, 1)
            if f.validate_throw then
                error("validation raised")
            end
            return f.validate_code or 1
        end,
        begin = function(config, token)
            f.begins = f.begins + 1
            f.events[#f.events + 1] = "begin"
            token[0] = f.no_token and 0 or f.token
            if f.begin_throw then
                error("begin raised after possible installation")
            end
            return f.begin_code or 1
        end,
        bind = function(token, config)
            f.binds = f.binds + 1
            eq(token, f.token)
            eq(config.weapon, f.services.weapon.id)
            if f.bind_throw then
                error("bind raised")
            end
            return f.bind_code or 1
        end,
        finish = function(token)
            f.ends = f.ends + 1
            f.events[#f.events + 1] = "end"
            eq(token, f.token, "exact owned64-bit token reaches cleanup")
            if f.end_throw then
                error("cleanup raised")
            end
            return f.end_code or 1
        end,
        read_status = function(token)
            f.reads = f.reads + 1
            if f.read_throw then
                error("status transport raised")
            end
            local out = f.status or {}
            out.size, out.abi, out.lease = f.status_size or 128, f.status_abi or 1, f.foreign_token or token
            out.state, out.fault = f.state, f.fault
            out.enabled, out.armed, out.cut, out.cleanup_pending = 1, f.armed, f.state == 3 and 1 or 0, f.pending or 0
            out.heat, out.limit, out.next_heat, out.charge = f.heat or 40, f.limit or 150, 41, 1
            f.status = out
            return f.read_code or 1, out
        end,
    }
    f.settings = {
        get = function(_, id)
            eq(id, "weapon.heat_limiter")
            return f.enabled
        end,
    }
    f.limiter = Limiter.new(project, {
        settings = f.settings,
        report = function(text)
            f.reports[#f.reports + 1] = text
        end,
        profile = { abi = 1, build = 26251122, dll = "native/DBFHeatLimiter26251122_aabb.dll" },
        retry_frames = 2,
        helper_factory = function(context, profile)
            eq(context, project)
            eq(profile.abi, 1)
            f.loads = f.loads + 1
            if f.load_throw then
                error("native helper missing")
            end
            return f.helper
        end,
    })
    function f:step()
        return self.limiter:update(self.services)
    end
    return f
end
case("withheld production bridge cannot load even with a saved true preference", function()
    local f = fixture()
    f.limiter.profile = project.require("core/heat_limiter_profile.lua")
    eq(f.limiter.profile.available, false)
    for _ = 1, 5 do
        eq(f:step(), true)
    end
    eq(f.limiter.state, "unavailable")
    eq(f.limiter.active, false)
    eq(f.limiter.token, nil)
    eq(f.loads, 0)
    eq(f.validates, 0)
    eq(f.begins, 0)
    eq(f.limiter:close(), true)
end)
case("no owner and disabled protection never load a native helper", function()
    local f = fixture()
    eq(f.limiter:update(nil), true)
    eq(f.limiter.active, false)
    f.enabled = false
    eq(f:step(), true)
    eq(f.limiter.state, "disabled")
    eq(f.limiter:close(), true)
    eq(f.ends, 0)
end)
case("incomplete ownership never reaches Validate or Begin", function()
    local changes = {
        function(s)
            s.initialized = false
        end,
        function(s)
            s.failed = true
        end,
        function(s)
            s.recovering = true
        end,
        function(s)
            s.weapon = nil
        end,
        function(s)
            s.weapon.known = false
        end,
        function(s)
            s.weapon.binding.module_base = 0x150000000
        end,
        function(s)
            s.weapon.binding.avatar_record = 0
        end,
        function(s)
            s.weapon.binding.avatar_id = 0xffffffff
        end,
        function(s)
            s.weapon.avatar_unit_ref = nil
        end,
    }
    for _, change in ipairs(changes) do
        local f = fixture()
        change(f.services)
        eq(f:step(), true)
        eq(f.loads, 0)
        eq(f.limiter.active, false)
    end
end)
case("ordinary observer follows native hot-weapon switch before Lua DTO refresh", function()
    local f = fixture()
    f.services.weapon.ammo_kind, f.state, f.armed = "rounds", 1, 0
    eq(f:step(), true)
    eq(f.loads, 1)
    eq(f.limiter.state, "observing")
    eq(f.limiter.active, false)
    -- Original weapon DTO intentionally remains the ordinary old weapon here.
    f.state, f.armed = 3, 1
    eq(f:step(), true)
    eq(f.limiter.state, "cut")
    eq(f.limiter.active, true)
    eq(f.begins, 1)
    eq(f.binds, 0, "native selection following requires no Lua rebind")
    f.services.weapon = nil
    eq(f:step(), true)
    eq(f.limiter.active, true, "native owner proof survives original DTO's polling gap")
    eq(f.ends, 0)
end)
case("weapon hints can be absent but actor ownership remains mandatory", function()
    local f = fixture()
    f.state, f.armed = 1, 0
    f.services.weapon.binding.record, f.services.weapon.id, f.services.weapon.unit_ref = nil, nil, nil
    f.helper.validate = function(config)
        f.validates = f.validates + 1
        eq(config.avatar_record, 0x210000)
        eq(config.avatar, 7)
        eq(config.avatar_unit, 9)
        eq(config.weapon_record, 0)
        eq(config.weapon, 0)
        eq(config.weapon_unit, 0)
        return 1
    end
    eq(f:step(), true)
    eq(f.limiter.state, "observing")
    eq(f.limiter.active, false)
    eq(f.begins, 1)
end)
case("helper unavailable is visible and does not fail original Core", function()
    local f = fixture()
    f.load_throw = true
    eq(f:step(), true)
    eq(f.limiter.state, "unavailable")
    eq(f.limiter.status:find("strict heat limiter unavailable", 1, true) ~= nil, true)
    eq(f.limiter.active, false)
    eq(f:step(), true)
    eq(f.loads, 1, "bounded retry avoids loading every frame")
    eq(#f.reports, 1, "unavailable protection reports once, not every frame")
    f.load_throw = false
    eq(f:step(), true)
    eq(f.loads, 2)
    eq(f.limiter.active, true)
    eq(f.reports[2], "Heat limiter: native protection acknowledged")
end)
case("only armed native status publishes activity; cut is still protected", function()
    local f = fixture()
    f.state, f.armed = 1, 0
    eq(f:step(), true)
    eq(f.limiter.state, "observing")
    eq(f.limiter.active, false, "Begin acknowledgement alone is not active protection")
    f.state, f.armed = 2, 1
    eq(f:step(), true)
    eq(f.limiter.active, true)
    f.state = 3
    eq(f:step(), true)
    eq(f.limiter.state, "cut")
    eq(f.limiter.active, true)
    eq(f.begins, 1)
    eq(f.binds, 0, "unchanged owner needs no repeated Bind")
    local snapshot = f.limiter:snapshot()
    eq(snapshot.active, true)
    eq(snapshot.state, "cut")
    eq(snapshot.native_status.lease, f.token)
    eq(snapshot, f.limiter:snapshot(), "one retained public DTO")
end)
case("weapon hint replacement does not rebind; actor replacement validates first", function()
    local f = fixture()
    eq(f:step(), true)
    f.services.weapon.id, f.services.weapon.unit_ref, f.services.weapon.binding.record = 21, 29, 0x230000
    eq(f:step(), true)
    eq(f.binds, 0)
    eq(f.begins, 1)
    eq(f.limiter.active, true)
    eq(f.validates, 1)
    f.services.weapon.binding.avatar_id, f.services.weapon.binding.avatar_record, f.services.weapon.avatar_unit_ref =
        8, 0x240000, 10
    eq(f:step(), true)
    eq(f.binds, 1)
    eq(f.validates, 2)
    eq(f.limiter.bound.weapon_record, 0x230000)
end)
case("refused validation has no native ownership", function()
    local f = fixture()
    f.validate_code, f.fault = 0, 4
    eq(f:step(), true)
    eq(f.limiter.state, "unavailable")
    eq(f.limiter.status:find("native witness", 1, true) ~= nil, true)
    eq(f.begins, 0)
    eq(f.limiter.token, nil)
    eq(f.limiter:close(), true)
    eq(f.ends, 0)
end)
case("every returned nonzero lease survives partial or thrown Begin", function()
    for _, result in ipairs({ 0, 2, "throw" }) do
        local f = fixture()
        f.begin_code, f.begin_throw = result == "throw" and 0 or result, result == "throw"
        f.end_code = 0
        eq(f:step(), false)
        eq(f.limiter.token[0], f.token)
        eq(f.limiter.active, false)
        eq(f.limiter:snapshot().cleanup_pending, true)
        eq(f.limiter:snapshot().native_status, nil)
        eq(f:step(), false)
        eq(f.begins, 1, "no new owner while cleanup is pending")
        f.end_code = 1
        eq(f.limiter:close(), true)
        eq(f.limiter.token, nil)
    end
end)
case("Begin without token never fabricates ownership or protection", function()
    local f = fixture()
    f.no_token = true
    eq(f:step(), true)
    eq(f.limiter.active, false)
    eq(f.limiter.state, "unavailable")
    eq(f.ends, 0)
end)
case("Bind failure withdraws protection and retains refused cleanup", function()
    local f = fixture()
    eq(f:step(), true)
    f.services.weapon.binding.avatar_id = 25
    f.bind_throw, f.end_throw = true, true
    eq(f:step(), false)
    eq(f.limiter.active, false)
    eq(f.limiter:snapshot().native_status, nil)
    eq(f.limiter.token[0], f.token)
    f.end_throw = false
    eq(f.limiter:close(), true)
end)
case("recoverable native owner unknown keeps watcher inactive and can recover without DTO refresh", function()
    local f = fixture()
    eq(f:step(), true)
    f.state, f.fault, f.armed, f.services.weapon = 4, 6, 0, nil
    eq(f:step(), true)
    eq(f.limiter.active, false)
    eq(f.limiter.state, "unavailable")
    eq(f.ends, 0)
    eq(f.limiter.token[0], f.token)
    f.state, f.fault, f.armed = 2, 0, 1
    eq(f:step(), true)
    eq(f.limiter.active, true)
    eq(f.begins, 1)
    eq(f.binds, 0)
end)
case("unreadable or malformed ReadStatus cannot preserve an armed publication", function()
    local corruptions = {
        function(f)
            f.read_code = 0
        end,
        function(f)
            f.read_throw = true
        end,
        function(f)
            f.status_size = 64
        end,
        function(f)
            f.status_abi = 2
        end,
        function(f)
            f.foreign_token = 999
        end,
        function(f)
            f.state = 17
        end,
        function(f)
            f.fault = 4
        end,
        function(f)
            f.pending = 1
        end,
        function(f)
            f.armed = 3
        end,
        function(f)
            f.heat = 0 / 0
        end,
        function(f)
            f.limit = 0
        end,
    }
    for _, corrupt in ipairs(corruptions) do
        local f = fixture()
        eq(f:step(), true)
        local public = f.limiter:snapshot()
        eq(public.active, true)
        corrupt(f)
        f.end_code = 0
        eq(f:step(), false)
        eq(f.limiter:snapshot(), public)
        eq(public.active, false)
        eq(public.cleanup_pending, true)
        eq(public.native_status, nil, "stale native armed receipt is not published")
        eq(f.limiter.token[0], f.token)
    end
end)
case("toggle off and unknown owner retire first; re-enable gets fresh generation", function()
    local f = fixture()
    eq(f:step(), true)
    f.enabled, f.end_code = false, 0
    eq(f:step(), false)
    eq(f.limiter.active, false)
    f.enabled = true
    eq(f:step(), false)
    eq(f.begins, 1)
    f.end_code, f.token = 1, 31
    eq(f:step(), true)
    eq(f.begins, 2)
    eq(f.limiter.active, true)
    f.services.recovering = true
    eq(f:step(), true)
    eq(f.limiter.token, nil)
    eq(f.limiter.active, false)
    eq(f.limiter.state, "waiting")
end)
case("closing disables before native End and never drops a refused owner", function()
    local f = fixture()
    eq(f:step(), true)
    local finish = f.helper.finish
    f.helper.finish = function(token)
        eq(f.limiter.active, false)
        eq(f.limiter.retiring, true)
        eq(f.limiter.public.active, false, "retained public DTO is withdrawn before native cleanup")
        eq(f.limiter.public.cleanup_pending, true)
        return finish(token)
    end
    f.end_code = 0
    eq(f.limiter:close(), false)
    eq(f.limiter.token[0], f.token)
    eq(f:step(), false)
    eq(f.begins, 1)
    f.end_code = 1
    eq(f.limiter:close(), true)
    local ends = f.ends
    eq(f.limiter:close(), true)
    eq(f.ends, ends)
    eq(f.limiter:snapshot().state, "closed")
end)
case("opaque64-bit native leases never pass through Lua double conversion", function()
    local f = fixture()
    f.token = ffi.new("uint64_t", 2 ^ 53) + ffi.new("uint64_t", 7)
    eq(f:step(), true)
    eq(f.limiter.active, true)
    eq(f.limiter.token[0], f.token)
    eq(f.limiter:close(), true)
end)
case("production FFI marshalling matches Config64 Status128 and retains pinned library", function()
    local loads, definitions, begins, ends = 0, 0, 0, 0
    local token = ffi.new("uint64_t", 2 ^ 53) + ffi.new("uint64_t", 31)
    local library = {}
    function library.DBFH_Validate(config)
        eq(tonumber(config.size), 64)
        eq(tonumber(config.abi), 1)
        eq(tonumber(config.game), 0x140000000)
        eq(tonumber(config.avatar_record), 0x210000)
        eq(tonumber(config.weapon_record), 0x220000)
        eq(tonumber(config.avatar), 7)
        eq(tonumber(config.avatar_unit), 9)
        eq(tonumber(config.weapon), 18)
        eq(tonumber(config.weapon_unit), 22)
        eq(math.abs(tonumber(config.ceiling) - 0.99) < 1e-6, true)
        eq(math.abs(tonumber(config.resume) - 0.8) < 1e-6, true)
        eq(tonumber(config.enforce), 1)
        eq(tonumber(config.reserved), 0)
        return 1
    end
    function library.DBFH_Begin(_, result)
        begins = begins + 1
        result[0] = token
        return 1
    end
    function library.DBFH_Bind(lease)
        eq(lease, token)
        return 1
    end
    function library.DBFH_End(lease)
        eq(lease, token)
        ends = ends + 1
        return 1
    end
    function library.DBFH_ReadStatus(lease, status)
        eq(lease, token)
        eq(tonumber(status.size), 128)
        eq(tonumber(status.abi), 1)
        status.lease, status.state, status.fault = token, 2, 0
        status.enabled, status.armed, status.cut, status.cleanup_pending = 1, 1, 0, 0
        status.heat, status.limit, status.next_heat, status.charge = 90, 150, 91, 1
        status.seen_shot, status.seen_windup, status.seen_heat, status.seen_beam = 3, 4, 5, 6
        return 1
    end
    local proxy = setmetatable({
        os = "Windows",
        load = function(path)
            loads = loads + 1
            eq(path, "dbf_modular/native/DBFHeatLimiter26251122_aabb.dll")
            return library
        end,
        cdef = function(text)
            definitions = definitions + 1
            return ffi.cdef(text)
        end,
    }, { __index = ffi })
    local globals = setmetatable({
        require = function(name)
            eq(name, "ffi")
            return proxy
        end,
    }, { __index = _G })
    local native_project = Support.project("dbf_modular", globals)
    local NativeLimiter = native_project.require("core/heat_limiter.lua")
    for _ = 1, 2 do
        local f = fixture()
        local limiter = NativeLimiter.new(native_project, {
            settings = f.settings,
            profile = { abi = 1, build = 26251122, dll = "native/DBFHeatLimiter26251122_aabb.dll" },
        })
        eq(limiter:update(f.services), true)
        eq(limiter.active, true)
        eq(limiter.token[0], token)
        eq(limiter:snapshot().native_status.seen_beam, 6)
        eq(limiter:close(), true)
    end
    eq(loads, 1, "native hook library stays strongly owned across generations")
    eq(definitions, 1, "hot reload must not redeclare shared FFI types")
    eq(begins, 2)
    eq(ends, 2)
    eq(ffi.sizeof("DBFH_Config"), 64)
    eq(ffi.offsetof("DBFH_Config", "avatar_record"), 16)
    eq(ffi.offsetof("DBFH_Config", "weapon_unit"), 44)
    eq(ffi.offsetof("DBFH_Config", "ceiling"), 48)
    eq(ffi.sizeof("DBFH_Status"), 128)
    eq(ffi.offsetof("DBFH_Status", "enabled"), 64)
    eq(ffi.offsetof("DBFH_Status", "heat"), 80)
    eq(ffi.offsetof("DBFH_Status", "seen_beam"), 120)
end)
print("heat limiter adapter: " .. cases .. " cases / " .. checks .. " checks; ownership, acknowledgements and cleanup")
