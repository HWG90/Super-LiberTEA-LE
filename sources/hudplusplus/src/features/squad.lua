local Inputs = require("game.squad_inputs")
local Card = require("game.stratagem_card")
local BOOSTERS = require("game.resources").boosters
local Feature = {}
Feature.__index = Feature
function Feature.new(ui, weapon, comms)
    return setmetatable({ ui = ui, inputs = Inputs.new(weapon, comms), seats = {}, frame = 0, time = 0 }, Feature)
end
local function reparent(ui, held, parent, root)
    if held.parent ~= parent then
        ui:call("widget_detach", root.at)
        ui:context(parent, function()
            ui:attach(parent, root)
        end)
        held.parent = parent
    end
end
local function close_status(ui, seat)
    ui:destroy(seat.icon)
    ui:destroy(seat.skull)
    ui:destroy(seat.root)
    seat.parent = nil
end
function Feature:vectors(node, material)
    local ui, w = self.ui, self.inputs.weapon
    local n = ui.n
    if material == n.seat_skull_picture or material == n.ping_glyph_material or material == n.mask_material then
        if self.bend == nil then
            self.bend = w.read:vector(w.game + n.picture_bend_data, 4)
        end
        if material == n.mask_material then
            if self.white == nil then
                self.white = w.read:vector(w.game + n.mask_white, 4)
            end
            if self.white ~= nil then
                ui:material_four(node, n.mask_c0, unpack(self.white))
                ui:material_four(node, n.mask_c1, unpack(self.white))
            end
            if self.bend ~= nil then
                ui:material_four(node, n.mask_c2, unpack(self.bend))
            end
        else
            if self.face == nil then
                self.face = w.read:vector(w.game + n.picture_face_data, 2)
            end
            if self.bend ~= nil then
                ui:material_four(node, n.picture_bend_key, unpack(self.bend))
            end
            if self.face ~= nil then
                ui:material_pair(node, n.picture_face_key, unpack(self.face))
            end
        end
    end
end
function Feature:status(seat, row, subject)
    local ui, n = self.ui, self.ui.n
    if row == nil or row.parent == nil then
        close_status(ui, seat)
        return
    end
    local alive = ui:alive(seat.root)
    if alive == nil then
        return
    end
    if not alive then
        close_status(ui, seat)
        seat.fresh = true
        ui:context(row.parent, function()
            seat.root = ui:frame(seat.root)
            ui:attach(row.parent, seat.root)
            ui:size(seat.root, 0, 0)
            ui:anchor(seat.root, 0, 1)
            ui:position(seat.root, subject and -8 or -18, 12)
            seat.skull = ui:image_node(seat.skull)
            seat.icon = ui:image_node(seat.icon)
            for _, node in ipairs({ seat.skull, seat.icon }) do
                ui:size(node, 36, 36)
                ui:pivot(node, 0.5, 0.5)
                ui:layer(node, n.squad_picture_layer)
                ui:attach(seat.root.at, node)
            end
        end)
        seat.parent = row.parent
    else
        reparent(ui, seat, row.parent, seat.root)
    end
    ui:show(seat.root, row.player ~= nil)
    if row.skull ~= nil then
        if seat.skull.material ~= row.skull then
            ui:material(seat.skull, row.skull)
            self:vectors(seat.skull, row.skull)
            seat.skull.material = row.skull
        end
        ui:show(seat.skull, true)
    else
        ui:show(seat.skull, false)
    end
    local texture = row.icon
    if row.booster ~= nil then
        texture = BOOSTERS[row.booster]
    end
    ui:image(seat.icon, texture, row.material or n.picture_material)
    if texture ~= nil then
        self:vectors(seat.icon, row.material)
    end
end
local function close_calls(ui, held)
    for _, card in ipairs(held.cards) do
        card:close()
    end
    ui:destroy(held.root)
    held.parent = nil
end
function Feature:calls(held, row, dt)
    local ui, n = self.ui, self.ui.n
    if row == nil or row.edge == nil then
        close_calls(ui, held)
        return
    end
    local alive = ui:alive(held.root)
    if alive == nil then
        return
    end
    if not alive then
        close_calls(ui, held)
        ui:context(row.edge, function()
            held.root = ui:frame(held.root)
            ui:size(held.root, 0, 0)
            ui:anchor(held.root, 1, 0.5)
            ui:attach(row.edge, held.root)
        end)
        held.parent = row.edge
    else
        reparent(ui, held, row.edge, held.root)
    end
    local calls = row.calls or {}
    ui:show(held.root, #calls > 0)
    for index, call in ipairs(calls) do
        local card = held.cards[index]
        if card == nil then
            card = Card.new(ui)
            held.cards[index] = card
        end
        local live = ui:alive(card.node)
        if live == false then
            ui:context(row.edge, function()
                local node = card:create(held.root.at, self.frame, n.component_card_squad_layer, false)
                ui:anchor(node, 1, 0.5)
                ui:pivot(node, 0, 0.5)
                ui:position(node, 8 + (index - 1) * 52, 0)
                ui:call("widget_opacity_set", node.at + n.stratagem_uses_widget, 0)
            end)
        end
        if live ~= nil then
            card:update(self.frame, dt, call.row, call.record, n.component_card_calling, call.beacon)
        end
    end
    for index = #calls + 1, #held.cards do
        held.cards[index]:update(self.frame, nil)
    end
end
local FILL_OPACITY = 0.3
local function close_fills(ui, fills)
    for _, fill in pairs(fills) do
        ui:destroy(fill.node)
        fill.parent = nil
    end
end
function Feature:fill(fill, cell, share, fresh)
    local ui, n = self.ui, self.ui.n
    if fresh or fill.node == nil or not fill.node.live or fill.parent ~= cell then
        local read = self.inputs.weapon.read
        local width = read:value(cell + n.widget_local_size, "f32")
        local height = read:value(cell + n.widget_local_size + 4, "f32")
        ui:destroy(fill.node)
        fill.parent = nil
        if width == nil or height == nil then
            return
        end
        ui:context(cell, function()
            local node = ui:image_node(fill.node)
            fill.node = node
            ui:image(node, n.squad_fill_texture, n.squad_fill_material)
            ui:call("widget_uv_set", node.at, ui:pair(0.5, 0.5), ui:pair(0.5, 0.5))
            local tint = n.squad_bracket_vector
            ui:colour(node, tint[2], tint[3], tint[4])
            ui:opacity(node, FILL_OPACITY)
            ui:layer(node, n.squad_cell_blur_layer)
            ui:size(node, width, height)
            ui:anchor(node, 0.5, 0)
            ui:pivot(node, 0.5, 0)
            ui:position(node, 0, 0)
            ui:attach(cell, node)
        end)
        fill.parent = cell
    end
    if share == nil or share <= 0 then
        ui:show(fill.node, false)
        return
    end
    ui:scale(fill.node, 1, share)
    ui:show(fill.node, true)
end
function Feature:step(panel, enabled, avatar, player, players, dead)
    self.frame = self.frame + 1
    local dt = panel.dt
    self.time = self.time + (dt or 0)
    local supply = enabled and (dt == nil or self.supply_at == nil or self.time >= self.supply_at)
    if supply then
        self.supply_at = self.time + 1 / 4
    elseif not enabled then
        self.supply_at = nil
    end
    self.inputs:observe(panel, enabled, supply, avatar, player, players, dead)
    local n = self.ui.n
    for i = 1, n.hud_squad_count + 1 do
        local seat = self.seats[i]
        if seat == nil then
            seat = { calls = { cards = {} }, fills = { stim = {}, ammo = {}, pack = {} } }
            self.seats[i] = seat
        end
        local subject = i > n.hud_squad_count
        local row = subject and self.inputs.view or self.inputs.rows[i]
        seat.fresh = false
        self:status(seat, row, subject)
        if not subject then
            self:calls(seat.calls, row, panel.dt)
            if row == nil then
                close_fills(self.ui, seat.fills)
                seat.pack_id, seat.shares_of = nil, nil
            else
                local pack = row.parent + n.squad_slot_base
                if
                    seat.fresh
                    or seat.shares_of ~= row.parent
                    or seat.shares_player ~= row.player
                    or seat.shares_avatar ~= row.avatar
                then
                    seat.stim, seat.ammo, seat.pack, seat.shares_of = nil, nil, nil, nil
                end
                if supply then
                    local share = row.pack
                    if row.pack_id == nil or row.pack_id ~= seat.pack_id then
                        if row.pack_id ~= nil then
                            self.ui:put(pack + n.squad_cell_share, n.squad_cell_unset, 4)
                        end
                        share = nil
                    end
                    seat.pack_id = row.pack_id
                    seat.stim, seat.ammo, seat.pack, seat.shares_of = row.stim, row.ammo, share, row.parent
                    seat.shares_player, seat.shares_avatar = row.player, row.avatar
                end
                self:fill(seat.fills.stim, row.parent + n.squad_stim_cell, seat.stim, seat.fresh)
                self:fill(seat.fills.ammo, row.parent + n.squad_weapon_object, seat.ammo, seat.fresh)
                self:fill(seat.fills.pack, pack, seat.pack, seat.fresh)
            end
        end
    end
end
function Feature:close()
    for _, seat in ipairs(self.seats) do
        close_status(self.ui, seat)
        close_calls(self.ui, seat.calls)
        if seat.fills ~= nil then
            close_fills(self.ui, seat.fills)
        end
    end
end
return Feature
