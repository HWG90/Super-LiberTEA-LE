-- The untouched native/input algorithms remain the exact restored source, ported to build26568081
-- (reference/original-dbf-26568081 = the immutable reference/original-dbf through maps/dbf-modular/port.py).
local changed = {
    entry = true,
    settings = true,
    mission_blacklist = true,
    terminal = true,
    weapon_status = true,
    binding_warning = true,
    cooldown_dock = true,
    expanded = true,
    weapon_status_strip = true,
}
local modules = {
    "layout",
    "guards",
    "native",
    "native_startup",
    "menu_latch",
    "mission_blacklist",
    "input",
    "pointing",
    "camera",
    "icon_colors",
    "duplicate",
    "emote",
    "expanded",
    "cooldown_gui",
    "cooldown_dock",
    "binding_warning",
    "binding_defaults",
    "selection",
    "release",
    "blacklist",
    "settings",
    "feedback",
    "hud_plus",
    "foliage_compat",
    "entry",
    "stratagems",
    "weapon_status_memory",
    "weapon_status_layouts",
    "weapon_status_ammo",
    "weapon_status_reader",
    "weapon_status_strip",
    "weapon_status",
    "terminal_guards",
    "terminal",
}
local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end
local checked = 0
for _, name in ipairs(modules) do
    if not changed[name] then
        assert(
            read("dbf_modular/src/" .. name .. ".lua") == read("reference/original-dbf-26568081/src/" .. name .. ".lua"),
            "Native algorithm changed: " .. name
        )
        checked = checked + 1
    end
end
assert(checked == 25)
print("Core preservation: " .. checked .. " exact native modules")
