-- Real FFI buffers/production bridge; native functions and module bytes are synthetic.
-- No process memory, Windows libraries, installed files or game calls are used.
local ffi = require("ffi")
local Support = assert(loadfile("tests/support.lua"))()
local project = Support.project()
local Build, Native = project.require("sampling/build.lua"), project.require("sampling/native.lua")
local checks = 0
local function eq(actual, expected, why)
    checks = checks + 1
    assert(actual == expected, (why or "different") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function check(value, why)
    eq(not not value, true, why)
end
local function binary(hex)
    return (hex:gsub("..", function(value)
        return string.char(tonumber(value, 16))
    end))
end
local function fixture()
    local f = {
        memory = {},
        bases = { exe = 0x10000000, game = 0x30000000 },
        calls = {},
        binds = {},
        executable = true,
        position = 0x50000000,
        pose = 0x51000000,
        node = 3,
        alive = true,
        x = 1200,
        y = 700,
        clip = 0,
        reads = 0,
        pages = 0,
        short = {},
    }
    function f:put(at, raw)
        for index = 1, #raw do
            self.memory[at + index - 1] = raw:byte(index)
        end
    end
    function f:uint(at, value, width)
        for index = 0, (width or 4) - 1 do
            self.memory[at + index] = value % 256
            value = math.floor(value / 256)
        end
    end
    function f:install(module)
        local base, identity = self.bases[module], Build.modules[module]
        self:put(base, "MZ" .. string.rep("\0", 62))
        self:uint(base + 60, 0x100)
        self:put(base + 0x100, "PE\0\0" .. string.rep("\0", 80))
        self:uint(base + 0x104, identity.machine, 2)
        self:uint(base + 0x108, identity.timestamp)
        self:uint(base + 0x118, identity.magic, 2)
        self:uint(base + 0x150, identity.image_size)
        for _, spec in pairs(Build.calls) do
            if spec.module == module then
                self:put(base + spec.rva + (spec.head_at or 0), binary(spec.head))
            end
        end
        if module == "exe" then
            for _, witness in ipairs(Build.geometry_witnesses) do
                self:put(base + witness.rva, binary(witness.hex))
            end
        end
    end
    f:install("exe")
    f:install("game")
    local position = ffi.new("float[4]", { 1, 2, 3, 0 })
    f:put(f.position, ffi.string(position, 16))
    function f:matrix(values)
        self:put(self.pose, ffi.string(ffi.new("float[16]", values), 64))
    end
    f:matrix({ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 2, 3, 1 })
    local backend = { base = f.bases.game }
    function backend.read(at, size)
        f.reads = f.reads + 1
        if f.before_read then
            f.before_read(at, size)
        end
        if f.short[at] ~= nil then
            return f.short[at]
        end
        local out = {}
        for index = 0, size - 1 do
            local value = f.memory[at + index]
            if value == nil then
                return nil
            end
            out[index + 1] = string.char(value)
        end
        return table.concat(out)
    end
    f.native = Native.new(backend, {
        module = function(name)
            return f.bases[name]
        end,
        executable = function(at, size)
            f.pages = f.pages + 1
            f.last_page_at, f.last_page_size = at, size
            return f.executable
        end,
        bind = function(ctype, at, name)
            eq(ctype, Build.calls[name].ctype, "exact verified native prototype")
            f.binds[name] = (f.binds[name] or 0) + 1
            return function(...)
                f.calls[#f.calls + 1] = name
                if f.raise == name then
                    error("native getter refused")
                end
                local result
                if name == "unit_alive" then
                    eq(select(1, ...), 77)
                    result = f.alive
                elseif name == "unit_node" then
                    local unit, node_name = ...
                    eq(unit, 77)
                    eq(node_name, f.node_hash or Build.numbers.avatar_head_node)
                    result = f.node
                elseif name == "unit_world_position" or name == "unit_world_pose" then
                    local unit, node = ...
                    eq(unit, 77)
                    eq(node, f.node)
                    result = name == "unit_world_pose" and f.pose or f.position
                elseif name == "unit_box" then
                    local out, unit, ignore_hidden = ...
                    eq(unit, 77)
                    eq(ignore_hidden, 1, "invisible meshes cannot enlarge the sight envelope")
                    eq(tonumber(ffi.cast("uintptr_t", out)) % 16, 0)
                    if not f.no_box_output then
                        local values = f.box_values or { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 2, 3, 1, 0.1, 0.2, 0.3 }
                        ffi.copy(out, ffi.new("float[19]", values), 76)
                    end
                    result = f.bad_box_return and 0 or ffi.cast("uintptr_t", out)
                elseif name == "camera_world_to_screen" then
                    local out, camera, input = ...
                    eq(camera, 0x60000000)
                    eq(tonumber(ffi.cast("uintptr_t", input)) % 16, 0)
                    eq(tonumber(ffi.cast("uintptr_t", out)) % 16, 0)
                    f.project_index = (f.project_index or 0) + 1
                    local expected = f.points_expected and f.points_expected[f.project_index]
                        or f.expected
                        or { 1, 2, 3 }
                    eq(input[0], expected[1])
                    eq(input[1], expected[2])
                    eq(input[2], expected[3])
                    if not f.no_output then
                        -- A full SIMD-sized write must fit the owning allocation.
                        out[0], out[1], out[2], out[3] = f.x, f.y, f.clip, 42
                    end
                    result = ffi.cast("uintptr_t", out)
                elseif name == "reloading" then
                    result = false
                end
                if f.after_call then
                    f.after_call(name)
                end
                return result
            end
        end,
    })
    return f
end
do
    local f = fixture()
    for _, name in ipairs({ "input", "output", "pose" }) do
        local at, owner = tonumber(ffi.cast("uintptr_t", f.native[name])), f.native[name .. "_owner"]
        local delta = at - tonumber(ffi.cast("uintptr_t", owner))
        eq(at % 16, 0)
        check(delta >= 0 and delta <= 15)
        check(delta + (name == "pose" and 64 or 16) <= ffi.sizeof(owner), "complete aligned buffer fits owner")
    end
    eq(f.native:call("unit_alive", 77), true)
    eq(f.native:call("unit_alive", 77), true)
    eq(f.binds.unit_alive, 1)
    eq(f.pages, 2, "fresh executable guard even for cached function")
    local old_reads = f.reads
    eq(f.native:call("unit_alive", 77), true)
    check(f.reads > old_reads, "fresh PE and head checks")
    eq(f.native:call("reloading", 0x65000000, 123), false, "false native result stays known false")
    eq(f.last_page_at, f.bases.game + Build.calls.reloading.rva)
    local reads = f.reads
    eq(f.native:call("not_a_routine"), nil)
    eq(f.reads, reads)
end
-- Mutate byte-level module/header/code facts before a cached callable can run.
for _, defect in ipairs({
    "dos_missing",
    "dos_short",
    "dos_magic",
    "pe_too_small",
    "pe_too_large",
    "pe_short",
    "pe_magic",
    "machine",
    "timestamp",
    "optional_magic",
    "image_size",
    "no_execute",
    "head_short",
    "head_changed",
}) do
    local f = fixture()
    eq(f.native:call("unit_alive", 77), true)
    local base = f.bases.exe
    if defect == "dos_missing" then
        f.short[base] = false
    elseif defect == "dos_short" then
        f.short[base] = "MZ"
    elseif defect == "dos_magic" then
        f:put(base, "XX")
    elseif defect == "pe_too_small" then
        f:uint(base + 60, 32)
    elseif defect == "pe_too_large" then
        f:uint(base + 60, 1048577)
    elseif defect == "pe_short" then
        f.short[base + 0x100] = "PE\0\0"
    elseif defect == "pe_magic" then
        f:put(base + 0x100, "BAD!")
    elseif defect == "machine" then
        f:uint(base + 0x104, 0x14c, 2)
    elseif defect == "timestamp" then
        f:uint(base + 0x108, Build.modules.exe.timestamp + 1)
    elseif defect == "optional_magic" then
        f:uint(base + 0x118, 0x10b, 2)
    elseif defect == "image_size" then
        f:uint(base + 0x150, Build.modules.exe.image_size - 4096)
    elseif defect == "no_execute" then
        f.executable = false
    elseif defect == "head_short" then
        f.short[base + Build.calls.unit_alive.rva] = "\0"
    elseif defect == "head_changed" then
        f:put(base + Build.calls.unit_alive.rva, "\0")
    end
    local calls = #f.calls
    local value, why = f.native:call("unit_alive", 77)
    eq(value, nil, defect)
    check(type(why) == "string", defect .. " reason")
    eq(#f.calls, calls, defect .. " never invokes stale cached getter")
    eq(f.binds.unit_alive, 1)
end
do
    local f = fixture()
    local base, row = f.bases.exe, Build.calls.unit_alive
    local masked
    for index = 1, #row.mask / 2 do
        if row.mask:sub(index * 2 - 1, index * 2) == "00" then
            masked = index
            break
        end
    end
    check(masked ~= nil)
    local at = base + row.rva + masked - 1
    f.memory[at] = (f.memory[at] + 1) % 256
    eq(f.native:call("unit_alive", 77), true, "relocation-masked byte can differ")
    f.bases.exe = 0x70000000
    f:install("exe")
    eq(f.native:call("unit_alive", 77), true)
    eq(f.binds.unit_alive, 2, "changed module base rebinds after fresh identity proof")
    f.bases.exe = 0
    local calls = #f.calls
    eq(f.native:call("unit_alive", 77), nil)
    eq(#f.calls, calls)
    f.bases.exe = 2 ^ 47
    eq(f.native:call("unit_alive", 77), nil)
    local g = fixture()
    g:uint(g.bases.game + 0x108, Build.modules.game.timestamp + 1)
    eq(g.native:call("reloading", 0x65000000, 123), nil, "Game.dll getter also requires exact module identity")
    local outside = fixture()
    outside.native.specs.unit_alive.rva = Build.modules.exe.image_size
    eq(outside.native:call("unit_alive", 77), nil, "target bounds precede executable/bind")
    eq(outside.binds.unit_alive, nil)
end
do
    local f, validated = fixture(), 0
    local function current(unit)
        eq(unit, 77)
        validated = validated + 1
        return true
    end
    local x, y, clip, resolved_node = f.native:project(0x60000000, 77, nil, current)
    eq(x, 1200)
    eq(y, 700)
    eq(clip, 0)
    eq(resolved_node, 3)
    eq(validated, 5)
    eq(table.concat(f.calls, ","), "unit_alive,unit_node,unit_world_position,camera_world_to_screen")
    collectgarbage("collect")
    check(f.native.input_owner ~= nil and f.native.output_owner ~= nil, "GC retains owners behind derived pointers")
    eq(f.native.output[3], 42, "SIMD fourth lane remains within retained owner")
    f.calls = {}
    x = f.native:project(0x60000000, 77, 3, current)
    eq(x, 1200)
    eq(table.concat(f.calls, ","), "unit_alive,unit_world_position,camera_world_to_screen")
end
-- The existing guarded getter resolves a caller-selected semantic bone on the
-- same unit; no additional alive call or ABI is introduced for FPS anchors.
for _, hash in ipairs({ Build.numbers.viewmodel_weapon_node, 0, 4294967295 }) do
    local f = fixture()
    f.node_hash = hash
    local x, y, clip, node = f.native:project(0x60000000, 77, nil, function()
        return true
    end, nil, hash)
    eq(x, 1200)
    eq(y, 700)
    eq(clip, 0)
    eq(node, 3)
    eq(table.concat(f.calls, ","), "unit_alive,unit_node,unit_world_position,camera_world_to_screen")
end
for _, hash in ipairs({ -1, 0.5, 4294967296, math.huge, 0 / 0, "4fdd3337", false, {} }) do
    local f = fixture()
    local x, why = f.native:project(0x60000000, 77, nil, function()
        return true
    end, nil, hash)
    eq(x, nil)
    eq(why, "Anchor node hash unavailable")
    eq(#f.calls, 0, "invalid hashes are refused before any native getter")
end
do
    local f, current = fixture(), true
    f.node_hash, f.node = Build.numbers.viewmodel_weapon_node, -1
    local x, why = f.native:project(0x60000000, 77, nil, function()
        return current
    end, nil, f.node_hash)
    eq(x, nil)
    eq(why, "Anchor node unavailable", "a missing attachment cannot fall back to the player head")
    eq(table.concat(f.calls, ","), "unit_alive,unit_node")
    f.calls, f.node = {}, 3
    f.after_call = function(name)
        if name == "unit_node" then
            current = false
        end
    end
    x, why = f.native:project(0x60000000, 77, nil, function()
        return current
    end, nil, f.node_hash)
    eq(x, nil)
    eq(why, "Anchor identity changed")
    eq(table.concat(f.calls, ","), "unit_alive,unit_node", "attachment lookup preserves the next-getter identity fence")
end
do
    local f = fixture()
    eq(
        f.native:project(0x60000000, 77, 3, function()
            return true
        end, nil, "unused"),
        1200,
        "explicit node does not resolve or consume a semantic hash"
    )
    eq(table.concat(f.calls, ","), "unit_alive,unit_world_position,camera_world_to_screen")
    eq(Build.numbers.avatar_viewmodel_offset, 0x10c0)
    eq(Build.numbers.camera_queue_head, 0x1f8)
    eq(Build.numbers.camera_queue_tail, 0x1fc)
end
-- Caller guards include current camera/HUD. Every transition fence must stop
-- before its next getter; the final fence must prevent native projection.
for invalid_after = 1, 5 do
    local f, seen = fixture(), 0
    local x, why = f.native:project(0x60000000, 77, nil, function()
        seen = seen + 1
        return seen ~= invalid_after
    end)
    eq(x, nil)
    eq(why, "Anchor identity changed")
    eq(#f.calls, invalid_after - 1)
end
-- Current live wrappers end at RET. Neighboring function bytes are not a
-- witness: they changed from old CC padding in the same pinned executable.
do
    local live = {
        unit_alive = "4883ec28e857b9eaff4885c00f95c04883c428c3",
        unit_world_position = "40534883ec204863dae872d6eaff488bc84c8b0041ff90e8000000488bcb48c1e1064883c130488b40284803c14883c4205bc3",
        unit_world_pose = "40534883ec204863dae8e2d5eaff488bc84c8b0041ff90e8000000488bcb48c1e10648034828488bc14883c4205bc3",
    }
    for name, head in pairs(live) do
        eq(Build.calls[name].head, head, "current live semantic getter witness")
        eq(head:sub(-2), "c3")
        local f = fixture()
        f.memory[f.bases.exe + Build.calls[name].rva + #head / 2] = 0
        if name == "unit_alive" then
            eq(f.native:call(name, 77), true)
        else
            eq(f.native:call(name, 77, 3), name == "unit_world_pose" and f.pose or f.position)
        end
    end
end
for _, case in ipairs({
    { matrix = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 2, 3, 1 }, point = { 2, 2.5, 2.75 } },
    { matrix = { 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 1, 2, 3, 1 }, point = { 0.5, 3, 2.75 } },
    { matrix = { 2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0.5, 0, 1, 2, 3, 1 }, point = { 3, 3.5, 2.875 } },
    { matrix = { 1, 0, 0, 0, 0.25, 1, 0, 0, 0, 0, 1, 0, 1, 2, 3, 1 }, point = { 2.125, 2.5, 2.75 } },
}) do
    local f = fixture()
    f:matrix(case.matrix)
    f.expected = case.point
    local x, y, clip, node = f.native:project(0x60000000, 77, nil, function()
        return true
    end, { x = 1, y = 0.5, z = -0.25 })
    eq(x, 1200)
    eq(y, 700)
    eq(clip, 0)
    eq(node, 3)
    eq(table.concat(f.calls, ","), "unit_alive,unit_node,unit_world_pose,camera_world_to_screen")
    eq(f.binds.unit_world_position, nil, "local offsets never perform a redundant position getter")
end
do
    local f = fixture()
    eq(
        f.native:project(0x60000000, 77, nil, function()
            return true
        end, { x = 0, y = 0, z = 0 }),
        1200
    )
    eq(f.binds.unit_world_pose, nil, "zero local offset preserves existing translation-only path")
    f.node = 0
    f.expected = { 2, 2, 3 }
    local x, _, _, node = f.native:project(0x60000000, 77, 0, function()
        return true
    end, { x = 1, y = 0, z = 0 })
    eq(x, 1200)
    eq(node, 0, "explicit root node remains valid")
end
for _, offset in ipairs({
    {},
    { x = 0, y = 0 },
    { x = 0 / 0, y = 0, z = 0 },
    { x = math.huge, y = 0, z = 0 },
    {
        x = 2.01,
        y = 0,
        z = 0,
    },
    {
        x = 0,
        y = -2.01,
        z = 0,
    },
}) do
    local f = fixture()
    eq(
        f.native:project(0x60000000, 77, nil, function()
            return true
        end, offset),
        nil
    )
    eq(#f.calls, 0, "invalid local offset refuses before native getters")
end
for _, defect in ipairs({
    "nan",
    "infinite",
    "zero_axis",
    "parallel_axes",
    "affine_row",
    "homogeneous",
    "huge_axis",
    "huge_origin",
    "short_pose",
    "missing_pose",
    "changed_head",
}) do
    local f = fixture()
    local matrix = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 2, 3, 1 }
    if defect == "nan" then
        matrix[1] = 0 / 0
    elseif defect == "infinite" then
        matrix[7] = math.huge
    elseif defect == "zero_axis" then
        matrix[1] = 0
    elseif defect == "parallel_axes" then
        matrix[5] = 1
        matrix[6] = 0
    elseif defect == "affine_row" then
        matrix[4] = 1
    elseif defect == "homogeneous" then
        matrix[16] = 0
    elseif defect == "huge_axis" then
        matrix[1] = 1e5
    elseif defect == "huge_origin" then
        matrix[13] = 1e8
    elseif defect == "short_pose" then
        f.short[f.pose] = "\0"
    elseif defect == "missing_pose" then
        f.pose = 0
    elseif defect == "changed_head" then
        f.memory[f.bases.exe + Build.calls.unit_world_pose.rva] = 0
    end
    if f.pose ~= 0 then
        f:matrix(matrix)
    end
    local x, why = f.native:project(0x60000000, 77, nil, function()
        return true
    end, { x = 1, y = 0, z = 0 })
    eq(x, nil, defect)
    check(type(why) == "string")
    eq(f.binds.camera_world_to_screen, nil, "invalid pose never reaches native projection")
end
do
    local f, current = fixture(), true
    f.after_call = function(name)
        if name == "camera_world_to_screen" then
            current = false
        end
    end
    local x, why = f.native:project(0x60000000, 77, nil, function()
        return current
    end)
    eq(x, nil, "identity change inside projection cannot publish coordinates")
    eq(why, "Anchor identity changed")
    eq(#f.calls, 4, "post-call identity guard performs no extra native getter")
end
do
    local f = fixture()
    eq(
        f.native:project(0x60000000, 77, nil, function()
            return true
        end),
        1200
    )
    f.memory[f.bases.exe + Build.calls.unit_alive.rva] = 0
    local x, why = f.native:project(0x60000000, 77, nil, function()
        return true
    end)
    eq(x, nil)
    eq(why, "Native anchor witness changed: unit_alive", "project preserves exact Unit.alive refusal diagnostics")
end
do
    local f = fixture()
    f.expected = { 2, 2, 3 }
    eq(
        f.native:project(0x60000000, 77, 3, function()
            return true
        end, { x = 1, y = 0, z = 0 }),
        1200
    )
    f.pose = 0x52000000
    f:matrix({ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 10, 20, 30, 1 })
    f.expected = { 11, 20, 30 }
    eq(
        f.native:project(0x60000000, 77, 3, function()
            return true
        end, { x = 1, y = 0, z = 0 }),
        1200
    )
    eq(f.binds.unit_world_pose, 1, "only callable is cached; animated pose/pointer is read again")
    collectgarbage("collect")
    check(f.native.pose_owner ~= nil, "derived matrix pointer retains its owner")
end
for _, defect in ipairs({
    "missing_guard",
    "throwing_guard",
    "dead_unit",
    "bad_node",
    "bad_position",
    "short_position",
    "nonfinite_position",
    "getter_throw",
    "unwritten_output",
    "nonfinite_output",
    "clipped_output",
}) do
    local f = fixture()
    local validate = function()
        return true
    end
    if defect == "missing_guard" then
        validate = nil
    elseif defect == "throwing_guard" then
        validate = function()
            error("identity unavailable")
        end
    elseif defect == "dead_unit" then
        f.alive = false
    elseif defect == "bad_node" then
        f.node = -1
    elseif defect == "bad_position" then
        f.position = 0
    elseif defect == "short_position" then
        f.short[f.position] = "\0"
    elseif defect == "nonfinite_position" then
        local raw = ffi.new("float[3]", { 0 / 0, 2, 3 })
        f:put(f.position, ffi.string(raw, 12))
    elseif defect == "getter_throw" then
        f.raise = "unit_world_position"
    elseif defect == "unwritten_output" then
        f.no_output = true
    elseif defect == "nonfinite_output" then
        f.x = 0 / 0
    elseif defect == "clipped_output" then
        f.clip = 1.01
    end
    local x, why = f.native:project(0x60000000, 77, nil, validate)
    eq(x, nil, defect)
    check(type(why) == "string", defect .. " reason")
end
do
    local f = fixture()
    eq(f.native:close(), true)
    eq(f.native:close(), true)
    eq(f.native.input, nil)
    eq(f.native.output, nil)
    eq(f.native.input_owner, nil)
    eq(f.native.output_owner, nil)
    eq(f.native.pose, nil)
    eq(f.native.pose_owner, nil)
    eq(f.native:call("unit_alive", 77), nil)
    eq(
        f.native:project(0x60000000, 77, nil, function()
            return true
        end),
        nil
    )
    eq(#f.calls, 0)
    eq(f.reads, 0, "closed bridge does not touch retired native resources")
end
-- Integrate the actual byte-decoding Session with the actual guarded Native
-- bridge. Change a producer identity between native getters, not before sample.
local SessionFixture = assert(loadfile("tests/sampling_fixture.lua"))()
local function session_fixture()
    local f = SessionFixture.new()
    local B, N = f.context.require("sampling/build.lua"), f.context.require("sampling/native.lua")
    -- Distinct values are essential: Original DBF +16 references identify ECS
    -- records, while pinned HUD+ passes the fresh +12 engine handles to Unit.
    f.body_engine, f.weapon_engine = 14117, 14145
    f.uint(f.actor_record + B.numbers.record_engine_unit, f.body_engine)
    f.uint(f.weapon_record + B.numbers.record_engine_unit, f.weapon_engine)
    f.unit_calls = {}
    local bases = { game = f.backend.base, exe = 0x80000000 }
    for name, pin in pairs(B.modules) do
        local base = bases[name]
        f.put(base, "MZ" .. string.rep("\0", 62))
        f.uint(base + 60, 0x80)
        f.put(base + 0x80, "PE\0\0" .. string.rep("\0", 80))
        f.put(base + 0x84, string.char(pin.machine % 256, math.floor(pin.machine / 256)))
        f.uint(base + 0x88, pin.timestamp)
        f.put(base + 0x98, string.char(pin.magic % 256, math.floor(pin.magic / 256)))
        f.uint(base + 0xd0, pin.image_size)
    end
    for _, spec in pairs(B.calls) do
        f.put(bases[spec.module] + spec.rva + (spec.head_at or 0), binary(spec.head))
    end
    f.float(0x61000000, 1)
    f.float(0x61000004, 2)
    f.float(0x61000008, 3)
    f.put(
        0x61001000,
        ffi.string(
            ffi.new("float[16]", {
                1,
                0,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                0,
                1,
                0,
                1,
                2,
                3,
                1,
            }),
            64
        )
    )
    f.getters = {}
    f.sampler.native_factory = function(backend)
        return N.new(backend, {
            module = function(name)
                return bases[name]
            end,
            executable = function()
                return true
            end,
            bind = function(_, _, name)
                return function(output, second, third)
                    f.getters[#f.getters + 1] = name
                    local unit
                    if name:sub(1, 5) == "unit_" then
                        unit = tonumber(output)
                        f.unit_calls[#f.unit_calls + 1] = { name = name, unit = unit }
                    end
                    if name == "unit_world_pose" or name == "unit_world_position" then
                        f.project_unit = unit
                    end
                    if f.after_getter then
                        f.after_getter(name, unit or f.project_unit)
                    end
                    if name == "unit_alive" then
                        return unit == f.body_engine or unit == f.weapon_engine or unit == f.viewmodel_engine
                    end
                    if name == "unit_node" then
                        if unit == f.viewmodel_engine then
                            eq(second, B.numbers.viewmodel_weapon_node, "FPS resolves the actual attachment hash")
                            return 8
                        end
                        eq(unit, f.body_engine, "player node resolves the native handle, never its DBF reference")
                        eq(second, B.numbers.avatar_head_node)
                        return 3
                    end
                    if name == "unit_world_position" then
                        eq(unit == f.body_engine or unit == f.weapon_engine or unit == f.viewmodel_engine, true)
                        return 0x61000000
                    end
                    if name == "unit_world_pose" then
                        eq(
                            unit == f.body_engine or unit == f.weapon_engine or unit == f.viewmodel_engine,
                            true,
                            "bone pose requires fresh engine handle"
                        )
                        return 0x61001000
                    end
                    if name == "camera_world_to_screen" then
                        if f.project_unit == f.viewmodel_engine then
                            eq(third[0], 1)
                            eq(third[1], 2.5, "FPS calibration transforms forward in its live bone basis")
                            eq(third[2], 3)
                        end
                        output[0], output[1], output[2] = 800, 500, 0
                        return ffi.cast("uintptr_t", output)
                    end
                    if name == "reloading" then
                        return false
                    end
                end
            end,
        })
    end
    return f
end
do
    local f = session_fixture()
    f:first_person()
    local model = f:sample(1)
    eq(model.known, true, f.sampler.reason)
    eq(model.anchors.viewmodel.known, true, "actual guarded Native accepts the separately owned FPS handle")
    eq(model.anchors.viewmodel.unit, f.viewmodel_engine)
    eq(model.anchors.viewmodel.unit_ref, nil)
    eq(model.anchors.viewmodel.node, 8)
    eq(model.anchors.body.known, false)
    eq(model.anchors.weapon.known, false)
    eq(
        table.concat(f.getters, ","),
        "unit_alive,unit_node,unit_world_pose,camera_world_to_screen",
        "calibrated FPS resolves one pose point with no duplicate alive/getter"
    )
    eq(f.sampler.r.reads <= 512, true, "all actual Native FPS fences fit the production read budget")
    for _, call in ipairs(f.unit_calls) do
        eq(call.unit, f.viewmodel_engine, "FP getters cannot consume TP body or gun handles")
    end
    eq(f.sampler:close(), true)
end
do
    local f = session_fixture()
    f.set_camera_request(6)
    f.action(f.n.first_person_action_bit, false)
    f.action(f.n.aim_action_bit, true)
    local model = f:sample(1)
    eq(model.aim.first_person, false, "camera annotation does not rewrite the native lifecycle bit")
    eq(model.aim.aiming, true)
    eq(model.aim.viewmodel_active, true, "owned kind6 enables the actual custom FP view while aiming")
    eq(model.anchors.viewmodel.known, true)
    eq(model.anchors.viewmodel.unit, f.viewmodel_engine)
    eq(model.anchors.body.known, false)
    eq(model.anchors.weapon.known, false)
    eq(table.concat(f.getters, ","), "unit_alive,unit_node,unit_world_pose,camera_world_to_screen")
    eq(f.sampler.r.reads <= 512, true)
    eq(f.sampler:close(), true)
end
do
    local f = session_fixture()
    f.action(f.n.aim_action_bit, true)
    local model = f:sample(1)
    eq(model.aim.first_person, false)
    eq(model.aim.viewmodel_active, false, "normal kind4 aim retains third-person positioning")
    eq(model.anchors.viewmodel.known, false)
    eq(model.anchors.body.known, true)
    eq(model.anchors.weapon.known, true)
    eq(
        table.concat(f.getters, ","),
        "unit_alive,unit_node,unit_world_pose,camera_world_to_screen,unit_alive,unit_world_pose,camera_world_to_screen"
    )
    eq(f.sampler:close(), true)
end
for _, after in ipairs({ "unit_world_pose", "camera_world_to_screen" }) do
    for _, mutation in ipairs({ "fps", "request", "queue", "controller", "body", "weapon", "wield", "camera" }) do
        local f = session_fixture()
        local request = f:first_person()
        f.after_getter = function(name)
            if name ~= after then
                return
            end
            if mutation == "fps" then
                f.uint(f.controller + f.n.avatar_viewmodel_offset, f.viewmodel_engine + 1)
            elseif mutation == "request" then
                f.uint(request + 8, f.info.id + 1)
            elseif mutation == "queue" then
                f.uint(f.camera_manager + f.n.camera_queue_tail, 1)
            elseif mutation == "controller" then
                f.uint(f.controller + f.n.avatar_controller_dive_identity_offset, 43)
            elseif mutation == "body" then
                f.uint(f.actor_record + f.n.record_engine_unit, f.body_engine + 1)
            elseif mutation == "weapon" then
                f.uint(f.weapon_record + f.n.record_engine_unit, f.weapon_engine + 1)
            elseif mutation == "wield" then
                f.uint(f.selector_row, f.info.id + 1)
            else
                f.pointer(f.camera_manager, f.camera + 0x100)
            end
        end
        local model = f:sample(1)
        eq(model.anchors.viewmodel.known, false, after .. ": fresh FPS callback rejects " .. mutation)
        eq(model.anchors.viewmodel.token, nil)
        eq(model.weapon.count, 31, "optional attachment refusal preserves combat facts")
        eq(
            table.concat(f.getters, ","),
            "unit_alive,unit_node,unit_world_pose"
                .. ((after == "camera_world_to_screen" or mutation ~= "camera") and ",camera_world_to_screen" or ""),
            "only copied-point projection may finish before the full transaction rejects a replaced owner"
        )
        eq(f.sampler:close(), true)
    end
end
do
    local f = session_fixture()
    local model = f:sample(1)
    eq(model.known, true, f.sampler.reason)
    eq(model.anchors.body.known, true)
    eq(model.anchors.weapon.known, true)
    eq(model.anchors.body.unit, f.body_engine)
    eq(model.anchors.weapon.unit, f.weapon_engine)
    eq(model.anchors.body.unit_ref, 77, "Original player reference remains separate")
    eq(model.anchors.weapon.unit_ref, 88, "Original weapon reference remains separate")
    for _, call in ipairs(f.unit_calls) do
        eq(call.unit == 77 or call.unit == 88, false, "reference cannot reach a Unit getter")
    end
    eq(
        table.concat(f.getters, ","),
        "unit_alive,unit_node,unit_world_pose,camera_world_to_screen,unit_alive,unit_world_pose,camera_world_to_screen"
    )
    eq(f.sampler:close(), true)
end
do
    local f = session_fixture()
    local model = f:sample(1)
    eq(model.anchors.body.known, true)
    for _, reference in ipairs({ 77, 88 }) do
        local alive, why, called = f.sampler.native:call("unit_alive", reference)
        eq(alive, false, "fixture reproduces live Unit.alive false for DBF reference")
        eq(why, nil)
        eq(called, true, "reference rejection is native false, not a missing witness")
    end
    eq(f.sampler:close(), true)
end
for _, role in ipairs({ "body", "weapon" }) do
    local f = session_fixture()
    f.after_getter = function(name, unit)
        local engine = role == "body" and f.body_engine or f.weapon_engine
        if name == "unit_world_pose" and unit == engine then
            f.uint(
                (role == "body" and f.actor_record or f.weapon_record) + Build.numbers.record_engine_unit,
                engine + 1
            )
        end
    end
    local model = f:sample(1)
    eq(model.anchors[role].known, false, "changed +12 handle retires the projected role with +16 unchanged")
    eq(model.anchors.weapon.known, role == "body", "player handle replacement cannot discard valid gun pose")
    eq(model.anchors.body.known, role == "weapon", "gun handle replacement cannot discard valid player pose")
    eq(model.known, true, "engine-model replacement alone does not replace the ECS actor")
    eq(f.sampler:close(), true)
end
for _, shift in ipairs({ "camera", "camera_manager", "hud_root", "gui_context", "retired_context" }) do
    local f = session_fixture()
    f.after_getter = function(name)
        if name ~= "unit_world_pose" then
            return
        end
        if shift == "camera" then
            f.pointer(0x56000000, 0x56002000)
        elseif shift == "camera_manager" then
            f.pointer(f.backend.base + f.n.camera_manager, 0x57000000)
            f.pointer(0x57000000, 0x56001000)
        elseif shift == "hud_root" then
            f.pointer(f.backend.base + f.n.roots_hud_manager_rva, f.root + 0x100000)
        elseif shift == "gui_context" then
            f.pointer(f.panel + f.n.widget_gui_context, 0x58000000)
        elseif shift == "retired_context" then
            f.uint(0x40000000, 0)
        end
    end
    local model = f:sample(1)
    eq(model.anchors.body.known, false, shift .. " cannot publish a projected anchor")
    eq(table.concat(f.getters, ","), "unit_alive,unit_node,unit_world_pose", shift .. " fences final native projection")
    eq(f.sampler:close(), true)
end
for _, shift in ipairs({ "camera", "camera_manager", "hud_root", "gui_context", "retired_context" }) do
    local f = session_fixture()
    f.after_getter = function(name)
        if name ~= "camera_world_to_screen" then
            return
        end
        if shift == "camera" then
            f.pointer(0x56000000, 0x56002000)
        elseif shift == "camera_manager" then
            f.pointer(f.backend.base + f.n.camera_manager, 0x57000000)
            f.pointer(0x57000000, 0x56001000)
        elseif shift == "hud_root" then
            f.pointer(f.backend.base + f.n.roots_hud_manager_rva, f.root + 0x100000)
        elseif shift == "gui_context" then
            f.pointer(f.panel + f.n.widget_gui_context, 0x58000000)
        elseif shift == "retired_context" then
            f.uint(0x40000000, 0)
        end
    end
    local model = f:sample(1)
    eq(model.anchors.body.known, false, shift .. " cannot publish after projection switches identity")
    eq(table.concat(f.getters, ","), "unit_alive,unit_node,unit_world_pose,camera_world_to_screen")
    eq(f.sampler:close(), true)
end
-- Conservative weapon bounds: real aligned output buffers, pinned getters,
-- refused lifetime transitions and fresh world-scalar projection batches.
do
    local f = fixture()
    local at = tonumber(ffi.cast("uintptr_t", f.native.box))
    local delta = at - tonumber(ffi.cast("uintptr_t", f.native.box_owner))
    eq(at % 16, 0)
    check(delta >= 0 and delta + 80 <= ffi.sizeof(f.native.box_owner))
    eq(f.native:geometry_ready(), f.bases.exe)
    local box = assert(f.native:unit_box(77, function(unit)
        return unit == 77
    end))
    eq(box.matrix[13], 1)
    check(math.abs(box.half[1] - 0.1) < 1e-6)
    eq(table.concat(f.calls, ","), "unit_alive,unit_box")
    f.box_values = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 4, 5, 6, 1, 0.5, 0.6, 0.7 }
    eq(
        f.native:unit_box(77, function()
            return true
        end),
        box,
        "reuses storage, never stale geometry"
    )
    eq(box.matrix[13], 4)
end
for _, witness in ipairs(Build.geometry_witnesses) do
    local f = fixture()
    f:put(f.bases.exe + witness.rva, "X")
    local result, why = f.native:unit_box(77, function()
        return true
    end)
    eq(result, nil)
    check(why:find("witness", 1, true))
    eq(#f.calls, 0, "changed converter/registry/attachment layout never reaches Unit getter")
end
for _, defect in ipairs({
    "no_guard",
    "dead",
    "before_box",
    "during_box",
    "unwritten",
    "wrong_return",
    "nan",
    "negative_extent",
    "huge_extent",
    "empty",
    "affine",
    "singular",
}) do
    local f, current = fixture(), true
    local validate = function()
        return current
    end
    if defect == "no_guard" then
        validate = nil
    elseif defect == "dead" then
        f.alive = false
    elseif defect == "before_box" or defect == "during_box" then
        f.after_call = function(name)
            if name == (defect == "before_box" and "unit_alive" or "unit_box") then
                current = false
            end
        end
    elseif defect == "unwritten" then
        f.no_box_output = true
    elseif defect == "wrong_return" then
        f.bad_box_return = true
    else
        local v = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 2, 3, 1, 0.1, 0.2, 0.3 }
        if defect == "nan" then
            v[17] = 0 / 0
        elseif defect == "negative_extent" then
            v[17] = -1
        elseif defect == "huge_extent" then
            v[18] = 9
        elseif defect == "empty" then
            v[17], v[18], v[19] = 0, 0, 0
        elseif defect == "affine" then
            v[16] = 0
        elseif defect == "singular" then
            v[1] = 0
        end
        f.box_values = v
    end
    local result, why = f.native:unit_box(77, validate)
    eq(result, nil, defect)
    check(type(why) == "string")
    if defect == "before_box" or defect == "dead" then
        eq(table.concat(f.calls, ","), "unit_alive")
    end
end
do
    local f = fixture()
    local points = { { x = 1, y = 2, z = 3 }, { x = 4, y = 5, z = 6 } }
    f.points_expected = { { 1, 2, 3 }, { 4, 5, 6 } }
    local out = assert(f.native:project_points(0x60000000, points, function()
        return true
    end))
    eq(#out, 2)
    eq(out[2].x, 1200)
    eq(
        table.concat(f.calls, ","),
        "camera_world_to_screen,camera_world_to_screen",
        "copied corners never repeat Unit lookups"
    )
    f.points_expected, f.project_index, points[2] = { { 1, 2, 3 } }, 0, nil
    eq(
        f.native:project_points(0x60000000, points, function()
            return true
        end),
        out
    )
    eq(#out, 1, "shorter batch cannot expose old projected corners")
end
for _, defect in ipairs({
    "no_guard",
    "camera_changed",
    "nan_point",
    "unwritten",
    "clipped",
    "nan_output",
    "bad_camera",
    "too_many",
}) do
    local f, current = fixture(), true
    local points, camera = { { x = 1, y = 2, z = 3 }, { x = 1, y = 2, z = 3 } }, 0x60000000
    local guard = function()
        return current
    end
    if defect == "no_guard" then
        guard = nil
    elseif defect == "camera_changed" then
        f.after_call = function()
            current = false
        end
    elseif defect == "nan_point" then
        points[1].x = 0 / 0
    elseif defect == "unwritten" then
        f.no_output = true
    elseif defect == "clipped" then
        f.clip = 2
    elseif defect == "nan_output" then
        f.x = math.huge
    elseif defect == "bad_camera" then
        camera = 0
    elseif defect == "too_many" then
        for i = 3, 65 do
            points[i] = points[1]
        end
    end
    local result, why = f.native:project_points(camera, points, guard)
    eq(result, nil, defect)
    check(type(why) == "string")
    if defect == "camera_changed" then
        eq(#f.calls, 1, "changed camera stops before the next corner")
    end
end

do
    local f = fixture()
    local points = { { x = 1, y = 2, z = 3 }, { x = 1, y = 2, z = 3 }, { x = 1, y = 2, z = 3 } }
    check(f.native:project_points(0x60000000, points, function()
        return true
    end))
    points[2] = nil
    eq(#points, 3, "fixture retains a sparse batch with a trailing corner")
    local result, why = f.native:project_points(0x60000000, points, function()
        return true
    end)
    eq(result, nil, "sparse batch never publishes retained old corners")
    check(type(why) == "string")
    eq(f.native:close(), true)
    local calls, reads = #f.calls, f.reads
    eq(
        f.native:project_points(0x60000000, { { x = 1, y = 2, z = 3 } }, function()
            return true
        end),
        nil
    )
    eq(
        f.native:unit_box(77, function()
            return true
        end),
        nil
    )
    eq(#f.calls, calls, "closed optional services do not call native functions")
    eq(f.reads, reads, "closed optional services do not touch retired resources")
end
-- Reduced camera fences are used only for copied coordinates inside Session's
-- final full-owner transaction; all native Unit getters retain full fences.
do
    local f, full, camera = fixture(), 0, 0
    local x = f.native:project(
        0x60000000,
        77,
        nil,
        function()
            full = full + 1
            return true
        end,
        nil,
        nil,
        function()
            camera = camera + 1
            return true
        end
    )
    eq(x, 1200)
    eq(full, 3, "full proof precedes every Unit getter")
    eq(camera, 2, "copied-point projection fences the camera before and after")
    eq(table.concat(f.calls, ","), "unit_alive,unit_node,unit_world_position,camera_world_to_screen")
end
for _, defect in ipairs({ "lost_after_alive", "lost_after_node", "lost_camera", "throwing_camera", "bad_camera_guard" }) do
    local f, current = fixture(), true
    f.after_call = function(name)
        if
            (defect == "lost_after_alive" and name == "unit_alive")
            or (defect == "lost_after_node" and name == "unit_node")
        then
            current = false
        end
    end
    local guard = function()
        return defect ~= "lost_camera"
    end
    if defect == "throwing_camera" then
        guard = function()
            error("camera unavailable")
        end
    elseif defect == "bad_camera_guard" then
        guard = true
    end
    local x, why = f.native:project(0x60000000, 77, nil, function()
        return current
    end, nil, nil, guard)
    eq(x, nil, defect)
    check(type(why) == "string")
    eq(f.binds.camera_world_to_screen, nil, "reduced camera fence cannot bypass a refused Unit/camera owner")
end
print("guarded native sampling: " .. checks .. " checks passed")
