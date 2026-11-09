local A=dofile(NATIVE_ADS_TEST_ROOT..'/src/action_placement.lua')
local function p(x)return{x=x,y=0,z=0}end
local c={placement=p(.1),weapon_placements={a=p(.2)}}
assert(A.resolve(c,'a','idle').x==.2)
assert(A.resolve(c,'b','sprint').x==.1)
assert(A.resolve(c,'a','ads').x==0)
local key='1234567890abcdef';local other='0123456789abcdef'
c.action_placements=A.saved(c,key,'sprint',p(.3),false)
assert(A.resolve(c,key,'sprint').x==.3 and A.resolve(c,other,'sprint').x==.1)
c.action_placements=A.saved(c,other,'crouch',p(.4),false)
c.action_placements=A.saved(c,key,'sprint',p(-.2),true)
assert(A.resolve(c,key,'sprint').x==-.2 and A.resolve(c,other,'sprint').x==-.2)
assert(A.resolve(c,other,'crouch').x==.4)
assert(A.select({ads=true,sprint=true})=='ads')
assert(A.select({sprint=true})=='sprint')
assert(A.select({action_resource='r',action_verified=true,l1=1,l3=2},{r={['1:2']='crouch'}})=='crouch')
assert(A.select({action_resource='x',action_verified=true,l1=1,l3=2},{r={['1:2']='crouch'}})=='idle')
assert(not pcall(A.saved,c,key,'bad',p(0),false))
assert(not pcall(A.saved,c,key,'idle',p(10),false))
print('Action placement profiles: 13 passed')

local function decode(s)return(s:gsub('%x%x',function(h)return string.char(tonumber(h,16))end))end
local cases={
 {15,4,'0a0200000000040000200000000000000000000000000000','crouch'},
 {16,4,'0a0200000000040000200000000000000000000000000000','crouch'},
 {47,60,'0a0200000000040000400000000000000000000000000000','prone'},
 {48,56,'0a0200000000040000400000000000000000000000000000','prone'},
 {16,4,'0a0200000000040001200200000000000000000000000000','slide'},
 {16,4,'0a0200000000040000200200000000000000000000000000','slide'},
 {45,37,'0a0200000000040001400000200000000000000000000000','dive'},
 {48,56,'0a0200000000040000400000200000000000000000000000','dive'},
 {59,67,'0a0200000000040000000000000000000000000000000000','idle'}}
for _,c in ipairs(cases)do
 local s={l1=c[1],l3=c[2],stance_flags=decode(c[3]),action_resource='4D1C334D294DFA97',action_verified=true}
 assert(A.select(s)==c[4],c[4]);s.action_resource='foreign';assert(A.select(s)=='idle')
 s.action_resource='4D1C334D294DFA97';s.action_verified=false;assert(A.select(s)=='idle')
 s.action_verified=true;s.ads=true;assert(A.select(s)=='ads')
end
print('Labelled action-state fixture: 36 passed')

local rotation={x=.1,y=0,z=0,yaw=12,pitch=-8}
local config={action_placements=A.saved({},'1234567890abcdef','sprint',rotation,false)}
local saved=A.resolve(config,'1234567890abcdef','sprint');assert(saved.yaw==12 and saved.pitch==-8)
assert(not A.valid({x=0,y=0,z=0,yaw=91}));assert(not A.valid({x=0,y=0,z=0,pitch=0/0}))
print('Action rotation profiles: 3 passed')

assert(A.valid({x=0,y=0,z=0,yaw=90,pitch=-90}))
assert(not A.valid({x=0,y=0,z=0,yaw=90.1}))

-- Live 2026-10-19: moving/transitioning crouch used these bridge variants.
for _,pair in ipairs({{16,3},{20,3},{25,5},{16,4},{15,4}})do
 local f=string.rep('\0',9)..string.char(0x20)..string.rep('\0',14)
 local sample={l1=pair[1],l3=pair[2],stance_flags=f,action_resource='4D1C334D294DFA97',action_verified=true}
 assert(A.select(sample)=='crouch');sample.action_verified=false;assert(A.select(sample)=='idle')
end
print('Bridge crouch blends and unverified-resource rejection: 10 passed')

for _,pair in ipairs({{47,33},{47,22},{48,22},{48,50}})do
 local flags=string.rep('\0',9)..string.char(0x40)..'\0\0'..string.char(0x20)..string.rep('\0',11)
 assert(#flags==24)
 local sample={l1=pair[1],l3=pair[2],stance_flags=flags,action_resource='4D1C334D294DFA97',action_verified=true}
 assert(A.select(sample)=='dive');sample.stance_flags=flags:sub(1,12)..'\0'..flags:sub(14);assert(A.select(sample)=='prone')
end
print('Live dive entry, flight and prone recovery variants: 8 passed')

local roll_profile=A.saved({},'1234567890abcdef','sprint',{x=.1,y=.2,z=.3,roll=70},false)
assert(A.resolve({action_placements=roll_profile},'1234567890abcdef','sprint').roll==70)
print('Per-weapon/action roll round trip passed')

-- Family defaults are resource-whitelisted against the combined catalogue.
-- The resource read by the pose backend uses the type's little-endian bytes.
local catalogue=dofile(NATIVE_ADS_TEST_ROOT..'/src'..'/loadout_catalogue.lua')
A.configure_catalogue(catalogue.gear)
local scythe='5663fbf6d81eee27'
local info=assert(A.weapon_info(scythe));assert(info.name=='LAS-5 Scythe'and info.family=='energy')
assert(not A.weapon_info('0000000000000000'))
local cfg={placement={x=.15,y=0,z=-.12},family_placement_defaults=true}
local family=A.resolve(cfg,scythe,'idle');assert(family.z==-.115)
assert(A.resolve(cfg,scythe,'sprint').z==-.115)
assert(A.resolve(cfg,scythe,'ads').x==0)
assert(A.resolve(cfg,'0000000000000000','idle').z==-.12)
cfg.family_placement_defaults=false;assert(A.resolve(cfg,scythe,'idle').z==-.12)
cfg.family_placement_defaults=true;cfg.placement.x=.133;assert(A.resolve(cfg,scythe,'idle').x==.133)
cfg.placement={x=.15,y=0,z=-.12};cfg.weapon_placements={[scythe]={x=.21,y=0,z=0}}
assert(A.resolve(cfg,scythe,'idle').x==.21)
cfg.action_placements={__all={idle={x=.22,y=0,z=0}},[scythe]={idle={x=.23,y=0,z=0}}}
assert(A.resolve(cfg,scythe,'idle').x==.23)
assert(A.default_placement(cfg,scythe,'idle').z==-.115 and A.default_placement(cfg,scythe,'ads').z==0)
-- Melee, unidentified and catalogue ambiguity never create a firearm guess.
for _,row in ipairs(catalogue.gear)do
 if row.name:match('^CQC')or row.name:match('^Item ')or row.name=='Breaching Hammer'then
  if row.type then local chunks={};for i=15,1,-2 do chunks[#chunks+1]=row.type:sub(i,i+1)end;assert(not A.weapon_info(table.concat(chunks)))end
 end
end
local unknown='0011223344556677'
A.configure_catalogue({{kind=1,name='AR-23 Liberator',type=unknown},{kind=3,name='P-2 Peacemaker',type=unknown}})
assert(not A.weapon_info('7766554433221100'))
A.configure_catalogue(catalogue.gear)
local seen={}
for _,row in ipairs(catalogue.gear)do
 if row.type then local chunks={};for i=15,1,-2 do chunks[#chunks+1]=row.type:sub(i,i+1)end
  local key=table.concat(chunks);local entry=A.weapon_info(key)
  if entry then assert(A.valid(A.family_baseline(key)));seen[entry.family]=true end
 end
end
for _,name in ipairs({'rifle','compact','sidearm','marksman','shotgun','energy','support'})do assert(seen[name],name)end
print('Catalogue-backed composition: seven families, exact keys, unknown/melee refusal, saved-profile priority and opt-in preservation passed')
