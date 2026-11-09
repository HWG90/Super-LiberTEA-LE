local Ui = {}
Ui.__index = Ui
function Ui.new(access, n)
    local self = setmetatable({ read = access.read, port = access.call.ui, write = access.write, n = n }, Ui)
    self.colour_buffer = assert(self.port:buffer("float", 3))
    return self
end
function Ui:call(name, ...)
    local token, why = self.port:routine(name)
    if token == nil then
        error(why or name, 0)
    end
    return self.port:call(token, ...)
end
function Ui:pair(x, y)
    return assert(self.port:pair(x, y))
end
function Ui:resource(hash)
    if hash == nil or hash == "0000000000000000" then
        return nil
    end
    return self.port:uint64_of(hash)
end
function Ui:put(at, value, width)
    local bytes = type(value) == "string" and value or assert(self.read.bytes.pack(value, width or 4))
    local okay, why = self.write:swap(at, nil, bytes)
    if not okay then
        error(why, 0)
    end
end
local function forget(node)
    node.shown, node.text, node.texture, node.material = nil, nil, nil, nil
    node.red, node.green, node.blue, node.opacity, node.fade = nil, nil, nil, nil, nil
    node.held, node.vars = nil, nil
end
function Ui:node(size, previous)
    if previous ~= nil then
        assert(previous.size == size, "owner-size-changed")
        forget(previous)
        previous.live = true
        return previous
    end
    local owner = assert(self.port:own(string.rep("\0", size)))
    return { at = owner, owner = owner, size = size, live = true }
end
function Ui:alive(node)
    if node == nil or not node.live then
        return false
    end
    local first = self.read:value(node.at, "u32")
    if first == nil then
        return nil
    end
    if first == 0 then
        node.live = false
        forget(node)
        return false
    end
    return true
end
function Ui:destroy(node)
    if node == nil or not node.live then
        return
    end
    if self:alive(node) == true then
        self:call("widget_destroy", node.at)
    end
    node.live = false
    forget(node)
end
function Ui:context(parent, create, explicit_context)
    local read, n = self.read, self.n
    local game = assert(read:module("game"))
    local base = assert(read:ptr(game + n.gui_contexts))
    local context = explicit_context or assert(read:ptr(parent + n.widget_gui_context))
    local slot = (context - base) / n.gui_context_stride
    assert(slot >= 0 and slot < n.gui_context_slots and slot % 1 == 0, "context-slot")
    assert(read:value(context, "u8") == 1, "context-inactive")
    local top_at = base + n.gui_context_top
    local top = assert(read:value(top_at, "i32"))
    assert(top >= -1 and top < n.gui_context_top - n.gui_context_stack - 1, "context-stack")
    local old_slot
    if top >= 0 then
        old_slot = assert(read:value(base + n.gui_context_stack + top, "u8"))
    end
    local pushed = pcall(self.call, self, "ui_context_push", base, slot)
    local okay, result = pcall(function()
        assert(pushed and read:value(top_at, "i32") == top + 1, "context-push")
        assert(read:value(base + n.gui_context_stack + top + 1, "u8") == slot, "context-push-slot")
        return create(context, slot)
    end)
    if read:ptr(game + n.gui_contexts) == base and read:value(top_at, "i32") == top + 1 then
        local restored = pcall(self.call, self, "ui_context_pop")
        assert(restored and read:value(top_at, "i32") == top, "context-restore")
        if top >= 0 then
            assert(read:value(base + n.gui_context_stack + top, "u8") == old_slot, "context-restore-slot")
        end
    else
        error("context-changed", 0)
    end
    if not okay then
        error(result, 0)
    end
    return result
end
function Ui:attach(parent, node)
    self:call("widget_attach", parent, node.at)
end
function Ui:frame(previous)
    local node = self:node(self.n.widget_last + 8, previous)
    self:call("widget_init", node.at, self.n.container_kind)
    return node
end
function Ui:root(slot, previous)
    local node = self:node(math.ceil((self.n.root_last + 1) / 8) * 8, previous)
    self:call("root_build", node.at, slot, self.n.root_flag, self.n.root_flag)
    return node
end
function Ui:text_node(font, flat, style, height, previous, own_material)
    local node = self:node(math.ceil((self.n.string_text_last + 1) / 16) * 16, previous)
    self:call("string_text_make", node.at)
    self:call("text_font_set", node.at, font, flat, style, 1, own_material and 1 or 0)
    node.height = height
    self:show(node, false)
    return node
end
function Ui:label_node(font, flat, style, template, previous)
    local node = self:node(math.ceil((self.n.label_text_last + 1) / 16) * 16, previous)
    self:call("label_text_make", node.at)
    self:call("label_template_set", node.at, template)
    self:call("text_font_set", node.at, font, flat, style, 1, 0)
    self:show(node, false)
    return node
end
function Ui:number(node, argument, value)
    if value == nil then
        self:show(node, false)
        node.text = nil
        return
    end
    if node.text ~= value then
        self:call("number_arg_set", node.at, argument, value, 0)
        self:call("measure_widget", node.at)
        node.text = value
    end
    self:show(node, true)
end
function Ui:image_node(previous)
    local node = self:node(math.ceil((self.n.picture_last + 8) / 16) * 16, previous)
    self:call("picture_init", node.at)
    self:show(node, false)
    return node
end
local function held_of(node)
    local held = node.held
    if held == nil then
        held = {}
        node.held = held
    end
    return held
end
local function put_pair(self, node, call, x, y)
    local held = held_of(node)
    local last = held[call]
    if last ~= nil and last[1] == x and last[2] == y then
        return
    end
    self:call(call, node.at, self:pair(x, y))
    if last == nil then
        held[call] = { x, y }
    else
        last[1], last[2] = x, y
    end
end
local function put_one(self, node, call, value)
    local held = held_of(node)
    if held[call] == value then
        return
    end
    self:call(call, node.at, value)
    held[call] = value
end
function Ui:size(node, x, y)
    put_pair(self, node, "widget_size_set", x, y)
end
function Ui:scale(node, x, y)
    put_pair(self, node, "widget_scale_set", x, y)
end
function Ui:anchor(node, x, y)
    put_pair(self, node, "widget_anchor_set", x, y)
end
function Ui:pivot(node, x, y)
    put_pair(self, node, "widget_pivot_set", x, y)
end
function Ui:position(node, x, y)
    put_pair(self, node, "widget_position_set", x, y)
end
function Ui:rotation(node, value)
    put_one(self, node, "widget_rotation_set", value)
end
function Ui:slide_scale(at, from, to, seconds)
    local first = self.read:value(at, "u32")
    if first == nil or first == 0 then
        return
    end
    if self.slide_points == nil then
        self.slide_points = assert(self.port:buffer("float", 4, 16))
    end
    self:call("widget_scale_slide", at, self:pair(from, from), self:pair(to, to), 1, seconds, 0, self.slide_points)
end
function Ui:layer(node, value)
    put_one(self, node, "widget_layer_set", value)
end
function Ui:show(node, value)
    if node.shown == value then
        return
    end
    self:call("widget_shown_set", node.at, value and 1 or 0)
    node.shown = value
end
function Ui:opacity(node, value)
    if node.opacity == value then
        return
    end
    self:call("widget_opacity_set", node.at, value)
    node.opacity, node.fade = value, nil
end
function Ui:fade(node, shown, full, seconds)
    local target = false
    if shown then
        target = full
    end
    if node.fade == target then
        return
    end
    self:call("widget_fade", node.at, shown and 0 or 1, seconds, full, 0)
    node.opacity, node.fade = nil, target
end
function Ui:colour(node, red, green, blue)
    if node.red == red and node.green == green and node.blue == blue then
        return
    end
    local colour = self.colour_buffer
    colour[0], colour[1], colour[2] = red, green, blue
    self:call("widget_color_set", node.at, colour)
    node.red, node.green, node.blue = red, green, blue
end
function Ui:text(node, value)
    if value == nil then
        self:show(node, false)
        node.text = nil
        return
    end
    local text = tostring(value)
    if node.text ~= text then
        self:call("text_string_set", node.at, text)
        if node.height ~= nil then
            self:call("text_size_set", node.at, node.height)
        end
        self:call("measure_widget", node.at)
        node.text = text
    end
    self:show(node, true)
end
function Ui:image(node, texture, material)
    if texture == nil then
        self:show(node, false)
        node.texture = nil
        return
    end
    if node.texture ~= texture or node.material ~= material then
        self:call("picture_set", node.at, assert(self:resource(material)), assert(self:resource(texture)), 0)
        node.texture, node.material, node.vars = texture, material, nil
    end
    self:show(node, true)
end
function Ui:submit(root, dt)
    if dt == nil then
        return
    end
    self:call("root_tick", root.at, dt)
    local first = assert(self.read:value(root.at, "u8"))
    if self.read.bytes.any_bit(first, self.n.root_dirty_mask) then
        self:call("root_push", root.at)
    end
end
function Ui:shade(node)
    if node == nil or not node.live or not node.shown then
        return
    end
    local n = self.n
    local alpha = self.read:value(node.at + n.widget_inherited_opacity, "f32")
    if alpha ~= nil then
        self:material_scalar(node, n.shadow_alpha_mul_key, alpha)
    end
end
function Ui:material(node, hash)
    self:call("widget_material_set", node.at, assert(self:resource(hash)), 0)
    node.vars = nil
end
local function put_vars(self, node, call, key, count, a, b, c, d)
    local vars = node.vars
    local last = vars and vars[key]
    if last ~= nil and last[1] == a and last[2] == b and last[3] == c and last[4] == d then
        return
    end
    local material = self:call("widget_material_get", node.at)
    assert(material ~= nil and material ~= 0, "material")
    if count == 1 then
        self:call(call, node.at, key, a)
    else
        if self.material_buffer == nil then
            self.material_buffer = assert(self.port:buffer("float", 4))
        end
        local vector = self.material_buffer
        vector[0], vector[1] = a, b
        if count == 4 then
            vector[2], vector[3] = c, d
        end
        self:call(call, node.at, key, vector)
    end
    if vars == nil then
        vars = {}
        node.vars = vars
    end
    if last == nil then
        vars[key] = { a, b, c, d }
    else
        last[1], last[2], last[3], last[4] = a, b, c, d
    end
end
function Ui:material_scalar(node, key, value)
    put_vars(self, node, "material_scalar_set", key, 1, value)
end
function Ui:material_four(node, key, a, b, c, d)
    put_vars(self, node, "material_var_set", key, 4, a, b, c, d)
end
function Ui:material_pair(node, key, x, y)
    put_vars(self, node, "material_pair_set", key, 2, x, y)
end
Ui.public_resources = {
    hud_text_font = true,
    hud_text_variant = true,
    map_marker_clip_key = true,
    map_marker_layer = true,
    map_marker_pool_slots = true,
    map_marker_scalar_key = true,
    choice_arrow_picture = true,
    choice_arrow_material = true,
    choice_arrow_uv_width = true,
    shadow_color_key = true,
    shadow_offset = true,
    shadow_offset_key = true,
    stratagem_row_card_layer = true,
}
function Ui:public(resources)
    local ui, api = self, { n = {} }
    local native = setmetatable({}, { __mode = "k" })
    local handles = setmetatable({}, { __mode = "v" })
    for _, name in ipairs(resources or {}) do
        assert(Ui.public_resources[name], "addon-resource:" .. name)
        api.n[name] = assert(ui.n[name], "addon-resource:" .. name)
    end
    local function wrap(value)
        if value == nil then
            return
        end
        local key = type(value) == "number" and value or value.at
        local handle = handles[key]
        if handle == nil then
            handle = {}
            handle.at = handle
            handles[key] = handle
        end
        if type(value) == "number" then
            if native[handle] == nil then
                native[handle] = { at = value }
            end
        else
            native[handle] = value
            handle.live, handle.shown = value.live, value.shown
        end
        return handle
    end
    for _, name in ipairs({
        "alive",
        "destroy",
        "size",
        "scale",
        "anchor",
        "pivot",
        "position",
        "rotation",
        "layer",
        "show",
        "opacity",
        "colour",
        "text",
        "image",
    }) do
        local method = assert(ui[name])
        api[name] = function(_, handle, ...)
            local node = native[handle]
            local result = method(ui, node, ...)
            if handle ~= nil then
                handle.live, handle.shown = node.live, node.shown
            end
            return result
        end
    end
    function api:frame(previous)
        return wrap(ui:frame(native[previous]))
    end
    function api:image_node(previous)
        return wrap(ui:image_node(native[previous]))
    end
    function api:text_node(font, flat, style, height, previous, own_material)
        return wrap(ui:text_node(font, flat, style, height, native[previous], own_material))
    end
    function api:context(parent, create)
        return ui:context(native[parent].at, create)
    end
    function api:attach(parent, node)
        return ui:attach(native[parent].at, native[node])
    end
    function api:material_scalar(node, key, value)
        return ui:material_scalar(native[node], key, value)
    end
    function api:material_four(node, key, ...)
        return ui:material_four(native[node], key, ...)
    end
    function api:material_pair(node, key, ...)
        return ui:material_pair(native[node], key, ...)
    end
    function api:uv(node, x1, y1, x2, y2)
        return ui:call("widget_uv_set", native[node].at, ui:pair(x1, y1), ui:pair(x2, y2))
    end
    function api:shade(handle)
        ui:shade(native[handle])
    end
    return api, wrap
end
return Ui
