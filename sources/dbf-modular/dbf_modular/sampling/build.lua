-- Selected HUD+ anchor/aim/UI facts, moved to build26568081 by maps/dbf-modular/port.py; no HUD product/runtime imported.
return {
    game_timestamp = 1794319041,
    modules = {
        game = { timestamp = 0x6af322c1, image_size = 0x3382000, machine = 0x8664, magic = 0x20b },
        exe = { timestamp = 0x6af2d5e6, image_size = 0x29fe000, machine = 0x8664, magic = 0x20b },
    },
    -- Current26251122 read-only box converter and Unit graph layout witnesses.
    geometry_witnesses = {
        {
            rva = 0x1f1260,
            hex = "4c8bdc4881ec980000000f28020f11010f284a100f1149100f2842200f1141200f284a300f1149300f2842400f114140f20f104a50f20f114950410f2973e80f297c2470450f2943c8450f294bb8450f2953a8f3440f105248f3440f585254450f295b98f3440f105a40f3440f585a4c450f296388f3440f106244440f296c2410f3440f586250f3440f102de8c15501f3450f59ddf3450f59d5f3450f59e5410f28c3f30f5901410f28caf30f594920410f28d4f30f595110410f28dcf30f58d0410f28c3f30f58d1410f28caf30f585130f30f115130f30f594104f30f594924f30f595914f30f58d8f30f58d9f30f585934f30f115934f3440f596118f3440f595908f3440f595128f3450f58e3f3450f58e2f3440f586138f3440f116138f30f10524cf30f5c5240f30f104254f30f5c4248f30f104a50f30f5c4a44f3410f59d5f3410f59c5f3410f59cdf30f114424080f28c28b4424080f14c1f30f100d4bcf5501f20f11414c894154f30f10594cf30f1041540f57d9f30f1051500f57c10f57d1f30f114424080f28cb8b4424084d8d1b410f2873e80f287c2470450f2843c8450f284bb8450f2853a8450f285b98450f286388440f286c24100f14caf20f114940894148488bc1498be3c3",
        },
        {
            rva = 0xa06d0,
            hex = "48895c24084889742410574883ec20488b351270a1018bd9488d8ed0000000ff159bcd3e018bc325ffff3f003b8698000000720433dbeb1c8bc8488b86a0000000c1eb16381c0175eb488b8688000000488b1cc8488d8ed0000000ff1557cd3e01488b742438488bc3488b5c24304883c4205fc3",
        },
        {
            rva = 0x28e700,
            hex = "48895c2410574883ec20488db9d8010000488bda48833f0074628b124889742430beffffffff8b4b048d42013bc1762883f90872128bc148d1e84803c1483bc6760a488bc6eb05b8080000008bd0488bcbe81aa6e1ff8b13488b07488b4b08488904d1ff03488b3f8b134881c7e001000048833f0075af488b742430488b5c24384883c4205fc3",
        },
        {
            rva = 0x174d4d8,
            hex = "0000003f",
            code = false,
        },
    },
    -- Exact current26251122 decrypted witnesses, independently read live.
    -- Typed heat definition hash/stride and native division by config+0x60.
    heat_witnesses = {
        {
            at = 0x516310,
            hex = "4885c9745c488b059cde7c02448bc14c8b909047f10048b8898888888888888848f7e148c1ea056bc23c442bc04533c9418bc048c1e0044903c2488b10483bd174224885d2741a418bc0418d50014533c041ffc183f83b440f45c24183f93c72cf33c0c34885c074f88b48084869c1500200004805c00300004903c2c3",
        },
        {
            at = 0x15d95bd,
            hex = "8b475c0f57c9c745e00c000000f3480f2ac833c0488945e8488945f08bc3ffc30f1045e0486bc81c0fc6c0e1f30f10c10f28cb0fc6c0e10f1145e00f110431f20f1045f0f20f1144311089543118498bcbe83dd8f3fe4885c0740af30f1047780f2fc3772e4d85ff740bf3410f1047080f2fc377154d85f6742241837e6406751b66410f6e46680f5bc0f30f5ec4f30f594774f30f104f60f30f5ec8413bdd0f",
        },
    },
    menu_panel = 0x24e340 + 0x146940,
    menu_open_at = 0x38769,
    numbers = {
        ["hud_scene_manager"] = 47060232,
        ["hud_scene"] = 705180,
        ["hud_scene_mission"] = 4,
        ["roots_hud_manager_rva"] = 48400264,
        ["hud_widgets_mission_hud"] = 2417472,
        ["hud_widgets_panels_self_panel_at"] = 96,
        ["hud_gate_ready"] = 2224432,
        ["hud_built"] = 2417460,
        ["hud_local_pause"] = 89,
        ["hud_widgets_panels_crosshair_at"] = 1681016,
        ["hud_widgets_size_x"] = 36,
        ["widget_gui_context"] = 248,
        ["widget_inherited_opacity"] = 84,
        ["widget_shown_bit"] = 4,
        ["ui_context_live"] = 1,
        ["ui_context_world"] = 16,
        ["health_bar_drawn"] = 3296,
        ["self_panel_health_bar"] = 16648,
        ["self_panel_health_danger"] = 19948,
        ["hud_widgets_stamina_panel_at"] = 22392,
        ["stamina_panel_share"] = 10868,
        ["self_panel_stims"] = 22184,
        ["hud_self_throwables"] = 22168,
        -- HUD+ Panel:throwable_icon: the native HUD has already selected the
        -- equipped grenade's texture; preserve it instead of a resource catalog.
        ["self_panel_throwable_picture"] = 22200,
        ["self_panel_throwable_icon"] = 8032,
        -- Stock169bd0c uses the current resource's filled ammo art+0x408
        -- on self+0x3488; outline+0x410 is a different reserve-canister image.
        ["self_magazine_fill"] = 13448,
        ["weapon_data_instance_ammo_icon"] = 1032,
        ["hud_self_last_slot"] = 22288,
        ["throwable_slot"] = 4,
        ["hud_weapon_count_shown"] = 22164,
        ["hud_weapon_reserve_shown"] = 22156,
        ["hud_weapon_ammo_state"] = 22188,
        ["hud_ammo_none_state"] = 4,
        ["ammo_gauge"] = 22228,
        ["self_panel_magazine_low"] = 22179,
        ["self_panel_reserve_low"] = 22180,
        ["self_panel_bright"] = 22192,
        ["spare_widget"] = 14944,
        ["roots_avatar_manager_rva"] = 47062752,
        ["roots_avatar_manager_map"] = 248,
        ["roots_avatar_manager_controller_base"] = 5495040,
        ["roots_avatar_manager_controller_stride"] = 4672,
        ["avatar_controller_dive_identity_offset"] = 2948,
        ["avatar_action_words"] = 3976,
        -- Current-build first_person/backend.lua174: owner+0x53e9c0+i*0x1240,
        -- relative to the existing owner+0x53d900 controller record.
        ["avatar_viewmodel_offset"] = 0x10c0,
        -- FPS weapon attachment hash; native-work/fp-rig-trace ADS receipt
        -- resolves the live weapon renderer root to this FPS graph node.
        ["viewmodel_weapon_node"] = 0x4fdd3337,
        -- Current FPS rig: l_hand. Gadget Kit native rig validation and the
        -- labelled26251122 trace agree; resolve the hash, never a bone index.
        ["viewmodel_left_arm_node"] = 0x5c0c68d3,
        -- l_elbow: same current Gadget Kit rig witnesses (pose.cpp133 /
        -- editor.cpp213), and labelled FPS trace raw12. Resolve by hash.
        ["viewmodel_left_elbow_node"] = 0x1ca2cd66,
        ["aim_action_bit"] = 82,
        ["first_person_action_bit"] = 48,
        ["switch_action_word"] = 8,
        ["switch_action_bit"] = 47,
        ["avatar_head_node"] = 2354409673,
        -- Pinned HUD+ numbers.lua773/world_inputs152..203; current live
        -- Unit.alive/head lookup confirms this handle. +16 is the DBF reference.
        ["record_engine_unit"] = 12,
        ["camera_manager"] = 48400336,
        -- Current-build first_person/backend.lua:_top queue selection. The
        -- eight bytes at +0x1f8 contain head then tail, in that order.
        ["camera_queue_head"] = 0x1f8,
        ["camera_queue_tail"] = 0x1fc,
        ["camera_queue_rows"] = 0x200,
        ["camera_queue_stride"] = 0xe8,
        ["camera_queue_fallback"] = 0x1f00,
        ["weapon_data_manager"] = 47062688,
        ["weapon_data_map"] = 48,
        ["weapon_data_r1_at"] = 88,
        ["weapon_data_r1_stride"] = 1008,
        ["weapon_data_fire_count"] = 216,
        ["weapon_data_fire_node"] = 120,
        ["reload_manager"] = 47062064,
    },
    supply = {
        parent = 0x820,
        material = "358512d85e35b47d",
        stim_texture = "93b43ada76587340",
        stim_width = 64,
        stim_height = 32,
    },
    calls = {
        -- HUD+ Ui:image / picture_set. Existing Original DBF sprite machinery
        -- supplies construction, context scopes, setters and guarded release.
        ["supply_picture_set"] = {
            rva = 0x12e80a0,
            module = "game",
            ctype = "void (*)(uintptr_t, uint64_t, uint64_t, uint8_t)",
            head = "48895c2410574883ec30498bd8488bf9450fb6c1",
            mask = "ffffffff00ffffffffffffffffffffffffffffff",
            head_at = 0,
        },
        -- HUD+ Ui:rotation forwards degrees (WeaponPanel uses90 unchanged).
        ["supply_rotation_set"] = {
            rva = 0x12e0d60,
            module = "game",
            ctype = "uint64_t (*)(uintptr_t, float)",
            head = "40574883ec20f30f1081a4000000488bf90f2ec1",
            mask = "ffffffffffffffffffff00000000ffffffffffff",
            head_at = 0,
        },
        ["unit_box"] = {
            rva = 0x1fb860,
            module = "exe",
            ctype = "uintptr_t (*)(float *, uint32_t, uint32_t)",
            -- Current UnitCApi slot1912: sret76 bytes; never use the older SDK slot.
            head = "48895c2408574881ece0000000488bf9418bd88bcae8564eeaff4533c0488d54242085db488bc84c8b08410f95c041ff9138020000f30f104424600f2f44246c7774f30f104424640f2f4424707767f30f104424680f2f442474775a488d542420488d8c2480000000e89259ffff0f10200f296424200f1050100f295424300f1058200f295c24400f1068300f296c24500f1040400f29442460f20f104850f20f114c2470f20f1044246c8b442474f20f114740eb1a0f286c245033c00f285c24400f285424300f2864242048894740488b9c24f0000000894748488bc70f11270f1157100f115f200f116f304881c4e00000005fc3",
            mask = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            head_at = 0,
        },
        ["unit_alive"] = {
            rva = 2051440,
            module = "exe",
            ctype = "bool (*)(uint32_t)",
            head = "4883ec28e857b9eaff4885c00f95c04883c428c3",
            mask = "ffffffffff00000000ffffffffffffffffffffff",
            head_at = 0,
        },
        ["unit_node"] = {
            rva = 2049184,
            module = "exe",
            ctype = "int32_t (*)(uint32_t, uint32_t)",
            head = "40534883ec208bdae823c2eaff488bc84c8b0041ff90e8000000488bd0",
            mask = "ffffffffffffffffff00000000ffffffffff00ffffff00000000ffffff",
            head_at = 0,
        },
        ["unit_world_position"] = {
            rva = 2043984,
            module = "exe",
            ctype = "uintptr_t (*)(uint32_t, int32_t)",
            head = "40534883ec204863dae872d6eaff488bc84c8b0041ff90e8000000488bcb48c1e1064883c130488b40284803c14883c4205bc3",
            mask = "ffffffffffffffffffff00000000ffffffffff00ffffff00000000ffffffffffffffffffffffffffff00ffffffffffffffffff",
            head_at = 0,
        },
        ["unit_world_pose"] = {
            rva = 2044128,
            module = "exe",
            ctype = "uintptr_t (*)(uint32_t, int32_t)",
            -- Current26251122 live read; stop at this getter's RET, not padding
            -- or the adjacent routine. The relative call remains masked.
            head = "40534883ec204863dae8e2d5eaff488bc84c8b0041ff90e8000000488bcb48c1e10648034828488bc14883c4205bc3",
            mask = "ffffffffffffffffffff00000000ffffffffff00ffffff00000000ffffffffffff00ffffff00ffffffffffffffffff",
            head_at = 0,
        },
        ["camera_world_to_screen"] = {
            rva = 3005104,
            module = "exe",
            ctype = "uintptr_t (*)(float *, uintptr_t, const float *)",
            head = "48895c2408574883ec60488b05ff9c7d014d8bd8488bfa",
            mask = "ffffffff00ffffffffffffffff00000000ffffffffffff",
            head_at = 0,
        },
        ["reloading"] = {
            rva = 7870240,
            module = "game",
            ctype = "bool (*)(uintptr_t, uint32_t)",
            head = "48895c2418555657415641574883ec208b1daed96b02",
            mask = "ffffffff00ffffffffffffffffffff00ffff00000000",
            head_at = 0,
        },
    },
}
