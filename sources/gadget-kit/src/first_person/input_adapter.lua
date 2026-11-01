-- Adapt the current token-owned LLL input service without modifying DBF-MCM.
local Shared=mod.require('src/first_person/shared_input.lua')
local M={}
function M.new(sr,service)
    local raw=Shared.new(sr,service)
    local self={api=2,isolated_look=true}
    local previous
    function self.frame()raw.frame()end
    function self.focused()return sr.Window.has_focus()==true end
    function self.down(key)return raw.down(key)end
    function self.acquire()
        raw.frame()
        local ok,why=raw.set_mode('menu')
        if ok then return true end
        return nil,why
    end
    function self.release()previous=nil;return raw.release()end
    function self.set_focus(menu)return raw.set_mode(menu and 'menu'or'camera')end
    function self.menu_sample()
        raw.frame()
        local sample,why=raw.sample()
        if not sample then return nil,why end
        if sample.pending then return {pending=true,x=0,y=0,click=false,wheel=0,dt=0}end
        local now=sr.Application.time_since_launch()
        local dt=previous and math.max(0,math.min(.1,now-previous))or 0
        previous=now
        return {x=sample.x,y=sample.y,click=sample.click,wheel=raw.wheel(),dt=dt}
    end
    return self
end
return M
