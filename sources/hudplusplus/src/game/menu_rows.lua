local Rows = {}
Rows.__index = Rows
function Rows.new(ui, settings, data)
    local n, plans, groups = ui.n, {}, {}
    for i, label in ipairs(data.groups) do
        plans[i] = { label = label, members = {}, order = {} }
        groups[label] = plans[i]
    end
    for _, entry in ipairs(settings.entries) do
        if entry.title ~= nil then
            local plan = assert(groups[entry.group])
            local heading = entry.heading or false
            if heading == entry.group then
                heading = false
            end
            if plan.members[heading] == nil then
                plan.members[heading] = {}
                table.insert(plan.order, heading and #plan.order + 1 or 1, heading)
            end
            local members = plan.members[heading]
            members[#members + 1] = entry
        end
    end
    for _, plan in ipairs(plans) do
        plan.rows = {}
        for i, heading in ipairs(plan.order) do
            if heading then
                plan.rows[#plan.rows + 1] = { title = heading, gap = i > 1 }
            end
            for _, entry in ipairs(plan.members[heading]) do
                plan.rows[#plan.rows + 1] = { title = entry.title, entry = entry }
            end
        end
        plan.members, plan.order = nil, nil
        assert(#plan.rows <= n.menu_last_row + 1, "menu-row-capacity")
    end
    local panels = {
        {
            at = n.menu_first_panel,
            count = n.menu_panel_count,
            x = n.menu_panel_x,
            gap = n.menu_panel_gap,
            settings = n.menu_panel_settings,
            selected = n.menu_panel_selected,
        },
    }
    for _, at in ipairs({ n.menu_display_panel, n.menu_graphics_panel }) do
        panels[#panels + 1] = {
            at = at,
            count = n.menu_large_count,
            x = n.menu_large_x,
            gap = n.menu_large_gap,
            settings = n.menu_large_settings,
            selected = n.menu_large_selected,
            scrolls = n.menu_large_scrolls,
        }
    end
    assert(#plans <= #panels, "menu-category-capacity")
    return setmetatable(
        { ui = ui, read = ui.read, n = n, settings = settings, plans = plans, panels = panels, data = data },
        Rows
    )
end
function Rows:label(at, id)
    self.ui:put(at + self.n.menu_label_args + self.n.menu_label_arg_count, 0, 1)
    self.ui:call("label_template_set", at, id)
end
function Rows:label_is(at, id)
    return self.read:value(at + self.n.menu_label_args, "u32") == id
        and self.read:value(at + self.n.menu_label_args + self.n.menu_label_arg_count, "u8") == 0
end
function Rows:descriptor(cells)
    local bytes = self.template
    for _, cell in ipairs(cells) do
        assert(cell[1] + 4 <= #bytes, "menu-descriptor-cell")
        bytes = bytes:sub(1, cell[1]) .. assert(self.read.bytes.pack(cell[2], 4)) .. bytes:sub(cell[1] + 5)
    end
    return assert(self.ui.port:own(bytes))
end
function Rows:prepare()
    if self.descriptors ~= nil then
        return
    end
    local ui, n, read = self.ui, self.n, self.read
    local at = assert(ui:call("menu_descriptor", n.menu_inert_setting))
    assert(
        at ~= 0
            and read:value(at + n.menu_descriptor_value_type, "u32") == 0
            and read:value(at + n.menu_descriptor_description, "u32") == 0,
        "menu-bound-setting"
    )
    self.template, self.descriptors = assert(read:text(at, n.menu_descriptor_size)), {}
    self.title_descriptor = self:descriptor({
        { n.menu_descriptor_widget_type, n.menu_title_kind },
        { n.menu_descriptor_label, n.menu_text_template },
    })
    local game = read:module("game")
    self.row_step, self.group_gap =
        read:value(game + n.menu_row_step, "f32"), read:value(game + n.menu_group_gap, "f32")
    self.scroll_row, self.scroll_view =
        read:value(game + n.menu_scroll_row, "f32"), read:value(game + n.menu_scroll_view, "f32")
    self.pivot = assert(ui.port:uint64(n.menu_pivot_y, n.menu_pivot_x))
    self.apply_action = assert(ui:call("menu_key_decode", ui:resource(n.menu_apply_key)))
end
function Rows:option_descriptor(entry)
    local n, cells, key = self.n, nil, nil
    if entry.range ~= nil then
        key = "slider:" .. entry.range[1] .. ":" .. entry.range[2] .. ":" .. entry.step
        cells = {
            { n.menu_descriptor_widget_type, n.menu_slider_kind },
            { n.menu_descriptor_label, n.menu_text_template },
            { n.menu_descriptor_slider_min, self.ui.port:bits(entry.range[1]) },
            { n.menu_descriptor_slider_max, self.ui.port:bits(entry.range[2]) },
            { n.menu_descriptor_slider_step, self.ui.port:bits(entry.step) },
        }
    else
        local labels = {}
        for i, value in ipairs(entry.choices) do
            labels[i] = value == "off" and n.menu_toggle_off or value == "on" and n.menu_toggle_on or value
        end
        key = table.concat(labels, ",")
        assert(n.menu_descriptor_choices + 4 * #labels <= n.menu_descriptor_size, "menu-choices")
        cells = {
            { n.menu_descriptor_widget_type, n.menu_selector_kind },
            { n.menu_descriptor_label, n.menu_text_template },
            { n.menu_descriptor_choice_count, #labels },
        }
        for i, label in ipairs(labels) do
            cells[#cells + 1] = { n.menu_descriptor_choices + 4 * (i - 1), label }
        end
    end
    if self.descriptors[key] == nil then
        self.descriptors[key] = self:descriptor(cells)
    end
    return self.descriptors[key]
end
function Rows:select(category)
    local current = assert(self.read:value(self.content + self.n.menu_current_category, "u32"))
    if current == category then
        return
    end
    self.ui:put(self.content + self.n.menu_previous_category, current)
    self.ui:call("menu_category_select", self.content, category)
end
function Rows:raw(row)
    if row.entry.range ~= nil then
        return self.read:value(row.at + self.n.menu_row_slider + self.n.menu_slider_value, "f32")
    end
    return self.read:value(row.at + self.n.menu_row_selector + self.n.menu_selector_index, "u32")
end
function Rows:put_values()
    for _, row in ipairs(self.rows) do
        local entry = row.entry
        if entry ~= nil then
            local slider = entry.range ~= nil
            self.ui:call(
                slider and "menu_slider_set" or "menu_selector_set",
                row.at + (slider and self.n.menu_row_slider or self.n.menu_row_selector),
                self.settings.editing[entry.id]
            )
            row.raw = self:raw(row)
        end
    end
end
function Rows:pending()
    self.reset = false
    for _, row in ipairs(self.rows) do
        if row.entry ~= nil and self.settings.defaults[row.entry.id] ~= self.settings.editing[row.entry.id] then
            self.reset = true
        end
    end
    self.ui:put(self.content + self.n.menu_unapplied, self.settings:dirty() and 1 or 0, 1)
end
function Rows:build(category)
    local ui, read, n, spec = self.ui, self.read, self.n, assert(self.panels[category + 1])
    local panel = self.content + spec.at
    local base, settings = assert(read:ptr(panel + n.menu_panel_rows)), assert(read:ptr(panel + spec.settings))
    local x, plan = assert(read:value(panel + spec.x, "f32")), assert(self.plans[category + 1])
    self.rows = {}
    ui:context(panel + n.menu_panel_container, function()
        ui:call("menu_release_rows", panel)
        local gap = 0
        for i, source in ipairs(plan.rows) do
            if source.gap then
                gap = gap - self.group_gap
            end
            local at = base + (i - 1) * n.menu_row_stride
            ui:call(
                "menu_row_init",
                at,
                ui:pair(x, (i - 1) * self.row_step + gap),
                self.pivot,
                self.pivot,
                0,
                settings,
                source.entry and self:option_descriptor(source.entry) or self.title_descriptor,
                n.menu_row_init_flag
            )
            ui:call("menu_row_grey", at, 1)
            ui:call("menu_row_grey", at, 0)
            ui:call("widget_attach", panel + n.menu_panel_container, at)
            self:label(at + n.menu_row_title, source.title)
            self.rows[i] = { at = at, entry = source.entry, title = source.title }
        end
        ui:put(panel + spec.count, #self.rows)
        ui:put(panel + spec.gap, ui.port:bits(gap))
        ui:put(panel + spec.selected, 0)
        self:put_values()
        if spec.scrolls == nil then
            ui:call("menu_finish_simple", panel)
        else
            local scroll, height = panel + n.menu_panel_scroll, #self.rows * self.scroll_row - gap
            if #self.rows > 0 then
                ui:call("menu_scroll_thumb", scroll, math.min(1, self.scroll_view / height))
                ui:call("menu_scroll_extent", scroll, height - self.scroll_view)
            end
            local over = #self.rows > 0 and height > self.scroll_view
            ui:call("widget_opacity_set", scroll, over and 1 or 0)
            if #self.rows > 0 and not over and read:value(scroll + n.menu_scroll_position, "f32") ~= 0 then
                ui:put(scroll + n.menu_scroll_position, 0)
                ui:call("menu_scroll_reset", scroll)
            end
            ui:put(panel + spec.scrolls, over and 1 or 0, 1)
        end
    end)
    self.category, self.panel, self.spec, self.described = category, panel, spec, nil
    self:pending()
end
function Rows:intact()
    local first = self.rows[1]
    return self.read:value(self.panel + self.spec.count, "u32") == #self.rows
        and (
            first == nil
            or self.read:value(first.at + self.n.menu_row_setting, "u32") == self.n.menu_inert_setting
                and self:label_is(first.at + self.n.menu_row_title, first.title)
        )
end
function Rows:open(screen)
    self:prepare()
    local n, ui = self.n, self.ui
    self.content = screen + n.menu_options_content
    self.saved = assert(self.read:value(self.content + n.menu_current_category, "u32"))
    self.settings:begin()
    for i = 0, n.menu_categories - 1 do
        local button, plan = self.content + n.menu_category_button + n.menu_category_stride * i, self.plans[i + 1]
        if plan then
            self:label(button + n.menu_category_text, plan.label)
        end
        ui:call("widget_shown_set", button, plan and 1 or 0)
    end
    self:select(0)
    self:build(0)
end
function Rows:close()
    if self.content == nil then
        return
    end
    local n, ui, read = self.n, self.ui, self.read
    for i = 0, n.menu_categories - 1 do
        local button = self.content + n.menu_category_button + n.menu_category_stride * i
        ui:call(
            "label_template_set",
            button + n.menu_category_text,
            read:value(read:module("game") + n.menu_category_labels + n.menu_category_record * i, "u32")
        )
        ui:call("widget_shown_set", button, 1)
    end
    ui:put(self.content + n.menu_unapplied, 0, 1)
    ui:call("menu_description_show", self.content + n.menu_description_box, 1, 1)
    ui:call("menu_describe_setting", self.content, n.menu_no_setting)
    ui:context(self.content + n.menu_first_panel + n.menu_panel_container, function()
        if self.category == 0 then
            ui:call("menu_release_rows", self.content + n.menu_first_panel)
            ui:call("menu_build_native_rows", self.content + n.menu_first_panel)
        else
            self:select(0)
        end
        self:select(self.saved)
    end)
    self:forget()
end
function Rows:forget()
    self.settings:cancel()
    self.content, self.rows, self.dialog, self.decided = nil, nil, nil, nil
end
function Rows:describe(index)
    if index == self.described then
        return
    end
    local row = index ~= nil and self.rows[index + 1] or nil
    local entry = row and row.entry
    local ui, read, n = self.ui, self.read, self.n
    local box = self.content + n.menu_description_box
    if entry == nil or entry.description == nil then
        ui:call("menu_description_show", box, 1, 1)
    else
        local title, body = box + n.menu_description_title, box + n.menu_description_body
        self:label(title, entry.title)
        self:label(body, entry.description)
        ui:call("measure_widget", title)
        ui:call("measure_widget", body)
        local function number(offset)
            return read:value(read:module("game") + offset, "f32")
        end
        local th = read:value(self.content + n.menu_description_title_height, "f32")
            * read:value(self.content + n.menu_description_title_scale, "f32")
        local bh = read:value(self.content + n.menu_description_body_height, "f32")
            * read:value(self.content + n.menu_description_body_scale, "f32")
        ui:call(
            "widget_position_set",
            body,
            ui:pair(number(n.menu_description_left), -th - number(n.menu_description_gap))
        )
        ui:call("widget_opacity_set", body, number(n.menu_opacity_full))
        ui:call(
            "widget_size_set",
            box + n.menu_description_frame,
            ui:pair(
                number(n.menu_description_width),
                th + bh + number(n.menu_description_pad) + number(n.menu_description_margin)
            )
        )
        ui:call("menu_description_show", box, 0, 1)
    end
    self.described = index
end
function Rows:triggered(input, action, group)
    local n = self.n
    local value = self.read:value(
        input + n.menu_action_states + (action + (group or 0) * n.menu_group_actions) * 2 ^ n.menu_action_shift,
        "u8"
    )
    return value ~= nil and value ~= 0
end
function Rows:actions(report)
    local n, ui, read, settings = self.n, self.ui, self.read, self.settings
    local input = read:ptr(read:module("game") + n.menu_input_state)
    if input == nil then
        return
    end
    local open = read:value(self.content + n.menu_dialog_state, "u32") == n.menu_dialog_open
    local decision
    if open then
        decision = ui:call("menu_dialog_decision", self.content + n.menu_dialog, input)
    elseif self.dialog ~= nil and not self.decided then
        local key = self.content + n.menu_dialog + n.menu_dialog_cancel_action
        local group, action = read:value(key, "u32"), read:value(key + 4, "u32")
        action = ui:call("menu_key_decode", ui.port:uint64(action, group))
        decision = self:triggered(input, action, group) and n.menu_dialog_cancelled or n.menu_dialog_confirmed
    end
    if self.dialog ~= nil and not self.decided and decision == n.menu_dialog_confirmed then
        if self.dialog == n.menu_reset_mode then
            for _, row in ipairs(self.rows) do
                if row.entry ~= nil then
                    assert(settings:edit(row.entry.id, settings.defaults[row.entry.id]))
                end
            end
        else
            settings:begin()
        end
        self:put_values()
        self:pending()
        self.decided = true
        report({ event = "menu", id = "settings", action = self.dialog == n.menu_reset_mode and "reset" or "discard" })
    elseif decision == n.menu_dialog_cancelled then
        self.decided = true
    end
    if not open then
        local had = self.dialog ~= nil
        self.dialog, self.decided = nil, nil
        if not had and settings:dirty() and self:triggered(input, self.apply_action) then
            local okay = settings.save ~= nil and settings:commit()
            if okay then
                self:pending()
                ui:call("menu_play_sound", 0, n.menu_apply_sound)
            end
            report({ event = "menu", id = "settings", action = okay and "apply" or "save-failed" })
        end
    end
end
function Rows:step(dt, report)
    local current = self.read:value(self.content + self.n.menu_current_category, "u32")
    if current ~= self.category then
        if current == nil or self.plans[current + 1] == nil then
            self:select(0)
            current = 0
        end
        self:build(current)
    elseif not self:intact() then
        self:build(current)
    end
    local n, ui = self.n, self.ui
    local index = self.read:value(self.panel + self.spec.selected, "u32")
    local row = index ~= nil and self.rows[index + 1] or nil
    if row ~= nil and row.entry ~= nil then
        local raw, entry = self:raw(row), row.entry
        if raw ~= nil and raw ~= row.raw then
            local value = raw
            if entry.range ~= nil then
                local places = 0
                while
                    places < 99
                    and tonumber((string.format("%." .. places .. "f", entry.step):gsub(",", "."))) ~= entry.step
                do
                    places = places + 1
                end
                value = tonumber((string.format("%." .. places .. "f", raw):gsub(",", ".")))
                value = math.max(entry.range[1], math.min(entry.range[2], value))
            end
            if self.settings:edit(entry.id, value) then
                row.raw = raw
                self:pending()
            end
        end
    end
    self:actions(report)
    ui:call("menu_options_visual", self.content, dt)
    ui:put(self.content + n.menu_reset_enabled, self.reset and 1 or 0, 1)
    ui:call("menu_hint_set", self.read:ptr(self.content + n.menu_hints), n.menu_reset_hint, self.reset and 1 or 0)
    if self.read:value(self.content + n.menu_dialog_state, "u32") == n.menu_dialog_open then
        local mode = self.read:value(self.content + n.menu_dialog_mode, "u32")
        if mode == 0 or mode == n.menu_reset_mode then
            self.dialog, self.decided = mode, nil
            ui:put(self.content + n.menu_dialog_mode, n.menu_reset_mode + 1)
        end
    end
    self:describe(index)
end
return Rows
