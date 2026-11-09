-- Retained DBF screen GUI, independent of native crosshair widget extents.
-- prepare(model) validates world and binds the original dock font atlas.
-- measure(font,text,size) -> retained {left,bottom,right,top,width,height}.
-- render(model,view,layout) -> true,{weapon_options=false,cooldowns=false};
-- false,reason on failure. This additive HUD never claims Original DBF views.
local Pool = mod.require("render/pool.lua")
local Style = mod.require("ui/style.lua")
local Renderer = {}
Renderer.__index = Renderer
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function hex(value)
    return type(value) == "string" and #value == 16 and value:match("^%x+$") ~= nil
end
local function signature(font)
    if type(font) == "table" and hex(font.font) and hex(font.atlas) and hex(font.material) then
        return font.font .. font.atlas .. font.material
    end
end
function Renderer.new(deps)
    deps = deps or {}
    return setmetatable({
        globals = deps.globals or _G,
        report = deps.report or function() end,
        before_change = deps.before_change,
        owner = {},
        entries = {},
        measurements = {},
        measurement_count = 0,
        claims = { weapon_options = false, cooldowns = false },
        stats = { creates = 0, measures = 0 },
    }, Renderer)
end
function Renderer:viewport()
    local sr = rawget(self.globals, "stingray")
    if not sr or not sr.Gui or type(sr.Gui.resolution) ~= "function" then
        return nil, "viewport unavailable"
    end
    local okay, width, height = pcall(sr.Gui.resolution)
    if not okay or not finite(width) or not finite(height) or width <= 0 or height <= 0 then
        return nil, "viewport unavailable"
    end
    self.viewport_record = self.viewport_record or {}
    self.viewport_record.width, self.viewport_record.height = width, height
    return self.viewport_record
end
-- Native cooldown icons depend on this GUI's exported labels. Their original
-- presenter must acknowledge restoration before destructive GUI changes.
function Renderer:guard_change()
    if not self.before_change then
        return true
    end
    local called, accepted, why = pcall(self.before_change)
    if not called or accepted ~= true then
        return false, tostring(called and why or accepted)
    end
    return true
end
function Renderer:hide()
    local allowed, reason = self:guard_change()
    if not allowed then
        return false, reason
    end
    self.claims.weapon_options, self.claims.cooldowns = false, false
    if self.lease then
        return self.lease:hide()
    end
    if self.pool then
        return self.pool:release_owner(self.owner)
    end
    return true
end
function Renderer:prepare(model)
    self.ready = false
    local sr = rawget(self.globals, "stingray")
    local next_font = model and signature(model.font)
    if
        not sr
        or not sr.Gui
        or not sr.World
        or not sr.Application
        or not model
        or model.world == nil
        or not next_font
    then
        local hidden, why = self:hide()
        return false, hidden and "GUI/font unavailable" or why
    end
    if
        self.sr ~= sr
        or self.world ~= model.world
        or self.identity ~= model.identity
        or self.generation ~= model.generation
    then
        local closed, why = self:close()
        if not closed then
            return false, why
        end
        self.sr, self.world, self.identity, self.generation = sr, model.world, model.identity, model.generation
        self.pool = Pool.new(sr, self.globals)
    end
    if not self.lease then
        local lease, why = self.pool:acquire(model.world, self.owner)
        if not lease then
            return false, why
        end
        self.lease = lease
    end
    local valid, why = self.lease:valid()
    if not valid then
        return false, why
    end
    if self.font_signature ~= next_font then
        local hidden, hide_reason = self:hide()
        if not hidden then
            return false, hide_reason
        end
        local font, G, I = model.font, sr.Gui, sr.IdString64
        local okay, problem = pcall(function()
            assert(I and type(I.from_hex) == "function" and sr.Material, "Native font service unavailable")
            local found, material = pcall(G.material, self.lease.gui, I.from_hex(font.material))
            if not found or not material then
                material = G.create_material(self.lease.gui, I.from_hex(font.material))
            end
            assert(material, "Native font material unavailable")
            assert(
                sr.Material.set_texture(material, I.from_hex("88BAC99B00000000"), I.from_hex(font.atlas)) ~= false,
                "Native font atlas refused"
            )
        end)
        if not okay then
            return false, tostring(problem)
        end
        self.font_signature = next_font
        self.font = { font = font.font, atlas = font.atlas, material = font.material }
        self.measurements, self.measurement_count = {}, 0
        for _, entry in pairs(self.entries) do
            entry.signature = nil
        end
    end
    self.ready = true
    return true
end
local function component(sr, value, axis)
    if sr.Vector2 and type(sr.Vector2[axis]) == "function" then
        local okay, number = pcall(sr.Vector2[axis], value)
        if okay and finite(number) then
            return number
        end
    end
    if sr.Vector3 and type(sr.Vector3[axis]) == "function" then
        local okay, number = pcall(sr.Vector3[axis], value)
        if okay and finite(number) then
            return number
        end
    end
end
function Renderer:measure(font, text, size)
    if
        not self.ready
        or not self.lease
        or signature(font) ~= self.font_signature
        or type(text) ~= "string"
        or not finite(size)
        or size <= 0
    then
        return nil, "Native text measurement unavailable"
    end
    local key = tostring(size) .. ":" .. text
    local known = self.measurements[key]
    if known then
        return known
    end
    local sr, G = self.sr, self.sr.Gui
    local okay, minimum, maximum = pcall(G.text_extents, self.lease.gui, text, sr.IdString64.from_hex(font.font), size)
    if not okay then
        return nil, tostring(minimum)
    end
    local left, bottom, right, top =
        component(sr, minimum, "x"),
        component(sr, minimum, "y"),
        component(sr, maximum, "x"),
        component(sr, maximum, "y")
    if not left or not bottom or not right or not top or right < left or top < bottom then
        return nil, "Invalid native text extents"
    end
    known = { left = left, bottom = bottom, right = right, top = top, width = right - left, height = top - bottom }
    if self.measurement_count >= 256 then
        self.measurements, self.measurement_count = {}, 0
    end
    self.measurements[key], self.measurement_count = known, self.measurement_count + 1
    self.stats.measures = self.stats.measures + 1
    return known
end
local function mixed_channel(base, danger, mix)
    return math.floor(base + (danger - base) * mix + 0.5)
end
local function color(sr, tone, alpha, danger_mix)
    local token = assert(Style.tokens.colors[tone], "Unknown DBF HUD colour token")
    local danger, mix = Style.tokens.colors.danger, danger_mix or 0
    return sr.Color(
        math.floor((token[4] + (danger[4] - token[4]) * mix) * alpha + 0.5),
        mixed_channel(token[1], danger[1], mix),
        mixed_channel(token[2], danger[2], mix),
        mixed_channel(token[3], danger[3], mix)
    )
end
local function same(entry, primitive, font)
    return entry
        and entry.font == font
        and entry.kind == primitive.kind
        and entry.x == primitive.x
        and entry.y == primitive.y
        and entry.z == primitive.z
        and entry.width == primitive.width
        and entry.height == primitive.height
        and entry.text == primitive.text
        and entry.size == primitive.size
        and entry.tone == primitive.tone
        and entry.alpha == primitive.alpha
        and entry.danger_mix == primitive.danger_mix
end
local function render_primitives(self, layout)
    local sr, lease, font = self.sr, self.lease, self.font
    for _, entry in pairs(self.entries) do
        entry.used = false
    end
    for _, primitive in ipairs(layout.primitives) do
        assert(
            type(primitive.key) == "string" and (primitive.kind == "text" or primitive.kind == "rect"),
            "Invalid Bracket primitive"
        )
        assert(
            finite(primitive.x)
                and finite(primitive.y)
                and finite(primitive.z)
                and finite(primitive.alpha)
                and primitive.alpha >= 0
                and primitive.alpha <= 1,
            "Invalid Bracket geometry"
        )
        local entry = self.entries[primitive.key]
        assert(
            primitive.danger_mix == nil
                or finite(primitive.danger_mix) and primitive.danger_mix >= 0 and primitive.danger_mix <= 1,
            "Invalid Bracket danger mix"
        )
        if not same(entry, primitive, self.font_signature) then
            local update = entry
                and entry.kind == primitive.kind
                and type(sr.Gui["update_" .. primitive.kind]) == "function"
            if entry and not update then
                assert(lease:remove(primitive.key))
                self.entries[primitive.key] = nil
            end
            local position = sr.Vector3(primitive.x, primitive.y, primitive.z)
            if primitive.kind == "text" then
                assert(
                    type(primitive.text) == "string" and finite(primitive.size) and primitive.size > 0,
                    "Invalid Bracket text"
                )
                if update then
                    lease:update(
                        primitive.key,
                        "text",
                        primitive.text,
                        sr.IdString64.from_hex(font.font),
                        primitive.size,
                        sr.IdString64.from_hex(font.material),
                        position,
                        color(sr, primitive.tone, primitive.alpha, primitive.danger_mix)
                    )
                else
                    lease:add(
                        primitive.key,
                        "text",
                        primitive.text,
                        sr.IdString64.from_hex(font.font),
                        primitive.size,
                        sr.IdString64.from_hex(font.material),
                        position,
                        color(sr, primitive.tone, primitive.alpha, primitive.danger_mix)
                    )
                end
            else
                assert(
                    finite(primitive.width)
                        and finite(primitive.height)
                        and primitive.width >= 0
                        and primitive.height >= 0,
                    "Invalid Bracket rectangle"
                )
                if update then
                    lease:update(
                        primitive.key,
                        "rect",
                        position,
                        sr.Vector2(primitive.width, primitive.height),
                        color(sr, primitive.tone, primitive.alpha, primitive.danger_mix)
                    )
                else
                    lease:add(
                        primitive.key,
                        "rect",
                        position,
                        sr.Vector2(primitive.width, primitive.height),
                        color(sr, primitive.tone, primitive.alpha, primitive.danger_mix)
                    )
                end
            end
            entry = entry or {}
            for key, value in pairs(primitive) do
                entry[key] = value
            end
            entry.danger_mix = primitive.danger_mix
            entry.font = self.font_signature
            self.entries[primitive.key] = entry
            if not update then
                self.stats.creates = self.stats.creates + 1
            end
        end
        entry.used = true
    end
    for key, entry in pairs(self.entries) do
        if not entry.used then
            assert(lease:remove(key))
            self.entries[key] = nil
        end
    end
    assert(lease:show())
end
function Renderer:dependent_changes(layout)
    local destructive = false
    for key, entry in pairs(self.entries) do
        if key:sub(1, 9) == "cooldown/" then
            entry.dependency_used = false
        end
    end
    for _, primitive in ipairs(layout.primitives or {}) do
        if primitive.key:sub(1, 9) == "cooldown/" then
            local entry = self.entries[primitive.key]
            if
                not same(entry, primitive, self.font_signature)
                and (
                    not entry
                    or entry.kind ~= primitive.kind
                    or entry.font ~= self.font_signature
                    or type(self.sr.Gui["update_" .. primitive.kind]) ~= "function"
                )
            then
                destructive = true
            end
            if entry then
                entry.dependency_used = true
            end
        end
    end
    for key, entry in pairs(self.entries) do
        if key:sub(1, 9) == "cooldown/" and not entry.dependency_used then
            destructive = true
        end
    end
    return destructive
end
function Renderer:render(model, view, layout)
    self.claims.weapon_options, self.claims.cooldowns = false, false
    if not view or view.visible ~= true or not layout or layout.valid ~= true or layout.visible ~= true then
        local hidden, why = self:hide()
        return hidden, hidden and self.claims or why
    end
    local ready, why = self:prepare(model)
    if not ready then
        return false, why
    end
    -- Preflight the complete dependent set before any setters. Retained updates
    -- keep the same GUI/font/IDs, so model motion needs no Original GUI roundtrip.
    -- Removal/recreation still restores natives before changing their dependency.
    if self:dependent_changes(layout) then
        local allowed, reason = self:guard_change()
        if not allowed then
            return false, reason
        end
    end
    local okay, problem = pcall(render_primitives, self, layout)
    if not okay then
        local hidden, hide_reason = self:hide()
        return false, tostring(problem) .. (hidden and "" or "; " .. tostring(hide_reason))
    end
    return true, self.claims
end
function Renderer:close()
    local allowed, reason = self:guard_change()
    if not allowed then
        return false, reason
    end
    self.ready = false
    self.claims.weapon_options, self.claims.cooldowns = false, false
    local okay, why = true, nil
    if self.lease then
        okay, why = self.lease:release()
    elseif self.pool then
        okay, why = self.pool:release_owner(self.owner)
    end
    if not okay then
        return false, why
    end
    self.lease, self.pool, self.world, self.identity, self.sr, self.font, self.font_signature, self.generation =
        nil, nil, nil, nil, nil, nil, nil, nil
    self.entries, self.measurements, self.measurement_count = {}, {}, 0
    return true
end
return Renderer
