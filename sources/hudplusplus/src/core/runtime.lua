local Runtime = {}
Runtime.__index = Runtime
function Runtime.new(program, report)
    return setmetatable({ program = program, report = report, running = true }, Runtime)
end
function Runtime:uninstall()
    local environment = self.environment
    if environment == nil then
        return
    end
    -- Only remove hooks we still own. A later mod may wrap either hook.
    if environment.update == self.outer then
        environment.update = self.outer_inner
    end
    if environment.update == self.base then
        environment.update = self.original_update
    end
    if self.shutdown ~= nil and environment.shutdown == self.shutdown then
        environment.shutdown = self.original_shutdown
    end
    self.environment, self.outer, self.outer_inner = nil, nil, nil
    self.installed = false
end
function Runtime:stop(reason, stage)
    if not self.running then
        return true
    end
    self.running = false
    local okay, failure = pcall(self.program.close, self.program)
    self:uninstall()
    if self.report ~= nil then
        local detail
        if not okay then
            detail = tostring(failure)
        end
        pcall(self.report, reason or "closed", detail, stage)
    end
    return okay, failure
end
function Runtime:step(...)
    if not self.running then
        return
    end
    local okay, failure = pcall(self.program.step, self.program, ...)
    if not okay then
        self:stop(tostring(failure), "step")
        return
    end
    local successor = self.program.successor
    if successor ~= nil then
        self.program = successor
    end
end
function Runtime:after(completed)
    if not self.running or self.program.after == nil then
        return
    end
    local okay, failure = pcall(self.program.after, self.program, completed)
    if not okay then
        self:stop(tostring(failure), "after")
    end
end
function Runtime:install(environment)
    assert(type(environment.update) == "function", "no-global-update")
    assert(not self.installed, "already-installed")
    assert(self.running, "not-running")
    local original_update, original_shutdown = environment.update, environment.shutdown
    self.environment, self.original_update, self.original_shutdown = environment, original_update, original_shutdown
    local runtime = self
    local function finish(program, completed, ...)
        runtime:after(completed)
        if program ~= runtime.program and runtime.changed ~= nil then
            runtime:changed()
        end
        local top = environment.update
        if runtime.running and runtime.program.menu_outermost then
            if top ~= (runtime.outer or runtime.base) then
                runtime.outer_inner = top
                runtime.outer = runtime:link(top, finish)
                environment.update = runtime.outer
            end
        elseif runtime.outer ~= nil then
            if top == runtime.outer then
                environment.update = runtime.outer_inner
            end
            runtime.outer, runtime.outer_inner = nil, nil
        end
        if runtime.boundary ~= nil then
            runtime:boundary()
        end
        if not completed then
            error((...), 0)
        end
        return ...
    end
    runtime.base = runtime:link(original_update, finish)
    environment.update = runtime.base
    if type(original_shutdown) == "function" then
        runtime.shutdown = function(...)
            runtime:stop()
            return original_shutdown(...)
        end
        environment.shutdown = runtime.shutdown
    end
    self.installed = true
    return self
end
function Runtime:link(inner, finish)
    local runtime, wrapper = self, nil
    wrapper = function(...)
        -- Hooks buried under another mod cannot be detached; keep them inert.
        if not runtime.running or wrapper ~= (runtime.outer or runtime.base) then
            return inner(...)
        end
        local program = runtime.program
        runtime:step(...)
        return finish(program, pcall(inner, ...))
    end
    return wrapper
end
return Runtime
