-- Shared by the settings schema and sampler: pure data, no FFI or game access.
-- IDs1..10 are persisted preferences and must never be reordered.
-- Current26251122 FPS rig evidence:
--   gadget-kit/native/first_person/native_ads_pose.cpp132..134 and
--   native_ads_editor.cpp212..214 pin weapon, wrist, elbow and shoulder hashes.
--   native-work/fp-rig-trace/fp-rig-trace-ads.live.log labels the63-node rig;
--   its chest and clavicle names come from Unit.has_node/Unit.node in the
--   matching fp_rig_trace.lua. Unnamed helper bones and absent FPS head are
--   deliberately excluded. Every sample resolves a hash on its current unit.
-- Canonical C++ SHA256 (2026-11-08, read-only):
--   native_ads_pose.cpp:67c2cf4cef06172c59c33920f2629e20c6b6c3c90fb895aaeb136bda457c7afe
--   native_ads_editor.cpp:ba233ad8a128e523e8979651c26def0cff036abf06a85ac609df62ce07a027fc
-- Trace root:/home/goose/Documents/ChatGPT/Linux HD2/native-work/fp-rig-trace/
-- The row comments cite exact trace lines and returned native-node evidence;
-- the numeric indices are documentation only, never used by the sampler.
-- Weapon-domain catalog: all78 unique names/hashes from the earlier equipped-
-- weapon picker, native-work/dbf-hud-port/source/src/layout_editor.lua4..84.
-- SHA256:4a0344a4f6f8e401039a7fd8d2719e0b480fce77e59b7ae0914eca15d149fa0a
-- StingrayEntityRoot is deliberately first/newID11. Its hash also exists on
-- the FPS rig, so a hash NEVER chooses its own unit domain. Old trace155..156
-- records the separate40-node weapon root linked to FPSnode8. Remaining useful
-- main parts precede the other source rows sorted by hash. LOD/collision/helper
-- nodes stay available by native name; each resource may omit them. This is a
-- named static catalog, not a claim that all88 choices exist on every gun.
local rows = {
    { "Weapon chassis", 0x4fdd3337, "viewmodel", "fps" },
    { "Left wrist", 0x5c0c68d3, "tfp_left_wrist", "fps" },
    { "Left elbow", 0x1ca2cd66, "tfp_left_elbow", "fps" },
    { "Right wrist", 0x248004f5, "tfp_bone", "fps" },
    { "Right elbow", 0x31e34dac, "tfp_bone", "fps" },
    { "Left shoulder", 0x03752c98, "tfp_bone", "fps" },
    { "Right shoulder", 0x1620b2ce, "tfp_bone", "fps" },
    { "Chest", 0x37ef0820, "tfp_bone", "fps" },
    { "Left clavicle", 0xc4787b4e, "tfp_bone", "fps" },
    { "Right clavicle", 0xb2bcd839, "tfp_bone", "fps" },
    { "Weapon: StingrayEntityRoot", 0x4a182741, "tfp_weapon", "weapon" },
    { "Weapon: attach_optic", 0x4d25685a, "tfp_weapon", "weapon" },
    { "Weapon: sight", 0x527c9c73, "tfp_weapon", "weapon" },
    { "Weapon: g_reciever", 0x1f8155c7, "tfp_weapon", "weapon" },
    { "Weapon: g_body", 0x4c3a8f75, "tfp_weapon", "weapon" },
    { "Weapon: root", 0xbccf91e5, "tfp_weapon", "weapon" },
    { "Weapon: attach_weapon", 0xb298a52a, "tfp_weapon", "weapon" },
    { "Weapon: muzzle", 0x2c8ece2b, "tfp_weapon", "weapon" },
    { "Weapon: attach_muzzle", 0x57520abf, "tfp_weapon", "weapon" },
    { "Weapon: barrel", 0x866cc914, "tfp_weapon", "weapon" },
    { "Weapon: c_grip", 0x5be474d2, "tfp_weapon", "weapon" },
    { "Weapon: attach_mag", 0xe7f88e90, "tfp_weapon", "weapon" },
    { "Weapon: attach_mag_2", 0x23569738, "tfp_weapon", "weapon" },
    { "Weapon: attach_ammo", 0xfaeed71d, "tfp_weapon", "weapon" },
    { "Weapon: attach_underbarrel", 0x7950e36e, "tfp_weapon", "weapon" },
    { "Weapon: bolt", 0xca03689c, "tfp_weapon", "weapon" },
    { "Weapon: bolt_carrier", 0x32188af1, "tfp_weapon", "weapon" },
    { "Weapon: trigger", 0xb78d5aa4, "tfp_weapon", "weapon" },
    { "Weapon: fire_selector", 0xade50005, "tfp_weapon", "weapon" },
    { "Weapon: pivot", 0x8144a2c2, "tfp_weapon", "weapon" },
    { "Weapon: hammer", 0xc03596c1, "tfp_weapon", "weapon" },
    { "Weapon: g_mg", 0xbdae5555, "tfp_weapon", "weapon" },
    { "Weapon: slide", 0x0844391a, "tfp_weapon", "weapon" },
    { "Weapon: standard_pistol", 0x1245b39c, "tfp_weapon", "weapon" },
    { "Weapon: hellpod_interact_node", 0x12cda115, "tfp_weapon", "weapon" },
    { "Weapon: IK_right", 0x15c8ade4, "tfp_weapon", "weapon" },
    { "Weapon: g_mg_LOD1", 0x16092557, "tfp_weapon", "weapon" },
    { "Weapon: g_reciever_LOD4", 0x175f53c9, "tfp_weapon", "weapon" },
    { "Weapon: g_reciever_LOD3", 0x1a26b734, "tfp_weapon", "weapon" },
    { "Weapon: shadow_mesh", 0x1d667f2e, "tfp_weapon", "weapon" },
    { "Weapon: g_body_shadow_LOD2", 0x1e307614, "tfp_weapon", "weapon" },
    { "Weapon: g_reciever_shadow_LOD2", 0x27a837b4, "tfp_weapon", "weapon" },
    { "Weapon: game_mesh", 0x315cd161, "tfp_weapon", "weapon" },
    { "Weapon: g_mg_LOD2", 0x3e2c3cb2, "tfp_weapon", "weapon" },
    { "Weapon: g_reciever_shadow", 0x450a8e24, "tfp_weapon", "weapon" },
    { "Weapon: c_bodycollisionbot", 0x4cc67131, "tfp_weapon", "weapon" },
    { "Weapon: g_body_shadow", 0x51c77b11, "tfp_weapon", "weapon" },
    { "Weapon: c_bodycollisiontop", 0x58c66627, "tfp_weapon", "weapon" },
    { "Weapon: bipod_swivel", 0x6685da74, "tfp_weapon", "weapon" },
    { "Weapon: feed_arm", 0x670a7fdd, "tfp_weapon", "weapon" },
    { "Weapon: IK_left", 0x67c94e4b, "tfp_weapon", "weapon" },
    { "Weapon: g_body_shadow_LOD1", 0x71b4f330, "tfp_weapon", "weapon" },
    { "Weapon: bolthandle", 0x754fe6c2, "tfp_weapon", "weapon" },
    { "Weapon: ejector", 0x789b7d63, "tfp_weapon", "weapon" },
    { "Weapon: g_body_shadow_LOD3", 0x7a3790c2, "tfp_weapon", "weapon" },
    { "Weapon: FbxAxisSystem_ConvertNode", 0x7f30e61c, "tfp_weapon", "weapon" },
    { "Weapon: g_mg_shadow_LOD1", 0x817d30f2, "tfp_weapon", "weapon" },
    { "Weapon: g_body_LOD2", 0x839f1a10, "tfp_weapon", "weapon" },
    { "Weapon: g_mg_shadow", 0x83c9fe1a, "tfp_weapon", "weapon" },
    { "Weapon: g_mg_shadow_LOD3", 0x8f998342, "tfp_weapon", "weapon" },
    { "Weapon: l_bipod", 0x93d8a8f2, "tfp_weapon", "weapon" },
    { "Weapon: skeleton", 0x975cebbd, "tfp_weapon", "weapon" },
    { "Weapon: g_mg_shadow_LOD2", 0x97fcfe68, "tfp_weapon", "weapon" },
    { "Weapon: topcover", 0x98deb5de, "tfp_weapon", "weapon" },
    { "Weapon: boss", 0x9b115563, "tfp_weapon", "weapon" },
    { "Weapon: g_body_LOD1", 0x9f15b85a, "tfp_weapon", "weapon" },
    { "Weapon: collision", 0xa3d491d1, "tfp_weapon", "weapon" },
    { "Weapon: attach_paintjob", 0xb1f3aa0a, "tfp_weapon", "weapon" },
    { "Weapon: eject", 0xb232fef2, "tfp_weapon", "weapon" },
    { "Weapon: g_mg_LOD3", 0xb34be51e, "tfp_weapon", "weapon" },
    { "Weapon: g_reciever_LOD1", 0xb41f604d, "tfp_weapon", "weapon" },
    { "Weapon: c_reciever", 0xb4afc5cb, "tfp_weapon", "weapon" },
    { "Weapon: g_body_LOD4", 0xbbb52fb1, "tfp_weapon", "weapon" },
    { "Weapon: r_bipod", 0xbdc96a7f, "tfp_weapon", "weapon" },
    { "Weapon: c_scope", 0xc0978950, "tfp_weapon", "weapon" },
    { "Weapon: g_reciever_shadow_LOD1", 0xc372217f, "tfp_weapon", "weapon" },
    { "Weapon: ejection_cover", 0xc489b14a, "tfp_weapon", "weapon" },
    { "Weapon: g_reciever_shadow_LOD3", 0xc4a1d881, "tfp_weapon", "weapon" },
    { "Weapon: barrel_handle", 0xc5a432d3, "tfp_weapon", "weapon" },
    { "Weapon: g_body_LOD3", 0xd5a0518b, "tfp_weapon", "weapon" },
    { "Weapon: g_reciever_LOD2", 0xd69497c1, "tfp_weapon", "weapon" },
    { "Weapon: bolthandle_pivot", 0xd7901849, "tfp_weapon", "weapon" },
    { "Weapon: g_mg_LOD4", 0xda874826, "tfp_weapon", "weapon" },
    { "Weapon: ejector_socket", 0xdc0a2993, "tfp_weapon", "weapon" },
    { "Weapon: cog", 0xe50d157f, "tfp_weapon", "weapon" },
    { "Weapon: assault_rifle", 0xe81e9a8c, "tfp_weapon", "weapon" },
    { "Weapon: machinegun", 0xe994e9e9, "tfp_weapon", "weapon" },
    { "Weapon: feed_plate", 0xfd2aac63, "tfp_weapon", "weapon" },
}
local Bones = { choices = {} }
for choice, row in ipairs(rows) do
    Bones.choices[choice] = row[1]
end
function Bones.resolve(choice)
    if type(choice) ~= "number" or choice ~= choice or choice % 1 ~= 0 then
        return nil
    end
    local row = rows[choice]
    if row then
        return row[2], row[3], row[4]
    end
end
return Bones
