local Card = require("game.stratagem_card")
local List = {}
List.__index = List
function List.new(ui)
    return setmetatable({ ui = ui, names = {}, was = {}, faded = {} }, List)
end
function List:create(parent, frame)
    local ui, n = self.ui, self.ui.n
    local size = n.stratagem_list + n.stratagem_list_first_row + n.stratagem_list_row_size * n.stratagem_list_slots
    self.node = ui:node(size, self.node)
    self.target = self.node.owner + n.stratagem_list
    ui:call(
        "stratagem_panel_create",
        self.node.owner,
        ui:pair(0, 0),
        ui:pair(0.5, 1),
        ui:pair(0, 0),
        ui:pair(0.635, 0.871)
    )
    ui:scale(self.node, 0.6, 0.6)
    ui:call("widget_opacity_set", self.node.owner + n.stratagem_panel_root, n.stratagem_list_opacity[1])
    ui:call("widget_pivot_set", self.target, ui:pair(0, 0))
    ui:call("widget_opacity_set", self.node.owner + n.stratagem_panel_bracket, 0)
    local shadow, offset = n.stratagem_arrow_shadow_color, n.shadow_offset
    for index = 0, n.stratagem_list_rows - 1 do
        local row = self.target + n.stratagem_list_first_row + index * n.stratagem_list_row_size
        Card.flatten(ui, row + n.stratagem_row_card)
        ui:material({ at = row + n.stratagem_row_blur + n.blur_picture }, n.flat_blur_material)
        local name = row + n.stratagem_row_name
        self.names[index + 1] = name
        ui:call("text_font_set", name, n.stratagem_row_name_font, n.world_text_flat, n.stratagem_row_text_style, 1, 0)
        ui:call(
            "text_font_set",
            row + n.stratagem_row_state,
            n.stratagem_row_state_font,
            n.world_text_flat,
            n.stratagem_row_text_style,
            1,
            0
        )
        for arrow = 0, n.stratagem_row_arrows - 1 do
            local picture = { at = row + n.stratagem_row_arrow + arrow * n.stratagem_row_arrow_size }
            ui:call(
                "picture_set",
                picture.at,
                assert(ui:resource(n.choice_arrow_material)),
                assert(ui:resource(n.choice_arrow_picture)),
                0
            )
            ui:material_four(picture, n.shadow_color_key, shadow[1], shadow[2], shadow[3], shadow[4])
            ui:material_pair(picture, n.shadow_offset_key, offset[1], offset[2])
        end
    end
    ui:attach(parent, self.node)
    ui:show(self.node, false)
    self.created, self.valid = frame, false
    return self.node
end
function List:update(frame, dt, player, mode, original, dim, unready)
    local ui, n, node, faded = self.ui, self.ui.n, self.node, self.faded
    if node == nil or not node.live or frame == self.created then
        return
    end
    if mode ~= nil then
        ui:call("stratagem_list_input", self.target, mode)
        if mode == 0 then
            for at in pairs(faded) do
                faded[at] = nil
            end
        end
    end
    if dt == nil or player == nil or mode == nil then
        ui:show(node, false)
        self.valid = false
        return
    end
    ui:show(node, true)
    local opening, was = not self.valid and original ~= nil, self.was
    for at in pairs(faded) do
        if ui.read:value(at + n.component_card_state, "u32") == n.component_card_ready then
            ui:call("widget_opacity_set", at, n.stratagem_card_restore[1])
            faded[at] = nil
        end
    end
    if opening then
        for index = 0, n.stratagem_list_rows - 1 do
            local offset = n.stratagem_list_first_row + n.stratagem_row_card + index * n.stratagem_list_row_size
            was[index + 1] = ui.read:value(self.target + offset + n.component_card_state, "u32")
        end
    end
    Card.tick_untouched(ui, "stratagem_list_tick", self.target, dt, player, n.stratagem_open_full[1])
    if opening then
        for index = 0, n.stratagem_list_rows - 1 do
            local offset = n.stratagem_list_first_row + n.stratagem_row_card + index * n.stratagem_list_row_size
            local state = ui.read:value(original + offset + n.component_card_state, "u32")
            if state == n.component_card_calling or state == n.component_card_cooling then
                if state ~= was[index + 1] then
                    Card.carry(ui, self.target + offset, original + offset)
                else
                    Card.rebase(ui, self.target + offset, state)
                end
            end
            local at, row = self.target + offset, self.target + offset - n.stratagem_row_card
            local number = dim ~= nil and ui.read:value(row + n.stratagem_row_number, "u32") or nil
            if number ~= nil and dim[number] then
                ui:call("widget_opacity_set", at, n.stratagem_card_dim[1])
            elseif
                unready
                and ui.read:value(at + n.component_card_state, "u32") ~= n.component_card_ready
                and (number or ui.read:value(row + n.stratagem_row_number, "u32")) ~= 0
                and ui.read:value(row + n.stratagem_row_visible, "u8") ~= 0
            then
                ui:call("widget_opacity_set", at, n.stratagem_card_dim[1])
                faded[at] = true
            end
        end
    end
    for _, name in ipairs(self.names) do
        if ui.read:value(name + n.string_text_curved, "u8") ~= 0 then
            ui:call(
                "text_font_set",
                name,
                n.stratagem_row_name_font,
                n.world_text_flat,
                n.stratagem_row_text_style,
                1,
                0
            )
        end
    end
    self.valid = true
end
function List:close()
    self.ui:destroy(self.node)
    for at in pairs(self.faded) do
        self.faded[at] = nil
    end
    self.valid = false
end
return List
