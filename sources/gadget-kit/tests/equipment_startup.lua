local Native=dofile('src/equipment_backend.lua')
local ffi=require('ffi')
local game,profile,players,player,kits,state,manager=0x10000000,0x20000000,0x30000000,0x40000000,0x50000000,0x60000000,0x70000000
local bytes,pointers={},{}
local function put(at,s)for i=1,#s do bytes[at+i-1]=s:sub(i,i)end end
local function word(at,n)put(at,ffi.string(ffi.new('uint32_t[1]',n),4))end
local function read(at,n)local s={};for i=0,n-1 do if not bytes[at+i]then return nil end;s[#s+1]=bytes[at+i]end;return table.concat(s)end
pointers[game+0x2CE1508]=state;pointers[game+0x2E38110]=profile;pointers[game+0x2CE16A8]=kits
pointers[players+0xE8]=player;pointers[game+0x2CE2040]=manager
word(state+0xAC29C,3);word(players+0x88,1);word(player+8,22);word(manager+0x166C,0)
put(profile+0x3C,string.char(0));word(profile+0x40,1);word(profile+0x44,2);word(profile+0x48,3)
put(profile+0x14C,ffi.string(ffi.new('uint32_t[11]',{10,4,5,6,0,20,30,40,0,50,0}),44))
local function hex(s)return(s:gsub('%x%x',function(h)return string.char(tonumber(h,16))end))end
put(game+0x175E950,hex('40535556574883ec284c896c2458488bf98b098bda4c89742460e871cb90ff33f6448bc64885c07403448b008bd3e86d3a12ff4c8b35b63658018bee4139b640'))
put(game+0x175EBDC,hex('0f1007488b0d2a956d0133d20f11814c0100000f104f100f11895c010000f20f104720f20f11816c0100008b47288981740100004883c4285f5e5d5be9'))
local calls,cold_reads=0,0
local wrapped=setmetatable({}, {__index=ffi})
function wrapped.cast(kind,address)
 if kind=='void (*)(void *, uint32_t)'then
  assert(address==game+0x175E950)
  return function(appearance,id)
   assert(id==22);calls=calls+1;put(profile+0x14C,ffi.string(appearance,44))
  end
 end
 if kind=='void (*)(void *, bool)'then error('Cold Armory entry must never be used during ship startup')end
 return ffi.cast(kind,address)
end
local mem={_ffi=wrapped}
function mem:read(at,n)if at==game+0x12ED900 then cold_reads=cold_reads+1;return 'PACKED' end;return read(at,n)end
function mem:ptr(at)return pointers[at]end
function mem:u8(at)local s=read(at,1);return s and s:byte()end
function mem:u32(at)local s=read(at,4);if not s then return nil end;local a,b,c,d=s:byte(1,4);return a+b*256+c*65536+d*16777216 end
function mem:hashmap(at,id)if at==kits+0x938 and id==22 then return 0 end end
function mem:copy(at,s)put(at,s);return true end
local backend={mem=mem}
function backend:context()return {game=game,player=players,world=123}end
function backend:same_context(a,b)return a and b and a.game==b.game end
function backend:_kits()return {[4]='helmets',[5]='capes',[55]='capes',[6]='bodyarmor'}end
local io=Native.new(backend)
local before=assert(io:capture());assert(before.cape==5)
local target={};for k,v in pairs(before)do target[k]=v end;target.cape=55
local ok,why=io:restore(target,{weapons=true,helmets=true,capes=true,bodyarmor=true},before)
assert(ok,why);assert(calls==1 and cold_reads==0,'Startup must not depend on packed Armory code')
local after=assert(io:capture());assert(after.cape==55 and after.armor==6 and after.primary==1)
assert(mem:u8(profile+0x3C)==1)
assert(io:restore(before,{weapons=true,helmets=true,capes=true,bodyarmor=true},after))
assert(io:capture().cape==5)
print('PASS: startup restore with Armory unopened and its entry point packed; native player appearance commit and profile marker verified')
