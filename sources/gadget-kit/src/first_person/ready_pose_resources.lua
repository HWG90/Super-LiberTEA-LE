-- Qualified read-only resident-animation proof for the existing native ready pose.
-- No resource loads, references, SDK/native calls, frames or global lookups.
local M={}
local function collect(b,selected24)
    assert(type(b)=='table'and type(b.snapshot)=='function'and type(b._read)=='function','Ready resources backend required')
    assert(selected24==1 or selected24==6,'Native ready layer24 target must be explicitly1or6')
    local hip24=selected24==1 and 0 or 5
    local expected24={'469cb23d97d2e41c',selected24==1 and'2b85e4e5dbeab474'or'd98c81205d9a0452'}
    local expected25={'9fc7391f2d587eb4','9bf7e729369146ba','95bf5e66251c0fef','87ff303d5289b9fa'}
    local expected4={'001f305a0d9f127b','0d26007ed5ae55a8','001f305a0d9f127b','f1811f696b1803ac','985d97e3d322b07d','6204a769a561170b','1d179113e2d0b5eb','0610ce3c6c7764cc','e713ef243778cd81','61a94dea4da9b235','d25d4fbbb4ad626f','ee719a226cc71d28','5b6a45017ac9f5ed','f8df32761089e314','cc803ad67ac091b5','5c3574cfe64a15d3','4d97c79753df003f','d0c50df30bf92371','f448545b3cc967d6','c44c9d7cf2e3c7fe','fd8e3b4bf4962d85'}
    local captured4={
        [59]={header='ce931a33c5a11d5e0200000015000000a8000000000000000000000001000000000000000000000009000000540100000e0000009c010000010000007c0200000000000000000000000000000000000082000000ec02000015000000f40400000000000000000000030000004600000001000000500100000000000000001000ffffffff000000000000000000000000010000004805000000000000000000000000000000000000',program='0000803f0000a07f0e00907f000080bf0000803f0000a0400b00807f0000a07f0e00907f0000803f0000a040000010410b00807f0000a07f0e00907f0000a04000001041000020410b00807f0000a07f0e00907f0000104100002041000060410b00807f0000a07f0e00907f0000504100006041000070410b00807f0000a07f0e00907f0000604100007041000098410b00807f0000a07f0e00907f000098410000a0410000a8410b00807f0000a07f0e00907f0000a0410000a8410000b0410b00807f0000a07f0e00907f0000a8410000b0410000e8410b00807f0000a07f0e00907f0000e8410000f04100000c420b00807f0000a07f0e00907f00000c420000104200001c420b00807f0000a07f0e00907f000044420000484200004c420b00807f0000a07f0e00907f0000484200004c42000050420b00807f0000a07f0e00907f00004c420000504200006c420b00807f0000a07f0e00907f00006c4200007042000074420b00807f0000a07f0e00907f000070420000744200008a420b00807f0000a07f0e00907f00008a4200008c4200009e420b00807f0000a07f0e00907f00009e420000a0420000b2420b00807f0000a07f0e00907f0000b2420000b4420000c8420b00807f0000a07f0e00907f00001c4200002442000028420b00807f0000a07f0e00907f0000244200002842000044420b00807f0000a07f0e00907f0000a07f',outputs='02000000080000000e000000140000001a00000020000000260000002c00000032000000380000003e000000440000004a00000050000000560000005c00000062000000680000006e000000740000007a000000'},
        [67]={header='64952d6242873387010000000000000000000000000000000000000001000000010000000000000009000000ac0000000e000000f400000001000000d40100000000000000000000000000000000000004000000440200000000000000000000000000000000000003000000ffffffff01000000a80000000000000000004000ffffffff000000000000000000000000000000000000000000000000000000000000000000000000',program='0000803f0000a07f0e00907f0000a07f',outputs=''},
    }
    local function u32(s,o)local a,c,d,e=s:byte(o+1,o+4);assert(e,'Incomplete residency integer');return a+c*256+d*65536+e*16777216 end
    local function pointer(s,o,label,alignment)
        local n=u32(s,o)+u32(s,o+4)*4294967296
        assert(n==0 or n>=65536 and n<2^47 and n%(alignment or 8)==0,'Residency '..label..' pointer invalid');return n
    end
    local function hex(s)return(s:gsub('.',function(c)return string.format('%02x',c:byte())end))end
    local function unhex(s)return(s:gsub('..',function(c)return string.char(tonumber(c,16))end))end
    local function id(s)local out={};for i=8,1,-1 do out[#out+1]=string.format('%02x',s:byte(i))end;return table.concat(out)end
    local function float(s,o)
        local bits=u32(s,o);local e=math.floor(bits/8388608)%256;local m=bits%8388608
        if e==255 then return nil end
        local value=e==0 and math.ldexp(m,-149)or math.ldexp(1+m/8388608,e-127)
        return bits>=2147483648 and-value or value
    end
    local copied,read_count={},0
    local function read(at,n,label,watch)
        assert(type(at)=='number'and at%1==0 and at>=65536 and at+n<2^47 and n>0 and n<=1024,'Residency '..label..' read exceeds bounds')
        read_count=read_count+1;assert(read_count<=8192,'Residency total read bound exceeded')
        local raw=b:_read(at,n);assert(type(raw)=='string'and #raw==n,'Residency '..label..' protected read failed')
        if watch then copied[#copied+1]={at=at,n=n,raw=raw,label=label}end
        return raw
    end
    local function p(at,label,watch,alignment)return pointer(read(at,8,label,watch),0,label,alignment)end
    local function snapshot()
        local s,why=b:snapshot();return assert(s,why or'Residency snapshot unavailable')
    end
    local initial=snapshot()
    assert(initial.safe and initial.camera_kind==4 and not initial.controller_active,'Residency requires owned native camera4')
    if b.foreign_camera then assert(b.foreign_camera()==false,'Residency foreign camera active')end
    local owner_keys={'identity','player_identity','base','context','camera','controller','record','world','avatar_owner','avatar_index',
        'avatar','body','viewmodel','weapon_unit','flags','controller_bytes','safe','camera_kind','controller_active','shoulder_aim','aiming'}
    local saved_owner={};for _,key in ipairs(owner_keys)do saved_owner[key]=initial[key]end
    local function owner()
        local s=snapshot();for _,key in ipairs(owner_keys)do assert(s[key]==saved_owner[key],'Residency player, weapon or camera changed: '..key)end
        if b.foreign_camera then assert(b.foreign_camera()==false,'Residency foreign camera active')end
        return s
    end
    local c=b:_alignment_context({viewmodel=initial.body,avatar_owner=initial.avatar_owner,avatar_index=initial.avatar_index})
    local exe=b:_alignment_executable();assert(c.exe==exe and c.unit==initial.body,'Residency executable/body identity changed')
    local function generation()
        local fresh=b:_alignment_context({viewmodel=initial.body,avatar_owner=initial.avatar_owner,avatar_index=initial.avatar_index})
        for _,key in ipairs({'exe','unit','object','index','generation','registry','units','generations'})do
            assert(fresh[key]==c[key],'Residency body registry changed')
        end
        assert(b:_alignment_executable()==exe,'Residency executable identity changed')
        assert(b:_u8(c.generations+c.index)==c.generation and p(c.units+c.index*8,'body registry')==c.object
            and b:_u32(c.object+8)==initial.body,'Residency body generation retired')
    end
    generation()
    local pins={
        {0x28d510,'488b8178010000c3'},
        {0x28d520,'488b8158030000488902488bc2'},
        {0x63e180,'83791800745c4c8b0a33d24c8b4108498bc148c1e820f7711c8bc24869c8d00000004283bc01c8000000fe743581faffffff7f742a6666660f1f8400000000008bc24869c8d00000004e3b0c017410428b9401c800000081faffffff7f75e18bc2c3b8ffffff7fc3'},
        {0x63238f,'39753874454c8b4d2833d2488bc348c1e820f7753c488d0c5241837cc910fe742981faffffff7f74210f1f8400000000008bc2488d0c40493b1cc97479418b54c91081faffffff7f75e7'},
        {0x63246c,'8bc2488d0c40498b41088b4cc808488b4510488d148948c1e205488b2c024584db740d498d8fd8020000ff15ecafe5004885ed0f8459ffffff488bc54883c430415f415e415d5f5e5d5bc3'},
        {0x55c530,'837e0c00750433dbeb068b5e104803de4a8b1c234c8d4d60498b4e204c8d454848b826cc46766d331e9348895d48488d555048894550e8d55c0d00837e500048'},
        {0x55c5df,'488b45908b08488b85d0090000894c3dc0f30f104808410f'},
    }
    for _,pin in ipairs(pins)do local want=unhex(pin[2]);assert(read(exe+pin[1],#want,'executable pin',true)==want,'Residency executable contract changed')end
    local vt=p(c.object,'body vtable',true)
    assert(p(vt+0x1b0,'instance method',true)==exe+0x28d510 and p(vt+0x1b8,'resource method',true)==exe+0x28d520,
        'Residency animation interface changed')
    assert(read(c.object+0x358,8,'body resource',true)==unhex('97fa4d294d331c4d')and b:_u32(c.object+0x70)==107,
        'Residency requires captured 107-node player body')
    local instance=p(c.object+0x178,'animation instance',true);assert(instance~=0,'Residency animation instance absent')
    local world=p(c.object+0x18,'body native World',true)
    -- Authored graph blobs may be four-byte aligned. Native objects and map
    -- storage retain the original eight-byte qualification.
    local graph=p(instance+0x28,'animation graph',true,4)
    local header=read(graph,0x60,'graph header',true);assert(u32(header,4)==31 and u32(header,0x14)==54,'Residency graph dimensions changed')
    local layer_offset=u32(header,8);assert(layer_offset>=12 and layer_offset<=0x10000,'Residency layer table offset invalid')
    local layer_table=graph+layer_offset
    assert(u32(read(layer_table,4,'layer table count',true),0)==31,'Residency layer table count changed')
    local definitions=read(layer_table+4,31*4,'layer definitions',true)
    local selected,unique={},{}
    for _,selection in ipairs({{layer=4,state=59,count=78,clips=21,mask=70,ids=expected4},
        {layer=24,state=selected24,count=10,clips=2,mask=35,ids=expected24},
        {layer=25,state=1,count=4,clips=4,mask=45,ids=expected25}})do
        local relative=u32(definitions,(selection.layer-1)*4)
        assert(relative>=128 and relative<=0x1000000,'Residency layer definition offset invalid')
        local def=layer_table+relative;local dh=read(def,12,'layer header',true)
        assert(u32(dh,8)==selection.count,'Residency target layer state count changed')
        if selection.layer==4 then assert(dh==unhex('2c010000430000004e000000'),'Residency main layer header changed')end
        local entries=read(def+12,selection.count*4,'state offsets',true)
        local sr=u32(entries,selection.state*4)
        assert(sr>=12+selection.count*4 and sr<=0x1000000,'Residency target state offset invalid')
        local state=def+sr;local sh=read(state,0xa8,'target state header',true)
        assert(u32(sh,8)==2 and u32(sh,0xc)==selection.clips,'Residency target is not captured type2 clip state')
        assert(u32(sh,0x6c)==selection.mask,'Residency target mask changed')
        if selection.layer==4 then
            assert(sh==unhex(captured4[59].header),'Residency main target header changed')
            local function program(who,at,header)
                local expected=captured4[who]
                assert(header==unhex(expected.header),'Residency main restore header changed')
                local offset,count=u32(header,0x54),u32(header,0x50)
                assert(count>0 and count<=256 and offset>=0xa8 and offset+count*4<=0x8000,'Residency main program bounds invalid')
                assert(read(at+offset,count*4,'main program '..who,true)==unhex(expected.program),'Residency main program changed')
                local outputs=u32(header,0x58)
                if outputs>0 then
                    local relative=u32(header,0x5c)
                    assert(outputs==selection.clips and relative>=0xa8 and relative+outputs*4<=0x8000,'Residency main output bounds invalid')
                    assert(read(at+relative,outputs*4,'main outputs '..who,true)==unhex(expected.outputs),'Residency main output entries changed')
                else assert(expected.outputs=='','Residency main output count changed')end
            end
            program(59,state,sh)
            local restore_relative=u32(entries,67*4)
            assert(restore_relative>=12+selection.count*4 and restore_relative<=0x1000000,'Residency main restore state offset invalid')
            local restore=def+restore_relative;local rh=read(restore,0xa8,'main restore header',true)
            assert(u32(rh,8)==1 and u32(rh,0xc)==0,'Residency main restore is not captured type1 state')
            program(67,restore,rh)
        else
            for _,at in ipairs({0x40,0x70,0x88,0x90,0x98,0xa0})do assert(u32(sh,at)==0,'Residency target authored actions changed')end
        end
        local offset=u32(sh,0x10);assert(offset>=0xa8 and offset<=0x4000 and offset+selection.clips*8<=0x8000,'Residency clip ID offset invalid')
        local clips=read(state+offset,selection.clips*8,'target clip IDs',true)
        for i=0,selection.clips-1 do
            local raw=clips:sub(i*8+1,i*8+8);assert(raw~=string.rep('\0',8),'Residency clip ID absent')
            local name=id(raw);assert(name==selection.ids[i+1],'Residency target clip family changed')
            selected[#selected+1]={layer=selection.layer,state=selection.state,clip=i,id=name,raw=raw}
            unique[name]=raw
        end
    end
    -- Hash-map layout comes from the pinned native lookup, including total
    -- storage at+0, array+8, live count+18, buckets+1C and end/dead sentinels.
    local function lookup(at,key,stride,next_offset,label,limit)
        local mh=read(at,0x28,label..' map header',true)
        local capacity,live,buckets=u32(mh,0),u32(mh,0x18),u32(mh,0x1c)
        assert(capacity>0 and capacity<=limit and live<=capacity and buckets>0 and buckets<=capacity,
            'Residency '..label..' map bounds invalid')
        local array=pointer(mh,8,label..' map array');assert(array~=0,'Residency '..label..' map array absent')
        if live==0 then return nil,{capacity=capacity,live=live,buckets=buckets}end
        local index=u32(key,4)%buckets;local seen={}
        for step=1,math.min(capacity,2048)do
            assert(index<capacity and not seen[index],'Residency '..label..' chain exceeds owned map');seen[index]=true
            local row=read(array+index*stride,stride,label..' map row',true)
            local next_index=u32(row,next_offset)
            if next_index==4294967294 then return nil,{capacity=capacity,live=live,buckets=buckets}end
            if row:sub(1,8)==key then return {at=array+index*stride,raw=row,index=index},
                {capacity=capacity,live=live,buckets=buckets}end
            if next_index==2147483647 then return nil,{capacity=capacity,live=live,buckets=buckets}end
            index=next_index
        end
        error('Residency '..label..' lookup exceeded2048 rows')
    end
    local manager=p(instance+0x20,'resource manager',true);assert(manager~=0,'Residency resource manager absent')
    local class_key=unhex('26cc46766d331e93')
    local class,type_map=lookup(manager+0x2e8,class_key,0xd0,0xc8,'animation class',4096)
    assert(class,'Residency animation resource class absent')
    local slots=pointer(class.raw,0x10,'resource slots');assert(slots~=0,'Residency resource slots absent')
    local result={schema=3,read_only=true,player_body_resource='4d1c334d294dfa97',camera_kind=initial.camera_kind,
        ready_layer4_state=59,hip_layer4_state=67,
        ready_layer24_state=selected24,hip_layer24_state=hip24,
        shoulder_aim=initial.shoulder_aim,resource_class='931e336d7646cc26',type_map=type_map,clips={},selections={}}
    local all=true
    for name,raw in pairs(unique)do
        local row,map=lookup(class.at+0x20,raw,24,0x10,'clip '..name,262144)
        local item={id=name,direct_entry=row~=nil,map=map}
        if row then
            local slot=u32(row.raw,8);assert(slot<65536,'Residency clip slot exceeds65536')
            local slot_raw=read(slots+slot*0xa0,0xa0,'clip slot '..name,true)
            local clip=pointer(slot_raw,0,'resolved clip');item.slot=slot;item.slot_header_hex=hex(slot_raw)
            item.resolved=clip~=0
            if clip~=0 then
                local ch=read(clip,0x40,'resolved clip header '..name,true)
                local duration=float(ch,8);assert(duration and duration>0 and duration<600,'Residency clip duration invalid')
                item.header_hex=hex(ch);item.duration=duration;item.header_u32={}
                for off=0,0x3c,4 do item.header_u32[#item.header_u32+1]=u32(ch,off)end
                item.resident=true
            else item.reason='Direct entry has no resolved resource pointer';all=false end
        else
            -- 632D90 also supports aliases. An uninspected alias is never treated
            -- as a proved resident resource, and this diagnostic does not resolve
            -- or create native resources to make it pass.
            item.reason='No direct clip entry; native aliases not followed';all=false
        end
        result.clips[#result.clips+1]=item
    end
    table.sort(result.clips,function(a,d)return a.id<d.id end)
    for _,entry in ipairs(selected)do result.selections[#result.selections+1]={layer=entry.layer,state=entry.state,clip=entry.clip,id=entry.id}end
    owner();generation()
    for _,entry in ipairs(copied)do assert(read(entry.at,entry.n,entry.label)==entry.raw,'Residency metadata/resource changed: '..entry.label)end
    owner();generation()
    assert(#selected==27,'Residency selected reference count changed')
    result.selected_references=#selected;result.all_direct_resident=all;result.unique_clips=#result.clips;result.copied_records=#copied
    result.protected_reads=read_count
    result.note='Slot metadata/header scalars retained opaque; no reference-count or count-field semantics guessed.'
    return {result=result,validate=function()
        owner();generation()
        for _,entry in ipairs(copied)do assert(read(entry.at,entry.n,entry.label)==entry.raw,'Resident proof changed: '..entry.label)end
        owner();generation();return result.all_direct_resident==true
    end}
end
function M.prove(backend,target24)
    local ok,proof=pcall(collect,backend,target24)
    if not ok then return nil,tostring(proof)end
    if proof.result.all_direct_resident~=true then
        return nil,'Required native ready-pose clips are not resident',proof.result
    end
    return proof
end
function M.inspect(backend,target24)
    local ok,proof=pcall(collect,backend,target24)
    if not ok then return nil,tostring(proof)end
    return proof.result
end
return M
