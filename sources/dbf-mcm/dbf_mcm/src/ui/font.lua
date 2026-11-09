-- Read the already loaded HUD font; exact-build gates precede descriptor reads.
-- Layout provenance: Epic LUT src/platform/ui_font.lua and Pick-your-bots
-- Test36 Source/replace_automatons.lua:7061-7089. No scan or memory writes.
local F={}
local HIGH=4294967296
local function u32(bytes,offset)
    offset=offset or 0
    if type(bytes)~='string' or #bytes<offset+4 then return nil end
    local a,b,c,d=bytes:byte(offset+1,offset+4)
    return a+b*256+c*65536+d*16777216
end
local function hash(bytes)
    if type(bytes)~='string' or #bytes~=8 then return nil end
    local lo,hi=u32(bytes),u32(bytes,4)
    if lo==0 and hi==0 then return nil end
    return string.format('%08x%08x',hi,lo)
end
local function pointer(bytes)
    if type(bytes)~='string' or #bytes~=8 then return nil end
    local lo,hi=u32(bytes),u32(bytes,4)
    if hi>=0x8000 then return nil end
    local address=hi*HIGH+lo
    if address<0x10000 or address>0x800000000000-32 then return nil end
    return address
end
function F.new(memory,game,at)
    local function ensure_memory()
        if memory then return end
        local native
        local hosted,host=pcall(require,'hd2.lll_host')
        if hosted and type(host)=='table' and host.version==1 then
            -- LuaJIT boot runtime with LLL's in-process service: LLL ships no nativeinfo DLL there, so read this
            -- process through the runtime (ReadProcessMemory; bad addresses give nil).
            local ffi=require('ffi')
            local read=ffi.cast('int(*)(uint64_t,void *,uint32_t)',host.read_memory)
            local base=ffi.cast('uint64_t(*)(const char *)',host.module_base)
            local buffer,capacity=nil,0
            native={module_base=function(name)local value=tonumber(base(name));return value~=0 and value or nil end,
                read_memory=function(address,count)
                    if type(address)~='number' or type(count)~='number' or count<1 or count>4096 then return nil end
                    if count>capacity then buffer=ffi.new('uint8_t[?]',count);capacity=count end
                    if read(address,buffer,count)~=1 then return nil end
                    return ffi.string(buffer,count)
                end}
        else
            local path=assert(os.getenv('LOCALAPPDATA'))..'/LLL/Helldivers2/Native/hd2_nativeinfo_8d03e036881e4ddc.dll'
            local entry=assert(package.loadlib(path,'luaopen_hd2_nativeinfo'))
            native=assert(entry())
        end
        game=assert(native.module_base('game.dll'))
        memory={read=native.read_memory,address=function(value)return value end}
    end

    local self={}
    local cached_descriptor,cached_lifetime,remaining
    local function copy_descriptor(value)
        return {font=value.font,material=value.material,atlas=value.atlas}
    end
    -- A view may provide an opaque GUI/world lifetime to amortize protected
    -- descriptor reads over at most 15 frames. Resource availability is still
    -- checked on every frame using fresh native IDs. Other callers remain eager.
    function self.resolve(sr,lifetime)
        local ready=pcall(ensure_memory);if not ready then return nil end

        if not memory or type(memory.read)~='function' or type(memory.address)~='function' then return nil end
        if not sr or not sr.IdString64 or type(sr.IdString64.from_hex)~='function'
            or not sr.Application or type(sr.Application.can_get)~='function' then return nil end
        local ok,descriptor=pcall(function()
            local I,app=sr.IdString64,sr.Application
            local function available(value)
                return app.can_get('font',I.from_hex(value.font))
                    and app.can_get('texture',I.from_hex(value.atlas))
                    and app.can_get('material',I.from_hex(value.material))
            end
            if lifetime~=nil and cached_lifetime==lifetime and cached_descriptor and remaining>0 then
                remaining=remaining-1
                if available(cached_descriptor)then return copy_descriptor(cached_descriptor)end
            end
            cached_descriptor,cached_lifetime,remaining=nil,nil,0
            -- Bingus memory.address converts pointers, never module names.
            -- Keep names separate so a Lua string's buffer cannot become the
            -- PE base (and silently leave the UI on the debug fallback).
            local module=game
            if type(module)=='string' then
                if type(memory.module)~='function' then return nil end
                module=memory.module(module)
                if module==nil then return nil end
            end
            local base=memory.address(module)
            if type(base)~='number' or base<0x10000 or base>=0x800000000000 or base~=math.floor(base) then return nil end
            local function read_address(address,count) return memory.read(at and at(address) or address,count) end
            local function read(offset,count) return read_address(base+offset,count) end
            local pe=u32(read(0x3c,4))
            if not pe or pe<0x40 or pe>0x1000 or u32(read(pe,4))~=0x4550
                or u32(read(pe+8,4))~=0x6AE0E5FF
                or u32(read(pe+80,4))~=0x3382000
                or u32(read(pe+88,4))~=0x2ED103A then return nil end
            local font,atlas=hash(read(0x312D998,8)),hash(read(0x312E618,8))
            local owner=pointer(read(0x3180C08,8))
            local material=owner and hash(read_address(owner+24,8))
            if not font or not atlas or not material then return nil end
            local value={font=font,material=material,atlas=atlas}
            if not available(value)then return nil end
            if lifetime~=nil then
                cached_descriptor=copy_descriptor(value);cached_lifetime=lifetime;remaining=14
            end
            return value
        end)
        if ok then return descriptor end
        return nil
    end
    return self
end
return F
