local Inputs = {}
Inputs.__index = Inputs
local EMPTY = {}
function Inputs.new(weapon, panel)
    return setmetatable({
        weapon = weapon,
        panel = panel,
        reward_find = assert(weapon.judge:routine("reward_record_find")),
        sample_find = assert(weapon.judge:routine("sample_book_find")),
        kinds = {},
    }, Inputs)
end
function Inputs:clear()
    self.reward, self.loot, self.kinds, self.by_name = nil, nil, {}, {}
    self.map_parent, self.marker_parent, self.shown, self.center, self.pan, self.zoom, self.clip =
        nil, nil, nil, nil, nil, nil, nil
    self.reward_count, self.reward_peak = nil, nil
    self.reward_wanted = false
end
local function position(self, entity, manager, map, rows, stride, offset)
    local w = self.weapon
    if manager == nil then
        return nil
    end
    local index = w:find(manager + map, entity, w.invalid_entity)
    if index == nil then
        return nil
    end
    if rows ~= nil then
        return w.read:vector(rows + index * stride + offset, 3)
    end
end
function Inputs:rewards(wanted)
    local w, kinds = self.weapon, self.by_name
    local n, read = w.n, w.read
    local manager = w:manager(n.reward_manager)
    local count
    if manager ~= nil then
        count = read:value(manager + n.reward_count, "u32")
    end
    local cache = self.reward
    self.reward_count, self.reward_peak = nil, nil
    if not wanted or count == nil then
        self.reward, self.reward_wanted = nil, false
        return
    end
    if cache == nil or cache.manager ~= manager or cache.count ~= count then
        cache = { manager = manager, count = count, peak = read:value(manager + n.reward_peak, "u32") }
        self.reward = cache
    end
    local peak = cache.peak
    self.reward_peak = peak
    self.reward_wanted = count ~= nil and peak ~= nil and (self.shown or count == peak)
    if not self.reward_wanted or count > n.reward_slots then
        cache.medal, cache.super_credit, cache.positioned = nil, nil, nil
        return
    end
    self.reward_count = count
    if cache.medal == nil or (self.shown and not cache.positioned) then
        cache.medal, cache.super_credit, cache.medal_count, cache.super_credit_count = {}, {}, 0, 0
        local statics, rows
        if self.shown then
            statics = w:manager(n.static_position_manager)
            if statics ~= nil then
                rows = read:ptr(statics + n.static_position_array)
            end
        end
        for i = 0, count - 1 do
            local item = read:ptr(manager + n.reward_list + i * 8)
            if item ~= nil then
                local book = w.judge:call(self.reward_find, item)
                local kind
                if book ~= nil and book ~= 0 then
                    kind = read:value(book + n.reward_record_kind, "u32")
                end
                local name
                if kind == n.reward_kind_medal then
                    name = "medal"
                elseif kind == n.reward_kind_super_credit then
                    name = "super_credit"
                end
                if name ~= nil and kinds[name] ~= nil then
                    cache[name .. "_count"] = cache[name .. "_count"] + 1
                    if self.shown then
                        local entity = read:value(item + n.roots_entity_owner_entity_layout_id_at, "u32")
                        local at = position(
                            self,
                            entity,
                            statics,
                            n.static_position_map,
                            rows,
                            n.static_position_stride,
                            n.static_position_x
                        )
                        if at ~= nil then
                            cache[name][#cache[name] + 1] = at
                        end
                    end
                end
            end
        end
        cache.positioned = self.shown
    end
    for _, name in ipairs({ "super_credit", "medal" }) do
        local kind = kinds[name]
        if kind ~= nil then
            kind.remaining = cache[name .. "_count"]
            kind.points = cache[name]
        end
    end
end
function Inputs:samples(wanted)
    if not wanted or not self.shown then
        self.loot = nil
        return
    end
    local w, kinds = self.weapon, self.by_name
    local n, read = w.n, w.read
    local manager = w:manager(n.loot_manager)
    local count, capacity
    if manager ~= nil then
        count = read:value(manager + n.loot_count, "u32")
        capacity = read:value(manager + n.loot_capacity, "u32")
    end
    if count == nil or capacity == nil or count > capacity then
        self.loot = nil
        return
    end
    local cache = self.loot
    if cache == nil or cache.manager ~= manager or cache.count ~= count then
        cache = { manager = manager, count = count, super = {}, rare = {}, common = {} }
        local rows, physics = read:ptr(manager + n.loot_backref), w:manager(n.network_physics_manager)
        local live
        if physics ~= nil then
            live = read:ptr(physics + n.network_physics_live_array)
        end
        if rows ~= nil then
            for i = 0, count - 1 do
                local item = read:ptr(rows + i * 8)
                local book
                if item ~= nil then
                    local key = read:value(item, "key64")
                    if key ~= nil and key ~= false then
                        book = w.judge:call(self.sample_find, w.judge:uint64_of(key))
                    end
                end
                if book ~= nil and book ~= 0 then
                    local kind = read:value(book + n.sample_book_type, "u32")
                    local grade
                    if kind ~= nil then
                        grade = read:value(w.game + n.sample_type_grade + kind * n.sample_type_grade_stride, "u32")
                    end
                    local name
                    if grade == n.sample_grade_common then
                        name = "common"
                    elseif grade == n.sample_grade_rare then
                        name = "rare"
                    elseif grade == n.sample_grade_super then
                        name = "super"
                    end
                    if name ~= nil and kinds[name] ~= nil then
                        local entity = read:value(item + n.roots_entity_owner_entity_layout_id_at, "u32")
                        local at = position(
                            self,
                            entity,
                            physics,
                            n.network_physics_map,
                            live,
                            n.network_physics_live_stride,
                            n.network_physics_x
                        )
                        if at ~= nil then
                            cache[name][#cache[name] + 1] = at
                        end
                    end
                end
            end
        end
        self.loot = cache
    end
    for _, name in ipairs({ "super", "rare", "common" }) do
        if kinds[name] ~= nil then
            kinds[name].points = cache[name]
        end
    end
end
function Inputs:observe(kinds)
    local w, n = self.weapon, self.weapon.n
    local read = w.read
    local changed = self.kinds ~= kinds
    if changed then
        self:clear()
        self.kinds, self.by_name = kinds, {}
        for _, kind in ipairs(kinds) do
            self.by_name[kind.name] = kind
        end
    end
    self.center, self.pan, self.zoom, self.clip = nil, nil, nil, nil
    self.map_parent, self.marker_parent, self.shown = nil, nil, false
    if #kinds == 0 then
        self:clear()
        return
    end
    local mission = self.panel.mission
    local manager = mission ~= nil and mission - n.hud_widgets_mission_hud or nil
    if manager == nil then
        self:clear()
        return
    end
    local map = manager + n.mission_hud_map_view_at
    self.shown = w:map_open(manager) == true
    local marker, parent = map + n.map_marker_frame, map + n.map_view_map_frame
    local first, live = read:value(marker, "u32"), read:value(parent, "u32")
    if first ~= nil and first ~= 0 then
        self.marker_parent = marker
    end
    if live ~= nil and live ~= 0 then
        self.map_parent = parent
    end
    if changed then
        for _, kind in ipairs(kinds) do
            local name = kind.name
            local sample = name ~= "medal" and name ~= "super_credit"
            kind.material = sample and n.map_sample_material or n.map_marker_material
            if not sample then
                kind.picture = n[name .. "_picture"]
                kind.colour = self[name .. "_colour"] or read:vector(w.game + n[name .. "_colour"], 4)
                self[name .. "_colour"] = kind.colour
            end
        end
    end
    for _, kind in ipairs(self.kinds) do
        kind.remaining, kind.points = nil, EMPTY
        if self.shown and kind.name ~= "medal" and kind.name ~= "super_credit" then
            local offset = n["sample_grade_" .. kind.name] * n.sample_grade_stride
            kind.picture = read:value(w.game + n.sample_grade_pictures + offset, "hex64")
            kind.colour = read:vector(w.game + n.sample_grade_colours + offset, 4)
        end
    end
    self:rewards(self.by_name.medal ~= nil or self.by_name.super_credit ~= nil)
    self:samples(self.by_name.super ~= nil or self.by_name.rare ~= nil or self.by_name.common ~= nil)
    if self.shown then
        self.center, self.pan = read:vector(map + n.map_view_center_x, 2), read:vector(map + n.map_view_pan_x, 2)
        self.zoom = read:value(map + n.map_view_zoom, "f32")
        if self.center ~= nil and self.pan ~= nil and self.zoom ~= nil then
            if self.half == nil then
                self.half = read:value(w.game + n.spawn_throw_reach_at, "f32")
            end
        end
        self.clip = read:vector(map + n.map_marker_clip, 4)
        if self.scalar == nil then
            self.scalar = read:value(w.game + n.map_marker_scalar, "f32")
        end
    end
end
function Inputs:public(wrap)
    local input, out = self, {}
    function out:observe(kinds)
        input:observe(kinds)
        self.map_parent, self.marker_parent = wrap(input.map_parent), wrap(input.marker_parent)
        self.shown, self.center, self.pan, self.zoom = input.shown, input.center, input.pan, input.zoom
        self.half, self.clip, self.scalar = input.half, input.clip, input.scalar
        self.reward_count, self.reward_peak, self.reward_wanted =
            input.reward_count, input.reward_peak, input.reward_wanted
    end
    function out:clear()
        input:clear()
        self.map_parent, self.marker_parent, self.shown = nil, nil, false
        self.center, self.pan, self.zoom, self.half, self.clip, self.scalar = nil, nil, nil, nil, nil, nil
        self.reward_count, self.reward_peak, self.reward_wanted = nil, nil, false
    end
    return out
end
return Inputs
