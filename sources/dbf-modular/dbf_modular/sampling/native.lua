-- Read-only anchor getters borrowed from the verified HUD+ ABI, isolated from
-- its product, camera ownership, world-UI engine and input. No code-page writes.
local Build = mod.require("sampling/build.lua")
local Native = {}
Native.__index = Native
local function address(v)
    return type(v) == "number" and v == v and v >= 65536 and v < 2 ^ 47 and v % 1 == 0
end
local function number(v)
    return type(v) == "number" and v == v and math.abs(v) < math.huge
end
local function bytes(hex)
    return (hex:gsub("..", function(v)
        return string.char(tonumber(v, 16))
    end))
end
local function uint(raw, at, width)
    local value = 0
    for i = width - 1, 0, -1 do
        value = value * 256 + raw:byte(at + i + 1)
    end
    return value
end
function Native.new(backend, deps)
    deps = deps or {}
    local ffi = deps.ffi or require("ffi")
    local bit = require("bit")
    local module, executable = deps.module, deps.executable
    if not module or not executable then
        if not pcall(ffi.typeof, "DBFM_HUD_MBI") then
            ffi.cdef([[
              typedef struct { uint64_t base,allocation; uint32_t allocation_protect,pad;
                uint64_t region; uint32_t state,protect,kind,pad2; } DBFM_HUD_MBI;
              void *dbfm_hud_module(const char *) __asm__("GetModuleHandleA");
              size_t dbfm_hud_query(const void *, void *, size_t) __asm__("VirtualQuery");
            ]])
        end
        local kernel = ffi.load("kernel32")
        local mbi = ffi.new("DBFM_HUD_MBI[1]")
        module = module
            or function(which)
                if which == "game" then
                    return backend.base
                end
                return tonumber(ffi.cast("uintptr_t", kernel.dbfm_hud_module(nil)))
            end
        executable = executable
            or function(at, size)
                if
                    kernel.dbfm_hud_query(ffi.cast("const void *", at), mbi, ffi.sizeof(mbi[0])) ~= ffi.sizeof(mbi[0])
                then
                    return false
                end
                local row = mbi[0]
                local protect = tonumber(row.protect)
                local code = bit.band(protect, 0xff)
                return tonumber(row.state) == 0x1000
                    and bit.band(protect, 0x100) == 0
                    and (code == 0x10 or code == 0x20 or code == 0x40 or code == 0x80)
                    and at + size <= tonumber(row.base + row.region)
            end
    end
    local function aligned(size)
        local owner = ffi.new("uint8_t[?]", (size or 16) + 15)
        local at = math.floor((tonumber(ffi.cast("uintptr_t", owner)) + 15) / 16) * 16
        return owner, ffi.cast("float *", at)
    end
    local input_owner, input = aligned()
    local output_owner, output = aligned()
    local pose_owner, pose = aligned(64)
    local box_owner, box = aligned(80)
    local specs = {}
    for name, spec in pairs(Build.calls) do
        local row = {}
        for k, v in pairs(spec) do
            row[k] = v
        end
        row.head, row.mask = bytes(spec.head), bytes(spec.mask)
        assert(#row.head == #row.mask, "Invalid native anchor witness: " .. name)
        specs[name] = row
    end
    return setmetatable({
        b = backend,
        ffi = ffi,
        bit = bit,
        module = module,
        executable = executable,
        bind = deps.bind or function(ctype, at)
            return ffi.cast(ctype, at)
        end,
        specs = specs,
        functions = {},
        addresses = {},
        input_owner = input_owner,
        input = input,
        output_owner = output_owner,
        output = output,
        pose_owner = pose_owner,
        pose = pose,
        box_owner = box_owner,
        box = box,
        box_result = { matrix = {}, half = {} },
        projected_points = {},
    }, Native)
end
function Native:target(name)
    if self.closed then
        return nil, "Anchor services closed"
    end
    local spec = self.specs[name]
    if not spec then
        return nil, "Unknown anchor routine"
    end
    local base = self.module(spec.module)
    if not address(base) then
        return nil, "Native anchor module unavailable"
    end
    local identity = Build.modules[spec.module]
    if not identity then
        return nil, "Native anchor module unpinned"
    end
    local dos = self.b.read(base, 64)
    if type(dos) ~= "string" or #dos ~= 64 or dos:sub(1, 2) ~= "MZ" then
        return nil, "Native anchor module header unreadable"
    end
    local pe = uint(dos, 60, 4)
    if pe < 64 or pe > 1048576 then
        return nil, "Native anchor PE offset invalid"
    end
    local header = self.b.read(base + pe, 84)
    if
        type(header) ~= "string"
        or #header ~= 84
        or header:sub(1, 4) ~= "PE\0\0"
        or uint(header, 4, 2) ~= identity.machine
        or uint(header, 8, 4) ~= identity.timestamp
        or uint(header, 24, 2) ~= identity.magic
        or uint(header, 80, 4) ~= identity.image_size
    then
        return nil, "Native anchor module identity changed"
    end
    if spec.rva < 0 or spec.rva + (spec.head_at or 0) + #spec.head > identity.image_size then
        return nil, "Native anchor target outside image"
    end
    local at = base + spec.rva
    if not self.executable(at, #spec.head + (spec.head_at or 0)) then
        return nil, "Native anchor code unavailable"
    end
    local head = self.b.read(at + (spec.head_at or 0), #spec.head)
    if type(head) ~= "string" or #head ~= #spec.head then
        return nil, "Native anchor witness unreadable"
    end
    for index = 1, #head do
        local mask = spec.mask:byte(index)
        if self.bit.band(head:byte(index), mask) ~= self.bit.band(spec.head:byte(index), mask) then
            return nil, "Native anchor witness changed: " .. name
        end
    end
    return at, nil, spec
end
function Native:call(name, ...)
    local at, why, spec = self:target(name)
    if not at then
        return nil, why
    end
    local fn = self.functions[name]
    if not fn or self.addresses[name] ~= at then
        fn = self.bind(spec.ctype, at, name)
        self.functions[name], self.addresses[name] = fn, at
    end
    local okay, result = pcall(fn, ...)
    if not okay then
        return nil, tostring(result)
    end
    return result, nil, true
end
-- Optional FP clearance uses copied bounds of the current owned weapon family.
-- Verify the complete current-build getter/converter and Unit graph witnesses
-- before reading that graph. No SDK table-offset guesses or Lua Unit fabrication.
function Native:geometry_ready()
    local at, why = self:target("unit_box")
    if not at then
        return nil, why
    end
    local base = at - self.specs.unit_box.rva
    for _, witness in ipairs(Build.geometry_witnesses or {}) do
        local raw = bytes(witness.hex)
        if witness.code ~= false and not self.executable(base + witness.rva, #raw) then
            return nil, "Weapon geometry code unavailable"
        end
        if self.b.read(base + witness.rva, #raw) ~= raw then
            return nil, "Weapon geometry witness changed"
        end
    end
    return base
end
local function fresh(validate, unit)
    if type(validate) ~= "function" then
        return false
    end
    local okay, current = pcall(validate, unit)
    return okay and current == true
end
function Native:unit_box(unit, validate)
    if self.closed then
        return nil, "Anchor services closed"
    end
    if not number(unit) or unit % 1 ~= 0 or unit < 1 or unit >= 4294967295 then
        return nil, "Weapon bounds identity changed"
    end
    local ready, why = self:geometry_ready()
    if not ready then
        return nil, why
    end
    for i = 0, 19 do
        self.box[i] = 0 / 0
    end
    if not fresh(validate, unit) then
        return nil, "Weapon bounds identity changed"
    end
    local alive, alive_reason = self:call("unit_alive", unit)
    if alive ~= true then
        return nil, alive_reason or "Weapon bounds unit unavailable"
    end
    if not fresh(validate, unit) then
        return nil, "Weapon bounds identity changed"
    end
    local result, reason, called = self:call("unit_box", self.box, unit, 1)
    if not called then
        return nil, reason
    end
    if tonumber(result) ~= tonumber(self.ffi.cast("uintptr_t", self.box)) or not fresh(validate, unit) then
        return nil, "Weapon bounds identity changed"
    end
    local out = self.box_result
    for i = 0, 18 do
        local value = tonumber(self.box[i])
        if not number(value) or math.abs(value) > 1e7 then
            return nil, "Weapon bounds nonfinite or out of range"
        end
        if i < 16 then
            out.matrix[i + 1] = value
        else
            if value < 0 or value > 8 then
                return nil, "Weapon bounds extent out of range"
            end
            out.half[i - 15] = value
        end
    end
    local m = out.matrix
    if math.abs(m[4]) > 1e-5 or math.abs(m[8]) > 1e-5 or math.abs(m[12]) > 1e-5 or math.abs(m[16] - 1) > 1e-5 then
        return nil, "Weapon bounds not affine"
    end
    local det = m[1] * (m[6] * m[11] - m[7] * m[10])
        - m[5] * (m[2] * m[11] - m[3] * m[10])
        + m[9] * (m[2] * m[7] - m[3] * m[6])
    if math.abs(det) < 1e-8 or math.max(out.half[1], out.half[2], out.half[3]) <= 1e-6 then
        return nil, "Weapon bounds degenerate"
    end
    return out
end
-- Projects only current copied world scalars. The caller proves the full Unit
-- family around this batch; each corner still rechecks the current camera/HUD.
function Native:project_points(camera, points, validate)
    if self.closed then
        return nil, "Anchor services closed"
    end
    if not address(camera) or type(points) ~= "table" or #points < 1 or #points > 64 then
        return nil, "Weapon bounds projection unavailable"
    end
    local out = self.projected_points
    local count = #points
    for index = 1, count do
        local point = points[index]
        if type(point) ~= "table" or not number(point.x) or not number(point.y) or not number(point.z) then
            return nil, "Weapon bounds point unavailable"
        end
        if not fresh(validate) then
            return nil, "Weapon bounds camera changed"
        end
        self.input[0], self.input[1], self.input[2] = point.x, point.y, point.z
        self.output[0], self.output[1], self.output[2] = 0 / 0, 0 / 0, 0 / 0
        local result, why, called = self:call("camera_world_to_screen", self.output, camera, self.input)
        if not called then
            return nil, why
        end
        local x, y, clip = tonumber(self.output[0]), tonumber(self.output[1]), tonumber(self.output[2])
        if not number(x) or not number(y) or not number(clip) or clip > 1 then
            return nil, "Weapon bounds clipped"
        end
        local p = out[index] or {}
        out[index], p.x, p.y, p.clip = p, x, y, clip
    end
    if not fresh(validate) then
        return nil, "Weapon bounds camera changed"
    end
    for i = #out, count + 1, -1 do
        out[i] = nil
    end
    return out
end
-- Offset is in the sampled node's local right/forward/up model units. Keep
-- translation-only callers on their existing getter; never retain a unit pose.
-- A nil node resolves a semantic hash on this same owned unit. Existing callers
-- retain the head hash; FPS callers supply the witnessed attachment hash.
-- An optional camera-only fence is for copied-point projection inside a caller
-- transaction that rechecks the FULL Unit owner before publishing its model.
-- Every Unit getter below still requires the original full owner validator.
function Native:project(camera, unit, node, validate, offset, node_hash, camera_validate)
    if self.closed then
        return nil, "Anchor services closed"
    end
    if not address(camera) or not number(unit) or unit % 1 ~= 0 or unit < 1 or unit >= 4294967295 then
        return nil, "Anchor target unavailable"
    end
    if node == nil then
        node_hash = node_hash == nil and Build.numbers.avatar_head_node or node_hash
        if not number(node_hash) or node_hash % 1 ~= 0 or node_hash < 0 or node_hash > 4294967295 then
            return nil, "Anchor node hash unavailable"
        end
    end
    local ox, oy, oz = 0, 0, 0
    if offset ~= nil then
        if
            type(offset) ~= "table"
            or not number(offset.x)
            or not number(offset.y)
            or not number(offset.z)
            or math.abs(offset.x) > 2
            or math.abs(offset.y) > 2
            or math.abs(offset.z) > 2
        then
            return nil, "Anchor local offset unavailable"
        end
        ox, oy, oz = offset.x, offset.y, offset.z
    end
    local transformed = ox ~= 0 or oy ~= 0 or oz ~= 0
    local function fresh()
        if type(validate) ~= "function" then
            return false
        end
        local okay, current = pcall(validate, unit)
        return okay and current == true
    end
    if not fresh() then
        return nil, "Anchor identity changed"
    end
    local alive, alive_reason = self:call("unit_alive", unit)
    if alive ~= true then
        return nil, alive_reason or "Anchor unit unavailable"
    end
    if node == nil then
        if not fresh() then
            return nil, "Anchor identity changed"
        end
        node = self:call("unit_node", unit, node_hash)
    end
    if not number(node) or node % 1 ~= 0 or node < 0 or node >= 4096 then
        return nil, "Anchor node unavailable"
    end
    if not fresh() then
        return nil, "Anchor identity changed"
    end
    local at = self:call(transformed and "unit_world_pose" or "unit_world_position", unit, node)
    if not address(tonumber(at)) then
        return nil, "Anchor position unavailable"
    end
    local size = transformed and 64 or 12
    local raw = self.b.read(tonumber(at), size)
    if not raw or #raw ~= size then
        return nil, "Anchor position unreadable"
    end
    if transformed then
        local m = self.pose
        self.ffi.copy(m, raw, 64)
        for i = 0, 15 do
            if not number(tonumber(m[i])) or math.abs(tonumber(m[i])) > 1e7 then
                return nil, "Anchor pose nonfinite or out of range"
            end
        end
        if math.abs(m[3]) > 1e-5 or math.abs(m[7]) > 1e-5 or math.abs(m[11]) > 1e-5 or math.abs(m[15] - 1) > 1e-5 then
            return nil, "Anchor pose not affine"
        end
        local xx = m[0] * m[0] + m[1] * m[1] + m[2] * m[2]
        local yy = m[4] * m[4] + m[5] * m[5] + m[6] * m[6]
        local zz = m[8] * m[8] + m[9] * m[9] + m[10] * m[10]
        local determinant = m[0] * (m[5] * m[10] - m[6] * m[9])
            - m[4] * (m[1] * m[10] - m[2] * m[9])
            + m[8] * (m[1] * m[6] - m[2] * m[5])
        if
            xx < 1e-12
            or yy < 1e-12
            or zz < 1e-12
            or xx > 1e8
            or yy > 1e8
            or zz > 1e8
            or math.abs(determinant) <= math.sqrt(xx * yy * zz) * 1e-6
        then
            return nil, "Anchor pose degenerate"
        end
        for i = 0, 2 do
            self.input[i] = m[12 + i] + m[i] * ox + m[4 + i] * oy + m[8 + i] * oz
        end
    else
        self.ffi.copy(self.input, raw, 12)
    end
    for i = 0, 2 do
        local v = tonumber(self.input[i])
        if not number(v) then
            return nil, "Anchor position nonfinite"
        end
        self.output[i] = 0 / 0
    end
    local function projection_fresh()
        if camera_validate == nil then
            return fresh()
        end
        if type(camera_validate) ~= "function" then
            return false
        end
        local okay, current = pcall(camera_validate)
        return okay and current == true
    end
    if not projection_fresh() then
        return nil, "Anchor identity changed"
    end
    local result, why, called = self:call("camera_world_to_screen", self.output, camera, self.input)
    if not called then
        return nil, why
    end
    local x, y, clip = tonumber(self.output[0]), tonumber(self.output[1]), tonumber(self.output[2])
    if not projection_fresh() then
        return nil, "Anchor identity changed"
    end
    if not number(x) or not number(y) or not number(clip) or clip > 1 then
        return nil, "Anchor clipped"
    end
    return x, y, clip, node
end
function Native:close()
    self.closed = true
    self.functions = {}
    self.input, self.output, self.input_owner, self.output_owner = nil, nil, nil, nil
    self.pose, self.pose_owner = nil, nil
    self.box, self.box_owner, self.box_result, self.projected_points = nil, nil, nil, nil
    return true
end
return Native
