local P=dofile('src/passive_ai.lua')
local c={game=0x10000000,player=0x20000000,world=0x30000000}
local m,descriptor,records=0x40000000,0x50000000,0x60000000
local flags=9
local unit=55
local writes=0
local mem={}
function mem:read(a,n) return ('4c8b15ef158302743e458b4a20'):gsub('%x%x',function(v)return string.char(tonumber(v,16))end) end
function mem:u32(a)
 if a==c.player+0x3A8 or a==descriptor+16 then return unit end
 if a==c.world+0xF349E8 or a==descriptor+8 then return 123 end
 if a==records then return flags end
end
function mem:ptr(a)
 return ({[c.game+0x2CE15E0]=m,[m+0x30]=m+100,[m+100]=descriptor,[m+0x38]=records})[a]
end
function mem:hashmap()return 0 end
local fail=false
function mem:copy(a,b)
 assert(a==records)
 if fail then return false,'Write failed' end
 local x,y,z,w=b:byte(1,4);flags=x+y*256+z*65536+w*16777216;writes=writes+1;return true
end
local b={mem=mem,passive_ai_context=function()return c end,gameplay_context=function()error('Unrelated gameplay fingerprints must not gate Passive AI')end}
local p=P.new(b)
assert(p:update(c,true));assert(flags==33554441 and writes==1)
assert(p:update(c,true));assert(writes==1)
flags=flags+4 -- unrelated flag changes survive release
fail=true;assert(not p:release() and p.lease)
fail=false;assert(p:release());assert(flags==13 and not p.lease)
assert(p:update(c,true));unit=56
assert(p:release());assert(flags==33554445 and not p.lease) -- no stale avatar write
flags=33554441;assert(p:update(c,true));assert(p:release());assert(flags==9)
print('Passive AI bit preservation, disable, retry and owner-change checks passed')
