local PORT51=mod.require('src/first_person/compat51.lua')
-- Build-specific native camera contract. RVAs are relative to game.dll.
-- tools/trace_native.py verifies these bytes against a supplied offline dump.
return {
    timestamp = 0x6ae0e5ff,
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
        enter = 0x110fb20,
        exit = 0x1110740,
        allowed = 0x1144c00,
    },
    alignment = {
        abi = 1,
        library = 'native/native_ads_alignment_26251122_bcd13229a6a7.dll',
        duration_ms = 10500,
        executable = {
            name = 'helldivers2.exe', timestamp = 0x6ae0964a, image_size = 0x29fe000,
            unit_registry = 0x1ab76f8,
        },
        -- These call instructions stay intact: the native helper filters only
        -- the leased unit and these two callers, forwarding every other call.
        position_return = 0x111a6ad,
        rotation_return = 0x111a6cd,
    },
    pose = {
        -- Native validation owns this captured rig contract: branch5/9B115563
        -- contains l_hand(13), r_hand(34), weapon attachment8; camera50 is a
        -- sibling under root4. Its copied local vector cannot move that camera.
        abi = 2,
        library = 'native/native_ads_editor_26251122_bcd13229a6a7.dll',
        duration_ms = 30500,
        blend_ms = 150,
        -- Arms/weapon branch parent coordinates; screen-right/down remains live QA.
        offset_x = 0.15,
        offset_y = 0,
        offset_z = -0.12,
        executable = {
            name = 'helldivers2.exe', timestamp = 0x6ae0964a, image_size = 0x29fe000,
            unit_registry = 0x1ab76f8,
        },
    },
    fov = {
        abi = 1,
        library = 'native/native_ads_fov_26251122_bcd13229a6a7.dll',
        executable = { name = 'helldivers2.exe', timestamp = 0x6ae0964a, image_size = 0x29fe000 },
    },
    blur = {abi=1,library='native/native_ads_blur_26251122_bcd13229a6a7.dll'},
    -- Near clip: game.dll 0x110DCAB sets near 0.05 through CameraAPI+0x68 each update.
    near = {abi=1,library='native/native_ads_near_26251122_8e4f29e63a3f.dll'},
    motion = {
        world_pose = {rva=0x1f3020,hex='40534883ec204863dae872d6eaff488bc84c8b0041ff90e8000000488bcb48c1e10648034828488bc14883c4205bc3c3'},
    },
    camera = {
        abi=1,library='native/native_ads_camera_26251122_bcd13229a6a7.dll',
        forward=.18,up=.04,smoothing_ms=100,blend_ms=120,max_gap_ms=250,
        executable={name='helldivers2.exe',timestamp=0x6ae0964a,image_size=0x29fe000},
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
            name = 'helldivers2.exe', timestamp = 0x6ae0964a, image_size = 0x29fe000,
            exists = { rva = 0x1f7510, hex = '48895c2408574883ec208bfae87f91eaff488bc8488bd84c8b0041ff90b00100' },
            trigger = { rva = 0x1f7700, hex = '48895c2408574883ec208bda8bf9e88d8feaff448bc38bd7488b4818488b5c24' },
        },
    },
    checks = {
        {name = "enter_wrapper", rva = 0x110fb20, hex = "40534883ec20488b1da38cd101488bcbe85b0000008b83fc0100003983f80100007509488d93001f"},
        {name = "constructor", rva = 0x110fb90, hex = "4055535657488dac2478ffffff4881ec88010000488b0565543a014833c4488945500f57c033c041"},
        {name = "exit", rva = 0x1110740, hex = "405541544156488dac24d0feffff4881ec30020000488b05b4483a014833c4488945708b81fc0100"},
        {name = "evaluator", rva = 0x1118210, hex = "48895c24205556574154415541564157488dac24f0fcffff4881ec10040000440f299c24b0030000"},
        {name = "controller_enter", rva = 0x1144890, hex = "48895c2410574883ec20807904008bda488bf90f85010100008339000f85f8000000807905000f85"},
        {name = "controller_exit", rva = 0x11449c0, hex = "4883ec28807904007446c6410400488b0dfb3dce01e866bdfcff488b0527cbb9"},
        {name = "controller_update", rva = 0x1144580, hex = "f30f114c24105341574883ec38488b0584d0b9014c8bf983b8880000000074128b90a8030000488d"},
        {name = "controller_aim_gate", rva = 0x1144783, hex = "48b800000000000001004985842488e853004c8b64243074083b3d16b5cf017508498bcfe814020000"},
        {name = "input_desired_gate", rva = 0xa5c41b, hex = "488b0d86bd3d024c8bb424b80000003a4104741984c074098bd3e856846e00eb0c488b0d65bd3d02e878856e00"},
        {name = "allowed", rva = 0x1144c00, hex = "48895c240848896c2410488974241857415641574883ec203b15b2a4cf017452488b1d79d2b90145"},
        {name = "allow_fpv_field", rva = 0x1144cdb, hex = "418bc9488b0ccee829d33cff80b880010000007482b001eb80"},
        {name = "root_position_call", rva = 0x111a6a9, hex = "41ff5138"},
        {name = "root_rotation_call", rva = 0x111a6c9, hex = "41ff5148"},
        {name = "pose_branch_position_call", rva = 0x111a300, hex = "41ff5138"},
    },
}
