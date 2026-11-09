local Pick = {}
Pick.__index = Pick
function Pick.new(ui, weapon)
    local judge, n = weapon.judge, weapon.n
    local mouse = stingray.Mouse
    local index_of, presses = assert(judge:routine("stratagem_action_index")), {}
    for direction, name in ipairs({
        "stratagem_press_key_1",
        "stratagem_press_key_2",
        "stratagem_press_key_3",
        "stratagem_press_key_4",
    }) do
        local high, low = weapon.read.bytes.words_of(n[name])
        local index = judge:call(index_of, high * 4294967296 + low)
        if index ~= nil then
            presses[direction] = n.stratagem_press_base + index * n.stratagem_press_shift
        end
    end
    local aim_high, aim_low = weapon.read.bytes.words_of(n.aim_action_key)
    return setmetatable({
        ui = ui,
        weapon = weapon,
        read = weapon.read,
        judge = judge,
        n = n,
        keyboard = stingray.Keyboard,
        aim = aim_high * 4294967296 + aim_low,
        consume = assert(judge:routine("action_consume")),
        release = assert(judge:routine("action_release")),
        consumed = assert(judge:routine("action_consumed_entry")),
        mouse = mouse,
        vector = stingray.Vector3,
        wheel_id = mouse ~= nil and mouse.axis_id("wheel") or nil,
        left_id = mouse ~= nil and mouse.button_id("left") or nil,
        start = n.stratagem_start_trigger_row * n.stratagem_press_shift,
        code_of = assert(judge:routine("stratagem_code_of")),
        press = assert(judge:routine("stratagem_arrow_press")),
        presses = presses,
        code = assert(judge:buffer("uint32_t", n.stratagem_input_capacity)),
        length = assert(judge:buffer("uint32_t", 1)),
    }, Pick)
end
local function start_cell(self)
    local system = self.weapon:manager(self.n.input_system_rva)
    if system ~= nil and system ~= 0 then
        return system + self.start
    end
end
function Pick:reset()
    local hold = self.hold
    self.row, self.number, self.written, self.played, self.wait, self.hold = nil, nil, nil, nil, nil, nil
    self.tempo = nil
    if hold ~= nil then
        local cell = start_cell(self)
        if cell ~= nil then
            self.ui:put(cell, hold)
        end
    end
end
local function block_aim(self)
    local system = self.weapon:manager(self.n.input_system_rva)
    if system == nil or system == 0 then
        return
    end
    local entry = self.judge:call(self.consumed, system, self.aim)
    if entry ~= nil and entry ~= 0 and self.read:value(entry, "u32") ~= 0 then
        return
    end
    self.judge:call(self.consume, system, self.aim, self.n.action_consume_seconds[1])
    self.blocking = true
end
local function unblock_aim(self)
    if not self.blocking then
        return
    end
    self.blocking = false
    local system = self.weapon:manager(self.n.input_system_rva)
    if system ~= nil and system ~= 0 then
        self.judge:call(self.release, system, self.aim)
    end
end
function Pick:leave()
    self.last = nil
end
function Pick:frame(remember)
    unblock_aim(self)
    if not self.stepped then
        self:reset()
    end
    self.stepped = false
    if not remember then
        self.last = nil
    end
end
local function gap(self, base)
    return base * self.tempo * (0.8 + 0.4 * math.random())
end
local function strain(body)
    local health = body ~= nil and body:health() or nil
    if health == nil then
        return 1
    end
    return 2 - math.max(0, math.min(1, health))
end
local function intact(self, input, count)
    local read, n = self.read, self.n
    return read:value(input, "u32") == count and read:value(input + n.stratagem_input_number, "u32") == 0
end
local function choices(self, list, skip)
    local read, n, out = self.read, self.n, {}
    for index = 0, n.stratagem_list_rows - 1 do
        local row = list.target + n.stratagem_list_first_row + index * n.stratagem_list_row_size
        local number = read:value(row + n.stratagem_row_number, "u32")
        if
            number ~= nil
            and number ~= 0
            and not (skip ~= nil and skip[number])
            and read:value(row + n.stratagem_row_visible, "u8") ~= 0
            and read:value(row + n.stratagem_row_card + n.component_card_state, "u32") == n.component_card_ready
        then
            local spot = read:vector(row + n.widget_local_position, 2)
            if spot ~= nil then
                out[#out + 1] = { index = index, row = row, number = number, y = spot[2] }
            end
        end
    end
    table.sort(out, function(a, b)
        return a.y > b.y or (a.y == b.y and a.index < b.index)
    end)
    return out
end
local function confirmed(self)
    local cell = start_cell(self)
    local trigger = cell ~= nil and self.read:value(cell, "u32") or nil
    if trigger == self.n.stratagem_start_hold then
        self.ui:put(cell, 0)
        self.hold = trigger
        return false
    end
    return self.hold ~= nil or self.mouse.released(self.left_id)
end
local function code(self, input, number)
    local read, n = self.read, self.n
    local context = self.weapon:manager(n.stratagem_code_context)
    local body = read:value(input + n.stratagem_input_avatar, "u32")
    if
        context == nil
        or context == 0
        or body == nil
        or body == read:value(self.weapon.game + n.avatar_absent, "u32")
        or body == self.weapon.invalid_player
    then
        return nil
    end
    self.length[0] = 0
    self.judge:call(self.code_of, context, body, number, 0, self.code, self.length, 0)
    local length = self.length[0]
    if length ~= 0 and length <= n.stratagem_input_capacity then
        return length
    end
end
local function enter(self, input, chosen)
    local read, n = self.read, self.n
    local length = code(self, input, chosen.number)
    if length == nil then
        return nil
    end
    local text = { read.bytes.pack(length, n.stratagem_input_arrows) }
    for index = 0, length - 1 do
        text[index + 2] = string.char(self.code[index] % 256)
    end
    self.ui:put(input, table.concat(text))
    self.ui:call("widget_opacity_set", chosen.row + n.stratagem_row_card, n.stratagem_card_restore[1])
    return length
end
local function play(self, world, input, base, dt)
    if not intact(self, input, self.played) then
        return self:reset()
    end
    block_aim(self)
    if self.wait > 0 then
        self.wait = self.wait - (dt or 0)
        if self.wait > 0 then
            return
        end
    end
    if self.played == 0 then
        self.written = code(self, input, self.number)
        if self.written == nil then
            return self:reset()
        end
    end
    if self.keyboard ~= nil and self.keyboard.any_pressed() ~= nil then
        return
    end
    local read, n = self.read, self.n
    local row = world.manager + world.index * n.stratagem_press_stride
    for _, at in pairs(self.presses) do
        if read:value(row + at, "u8") ~= 0 then
            return
        end
    end
    local at = self.presses[self.code[self.played] % 256]
    if at == nil then
        return self:reset()
    end
    self.ui:put(row + at, "\1")
    self.judge:call(self.press, input)
    self.played = self.played + 1
    if self.played >= self.written then
        return self:reset()
    end
    self.wait = self.wait + gap(self, base)
end
local function turn(self, input, list, wheel, skip, last)
    local rows = choices(self, list, skip)
    if #rows == 0 then
        return
    end
    local at, kept
    for place, row in ipairs(rows) do
        if row.index == self.row then
            at = place
        end
        if row.number == last then
            kept = place
        end
    end
    if at == nil and kept ~= nil then
        at = kept
    elseif at == nil then
        at = wheel < 0 and 1 or #rows
    else
        at = math.max(1, math.min(#rows, at + (wheel < 0 and 1 or -1)))
    end
    local chosen = rows[at]
    if chosen.index == self.row then
        return
    end
    local written = enter(self, input, chosen)
    if written ~= nil then
        self.row, self.number, self.written = chosen.index, chosen.number, written
    end
end
function Pick:step(world, input, list, base, dt, skip, remember, body)
    self.stepped = true
    if self.wheel_id == nil or self.left_id == nil then
        return
    end
    if self.played ~= nil then
        return play(self, world, input, base, dt)
    end
    local wheel = self.vector.y(self.mouse.axis(self.wheel_id))
    if wheel ~= 0 then
        turn(self, input, list, wheel, skip, self.last)
    end
    if self.row == nil or not confirmed(self) then
        return
    end
    if not intact(self, input, self.written) then
        return self:reset()
    end
    if remember then
        self.last = self.number
    end
    self.ui:put(input, 0, self.n.stratagem_input_arrows)
    self.played, self.tempo = 0, (1 + math.random()) * strain(body)
    self.wait = gap(self, base)
    block_aim(self)
end
return Pick
