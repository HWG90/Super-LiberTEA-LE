-- Read-only mode receipt from Goose Gadget Kit's public API. A saved toggle or
-- native ADS bit does not prove that its True First Person lease is running.
-- Installed0.5.29: first_person/runtime.lua status() returns(label, snapshot).
local Mode = {}
Mode.__index = Mode
local PHASES =
    { idle = true, disabled = true, waiting = true, reacquiring = true, running = true, cleanup_pending = true }
function Mode.new(globals)
    return setmetatable({ globals = globals or _G, generation = 0, view = { known = false, active = false } }, Mode)
end
function Mode:update()
    local out = self.view
    out.known, out.active, out.token = false, false, nil
    if self.closed then
        return out
    end
    local provider = rawget(self.globals, "NativeADSCameraTest")
    local status = type(provider) == "table" and rawget(provider, "status") or nil
    if provider ~= self.provider or status ~= self.status then
        self.generation = self.generation + 1
        self.provider, self.status = provider, status
        self.token = "true_first_person:" .. tostring(self.generation)
    end
    if type(provider) ~= "table" or type(status) ~= "function" then
        return out
    end
    -- Exactly one public poll per update. No provider imports, writes, native
    -- calls, setting lookups, or a second poll during publication checks.
    local okay, _, result = pcall(status)
    if
        not okay
        or type(result) ~= "table"
        or type(result.enabled) ~= "boolean"
        or PHASES[result.phase] ~= true
        or result.mode ~= nil and type(result.mode) ~= "string"
        or result.cleanup_pending ~= nil and type(result.cleanup_pending) ~= "boolean"
        or result.editor_active ~= nil and type(result.editor_active) ~= "boolean"
        or result.fird ~= nil and type(result.fird) ~= "table"
    then
        return out
    end
    if
        result.fird
        and (
            result.fird.enabled ~= nil and type(result.fird.enabled) ~= "boolean"
            or result.fird.pending ~= nil and type(result.fird.pending) ~= "boolean"
        )
    then
        return out
    end
    -- The global can be replaced from inside the callback. A snapshot cannot
    -- authorize another provider even if its returned fields look identical.
    if rawget(self.globals, "NativeADSCameraTest") ~= provider or rawget(provider, "status") ~= status then
        return out
    end
    out.known = true
    local fird = result.fird
    out.active = result.mode == "pose_offset"
        and result.phase == "running"
        and result.enabled == true
        and result.cleanup_pending ~= true
        and result.editor_active ~= true
        and not (fird and (fird.enabled == true or fird.pending == true))
    if out.active then
        out.token = self.token
    end
    return out
end
function Mode:current()
    return self.view.active == true
        and type(self.provider) == "table"
        and rawget(self.globals, "NativeADSCameraTest") == self.provider
        and rawget(self.provider, "status") == self.status
end
function Mode:close()
    self.provider, self.status, self.token = nil, nil, nil
    self.globals, self.closed = nil, true
    self.view.known, self.view.active, self.view.token = false, false, nil
    return true
end
return Mode
