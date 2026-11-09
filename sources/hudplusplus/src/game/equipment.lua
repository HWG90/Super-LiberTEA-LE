local Charge = require("game.charge")
local Throwable = require("game.throwable")
local Equipment = {}
Equipment.__index = Equipment
function Equipment.new(weapon, options)
    return setmetatable(
        { weapon = weapon, options = options, charge = Charge.new(weapon), throwable = Throwable.new(weapon) },
        Equipment
    )
end
function Equipment:select(avatar, needed)
    self.inventory, self.cell = nil, nil
    if not needed then
        return
    end
    local weapon, n = self.weapon, self.weapon.n
    self.inventory = weapon:manager(n.inventory_manager)
    self.cell = weapon:item(self.inventory, avatar, n.throwable_slot)
end
function Equipment:observe(inputs, wield, needed)
    self.wield, self.record, self.fire, self.fire_record = wield, nil, nil, nil
    self.fire_count, self.avatar_row = nil, nil
    if not needed then
        self.charge:observe(nil, nil, nil)
        self.throwable:choice(nil, false)
        return
    end
    local weapon, n = self.weapon, self.weapon.n
    self.record = weapon:record(wield)
    local mode
    mode, self.fire_count = self.options:mode()
    self.charge:observe(wield, self.record, mode)
    self.avatar_row = inputs.manager + inputs.index * n.roots_avatar_manager_controller_stride
    self.throwable:choice(self.cell, inputs.holding)
end
function Equipment:firing(avatar)
    local id = self.weapon:fire(avatar)
    self.fire, self.fire_record = id, self.record
    if id ~= self.wield then
        self.fire_record = self.weapon:record(id)
    end
end
return Equipment
