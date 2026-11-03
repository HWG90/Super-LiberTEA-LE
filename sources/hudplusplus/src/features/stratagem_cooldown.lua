local Card = require("game.stratagem_card")
local Gauge = require("game.gauge")
local Wake = require("game.wake")
local Feature = {}
Feature.__index = Feature
local CARD_GAP = 4
local IDLE_DIM = 0.5
function Feature.new(ui, panel, inputs)
    local n = ui.n
    local blocked = {
        [n.component_card_calling] = true,
        [n.component_card_cooling] = true,
        [n.component_card_zone0] = true,
        [n.component_card_zone1] = true,
    }
    local row_cells =
        ui.read.layout({ { n.stratagem_row_card + n.component_card_state, "u32" }, { n.stratagem_row_raised, "u8" } })
    return setmetatable({
        ui = ui,
        panel = panel,
        inputs = inputs,
        blocked = blocked,
        cards = {},
        states = {},
        raised = {},
        mission = {},
        bright = {},
        shown = {},
        root_place = {},
        scene = {},
        wake = Wake.new(1),
        row_cells = row_cells,
        row_values = {},
    }, Feature)
end
function Feature:observe(values, ready, clock, avatar, players, held)
    self.enabled = values["hud.weapon3d.cooldown"] == 1
    if not self.enabled then
        self:close()
        return false
    end
    self.avatar, self.players = avatar, players
    if not ready then
        clock = nil
    end
    self.scene[1] = held == true
    self.awake = self.wake:step(clock, self.scene, held == true, values["hud.world3d.fire_time"])
    return true
end
local function read_rows(self)
    local ui, n, states, raised = self.ui, self.ui.n, self.states, self.raised
    for row = 1, n.stratagem_list_rows do
        states[row], raised[row] = nil, nil
    end
    self.record = nil
    local record = self.inputs:history(self.avatar, self.players)
    local rows
    if record ~= nil then
        rows = ui.read:value(record + n.stratagem_record_rows, "u32")
    end
    if rows == nil then
        return
    end
    self.record, self.rows_at = record, self.inputs:wrapper(self.panel) + n.stratagem_list + n.stratagem_list_first_row
    local cells, values = self.row_cells, self.row_values
    for row = 1, math.min(rows, n.stratagem_list_rows) do
        local got = ui.read:value(self.rows_at + (row - 1) * n.stratagem_list_row_size, cells, values)
        if got ~= nil then
            states[row], raised[row] = got[1], got[2]
        end
    end
end
local function visible(self, row, idle)
    local n, state = self.ui.n, self.states[row]
    if state == nil then
        return nil
    end
    local raised, card = self.raised[row] ~= nil and self.raised[row] ~= 0, self.cards[row]
    local seen = card ~= nil and (card.valid or (card.view ~= nil and card.view.lit))
    if
        not self.blocked[state]
        and state ~= n.component_card_unavailable
        and not (state == n.component_card_ready and raised and seen)
    then
        return nil
    end
    local bright = raised or self.awake == true
    if not bright and not (idle > 0) and not seen then
        return nil
    end
    local mission = self.ui.read:value(self.record + (row - 1) * n.stratagem_row_stride + n.stratagem_row_mission, "u8")
    if mission == nil or (mission ~= 0 and state ~= n.component_card_calling) then
        return nil
    end
    return mission, bright
end
local function hide_card(card, frame)
    if card.view == nil or (not card.valid and not card.view.lit) then
        return
    end
    card:update(frame, nil)
    card.view.lit, card.place[1] = false, nil
end
function Feature:create(parent)
    local ui = self.ui
    ui:context(parent, function()
        self.root = ui:frame(self.root)
        ui:size(self.root, 0, 0)
        ui:anchor(self.root, 0.5, 0.5)
        ui:pivot(self.root, 0.5, 0.5)
        ui:opacity(self.root, 0)
        ui:attach(parent, self.root)
    end)
    self.parent, self.root_place[1], self.root_place[2] = parent, nil, nil
end
function Feature:card(row, frame, scale, bright, idle, full, seconds)
    local ui, n = self.ui, self.ui.n
    local card = self.cards[row]
    if card == nil then
        card = Card.new(ui)
        self.cards[row] = card
    end
    local alive = ui:alive(card.node)
    if alive == nil then
        return nil
    end
    if not alive then
        ui:context(self.parent, function()
            local node = card:create(self.root.at, frame, n.stratagem_row_card_layer, true)
            ui:anchor(node, 0.5, 0.5)
            ui:pivot(node, 0.5, 0.5)
        end)
        card.size, card.scale = ui.read:vector(card.node.at + n.widget_local_size, 2), nil
        card.place, card.view = card.place or {}, card.view or { ui = ui }
        card.place[1], card.view.root, card.view.lit = nil, card.node, false
        return nil
    end
    if card.size == nil then
        return nil
    end
    if not Gauge.display(card.view, bright, idle, full, seconds, IDLE_DIM) then
        hide_card(card, frame)
        return nil
    end
    if card.scale ~= scale then
        ui:scale(card.node, scale, scale)
        card.scale = scale
    end
    local state, fresh = self.states[row], not card.valid
    card:update(frame, self.panel.dt, row - 1, self.record, state)
    if fresh and card.valid and (state == n.component_card_calling or state == n.component_card_cooling) then
        Card.carry(ui, card.node.at, self.rows_at + (row - 1) * n.stratagem_list_row_size + n.stratagem_row_card)
    end
    if card.valid then
        return card
    end
end
function Feature:put(parent, frame, values, fixed, spot, size, keep, pixel)
    if not self.enabled then
        return false
    end
    local ui, n = self.ui, self.ui.n
    local alive = ui:alive(self.root)
    if alive == nil then
        return false
    end
    if self.parent ~= parent or not alive then
        self:drop()
        self:create(parent)
    end
    read_rows(self)
    local scale, gap = values["hud.weapon3d.cooldown_size"], values["hud.weapon3d.cooldown_gap"]
    local idle, full, seconds = values["hud.world3d.idle"], values["hud.weapon3d.opacity"], n.widget_fade_seconds[1]
    local mission, bright, shown, pitch, height = self.mission, self.bright, self.shown, 0, 0
    for index = #shown, 1, -1 do
        shown[index] = nil
    end
    for row = 1, n.stratagem_list_rows do
        mission[row], bright[row] = nil, nil
        if self.record ~= nil then
            mission[row], bright[row] = visible(self, row, idle)
        end
        local card = self.cards[row]
        if mission[row] == nil and card ~= nil then
            hide_card(card, frame)
        end
    end
    for pass = 1, 2 do
        for row = 1, n.stratagem_list_rows do
            if mission[row] ~= nil and (mission[row] ~= 0) == (pass == 1) then
                local card = self:card(row, frame, scale, bright[row], idle, full, seconds)
                if card ~= nil then
                    shown[#shown + 1] = card
                    pitch, height =
                        math.max(pitch, (card.size[1] + CARD_GAP) * scale), math.max(height, card.size[2] * scale)
                end
            end
        end
    end
    if #shown == 0 then
        self:hide()
        return false
    end
    ui:fade(self.root, true, 1, seconds)
    local toward = Gauge.toward(values["hud.weapon3d.layout"])
    local x, y = Gauge.centre(1, toward, fixed, spot)
    if toward[1] ~= 0 then
        y = y - size[2] / 2 - gap - height / 2
    else
        x = x + size[1] / 2 + gap + pitch * #shown / 2
    end
    Gauge.approach(ui, self.root, self.root_place, x, y, keep, pixel)
    for index, card in ipairs(shown) do
        Gauge.approach(ui, card.node, card.place, (index - (#shown + 1) / 2) * pitch, 0, keep, pixel)
    end
    return true
end
function Feature:hide()
    if self.root ~= nil and self.root.live then
        self.ui:opacity(self.root, 0)
    end
    self.root_place[1] = nil
end
function Feature:drop()
    for row, card in pairs(self.cards) do
        card:close()
        self.cards[row] = nil
    end
    self.ui:destroy(self.root)
    self.parent = nil
end
function Feature:close()
    if next(self.cards) == nil and (self.root == nil or not self.root.live) and self.wake.clock == nil then
        return
    end
    self:drop()
    self.wake:clear()
end
return Feature
