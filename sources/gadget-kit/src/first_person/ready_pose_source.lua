-- Native ready-pose adapter. The injected gate owns qualified Update authority.
-- The existing engine state API animates the complete third-person rig; no
-- bone, attachment, camera, gameplay-input or sensitivity override is made here.
local Compat=mod.require('src/first_person/compat51.lua')
local Resources=mod.require('src/first_person/ready_pose_resources.lua')
local Contract=mod.require('src/first_person/ready_pose_contract.lua')
local M={}
local COUNTS={[4]=78,[24]=10,[25]=4}
-- Current game consumer A74821 reads flags+8, shifts38 and masks1: bit102,
-- Lua byte13 bit6. A firing action is qualified only with observed main60.
local FIRING_CONSUMER='4a8b841090e8530048c1e82624014883c408c3'
local function u32(s,o)local a,b,c,d=s:byte(o+1,o+4);assert(d);return a+b*256+c*65536+d*16777216 end
local function unhex(s)return(s:gsub('..',function(c)return string.char(tonumber(c,16))end))end
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
MAIN.pins[#MAIN.pins+1]={name='entry_behavior_callbacks',rva=0x55cfd9,hex='498b4628488bfb8b483085c97404488d3c08837e70000f8657010000488bce8bd3e831b3ffff4d8b66184533ff4c8965c84c8975d08b0c908b548f044803d7488955c08b0a85c9741a83f90175094c8d3d42520900eb13f20f1045880f10742478eb104c8d3d2d4f0900f20f1045d00f1075c0488b442460498b4e30468b2c28418bd5e8df5a01004c8bc04885c0743b8b88980300008d410141898098030000488d511d488b44246848c1e2054e893c02420f11740208f2420f11440218488b5424604d8b6618448b2c104d8b4630488bcee880b2ffff8bcb4533ff4c8965c84c8975d08b0c888b548f044803d7488955c08b0a85c9741983f90175094c8d3d335f0900eb12f20f1045a80f107598eb104c8d3d0f5f0900f20f1045d00f1075c0418bd5498bc8e83b5a01004885c0742d8b88a00400008bd148c1e205ffc18988a00400004c89bc02a80400000f11b402b0040000f20f118402c00400004c8b6c2468ffc33b5e700f82aefeffff'}
MAIN.pins[#MAIN.pins+1]={name='entry_parameter_precedence',rva=0x55d22e,hex='4439be900000000f86720100008b8dd80900008d5901488d1449899de0090000488995d00900006666660f1f840000000000458b9eb001000040b701443bdb765390b8ffffffff4403d84084ff743e498b86b80100004f8d0c5b33d2468b04c84585c074234e8b4cc808488bcee8e0b0ffff428b04f8413904d17409ffc2413bd072e7eb034032ff443bdb77b5488b95d0090000488bce4e8d2cfd00000000e8aeb0ffff498b8eb80100004c8be0448b04d1488d1cd18b54d104418d48013bca762d83fa0872168bcab8ffffffff48d1e94803ca483bc876098bc8eb05b9080000008bd1488bcbe876d30000448b034b8b042c488b4b08418bd0488904d1ff034084ff745d4d8b4e30488bcee841b0ffff428b14284c6bc258e834b0ffff498b8960020000428b4428044189440838498b8160020000486bca58c744014000000000498b81600200008b8dd8090000f3450f114c0044498b816002000041894c00488b9de009000041ffc7488b95d0090000443bbe900000000f82b3feffff'}
MAIN.pins[#MAIN.pins+1]={name='exit_events_parameters',rva=0x55bf0e,hex='438b543e143b56407377488bcee8d0c3ffff8bca4c8d044942837c8008027555428b448004418b9dc00000008985b0080000498b45008d53108b4808898db4080000498d8dc0000000e8f4faafff498b8dc8000000488b85b0080000c7041908000000c7441904b291b6154889441908438b543e14ffc24389543e143b5640728933c9448be1398e900000000f866c010000448bb5b8080000418d7e0189bdb0080000458b8db0010000b301443bcf765f9041ffc984db0f842c010000498b85b80100004f8d14498bd1468b04d04585c074304e8b54d008458bdc0f1f8000000000488bcee888c3ffff8bca428b04d8413904ca7409ffc2413bd072e5eb0232db33c9443bcf77aa84db0f84d90000000f57c0448bf9458bd64585f674784d8bb5b80100000f1f4000660f1f84000000000041ffca8bd14b8d0452458b0cc64585c9742b4d8b5cc608418bdc660f1f440000488bce448bc2e815c3ffff8b0cd843390cc37410ffc2413bd172e533c94585d275beeb134b8d0452458bfa498b4cc608f3420f1044c104448bb5b80800008bbdb00800004d8b4d30488bcee8d0c2ffff418bcc8b14c8498b81600200004c6bc258486bca58f3410f11440038498b81600200004533d24489540140498b816002000042c7440044cdcc4c3d498b816002000046897c004841ffc4b900000000443ba6900000000f82a5feffff488b85c008000033d2488d0c40498b85b8010000488d0cc8e817d20000'}
MAIN.pins[#MAIN.pins+1]={name='type1_pose_controls',rva=0x5f2299,hex='488b7908488bd9488b41104c8b31488d8d100100004889542420440f29bc24c0020000440f28fb4c8b6808488b87800000004983c510458b4e0c498bd548897da0468b0488488b87880000004c8bc84889442460e8dedcffff488b531033f6418b4e0848c1e1060f104830488b8298000000488975300f118dc0000000f20f104401308b4401388945c0488b4228418b5604f20f1145b80f57c0f30f7f453883faff750df30f7f4424704c8b642470eb2339701c750df30f7f4424704c8b642470eb118b48204803c88b5491044c8d61044c03e2'}
MAIN.pins[#MAIN.pins+1]={name='type1_feedback_guard',rva=0x5f301f,hex='488b194d8bd0488bf9807b18000f84200100008b431083f8ff0f8314010000'}
MAIN.pins[#MAIN.pins+1]={name='type1_axis25',rva=0x5f293c,hex='41807e2500440f28e6f3470f'}
MAIN.pins[#MAIN.pins+1]={name='type1_axis26',rva=0x5f29bc,hex='41807e2600750b41807e27000f84af020000f30f'}
MAIN.pins[#MAIN.pins+1]={name='type1_feedback_multiplier',rva=0x5f2c7d,hex='f3450f59beb400000041'}
MAIN.pins[#MAIN.pins+1]={name='blend_flag_copy',rva=0x56d8a9,hex='8b85400c000089442458488b85480c0000f30f114424540f2805f9091e01488985e00200008b85500c0000898de802000048898d5005000048898d4805000048898d5805000048898d60050000488d8d80050000898540050000'}
local EXPECTED=unhex('97fa4d294d331c4d')
local ACTOR={'base','world','avatar_owner','avatar_index','avatar','body','avatar_descriptor'}
local BODY={'unit','object','generation','instance','graph','resource'}
local function actor(s)
 if type(s)~='table'or type(s.avatar_descriptor)~='string'or #s.avatar_descriptor~=20 then return false end
 for _,key in ipairs(ACTOR)do if key~='avatar_descriptor'and type(s[key])~='number'then return false end end
 return true
end
local function same(a,b,keys)for _,key in ipairs(keys)do if a[key]~=b[key]then return false end end;return true end
-- This pure ownership classifier is also used by the mocked lifecycle tests.
-- Weapon/camera/request identity is eligibility, never body-graph ownership.
function M.owner(initial,owned,read_body)
 assert(actor(initial)and type(read_body)=='function')
 for _,key in ipairs(BODY)do assert(owned[key]~=nil,'Incomplete body identity: '..key)end
 local actor_copy,body_copy={},{}
 for _,key in ipairs(ACTOR)do actor_copy[key]=initial[key]end
 for _,key in ipairs(BODY)do body_copy[key]=owned[key]end
 initial,owned=actor_copy,body_copy
 local parts={};for _,key in ipairs(ACTOR)do parts[#parts+1]=tostring(initial[key])end
 for _,key in ipairs(BODY)do parts[#parts+1]=tostring(owned[key])end
 local token=table.concat(parts,':')
 return{observe=function(_,player,full)
  if not actor(player)then return nil,'Player identity temporarily unavailable'end
  if not same(player,initial,ACTOR)then return{ownerToken=token,retired=true,reason='avatar_owner_retired'}end
  local current,why=read_body(player)
  if not current then return nil,why or'Body identity temporarily unavailable'end
  if current.retired==true then return{ownerToken=token,retired=true,reason='body_generation_retired'}end
  for _,key in ipairs(BODY)do if current[key]==nil then return nil,'Body identity incomplete: '..key end end
  if not same(current,owned,BODY)then return{ownerToken=token,retired=true,reason='body_graph_retired'}end
  if full and(not actor(full)or not same(full,player,ACTOR))then return nil,'Player changed during weapon observation'end
  return{ownerToken=token,retired=false,available=full~=nil,player=player,full=full}
 end}
end
local function flag(s,byte,bit)return math.floor(s.flags:byte(byte)/2^bit)%2==1 end
local function weapon_token(s)
 if type(s.weapon)~='number'or s.weapon%1~=0 or s.weapon<=0 or s.weapon>=0xffffffff
  or type(s.weapon_unit)~='number'or s.weapon_unit%1~=0 or s.weapon_unit<=0 or s.weapon_unit>=0xffffffff
  or type(s.weapon_descriptor)~='string'or #s.weapon_descriptor~=20 then return nil end
 local descriptor=(s.weapon_descriptor:gsub('.',function(c)return string.format('%02x',c:byte())end))
 return string.format('%.0f:%.0f:',s.weapon,s.weapon_unit)..descriptor
end
function M.guard(s,native,on_foot,foreign)
 local flags=type(s)=='table'and type(s.flags)=='string'and #s.flags==24
 local qualified=flags and type(native)=='table'and native.resource_match==true and native.layer_count==31 and on_foot==true
 local firing=flags and flag(s,13,6)or false
 if not qualified then return{safeNormal4=false,actualAim=true,reload=false,sprint=false,firing=firing,foreign=foreign==true,ads=true}end
 local aim=s.shoulder_aim==true or s.aiming==true or flag(s,11,2)or flag(s,16,5)or flag(s,7,0)
 local sprint=(native.l14==36 or native.l14==3 and on_foot==true)
  and(flag(s,10,2)or native.l3==71 or native.l14==3 and native.l3==68 and(native.l1==75 or native.l1==78))
 return{safeNormal4=s.safe==true and s.camera_kind==4 and not s.controller_active and not s.weapon_transition and foreign~=true,
  actualAim=aim,reload=s.reloading==true or flag(s,16,1),sprint=sprint==true,firing=firing,foreign=foreign==true,
  ads=s.controller_active==true or s.camera_kind~=4}
end
function M.new(b,before_native_call)
 local P,contract=Compat,Contract
 assert(type(before_native_call)=='function','Ready Update before_native_call gate required')
 local ffi=P.ffi;local self={calls=0,resources_checked=0,gate_refusals=0}
 local function block(at,n)
  assert(type(n)=='number'and n%1==0 and n>=1 and n<=0x4000,'Ready copied block exceeds bounds')
  local pieces={}
  for offset=0,n-1,1024 do
   local size=math.min(1024,n-offset);local raw=b:_read(at+offset,size)
   assert(type(raw)=='string'and #raw==size,'Ready copied block read incomplete')
   pieces[#pieces+1]=raw
  end
  return table.concat(pieces)
 end
 local initial=assert(b:snapshot());assert(initial.safe and initial.camera_kind==4 and not initial.controller_active)
 local c=b:_alignment_context({viewmodel=initial.body,avatar_owner=initial.avatar_owner,avatar_index=initial.avatar_index})
 local exe=b:_alignment_executable();assert(c.exe==exe)
 local function valid()
  assert(b:_u8(c.generations+c.index)==c.generation and b:_ptr(c.units+c.index*8)==c.object and b:_u32(c.object+8)==c.unit,'Ready body retired')
  assert(b:_u32(c.object+0x70)==107 and block(c.object+0x358,8)==EXPECTED,'Ready body resource changed')
 end
 valid();local instance=b:_ptr(c.object+0x178);local graph=b:_ptr(instance+0x28)
 local header=block(graph,0x60);assert(u32(header,4)==31 and u32(header,0x14)==54)
 local definitions_at=graph+u32(header,8)+4
 local definitions=block(definitions_at,31*4);local immutable={}
 for _,layer in ipairs({4,24,25})do
  local at=graph+u32(header,8)+u32(definitions,(layer-1)*4)
  local h=block(at,12);local n=u32(h,8)
  assert(n==COUNTS[layer]);immutable[#immutable+1]={at=at,raw=block(at,12+n*4)}
 end
 local owned={unit=c.unit,object=c.object,generation=c.generation,instance=instance,graph=graph,resource=EXPECTED}
 local owner=M.owner(initial,owned,function(player)
  local ok,current=pcall(function()
   -- The old registry generation/object can positively retire the lease even
   -- while a firearm snapshot is unavailable. A protected-read failure cannot.
   -- Requalify the current arrays before consulting the old UnitRef: cached
   -- generation storage alone cannot prove retirement after registry growth.
   local root_at=exe+b.profile.alignment.executable.unit_registry
   local registry=b:_ptr(root_at);local metadata=block(registry+0x88,32)
   local capacity=u32(metadata,16);assert(capacity>0 and capacity<=0x400000 and c.index<capacity)
   local units=u32(metadata,0)+u32(metadata,4)*4294967296
   local generations=u32(metadata,24)+u32(metadata,28)*4294967296
   assert(units>=65536 and units<2^47 and generations>=65536 and generations<2^47)
   local generation=b:_u8(generations+c.index)
   local raw=block(units+c.index*8,8);local object=u32(raw,0)+u32(raw,4)*4294967296
   assert(b:_ptr(root_at)==registry and block(registry+0x88,32)==metadata
    and b:_u8(generations+c.index)==generation and block(units+c.index*8,8)==raw,'Ready registry changed during observation')
   if generation~=owned.generation or object~=owned.object then return{retired=true}end
   local fresh=b:_alignment_context({viewmodel=player.body,avatar_owner=player.avatar_owner,avatar_index=player.avatar_index})
   if fresh.object~=owned.object or fresh.unit~=owned.unit or fresh.generation~=owned.generation then return{retired=true}end
   c=fresh
   local function nullable(at)local raw=block(at,8);return u32(raw,0)+u32(raw,4)*4294967296 end
   local current_instance=nullable(c.object+0x178)
   local current_graph=current_instance~=0 and b:_ptr(current_instance+0x28)or 0
   return{unit=c.unit,object=c.object,generation=c.generation,instance=current_instance,graph=current_graph,
    resource=block(c.object+0x358,8)}
  end)
  if not ok then return nil,tostring(current)end;return current
 end)
 local function layout()
  valid();assert(b:_ptr(c.object+0x178)==instance and b:_ptr(instance+0x28)==graph and block(graph,0x60)==header,'Ready graph retired')
  assert(block(definitions_at,#definitions)==definitions,'Ready layer definitions changed')
  for _,v in ipairs(immutable)do assert(block(v.at,#v.raw)==v.raw,'Ready state mapping changed')end
 end
 local function target(layer,index)
  local table_at=graph+u32(header,8)
  local def=table_at+b:_u32(table_at+4+(layer-1)*4)
  local n=b:_u32(def+8);assert(n==COUNTS[layer]and index>=0 and index<n)
  local at=def+b:_u32(def+12+index*4);return at,block(at,0xa8),n
 end
 local captured=assert(b.actions:sample(initial,{4,24,25}))
 assert(captured.resource_match and captured.layer_count==31 and #captured.unknown_layers==0
  and captured.instance==instance and captured.graph==graph and captured.body_object==c.object,
  'Ready initial layer observation unqualified')
 -- Native firing/aim release can leave L24 in its held member while main67
 -- and L25=3 are already released. Borrow that exact member without changing
 -- the actual captured state used by the active-pointer bracket below.
 local captured24=captured.states[24]
 local hip24=captured24==1 and 0 or captured24==6 and 5 or captured24
 assert(captured.states[4]==67 and(hip24==0 or hip24==5)and captured.states[25]==3,'Ready constructor requires a captured released hip family')
 local target24=hip24+1
 self.ready_variant={hip24=hip24,target24=target24}
 self.main_pair={hip4=67,target4=59}
 local selected_active=b:_ptr(instance+0x50)
 for _,layer in ipairs({4,24,25})do
  local at=target(layer,captured.states[layer])
  assert(b:_ptr(selected_active+(layer-1)*8)==at,'Ready initial hip family changed during capture')
 end
 -- The L24 hip and held poses use the same two clips; restoring hip cannot
 -- introduce an additional resource dependency after the complete27-reference preflight.
 local h0,b0=target(24,hip24);local h1,b1=target(24,target24)
 assert(u32(b0,8)==2 and u32(b1,8)==2 and u32(b0,0xc)==2 and u32(b1,0xc)==2)
 local hip_clips=block(h0+u32(b0,0x10),16)
 assert(hip_clips==block(h1+u32(b1,0x10),16),'Hip and ready clip dependencies differ')
 immutable[#immutable+1]={at=h0+u32(b0,0x10),raw=hip_clips}
 local target_headers={}
 for _,selection in ipairs({{4,67},{4,59},{24,hip24},{24,target24},{25,3},{25,1}})do
  local layer,index=selection[1],selection[2];local at,raw=target(layer,index)
  if layer==4 then
   local wanted=unhex(assert(MAIN.states[index]))
   assert(block(at,#wanted)==wanted,'Ready main-layer authored payload changed')
   immutable[#immutable+1]={at=at,raw=wanted}
  else
   if layer==25 and index==3 then assert(u32(raw,8)==1 and u32(raw,0xc)==0)
   else assert(u32(raw,8)==2 and u32(raw,0xc)==(layer==24 and 2 or 4))end
   for _,o in ipairs({0x40,0x70,0x88,0x90,0x98,0xa0})do assert(u32(raw,o)==0,'Ready state has unqualified authored actions')end
  end
  target_headers[#target_headers+1]={at=at,raw=raw}
 end
 -- Qualify the exact used authored type1 controls. Padding and the unused
 -- pointer-looking bytes in the184B behavior slots are deliberately excluded.
 local bank_extent=u32(header,0x2c);assert(bank_extent==0xbc4,'Ready behavior bank byte extent changed')
 local bank_offset=u32(header,0x30);assert(bank_offset>=0x34 and bank_offset<=0x1000000)
 local bank=graph+bank_offset;local bank_offsets=unhex(MAIN.bank_offsets)
 assert(block(bank,#bank_offsets)==bank_offsets,'Ready behavior bank mapping changed')
 immutable[#immutable+1]={at=bank,raw=bank_offsets}
 for index,controls in pairs(MAIN.behaviors)do
  local offset=u32(bank_offsets,4+index*4)
  assert(offset>=#bank_offsets and offset+0xb8<=bank_extent,'Ready behavior slot exceeds bank')
  for _,v in ipairs(controls)do
   local wanted=unhex(v.hex);local at=bank+offset+v.offset
   assert(block(at,#wanted)==wanted,'Ready type1 behavior consumed control changed')
   immutable[#immutable+1]={at=at,raw=wanted}
  end
 end
 local mask_count,mask_offset=u32(header,0x1c),u32(header,0x20)
 assert(mask_count==80 and mask_offset>=0x24 and mask_offset<=0x1000000,'Ready authored mask table changed')
 local mask_table=graph+mask_offset;local mask_offsets=block(mask_table,4+mask_count*4)
 assert(u32(mask_offsets,0)==mask_count,'Ready authored mask count changed')
 immutable[#immutable+1]={at=mask_table,raw=mask_offsets}
 for index,raw_hex in pairs(MAIN.masks)do
  local offset=u32(mask_offsets,4+index*4);local weights=unhex(raw_hex)
  assert(offset>=#mask_offsets and offset<=0x1000000 and #weights==90*4,'Ready authored mask offset changed')
  local wanted=string.char(90,0,0,0)..weights;local at=mask_table+offset
  assert(block(at,#wanted)==wanted,'Ready authored mask weights changed')
  immutable[#immutable+1]={at=at,raw=wanted}
 end
 local function firing_contract()
  local expected=unhex(FIRING_CONSUMER)
  assert(block(initial.base+0xa74851,#expected)==expected,'Ready firing flag consumer changed')
 end
 local function code()
  assert(b:_alignment_executable()==exe)
  firing_contract()
  local root=b:_ptr(initial.base+0x2ce14c8);local api=b:_ptr(root+0x18)
  assert(api==exe+tonumber(contract.table_rva,16)and b:_ptr(api+0x3d8)==exe+0x1f7da0,'Native animation API owner changed')
  for _,pin in ipairs(contract.pins)do
   local expected=unhex(pin.hex);assert(block(exe+pin.rva,#expected)==expected,'Ready animation setter contract changed: '..pin.name)
  end
  for _,pin in ipairs(MAIN.pins)do
   local wanted=unhex(pin.hex)
   assert(block(exe+pin.rva,#wanted)==wanted,'Ready main animation code changed: '..pin.name)
  end
 end
 code()
 local setter=ffi.cast('void (*)(uint32_t,const int32_t *)',exe+0x1f7da0)
 function self:snapshot()
  local player,why=b:player_snapshot();if not player then return nil,why end
  local s=b:snapshot()
  local observation,problem=owner:observe(player,s);if not observation then return nil,problem end
  if observation.retired then observation.safeNormal4=false;observation.layers={};return observation end
  if not observation.available then observation.safeNormal4=false;observation.layers={};return observation end
  layout()
  local a=assert(b.actions:sample(s,{4,24,25}));assert(a.resource_match and a.layer_count==31 and #a.unknown_layers==0)
  assert(a.instance==instance and a.graph==graph and a.body_object==c.object)
  local native=assert(b:action_state(s),'Ready action sample unavailable')
  assert(native.resource_match and native.layer_count==31 and #native.unknown_layers==0,
   'Ready action sample unqualified')
  local foreign_value
  if b.foreign_camera then foreign_value=b.foreign_camera()end
  local foreign=b.foreign_camera and foreign_value~=false or false
  local result=M.guard(s,native,b:on_foot(s,native),foreign)
  local active=b:_ptr(instance+0x50)
  local active_states=block(active,31*8)
  for _,layer in ipairs({4,24,25})do
   local index=a.states[layer]
   if index>=0 then
    local at=target(layer,index);local raw=active_states:sub((layer-1)*8+1,layer*8)
    assert(u32(raw,0)+u32(raw,4)*4294967296==at,'Ready layers changed during observation')
   end
  end
  result.ownerToken=observation.ownerToken;result.retired=false
  result.body_ref=c.unit;result.body_generation=c.generation
  result.layers={[4]=a.states[4],[24]=a.states[24],[25]=a.states[25]};result.snapshot=s
  result.active=active;result.active_states=active_states
  result.stable_weapon_token=weapon_token(s)
  result.weapon_token=result.stable_weapon_token
  if result.stable_weapon_token==nil then result.safeNormal4=false end
  result.weapon_transition=s.weapon_transition==true
  -- Historical layer-state inference may inhibit a call, but only observed
  -- native input/camera facts renew a retry budget. The qualified on-foot
  -- gait bit is a current native sprint observation.
  local gait_verified=result.safeNormal4==true and flag(s,10,2)
  local firing_verified=result.firing and a.states[4]==60
  if firing_verified then firing_contract()end
  result.firing_verified=firing_verified
  result.action_verified=result.safeNormal4==true and(result.actualAim or result.reload or gait_verified or firing_verified)
   or foreign_value==true or s.controller_active==true
   or type(s.camera_kind)=='number'and s.camera_kind~=4 or result.weapon_transition
  return result
 end
 local function eligible(s)
  return type(s)=='table'and s.safeNormal4 and not(s.actualAim or s.reload or s.sprint or s.firing or s.foreign or s.ads or s.weapon_transition)
   and type(s.snapshot)=='table'and not s.snapshot.aiming
 end
 local function cohort(s)
  return type(s.layers)=='table'and(s.layers[4]==67 or s.layers[4]==59)and(s.layers[24]==0 or s.layers[24]==1 or s.layers[24]==5 or s.layers[24]==6)
   and(s.layers[25]==3 or s.layers[25]==1)
 end
 local function unchanged(now,fresh,stage)
  assert(fresh.ownerToken==now.ownerToken and eligible(fresh)and cohort(fresh),'Ready owner/action changed '..stage)
  for _,layer in ipairs({4,24,25})do assert(fresh.layers[layer]==now.layers[layer],'Ready layers changed '..stage)end
  for _,key in ipairs({'identity','player_identity','base','context','camera','record','body','weapon_unit','flags','controller_bytes'})do
   assert(fresh.snapshot[key]==now.snapshot[key],'Ready player/input changed '..stage)
  end
  assert(fresh.active==now.active and b:_ptr(instance+0x50)==now.active,'Ready active array changed '..stage)
  assert(fresh.active_states==now.active_states,'Ready active layers changed '..stage)
  assert(fresh.stable_weapon_token==now.stable_weapon_token and fresh.weapon_transition==now.weapon_transition,
   'Ready weapon ownership changed '..stage)
 end
 local function definitions()
  layout();code()
  for _,v in ipairs(target_headers)do assert(block(v.at,#v.raw)==v.raw,'Ready target definition changed before native call')end
 end
 local function gate(expected,context,operation)
  local ok,allowed,why
  if b.frame_active~=true then ok,allowed,why=true,false,'Ready requires the existing owned normal Update frame'
  else ok,allowed,why=pcall(before_native_call,expected,context,operation)end
  if not ok or allowed~=true then
   self.gate_refusals=self.gate_refusals+1
   self.last_gate_reason=tostring(ok and(why or'Ready native-call gate refused')or allowed)
   -- No ownership is retired here. The caller must retain any prior or
   -- uncertain lease and retry qualified cleanup in a later normal Update.
   return false,self.last_gate_reason
  end
  self.last_gate_reason=nil;return true
 end
 function self:can_mutate(context,expected)
  local now=assert(self:snapshot())
  if not eligible(now)or not cohort(now)then return false,'Ready requires the captured hip/target cohort with native actions released'end
  if expected then unchanged(expected,now,'before Update preflight')end
  return gate(now,context,'preflight')
 end
 local function set(changes,expected,restoring,context)
  local now=assert(self:snapshot())
  assert(now.ownerToken==expected.ownerToken and eligible(now)and cohort(now),'Ready native action or unknown cohort now owns the pose')
  if not restoring then
   assert(now.layers[24]==hip24 or now.layers[24]==target24,'Ready captured animation family changed before apply')
  end
  for _,layer in ipairs({4,24,25})do assert(now.layers[layer]==expected.layers[layer],'Ready layers changed before call')end
  assert(now.stable_weapon_token==expected.stable_weapon_token and now.weapon_transition==expected.weapon_transition,
   'Ready weapon ownership changed before native call')
  layout();code()
  for _,v in pairs(target_headers)do assert(block(v.at,#v.raw)==v.raw,'Ready target definition changed')end
  local proof,proof_problem=Resources.prove(b,target24)
 assert(proof,proof_problem or'Ready resident-animation proof unavailable')
  assert(proof.result.all_direct_resident and proof.result.ready_layer4_state==59
   and proof.result.hip_layer4_state==67 and proof.result.ready_layer24_state==target24
   and type(proof.result.selections)=='table'and #proof.result.selections==27 and proof:validate());self.resources_checked=self.resources_checked+1
  local values=ffi.new('int32_t[33]');for i=0,31 do values[i]=-1 end;values[32]=25
  local changed=0
  for layer,index in pairs(changes)do
   assert(layer==4 or layer==24 or layer==25,'Ready attempted another layer')
   assert(index==(layer==4 and(restoring and 67 or 59)or layer==24 and(restoring and hip24 or target24)or(restoring and 3 or 1)),
    'Ready target is not the captured native state')
   assert(now.layers[layer]~=index,'Ready would restart an unchanged layer')
   if layer==4 then
    assert(now.layers[4]==(restoring and 59 or 67),'Ready L4 is no longer the captured source state')
   elseif layer==24 then
    assert(now.layers[24]==(restoring and target24 or hip24),'Ready L24 is no longer the captured source state')
   end
   local _,_,count=target(layer,index);assert(index>=0 and index<count)
   values[layer-1]=index;changed=changed+1
  end
  assert(changed>0 and changed<=3)
  -- Backend snapshots are fresh reads. Do not invalidate/mutate the caller's
  -- frame epoch; a private residency provider may have its own checked epoch.
  local final_before=assert(self:snapshot())
  unchanged(now,final_before,'during asset validation');definitions()
  local operation=restoring and'restore'or'apply'
  local allowed,reason=gate(final_before,context,operation)
  if not allowed then return false,reason end
  local gate_epoch=b.frame_epoch
  local after_gate=assert(self:snapshot())
  unchanged(final_before,after_gate,'after native-call gate');definitions()
  assert(b.frame_active==true and b.frame_epoch==gate_epoch,'Ready Update frame retired after native-call gate')
  local active=now.active;local before=block(active,31*8)
  assert(before==after_gate.active_states,'Ready active layers changed immediately before native call')
  -- Native ABI explicitly accepts a uint32 UnitRef. This is not a Lua SDK
  -- Unit method receiving a numeric handle; the pinned native resolver owns it.
  self.calls=self.calls+1;setter(c.unit,values)
  layout();assert(b:_ptr(instance+0x50)==active,'Ready active array changed during native call');local after=block(active,31*8)
  for layer=1,31 do
   if changes[layer]~=nil then
    local at=target(layer,changes[layer]);local raw=after:sub((layer-1)*8+1,layer*8)
    assert(u32(raw,0)+u32(raw,4)*4294967296==at,'Ready state was not acknowledged')
   else assert(before:sub((layer-1)*8+1,layer*8)==after:sub((layer-1)*8+1,layer*8),'Ready setter changed another layer')end
  end
  local final=assert(b:snapshot());assert(final.player_identity==now.snapshot.player_identity and final.identity==now.snapshot.identity and final.record==now.snapshot.record and final.camera_kind==now.snapshot.camera_kind and final.flags==now.snapshot.flags and final.controller_bytes==now.snapshot.controller_bytes,'Ready setter changed gameplay input ownership')
  return true
 end
 function self:apply(changes,expected,context)return set(changes,expected,false,context)end
 function self:restore(changes,expected,context)return set(changes,expected,true,context)end
 function self:describe()local s=assert(self:snapshot());return{ready=true,layers=s.layers,actualAim=s.actualAim,normal=s.safeNormal4,reload=s.reload,sprint=s.sprint,calls=self.calls,
  ready_variant={hip24=hip24,target24=target24},main_pair={hip4=67,target4=59}}end
 return self
end
return M
