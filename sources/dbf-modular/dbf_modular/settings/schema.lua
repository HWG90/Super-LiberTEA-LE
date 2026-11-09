-- Original DBF domains plus Quiet Bracket preferences. No inherited HUD catalog.
-- HUD scale/opacity getters are percentages; offsets are 1080p pixels, positive Y down.
local FirstPersonBones = mod.require("sampling/first_person_bones.lua")
local Schema = {
    version = 1,
    definitions = {},
    by_id = {},
    aliases = {},
    dbf_keys = {},
    exclusions = {},
    origins = {},
    categories = {},
    pages = {},
}
local PREFIX = "native_stratagem_radial."
local groups = {}
local function group(id, name, keys)
    Schema.categories[#Schema.categories + 1] = { id = id, name = name, collapsed = id == "exclusions" }
    if id ~= "exclusions" then
        Schema.pages[#Schema.pages + 1] = { id = id, name = name, category = id }
    end
    for _, key in ipairs(keys or {}) do
        groups[key] = id
    end
end
group("hud", "Combat HUD")
group("placement", "Position and ADS")
group("tfp", "First-person anchors")
group("selection", "Selection", { "enabled", "selection_mode_ordered", "selection_sounds", "release_selection_mode" })
group("wheel", "Wheel appearance", {
    "experimental_layout",
    "appearance_preset",
    "wheel_size",
    "icon_size",
    "label_size",
    "native_opacity",
    "wedge_darkness",
    "wedge_opacity",
    "vertical_offset",
})
group("list", "List filtering", { "dim_unselected", "hide_blacklisted_list", "hide_cooldown_list" })
group("weapon", "Weapon controls")
group("cooldowns", "Cooldown display", {
    "hide_closed_status",
    "dock_gap",
    "cooldown_icons",
    "cooldown_display",
    "short_status_placement",
    "track_unavailable",
    "balance_separated_dock",
})
group("timers", "Cooldown timers", { "cooldown_timers", "cooldown_timer", "short_timer_style", "brief_timer_limit" })
group(
    "input",
    "Input and terminals",
    { "input_interval_ms", "randomize_input_delay", "instant_stratagems", "auto_terminal_complete", "terminal_input" }
)
group("exclusions", "Mission exclusions")
local function add(spec)
    assert(not Schema.by_id[spec.id], "Duplicate setting: " .. spec.id)
    Schema.by_id[spec.id] = spec
    Schema.definitions[#Schema.definitions + 1] = spec
end
local original = {
    {
        id = "native_stratagem_radial.enabled",
        type = "toggle",
        label = "Selection / Enable Mod",
        default = true,
        description = "Enable Mod",
    },
    {
        id = "native_stratagem_radial.selection_mode_ordered",
        type = "choice",
        label = "Appearance / Mode",
        default = 1,
        description = "Mode",
        choices = { "Wedge Wheel", "List Select", "Native wheel" },
    },
    {
        id = "native_stratagem_radial.selection_sounds",
        type = "toggle",
        label = "Selection / Sound feedback",
        default = true,
        description = "Sound feedback",
    },
    {
        id = "native_stratagem_radial.experimental_layout",
        type = "choice",
        label = "Appearance / Wedge Wheel layout",
        default = 2,
        description = "Available while Wedge Wheel is selected.",
        choices = { "Cards - copied list rows", "Expanded wedges" },
    },
    {
        id = "native_stratagem_radial.appearance_preset",
        type = "choice",
        label = "Appearance / Preset",
        default = 1,
        description = "Custom uses the size sliders below. Other presets override sizes; opacity and colors stay independent.",
        choices = { "Custom", "Compact", "Standard", "Large" },
    },
    {
        id = "native_stratagem_radial.wheel_size",
        type = "slider",
        label = "Appearance / Wheel size (%)",
        default = 100,
        description = "All radial layouts. Custom preset only.",
        min = 70,
        max = 130,
        step = 5,
    },
    {
        id = "native_stratagem_radial.icon_size",
        type = "slider",
        label = "Appearance / Icon size (%)",
        default = 100,
        description = "Native and expanded wheels. Relative to wheel size; Custom preset only.",
        min = 70,
        max = 130,
        step = 5,
    },
    {
        id = "native_stratagem_radial.label_size",
        type = "slider",
        label = "Appearance / Center label size (%)",
        default = 100,
        description = "Native and expanded wheels. Relative to wheel size; Custom preset only.",
        min = 70,
        max = 130,
        step = 5,
    },
    {
        id = "native_stratagem_radial.native_opacity",
        type = "slider",
        label = "Appearance / Native wheel opacity (%)",
        default = 100,
        description = "Native wheel only; background opacity. Selected highlight stays visible.",
        min = 0,
        max = 100,
        step = 5,
    },
    {
        id = "native_stratagem_radial.wedge_darkness",
        type = "slider",
        label = "Appearance / Expanded wedge darkness (%)",
        default = 70,
        description = "Expanded wedges only.",
        min = 0,
        max = 100,
        step = 5,
    },
    {
        id = "native_stratagem_radial.wedge_opacity",
        type = "slider",
        label = "Appearance / Wedge opacity (%)",
        default = 50,
        description = "Expanded wedges only; selected highlight stays visible.",
        min = 0,
        max = 100,
        step = 5,
    },
    {
        id = "native_stratagem_radial.cooldown_timers",
        type = "toggle",
        label = "Appearance / Show cooldown timers",
        default = true,
        description = "Show native remaining time on dock icons, using the game font.",
    },
    {
        id = "native_stratagem_radial.cooldown_timer",
        type = "choice",
        label = "Appearance / Cooldown timer position",
        default = 2,
        description = "Position of regular cooldown timers. Short countdown style controls inbound, impact and brief cooldowns separately.",
        choices = { "Off", "Above icon", "Below icon", "Inside icon" },
    },
    {
        id = "native_stratagem_radial.short_timer_style",
        type = "choice",
        label = "Appearance / Short countdown style",
        default = 2,
        description = "Separate style for inbound, impact and brief cooldown countdowns.",
        choices = { "Use cooldown position", "Large inside icon" },
    },
    {
        id = "native_stratagem_radial.dim_unselected",
        type = "toggle",
        label = "Appearance / Dim unselected stratagems",
        default = true,
        description = "Dim unselected available entries in List Select. Native cooldown styling stays unchanged.",
    },
    {
        id = "native_stratagem_radial.hide_blacklisted_list",
        type = "toggle",
        label = "Appearance / Hide blacklisted stratagems",
        default = false,
        description = "Hide blacklisted entries in List Select. Off keeps them visible but unselectable. Wheels always omit them.",
    },
    {
        id = "native_stratagem_radial.hide_cooldown_list",
        type = "toggle",
        label = "Appearance / Hide stratagems on cooldown",
        default = false,
        description = "Hide cooldown entries in List Select. Inbound entries remain visible. Does not affect the cooldown dock or overview.",
    },
    {
        id = "native_stratagem_radial.brief_timer_limit",
        type = "slider",
        label = "Appearance / Brief cooldown threshold",
        default = 10,
        description = "Cooldowns at or below this many seconds use the short countdown style.",
        min = 1,
        max = 30,
        step = 1,
    },
    {
        id = "native_stratagem_radial.hide_closed_status",
        type = "toggle",
        label = "Appearance / Hide top-left status notices",
        default = true,
        description = "Hide native inbound, impact and cooldown notices while the stratagem menu is closed. The open list stays complete.",
    },
    {
        id = "native_stratagem_radial.dock_gap",
        type = "slider",
        label = "Appearance / Cooldown spacing",
        default = 24,
        description = "Spacing below Bracket combat instruments when integrated; gap above the native stamina bar in the original viewport layout. Existing values and range are preserved.",
        min = 0,
        max = 80,
        step = 2,
    },
    {
        id = "native_stratagem_radial.cooldown_icons",
        type = "toggle",
        label = "Appearance / Show cooldown display",
        default = true,
        description = "Show the chosen dock or overview. Off hides the display and stops its timer checks.",
    },
    {
        id = "native_stratagem_radial.cooldown_display",
        type = "choice",
        label = "Appearance / Cooldown display style",
        default = 1,
        description = "Compact overview: a vertical list of icons, status and native remaining times. Compact row: small icons in one line under the health bar, incoming on the right after a separator.",
        choices = { "Icon dock", "Compact overview", "Compact row" },
    },
    {
        id = "native_stratagem_radial.short_status_placement",
        type = "choice",
        label = "Appearance / Short status placement",
        default = 3,
        description = "Dock only. Separate inbound, impact, brief and per-charge cooldowns from longer cooldowns. Left/right adds a divider; below uses the stamina bar as the divider.",
        choices = { "Together", "Left of dock", "Right of dock", "Below stamina bar" },
    },
    {
        id = "native_stratagem_radial.track_unavailable",
        type = "toggle",
        label = "Appearance / Track unavailable / ineligible",
        default = false,
        description = "Include native unavailable or ineligible stratagems in the cooldown display. No countdown is invented when the game supplies none.",
    },
    {
        id = "native_stratagem_radial.balance_separated_dock",
        type = "toggle",
        label = "Appearance / Center Cooldown Separator",
        default = true,
        description = "Center the entire left/right separated bar. Off keeps the main cooldown group centered instead.",
    },
    {
        id = "native_stratagem_radial.release_selection_mode",
        type = "choice",
        label = "Controller / Select on Release",
        default = 1,
        description = "Automatic enables release selection for active controller input. On also enables mouse. Requires a Hold menu binding; center before releasing to cancel.",
        choices = { "Automatic (controller)", "On", "Off" },
    },
    {
        id = "native_stratagem_radial.input_interval_ms",
        type = "slider",
        label = "Advanced / Input interval (ms)",
        default = 70,
        description = "Delay between directions, for stratagem codes and entered terminal arrows. 0 sends one per frame; applies to the next code.",
        min = 0,
        max = 250,
        step = 5,
    },
    {
        id = "native_stratagem_radial.randomize_input_delay",
        type = "toggle",
        label = "Advanced / Randomize input delay",
        default = false,
        description = "Choose one delay between 70 and 240 ms for each stratagem use or terminal code. Overrides the fixed delay.",
    },
    {
        id = "native_stratagem_radial.instant_stratagems",
        type = "toggle",
        label = "Advanced / Instant complete Stratagems",
        default = false,
        description = "Enter the whole code in one frame through the native input handler. Overrides the input interval and random delay.",
    },
    {
        id = "native_stratagem_radial.auto_terminal_complete",
        type = "toggle",
        label = "Terminals / Auto Terminal Complete",
        default = true,
        description = "Complete arrow-code terminals as soon as they accept input.",
    },
    {
        id = "native_stratagem_radial.terminal_input",
        type = "choice",
        label = "Terminals / Terminal input",
        default = 1,
        description = "Instant completes the code at once as host. Enter arrows presses each arrow at the input interval. As a client, Instant presses arrows as fast as the terminal takes them.",
        choices = { "Instant", "Enter arrows" },
    },
    {
        id = "native_stratagem_radial.vertical_offset",
        type = "slider",
        label = "Appearance / Radial vertical offset (down)",
        default = 0,
        description = "Radial layouts: positive moves down. Leave at 0 for automatic centering.",
        min = -600,
        max = 600,
        step = 25,
    },
}

for _, spec in ipairs(original) do
    local key = spec.id:sub(#PREFIX + 1)
    Schema.dbf_keys[#Schema.dbf_keys + 1] = key
    spec.category = assert(groups[key], "Unclassified original setting: " .. key)
    spec.page = spec.category
    spec.label = spec.label:match(" / (.*)$") or spec.label
    if key == "enabled" then
        spec.label = "Selection controls"
    end
    add(spec)
    Schema.origins[#Schema.origins + 1] = { id = spec.id, source = "general" }
end
add({
    id = "weapon.heat_limiter",
    type = "toggle",
    default = false,
    label = "Heat limiter",
    category = "weapon",
    page = "weapon",
    description = "Unavailable in this build while the firing bridge crash is investigated.",
})
local exclusion_groups = {
    { id = "general", name = "General", rows = { { 51, "Eagle Rearm" }, { 149, "SOS Beacon" } } },
    {
        id = "support",
        name = "Support and extraction",
        rows = {
            { 5, "ORBITAL ILLUMINATION FLARE" },
            { 7, "EXTRACTION BEACON" },
            { 29, "SEAF Artillery" },
            { 34, "Resupply" },
            { 43, "HELLBOMB" },
            { 101, "EMERGENCY EXTRACTION BEACON" },
            { 106, "Carpet Bombing Run" },
            { 111, "Scrambler" },
            { 114, "IMMEDIATE EXTRACTION BEACON" },
            { 126, "CALL IN DESTROYER" },
            { 127, "Reinforce" },
            { 135, "Nuke" },
            { 152, "EXTRACTION" },
        },
    },
    {
        id = "devices",
        name = "Mission devices",
        rows = {
            { 17, "BUG THUMPER" },
            { 19, "SEISMIC PROBE" },
            { 37, "OIL RIG EXTRACT" },
            { 67, "TCS 03 THUMPER" },
            { 73, "PROSPECTING DRILL" },
            { 75, "BUG PLUG" },
            { 87, "JAMMED PINATA" },
            { 89, "REMOTE EXPLOSIVES" },
            { 97, "POISON DRILL" },
            { 125, "SPIRE STERILIZER" },
            { 132, "DRILLING CHARGE" },
        },
    },
    {
        id = "objectives",
        name = "Cargo and objectives",
        rows = {
            { 11, "RAISE FLAG" },
            { 30, "DARK FLUID BACKPACK" },
            { 49, "DATA JACK" },
            { 74, "CARGO CONTAINER" },
            { 79, "Cyborg Carry Data" },
            { 81, "SHOULDER MOUNTED CAMERA" },
            { 82, "Carry Data" },
            { 88, "RAISE FLAG NO CLEAR AREA" },
            { 105, "MOBILE COMMS RELAY" },
            { 131, "Upload Discovery" },
            { 141, "CARGO CONTAINER" },
        },
    },
}
for _, page in ipairs(exclusion_groups) do
    local page_id = "exclusions_" .. page.id
    Schema.pages[#Schema.pages + 1] = { id = page_id, name = page.name, category = "exclusions" }
    for _, row in ipairs(page.rows) do
        local id = "kind_" .. row[1]
        add({
            id = id,
            type = "toggle",
            default = false,
            label = row[2],
            category = "exclusions",
            page = page_id,
            description = "Prevents selecting this mission-provided stratagem in List and hides it on wheels. Equipped stratagems and unreadable mission data remain protected.",
        })
        Schema.exclusions[#Schema.exclusions + 1] = { kind = row[1], id = id, label = row[2] }
        Schema.origins[#Schema.origins + 1] = { id = id, source = "exclusion", kind = row[1] }
        Schema.aliases[PREFIX .. "mission_kind_" .. row[1]] = id
    end
end
Schema.aliases[PREFIX .. "hide_sos"] = "kind_149"
Schema.aliases[PREFIX .. "hide_eagle_rearm"] = "kind_51"
local hud = {
    {
        id = "hud.enabled",
        type = "toggle",
        default = true,
        label = "Combat HUD",
        category = "hud",
        description = "Show the Quiet Bracket combat instruments. Original DBF selection and terminal controls stay independent.",
    },
    {
        id = "hud.density",
        type = "choice",
        default = 1,
        label = "Information density",
        category = "hud",
        choices = { "Quiet", "Detailed" },
        description = "Quiet keeps supporting facts contextual and minimizes routine details while aiming. Detailed keeps useful known weapon, player and supply information visible.",
    },
    {
        id = "hud.ads_minimal",
        type = "toggle",
        default = true,
        label = "Minimize Quiet while aiming",
        category = "hud",
        description = "Quiet aiming keeps ammo or heat, reload warnings and urgent health/no-stim cues. Hide routine options, cooldowns and supporting details. Inspection and Detailed reveal them.",
    },
    {
        id = "hud.heat_display",
        type = "choice",
        default = 1,
        label = "Heat display",
        category = "hud",
        choices = { "Percentage", "Bar", "Hybrid" },
        description = "Show validated accumulated heat as a percentage, a compact HEAT bar, or both. Zero is cold and a full bar is maximum heat. Unknown heat remains hidden.",
    },
    {
        id = "hud.anchor",
        type = "choice",
        default = 1,
        label = "Anchor",
        category = "placement",
        choices = { "Player and weapon", "Reticle", "Beside reticle" },
        description = "Player and weapon follows validated animated bones. Hip ammo follows the player head; aiming follows the gun. First-person places health left and ammo right of the sights, automatically clearing current weapon and optic bounds. Cooldown placement selects their group.",
    },
    {
        id = "hud.tfp_vitals_bone",
        type = "choice",
        default = 1,
        label = "First-person health anchor",
        category = "tfp",
        choices = FirstPersonBones.choices,
        description = "True First Person only. Choose an FPS rig bone or a Weapon: node on the equipped gun. Health, stamina and supplies follow that point. Unavailable or off-screen points use the current screen fallback.",
    },
    {
        id = "hud.tfp_vitals_offset_x",
        type = "slider",
        default = 0,
        min = -600,
        max = 600,
        step = 5,
        fine_step = 1,
        label = "Health X offset",
        category = "tfp",
        description = "True First Person only. 1080p pixels; Positive moves right. Moves health, stamina, supplies and their attached cooldowns relative to the selected bone. In Above health mode, the ammo stack follows this movement.",
    },
    {
        id = "hud.tfp_vitals_offset_y",
        type = "slider",
        default = 0,
        min = -600,
        max = 600,
        step = 5,
        fine_step = 1,
        label = "Health Y offset",
        category = "tfp",
        description = "True First Person only. 1080p pixels; Positive moves down. Moves health, stamina, supplies and their attached cooldowns relative to the selected bone. In Above health mode, the ammo stack follows this movement.",
    },
    {
        id = "hud.tfp_ammo_bone",
        type = "choice",
        default = 1,
        label = "First-person ammo anchor",
        category = "tfp",
        choices = FirstPersonBones.choices,
        description = "True First Person only. Choose an FPS rig bone or a Weapon: node for ammo, heat and weapon controls. Weapon nodes depend on the equipped gun; unavailable or off-screen points use the current screen fallback. Above health follows the health anchor instead.",
    },
    {
        id = "hud.tfp_ammo_offset_x",
        type = "slider",
        default = 0,
        min = -600,
        max = 600,
        step = 5,
        fine_step = 1,
        label = "Ammo X offset",
        category = "tfp",
        description = "True First Person only. 1080p pixels; Positive moves right. Moves ammo, heat and weapon controls relative to their selected anchor. In Above health mode, adjusts ammo relative to health; downward movement stops before touching health.",
    },
    {
        id = "hud.tfp_ammo_offset_y",
        type = "slider",
        default = 0,
        min = -600,
        max = 600,
        step = 5,
        fine_step = 1,
        label = "Ammo Y offset",
        category = "tfp",
        description = "True First Person only. 1080p pixels; Positive moves down. Moves ammo, heat and weapon controls relative to their selected anchor. In Above health mode, adjusts ammo relative to health; downward movement stops before touching health.",
    },
    {
        id = "hud.tfp_ammo_placement",
        type = "choice",
        default = 1,
        label = "First-person ammo placement",
        category = "tfp",
        choices = { "Right of anchor", "Above health" },
        description = "True First Person only. Place ammo beside the selected weapon anchor, or stack the complete ammo and controls group above health.",
    },
    {
        id = "hud.heat_bar_vertical",
        type = "toggle",
        default = false,
        label = "Vertical heat bar",
        category = "hud",
        description = "Use an upright bottom-to-top heat bar in Bar or Hybrid mode. Percentage mode stays unchanged.",
    },
    {
        id = "hud.cooldown_anchor",
        type = "choice",
        default = 1,
        label = "Cooldown placement",
        category = "placement",
        choices = { "Under health", "Under ammo" },
        description = "Place the existing cooldown display under the health group or the ammo group. Original cooldown styles and timer choices stay in effect.",
    },
    {
        id = "hud.anchor_damping_ms",
        type = "slider",
        default = 80,
        min = 0,
        max = 300,
        step = 10,
        fine_step = 1,
        label = "Anchor damping (ms)",
        category = "placement",
        description = "Smooth animated anchor movement and hip-to-aim transitions. Zero follows immediately. Changing player, weapon or camera resets the blend.",
    },
    {
        id = "hud.scale",
        type = "slider",
        default = 100,
        min = 80,
        max = 125,
        step = 5,
        fine_step = 1,
        label = "HUD scale (%)",
        category = "placement",
        description = "100 is the saved 1080p Bracket size. Resolution scaling is automatic.",
    },
    {
        id = "hud.opacity",
        type = "slider",
        default = 94,
        min = 60,
        max = 100,
        step = 1,
        label = "HUD opacity (%)",
        category = "placement",
        description = "Opacity of the owned Bracket instruments. Vanilla HUD remains visible in this preview.",
    },
    {
        id = "hud.offset_x",
        type = "slider",
        default = 0,
        min = -600,
        max = 600,
        step = 5,
        fine_step = 1,
        label = "Horizontal position",
        category = "placement",
        description = "1080p pixels relative to the selected anchor. Positive moves right.",
    },
    {
        id = "hud.offset_y",
        type = "slider",
        default = 0,
        min = -600,
        max = 600,
        step = 5,
        fine_step = 1,
        label = "Vertical position (down)",
        category = "placement",
        description = "1080p pixels relative to the selected anchor. Positive moves down.",
    },
    {
        id = "hud.ads_offset_x",
        type = "slider",
        default = 0,
        min = -600,
        max = 600,
        step = 5,
        fine_step = 1,
        label = "Aim horizontal offset",
        category = "placement",
        description = "Additional 1080p pixels while aiming or in first-person. Positive moves right.",
    },
    {
        id = "hud.ads_offset_y",
        type = "slider",
        default = 0,
        min = -600,
        max = 600,
        step = 5,
        fine_step = 1,
        label = "Aim vertical offset (down)",
        category = "placement",
        description = "Additional 1080p pixels while aiming or in first-person. Positive moves down.",
    },
}
for _, spec in ipairs(hud) do
    spec.page = spec.category
    add(spec)
end
-- Old saved/console spelling remains an alias; it creates no second menu row.
Schema.aliases["hud.ads_expand"] = "hud.ads_minimal"
function Schema.resolve(id)
    if Schema.by_id[id] then
        return id
    end
    return Schema.aliases[id]
end
function Schema.validate(id, value)
    local spec = Schema.by_id[id]
    if not spec then
        return nil
    end
    if spec.type == "toggle" then
        if type(value) == "boolean" then
            return value
        end
    elseif type(value) == "number" and value == value and math.abs(value) < math.huge then
        if spec.type == "choice" then
            if value % 1 == 0 and value >= 1 and value <= #spec.choices then
                return value
            end
        elseif value >= spec.min and value <= spec.max then
            return value
        end
    end
end
function Schema.defaults()
    local out = {}
    for _, spec in ipairs(Schema.definitions) do
        out[spec.id] = spec.default
    end
    return out
end
function Schema.enabled(id, get)
    if id == "weapon.heat_limiter" then
        return false
    end
    local key = id:match("^native_stratagem_radial%.(.+)$")
    local function value(name)
        return get(PREFIX .. name)
    end
    if id:match("^hud%.") and id ~= "hud.enabled" then
        if id == "hud.tfp_ammo_bone" then
            return get("hud.enabled") == true and get("hud.tfp_ammo_placement") ~= 2
        end
        if id == "hud.heat_bar_vertical" then
            local display = get("hud.heat_display")
            return get("hud.enabled") == true and (display == 2 or display == 3)
        end
        return get("hud.enabled") == true
    end
    if not key then
        return true
    end
    local mode = value("selection_mode_ordered")
    local expanded = mode == 1 and value("experimental_layout") == 2
    local custom = value("appearance_preset") == 1
    local display = value("cooldown_icons") == true
    local dock = display and value("cooldown_display") == 1
    local timers = display and value("cooldown_timers") == true
    if key == "experimental_layout" then
        return mode == 1
    end
    if key == "wedge_darkness" or key == "wedge_opacity" then
        return expanded
    end
    if key == "native_opacity" then
        return mode == 3
    end
    if key == "wheel_size" then
        return mode ~= 2 and custom
    end
    if key == "icon_size" or key == "label_size" then
        return (expanded or mode == 3) and custom
    end
    if key == "vertical_offset" then
        return mode ~= 2
    end
    if key == "dim_unselected" or key == "hide_blacklisted_list" or key == "hide_cooldown_list" then
        return mode == 2
    end
    local paced = value("instant_stratagems") ~= true
        or value("auto_terminal_complete") == true and value("terminal_input") == 2
    if key == "input_interval_ms" then
        return value("randomize_input_delay") ~= true and paced
    end
    if key == "randomize_input_delay" then
        return paced
    end
    if key == "terminal_input" then
        return value("auto_terminal_complete") == true
    end
    if
        key == "cooldown_display"
        or key == "dock_gap"
        or key == "track_unavailable"
        or key == "cooldown_timers"
        or key == "brief_timer_limit"
    then
        return display
    end
    if key == "short_status_placement" then
        return dock
    end
    if key == "balance_separated_dock" then
        local p = value("short_status_placement")
        return dock and (p == 2 or p == 3)
    end
    if key == "cooldown_timer" or key == "short_timer_style" then
        return timers
    end
    return true
end
return Schema
