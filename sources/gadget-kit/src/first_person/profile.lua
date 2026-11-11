local PORT51=mod.require('src/first_person/compat51.lua')
-- Build-specific native camera contract. RVAs are relative to game.dll.
-- tools/trace_native.py verifies these bytes against a supplied offline dump.
return {
    timestamp = 0x6af322c1,
    image_size = 0x3382000,
    globals = {
        camera = 0x2e287d0,
        controller = 0x2e381a8,
        world = 0x2ce41b8,
        player = 0x2ce1618,
        avatar = 0x2ce1ee0,
        wield = 0x2ce1fd0,
        weapons = 0x2ce1ea0,
    },
    functions = {
        -- Wrapper replaces RCX, but forwards EDX/R8D: pass (nil, avatar, weapon).
        enter = 0x110fc80,
        exit = 0x11108a0,
        allowed = 0x1144d60,
    },
    alignment = {
        abi = 1,
        library = 'native/native_ads_alignment_26568081_8e0af36233bd.dll',
        duration_ms = 10500,
        executable = {
            name = 'helldivers2.exe', timestamp = 0x6af2d5e6, image_size = 0x29fe000,
            unit_registry = 0x1ab76f8,
        },
        -- These call instructions stay intact: the native helper filters only
        -- the leased unit and these two callers, forwarding every other call.
        position_return = 0x111a80d,
        rotation_return = 0x111a82d,
    },
    pose = {
        -- Native validation owns this captured rig contract: branch5/9B115563
        -- contains l_hand(13), r_hand(34), weapon attachment8; camera50 is a
        -- sibling under root4. Its copied local vector cannot move that camera.
        abi = 2,
        library = 'native/native_ads_editor_26568081_5ea05817ad56.dll',
        -- SDK-only trial stays off until explicitly requested for a timed lease.
        normalize_zoom_input = false,
        duration_ms = 30500,
        blend_ms = 150,
        -- Arms/weapon branch parent coordinates; screen-right/down remains live QA.
        offset_x = 0.15,
        offset_y = 0,
        offset_z = -0.12,
        executable = {
            name = 'helldivers2.exe', timestamp = 0x6af2d5e6, image_size = 0x29fe000,
            unit_registry = 0x1ab76f8,
        },
    },
    fov = {
        abi = 1,ads_blend_ms=180,
        library = 'native/native_ads_fov_26568081_764664986628.dll',
        executable = { name = 'helldivers2.exe', timestamp = 0x6af2d5e6, image_size = 0x29fe000 },
    },
    blur = {abi=1,library='native/native_ads_blur_26568081_c18c221e2cc6.dll'},
    -- Near clip: game.dll 0x110DE0B sets near 0.05 through CameraAPI+0x68 each update.
    near = {abi=1,library='native/native_ads_near_26568081_d9ac0249f950.dll'},
    -- Owned normal4 body only: skip the native hipfire start/end events.
    held_fire = {abi=1,library='native/native_ads_heldfire_26568081_4553a768a134.dll'},
    motion = {
        world_pose = {rva=0x1f30e0,hex='40534883ec204863dae8e2d5eaff488bc84c8b0041ff90e8000000488bcb48c1e10648034828488bc14883c4205bc3c3'},
    },
    camera = {
        abi=1,library='native/native_ads_camera_26568081_46e3ba382419.dll',
        forward=.18,up=.04,smoothing_ms=100,blend_ms=120,max_gap_ms=250,
        executable={name='helldivers2.exe',timestamp=0x6af2d5e6,image_size=0x29fe000},
    },
    -- Optional manual diagnostic only: the paired native exit body event.
    -- Event semantics and its effect on the held weapon pose remain unproven.
    body_pose = {
        event = 0x372071D0,
        unit_api_global = 0x2ce14c8,
        api_offset = 0x18,
        exists_offset = 0x350,
        trigger_offset = 0x370,
        executable = {
            name = 'helldivers2.exe', timestamp = 0x6af2d5e6, image_size = 0x29fe000,
            exists = { rva = 0x1f75d0, hex = '48895c2408574883ec208bfae8ef90eaff488bc8488bd84c8b0041ff90b00100' },
            trigger = { rva = 0x1f77c0, hex = '48895c2408574883ec208bda8bf9e8fd8eeaff448bc38bd7488b4818488b5c24' },
        },
    },
    checks = {
        {name = "enter_wrapper", rva = 0x110fc80, hex = "40534883ec20488b1d438bd101488bcbe85b0000008b83fc0100003983f80100007509488d93001f"},
        {name = "constructor", rva = 0x110fcf0, hex = "4055535657488dac2478ffffff4881ec88010000488b0505533a014833c4488945500f57c033c041"},
        {name = "exit", rva = 0x11108a0, hex = "405541544156488dac24d0feffff4881ec30020000488b0554473a014833c4488945708b81fc0100"},
        {name = "evaluator", rva = 0x1118370, hex = "48895c24205556574154415541564157488dac24f0fcffff4881ec10040000440f299c24b0030000"},
        {name = "controller_enter", rva = 0x11449f0, hex = "48895c2410574883ec20807904008bda488bf90f85010100008339000f85f8000000807905000f85"},
        {name = "controller_exit", rva = 0x1144b20, hex = "4883ec28807904007446c6410400488b0d9b3cce01e866bdfcff488b05c7c9b9"},
        {name = "controller_update", rva = 0x11446e0, hex = "f30f114c24105341574883ec38488b0524cfb9014c8bf983b8880000000074128b90a8030000488d"},
        {name = "controller_aim_gate", rva = 0x11448e3, hex = "48b800000000000001004985842488e853004c8b64243074083b3db6b3cf017508498bcfe814020000"},
        {name = "input_desired_gate", rva = 0xa5c44b, hex = "488b0d56bd3d024c8bb424b80000003a4104741984c074098bd3e886856e00eb0c488b0d35bd3d02e8a8866e00"},
        {name = "allowed", rva = 0x1144d60, hex = "48895c240848896c2410488974241857415641574883ec203b1552a3cf017452488b1d19d1b90145"},
        {name = "allow_fpv_field", rva = 0x1144e3b, hex = "418bc9488b0ccee8c9d13cff80b880010000007482b001eb80"},
        {name = "root_position_call", rva = 0x111a809, hex = "41ff5138"},
        {name = "root_rotation_call", rva = 0x111a829, hex = "41ff5148"},
        {name = "pose_branch_position_call", rva = 0x111a460, hex = "41ff5138"},
    },
}
