-- Actual original icon presenter; synthetic native widget functions touch only owned Lua storage.
local ffi = require("ffi")
if not pcall(ffi.typeof, "NSR_vec2") then
    ffi.cdef("typedef struct { float x,y; } NSR_vec2;")
end
local Support = assert(loadfile("tests/support.lua"))()
local checks = 0
local function eq(a, b, why)
    checks = checks + 1
    assert(a == b, (why or "different") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, why)
    checks = checks + 1
    assert(math.abs(a - b) < 0.000001, (why or "different") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function fixture()
    local context, globals = Support.project()
    local Strip = context.require("src/weapon_status_strip.lua")
    local f = {
        root = 0x10000000,
        context = 0x60000000,
        calls = 0,
        sets = 0,
        panel_releases = 0,
        panel_acquires = 0,
        nodes = {},
        links = {},
        contexts = {},
        alphas = {},
        panels = {},
    }
    local container = f.root + 0x820
    local weapon = f.root + 0x251468
    local box = f.root + 0x251000
    local frame = f.root + 0x1000
    f.links[weapon] = box
    f.links[box] = frame
    f.links[frame] = container
    for _, at in ipairs({ container, weapon, box, frame }) do
        f.contexts[at] = f.context
    end
    f.transforms = {
        [container] = { 1920, 1080, 2, 0, 0, 2, 0, 0 },
        [weapon] = { 64, 64, 2, 0, 0, 2, 2700, 100 },
        [box] = { 300, 100, 2, 0, 0, 2, 2600, 80 },
        [frame] = { 300, 100, 2, 0, 0, 2, 2600, 80 },
    }
    local function node(at)
        f.nodes[at] = f.nodes[at] or {}
        return f.nodes[at]
    end
    local b = { base = 0x40000000 }
    function b.valid(identity)
        return identity == f.root and not f.retired
    end
    function b.pointer(at)
        if at == b.base + 0x2e28788 then
            return f.root
        end
        for p, value in pairs(f.links) do
            if at == p + 0xf0 then
                return value
            end
        end
        for p, value in pairs(f.contexts) do
            if at == p + 0xf8 then
                return value
            end
        end
    end
    function b.read_u32(at)
        return f.transforms[at] and 1
    end
    function b.read(at, size)
        local t = f.transforms[at]
        assert(t and size == 0xb0, "unexpected native read")
        local values = ffi.new("float[44]")
        values[9] = t[1]
        values[10] = t[2]
        values[21] = f.alphas[at] or 1
        for i, lane in ipairs({ 0, 2, 8, 10, 12, 14 }) do
            values[25 + lane] = t[i + 2]
        end
        return ffi.string(values, size)
    end
    function b.set(at, key, value)
        f.sets = f.sets + 1
        node(at)[key] = { value[1], value[2] }
    end
    function b.widgets_ready()
        return not f.cold
    end
    function b.callable()
        return not f.cold
    end
    function b.release_owned_ui(storage, at, identity, parent)
        if f.refuse_native then
            return false, "native release refused"
        end
        if f.links[at] ~= nil and not b.valid(identity) then
            return false, "old root linked"
        end
        f.links[at] = nil
        return true
    end
    function b.fn(_, offset)
        return function(at, a, c)
            f.calls = f.calls + 1
            if offset == 0x12de550 or offset == 0x12d67c0 then
                f.contexts[at] = f.active_context or f.context
                node(at)
                if offset == 0x12de550 then
                    f.address = at
                end
            elseif offset == 0x12e42d0 then
                f.links[a] = at
            elseif offset == 0x12e7510 then
                node(at).asset = tostring(a)
            elseif offset == 0x12e07e0 then
                node(at).opacity = a
            elseif offset == 0x12e4cc0 then
                node(at).shown = a
            elseif offset == 0x12d6c00 then
                node(at).uv = { a.x, a.y, c.x, c.y }
            end
        end
    end
    local scope = {
        context_ready = function()
            return not f.cold
        end,
    }
    function scope.context_scope(_, fn)
        if f.switch_at_scope then
            f.context = f.context + 0x100
            f.contexts[container] = f.context
        end
        f.active_context = f.context
        return fn(f.context)
    end
    context.scope.cooldown_gui_pool = function()
        return {
            acquire = function()
                f.panel_acquires = f.panel_acquires + 1
                local api = {
                    rect = function(_, position, size, color)
                        f.panels[#f.panels + 1] = { position = position, size = size, color = color }
                        return 1
                    end,
                    destroy_rect = function() end,
                }
                return {
                    gui = {},
                    api = api,
                    valid = function()
                        return true
                    end,
                    show = function() end,
                    release = function()
                        f.panel_releases = f.panel_releases + 1
                        if f.throw_panel then
                            error("panel release throw")
                        end
                        if f.refuse_panel then
                            return false, "panel release refused"
                        end
                        return true
                    end,
                }
            end,
        }
    end
    globals.stingray = {
        Application = {
            main_world = function()
                return "main"
            end,
            worlds = function()
                return { "main", "ui" }
            end,
        },
        Gui = {},
        Vector3 = function(...)
            return { ... }
        end,
        Vector2 = function(...)
            return { ... }
        end,
        Color = function(...)
            return { ... }
        end,
    }
    local model = {
        fire_mode = "AUTO",
        rpm = 750,
        rpm_index = 1,
        ammo_mode = "FLAK",
        zoom = 2,
        zoom_index = 0,
        changeable = { fire_mode = true, rpm = true, ammo_mode = true, zoom = true },
    }
    local renderer = Strip.new(b, scope)
    local spec =
        { x = 2000, y = 1000, edge = 44, gap = 10, opacity = 0.94, root = f.root, generation = 1, source_revision = 1 }
    f.renderer, f.model, f.spec, f.container, f.module = renderer, model, spec, container, Strip
    f.weapon = weapon
    f.context_host, f.backend, f.scope = context, b, scope
    f.colors = context.require("ui/style.lua").tokens.colors
    return f
end
local f = fixture()
local metrics = f.module.metrics(f.model, 44, 10)
eq(metrics.ready, true)
eq(metrics.count, 4)
eq(metrics.width, 206)
eq(metrics.height, 44)
eq(f.module.metrics(nil, 44, 10), nil)
eq(f.module.metrics(f.model, 0, 10), nil)
eq(f.module.metrics(f.model, 44, -1), nil)
local empty = f.module.metrics({ changeable = {} }, 44, 10)
eq(empty.count, 0)
eq(empty.width, 0)
eq(empty.height, 0)
eq(f.renderer.draw(f.root, f.model, nil, f.spec), true)
eq(f.panel_acquires, 0, "Bracket mode creates no backing GUI")
local p = f.address + 0x110
eq(f.nodes[p].position[1], 1000)
eq(f.nodes[p].position[2], 500)
eq(f.nodes[p].size[1], 22)
eq(f.nodes[p].size[2], 22)
eq(f.nodes[p + 0x160].position[1], 1027)
eq(f.nodes[f.address].opacity, 0.94)
eq(f.nodes[p].opacity, 0.92)
eq(#f.renderer.icons, 4)
for i, item in ipairs(f.renderer.icons) do
    local at = p + (i - 1) * 0x160
    eq(f.nodes[at].shown, 1)
    eq(f.nodes[at].asset:sub(-3), "ULL")
    eq(f.nodes[at].uv[1] > 0.14 and f.nodes[at].uv[1] < 0.16, true)
end
local calls, sets = f.calls, f.sets
eq(f.renderer.draw(f.root, f.model, nil, f.spec), true)
eq(f.calls, calls, "unchanged frame reuses native widget setters")
eq(f.sets, sets)
f.spec.generation = 2
eq(f.renderer.draw(f.root, f.model, nil, f.spec), true)
eq(f.calls > calls, true, "generation changes invalidate presentation cache")
f.transforms[f.container][7] = 100
f.transforms[f.container][8] = 200
eq(f.renderer.draw(f.root, f.model, nil, f.spec), true)
eq(f.nodes[p].position[1], 950)
eq(f.nodes[p].position[2], 400)
f.transforms[f.container][3] = 4
f.transforms[f.container][6] = 4
eq(f.renderer.draw(f.root, f.model, nil, f.spec), true)
eq(f.nodes[p].size[1], 11)
eq(f.nodes[p].position[1], 475)
f.transforms[f.container][6] = 2
calls = f.calls
eq(f.renderer.draw(f.root, f.model, nil, f.spec), false)
eq(f.calls, calls, "unequal-axis placement refuses before native setters")
f.transforms[f.container][3] = 2
f.transforms[f.container][6] = 2
f.transforms[f.container][1] = 2560
f.transforms[f.container][2] = 1440
eq(f.renderer.draw(f.root, f.model, nil, f.spec), true)
eq(f.nodes[f.address].size[1], 2560)
eq(f.nodes[f.address].size[2], 1440)
f.spec.root = f.root + 1
eq(f.renderer.draw(f.root, f.model, nil, f.spec), false)
f.spec.root = f.root
-- Standalone legacy row returns immediately with its original backing.
eq(f.renderer.draw(f.root, f.model), true)
eq(f.panel_acquires, 1)
eq(f.nodes[f.address].opacity, 1)
f.refuse_panel = true
calls = f.calls
eq(f.renderer.draw(f.root, f.model, nil, f.spec), false)
eq(f.calls, calls)
eq(f.renderer.close(), false, "backing release refusal is retained")
local retries = f.panel_releases
f.refuse_panel = false
eq(f.renderer.draw(f.root, f.model, nil, f.spec), true)
eq(f.panel_releases, retries + 1)
f.refuse_native = true
eq(f.renderer.close(), false)
local address = f.address
f.refuse_native = false
eq(f.renderer.close(), true)
eq(f.links[address], nil)
-- Fresh resource-context change cannot pass cached-frame checks or release old links.
f = fixture()
eq(f.renderer.draw(f.root, f.model, nil, f.spec), true)
calls = f.calls
f.contexts[f.container] = f.context + 0x100
eq(f.renderer.draw(f.root, f.model, nil, f.spec), false)
eq(f.calls, calls)
eq(f.renderer.hide(), false)
eq(f.renderer.close(), false)
f.contexts[f.container] = f.context
eq(f.renderer.close(), true)
f = fixture()
f.switch_at_scope = true
local called = pcall(f.renderer.draw, f.root, f.model, nil, f.spec)
eq(called, false)
eq(f.calls, 0, "context switched after geometry refuses before initializers")
f = fixture()
eq(f.renderer.draw(f.root, f.model), true)
f.throw_panel = true
eq(f.renderer.close(), false, "throwing GUI release retains its lease")
f.throw_panel = false
eq(f.renderer.close(), true)
-- Native layout matches the weapon's inherited fade, while Bracket retains its own opacity.
f = fixture()
f.alphas[f.weapon] = 0.7
eq(f.renderer.draw(f.root, f.model), true)
near(f.nodes[f.address].opacity, 0.7, "native weapon fade replaces the old full-opacity root")
local native_icon = f.address + 0x110
eq(f.nodes[native_icon].opacity, 1, "no extra .92 dimming in native layout")
eq(#f.panels, 2, "one backing and one seam, with no separately faded frost layer")
eq(f.panels[1].color[1], math.floor(f.colors.hud_plate[4] * 0.7), "backing inherits the weapon fade once")
eq(f.panels[2].color[1], math.floor(f.colors.line_strong[4] * 0.7), "seam shares that native fade")
for channel = 1, 3 do
    eq(f.panels[1].color[channel + 1], f.colors.hud_plate[channel], "backing uses shared colour tokens")
end
calls, sets = f.calls, f.sets
eq(f.renderer.draw(f.root, f.model), true)
eq(f.calls, calls, "stable inherited alpha reuses the native widgets")
eq(f.sets, sets)
f.alphas[f.weapon] = 0.4
eq(f.renderer.draw(f.root, f.model), true)
near(f.nodes[f.address].opacity, 0.4, "alpha-only changes invalidate the draw key")
eq(f.calls > calls, true)
eq(#f.panels, 4, "alpha-only changes refresh the independent screen backing")
eq(f.panels[3].color[1], math.floor(f.colors.hud_plate[4] * 0.4))
eq(f.renderer.draw(f.root, f.model, nil, f.spec), true)
near(f.nodes[f.address].opacity, 0.94, "Bracket opacity stays controlled by its placement")
near(f.nodes[native_icon].opacity, 0.92, "Bracket icon appearance stays unchanged")
eq(f.panel_acquires, 1, "Bracket releases the existing backing without creating one")
eq(f.renderer.close(), true)
-- The owned root already inherits the native container; do not apply its fade twice.
f = fixture()
f.alphas[f.container], f.alphas[f.weapon] = 0.5, 0.35
eq(f.renderer.draw(f.root, f.model), true)
near(f.nodes[f.address].opacity, 0.7, "only the missing weapon-relative alpha is applied")
near(f.nodes[f.address].opacity * 0.5, 0.35, "effective icon alpha matches native weapon")
eq(f.panels[1].color[1], math.floor(f.colors.hud_plate[4] * 0.35), "screen backing uses inherited alpha, not sibling-relative alpha")
f.alphas[f.container], f.alphas[f.weapon] = 0, 0
eq(f.renderer.draw(f.root, f.model), true)
eq(f.nodes[f.address].opacity, 0, "fully hidden ancestry avoids division by zero")
f.alphas[f.container], f.alphas[f.weapon] = 1, 0.7
eq(f.renderer.draw(f.root, f.model), true)
near(f.nodes[f.address].opacity, 0.7, "native fade recovers when the container returns")
eq(f.renderer.close(), true)
-- Invalid native alpha never reaches native setters or creates a backing.
f = fixture()
f.alphas[f.weapon] = 1.2
eq(pcall(f.renderer.draw, f.root, f.model), false)
eq(f.calls, 0)
eq(f.panel_acquires, 0)
-- Real status wrapper keeps the original10Hz reader and only changes placement.
f = fixture()
local context = f.context_host
local require_module = context.require
local polls = 0
context.require = function(path, ...)
    if path == "src/weapon_status_memory.lua" then
        return {
            native = function()
                return { close = function() end }
            end,
        }
    end
    if path == "src/weapon_status_reader.lua" then
        return {
            new = function()
                return {
                    poll = function()
                        polls = polls + 1
                        return f.model
                    end,
                }
            end,
        }
    end
    return require_module(path, ...)
end
local Status = context.require("src/weapon_status.lua")
local status = Status.new({
    native_backend = function()
        return f.backend
    end,
    duplicate_cards = function()
        return f.scope
    end,
})
status.update(0.2)
eq(polls, 1)
local metric = status.metrics(44, 10)
eq(metric.count, 4)
eq(metric.root, f.root)
eq(metric.source_revision, 1)
f.spec.source_revision = metric.source_revision
eq(status.place(f.spec), true)
local places = f.calls
status.update(0.2)
eq(polls, 2, "placement does not create or pause another reader")
eq(f.calls, places, "ordinary new option sample defers old placement revision")
eq(status.place(f.spec), false, "external stale measurement is rejected")
metric = status.metrics(44, 10)
eq(metric.source_revision, 2)
f.spec.source_revision = metric.source_revision
eq(status.place(f.spec), true)
status.update(0.2)
eq(polls, 3, "ordinary poll deferral never adds a1second backoff")
metric = status.metrics(44, 10)
f.spec.source_revision = metric.source_revision
eq(status.place(f.spec), true)
eq(status.place(nil), true, "standalone fallback is immediate without a new reader")
eq(polls, 3)
local previous = f.panel_acquires
eq(previous >= 2, true, "legacy backing returns only on standalone fallback")
f.refuse_panel = true
eq(status.place(f.spec), false, "wrapper propagates backing refusal")
eq(status.close(), false, "wrapper retains renderer when cleanup refuses")
f.refuse_panel = false
eq(status.close(), true)
print("original weapon placement: " .. checks .. " checks passed")
