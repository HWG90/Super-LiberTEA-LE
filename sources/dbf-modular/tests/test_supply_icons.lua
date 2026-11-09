-- Real owned FFI storage and production presenter, with inert native callbacks.
local ffi = require("ffi")
local Support = assert(loadfile("tests/support.lua"))()
local project = Support.project()
local Supply, Build, Style, Native =
    project.require("render/supply_icons.lua"),
    project.require("sampling/build.lua"),
    project.require("ui/style.lua"),
    project.require("sampling/native.lua")
local checks = 0
local function eq(a, b, why)
    checks = checks + 1
    assert(a == b, (why or "different") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, why)
    checks = checks + 1
    assert(type(a) == "number" and math.abs(a - b) < 1e-6, why or "different scalar")
end
local function fixture()
    local f = { writes = {}, pictures = {}, properties = {}, pointers = {}, scalars = {}, releases = 0, pushes = 0 }
    local root, base, manager = 0x20000000, 0x10000000, 0x40000000
    local parent, context = root + Build.supply.parent, manager + 2 * 0x3698
    local p, s = f.pointers, f.scalars
    p[base + Build.numbers.roots_hud_manager_rva] = root
    p[base + 0x2e381c8] = manager
    p[parent + 0xf8], p[context + 8] = context, 0x50000000
    s[context], s[manager + 0x2c5bc] = 1, 0xffffffff
    local matrix = ffi.new("float[16]")
    matrix[0], matrix[5], matrix[10], matrix[15] = 2, 1, 2, 1
    matrix[12], matrix[14] = 100, 50
    local source = root
        + Build.numbers.hud_widgets_mission_hud
        + Build.numbers.hud_widgets_panels_self_panel_at
        + Build.numbers.self_panel_throwable_picture
    local texture = "abcdef0112345678"
    local function bytes(hex)
        return (hex:gsub("..", function(v)
            return string.char(tonumber(v, 16))
        end))
    end
    local function uint(v)
        return string.char(
            v % 256,
            math.floor(v / 256) % 256,
            math.floor(v / 65536) % 256,
            math.floor(v / 16777216) % 256
        )
    end
    local pin = Build.modules.game
    local dos = "MZ" .. string.rep("\0", 58) .. uint(0x80)
    local pe = "PE\0\0"
        .. string.char(0x64, 0x86, 0, 0)
        .. uint(pin.timestamp)
        .. string.rep("\0", 12)
        .. string.char(0x0b, 0x02)
        .. string.rep("\0", 54)
        .. uint(pin.image_size)
    eq(#pe, 84)
    local function raw_texture(hash)
        return (hash:gsub("..", function(v)
            return string.char(tonumber(v, 16))
        end)):reverse()
    end
    local function write(kind, at)
        f.writes[#f.writes + 1] = { kind = kind, at = at }
        if f.before_write then
            f.before_write(kind, at)
        end
    end
    local b = { base = base }
    b.read = function(at, size)
        if at == parent + 0x64 and size == 64 then
            return ffi.string(matrix, 64)
        end
        if at == source and size == 8 then
            return f.picture_raw or raw_texture(texture)
        end
        if at == f.heat_source and size == 8 then
            return f.heat_raw
        end
        if at == f.heat_record and size == 24 then
            return f.heat_record_bytes
        end
        if at == base and size == 64 then
            return dos
        end
        if at == base + 0x80 and size == 84 then
            return f.bad_pe and pe:sub(1, 8) .. uint(0) .. pe:sub(13) or pe
        end
        if at == base + Build.calls.supply_picture_set.rva then
            return f.pin_refuse and string.rep("\0", size) or bytes(Build.calls.supply_picture_set.head)
        end
        if at == base + Build.calls.supply_rotation_set.rva then
            return f.rotation_refuse and string.rep("\0", size) or bytes(Build.calls.supply_rotation_set.head)
        end
        return nil
    end
    b.pointer = function(at)
        return p[at]
    end
    b.read_u64 = function(at)
        if f.unknown_link and f.presenter and at == f.presenter.address + 0xf0 then
            return nil
        end
        if p[at] ~= nil then
            return p[at]
        end
        return s[at]
    end
    b.read_u32 = function(at)
        if f.unreadable_visibility and f.presenter and at == f.presenter.address then
            return nil
        end
        return s[at]
    end
    b.read_u8 = function(at)
        return s[at]
    end
    b.valid = function(identity)
        return f.invalid_root ~= true and identity == root
    end
    b.widgets_ready = function()
        return not f.cold
    end
    b.callable = function()
        return not f.cold
    end
    b.set = function(at, property, value)
        write(property, at)
        f.properties[at] = f.properties[at] or {}
        f.properties[at][property] = { value[1], value[2] }
        if f.reject_set == property then
            return false
        end
    end
    b.set_text_style = function(at, value)
        write("colour", at)
        f.properties[at].colour = { unpack(value) }
    end
    b.release_owned_ui = function(_, at)
        f.releases = f.releases + 1
        if f.release_refuse then
            return false, "release refused"
        end
        p[at + 0xf0] = nil
        s[at + 0xf0] = 0
        return true
    end
    b.fn = function(_, rva)
        if rva == 0x12de550 or rva == 0x12d67c0 then
            return function(at)
                write("construct", at)
                p[at + 0xf8], s[at] = context, 1
                s[at + 0xf0] = 0
            end
        elseif rva == 0x12e42d0 then
            return function(owner, child)
                write("attach", child)
                p[child + 0xf0], s[child + 0xf0] = owner, nil
            end
        elseif rva == 0x12e4cc0 then
            return function(at, shown)
                write("visible", at)
                if not f.ignore_visibility then
                    s[at] = 1 + shown * 16
                end
            end
        elseif rva == Build.calls.supply_picture_set.rva then
            return function(at, material, picture, flag)
                write("picture", at)
                f.pictures[#f.pictures + 1] =
                    { at = at, material = tostring(material), texture = tostring(picture), flag = flag }
            end
        elseif rva == Build.calls.supply_rotation_set.rva then
            return function(at, degrees)
                write("rotation", at)
                f.properties[at].rotation = degrees
                return 0
            end
        elseif rva == 0x11822f0 then
            return function(_, index)
                f.pushes = f.pushes + 1
                write("push", manager)
                s[manager + 0x2c5bc], s[manager + 0x2c5b8] = 0, index
            end
        elseif rva == 0x1182310 then
            return function()
                write("pop", manager)
                s[manager + 0x2c5bc] = 0xffffffff
            end
        end
        assert(rva ~= 0x12e7510, "Texture hash must never be sent to the whole-resource asset() setter")
        return function(at)
            write("native", at)
        end
    end
    local core = {
        services = function()
            return { backend = b }
        end,
    }
    local presenter = Supply.new({
        core = core,
        native_factory = function()
            return Native.new(b, {
                module = function()
                    return base
                end,
                executable = function()
                    return not f.no_execute
                end,
            })
        end,
    })
    local model = { known = true, identity = root, generation = 3, supply_icons = {} }
    for _, key in ipairs({ "stims", "throwables" }) do
        model.supply_icons[key] = {
            known = true,
            texture = key == "stims" and Build.supply.stim_texture or texture,
            width = key == "stims" and 64 or 32,
            height = key == "stims" and 32 or 64,
            identity = root,
            generation = 3,
            context = context,
            source = key == "throwables" and source or nil,
        }
    end
    local layout = {
        supplies = {
            { key = "stims", x = 230, y = 170, width = 48, height = 24, tone = "text" },
            { key = "throwables", x = 330, y = 170, width = 12, height = 24, tone = "danger" },
        },
    }
    f.presenter, f.model, f.layout, f.backend, f.root, f.parent, f.context, f.matrix =
        presenter, model, layout, b, root, parent, context, matrix
    function f:add_heat()
        self.heat_source, self.heat_record = 0x60000000, 0x61000000
        self.heat_raw = raw_texture("abcde123fedcb456")
        self.heat_record_bytes = string.rep("\1", 24)
        self.model.supply_icons.heat = {
            known = true,
            texture = "abcde123fedcb456",
            width = 16,
            height = 32,
            identity = root,
            generation = model.generation,
            context = context,
            source = self.heat_source,
            weapon_record = self.heat_record,
            weapon_record_bytes = self.heat_record_bytes,
        }
        self.layout.supplies[3] = { key = "heat", x = 500, y = 200, width = 10, height = 28, rotation = 0 }
    end
    return f
end
local f = fixture()
local p, m, l = f.presenter, f.model, f.layout
eq(p:prepare(m), true)
eq(p.ready, true)
eq(#f.writes, 0, "prepare never constructs/mutates widgets")
eq(p:render(m, l, 0.5), true)
eq(#f.pictures, 2)
eq(f.pictures[1].flag, 0)
local stim, grenade = p.address + 0x110, p.address + 0x270
near(f.properties[stim].position[1], 65, "physical inverse-affine X")
near(f.properties[stim].position[2], 60, "physical inverse-affine Y")
near(f.properties[stim].size[1], 24)
near(f.properties[stim].size[2], 12)
near(f.properties[stim].colour[1], 0.5)
near(f.properties[grenade].colour[2], Style.tokens.colors.danger[1] / 255)
eq(f.pictures[1].material, tostring(ffi.new("uint64_t", 0x358512d8) * 4294967296ULL + 0x5e35b47d))
eq(f.pictures[1].texture, tostring(ffi.new("uint64_t", 0x93b43ada) * 4294967296ULL + 0x76587340))
eq(f.pictures[2].texture, tostring(ffi.new("uint64_t", 0xabcdef01) * 4294967296ULL + 0x12345678))
local writes, pushes, storage = #f.writes, f.pushes, p.storage
eq(p:render(m, l, 0.5), true)
eq(#f.writes, writes, "unchanged frame has zero native setters/context pushes")
eq(f.pushes, pushes)
eq(p.storage, storage)
eq(p:prepare(m), true)
f.bad_pe = true
eq(p:render(m, l, 0.5, true), true, "same-frame prepared path avoids duplicate native code validation")
f.bad_pe = false
f.pointers[f.parent + 0xf8] = f.context + 0x3698
writes = #f.writes
eq(p:render(m, l, 0.5, true), false, "prepared path still freshly checks ownership")
eq(#f.writes, writes)
f.pointers[f.parent + 0xf8] = f.context
l.supplies[1].x = 250
eq(p:render(m, l, 0.5), true)
near(f.properties[stim].position[1], 75)
eq(#f.pictures, 2, "moving labels never rebinds textures")
f.matrix[0], f.matrix[10], f.matrix[12], f.matrix[14] = 4, 4, 200, 100
eq(p:render(m, l, 0.5), true)
near(f.properties[stim].position[1], 12.5)
near(f.properties[stim].size[1], 12)
eq(p:hide(), true)
eq(f.scalars[p.address], 1)
eq(p:render(m, l, 0.5), true)
eq(f.scalars[p.address], 17)
eq(#f.pictures, 2, "hide/reveal retains image binding")
m.supply_icons.throwables.known = false
local grenade_spec = l.supplies[2]
l.supplies[2] = nil
eq(p:render(m, l), true)
eq(f.scalars[grenade], 1, "unknown grenade removes only its image")
eq(f.scalars[stim], 17)
l.supplies[2] = grenade_spec
writes = #f.writes
eq(p:render(m, l), false, "already-requested unknown DTO requires descriptive text fallback")
eq(#f.writes, writes, "invalid requested image refuses before native writes")
eq(p:hide(), true)
m.supply_icons.throwables.known = true
eq(p:render(m, l), true)
f.picture_raw = string.rep("\15", 8)
writes = #f.writes
eq(p:render(m, l), false, "actual equipped texture change after sampling requests text fallback")
eq(#f.writes, writes, "source race cannot write any new images")
eq(p:hide(), true, "fallback can proceed only after old native images hide positively")
eq(f.scalars[p.address], 1)
f.picture_raw = nil
eq(p:render(m, l), true)
eq(f.scalars[grenade], 17)
m.supply_icons.throwables.generation = m.generation + 1
writes = #f.writes
eq(p:render(m, l), false, "already-requested foreign generation requires text fallback")
eq(#f.writes, writes)
eq(p:hide(), true)
m.supply_icons.throwables.generation = m.generation
eq(p:render(m, l), true)
f.pointers[grenade + 0xf8] = f.context + 0x3698
writes = #f.writes
eq(p:hide(), false, "child context refusal retains live root")
eq(#f.writes, writes)
eq(p:close(), false)
eq(f.releases, 0)
eq(p.storage, storage)
f.pointers[grenade + 0xf8] = f.context
f.release_refuse = true
eq(p:close(), false)
eq(p.storage, storage)
f.release_refuse = false
eq(p:close(), true)
eq(p.storage, nil)
eq(p:close(), true)
for _, mutation in ipairs({ "parent", "root", "link", "unknown", "pin", "byte" }) do
    local q = fixture()
    eq(q.presenter:render(q.model, q.layout), true)
    local at = q.presenter.address
    if mutation == "parent" then
        q.pointers[q.parent + 0xf8] = q.context + 0x3698
    elseif mutation == "root" then
        q.pointers[q.backend.base + Build.numbers.roots_hud_manager_rva] = q.root + 0x100000
    elseif mutation == "link" then
        q.pointers[at + 0xf0] = q.parent + 0x1000
    elseif mutation == "unknown" then
        q.unknown_link = true
    elseif mutation == "pin" then
        q.pin_refuse = true
    else
        q.scalars[q.context] = 0
    end
    local before = #q.writes
    eq(q.presenter:close(), false, mutation .. " cannot acknowledge native retirement")
    eq(q.presenter.storage ~= nil, true)
    eq(q.releases, 0)
    eq(#q.writes, before)
    -- Positive detachment is safe retirement even after resource context loss.
    q.unknown_link, q.pointers[at + 0xf0], q.scalars[at + 0xf0] = nil, nil, 0
    eq(q.presenter:close(), true)
end
f = fixture()
f.cold = true
eq(f.presenter:prepare(f.model), true)
eq(f.presenter.ready, false, "normal cold code leaves descriptive text fallback")
eq(f.presenter:render(f.model, f.layout), true)
eq(#f.writes, 0)
f.cold = false
eq(f.presenter:render(f.model, f.layout), true)
f.ignore_visibility = true
eq(f.presenter:hide(), false, "hide requires read-back acknowledgment")
eq(f.presenter.storage ~= nil, true)
f.ignore_visibility = false
eq(f.presenter:hide(), true)
f = fixture()
f.matrix[8] = 0.5
eq(f.presenter:render(f.model, f.layout), false, "unsupported affine fails before creating native owners")
eq(f.presenter.storage, nil)
eq(#f.writes, 0)
f = fixture()
f.reject_set = "size"
eq(f.presenter:render(f.model, f.layout), false)
eq(f.presenter.storage ~= nil, true, "partial constructor remains owned")
eq(f.scalars[0x40000000 + 0x2c5bc], 0xffffffff, "context unwinds after constructor refusal")
f.reject_set = nil
eq(f.presenter:close(), true)
f = fixture()
eq(f.presenter:render(f.model, f.layout), true)
local old_storage = f.presenter.storage
f.model.generation = 4
for _, icon in pairs(f.model.supply_icons) do
    icon.generation = 4
end
eq(f.presenter:render(f.model, f.layout), true)
eq(f.releases, 1, "new generation releases prior owner before creating another")
eq(f.presenter.storage ~= old_storage, true)
eq(f.presenter:close(), true)
local empty = Supply.new({ core = {} })
eq(empty:prepare({ known = true }), true, "missing normal Core services is cold readiness")
eq(empty.ready, false)
eq(empty:close(), true)
for _, invalid in ipairs({ "pin_refuse", "bad_pe", "no_execute" }) do
    f = fixture()
    f[invalid] = true
    eq(f.presenter:prepare(f.model), true)
    eq(f.presenter.ready, false, invalid .. " prevents new native images")
    eq(#f.writes, 0)
end
f = fixture()
local changed = false
f.before_write = function(kind, at)
    if kind == "visible" and at == f.presenter.address and f.presenter.linked and not changed then
        changed = true
        f.pointers[f.parent + 0xf8] = f.context + 0x3698
    end
end
eq(f.presenter:render(f.model, f.layout), false, "context drift inside final setter is not published as success")
eq(changed, true)
eq(f.presenter.storage ~= nil, true)
eq(f.scalars[0x40000000 + 0x2c5bc], 0xffffffff, "scope still unwinds after final context drift")
eq(f.presenter:close(), false)
eq(f.releases, 0)
f.before_write = nil
f.pointers[f.parent + 0xf8] = f.context
eq(f.presenter:close(), true)
f = fixture()
f.before_write = function(kind, at)
    if kind == "visible" and at == f.presenter.address and f.presenter.linked then
        f.unreadable_visibility = true
    end
end
eq(f.presenter:render(f.model, f.layout), false, "successful show with unreadable acknowledgment retains debt")
eq(f.scalars[f.presenter.address], 17, "show setter actually changed native flag")
eq(f.presenter.visibility_pending, true)
eq(f.presenter:hide(), false, "uncertain show cannot be acknowledged by an early hidden cache")
eq(f.presenter.visibility_pending, true)
f.before_write, f.unreadable_visibility = nil, nil
eq(f.presenter:hide(), true)
eq(f.scalars[f.presenter.address], 1)
eq(f.presenter.visibility_pending, nil)
eq(f.presenter:close(), true)
f = fixture()
f:add_heat()
eq(f.presenter:render(f.model, f.layout), true)
local heat_at = f.presenter.address + 0x110 + 2 * 0x160
eq(#f.pictures, 3, "coil shares the same owned image presenter")
near(f.properties[heat_at].pivot[1], 0.5)
near(f.properties[heat_at].pivot[2], 0.5)
near(f.properties[heat_at].position[1], 202.5)
near(f.properties[heat_at].position[2], 82)
near(f.properties[heat_at].size[1], 5)
near(f.properties[heat_at].size[2], 14)
eq(f.properties[heat_at].rotation, 0)
local heat_spec = f.layout.supplies[3]
heat_spec.width, heat_spec.height, heat_spec.rotation = 28, 10, 90
eq(f.presenter:render(f.model, f.layout), true)
near(f.properties[heat_at].position[1], 207)
near(f.properties[heat_at].position[2], 77.5)
near(f.properties[heat_at].size[1], 5, "90degree rotated AABB swaps underlying native width")
near(f.properties[heat_at].size[2], 14)
eq(f.properties[heat_at].rotation, 90)
writes = #f.writes
eq(f.presenter:render(f.model, f.layout), true)
eq(#f.writes, writes, "unchanged coil also has zero setters/context writes")
f.rotation_refuse = true
eq(f.presenter:prepare(f.model), true)
eq(f.presenter.ready, false, "rotation witness refuses new placement")
eq(f.presenter:hide(), true, "cold rotation does not block independent visibility cleanup")
f.rotation_refuse = false
eq(f.presenter:render(f.model, f.layout), true)
f.heat_record_bytes = string.rep("\2", 24)
writes = #f.writes
eq(f.presenter:render(f.model, f.layout), false, "changed weapon rejects stale coil before mutations")
eq(#f.writes, writes)
eq(f.presenter:hide(), true)
eq(f.presenter:close(), true)
print("Supply icons: " .. checks .. " checks passed")
