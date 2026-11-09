local M = {}
local fire =
    { SEMI = "3efff09cd12fb89a", AUTO = "6115051c9558c50e", BURST = "131742904d846798", VOLLEY = "16413ee2e6725687" }
local ammo = { FLAK = "f8ede5f922c05cb6", APHET = "9dcc0312a14e11e6" }
local rpm = { "52bbfc5a70359393", "c7546fc9c7b6db4e", "f03c671b15d01a6b" }
local zoom = { "6be28cced767bb52", "46271d0b4ce4136c", "a2ab43e85546f79a" }
-- Icon texture IDs as uint64 cdata, built once from the hex names above.
local asset_ids = {}
do
    local ffi = require("ffi")
    for _, group in ipairs({ fire, ammo, rpm, zoom }) do
        for _, hex in pairs(group) do
            asset_ids[hex] = ffi.new("uint64_t", tonumber(hex:sub(1, 8), 16)) * 4294967296ULL + tonumber(hex:sub(9), 16)
        end
    end
end
-- The weapon option kind behind each icon (weapon settings +0x350.., as in
-- weapon_status_reader.lua): HUD+'s option cells report the same numbers.
local role_kinds = { fire_mode = { 3 }, rpm = { 2 }, ammo_mode = { 8, 11 }, zoom = { 1 } }
-- `shown`: option kinds another HUD already draws; their icons are left out.
function M.icons(model, shown)
    local result = {}
    if not model then
        return result
    end
    if shown then
        local kept = M.icons(model)
        for _, item in ipairs(kept) do
            local covered = false
            for _, kind in ipairs(role_kinds[item.role]) do
                covered = covered or shown[kind] == true
            end
            if not covered then
                result[#result + 1] = item
            end
        end
        return result
    end
    local controls = model.changeable
    if type(controls) ~= "table" then
        return result
    end
    if controls.fire_mode == true and fire[model.fire_mode] then
        result[#result + 1] = { role = "fire_mode", asset = fire[model.fire_mode], value = model.fire_mode }
    end
    local index = model.rpm_index
    if
        controls.rpm == true
        and model.rpm
        and type(index) == "number"
        and index % 1 == 0
        and index >= 0
        and index <= 2
    then
        result[#result + 1] = { role = "rpm", asset = rpm[index + 1], value = model.rpm }
    end
    if controls.ammo_mode == true and ammo[model.ammo_mode] then
        result[#result + 1] = { role = "ammo_mode", asset = ammo[model.ammo_mode], value = model.ammo_mode }
    end
    local zi = model.zoom_index
    if controls.zoom == true and model.zoom and type(zi) == "number" and zi % 1 == 0 and zi >= 0 and zi <= 2 then
        result[#result + 1] = { role = "zoom", asset = zoom[zi + 1], value = model.zoom }
    end
    return result
end
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
-- Physical pixels, bottom-left/Y up; uses the original icon choices only.
function M.metrics(model, edge, gap, out)
    if not model then
        return nil, "Weapon sample unavailable"
    end
    if not finite(edge) or edge <= 0 or edge > 10000 or not finite(gap) or gap < 0 or gap > 10000 then
        return nil, "Invalid weapon icon dimensions"
    end
    out = out or {}
    local count = #M.icons(model)
    out.ready, out.count, out.edge, out.gap = true, count, edge, gap
    out.width, out.height = count > 0 and count * edge + (count - 1) * gap or 0, count > 0 and edge or 0
    return out
end
function M.new(b, scope)
    local Style = mod.require("ui/style.lua")
    local function color(sr, name, opacity)
        local c = Style.tokens.colors[name]
        return sr.Color(math.floor(c[4] * (opacity or 1)), c[1], c[2], c[3])
    end
    local ffi = require("ffi")
    local function call(signature, offset)
        return b.fn(signature, offset)
    end
    local init = call("void (*)(uintptr_t,uint32_t)", 0x12de550)
    local sprite = call("void (*)(uintptr_t)", 0x12d67c0)
    local asset = call("void (*)(uintptr_t,uint64_t,uint8_t)", 0x12e7510)
    local attach = call("void (*)(uintptr_t,uintptr_t)", 0x12e42d0)
    local finish = call("void (*)(uintptr_t)", 0x12e3fd0)
    local opacity = call("void (*)(uintptr_t,float)", 0x12e07e0)
    local order = call("void (*)(uintptr_t,uint32_t)", 0x12e0f00)
    local visible = call("void (*)(uintptr_t,uint8_t)", 0x12e4cc0)
    local uv = call("void (*)(uintptr_t, NSR_vec2, NSR_vec2)", 0x12d6c00)
    -- The icon textures carry a wide empty margin; show their centre so each glyph
    -- fills more of its tile (crop per side, in texture UV units).
    local zoom_crop = 0.15
    local uv_min, uv_max =
        ffi.new("NSR_vec2", { zoom_crop, zoom_crop }), ffi.new("NSR_vec2", { 1 - zoom_crop, 1 - zoom_crop })
    local storage, address, identity, parent, key, resource_context, owned_width, owned_height
    local size = 0x690
    -- Largest icon edge and spacing in HUD pixels (bottom-left pivot, Y up); on the
    -- weapon row the icons shrink to fit its height.
    local icon_size, icon_gap = 48, 10
    local self = { status = "closed", icons = {} }
    local function owned()
        return address
            and b.valid(identity)
            and b.pointer(address + 0xf0) == parent
            and b.pointer(address + 0xf8) == resource_context
            and b.pointer(parent + 0xf8) == resource_context
    end
    local function bounds()
        assert(
            ffi.string(ffi.cast("const char *", address - 16), 16) == string.rep("\165", 16),
            "Weapon status prefix overwritten"
        )
        assert(
            ffi.string(ffi.cast("const char *", address + size), 16) == string.rep("\165", 16),
            "Weapon status suffix overwritten"
        )
    end
    -- The legacy row has one token backing. Its screen GUI does not inherit
    -- native widget fades, so pass the already inherited weapon alpha once.
    -- Bracket is unboxed and never acquires this GUI.
    local panel = {}
    local function panel_hide()
        if not panel.lease then
            return true
        end
        if panel.lease then
            local called, accepted, why = pcall(panel.lease.release)
            if not called or accepted == false then
                return false, tostring(called and why or accepted)
            end
        end
        panel = {}
        return true
    end
    local function panel_draw(v, x0, y0, x1, y1, seam, native_alpha)
        local sr = rawget(_G, "stingray")
        if not sr then
            return
        end
        if panel.lease and not panel.lease.valid() then
            local closed, why = panel_hide()
            assert(closed, why)
        end
        if not panel.lease then
            local A = sr.Application
            local world = A.main_world()
            for _, candidate in pairs(A.worlds() or {}) do
                if candidate ~= world then
                    world = candidate
                    break
                end
            end
            if not world then
                return
            end
            panel.owner = {}
            panel.lease = cooldown_gui_pool(sr, "DBFWeaponStripGuiPool").acquire(world, panel.owner)
            panel.gui, panel.ui, panel.ids = panel.lease.gui, panel.lease.api, {}
        end
        local G, gui = panel.ui, panel.gui
        for _, item in ipairs(panel.ids) do
            G["destroy_" .. item[1]](gui, item[2])
        end
        panel.ids = {}
        -- Weapon HUD space (Y up) to screen GUI space through the container matrix.
        local function screen(x, y)
            return v[1] * x + v[3] * y + v[5], v[2] * x + v[4] * y + v[6]
        end
        local ax, ay = screen(x0, y0)
        local bx, by = screen(x1, y1)
        local left, bottom = math.min(ax, bx), math.min(ay, by)
        local width, height = math.abs(bx - ax), math.abs(by - ay)
        local unit = math.abs(bx - ax) / (x1 - x0)
        local function add(kind, id)
            if id ~= nil and id ~= false then
                panel.ids[#panel.ids + 1] = { kind, id }
            end
        end
        add(
            "rect",
            G.rect(
                gui,
                sr.Vector3(left, bottom, 0x220),
                sr.Vector2(width, height),
                color(sr, "hud_plate", native_alpha)
            )
        )
        local edge = math.max(1, unit * 0.65)
        -- Butted against the native box, the left edge is a seam marked by a vertical
        -- separator inset from top and bottom. No corner trims (they read as clutter
        -- once the panel continues the native row).
        if seam then
            local inset = math.min(height / 4, 8 * unit)
            add(
                "rect",
                G.rect(
                    gui,
                    sr.Vector3(left - edge / 2, bottom + inset, 0x221),
                    sr.Vector2(edge, height - 2 * inset),
                    color(sr, "line_strong", native_alpha)
                )
            )
        end
        panel.lease.show()
    end
    function self.close()
        local closed, reason = panel_hide()
        if not closed then
            return false, reason
        end
        if not address then
            return true
        end
        if
            b.valid(identity)
            and b.pointer(address + 0xf0) == parent
            and (b.pointer(address + 0xf8) ~= resource_context or b.pointer(parent + 0xf8) ~= resource_context)
        then
            return false, "Weapon UI resource context changed; cleanup pending"
        end
        local ok, why = b.release_owned_ui(storage, address, identity, parent, {})
        if not ok then
            self.status = why
            return false, why
        end
        bounds()
        storage, address, identity, parent, key, resource_context, owned_width, owned_height =
            nil, nil, nil, nil, nil, nil, nil, nil
        self.status = "closed"
        return true
    end
    function self.hide()
        local closed, reason = panel_hide()
        if not closed then
            return false, reason
        end
        if address and not owned() then
            return self.close()
        end
        if owned() then
            visible(address, 0)
        end
        key = nil
        self.status = "hidden"
        return closed, reason
    end
    local node_floats, matrix_lanes = ffi.new("float[44]"), { 0, 2, 8, 10, 12, 14 }
    local function geometry(node)
        local h = assert(b.read(node, 0xb0))
        local v = node_floats
        ffi.copy(v, h, #h)
        local width, height = v[9], v[10]
        local m = {}
        for i, k in ipairs(matrix_lanes) do
            m[i] = v[25 + k]
        end
        for _, n in ipairs(m) do
            assert(n == n and math.abs(n) <= 100000, "Invalid weapon HUD transform")
        end
        assert(width > 0 and width < 10000 and height > 0 and height < 10000, "Invalid weapon HUD size")
        return width, height, m, tonumber(v[21])
    end
    -- A node's bounds in the container's space (Y up), through its inverse matrix v/det.
    local function extent(node, v, det)
        local w, h, m = geometry(node)
        local top, bottom, left, right = -math.huge, math.huge, math.huge, -math.huge
        for _, c in ipairs({ { 0, 0 }, { w, 0 }, { 0, h }, { w, h } }) do
            local ex, ey = m[5] + m[1] * c[1] + m[3] * c[2] - v[5], m[6] + m[2] * c[1] + m[4] * c[2] - v[6]
            local lx = (ex * v[4] - ey * v[3]) / det
            local ly = (ey * v[1] - ex * v[2]) / det
            top, bottom = math.max(top, ly), math.min(bottom, ly)
            left, right = math.min(left, lx), math.max(right, lx)
        end
        return top, bottom, left, right
    end
    -- neighbours: optional function listing another HUD's option cells on this row
    -- ({kind=option kind, at=widget}), e.g. HUD+'s weapon line.
    function self.draw(root, model, neighbours, placement)
        local icons = M.icons(model)
        self.icons = icons
        if #icons == 0 then
            return self.hide()
        end
        if
            placement
            and (
                not finite(placement.x)
                or math.abs(placement.x) > 100000
                or not finite(placement.y)
                or math.abs(placement.y) > 100000
                or not M.metrics(model, placement.edge, placement.gap)
                or not finite(placement.opacity)
                or placement.opacity < 0
                or placement.opacity > 1
                or placement.root ~= nil and placement.root ~= root
            )
        then
            return false, "Invalid Bracket weapon placement"
        end
        assert(b.valid(root), "Weapon status HUD changed")
        -- Same native current-weapon image used by the stock HUD; follow its matrix.
        local weapon = root + 0x251468
        local context = assert(b.pointer(root + 0x820 + 0xf8), "Weapon HUD context unavailable")
        if
            address
            and b.pointer(address + 0xf0) == parent
            and b.valid(identity)
            and (context ~= resource_context or b.pointer(address + 0xf8) ~= resource_context)
        then
            return false, "Weapon UI resource context changed; cleanup pending"
        end
        local node, seen, frame, box = weapon, {}, weapon, weapon
        for depth = 1, 24 do
            assert(node >= root and node < root + 0x500000 and not seen[node], "Weapon HUD ancestry escaped or cycled")
            seen[node] = true
            local flags = b.read_u32(node)
            assert(flags and flags % 2 == 1 and b.pointer(node + 0xf8) == context, "Weapon HUD ancestry retired")
            if node == root + 0x820 then
                break
            end
            box, frame = frame, node -- frame: last ancestor below the container; box: the weapon row inside it
            node = assert(b.pointer(node + 0xf0), "Weapon HUD ancestry detached")
        end
        assert(node == root + 0x820, "Weapon HUD ancestry exceeds native bound")
        local _, _, _, weapon_alpha = geometry(weapon) -- inherited, including the native container
        local vw, vh, v, container_alpha = geometry(root + 0x820)
        local det = v[1] * v[4] - v[2] * v[3]
        assert(math.abs(det) > 0.01, "Weapon HUD transform degenerate")
        -- The weapon row's background box (the frame's child holding the weapon image)
        -- is the reference (container space, Y up).
        local box_top, box_bottom, box_left, box_right
        local start, seam, left, cy, edge, spacing, row, x0
        local strip_alpha, icon_alpha = placement and placement.opacity or 1, placement and 0.92 or 1
        if placement then
            if
                v[1] <= 0
                or v[4] <= 0
                or v[2] ~= 0
                or v[3] ~= 0
                or math.abs(v[1] - v[4]) > math.max(v[1], v[4]) * 1e-6
            then
                return false, "Bracket weapon transform unsupported"
            end
            left, cy = (placement.x - v[5]) / v[1], (placement.y - v[6]) / v[4]
            edge, spacing = placement.edge / v[1], placement.gap / v[1]
            local closed, why = panel_hide()
            if not closed then
                return false, why
            end
        else
            assert(
                finite(weapon_alpha) and weapon_alpha >= 0 and weapon_alpha <= 1
                    and finite(container_alpha) and container_alpha >= 0 and container_alpha <= 1,
                "Invalid native weapon opacity"
            )
            -- Our node is a sibling of the weapon under the native HUD container.
            -- Its inherited alpha already includes that container, so copy only
            -- the missing weapon fade rather than multiplying the ancestor twice.
            if container_alpha == 0 then
                assert(weapon_alpha == 0, "Native weapon opacity ancestry changed")
                strip_alpha = 0
            else
                strip_alpha = weapon_alpha / container_alpha
                assert(strip_alpha <= 1.000001, "Native weapon opacity ancestry changed")
                strip_alpha = math.min(1, strip_alpha)
            end
            box_top, box_bottom, box_left, box_right = extent(box, v, det)
            -- HUD+'s weapon line puts the game's option cells right of the same row (it
            -- widens the row for the rest). Leave out every option it already shows and
            -- start after its cells. Only a live widget of this HUD counts.
            start, seam = box_right, true
            local listed, cells = false, nil
            if neighbours then
                listed, cells = pcall(neighbours)
            end
            if listed and type(cells) == "table" then
                local shown, right
                for _, cell in ipairs(cells) do
                    local flags = type(cell) == "table" and type(cell.at) == "number" and b.read_u32(cell.at)
                    if flags and flags % 2 == 1 and b.pointer(cell.at + 0xf8) == context then
                        local ok, _, _, _, cell_right = pcall(extent, cell.at, v, det)
                        if ok then
                            shown = shown or {}
                            shown[cell.kind] = true
                            right = math.max(right or cell_right, cell_right)
                        end
                    end
                end
                if shown then
                    icons = M.icons(model, shown)
                    self.icons = icons
                    if #icons == 0 then
                        local hidden, why = self.hide()
                        self.status = "shown by HUD+"
                        return hidden, why
                    end
                    if right > box_right then
                        start, seam = right + 6, false
                    end -- HUD+'s own cell spacing
                end
            end
            -- The panel sits on the weapon's own row, right of its box: flush with the
            -- box's top and bottom, a small gap from its right end. Icons scale to fit
            -- the row height (at most icon_size).
            local gap, pad = 0, 4 -- butted against the native box; the seam gets a separator
            edge = math.max(8, math.min(icon_size, (box_top - box_bottom) - 2 * pad))
            spacing = math.min(icon_gap, edge * 0.25)
            row = #icons * edge + (#icons - 1) * spacing
            x0 = start + gap
            left = x0 + pad
            cy = box_bottom + ((box_top - box_bottom) - edge) / 2
        end
        local parts = {
            tostring(root),
            tostring(context),
            placement and "bracket" or "native",
            tostring(placement and placement.generation or ""),
            tostring(placement and placement.source_revision or ""),
            string.format("%.6f,%.6f,%.6f,%.6f,%.6f", left, cy, edge, spacing, placement and placement.opacity or 1),
            table.concat(v, ","),
            tostring(vw),
            tostring(vh),
            tostring(strip_alpha),
            tostring(icon_alpha),
            placement and "" or tostring(weapon_alpha),
            placement and "" or tostring(container_alpha),
        }
        for _, item in ipairs(icons) do
            parts[#parts + 1] = item.asset
        end
        local nextkey = table.concat(parts, ":")
        if owned() and key == nextkey then
            return true
        end
        if address and not owned() then
            assert(self.close())
        end
        if
            not address
            and not (
                scope.context_ready()
                and b.widgets_ready()
                and b.callable(init, sprite, asset, attach, finish, opacity, order, visible, uv)
            )
        then
            self.status = "waiting for game code"
            return false, self.status
        end
        scope.context_scope(root + 0x820, function(resource)
            assert(resource == context, "Weapon HUD resource context changed before drawing")
            assert(not address or owned(), "Weapon strip ownership changed before drawing")
            if not address then
                storage = ffi.new("uint8_t[?]", size + 64)
                address = math.floor((tonumber(ffi.cast("uintptr_t", storage)) + 31) / 16) * 16
                ffi.fill(ffi.cast("void *", address - 16), 16, 165)
                ffi.fill(ffi.cast("void *", address + size), 16, 165)
                identity, parent, resource_context = root, root + 0x820, resource
                init(address, 1)
                assert(b.pointer(address + 0xf8) == resource_context, "Weapon strip context changed")
                b.set(address, "size", { vw, vh })
                owned_width, owned_height = vw, vh
                b.set(address, "anchor", { 0, 0 })
                b.set(address, "pivot", { 0, 0 })
                b.set(address, "position", { 0, 0 })
                opacity(address, 1)
                for i = 1, 4 do
                    local p = address + 0x110 + (i - 1) * 0x160
                    sprite(p)
                    assert(b.pointer(p + 0xf8) == resource, "Weapon icon context changed")
                    b.set(p, "anchor", { 0, 0 })
                    b.set(p, "pivot", { 0, 0 })
                    b.set(p, "size", { icon_size, icon_size })
                    opacity(p, icon_alpha)
                    order(p, 0x400)
                    attach(address, p)
                    finish(address)
                end
                attach(parent, address)
                finish(parent)
                assert(owned(), "Weapon strip attachment failed")
            end
            if owned_width ~= vw or owned_height ~= vh then
                b.set(address, "size", { vw, vh })
                owned_width, owned_height = vw, vh
            end
            opacity(address, strip_alpha)
            for i = 1, 4 do
                local p = address + 0x110 + (i - 1) * 0x160
                opacity(p, icon_alpha)
                local item = icons[i]
                if item then
                    asset(p, asset_ids[item.asset], 0)
                    uv(p, uv_min, uv_max)
                    b.set(p, "size", { edge, edge })
                    b.set(p, "position", { left + (i - 1) * (edge + spacing), cy })
                    visible(p, 1)
                else
                    visible(p, 0)
                end
            end
            visible(address, 1)
            bounds()
            key = nextkey
            self.status = "visible"
        end)
        if not placement then
            local drawn, why = pcall(panel_draw, v, x0, box_bottom, left + row + 4, box_top, seam, weapon_alpha)
            if not drawn then
                local hidden, reason = panel_hide()
                self.panel_error = tostring(why)
                if not hidden then
                    return false, reason
                end
            end
        end
        return true
    end
    return self
end
return M
