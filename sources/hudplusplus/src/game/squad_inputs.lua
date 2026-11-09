local Inputs = {}
Inputs.__index = Inputs
function Inputs.new(weapon, comms)
    local self = setmetatable({ weapon = weapon, comms = comms, rows = {}, textures = {} }, Inputs)
    for _, name in ipairs({
        "player_of_avatar",
        "avatar_of_player",
        "dead_of",
        "stratagem_record",
        "material_texture_lookup",
        "worn_pack",
    }) do
        self[name] = assert(weapon.judge:routine(name))
    end
    return self
end
function Inputs:subject(panel, avatar, player, players, dead)
    local w, n = self.weapon, self.weapon.n
    local read, judge = w.read, w.judge
    if not panel.ready then
        return nil
    end
    local local_subject = avatar ~= nil
    if not local_subject then
        players = w:manager(n.roots_player_manager_rva)
        if players == nil then
            return nil
        end
        local count = read:value(players + n.roster_local_count, "u32")
        if count == nil or count == 0 then
            return nil
        end
        local first = read:ptr(players + n.roster_pointers)
        if first ~= nil then
            player = read:value(first + n.roster_id, "u32")
        end
        local camera = w:manager(n.camera_manager)
        if camera ~= nil then
            local head, tail = read:value(camera + n.camera_head, "u32"), read:value(camera + n.camera_tail, "u32")
            if head ~= nil and tail ~= nil then
                local current = camera + n.camera_fallback
                if head ~= tail then
                    current = camera + n.camera_entries + ((head - 1) % (n.camera_mask + 1)) * n.camera_stride
                end
                if read:value(current, "u16") == n.camera_spectator then
                    local id = read:value(current + n.camera_subject_avatar, "u32")
                    local manager = w:manager(n.roots_avatar_manager_rva)
                    if manager ~= nil and w:find(manager + n.roots_avatar_manager_map, id, w.invalid_player) ~= nil then
                        if judge:call(self.player_of_avatar, players, w.out, id) ~= nil then
                            local candidate = tonumber(w.out[0])
                            if candidate ~= w.invalid_local then
                                player = candidate
                            end
                        end
                    end
                end
            end
        end
        if player ~= nil and judge:call(self.avatar_of_player, players, w.out, player) ~= nil then
            avatar = tonumber(w.out[0])
        end
    end
    if avatar == nil or avatar == w.invalid_local then
        return nil
    end
    if not local_subject then
        local health = w:manager(n.health_manager)
        if health ~= nil then
            dead = judge:call(self.dead_of, health, avatar)
        end
    end
    local parent, weapon, bar = nil, panel.base + n.self_weapon_widget, panel.base + n.self_health_widget
    local opacity = read:value(weapon + n.hud_widgets_shown, "f32")
    if opacity ~= nil and opacity > 0 then
        parent = weapon
    else
        opacity = read:value(bar + n.hud_widgets_shown, "f32")
        if opacity ~= nil and opacity > 0 then
            parent = bar
        end
    end
    return { parent = parent, player = player, avatar = avatar, dead = dead }
end
function Inputs:icon(row, loadouts)
    local w, n, textures = self.weapon, self.weapon.n, self.textures
    local read, judge = w.read, w.judge
    if row.dead == true then
        row.skull = n.seat_skull_picture
        return
    end
    if row.dead ~= false then
        return
    end
    local mark = self.comms.pings and self.comms.pings[row.avatar]
    if mark ~= nil and row.avatar ~= w.invalid_player then
        local style = read:value(mark + n.comms_picture_style, "u32")
        local material
        if style == 0 then
            material = n.picture_material
        elseif style == 1 then
            material = n.ping_glyph_material
        elseif style == 2 then
            material = n.mask_material
        end
        if material ~= nil then
            local hash = read:value(mark + n.comms_picture, "hex64")
            if hash ~= nil and hash ~= "0000000000000000" then
                local picture = textures[hash]
                if picture == nil then
                    picture = false
                    local key = judge:uint64_of(hash)
                    if key ~= nil and judge:open(judge:app(), n.material_type, hash) == true then
                        local found = judge:call(self.material_texture_lookup, key, n.picture_texture_usage)
                        if type(found) == "string" and found ~= "0000000000000000" then
                            picture = found
                        end
                    end
                    textures[hash] = picture
                end
                if picture then
                    row.icon, row.material = picture, material
                    return
                end
            end
        end
    end
    if loadouts == nil then
        return
    end
    local index = w:find(loadouts + n.roster_rows_map, row.player, w.invalid_player)
    if index == nil then
        return
    end
    local number = read:value(loadouts + n.roster_rows_at + index * n.roster_rows_stride, "u32")
    if number ~= nil and number < n.booster_slots then
        row.booster = read:value(w.game + n.booster_table + number * n.booster_stride + n.booster, "hex64")
        row.icon, row.material = row.booster, n.picture_material
    end
end
function Inputs:calls(row, beacon, entries, history)
    local w, n = self.weapon, self.weapon.n
    local read, judge = w.read, w.judge
    if row.avatar == nil or row.avatar == w.invalid_player then
        return
    end
    local calls = self.comms.calls and self.comms.calls[row.avatar]
    row.calls = {}
    if calls == nil then
        return
    end
    for _, at in ipairs(calls) do
        local out = { beacon = read:value(at + n.marker_beacon, "u32") }
        row.calls[#row.calls + 1] = out
        if beacon ~= nil and entries ~= nil and history ~= nil then
            local index = w:find(beacon + n.beacon_map, out.beacon, w.invalid_player)
            if index ~= nil then
                local entry = entries + index * n.beacon_entry_size
                local key = read:value(entry + n.beacon_key, "key64")
                out.row = read:value(entry + n.beacon_row, "u32")
                if key and out.row ~= nil and out.row < n.stratagem_row_cap then
                    local record = judge:call(self.stratagem_record, history, judge:uint64_of(key))
                    if
                        record ~= nil
                        and record ~= 0
                        and read:value(record + out.row * n.stratagem_row_stride + n.stratagem_row_record, "u32")
                            ~= nil
                    then
                        out.record = record
                    end
                end
            end
        end
    end
end
function Inputs:supply(cell)
    local value = self.weapon.read:value(cell + self.weapon.n.squad_cell_share, "f32")
    if value == nil or value ~= value or value < 0 then
        return nil
    end
    return math.min(value, 1)
end
function Inputs:observe(panel, enabled, supply, avatar, player, players, dead)
    self.rows, self.view, self.textures = {}, nil, {}
    self.comms:observe(enabled and panel.editable)
    if not enabled or not panel.editable then
        return
    end
    local w, n = self.weapon, self.weapon.n
    local read = w.read
    local loadouts, beacon, history =
        w:manager(n.roster_rows_global), w:manager(n.beacon_manager), w:manager(n.stratagem_slots_global)
    local inventory
    local entries
    if beacon ~= nil then
        entries = read:ptr(beacon + n.beacon_entries)
    end
    local base = panel.mission + n.hud_widgets_panels_squad_panel_at
    local first = read:value(base, "u32")
    if first ~= nil and first ~= 0 then
        for index = 0, n.hud_squad_count - 1 do
            local at = base + n.hud_squad_first + index * n.hud_squad_stride
            local shown = read:value(at, "bit", n.widget_shown_bit)
            if shown ~= nil and shown ~= 0 then
                local death = read:value(at + n.hud_squad_death, "u32")
                local row = {
                    parent = at,
                    player = read:value(at + n.hud_squad_player, "u32"),
                    avatar = read:value(at + n.hud_squad_avatar, "u32"),
                }
                if death ~= nil then
                    row.dead = death ~= 0
                end
                self.rows[index + 1] = row
                row.edge = at + n.squad_weapon_object
                for slot = 2, 0, -1 do
                    local gear = at + n.squad_slot_base + slot * n.squad_slot_stride
                    local visible = read:value(gear, "bit", n.widget_shown_bit)
                    if visible ~= nil and visible ~= 0 then
                        row.edge = gear
                        break
                    end
                end
                if supply then
                    row.stim, row.ammo = self:supply(at + n.squad_stim_cell), self:supply(at + n.squad_weapon_object)
                end
                if supply and row.edge ~= at + n.squad_weapon_object then
                    row.pack = self:supply(at + n.squad_slot_base)
                    if inventory == nil then
                        inventory = w:manager(n.inventory_manager)
                    end
                    if
                        inventory ~= nil
                        and row.avatar ~= nil
                        and w.judge:call(self.worn_pack, inventory, w.out, row.avatar) ~= nil
                    then
                        row.pack_id = tonumber(w.out[0])
                    end
                end
                self:icon(row, loadouts)
                self:calls(row, beacon, entries, history)
            end
        end
    end
    self.view = self:subject(panel, avatar, player, players, dead)
    if self.view ~= nil then
        self:icon(self.view, loadouts)
    end
end
return Inputs
