-- Packaged native ready-pose backend fixtures. Fake FFI/memory only; no game access.
local ROOT=NATIVE_ADS_TEST_ROOT or'.'
do
local contract=dofile(ROOT..'/src/first_person/ready_pose_contract.lua')
local constructing
local previous_mod=mod
local mock_compat={ffi={}}
function mock_compat.ffi.cast(...)return assert(constructing).P.ffi.cast(...)end
function mock_compat.ffi.new(signature)assert(signature=='int32_t[33]');return{}end
local mock_resources={prove=function(backend,target24)
 return assert(backend._ready_fixture).proof(target24)
end}
mod={require=function(name)
 if name=='src/first_person/compat51.lua'then return mock_compat end
 if name=='src/first_person/ready_pose_resources.lua'then return mock_resources end
 if name=='src/first_person/ready_pose_contract.lua'then return contract end
 error('Unexpected ready backend dependency '..tostring(name))
end}
local Adapter=dofile(ROOT..'/src/first_person/ready_pose_source.lua')
mod=previous_mod
local MAIN={states={},masks={},behaviors={},pins={}}
MAIN.states[59]='ce931a33c5a11d5e0200000015000000a8000000000000000000000001000000000000000000000009000000540100000e0000009c010000010000007c0200000000000000000000000000000000000082000000ec02000015000000f40400000000000000000000030000004600000001000000500100000000000000001000ffffffff0000000000000000000000000100000048050000000000000000000000000000000000007b129f0d5a301f00a855aed57e00260d7b129f0d5a301f00ac03186b691f81f17db022d3e3975d980b1761a569a70462ebb5d0e21391171dcc64776c3cce100681cd783724ef13e735b2a94dea4da9616f62adb4bb4f5dd2281dc76c229a71eeedf5c97a01456a5b14e389107632dff8b591c07ad63a80ccd3154ae6cf74355c3f00df5397c7974d7123f90bf30dc5d0d667c93c5b5448f4fec7e3f27c9d4cc4852d96f44b3b8efd0a000000ab4055b6000000006bb1ae1301000000d7a42ada02000000e3c5d96b000000801485880209000000d64729710a00000030b85f4f0b0000004eeabc150c0000006191cd8b0d00000000000000cdcc4c3e000000000000000015000000cdcc4c3e000000000000000011000000cdcc4c3e00000000000000003c000000cdcc4c3e00000000000000003c000000cdcc4c3e00000000000000003c000000cdcc4c3e000000000000000040000000cdcccc3d00000000000000003d000000cdcccc3d00000000000000003d000000cdcccc3d00000000000000004d000000cdcc4c3e00000000000000004c000000cdcc4c3e00000000000000003b0000000000803f0000000000000000430000000000803f0000000000000000430000009a99993e00000000000000000100000008000000800000000600000003000000000020410000e84100000000040000000000204200008a4200000000050000000000a0420000c842000000000600000000008c4200009e420000000007000000000000000000104100000000080000000000f04100001c42000000000000803f0000a07f0e00907f000080bf0000803f0000a0400b00807f0000a07f0e00907f0000803f0000a040000010410b00807f0000a07f0e00907f0000a04000001041000020410b00807f0000a07f0e00907f0000104100002041000060410b00807f0000a07f0e00907f0000504100006041000070410b00807f0000a07f0e00907f0000604100007041000098410b00807f0000a07f0e00907f000098410000a0410000a8410b00807f0000a07f0e00907f0000a0410000a8410000b0410b00807f0000a07f0e00907f0000a8410000b0410000e8410b00807f0000a07f0e00907f0000e8410000f04100000c420b00807f0000a07f0e00907f00000c420000104200001c420b00807f0000a07f0e00907f000044420000484200004c420b00807f0000a07f0e00907f0000484200004c42000050420b00807f0000a07f0e00907f00004c420000504200006c420b00807f0000a07f0e00907f00006c4200007042000074420b00807f0000a07f0e00907f000070420000744200008a420b00807f0000a07f0e00907f00008a4200008c4200009e420b00807f0000a07f0e00907f00009e420000a0420000b2420b00807f0000a07f0e00907f0000b2420000b4420000c8420b00807f0000a07f0e00907f00001c4200002442000028420b00807f0000a07f0e00907f0000244200002842000044420b00807f0000a07f0e00907f0000a07f02000000080000000e000000140000001a00000020000000260000002c00000032000000380000003e000000440000004a00000050000000560000005c00000062000000680000006e000000740000007a000000040000000000803f'
MAIN.states[67]='64952d6242873387010000000000000000000000000000000000000001000000010000000000000009000000ac0000000e000000f400000001000000d40100000000000000000000000000000000000004000000440200000000000000000000000000000000000003000000ffffffff01000000a80000000000000000004000ffffffff0000000000000000000000000000000000000000000000000000000000000000000000000e000000ab4055b6000000006bb1ae1301000000d7a42ada02000000e3c5d96b000000801485880209000000d64729710a00000030b85f4f0b0000004eeabc150c0000006191cd8b0d00000008000000cdcc4c3e000000000000000012000000cdcc4c3e000000000000000012000000cdcc4c3e00000000000000003c000000cdcc4c3e00000000000000003c000000cdcc4c3e00000000000000003c000000cdcc4c3e000000000000000040000000cdcccc3d00000000000000003d000000cdcccc3d00000000000000003d000000cdcccc3d00000000000000004d000000cdcc4c3e00000000000000004c000000cdcc4c3e00000000000000003b0000000000803f0000000000000000430000000000803f0000000000000000430000009a99993e00000000000000000100000008000000020000000600000003000000000020410000e84100000000040000000000204200008a4200000000050000000000a0420000c842000000000600000000008c4200009e420000000007000000000000000000104100000000080000000000f04100001c42000000000000803f0000a07f0e00907f0000a07f'
MAIN.masks[49]='000000000000000000000000000000000000000000000000cdcc4c3e0000003f9a99193f0000000000000000000000000000803f0000803f0000803f000000000000803f0000000000000000000000000000000000000000000000000000803f00000000000000000000000000000000000000000000000000000000000000000000803f0000803f0000803f0000803f0000803f0000803f0000803f0000803f0000803f000000000000000000000000000000000000003f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000803f0000000000000000000000000000803f0000803f000000000000803f00000000000000000000803f0000000000000000000000000000803f0000803f0000803f0000803f0000803f000000000000000000000000000000000000000000000000000000000000000000000000'
MAIN.masks[70]='000000000000000000000000cdcccc3e00000000000000009a99193f6666663f9a99193f0000000000000000000000009a99193fcdcc4c3f0000803f000000000000803f0000000000000000000000000000000000000000000000000000803f00000000000000000000000000000000000000000000000000000000000000009a99193f0000803f0000803f0000803f0000803f0000803f0000803f0000803f0000803f00000000000000000000803f000000009a99193f000000000000803f0000000000000000000000000000803f000000000000000000000000000000000000803f000000000000803f0000803f0000803f000000000000803f00000000000000000000803f0000803f0000803f000000000000803f00000000000000000000803f0000803f0000803f000000000000803f0000803f0000803f0000803f0000803f000000000000000000000000000000000000803f0000803f0000803f0000803f0000803f'
MAIN.masks[26]='0000000000000000000000000000000000000000000000000000000000000000cdcccc3e0000000000000000000000000000803f0000803f0000803f000000000000803f0000000000000000000000000000000000000000000000000000803f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000803f0000803f0000803f0000803f0000803f0000803f000000000000000000000000000000000000803f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000803f0000000000000000000000000000803f0000803f000000000000803f00000000000000000000803f0000000000000000000000000000803f0000803f0000803f0000803f0000803f000000000000000000000000000000000000000000000000000000000000000000000000'
MAIN.masks[45]='00000000000000000000803f0000803f0000803f0000803f0000803f0000803f00000000000000000000803f000000000000000000000000000000000000000000000000000000000000803f000000000000803f0000803f00000000000000000000803f0000803f000000000000000000000000000000000000803f0000803f0000803f000000000000803f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000803f0000803f0000803f0000000000000000000000000000000000000000'
MAIN.bank_offsets='1000000044000000fc000000b40100006c02000024030000dc030000940400004c05000004060000bc060000740700002c080000e40800009c090000540a00000c0b0000'
MAIN.behaviors[10]={{offset=0x0,hex='01000000310000000200000017000000ffffffff'},{offset=0x18,hex='00'},{offset=0x25,hex='000000'},{offset=0xb4,hex='0000803f'}}
MAIN.behaviors[14]={{offset=0x0,hex='010000001a0000000200000017000000ffffffff'},{offset=0x18,hex='00'},{offset=0x25,hex='000000'},{offset=0xb4,hex='0000803f'}}
MAIN.pins[#MAIN.pins+1]={name='entry_behavior_callbacks',rva=0x55cf39,hex='498b4628488bfb8b483085c97404488d3c08837e70000f8657010000488bce8bd3e831b3ffff4d8b66184533ff4c8965c84c8975d08b0c908b548f044803d7488955c08b0a85c9741a83f90175094c8d3d42520900eb13f20f1045880f10742478eb104c8d3d2d4f0900f20f1045d00f1075c0488b442460498b4e30468b2c28418bd5e8ef5a01004c8bc04885c0743b8b88980300008d410141898098030000488d511d488b44246848c1e2054e893c02420f11740208f2420f11440218488b5424604d8b6618448b2c104d8b4630488bcee880b2ffff8bcb4533ff4c8965c84c8975d08b0c888b548f044803d7488955c08b0a85c9741983f90175094c8d3d335f0900eb12f20f1045a80f107598eb104c8d3d0f5f0900f20f1045d00f1075c0418bd5498bc8e84b5a01004885c0742d8b88a00400008bd148c1e205ffc18988a00400004c89bc02a80400000f11b402b0040000f20f118402c00400004c8b6c2468ffc33b5e700f82aefeffff'}
MAIN.pins[#MAIN.pins+1]={name='entry_parameter_precedence',rva=0x55d18e,hex='4439be900000000f86720100008b8dd80900008d5901488d1449899de0090000488995d00900006666660f1f840000000000458b9eb001000040b701443bdb765390b8ffffffff4403d84084ff743e498b86b80100004f8d0c5b33d2468b04c84585c074234e8b4cc808488bcee8e0b0ffff428b04f8413904d17409ffc2413bd072e7eb034032ff443bdb77b5488b95d0090000488bce4e8d2cfd00000000e8aeb0ffff498b8eb80100004c8be0448b04d1488d1cd18b54d104418d48013bca762d83fa0872168bcab8ffffffff48d1e94803ca483bc876098bc8eb05b9080000008bd1488bcbe886d30000448b034b8b042c488b4b08418bd0488904d1ff034084ff745d4d8b4e30488bcee841b0ffff428b14284c6bc258e834b0ffff498b8960020000428b4428044189440838498b8160020000486bca58c744014000000000498b81600200008b8dd8090000f3450f114c0044498b816002000041894c00488b9de009000041ffc7488b95d0090000443bbe900000000f82b3feffff'}
MAIN.pins[#MAIN.pins+1]={name='exit_events_parameters',rva=0x55be6e,hex='438b543e143b56407377488bcee8d0c3ffff8bca4c8d044942837c8008027555428b448004418b9dc00000008985b0080000498b45008d53108b4808898db4080000498d8dc0000000e894fbafff498b8dc8000000488b85b0080000c7041908000000c7441904b291b6154889441908438b543e14ffc24389543e143b5640728933c9448be1398e900000000f866c010000448bb5b8080000418d7e0189bdb0080000458b8db0010000b301443bcf765f9041ffc984db0f842c010000498b85b80100004f8d14498bd1468b04d04585c074304e8b54d008458bdc0f1f8000000000488bcee888c3ffff8bca428b04d8413904ca7409ffc2413bd072e5eb0232db33c9443bcf77aa84db0f84d90000000f57c0448bf9458bd64585f674784d8bb5b80100000f1f4000660f1f84000000000041ffca8bd14b8d0452458b0cc64585c9742b4d8b5cc608418bdc660f1f440000488bce448bc2e815c3ffff8b0cd843390cc37410ffc2413bd172e533c94585d275beeb134b8d0452458bfa498b4cc608f3420f1044c104448bb5b80800008bbdb00800004d8b4d30488bcee8d0c2ffff418bcc8b14c8498b81600200004c6bc258486bca58f3410f11440038498b81600200004533d24489540140498b816002000042c7440044cdcc4c3d498b816002000046897c004841ffc4b900000000443ba6900000000f82a5feffff488b85c008000033d2488d0c40498b85b8010000488d0cc8e827d20000'}
MAIN.pins[#MAIN.pins+1]={name='type1_pose_controls',rva=0x5f21f9,hex='488b7908488bd9488b41104c8b31488d8d100100004889542420440f29bc24c0020000440f28fb4c8b6808488b87800000004983c510458b4e0c498bd548897da0468b0488488b87880000004c8bc84889442460e8dedcffff488b531033f6418b4e0848c1e1060f104830488b8298000000488975300f118dc0000000f20f104401308b4401388945c0488b4228418b5604f20f1145b80f57c0f30f7f453883faff750df30f7f4424704c8b642470eb2339701c750df30f7f4424704c8b642470eb118b48204803c88b5491044c8d61044c03e2'}
MAIN.pins[#MAIN.pins+1]={name='type1_feedback_guard',rva=0x5f2f7f,hex='488b194d8bd0488bf9807b18000f84200100008b431083f8ff0f8314010000'}
MAIN.pins[#MAIN.pins+1]={name='type1_axis25',rva=0x5f289c,hex='41807e2500440f28e6f3470f'}
MAIN.pins[#MAIN.pins+1]={name='type1_axis26',rva=0x5f291c,hex='41807e2600750b41807e27000f84af020000f30f'}
MAIN.pins[#MAIN.pins+1]={name='type1_feedback_multiplier',rva=0x5f2bdd,hex='f3450f59beb400000041'}
MAIN.pins[#MAIN.pins+1]={name='blend_flag_copy',rva=0x56d819,hex='8b85400c000089442458488b85480c0000f30f114424540f2805990a1e01488985e00200008b85500c0000898de802000048898d5005000048898d4805000048898d5805000048898d60050000488d8d80050000898540050000'}

local passed=0
local function u32(n)local out={};for i=1,4 do out[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(out)end
local function ptr(n)return u32(n%4294967296)..u32(math.floor(n/4294967296))end
local function unhex(s)return(s:gsub('..',function(c)return string.char(tonumber(c,16))end))end
local function fixture(initial24)
 local f={memory={},native_calls=0,invalidations=0,proofs=0,proof_checks=0,gates={},events={},token={}}
 function f:put(at,raw)for i=1,#raw do self.memory[at+i-1]=raw:byte(i)end end
 f.exe,f.object,f.instance,f.graph,f.active=0x140000000,0x100000,0x200000,0x300000,0x400000
 f.c={exe=f.exe,unit=123,index=7,generation=3,generations=0x500000,units=0x600000,object=f.object}
 f.b={frame_active=true,frame_epoch=11,profile={alignment={executable={unit_registry=0x1000}}}}
 function f.b:_read(at,n)
  assert(type(n)=='number'and n>=1 and n<=1024,'Actual backend protected-read cap exceeded')
  f.max_read=math.max(f.max_read or 0,n)
  if f.on_read then f:on_read(at,n)end
  local out={};for i=0,n-1 do out[i+1]=string.char(f.memory[at+i]or 0)end;return table.concat(out)
 end
 function f.b:_u8(at)return self:_read(at,1):byte(1)end
 function f.b:_u32(at)local a,b,c,d=self:_read(at,4):byte(1,4);return a+b*256+c*65536+d*16777216 end
 function f.b:_ptr(at)return self:_u32(at)+self:_u32(at+4)*4294967296 end
 function f.b:_alignment_context(s)assert(s.viewmodel==123);return f.c end
 function f.b:_alignment_executable()return f.exe end
 function f.b:_invalidate_frame_checks()f.invalidations=f.invalidations+1;self.frame_epoch=self.frame_epoch+1 end
 f.state={identity='weapon-instance',player_identity='player-generation',base=0x700000,context=2,camera=3,record=4,
  world=0x710000,avatar=987,avatar_descriptor=string.rep('a',20),
  controller_active=false,avatar_owner=6,avatar_index=0,body=123,weapon=789,weapon_unit=456,
  weapon_descriptor=string.rep('w',20),camera_kind=4,safe=true,
  flags=string.rep('\0',24),controller_bytes=string.rep('\0',24),shoulder_aim=false,reloading=false,aiming=false}
 f:put(f.state.base+0xa74821,unhex('4a8b841090e8530048c1e82624014883c408c3'))
 function f.b:snapshot()
  if f.on_snapshot then f:on_snapshot()end
  if f.no_full then return nil,'No equipped firearm' end
  local s={};for k,v in pairs(f.state)do s[k]=v end;return s
 end
 function f.b:player_snapshot()
  if f.no_player then return nil,'Player temporarily unavailable'end
  local s={};for k,v in pairs(f.player_state or f.state)do s[k]=v end;return s
 end
 function f.b.foreign_camera()return f.foreign or false end
 function f.b:action_state()
  return{resource_match=f.native_resource~=false,layer_count=31,unknown_layers=f.native_unknown and{3}or{},
   l3=f.l3 or 0,l14=f.l14 or 36,l1=f.l1 or 0}
 end
 function f.b:on_foot()return f.on_foot~=false end
 f:put(f.c.generations+7,string.char(3));f:put(f.c.units+7*8,ptr(f.object));f:put(f.object+8,u32(123))
 f.registry=0x900000;f.c.registry=f.registry
 f:put(f.exe+f.b.profile.alignment.executable.unit_registry,ptr(f.registry))
 f:put(f.registry+0x88,ptr(f.c.units)..string.rep('\0',8)..u32(16)..u32(0)..ptr(f.c.generations))
 f:put(f.object+0x70,u32(107));f:put(f.object+0x358,unhex('97fa4d294d331c4d'))
 f:put(f.object+0x178,ptr(f.instance));f:put(f.instance+0x28,ptr(f.graph));f:put(f.instance+0x50,ptr(f.active))
 f:put(f.graph+4,u32(31));f:put(f.graph+8,u32(0x100));f:put(f.graph+0x14,u32(54))
 f.addresses,f.layers={}, {[4]=67,[24]=initial24 or 0,[25]=3}
 for layer=1,31 do f:put(f.graph+0x104+(layer-1)*4,u32(0x1000));f:put(f.active+(layer-1)*8,ptr(0xd00000+layer*0x100))end
 for _,layer in ipairs({4,24,25})do
  local offset=layer==4 and 0x1000 or layer==24 and 0x40000 or 0x50000;f:put(f.graph+0x104+(layer-1)*4,u32(offset))
  local def=f.graph+0x100+offset;local count=layer==4 and 78 or layer==24 and 10 or 4;f:put(def+8,u32(count));f.addresses[layer]={}
  for state=0,count-1 do
   local state_offset=0x1000+state*0x800;local at=def+state_offset
   f.addresses[layer][state]=at;f:put(def+12+state*4,u32(state_offset))
   f:put(at+8,u32(layer==25 and state==3 and 1 or 2));f:put(at+0xc,u32(layer==25 and state==3 and 0 or(layer==24 and 2 or 4)))
   f:put(at+0x10,u32(0xb0))
   f:put(at+0xb0,layer==24 and(string.rep('\17',8)..string.rep(state>=5 and'\51'or'\34',8))or string.rep('\17',32))
  end
  f:put(f.active+(layer-1)*8,ptr(f.addresses[layer][f.layers[layer]]))
 end
 for index,raw in pairs(MAIN.states)do f:put(f.addresses[4][index],unhex(raw))end
 f:put(f.graph+0x1c,u32(80));f:put(f.graph+0x20,u32(0x80000))
 f:put(f.graph+0x2c,u32(0xbc4));f:put(f.graph+0x30,u32(0x90000))
 f.mask_table=f.graph+0x80000;f.behavior_bank=f.graph+0x90000
 f:put(f.mask_table,u32(80));f:put(f.behavior_bank,unhex(MAIN.bank_offsets))
 f.mask_at={};f.behavior_at={}
 for index,raw in pairs(MAIN.masks)do
  local offset=0x1000+index*0x200;f:put(f.mask_table+4+index*4,u32(offset));f.mask_at[index]=f.mask_table+offset
  f:put(f.mask_at[index],u32(90)..unhex(raw))
 end
 local function word(raw,offset)local a,b,c,d=raw:byte(offset+1,offset+4);return a+b*256+c*65536+d*16777216 end
 for index,controls in pairs(MAIN.behaviors)do
  local offset=word(unhex(MAIN.bank_offsets),4+index*4);f.behavior_at[index]=f.behavior_bank+offset
  for _,v in ipairs(controls)do f:put(f.behavior_at[index]+v.offset,unhex(v.hex))end
 end
 function f:set_layer(layer,state)
  self.layers[layer]=state;self:put(self.active+(layer-1)*8,ptr(self.addresses[layer][state]))
 end
 f.b.actions={}
 function f.b.actions:sample()
  return{resource_match=true,layer_count=31,unknown_layers={},instance=f.instance,graph=f.graph,body_object=f.object,
   states={[4]=f.layers[4],[24]=f.layers[24],[25]=f.layers[25]}}
 end
 local engine_root,api=0x800000,f.exe+tonumber(contract.table_rva,16)
 f:put(f.state.base+0x2ce14c8,ptr(engine_root));f:put(engine_root+0x18,ptr(api));f:put(api+0x3d8,ptr(f.exe+0x1f7ce0))
 for _,pin in ipairs(contract.pins)do f:put(f.exe+pin.rva,unhex(pin.hex))end
 for _,pin in ipairs(MAIN.pins)do f:put(f.exe+pin.rva,unhex(pin.hex))end
 f.P={ffi={}}
 function f.P.ffi.cast(signature,at)
  assert(signature=='void (*)(uint32_t,const int32_t *)'and at==f.exe+0x1f7ce0)
  return function(unit,values)
   assert(unit==123);f.native_calls=f.native_calls+1;f.events[#f.events+1]='setter'
   assert(values[32]==25);f.last_values={};for i=0,32 do f.last_values[i]=values[i]end
   for i=0,31 do
    if i~=3 and i~=23 and i~=24 then assert(values[i]==-1,'Unrelated layer requested')end
    if values[i]~=-1 then f:set_layer(i+1,values[i])end
   end
   if f.on_native then f:on_native()end
  end
 end
 function f.P.ffi.new(signature)assert(signature=='int32_t[33]');return{}end
 function f.proof(target24)
  local captured24=initial24 or 0;local hip24=captured24==1 and 0 or captured24==6 and 5 or captured24
  f.proof_variant=target24;assert(f.proof_variant==hip24+1)
  f.proofs=f.proofs+1;f.events[#f.events+1]='residency'
  if f.on_proof then f:on_proof()end
  local selections={};for i=1,(f.proof_selections or 27)do selections[i]={}end
  return{result={all_direct_resident=f.resident~=false,ready_layer4_state=f.proof_main_state or 59,
   hip_layer4_state=67,ready_layer24_state=f.proof_variant,selections=selections},validate=function()
   f.proof_checks=f.proof_checks+1;if f.on_validate then f:on_validate()end;return f.valid_residency~=false
  end}
 end
 function f.gate(expected,context,operation)
  f.events[#f.events+1]='gate';f.gates[#f.gates+1]={expected=expected,context=context,operation=operation}
  assert(expected.snapshot and expected.active==f.active and type(expected.action_verified)=='boolean')
  if f.on_gate then return f:on_gate(expected,context,operation)end
  return context and context.token==f.token and context.phase=='qualified_update','Mock normal-Update authority refused'
 end
 function f:context()return{phase='qualified_update',tick=1,token=self.token}end
 function f:construct(gate)
  constructing=self;self.b._ready_fixture=self
  return Adapter.new(self.b,gate or self.gate)
 end
 return f
end
local function test(name,fn)
 local ok,e=pcall(fn);assert(ok,name..': '..tostring(e));passed=passed+1
end
local function fails(fn,text)local ok,e=pcall(fn);assert(not ok and tostring(e):find(text,1,true),tostring(e))end
local function same(a,b)assert(a==b,tostring(a)..' ~= '..tostring(b))end

test('constructor requires injected authority before reads',function()
 local f=fixture();local reads=0;f.on_read=function()reads=reads+1 end
 fails(function()Adapter.new(f.b)end,'gate required');same(reads,0);same(f.native_calls,0)
end)
test('constructor never calls native or gate',function()
 local f=fixture();f:construct();same(f.native_calls,0);same(#f.gates,0);same(f.proofs,0)
end)
test('successful snapshots expose the qualified body reference and generation',function()
 local f=fixture();local a=f:construct();local s=a:snapshot()
 same(s.body_ref,f.c.unit);same(s.body_generation,f.c.generation);same(f.native_calls,0)
 f:put(f.c.generations+f.c.index,string.char(f.c.generation+1));s=a:snapshot()
 assert(s.retired==true and s.body_ref==nil and s.body_generation==nil)
end)
test('apply only two captured layers after fresh residency and gate',function()
 local f=fixture();local a=f:construct();local s=a:snapshot();assert(s.action_verified==false)
 assert(a:apply({[24]=1,[25]=1},s,f:context()));same(f.native_calls,1);same(a.calls,1)
 same(f.last_values[23],1);same(f.last_values[24],1);same(f.last_values[32],25)
 same(table.concat(f.events,','),'residency,gate,setter');same(f.invalidations,0)
end)
test('restore gates independently and retains state on refusal',function()
 local f=fixture();local a=f:construct();assert(a:apply({[24]=1,[25]=1},a:snapshot(),f:context()))
 local ok=a:restore({[24]=0,[25]=3},a:snapshot(),{});assert(ok==false);same(f.native_calls,1);same(f.layers[24],1);same(f.layers[25],1)
 same(a.gate_refusals,1);assert(a:restore({[24]=0,[25]=3},a:snapshot(),f:context()));same(f.native_calls,2)
 same(f.gates[2].operation,'restore');same(f.layers[24],0);same(f.layers[25],3)
end)
test('partial restore does not restart native changed layer',function()
 local f=fixture();local a=f:construct();assert(a:apply({[24]=1,[25]=1},a:snapshot(),f:context()));f:set_layer(25,3)
 assert(a:restore({[24]=0},a:snapshot(),f:context()));same(f.last_values[24],-1);same(f.layers[25],3)
end)
test('inactive frame refuses without injected gate or setter',function()
 local f=fixture();local a=f:construct();local s=a:snapshot();f.b.frame_active=false
 assert(a:apply({[24]=1},s,f:context())==false);same(#f.gates,0);same(f.native_calls,0);same(a.calls,0)
end)
test('gate exception refuses without setter',function()
 local f=fixture();f.on_gate=function()error('authority retired')end;local a=f:construct()
 local ok,why=a:apply({[24]=1},a:snapshot(),f:context());assert(ok==false and why:find('authority retired',1,true));same(f.native_calls,0)
end)
test('preflight requires private context and known cohort',function()
 local f=fixture();local a=f:construct();assert(a:can_mutate({},a:snapshot())==false)
 assert(a:can_mutate(f:context(),a:snapshot()));same(f.gates[#f.gates].operation,'preflight');same(f.native_calls,0)
 f:set_layer(24,2);local count=#f.gates;assert(a:can_mutate(f:context(),a:snapshot())==false);same(#f.gates,count)
end)
test('residency epoch bumps precede gate and are allowed',function()
 local f=fixture();f.on_proof=function()f.b.frame_epoch=f.b.frame_epoch+2 end
 f.on_gate=function()same(f.b.frame_epoch,13);return true end;local a=f:construct()
 assert(a:apply({[24]=1},a:snapshot(),f:context()));same(f.native_calls,1);same(f.invalidations,0)
end)
test('owner changes during residency prevent gate and setter',function()
 local f=fixture();f.on_validate=function()f.state.identity='another-instance'end;local a=f:construct();local s=a:snapshot()
 fails(function()a:apply({[24]=1},s,f:context())end,'player/input changed');same(#f.gates,0);same(f.native_calls,0)
end)
test('native action starts during residency prevent gate and setter',function()
 local f=fixture();f.on_validate=function()f.state.reloading=true end;local a=f:construct();local s=a:snapshot()
 fails(function()a:apply({[24]=1},s,f:context())end,'owner/action changed');same(#f.gates,0);same(f.native_calls,0)
end)
test('unknown cohort after gate prevents setter',function()
 local f=fixture();f.on_gate=function()f:set_layer(24,2);return true end;local a=f:construct();local s=a:snapshot()
 fails(function()a:apply({[24]=1},s,f:context())end,'owner/action changed');same(f.native_calls,0);same(a.calls,0)
end)
test('layer changes after gate prevent setter',function()
 local f=fixture();f.on_gate=function()f:set_layer(25,1);return true end;local a=f:construct();local s=a:snapshot()
 fails(function()a:apply({[24]=1},s,f:context())end,'layers changed after');same(f.native_calls,0)
end)
test('unrelated layer changes during gate prevent setter',function()
 local f=fixture();f.on_gate=function()f:put(f.active+4*8,ptr(0xf00000));return true end;local a=f:construct();local s=a:snapshot()
 fails(function()a:apply({[24]=1},s,f:context())end,'active layers changed after');same(f.native_calls,0)
end)
test('active array changes during gate prevent setter',function()
 local f=fixture();f.on_gate=function()f:put(f.instance+0x50,ptr(f.active+0x1000));return true end;local a=f:construct();local s=a:snapshot()
 fails(function()a:apply({[24]=1},s,f:context())end,'layers changed during observation');same(f.native_calls,0)
end)
test('camera or weapon changes after gate prevent setter',function()
 for _,key in ipairs({'camera','weapon_unit','flags','controller_bytes'})do
  local f=fixture();f.on_gate=function()f.state[key]=type(f.state[key])=='number'and f.state[key]+1 or 'different';return true end
  local a=f:construct();local s=a:snapshot();fails(function()a:apply({[24]=1},s,f:context())end,key=='flags'and'owner/action changed'or'player/input changed');same(f.native_calls,0)
 end
end)
test('retired frame after gate prevents setter',function()
 local f=fixture();f.on_gate=function()f.b.frame_active=false;return true end;local a=f:construct();local s=a:snapshot()
 fails(function()a:apply({[24]=1},s,f:context())end,'frame retired');same(f.native_calls,0)
end)
test('epoch change after gate prevents setter',function()
 local f=fixture();local gated=false;f.on_gate=function()gated=true;return true end
 f.on_snapshot=function()if gated then f.b.frame_epoch=f.b.frame_epoch+1 end end;local a=f:construct();local s=a:snapshot()
 fails(function()a:apply({[24]=1},s,f:context())end,'frame retired');same(f.native_calls,0)
end)
test('target headers changed by gate prevent setter',function()
 local f=fixture();f.on_gate=function()f:put(f.addresses[24][1]+0x40,u32(1));return true end;local a=f:construct();local s=a:snapshot()
 fails(function()a:apply({[24]=1},s,f:context())end,'target definition changed');same(f.native_calls,0)
end)
test('code pin changed by gate prevents setter',function()
 local f=fixture();f.on_gate=function()f:put(f.exe+contract.pins[1].rva,'\0');return true end;local a=f:construct();local s=a:snapshot()
 fails(function()a:apply({[24]=1},s,f:context())end,'setter contract changed');same(f.native_calls,0)
end)
test('resident refusal and unknown native action never authorize',function()
 local f=fixture();local a=f:construct();f.resident=false
 fails(function()a:apply({[24]=1},a:snapshot(),f:context())end,'assertion failed');same(#f.gates,0);same(f.native_calls,0)
 f.native_unknown=true;fails(function()a:snapshot()end,'action sample unqualified')
end)
test('only complete qualified native action guard authorizes an action cycle',function()
 local f=fixture();local a=f:construct();f.l3=71
 local s=a:snapshot();assert(s.sprint and s.action_verified==false)
 f.state.flags=string.rep('\0',9)..string.char(4)..string.rep('\0',14);s=a:snapshot();assert(s.sprint and s.action_verified==true)
 f.state.flags=string.rep('\0',24)
 f.state.reloading=true;s=a:snapshot();assert(s.reload and s.action_verified==true)
 f.state.reloading=false;f.state.aiming=true;s=a:snapshot();assert(s.actualAim and s.action_verified==true)
 same(f.native_calls,0)
end)
test('firing requires exact native bit102 and main60 for budget authority',function()
 local f=fixture();local a=f:construct()
 f.state.flags=string.rep('\0',12)..string.char(64)..string.rep('\0',11)
 local s=a:snapshot();assert(s.firing and not s.firing_verified and not s.action_verified)
 assert(not a:can_mutate(f:context(),s));same(#f.gates,0)
 f:set_layer(4,60);s=a:snapshot();assert(s.firing and s.firing_verified and s.action_verified)
 assert(not a:can_mutate(f:context(),s));same(#f.gates,0)
 f.state.flags=string.rep('\0',24);s=a:snapshot();assert(not s.firing and not s.firing_verified and not s.action_verified)
 assert(not a:can_mutate(f:context(),s));same(f.native_calls,0)
end)
test('neighboring bit94 is not the observed firing flag',function()
 local f=fixture();local a=f:construct();f:set_layer(4,60)
 f.state.flags=string.rep('\0',11)..string.char(64)..string.rep('\0',12)
 local s=a:snapshot();assert(not s.firing and not s.firing_verified and not s.action_verified)
 same(f.native_calls,0)
end)
test('firing starts after preflight without allowing a native setter',function()
 local f=fixture();local a=f:construct();local s=a:snapshot();assert(a:can_mutate(f:context(),s))
 f.state.flags=string.rep('\0',12)..string.char(64)..string.rep('\0',11)
 fails(function()a:apply({[4]=59,[24]=1,[25]=1},s,f:context())end,'native action or unknown cohort')
 same(f.proofs,0);same(f.native_calls,0);same(#f.gates,1)
end)
test('firing starts in final gate without allowing a native setter',function()
 local f=fixture();local a=f:construct()
 f.on_gate=function()f.state.flags=string.rep('\0',12)..string.char(64)..string.rep('\0',11);return true end
 fails(function()a:apply({[4]=59,[24]=1,[25]=1},a:snapshot(),f:context())end,'owner/action changed after native-call gate')
 same(f.native_calls,0)
end)
test('firing during restoration retains the untouched target layers',function()
 local f=fixture();local a=f:construct();assert(a:apply({[4]=59,[24]=1,[25]=1},a:snapshot(),f:context()))
 f.on_gate=function()f.state.flags=string.rep('\0',12)..string.char(64)..string.rep('\0',11);return true end
 fails(function()a:restore({[4]=67,[24]=0,[25]=3},a:snapshot(),f:context())end,'owner/action changed after native-call gate')
 same(f.native_calls,1);same(f.layers[4],59);same(f.layers[24],1);same(f.layers[25],1)
end)
test('firing consumer fingerprint is required before construction',function()
 local f=fixture();f:put(f.state.base+0xa74821,'\0')
 fails(function()f:construct()end,'firing flag consumer changed');same(f.native_calls,0)
end)
test('firing consumer drift cannot authorize an action or a setter',function()
 local f=fixture();local a=f:construct();f:put(f.state.base+0xa74821,'\0')
 f.state.flags=string.rep('\0',12)..string.char(64)..string.rep('\0',11);f:set_layer(4,60)
 fails(function()a:snapshot()end,'firing flag consumer changed')
 f.state.flags=string.rep('\0',24);f:set_layer(4,67)
 fails(function()a:apply({[4]=59,[24]=1,[25]=1},a:snapshot(),f:context())end,'firing flag consumer changed')
 same(f.native_calls,0);same(f.proofs,0)
end)
test('firing consumer drift in final gate refuses the native setter',function()
 local f=fixture();local a=f:construct();f.on_gate=function()f:put(f.state.base+0xa74821,'\0');return true end
 fails(function()a:apply({[4]=59,[24]=1,[25]=1},a:snapshot(),f:context())end,'firing flag consumer changed')
 same(f.native_calls,0)
end)
test('same state restart and unrelated layers rejected',function()
 local f=fixture();local a=f:construct();fails(function()a:apply({[23]=1},a:snapshot(),f:context())end,'another layer')
 assert(a:apply({[24]=1},a:snapshot(),f:context()));fails(function()a:apply({[24]=1},a:snapshot(),f:context())end,'restart an unchanged layer');same(f.native_calls,1)
end)
test('foreign mutation of other layer detected after mocked native call',function()
 local f=fixture();f.on_native=function()f:put(f.active,ptr(0xee0000))end;local a=f:construct()
 fails(function()a:apply({[24]=1},a:snapshot(),f:context())end,'changed another layer');same(f.native_calls,1)
end)
test('actual adapter unqualified on-foot lifecycle blocks without budget authority',function()
 local f=fixture();local a=f:construct();f.on_foot=false;local s=a:snapshot()
 assert(not s.safeNormal4 and s.action_verified==false);assert(not a:can_mutate(f:context(),s));same(f.native_calls,0)
end)
test('variant5 captures six and applies/restores exact native family',function()
 local f=fixture(5);local a=f:construct();same(a.ready_variant.hip24,5);same(a.ready_variant.target24,6)
 local d=a:describe();same(d.ready_variant.hip24,5);same(d.ready_variant.target24,6)
 assert(a:apply({[24]=6,[25]=1},a:snapshot(),f:context()))
 same(f.last_values[23],6);same(f.layers[24],6);same(f.proof_variant,6)
 assert(a:restore({[24]=5,[25]=3},a:snapshot(),f:context()))
 same(f.last_values[23],5);same(f.layers[24],5);same(f.layers[25],3);same(f.native_calls,2)
end)
test('constructors refuse unproved L24 families and unreleased L25',function()
 for _,state in ipairs({2,3,4,7,8,9})do
  local f=fixture(state);fails(function()f:construct()end,'released hip family');same(f.native_calls,0);same(#f.gates,0)
 end
 for _,state in ipairs({0,1,5,6})do
  local f=fixture(state);f:set_layer(25,1);fails(function()f:construct()end,'released hip family');same(f.native_calls,0)
 end
end)
for _,target24 in ipairs({1,6})do
 test('released main borrows native L24 target'..target24..' without setting or restoring it',function()
  local f=fixture(target24);local a=f:construct()
  same(a.ready_variant.hip24,target24-1);same(a.ready_variant.target24,target24)
  same(a:snapshot().layers[24],target24);same(f.native_calls,0);same(#f.gates,0)
  assert(a:apply({[4]=59,[25]=1},a:snapshot(),f:context()))
  same(f.last_values[23],-1);same(f.layers[24],target24);same(f.proof_variant,target24)
  assert(a:restore({[4]=67,[25]=3},a:snapshot(),f:context()))
  same(f.last_values[23],-1);same(f.layers[24],target24);same(f.layers[4],67);same(f.layers[25],3)
  same(f.native_calls,2)
 end)
 test('borrowed L24 target'..target24..' still requires its captured active pointer',function()
  local f=fixture(target24);f:put(f.active+23*8,ptr(f.addresses[24][target24-1]))
  fails(function()f:construct()end,'initial hip family changed during capture');same(f.native_calls,0)
 end)
 test('borrowed L24 target'..target24..' never permits an unreleased main constructor',function()
  for _,main in ipairs({59,60,68})do
   local f=fixture(target24);f:set_layer(4,main)
   fails(function()f:construct()end,'released hip family');same(f.native_calls,0)
  end
 end)
end
test('variant5 refuses target1 or restore0 instead of captured pair',function()
 local f=fixture(5);local a=f:construct()
 fails(function()a:apply({[24]=1},a:snapshot(),f:context())end,'captured native state');same(f.native_calls,0)
 assert(a:apply({[24]=6},a:snapshot(),f:context()))
 fails(function()a:restore({[24]=0},a:snapshot(),f:context())end,'captured native state');same(f.native_calls,1)
end)
test('variant changed before apply is refused without any setter',function()
 local f=fixture(5);local a=f:construct();f:set_layer(24,0)
 fails(function()a:apply({[24]=6,[25]=1},a:snapshot(),f:context())end,'family changed before apply')
 same(f.native_calls,0);same(#f.gates,0)
 fails(function()a:apply({[25]=1},a:snapshot(),f:context())end,'family changed before apply');same(f.native_calls,0)
end)
test('variant changed during residency aborts before gate and setter',function()
 local f=fixture(5);local a=f:construct();f.on_validate=function()f:set_layer(24,0)end
 fails(function()a:apply({[24]=6},a:snapshot(),f:context())end,'layers changed during asset validation')
 same(f.native_calls,0);same(#f.gates,0)
end)
test('variant changed during gate aborts without setter',function()
 local f=fixture(5);local a=f:construct();f.on_gate=function()f:set_layer(24,0);return true end
 fails(function()a:apply({[24]=6},a:snapshot(),f:context())end,'layers changed after native-call gate');same(f.native_calls,0)
end)
test('native other family permits only L25 partial cleanup',function()
 for _,variant in ipairs({{0,1,6},{5,6,1},{5,6,0}})do
  local f=fixture(variant[1]);local a=f:construct()
  assert(a:apply({[24]=variant[2],[25]=1},a:snapshot(),f:context()));f:set_layer(24,variant[3])
  assert(a:can_mutate(f:context(),a:snapshot()))
  assert(a:restore({[25]=3},a:snapshot(),f:context()))
  same(f.layers[24],variant[3]);same(f.layers[25],3);same(f.last_values[23],-1);same(f.native_calls,2)
 end
end)
test('native other family never gets overwritten by stale L24 restore',function()
 local f=fixture(5);local a=f:construct();assert(a:apply({[24]=6,[25]=1},a:snapshot(),f:context()))
 f:set_layer(24,1);fails(function()a:restore({[24]=5},a:snapshot(),f:context())end,'captured source state')
 same(f.native_calls,1);same(f.layers[24],1)
end)
test('three-layer main pair applies and restores with28 states skipped',function()
 local f=fixture(5);local a=f:construct();same(a.main_pair.hip4,67);same(a.main_pair.target4,59)
 assert(a:apply({[4]=59,[24]=6,[25]=1},a:snapshot(),f:context()))
 same(f.last_values[3],59);same(f.last_values[23],6);same(f.last_values[24],1)
 local skipped=0;for i=0,30 do if f.last_values[i]==-1 then skipped=skipped+1 end end;same(skipped,28)
 assert(a:restore({[4]=67,[24]=5,[25]=3},a:snapshot(),f:context()))
 same(f.last_values[3],67);same(f.layers[4],67);same(f.layers[24],5);same(f.layers[25],3);same(f.native_calls,2)
end)
test('1360byte mainpayload is chunked during constructor and later rechecks',function()
 local f=fixture();local chunks={};local at=f.addresses[4][59]
 f.on_read=function(_,where,n)if where>=at and where<at+0x550 then chunks[where]=math.max(chunks[where]or 0,n)end end
 local a=f:construct();same(chunks[at],1024);same(chunks[at+1024],0x550-1024)
 chunks={};assert(a:apply({[4]=59,[24]=1,[25]=1},a:snapshot(),f:context()))
 same(chunks[at],1024);same(chunks[at+1024],0x550-1024)
 assert(a:restore({[4]=67,[24]=0,[25]=3},a:snapshot(),f:context()));same(f.max_read,1024)
end)
test('main constructor requires exacthip67',function()
 for _,state in ipairs({59,60,68})do local f=fixture();f:set_layer(4,state)
  fails(function()f:construct()end,'released hip family');same(f.native_calls,0)
 end
end)
test('unknown main state blocks even L25-only cleanup',function()
 local f=fixture();local a=f:construct();assert(a:apply({[4]=59,[24]=1,[25]=1},a:snapshot(),f:context()))
 f:set_layer(4,60);local s=a:snapshot();assert(not a:can_mutate(f:context(),s))
 fails(function()a:restore({[25]=3},s,f:context())end,'native action or unknown cohort');same(f.native_calls,1)
end)
test('only exact owned59 can restore67',function()
 local f=fixture();local a=f:construct()
 fails(function()a:apply({[4]=60},a:snapshot(),f:context())end,'captured native state');same(f.native_calls,0)
 assert(a:apply({[4]=59},a:snapshot(),f:context()))
 fails(function()a:restore({[4]=68},a:snapshot(),f:context())end,'captured native state');same(f.native_calls,1)
end)
test('main state change aftergate makes zero writes',function()
 local f=fixture();local a=f:construct();f.on_gate=function()f:set_layer(4,59);return true end
 fails(function()a:apply({[4]=59,[24]=1,[25]=1},a:snapshot(),f:context())end,'layers changed after native-call gate')
 same(f.native_calls,0);same(a.calls,0)
end)
test('exact main program and parameter pair are pinned atconstruction',function()
 for _,offset in ipairs({0x2ec,0x548,0x54c})do local f=fixture();f:put(f.addresses[4][59]+offset,u32(999))
  fails(function()f:construct()end,'main-layer authored payload changed');same(f.native_calls,0)
 end
end)
test('main event orflag drift is rejected',function()
 for _,offset in ipairs({0x40,0x7c,0x70,0x90})do local f=fixture();f:put(f.addresses[4][59]+offset,u32(999))
  fails(function()f:construct()end,'main-layer authored payload changed');same(f.native_calls,0)
 end
end)
test('consumed behaviorcontrols drift rejected atconstruction',function()
 for _,offset in ipairs({0,4,8,0xc,0x10,0x18,0x25,0xb4})do local f=fixture()
  local at=f.behavior_at[10]+offset;f:put(at,string.char((f.b:_u8(at)+1)%256))
  fails(function()f:construct()end,'consumed control changed');same(f.native_calls,0)
 end
end)
test('unused behaviorpadding can differ without invented pointersemantics',function()
 local f=fixture();f:put(f.behavior_at[10]+0x48,string.rep('X',8));local a=f:construct()
 f:put(f.behavior_at[14]+0x88,string.rep('Y',8))
 assert(a:apply({[4]=59,[24]=1,[25]=1},a:snapshot(),f:context()));same(f.native_calls,1)
end)
test('allfour authored masks including49and26 are pinned',function()
 for _,index in ipairs({26,45,49,70})do local f=fixture();f:put(f.mask_at[index]+4,u32(0x7fc00000))
  fails(function()f:construct()end,'mask weights changed');same(f.native_calls,0)
 end
end)
test('behavior ormask drift during gate prevents allthree writes',function()
 for _,kind in ipairs({'behavior','mask'})do local f=fixture();local a=f:construct()
  f.on_gate=function()f:put(kind=='behavior'and f.behavior_at[10]+0x25 or f.mask_at[49]+4,'X');return true end
  fails(function()a:apply({[4]=59,[24]=1,[25]=1},a:snapshot(),f:context())end,'state mapping changed');same(f.native_calls,0)
 end
end)
test('newmain code pins also rechecked aftergate',function()
 local f=fixture();local a=f:construct();f.on_gate=function()f:put(f.exe+MAIN.pins[5].rva,'X');return true end
 fails(function()a:apply({[4]=59,[24]=1,[25]=1},a:snapshot(),f:context())end,'main animation code changed');same(f.native_calls,0)
end)
test('six-clip or wrongmain residentproof never authorizes L4',function()
 local f=fixture();local a=f:construct();f.proof_selections=6
 fails(function()a:apply({[4]=59},a:snapshot(),f:context())end,'assertion failed');same(f.native_calls,0);same(#f.gates,0)
 f.proof_selections=27;f.proof_main_state=58
 fails(function()a:apply({[4]=59},a:snapshot(),f:context())end,'assertion failed');same(f.native_calls,0)
end)

local function owned_fixture()
 local f=fixture(5);local a=f:construct()
 assert(a:apply({[4]=59,[24]=6,[25]=1},a:snapshot(),f:context()))
 return f,a
end
test('weapon swap keeps graph owner and restores against current weapon identity',function()
 local f,a=owned_fixture();local token=a:snapshot().ownerToken
 f.state.identity='weapon-two';f.state.weapon_unit=457;f.state.record=55
 same(a:snapshot().ownerToken,token)
 assert(a:restore({[4]=67,[24]=5,[25]=3},a:snapshot(),f:context()));same(f.native_calls,2)
end)
test('camera roundtrip keeps graph owner and restores current camera identity',function()
 local f,a=owned_fixture();local token=a:snapshot().ownerToken
 f.state.camera_kind=6;f.state.controller_active=true;f.state.camera=44;f.state.context=33
 f.state.player_identity='player-camera6';f.state.identity='weapon-camera6'
 local s=a:snapshot();same(s.ownerToken,token);assert(s.ads and not s.safeNormal4 and not s.retired)
 assert(not a:can_mutate(f:context(),s));same(f.native_calls,1)
 f.state.camera_kind=4;f.state.controller_active=false;f.state.camera=45;f.state.context=34
 f.state.player_identity='player-camera4-new';f.state.identity='weapon-camera4-new'
 assert(a:restore({[4]=67,[24]=5,[25]=3},a:snapshot(),f:context()));same(f.native_calls,2)
end)
test('missing firearm preserves body owner without granting mutation',function()
 local f,a=owned_fixture();local token=a:snapshot().ownerToken;f.no_full=true
 local s=a:snapshot();same(s.ownerToken,token);assert(not s.retired and not s.safeNormal4)
 assert(not a:can_mutate(f:context(),s));same(f.native_calls,1)
end)
test('positive graph or instance retirement never calls setter',function()
 for _,kind in ipairs({'graph','instance'})do
  local f,a=owned_fixture()
  if kind=='graph'then f:put(f.instance+0x28,ptr(f.graph+0x100000))else f:put(f.object+0x178,ptr(0));f.no_full=true end
  assert(a:snapshot().retired);same(f.native_calls,1)
 end
end)
test('current registry generation and resized registry are requalified',function()
 local f,a=owned_fixture();f:put(f.c.generations+7,string.char(4));assert(a:snapshot().retired);same(f.native_calls,1)
 f,a=owned_fixture();local units,generations=0xa00000,0xb00000
 f:put(f.registry+0x88,ptr(units)..string.rep('\0',8)..u32(32)..u32(0)..ptr(generations))
 f:put(generations+7,string.char(4));f:put(units+7*8,ptr(f.object))
 assert(a:snapshot().retired);same(f.native_calls,1)
end)
test('protected registry failure remains transient',function()
 local f,a=owned_fixture();f.on_read=function(_,at)if at==f.registry+0x88 then error('registry unavailable')end end
 local s,why=a:snapshot();assert(s==nil and why:find('registry unavailable',1,true));same(f.native_calls,1)
end)
test('all individual native aim bits forbid state calls',function()
 for _,pair in ipairs({{7,0},{11,2},{16,5}})do
  local f,a=owned_fixture();local bytes={};for i=1,24 do bytes[i]=i==pair[1]and 2^pair[2]or 0 end
  f.state.flags=string.char(unpack(bytes));local s=a:snapshot();assert(s.actualAim)
  assert(not a:can_mutate(f:context(),s));same(f.native_calls,1)
 end
end)
test('bridge sprint entry and steady states forbid state calls',function()
 for _,l1 in ipairs({75,78})do
  local f,a=owned_fixture();f.l14=3;f.l3=68;f.l1=l1;local s=a:snapshot();assert(s.sprint)
  assert(not a:can_mutate(f:context(),s));same(f.native_calls,1)
 end
end)
test('weapon token excludes camera and request identity but tracks weapon ownership',function()
 local f=fixture();local a=f:construct();local original=a:snapshot().stable_weapon_token
 same(a:snapshot().weapon_token,original)
 assert(type(original)=='string'and original:match('^%d+:%d+:%x+$'))
 f.state.camera=333;f.state.context=444;f.state.record=555
 f.state.identity='camera-only';f.state.player_identity='camera-player-only'
 same(a:snapshot().stable_weapon_token,original)
 for _,key in ipairs({'weapon','weapon_unit','weapon_descriptor'})do
  local saved=f.state[key];f.state[key]=type(saved)=='number'and saved+1 or string.rep('z',20)
  assert(a:snapshot().stable_weapon_token~=original);f.state[key]=saved
 end
 f.state.weapon_descriptor=nil;local s=a:snapshot()
 assert(s.stable_weapon_token==nil and not s.safeNormal4 and not s.retired)
end)
test('native weapon transition is verified but never mutation eligible',function()
 local f=fixture();local a=f:construct();f.state.weapon_transition=true
 local s=a:snapshot();assert(s.weapon_transition and s.action_verified and not s.safeNormal4)
 assert(not a:can_mutate(f:context(),s));same(f.native_calls,0)
end)
test('weapon transition after manager preflight refuses initial apply snapshot',function()
 local f=fixture();local a=f:construct();local s=a:snapshot();assert(a:can_mutate(f:context(),s))
 f.state.weapon_transition=true
 fails(function()a:apply({[4]=59,[24]=1,[25]=1},s,f:context())end,'native action or unknown cohort')
 same(f.native_calls,0);same(f.proofs,0);same(#f.gates,1)
end)
test('weapon descriptor after manager preflight refuses initial apply snapshot',function()
 local f=fixture();local a=f:construct();local s=a:snapshot();assert(a:can_mutate(f:context(),s))
 f.state.weapon_descriptor=string.rep('z',20)
 fails(function()a:apply({[4]=59,[24]=1,[25]=1},s,f:context())end,'weapon ownership changed before native call')
 same(f.native_calls,0);same(f.proofs,0);same(#f.gates,1)
end)
test('weapon descriptor change inside final gate refuses native mutation',function()
 local f=fixture();local a=f:construct();f.on_gate=function()f.state.weapon_descriptor=string.rep('z',20);return true end
 fails(function()a:apply({[4]=59,[24]=1,[25]=1},a:snapshot(),f:context())end,'weapon ownership changed')
 same(f.native_calls,0)
end)
print('Ready pose adapter: '..passed..' cases passed (no native calls)')
end

do
local Resources=dofile(ROOT..'/src/first_person/ready_pose_resources.lua')
local resource_path=ROOT..'/src/first_person/ready_pose_resources.lua'
local h=assert(io.open(resource_path,'rb'));local source=h:read('*a');h:close()
local passed=0
local function unhex(s)return(s:gsub('..',function(c)return string.char(tonumber(c,16))end))end
local function u32(n)local a={};for i=1,4 do a[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(a)end
local function ptr(n)return u32(n%4294967296)..u32(math.floor(n/4294967296))end
local function le(s)return unhex(s):reverse()end
local IDS={'469cb23d97d2e41c','2b85e4e5dbeab474','d98c81205d9a0452',
 '9fc7391f2d587eb4','9bf7e729369146ba','95bf5e66251c0fef','87ff303d5289b9fa'}
local MAINIDS={'001f305a0d9f127b','0d26007ed5ae55a8','001f305a0d9f127b','f1811f696b1803ac','985d97e3d322b07d','6204a769a561170b','1d179113e2d0b5eb','0610ce3c6c7764cc','e713ef243778cd81','61a94dea4da9b235','d25d4fbbb4ad626f','ee719a226cc71d28','5b6a45017ac9f5ed','f8df32761089e314','cc803ad67ac091b5','5c3574cfe64a15d3','4d97c79753df003f','d0c50df30bf92371','f448545b3cc967d6','c44c9d7cf2e3c7fe','fd8e3b4bf4962d85'}
local MAINPAYLOAD={
 [59]='ce931a33c5a11d5e0200000015000000a8000000000000000000000001000000000000000000000009000000540100000e0000009c010000010000007c0200000000000000000000000000000000000082000000ec02000015000000f40400000000000000000000030000004600000001000000500100000000000000001000ffffffff0000000000000000000000000100000048050000000000000000000000000000000000007b129f0d5a301f00a855aed57e00260d7b129f0d5a301f00ac03186b691f81f17db022d3e3975d980b1761a569a70462ebb5d0e21391171dcc64776c3cce100681cd783724ef13e735b2a94dea4da9616f62adb4bb4f5dd2281dc76c229a71eeedf5c97a01456a5b14e389107632dff8b591c07ad63a80ccd3154ae6cf74355c3f00df5397c7974d7123f90bf30dc5d0d667c93c5b5448f4fec7e3f27c9d4cc4852d96f44b3b8efd0a000000ab4055b6000000006bb1ae1301000000d7a42ada02000000e3c5d96b000000801485880209000000d64729710a00000030b85f4f0b0000004eeabc150c0000006191cd8b0d00000000000000cdcc4c3e000000000000000015000000cdcc4c3e000000000000000011000000cdcc4c3e00000000000000003c000000cdcc4c3e00000000000000003c000000cdcc4c3e00000000000000003c000000cdcc4c3e000000000000000040000000cdcccc3d00000000000000003d000000cdcccc3d00000000000000003d000000cdcccc3d00000000000000004d000000cdcc4c3e00000000000000004c000000cdcc4c3e00000000000000003b0000000000803f0000000000000000430000000000803f0000000000000000430000009a99993e00000000000000000100000008000000800000000600000003000000000020410000e84100000000040000000000204200008a4200000000050000000000a0420000c842000000000600000000008c4200009e420000000007000000000000000000104100000000080000000000f04100001c42000000000000803f0000a07f0e00907f000080bf0000803f0000a0400b00807f0000a07f0e00907f0000803f0000a040000010410b00807f0000a07f0e00907f0000a04000001041000020410b00807f0000a07f0e00907f0000104100002041000060410b00807f0000a07f0e00907f0000504100006041000070410b00807f0000a07f0e00907f0000604100007041000098410b00807f0000a07f0e00907f000098410000a0410000a8410b00807f0000a07f0e00907f0000a0410000a8410000b0410b00807f0000a07f0e00907f0000a8410000b0410000e8410b00807f0000a07f0e00907f0000e8410000f04100000c420b00807f0000a07f0e00907f00000c420000104200001c420b00807f0000a07f0e00907f000044420000484200004c420b00807f0000a07f0e00907f0000484200004c42000050420b00807f0000a07f0e00907f00004c420000504200006c420b00807f0000a07f0e00907f00006c4200007042000074420b00807f0000a07f0e00907f000070420000744200008a420b00807f0000a07f0e00907f00008a4200008c4200009e420b00807f0000a07f0e00907f00009e420000a0420000b2420b00807f0000a07f0e00907f0000b2420000b4420000c8420b00807f0000a07f0e00907f00001c4200002442000028420b00807f0000a07f0e00907f0000244200002842000044420b00807f0000a07f0e00907f0000a07f02000000080000000e000000140000001a00000020000000260000002c00000032000000380000003e000000440000004a00000050000000560000005c00000062000000680000006e000000740000007a000000040000000000803f',
 [67]='64952d6242873387010000000000000000000000000000000000000001000000010000000000000009000000ac0000000e000000f400000001000000d40100000000000000000000000000000000000004000000440200000000000000000000000000000000000003000000ffffffff01000000a80000000000000000004000ffffffff0000000000000000000000000000000000000000000000000000000000000000000000000e000000ab4055b6000000006bb1ae1301000000d7a42ada02000000e3c5d96b000000801485880209000000d64729710a00000030b85f4f0b0000004eeabc150c0000006191cd8b0d00000008000000cdcc4c3e000000000000000012000000cdcc4c3e000000000000000012000000cdcc4c3e00000000000000003c000000cdcc4c3e00000000000000003c000000cdcc4c3e00000000000000003c000000cdcc4c3e000000000000000040000000cdcccc3d00000000000000003d000000cdcccc3d00000000000000003d000000cdcccc3d00000000000000004d000000cdcc4c3e00000000000000004c000000cdcc4c3e00000000000000003b0000000000803f0000000000000000430000000000803f0000000000000000430000009a99993e00000000000000000100000008000000020000000600000003000000000020410000e84100000000040000000000204200008a4200000000050000000000a0420000c842000000000600000000008c4200009e420000000007000000000000000000104100000000080000000000f04100001c42000000000000803f0000a07f0e00907f0000a07f',
}
local known={};for _,id in ipairs(IDS)do known[id]=true end
for _,id in ipairs(MAINIDS)do if not known[id]then IDS[#IDS+1]=id;known[id]=true end end
local function fixture(graph_offset)
 local f={memory={},reads=0,contexts=0,rows={},slots={},state_clips={},states={}}
 function f:put(at,raw)for i=1,#raw do self.memory[at+i-1]=raw:byte(i)end end
 function f:zero(at,n)self:put(at,string.rep('\0',n))end
 function f:read(at,n)
  self.reads=self.reads+1;assert(n>0 and n<=1024,'Mock read exceeds backend bounds')
  if self.on_read then self:on_read(at,n)end
  local a={};for i=0,n-1 do assert(self.memory[at+i]~=nil,'Mock unmapped protected read');a[#a+1]=string.char(self.memory[at+i])end
  return table.concat(a)
 end
 f.exe,f.object,f.instance,f.graph,f.world,f.manager=0x140000000,0x100000,0x200000,0x300000+(graph_offset or 0),0x400000,0x500000
 f.class_array,f.slot_array,f.clip_array=0x600000,0x700000,0x800000
 f.c={exe=f.exe,unit=3*0x400000+7,index=7,generation=3,generations=0x900000,units=0xa00000,registry=0xb00000,object=f.object}
 f:put(f.c.generations+7,string.char(3));f:put(f.c.units+7*8,ptr(f.object));f:put(f.object+8,u32(f.c.unit))
 f:put(f.object+0x70,u32(107));f:put(f.object+0x358,unhex('97fa4d294d331c4d'));f:put(f.object+0x18,ptr(f.world))
 local vt=0x110000;f:put(f.object,ptr(vt));f:put(vt+0x1b0,ptr(f.exe+0x28d460));f:put(vt+0x1b8,ptr(f.exe+0x28d470))
 f:put(f.object+0x178,ptr(f.instance));f:put(f.instance+0x28,ptr(f.graph));f:put(f.instance+0x20,ptr(f.manager))
 for offset,raw in source:gmatch("{%s*(0x%x+)%s*,%s*'(%x+)'%s*}")do f:put(f.exe+tonumber(offset),unhex(raw))end
 f:zero(f.graph,0x60);f:put(f.graph+4,u32(31));f:put(f.graph+8,u32(0x100));f:put(f.graph+0x14,u32(54))
 local lt=f.graph+0x100;f:put(lt,u32(31));f:zero(lt+4,31*4)
 local function layer(number,count,relative,states)
  local def=lt+relative;f:put(lt+4+(number-1)*4,u32(relative));f:put(def,u32(0)..u32(0)..u32(count))
  local stride=number==4 and 0x600 or 0x200
  for i=0,count-1 do f:put(def+12+i*4,u32(12+count*4+i*stride))end
  for index,ids in pairs(states)do
   local state=def+12+count*4+index*stride
   f:zero(state,0xa8);f:put(state+8,u32(2));f:put(state+0xc,u32(#ids));f:put(state+0x10,u32(0xa8))
   f:put(state+0x6c,u32(number==24 and 35 or 45))
   local values={};for _,id in ipairs(ids)do values[#values+1]=le(id)end;f:put(state+0xa8,table.concat(values))
   f.state_clips[number..':'..index]=state+0xa8;f.states[number..':'..index]=state
   if number==4 then f:put(state,unhex(MAINPAYLOAD[index]))end
  end
 end
 layer(4,78,0x10000,{[59]=MAINIDS,[67]={}})
 f:put(lt+0x10000,unhex('2c010000430000004e000000'))
 layer(24,10,0x1000,{[1]={IDS[1],IDS[2]},[6]={IDS[1],IDS[3]}})
 layer(25,4,0x4000,{[1]={IDS[4],IDS[5],IDS[6],IDS[7]}})
 local function map(at,array,stride,next_offset,keys)
  f:zero(at,0x28);f:put(at,u32(64));f:put(at+8,ptr(array));f:put(at+0x18,u32(#keys));f:put(at+0x1c,u32(32))
  for i=0,63 do f:zero(array+i*stride,stride);f:put(array+i*stride+next_offset,u32(4294967294))end
  local occupied,locations={},{};local extra=32
  for _,id in ipairs(keys)do
   local bucket=tonumber(id:sub(1,8),16)%32;local index=bucket
   if occupied[index]then
    while occupied[index].next do index=occupied[index].next end
    occupied[index].next=extra;f:put(array+index*stride+next_offset,u32(extra));index=extra;extra=extra+1
   end
   assert(index<64);occupied[index]={};local row=array+index*stride
   f:put(row,le(id));f:put(row+next_offset,u32(2147483647));locations[id]=row
  end
  return locations
 end
 local classes=map(f.manager+0x2e8,f.class_array,0xd0,0xc8,{'931e336d7646cc26'})
 f.class=classes['931e336d7646cc26'];f:put(f.class+0x10,ptr(f.slot_array))
 f.rows=map(f.class+0x20,f.clip_array,24,0x10,IDS)
 for i,id in ipairs(IDS)do
  local slot=f.slot_array+(i-1)*0xa0;local clip=0xc00000+i*0x1000
  f:put(f.rows[id]+8,u32(i-1));f:zero(slot,0xa0);f:put(slot,ptr(clip));f:zero(clip,0x40);f:put(clip+8,unhex('0000c03f'))
  f.slots[id]=slot
 end
 f.state={identity='fixture weapon',player_identity='fixture player',base=1,context=2,camera=3,controller=4,record=5,
  world=6,avatar_owner=7,avatar_index=0,avatar=8,body=f.c.unit,viewmodel=9,weapon_unit=10,
  flags=string.rep('\0',24),controller_bytes='fixture flags',safe=true,camera_kind=4,controller_active=false,shoulder_aim=false,aiming=false}
 local backend={}
 function backend:_read(at,n)return f:read(at,n)end
 function backend:_u32(at)local s=self:_read(at,4);local a,b,c,d=s:byte(1,4);return a+b*256+c*65536+d*16777216 end
 function backend:_u8(at)return self:_read(at,1):byte()end
 function backend:_alignment_executable()return f.exe end
 function backend:_alignment_context(s)assert(s.viewmodel==f.c.unit);f.contexts=f.contexts+1;return f.c end
 function backend:snapshot()local s={};for k,v in pairs(f.state)do s[k]=v end;return s end
 function backend.foreign_camera()return f.foreign or false end
 f.backend=backend
 function backend:_invalidate_frame_checks()error('Resource proof must not invalidate a frame')end
 function f:run(choice,return_proof)
  if return_proof==false then
   local report,why=Resources.inspect(self.backend,choice);assert(report,why);self.output=report;return report
  end
  local proof,why=Resources.prove(self.backend,choice);assert(proof,why);return proof
 end
 return f
end
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function refused(f,choice,fragment)
 local ok,why=pcall(f.run,f,choice);assert(not ok and tostring(why):find(fragment,1,true),tostring(why))
end
test('variant1 selects exactly 27 references with legacy family with fresh validation',function()
 local f=fixture();local p=f:run(1);assert(p.result.ready_layer24_state==1 and p.result.hip_layer24_state==0)
 assert(p.result.all_direct_resident and p.result.unique_clips==26 and p.result.selected_references==27 and p:validate())
 local found={};for _,v in ipairs(p.result.clips)do found[v.id]=true end
 assert(found[IDS[2]]and not found[IDS[3]])
end)
test('variant6 selects exactly 27 references with alternate family with fresh validation',function()
 local f=fixture();local p=f:run(6);assert(p.result.ready_layer24_state==6 and p.result.hip_layer24_state==5)
 assert(p.result.all_direct_resident and p.result.unique_clips==26 and p.result.selected_references==27 and p:validate())
 local found={};for _,v in ipairs(p.result.clips)do found[v.id]=true end
 assert(found[IDS[3]]and not found[IDS[2]])
 for _,v in ipairs(p.result.selections)do assert(v.state==(v.layer==4 and 59 or v.layer==24 and 6 or 1))end
end)
test('variant must be explicitly numeric1or6 before any protected read',function()
 local f=fixture();refused(f,nil,'explicitly1or6');assert(f.reads==0 and f.contexts==0)
 for _,v in ipairs({0,5,7,'6',false,math.huge,0/0})do refused(f,v,'explicitly1or6');assert(f.reads==0)end
end)
test('wrong clip family is rejected before residency can certify it',function()
 local f=fixture();f:put(f.state_clips['24:6']+8,le(IDS[2]));refused(f,6,'clip family changed')
end)
test('missing alternate direct resource cannot produce a private proof',function()
 local f=fixture();f:put(f.rows[IDS[3]]+0x10,u32(4294967294));refused(f,6,'Required native ready-pose clips are not resident')
end)
test('unresolved resource slot cannot produce a private proof',function()
 local f=fixture();f:put(f.slots[IDS[3]],ptr(0));refused(f,6,'Required native ready-pose clips are not resident')
end)
test('standalone diagnostic reports missing residency without loading resources',function()
 local f=fixture();f:put(f.slots[IDS[3]],ptr(0));f:run(6,false)
 assert(f.output.ready_layer24_state==6 and f.output.all_direct_resident==false)
end)
test('authored graph supports proved four-byte alignment',function()
 local f=fixture(4);local p=f:run(6);assert(p:validate())
end)
test('fresh validation catches resource slot replacement',function()
 local f=fixture();local p=f:run(6);f:put(f.slots[IDS[3]],ptr(0))
 local ok,why=pcall(p.validate);assert(not ok and tostring(why):find('Resident proof changed',1,true))
end)
test('fresh validation catches code pin replacement',function()
 local f=fixture();local p=f:run(6);f:put(f.exe+0x28d460,'\0')
 local ok,why=pcall(p.validate);assert(not ok and tostring(why):find('Resident proof changed: executable pin',1,true))
end)
test('fresh validation catches native World replacement',function()
 local f=fixture();local p=f:run(6);f:put(f.object+0x18,ptr(f.world+8))
 local ok,why=pcall(p.validate);assert(not ok and tostring(why):find('body native World',1,true))
end)
test('fresh validation catches ResourceManager replacement',function()
 local f=fixture();local p=f:run(6);f:put(f.instance+0x20,ptr(f.manager+8))
 local ok,why=pcall(p.validate);assert(not ok and tostring(why):find('resource manager',1,true))
end)
test('body generation replacement invalidates proof',function()
 local f=fixture();local p=f:run(6);f:put(f.c.generations+7,string.char(4))
 local ok,why=pcall(p.validate);assert(not ok and tostring(why):find('generation retired',1,true))
end)
test('bounded map chain cycle is rejected without a resource resolve',function()
 local f=fixture();local row=f.rows[IDS[3]];local idx=(row-f.clip_array)/24
 f:put(row,string.rep('\0',8));f:put(row+0x10,u32(idx));refused(f,6,'chain exceeds owned map')
end)
test('owner and native camera changes cannot validate an old proof',function()
 local f=fixture();local p=f:run(6);f.state.camera_kind=6
 local ok,why=pcall(p.validate);assert(not ok and tostring(why):find('player, weapon or camera changed',1,true))
end)
test('foreign camera cannot construct or validate a proof',function()
 local f=fixture();f.foreign=true;refused(f,6,'foreign camera active')
 f=fixture();local p=f:run(6);f.foreign=true
 local ok,why=pcall(p.validate);assert(not ok and tostring(why):find('foreign camera active',1,true))
end)
test('main selection preserves21 references including duplicate clip without extra hip dependencies',function()
 local f=fixture();local p=f:run(6);local n,counts=0,{}
 assert(p.result.ready_layer4_state==59 and p.result.hip_layer4_state==67)
 for _,r in ipairs(p.result.selections)do if r.layer==4 then n=n+1;counts[r.id]=(counts[r.id]or 0)+1 end end
 assert(n==21 and counts[MAINIDS[1]]==2 and p.result.unique_clips==26)
 assert(p.result.protected_reads<8192)
end)
test('missing main direct resident entry is reported with its exact clip key',function()
 local f=fixture();f:put(f.rows[MAINIDS[4]]+0x10,u32(4294967294));f:run(6,false)
 assert(f.output.selected_references==27 and f.output.unique_clips==26 and not f.output.all_direct_resident)
 local found=false;for _,r in ipairs(f.output.clips)do if r.id==MAINIDS[4]then found=true;assert(not r.direct_entry and not r.resident)end end
 assert(found)
end)
test('missing main direct entry refuses a private proof',function()
 local f=fixture();f:put(f.rows[MAINIDS[4]]+0x10,u32(4294967294))
 refused(f,6,'Required native ready-pose clips are not resident')
end)
test('main unresolved resource pointer refuses a private proof',function()
 local f=fixture();f:put(f.slots[MAINIDS[4]],ptr(0));refused(f,6,'Required native ready-pose clips are not resident')
end)
test('captured main target header must match exactly',function()
 local f=fixture();f:put(f.states['4:59']+0x7c,u32(0));refused(f,6,'main target header changed')
end)
test('main restore state remains exact type1 with no clip collection',function()
 local f=fixture();f:put(f.states['4:67']+8,u32(2));refused(f,6,'restore is not captured type1')
end)
test('main restore opaque header change fails before residency qualification',function()
 local f=fixture();f:put(f.states['4:67']+0x7c,u32(0));refused(f,6,'main restore header changed')
end)
test('main expression program drift fails qualification',function()
 local f=fixture();f:put(f.states['4:59']+0x2ec,u32(0));refused(f,6,'main program changed')
end)
test('main output index drift fails qualification',function()
 local f=fixture();f:put(f.states['4:59']+0x4f4,u32(0));refused(f,6,'main output entries changed')
end)
test('main clip ID swap fails qualification even if replacement is resident',function()
 local f=fixture();f:put(f.state_clips['4:59']+3*8,le(MAINIDS[5]));refused(f,6,'clip family changed')
end)
test('fresh validation catches main state header replacement',function()
 local f=fixture();local p=f:run(6);f:put(f.states['4:59']+0x7c,u32(0))
 local ok,why=pcall(p.validate);assert(not ok and tostring(why):find('Resident proof changed: target state header',1,true))
end)
test('fresh validation catches main program replacement',function()
 local f=fixture();local p=f:run(6);f:put(f.states['4:59']+0x2ec,u32(0))
 local ok,why=pcall(p.validate);assert(not ok and tostring(why):find('Resident proof changed: main program 59',1,true))
end)
test('fresh validation catches main resource key replacement',function()
 local f=fixture();local p=f:run(6);f:put(f.rows[MAINIDS[4]],le(MAINIDS[5]))
 local ok,why=pcall(p.validate)
 assert(not ok and tostring(why):find('Resident proof changed: clip ',1,true)and tostring(why):find(' map row',1,true))
end)
test('fresh validation catches selected main resource header replacement',function()
 local f=fixture();local p=f:run(6);local at=f.slots[MAINIDS[4]]
 local raw=f:read(at,8);local a,b,c,d=raw:byte(1,4);local clip=a+b*256+c*65536+d*16777216
 f:put(clip+8,u32(0))
 local ok,why=pcall(p.validate);assert(not ok and tostring(why):find('Resident proof changed: resolved clip header',1,true))
end)
print(passed..' main ready residency proof cases passed')

end

do
local Reader=dofile(ROOT..'/src/first_person/ready_pose_timing.lua')
local passed=0
local function fixture(group,flags)
    local mem={};local f={reads=0,snapshots=0,invalidations=0}
    function f:put(at,raw)for i=1,#raw do mem[at+i-1]=raw:byte(i)end end
    local function u32(n)local t={};for i=1,4 do t[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(t)end
    local function ptr(n)return u32(n%4294967296)..u32(math.floor(n/4294967296))end
    local function unhex(s)return(s:gsub('..',function(v)return string.char(tonumber(v,16))end))end
    f.u32,f.ptr=u32,ptr
    f.exe,f.object,f.instance,f.graph,f.world,f.manager=0x140000000,0x100000,0x200000,0x300000,0x400000,0x500000
    f.group90,f.groupA8,f.handles,f.records=0x600000,0x610000,0x700000,0x800000
    f.c={exe=f.exe,unit=123,index=7,generation=3,generations=0x900000,units=0xa00000,object=f.object}
    for _,pin in ipairs(Reader.pins)do f:put(f.exe+pin.rva,unhex(pin.hex))end
    local vt=0x110000;f:put(f.object,ptr(vt));f:put(vt+0x1b0,ptr(f.exe+0x28d460));f:put(vt+0x1b8,ptr(f.exe+0x28d470))
    f:put(f.object+8,u32(123));f:put(f.object+0x70,u32(107));f:put(f.object+0x358,unhex('97fa4d294d331c4d'))
    f:put(f.object+0x178,ptr(f.instance));f:put(f.instance+0x28,ptr(f.graph));f:put(f.graph+4,u32(31));f:put(f.graph+0x14,u32(54))
    f:put(f.object+0x18,ptr(f.world));f:put(f.world+0x230050,ptr(f.manager))
    f:put(f.c.generations+7,string.char(3));f:put(f.c.units+7*8,ptr(f.object))
    function f:vector(offset,array,values)
        self:put(self.manager+offset,u32(#values)..u32(#values)..ptr(#values>0 and array or 0))
        for i,v in ipairs(values)do self:put(array+(i-1)*8,ptr(v))end
    end
    f:vector(0x90,f.group90,group=='A8'and{}or{f.instance})
    f:vector(0xa8,f.groupA8,group=='A8'and{f.instance}or{})
    flags=flags or{}
    f:put(f.manager+0xf0,u32(#flags)..u32(#flags)..ptr(#flags>0 and f.handles or 0))
    f:put(f.manager+0x170,ptr(#flags>0 and f.records or 0))
    for i,v in ipairs(flags)do f:put(f.records+(i-1)*0x30+0x28,string.char(v))end
    f.state={identity='weapon-instance',player_identity='player-generation',base=1,context=2,camera=3,record=4,
        world=99,controller=5,controller_active=false,avatar_owner=6,avatar_index=0,avatar=7,
        body=123,viewmodel=321,weapon_unit=456,camera_kind=4,safe=true,shoulder_aim=false,reloading=false}
    local b={frame_active=true,frame_epoch=11}
    function b:_read(at,n)
        assert(type(n)=='number'and n>=1 and n<=1024,'Timing read exceeds backend cap')
        f.reads=f.reads+1;if f.on_read then f:on_read(at,n)end
        local out={};for i=0,n-1 do out[#out+1]=string.char(mem[at+i]or 0)end;return table.concat(out)
    end
    function b:_u8(at)return self:_read(at,1):byte(1)end
    function b:_u32(at)local a,c,d,e=self:_read(at,4):byte(1,4);return a+c*256+d*65536+e*16777216 end
    function b:_invalidate_frame_checks()
        f.invalidations=f.invalidations+1
        if self.frame_active then self.frame_epoch=self.frame_epoch+1 end
    end
    function b:snapshot()
        f.snapshots=f.snapshots+1;if f.on_snapshot then f:on_snapshot(f.snapshots)end
        local s={};for k,v in pairs(f.state)do s[k]=v end;return s
    end
    function b:_alignment_context(s)assert(s.viewmodel==f.state.body);return f.c end
    function b.foreign_camera()return f.foreign or false end
    f.b=b;f.reader=Reader.new(b)
    function f:sample()return self.reader:sample({phase='fird_update_after_probe',epoch=11,tick=7,elapsed=.1})end
    return f
end
local function good(f)
    local r,e=f:sample();assert(r,e);assert(r.write_authorized==false)
    assert(f.invalidations==0,'Observer must not invalidate/mutate backend frame checks')
    passed=passed+1;return r
end
local function bad(f,expected)
    local r,e=f:sample();assert(r==nil and type(e)=='string'and e:find(expected,1,true),tostring(e));passed=passed+1
end
local f=fixture();assert(f.reads==0,'Constructor must not read/execute the game');local r=good(f)
assert(r.observed_idle and r.pending_batches==0 and r.body_group=='group90'and r.phase=='fird_update_after_probe')
f=fixture('A8',{0,1});r=good(f);assert(not r.observed_idle and r.pending_batches==2 and r.incomplete_after==1 and r.body_group=='groupA8')
f=fixture('90',{1,1});r=good(f);assert(not r.observed_idle and r.completed_after==2,'Completed but undrained batches remain pending')
f=fixture();f:vector(0x90,f.group90,{f.instance+16});bad(f,'not uniquely owned')
f=fixture();f:vector(0xa8,f.groupA8,{f.instance});bad(f,'not uniquely owned')
f=fixture();f:put(f.manager+0x90,f.u32(16385));bad(f,'vector bounds invalid')
f=fixture();f:put(f.manager+0x98,f.ptr(9));bad(f,'pointer invalid')
f=fixture('A8',{0});f:put(f.manager+0xf4,f.u32(0));bad(f,'pending batch bounds invalid')
f=fixture('A8',{0});f:put(f.manager+0x170,f.ptr(0));bad(f,'batch records absent')
f=fixture('A8',{2});bad(f,'not Boolean')
f=fixture('A8',{0});local reads=0
function f:on_read(at)if at==self.records+0x28 then reads=reads+1;if reads==2 then self:put(at,string.char(1))end end end
r=good(f);assert(not r.completion_stable and r.completed_before==0 and r.completed_after==1 and not r.observed_idle)
f=fixture();function f:on_snapshot(n)if n==2 then self:put(self.c.generations+7,string.char(4))end end;bad(f,'generation retired')
f=fixture();function f:on_snapshot(n)if n==2 then self.state.identity='new weapon'end end;bad(f,'player/weapon/camera changed')
f=fixture();function f:on_snapshot(n)if n==2 then self:put(self.object+0x178,self.ptr(self.instance+16))end end;bad(f,'body graph changed')
f=fixture();local reads=0
function f:on_read(at)if at==self.manager+0xf0 then reads=reads+1;if reads==2 then self:put(at,self.u32(1))end end end
bad(f,'pending batch owner/count changed')
f=fixture();local reads=0
function f:on_read(at)if at==self.group90 then reads=reads+1;if reads==2 then self:put(at,self.ptr(self.instance+16))end end end
bad(f,'manager membership changed')
f=fixture();f.foreign=true;bad(f,'foreign camera active')
f=fixture();f.b.frame_active=false;bad(f,'requires existing Update frame')
f=fixture();function f:on_snapshot(n)if n==2 then self.b.frame_epoch=12 end end;bad(f,'Update frame retired')
f=fixture();f:put(f.exe+Reader.pins[1].rva,'\0');bad(f,'code contract changed')
f=fixture();f.state.camera_kind=6;bad(f,'normal camera4')
f=fixture();f.state.world=0xdead;good(f) -- ECS pointer must not be mistaken for native World.
f=fixture();f.graph=f.graph+4;f:put(f.instance+0x28,f.ptr(f.graph))
f:put(f.graph+4,f.u32(31));f:put(f.graph+0x14,f.u32(54));good(f) -- Authored graph can be four-byte aligned.
print('Fird quiescence reader: '..passed..' cases passed')

end
