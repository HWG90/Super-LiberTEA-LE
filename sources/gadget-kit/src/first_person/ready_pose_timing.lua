-- Read-only native animation-batch observation. The caller owns Update authority.
-- observed_idle is one scoped observation, never general permission to mutate poses.
-- Caller must run inside the existing backend Update frame; this module owns
-- no callbacks, frames, SDK getters, native invocations, FFI casts or writes.
local M={pins={
    {name='instance_getter',rva=0x28d510,hex='488b8178010000c3'},
    {name='resource_getter',rva=0x28d520,hex='488b8158030000488902488bc2c3'},
    {name='native_World_manager_instance',rva=0x12b2d9,hex='488b03488bcbff90b0010000488b4b18488bd0448b4704488b8950002300e864bb4300'},
    {name='manager_group90_membership',rva=0x566e7a,hex='488b8998000000beffffffff8b87900000004c8d04c1493bc87437488d51084839197414488bca493bd075ef4881c7a8000000e9d2000000'},
    {name='manager_groupA8_membership',rva=0x566ed8,hex='488b91b00000008b81a8000000488d0cc2488bc2483bd1740e48391874094883c008483bc175f2'},
    {name='vector_count_capacity_pointer',rva=0x566f84,hex='8b0f8b57048d41013bc2761b488d04550a000000488bcf483bc6480f47c68bd0e807e4c4ff8b0f488b470833d2488b742438488914c88b0f488b470848891cc8'},
    {name='batch_completion_initialization',rva=0x5669fd,hex='488b837001000041c64403f800'},
    {name='batch_count_capacity',rva=0x566a1b,hex='8b83f40000003bf8763383f808720a8bc848d1e94803c8eb05b9080000008bc7483bc8720a493bcf488bc1490f47c78bd0488d8bf0000000e8d8a7b2ff89bbf000000041b9010000004c8b83f8000000488b9358010000488b8b88000000'},
    {name='batch_wait_inputs',rva=0x566d18,hex='8b99f0000000488bf1488b9170010000448bc3488b8988000000c744242001000000e8613e0000'},
    {name='batch_count_clear',rva=0x566e51,hex='89bef0000000'},
    {name='completion_poll',rva=0x56ae2e,hex='410fb6042441b901000000488b55df84c00f84dbfdffff488b4dd7bad8010000'},
}}
local MAX_INSTANCES,MAX_BATCHES=16384,256
local function u32(raw,o)
    local a,b,c,d=raw:byte(o+1,o+4);assert(d,'Quiescence integer incomplete')
    return a+b*256+c*65536+d*16777216
end
local function pointer(raw,o,label)
    local n=u32(raw,o)+u32(raw,o+4)*4294967296
    -- Authored graph assets may be only four-byte aligned. Raw protected
    -- reads and the owning structures qualify targets, not a universal
    -- invented alignment rule.
    assert(n==0 or n>=65536 and n<2^47,'Quiescence '..label..' pointer invalid');return n
end
local function unhex(raw)return(raw:gsub('..',function(s)return string.char(tonumber(s,16))end))end
local function finite(n)return type(n)=='number'and n==n and n~=math.huge and n~=-math.huge end
local OWNER={'identity','player_identity','base','context','camera','record','world','controller','controller_active',
    'avatar_owner','avatar_index','avatar','body','viewmodel','weapon_unit','camera_kind','safe'}
local function same_owner(a,b)
    for _,key in ipairs(OWNER)do assert(a[key]==b[key],'Quiescence player/weapon/camera changed: '..key)end
end
function M.new(b)
    assert(type(b)=='table'and type(b._read)=='function'and type(b.snapshot)=='function','Quiescence backend required')
    local self={}
    function self:sample(context)
        local ok,result=pcall(function()
            context=context or{};assert(type(context)=='table','Quiescence sample context invalid')
            assert(b.frame_active==true,'Quiescence requires existing Update frame')
            local epoch=b.frame_epoch
            if context.epoch~=nil then assert(context.epoch==epoch,'Quiescence frame epoch changed')end
            local calls,total=0,0
            local function read(at,n,label)
                assert(finite(at)and at>=65536 and at<2^47 and n>=0 and n<=MAX_INSTANCES*8,
                    'Quiescence '..label..' read exceeds bounds')
                if n==0 then return''end
                local out={}
                for off=0,n-1,1024 do
                    local size=math.min(1024,n-off);calls=calls+1;total=total+size
                    assert(calls<=512 and total<=1048576,'Quiescence cumulative read bound exceeded')
                    local raw=b:_read(at+off,size)
                    assert(type(raw)=='string'and #raw==size,'Quiescence '..label..' protected read failed')
                    out[#out+1]=raw
                end
                return table.concat(out)
            end
            local function p(at,label)return pointer(read(at,8,label),0,label)end
            local function fresh()
                -- snapshot() already performs fresh reads. Invalidating the
                -- backend checks would mutate its active frame epoch.
                local s,why=b:snapshot();return assert(s,why or'Quiescence player unavailable')
            end
            local s=fresh()
            assert(s.safe and s.camera_kind==4 and not s.controller_active,'Quiescence requires owned normal camera4')
            if b.foreign_camera then assert(b.foreign_camera()==false,'Quiescence foreign camera active')end
            if context.expected then same_owner(context.expected,s)end
            local c=b:_alignment_context({viewmodel=s.body,avatar_owner=s.avatar_owner,avatar_index=s.avatar_index})
            assert(c.unit==s.body and finite(c.exe),'Quiescence body context unavailable')
            local function generation()
                assert(b:_u8(c.generations+c.index)==c.generation and p(c.units+c.index*8,'body registry')==c.object
                    and b:_u32(c.object+8)==s.body,'Quiescence body generation retired')
            end
            generation()
            for _,pin in ipairs(M.pins)do
                local raw=unhex(pin.hex);assert(read(c.exe+pin.rva,#raw,pin.name)==raw,
                    'Quiescence code contract changed: '..pin.name)
            end
            local vt=p(c.object,'body vtable')
            assert(p(vt+0x1b0,'body instance getter')==c.exe+0x28d510
                and p(vt+0x1b8,'body resource getter')==c.exe+0x28d520,'Quiescence body interface changed')
            local resource=read(c.object+0x358,8,'body resource')
            assert(resource==unhex('97fa4d294d331c4d')and b:_u32(c.object+0x70)==107,'Quiescence body resource changed')
            local instance=p(c.object+0x178,'body instance');assert(instance~=0,'Quiescence body instance absent')
            local graph=p(instance+0x28,'body graph');assert(graph~=0,'Quiescence body graph absent')
            local graph_header=read(graph,0x60,'body graph header')
            assert(u32(graph_header,4)==31 and u32(graph_header,0x14)==54,'Quiescence body graph contract changed')
            -- Unit+18 is the native World. snapshot.world is the game ECS.
            local world=p(c.object+0x18,'native World');assert(world~=0,'Quiescence native World absent')
            local manager=p(world+0x230050,'World animation manager');assert(manager~=0,'Quiescence animation manager absent')
            local function vector(offset,label)
                local header=read(manager+offset,16,label..' vector')
                local count,capacity=u32(header,0),u32(header,4);local array=pointer(header,8,label..' array')
                assert(count<=MAX_INSTANCES and capacity>=count and capacity<=65536,
                    'Quiescence '..label..' vector bounds invalid')
                assert(count==0 or array~=0,'Quiescence '..label..' array absent')
                local raw=count>0 and read(array,count*8,label..' members')or''
                local matches=0
                for i=0,count-1 do if pointer(raw,i*8,label..' member')==instance then matches=matches+1 end end
                return{offset=offset,label=label,header=header,count=count,array=array,raw=raw,matches=matches}
            end
            -- 12B2A9..12B2C7 passes the exact Unit+1B0 state machine to
            -- 566DD0, which moves it between these two manager-owned vectors.
            local groups={vector(0x90,'group90'),vector(0xa8,'groupA8')}
            assert(groups[1].matches+groups[2].matches==1,'Quiescence body instance is not uniquely owned by manager')
            local pending=read(manager+0xf0,16,'pending batch vector')
            local count,capacity=u32(pending,0),u32(pending,4);local handles=pointer(pending,8,'pending handles')
            assert(count<=MAX_BATCHES and capacity>=count and capacity<=4096,'Quiescence pending batch bounds invalid')
            assert(count==0 or handles~=0,'Quiescence pending handle array absent')
            local records=p(manager+0x170,'batch records')
            assert(count==0 or records~=0,'Quiescence batch records absent')
            local function completion()
                local values,completed={},0
                for i=0,count-1 do
                    local value=read(records+i*0x30+0x28,1,'batch completion'):byte(1)
                    assert(value==0 or value==1,'Quiescence completion flag is not Boolean')
                    values[#values+1]=value;if value==1 then completed=completed+1 end
                end
                return values,completed
            end
            local before,completed_before=completion()
            -- No job record payload pointers or opaque counters are followed.
            local after,completed_after=completion();local stable=true
            for i=1,#before do if before[i]~=after[i]then stable=false end end
            same_owner(s,fresh());generation()
            assert(p(c.object,'body vtable')==vt and read(c.object+0x358,8,'body resource')==resource
                and p(c.object+0x178,'body instance')==instance and p(instance+0x28,'body graph')==graph
                and read(graph,0x60,'body graph header')==graph_header,'Quiescence body graph changed during observation')
            assert(p(c.object+0x18,'native World')==world and p(world+0x230050,'World animation manager')==manager,
                'Quiescence native World/manager changed during observation')
            for _,v in ipairs(groups)do
                assert(read(manager+v.offset,16,v.label..' vector')==v.header
                    and(v.count==0 or read(v.array,#v.raw,v.label..' members')==v.raw),
                    'Quiescence manager membership changed during observation')
            end
            assert(read(manager+0xf0,16,'pending batch vector')==pending and p(manager+0x170,'batch records')==records,
                'Quiescence pending batch owner/count changed during observation')
            assert(b.frame_active==true and b.frame_epoch==epoch,'Quiescence Update frame retired')
            return{schema=1,scope='owned_world_animation_manager_batches',phase=context.phase,
                tick=context.tick,epoch=epoch,elapsed=context.elapsed,owner_token=string.format('%x:%d:%x:%x',c.object,c.generation,instance,manager),
                body_ref=s.body,weapon_ref=s.weapon_unit,camera_kind=s.camera_kind,shoulder_aim=s.shoulder_aim==true,
                reloading=s.reloading==true,group90_count=groups[1].count,groupA8_count=groups[2].count,
                body_group=groups[1].matches==1 and'group90'or'groupA8',pending_batches=count,
                completed_before=completed_before,completed_after=completed_after,incomplete_after=count-completed_after,
                completion_before=before,completion_after=after,completion_stable=stable,
                observed_idle=count==0,write_authorized=false,read_calls=calls,read_bytes=total}
        end)
        if not ok then return nil,tostring(result)end
        return result
    end
    return self
end
return M
