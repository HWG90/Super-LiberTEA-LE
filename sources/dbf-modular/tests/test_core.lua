-- Execute real Core, Entry, settings, selection/release and weapon orchestration.
-- Only process-memory/native-widget producers and terminal transport are fake.
local checks = 0
local function eq(a, b, why)
    checks = checks + 1
    assert(a == b, (why or "different") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local Core = assert(loadfile("dbf_modular/core/dbf.lua"))()
local function fixture(limiter_factory)
    local f = {
        now = 1000,
        factories = 0,
        snapshots = 0,
        polls = 0,
        terminal = 0,
        draws = 0,
        closes = 0,
        events = {},
        root = 90000,
    }
    local globals = setmetatable({ Fixture = f }, { __index = _G })
    globals.io = {
        open = function()
            error("Core must not read legacy settings")
        end,
    }
    globals.ModOptionsMenu = {
        get = function()
            error("Foreign options owner must not be used")
        end,
    }
    globals.DBFMCM = {
        api = 1,
        mods = {},
        register = function()
            error("Core must not register another MCM row")
        end,
    }
    globals.CowboyBingusModLoader = {
        open_log = function()
            return { write = function() end, close = function() end }
        end,
    }
    globals.ModBindingsMenu = {
        api = 1,
        version = 2,
        register_binding = function()
            return true
        end,
        is_down = function()
            return false
        end,
    }
    local foreign_update = function()
        error("Core must not invoke a loader/global callback")
    end
    globals.update = foreign_update
    local values, callbacks = {}, {}
    local facade = { api = 1, version = 1, unified = true }
    function facade.register_option(id, spec)
        if values[id] == nil then
            values[id] = spec.default
        end
        return true
    end
    function facade.get(id)
        return values[id]
    end
    function facade.on_change(id, fn)
        callbacks[id] = fn
        return true
    end
    function facade.set(id, value)
        values[id] = value
        if callbacks[id] then
            callbacks[id](value)
        end
        return true
    end
    f.facade, f.values = facade, values
    local settings = {
        dbf_options = function()
            return facade
        end,
        get = function(_, id)
            if id == "weapon.heat_limiter" then
                return false
            end
        end,
    }
    local function view()
        return {
            count = 0,
            status = "native-view",
            restore = function() end,
            hide = function() end,
            close = function()
                return true
            end,
            step = function() end,
            prepare = function(s)
                return s
            end,
            draw = function() end,
            timer = function() end,
            caption = function() end,
        }
    end
    f.radial = { controller = view, list_controller = view }
    f.view = view
    f.backend = {
        base = 100000,
        milliseconds = function()
            return f.now
        end,
        focused = function()
            return true
        end,
        deferred = function()
            return {}
        end,
        valid = function(root)
            return root == f.root
        end,
        widgets_ready = function()
            return false
        end,
        pointer = function(at)
            if at == 100000 + 0x2e28788 then
                return f.root
            end
        end,
        read = function()
            return nil
        end,
        u32 = function()
            return 0
        end,
        snapshot = function(closed)
            f.snapshots = f.snapshots + 1
            f.events[#f.events + 1] = "entry"
            if f.unknown then
                return nil
            end
            return { identity = f.root, open = f.open == true, hud_visible = true, rows = {}, dock_rows = closed }
        end,
    }
    f.model = {
        id = 42,
        unit_ref = 77,
        avatar_unit_ref = 88,
        resource_hex = "0123456789abcdef",
        rpm = 750,
        rpm_index = 1,
        fire_mode = "AUTO",
        zoom = 2,
        zoom_index = 0,
        changeable = { rpm = true, fire_mode = true, zoom = true, ammo_mode = false },
        binding = {
            module_base = 100000,
            record = 200000,
            avatar_id = 3,
            avatar_record = 300000,
            candidate = 123,
            avatar_candidate = 456,
            driver_state = "diagnostic-only",
        },
    }
    local sources = {
        ["src/layout.lua"] = "return {radial=Fixture.radial}",
        ["src/native.lua"] = "return {native_backend=function() Fixture.factories=Fixture.factories+1;return Fixture.backend end}",
        ["src/input.lua"] = [[return {input_backend=function() return {
            decorate=function(s)if s then s.decorated=true end end,mission_blacklist_kinds=function()return {}end}end}]],
        ["src/camera.lua"] = "return {camera_capture=function()return {release=function()end,capture=function()end}end}",
        ["src/duplicate.lua"] = "return {duplicate_cards=Fixture.view}",
        ["src/emote.lua"] = "return {emote_wheel=Fixture.view}",
        ["src/expanded.lua"] = "return {expanded_wheel=Fixture.view}",
        ["src/pointing.lua"] = "return {native_pointing=function()return {reset=function()end}end}",
        ["src/cooldown_dock.lua"] = [[return {cooldown_dock=function()return {
            hide=function()Fixture.dock_visible=false end,sample=function()Fixture.dock_samples=(Fixture.dock_samples or 0)+1 end,
            draw=function(_,shown)if Fixture.visibility_refuse then return false,'visibility retained'end;Fixture.dock_visible=shown;Fixture.dock_draws=(Fixture.dock_draws or 0)+1 end,
            bracket_layout=function(_,o)Fixture.layout_enabled=o.enabled;return {valid=true,identity=o.identity,generation=o.generation,has_content=true}end,
            draw_bracket=function(_,packet)Fixture.bracket_draws=(Fixture.bracket_draws or 0)+1;return not Fixture.spatial_refuse,'spatial refused'end,
            clear_bracket=function()Fixture.original_restores=(Fixture.original_restores or 0)+1;return not Fixture.restore_refuse,'restore refused'end,
            close=function()return true end}end,
            cooldown_closed_notices=function()return {step=function()end,restore=function()end}end}]],
        ["src/weapon_status_memory.lua"] = [[return {native=function()return {
            close=function()Fixture.memory_closed=(Fixture.memory_closed or 0)+1 end}end}]],
        ["src/weapon_status_reader.lua"] = [[return {new=function()return {status='unknown',poll=function()
            Fixture.polls=Fixture.polls+1;Fixture.events[#Fixture.events+1]='weapon';return Fixture.model end}end}]],
        ["src/weapon_status_strip.lua"] = [[return {icons=function()return {{},{},{}}end,metrics=function(_,edge,gap,out)out.ready=true;out.count=3;out.width=3*edge+2*gap;out.height=edge;out.edge=edge;out.gap=gap;return out end,new=function()return {status='native-strip',
            draw=function()Fixture.draws=Fixture.draws+1;Fixture.strip_visible=true end,
            hide=function()Fixture.strip_visible=false end,
            close=function()Fixture.closes=Fixture.closes+1;if Fixture.refuse then return false,'strip still owned'end;return true end}end}]],
        ["src/terminal.lua"] = [[return {new=function(factories)return {update=function()
            factories.native_backend();Fixture.terminal=Fixture.terminal+1;Fixture.events[#Fixture.events+1]='terminal' end}end}]],
    }
    local context, cache = { config = { preferences = {} } }, {}
    function context.read(path)
        if sources[path] then
            return sources[path]
        end
        local file = assert(io.open("dbf_modular/" .. path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end
    local host = setmetatable({ mod = context, _G = globals }, { __index = globals })
    function context.require(path)
        if cache[path] then
            return cache[path]
        end
        local chunk = assert(loadstring(context.read(path), "@" .. path))
        setfenv(chunk, host)
        cache[path] = chunk()
        return cache[path]
    end
    local core = Core.new(context, { settings = settings, globals = globals, heat_limiter_factory = limiter_factory })
    return core, f, globals, foreign_update
end
local core, f, globals, foreign_update = fixture()
eq(core:services().backend, nil)
eq(core:enable(), true)
eq(globals.update, foreign_update, "one descriptor: the global update hook is unchanged")
eq(globals.DiversBestFriend, core.api)
eq(globals.NativeStratagemRadial, core.api)
eq(core:services().backend, nil, "getter observes live state, not startup nil exports")
core:update(0.2)
eq(f.factories, 1, "all original consumers share the successful native factory")
eq(core:services().backend, f.backend)
eq(core:services().snapshot.decorated, true)
eq(core:services().cooldowns.decorated, true)
local events = table.concat(f.events, ",")
eq(events:match("weapon,terminal$") ~= nil, true, "original Entry -> weapon -> terminal order")
eq(f.strip_visible, true)
eq(f.dock_visible, true)
eq(core:services().weapon.rpm, 750)
eq(core:services().weapon.changeable.zoom, true)
eq(core:services().weapon.binding.avatar_id, 3)
eq(core:services().weapon.binding.record, 200000)
eq(core:services().weapon.binding.candidate, nil, "unverified candidate is not a native handle")
eq(core:services().weapon.binding.driver_state, nil)
local function driver_flags(value)
    return string.char(value % 256, math.floor(value / 256) % 256, 0, 0) .. string.rep("\0", 36)
end
for _, case in ipairs({
    { 0x80, "magazine" },
    { 0x100, "rounds" },
    { 0x200, "heat" },
    { 0x2242, "heat" },
    { 0x40, nil },
    { 0x280, "magazine" },
}) do
    f.model.binding.driver_state = driver_flags(case[1])
    f.now = f.now + 200
    core:update(0.2)
    eq(core:services().weapon.ammo_kind, case[2], "safe DTO keeps original native driver discriminator")
    eq(core:services().weapon.binding.driver_state, nil, "raw native driver bytes stay private")
end
eq(globals.DBFMenuSubscriptions, nil, "private Store does not use the legacy subscription broker")
local polls = f.polls
eq(core:set_presentation({ weapon_options = false, cooldowns = false }), true)
eq(f.strip_visible, false)
eq(f.dock_visible, false)
f.now = f.now + 200
core:update(0.2)
eq(f.polls, polls + 1, "presentation gates never stop the original reader")
eq(f.strip_visible, false)
eq(core:set_presentation({}), true)
eq(f.strip_visible, true, "the original view is immediate fallback")
f.visibility_refuse = true
eq(core:set_presentation({ weapon_options = false, cooldowns = false }), false)
eq(core.presentation_pending.cooldowns, true, "hide refusal remains pending")
local held_polls = f.polls
f.now = f.now + 200
core:update(0.2)
eq(f.polls, held_polls + 1, "visibility refusal never stalls input/data engine")
eq(
    core:set_presentation({ weapon_options = false, cooldowns = false }),
    false,
    "unchanged policy retries refused owner"
)
f.visibility_refuse = false
eq(core:set_presentation({ weapon_options = false, cooldowns = false }), true)
eq(core.presentation_pending.cooldowns, false)
eq(f.dock_visible, false)
eq(core:set_presentation({}), true)
eq(f.dock_visible, true, "revealing original cooldowns is immediate")
local snapshot_count = f.snapshots
core:services()
core:services()
eq(f.snapshots, snapshot_count, "services never polls native state")
-- Real Core/Entry defer only legacy drawing, never the existing collector.
local metric = core:weapon_metrics(22, 5)
eq(metric.ready, true)
eq(metric.count, 3)
local packet = core:cooldown_layout({ identity = f.root, generation = 2 })
eq(packet.valid, true)
eq(f.layout_enabled, true)
eq(core:set_layout(nil, packet, { x = 960, y = 540 }, 0.94), true)
eq(core.layout_request.cooldowns, true)
local samples, draws = f.dock_samples, f.dock_draws
f.now = f.now + 200
core:update(0.2)
eq(f.dock_samples, samples + 1, "placement preserves original sampling")
eq(f.dock_draws, draws, "active spatial lease defers only legacy presenter draw")
eq(core:clear_layout(), true)
eq(core.layout_request, nil)
f.now = f.now + 200
core:update(0.2)
eq(f.dock_draws, draws + 1, "original viewport path resumes after clear")
-- Failed restoration retains Core's request marker for safe retry.
eq(core:set_layout(nil, packet, { x = 960, y = 540 }, 0.94), true)
f.spatial_refuse, f.restore_refuse = true, true
local owned_request = core.layout_request
eq(core:set_layout(nil, packet, { x = 900, y = 530 }, 0.94), false)
eq(core.layout_request, owned_request)
eq(core.layout_request.restore_pending, true)
local attempted = f.bracket_draws
eq(core:set_layout(nil, packet, { x = 900, y = 530 }, 0.94), false)
eq(f.bracket_draws, attempted, "restore refusal fences new placement writes")
eq(core:clear_layout(), false)
eq(core.layout_request, owned_request)
f.restore_refuse = false
eq(core:clear_layout(), true)
eq(core.layout_request, nil)
f.spatial_refuse = false
f.unknown = true
f.now = f.now + 200
core:update(0.2)
eq(core:services().snapshot, nil)
f.unknown = false
f.refuse = true
local scope = core.scope
eq(core:close(), false)
eq(core.scope, scope, "cleanup refusal retains the private/native owners")
eq(globals.DiversBestFriend, core.api)
polls = f.polls
core:update(0.5)
eq(f.polls, polls, "teardown never resumes native work")
f.refuse, f.open = false, true
eq(core:close(), false, "original open-menu cleanup refusal survives composition")
eq(core.scope, scope)
f.open = false
eq(core:close(), true)
eq(core:close(), true)
eq(globals.DiversBestFriend, nil)
eq(globals.NativeStratagemRadial, nil)
eq(core.scope, nil)
eq(core:set_presentation({}), false)
local next_core = fixture()
eq(next_core:enable(), true, "fresh component creates a fresh private factory scope")
eq(next_core:close(), true)
-- The new native generation retires BEFORE any original component. A refusal
-- must keep the shared backend and source scope available for a later retry.
local limiter = { pending = true, updates = 0, closes = 0 }
function limiter:snapshot()
    return self
end
function limiter:update(services)
    self.updates = self.updates + 1
    self.observed = services.weapon
end
function limiter:close()
    self.closes = self.closes + 1
    return not self.pending, self.pending and "native callbacks still owned" or nil
end
local gated, gf, gg = fixture(function()
    return limiter
end)
eq(gated:enable(), true)
gated:update(0.1)
eq(limiter.updates, 1)
eq(limiter.observed, gated:services().weapon, "limiter uses the original weapon service")
local retained_scope, old_closes = gated.scope, gf.closes
eq(gated:close(), false, "native cancellation needs a positive acknowledgement")
eq(gf.closes, old_closes, "a limiter refusal fences original presenter retirement")
eq(gated.scope, retained_scope)
eq(gg.DiversBestFriend, gated.api)
gated:update(0.1)
eq(limiter.updates, 1, "a retiring Core never rearms the native generation")
limiter.pending = false
eq(gated:close(), true)
eq(limiter.closes, 2)
eq(gated.heat_limiter, nil)
eq(gg.DiversBestFriend, nil)
print("original Core: " .. checks .. " checks passed")
