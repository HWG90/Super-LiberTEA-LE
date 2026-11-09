-- Persisted choice/semantic hash contract, independently checked against the
-- labelled26251122 trace and the current Gadget Kit C++ rig witnesses.
local file = assert(io.open("dbf_modular/sampling/first_person_bones.lua", "rb"))
local source = file:read("*a")
file:close()
local chunk = assert(loadstring(source, "@first_person_bones.lua"))
setfenv(
    chunk,
    setmetatable({ type = type, ipairs = ipairs }, {
        __index = function(_, key)
            error("Catalog must be schema-safe pure data; unexpected global:" .. tostring(key))
        end,
    })
)
local Bones = chunk()
local expected = {
    { "Weapon chassis", 0x4fdd3337, "viewmodel" },
    { "Left wrist", 0x5c0c68d3, "tfp_left_wrist" },
    { "Left elbow", 0x1ca2cd66, "tfp_left_elbow" },
    { "Right wrist", 0x248004f5, "tfp_bone" },
    { "Right elbow", 0x31e34dac, "tfp_bone" },
    { "Left shoulder", 0x03752c98, "tfp_bone" },
    { "Right shoulder", 0x1620b2ce, "tfp_bone" },
    { "Chest", 0x37ef0820, "tfp_bone" },
    { "Left clavicle", 0xc4787b4e, "tfp_bone" },
    { "Right clavicle", 0xb2bcd839, "tfp_bone" },
}
local checks = 0
local function eq(a, b, why)
    checks = checks + 1
    assert(a == b, (why or "different") .. ":" .. tostring(a) .. "~=" .. tostring(b))
end
eq(#Bones.choices, 88)
local used = {}
for choice, row in ipairs(expected) do
    eq(Bones.choices[choice], row[1], "stable persisted choice label")
    local hash, calibration, domain = Bones.resolve(choice)
    eq(hash, row[2], "current named semantic hash")
    eq(calibration, row[3])
    eq(domain, "fps", "old persisted choices retain their unit domain")
    eq(used[hash], nil, "choices are a bijection, not aliases for another bone")
    used[hash] = true
end
-- Independently retained name/hash inventory from the earlier equipped-weapon
-- picker (source SHA4a0344a4f6f8e401039a7fd8d2719e0b480fce77e59b7ae0914eca15d149fa0a).
local weapon_names = {
    [0x1245b39c] = "standard_pistol",
    [0x12cda115] = "hellpod_interact_node",
    [0x15c8ade4] = "IK_right",
    [0x16092557] = "g_mg_LOD1",
    [0x175f53c9] = "g_reciever_LOD4",
    [0x1a26b734] = "g_reciever_LOD3",
    [0x1d667f2e] = "shadow_mesh",
    [0x1e307614] = "g_body_shadow_LOD2",
    [0x1f8155c7] = "g_reciever",
    [0x27a837b4] = "g_reciever_shadow_LOD2",
    [0x315cd161] = "game_mesh",
    [0x32188af1] = "bolt_carrier",
    [0x3e2c3cb2] = "g_mg_LOD2",
    [0x450a8e24] = "g_reciever_shadow",
    [0x4a182741] = "StingrayEntityRoot",
    [0x4c3a8f75] = "g_body",
    [0x4cc67131] = "c_bodycollisionbot",
    [0x51c77b11] = "g_body_shadow",
    [0x58c66627] = "c_bodycollisiontop",
    [0x6685da74] = "bipod_swivel",
    [0x670a7fdd] = "feed_arm",
    [0x67c94e4b] = "IK_left",
    [0x71b4f330] = "g_body_shadow_LOD1",
    [0x754fe6c2] = "bolthandle",
    [0x789b7d63] = "ejector",
    [0x7950e36e] = "attach_underbarrel",
    [0x7a3790c2] = "g_body_shadow_LOD3",
    [0x7f30e61c] = "FbxAxisSystem_ConvertNode",
    [0x8144a2c2] = "pivot",
    [0x817d30f2] = "g_mg_shadow_LOD1",
    [0x839f1a10] = "g_body_LOD2",
    [0x83c9fe1a] = "g_mg_shadow",
    [0x8f998342] = "g_mg_shadow_LOD3",
    [0x93d8a8f2] = "l_bipod",
    [0x975cebbd] = "skeleton",
    [0x97fcfe68] = "g_mg_shadow_LOD2",
    [0x98deb5de] = "topcover",
    [0x9b115563] = "boss",
    [0x9f15b85a] = "g_body_LOD1",
    [0xa3d491d1] = "collision",
    [0xade50005] = "fire_selector",
    [0xb1f3aa0a] = "attach_paintjob",
    [0xb34be51e] = "g_mg_LOD3",
    [0xb41f604d] = "g_reciever_LOD1",
    [0xb4afc5cb] = "c_reciever",
    [0xbbb52fb1] = "g_body_LOD4",
    [0xbdae5555] = "g_mg",
    [0xbdc96a7f] = "r_bipod",
    [0xc372217f] = "g_reciever_shadow_LOD1",
    [0xc489b14a] = "ejection_cover",
    [0xc4a1d881] = "g_reciever_shadow_LOD3",
    [0xc5a432d3] = "barrel_handle",
    [0xd5a0518b] = "g_body_LOD3",
    [0xd69497c1] = "g_reciever_LOD2",
    [0xd7901849] = "bolthandle_pivot",
    [0xda874826] = "g_mg_LOD4",
    [0xdc0a2993] = "ejector_socket",
    [0xe50d157f] = "cog",
    [0xe81e9a8c] = "assault_rifle",
    [0xe994e9e9] = "machinegun",
    [0xfaeed71d] = "attach_ammo",
    [0xfd2aac63] = "feed_plate",
    [0x0844391a] = "slide",
    [0x23569738] = "attach_mag_2",
    [0x2c8ece2b] = "muzzle",
    [0x4d25685a] = "attach_optic",
    [0x527c9c73] = "sight",
    [0x57520abf] = "attach_muzzle",
    [0x5be474d2] = "c_grip",
    [0x866cc914] = "barrel",
    [0xb232fef2] = "eject",
    [0xb298a52a] = "attach_weapon",
    [0xb78d5aa4] = "trigger",
    [0xbccf91e5] = "root",
    [0xc03596c1] = "hammer",
    [0xc0978950] = "c_scope",
    [0xca03689c] = "bolt",
    [0xe7f88e90] = "attach_mag",
}
local priority = {
    "StingrayEntityRoot",
    "attach_optic",
    "sight",
    "g_reciever",
    "g_body",
    "root",
    "attach_weapon",
    "muzzle",
    "attach_muzzle",
    "barrel",
    "c_grip",
    "attach_mag",
    "attach_mag_2",
    "attach_ammo",
    "attach_underbarrel",
    "bolt",
    "bolt_carrier",
    "trigger",
    "fire_selector",
    "pivot",
    "hammer",
    "g_mg",
}
local count, previous = 0, nil
for choice = 11, #Bones.choices do
    local hash, calibration, domain = Bones.resolve(choice)
    local name = weapon_names[hash]
    eq(type(name), "string", "every appended choice is in the source-backed native-name catalog")
    eq(Bones.choices[choice], "Weapon: " .. name)
    eq(calibration, "tfp_weapon", "weapon poses have a separate zero calibration")
    eq(domain, "weapon", "hash equality cannot select the FPS rig")
    eq(used[hash], nil, "no duplicated semantic hash was appended")
    used[hash], count = true, count + 1
    if choice <= 10 + #priority then
        eq(name, priority[choice - 10], "stable useful-part order")
    else
        if previous then
            eq(hash > previous, true, "remaining source rows have deterministic numeric-hash order")
        end
        previous = hash
    end
end
eq(count, 78)
for hash in pairs(weapon_names) do
    eq(used[hash], true, "full source inventory survives, including LOD/collision/helper nodes")
end
for _, invalid in ipairs({ false, true, "1", {}, -1, 0, #Bones.choices + 1, 1.5, math.huge, 0 / 0 }) do
    local hash, calibration, domain = Bones.resolve(invalid)
    eq(hash, nil, "unverified choice cannot reach a native getter")
    eq(calibration, nil)
    eq(domain, nil)
end
eq(Bones.resolve(nil), nil)
print("First-person and weapon bones:" .. checks .. " checks passed")
