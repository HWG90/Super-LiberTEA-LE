-- Actual current MCM implementation, rather than only a fake registration API.
local Support = assert(loadfile("tests/support.lua"))()
local project, globals = Support.project()
local Schema = project.require("settings/schema.lua")
local Store = project.require("settings/store.lua")
local Menu = project.require("settings/menu.lua")
local MCM = assert(loadfile("reference/mcm/core.lua"))()
local checks = 0
local function eq(actual, expected, why)
    checks = checks + 1
    assert(actual == expected, (why or "different") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local P, text, writes, refuse =
    "native_stratagem_radial.",
    "schema_version=1\nhud.opacity=83.25\nnative_stratagem_radial.wheel_size=103.12345\n",
    0,
    false
local store = Store.new(project, globals, {
    read = function()
        return text
    end,
    read_legacy = function()
        error("Versioned settings must not read original files")
    end,
    write_atomic = function(saved)
        if refuse then
            return false, "atomic disk refusal"
        end
        text, writes = saved, writes + 1
        return true
    end,
})
local api = MCM.new(nil, function() end)
local available = nil
local menu = Menu.new(store, function()
    return available
end)
eq(menu:update(), false, "An unavailable MCM is ordinary pending")
eq(menu.handle, nil)
eq(writes, 0)
available = api
eq(menu:update(), true)
local owner, handle = api.mods.dbf_modular, menu.handle
eq(menu.registered, 91)
eq(#owner.categories, 11)
eq(#owner.pages, 14)
local count, unique, tfp_rows = 0, {}, 0
local placement_rows, placement_control, damping_control, heat_control, vertical_control, limiter_control =
    0, nil, nil, nil, nil, nil
for _ in pairs(api.mods) do
    count = count + 1
end
eq(count, 1)
for _, page in ipairs(owner.pages) do
    local rows = 0
    for _, control in ipairs(page.controls) do
        if control.id then
            eq(unique[control.id], nil)
            unique[control.id] = true
            rows = rows + 1
            if page.id == "hud" and control.id == menu.controls["hud.heat_display"] then
                heat_control = control
            end
            if page.id == "hud" and control.id == menu.controls["hud.heat_bar_vertical"] then
                vertical_control = control
            end
            if page.id == "weapon" and control.id == menu.controls["weapon.heat_limiter"] then
                limiter_control = control
            end
            if page.id == "tfp" then
                tfp_rows = tfp_rows + 1
            end
            if page.id == "placement" then
                placement_rows = placement_rows + 1
                if control.id == menu.controls["hud.cooldown_anchor"] then
                    placement_control = control
                elseif control.id == menu.controls["hud.anchor_damping_ms"] then
                    damping_control = control
                end
            end
        end
    end
    eq(rows > 0 and rows <= 13, true, "Every purpose page is bounded")
end
eq(placement_rows, 9)
eq(tfp_rows, 7)
eq(placement_control.label, "Cooldown placement")
eq(placement_control.type, "choice")
eq(placement_control.choices[1], "Under health")
eq(placement_control.choices[2], "Under ammo")
eq(#placement_control.choices, 2)
eq(menu.controls["hud.cooldown_anchor"], "s_hud_2ecooldown_5fanchor", "one stable MCM route")
eq(damping_control.label, "Anchor damping (ms)")
eq(damping_control.type, "slider")
eq(damping_control.min, 0)
eq(damping_control.max, 300)
eq(damping_control.step, 10)
eq(damping_control.fine_step, 1)
eq(menu.controls["hud.anchor_damping_ms"], "s_hud_2eanchor_5fdamping_5fms", "one stable damping route")
eq(heat_control.label, "Heat display")
eq(heat_control.type, "choice")
eq(table.concat(heat_control.choices, ","), "Percentage,Bar,Hybrid")
eq(menu.controls["hud.heat_display"], "s_hud_2eheat_5fdisplay", "one stable heat route")
eq(vertical_control.label, "Vertical heat bar")
eq(vertical_control.type, "toggle")
eq(menu.controls["hud.heat_bar_vertical"], "s_hud_2eheat_5fbar_5fvertical")
eq(limiter_control.label, "Heat limiter")
eq(limiter_control.type, "toggle")
eq(limiter_control.default, false)
eq(menu.controls["weapon.heat_limiter"], "s_weapon_2eheat_5flimiter")
for id in pairs(Schema.by_id) do
    eq(unique[menu.controls[id]], true)
end
eq(menu.controls.kind_5, "kind_5", "Original exclusion MCM IDs remain recognizable")
local function key(id)
    return assert(menu.controls[id], id)
end
local function value(id)
    return handle.get(key(id))
end
local function set(id, value)
    return handle.set(key(id), value)
end
eq(value("hud.opacity"), 83.25)
eq(value(P .. "wheel_size"), 103.12345)
eq(value("hud.cooldown_anchor"), 1)
eq(value("hud.anchor_damping_ms"), 80)
eq(value("hud.heat_display"), 1)
eq(value("hud.heat_bar_vertical"), false)
eq(handle.available(key("hud.heat_bar_vertical")), false, "orientation is irrelevant to percentage-only mode")
eq(writes, 0, "Registration does not save or round loaded values")
eq(handle.set_many({ [key("hud.enabled")] = false, [key(P .. "enabled")] = false, kind_149 = true }), true)
eq(writes, 1)
eq(store:get("hud.enabled"), false)
eq(store:get(P .. "enabled"), false)
eq(store:get("kind_149"), true)
eq(value(P .. "wheel_size"), 103.12345, "An unrelated setting edit preserves original precision")
refuse = true
local okay, why = set(P .. "wheel_size", 110)
eq(okay, false)
eq(why:find("atomic disk refusal", 1, true) ~= nil, true)
eq(value("hud.opacity"), 83.25)
eq(store:get("hud.opacity"), 83.25)
eq(writes, 1)
refuse = false
eq(handle.available(key("hud.ads_minimal")), false)
eq(handle.available(key("hud.cooldown_anchor")), false)
eq(handle.available(key("hud.anchor_damping_ms")), false)
eq(handle.available(key("hud.heat_display")), false)
eq(set("hud.enabled", true), true)
eq(handle.available(key("hud.ads_minimal")), true)
eq(handle.available(key("hud.cooldown_anchor")), true)
eq(handle.available(key("hud.anchor_damping_ms")), true)
eq(handle.available(key("hud.heat_display")), true)
eq(handle.reset(key("hud.opacity")), true)
eq(value("hud.opacity"), 94, "Reset uses the declared default")
eq(handle.reset(key(P .. "wheel_size")), true)
eq(value(P .. "wheel_size"), 100)
eq(set(P .. "selection_mode_ordered", 2), true)
eq(handle.available(key(P .. "dim_unselected")), true)
eq(handle.available(key(P .. "wheel_size")), false)
eq(set(P .. "selection_mode_ordered", 1), true)
eq(handle.available(key(P .. "experimental_layout")), true)
eq(set(P .. "experimental_layout", 2), true)
eq(handle.available(key(P .. "wedge_opacity")), true)
eq(set(P .. "cooldown_icons", false), true)
eq(handle.available(key(P .. "cooldown_display")), false)
eq(handle.available(key(P .. "cooldown_timer")), false)
eq(set(P .. "cooldown_icons", true), true)
eq(set(P .. "cooldown_timers", false), true)
eq(handle.available(key(P .. "cooldown_timer")), false)
eq(set(P .. "instant_stratagems", true), true)
eq(set(P .. "auto_terminal_complete", true), true)
eq(set(P .. "terminal_input", 1), true)
eq(handle.available(key(P .. "input_interval_ms")), false)
eq(set(P .. "terminal_input", 2), true)
eq(handle.available(key(P .. "input_interval_ms")), true)
eq(set(P .. "randomize_input_delay", true), true)
eq(handle.available(key(P .. "input_interval_ms")), false)
local same = menu.handle
eq(store:set("hud.density", 2), true)
eq(menu:update(), true)
eq(menu.handle, same)
eq(value("hud.density"), 2)

local before_damping = writes
for index, milliseconds in ipairs({ 0, 300, 80 }) do
    eq(set("hud.anchor_damping_ms", milliseconds), true)
    eq(writes, before_damping + index, "MCM damping saves one atomic transaction")
    eq(store:get("hud.anchor_damping_ms"), milliseconds)
    eq(text:find("hud.anchor_damping_ms=" .. milliseconds, 1, true) ~= nil, true)
    eq(value("hud.density"), 2)
    eq(value("hud.cooldown_anchor"), 1)
end
for _, invalid in ipairs({ -1, 301 }) do
    eq(pcall(set, "hud.anchor_damping_ms", invalid), false)
    eq(writes, before_damping + 3, "out-of-range MCM damping cannot save")
    eq(value("hud.anchor_damping_ms"), 80)
end
local before_placement = writes
eq(set("hud.cooldown_anchor", 2), true)
eq(writes, before_placement + 1, "MCM choice saves one atomic transaction")
eq(store:get("hud.cooldown_anchor"), 2)
eq(text:find("hud.cooldown_anchor=2", 1, true) ~= nil, true)
eq(value("hud.density"), 2, "placement does not reset current Detailed choice")
local before_tfp = writes
for _, id in ipairs({ "hud.tfp_vitals_bone", "hud.tfp_ammo_bone" }) do
    eq(value(id), 1)
    eq(handle.available(key(id)), true)
    eq(set(id, 3), true)
    eq(value(id), 3)
end
eq(set("hud.tfp_ammo_placement", 2), true)
eq(handle.available(key("hud.tfp_ammo_bone")), false)
eq(value("hud.tfp_ammo_bone"), 3)
eq(handle.available(key("hud.tfp_vitals_bone")), true)
eq(set("hud.tfp_ammo_placement", 1), true)
eq(handle.available(key("hud.tfp_ammo_bone")), true)
eq(value("hud.tfp_ammo_bone"), 3)
eq(writes, before_tfp + 4, "anchor selections use the existing atomic settings owner")
local before_offsets = writes
local offset_values = { 17, -45, 81, -120 }
for i, id in ipairs({
    "hud.tfp_vitals_offset_x",
    "hud.tfp_vitals_offset_y",
    "hud.tfp_ammo_offset_x",
    "hud.tfp_ammo_offset_y",
}) do
    eq(handle.available(key(id)), true)
    eq(value(id), 0)
    eq(set(id, offset_values[i]), true)
    eq(value(id), offset_values[i])
end
eq(writes, before_offsets + 4)
eq(set("hud.tfp_ammo_placement", 2), true)
eq(handle.available(key("hud.tfp_ammo_bone")), false)
for i, id in ipairs({
    "hud.tfp_vitals_offset_x",
    "hud.tfp_vitals_offset_y",
    "hud.tfp_ammo_offset_x",
    "hud.tfp_ammo_offset_y",
}) do
    eq(handle.available(key(id)), true, "XY tuning remains editable while stacked")
    eq(value(id), offset_values[i])
end
eq(set("hud.tfp_ammo_placement", 1), true)
eq(handle.available(key("hud.tfp_ammo_bone")), true)
local before_heat = writes
for index, mode in ipairs({ 2, 3, 1, 3 }) do
    eq(set("hud.heat_display", mode), true)
    eq(writes, before_heat + index)
    eq(store:get("hud.heat_display"), mode)
    eq(value("hud.cooldown_anchor"), 2)
    eq(value("hud.anchor_damping_ms"), 80)
end
for _, invalid in ipairs({ 0, 4, 1.5 }) do
    eq(pcall(set, "hud.heat_display", invalid), false)
    eq(writes, before_heat + 4, "invalid heat mode cannot save")
end
eq(handle.available(key("hud.heat_bar_vertical")), true)
eq(set("hud.heat_bar_vertical", true), true)
eq(set("hud.heat_display", 1), true)
eq(handle.available(key("hud.heat_bar_vertical")), false)
eq(value("hud.heat_bar_vertical"), true, "percentage mode retains the selected orientation")
eq(set("hud.heat_display", 3), true)
eq(handle.available(key("hud.heat_bar_vertical")), true)
local after_heat = writes
eq(value("weapon.heat_limiter"), false)
eq(handle.available(key("weapon.heat_limiter")), false, "withheld bridge is disabled in the live menu")
eq(set("weapon.heat_limiter", true), false)
eq(value("weapon.heat_limiter"), false)
eq(writes, after_heat, "Withheld native protection cannot be enabled or saved by the menu")
local after_limiter = writes
eq(set("weapon.heat_limiter", 1), false)
eq(writes, after_limiter, "invalid limiter type cannot save")
after_heat = writes
local loaded = Store.new(project, globals, {
    read = function()
        return text
    end,
    read_legacy = function()
        error("Owned reload must not import original settings")
    end,
    write_atomic = function()
        error("Reload must not write")
    end,
})
eq(loaded:get("hud.cooldown_anchor"), 2, "actual MCM saved choice survives Store reload")
eq(loaded:get("hud.anchor_damping_ms"), 80, "actual MCM damping survives Store reload")
eq(loaded:get("hud.density"), 2)
eq(loaded:get("hud.heat_display"), 3, "actual MCM heat choice survives Store reload")
eq(loaded:get("hud.heat_bar_vertical"), true, "actual MCM orientation survives Store reload")
eq(loaded:get("weapon.heat_limiter"), false, "actual MCM limiter choice survives Store reload")
eq(loaded:close(), true)
eq(pcall(set, "hud.cooldown_anchor", 3), false, "actual MCM rejects invalid choice before save")
eq(writes, after_heat, "out-of-range MCM choice cannot save")
eq(handle.reset(key("hud.cooldown_anchor")), true)
eq(value("hud.cooldown_anchor"), 1)
eq(store:get("hud.cooldown_anchor"), 1)
eq(value("hud.density"), 2)

-- Refusal and foreign ownership must retain the exact cleanup handle.
local unregister = handle.unregister
handle.unregister = function()
    return false, "MCM cleanup pending"
end
okay, why = menu:close()
eq(okay, false)
eq(why, "MCM cleanup pending")
eq(menu.handle, handle)
eq(api.mods.dbf_modular, owner)
handle.unregister = unregister
local foreign = {}
api.mods.dbf_modular = foreign
eq(menu:close(), false)
eq(menu.handle, handle)
eq(api.mods.dbf_modular, foreign)
api.mods.dbf_modular = owner
eq(menu:close(), true)
eq(api.mods.dbf_modular, nil)
eq(menu:close(), true)
eq(menu:update(), false)
eq(store:close(), true)

-- An unfamiliar existing owner is never adopted, overwritten or unregistered.
local other = MCM.new(nil, function() end)
other.mods.dbf_modular = foreign
local fresh = Menu.new(store, function()
    return other
end)
eq(fresh:update(), false)
eq(other.mods.dbf_modular, foreign)
eq(fresh.handle, nil)
print("settings MCM: " .. checks .. " checks; real91-row owner, atomic transactions, conditions, precision and cleanup")
