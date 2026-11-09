-- Actual production counter decoder; no process, game calls or writes.
local Fixture = assert(loadfile("tests/sampling_fixture.lua"))()
local checks = 0
local function eq(a, b, why)
    checks = checks + 1
    assert(a == b, (why or "different") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local f = Fixture.new()
local n = f.n
local dimension = f.panel + n.self_panel_throwable_icon + n.hud_widgets_size_x
local source = f.panel + n.self_panel_throwable_picture
local function picture(low, high, width, height)
    f.uint(source, low)
    f.uint(source + 4, high)
    f.float(dimension, width)
    f.float(dimension + 4, height)
end
picture(0x12345678, 0xabcdef01, 48, 64)
local model = f:sample()
local icons = model.supply_icons
eq(model.known, true)
eq(icons.stims.known, true)
eq(icons.stims.texture, "93b43ada76587340")
eq(icons.stims.width, 64)
eq(icons.stims.height, 32)
eq(icons.throwables.known, true)
eq(icons.throwables.texture, "abcdef0112345678", "little-endian native picture is not rounded through a double")
eq(icons.throwables.width, 48)
eq(icons.throwables.height, 64)
eq(icons.throwables.source, source)
for _, key in ipairs({ "stims", "throwables" }) do
    eq(icons[key].identity, model.identity)
    eq(icons[key].generation, model.generation)
    eq(icons[key].context, 0x40000000)
end
local standalone, batches, dimensions = 0, 0, 0
for _, row in ipairs(f.reads) do
    if row.at == source then
        standalone = standalone + 1
    end
    if row.at == f.panel + n.hud_weapon_reserve_shown and row.size == 136 then
        batches = batches + 1
    end
    if row.at == dimension and row.size == 8 then
        dimensions = dimensions + 1
    end
end
eq(standalone, 0, "picture uses existing counter batch")
eq(batches, 1)
eq(dimensions, 1)
picture(0xffffffff, 0xffffffff, 32, 64)
model = f:sample()
eq(model.supply_icons, icons, "DTO table is retained")
eq(icons.throwables.texture, "ffffffffffffffff", "all64 native hash bits survive")
picture(0, 0, 32, 64)
model = f:sample()
eq(model.known, true)
eq(icons.throwables.known, false)
eq(icons.throwables.texture, nil)
eq(icons.stims.known, true)
for _, size in ipairs({ 0, -1, 4097, math.huge }) do
    picture(1, 2, size, 64)
    model = f:sample()
    eq(model.known, true, "bad optional icon dimensions preserve combat sample")
    eq(icons.throwables.known, false)
end
picture(1, 2, 32, 64)
local read = f.backend.read
f.backend.read = function(at, size)
    if at == dimension then
        return nil
    end
    return read(at, size)
end
model = f:sample()
eq(model.known, true, "unreadable optional dimension is isolated")
eq(icons.throwables.known, false)
eq(icons.stims.known, true)
f.backend.read = read
model = f:sample()
eq(icons.throwables.known, true)
f.uint(f.root + f.context.require("sampling/build.lua").numbers.hud_built, 0)
model = f:sample()
eq(model.known, false)
eq(icons.throwables.known, false, "unknown context clears prior picture")
eq(icons.stims.known, false)
eq(icons.stims.texture, nil)
eq(f.sampler:close(), true)
eq(icons.throwables.source, nil)
-- Filled ammo art is distinct from both the empty reserve outline and the
-- wide gun silhouette (current Scythe live resource receipt, dev14).
f = Fixture.new()
f:heat_sample(25, 100, false, "7e3145a5baa4b948")
local Layout = f.context.require("src/weapon_status_layouts.lua")
local Memory = f.context.require("src/weapon_status_memory.lua")
local reader = Memory.new(f.backend)
local owner = reader.p(f.backend.base + Layout.owner)
local spec = Layout.static.weapon_data
local data = 0x59000000
local low, high = 0xbaa4b948, 0x7e3145a5
local home = ((high % spec[2]) * (2 ^ 32 % spec[2]) + low % spec[2]) % spec[2]
f.pointer(owner + spec[1], data)
f.put(data, string.rep("\0", spec[2] * 16))
local row = data + home * 16
f.uint(row, low)
f.uint(row + 4, high)
f.uint(row + 8, 0)
f.uint(row + 12, 0)
local config = data + spec[2] * 16
f.uint(config + 1032, 0xa1645aa8)
f.uint(config + 1036, 0xfb6b3350)
f.uint(config + 1040, 0xadeaddf6)
f.uint(config + 1044, 0x728b4020)
f.float(f.panel + f.n.self_magazine_fill + f.n.hud_widgets_size_x, 17)
f.float(f.panel + f.n.self_magazine_fill + f.n.hud_widgets_size_x + 4, 34)
local function sample_heat(wanted)
    return f.sampler:sample(0.016, {
        anchor = 2,
        heat_icon = wanted,
        viewport = { width = 3840, height = 2160 },
    })
end
model = sample_heat(false)
eq(model.supply_icons.heat.known, false, "percentage-only mode does no decorative lookup")
local lookups = 0
for _, read in ipairs(f.reads) do
    if read.at == owner + spec[1] then
        lookups = lookups + 1
    end
end
eq(lookups, 0)
model = sample_heat(true)
local heat = model.supply_icons.heat
eq(model.known, true, f.sampler.reason)
eq(heat.known, true)
eq(heat.texture, "fb6b3350a1645aa8", "use native filled art, never the outlined spare canister")
eq(heat.kind, "native_ammo_fill")
eq(heat.source, config + 1032)
eq(heat.width, 17)
eq(heat.height, 34)
eq(heat.weapon_record, f.weapon_record)
eq(heat.weapon_record_bytes, f.backend.read(f.weapon_record, 24))
eq(heat.identity, model.identity)
eq(heat.generation, model.generation)
eq(heat.context, f.ui_context)
model = sample_heat(true)
eq(model.supply_icons.heat, heat, "coil DTO reused")
eq(heat.known, true, "cache revalidates native resource row")
local reads = f.backend.read
f.backend.read = function(at, size)
    local raw = reads(at, size)
    if at == config + 1032 then
        f.uint(f.selector_row, 999)
    end
    return raw
end
model = sample_heat(true)
eq(model.known, true)
eq(heat.known, false, "wield change during lookup cannot publish old coil")
f.backend.read = reads
f.uint(f.selector_row, f.info.id)
f.uint(row + 8, 1)
local next_config = config + spec[3]
f.uint(next_config + 1032, 0x12345678)
f.uint(next_config + 1036, 0xabcdef01)
model = sample_heat(true)
eq(heat.known, true)
eq(heat.texture, "abcdef0112345678", "resource compaction invalidates cached row/index")
eq(heat.source, next_config + 1032)
f.uint(next_config + 1032, 0)
f.uint(next_config + 1036, 0)
model = sample_heat(true)
eq(model.known, true)
eq(heat.known, false, "missing native art preserves HEAT text fallback")
f.uint(next_config + 1032, 0xa1645aa8)
f.uint(next_config + 1036, 0xfb6b3350)
f.project_validations = 5 -- Actual Native.project:3full Unit +2camera-only fences.
local peak_reads = 0
local function sample_attachment(fp, aiming)
    f.action(f.n.first_person_action_bit, fp)
    f.action(f.n.aim_action_bit, aiming)
    if fp then
        f:first_person()
    else
        f.set_camera_request(4)
    end
    local model = f.sampler:sample(0.016, {
        anchor = 1,
        heat_icon = true,
        sight_clearance = true,
        viewport = { width = 3840, height = 2160 },
    })
    peak_reads = math.max(peak_reads, f.sampler.r.reads)
    eq(f.sampler.r.reads <= 512, true, "native artwork and attachments keep original read cap")
    return model
end
for _, pose in ipairs({ { false, false }, { false, true }, { true, true } }) do
    model = sample_attachment(pose[1], pose[2])
    eq(model.known, true, f.sampler.reason)
    eq(heat.known, true, "projection work cannot starve already-collected heat artwork")
    eq(heat.texture, "fb6b3350a1645aa8")
    if not pose[1] then
        eq(model.anchors.body.known, true)
        eq(model.anchors.weapon.known, true)
    else
        eq(model.anchors.viewmodel.known, true)
    end
end
local engine = f.weapon_engine
f.after_pose = function(_, unit)
    if unit == engine then
        f.uint(f.weapon_record + f.n.record_engine_unit, engine + 1)
    end
end
model = sample_attachment(false, true)
eq(model.anchors.weapon.known, false, "copied projection cannot publish a replaced Unit")
eq(heat.known, false, "final weapon publication fence remains fresh after pose copy")
f.uint(f.weapon_record + f.n.record_engine_unit, engine)
f.after_pose = function()
    f.uint(f.selector_row, 999)
end
model = sample_attachment(true, true)
eq(model.anchors.viewmodel.known, false)
eq(heat.known, false, "current-wield change after Unit pose invalidates artwork")
f.uint(f.selector_row, f.info.id)
f.after_pose = function()
    f.uint(next_config + 1032, 123)
end
model = sample_attachment(true, true)
eq(heat.known, false, "resource texture mutation after pose cannot publish stale art")
f.uint(next_config + 1032, 0xa1645aa8)
f.after_pose = function()
    f.pointer(f.camera_manager, f.camera + 0x1000)
end
model = sample_attachment(false, true)
eq(model.known, false, "camera replacement after copying a pose rejects the whole attachment context")
eq(model.anchors.body.known, false)
eq(heat.known, false)
f.pointer(f.camera_manager, f.camera)
f.after_pose = nil
model = sample_attachment(true, true)
eq(heat.known, true)
-- Production True First Person has TWO independent current-rig points. Use
-- the actual sampler/typed resource decoder and the five Native guard calls;
-- no read counters are injected or reset inside the production sample.
f.globals.NativeADSCameraTest = {
    status = function()
        return "True FP",
            {
                mode = "pose_offset",
                phase = "running",
                enabled = true,
                cleanup_pending = false,
                editor_active = false,
            }
    end,
}
local two_point_reads, two_point_bytes = 0, 0
for _, aiming in ipairs({ false, true }) do
    f.action(f.n.first_person_action_bit, false)
    f.action(f.n.aim_action_bit, aiming)
    f.set_camera_request(6)
    model = f.sampler:sample(0.016, {
        anchor = 1,
        heat_icon = true,
        sight_clearance = true,
        tfp_vitals_bone = 2,
        tfp_ammo_bone = 1,
        viewport = { width = 3840, height = 2160 },
    })
    eq(model.known, true, f.sampler.reason)
    eq(model.aim.true_first_person, true)
    eq(model.anchors.tfp_vitals.known, true, "first point remains current on a heat weapon")
    eq(model.anchors.viewmodel.known, true, "second current weapon point survives the original cap")
    eq(heat.known, true, "native coil retains its own final publication proof")
    eq(f.sampler.r.reads <= 512, true)
    eq(f.sampler.r.bytes <= 65536, true)
    two_point_reads, two_point_bytes =
        math.max(two_point_reads, f.sampler.r.reads), math.max(two_point_bytes, f.sampler.r.bytes)
end
local original_read = f.sampler.r.read
f.after_unit_getter = function(_, hash, ordinal)
    if hash == f.n.viewmodel_weapon_node and ordinal == 1 then
        while f.sampler.r.reads < 512 - 80 do
            f.sampler.r.read(f.root + f.n.hud_built, 4)
        end
    end
end
model = f.sampler:sample(0.016, {
    anchor = 1,
    heat_icon = true,
    sight_clearance = true,
    tfp_vitals_bone = 2,
    tfp_ammo_bone = 1,
    viewport = { width = 3840, height = 2160 },
})
eq(model.known, true)
eq(model.aim.true_first_person, true)
eq(model.anchors.tfp_vitals.known, true, "optional second-point exhaustion never cuts the first arm")
eq(model.anchors.viewmodel.known, false)
eq(model.anchors.viewmodel.reason, "optional FPS weapon projection read budget exhausted")
eq(heat.known, true, "reserved final publication fence still validates the native coil")
eq(f.sampler.r.reads <= 512, true)
eq(f.sampler.r.bytes <= 65536, true)
eq(f.sampler.r.read, original_read, "bounded reader restores after an early Native getter refusal")
f.after_unit_getter = nil
local default_reads, choices_peak = nil, 0
local Bones = f.context.require("sampling/first_person_bones.lua")
for health = 1, #Bones.choices do
    for ammo = 1, #Bones.choices do
        local before = #f.projections
        model = f.sampler:sample(0.016, {
            anchor = 1,
            heat_icon = true,
            sight_clearance = true,
            tfp_vitals_bone = health,
            tfp_ammo_bone = ammo,
            viewport = { width = 3840, height = 2160 },
        })
        eq(model.known, true)
        eq(model.aim.true_first_person, true)
        eq(model.anchors.tfp_vitals.known, true, "selected health bone survives heat-weapon proof budget")
        eq(model.anchors.viewmodel.known, true, "selected ammo bone survives heat-weapon proof budget")
        eq(model.anchors.tfp_vitals.bone_hash, Bones.resolve(health))
        eq(model.anchors.viewmodel.bone_hash, Bones.resolve(ammo))
        eq(#f.projections - before, health == ammo and 1 or 2)
        eq(heat.known, true)
        eq(f.sampler.r.reads <= 512, true)
        eq(f.sampler.r.bytes <= 65536, true)
        choices_peak = math.max(choices_peak, f.sampler.r.reads)
        if health == 1 and ammo == 1 then
            default_reads = f.sampler.r.reads
        end
    end
end
eq(f.sampler:close(), true)
print(
    "Supply sampling: "
        .. checks
        .. " checks passed; heat attachment peak "
        .. peak_reads
        .. "/512 reads; TFPtwo-point "
        .. two_point_reads
        .. "/512 reads,"
        .. two_point_bytes
        .. "/65536 bytes; selected defaults="
        .. default_reads
        .. ", all"
        .. ((#Bones.choices) ^ 2)
        .. "choices peak="
        .. choices_peak
)
