-- Exercise the real Backend's private phase publication. Native ownership is
-- still checked by its helper; this path must not duplicate a Lua heap walk.
local root=assert(NATIVE_ADS_TEST_ROOT)
local Profile=dofile(root..'/src/profile.lua')
local previous_mod=rawget(_G,'mod')
_G.mod={require=function(name)assert(name=='src/profile.lua');return Profile end}
local Backend=dofile(root..'/src/backend.lua')
_G.mod=previous_mod
local passed=0
local function equal(a,b)assert(a==b,tostring(a)..' ~= '..tostring(b))end
local function test(name,body)local ok,why=pcall(body);assert(ok,name..': '..tostring(why));passed=passed+1 end
local function copy(t)local out={};for k,v in pairs(t)do out[k]=v end;return out end
local function fixture()
    local f={calls=0,reads=0,snapshots=0,contexts=0,owned_queries=0,packets={}}
    local helper={}
    local backend=Backend.new(nil,{read=function()f.reads=f.reads+1;error('phase publication read process memory')end},nil,helper)
    f.backend,f.helper=backend,helper
    function backend:snapshot()f.snapshots=f.snapshots+1;error('phase publication sampled a full snapshot')end
    function backend:_pose_context()f.contexts=f.contexts+1;error('phase publication walked the native rig')end
    function helper:owned_handle()f.owned_queries=f.owned_queries+1;return f.owned end
    function helper:transition(handle,token)
        equal(handle,f.owned);f.calls=f.calls+1;f.packets[#f.packets+1]=copy(token)
        if f.throw then error('fixture native phase call threw')end
        if f.refuse then return false,'fixture native phase call refused'end
        return true
    end
    f.handle={owner=helper,disarmed=false,generation={[0]=123}}
    f.owned=f.handle
    f.alignment={helper=helper,handle=f.handle,kind='pose',ended=false,context={}}
    f.lease={owner=backend,origin={identity='rig-a',player_identity='player-a'},
        request=0x20000,alignment=f.alignment,done=false,cleanup_only=false}
    backend.alignment_lease=f.lease
    f.packet={epoch=1,progress=.25,ads=false,identity='rig-a',player_identity='player-a',
        reason='action',action='idle',started=10,duration=.18,continuous=true}
    function f:begin()self.backend:begin_frame()end
    function f:publish(packet)return self.backend:set_pose_transition(self.lease,packet or self.packet)end
    function f:no_walks()equal(self.reads,0);equal(self.snapshots,0);equal(self.contexts,0)end
    return f
end

test('owned qualified phase publication never duplicates snapshot, rig context or process reads',function()
    local f=fixture();f:begin();assert(f:publish());equal(f.calls,1);f:no_walks()
    equal(f.packets[1].epoch,1);equal(f.packets[1].progress,.25)
    equal(f.backend.presentation_pose_lease,f.lease);equal(f.backend.presentation_pose_epoch,1)
end)
test('nonnull phase publication is forbidden outside Update even after a cached success',function()
    local f=fixture();assert(not f:publish());equal(f.calls,0)
    f:begin();assert(f:publish());f.backend:end_frame()
    assert(not f:publish());equal(f.calls,1);f:no_walks()
    assert(f.backend:set_pose_transition(f.lease,nil));equal(f.calls,1)
end)
test('identical copied packet values coalesce within one frame without retaining a mutable packet reference',function()
    local f=fixture();f:begin();assert(f:publish());assert(f:publish(copy(f.packet)));assert(f:publish())
    equal(f.calls,1)
    f.packet.progress=.5;assert(f:publish());equal(f.calls,2)
    assert(f:publish(copy(f.packet)));equal(f.calls,2);f:no_walks()
end)
test('each semantic mid-frame edge publishes even when an earlier packet already succeeded',function()
    local f=fixture();f:begin();assert(f:publish())
    local changes={{'epoch',2},{'progress',.5},{'ads',true},{'action','reload'},{'reason','ads_enter'},
        {'started',10.01},{'duration',.2},{'continuous',false}}
    for _,row in ipairs(changes)do
        local before=f.calls;f.packet[row[1]]=row[2]
        assert(f:publish());equal(f.calls,before+1);assert(f:publish(copy(f.packet)));equal(f.calls,before+1)
    end
    f:no_walks()
end)
test('new qualified frame is a heartbeat and cannot reuse the preceding frame cache',function()
    local f=fixture();f:begin();assert(f:publish());f.backend:end_frame();f:begin()
    assert(f:publish());equal(f.calls,2);assert(f:publish());equal(f.calls,2);f:no_walks()
end)
test('a fresh lease or alignment identity cannot inherit a same-frame successful cache',function()
    local f=fixture();f:begin();assert(f:publish())
    local old=f.lease;f.lease=copy(old);f.backend.alignment_lease=f.lease
    assert(f:publish());equal(f.calls,2)
    f.alignment=copy(f.alignment);f.lease.alignment=f.alignment
    assert(f:publish());equal(f.calls,3);f:no_walks()
end)
test('a new exact owned native handle is published within the same frame',function()
    local f=fixture();f:begin();assert(f:publish())
    f.handle={owner=f.helper,disarmed=false,generation={[0]=124}};f.owned=f.handle;f.alignment.handle=f.handle
    assert(f:publish());equal(f.calls,2);f:no_walks()
end)
test('a replacement helper plus its exact owned handle does not reuse another helper cache',function()
    local f=fixture();f:begin();assert(f:publish())
    local next_helper={}
    local next_handle={owner=next_helper,disarmed=false,generation={[0]=125}}
    function next_helper:owned_handle()return next_handle end
    function next_helper:transition(handle,packet)equal(handle,next_handle);equal(packet.epoch,1);f.calls=f.calls+1;return true end
    f.alignment.helper=next_helper;f.alignment.handle=next_handle;f.backend.pose=next_helper
    assert(f:publish());equal(f.calls,2);f:no_walks()
end)
test('stale player or rig phase is ignored without publishing or updating a valid cache',function()
    local f=fixture();f:begin();assert(f:publish())
    for _,field in ipairs({'identity','player_identity'})do
        local stale=copy(f.packet);stale[field]='other-owner';assert(f:publish(stale));equal(f.calls,1)
        assert(f:publish(copy(f.packet)));equal(f.calls,1)
    end
    f.packet.progress=.5;assert(f:publish());equal(f.calls,2);f:no_walks()
end)
test('local lease and alignment retirement guards run before cache reuse',function()
    for _,which in ipairs({'stale_lease','done','cleanup','missing_alignment','ended','other_kind'})do
        local f=fixture();f:begin();assert(f:publish())
        if which=='stale_lease'then f.backend.alignment_lease=copy(f.lease)
        elseif which=='done'then f.lease.done=true
        elseif which=='cleanup'then f.lease.cleanup_only=true
        elseif which=='missing_alignment'then f.lease.alignment=nil
        elseif which=='ended'then f.alignment.ended=true
        else f.alignment.kind='alignment'end
        assert(not f:publish());equal(f.calls,1);f:no_walks()
    end
end)
test('disarmed missing or foreign native handles cannot pass a previously successful cache',function()
    for _,which in ipairs({'disarmed','missing','foreign_owner','foreign_owned','missing_owned_api','throwing_owned_api','missing_transition'})do
        local f=fixture();f:begin();assert(f:publish())
        if which=='disarmed'then f.handle.disarmed=true
        elseif which=='missing'then f.alignment.handle=nil
        elseif which=='foreign_owner'then f.handle.owner={}
        elseif which=='foreign_owned'then f.owned={owner=f.helper,disarmed=false}
        elseif which=='missing_owned_api'then f.helper.owned_handle=nil
        elseif which=='throwing_owned_api'then f.helper.owned_handle=function()error('fixture query failed')end
        else f.helper.transition=nil end
        assert(not f:publish());equal(f.calls,1);f:no_walks()
    end
end)
test('malformed scalar packet cannot reach a native helper',function()
    local invalid={false,{},
        {epoch=0,progress=0,ads=false},{epoch=-1,progress=0,ads=false},{epoch=1.5,progress=0,ads=false},
        {epoch=9007199254740992,progress=0,ads=false},{epoch=math.huge,progress=0,ads=false},{epoch=0/0,progress=0,ads=false},
        {epoch=1,progress=-.1,ads=false},{epoch=1,progress=1.1,ads=false},{epoch=1,progress=0/0,ads=false},
        {epoch=1,progress=math.huge,ads=false},{epoch=1,progress=.5,ads=1},
        {epoch=1,progress=.5,ads=false,identity=''},{epoch=1,progress=.5,ads=false,player_identity=''}}
    for _,row in ipairs(invalid)do
        local f=fixture();f:begin();local token=type(row)=='table'and copy(f.packet)or row
        if type(row)=='table'then for k,v in pairs(row)do token[k]=v end end
        if type(row)=='table'and next(row)==nil then token={}end
        assert(not f.backend:set_pose_transition(f.lease,token));equal(f.calls,0);f:no_walks()
    end
end)
test('missing core token fields fail before native publication',function()
    for _,name in ipairs({'epoch','progress','ads','identity','player_identity'})do
        local f=fixture();f:begin();local token=copy(f.packet);token[name]=nil
        assert(not f.backend:set_pose_transition(f.lease,token));equal(f.calls,0);f:no_walks()
    end
end)
test('an invalidated frame epoch cannot reuse earlier publication state',function()
    local f=fixture();f:begin();assert(f:publish());f.backend:_invalidate_frame_checks()
    assert(f:publish());equal(f.calls,2);assert(f:publish());equal(f.calls,2);f:no_walks()
end)
test('helper refusal and uncertain exception do not cache an unacknowledged phase',function()
    for _,which in ipairs({'refuse','throw'})do
        local f=fixture();f:begin();f[which]=true
        assert(not f:publish());equal(f.calls,1);assert(not f:publish());equal(f.calls,2)
        f[which]=false;assert(f:publish());equal(f.calls,3);assert(f:publish());equal(f.calls,3);f:no_walks()
    end
end)
test('failed changed phase invalidates prior acknowledgement so next packet reasserts',function()
    for _,failure in ipairs({'refuse','throw'})do
        local f=fixture();f:begin();assert(f:publish());local prior=copy(f.packet)
        f.packet.progress=.5;f[failure]=true;assert(not f:publish());equal(f.calls,2)
        -- The failed/throwing call may have changed native state before its
        -- acknowledgement was lost. Reassert even a previously accepted phase.
        f[failure]=false;assert(f:publish(prior));equal(f.calls,3)
        assert(f:publish(copy(prior)));equal(f.calls,3)
        assert(f:publish());equal(f.calls,4);assert(f:publish(copy(f.packet)));equal(f.calls,4)
        f:no_walks()
    end
end)
print('Private backend phase publication: '..passed..' no-walk/ownership/frame/coalescing cases passed')
