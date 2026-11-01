package.preload.cffi=function()return require('ffi')end
local ffi=require('ffi')
local M=dofile('src/memory.lua')
local chunks={}
local function put(a,ctype,v)local x=ffi.new(ctype,v);chunks[a]=ffi.string(x,ffi.sizeof(x))end
local function read(a,n)for at,s in pairs(chunks)do if a>=at and a+n<=at+#s then return s:sub(a-at+1,a-at+n)end end end
local map,buckets=0x100000,0x200000
local h=ffi.new('uint32_t[5]',buckets,0,8,0xffffffff,0xfedcba99);chunks[map]=ffi.string(h,20)
local key=0xf1234567
local al,ah,bl,bh=key%65536,math.floor(key/65536),0xba99,0xfedc
local prod=(al*bl+((al*bh+ah*bl)%65536)*65536)%4294967296
put(buckets+prod%8*8,'uint32_t[2]',{key,23})
local m=M.new({read=read});assert(m:hashmap(map,key)==23)
assert(m:hashmap(map,0xffffffff)==nil)
local bad=ffi.new('uint32_t[5]',buckets,0,7,0xffffffff,1);chunks[map]=ffi.string(bad,20)
assert(m:hashmap(map,key)==nil)
print('Bounded hash lookup, exact high-bit multiplication and invalid maps passed')
-- Exact-size reuse is scoped and never enlarges protected reads.
local cached=M.new();local calls=0;local generation='a'
function cached:_read_uncached(address,size) calls=calls+1;return string.rep(generation,size)end
cached:begin_snapshot();assert(cached:read(0x300010,4)=='aaaa')
assert(cached:read(0x300010,4)=='aaaa' and calls==1)
assert(cached:read(0x300010,8)=='aaaaaaaa' and calls==2)
generation='b';cached:end_snapshot();assert(cached:read(0x300010,4)=='bbbb')
cached:begin_snapshot();cached:read(0x300010,4);cached:copy(0,'');assert(cached._snapshot==nil)
cached:begin_snapshot();cached:begin_frame();assert(cached._snapshot==nil)
print('Exact protected read reuse and write/frame invalidation passed')
