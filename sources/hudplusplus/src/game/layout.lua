local Layout = {}
Layout.__index = Layout
function Layout.new(ui)
    return setmetatable({ ui = ui }, Layout)
end
function Layout:create(widget, kind, gap, owner_kind, padding)
    local ui, n = self.ui, self.ui.n
    local bytes = {}
    for index = 1, n.layout_last + 8 do
        bytes[index] = "\0"
    end
    local function put(offset, value, width)
        local raw = assert(ui.read.bytes.pack(value, width))
        for index = 1, width do
            bytes[offset + index] = raw:sub(index, index)
        end
    end
    put(n.layout_widget, widget.at, 8)
    put(n.layout_kind, kind, 4)
    put(n.layout_align, n.layout_centre, 4)
    put(n.layout_dirty, n.layout_dirty_on, 1)
    put(n.layout_flags, n.layout_flags_on, 2)
    if gap ~= nil then
        local offset = n.layout_gap
        if owner_kind == n.layout_right then
            offset = n.layout_gap_right
        elseif owner_kind == n.layout_down then
            offset = n.layout_gap_down
        end
        put(offset, assert(ui.port:bits(gap)), 4)
    end
    if padding ~= nil then
        for side = 0, 3 do
            put(n.layout_padding + side * 4, assert(ui.port:bits(padding)), 4)
        end
    end
    local extent = assert(ui.read:text(widget.at + n.widget_local_size, 8))
    for index = 1, 8 do
        bytes[n.layout_size + index] = extent:sub(index, index)
    end
    local initial = table.concat(bytes)
    if self.at == nil then
        self.at = assert(ui.port:own(initial))
    else
        assert(ui.write:swap(self.at, nil, initial))
    end
    return self
end
function Layout:add(child)
    self.ui:call("layout_add", self.at, child.at)
end
function Layout:place()
    self.ui:call("layout_place", self.at)
end
return Layout
