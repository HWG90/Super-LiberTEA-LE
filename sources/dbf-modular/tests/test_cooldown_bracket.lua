-- Real cooldown model/presenter with pure text metrics and owned native standins.
-- No game process, game files, input forwarding, or second row collector.
local ffi = require("ffi")
local checks = 0
local function check(value, why)
    checks = checks + 1
    assert(value, why or ("check " .. checks))
end
local function eq(actual, expected, why)
    check(actual == expected, (why or "mismatch") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, why)
    check(math.abs(actual - expected) < 0.00001, (why or "mismatch") .. ": " .. actual .. " ~= " .. expected)
end
mod = {
    require = function(path)
        return assert(loadfile("dbf_modular/" .. path))()
    end,
}
radial = {}
local C = assert(loadfile("dbf_modular/src/cooldown_dock.lua"))()
local font = { font = "0123456789abcdef", atlas = "123456789abcdef0", material = "23456789abcdef01" }
local function measure(_, text, size)
    return {
        left = -size * 0.1,
        bottom = -size * 0.2,
        right = #text * size * 0.55,
        top = size * 0.8,
        width = #text * size * 0.55 + size * 0.1,
        height = size,
    }
end
local function row(entry, phase, seconds)
    return {
        entry = entry,
        kind = entry + 100,
        timer_kind = phase,
        timer_seconds = seconds,
        unavailable = phase == "unavailable",
        dock_payload = 444,
        dock_source = 555,
    }
end
local function options(scale)
    local badges = {}
    for index = 1, 16 do
        badges[index] = { left = -32, bottom = -32, right = 40, top = 40, icon_width = 64, icon_height = 64 }
    end
    return {
        identity = 1000,
        generation = 3,
        scale = scale or 0.75,
        pixel = 1,
        font = font,
        measure = measure,
        combat_bounds = { bottom = -100 },
        native_badges = badges,
    }
end
local function find(packet, key)
    for _, p in ipairs(packet.primitives) do
        if p.key == key then
            return p
        end
    end
end
local function contains(packet, p)
    local b = packet.bounds
    local m = p.kind == "text" and measure(font, p.text, p.size)
        or { left = 0, bottom = 0, right = p.width, top = p.height }
    check(
        p.x + m.left >= b.left - 0.00001
            and p.x + m.right <= b.right + 0.00001
            and p.y + m.bottom >= b.bottom - 0.00001
            and p.y + m.top <= b.top + 0.00001,
        "complete bounds include " .. p.key
    )
end
do
    local model = C.cooldown_dock_model()
    local rows = { row(1, "cooldown", 65), row(2, "incoming", 5), row(3, "cooldown", 4), row(4, "unavailable") }
    model.sample({ identity = 1000, rows = rows }, 0, true)
    local config = {
        cooldown_display = 1,
        cooldown_timer = 2,
        short_timer_style = 2,
        short_status_placement = 3,
        brief_timer_limit = 10,
        balance_separated_dock = true,
    }
    local layout = C.cooldown_dock_bracket(model, config)
    local packet = layout.update(400, options())
    eq(packet.valid, true)
    eq(packet.eligible, true)
    eq(packet.has_content, true)
    eq(packet.tile_count, 4)
    eq(packet.generation, 3)
    eq(packet.sourceRevision, model.revision)
    near(packet.bounds.top, -109, "whole component below combat by12*scale")
    eq(find(packet, "cooldown_timer_1").text, "1:05")
    eq(find(packet, "cooldown_timer_2").text, "5")
    eq(find(packet, "cooldown_timer_3").text, "4")
    eq(find(packet, "cooldown_timer_4"), nil, "unavailable has no invented countdown")
    for _, p in ipairs(packet.primitives) do
        check(p.kind == "text" or p.key == "cooldown_divider", "no Bracket label/panel box")
        contains(packet, p)
    end
    local tile, primitive = packet.tiles[1], packet.primitives[1]
    eq(layout.update(400, options()), packet, "packet reused")
    eq(packet.tiles[1], tile, "tile reused")
    eq(packet.primitives[1], primitive, "primitive reused")
    local original = model.items[model.order[1]]
    eq(original.x, nil, "Bracket geometry never changes original tween")
    original.cooldown_span = 60
    original.row.timer_seconds = 5
    packet = layout.update(800, options())
    eq(packet.tiles[1].item.short_status, false, "long native span remains long when remaining<10")
    eq(find(packet, "cooldown_timer_1").text, "5", "short timer formatting still uses remaining seconds")
    config.dock_gap = 0
    near(layout.update(800, options()).bounds.top, -100, "zero spacing remains operative")
    config.dock_gap = 80
    near(layout.update(800, options()).bounds.top, -130, "maximum spacing remains operative")
    config.dock_gap = 24
    -- Every original setting combination retains every selected row.
    for display = 1, 3 do
        config.cooldown_display = display
        for placement = 1, 4 do
            config.short_status_placement = placement
            for timer = 1, 4 do
                config.cooldown_timer = timer
                for short = 1, 2 do
                    config.short_timer_style = short
                    packet = layout.update(1200, options(1.5))
                    eq(packet.valid, true)
                    eq(#packet.tiles, 4)
                    near(packet.bounds.top, -118)
                    for _, p in ipairs(packet.primitives) do
                        contains(packet, p)
                    end
                    for _, t in ipairs(packet.tiles) do
                        if t.charge_side == "native" then
                            check(
                                packet.bounds.right >= t.x + t.size * 40 / 64 - 0.00001
                                    and packet.bounds.top >= t.y + t.size * 40 / 64 - 0.00001,
                                "measured native badge extends beyond icon box"
                            )
                            local dx = (t.item.target_x - t.item.x) * packet.scale
                            local dy = (t.item.target_y - t.item.y) * packet.scale
                            check(
                                packet.bounds.right >= t.x + dx + t.size * 40 / 64 - 0.00001
                                    and packet.bounds.top >= t.y + dy + t.size * 40 / 64 - 0.00001,
                                "native badge target extent included"
                            )
                        end
                    end
                    if display == 2 then
                        eq(find(packet, "cooldown_timer_4").text, "Unavailable")
                        check(find(packet, "cooldown_heading_1") ~= nil, "overview grouping retained")
                    elseif timer == 1 then
                        eq(find(packet, "cooldown_timer_1"), nil, "Off stays Off outside native overview")
                    end
                end
            end
        end
    end
    config.cooldown_display, config.cooldown_timer = 1, 2
    config.short_status_placement, config.balance_separated_dock = 2, false
    layout.update(1600, options())
    packet = layout.update(1950, options())
    local unbalanced_x = packet.tiles[1].x
    config.balance_separated_dock = true
    layout.update(2000, options())
    packet = layout.update(2350, options())
    check(packet.tiles[1].x ~= unbalanced_x, "separator balance remains operative")
    config.short_status_placement = 4
    layout.update(2400, options())
    packet = layout.update(2750, options())
    check(packet.tiles[2].y < packet.tiles[1].y, "below-group short-status placement remains separate")
    config.cooldown_display = 3
    local aligned = options()
    aligned.combat_bounds.left, aligned.combat_bounds.right = -145, 200
    layout.update(2800, aligned)
    packet = layout.update(3150, aligned)
    near(packet.bounds.left, -145, "compact row aligns NEW Bracket left, never old native health")
    config.cooldown_display = 1
    -- A membership change starts a tween: clamp must include target too.
    model.sample({ identity = 1000, rows = { rows[1] } }, 3201, true)
    packet = layout.update(3201, options())
    tile = packet.tiles[1]
    local dx = (tile.item.target_x - tile.item.x) * packet.scale
    local dy = (tile.item.target_y - tile.item.y) * packet.scale
    check(
        packet.bounds.left <= tile.x + dx - tile.size / 2 and packet.bounds.right >= tile.x + dx + tile.size / 2,
        "target tile width bounded"
    )
    check(
        packet.bounds.bottom <= tile.y + dy - tile.size / 2 and packet.bounds.top >= tile.y + dy + tile.size / 2,
        "target tile height bounded"
    )
    for _, p in ipairs(packet.primitives) do
        if p.key:match("cooldown_timer_1") then
            local moved = {}
            for k, v in pairs(p) do
                moved[k] = v
            end
            moved.x, moved.y = p.x + dx, p.y + dy
            contains(packet, moved)
        end
    end
    local notice = options()
    notice.ready = { visible = true, text = "STRATAGEM READY", tone = "text" }
    local bar_bottom, tile_x, tile_y = packet.bounds.bottom, packet.tiles[1].x, packet.tiles[1].y
    packet = layout.update(3201, notice)
    local ready = find(packet, "ready")
    check(ready ~= nil, "ready notice accompanies the existing cooldown bar")
    near(ready.y + measure(font, ready.text, ready.size).top, bar_bottom - 6, "ready notice is below whole bar")
    near(packet.tiles[1].x, tile_x, "notice does not move native icons")
    near(packet.tiles[1].y, tile_y)
    contains(packet, ready)
    contains(packet, find(packet, "ready_shadow"))
    notice.ready.visible = false
    eq(find(layout.update(3201, notice), "ready"), nil, "expired notice disappears")
    local off = options()
    off.enabled = false
    off.ready = { visible = true, text = "STRATAGEM READY" }
    packet = layout.update(3300, off)
    eq(packet.valid, true)
    eq(packet.eligible, true)
    eq(packet.has_content, false)
    eq(#packet.tiles, 0)
    eq(#packet.primitives, 0)
    eq(packet.bounds.top, 0)
    local bad = options()
    bad.measure = function()
        return nil
    end
    eq(layout.update(3400, bad).valid, false, "unknown measurements refuse")
    bad = options()
    bad.generation = nil
    eq(layout.update(3400, bad).valid, false, "generation required")
    model.sample({ identity = 1000, rows = {} }, 3500, true)
    notice.ready.visible = true
    packet = layout.update(3500, notice)
    eq(packet.valid, true)
    eq(packet.tile_count, 0, "last cooldown can finish before notice expires")
    eq(packet.has_content, true)
    check(find(packet, "ready") ~= nil, "ready notice remains after last icon clears")
    contains(packet, find(packet, "ready"))
    notice.ready.visible = false
    eq(layout.update(3500, notice).has_content, false, "empty dock clears after the notice")
end
local function fixture()
    local fields, parents, stats =
        {}, {}, {
            ticks = 0,
            sets = 0,
            contexts = 0,
            creates = 0,
            releases = 0,
            visibilities = 0,
            visibility_events = {},
        }
    local state = {
        valid = true,
        ready = true,
        sx = 2,
        sy = 2,
        ox = 1920,
        oy = 0,
        skew = 0,
        count = 3,
        resource = 32,
        parent_context = ffi.new("uintptr_t[1]", 32),
    }
    local function field(at)
        fields[at] = fields[at] or {}
        return fields[at]
    end
    local b = {
        valid = function(id)
            return state.valid and id == 1000
        end,
        get = function(at, key)
            return field(at)[key] or (key == "size" and { 64, 64 } or key == "scale" and { 1, 1 } or { 0, 0 })
        end,
        set = function(at, key, value)
            if state.fail_write and key == "position" then
                error("position refused")
            end
            stats.sets = stats.sets + 1
            field(at)[key] = { value[1], value[2] }
        end,
        pointer = function(at)
            if at == 1000 + 0x258 + 0xf8 then
                return tonumber(state.parent_context[0])
            end
            return parents[at]
        end,
        read_u64 = function(at)
            if state.link_unknown then
                return nil
            end
            return parents[at] or 0
        end,
        read = function(_, count)
            if count == 4 then
                return ffi.string(ffi.new("float[1]", 60), 4)
            end
            return string.rep("\0", count)
        end,
        widgets_ready = function()
            return state.ready
        end,
        callable = function()
            return state.ready
        end,
        release_owned_ui = function(_, at)
            stats.releases = stats.releases + 1
            if state.release_refused then
                return false, "detach refused"
            end
            if at then
                parents[at + 0xf0] = 0
            end
            return true
        end,
        dock_text_position = function(_, x, y)
            return state.ox + state.sx * x, state.oy + state.skew * x + state.sy * y
        end,
    }
    function state.detach()
        for at, values in pairs(fields) do
            if values.size and values.size[1] == 0 and values.size[2] == 0 then
                parents[at + 0xf0] = 0
            end
        end
    end
    function b.fn(_, rva)
        if rva == 0x12de6b0 then
            return function(at)
                parents[at + 0xf8] = state.resource
            end
        end
        if rva == 0x16ba580 then
            return function(at)
                stats.creates = stats.creates + 1
                parents[at + 0x920 + 0xf0] = at
                parents[at + 0xf8] = state.resource
                parents[at + 0x920 + 0xf8] = state.resource
                for _, offset in ipairs({ 0xa30, 0xb88, 0xce0 }) do
                    parents[at + offset + 0xf0] = at + 0x920
                    parents[at + offset + 0xf8] = state.resource
                end
                ffi.cast("uint32_t *", at + 0x14bc)[0] = 3
                ffi.cast("float *", at + 0x14c4)[0] = 60
            end
        end
        if rva == 0x12e4430 then
            return function(parent, child)
                parents[child + 0xf0] = parent
            end
        end
        if rva == 0x16bb030 then
            return function(at)
                stats.ticks = stats.ticks + 1
                ffi.cast("uint32_t *", at + 0x14bc)[0] = state.count
                for _, offset in ipairs({ 0xa30, 0xb88, 0xce0 }) do
                    field(at + offset).opacity = 1
                end
            end
        end
        if rva == 0x12e4e20 then
            return function(at, visible)
                stats.visibilities = stats.visibilities + 1
                stats.visibility_events[#stats.visibility_events + 1] = { at = at, value = visible }
                field(at).visible = visible
            end
        end
        if rva == 0x12e0940 then
            return function(at, opacity)
                field(at).opacity = opacity
            end
        end
        return function() end
    end
    local scope = {
        context_ready = function()
            return state.ready
        end,
        context_scope = function(_, fn)
            stats.contexts = stats.contexts + 1
            fn(state.resource)
        end,
    }
    radial = {
        cooldown_display = 1,
        cooldown_timer = 2,
        short_timer_style = 2,
        short_status_placement = 3,
        brief_timer_limit = 10,
        balance_separated_dock = true,
    }
    local dock = C.cooldown_dock(b, scope, {})
    local snapshot = {
        identity = 1000,
        open = false,
        hud_visible = true,
        dock_parent = 1000 + 0x258,
        dock_y = 120,
        dock_below_y = 58,
        rows = { row(1, "cooldown", 5) },
    }
    dock.sample(snapshot, 0)
    return dock, b, snapshot, state, stats, fields
end
do
    local dock, _, snapshot, _, stats, fields = fixture()
    eq(dock.draw(400, true), true)
    local root
    for at, values in pairs(fields) do
        if values.size and values.size[1] == 0 and values.size[2] == 0 then
            root = at
        end
    end
    check(root ~= nil)
    local first, second = root + 0x110, root + 0x110 + 0x1500
    local packet = dock.bracket_layout(401, options())
    local source, source_revision = packet.tiles[1].item.source, packet.sourceRevision
    local anchor = { x = 960, y = 540 }
    eq(dock.draw_bracket(401, packet, anchor, 1), true)
    eq(fields[first].visible, 1)
    local ticks = stats.ticks
    eq(dock.draw(402, false), true)
    eq(fields[first].visible, 0, "hide explicitly hides cached child")
    eq(fields[root].visible, 0)
    eq(dock.draw_bracket(403, packet, anchor, 1), true)
    eq(fields[first].visible, 1, "reveal restores cached native child, not only root/text")
    eq(fields[root].visible, 1)
    eq(stats.visibility_events[#stats.visibility_events].at, root, "root is shown after current icons")
    eq(stats.ticks, ticks, "visibility change does not resample or advance native countdown")
    for now = 404, 408, 2 do
        eq(dock.draw(now, false), true)
        eq(fields[first].visible, 0)
        eq(dock.draw_bracket(now + 1, packet, anchor, 1), true)
        eq(fields[first].visible, 1, "repeated Quiet/Detailed reveal restores cached icon")
    end
    packet = dock.bracket_layout(410, options())
    eq(packet.sourceRevision, source_revision, "hide/reveal does not reset source model")
    eq(packet.tiles[1].item.source, source, "same membership/timer owner survives visibility transitions")
    eq(source.cooldown_span, 60)
    local sets, visibility = stats.sets, stats.visibilities
    eq(dock.draw_bracket(410, packet, anchor, 1), true)
    eq(stats.sets, sets, "unchanged shown packet does not add geometry setters")
    eq(stats.visibilities, visibility, "unchanged shown packet does not repeat visibility setters")
    -- Change membership while hidden, then exercise the Original fallback's
    -- reveal before shared packet metadata is prepared for the added slot.
    eq(dock.draw(420, false), true)
    snapshot.rows = { row(2, "incoming", 8), row(3, "cooldown", 20) }
    dock.sample(snapshot, 421)
    eq(dock.draw(422, true), true)
    eq(fields[first].visible, 1, "changed cached slot revealed")
    eq(fields[second].visible, 1, "new slot revealed")
    packet = dock.bracket_layout(423, options())
    eq(packet.valid, true)
    eq(packet.tile_count, 2)
    eq(dock.draw_bracket(423, packet, anchor, 1), true)
    eq(dock.draw(430, false), true)
    snapshot.rows = { snapshot.rows[2] }
    dock.sample(snapshot, 431)
    eq(dock.draw(432, true), true)
    eq(fields[first].visible, 1)
    eq(fields[second].visible, 0, "removed row remains hidden on reveal")
    eq(stats.creates, 16, "visibility transitions retain one native tile set")
    eq(dock.draw(1000, true), true)
    sets, visibility, ticks = stats.sets, stats.visibilities, stats.ticks
    eq(dock.draw(1001, true), true)
    eq(stats.sets, sets)
    eq(stats.visibilities, visibility)
    eq(stats.ticks, ticks)
    eq(dock.close(), true)
end
do
    local dock, _, _, _, stats = fixture()
    eq(dock.draw(400, true), true)
    local packet = dock.bracket_layout(401, options())
    eq(dock.draw_bracket(401, packet, { x = 960, y = 540 }, 1), true)
    local before, last_tick, ticks = stats.ticks, 401, 0
    local anchor = { x = 960, y = 540 }
    for now = 416, 1600, 16 do
        packet = dock.bracket_layout(now, options())
        eq(packet.valid, true)
        anchor.x = 960 + (now - 400) / 100
        local prior = stats.ticks
        eq(dock.draw_bracket(now, packet, anchor, 1), true)
        if now - last_tick >= 250 then
            eq(stats.ticks, prior + 1, "continuous movement cannot starve the native250ms tick")
            check(now - last_tick <= 265, "tick runs on the first due16ms frame")
            last_tick, ticks = now, ticks + 1
        else
            eq(stats.ticks, prior, "position updates never advance native elapsed time early")
        end
    end
    eq(ticks, 4)
    eq(stats.ticks, before + 4)
    local sets, visibility, native_ticks = stats.sets, stats.visibilities, stats.ticks
    packet = dock.bracket_layout(1601, options())
    eq(dock.draw_bracket(1601, packet, anchor, 1), true)
    eq(stats.sets, sets, "unchanged moving-presenter frame retains geometry fast path")
    eq(stats.visibilities, visibility)
    eq(stats.ticks, native_ticks)
    eq(dock.close(), true)
end
do
    local dock, b, snapshot, state, stats, fields = fixture()
    state.count = 0
    eq(dock.draw(400, true), true, "Original constructs and measures native badge first")
    local packet = dock.bracket_layout(401, options())
    local anchor = { x = 960, y = 540 }
    eq(packet.tiles[1].charge_text, false, "first tick has no invented count")
    eq(packet.tiles[1].charge_side, "native", "unknown exported count retains native badge")
    state.count = 3
    eq(dock.draw_bracket(650, packet, anchor, 1), true)
    local icon
    for at, values in pairs(fields) do
        if values.position and values.visible == 1 and values.size == nil then
            icon = at
        end
    end
    check(icon ~= nil)
    -- Original's unknown/zero count had hidden these. Native tick restores its
    -- own badge; Bracket does not add another suppression until text is ready.
    eq(fields[icon + 0xce0].opacity, 1, "first native count stays visible until exported label exists")
    packet = dock.bracket_layout(651, options())
    eq(find(packet, "cooldown_charge_1").text, "3", "next packet reuses learned native count")
    eq(packet.tiles[1].charge_text, true)
    eq(dock.draw_bracket(651, packet, anchor, 1), true)
    eq(fields[icon + 0xce0].opacity, 0, "native text hidden only with exported known count")
    state.count = 2
    local okay, why = dock.draw_bracket(901, packet, anchor, 1)
    eq(okay, false, "changed after-tick count refuses stale exported text")
    check(why:find("charge count changed", 1, true) ~= nil)
    eq(packet.tiles[1].item.source.native_charge_count, 2, "new fact retained for next layout")
    eq(dock.clear_bracket(901, true), true, "changed count restores original in same frame")
    packet = dock.bracket_layout(902, options())
    eq(find(packet, "cooldown_charge_1").text, "2")
    eq(dock.draw_bracket(902, packet, anchor, 1), true)
    local sets = stats.sets
    snapshot.dock_parent = snapshot.dock_parent + 16
    eq(dock.draw_bracket(903, packet, anchor, 1), false, "fresh exact native parent required")
    eq(stats.sets, sets)
    snapshot.dock_parent = snapshot.identity + 0x258
    state.ready = false
    eq(dock.draw_bracket(903, packet, anchor, 1), false, "fresh native resource context required")
    eq(stats.sets, sets)
    state.ready = true
    dock.sample(snapshot, 1000)
    eq(dock.draw_bracket(1000, packet, anchor, 1), false, "new sample invalidates prior packet revision")
    eq(stats.sets, sets)
    eq(dock.close(), true)
end
do
    local dock, b, snapshot, state, stats, fields = fixture()
    eq(dock.draw(400, true), true)
    local packet = dock.bracket_layout(401, options())
    eq(dock.draw_bracket(401, packet, { x = 960, y = 540 }, 1), true)
    local source_revision = packet.sourceRevision
    local sets, contexts, ticks = stats.sets, stats.contexts, stats.ticks
    -- Change the actual bytes exposed by the parent.f8 read. Root identity,
    -- parent link, context-ready Boolean and address all remain unchanged.
    state.parent_context[0], state.resource = 64, 64
    eq(dock.draw_bracket(402, packet, { x = 960, y = 540 }, 1), false, "same-root resource replacement refused")
    eq(dock.draw(402, true), false, "resource guard precedes legacy cached-return path")
    eq(dock.hide(), false, "hide refuses linked old-context owner")
    eq(dock.clear_bracket(402, true), false, "rollback refuses linked old-context owner")
    eq(stats.sets, sets)
    eq(stats.contexts, contexts)
    eq(stats.ticks, ticks)
    eq(dock.bracket_layout(402, options()).valid, false, "stale resource cannot export a new packet")
    -- Returning to the proven old context shows that no failed hide/reset
    -- silently discarded the collected rows, counts or external dirty state.
    state.parent_context[0], state.resource = 32, 32
    packet = dock.bracket_layout(403, options())
    eq(packet.valid, true)
    eq(packet.tile_count, 1)
    eq(packet.sourceRevision, source_revision, "refusal retains exact source model")
    eq(dock.clear_bracket(403, true), true)
    eq(dock.draw_bracket(404, packet, { x = 960, y = 540 }, 1), true)
    local empty = options()
    empty.enabled = false
    packet = dock.bracket_layout(405, empty)
    eq(packet.valid, true)
    eq(packet.has_content, false)
    state.parent_context[0], state.resource = 64, 64
    eq(dock.draw_bracket(405, packet, { x = 960, y = 540 }, 1), false, "empty packet propagates explicit hide refusal")
    state.release_refused = true
    eq(dock.close(), false, "guarded detach refusal retains terminal owner")
    eq(stats.releases, 0, "linked resource mismatch never reaches release helper")
    state.parent_context[0], state.resource = 32, 32
    eq(dock.close(), false, "restored context still retains backend detach refusal")
    eq(stats.releases, 1, "release helper called only after context proof")
    state.release_refused = false
    eq(dock.close(), true, "only guarded detach acknowledgment releases terminal owner")
    eq(stats.releases, 2)
end
do
    local dock, _, _, state, stats = fixture()
    eq(dock.draw(400, true), true)
    local packet = dock.bracket_layout(401, options())
    eq(dock.draw_bracket(401, packet, { x = 960, y = 540 }, 1), true)
    state.link_unknown = true
    eq(dock.close(), false, "unknown native attachment refuses release")
    eq(stats.releases, 0)
    state.link_unknown, state.parent_context[0] = false, 0
    eq(dock.close(), false, "unknown current resource refuses release")
    eq(stats.releases, 0)
    state.parent_context[0], state.resource = 64, 64
    eq(dock.close(), false, "replaced context remains retained")
    eq(stats.releases, 0)
    state.detach()
    eq(dock.close(), true, "detached link0 proves retirement despite context replacement")
    eq(stats.releases, 1, "retired allocation may reach guarded acknowledgment")
end
do
    local dock, b, snapshot, state, stats, fields = fixture()
    eq(dock.draw(400, true), true)
    eq(stats.creates, 16, "one retained native icon set")
    local packet = dock.bracket_layout(401, options(1.5))
    eq(packet.tiles[1].item.short_status, false, "native denominator shared into clone")
    local tile = packet.tiles[1]
    local anchor = { x = 1920, y = 1080 }
    eq(dock.draw_bracket(401, packet, anchor, 0.8), true)
    local icon
    for at, values in pairs(fields) do
        if values.position and values.visible == 1 and values.size == nil then
            icon = at
        end
    end
    check(icon ~= nil, "native icon placed")
    near(b.get(icon, "position")[1], tile.x / 2, "physical X inverse")
    near(b.get(icon, "position")[2], (1080 + tile.y) / 2, "physical Y inverse")
    near(b.get(icon, "scale")[1] * 64 * 2, tile.size, "physical tile width")
    near(b.get(icon, "scale")[2] * 64 * 2, tile.size, "physical tile height")
    eq(stats.creates, 16, "Bracket creates no second icon set")
    local ticks = stats.ticks
    eq(dock.draw_bracket(402, packet, anchor, 0.8), true, "unchanged placement acknowledged")
    eq(stats.ticks, ticks, "no second native timer tick inside250ms")
    local sets = stats.sets
    for now = 403, 425 do
        packet = dock.bracket_layout(now, options(1.5))
        eq(dock.draw_bracket(now, packet, anchor, 0.8), true)
    end
    eq(stats.sets, sets, "unchanged packet updates produce zero native setters")
    local revision = packet.sourceRevision
    eq(dock.clear_bracket(426, true), true, "same-frame explicit rollback")
    near(b.get(icon, "position")[1], 0, "original X restored immediately")
    near(b.get(icon, "position")[2], 120, "original Y restored immediately")
    near(b.get(icon, "scale")[1] * 64, 48, "original size restored")
    packet = dock.bracket_layout(427, options())
    eq(packet.sourceRevision, revision, "rollback did not reset/recollect model")
    eq(packet.tiles[1].item.source.cooldown_span, 60, "native span retained")
    check(packet.tiles[1].item.source.charge_count == 3, "native charges retained")
    state.valid = false
    sets = stats.sets
    eq(dock.draw_bracket(428, packet, anchor, 1), false, "fresh HUD identity refusal")
    eq(stats.sets, sets, "no native writes after refusal")
    state.valid, state.skew = true, 0.1
    eq(dock.draw_bracket(428, packet, anchor, 1), false, "skew unsupported")
    eq(stats.sets, sets)
    state.skew, state.sx = 0, 0
    eq(dock.draw_bracket(428, packet, anchor, 1), false, "singular unsupported")
    state.sx = -2
    eq(dock.draw_bracket(428, packet, anchor, 1), false, "reflection unsupported")
    state.sx, state.sy = 4, 2
    eq(dock.draw_bracket(428, packet, anchor, 1), true, "independent inverse native scale")
    near(b.get(icon, "scale")[1] * 64 * 4, tile.size)
    near(b.get(icon, "scale")[2] * 64 * 2, tile.size)
    state.fail_write = true
    anchor.x = 2000
    eq(dock.draw_bracket(429, packet, anchor, 1), false, "native partial draw refused")
    state.fail_write = false
    eq(dock.clear_bracket(429, true), true, "refusal rollback bypasses idle cache")
    near(b.get(icon, "position")[2], 120)
    snapshot.open = true
    dock.sample(snapshot, 430)
    eq(dock.bracket_layout(430, options()).eligible, false, "open menu stays Original")
    eq(dock.close(), true)
    eq(dock.draw_bracket(431, packet, anchor, 1), false, "closed owner cannot resurrect")
end
do
    local dock, _, snapshot, _, stats = fixture()
    snapshot.rows = {}
    dock.sample(snapshot, 1)
    local packet = dock.bracket_layout(1, options())
    eq(packet.valid, true)
    eq(packet.has_content, false)
    eq(dock.draw_bracket(1, packet, { x = 960, y = 540 }, 1), true)
    eq(stats.creates, 0, "empty packet creates no native GUI")
    local off = options()
    off.enabled = false
    eq(dock.bracket_layout(2, off).valid, true, "icons Off acknowledged while sampling stopped")
    eq(stats.creates, 0)
end
print("Cooldown Bracket: " .. checks .. " checks")
