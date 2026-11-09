-- Design illustration generated from the ACTUAL Policy/Layout/Anchor modules.
-- Font metrics are a monospace approximation; native Sinclair is tested in-game.
local context = assert(loadfile("tests/support.lua"))().project()
local Policy = context.require("hud/policy.lua")
local Layout = context.require("hud/bracket_layout.lua")
local Anchor = context.require("hud/anchor.lua")
local Style = context.require("ui/style.lua")
local Schema = context.require("settings/schema.lua")
local values = {}
for _, row in ipairs(Schema.definitions) do
    values[row.id] = row.default
end
local settings = {
    get = function(_, id)
        return values[id]
    end,
}
local output = {}
local function emit(s)
    output[#output + 1] = s
end
local function escape(s)
    return tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end
local function color(name)
    local c = assert(Style.tokens.colors[name])
    return string.format("#%02x%02x%02x", c[1], c[2], c[3]), c[4] / 255
end
local function measure(_, text, size)
    return { left = 0, bottom = -size * 0.18, right = #text * size * 0.58, top = size * 0.82 }
end
local function label(x, y, text, size, tone)
    emit(
        string.format(
            '<text x="%g" y="%g" font-size="%g" fill="%s">%s</text>',
            x,
            y,
            size,
            color(tone or "text_dim"),
            escape(text)
        )
    )
end
emit(
    '<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="440" viewBox="0 0 1280 440"><g font-family="monospace">'
)
emit(string.format('<rect width="1280" height="440" fill="%s"/>', color("panel_alt")))
label(32, 36, "DBF MODULAR / QUIET BRACKET", 20, "yellow")
label(32, 62, "Actual policy and geometry. Illustrated font metrics; in-game appearance pending.", 12)
for index, aim in ipairs({ false, true }) do
    local x = (index - 1) * 624 + 24
    emit(
        string.format(
            '<rect x="%d" y="88" width="608" height="306" rx="10" fill="%s" stroke="%s"/>',
            x,
            color("panel"),
            color("line")
        )
    )
    label(x + 24, 120, aim and "ADS / EXPANDED DETAILS" or "HIPFIRE / CONTEXTUAL", 14, "text")
    local model = {
        known = true,
        identity = 1,
        generation = 1,
        time = 0,
        in_mission = true,
        alive = true,
        hud_visible = true,
        menu_open = false,
        blocked = false,
        aim = { known = true, first_person = false, aiming = aim, switching = false },
        reticle = { known = true, x = 960, y = 540 },
        anchors = {},
        health = 0.72,
        stamina = 0.64,
        stims = 3,
        throwables = 4,
        weapon = {
            known = true,
            count = 17,
            reserve = 5,
            reloading = false,
            fire_mode = "AUTO",
            rpm = 750,
            rpm_index = 1,
            changeable = { fire_mode = true, rpm = true, ammo_mode = false, zoom = false },
        },
        font = {},
    }
    local view = Policy.new():update(model, settings, 0.016, false)
    local layout = Layout.new()
    local viewport = { width = 1920, height = 1080 }
    layout:update(view, settings, viewport, nil, measure)
    local anchor = assert(Anchor.resolve(model, settings, viewport, layout.bounds))
    layout:update(view, settings, viewport, anchor, measure)
    assert(layout.valid)
    local cx, cy = x + 270, 208
    local reticle = color("text_dim")
    emit(
        string.format(
            '<path d="M %g %g h 8 m 8 0 h 8 M %g %g v 8 m 0 8 v 8" fill="none" stroke="%s" opacity=".55"/>',
            cx - 12,
            cy,
            cx,
            cy - 12,
            reticle
        )
    )
    for _, p in ipairs(layout.primitives) do
        local px, py = cx + p.x - anchor.x, cy - (p.y - anchor.y)
        local tone, alpha = color(p.tone)
        if p.kind == "rect" then
            emit(
                string.format(
                    '<rect x="%g" y="%g" width="%g" height="%g" fill="%s" opacity="%g"/>',
                    px,
                    py - p.height,
                    p.width,
                    p.height,
                    tone,
                    alpha * p.alpha
                )
            )
        else
            emit(
                string.format(
                    '<text x="%g" y="%g" font-size="%g" fill="%s" opacity="%g">%s</text>',
                    px,
                    py,
                    p.size,
                    tone,
                    alpha * p.alpha,
                    escape(p.text)
                )
            )
        end
    end
end
label(32, 422, "Vanilla HUD remains visible in the candidate. Bracket adds no selection or wheel input owner.", 12)
emit("</g></svg>")
local file = assert(io.open(arg[1] or "design/bracket-implementation.svg", "wb"))
assert(file:write(table.concat(output, "\n")))
assert(file:close())
