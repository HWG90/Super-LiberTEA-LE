local root=assert(NATIVE_ADS_TEST_ROOT)
local Zoom=dofile(root..'/src/zoom.lua')
local ffi=require('ffi')
local passed=0
local function test(name,body)local ok,why=pcall(body);assert(ok,name..': '..tostring(why));passed=passed+1 end
local function fixture()
    local f={events={},begins=0,ends=0,updates=0}
    local function event(value)table.insert(f.events,value)end
    f.controller={enabled=true,phase='running',mode='pose_offset',lease={request=100,weapon=11,alignment={}}}
    function f.controller:is_enabled()return self.enabled end
    function f.controller:result()return {phase=self.phase,mode=self.mode}end
    f.backend={alignment_lease=f.controller.lease}
    function f.backend:fov_config(lease)return {request=lease and lease.request or 80,weapon=lease and lease.weapon or 11}end
    function f.backend:set_pose_zoom_policy(lease,active)
        assert(lease==f.controller.lease);event(active and 'pose-on'or 'pose-off');return true
    end
    f.helper={
        validate=function()event('validate');return true end,
        begin=function()
            f.begins=f.begins+1;event('begin')
            if f.refuse then return false,'foreign lease'end
            f.handle={}
            if f.partial then return false,'partial install'end
            return true,f.handle
        end,
        owned_handle=function()return f.handle end,
        update=function(_,handle)assert(handle==f.handle);f.updates=f.updates+1;return not f.update_fail,'update refused'end,
        stats=function(_,handle)assert(handle==f.handle);return {armed=not f.disarmed,error=0}end,
        finish=function(_,handle)
            assert(handle==f.handle);f.ends=f.ends+1;event('end')
            if f.end_fail then return false,'cleanup pending'end
            f.handle=nil;return true
        end,
    }
    f.manager=Zoom.new(f.backend,nil,f.helper)
    return f
end
test('preflight reads only; active zoom disables old compensation before native activation',function()
    local f=fixture();assert(f.manager:preflight());assert(f.begins==0)
    assert(f.manager:update(f.controller));assert(table.concat(f.events,',')=='validate,pose-on,begin')
    assert(f.manager:update(f.controller));assert(f.begins==1 and f.updates==2)
    assert(f.manager:stop());assert(table.concat(f.events,',')=='validate,pose-on,begin,end,pose-off')
    assert(f.manager:is_clean())
end)
test('native ADS baseline and waiting intent release only their own zoom lease',function()
    for _,kind in ipairs({'disabled','native','waiting'})do
        local f=fixture();assert(f.manager:update(f.controller))
        if kind=='disabled'then f.controller.enabled=false
        elseif kind=='native'then f.controller.mode='native'
        else f.controller.phase='waiting'end
        assert(f.manager:update(f.controller));assert(f.ends==1 and f.manager:is_clean())
    end
end)
test('refused and partial installation retain exact cleanup ownership',function()
    local f=fixture();f.refuse=true;assert(not f.manager:update(f.controller));assert(f.ends==0)
    assert(f.events[#f.events]=='pose-off');assert(f.manager:is_clean())
    f=fixture();f.partial=true;f.end_fail=true;assert(not f.manager:update(f.controller))
    assert(f.ends==1 and not f.manager:is_clean());assert(f.events[#f.events]=='end')
    assert(not f.manager:update(f.controller));assert(f.begins==1)
    f.end_fail=false;assert(f.manager:stop());assert(f.events[#f.events]=='pose-off')
end)
test('native failure stops selection before restoring legacy depth policy',function()
    for _,failure in ipairs({'update_fail','disarmed'})do
        local f=fixture();assert(f.manager:update(f.controller));f[failure]=true
        assert(not f.manager:update(f.controller));assert(f.ends==1)
        assert(f.events[#f.events-1]=='end'and f.events[#f.events]=='pose-off')
    end
end)
test('combined FOV cleanup is attempted while zoom restoration remains pending',function()
    local f=fixture();local stops=0
    local base={is_clean=function()return true end,result=function()return {}end,status=function()return ''end,
        update=function()return true end,preflight=function()return true end,
        stop=function()stops=stops+1;return true end,shutdown=function()stops=stops+1;return true end}
    local group=Zoom.attach(base,f.backend,nil,f.helper);assert(group:update(f.controller));f.end_fail=true
    assert(not group:shutdown());assert(stops==1 and not group:is_clean())
    f.end_fail=false;assert(group:shutdown());assert(stops==2 and group:is_clean())
end)
test('adapter preserves opaque generation and disarmed resident hook is a clean lease',function()
    local a=Zoom.Adapter.new({abi=1});local token=ffi.new('uint64_t',0x200000)*ffi.new('uint64_t',4294967296)+37
    local owned=false;local ends=0
    a.library={NADZ_Validate=function()return 1 end,NADZ_Begin=function(_,out)out[0]=token;owned=true;return 1 end,
        NADZ_Bind=function(g,c)assert(g==token and tonumber(c.weapon)==11);return 1 end,
        NADZ_Update=function(g)assert(g==token);return 1 end,
        NADZ_ReadStats=function(g,s)assert(g==token);s.armed=owned and 1 or 0;s.installed=1;return 1 end,
        NADZ_End=function(g)assert(g==token);ends=ends+1;owned=false;return 1 end,NADZ_Error=function()return 0 end}
    local c={game=1,exe=2,context=3,camera=4,avatar_owner=5,request=100,avatar_index=0,avatar=6,body=7,weapon=11}
    assert(a:validate(c));local ok,h=a:begin(c);assert(ok and h.generation[0]==token)
    assert(a:bind(h,c));assert(a:update(h));assert(a:stats(h).armed)
    assert(a:finish(h));assert(a:finish(h));assert(ends==1 and not a:owned_handle())
end)
print('FPV zoom lifecycle: '..passed..' passed')
