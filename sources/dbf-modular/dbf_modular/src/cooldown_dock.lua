-- State and geometry are independent of native ownership and rendering.
local function cooldown_dock_timed(row, track_unavailable)
    return (track_unavailable and row.unavailable == true)
        or not row.unavailable
            and (row.timer_kind == "incoming" or row.timer_kind == "cooldown")
            and type(row.timer_seconds) == "number"
            and row.timer_seconds > 0
end
local function cooldown_dock_model()
    local self = { items = {}, order = {}, identity = nil, revision = 0 }
    function self.reset()
        self.items = {}
        self.order = {}
        self.identity = nil
        self.revision = self.revision + 1
    end
    function self.sample(snapshot, now, track_unavailable)
        if not snapshot then
            self.reset()
            return
        end
        if self.identity ~= snapshot.identity then
            self.reset()
            self.identity = snapshot.identity
        end
        local wanted = {}
        for _, row in ipairs(snapshot.rows or {}) do
            if cooldown_dock_timed(row, track_unavailable) then
                local key = tostring(row.entry) .. ":" .. tostring(row.kind)
                wanted[key] = true
                local item = self.items[key]
                if not item then
                    item = { key = key, kind = row.kind, born = now }
                    self.items[key] = item
                    self.order[#self.order + 1] = key
                end
                -- Incoming -> cooldown updates the same docked icon, without a second flight.
                local phase = row.unavailable and "unavailable" or row.timer_kind
                if item.phase ~= phase then
                    item.cooldown_span = nil
                end
                item.phase = phase
                item.row = row
            end
        end
        for i = #self.order, 1, -1 do
            local key = self.order[i]
            if not wanted[key] then
                self.items[key] = nil
                table.remove(self.order, i)
            end
        end
        self.revision = self.revision + 1
    end
    function self.layout(now, y, overview, placement, brief_limit, below_y, balanced, stamina, row)
        local result = {}
        local n = #self.order
        local panels
        -- Compact row: 32 px tiles in one line under the health bar's row box,
        -- left-aligned with the bar; cooldowns, then a padded vertical
        -- separator, then incoming. Dock coordinates (x from centre, Y up).
        local row_y, row_divider
        if row then
            local size, pitch, pad = 32, 40, 12
            -- 3 px under the health row: room for the timers below plus ~4 px of
            -- padding above the screen edge.
            row_y = row.bottom - 3 - size / 2
            local x = row.left + size / 2
            local cooling, incoming = {}, {}
            for _, key in ipairs(self.order) do
                local item = self.items[key]
                local group = item.phase == "incoming" and incoming or cooling
                group[#group + 1] = item
            end
            for _, item in ipairs(cooling) do
                item.row_x = x
                x = x + pitch
            end
            if #cooling > 0 and #incoming > 0 then
                row_divider = x - pitch + size / 2 + pad
                x = row_divider + pad + size / 2
            end
            for _, item in ipairs(incoming) do
                item.row_x = x
                x = x + pitch
            end
        end
        if overview then
            local groups = { { title = "Cooldowns", items = {} }, { title = "In Progress", items = {} } }
            for _, key in ipairs(self.order) do
                local item = self.items[key]
                item.short_status = item.phase == "incoming"
                    or item.phase ~= "unavailable"
                        and math.max(item.cooldown_span or 0, item.row.timer_seconds or 0) <= (brief_limit or 10)
                local group = groups[item.short_status and 2 or 1]
                group.items[#group.items + 1] = item
            end
            panels = {}
            local bottom = stamina and stamina.bottom or y - 24
            for index = 2, 1, -1 do
                local group = groups[index]
                local count = #group.items
                if count > 0 then
                    local top = bottom + count * 36 + 40
                    local offset = index == 1 and ((stamina and stamina.left or -110) - 12 - 56)
                        or ((stamina and stamina.right or 110) + 12 + 56)
                    panels[#panels + 1] =
                        { title = group.title, left = offset - 56, right = offset + 56, bottom = bottom, top = top }
                    for i, item in ipairs(group.items) do
                        item.overview_y = top - 50 - (i - 1) * 36
                        item.overview_offset = offset
                    end
                end
            end
        end
        local split = not overview and not row and placement and placement > 1
        local short_n = 0
        if split then
            for _, key in ipairs(self.order) do
                local item = self.items[key]
                -- Remaining charges survive a full Eagle rearm. They do not prove
                -- this is the brief between-run cooldown; classify by native time.
                item.short_status = item.phase == "incoming"
                    or item.phase ~= "unavailable"
                        and math.max(item.cooldown_span or 0, item.row.timer_seconds or 0) <= (brief_limit or 10)
                if item.short_status then
                    short_n = short_n + 1
                end
            end
        end
        local main_n = n - short_n
        local main_i, short_i = 0, 0
        local balance = balanced ~= false
                and split
                and placement ~= 4
                and main_n > 0
                and short_n > 0
                and (short_n * 30 + 12) * (placement == 2 and 1 or -1)
            or 0
        for i, key in ipairs(self.order) do
            local item = self.items[key]
            local x = row and item.row_x or overview and item.overview_offset + 28 or (i - (n + 1) / 2) * 60
            local target_y = row and row_y or overview and item.overview_y or y
            item.below_stamina = false
            item.compact_row = row ~= nil
            if split then
                if item.short_status then
                    short_i = short_i + 1
                    if placement == 4 then
                        x = (short_i - (short_n + 1) / 2) * 60
                        target_y = below_y or y - 62
                        item.below_stamina = true
                    elseif main_n == 0 then
                        x = (short_i - (short_n + 1) / 2) * 60
                    elseif placement == 2 then
                        x = -(main_n * 30 + 54) - (short_n - short_i) * 60
                    else
                        x = main_n * 30 + 54 + (short_i - 1) * 60
                    end
                else
                    main_i = main_i + 1
                    x = (main_i - (main_n + 1) / 2) * 60
                end
            end
            x = x + balance
            if item.target_x ~= x or item.target_y ~= target_y then
                item.start_x, item.start_y = item.x or x, item.y or target_y
                item.target_x, item.target_y = x, target_y
                item.moved = now
            end
            local t = math.min(1, math.max(0, (now - item.moved) / 350))
            local ease = 1 - (1 - t) ^ 3
            item.x = item.start_x + (x - item.start_x) * ease
            item.y = item.start_y + (target_y - item.start_y) * ease
            item.alpha = math.min(1, math.max(0, (now - item.born) / 140))
            result[i] = item
        end
        local divider
        if row_divider then
            local alpha = 1
            for _, item in ipairs(result) do
                alpha = math.min(alpha, item.alpha)
            end
            divider = { x = row_divider, y = row_y, alpha = alpha, half = 16 }
        elseif split and placement ~= 4 and main_n > 0 and short_n > 0 then
            local alpha = 1
            for _, item in ipairs(result) do
                alpha = math.min(alpha, item.alpha)
            end
            divider = { x = (main_n * 30 + 12) * (placement == 2 and -1 or 1) + balance, y = y, alpha = alpha }
        end
        return result, divider, panels
    end
    return self
end
-- A physical-pixel view of the SAME sampled dock model. The caller supplies
-- Bracket's font measurement service; no GUI, native row or input read occurs
-- here. Native icon art and charge badges remain under the original presenter.
local function cooldown_dock_bracket(model, config)
    local self = { valid = false, eligible = false, tiles = {}, primitives = {}, bounds = {}, revision = 0 }
    local slots, tile_slots, native_parts = {}, {}, {}
    local geometry = cooldown_dock_model()
    local function finite(value)
        return type(value) == "number" and value == value and math.abs(value) < math.huge
    end
    local function include(left, bottom, right, top)
        self.left, self.bottom = math.min(self.left, left), math.min(self.bottom, bottom)
        self.right, self.top = math.max(self.right, right), math.max(self.top, top)
        -- A tween can move further after Anchor's clamp pass. Include its target
        -- as well as the currently drawn geometry (also for labels/badges).
        self.left, self.bottom = math.min(self.left, left + self.dx), math.min(self.bottom, bottom + self.dy)
        self.right, self.top = math.max(self.right, right + self.dx), math.max(self.top, top + self.dy)
    end
    local function primitive(key, kind, x, y, w, h, text, size, tone, alpha, align, shadow)
        local slot = slots[key]
        if not slot then
            slot = { key = key, kind = kind }
            slots[key] = slot
        end
        local left, bottom, right, top = 0, 0, w, h
        if kind == "text" then
            local metrics, why = self.measure(self.font, text, size)
            if
                not metrics
                or not finite(metrics.left)
                or not finite(metrics.bottom)
                or not finite(metrics.right)
                or not finite(metrics.top)
                or metrics.right < metrics.left
                or metrics.top < metrics.bottom
            then
                return false, why or "Cooldown text measurement unavailable"
            end
            left, bottom, right, top = metrics.left, metrics.bottom, metrics.right, metrics.top
            if align == "center" then
                x = x - (left + right) / 2
            elseif align == "right" then
                x = x - right
            end
            if not shadow then
                local okay, problem = primitive(
                    key .. "_shadow",
                    "text",
                    x + self.pixel,
                    y - self.pixel,
                    0,
                    0,
                    text,
                    size,
                    "hud_shadow",
                    alpha,
                    nil,
                    true
                )
                if not okay then
                    return false, problem
                end
            end
        end
        slot.x, slot.y, slot.z = x, y, shadow and 950 or kind == "text" and 951 or 949
        slot.width, slot.height, slot.text, slot.size = w, h, text, size
        slot.tone, slot.alpha = tone, alpha
        self.used = self.used + 1
        self.primitives[self.used] = slot
        include(x + left, y + bottom, x + right, y + top)
        return true
    end
    function self.update(now, options)
        options = options or {}
        self.valid, self.eligible, self.reason, self.has_content = false, false, nil, false
        local scale, combat = options.scale, options.combat_bounds
        if
            not finite(now)
            or not finite(scale)
            or scale <= 0
            or options.identity == nil
            or options.generation == nil
            or (#model.order > 0 and options.identity ~= model.identity)
            or type(options.measure) ~= "function"
            or type(options.font) ~= "table"
            or type(combat) ~= "table"
            or not finite(combat.bottom)
        then
            self.reason = "Cooldown Bracket layout inputs unavailable"
            return self
        end
        self.identity, self.generation, self.sourceRevision = options.identity, options.generation, model.revision
        self.scale, self.font, self.measure = scale, options.font, options.measure
        self.pixel = finite(options.pixel) and options.pixel > 0 and options.pixel or scale
        self.left, self.bottom, self.right, self.top = math.huge, math.huge, -math.huge, -math.huge
        self.used, self.tile_count, self.dx, self.dy = 0, 0, 0, 0
        if geometry.identity ~= model.identity then
            geometry.reset()
            geometry.identity = model.identity
        end
        local wanted = {}
        for index, key in ipairs(model.order) do
            local source = model.items[key]
            local item = geometry.items[key]
            if not item then
                item = { key = key, kind = source.kind, born = source.born }
                geometry.items[key] = item
            end
            item.source, item.row, item.phase = source, source.row, source.phase
            item.cooldown_span = source.cooldown_span
            item.charge_count = source.native_charge_count or source.charge_count
            geometry.order[index], wanted[key] = key, true
        end
        for index = #geometry.order, #model.order + 1, -1 do
            geometry.order[index] = nil
        end
        for key in pairs(geometry.items) do
            if not wanted[key] then
                geometry.items[key] = nil
            end
        end
        local overview = config.cooldown_display == 2
        local compact = config.cooldown_display == 3
        local count = options.enabled == false and 0 or #model.order
        local items, divider, panels = {}, nil, nil
        if count > 0 then
            -- Preserve original grouping, sorting, brief threshold, separator
            -- balance and easing. The virtual native-bar bounds only relocate
            -- each existing layout; they do not select a different mode.
            local row = compact and { left = -(count * 40 - 8) / 2, bottom = 0 } or nil
            items, divider, panels = geometry.layout(
                now,
                0,
                overview,
                config.short_status_placement,
                config.brief_timer_limit,
                -62,
                config.balance_separated_dock,
                { left = -18, right = 18, bottom = 0 },
                row
            )
        end
        local position = overview and 5
            or compact and (config.cooldown_timer == 1 and 1 or 3)
            or config.cooldown_timer
            or 2
        local short_style = compact and 1 or config.short_timer_style
        for index, item in ipairs(items) do
            local tile = tile_slots[index]
            if not tile then
                tile = {}
                tile_slots[index] = tile
            end
            local pixels = (overview or item.below_stamina or item.compact_row) and 32 or 48
            local x, y, size = item.x * scale, item.y * scale, pixels * scale
            self.dx, self.dy = (item.target_x - item.x) * scale, (item.target_y - item.y) * scale
            tile.item, tile.x, tile.y, tile.size, tile.base_size = item, x, y, size, pixels
            tile.alpha = item.alpha
            self.tiles[index], self.tile_count = tile, index
            include(x - size / 2, y - size / 2, x + size / 2, y + size / 2)
            local incoming = item.phase == "incoming" or item.row.timer_kind == "incoming"
            local seconds = math.max(0, math.ceil(item.row.timer_seconds or 0))
            local large = not overview
                and short_style == 2
                and (incoming or seconds <= (config.brief_timer_limit or 10))
            local inside = large or position == 4
            if position ~= 1 and (item.phase ~= "unavailable" or overview) then
                local font_size = (large and 36 or compact and 15 or inside and 22 or 18) * scale
                local text = large and tostring(seconds)
                    or string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
                local text_x = x
                local text_y = y
                    + (inside and 0 or position == 2 and not item.below_stamina and 30 or compact and -33 or -42)
                        * scale
                local align = "center"
                if overview then
                    font_size = 16 * scale
                    text = item.phase == "unavailable" and "Unavailable" or text
                    text_x, text_y, align = ((item.overview_offset or 0) + 4) * scale, y - 5 * scale, "right"
                    local metrics = self.measure(self.font, text, font_size)
                    if not metrics or not finite(metrics.width) or metrics.width < 0 then
                        self.reason = "Cooldown overview text measurement unavailable"
                        return self
                    end
                    if metrics.width > 50 * scale then
                        font_size = font_size * 50 * scale / metrics.width
                    end
                elseif inside then
                    text_y = text_y - font_size * 0.35
                end
                local okay, why = primitive(
                    "cooldown_timer_" .. index,
                    "text",
                    text_x,
                    text_y,
                    0,
                    0,
                    text,
                    font_size,
                    "text",
                    item.alpha,
                    align
                )
                if not okay then
                    self.reason = why
                    return self
                end
            end
            -- Reserve the native badge/count area even before the first tile
            -- tick supplies a count. No count or timer value is fabricated.
            local side = (overview or compact) and "native"
                or item.below_stamina and "left"
                or (not large and config.cooldown_timer == 3 and "above" or "below")
            tile.charge_side, tile.charge_text, tile.charge_value = "native", false, nil
            if side ~= "native" then
                local cx = x + (side == "left" and -36 or 0) * scale
                local cy = y + (side == "above" and 37 or side == "left" and 0 or -37) * scale
                local font_size = 18 * scale
                local metrics = self.measure(self.font, "99", font_size)
                if
                    not metrics
                    or not finite(metrics.left)
                    or not finite(metrics.right)
                    or not finite(metrics.bottom)
                    or not finite(metrics.top)
                then
                    self.reason = "Cooldown charge measurement unavailable"
                    return self
                end
                local center = (metrics.left + metrics.right) / 2
                include(
                    cx + metrics.left - center,
                    cy - font_size * 0.35 + metrics.bottom - self.pixel,
                    cx + metrics.right - center + self.pixel,
                    cy - font_size * 0.35 + metrics.top
                )
                if item.phase == "cooldown" and item.charge_count then
                    local okay, why = primitive(
                        "cooldown_charge_" .. index,
                        "text",
                        cx,
                        cy - font_size * 0.35,
                        0,
                        0,
                        tostring(item.charge_count),
                        font_size,
                        "text",
                        item.alpha,
                        "center"
                    )
                    if not okay then
                        self.reason = why
                        return self
                    end
                    tile.charge_side, tile.charge_text, tile.charge_value = side, true, item.charge_count
                end
            end
            if tile.charge_side == "native" then
                local badge = options.native_badges and options.native_badges[index]
                if
                    not badge
                    or not finite(badge.left)
                    or not finite(badge.right)
                    or not finite(badge.bottom)
                    or not finite(badge.top)
                    or not finite(badge.icon_width)
                    or badge.icon_width <= 0
                    or not finite(badge.icon_height)
                    or badge.icon_height <= 0
                then
                    self.reason = "Native cooldown badge bounds not ready"
                    return self
                end
                tile.badge_signature = badge.signature
                include(
                    x + badge.left * size / badge.icon_width,
                    y + badge.bottom * size / badge.icon_height,
                    x + badge.right * size / badge.icon_width,
                    y + badge.top * size / badge.icon_height
                )
            else
                tile.badge_signature = nil
            end
        end
        self.dx, self.dy = 0, 0
        for index, panel in ipairs(panels or {}) do
            local okay, why = primitive(
                "cooldown_heading_" .. index,
                "text",
                (panel.left + 10) * scale,
                (panel.top - 19) * scale,
                0,
                0,
                panel.title:upper(),
                12 * scale,
                "yellow",
                1
            )
            if not okay then
                self.reason = why
                return self
            end
        end
        if divider then
            local half = (divider.half or 24) * scale
            primitive(
                "cooldown_divider",
                "rect",
                divider.x * scale - self.pixel / 2,
                divider.y * scale - half,
                self.pixel,
                half * 2,
                nil,
                0,
                "line_strong",
                divider.alpha
            )
        end
        for index = #self.tiles, self.tile_count + 1, -1 do
            self.tiles[index] = nil
        end
        for index = #self.primitives, self.used + 1, -1 do
            self.primitives[index] = nil
        end
        self.has_content = self.tile_count > 0
        if self.has_content then
            -- Move the WHOLE measured component below combat, preserving every
            -- original relative position and short-status placement choice.
            -- Original gap24 remains12 here; every original0..80 value stays
            -- operative. Do not recenter the total Icon Dock bounds: doing so
            -- would cancel its explicit separated-bar balance setting.
            local gap = (config.dock_gap or 24) * 0.5 * scale
            local center = finite(combat.left) and finite(combat.right) and (combat.left + combat.right) / 2 or 0
            local dx = compact and finite(combat.left) and combat.left - self.left or center
            local dy = combat.bottom - gap - self.top
            for _, tile in ipairs(self.tiles) do
                tile.x, tile.y = tile.x + dx, tile.y + dy
            end
            for _, p in ipairs(self.primitives) do
                p.x, p.y = p.x + dx, p.y + dy
            end
            self.left, self.right = self.left + dx, self.right + dx
            self.bottom, self.top = self.bottom + dy, self.top + dy
        else
            self.left, self.bottom, self.right, self.top = 0, 0, 0, 0
        end
        local ready = options.ready
        if options.enabled ~= false and ready and ready.visible and type(ready.text) == "string" then
            local size = 11 * scale / 0.75
            local metrics = self.measure(self.font, ready.text, size)
            if not metrics or not finite(metrics.top) then
                self.reason = "Ready notice measurement unavailable"
                return self
            end
            local center = self.has_content and (self.left + self.right) / 2
                or finite(combat.left) and finite(combat.right) and (combat.left + combat.right) / 2
                or 0
            local bottom = self.has_content and self.bottom or combat.bottom
            if not self.has_content then
                self.left, self.bottom, self.right, self.top = math.huge, math.huge, -math.huge, -math.huge
            end
            local okay, why = primitive(
                "ready",
                "text",
                center,
                bottom - 6 * self.pixel - metrics.top,
                0,
                0,
                ready.text,
                size,
                ready.tone or "yellow",
                1,
                "center"
            )
            if not okay then
                self.reason = why
                return self
            end
            self.has_content = true
        end
        self.bounds.left, self.bounds.bottom, self.bounds.right, self.bounds.top =
            self.left, self.bottom, self.right, self.top
        for index, tile in ipairs(self.tiles) do
            native_parts[index] = table.concat({
                tile.item.key,
                tile.item.phase,
                tile.x,
                tile.y,
                tile.size,
                tile.alpha,
                tile.charge_side,
                tostring(tile.charge_value),
            }, ":")
        end
        for index = #native_parts, self.tile_count + 1, -1 do
            native_parts[index] = nil
        end
        self.native_signature = table.concat(native_parts, "|")
        self.eligible, self.valid = true, true
        self.revision = self.revision + 1
        return self
    end
    return self
end
-- Retained screen-GUI labels. No timer subscription exists; consume the dock's
-- existing timer updates and change retained text only when its value changes.
local function cooldown_dock_text(b)
    local Style = mod.require("ui/style.lua")
    local style
    local function color(name, opacity)
        return style.color(name, math.floor(Style.tokens.colors[name][4] * (opacity or 1)))
    end
    local self = {}
    local gui, world, sr, font, identity, attempted, lease, ui
    local labels = {}
    local owner = {}
    local separator, separator_key
    local overview_panels = {}
    local overview_key
    local blur_material
    -- Since build 26088801, Gui.text_extents returns Vector2 bounds. The engine's own
    -- Vector3.x read them unchecked, but the LuaJIT runtime's typed Vector3 port
    -- rejects a Vector2, so read the bounds as what they are (Vector3 on older builds).
    local function text_width(min, max)
        local ok, right = pcall(sr.Vector2.x, max)
        if ok then
            return right - sr.Vector2.x(min)
        end
        return sr.Vector3.x(max) - sr.Vector3.x(min)
    end
    local function destroy_label(label)
        if not label then
            return
        end
        ui.destroy_text(gui, label.id)
        ui.destroy_text(gui, label.shadow)
        if label.backdrop then
            ui.destroy_rect(gui, label.backdrop)
        end
    end
    local function destroy_panel(panel)
        ui.destroy_rect(gui, panel.rect)
        destroy_label(panel.label)
        if panel.blur then
            ui.destroy_bitmap(gui, panel.blur)
        end
        for _, id in ipairs(panel.trim or {}) do
            ui.destroy_rect(gui, id)
        end
    end
    function self.hide()
        if not lease and not gui and not attempted and identity == nil then
            return
        end
        if lease then
            lease.release()
        end
        lease, ui, gui, world, font, identity, attempted = nil, nil, nil, nil, nil, nil, nil
        labels = {}
        overview_panels = {}
        separator, separator_key, overview_key, blur_material = nil, nil, nil, nil
    end
    function self.close()
        self.closed = true
        self.hide()
    end
    function self.draw(s, items, now, position, short_style, brief_limit, divider, panels)
        if self.closed or owner.retired then
            return
        end
        local timers = position and position ~= 1
        local charges = false
        for _, item in ipairs(items) do
            if item.phase == "cooldown" and item.charge_count then
                charges = true
                break
            end
        end
        if (not timers and not charges and not divider) or #items == 0 then
            self.hide()
            return
        end
        local current = rawget(_G, "stingray")
        if not current or not b.dock_font then
            return
        end
        if sr ~= current or identity ~= s.identity then
            self.hide()
            sr = current
            identity = s.identity
        end
        if lease and not lease.valid() then
            self.hide()
            identity = s.identity
        end
        if not gui then
            if attempted then
                return
            end
            attempted = true
            font = b.dock_font(sr)
            if not font then
                return
            end
            local A, G = sr.Application, sr.Gui
            world = A.main_world()
            for _, candidate in pairs(A.worlds() or {}) do
                if candidate ~= world then
                    world = candidate
                    break
                end
            end
            if not world then
                return
            end
            lease = cooldown_gui_pool(sr).acquire(world, owner)
            gui, ui = lease.gui, lease.api
            G = ui
            style = Style.new({ Gui = G, Vector2 = sr.Vector2, Vector3 = sr.Vector3, Color = sr.Color })
            -- Probe native HUD materials once per GUI lifetime, never each tick.
            if type(A.can_get) == "function" and type(G.bitmap) == "function" then
                for _, name in ipairs({
                    "content/ui/shared/material/gui_blur",
                    "content/ui/shared/material/blur_background",
                }) do
                    local ok, available = pcall(A.can_get, "material", name)
                    if ok and available then
                        blur_material = name
                        break
                    end
                end
            end
            local ok, material = pcall(G.material, gui, sr.IdString64.from_hex(font.material))
            if not ok or not material then
                material = G.create_material(gui, sr.IdString64.from_hex(font.material))
            end
            if
                not material
                or sr.Material.set_texture(
                        material,
                        sr.IdString64.from_hex("88BAC99B00000000"),
                        sr.IdString64.from_hex(font.atlas)
                    )
                    == false
            then
                self.hide()
                attempted = true
                return
            end
        end
        local G = ui
        lease.show()
        local width = G.resolution()
        local scale = (width or 1920) / 1920
        -- Panel geometry is retained separately from ticking labels. Only a
        -- membership/layout change rebuilds backgrounds and headings.
        local panel_parts = {}
        for _, panel in ipairs(panels or {}) do
            panel_parts[#panel_parts + 1] = panel.title
                .. ":"
                .. panel.left
                .. ":"
                .. panel.right
                .. ":"
                .. panel.bottom
                .. ":"
                .. panel.top
        end
        local origin_x, origin_y = b.dock_text_position(s, 0, 0)
        local unit_x, unit_y = b.dock_text_position(s, 1, 1)
        local panel_key = table.concat(panel_parts, "|")
            .. ":"
            .. origin_x
            .. ":"
            .. origin_y
            .. ":"
            .. unit_x
            .. ":"
            .. unit_y
        if panel_key ~= overview_key then
            for _, panel in ipairs(overview_panels) do
                destroy_panel(panel)
            end
            overview_panels = {}
            overview_key = panel_key
            for _, panel in ipairs(panels or {}) do
                local left, bottom = b.dock_text_position(s, panel.left, panel.bottom)
                local right, top = b.dock_text_position(s, panel.right, panel.top)
                local unit = math.abs(right - left) / (panel.right - panel.left)
                local size = 12 * unit
                local x, y = b.dock_text_position(s, panel.left + 10, panel.top - 19)
                local text = panel.title
                local min, max = G.text_extents(gui, text, sr.IdString64.from_hex(font.font), size)
                local extent = text_width(min, max)
                if extent > 92 * unit then
                    size = size * 92 * unit / extent
                end
                local id = G.text(
                    gui,
                    text,
                    sr.IdString64.from_hex(font.font),
                    size,
                    sr.IdString64.from_hex(font.material),
                    sr.Vector3(x, y, 951),
                    color("yellow")
                )
                local shadow = G.text(
                    gui,
                    text,
                    sr.IdString64.from_hex(font.font),
                    size,
                    sr.IdString64.from_hex(font.material),
                    sr.Vector3(x + unit, y - unit, 950),
                    color("hud_shadow")
                )
                -- Frost, tint and trim remain below native icons (0x22b).
                local panel_left, panel_bottom = math.min(left, right), math.min(bottom, top)
                local panel_width, panel_height = math.abs(right - left), math.abs(top - bottom)
                local frost
                if blur_material then
                    local ok, value = pcall(
                        G.bitmap,
                        gui,
                        blur_material,
                        sr.Vector3(panel_left, panel_bottom, 0x21f),
                        sr.Vector2(panel_width, panel_height),
                        color("text", 0.82)
                    )
                    if ok then
                        frost = value
                    end
                end
                local trim = {}
                local function line(x, y, w, h, alpha)
                    trim[#trim + 1] =
                        G.rect(gui, sr.Vector3(x, y, 0x221), sr.Vector2(w, h), color("line_strong", alpha / 255))
                end
                local edge = math.max(1, unit * 0.65)
                local arm = 6 * unit
                for _, cx in ipairs({ panel_left, panel_left + panel_width - arm }) do
                    line(cx, panel_bottom, arm, edge, 155)
                    line(cx, panel_bottom + panel_height - edge, arm, edge, 155)
                end
                for _, cx in ipairs({ panel_left, panel_left + panel_width - edge }) do
                    line(cx, panel_bottom, edge, arm, 155)
                    line(cx, panel_bottom + panel_height - arm, edge, arm, 155)
                end
                line(panel_left + 10 * unit, panel_bottom + panel_height - 26 * unit, panel_width - 20 * unit, edge, 90)
                overview_panels[#overview_panels + 1] = {
                    rect = G.rect(
                        gui,
                        sr.Vector3(panel_left, panel_bottom, 0x220),
                        sr.Vector2(panel_width, panel_height),
                        color("hud_plate", frost and 0.5 or 0.8)
                    ),
                    label = { id = id, shadow = shadow },
                    blur = frost,
                    trim = trim,
                }
            end
        end
        for i = 1, 16 do
            local item, old = items[i], labels[i]
            if item and timers and (item.phase ~= "unavailable" or position == 5) then
                local seconds = math.max(0, math.ceil(item.row.timer_seconds or 0))
                local overview = position == 5
                local incoming = item.phase == "incoming" or item.row.timer_kind == "incoming"
                local large = not overview and short_style == 2 and (incoming or seconds <= (brief_limit or 10))
                local inside = large or position == 4
                -- Compact-row tiles are 32 px: smaller timers fit them.
                local size = math.max(14, (large and 36 or item.compact_row and 15 or inside and 22 or 18) * scale)
                local text = large and tostring(seconds)
                    or string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
                local above = position == 2 and not item.below_stamina
                -- Compact row: below the 32 px tile (16 px half, 2 px gap, 15 px text).
                local x, y = b.dock_text_position(
                    s,
                    item.x,
                    item.y + (inside and 0 or above and 30 or item.compact_row and -33 or -42)
                )
                if overview then
                    local left = b.dock_text_position(s, (item.overview_offset or 0) - 46, item.y)
                    local right = b.dock_text_position(s, (item.overview_offset or 0) + 4, item.y)
                    size = 16 * math.abs(right - left) / 50
                    text = item.phase == "unavailable" and "Unavailable" or text
                    x, y = b.dock_text_position(s, (item.overview_offset or 0) + 4, item.y - 5)
                end
                if inside then
                    y = y - size * 0.35
                end
                local key = text
                    .. ":"
                    .. x
                    .. ":"
                    .. y
                    .. ":"
                    .. item.alpha
                    .. ":"
                    .. size
                    .. ":"
                    .. tostring(overview)
                if not old or old.key ~= key then
                    destroy_label(old)
                    local min, max = G.text_extents(gui, text, sr.IdString64.from_hex(font.font), size)
                    local extent = text_width(min, max)
                    if overview then
                        local left = b.dock_text_position(s, (item.overview_offset or 0) - 46, item.y)
                        local available = math.abs(x - left)
                        if extent > available then
                            size = size * available / extent
                            extent = available
                        end
                    end
                    local backdrop
                    if inside then
                        local half = (item.below_stamina or item.compact_row) and 16 or 24
                        local left, bottom = b.dock_text_position(s, item.x - half, item.y - half)
                        local right, top = b.dock_text_position(s, item.x + half, item.y + half)
                        backdrop = G.rect(
                            gui,
                            sr.Vector3(math.min(left, right), math.min(bottom, top), 949),
                            sr.Vector2(math.abs(right - left), math.abs(top - bottom)),
                            color("hud_plate", item.alpha)
                        )
                    end
                    local text_x = overview and x - extent or x - extent / 2
                    local shadow_id = G.text(
                        gui,
                        text,
                        sr.IdString64.from_hex(font.font),
                        size,
                        sr.IdString64.from_hex(font.material),
                        sr.Vector3(text_x + 2 * scale, y - 2 * scale, 950),
                        color("hud_shadow", item.alpha)
                    )
                    labels[i] = {
                        key = key,
                        backdrop = backdrop,
                        shadow = shadow_id,
                        id = G.text(
                            gui,
                            text,
                            sr.IdString64.from_hex(font.font),
                            size,
                            sr.IdString64.from_hex(font.material),
                            sr.Vector3(text_x, y, 951),
                            color("text", item.alpha)
                        ),
                    }
                end
            elseif old then
                destroy_label(old)
                labels[i] = nil
            end
            local old_charge = labels[i + 16]
            if item and item.phase == "cooldown" and item.charge_count then
                local text = tostring(item.charge_count)
                local size = 18 * scale
                if position == 5 then
                    size = 12 * math.abs(unit_x - origin_x)
                end
                local side = item.charge_side
                local x, y = b.dock_text_position(
                    s,
                    item.x + (position == 5 and 20 or side == "left" and -36 or 0),
                    item.y + (side == "above" and 37 or side == "left" and 0 or -37)
                )
                y = y - size * 0.35
                local key = text .. ":" .. x .. ":" .. y .. ":" .. item.alpha .. ":" .. size
                if not old_charge or old_charge.key ~= key then
                    destroy_label(old_charge)
                    local min, max = G.text_extents(gui, text, sr.IdString64.from_hex(font.font), size)
                    local extent = text_width(min, max)
                    local shadow = G.text(
                        gui,
                        text,
                        sr.IdString64.from_hex(font.font),
                        size,
                        sr.IdString64.from_hex(font.material),
                        sr.Vector3(x - extent / 2 + 2 * scale, y - 2 * scale, 950),
                        color("hud_shadow", item.alpha)
                    )
                    labels[i + 16] = {
                        key = key,
                        shadow = shadow,
                        id = G.text(
                            gui,
                            text,
                            sr.IdString64.from_hex(font.font),
                            size,
                            sr.IdString64.from_hex(font.material),
                            sr.Vector3(x - extent / 2, y, 951),
                            color("text", item.alpha)
                        ),
                    }
                end
            elseif old_charge then
                destroy_label(old_charge)
                labels[i + 16] = nil
            end
        end
        if divider then
            local half = divider.half or 24
            local left, bottom = b.dock_text_position(s, divider.x - 1, divider.y - half)
            local right, top = b.dock_text_position(s, divider.x + 1, divider.y + half)
            local key = left .. ":" .. bottom .. ":" .. right .. ":" .. top .. ":" .. divider.alpha
            if key ~= separator_key then
                if separator then
                    G.destroy_rect(gui, separator)
                end
                separator = G.rect(
                    gui,
                    sr.Vector3(left, bottom, 952),
                    sr.Vector2(right - left, top - bottom),
                    color("line_strong", divider.alpha)
                )
                separator_key = key
            end
        elseif separator then
            G.destroy_rect(gui, separator)
            separator, separator_key = nil, nil
        end
    end
    return self
end
-- Consume the dock's existing native snapshots; never start another reader.
local function cooldown_closed_notices(b)
    local self = {}
    local saved
    function self.restore(open)
        if
            saved
            and b.valid(saved.identity)
            and b.pointer(saved.address + 0xf0) == saved.identity + 0x24e340 + 0x146940 + 0x220
            and b.get_opacity(saved.address) == saved.applied
        then
            -- Closed native lists can already have alpha zero. Replaying that
            -- value after the open transition makes the entire menu invisible.
            b.set_opacity(saved.address, open and saved.before == 0 and 1 or saved.before)
        end
        saved = nil
    end
    function self.step(s)
        if not s or s.open ~= false then
            self.restore(s and s.open == true)
            return
        end
        local panel = s.identity + 0x24e340 + 0x146940
        local address = panel + 0x1040
        assert(b.pointer(address + 0xf0) == panel + 0x220, "Closed status list parent changed")
        if saved and saved.identity == s.identity then
            return
        end
        if not b.widgets_ready() then
            return
        end -- opacity code not run by the game yet
        self.restore()
        assert(b.valid(s.identity), "Closed status HUD changed")
        local before = assert(b.get_opacity(address), "Closed status opacity unavailable")
        b.set_opacity(address, 0)
        saved = { identity = s.identity, address = address, before = before, applied = assert(b.get_opacity(address)) }
    end
    return self
end
local function cooldown_dock(b, scope, input)
    local ffi = require("ffi")
    local init = b.fn("void (*)(uintptr_t, uint32_t)", 0x12de550)
    local create = b.fn("void (*)(uintptr_t, uint64_t, uint64_t, uint64_t, int32_t, uint32_t)", 0x16ba420)
    local tick = b.fn("void (*)(uintptr_t, float, uint32_t, uintptr_t)", 0x16baed0)
    local attach = b.fn("void (*)(uintptr_t, uintptr_t)", 0x12e42d0)
    local finish = b.fn("void (*)(uintptr_t)", 0x12e3fd0)
    local visible = b.fn("void (*)(uintptr_t, uint8_t)", 0x12e4cc0)
    local order = b.fn("void (*)(uintptr_t, uint32_t)", 0x12e0f00)
    local opacity = b.fn("void (*)(uintptr_t, float)", 0x12e07e0)
    local model = cooldown_dock_model()
    local bracket = cooldown_dock_bracket(model, radial)
    local timer_text = cooldown_dock_text(b)
    local storage, address, identity, parent, snapshot, resource_context
    local retired, drawn = {}, {}
    -- Constructor placement of each tile's count badge, so the overview can keep
    -- the game's own corner badge and backing.
    local badge_home, native_badges, bracket_options, native_tick_at = {}, {}, {}, {}
    local badge_children = { 0xa30, 0xb88, 0xce0 }
    local self = {}
    local sampled_signature, timer_text_key
    local bracket_draw_key
    local bracket_dirty = false
    local function owned()
        return address and b.valid(identity) and b.pointer(address + 0xf0) == parent
    end
    local function context_owned()
        if
            not owned()
            or resource_context == nil
            or b.pointer(parent + 0xf8) ~= resource_context
            or b.pointer(address + 0xf8) ~= resource_context
        then
            return false
        end
        for i = 1, 16 do
            local icon = address + 0x110 + (i - 1) * 0x1500
            if b.pointer(icon + 0xf0) ~= address or b.pointer(icon + 0xf8) ~= resource_context then
                return false
            end
            local badge = icon + 0x920
            if b.pointer(badge + 0xf0) ~= icon or b.pointer(badge + 0xf8) ~= resource_context then
                return false
            end
            for _, offset in ipairs(badge_children) do
                local child = icon + offset
                if b.pointer(child + 0xf0) ~= badge or b.pointer(child + 0xf8) ~= resource_context then
                    return false
                end
            end
        end
        return true
    end
    local function capture_badge(index, icon)
        local home = badge_home[index]
        local function pair(value, positive)
            return type(value) == "table"
                and type(value[1]) == "number"
                and type(value[2]) == "number"
                and value[1] == value[1]
                and value[2] == value[2]
                and math.abs(value[1]) < math.huge
                and math.abs(value[2]) < math.huge
                and (not positive or value[1] > 0 and value[2] > 0)
        end
        local okay, bounds = pcall(function()
            assert(home and pair(home.anchor) and pair(home.pivot) and pair(home.position), "Badge home unavailable")
            local badge = icon + 0x920
            assert(
                b.pointer(badge + 0xf0) == icon and b.pointer(badge + 0xf8) == resource_context,
                "Badge owner/context changed"
            )
            local size, badge_size, badge_scale = b.get(icon, "size"), b.get(badge, "size"), b.get(badge, "scale")
            assert(
                pair(size, true)
                    and pair(badge_size)
                    and badge_size[1] >= 0
                    and badge_size[2] >= 0
                    and pair(badge_scale, true),
                "Badge dimensions unavailable"
            )
            local x0 = (home.anchor[1] - 0.5) * size[1]
                + home.position[1]
                - home.pivot[1] * badge_size[1] * badge_scale[1]
            local y0 = (home.anchor[2] - 0.5) * size[2]
                + home.position[2]
                - home.pivot[2] * badge_size[2] * badge_scale[2]
            local out = {
                left = math.huge,
                bottom = math.huge,
                right = -math.huge,
                top = -math.huge,
                icon_width = size[1],
                icon_height = size[2],
            }
            -- These are the exact native backing/text children already used by
            -- the Original badge suppression. Local widget fields avoid stale
            -- derived matrices during a just-created tile's first layout.
            for _, offset in ipairs(badge_children) do
                local child = icon + offset
                assert(
                    b.pointer(child + 0xf0) == badge and b.pointer(child + 0xf8) == resource_context,
                    "Badge child owner/context changed"
                )
                local child_size, anchor, pivot, position, scale =
                    b.get(child, "size"),
                    b.get(child, "anchor"),
                    b.get(child, "pivot"),
                    b.get(child, "position"),
                    b.get(child, "scale")
                assert(
                    pair(child_size, true) and pair(anchor) and pair(pivot) and pair(position) and pair(scale, true),
                    "Badge child geometry unavailable"
                )
                local left = x0
                    + (anchor[1] * badge_size[1] + position[1] - pivot[1] * child_size[1] * scale[1])
                        * badge_scale[1]
                local bottom = y0
                    + (anchor[2] * badge_size[2] + position[2] - pivot[2] * child_size[2] * scale[2])
                        * badge_scale[2]
                out.left, out.bottom = math.min(out.left, left), math.min(out.bottom, bottom)
                out.right, out.top =
                    math.max(out.right, left + child_size[1] * scale[1] * badge_scale[1]),
                    math.max(out.top, bottom + child_size[2] * scale[2] * badge_scale[2])
            end
            out.signature =
                table.concat({ out.left, out.bottom, out.right, out.top, out.icon_width, out.icon_height }, ":")
            return out
        end)
        native_badges[index] = okay and bounds or nil
    end
    local function hide_native()
        if not self.shown and not bracket_dirty then
            return true
        end
        local checked, ours = pcall(context_owned)
        if not checked or not ours then
            -- A detached owned allocation is retired; an unknown or still
            -- linked old-context widget must retain every restoration record.
            local read, link = pcall(b.read_u64, address and address + 0xf0)
            if read and link == 0 then
                return true
            end
            return false, "Cooldown native owner/context unavailable for hide"
        end
        for i = 1, 16 do
            if drawn[i] then
                visible(address + 0x110 + (i - 1) * 0x1500, 0)
            end
        end
        visible(address, 0)
        return true
    end
    function self.hide()
        if not snapshot and not self.shown and not bracket_dirty and #model.order == 0 then
            return true
        end
        local hidden, why = hide_native()
        if not hidden then
            return false, why
        end
        timer_text.hide()
        model.reset()
        snapshot = nil
        drawn = {}
        self.shown = false
        sampled_signature = nil
        bracket_dirty = false
        return true
    end
    function self.sample(s, now)
        if self.closed then
            return
        end
        snapshot = s
        local parts = {
            tostring(s and s.identity),
            tostring(s and s.dock_y),
            tostring(radial.full_color),
            tostring(radial.cooldown_timer),
            tostring(radial.cooldown_display),
        }
        for _, row in ipairs(s and s.rows or {}) do
            if cooldown_dock_timed(row, radial.track_unavailable) then
                parts[#parts + 1] = tostring(row.entry)
                    .. ":"
                    .. tostring(row.kind)
                    .. ":"
                    .. tostring(row.unavailable and "unavailable" or row.timer_kind)
            end
        end
        if s and s.stamina_bounds then
            local bar = s.stamina_bounds
            parts[#parts + 1] = bar.left .. ":" .. bar.right .. ":" .. bar.bottom .. ":" .. bar.top
        end
        if s and s.health_bounds then
            local bar = s.health_bounds
            parts[#parts + 1] = bar.left .. ":" .. bar.bottom
        end
        local signature = table.concat(parts, "|")
        if signature ~= sampled_signature or not self.next_sample or now >= self.next_sample then
            model.sample(s, now, radial.track_unavailable)
            self.next_sample = now + 250
        end
        if signature ~= sampled_signature then
            sampled_signature = signature
            self.animate_until = now + 350
            self.settled = false
        end
    end
    function self.draw(now, hud_visible, placed)
        if self.closed then
            return
        end
        -- Same HUD address/parent does not prove the same resource context.
        -- Fence before the idle return and before any existing-node setter.
        if
            address
            and snapshot
            and identity == snapshot.identity
            and parent == snapshot.dock_parent
            and b.read_u64(address + 0xf0) ~= 0
        then
            local checked, ours = pcall(context_owned)
            if not checked or not ours then
                return false, "Cooldown resource context changed; cleanup required"
            end
        end
        local display_style = radial.cooldown_display or 1
        if self.display_style ~= display_style then
            -- A style owns its whole retained GUI, including headings/panels.
            -- Retire it explicitly before the idle gate or timer-Off paths can
            -- skip label drawing; the new style starts with a clean GUI.
            if not placed then
                timer_text.hide()
            end
            self.timer_error = nil
            timer_text_key = nil
            self.display_style = display_style
            self.settled = false
        end
        local placement_key = placed and placed.key or "legacy"
        local placement_changed = placement_key ~= bracket_draw_key
        if placement_changed then
            self.settled = false
        end
        if hud_visible == false then
            local hidden, why = hide_native()
            if not hidden then
                return false, why
            end
            timer_text.hide()
            self.shown = false
            self.settled = false
            return true
        end
        local timer_due = not self.next_tick or now >= self.next_tick
        if
            self.animate_until
            and now > self.animate_until
            and self.shown
            and self.settled
            and not timer_due
            and not placement_changed
        then
            if not placed or owned() then
                return true
            end
        end
        local s = snapshot
        if not s or not s.dock_parent then
            return self.hide()
        end
        if #model.order == 0 then
            return self.hide()
        end
        if address and (identity ~= s.identity or parent ~= s.dock_parent or not owned()) then
            if b.read_u64(address + 0xf0) ~= 0 then
                assert(#retired < 8, "Too many cooldown dock HUD generations; restart game")
                retired[#retired + 1] = storage
            end
            address, storage, resource_context = nil, nil, nil
            native_badges, native_tick_at = {}, {}
            drawn = {}
            self.shown = false
        end
        local overview = radial.cooldown_display == 2
        -- Compact row needs the health bar; without it the normal dock is used.
        local row = radial.cooldown_display == 3 and s.health_bounds or nil
        local items, divider, panels
        if placed then
            items = placed.items
        else
            items, divider, panels = model.layout(
                now,
                s.dock_y,
                overview,
                radial.short_status_placement,
                radial.brief_timer_limit,
                s.dock_below_y,
                radial.balance_separated_dock,
                s.stamina_bounds,
                row
            )
        end
        local label_key = tostring(s.identity)
            .. ":"
            .. tostring(radial.cooldown_timer)
            .. ":"
            .. tostring(overview)
            .. ":"
            .. tostring(row ~= nil)
        -- Compact row: timers below the tiles (or off), never the large style; no
        -- inside backdrop, so the native charge badge stays uncovered.
        local timer_position = overview and 5
            or row and (radial.cooldown_timer == 1 and 1 or 3)
            or radial.cooldown_timer
        local timer_style = row and 1 or radial.short_timer_style
        if timer_text_key ~= label_key then
            timer_text_key = label_key
            self.timer_error = nil
        end
        local function draw_labels()
            if placed then
                return
            end
            if not self.timer_error then
                local ok, why = pcall(
                    timer_text.draw,
                    s,
                    items,
                    now,
                    timer_position,
                    timer_style,
                    radial.brief_timer_limit,
                    divider,
                    panels
                )
                if not ok then
                    timer_text.hide()
                    self.timer_error = tostring(why)
                end
            end
        end
        local changed = not self.shown or timer_due or placement_changed
        for i = 1, 16 do
            local item, old = items[i], drawn[i]
            if item then
                local tile = placed and placed.packet.tiles[i]
                local item_x, item_y = tile and tile.native_x or item.x, tile and tile.native_y or item.y
                local item_alpha = item.alpha * (placed and placed.opacity or 1)
                local signature = item.key
                    .. ":"
                    .. item.phase
                    .. ":"
                    .. tostring(overview)
                    .. ":"
                    .. tostring(item.below_stamina)
                    .. ":"
                    .. tostring(item.compact_row)
                if
                    not old
                    or old.signature ~= signature
                    or old.x ~= item_x
                    or old.y ~= item_y
                    or old.alpha ~= item_alpha
                then
                    changed = true
                end
            elseif old then
                changed = true
            end
        end
        self.settled = true
        for _, item in ipairs(items) do
            if item.x ~= item.target_x or item.y ~= item.target_y or item.alpha < 1 then
                self.settled = false
            end
        end
        if not changed then
            draw_labels()
            return true
        end
        -- Build the dock only once all of its game code may run: cards whose code
        -- the game has not executed yet wait instead of failing mid-construction.
        if
            not address
            and not (
                scope.context_ready()
                and b.widgets_ready()
                and b.callable(init, create, tick, attach, finish, visible, order, opacity)
            )
        then
            return
        end
        local expected_context = b.pointer(s.dock_parent + 0xf8)
        if expected_context == nil then
            return false, "Cooldown parent resource context unavailable"
        end
        scope.context_scope(s.dock_parent, function(resource)
            assert(
                resource == expected_context and b.pointer(s.dock_parent + 0xf8) == resource,
                "Cooldown parent resource context changed"
            )
            if address then
                assert(context_owned(), "Cooldown existing resource context changed")
            end
            -- A later guard/native failure still leaves an external placement
            -- to restore. Set this before the first owned native mutation.
            if placed then
                bracket_dirty = true
            end
            if not address then
                storage = ffi.new("uint8_t[?]", 0x15150)
                address = math.floor((tonumber(ffi.cast("uintptr_t", storage)) + 31) / 16) * 16
                identity, parent, resource_context = s.identity, s.dock_parent, resource
                init(address, 1)
                b.set(address, "size", { 0, 0 })
                b.set(address, "anchor", { 0.5, 0 })
                b.set(address, "pivot", { 0.5, 0 })
                b.set(address, "position", { 0, 0 })
                assert(b.pointer(address + 0xf8) == resource, "Dock resource context mismatch")
                for i = 1, 16 do
                    local icon = address + 0x110 + (i - 1) * 0x1500
                    create(icon, 0ULL, 0ULL, 0ULL, 0x22b, 0)
                    assert(b.pointer(icon + 0xf8) == resource, "Cooldown child resource context mismatch")
                    local badge = icon + 0x920
                    local anchor, pivot, position =
                        b.get(badge, "anchor"), b.get(badge, "pivot"), b.get(badge, "position")
                    badge_home[i] = anchor
                            and pivot
                            and position
                            and { anchor = anchor, pivot = pivot, position = position }
                        or nil
                    local size = assert(b.get(icon, "size"), "Native tile size unavailable")
                    assert(size[1] > 0 and size[2] > 0, "Invalid native tile dimensions")
                    local pixels = (overview or row) and 32 or 48
                    b.set(icon, "scale", {
                        (placed and placed.packet.tiles[i] and placed.packet.tiles[i].native_width or pixels) / size[1],
                        (placed and placed.packet.tiles[i] and placed.packet.tiles[i].native_height or pixels)
                            / size[2],
                    })
                    b.set(icon, "pivot", { 0.5, 0.5 })
                    b.set(icon, "anchor", { 0, 0 })
                    order(icon, 0x22b)
                    attach(address, icon)
                    finish(address)
                end
                attach(parent, address)
                finish(parent)
            end
            assert(context_owned(), "Cooldown dock ownership/context mismatch")
            for i = 1, 16 do
                local icon = address + 0x110 + (i - 1) * 0x1500
                assert(b.pointer(icon + 0xf0) == address, "Cooldown dock child ownership changed")
                local item = items[i]
                local old = drawn[i]
                if item then
                    local tile = placed and placed.packet.tiles[i]
                    local item_x, item_y = tile and tile.native_x or item.x, tile and tile.native_y or item.y
                    local item_alpha = item.alpha * (placed and placed.opacity or 1)
                    local signature = item.key
                        .. ":"
                        .. item.phase
                        .. ":"
                        .. tostring(overview)
                        .. ":"
                        .. tostring(item.below_stamina)
                        .. ":"
                        .. tostring(item.compact_row)
                    local denominator = old and old.denominator
                    local large = not item.compact_row
                        and radial.short_timer_style == 2
                        and (
                            item.phase == "incoming"
                            or (item.row.timer_seconds or math.huge) <= (radial.brief_timer_limit or 10)
                        )
                    -- The overview keeps the native corner badge; other layouts move it aside.
                    local charge_side = tile and tile.charge_side
                        or (overview or item.compact_row) and "native"
                        or item.below_stamina and "left"
                        or (not large and radial.cooldown_timer == 3 and "above" or "below")
                    local charge_key = signature .. ":" .. charge_side
                    if (not old and item.below_stamina) or (old and old.signature ~= signature) then
                        local size = assert(b.get(icon, "size"))
                        local pixels = (overview or item.below_stamina or item.compact_row) and 32 or 48
                        b.set(icon, "scale", {
                            (tile and tile.native_width or pixels) / size[1],
                            (tile and tile.native_height or pixels) / size[2],
                        })
                    end
                    if timer_due or not old or old.signature ~= signature then
                        local row = item.row
                        assert(row and row.dock_payload and row.entry, "Native dock record unavailable")
                        ffi.cast("uint32_t *", icon + 0x14b8)[0] = row.entry
                        tick(
                            icon,
                            native_tick_at[i] == now and 0 or 0.25,
                            item.phase == "incoming" and 3 or item.phase == "unavailable" and 5 or 4,
                            row.dock_payload
                        )
                        native_tick_at[i], self.next_tick = now, now + 250
                        -- Native initialization can reset the span. Restore the game's
                        -- original denominator afterwards, then refresh without elapsed time.
                        if item.phase ~= "unavailable" then
                            denominator =
                                assert(b.read(row.dock_source + 0x14c4, 4), "Native tile timer span unavailable")
                            if not old or old.signature ~= signature or old.denominator ~= denominator then
                                ffi.copy(ffi.cast("void *", icon + 0x14c4), denominator, 4)
                                tick(
                                    icon,
                                    0,
                                    item.phase == "incoming" and 3 or item.phase == "unavailable" and 5 or 4,
                                    row.dock_payload
                                )
                            end
                            local span = tonumber(ffi.cast("float *", icon + 0x14c4)[0])
                            span = span == span and span > 0 and span <= 86400 and span or 0
                            item.cooldown_span = math.max(span, item.row.timer_seconds, item.cooldown_span or 0)
                            if item.source then
                                item.source.cooldown_span = item.cooldown_span
                            end
                        end
                    end
                    if timer_due or not old or old.charge_key ~= charge_key then
                        -- Native tile constructor owns the count group at +920,
                        -- its two backing sprites and the count text at +CE0.
                        local badge = icon + 0x920
                        assert(b.pointer(badge + 0xf0) == icon, "Dock charge group ownership changed")
                        local count = tonumber(ffi.cast("uint32_t *", icon + 0x14bc)[0])
                        local known_count = count > 0 and count <= 99 and count or nil
                        item.native_charge_count = known_count
                        if item.source then
                            item.source.native_charge_count = known_count
                            -- Shared labels were rendered before this native
                            -- tick. A changed count must trigger Root's atomic
                            -- Original rollback, not hide the accurate badge.
                            if tile.charge_text and count ~= tile.charge_value then
                                item.source.charge_count = item.phase == "cooldown" and known_count or nil
                                error("Cooldown charge count changed during Bracket layout")
                            end
                        end
                        if charge_side == "native" then
                            -- Constructor placement; the native tick shows and styles
                            -- the badge, its backing and the count itself.
                            local home = badge_home[i]
                            if home and (not old or old.charge_key ~= charge_key) then
                                b.set(badge, "anchor", home.anchor)
                                b.set(badge, "pivot", home.pivot)
                                b.set(badge, "position", home.position)
                            end
                        else
                            if not old or old.charge_key ~= charge_key or old.charge_count ~= count then
                                b.set(badge, "anchor", { 0.5, 0.5 })
                                b.set(badge, "pivot", { 0.5, 0.5 })
                                b.set(
                                    badge,
                                    "position",
                                    charge_side == "left" and { -36, 0 } or { 0, charge_side == "above" and 37 or -37 }
                                )
                            end
                            -- Native tick recolors/reveals these children. Suppress
                            -- AFTER it runs, at its existing bounded 4 Hz cadence.
                            opacity(icon + 0xa30, 0)
                            opacity(icon + 0xb88, 0)
                            opacity(icon + 0xce0, 0)
                        end
                        -- Native count cache, witnessed by 183AEF1's count-label
                        -- formatter. Read only our constructed/owned tile. No ASS
                        -- label is drawn while the native badge shows the count.
                        item.charge_count = charge_side ~= "native"
                                and item.phase == "cooldown"
                                and count > 0
                                and count <= 99
                                and count
                            or nil
                        item.charge_side = charge_side
                        if item.source then
                            item.source.charge_count, item.source.charge_side = item.charge_count, charge_side
                            item.source.native_charge_count = known_count
                        end
                        if old then
                            old.charge_count = count
                        end
                        capture_badge(i, icon)
                        if
                            tile
                            and tile.charge_side == "native"
                            and (not native_badges[i] or native_badges[i].signature ~= tile.badge_signature)
                        then
                            error("Cooldown native badge bounds changed during Bracket layout")
                        end
                    end
                    local size = assert(b.get(icon, "size"), "Native tile size unavailable")
                    assert(size[1] > 0 and size[2] > 0, "Invalid native tile dimensions")
                    local pixels = (overview or item.below_stamina or item.compact_row) and 32 or 48
                    b.set(icon, "scale", {
                        (tile and tile.native_width or pixels) / size[1],
                        (tile and tile.native_height or pixels) / size[2],
                    })
                    local position = timer_due and b.get(icon, "position") or nil
                    if
                        not old
                        or old.x ~= item_x
                        or old.y ~= item_y
                        or (position and (position[1] ~= item_x or position[2] ~= item_y))
                    then
                        b.set(icon, "position", { item_x, item_y })
                    end
                    if not old or old.alpha ~= item_alpha then
                        opacity(icon, item_alpha)
                    end
                    -- Hiding retains the draw cache but hides its children too.
                    -- Restore each current child before revealing their root.
                    if not old or not self.shown then
                        visible(icon, 1)
                    end
                    local retained = old or {}
                    retained.signature, retained.x, retained.y = signature, item_x, item_y
                    retained.alpha, retained.denominator = item_alpha, denominator
                    retained.charge_key = charge_key
                    retained.charge_count = tonumber(ffi.cast("uint32_t *", icon + 0x14bc)[0])
                    drawn[i] = retained
                elseif old then
                    visible(icon, 0)
                    drawn[i] = nil
                elseif not drawn.initialized then
                    visible(icon, 0)
                end
            end
            -- The tick branch advances its own deadline. Moving/revealing an
            -- already sampled icon must not postpone native timer refreshes.
            drawn.initialized = true
            if not self.shown then
                visible(address, 1)
                self.shown = true
            end
        end)
        bracket_draw_key = placement_key
        if not placed then
            bracket_dirty = false
        end
        draw_labels()
        return true
    end
    function self.bracket_layout(now, options)
        options = options or {}
        if
            self.closed
            or (
                options.enabled ~= false
                and (
                    not snapshot
                    or snapshot.open ~= false
                    or snapshot.hud_visible ~= true
                    or snapshot.identity ~= options.identity
                )
            )
        then
            bracket.valid, bracket.eligible, bracket.reason = false, false, "Cooldown snapshot not eligible for Bracket"
            return bracket
        end
        if address then
            local checked, ours = pcall(context_owned)
            if not checked or not ours then
                bracket.valid, bracket.eligible, bracket.reason =
                    false, false, "Cooldown retained resource context changed"
                return bracket
            end
        end
        for key in pairs(bracket_options) do
            bracket_options[key] = nil
        end
        for key, value in pairs(options) do
            bracket_options[key] = value
        end
        bracket_options.native_badges = native_badges
        return bracket.update(now, bracket_options)
    end
    function self.draw_bracket(now, packet, anchor, alpha)
        local function finite(value)
            return type(value) == "number" and value == value and math.abs(value) < math.huge
        end
        if
            self.closed
            or packet ~= bracket
            or not packet.valid
            or not packet.eligible
            or packet.sourceRevision ~= model.revision
            or packet.generation == nil
            or type(anchor) ~= "table"
            or not finite(anchor.x)
            or not finite(anchor.y)
            or not finite(alpha)
            or alpha < 0
            or alpha > 1
        then
            return false, "Cooldown Bracket packet is stale or invalid"
        end
        if not packet.has_content then
            local called, okay, why = pcall(self.hide)
            return called and okay == true, not called and tostring(okay) or why
        end
        local s = snapshot
        if
            not s
            or s.identity ~= packet.identity
            or s.open ~= false
            or s.hud_visible ~= true
            or not finite(s.identity)
            or s.dock_parent ~= s.identity + 0x258
        then
            return false, "Cooldown Bracket native owner unavailable"
        end
        local checked, ready = pcall(function()
            return b.valid(s.identity) == true and scope.context_ready() == true
        end)
        if not checked or not ready then
            return false, "Cooldown Bracket native context unavailable"
        end
        if address then
            local checked, ours = pcall(context_owned)
            if not checked or not ours then
                return false, "Cooldown Bracket retained resource context changed"
            end
        end
        -- Recover parent-local units from the proven native X/Z screen mapping,
        -- not the parent's width/viewport ratio (crosshair parents can be1x1).
        local okay, ox, oy, a, d = pcall(function()
            local x0, y0 = b.dock_text_position(s, 0, 0)
            local x1, y1 = b.dock_text_position(s, 1, 0)
            local x2, y2 = b.dock_text_position(s, 0, 1)
            assert(
                finite(x0) and finite(y0) and finite(x1) and finite(y1) and finite(x2) and finite(y2),
                "Cooldown parent transform unavailable"
            )
            local sx, sy = x1 - x0, y2 - y0
            local tolerance = math.max(1, math.abs(sx), math.abs(sy)) * 0.000001
            assert(
                sx > 0.000001 and sy > 0.000001 and math.abs(y1 - y0) <= tolerance and math.abs(x2 - x0) <= tolerance,
                "Unsupported cooldown parent transform"
            )
            return x0, y0, sx, sy
        end)
        if not okay then
            return false, tostring(ox)
        end
        local placed = { packet = packet, items = {}, opacity = alpha }
        placed.key = table.concat(
            { "bracket", packet.native_signature, packet.scale, anchor.x, anchor.y, alpha, ox, oy, a, d },
            ":"
        )
        for index, tile in ipairs(packet.tiles) do
            if not finite(tile.x) or not finite(tile.y) or not finite(tile.size) or tile.size <= 0 then
                return false, "Invalid cooldown physical geometry"
            end
            tile.native_x, tile.native_y = (anchor.x + tile.x - ox) / a, (anchor.y + tile.y - oy) / d
            tile.native_width, tile.native_height = tile.size / a, tile.size / d
            placed.items[index] = tile.item
        end
        local called, accepted, draw_reason = pcall(self.draw, now, true, placed)
        if not called or accepted ~= true then
            -- A partially applied placement must force the legacy rollback to
            -- redraw, even if the250ms native timer cadence is not due yet.
            bracket_draw_key, self.settled = nil, false
            return false, called and (draw_reason or "Cooldown Bracket native draw not ready") or tostring(accepted)
        end
        -- Root has already rendered the complete shared-screen packet. Retire
        -- the old label GUI only AFTER owned native icon placement succeeds.
        local hidden, why = pcall(timer_text.hide)
        if not hidden then
            bracket_draw_key, self.settled = nil, false
            return false, tostring(why)
        end
        return true
    end
    function self.clear_bracket(now, hud_visible)
        if self.closed then
            return false, "Cooldown dock is closed"
        end
        -- Unknown/cold constructors may have refused BEFORE any native write.
        -- That normal readiness state has no external placement to restore.
        if not bracket_dirty then
            return true
        end
        -- Invalidate ONLY presenter caches. The original model/tween state has
        -- never been converted to physical coordinates and remains authoritative.
        bracket_draw_key, self.settled = nil, false
        local s = snapshot
        if address then
            local read, link = pcall(b.read_u64, address + 0xf0)
            if read and link == 0 then
                bracket_dirty, self.shown = false, false
                return true
            end
        end
        if #model.order == 0 then
            local okay, why = pcall(function()
                local hidden, reason = hide_native()
                assert(hidden, reason)
                timer_text.hide()
                self.shown = false
                bracket_dirty = false
            end)
            return okay, not okay and tostring(why) or nil
        end
        local checked, ready = pcall(function()
            return s
                and s.dock_parent == s.identity + 0x258
                and b.valid(s.identity) == true
                and scope.context_ready() == true
        end)
        if not checked or not ready then
            return false, "Cooldown rollback native owner unavailable"
        end
        local checked, ours = pcall(context_owned)
        if not checked or not ours then
            return false, "Cooldown rollback retained resource context changed"
        end
        local called, accepted, draw_reason = pcall(self.draw, now, true)
        if not called or accepted ~= true then
            bracket_draw_key, self.settled = nil, false
            return false, called and (draw_reason or "Cooldown rollback native draw not ready") or tostring(accepted)
        end
        if hud_visible == false then
            local called, hidden, why = pcall(self.draw, now, false)
            if not called or hidden ~= true then
                return false, called and why or tostring(hidden)
            end
        end
        return true
    end
    function self.close()
        -- Closing is terminal. Old update/menu closures must never resurrect
        -- a GUI after loader cleanup has relinquished this owner.
        self.closed = true
        if address then
            local read, link = pcall(b.read_u64, address + 0xf0)
            if not read or link == nil then
                return false, "Cooldown native attachment unknown; cleanup pending"
            end
            if link ~= 0 then
                -- release_owned_ui validates parent links, but cannot prove the
                -- resource context. Never let its native destructor touch a
                -- still-linked old-context allocation. Retain it for retry.
                local checked, ours = pcall(context_owned)
                if not checked or not ours then
                    return false, "Cooldown resource context changed; cleanup pending"
                end
            end
        end
        timer_text.close()
        local hidden, hide_reason = self.hide()
        if hidden ~= true then
            return false, hide_reason
        end
        local ok, why = b.release_owned_ui(storage, address, identity, parent, retired)
        if not ok then
            return false, why
        end
        storage, address, identity, parent, resource_context = nil, nil, nil, nil, nil
        bracket_dirty = false
        for i = #retired, 1, -1 do
            retired[i] = nil
        end
        return true
    end
    return self
end

return {
    cooldown_dock_timed = cooldown_dock_timed,
    cooldown_dock_model = cooldown_dock_model,
    cooldown_dock_bracket = cooldown_dock_bracket,
    cooldown_dock_text = cooldown_dock_text,
    cooldown_closed_notices = cooldown_closed_notices,
    cooldown_dock = cooldown_dock,
}
