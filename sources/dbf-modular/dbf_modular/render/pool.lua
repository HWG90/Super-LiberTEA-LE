-- Unique reload-stable DBF Modular GUI ledger. A failed/unknown world query is
-- NOT retirement. Hide before cleanup; retain each ID until destroy succeeds.
local Pool = {}
Pool.__index = Pool
local REGISTRY = "DBFModularScreenGuiPool"
function Pool.new(sr, globals)
    globals = globals or _G
    local registry = rawget(globals, REGISTRY)
    if registry == nil then
        registry = { version = 1, records = {} }
        rawset(globals, REGISTRY, registry)
    end
    assert(type(registry) == "table" and registry.version == 1, "Unsupported DBF Modular GUI ledger")
    return setmetatable({ sr = sr, registry = registry }, Pool)
end
function Pool:live(world)
    local application = self.sr.Application
    if not application or type(application.worlds) ~= "function" then
        return nil
    end
    local okay, worlds = pcall(application.worlds)
    if not okay or type(worlds) ~= "table" then
        return nil
    end
    for _, candidate in pairs(worlds) do
        if candidate == world then
            return true
        end
    end
    return false
end
function Pool:retire(record)
    self.registry.records[record.world] = nil
    record.owner, record.visible = nil, false
    for key in pairs(record.primitives) do
        record.primitives[key] = nil
    end
end
function Pool:hide(record)
    local live = self:live(record.world)
    if live == false then
        self:retire(record)
        return true
    end
    if live == nil then
        return false, "GUI world ownership unknown"
    end
    if record.visible ~= false then
        local okay, accepted = pcall(self.sr.Gui.set_visible, record.gui, false)
        if not okay or accepted == false then
            return false, "GUI hide refused: " .. tostring(accepted)
        end
        record.visible = false
    end
    return true
end
function Pool:clear(record)
    local okay, why = self:hide(record)
    if not okay then
        return false, why
    end
    if self.registry.records[record.world] ~= record then
        return true
    end
    record.failed = true
    for key, primitive in pairs(record.primitives) do
        local called, accepted = pcall(self.sr.Gui["destroy_" .. primitive.kind], record.gui, primitive.id)
        if not called or accepted == false then
            return false, "GUI primitive cleanup refused: " .. tostring(accepted)
        end
        record.primitives[key] = nil
    end
    local called, accepted = pcall(self.sr.Gui.reset, record.gui)
    if not called or accepted == false then
        return false, "GUI reset refused: " .. tostring(accepted)
    end
    record.failed = false
    return true
end
function Pool:acquire(world, owner)
    local live = self:live(world)
    if live ~= true then
        return nil, live == false and "GUI world retired" or "GUI world ownership unknown"
    end
    local record = self.registry.records[world]
    if record and record.owner and record.owner ~= owner then
        return nil, "GUI already owned"
    end
    if record and (record.failed or next(record.primitives) ~= nil or record.visible ~= false) then
        local okay, why = self:clear(record)
        if not okay then
            return nil, why
        end
    end
    if not record then
        local okay, gui = pcall(self.sr.World.create_screen_gui, world, "scale", 1, 1)
        if not okay or gui == nil or gui == false then
            return nil, "GUI creation refused: " .. tostring(gui)
        end
        record = { world = world, gui = gui, primitives = {}, visible = nil, failed = true, owner = owner }
        -- Publish the handle BEFORE the next native call can fail.
        self.registry.records[world] = record
        local hidden, why = self:hide(record)
        if not hidden then
            return nil, why
        end
        record.failed = false
    end
    record.owner = owner
    local pool, lease = self, { gui = record.gui, record = record }
    function lease:valid()
        if pool.registry.records[world] ~= record or record.owner ~= owner then
            return false, "GUI owner changed"
        end
        local alive = pool:live(world)
        if alive == false then
            pool:retire(record)
            return false, "GUI world retired"
        end
        if alive == nil then
            return false, "GUI world ownership unknown"
        end
        return not record.failed, record.failed and "GUI cleanup pending" or nil
    end
    function lease:hide()
        if pool.registry.records[world] ~= record then
            return true
        end
        if record.owner ~= owner then
            return false, "GUI owner changed"
        end
        return pool:hide(record)
    end
    function lease:show()
        local valid, why = self:valid()
        if not valid then
            return false, why
        end
        if record.visible ~= true then
            local okay, accepted = pcall(pool.sr.Gui.set_visible, record.gui, true)
            if not okay or accepted == false then
                return false, "GUI show refused: " .. tostring(accepted)
            end
            record.visible = true
        end
        return true
    end
    function lease:add(key, kind, ...)
        assert(
            pool.registry.records[world] == record and record.owner == owner and not record.failed,
            "GUI owner changed"
        )
        assert(record.primitives[key] == nil, "GUI primitive already owned")
        local id = pool.sr.Gui[kind](record.gui, ...)
        assert(id ~= nil and id ~= false, "GUI primitive creation refused")
        record.primitives[key] = { id = id, kind = kind }
        return id
    end
    function lease:remove(key)
        local primitive = record.primitives[key]
        if not primitive then
            return true
        end
        assert(pool.registry.records[world] == record and record.owner == owner, "GUI owner changed")
        local okay, accepted = pcall(pool.sr.Gui["destroy_" .. primitive.kind], record.gui, primitive.id)
        if not okay or accepted == false then
            return false, "GUI primitive cleanup refused: " .. tostring(accepted)
        end
        record.primitives[key] = nil
        return true
    end
    function lease:update(key, kind, ...)
        local primitive = assert(record.primitives[key], "GUI primitive not owned")
        assert(
            pool.registry.records[world] == record and record.owner == owner and not record.failed,
            "GUI owner changed"
        )
        assert(primitive.kind == kind, "GUI primitive kind changed")
        assert(pool.sr.Gui["update_" .. kind](record.gui, primitive.id, ...) ~= false, "GUI primitive update refused")
        return primitive.id
    end
    function lease:release()
        if pool.registry.records[world] ~= record then
            return true
        end
        if record.owner ~= owner then
            return false, "GUI owner changed"
        end
        local okay, why = pool:clear(record)
        if not okay then
            return false, why
        end
        record.owner = nil
        return true
    end
    return lease
end
-- Cleanup a published GUI even when acquire failed before returning a lease.
function Pool:release_owner(owner)
    for _, record in pairs(self.registry.records) do
        if record.owner == owner then
            local okay, why = self:clear(record)
            if not okay then
                return false, why
            end
            record.owner = nil
        end
    end
    return true
end
return Pool
