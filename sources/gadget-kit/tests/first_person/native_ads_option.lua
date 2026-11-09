local M=dofile(NATIVE_ADS_TEST_ROOT..'/src/native_ads_option.lua')
local passed=0
local function test(name,fn)local ok,why=pcall(fn);assert(ok,name..': '..tostring(why));passed=passed+1 end
local function fixture()
 local f={on=true,active=true,foreign=false,writes=0};f.r={key='a',at=42,descriptor='a',value=0}
 local source={probe=function()local r={};for k,v in pairs(f.r)do r[k]=v end;return r end,
 read=function(_,r)if r.key~=f.r.key then return nil,'retired'end;return f.r.value end,
 write=function(_,r,before,value)assert(not f.foreign and r.key==f.r.key and f.r.value==before);f.r.value=value;f.writes=f.writes+1;if f.throw_after then error('uncertain')end end}
 f.controller={is_enabled=function()return f.active end,result=function()return {mode='pose_offset'}end}
 f.manager=M.new(source,function()return f.on end,function()return f.foreign end)
 function f:step()return self.manager:update(self.controller)end
 return f
end
test('native selector is leased while enabled and restored on disable',function()
 local f=fixture();assert(f:step());assert(f.r.value==1 and f.writes==1)
 for _=1,10 do assert(f:step())end;assert(f.writes==1)
 f.on=false;assert(f:step());assert(f.r.value==0 and f.writes==2 and f.manager:is_clean())
end)
test('existing native ADS preference stays unowned',function()
 local f=fixture();f.r.value=1;assert(f:step());assert(f.manager:is_clean());assert(f.manager:stop());assert(f.writes==0 and f.r.value==1)
end)
test('weapon retirement never restores into a replacement',function()
 local f=fixture();assert(f:step());f.r={key='b',at=43,descriptor='b',value=0};assert(f:step());assert(f.r.value==1 and f.writes==2)
 assert(f.manager:stop());assert(f.r.value==0 and f.writes==3)
end)
test('foreign cameras defer restoration and new writes',function()
 local f=fixture();assert(f:step());f.foreign=true;assert(f:step());assert(f.writes==1)
 assert(not f.manager:stop());f.foreign=false;assert(f.manager:stop());assert(f.r.value==0)
end)
test('uncertain write retains its original value for cleanup',function()
 local f=fixture();f.throw_after=true;assert(f:step());assert(not f.manager:is_clean()and f.r.value==1)
 f.throw_after=false;assert(f.manager:stop());assert(f.r.value==0)
end)
test('turning the camera off and shutdown restore independently',function()
 local f=fixture();assert(f:step());f.active=false;assert(f:step());assert(f.r.value==0 and f.manager:is_clean())
 f.active=true;assert(f:step());assert(f.manager:shutdown());assert(f.r.value==0)
end)

local function source_fixture(mode)
 local f={bytes={},pointers={},numbers={},mode=mode,reads=0,writes=0}
 local s={base=0x10000000,avatar_owner=0x20000000,weapon=123,player_identity='p',identity='i',weapon_descriptor=string.rep('D',20),safe=true,camera_kind=6}
 f.s=s;local b={};f.backend=b
 function b:snapshot()if f.strict_missing then return nil,'fixture nonlocal camera request'end;return s end
 function b:player_snapshot()if f.strict_missing then return nil,'fixture nonlocal camera request'end;return s end
 function b:pin_player_snapshot()
  f.pin_reads=(f.pin_reads or 0)+1
  if f.pin_missing then return nil,'fixture local body unavailable'end
  return s
 end
 function b:foreign_camera()return f.foreign==true end
 local player,settings,pool,selected,descriptors,descriptor,flags=0x30000000,0x40000000,0x50000000,0x60000000,0x70000000,0x71000000,0x72000000
 f.pointers[s.base+0x2ce1618]=player;f.pointers[s.avatar_owner+0x40]=settings;f.numbers[settings+0xf0]=mode
 f.pointers[s.base+0x2ce1ea0]=pool;f.pointers[pool+0x48]=descriptors;f.pointers[descriptors+8]=descriptor;f.bytes[descriptor]=s.weapon_descriptor;f.numbers[descriptor+8]=123;f.pointers[pool+0x50]=flags
 f.numbers[player+0x88]=1;f.pointers[player+0xe8]=selected;f.numbers[selected+8]=5;f.bytes[selected]=string.rep('P',20)
 for at,hex in pairs({[0xa5ced3]='488b0506502802488b4840f781f0000000fdffffff',[0xa5cfc5]='8bc8498b42500fb60448',[0xa5d083]='486bc138420fb68408ec020000'})do
  f.bytes[s.base+at]=(hex:gsub('%x%x',function(p)return string.char(tonumber(p,16))end))
 end
 function b:_ptr(at)return assert(f.pointers[at],tostring(at))end
 function b:_u32(at)return assert(f.numbers[at],tostring(at))end
 function b:_u8(at)return(f.bytes[at]or'\0'):byte()end
 function b:_read(at,n)local v=assert(f.bytes[at]);assert(#v==n);return v end
 function b:_map(at,id,limit)
  if at==pool+0x30 then assert(id==123);return 1 end
  assert(at==player+0xd0 and id==5 and limit==8);return 0
 end
 local writer={copy=function(_,at,bytes)assert(#bytes==1);f.bytes[at]=bytes;f.writes=f.writes+1;return true end}
 f.source=M.source(b,function()return writer end);f.settings=settings;f.flag=mode==0 or mode==2 and player+0x2ec or flags+2
 return f
end
test('source leases native global and per-weapon selectors for all remember modes',function()
 for mode=0,3 do local f=source_fixture(mode);local r=f.source:probe();assert(r.mode==mode and r.value==0)
  f.source:write(r,0,1);assert(f.source:read(r)==1 and f.writes==1)
  f.source:write(r,1,0);assert(f.source:read(r)==0 and f.writes==2)
 end
end)
test('source restores the previous selector when the game changes remember mode',function()
 local f=source_fixture(0);local old=f.source:probe();f.source:write(old,0,1);f.numbers[f.settings+0xf0]=1
 local new=f.source:probe();assert(new.at~=old.at);assert(f.source:read(old)==1);f.source:write(old,1,0);assert(f.writes==2)
end)
test('source rejects drift foreign views and changed descriptors before writing',function()
 local f=source_fixture(1);local r=f.source:probe();f.foreign=true;assert(not pcall(f.source.write,f.source,r,0,1));assert(f.writes==0)
 f.foreign=false;f.s.player_identity='different';assert(not pcall(f.source.write,f.source,r,0,1));assert(f.writes==0)
end)

test('pinned cleanup follows the same local body during vehicle cameras without relaxing the firearm probe',function()
 for mode=0,3 do
  local f=source_fixture(mode);local r=f.source:probe();f.source:write(r,0,1)
  f.backend.pin_first_person=true;f.strict_missing=true;f.s.safe=false;f.s.seated=true;f.s.camera_kind=9
  assert(f.source:read(r)==1);assert(not pcall(f.source.probe,f.source))
  f.source:write(r,1,0);assert(f.source:read(r)==0 and f.writes==2 and f.pin_reads>=3)
  f.strict_missing=false;assert(not pcall(f.source.probe,f.source))
 end
end)

test('pin cleanup requires explicit pin mode and cannot restore through missing or replaced body ownership',function()
 for _,pin in ipairs({false,1})do
  local f=source_fixture(0);local r=f.source:probe();f.backend.pin_first_person=pin;f.strict_missing=true
  assert(not pcall(f.source.read,f.source,r));assert(f.pin_reads==nil)
 end
 local f=source_fixture(1);local r=f.source:probe();f.source:write(r,0,1);f.backend.pin_first_person=true;f.strict_missing=true
 f.pin_missing=true;assert(not pcall(f.source.write,f.source,r,1,0));assert(f.writes==1)
 f.pin_missing=false;f.s.player_identity='replacement-body';local value,why=f.source:read(r)
 assert(value==nil and why=='retired');assert(not pcall(f.source.write,f.source,r,1,0));assert(f.writes==1)
end)

test('pinned manager keeps exact cleanup while local body is unreadable or a foreign camera owns the view',function()
 local f=source_fixture(0);f.backend.pin_first_person=true
 local controller={is_enabled=function()return true end,result=function()return{mode='pose_offset'}end}
 local manager=M.new(f.source,function()return true end,function()return f.foreign==true end)
 assert(manager:update(controller));assert(f.writes==1 and not manager:is_clean())
 f.strict_missing=true;f.s.safe=false;f.s.seated=true;f.s.camera_kind=9
 assert(manager:update(controller));assert(manager:result().phase=='waiting' and f.writes==1)
 f.foreign=true;assert(not manager:stop());assert(f.writes==1 and not manager:is_clean())
 f.foreign=false;f.pin_missing=true;assert(not manager:stop());assert(f.writes==1 and not manager:is_clean())
 f.pin_missing=false;assert(manager:stop());assert(f.writes==2 and manager:is_clean())
end)

print('Native ADS option fixtures: '..passed..' passed')
