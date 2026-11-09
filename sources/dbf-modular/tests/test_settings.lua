-- Real original schema/facade contracts and first-import/atomic persistence.
local Support = assert(loadfile("tests/support.lua"))()
local project, globals = Support.project()
local Schema = project.require("settings/schema.lua")
local Store = project.require("settings/store.lua")
local Migrate = project.require("settings/migrate.lua")
local checks, cases = 0, 0
local P = "native_stratagem_radial."
local function eq(actual, expected, why)
    checks = checks + 1
    assert(actual == expected, (why or "different") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function check(value, why)
    eq(not not value, true, why)
end
local function case(name, run)
    local okay, why = pcall(run)
    assert(okay, name .. ": " .. tostring(why))
    cases = cases + 1
end
local function fixture(sources, preferences, environment)
    sources = sources or {}
    local result = { text = sources.owned, writes = 0, reads = {} }
    local context = { require = project.require, config = { preferences = preferences or {} } }
    local storage = {
        read = function()
            return result.text
        end,
        read_legacy = function(name)
            result.reads[#result.reads + 1] = name
            assert(name == "menu" or name == "blacklist", "Foreign settings catalog queried")
            return sources[name]
        end,
        write_atomic = function(text)
            result.writes = result.writes + 1
            if result.before then
                result.before()
            end
            if result.fail == "throw" then
                error("disk raised")
            end
            if result.fail then
                return false, "disk refused"
            end
            result.text = text
            return true
        end,
    }
    result.storage, result.context = storage, context
    result.store = Store.new(context, environment or globals, storage)
    return result
end
local original, original_order = {}, {}
local scope = setmetatable({ mod = { config = { preferences = {} } } }, { __index = _G })
scope._G = scope
local original_chunk = assert(loadfile("reference/original-dbf/src/settings.lua"))
setfenv(original_chunk, scope)
original_chunk().canary_settings({
    get = function() end,
    on_change = function()
        return true
    end,
    register_option = function(id, spec)
        original[id] = spec
        original_order[#original_order + 1] = id
        return true
    end,
}, {}, {}, 0)

case("exact32 original domains and37 original MCM exclusion IDs", function()
    eq(#Schema.dbf_keys, 32)
    eq(#Schema.exclusions, 37)
    eq(#Schema.definitions, 91)
    eq(#Schema.categories, 11)
    local seen, pages, page_counts, hud_count = {}, {}, {}, 0
    for _, page in ipairs(Schema.pages) do
        pages[page.id] = true
    end
    for _, spec in ipairs(Schema.definitions) do
        eq(seen[spec.id], nil, "One public row per fact")
        seen[spec.id] = true
        check(pages[spec.page])
        page_counts[spec.page] = (page_counts[spec.page] or 0) + 1
        if spec.id:match("^hud%.") then
            hud_count = hud_count + 1
        end
        check(Schema.validate(spec.id, spec.default) ~= nil)
        check(not spec.id:find("combat_", 1, true))
    end
    for index, key in ipairs(Schema.dbf_keys) do
        local id = P .. key
        eq(id, original_order[index])
        local expected, actual = original[id], Schema.by_id[id]
        for _, field in ipairs({ "type", "default", "min", "max", "step" }) do
            eq(actual[field], expected[field], id .. "." .. field)
        end
        eq(#(actual.choices or {}), #(expected.choices or {}))
        for n, label in ipairs(expected.choices or {}) do
            eq(actual.choices[n], label)
        end
    end
    local chunk = assert(loadfile("reference/original-dbf/src/mission_blacklist.lua"))
    setfenv(
        chunk,
        setmetatable({
            mod = {
                require = function()
                    return {}
                end,
            },
        }, { __index = _G })
    )
    local names = chunk().mission_blacklist_names
    local count = 0
    for kind, label in pairs(names) do
        count = count + 1
        eq(Schema.by_id["kind_" .. kind].label, label)
        eq(Schema.by_id["kind_" .. kind].default, false)
        eq(Schema.resolve(P .. "mission_kind_" .. kind), "kind_" .. kind)
    end
    eq(count, 37)
    eq(Schema.resolve(P .. "hide_sos"), "kind_149")
    eq(Schema.resolve(P .. "hide_eagle_rearm"), "kind_51")
    eq(Schema.by_id[P .. "mission_kind_5"], nil, "Compatibility aliases are never duplicate public controls")
    eq(Schema.by_id[P .. "input_interval_ms"].min, 0)
    eq(Schema.by_id[P .. "input_interval_ms"].max, 250)
    eq(Schema.by_id["hud.anchor"].default, 1)
    eq(Schema.by_id["hud.ads_minimal"].default, true)
    eq(Schema.by_id["hud.scale"].default, 100)
    eq(Schema.by_id["hud.opacity"].default, 94)
    eq(hud_count, 21)
    local limiter = Schema.by_id["weapon.heat_limiter"]
    eq(limiter.type, "toggle")
    eq(limiter.default, false)
    eq(limiter.category, "weapon")
    eq(limiter.page, "weapon")
    eq(page_counts.weapon, 1)
    eq(
        Schema.enabled(limiter.id, function()
            return false
        end),
        false,
        "Heat bridge is withheld after failed live acceptance"
    )
    local heat = Schema.by_id["hud.heat_display"]
    eq(heat.type, "choice")
    eq(heat.default, 1)
    eq(heat.label, "Heat display")
    eq(heat.category, "hud")
    eq(heat.page, "hud")
    eq(#heat.choices, 3)
    eq(table.concat(heat.choices, ","), "Percentage,Bar,Hybrid")
    local vertical = Schema.by_id["hud.heat_bar_vertical"]
    eq(vertical.type, "toggle")
    eq(vertical.default, false)
    eq(vertical.category, "hud")
    eq(vertical.page, "hud")
    eq(page_counts.placement, 9)
    eq(page_counts.tfp, 7)
    eq(Schema.by_id["hud.cooldown_anchor"].type, "choice")
    eq(Schema.by_id["hud.cooldown_anchor"].label, "Cooldown placement")
    eq(Schema.by_id["hud.cooldown_anchor"].category, "placement")
    eq(Schema.by_id["hud.cooldown_anchor"].page, "placement")
    eq(Schema.by_id["hud.cooldown_anchor"].default, 1)
    eq(#Schema.by_id["hud.cooldown_anchor"].choices, 2)
    eq(Schema.by_id["hud.cooldown_anchor"].choices[1], "Under health")
    eq(Schema.by_id["hud.cooldown_anchor"].choices[2], "Under ammo")
    local damping = Schema.by_id["hud.anchor_damping_ms"]
    eq(damping.type, "slider")
    eq(damping.label, "Anchor damping (ms)")
    eq(damping.category, "placement")
    eq(damping.page, "placement")
    eq(damping.default, 80)
    eq(damping.min, 0)
    eq(damping.max, 300)
    eq(damping.step, 10)
    eq(damping.fine_step, 1)
    eq(#Schema.origins, 69)
end)

case("all original controls import with explicit false/zero and precision", function()
    local lines, expected = {}, {}
    for id, spec in pairs(original) do
        local value = spec.type == "toggle" and not spec.default or spec.type == "choice" and #spec.choices or spec.min
        if spec.type == "toggle" then
            value = not spec.default
        end
        if spec.type == "slider" and spec.max > 100 then
            value = spec.min + 0.12345
        end
        expected[id] = value
        lines[#lines + 1] = id .. "\t" .. tostring(value) .. "\n"
    end
    local blacklist = { "version\t3\n" }
    for _, row in ipairs(Schema.exclusions) do
        blacklist[#blacklist + 1] = row.kind .. "\ttrue\n"
    end
    local f = fixture({ menu = table.concat(lines), blacklist = table.concat(blacklist) })
    eq(f.writes, 0)
    eq(#f.reads, 2)
    for id, value in pairs(expected) do
        eq(f.store:get(id), value)
    end
    for _, row in ipairs(Schema.exclusions) do
        eq(f.store:get(row.id), true)
    end
    eq(f.store:get("hud.density"), 1)
    local store =
        fixture({ menu = P .. "wheel_size\t999\n" .. P .. "input_interval_ms\t0\n" }, { wheel_size = 105 }).store
    eq(store:get(P .. "wheel_size"), 105)
    eq(store:get(P .. "input_interval_ms"), 0)
    eq(Migrate.parse("a=nan\nb=inf\nc=1e999\nd=false\ne=0\n").a, nil)
    eq(Migrate.parse("d=false\ne=0\n").d, false)
    eq(Migrate.parse("e=0\n").e, 0)
end)

case("original blacklist versions and historical controls retain semantics", function()
    local map = { [145] = 149, [49] = 51 }
    for _, text in ipairs({
        "version\t1\n1\t145\n2\t49\n",
        "version\t2\n145\ttrue\n49\ttrue\n",
        "version\t3\n149\ttrue\n51\ttrue\n",
    }) do
        local values = Migrate.run({ blacklist = text }, {}, map)
        eq(values.kind_149, true)
        eq(values.kind_51, true)
        eq(values.kind_5, false)
    end
    local values = Migrate.run(
        { menu = P .. "hide_sos\ttrue\n" .. P .. "hide_eagle_rearm\ttrue\n", blacklist = "version\t3\n" },
        {},
        map
    )
    eq(values.kind_149, false, "Original complete blacklist owns exclusions")
    eq(values.kind_51, false)
    values = Migrate.run(
        { menu = P .. "selection_mode\t4\n" .. P .. "select_on_release\ttrue\n" .. P .. "blacklist_kind_1\t145\n" },
        {},
        map
    )
    eq(values[P .. "selection_mode_ordered"], 1)
    eq(values[P .. "experimental_layout"], 2)
    eq(values[P .. "release_selection_mode"], 2)
    eq(values.kind_149, true)
    values = Migrate.run({ menu = P .. "selection_mode\t1\n" .. P .. "select_on_release\tfalse\n" }, {}, map)
    eq(values[P .. "selection_mode_ordered"], 3)
    eq(values[P .. "release_selection_mode"], 1)
end)

case("one validated atomic batch; refusal does not publish", function()
    local f = fixture({ owned = "private.future=false\nprivate.precision=.38123\n" })
    local store, events = f.store, 0
    local initial = store:get(P .. "enabled")
    store:on_change(P .. "enabled", function(value, id)
        events = events + 1
        eq(value, false)
        eq(id, P .. "enabled")
        eq(store:get("hud.opacity"), 80)
    end)
    f.before = function()
        eq(store:get(P .. "enabled"), initial)
        eq(store.revision, 0)
        eq(events, 0)
    end
    f.fail = true
    local changes = { [P .. "enabled"] = false, ["hud.opacity"] = 80, kind_149 = true }
    eq(store:apply(changes), false)
    eq(f.writes, 1)
    eq(store.revision, 0)
    eq(events, 0)
    eq(store:get("kind_149"), false)
    eq(store:get("hud.opacity"), 94)
    f.fail = "throw"
    eq(store:apply(changes), false)
    eq(store.revision, 0)
    f.fail = false
    check(store:apply(changes))
    eq(store.revision, 1)
    eq(events, 1)
    f.before = nil
    local writes = f.writes
    check(store:apply(changes))
    eq(f.writes, writes)
    eq(store:apply({ ["hud.opacity"] = 70, [P .. "input_interval_ms"] = 251 }), false)
    eq(store:get("hud.opacity"), 80)
    eq(f.writes, writes)
    eq(store:apply({ kind_149 = false, [P .. "hide_sos"] = true }), false)
    eq(f.writes, writes)
    eq(store:set("hud.opacity", 0 / 0), false)
    eq(store:set("hud.density", 1.5), false)
    check(f.text:find("schema_version=1\n", 1, true))
    check(f.text:find("private.future=false\n", 1, true))
    check(math.abs(Migrate.parse(f.text)["private.precision"] - 0.38123) < 1e-12)
    local detached = store:snapshot()
    detached["hud.opacity"] = 60
    eq(store:get("hud.opacity"), 80)
end)

case("own canonical reload ends every original import", function()
    local f = fixture({
        owned = "schema_version=1\nhud.opacity=83.25\n"
            .. P
            .. "enabled=false\n"
            .. P
            .. "input_interval_ms=999\nprivate.future=false\nkind_149=false\n"
            .. P
            .. "hide_sos=true\n",
    })
    local context = {
        config = {
            preferences = setmetatable({}, {
                __index = function()
                    error("Stale preferences queried")
                end,
            }),
        },
        require = function()
            error("Canonical reload queried original kind catalog")
        end,
    }
    local reads, queries = 0, 0
    f.storage.read_legacy = function()
        reads = reads + 1
        error("Stale legacy file unreadable")
    end
    local store = Store.new(context, {
        ModOptionsMenu = {
            get = function()
                queries = queries + 1
                error("Stale provider queried")
            end,
        },
    }, f.storage)
    eq(reads, 0)
    eq(queries, 0)
    eq(#f.reads, 0)
    eq(store:get(P .. "enabled"), false)
    eq(store:get(P .. "input_interval_ms"), 70)
    eq(store:get("kind_149"), false, "Own canonical ID wins over a conflicting private alias")
    eq(store:get("hud.opacity"), 83.25)
    eq(store:get("hud.scale"), 100)
    eq(store.unclaimed["private.future"], false)
    check(store:set("hud.scale", 105))
    local reloaded = Store.new(context, {}, f.storage)
    eq(reloaded:get("hud.scale"), 105)
    eq(reloaded:get("hud.opacity"), 83.25)
    eq(reloaded.unclaimed["private.future"], false)
    eq(Store.new == nil, false)
    eq(
        pcall(Store.new, context, {}, {
            read = function()
                return "schema_version=2\n"
            end,
            write_atomic = function() end,
        }),
        false
    )
    eq(
        pcall(Store.new, context, {}, {
            read = function()
                return nil, "read denied"
            end,
            write_atomic = function() end,
        }),
        false
    )
end)

case("original LLL persisted preferences overlay original defaults, never new HUD values", function()
    local reads = 0
    local f = fixture(nil, { label_size = 95 })
    f.storage.read_preferences = function()
        reads = reads + 1
        return [[{"preferences":{"enabled":true,"wheel_size":105,"icon_size":110,"input_interval_ms":85}}]],
            [[{"preferences":{"enabled":false,"wheel_size":112.34567,"input_interval_ms":0,"label_size":999,"hud.enabled":false,"future_setting":8}}]]
    end
    f.storage.read_legacy = function(name)
        if name == "menu" then
            return P .. "icon_size\t115\n"
        end
    end
    local store = Store.new(f.context, globals, f.storage)
    eq(reads, 1)
    eq(store:get(P .. "enabled"), false)
    eq(store:get(P .. "wheel_size"), 112.34567)
    eq(store:get(P .. "input_interval_ms"), 0)
    eq(store:get(P .. "icon_size"), 115)
    eq(store:get(P .. "label_size"), 95)
    eq(store:get("hud.enabled"), true)
    eq(store.unclaimed.future_setting, nil, "Only own-file unknown data is retained")
    eq(f.writes, 0)
    eq(store:set("hud.opacity", 80), true)
    f.storage.read_preferences = function()
        error("Own versioned state must never revisit original preferences")
    end
    local reloaded = Store.new(f.context, globals, f.storage)
    eq(reloaded:get(P .. "enabled"), false)
    eq(reloaded:get(P .. "wheel_size"), 112.34567)
    eq(reloaded:get("hud.opacity"), 80)
    local Json = project.require("settings/json.lua")
    eq(pcall(Json.decode, 'return os.execute("bad")'), false)
    eq(pcall(Json.decode, string.rep("x", 65537)), false)
    eq(pcall(Json.decode, '{"preferences":{"enabled":true}} trailing'), false)
end)

case("real original facade registers validation only, callbacks and close", function()
    local registrations = 0
    local f = fixture(nil, nil, {
        ModOptionsMenu = {
            get = function() end,
            register_option = function()
                registrations = registrations + 1
                error("Second settings owner")
            end,
        },
    })
    local api = f.store:dbf_options()
    eq(api, f.store:dbf_options())
    eq(api.unified, true)
    for id, spec in pairs(original) do
        eq(api.register_option(id, spec), true)
        eq(api.get(id), spec.default)
    end
    for _, row in ipairs(Schema.exclusions) do
        eq(api.register_option(P .. "mission_kind_" .. row.kind, { type = "toggle" }), true)
    end
    eq(api.register_option("unknown", { type = "toggle" }), false)
    eq(api.register_option(P .. "enabled", { type = "choice", choices = {} }), false)
    eq(registrations, 0)
    eq(#f.store.definitions, 91)
    eq(f.writes, 0)
    local called = 0
    eq(
        api.on_change(P .. "hide_sos", function(value, id)
            called = called + 1
            eq(value, true)
            eq(id, P .. "hide_sos")
        end),
        true
    )
    eq(api.set(P .. "hide_sos", true), true)
    eq(f.store:get("kind_149"), true)
    eq(called, 1)
    eq(f.writes, 1)
    eq(api.on_change("unknown", function() end), false)
    local unsubscribe = f.store:on_change("hud.enabled", function()
        error("observer raised")
    end)
    eq(f.store:set("hud.enabled", false), true)
    check(f.store.notification_error:find("observer raised", 1, true))
    unsubscribe()
    eq(f.store:close(), true)
    eq(api.set(P .. "enabled", false), false)
    eq(api.on_change(P .. "enabled", function() end), false)
    eq(api.register_option(P .. "enabled", original[P .. "enabled"]), false)
end)
case("ADS-minimal rename preserves old files without duplicate settings", function()
    eq(Schema.resolve("hud.ads_expand"), "hud.ads_minimal")
    eq(Schema.by_id["hud.ads_expand"], nil)
    local f = fixture({ owned = "schema_version=1\nhud.ads_expand=false\nhud.anchor=2\n" })
    eq(f.store:get("hud.ads_minimal"), false)
    eq(f.store:get("hud.ads_expand"), false)
    eq(f.store:get("hud.anchor"), 2, "saved positioning choice remains editable")
    eq(f.store:set("hud.ads_expand", true), true)
    eq(f.store:get("hud.ads_minimal"), true)
    check(f.text:find("hud.ads_minimal=true", 1, true))
    eq(f.text:find("hud.ads_expand=", 1, true), nil)
    f = fixture({ owned = "schema_version=1\nhud.ads_expand=false\nhud.ads_minimal=true\n" })
    eq(f.store:get("hud.ads_minimal"), true, "canonical value wins deterministically")
end)
case("TrueFP anchor choices persist independently and stacked ammo retains its bone", function()
    local f = fixture({ owned = "schema_version=1\nhud.opacity=83.25\n" .. P .. "wheel_size=113.125\n" })
    for _, id in ipairs({ "hud.tfp_vitals_bone", "hud.tfp_ammo_bone", "hud.tfp_ammo_placement" }) do
        eq(f.store:get(id), 1)
        eq(Schema.by_id[id].category, "tfp")
        eq(Schema.by_id[id].page, "tfp")
    end
    eq(f.writes, 0, "new defaults do not rewrite the old file")
    eq(f.store:set("hud.tfp_vitals_bone", 2), true)
    eq(f.store:set("hud.tfp_ammo_bone", 3), true)
    eq(f.store:set("hud.tfp_ammo_placement", 2), true)
    local get = function(id)
        return f.store:get(id)
    end
    eq(Schema.enabled("hud.tfp_ammo_bone", get), false, "stacked ammo uses health's effective anchor")
    eq(f.store:get("hud.tfp_ammo_bone"), 3, "retain independent ammo preference")
    local loaded = fixture({ owned = f.text })
    eq(loaded.store:get("hud.tfp_vitals_bone"), 2)
    eq(loaded.store:get("hud.tfp_ammo_bone"), 3)
    eq(loaded.store:get("hud.tfp_ammo_placement"), 2)
    eq(loaded.store:get("hud.opacity"), 83.25)
    eq(loaded.store:get(P .. "wheel_size"), 113.125)
    eq(f.store:set("hud.tfp_ammo_placement", 1), true)
    eq(Schema.enabled("hud.tfp_ammo_bone", get), true)
    eq(f.store:get("hud.tfp_ammo_bone"), 3)
    local before = f.writes
    for _, id in ipairs({ "hud.tfp_vitals_bone", "hud.tfp_ammo_bone" }) do
        for _, invalid in ipairs({ 0, #Schema.by_id[id].choices + 1, 1.5, "Left wrist" }) do
            eq(f.store:set(id, invalid), false)
        end
    end
    eq(f.store:set("hud.tfp_ammo_placement", 3), false)
    eq(f.writes, before, "invalid anchor selections cannot save")
end)
case("independent TrueFP XY offsets preserve precision and old preferences", function()
    local f = fixture({
        owned = "schema_version=1\nhud.opacity=83.25\nhud.tfp_vitals_bone=2\nhud.tfp_ammo_bone=3\n"
            .. P
            .. "wheel_size=113.125\n",
    })
    local offsets = {
        ["hud.tfp_vitals_offset_x"] = 73.125,
        ["hud.tfp_vitals_offset_y"] = -25.5,
        ["hud.tfp_ammo_offset_x"] = 22.75,
        ["hud.tfp_ammo_offset_y"] = -63.25,
    }
    local baseline = f.store:snapshot()
    for id in pairs(offsets) do
        eq(f.store:get(id), 0)
        local d = Schema.by_id[id]
        eq(d.type, "slider")
        eq(d.category, "tfp")
        eq(d.page, "tfp")
        eq(d.min, -600)
        eq(d.max, 600)
        eq(d.step, 5)
        eq(d.fine_step, 1)
    end
    eq(f.writes, 0)
    eq(f.store:apply(offsets), true)
    eq(f.writes, 1, "one atomic transaction for all independent offsets")
    local loaded = fixture({ owned = f.text })
    for id, previous in pairs(baseline) do
        eq(loaded.store:get(id), offsets[id] or previous, "unrelated preference retained: " .. id)
    end
    local get = function(id)
        return loaded.store:get(id)
    end
    eq(loaded.store:set("hud.tfp_ammo_placement", 2), true)
    eq(Schema.enabled("hud.tfp_ammo_bone", get), false)
    for id, expected in pairs(offsets) do
        eq(loaded.store:get(id), expected)
        eq(Schema.enabled(id, get), true, "stacked mode retains editable XY offsets")
        for _, invalid in ipairs({ -601, 601, math.huge, "10" }) do
            eq(loaded.store:set(id, invalid), false)
        end
    end
    eq(loaded.writes, 1)
    eq(loaded.store:set("hud.enabled", false), true)
    for id in pairs(offsets) do
        eq(Schema.enabled(id, get), false)
    end
end)
case("cooldown placement defaults and persists without changing existing preferences", function()
    local f = fixture({ owned = "schema_version=1\nhud.density=2\nhud.opacity=83.25\n" .. P .. "wheel_size=113.125\n" })
    eq(f.store:get("hud.cooldown_anchor"), 1, "old settings acquire Under health default")
    eq(f.writes, 0, "new default does not rewrite existing settings")
    eq(f.store:get("hud.density"), 2, "Detailed remains selected")
    eq(f.store:set("hud.cooldown_anchor", 2), true)
    eq(f.writes, 1)
    eq(f.store:get("hud.cooldown_anchor"), 2)
    check(f.text:find("hud.cooldown_anchor=2", 1, true))
    eq(f.store:get("hud.density"), 2)
    eq(f.store:get("hud.opacity"), 83.25)
    eq(f.store:get(P .. "wheel_size"), 113.125)
    local reloaded = fixture({ owned = f.text })
    eq(reloaded.store:get("hud.cooldown_anchor"), 2, "Under ammo survives reload")
    eq(reloaded.store:get("hud.density"), 2)
    eq(reloaded.writes, 0)
    eq(reloaded.store:set("hud.cooldown_anchor", 1), true)
    check(reloaded.text:find("hud.cooldown_anchor=1", 1, true))
    for _, invalid in ipairs({ 0, 3, 1.5, "2", false }) do
        eq(reloaded.store:set("hud.cooldown_anchor", invalid), false)
        eq(reloaded.store:get("hud.cooldown_anchor"), 1)
        eq(reloaded.writes, 1, "invalid placement never writes")
    end
    local invalid = fixture({ owned = "schema_version=1\nhud.cooldown_anchor=3\nhud.density=2\n" })
    eq(invalid.store:get("hud.cooldown_anchor"), 1, "invalid saved choice uses declared default")
    eq(invalid.store:get("hud.density"), 2)
    eq(invalid.writes, 0)
end)
case("anchor damping defaults and persists its exact range", function()
    local f =
        fixture({ owned = "schema_version=1\nhud.density=2\nhud.cooldown_anchor=2\n" .. P .. "wheel_size=113.125\n" })
    eq(f.store:get("hud.anchor_damping_ms"), 80)
    eq(f.writes, 0, "new default does not rewrite existing settings")
    for index, value in ipairs({ 0, 300, 80 }) do
        eq(f.store:set("hud.anchor_damping_ms", value), true)
        eq(f.writes, index, "each damping edit is one atomic transaction")
        eq(f.store:get("hud.anchor_damping_ms"), value)
        check(f.text:find("hud.anchor_damping_ms=" .. value, 1, true))
        local loaded = fixture({ owned = f.text })
        eq(loaded.store:get("hud.anchor_damping_ms"), value)
        eq(loaded.store:get("hud.density"), 2)
        eq(loaded.store:get("hud.cooldown_anchor"), 2)
        eq(loaded.store:get(P .. "wheel_size"), 113.125)
        eq(loaded.writes, 0)
    end
    for _, invalid in ipairs({ -1, 301, "80", false, math.huge }) do
        eq(f.store:set("hud.anchor_damping_ms", invalid), false)
        eq(f.store:get("hud.anchor_damping_ms"), 80)
        eq(f.writes, 3, "invalid damping never writes")
    end
    local invalid = fixture({ owned = "schema_version=1\nhud.anchor_damping_ms=301\nhud.density=2\n" })
    eq(invalid.store:get("hud.anchor_damping_ms"), 80, "invalid persisted damping uses declared default")
    eq(invalid.store:get("hud.density"), 2)
    eq(invalid.writes, 0)
end)
case("heat display defaults preserve every prior preference and save valid modes atomically", function()
    local f = fixture({
        owned = "schema_version=1\nhud.density=2\nhud.cooldown_anchor=2\n"
            .. P
            .. "wheel_size=113.125\nprivate.future=7\n",
    })
    local baseline = f.store:snapshot()
    eq(f.store:get("hud.heat_display"), 1)
    eq(f.writes, 0, "new percentage default does not rewrite the existing file")
    for index, mode in ipairs({ 2, 3, 1 }) do
        eq(f.store:set("hud.heat_display", mode), true)
        eq(f.writes, index)
        eq(f.store:get("hud.heat_display"), mode)
        local loaded = fixture({ owned = f.text })
        eq(loaded.store:get("hud.heat_display"), mode)
        for id, value in pairs(baseline) do
            if id ~= "hud.heat_display" then
                eq(loaded.store:get(id), value, "heat edit preserves " .. id)
            end
        end
        eq(loaded.writes, 0)
    end
    for _, value in ipairs({ 0, 4, 1.5, "2", false, math.huge }) do
        eq(f.store:set("hud.heat_display", value), false)
        eq(f.writes, 3)
        eq(f.store:get("hud.heat_display"), 1)
    end
end)
case("vertical heat orientation defaults preserve all prior preferences", function()
    local f = fixture({
        owned = "schema_version=1\nhud.heat_display=3\nhud.density=2\nhud.cooldown_anchor=2\n"
            .. P
            .. "wheel_size=113.125\nprivate.future=7\n",
    })
    local baseline = f.store:snapshot()
    eq(f.store:get("hud.heat_bar_vertical"), false)
    eq(f.writes, 0)
    for index, value in ipairs({ true, false }) do
        eq(f.store:set("hud.heat_bar_vertical", value), true)
        eq(f.writes, index)
        local loaded = fixture({ owned = f.text })
        eq(loaded.store:get("hud.heat_bar_vertical"), value)
        for id, prior in pairs(baseline) do
            if id ~= "hud.heat_bar_vertical" then
                eq(loaded.store:get(id), prior, "orientation preserves " .. id)
            end
        end
    end
    for _, value in ipairs({ 0, 1, "true" }) do
        eq(f.store:set("hud.heat_bar_vertical", value), false)
        eq(f.writes, 2)
    end
end)
case("heat limiter is one independent weapon control preserving83 prior preferences", function()
    local f = fixture({
        owned = "schema_version=1\nhud.heat_bar_vertical=true\nhud.heat_display=3\nhud.enabled=false\n"
            .. P
            .. "enabled=false\n"
            .. P
            .. "wheel_size=113.125\nprivate.future=7\n",
    })
    local baseline = f.store:snapshot()
    eq(f.store:get("weapon.heat_limiter"), false, "A new native capability requires an explicit opt-in")
    eq(f.writes, 0)
    for index, value in ipairs({ true, false }) do
        eq(f.store:set("weapon.heat_limiter", value), true)
        eq(f.writes, index)
        local loaded = fixture({ owned = f.text })
        eq(loaded.store:get("weapon.heat_limiter"), value)
        for id, prior in pairs(baseline) do
            if id ~= "weapon.heat_limiter" then
                eq(loaded.store:get(id), prior, "limiter preserves " .. id)
            end
        end
    end
    for _, invalid in ipairs({ 0, 1, "true" }) do
        eq(f.store:set("weapon.heat_limiter", invalid), false)
        eq(f.writes, 2)
    end
end)
print(
    "settings: "
        .. cases
        .. " cases / "
        .. checks
        .. " checks; exact69 original routes +21HUD +1weapon, atomic imports and facade"
)
