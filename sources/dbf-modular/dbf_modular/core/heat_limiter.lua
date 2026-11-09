-- Core-owned native heat protection. No HUD, second weapon reader, input poll,
-- Lua callback hook or heat writes. Only the native owner may acknowledge armed.
local Limiter = {}
Limiter.__index = Limiter
local CONFIG_SIZE, STATUS_SIZE, ABI = 64, 128, 1
local CONFIG_FIELDS = {
    "game",
    "avatar_record",
    "weapon_record",
    "avatar",
    "avatar_unit",
    "weapon",
    "weapon_unit",
    "ceiling",
    "resume",
    "enforce",
}
local BIND_FIELDS = { "game", "avatar_record", "avatar", "avatar_unit", "ceiling", "resume", "enforce" }
local RECOVERABLE = { [5] = true, [6] = true, [7] = true, [8] = true, [13] = true }
local STATUS_FIELDS = {
    "size",
    "abi",
    "state",
    "fault",
    "callbacks",
    "cut_count",
    "denied_shots",
    "cut_beams",
    "unknown_owners",
    "enabled",
    "armed",
    "cut",
    "cleanup_pending",
    "heat",
    "limit",
    "next_heat",
    "charge",
    "seen_shot",
    "seen_windup",
    "seen_heat",
    "seen_beam",
}
local STATUS_FLAGS = { "enabled", "armed", "cut", "cleanup_pending" }
local FAULTS = {
    [0] = "none",
    "configuration",
    "another native owner",
    "unsupported image",
    "native witness",
    "native read",
    "weapon owner",
    "heat component",
    "thermal state",
    "hook installation",
    "foreign hook",
    "callback in flight",
    "hook cleanup",
    "unsupported weapon",
}
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function integer(value, low, high)
    return finite(value) and value % 1 == 0 and value >= low and value < high
end
local function pointer(value)
    return integer(value, 65536, 2 ^ 47) and value % 8 == 0
end
local function u32(value)
    return integer(value, 0, 4294967295)
end
local function nonzero(value)
    return (type(value) == "number" and finite(value) and value > 0 and value % 1 == 0)
        or type(value) == "cdata" and value ~= 0
end
local function directory(context)
    local dir = context.dir or context.root
    if type(dir) ~= "string" or dir == "" then
        dir = type(context.path) == "string" and context.path:match("^(.*)[/\\][^/\\]+%.lua$") or nil
    end
    assert(type(dir) == "string" and dir ~= "", "native helper directory unavailable")
    return dir:gsub("[/\\]$", "")
end
local function native_helper(context, profile)
    assert(profile.abi == ABI and tostring(profile.build) == "26251122", "native helper profile mismatch")
    local name = profile.dll
    assert(
        type(name) == "string"
            and (
                name:match("^DBFHeatLimiter26251122_[0-9a-f]+%.dll$")
                or name:match("^native/DBFHeatLimiter26251122_[0-9a-f]+%.dll$")
            ),
        "native helper filename is not pinned"
    )
    local ffi = require("ffi")
    assert(ffi.os == "Windows" and ffi.abi("64bit"), "Windows x64 native helper required")
    if not pcall(ffi.typeof, "DBFH_Config") then
        ffi.cdef([[
            typedef struct DBFH_Config {
                uint32_t size, abi;
                uint64_t game, avatar_record, weapon_record;
                uint32_t avatar, avatar_unit, weapon, weapon_unit;
                float ceiling, resume;
                uint32_t enforce, reserved;
            } DBFH_Config;
            typedef struct DBFH_Status {
                uint32_t size, abi, state, fault;
                uint64_t lease, callbacks, cut_count, denied_shots, cut_beams, unknown_owners;
                uint32_t enabled, armed, cut, cleanup_pending;
                float heat, limit, next_heat, charge;
                uint64_t seen_shot, seen_windup, seen_heat, seen_beam;
            } DBFH_Status;
            uint32_t DBFH_Validate(const DBFH_Config *);
            uint32_t DBFH_Begin(const DBFH_Config *, uint64_t *);
            uint32_t DBFH_Bind(uint64_t, const DBFH_Config *);
            uint32_t DBFH_End(uint64_t);
            uint32_t DBFH_ReadStatus(uint64_t, DBFH_Status *);
        ]])
    end
    assert(
        ffi.sizeof("DBFH_Config") == CONFIG_SIZE and ffi.sizeof("DBFH_Status") == STATUS_SIZE,
        "native heat helper ABI mismatch"
    )
    local path = directory(context) .. "/" .. name
    -- A refusing cleanup must never allow FFI GC to unload hook/trampoline code.
    local scope = type(context.scope) == "table" and context.scope or context
    scope.dbf_heat_limiter_libraries = scope.dbf_heat_limiter_libraries or {}
    local libraries = scope.dbf_heat_limiter_libraries
    local lib = libraries[path] or ffi.load(path)
    libraries[path] = lib
    local config, status, out = ffi.new("DBFH_Config"), ffi.new("DBFH_Status"), {}
    local function pack(value)
        config.size, config.abi, config.reserved = CONFIG_SIZE, ABI, 0
        for _, key in ipairs(CONFIG_FIELDS) do
            config[key] = value[key]
        end
        return config
    end
    return {
        new_token = function()
            return ffi.new("uint64_t[1]")
        end,
        validate = function(value)
            return tonumber(lib.DBFH_Validate(pack(value)))
        end,
        begin = function(value, token)
            return tonumber(lib.DBFH_Begin(pack(value), token))
        end,
        bind = function(token, value)
            return tonumber(lib.DBFH_Bind(token, pack(value)))
        end,
        finish = function(token)
            return tonumber(lib.DBFH_End(token))
        end,
        read_status = function(token)
            ffi.fill(status, STATUS_SIZE)
            status.size, status.abi = STATUS_SIZE, ABI
            local accepted = tonumber(lib.DBFH_ReadStatus(token, status))
            for _, key in ipairs(STATUS_FIELDS) do
                out[key] = tonumber(status[key])
            end
            -- Preserve all64 bits of native lease identity, including above2^53.
            out.lease = status.lease
            return accepted, out
        end,
    }
end
function Limiter.new(context, dependencies)
    local deps = dependencies or {}
    return setmetatable({
        context = assert(context),
        settings = assert(deps.settings),
        globals = deps.globals or _G,
        report = deps.report or function() end,
        factory = deps.helper_factory or native_helper,
        profile = deps.profile,
        config = {},
        bound = {},
        public = {},
        frame = 0,
        retry_at = 0,
        retry_frames = deps.retry_frames or 60,
        state = "waiting",
        status = "waiting for native weapon owner",
        active = false,
    }, Limiter)
end
function Limiter:_report(message)
    if self.last_report ~= message then
        self.last_report = message
        pcall(self.report, "Heat limiter: " .. message)
    end
end
function Limiter:_status(state, message, quiet)
    self.state, self.status, self.active = state, message, false
    self:snapshot()
    if not quiet and (state == "unavailable" or state == "cleanup_pending") then
        self:_report(message)
    end
end
function Limiter:_unavailable(message)
    self:_status("unavailable", "strict heat limiter unavailable: " .. tostring(message))
    self.retry_at = self.frame + self.retry_frames
    return true
end
function Limiter:_reason(message)
    if self.helper then
        local okay, accepted, status = pcall(self.helper.read_status, 0)
        if
            okay
            and accepted == 1
            and type(status) == "table"
            and status.size == STATUS_SIZE
            and status.abi == ABI
            and integer(status.fault, 1, 14)
        then
            return message .. " (" .. FAULTS[status.fault] .. ")"
        end
    end
    return message
end
function Limiter:_helper()
    if self.helper then
        return self.helper
    end
    if not self.profile then
        self.profile =
            assert(self.context.require("core/heat_limiter_profile.lua"), "native helper profile unavailable")
    end
    assert(self.profile.available ~= false, "native bridge withheld after a live test crash")
    local helper = self.factory(self.context, self.profile)
    for _, name in ipairs({ "new_token", "validate", "begin", "bind", "finish", "read_status" }) do
        assert(type(helper) == "table" and type(helper[name]) == "function", "native helper method missing: " .. name)
    end
    self.helper = helper
    return helper
end
function Limiter:_end(reason)
    self.active, self.native_status = false, nil
    self:snapshot()
    if not self.token then
        return true
    end
    self.pending = true
    self:_status("cleanup_pending", "heat limiter cleanup pending: " .. tostring(reason), true)
    local okay, accepted = pcall(self.helper.finish, self.token[0])
    if not okay or accepted ~= 1 then
        self:_status("cleanup_pending", "heat limiter cleanup pending: " .. tostring(reason))
        return false, self.status
    end
    self.token, self.pending, self.native_status = nil, nil, nil
    for key in pairs(self.bound) do
        self.bound[key] = nil
    end
    self:snapshot()
    return true
end
function Limiter:_suspend(state, reason)
    local closed, why = self:_end(reason)
    if not closed then
        return false, why
    end
    self:_status(state, reason)
    return true
end
function Limiter:_configuration(services)
    if type(services) ~= "table" or services.initialized ~= true or services.failed or services.recovering then
        return nil, "waiting for native Core"
    end
    local weapon, backend = services.weapon, services.backend
    if type(backend) ~= "table" or not pointer(backend.base) then
        return nil, "waiting for native Core backend"
    end
    local config = self.config
    local binding = type(weapon) == "table" and weapon.binding
    if
        type(binding) ~= "table"
        or weapon.known == false
        or binding.module_base ~= backend.base
        or not pointer(binding.avatar_record)
        or not u32(binding.avatar_id)
        or not u32(weapon.avatar_unit_ref)
    then
        -- The original DTO is sampled at10Hz. The native watcher MUST continue
        -- following the current local selection during a Lua DTO gap or switch.
        -- Its callbacks revalidate the actor and resolve the wield themselves.
        if self.token and self.bound.game == backend.base then
            for _, key in ipairs(CONFIG_FIELDS) do
                config[key] = self.bound[key]
            end
            return config
        end
        return nil, "waiting for complete actor ownership"
    end
    config.game, config.avatar_record, config.weapon_record = backend.base, binding.avatar_record, binding.record
    config.avatar, config.avatar_unit = binding.avatar_id, weapon.avatar_unit_ref
    -- Weapon fields are initial hints only, never native firing authority.
    if pointer(binding.record) and u32(weapon.id) and u32(weapon.unit_ref) then
        config.weapon_record, config.weapon, config.weapon_unit = binding.record, weapon.id, weapon.unit_ref
    else
        config.weapon_record, config.weapon, config.weapon_unit = 0, 0, 0
    end
    config.ceiling, config.resume, config.enforce = 0.99, 0.8, 1
    return config
end
function Limiter:_read()
    local okay, accepted, status = pcall(self.helper.read_status, self.token[0])
    if
        not okay
        or accepted ~= 1
        or type(status) ~= "table"
        or status.size ~= STATUS_SIZE
        or status.abi ~= ABI
        or status.lease ~= self.token[0]
        or not integer(status.state, 0, 7)
        or not integer(status.fault, 0, 14)
    then
        return nil, "native status acknowledgement unavailable"
    end
    for _, name in ipairs(STATUS_FLAGS) do
        if status[name] ~= 0 and status[name] ~= 1 then
            return nil, "native status flags invalid"
        end
    end
    self.native_status = status
    if status.cleanup_pending ~= 0 or status.state == 5 then
        return nil, "native cleanup requested"
    end
    if status.state == 4 and (status.fault == 0 or RECOVERABLE[status.fault]) then
        self:_status(
            "unavailable",
            "strict heat limiter unavailable: " .. (status.fault ~= 0 and FAULTS[status.fault] or "current weapon")
        )
        return true
    end
    if status.fault ~= 0 or status.state == 6 then
        return nil, status.fault ~= 0 and FAULTS[status.fault] or "native protection unavailable"
    end
    if status.enabled == 1 and status.armed == 1 and (status.state == 2 or status.state == 3) then
        if not finite(status.heat) or status.heat < 0 or not finite(status.limit) or status.limit <= 0 then
            return nil, "native thermal status invalid"
        end
        self.state, self.status, self.active =
            status.state == 3 and "cut" or "armed",
            status.state == 3 and "strict heat limiter: cooling" or "strict heat limiter: armed",
            true
        if not self.reported_armed then
            self.reported_armed = true
            self:_report("native protection acknowledged")
        end
    else
        self:_status("observing", "waiting for native protection acknowledgement")
    end
    self:snapshot()
    return true
end
function Limiter:update(services)
    self.active, self.native_status = false, nil
    self:snapshot()
    if self.closed or self.retiring then
        return false, "heat limiter is retiring"
    end
    self.frame = self.frame + 1
    if self.pending then
        local closed, why = self:_end("previous native operation")
        if not closed then
            return false, why
        end
    end
    if type(self.settings.get) ~= "function" or self.settings:get("weapon.heat_limiter") ~= true then
        return self:_suspend("disabled", "heat limiter disabled")
    end
    local config, why = self:_configuration(services)
    if not config then
        return self:_suspend("waiting", why)
    end
    if self.frame < self.retry_at then
        return true
    end
    local loaded, helper = pcall(self._helper, self)
    if not loaded then
        return self:_unavailable(helper)
    end
    local changed = not self.token
    for _, key in ipairs(BIND_FIELDS) do
        changed = changed or self.bound[key] ~= config[key]
    end
    if changed then
        local validated, accepted = pcall(helper.validate, config)
        if not validated or accepted ~= 1 then
            local cleaned, problem = self:_end("native validation refused")
            if not cleaned then
                return false, problem
            end
            return self:_unavailable(self:_reason("native validation refused"))
        end
        if self.token then
            local called, bound = pcall(helper.bind, self.token[0], config)
            if not called or bound ~= 1 then
                local cleaned, problem = self:_end("native binding refused")
                if not cleaned then
                    return false, problem
                end
                return self:_unavailable(self:_reason("native binding refused"))
            end
        else
            local made, token = pcall(helper.new_token)
            if not made then
                return self:_unavailable(token)
            end
            local called, begun = pcall(helper.begin, config, token)
            if nonzero(token[0]) then
                self.token = token
            end
            if not called or begun ~= 1 or not self.token then
                local cleaned, problem = self:_end("native installation not acknowledged")
                if not cleaned then
                    return false, problem
                end
                return self:_unavailable(self:_reason("native installation not acknowledged"))
            end
        end
        for _, key in ipairs(CONFIG_FIELDS) do
            self.bound[key] = config[key]
        end
    end
    local observed, reason = self:_read()
    if not observed then
        local cleaned, problem = self:_end(reason)
        if not cleaned then
            return false, problem
        end
        return self:_unavailable(reason)
    end
    return true
end
function Limiter:snapshot()
    local out = self.public
    out.state, out.active, out.status = self.state, self.active, self.status
    out.cleanup_pending, out.native_status = self.pending == true, self.native_status
    return out
end
function Limiter:close()
    if self.closed then
        return true
    end
    self.retiring, self.active = true, false
    local closed, why = self:_end("retiring")
    if not closed then
        return false, why
    end
    self.closed = true
    self:_status("closed", "heat limiter closed")
    return true
end
return Limiter
