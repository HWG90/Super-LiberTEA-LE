-- Sparse native-byte fixture. All pointer/maps/scalars use the production decoder.
local ffi = require("ffi")
local Support = assert(loadfile("tests/support.lua"))()
local Fixture = {}
function Fixture.new()
    local context, globals = Support.project()
    local Build, Layout = context.require("sampling/build.lua"), context.require("src/weapon_status_layouts.lua")
    local Session = context.require("sampling/session.lua")
    local n, bytes, f =
        Build.numbers, {}, {
            reads = {},
            calls = {},
            projections = {},
            now = 0,
            body_point = { x = 800, y = 500, node = 6 },
            weapon_point = { x = 1000, y = 450 },
            viewmodel_point = { x = 1920, y = 850, node = 8 },
            left_arm_point = { x = 1400, y = 650, node = 13 },
            left_elbow_point = { x = 1300, y = 700, node = 12 },
            body_unit = 77,
        }
    -- Hash/returned-node pairs from the labelled current63-node rig. These
    -- inert test points model Unit.node resolving the current semantic hash;
    -- production never stores these numeric indices or scans a skeleton.
    f.extra_bone_points = {
        [0x248004f5] = { x = 2100, y = 620, node = 34 },
        [0x31e34dac] = { x = 2200, y = 700, node = 32 },
        [0x03752c98] = { x = 1250, y = 740, node = 10 },
        [0x1620b2ce] = { x = 2150, y = 740, node = 30 },
        [0x37ef0820] = { x = 1700, y = 720, node = 59 },
        [0xc4787b4e] = { x = 1500, y = 760, node = 61 },
        [0xb2bcd839] = { x = 1900, y = 760, node = 60 },
    }
    local Bones = context.require("sampling/first_person_bones.lua")
    local known_bone_hashes, weapon_bone_hashes = {}, {}
    f.weapon_bone_points = {}
    for choice = 1, #Bones.choices do
        local hash, _, domain = Bones.resolve(choice)
        if domain == "weapon" then
            weapon_bone_hashes[hash] = true
            -- Inert resolved-node output only. Root index zero deliberately
            -- differs from the FPS rig's weapon-attachment node eight.
            f.weapon_bone_points[hash] = { x = 1800 + choice, y = 800 - choice, node = choice == 11 and 0 or choice }
        else
            known_bone_hashes[hash] = true
        end
    end
    local function put(at, text)
        for i = 1, #text do
            bytes[at + i - 1] = text:byte(i)
        end
    end
    local function zero(at, size)
        put(at, string.rep("\0", size))
    end
    local function uint(at, value)
        put(
            at,
            string.char(
                value % 256,
                math.floor(value / 256) % 256,
                math.floor(value / 65536) % 256,
                math.floor(value / 16777216) % 256
            )
        )
    end
    local function pointer(at, value)
        uint(at, value % 2 ^ 32)
        uint(at + 4, math.floor(value / 2 ^ 32))
    end
    local function float(at, value)
        local v = ffi.new("float[1]", value)
        put(at, ffi.string(v, 4))
    end
    local map_at = 0x70000000
    local function map(at, key, value)
        map_at = map_at + 0x100
        local data = map_at
        pointer(at, data)
        uint(at + 8, 8)
        uint(at + 12, 0xffffffff)
        uint(at + 16, 1)
        for i = 0, 7 do
            uint(data + i * 8, 0xffffffff)
            uint(data + i * 8 + 4, 0xffffffff)
        end
        uint(data + key % 8 * 8, key)
        uint(data + key % 8 * 8 + 4, value)
        return data
    end
    local base, root, scene, ui, pm, player, owner =
        0x10000000, 0x30000000, 0x20000000, 0x40000000, 0x41000000, 0x42000000, 0x43000000
    local actor_id, actor_unit, weapon_id, weapon_unit = 42, 77, 90, 88
    f.body_engine, f.weapon_engine, f.viewmodel_engine = 14117, 14145, 14161
    local actor_record, weapon_record = owner + Layout.records + 24, owner + Layout.records + 48
    local mission, panel =
        root + n.hud_widgets_mission_hud, root + n.hud_widgets_mission_hud + n.hud_widgets_panels_self_panel_at
    pointer(base + n.hud_scene_manager, scene)
    uint(scene + n.hud_scene, n.hud_scene_mission)
    pointer(base + n.roots_hud_manager_rva, root)
    uint(panel, 16)
    pointer(panel + n.widget_gui_context, ui)
    uint(ui, 1)
    uint(root + n.hud_built, 1)
    uint(mission + n.hud_gate_ready, 1)
    uint(mission + n.hud_local_pause, 0)
    float(panel + n.widget_inherited_opacity, 1)
    float(panel + n.self_panel_health_bar + n.health_bar_drawn, 0.75)
    float(mission + n.hud_widgets_stamina_panel_at + n.stamina_panel_share, 0.5)
    zero(panel + n.hud_weapon_reserve_shown, 136)
    uint(panel + n.hud_weapon_reserve_shown, 3)
    uint(panel + n.hud_weapon_count_shown, 31)
    uint(panel + n.hud_weapon_ammo_state, 0)
    uint(panel + n.hud_self_last_slot, 1)
    uint(panel + n.self_panel_stims, 2)
    uint(panel + n.hud_self_throwables, 4)
    float(panel + n.ammo_gauge, 0.25)
    put(panel + n.spare_widget, string.char(16))
    uint(root + Build.menu_panel + Build.menu_open_at, 0)
    pointer(base + Layout.player, pm)
    uint(pm + 0x84, 1)
    uint(pm + 0x88, 1)
    pointer(pm + 0xe8, player)
    zero(player, 24)
    uint(player + 8, 9)
    put(player + 20, "\1")
    map(pm + 0xd0, 9, 0)
    uint(pm + 0x3a8, actor_unit)
    pointer(base + Layout.owner, owner)
    map(owner + Layout.unit_map, actor_unit, 1)
    zero(actor_record, 24)
    uint(actor_record + 8, actor_id)
    uint(actor_record + n.record_engine_unit, f.body_engine)
    uint(actor_record + 16, actor_unit)
    put(actor_record + 20, "\1")
    zero(weapon_record, 24)
    uint(weapon_record + 8, weapon_id)
    uint(weapon_record + n.record_engine_unit, f.weapon_engine)
    uint(weapon_record + 16, weapon_unit)
    put(weapon_record + 20, "\1")
    local avatars, inventory, selector, data = 0x51000000, 0x50000000, 0x52000000, 0x53000000
    pointer(base + n.roots_avatar_manager_rva, avatars)
    map(avatars + n.roots_avatar_manager_map, actor_id, 0)
    local controller = avatars + n.roots_avatar_manager_controller_base
    uint(controller + n.avatar_controller_dive_identity_offset, actor_id)
    zero(controller + n.avatar_action_words, 16)
    uint(controller + n.avatar_viewmodel_offset, f.viewmodel_engine)
    local function action(index, enabled)
        local at = controller + n.avatar_action_words + math.floor(index / 8)
        local bit = 2 ^ (index % 8)
        local value = bytes[at]
        local set = math.floor(value / bit) % 2 == 1
        if enabled ~= set then
            bytes[at] = value + (enabled and bit or -bit)
        end
    end
    pointer(base + Layout.inventory, inventory)
    uint(inventory + 0x14, 1)
    map(inventory + 0x28, actor_id, 0)
    pointer(inventory + 0x40, 0x54000000)
    pointer(0x54000000, actor_record)
    pointer(inventory + 0x50, 0x54001000)
    zero(0x54001000, 48)
    uint(0x54001000, weapon_id)
    uint(0x54001000 + 28, 1)
    pointer(base + Layout.selector, selector)
    uint(selector + 0x10, 8)
    uint(selector + 0x18, 1)
    map(selector + 0x30, actor_id, 0)
    pointer(selector + 0x48, 0x54002000)
    pointer(0x54002000, actor_record)
    pointer(selector + 0x60, 0x54003000)
    uint(0x54003000, weapon_id)
    pointer(base + n.weapon_data_manager, data)
    map(data + n.weapon_data_map, weapon_id, 0)
    pointer(data + n.weapon_data_r1_at, 0x54004000)
    uint(0x54004000 + n.weapon_data_fire_count, 1)
    uint(0x54004000 + n.weapon_data_fire_node, 3)
    pointer(base + n.reload_manager, 0x55000000)
    pointer(base + n.camera_manager, 0x56000000)
    pointer(0x56000000, 0x56001000)
    local function camera_request(kind, head, tail)
        head, tail = head or 0, tail or 0
        uint(0x56000000 + n.camera_queue_head, head)
        uint(0x56000000 + n.camera_queue_tail, tail)
        local at = head ~= tail and 0x56000000 + n.camera_queue_rows + ((tail + 31) % 32) * n.camera_queue_stride
            or 0x56000000 + n.camera_queue_fallback
        zero(at, 16)
        uint(at, kind)
        uint(at + 4, actor_id)
        uint(at + 8, weapon_id)
        uint(at + 12, f.body_engine)
        f.camera_request = at
        return at
    end
    camera_request(4)
    local crosshair = mission + n.hud_widgets_panels_crosshair_at
    uint(crosshair, 16)
    pointer(crosshair + n.widget_gui_context, ui)
    float(crosshair + n.widget_inherited_opacity, 1)
    float(crosshair + n.hud_widgets_size_x, 1)
    float(crosshair + n.hud_widgets_size_x + 4, 1)
    zero(crosshair + 0x64, 64)
    float(crosshair + 0x64, 2)
    float(crosshair + 0x64 + 40, 2)
    float(crosshair + 0x64 + 48, 1919)
    float(crosshair + 0x64 + 56, 1079)
    local b = { base = base }
    function b.read(at, size)
        f.reads[#f.reads + 1] = { at = at, size = size }
        if f.before_read then
            f.before_read(at, size)
        end
        local out = {}
        for i = 0, size - 1 do
            if bytes[at + i] == nil then
                return nil
            end
            out[i + 1] = string.char(bytes[at + i])
        end
        return table.concat(out)
    end
    b.focused = function()
        return not f.unfocused
    end
    b.dock_font = function()
        return { font = "0123456789abcdef", atlas = "1111111111111111", material = "2222222222222222" }
    end
    local info = {
        id = weapon_id,
        unit_ref = weapon_unit,
        avatar_unit_ref = actor_unit,
        reloadable = false,
        resource_hex = "0123456789abcdef",
        fire_mode = "AUTO",
        rpm = 750,
        rpm_index = 1,
        zoom = 2,
        zoom_index = 0,
        changeable = { fire_mode = true, rpm = true, zoom = true },
        binding = { module_base = base, record = weapon_record, avatar_id = actor_id, avatar_record = actor_record },
    }
    local services = {
        backend = b,
        weapon = info,
        snapshot = { identity = root, open = false },
        cooldowns = {
            rows = { { kind = 34, entry = 1, timer_kind = "cooldown", timer_seconds = 4, unavailable = false } },
        },
    }
    globals.stingray = {
        Application = {
            worlds = function()
                return { "main", "ui" }
            end,
            main_world = function()
                return "main"
            end,
        },
    }
    globals.DBFMCM = {
        is_open = function()
            return false
        end,
    }
    globals.LiveLuaLoader = {
        input_service = {
            status = function()
                return { owner = false, pending_restore = false }
            end,
        },
    }
    local native = {
        close = function()
            return true
        end,
    }
    function native:call(name, ...)
        f.calls[#f.calls + 1] = name
        if name == "reloading" then
            return f.reloading == true
        end
    end
    function native:project(camera, unit, node, validate, offset, node_hash, camera_validate)
        f.calls[#f.calls + 1] = "project"
        f.projections[#f.projections + 1] =
            { camera = camera, unit = unit, node = node, offset = offset, node_hash = node_hash }
        assert(
            unit == f.body_engine or unit == f.weapon_engine or unit == f.viewmodel_engine,
            "DBF references are not engine handles"
        )
        if f.before_project then
            f.before_project(camera, unit, node, offset, node_hash)
        end
        local unit_validations = camera_validate and f.project_validations and 3 or f.project_validations or 1
        for _ = 1, unit_validations do
            if validate(unit) ~= true then
                return nil, "attachment identity changed"
            end
            if f.after_unit_getter then
                f.after_unit_getter(unit, node_hash, _)
            end
        end
        if f.after_pose then
            f.after_pose(camera, unit, node, offset, node_hash)
        end
        if camera_validate and camera_validate() ~= true then
            return nil, "camera changed before projection"
        end
        local point = unit == f.body_engine and f.body_point
            or unit == f.viewmodel_engine and f.viewmodel_point
            or f.weapon_point
        if unit == f.viewmodel_engine then
            assert(
                node == nil
                    and (
                        node_hash == n.viewmodel_weapon_node
                        or node_hash == n.viewmodel_left_arm_node
                        or node_hash == n.viewmodel_left_elbow_node
                        or known_bone_hashes[node_hash] == true
                    ),
                "FPS attachment resolves its semantic node afresh"
            )
            if node_hash == n.viewmodel_left_arm_node then
                point = f.left_arm_point
            elseif node_hash == n.viewmodel_left_elbow_node then
                point = f.left_elbow_point
            elseif node_hash ~= n.viewmodel_weapon_node then
                point = f.extra_bone_points[node_hash]
            end
        elseif unit == f.weapon_engine and node_hash ~= nil then
            assert(node == nil and weapon_bone_hashes[node_hash], "actual weapon bone requires selected gun engine")
            point = f.weapon_bone_points[node_hash]
        end
        if f.after_project then
            f.after_project(camera, unit, node, offset, node_hash)
        end
        local current = camera_validate and camera_validate() or not camera_validate and validate(unit)
        if current ~= true then
            return nil, "attachment identity changed after projection"
        end
        if f.project_failure == unit then
            return nil, "optional projection unavailable"
        end
        if f.project_failure_hash ~= nil and f.project_failure_hash == node_hash then
            return nil, "optional projection unavailable"
        end
        if not point then
            return nil, "bone unavailable"
        end
        return point.x, point.y, point.clip or 0, node or point.node
    end
    local sampler = Session.new({
        core = {
            services = function()
                return services
            end,
        },
        globals = globals,
        native_factory = function()
            return native
        end,
    })
    function f:sample(anchor, sight_clearance)
        local options = {
            anchor = anchor or 2,
            sight_clearance = sight_clearance,
            viewport = { width = 3840, height = 2160 },
        }
        for key, value in pairs(self.sample_options or {}) do
            options[key] = value
        end
        return sampler:sample(0.016, options)
    end
    f.context, f.globals, f.sampler, f.services, f.info, f.backend = context, globals, sampler, services, info, b
    f.put, f.uint, f.pointer, f.float, f.action, f.memory, f.n = put, uint, pointer, float, action, bytes, n
    f.panel, f.root, f.pm, f.actor_record, f.weapon_record, f.crosshair =
        panel, root, pm, actor_record, weapon_record, crosshair
    f.inventory_row, f.selector_row, f.controller = 0x54001000, 0x54003000, controller
    f.camera_manager, f.camera, f.fire_row, f.weapon_data = 0x56000000, 0x56001000, 0x54004000, data
    f.ui_context = ui
    f.avatars = avatars
    f.set_camera_request = camera_request
    function f:first_person(head, tail)
        action(n.first_person_action_bit, true)
        return camera_request(6, head, tail)
    end
    function f:replace_actor(id, unit)
        uint(pm + 0x3a8, unit)
        uint(actor_record + 8, id)
        uint(actor_record + 16, unit)
        map(owner + Layout.unit_map, unit, 1)
        map(avatars + n.roots_avatar_manager_map, id, 0)
        map(inventory + 0x28, id, 0)
        map(selector + 0x30, id, 0)
        uint(controller + n.avatar_controller_dive_identity_offset, id)
        info.avatar_unit_ref, info.binding.avatar_id = unit, id
        f.body_unit = unit
    end
    function f:heat_sample(value, limit, use_override, resource, kind)
        info.ammo_kind = kind or "heat"
        info.resource_hex = resource or "27ee1ed8f6fb6356"
        local low, high = tonumber(info.resource_hex:sub(9, 16), 16), tonumber(info.resource_hex:sub(1, 8), 16)
        uint(weapon_record, low)
        uint(weapon_record + 4, high)
        for _, row in ipairs(Build.heat_witnesses) do
            put(base + row.at, (row.hex:gsub("..", function(v)
                return string.char(tonumber(v, 16))
            end)))
        end
        local heat, runtime, configs = 0x57000000, 0x57002000, 0x58000000
        pointer(base + Layout.heat, heat)
        uint(heat + 0x14, 1)
        map(heat + 0x28, weapon_id, 0)
        pointer(heat + 0x40, 0x57001000)
        pointer(0x57001000, weapon_record)
        pointer(heat + 0x58, runtime)
        zero(runtime, 12)
        float(runtime + 4, value)
        local config
        if use_override then
            map(heat + 0x68, weapon_id, 0)
            pointer(heat + 0xa8, configs)
            config = configs
        else
            map(heat + 0x68, weapon_id + 1, 0)
            pointer(owner + Layout.static.heat[1], configs)
            zero(configs, 60 * 16)
            local home = ((high % 60) * (2 ^ 32 % 60) + low % 60) % 60
            uint(configs + home * 16, low)
            uint(configs + home * 16 + 4, high)
            config = configs + 60 * 16
        end
        float(config + 0x60, limit)
        f.heat, f.heat_runtime, f.heat_config = heat, runtime, config
        return f:sample()
    end
    return f
end
return Fixture
