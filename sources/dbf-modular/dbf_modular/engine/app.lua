-- Sole API-1 owner. Original Core order, then one read-only Bracket pass.
local Store = mod.require("settings/store.lua")
local Menu = mod.require("settings/menu.lua")
local Core = mod.require("core/dbf.lua")
local HUD = mod.require("hud/controller.lua")
local Schema = mod.require("settings/schema.lua")
local App = {}
App.__index = App
function App.new(context, globals, deps)
    return setmetatable({ context = context, globals = globals or _G, deps = deps or {}, state = "new" }, App)
end
function App:report(text)
    if self.last_report == text then
        return
    end
    self.last_report = text
    if type(self.context.log) == "function" then
        pcall(self.context.log, "DBF Modular: " .. tostring(text))
    end
end
function App:enable()
    if self.state ~= "new" then
        return false, "DBF Modular is already enabled or retiring"
    end
    if
        rawget(self.globals, "DBFModular")
        or rawget(self.globals, "DiversBestFriend")
        or rawget(self.globals, "NativeStratagemRadial")
    then
        return false, "Another DBF provider is active"
    end
    self.state = "starting"
    rawset(self.globals, "DBFModular", self)
    local okay, why = pcall(function()
        local deps = {
            globals = self.globals,
            report = function(text)
                self:report(text)
            end,
        }
        self.store = (self.deps.Store or Store).new(self.context, self.globals, self.deps.storage)
        self.menu = (self.deps.Menu or Menu).new(self.store, function()
            return rawget(self.globals, "DBFMCM")
        end)
        -- Public definitions exist before the original native engine starts.
        self.menu:update()
        deps.settings = self.store
        self.core = (self.deps.Core or Core).new(self.context, deps)
        local enabled, reason = self.core:enable()
        assert(enabled ~= false, reason)
        deps.core = self.core
        self.hud = (self.deps.HUD or HUD).new(deps)
        if type(self.context.expose) == "function" then
            local fields = {}
            for _, definition in ipairs(Schema.definitions) do
                local id = definition.id
                local parent = fields
                local segments = {}
                for segment in id:gmatch("[^.]+") do
                    segments[#segments + 1] = segment
                end
                for index = 1, #segments - 1 do
                    local segment = segments[index]
                    parent[segment] = parent[segment] or {}
                    parent = parent[segment]
                end
                parent[segments[#segments]] = {
                    type = type(definition.default),
                    get = function()
                        return self.store:get(id)
                    end,
                    set = function(value)
                        if self.state ~= "running" then
                            return false, "DBF Modular is retiring"
                        end
                        return self.store:set(id, value)
                    end,
                }
            end
            fields.hud.ads_expand = fields.hud.ads_minimal
            local release = self.context.expose("dbf_modular", {
                settings = fields,
                status = {
                    get = function()
                        return self:status()
                    end,
                },
            })
            if type(release) == "function" then
                self.console_release = release
            end
        end
        self.state = "running"
    end)
    if not okay then
        self.error = tostring(why)
        local clean, problem = self:close()
        return false, self.error .. (clean and "" or "; cleanup refused: " .. tostring(problem))
    end
    self:report(
        "enabled v0.1.0-dev.23; build26251122; animated player/weapon anchors; Quiet aiming minimizes routine details"
    )
    return true
end
function App:status()
    return {
        state = self.state,
        error = self.error,
        hud = self.hud and self.hud.status,
        settings = self.menu and self.menu.status,
        core = self.core and self.core:services(),
    }
end
function App:update(dt)
    if self.state ~= "running" then
        return
    end
    self.menu:update()
    local core_ok, core_reason = pcall(self.core.update, self.core, dt)
    if not core_ok then
        self:report("Core update suspended: " .. tostring(core_reason))
        local hidden, hide_reason = pcall(self.hud.fallback, self.hud, core_reason)
        if not hidden then
            self.error = tostring(hide_reason)
            self:report(self.error)
        end
        return
    end
    local okay, why = pcall(self.hud.update, self.hud, dt)
    if not okay then
        self:report("HUD suspended: " .. tostring(why))
        local hidden, hide_reason = pcall(self.hud.fallback, self.hud, why)
        if not hidden then
            self.error = tostring(hide_reason)
            self:report(self.error)
        end
    end
end
function App:close()
    if self.state == "closed" or self.state == "new" then
        return true
    end
    self.state = "retiring"
    for _, name in ipairs({ "hud", "core", "menu", "store" }) do
        local owner = self[name]
        if owner then
            local called, accepted, why = pcall(owner.close, owner)
            if not called or accepted ~= true then
                self.error = "Cleanup refused by " .. name .. ": " .. tostring(called and why or accepted)
                return false, self.error
            end
        end
    end
    if self.console_release then
        local called, accepted = pcall(self.console_release)
        if not called or accepted == false then
            return false, "Console cleanup refused"
        end
        self.console_release = nil
    end
    if rawget(self.globals, "DBFModular") == self then
        rawset(self.globals, "DBFModular", nil)
    end
    self.state = "closed"
    return true
end
function App.descriptor(context, globals)
    local app
    local function retire()
        if not app then
            return true
        end
        local okay, why = app:close()
        if okay then
            app = nil
        end
        return okay, why
    end
    return {
        live_lua_api = 1,
        name = "DBF Modular",
        version = "0.1.0-dev.23",
        on_enable = function()
            if app then
                return false, "DBF Modular lifecycle already owns state"
            end
            app = App.new(context, globals)
            local okay, why = app:enable()
            if not okay and app.state == "closed" then
                app = nil
            end
            if not okay then
                error(why, 0)
            end
            return true
        end,
        on_update = function(dt)
            if app then
                return app:update(dt)
            end
        end,
        on_disable = retire,
        -- LLL may retry an acknowledged cleanup refusal while owners stay pinned.
        on_cleanup_poll = retire,
    }
end
return App
