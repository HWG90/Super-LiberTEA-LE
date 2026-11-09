local List = require("game.stratagem_list")
local Card = require("game.stratagem_card")
local Inputs = require("game.stratagem_inputs")
local Stratagem = {}
Stratagem.__index = Stratagem
function Stratagem.new(ui, panel, weapon, pick)
    return setmetatable({
        ui = ui,
        panel = panel,
        inputs = Inputs.new(weapon),
        pick = pick,
        list = List.new(ui),
        card = Card.new(ui),
        off = {},
    }, Stratagem)
end
function Stratagem:vanilla(hidden)
    local panel, ui, n = self.panel, self.ui, self.ui.n
    if not panel.editable then
        self.edited = nil
        return
    end
    local group = panel.mission + n.hud_widgets_panels_stratagem_hud_at + n.stratagem_panel_group
    if self.edited ~= nil and (self.edited ~= group or not hidden) then
        if self.edited == group then
            ui:call("widget_opacity_set", group, n.widget_opacity_default[1])
        end
        self.edited = nil
    end
    if hidden and self.edited ~= group then
        ui:call("widget_opacity_set", group, 0)
        self.edited = group
    end
end
function Stratagem:prepare(enabled, world, arrow, list)
    return self.inputs:prepare(self.panel, world, enabled or arrow, list)
end
function Stratagem:observe(enabled, world, player, players, arrow, cell)
    if enabled or arrow then
        self.inputs:observe(self.panel, world, player, players, cell)
    end
    self:vanilla(enabled and self.inputs.showing == true)
    if not enabled then
        self:drop()
    elseif not self.inputs.showing then
        if self.segment and self.ui:alive(self.root) == true then
            self.list:update(nil, nil, nil, 0)
        end
        self:hide()
    end
    self.segment = enabled and self.inputs.showing == true
    self.world = world
    return self.inputs.showing
end
function Stratagem:create(parent, frame)
    local ui, n = self.ui, self.ui.n
    ui:context(parent, function()
        self.root = ui:frame(self.root)
        ui:size(self.root, 140, 90)
        ui:opacity(self.root, 0)
        ui:attach(parent, self.root)
        self.listing = ui:frame(self.listing)
        ui:size(self.listing, 140, 90)
        ui:attach(self.root.at, self.listing)
        self.list:create(self.listing.at, frame)
        local card = self.card:create(self.root.at, frame, n.stratagem_row_card_layer, true)
        ui:anchor(card, 0.5, 0.5)
        ui:pivot(card, 0.5, 0.5)
        ui:scale(card, 0.6, 0.6)
        ui:call("widget_opacity_set", card.at + n.stratagem_uses_widget, 0)
    end)
    self.parent = parent
end
function Stratagem:put(parent, frame, values)
    local ui, input = self.ui, self.inputs
    local alive = ui:alive(self.root)
    if alive == nil then
        return false
    end
    if self.parent ~= parent or not alive then
        self:drop()
        self:create(parent, frame)
    end
    ui:show(self.root, true)
    ui:position(self.listing, values["hud.stratagem3d.list_x"], values["hud.stratagem3d.list_y"])
    ui:position(self.card.node, values["hud.stratagem3d.icon_x"], values["hud.stratagem3d.icon_y"])
    ui:show(self.listing, input.listing == true)
    local pick, list, off = self.pick, self.list, self.off
    off[ui.n.sos_stratagem] = values["hud.stratagem3d.skip_sos"] == 1 or nil
    off[ui.n.eagle_rearm_stratagem] = values["hud.stratagem3d.skip_rearm"] == 1 or nil
    if next(off) == nil then
        off = nil
    end
    local wheel = pick ~= nil and values["hud.stratagem3d.pick"] == 1
    if wheel and input.listing and list.valid then
        pick:step(
            self.world,
            input.input,
            list,
            values["hud.stratagem3d.pick_gap"],
            self.panel.dt,
            off,
            values["hud.stratagem3d.pick_remember"] == 1,
            self.panel
        )
    end
    self.list:update(frame, self.panel.dt, input.player, input.mode, input.original, off, wheel)
    self.card:update(frame, self.panel.dt, input.row, input.card_record, ui.n.component_card_ready)
    ui:fade(self.root, true, ui.n.widget_fade_alpha[1], ui.n.widget_fade_seconds[1])
    return true
end
function Stratagem:hide()
    if self.root ~= nil and self.root.live then
        self.ui:opacity(self.root, 0)
        self.ui:show(self.root, false)
    end
    self.list:update(nil, nil)
    self.card:update(nil, nil)
end
function Stratagem:drop()
    self.list:close()
    self.card:close()
    self.ui:destroy(self.listing)
    self.ui:destroy(self.root)
    self.parent = nil
end
function Stratagem:close()
    self:vanilla(false)
    self:drop()
end
return Stratagem
