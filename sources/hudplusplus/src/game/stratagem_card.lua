local Card = {}
Card.__index = Card
function Card.new(ui)
    return setmetatable({ ui = ui }, Card)
end
function Card.tick_untouched(ui, name, ...)
    local random = assert(ui.read:module("game")) + ui.n.game_random
    local saved = assert(ui.read:text(random, 8))
    local okay, why = pcall(ui.call, ui, name, ...)
    ui:put(random, saved)
    if not okay then
        error(why, 0)
    end
end
local function overrun(ui, at)
    local spot = ui.read:vector(at + ui.n.stratagem_card_fill_0 + ui.n.widget_local_position, 2)
    return spot ~= nil and spot[2] > 0
end
function Card.carry(ui, to, from)
    local n = ui.n
    ui:put(
        to + n.component_card_denominator,
        overrun(ui, from) and n.component_card_span_unset
            or assert(ui.read:value(from + n.component_card_denominator, "u32"))
    )
end
function Card.rebase(ui, at, state)
    if state == ui.n.component_card_cooling and overrun(ui, at) then
        ui:put(at + ui.n.component_card_denominator, ui.n.component_card_span_unset)
    end
end
function Card.flatten(ui, at)
    local n = ui.n
    for _, offset in ipairs({
        n.stratagem_card_mask_0,
        n.stratagem_card_mask_1,
        n.stratagem_card_mask_2,
        n.stratagem_card_mask_3,
    }) do
        ui:material({ at = at + offset }, n.flat_mask_material)
    end
    for _, offset in ipairs({
        n.stratagem_card_fill_0,
        n.stratagem_card_fill_name,
        n.stratagem_card_badge_fill,
        n.stratagem_card_badge_back,
    }) do
        ui:material({ at = at + offset }, n.flat_fill_material)
    end
    ui:call(
        "picture_set",
        at + n.stratagem_card_noise,
        assert(ui:resource(n.flat_picture_material)),
        assert(ui:resource(n.stratagem_card_noise_texture)),
        0
    )
    ui:call(
        "text_font_set",
        at + n.stratagem_card_count_text,
        n.world_text_font,
        n.world_text_flat,
        n.stratagem_card_text_style,
        1,
        0
    )
    ui:call(
        "text_font_set",
        at + n.stratagem_card_uses_text,
        n.stratagem_card_uses_font,
        n.world_text_flat,
        n.stratagem_card_text_style,
        1,
        0
    )
end
function Card:create(parent, frame, layer, flat)
    local ui, n = self.ui, self.ui.n
    self.node = ui:node(n.component_card_size, self.node)
    local pair = ui:pair(0, 0)
    ui:call("component_card_create", self.node.at, pair, pair, pair, layer, 0)
    if flat then
        Card.flatten(ui, self.node.at)
    end
    ui:attach(parent, self.node)
    ui:show(self.node, false)
    self.created, self.row, self.identity, self.valid = frame, nil, nil, false
    return self.node
end
function Card:update(frame, dt, row, record, state, identity)
    local ui, n, node = self.ui, self.ui.n, self.node
    if node == nil or not node.live then
        return
    end
    if dt == nil or row == nil or record == nil or state == nil then
        ui:show(node, false)
        self.valid = false
        return
    end
    if frame == self.created then
        return
    end
    if not self.valid or self.row ~= row then
        ui:put(node.at + n.component_card_row, row)
    end
    if identity ~= nil and self.identity ~= identity then
        ui:put(node.at + n.component_card_state, 0)
    end
    ui:show(node, true)
    Card.rebase(ui, node.at, state)
    if state == n.component_card_zone0 then
        Card.tick_untouched(ui, "component_card_tick", node.at, dt, state, record)
    else
        ui:call("component_card_tick", node.at, dt, state, record)
    end
    self.row, self.identity, self.valid = row, identity, true
end
function Card:close()
    self.ui:destroy(self.node)
    self.valid = false
end
return Card
