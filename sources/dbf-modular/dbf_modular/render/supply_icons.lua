-- Game-art images owned by this HUD. No stock widget is moved or hidden.
-- Picture hashes come from the native supply HUD; they are textures, not the
-- whole-resource IDs accepted by Original DBF's option-strip asset() setter.
local Build = mod.require("sampling/build.lua")
local Native = mod.require("sampling/native.lua")
local Style = mod.require("ui/style.lua")
local Supply = {}
Supply.__index = Supply
local KEYS, SIZE = { "stims", "throwables", "heat" }, 0x110 + 3 * 0x160
local function finite(v)
    return type(v) == "number" and v == v and math.abs(v) < math.huge
end
local function address(v)
    return finite(v) and v >= 65536 and v < 2 ^ 47 and v % 1 == 0
end
local function hex(v)
    return type(v) == "string" and #v == 16 and not v:find("[^%x]") and v ~= "0000000000000000"
end
local function texture_of(raw)
    if type(raw) ~= "string" or #raw ~= 8 then
        return nil
    end
    local out = ""
    for i = 8, 1, -1 do
        out = out .. string.format("%02x", raw:byte(i))
    end
    return out ~= "0000000000000000" and out or nil
end
local function attempt(self, fn)
    local okay, accepted, why = pcall(fn)
    if not okay or accepted == false then
        self.ready = false
        self.reason = tostring(okay and why or accepted)
        return false, self.reason
    end
    return true
end
function Supply.new(deps)
    assert(deps and deps.core, "Supply icon Core required")
    return setmetatable({
        core = deps.core,
        native_factory = deps.native_factory or Native.new,
        ffi = deps.ffi or require("ffi"),
        ready = false,
        cache = {},
        textures = {},
        constructed = 0,
        attached = 0,
    }, Supply)
end
function Supply:_bind(b)
    self.backend, self.native = b, self.native_factory(b)
    local call = b.fn
    self.calls = {
        init = call("void (*)(uintptr_t,uint32_t)", 0x12de550),
        sprite = call("void (*)(uintptr_t)", 0x12d67c0),
        picture = call(Build.calls.supply_picture_set.ctype, Build.calls.supply_picture_set.rva),
        rotation = call(Build.calls.supply_rotation_set.ctype, Build.calls.supply_rotation_set.rva),
        attach = call("void (*)(uintptr_t,uintptr_t)", 0x12e42d0),
        finish = call("void (*)(uintptr_t)", 0x12e3fd0),
        opacity = call("void (*)(uintptr_t,float)", 0x12e07e0),
        order = call("void (*)(uintptr_t,uint32_t)", 0x12e0f00),
        visible = call("void (*)(uintptr_t,uint8_t)", 0x12e4cc0),
        release = call("void (*)(uintptr_t)", 0x12e5a80),
        push = call("void (*)(uintptr_t,uint8_t)", 0x11822f0),
        pop = call("void (*)(void)", 0x1182310),
    }
end
function Supply:_code(rotate)
    local b, c = self.backend, self.calls
    local at, why = self.native:target("supply_picture_set")
    if not at then
        return false, why
    end
    if rotate then
        at, why = self.native:target("supply_rotation_set")
        if not at then
            return false, why
        end
    end
    if not b.widgets_ready() then
        return false, "Supply widget setters unavailable"
    end
    for name, fn in pairs(c) do
        if (name ~= "rotation" or rotate) and not b.callable(fn) then
            return false, "Supply widget code unavailable"
        end
    end
    return true
end
-- These are the Original DBF context table/stack guards, without creating a
-- duplicate_cards object (which would replace the backend's radial predicate).
function Supply:_scope(fn)
    local b, c = self.backend, self.calls
    local manager = assert(b.pointer(b.base + 0x2e381c8), "Supply context manager unavailable")
    local index = (self.context - manager) / 0x3698
    assert(index >= 0 and index < 13 and index % 1 == 0, "Supply context outside native table")
    assert(b.pointer(self.context + 8), "Supply context renderer unavailable")
    local before = assert(b.read_u32(manager + 0x2c5bc), "Supply context stack unreadable")
    local depth = before == 0xffffffff and -1 or before
    assert(depth >= -1 and depth < 3, "Supply context stack full")
    self:_fresh()
    c.push(manager, index)
    local okay, result = pcall(function()
        assert(b.read_u32(manager + 0x2c5bc) == depth + 1, "Supply context push failed")
        assert(b.read_u8(manager + 0x2c5b8 + depth + 1) == index, "Supply context push changed")
        return fn()
    end)
    c.pop()
    assert(b.read_u32(manager + 0x2c5bc) == before, "Supply context stack did not restore")
    assert(okay, result)
end
function Supply:_bounds()
    if self.storage then
        local ffi, at = self.ffi, self.address
        assert(ffi.string(ffi.cast("const char *", at - 16), 16) == string.rep("\165", 16), "Supply prefix overwritten")
        assert(
            ffi.string(ffi.cast("const char *", at + SIZE), 16) == string.rep("\165", 16),
            "Supply suffix overwritten"
        )
    end
end
function Supply:_fresh()
    local b, n = self.backend, Build.numbers
    assert(b.pointer(b.base + n.roots_hud_manager_rva) == self.identity, "Supply HUD owner changed")
    assert(b.pointer(self.parent + n.widget_gui_context) == self.context, "Supply parent context changed")
    assert(b.read_u8(self.context) == n.ui_context_live, "Supply context retired")
    if self.initialized then
        assert(b.pointer(self.address + 0xf8) == self.context, "Supply owned context changed")
        if self.linked then
            assert(b.pointer(self.address + 0xf0) == self.parent, "Supply root link changed")
        end
        for i = 1, self.constructed do
            local at = self.address + 0x110 + (i - 1) * 0x160
            assert(b.pointer(at + 0xf8) == self.context, "Supply image context changed")
            if i <= self.attached then
                assert(b.pointer(at + 0xf0) == self.address, "Supply image link changed")
            end
        end
    end
    self:_bounds()
end
function Supply:_write(fn, ...)
    self:_fresh()
    assert(fn(...) ~= false, "Supply widget mutation refused")
end
function Supply:_visible(at, shown)
    -- Publish the obligation before calling a void native setter. It can have
    -- changed visibility even if the following read-back becomes unavailable.
    if at == self.address then
        self.visibility_pending = true
    end
    self:_write(self.calls.visible, at, shown and 1 or 0)
    local flags = assert(self.backend.read_u32(at), "Supply visibility unreadable")
    assert((math.floor(flags / 16) % 2 == 1) == shown, "Supply visibility did not acknowledge")
    if at == self.address then
        self.shown, self.visibility_pending = shown, nil
    end
end
function Supply:_set(at, property, x, y)
    self:_write(self.backend.set, at, property, { x, y })
end
function Supply:prepare(model)
    self.ready = false
    if self.retiring then
        return false, "Supply icons are retiring"
    end
    return attempt(self, function()
        local services = type(self.core.services) == "function" and self.core:services() or {}
        local b = services.backend
        if b ~= self.backend then
            local closed, why = self:close()
            assert(closed, why)
            self.retiring = nil
            if not b then
                return true
            end
            self:_bind(b)
        end
        if not b or not model or model.known ~= true or not address(model.identity) then
            return true
        end
        local parent = model.identity + Build.supply.parent
        local context = b.pointer(parent + Build.numbers.widget_gui_context)
        if not address(context) or not b.valid(model.identity) then
            self.reason = "Supply HUD unavailable"
            return true
        end
        if
            self.storage
            and (self.identity ~= model.identity or self.generation ~= model.generation or self.context ~= context)
        then
            local closed, why = self:close()
            assert(closed, why)
            self.retiring = nil
        end
        local code, why =
            self:_code(model.supply_icons and model.supply_icons.heat and model.supply_icons.heat.known == true)
        if not code then
            self.reason = why
            return true
        end
        self.identity, self.generation, self.parent, self.context = model.identity, model.generation, parent, context
        self:_fresh()
        self.ready, self.reason = true, nil
        self.prepared_model, self.prepared_time = model, model.time
        return true
    end)
end
function Supply:_create()
    if self.storage then
        return
    end
    local ffi, c = self.ffi, self.calls
    self.storage = ffi.new("uint8_t[?]", SIZE + 64)
    self.address = math.floor((tonumber(ffi.cast("uintptr_t", self.storage)) + 31) / 16) * 16
    ffi.fill(ffi.cast("void *", self.address - 16), 16, 165)
    ffi.fill(ffi.cast("void *", self.address + SIZE), 16, 165)
    self:_write(c.init, self.address, 1)
    self.initialized = true
    self:_set(self.address, "anchor", 0, 0)
    self:_set(self.address, "pivot", 0, 0)
    self:_set(self.address, "position", 0, 0)
    self:_set(self.address, "size", 1, 1)
    self:_write(c.opacity, self.address, 1)
    self:_visible(self.address, false)
    for i = 1, #KEYS do
        local at = self.address + 0x110 + (i - 1) * 0x160
        self:_write(c.sprite, at)
        self.constructed = i
        self:_set(at, "anchor", 0, 0)
        self:_set(at, "pivot", i == 3 and 0.5 or 0, i == 3 and 0.5 or 0)
        self:_visible(at, false)
        self:_write(c.order, at, 0x400)
        self:_write(c.attach, self.address, at)
        self.attached = i
        self:_write(c.finish, self.address)
    end
    self:_write(c.attach, self.parent, self.address)
    self.linked = true
    self:_write(c.finish, self.parent)
end
function Supply:_texture(hash)
    local found = self.textures[hash]
    if not found then
        found = self.ffi.new("uint64_t", tonumber(hash:sub(1, 8), 16)) * 4294967296ULL + tonumber(hash:sub(9), 16)
        self.textures[hash] = found
    end
    return found
end
function Supply:_matrix()
    local raw = assert(self.backend.read(self.parent + 0x64, 64), "Supply HUD matrix unreadable")
    assert(#raw == 64, "Supply HUD matrix short")
    self.matrix = self.matrix or self.ffi.new("float[16]")
    self.ffi.copy(self.matrix, raw, 64)
    local m = self.matrix
    local a, b, c, d, x, y = m[0], m[2], m[8], m[10], m[12], m[14]
    for _, v in ipairs({ a, b, c, d, x, y }) do
        assert(finite(v) and math.abs(v) <= 100000, "Supply HUD matrix invalid")
    end
    assert(
        a > 1e-6 and d > 1e-6 and b == 0 and c == 0 and math.abs(a - d) <= math.max(a, d) * 1e-6,
        "Supply HUD transform unsupported"
    )
    return a, d, x, y
end
function Supply:render(model, layout, opacity, prepared)
    if
        not (
            prepared == true
            and self.ready
            and self.prepared_model == model
            and self.prepared_time == model.time
            and self.identity == model.identity
            and self.generation == model.generation
        )
    then
        local accepted, why = self:prepare(model)
        if not accepted then
            return false, why
        end
    end
    if not self.ready then
        return self:hide()
    end
    return attempt(self, function()
        local requested = {}
        for _, spec in ipairs(layout and layout.supplies or {}) do
            assert(spec.key == "stims" or spec.key == "throwables" or spec.key == "heat", "Unknown supply icon")
            assert(not requested[spec.key], "Duplicate supply icon")
            requested[spec.key] = spec
        end
        local wanted = {}
        for i, key in ipairs(KEYS) do
            local icon, spec = model.supply_icons and model.supply_icons[key], requested[key]
            if spec then
                -- Layout has already replaced this descriptive label with a
                -- count. Withdraw the whole icon pass before any new writes
                -- if its current image cannot be proved, so Controller can
                -- hide with acknowledgment and recompose descriptive text.
                assert(
                    icon
                        and icon.known == true
                        and hex(icon.texture)
                        and icon.identity == self.identity
                        and icon.generation == self.generation
                        and icon.context == self.context,
                    "Requested supply image unavailable"
                )
                if key == "throwables" then
                    local source = self.identity
                        + Build.numbers.hud_widgets_mission_hud
                        + Build.numbers.hud_widgets_panels_self_panel_at
                        + Build.numbers.self_panel_throwable_picture
                    assert(
                        icon.source == source and texture_of(self.backend.read(source, 8)) == icon.texture:lower(),
                        "Equipped grenade picture changed after sampling"
                    )
                elseif key == "heat" then
                    assert(
                        address(icon.source) and texture_of(self.backend.read(icon.source, 8)) == icon.texture:lower(),
                        "Heat picture changed after sampling"
                    )
                    assert(
                        address(icon.weapon_record)
                            and type(icon.weapon_record_bytes) == "string"
                            and #icon.weapon_record_bytes == 24
                            and self.backend.read(icon.weapon_record, 24) == icon.weapon_record_bytes,
                        "Heat picture weapon changed after sampling"
                    )
                end
                for _, field in ipairs({ "x", "y", "width", "height" }) do
                    assert(finite(spec[field]) and math.abs(spec[field]) <= 100000, "Invalid supply placement")
                end
                assert(spec.width > 0 and spec.height > 0, "Invalid supply size")
                local alpha = (opacity or 1) * (spec.opacity or 1)
                assert(finite(alpha) and alpha >= 0 and alpha <= 1, "Invalid supply opacity")
                local rotation = key == "heat" and (spec.rotation or 0) or 0
                assert(rotation == 0 or key == "heat" and rotation == 90, "Unsupported supply rotation")
                wanted[i] = { spec = spec, texture = icon.texture:lower(), alpha = alpha, rotation = rotation }
            end
        end
        if not wanted[1] and not wanted[2] and not wanted[3] then
            return self:hide()
        end
        local a, d, tx, ty = self:_matrix()
        local changed = not self.storage or not self.shown
        for i = 1, #KEYS do
            local item, cached = wanted[i], self.cache[i] or {}
            if item then
                local spec = item.spec
                item.x, item.y = (spec.x - tx) / a, (spec.y - ty) / d
                item.width, item.height = spec.width / a, spec.height / d
                if i == 3 then
                    item.x, item.y = item.x + item.width / 2, item.y + item.height / 2
                    if item.rotation == 90 then
                        item.width, item.height = item.height, item.width
                    end
                end
                item.tone = spec.tone or "text"
                item.color = assert(Style.tokens.colors[item.tone], "Unknown supply colour token")
                changed = changed
                    or cached.texture ~= item.texture
                    or cached.x ~= item.x
                    or cached.y ~= item.y
                    or cached.width ~= item.width
                    or cached.height ~= item.height
                    or cached.tone ~= item.tone
                    or cached.alpha ~= item.alpha
                    or i == 3 and cached.rotation ~= item.rotation
                    or cached.shown ~= true
            else
                changed = changed or self.storage ~= nil and cached.shown ~= false
            end
        end
        if not changed then
            self:_fresh()
            return true
        end
        self:_scope(function()
            self:_create()
            for i = 1, #KEYS do
                local at, item = self.address + 0x110 + (i - 1) * 0x160, wanted[i]
                local cached = self.cache[i] or {}
                self.cache[i] = cached
                if item then
                    local x, y, width, height = item.x, item.y, item.width, item.height
                    local tone, color = item.tone, item.color
                    if cached.texture ~= item.texture then
                        self:_write(
                            self.calls.picture,
                            at,
                            self:_texture(Build.supply.material),
                            self:_texture(item.texture),
                            0
                        )
                        cached.texture = item.texture
                    end
                    if cached.x ~= x or cached.y ~= y then
                        self:_set(at, "position", x, y)
                        cached.x, cached.y = x, y
                    end
                    if cached.width ~= width or cached.height ~= height then
                        self:_set(at, "size", width, height)
                        cached.width, cached.height = width, height
                    end
                    if i == 3 and cached.rotation ~= item.rotation then
                        self:_write(self.calls.rotation, at, item.rotation)
                        cached.rotation = item.rotation
                    end
                    if cached.tone ~= tone or cached.alpha ~= item.alpha then
                        self:_write(
                            self.backend.set_text_style,
                            at,
                            { color[4] / 255 * item.alpha, color[1] / 255, color[2] / 255, color[3] / 255 }
                        )
                        cached.tone, cached.alpha = tone, item.alpha
                    end
                    if cached.shown ~= true then
                        self:_visible(at, true)
                        cached.shown = true
                    end
                elseif cached.shown ~= false then
                    self:_visible(at, false)
                    cached.shown = false
                end
            end
            if not self.shown then
                self:_visible(self.address, true)
                self.shown = true
            end
        end)
        self:_fresh()
        return true
    end)
end
function Supply:hide()
    if self.storage and not self.linked then
        local closed, why = self:close()
        if closed then
            self.retiring = nil
        end
        return closed, why
    end
    if not self.storage or not self.shown and not self.visibility_pending then
        return true
    end
    return attempt(self, function()
        self:_fresh()
        local code, why = self:_code()
        assert(code, why)
        self:_visible(self.address, false)
        self.shown = false
        return true
    end)
end
function Supply:close()
    self.ready, self.retiring = false, true
    if self.storage then
        local closed, why = attempt(self, function()
            local link = self.backend.read_u64(self.address + 0xf0)
            assert(link ~= nil, "Supply attachment unreadable; cleanup pending")
            if link ~= 0 then
                self:_fresh()
                local code, reason = self:_code()
                assert(code, reason)
                assert(self.backend.valid(self.identity), "Supply owner unavailable; cleanup pending")
            end
            local accepted, reason =
                self.backend.release_owned_ui(self.storage, self.address, self.identity, self.parent, {})
            assert(accepted == true, reason or "Supply release refused")
            assert(self.backend.read_u64(self.address + 0xf0) == 0, "Supply release did not detach")
            self:_bounds()
            return true
        end)
        if not closed then
            return false, why
        end
    end
    self.storage, self.address, self.initialized, self.linked, self.shown = nil, nil, nil, nil, nil
    self.visibility_pending = nil
    self.constructed, self.attached, self.cache = 0, 0, {}
    self.prepared_model, self.prepared_time = nil, nil
    return true
end
return Supply
