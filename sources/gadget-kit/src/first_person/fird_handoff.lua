local PORT51=mod.require('src/first_person/compat51.lua')
-- Wait for the existing owners before starting the third-person presentation.
local H={}
function H.new(stop,start,clock)
    assert(PORT51.kind(stop)=='function'and PORT51.kind(start)=='function','Fird handoff callbacks required')
    local self={phase='off'};local captured,deadline,clean_frame
    function self:is_pending()return captured~=nil end
    function self:status()return self.phase end
    function self:cancel()captured,deadline,clean_frame=nil,nil,nil;self.phase='off';return true end
    function self:request(value)
        if captured then return false,'Fird Person is already switching views'end
        assert(PORT51.kind(value)=='table','First-person reference unavailable')
        captured=value;deadline=clock()+3;self.phase='Switching to Fird Person'
        return self:update()
    end
    function self:update()
        if not captured then return true end
        local ok,ready,why=pcall(stop)
        if not ok then self:cancel();return false,tostring(ready)end
        if ready~=true then
            clean_frame=nil
            if clock()<=deadline then return true end
            self:cancel();return false,why or 'First-person cleanup is still pending'
        end
        -- Let the native normal-camera evaluator publish its lens and finish
        -- the arms' reattachment once after cleanup has acknowledged.
        if not clean_frame then clean_frame=true;return true end
        local reference=captured;self:cancel()
        ok,ready,why=pcall(start,reference)
        if not ok then return false,tostring(ready)end
        return ready,why
    end
    return self
end
return H
