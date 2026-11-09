local Rows = require("game.menu_rows")
local Menu = {}
Menu.__index = Menu
function Menu.new(ui, settings, report, parts)
    local data = require("game.menu_data")
    local texts = { { template = data.template, resource = data.resource } }
    for _, part in ipairs(parts or {}) do
        texts[#texts + 1] = part.menu
    end
    return setmetatable({
        ui = ui,
        read = ui.read,
        n = ui.n,
        data = data,
        rows = Rows.new(ui, settings, data),
        texts_data = texts,
        labels = {},
        report = report,
    }, Menu)
end
function Menu:observe()
    local n, read = self.n, self.read
    local game = read:module("game")
    if game == nil then
        return nil, "waiting"
    end
    local state = read:ptr(game + n.menu_ui_state)
    if state == nil then
        return nil, "closed"
    end
    local count = read:value(state + n.menu_stack_count, "u32")
    if count == nil or count > (n.menu_stack_count - n.menu_stack) / 4 then
        return nil, "unread"
    end
    local found = false
    for i = 0, count - 1 do
        if read:value(state + n.menu_stack + i * 4, "u32") == n.menu_escape_type then
            found = true
        end
    end
    if not found then
        return nil, "closed"
    end
    local system = read:ptr(game + n.menu_system)
    local screen
    if system ~= nil then
        screen = read:ptr(system + n.menu_escape_screen)
    end
    if screen == nil then
        return nil, "unread"
    end
    if read:value(state + n.menu_stack + (count - 1) * 4, "u32") ~= n.menu_escape_type then
        return screen, "covered"
    end
    local language = read:ptr(game + n.ui_language_manager)
    if language == nil or read:value(language + n.ui_language_switch, "u8") ~= 0 then
        return screen, "language"
    end
    return screen, "open"
end
function Menu:forget()
    self.rows:forget()
    self.slot, self.selected = false, nil
end
function Menu:track()
    local screen, state = self:observe()
    self.outermost = state == "open"
    if state == "closed" or (screen ~= nil and screen ~= self.screen) then
        self:forget()
        self.screen = screen
    end
    return state == "open"
end
function Menu:before()
    if not self:track() or not self.slot then
        return
    end
    local n, ui, read, rows = self.n, self.ui, self.read, self.rows
    local bar = self.screen + n.menu_tab_bar
    if not rows:label_is(bar + n.menu_tab_text + n.menu_tab_stride * self.slot, self.data.tab) then
        self:forget()
        return
    end
    local current = read:value(bar + n.menu_tab_current, "u32")
    if self.selected and current == n.menu_options_tab then
        current = self.slot
    end
    if rows.content ~= nil and current ~= self.slot then
        rows:close()
    end
    self.selected = current == self.slot
    if self.selected then
        if rows.content == nil then
            ui:call("menu_tab_switch", self.screen, n.menu_options_tab)
        end
        ui:put(bar + n.menu_tab_current, n.menu_options_tab)
    end
    if read:value(bar + n.menu_tab_count, "u32") == self.slot + 1 then
        ui:put(bar + n.menu_tab_count, self.slot)
    end
end
function Menu:texts()
    for _, text in ipairs(self.texts_data) do
        local found = self.ui:call("strings_find", text.template, 0)
        local state = found ~= nil and found ~= 0 and self.read:value(found, "u8") ~= 0 and "found" or nil
        if state == nil and (text.state == nil or text.state == "found") then
            state = self.ui:call("strings_add", self.ui:resource(text.resource)) ~= 0 and "added" or "refused"
        elseif state == nil then
            state = text.state == "added" and "unresolved" or text.state
        end
        text.state = state
    end
end
function Menu:place()
    local n, ui, read, rows = self.n, self.ui, self.read, self.rows
    local bar = self.screen + n.menu_tab_bar
    if self.slot ~= nil and not rows:label_is(bar + n.menu_tab_text + n.menu_tab_stride * self.slot, self.data.tab) then
        self.slot = nil
    end
    local count, current = read:value(bar + n.menu_tab_count, "u32"), read:value(bar + n.menu_tab_current, "u32")
    if self.slot ~= nil then
        if count == self.slot then
            ui:put(bar + n.menu_tab_count, self.slot + 1)
        end
        return read:value(bar + n.menu_tab_count, "u32") == self.slot + 1
    end
    if
        count == nil
        or count < n.menu_native_tabs
        or current == nil
        or current >= count
        or count + 1 > n.menu_max_tabs
    then
        return false
    end
    for i = 0, n.menu_native_tabs - 1 do
        if
            read:value(bar + n.menu_tab_labels + i * 4, "u32")
            ~= read:value(read:module("game") + n.menu_tab_label_table + i * 4, "u32")
        then
            return false
        end
    end
    local bytes = assert(read:text(bar + n.menu_tab_labels, count * 4))
    if self.labels[bytes] == nil then
        self.labels[bytes] = assert(ui.port:own(bytes .. self.read.bytes.pack(self.data.tab, 4)))
    end
    ui:call("menu_tabs_set", bar, self.labels[bytes], count + 1)
    ui:call("menu_tab_select", bar, current, 0, 0)
    rows:label(bar + n.menu_tab_text + n.menu_tab_stride * count, self.data.tab)
    self.slot = count
    return true
end
function Menu:after(dt, completed)
    if not self:track() then
        return
    end
    self:texts()
    if self.slot == false then
        self.slot = nil
        return
    end
    if not self:place() then
        if self.rows.content ~= nil then
            self.rows:close()
        end
        return
    end
    local bar = self.screen + self.n.menu_tab_bar
    local current = self.read:value(bar + self.n.menu_tab_current, "u32")
    if self.selected and current == self.n.menu_options_tab then
        self.ui:put(bar + self.n.menu_tab_current, self.slot)
        current = self.slot
    end
    self.selected = nil
    if completed ~= false and current == self.slot then
        if self.rows.content == nil then
            self.rows:open(self.screen)
        end
        self.rows:step(dt or 0, self.report)
    end
end
function Menu:close()
    local screen, state = self:observe()
    if screen == self.screen and state ~= "closed" and screen ~= nil then
        self.rows:close()
        local bar = screen + self.n.menu_tab_bar
        if
            self.slot
            and self.rows:label_is(bar + self.n.menu_tab_text + self.n.menu_tab_stride * self.slot, self.data.tab)
        then
            if self.read:value(bar + self.n.menu_tab_current, "u32") == self.slot then
                self.ui:put(bar + self.n.menu_tab_current, self.n.menu_options_tab)
            end
            if self.read:value(bar + self.n.menu_tab_count, "u32") == self.slot + 1 then
                self.ui:put(bar + self.n.menu_tab_count, self.slot)
            end
        end
    end
    self:forget()
    self.outermost = false
end
return Menu
