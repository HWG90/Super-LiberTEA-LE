local E=dofile('src/extraction.lua');local ffi=require('ffi')
local game,world=0x10000000,0x20000000
local manager=world+0x13C0
local state,mode,rows,descriptors,settings=0x30000000,0x40000000,0x50000000,0x60000000,0x70000000
local p={[game+0x2CE1508]=state,[game+0x2CE1850]=mode,[game+0x2CE1860]=manager,
 [manager+0x78]=rows,[manager+0x60]=descriptors,[manager+0x68]=settings,
 [descriptors]=0x71000000,[descriptors+8]=0x72000000}
local w={[state+0xAC29C]=4,[mode+8]=1,[manager+0x28]=8,[manager+0x38]=2,
 [rows+12]=152,[rows+60]=1,[settings+0x8E8]=0,[rows+64+12]=25,[rows+64+60]=1}
local function pack(n)return ffi.string(ffi.new('float[1]',n),4)end
local bytes={[rows]=pack(120),[rows+64]=pack(5),[0x71000000]=string.rep('A',24),[0x72000000]=string.rep('B',24)}
for _,pin in ipairs(E.fingerprints)do bytes[game+pin[1]]=pin.bytes end
local b={mem={_ffi=ffi},writes=0,valid=true}
function b:gameplay_context()if self.valid then return {game=game,world=world}end;return nil,'Local host required'end
function b:same_context(a,c)return a.game==c.game and a.world==c.world end
function b.mem:ptr(at)return p[at]end
function b.mem:u32(at)return w[at]end
b.mem.u8=b.mem.u32
function b.mem:read(at,n)local s=bytes[at];if s and #s==n then return s end end
function b.mem:copy(at,s)b.writes=b.writes+1;bytes[at]=s;return true end
local e=E.new(b);e:update(.1)
assert(b.writes==1 and bytes[rows]==pack(.1) and bytes[rows+64]==pack(5))
bytes[rows]=pack(20);e:update(.1);assert(b.writes==1,'Do not shorten a later timer on the same arrival identity')
e:stop();e:update(.1);assert(b.writes==2)
e:stop();bytes[rows]=pack(120);w[state+0xAC29C]=3;e:update(.1);assert(b.writes==2)
w[state+0xAC29C]=4;b.valid=false;e:update(.1);assert(b.writes==2)
b.valid=true;w[manager+0x38]=9;e:update(.1);assert(b.writes==2)
w[manager+0x38]=2;w[settings+0x8E8]=2;e:update(.1);assert(b.writes==2)
w[settings+0x8E8]=0;bytes[rows]=pack(0/0);e:update(.1);assert(b.writes==2)
bytes[rows]=pack(120);bytes[game+E.fingerprints[1][1]]='packed';e:update(.1);assert(b.writes==2)
print('PASS: extraction-only clamp, repeat/boarding protection, host/mission/bounds/state/NaN/code guards and untouched ordinary stratagem timer')
