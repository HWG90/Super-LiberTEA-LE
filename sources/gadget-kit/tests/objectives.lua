local O=dofile('src/objectives.lua')
local game=0x10000000
local manager,entities,instances,records=0x20000000,0x21000000,0x22000000,0x23000000
local state,mode=0x30000000,0x40000000
local p,w,bytes,map={},{},{},{}
local calls={}
local function objective(i,key,s,flags)
 p[entities+i*8]=0x50000000+i*0x100
 w[0x50000000+i*0x100+8]=key;w[0x50000000+i*0x100+0x14]=flags
 w[records+i*0x64+0x20]=s;w[instances+i*0x1078+0x1018]=s
 map[key]=i
end
local function reset()
 p={[game+0x2CE1508]=state,[game+0x2CE1850]=mode,[game+0x2CE1F68]=manager,
  [manager+0x50]=entities,[manager+0x60]=instances,[manager+0x68]=records}
 w={[state+0xAC29C]=4,[mode+8]=1,[manager+0x18]=16,[manager+0x20]=4,[manager+0x24]=4}
 map={};calls={}
 objective(0,0xA0,0,1)     -- active, host-owned
 objective(1,0xA1,2,1)     -- already completed
 objective(2,0xA2,1,1)     -- inactive, host-owned
 objective(3,0xA3,0,0)     -- active, owned elsewhere
end
for _,pin in ipairs(O.fingerprints)do bytes[game+pin[1]]=pin.bytes end
local b={mem={},valid=true}
function b:gameplay_context()if self.valid then return {game=game}end;return nil,'The local player must host this session'end
function b:same_context(a,c)return a.game==c.game end
function b.mem:ptr(at)return p[at]end
function b.mem:u32(at)return w[at]end
b.mem.u8=b.mem.u32
function b.mem:read(at,n)local s=bytes[at];if s and #s==n then return s end end
function b.mem:hashmap(at,key)assert(at==manager+0x38);return map[key]end
local on_complete
function b.mem:complete_objective(g,m,key)
 assert(g==game and m==manager)
 calls[#calls+1]=key
 local i=map[key];w[records+i*0x64+0x20]=2
 if on_complete then on_complete(key)end
 return true
end
local function keys()local t={};for _,k in ipairs(calls)do t[#t+1]=string.format('%X',k)end;return table.concat(t,',')end

reset()
local o=O.new(b)
o:update(1);assert(o:status()=='1 of 4 objectives complete',o:status());assert(#calls==0,'Status reads never complete')
assert(o:request());assert(not select(1,o:request()),'One request at a time')
o:update(0);assert(keys()=='A0,A2',keys());assert(o:status()=='Completed 2 objectives',o:status())
o:update(1);assert(o:status()=='3 of 4 objectives complete; completed 2 now',o:status())
assert(o:request());o:update(0);assert(#calls==2 and o:status()=='Another player owns the remaining objectives',o:status())

-- A request outside a host mission is dropped, not kept for the next mission.
reset();o=O.new(b)
b.valid=false;assert(o:request());o:update(0);assert(o:status()=='The local player must host this session')
b.valid=true;o:update(1);assert(#calls==0 and o:status()=='1 of 4 objectives complete')
w[state+0xAC29C]=3;assert(o:request());o:update(0);assert(o:status()=='Waiting for a mission')
w[state+0xAC29C]=4;o:update(1);assert(#calls==0)

-- The map entry must name the row; 5E1720 indexes the instances with it.
reset();o=O.new(b)
map[0xA0]=3;assert(o:request());o:update(0);assert(keys()=='A2',keys())
reset();o=O.new(b)
map[0xA0]=nil;map[0xA2]=nil;assert(o:request());o:update(0);assert(#calls==0 and o:status()=='Objectives changed; try again',o:status())

-- An objective completed by an earlier one's flow event is not completed twice.
reset();o=O.new(b)
on_complete=function(key)if key==0xA0 then w[records+2*0x64+0x20]=2 end end
assert(o:request());o:update(0);assert(keys()=='A0',keys())
on_complete=nil

-- Code witnesses: a packed page waits, changed bytes refuse; nothing is called either way.
for _,pin in ipairs(O.fingerprints)do
 reset();o=O.new(b)
 bytes[game+pin[1]]=nil;assert(o:request());o:update(0)
 assert(#calls==0 and o:status():find('is not loaded yet'),o:status())
 bytes[game+pin[1]]=string.char((pin.bytes:byte(1)+1)%256)..pin.bytes:sub(2);assert(o:request());o:update(0)
 assert(#calls==0 and o:status():find('mismatch'),o:status())
 bytes[game+pin[1]]=pin.bytes
end

-- Bounds and layout.
reset();o=O.new(b);w[manager+0x24]=5;assert(o:request());o:update(0);assert(#calls==0 and o:status()=='Objective manager bounds changed')
reset();o=O.new(b);w[manager+0x18]=4096;o:update(1);assert(o:status()=='Objective manager bounds changed')
reset();o=O.new(b);w[records+0x64+0x20]=7;assert(o:request());o:update(0);assert(#calls==0 and o:status()=='Objective state layout changed')
reset();o=O.new(b);p[entities+8]=nil;assert(o:request());o:update(0);assert(#calls==0 and o:status()=='Objective row is unreadable')
reset();o=O.new(b);w[manager+0x24]=0;w[manager+0x20]=0;o:update(1);assert(o:status()=='No objectives in this mission')
reset();o=O.new(b);for i=0,3 do w[records+i*0x64+0x20]=2 end;assert(o:request());o:update(0)
assert(#calls==0 and o:status()=='All objectives are already complete',o:status())

-- Fresh session check between the scan and the calls.
reset();o=O.new(b)
local same=b.same_context;b.same_context=function()return false end
assert(o:request());o:update(0);assert(#calls==0 and o:status()=='Session changed; try again');b.same_context=same
o:shutdown();assert(o:status()=='Off' and not o.pending)
print('PASS: host-owned open objectives only, map/row identity, no double completion, dropped requests, witnesses, bounds and layout')
