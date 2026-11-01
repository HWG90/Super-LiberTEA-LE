-- HD2-Addon: mods/hd2transmog/dev
-- First lines of an addon that extends the foundation (tools/build.py puts
-- them at the head of the addon's bundle and names it). The addon attaches to
-- the foundation, which it loads when it was discovered first, and takes the
-- foundation's modules by name; whatever is wrong, it says so and does nothing.
local HD2TM_ADDON = 'dev'
local HD2TM_HOST = rawget(_G, 'HD2Transmog')
if not HD2TM_HOST then
    local application = rawget(_G, 'Application') or (rawget(_G, 'stingray') or {}).Application
    local found, available = pcall(function()
        return application.can_get('lua', 'mods/hd2transmog/foundation')
    end)
    -- A resource that is not installed must never reach the engine's require.
    if found and available == true then
        local loaded, host = pcall(require, 'mods/hd2transmog/foundation')
        if loaded then HD2TM_HOST = host end
    end
end
local HD2TM_KERNEL, HD2TM_REFUSAL
if type(HD2TM_HOST) == 'table' and type(HD2TM_HOST.extend) == 'function' then
    HD2TM_KERNEL, HD2TM_REFUSAL = HD2TM_HOST.extend{name=HD2TM_ADDON, abi=2}
else
    HD2TM_REFUSAL = 'HD2 Transmog Foundation is not installed or did not start'
end
if not HD2TM_KERNEL then
    print('[HD2Transmog] ' .. HD2TM_ADDON .. ' addon not attached: ' .. tostring(HD2TM_REFUSAL))
    return false
end
if HD2TM_KERNEL:has('addon.' .. HD2TM_ADDON) then return true end
local HD2TM_CORE = HD2TM_KERNEL:need('modules')
local GameCatalogLayout = HD2TM_CORE.GameCatalogLayout
local GameCustomizationLayout = HD2TM_CORE.GameCustomizationLayout
local GameDecode = HD2TM_CORE.GameDecode
local DebugBridge = (function()
-- Development-only file commands, with a per-launch token against stale replay.
-- Data-only allowlist; no executable payloads or arbitrary native calls.
local M={}
function M.new(fs,engine,report)
 if fs.read('debug.enabled')~='HD2TM_DEBUG 1\n' then return nil end
 local session=tostring(os.time())..'-'..tostring(math.floor(fs.now()))
 local seen,command_count,next_poll={},0,0
 fs.write_atomic('debug.session','HD2TM_DEBUG_SESSION 1\n'..session..'\n')
 local self={session=session}
 -- Let the host avoid constructing its command closures between inbox polls.
 -- Checking the deadline neither reads the inbox nor consumes a request.
 function self:due()return fs.now()>=next_poll end
 function self:poll(handlers)
  if fs.now()<next_poll then return end
  next_poll=fs.now()+250
  local request=fs.read('debug.request')
  if not request or #request>2048 then return end
  local token,id,command,args=request:match('^HD2TM_DEBUG_REQUEST 1\n([%w%-]+)\n([%w%-]+)\n([a-z_]+)\n(.*)$')
  if token~=session or not id or #id>80 or seen[id] then return end
  if command_count>=1024 then return end
  seen[id]=true;command_count=command_count+1
  local ok,value=pcall(function()
   assert(handlers[command],'Unknown debug command')
   return assert(handlers[command](args),'Command did not return a result')
  end)
  local text=tostring(value):gsub('[\r\n]',' '):sub(1,1000)
  fs.write_atomic('debug.response','HD2TM_DEBUG_RESPONSE 1\n'..session..'\n'..id..'\n'..(ok and 'ok' or 'error')..'\n'..text..'\n')
  report('debug.'..command,(ok and 'ok: ' or 'error: ')..text)
 end
 function self:inspect()
  local lines={}
  local function names(prefix,t)
   if type(t)~='table'then return end
   local keys={};for k,v in pairs(t)do
    if type(k)=='string' and #k<128 then keys[#keys+1]=prefix..'.'..k..' '..type(v)end
   end;table.sort(keys)
   for i=1,math.min(#keys,2048)do lines[#lines+1]=keys[i]end
  end
  names('_G',_G);names('stingray',engine)
  local keys={};for k,v in pairs(engine)do if type(k)=='string' and type(v)=='table'then keys[#keys+1]=k end end
  table.sort(keys);for _,k in ipairs(keys)do names('stingray.'..k,engine[k])end
  local alternate=rawget(_G,'s3d')
  if alternate==engine then lines[#lines+1]='s3d.alias_of_stingray true'
  elseif type(alternate)=='table'then
   names('s3d',alternate)
   local nested={};for k,v in pairs(alternate)do if type(k)=='string'and type(v)=='table'then nested[#nested+1]=k end end
   table.sort(nested);for _,k in ipairs(nested)do names('s3d.'..k,alternate[k])end
  end
  fs.write_atomic('debug-api.txt',table.concat(lines,'\n')..'\n')
  return 'API names recorded'
 end
 function self:inspect_world()
  local markers={weapon_wall='be0be6b1875a4a66',bridge_shell='ce2566805c9e893a',galaxy_table='3b9bcf29e38da0a6'}
  local lines={'HD2TRANSMOG_WORLD_MARKERS 1'}
  local main=engine.Application.main_world()
  for index,world in ipairs(engine.Application.worlds()or{})do
   if index>16 then break end
   lines[#lines+1]='world='..index..' main='..tostring(world==main)
   for name,hash in pairs(markers)do
    local ok,units=pcall(engine.World.units_by_resource,world,engine.IdString64.from_hex(hash))
    lines[#lines+1]=name..'='..(ok and type(units)=='table' and tostring(#units)or 'unavailable')
   end
  end
  fs.write_atomic('debug-world.txt',table.concat(lines,'\n')..'\n')
  return 'Scene marker observations recorded'
 end
 self:inspect()
 return self
end
return M

end)()
local DebugArmory = (function()
-- Opt-in semantic inspection of native references to the proven menu global.
-- No native calls, writes, heap scan, raw-byte export, or Armory-open claim.
local M={}
local Decode=GameDecode or error('module is not bundled: src.game.decode')
local function u16(s,o)local a,b=s:byte(o+1,o+2);return a+b*256 end
local function u32(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
local function i32(s,o)local n=u32(s,o);return n>=2147483648 and n-4294967296 or n end
local function scalar32(s)
 local n=u32(s,0);local sign=n>=2147483648 and -1 or 1;n=n%2147483648
 local exponent,mantissa=math.floor(n/8388608),n%8388608
 if exponent==255 then return nil end
 return sign*(exponent==0 and mantissa*2^-149 or (1+mantissa/8388608)*2^(exponent-127))
end
-- The decoder is the game layer's; the developer tools find it here under the
-- name they have always used.
M.decode=Decode.decode
-- Iterative semantic-only inspection, deliberately separate from any caller.
-- Requested RVA is normalized to its validated PE function entry, so a byte in
-- an immediate cannot become a guessed instruction boundary. No native call.
function M.inspect_code(bridge,rva,byte_count)
 local ok,result=pcall(function()
  assert(type(bridge)=='table'and type(bridge.verify)=='function'and bridge.verify(),'debug proof changed')
  assert(type(rva)=='number'and rva%1==0 and rva>=4096 and type(byte_count)=='number'
   and byte_count%1==0 and byte_count>=16 and byte_count<=4096,'bounded RVA and byte count required')
  local base=bridge.base
  local function read(at,n)
   local s=bridge.read(base+at,n);assert(type(s)=='string'and #s==n,'code metadata unreadable');return s
  end
  local dos=read(0,64);assert(dos:sub(1,2)=='MZ','invalid image');local pe=u32(dos,60)
  assert(pe>=64 and pe<=65536,'invalid PE');local nt=read(pe,24+144)
  assert(nt:sub(1,4)=='PE\0\0'and u16(nt,4)==0x8664 and u16(nt,24)==0x20b,'PE64 required')
  local count,opt,size=u16(nt,6),u16(nt,20),u32(nt,80)
  assert(count>=1 and count<=96 and opt>=144 and opt<=4096 and size<=536870912,'invalid image bounds')
  local sections={}
  for i=0,count-1 do
   local h=read(pe+24+opt+i*40,40);local len,at,flags=u32(h,8),u32(h,12),u32(h,36)
   assert(at+len<=size,'section out of image')
   sections[#sections+1]={at=at,len=len,read=math.floor(flags/1073741824)%2==1,exec=math.floor(flags/536870912)%2==1,
    write=math.floor(flags/2147483648)%2==1}
  end
  local function contains(at,n,exec)
   for _,s in ipairs(sections)do if s.read and (not exec or s.exec)and at>=s.at and at+n<=s.at+s.len then return true end end
   return false
  end
  local pdata,len=u32(nt,24+136),u32(nt,24+140)
  assert(u32(nt,24+108)>=4 and len>=12 and len<=2400000 and len%12==0 and contains(pdata,len),'function metadata unavailable')
  local lo,hi,first,last=0,len/12-1
  while lo<=hi do
   local mid=math.floor((lo+hi)/2);local row=read(pdata+mid*12,12);local a,b=u32(row,0),u32(row,4)
   if rva<a then hi=mid-1 elseif rva>=b then lo=mid+1 else first,last=a,b;break end
  end
  assert(first and first<last and contains(first,last-first,true),'requested RVA has no validated function')
  assert(rva-first<=4096,'requested point too far from function entry')
  local n=math.min(last-first,rva-first+byte_count);assert(n<=8192,'code window too large')
  local code=read(first,n);local rows=Decode.decode(code,first,8192)
  local selected={};local boundary
  for index,row in ipairs(rows)do if row.rva==rva then boundary=index;break end end
  assert(boundary,'requested RVA is not an instruction boundary')
  selected[1]=string.format('HD2TRANSMOG_CODE_SEMANTICS 1\nfunction=0x%08x size=%d requested=0x%08x\nopens_armory=false',first,last-first,rva)
  for index=math.max(1,boundary-32),math.min(#rows,boundary+512)do
   local row=rows[index];selected[#selected+1]=string.format('0x%08x %s',row.rva,row.op)
   -- Export a typed scalar only when a decoded scalar-float instruction
   -- directly references read-only image data. Never expose arbitrary bytes.
   local mnemonic=row.op:match('^(%a+) ')
   if ({movss=true,addss=true,subss=true,mulss=true,divss=true,comiss=true,ucomiss=true})[mnemonic]and rows[index+1]then
    local direction,delta=row.op:match('%[rip([+-])0x(%x+)%]')
    if delta then
     local target=rows[index+1].rva+(direction=='-'and -1 or 1)*tonumber(delta,16)
     for _,section in ipairs(sections)do
      if section.read and not section.exec and not section.write and target>=section.at and target+4<=section.at+section.len then
       local raw=read(target,4);local value=scalar32(raw)
       if value then
        assert(read(target,4)==raw,'scalar operand changed')
        selected[#selected+1]=string.format('  read_only_f32=%.9g',value)
       end
       break
      end
     end
    end
   end
  end
  assert(read(first,n)==code and bridge.verify(),'code proof changed')
  return table.concat(selected,'\n')..'\n'
 end)
 if not ok then return nil,tostring(result)end;return result
end
-- Leaf functions can legitimately have no unwind entry. Their entry is accepted
-- only as the exact direct-call target of an already validated instruction.
-- This is semantic inspection, not a callable-address resolver.
function M.inspect_callee(bridge,callsite,byte_count)
 local ok,result=pcall(function()
  assert(type(byte_count)=='number'and byte_count%1==0 and byte_count>=16 and byte_count<=1024,'bounded callee window required')
  local caller,reason=M.inspect_code(bridge,callsite,16);assert(caller,reason)
  local wanted=string.format('0x%08x call 0x',callsite)
  local target
  for line in caller:gmatch('[^\n]+')do
   if line:sub(1,#wanted)==wanted then target=tonumber(line:sub(#wanted+1),16)end
  end
  assert(target,'validated instruction is not a direct call')
  local function read(rva,n)
   local s=bridge.read(bridge.base+rva,n);assert(type(s)=='string'and #s==n,'callee evidence unreadable');return s
  end
  local dos=read(0,64);local pe=u32(dos,60);local nt=read(pe,88)
  local count,opt,size=u16(nt,6),u16(nt,20),u32(nt,80)
  assert(count>=1 and count<=96 and opt>=112 and opt<=4096 and target+byte_count<=size,'callee image bounds rejected')
  local valid=false;local sections={}
  for i=0,count-1 do
   local h=read(pe+24+opt+i*40,40);local len,at,flags=u32(h,8),u32(h,12),u32(h,36)
   sections[#sections+1]={at=at,len=len,read=math.floor(flags/1073741824)%2==1,
    exec=math.floor(flags/536870912)%2==1,write=math.floor(flags/2147483648)%2==1}
   if math.floor(flags/1073741824)%2==1 and math.floor(flags/536870912)%2==1
    and target>=at and target+byte_count<=at+len then valid=true end
  end
  assert(valid and bridge.verify(),'callee is not current executable image code')
  local code=read(target,byte_count)
  local rows=Decode.decode(code,target,512)
  local out={string.format('HD2TM_DIRECT_CALLEE_SEMANTICS 1\ncallsite=0x%08x target=0x%08x\nno_native_call=true',callsite,target)}
  for _,row in ipairs(rows)do out[#out+1]=string.format('0x%08x %s',row.rva,row.op)end
  local ops={};for _,row in ipairs(rows)do ops[row.op]=true end
  if ops['mov r9d, 0x96']and ops['and eax, +0x0f']and ops['sar r9w, 0x04']then
   local masks,indices,base_proved
   for i,row in ipairs(rows)do
    local delta=row.op:match('^lea rcx, %[rip%-0x(%x+)%]$')
    if delta and rows[i+1]and rows[i+1].rva-tonumber(delta,16)==0 then base_proved=true end
    local a=row.op:match('^movzx r10d, word %[rcx%+rax%*2%+0x(%x+)%]$')
    local b=row.op:match('^mov rcx, %[rcx%+rax%*8%+0x(%x+)%]$')
    if a then masks=tonumber(a,16)end;if b then indices=tonumber(b,16)end
   end
   local function constant(at,n)
    if not at then return nil end
    for _,s in ipairs(sections)do
     if s.read and not s.exec and not s.write and at>=s.at and at+n<=s.at+s.len then
      local raw=read(at,n);assert(read(at,n)==raw,'typed truncation table changed');return raw
     end
    end
   end
   if base_proved then
    local a,b=constant(masks,32),constant(indices,16)
    if a and b then
     local values={};for i=0,15 do values[#values+1]=tostring(u16(a,i*2))end
     out[#out+1]='truncation_masks_u16='..table.concat(values,',')
     assert(u32(b,4)==0 and u32(b,12)==0,'truncation word indices outside uint32')
     out[#out+1]='truncation_word_indices_u64='..u32(b,0)..','..u32(b,8)
    end
   end
  end
  assert(read(target,byte_count)==code and bridge.verify(),'callee code changed')
  return table.concat(out,'\n')..'\n'
 end)
 if not ok then return nil,tostring(result)end;return result
end
-- Recognize the observed MSVC image-relative switch form before reading its
-- target table. Output is selector -> code RVA, never an arbitrary data read.
function M.inspect_switch(bridge,table_rva,count)
 local ok,result=pcall(function()
  assert(bridge.verify(),'debug proof changed')
  assert(type(table_rva)=='number'and table_rva%1==0 and table_rva>=4096
   and type(count)=='number'and count%1==0 and count>=1 and count<=64,'bounded switch request required')
  local base=bridge.base
  local function read(at,n)
   assert(at>=0 and n>=1 and n<=65536,'switch read rejected')
   local s=bridge.read(base+at,n);assert(type(s)=='string'and #s==n,'switch evidence unreadable');return s
  end
  local dos=read(0,64);assert(dos:sub(1,2)=='MZ','invalid image');local pe=u32(dos,60)
  assert(pe>=64 and pe<=65536,'invalid PE');local nt=read(pe,168)
  assert(nt:sub(1,4)=='PE\0\0'and u16(nt,4)==0x8664 and u16(nt,24)==0x20b,'PE64 required')
  local n,opt,size=u16(nt,6),u16(nt,20),u32(nt,80);assert(n>=1 and n<=96 and opt>=144 and opt<=4096,'image bounds rejected')
  local sections={}
  for i=0,n-1 do
   local h=read(pe+24+opt+i*40,40);local at,len,flags=u32(h,12),u32(h,8),u32(h,36)
   assert(at+len<=size,'section bounds rejected')
   sections[#sections+1]={at=at,len=len,read=math.floor(flags/0x40000000)%2==1,exec=math.floor(flags/0x20000000)%2==1}
  end
  local function inside(at,len,exec)
   for _,s in ipairs(sections)do if s.read and (not exec or s.exec)and at>=s.at and at+len<=s.at+s.len then return true end end
   return false
  end
  assert(inside(table_rva,count*4),'switch table outside readable image')
  local pdata,len=u32(nt,160),u32(nt,164)
  assert(u32(nt,132)>=4 and len>=12 and len%12==0 and len<=2400000 and inside(pdata,len),'function metadata unavailable')
  -- Search nearby PE-declared fragments. Optimized logical functions may be
  -- split into multiple .pdata rows; no guessed backward instruction starts.
  local lo,hi,index=0,len/12-1
  while lo<=hi do
   local mid=math.floor((lo+hi)/2);local row=read(pdata+mid*12,12);local first,last=u32(row,0),u32(row,4)
   if table_rva<first then hi=mid-1 elseif table_rva>=last then lo=mid+1 else index=mid;break end
  end
  assert(index,'switch table has no containing function metadata')
  local rows,proofs={},{}
  for i=math.max(0,index-255),index do
   local meta=read(pdata+i*12,12);local first,last=u32(meta,0),u32(meta,4)
   if first>=table_rva-16384 and first<table_rva and first<last and inside(first,last-first,true)then
    local length=math.min(last-first,table_rva-first)
    assert(length<=16384,'switch fragment too large')
    local code=read(first,length);proofs[#proofs+1]={at=first,bytes=code}
    for _,row in ipairs(Decode.decode(code,first,16384))do rows[#rows+1]=row end
   end
  end
  local found,selector_base
  for i,row in ipairs(rows)do
   local dst,reg,indexreg,disp=row.op:match('^mov (%w+), %[(%w+)%+(%w+)%*4%+0x(%x+)%]$')
   if disp and tonumber(disp,16)==table_rva then
    local dst64=dst:gsub('^e','r');local ix32=indexreg:gsub('^r','e')
    if rows[i+1]and rows[i+2]and rows[i+1].op=='add '..dst64..', '..reg and rows[i+2].op=='jmp '..dst64 then
     local imagebase,bound,decrement=false,false,false
     for j=math.max(1,i-256),i-1 do
      local op=rows[j].op;local sign,delta=op:match('^lea '..reg..', %[rip([+-])0x(%x+)%]$')
      local reg32=reg:gsub('^r','e')
      if op:match('^%w+ '..reg..',')or op:match('^%w+ '..reg32..',')then imagebase=false end
      if delta and rows[j+1]then
       local address=rows[j+1].rva+(sign=='-'and -1 or 1)*tonumber(delta,16)
       if address==0 then imagebase=true end
      end
      if j>=i-40 then
       local maximum=op:match('^cmp '..ix32..', [+]?0x(%x+)$')
       if maximum and tonumber(maximum,16)+1==count and rows[j+1]and rows[j+1].op:match('^ja ')then bound=true end
       if op=='dec '..ix32 then decrement=true end
      end
     end
     if imagebase and bound then assert(not found,'ambiguous switch evidence');found=row.rva;selector_base=decrement and 1 or 0 end
    end
   end
  end
  assert(found,'requested table/count lack the supported switch instruction proof')
  local table_bytes=read(table_rva,count*4)
  local out={string.format('HD2TRANSMOG_SWITCH_SEMANTICS 1\ndispatch=0x%08x selectors=%d..%d\nopens_armory=false',found,selector_base,count-1+selector_base)}
  for i=0,count-1 do
   local target=u32(table_bytes,i*4);assert(inside(target,1,true),'switch target outside executable image')
   out[#out+1]=string.format('selector=%d target=0x%08x',i+selector_base,target)
  end
  for _,p in ipairs(proofs)do assert(read(p.at,#p.bytes)==p.bytes,'switch code changed')end
  assert(read(table_rva,count*4)==table_bytes and bridge.verify(),'switch proof changed')
  return table.concat(out,'\n')..'\n'
 end)
 if not ok then return nil,tostring(result)end;return result
end
function M.new(bridge,report)
 assert(type(bridge)=='table' and type(bridge.read)=='function' and type(bridge.verify)=='function','verified debug bridge required')
 assert(type(bridge.base)=='number' and type(bridge.menu_global)=='number','menu global proof required')
 report=report or function()end
 local self={phase='resolving'};local lines={'HD2TRANSMOG_NATIVE_ARMORY_PROBE 1','purpose=read_only_transition_research','opens_armory=false'}
 local base=bridge.base;local sections={};local deadline=0
 local function output(value)
  assert(#lines<32768,'semantic output budget exceeded');lines[#lines+1]=value
 end
 local function read(rva,n)
  assert(type(rva)=='number'and rva>=0 and rva%1==0 and n>=1 and n<=262144,'debug read bounds rejected')
  local s=bridge.read(base+rva,n);assert(type(s)=='string'and #s==n,'native code unreadable');return s
 end
 local function executable(rva,n)
  for _,section in ipairs(sections)do if section.exec and rva>=section.rva and rva+n<=section.rva+section.size then return true end end
  return false
 end
 local function run()
  assert(bridge.verify(),'menu proof changed')
  local dos=read(0,64);assert(dos:sub(1,2)=='MZ','invalid image')
  local pe=u32(dos,60);assert(pe>=64 and pe<=65536,'PE offset rejected')
  local nt=read(pe,88);assert(nt:sub(1,4)=='PE\0\0'and u16(nt,4)==0x8664 and u16(nt,24)==0x20b,'PE64 required')
  local count,opt,size=u16(nt,6),u16(nt,20),u32(nt,80)
  assert(count>=1 and count<=96 and opt>=112 and opt<=4096 and size<=536870912,'PE bounds rejected')
  output('image_timestamp='..u32(nt,8));output(string.format('menu_global_rva=0x%08x',bridge.menu_global-base))
  local total=0
  for i=0,count-1 do
   local h=read(pe+24+opt+i*40,40);local len,rva,flags=u32(h,8),u32(h,12),u32(h,36)
   if len>0 then
    assert(rva>=4096 and rva+len<=size,'section bounds rejected')
    local exec=math.floor(flags/536870912)%2==1;local readable=math.floor(flags/1073741824)%2==1
    if exec then assert(readable,'unreadable code');total=total+len end
    sections[#sections+1]={rva=rva,size=len,exec=exec,readable=readable}
   end
  end
  assert(total>0 and total<=134217728,'code scan budget rejected')
  local pdata,pdata_size
  if opt>=144 then
   local d=read(pe+24+108,36);local rva,len=u32(d,28),u32(d,32)
   if u32(d,0)>=4 and len>=12 and len%12==0 and len<=2400000 then
    for _,s in ipairs(sections)do
     if s.readable and rva>=s.rva and rva+len<=s.rva+s.size then pdata,pdata_size=rva,len end
    end
   end
  end
  local function bounds(rva)
   if not pdata then return end
   local lo,hi=0,pdata_size/12-1
   while lo<=hi do
    local mid=math.floor((lo+hi)/2);local row=read(pdata+mid*12,12)
    local first,last=u32(row,0),u32(row,4)
    if rva<first then hi=mid-1 elseif rva>=last then lo=mid+1
    else if first<last and executable(first,last-first)then return first,last end;return end
   end
  end
  local found,call_targets,wrappers={},{},{};local hits,emitted,scanned=0,0,0
  local function inspect(rva)
   if found[rva]then return end;found[rva]=true;hits=hits+1;assert(hits<=4096,'menu xref limit exceeded')
   local available=160
   while available>0 and not executable(rva,available)do available=available-1 end
   local code=read(rva,available)
   local rows=Decode.decode(code,rva,32)
   local member,callee
   for index,row in ipairs(rows)do
    if row.op:find('0x4288',1,true)then member=index end
    if member then
     local target=row.op:match('^call%s+0x(%x+)$')or row.op:match('^jmp%s+0x(%x+)$')
     if target then callee=tonumber(target,16);break end
    end
    if row.op=='ret'or row.op:match('^int3')then break end
   end
   if not member or not callee then return end
   local first,last=bounds(rva)
   -- Recognize forwarding wrappers only at a PE-declared function start.
   if first==rva and last-first<=256 then wrappers[rva]=true end
   -- A Windows leaf tail-call thunk commonly has no unwind-table row. The
   -- exact MOV-global / ADD-subobject / JMP / INT3 sequence is still a useful
   -- target candidate; its CALLERS must pass the .pdata boundary check below.
   if rows[1]and rows[2]and rows[3]and rows[4]
    and rows[1].op:match('^mov rcx, %[%s*rip')
    and rows[2].op=='add rcx, 0x4288'and rows[3].op:match('^jmp%s+0x%x+$')
    and rows[4].op=='int3' then wrappers[rva]=true end
   emitted=emitted+1;assert(emitted<=384,'menu transition candidate limit exceeded')
   if executable(callee,1024)then call_targets[callee]=(call_targets[callee]or 0)+1 end
   output(string.format('xref=0x%08x',rva))
   for _,row in ipairs(rows)do
    output(string.format('  0x%08x %s',row.rva,row.op))
    if row.op=='ret'or row.op:match('^int3')then break end
   end
   assert(read(rva,available)==code,'menu reference changed during decode')
  end
  for _,section in ipairs(sections)do if section.exec then
   local tail=''
   for offset=0,section.size-1,262144 do
    assert(bridge.verify(),'menu proof changed')
    local chunk=read(section.rva+offset,math.min(262144,section.size-offset))
    local code=tail..chunk;local origin=section.rva+offset-#tail;local at=1
    while at<=#code-6 do
     if os.clock()>=deadline then coroutine.yield()end
     -- A RIP-relative MOV/LEA encoding of the proven global is a candidate
     -- anchor, not yet a function/ABI proof. Decode forward from that anchor;
     -- do not interpret isolated E8 bytes as calls. Function-start/xref
     -- confirmation remains necessary before deriving a callable entry point.
     local hit=code:find('[\139\141]',at)
     if not hit or hit+5>#code then break end
     local modrm=code:byte(hit+1)
     if modrm%8==5 and modrm<64 then
      local start=hit;local prefix=hit>1 and code:byte(hit-1)or 0
      if prefix>=64 and prefix<=79 then start=hit-1 end
      local target=base+origin+hit+5+i32(code,hit+1)
      if target==bridge.menu_global then inspect(origin+start-1)end
     end
     at=hit+1
    end
    scanned=scanned+#chunk;tail=code:sub(-8);self.scanned_bytes=scanned
    coroutine.yield() -- at most one large image read per step
   end
  end end
  local targets={};for rva in pairs(call_targets)do targets[#targets+1]=rva end
  table.sort(targets,function(a,b)if call_targets[a]~=call_targets[b]then return call_targets[a]>call_targets[b]end;return a<b end)
  output('xref_count='..hits);output('transition_candidates='..emitted);output('direct_call_targets='..#targets)
  -- Follow only a bounded first layer of direct callees from menu references.
  -- These are research candidates, not approved callable entry points.
  for index,rva in ipairs(targets)do
   if index>48 then output('callee_listing_truncated=true');break end
   if os.clock()>=deadline then coroutine.yield()end
   local code=read(rva,1024)
   output(string.format('callee=0x%08x',rva))
   for _,row in ipairs(Decode.decode(code,rva,160))do
    output(string.format('  0x%08x %s',row.rva,row.op))
    if row.op:match('^int3')then break end
   end
   assert(read(rva,1024)==code,'callee changed during decode')
  end
  -- The actual Armory site may call a forwarding wrapper, so it need not
  -- reference the menu global. Scan direct branches to dynamically observed
  -- wrappers/common callees, then validate instruction boundaries by decoding
  -- from the containing PE function's entry. Never infer from a lone E8 byte.
  if pdata then
   local sought={};local sought_count=0
   for rva in pairs(wrappers)do sought[rva]=true;sought_count=sought_count+1 end
   for index,rva in ipairs(targets)do if index<=16 and not sought[rva]then sought[rva]=true;sought_count=sought_count+1 end end
   output('branch_target_count='..sought_count)
   local branches,seen_branches=0,{}
   local function inspect_branch(at,target)
    if seen_branches[at]then return end;seen_branches[at]=true
    local first,last=bounds(at)
    if not first or at-first>2048 or at+5>last then return end
    local length=math.min(last-first,at-first+96)
    local code=read(first,length);local rows=Decode.decode(code,first,2048);local found_at
    for index,row in ipairs(rows)do if row.rva==at then
     local actual=row.op:match('^call%s+0x(%x+)$')or row.op:match('^jmp%s+0x(%x+)$')
     if actual and tonumber(actual,16)==target then found_at=index end;break
    end end
    if not found_at then return end
    assert(read(first,length)==code,'branch function changed during decode')
    branches=branches+1;assert(branches<=256,'validated branch budget exceeded')
    output(string.format('branch=0x%08x target=0x%08x function=0x%08x size=%d',at,target,first,last-first))
    for index=math.max(1,found_at-32),math.min(#rows,found_at+4)do
     local row=rows[index];output(string.format('  0x%08x %s',row.rva,row.op))
    end
   end
   for _,s in ipairs(sections)do if s.exec then
    local tail=''
    for offset=0,s.size-1,262144 do
     assert(bridge.verify(),'menu proof changed during branch scan')
     local chunk=read(s.rva+offset,math.min(262144,s.size-offset));local code=tail..chunk
     local origin=s.rva+offset-#tail;local at=1
     while at<=#code-4 do
      if os.clock()>=deadline then coroutine.yield()end
      local hit=code:find('[\232\233]',at);if not hit or hit+4>#code then break end
      local target=origin+hit+4+i32(code,hit)
      if sought[target]then inspect_branch(origin+hit-1,target)end
      at=hit+1
     end
     tail=code:sub(-4);coroutine.yield()
    end
   end end
   output('validated_branches='..branches)
  else output('branch_scan=PE_function_metadata_unavailable')end
  assert(bridge.verify(),'menu proof changed before completion')
  self.phase='ready';report('debug_armory.xrefs',hits);report('debug_armory.status','semantic_probe_complete')
 end
 local worker=coroutine.create(run)
 function self:step()
  if self.phase~='resolving'then return self.phase,self.failure end
  deadline=os.clock()+0.006
  local ok,why=coroutine.resume(worker)
  if not ok then self.phase='failed';self.failure=tostring(why);output('failure='..self.failure);report('debug_armory.status',self.failure)end
  return self.phase,self.failure
 end
 function self:summary()return table.concat(lines,'\n')..'\n'end
 return self
end
return M

end)()
local DebugController = (function()
-- Read-only development observation of the known kind-224 Armory controller.
-- It inventories candidate virtual functions; it NEVER calls a candidate.
-- Input: signature-verified {base,read,manager_global,menu_global,verify,decode?}.
-- Output contains semantic offsets/function RVAs, not raw bytes or heap pointers.
local M={}
local function u16(s,o)
 if type(s)~='string'or #s<o+2 then return nil end
 local a,b=s:byte(o+1,o+2);return a+256*b
end
local function u32(s,o)
 if type(s)~='string'or #s<o+4 then return nil end
 local a,b,c,d=s:byte(o+1,o+4);return a+256*b+65536*c+16777216*d
end
local function ptr(s,o)
 o=o or 0;local lo,hi=u32(s,o),u32(s,o+4)
 if not hi or hi>=32768 then return nil end
 local n=lo+hi*4294967296;return n>=65536 and n or nil
end
function M.inspect(bridge)
 local ok,result=pcall(function()
  assert(type(bridge)=='table'and type(bridge.read)=='function'and type(bridge.verify)=='function','verified debug bridge required')
  assert(bridge.verify()==true,'UI signature proof changed')
  local reads,total,watched=0,0,{}
  local function read(at,size)
   assert(type(at)=='number'and at>=65536 and at%1==0 and at+size<140737488355328 and size>=1 and size<=4096,'observation bounds rejected')
   reads,total=reads+1,total+size
   assert(reads<=2048 and total<=65536,'controller observation budget exceeded')
   local raw=bridge.read(at,size);assert(type(raw)=='string'and #raw==size,'controller evidence unreadable')
   return raw
  end
  local function watch(at,size)
   local raw=read(at,size);watched[#watched+1]={at=at,size=size,raw=raw};return raw
  end
  local base=assert(bridge.base,'module base required')
  local dos=watch(base,64);assert(dos:sub(1,2)=='MZ','invalid module header')
  local pe=u32(dos,60);assert(pe>=64 and pe<=65536,'invalid PE offset')
  local nt=watch(base+pe,24+144)
  assert(nt:sub(1,4)=='PE\0\0'and u16(nt,4)==0x8664 and u16(nt,24)==0x20b,'PE64 image required')
  local count,opt,image_size=u16(nt,6),u16(nt,20),u32(nt,80)
  assert(count>=1 and count<=96 and opt>=144 and opt<=4096 and image_size>=4096 and image_size<=536870912,'invalid PE bounds')
  local sections={}
  for i=0,count-1 do
   local h=watch(base+pe+24+opt+i*40,40)
   local size,rva,flags=u32(h,8),u32(h,12),u32(h,36)
   assert(rva+size<=image_size,'invalid section bounds')
   if size>0 then
    sections[#sections+1]={first=base+rva,last=base+rva+size,
     readable=math.floor(flags/0x40000000)%2==1,executable=math.floor(flags/0x20000000)%2==1}
   end
  end
  local function image_kind(at,size)
   for _,section in ipairs(sections)do
    if at>=section.first and at+size<=section.last and section.readable then
     return section.executable and 'code'or 'data'
    end
   end
  end
  local pdata_rva,pdata_size=u32(nt,24+112+24),u32(nt,24+112+28)
  -- A packed image may store its exception directory in readable executable
  -- .winlice memory. Protection alone does not invalidate that metadata.
  local pdata_valid,pdata_reason=pcall(function()
   assert(u32(nt,24+108)>=4 and pdata_size>=12 and pdata_size%12==0 and pdata_size<=2400000
    and image_kind(base+pdata_rva,pdata_size),'bounded readable PE function table required')
   local entries=pdata_size/12
   local previous,previous_index
   for i=0,math.min(16,entries-1)do
    local index=entries==1 and 0 or math.floor(i*(entries-1)/math.min(16,entries-1))
    if index~=previous_index then
     local row=watch(base+pdata_rva+index*12,12)
     local first,last=u32(row,0),u32(row,4)
     assert(first<last and image_kind(base+first,last-first)=='code','invalid sampled function range')
     assert(not previous or first>previous,'unsorted sampled function table')
     previous,previous_index=first,index
    end
   end
  end)
  local pdata_status=pdata_valid and 'sampled readable function table'or 'unavailable: '..tostring(pdata_reason)
  local function bounds(rva)
   if not pdata_valid then return nil end
   local lo,hi=0,pdata_size/12-1
   while lo<=hi do
    local mid=math.floor((lo+hi)/2)
    local row=read(base+pdata_rva+mid*12,12)
    local first,last=u32(row,0),u32(row,4)
    assert(first<last and image_kind(base+first,last-first)=='code','invalid function-table range')
    if rva<first then hi=mid-1
    elseif rva>=last then lo=mid+1
    else
     return first,last-first
    end
   end
  end
  local manager=assert(ptr(watch(bridge.manager_global,8)),'UI manager unavailable')
  local menu=assert(ptr(watch(bridge.menu_global,8)),'menu manager unavailable')
  local row_count=u32(watch(manager+0x166c,4),0)
  assert(row_count>=1 and row_count<=64,'UI registry bounds rejected')
  local rows=watch(manager+0x1670,row_count*16)
  local controller
  for i=0,row_count-1 do
   if u32(rows,i*16+8)==224 then
    assert(not controller,'ambiguous Armory controller')
    controller=assert(ptr(rows,i*16),'invalid Armory controller')
   end
  end
  local menu_state=watch(menu+0x4288,44)
  if not controller then
   local output={status='Armory controller is not registered',menu_owner_offsets={},slots={},
    vtable_status='unavailable',menu_current=u32(menu_state,12),menu_pending=u32(menu_state,16),
    menu_stack_depth=u32(menu_state,40)}
   if output.menu_stack_depth>=1 and output.menu_stack_depth<=5 then
    output.menu_stack_top=u32(menu_state,20+(output.menu_stack_depth-1)*4)
   end
   for _,item in ipairs(watched)do assert(read(item.at,item.size)==item.raw,'controller observation changed')end
   assert(bridge.verify()==true,'UI signature proof changed')
   output.reads,output.bytes_read=reads,total
   return output
  end
  local header=watch(controller,16)
  local menu_header=watch(menu,512)
  local menu_offsets={}
  for offset=0,504,8 do
   if ptr(menu_header,offset)==controller then menu_offsets[#menu_offsets+1]=offset end
  end
  local output={status='controller_observed',menu_owner_offsets=menu_offsets,
   controller_u32_at_8=u32(header,8),vtable_status='first word is not an image data pointer',slots={},
   menu_current=u32(menu_state,12),menu_pending=u32(menu_state,16),menu_stack_depth=u32(menu_state,40)}
  if output.menu_stack_depth and output.menu_stack_depth>=1 and output.menu_stack_depth<=5 then
   output.menu_stack_top=u32(menu_state,20+(output.menu_stack_depth-1)*4)
  end
  local vtable=ptr(header)
  if vtable and image_kind(vtable,8)=='data'then
   output.vtable_status='candidate image vtable';output.vtable_rva=vtable-base
   local functions={}
   for slot=0,23 do
    if image_kind(vtable+slot*8,8)~='data'then break end
    local target=ptr(watch(vtable+slot*8,8))
    if not target or image_kind(target,1)~='code'then break end
    local rva=target-base
    local entry={slot=slot,rva=rva}
    if not functions[rva]then
     local valid,first,size=pcall(bounds,rva)
     if not valid then
      pdata_valid=false;pdata_status='unavailable: '..tostring(first);first,size=nil,nil
     end
     functions[rva]={first=first,size=size}
     if first and type(bridge.decode)=='function'then
      local bytes=watch(base+first,math.min(size,256))
      functions[rva].instructions=bridge.decode(bytes,first)
     end
    end
    entry.function_start=functions[rva].first;entry.function_size=functions[rva].size
    entry.instructions=functions[rva].instructions
    output.slots[#output.slots+1]=entry
   end
   if #output.slots==0 then output.vtable_status='image data pointer has no executable slots'end
  end
  for _,item in ipairs(watched)do assert(read(item.at,item.size)==item.raw,'controller observation changed')end
  assert(bridge.verify()==true,'UI signature proof changed')
  output.function_metadata=pdata_status
  output.reads,output.bytes_read=reads,total
  return output
 end)
 if not ok then return nil,tostring(result)end
 return result
end
function M.format(result)
 local lines={'Armory controller metadata (read-only)',
  'status='..tostring(result.status),
  'menu_current='..tostring(result.menu_current),
  'menu_pending='..tostring(result.menu_pending),
  'menu_stack_depth='..tostring(result.menu_stack_depth),
  'menu_stack_top='..tostring(result.menu_stack_top),
  'controller_u32_at_8='..tostring(result.controller_u32_at_8),
  'function_metadata='..tostring(result.function_metadata),
  'vtable_status='..tostring(result.vtable_status),
  'vtable_rva='..(result.vtable_rva and string.format('0x%x',result.vtable_rva)or 'none')}
 for _,offset in ipairs(result.menu_owner_offsets or {})do
  lines[#lines+1]=string.format('menu_owner_offset=0x%x',offset)
 end
 for _,entry in ipairs(result.slots or {})do
  lines[#lines+1]=string.format('slot=%d target_rva=0x%x function_start=%s function_size=%s',entry.slot,entry.rva,
   entry.function_start and string.format('0x%x',entry.function_start)or 'no_pdata',tostring(entry.function_size or 'unknown'))
  for _,instruction in ipairs(entry.instructions or {})do
   if type(instruction)=='table'and type(instruction.rva)=='number'and type(instruction.op)=='string'then
    lines[#lines+1]=string.format('  %08x %s',instruction.rva,instruction.op)
   end
  end
 end
 lines[#lines+1]='reads='..tostring(result.reads)..' bytes_read='..tostring(result.bytes_read)
 return table.concat(lines,'\n')..'\n'
end
return M

end)()
local DebugOpenArmory = (function()
-- Development-only real native menu entry. No persisted addresses or guessed
-- menu-field writes. Every call target is derived from current RIP-relative
-- code and the two current switch tables, then checked again before invocation.
local M={}
local decoder=DebugArmory or error('module is not bundled: src.debug_armory')
local function u16(s,o)local a,b=s:byte(o+1,o+2);return a+256*b end
local function u32(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+256*b+65536*c+16777216*d end
local function i32(s,o)local n=u32(s,o);return n>=2147483648 and n-4294967296 or n end
local function ptr(s)
 if type(s)~='string'or #s~=8 then return nil end
 local hi=u32(s,4);if hi>=32768 then return nil end
 local n=u32(s,0)+hi*4294967296;return n>=65536 and n or nil
end
local function call_target(row,kind)
 local value=row and row.op:match('^'..(kind or 'call')..' 0x(%x+)$')
 return value and tonumber(value,16)or nil
end
local entry_type
local function native()
 local ffi=require('ffi');pcall(ffi.cdef,'size_t VirtualQuery(const void*,void*,size_t);')
 entry_type=entry_type or ffi.typeof('void (*)(void *, uint32_t, void *)')
 local kernel=ffi.load('kernel32');local region=ffi.new('uint8_t[48]')
 return {invoke=function(at,object,screen)
  assert(kernel.VirtualQuery(ffi.cast('const void*',at),ffi.cast('void*',region),48)==48,'native entry unavailable')
  local raw=ffi.string(region,48);local protection=u32(raw,36)
  assert(u32(raw,32)==4096 and ({[16]=true,[32]=true,[64]=true,[128]=true})[protection],'native entry not executable')
  ffi.cast(entry_type,at)(ffi.cast('void*',object),screen,nil)
 end}
end
function M.new(bridge,scene_guard,report,backend)
 assert(type(bridge)=='table'and type(bridge.read)=='function'and type(bridge.verify)=='function','verified bridge required')
 assert(type(bridge.base)=='number'and type(bridge.menu_global)=='number'and type(bridge.manager_global)=='number'
  and type(scene_guard)=='function','menu, manager and live scene guard required')
 report=report or function()end
 local self={phase='resolving'};local base=bridge.base;local proofs,sections={},{};local deadline,proof_bytes=0,0
 local push_rva,entry_rva
 local function read(at,n)
  assert(type(at)=='number'and at%1==0 and at>=65536 and at+n<140737488355328 and n>=1 and n<=262144,'open read bounds rejected')
  local s=bridge.read(at,n);assert(type(s)=='string'and #s==n,'open evidence unreadable');return s
 end
 local function image(rva,n)return read(base+rva,n)end
 local function inside(rva,n,exec)
  for _,s in ipairs(sections)do if s.read and (not exec or s.exec)and rva>=s.rva and rva+n<=s.rva+s.size then return true end end
  return false
 end
 local function watch(rva,n,exec)
  assert(inside(rva,n,exec),'open evidence outside current image')
  assert(#proofs<32 and proof_bytes+n<=16384,'open proof budget exceeded');proof_bytes=proof_bytes+n
  local s=image(rva,n);proofs[#proofs+1]={rva=rva,bytes=s};return s
 end
 local function instructions(rva,n)return decoder.decode(watch(rva,n,true),rva,2048)end
 local function has(rows,op)
  for _,row in ipairs(rows)do if row.op==op then return true end end;return false
 end
 local function following(rows,ops)
  local target
  for i=1,#rows-#ops do
   local match=true;for j,op in ipairs(ops)do if rows[i+j-1].op~=op then match=false;break end end
   if match then
    local at=call_target(rows[i+#ops]);assert(at,'expected native relative call')
    assert(not target or target==at,'ambiguous native call path');target=at
   end
  end
  return assert(target,'native call path changed')
 end
 local function switch_target(rows,selector)
  local found
  for i,row in ipairs(rows)do
   local table_hex=row.op:match('^mov ecx, %[r14%+rbx%*4%+0x(%x+)%]$')
   if table_hex and rows[i+1]and rows[i+2]and rows[i+1].op=='add rcx, r14'and rows[i+2].op=='jmp rcx'then
    local count,zero,decrement
    for j=math.max(1,i-40),i-1 do
     local max=rows[j].op:match('^cmp ebx, %+?0x(%x+)$')
     if max then count=tonumber(max,16)+1 end
     if rows[j].op=='dec ebx'then decrement=true end
     local delta=rows[j].op:match('^lea r14, %[rip%-0x(%x+)%]$')
     if delta and rows[j+1]and rows[j+1].rva-tonumber(delta,16)==0 then zero=true end
    end
    assert(zero and decrement and count and count<=64 and selector<=count,'native switch bounds/base changed')
    local table_rva=tonumber(table_hex,16);local bytes=watch(table_rva,count*4,false)
    for j=0,count-1 do assert(inside(u32(bytes,j*4),1,true),'invalid native switch target')end
    local target=u32(bytes,(selector-1)*4);assert(not found,'ambiguous native switch');found=target
   end
  end
  return assert(found,'native switch proof unavailable')
 end
 local function resolve()
  assert(bridge.verify(),'UI compatibility changed')
  local dos=image(0,64);assert(dos:sub(1,2)=='MZ','invalid image');local pe=u32(dos,60)
  assert(pe>=64 and pe<=65536,'invalid PE');local nt=image(pe,88)
  assert(nt:sub(1,4)=='PE\0\0'and u16(nt,4)==0x8664 and u16(nt,24)==0x20b,'PE64 required')
  local count,opt,size=u16(nt,6),u16(nt,20),u32(nt,80)
  assert(count>=1 and count<=96 and opt>=112 and opt<=4096 and size<=536870912,'invalid PE bounds')
  local total=0
  for i=0,count-1 do
   local h=image(pe+24+opt+i*40,40);local n,rva,flags=u32(h,8),u32(h,12),u32(h,36)
   if n>0 then
    assert(rva>=4096 and rva+n<=size,'invalid section')
    local s={rva=rva,size=n,read=math.floor(flags/0x40000000)%2==1,exec=math.floor(flags/0x20000000)%2==1}
    if s.exec then assert(s.read,'unreadable code');total=total+n end;sections[#sections+1]=s
   end
  end
  assert(total>0 and total<=134217728,'open scan budget rejected')
  local seen,matched={},{}
  for _,s in ipairs(sections)do if s.exec then
   local tail=''
   for offset=0,s.size-1,262144 do
    assert(bridge.verify(),'UI compatibility changed while resolving')
    local bytes=tail..image(s.rva+offset,math.min(262144,s.size-offset));local origin=s.rva+offset-#tail;local at=1
    while true do
     if os.clock()>=deadline then coroutine.yield()end
     local hit=bytes:find('\72\139\13',at,true);if not hit then break end
     if hit+19<=#bytes and bytes:sub(hit+7,hit+13)=='\72\129\193\136\66\0\0'
      and bytes:byte(hit+14)==233 and bytes:byte(hit+19)==204 then
      local rva=origin+hit-1;local slot=base+rva+7+i32(bytes,hit+2)
      if slot==bridge.menu_global then
       local target=rva+19+i32(bytes,hit+14)
       if not seen[target]and inside(target,1024,true)then
        seen[target]=true;local rows=decoder.decode(image(target,1024),target,512)
        if rows[1]and rows[1].op=='mov [rsp+0x18], r8'
         and has(rows,'movsxd rdi, edx')and has(rows,'mov [rsi+rax*4+0x14], edi')
         and has(rows,'inc dword [rsi+0x28]')and has(rows,'mov [rsi+0xc], edi')then
          matched[#matched+1]={rva=target,wrapper=rva}
        end
       end
      end
     end
     at=hit+1
    end
    tail=bytes:sub(-20);coroutine.yield()
   end
  end end
  assert(#matched==1,'unique native menu-push entry not resolved')
  push_rva=matched[1].rva;watch(matched[1].wrapper,20,true)
  local rows=instructions(push_rva,1024)
  local dispatcher=following(rows,{'mov r8, [rsp+0x90]','mov edx, edi','mov rcx, r12'})
  rows=instructions(dispatcher,160)
  assert(has(rows,'movsxd rbx, edx')and has(rows,'mov rdi, r8'),'menu payload dispatch changed')
  local top_case=switch_target(rows,5);rows=instructions(top_case,48)
  assert(rows[2]and rows[2].op=='mov r8, rdi'and rows[3]and rows[3].op=='mov edx, 0x2','Armory GUI mapping changed')
  local factory
  for _,row in ipairs(rows)do local at=call_target(row,'jmp');if at then factory=at;break end end
  assert(factory,'GUI factory branch unavailable')
  rows=instructions(factory,224)
  assert(has(rows,'mov rsi, r8')and has(rows,'mov edi, edx')and has(rows,'mov [rbx], edi'),'GUI factory ABI changed')
  local entering=following(rows,{'mov r8, rsi','mov rdx, rbx','mov rcx, rbx'})
  rows=instructions(entering,288)
  assert(has(rows,'mov r12, r8')and has(rows,'mov r8, r12'),'GUI enter payload preservation changed')
  local gui_dispatch=following(rows,{'mov rdx, r13','mov r9d, [r15]','mov rcx, r15'})
  rows=instructions(gui_dispatch,160)
  assert(has(rows,'mov ebx, r9d')and has(rows,'mov rsi, r8'),'GUI selector ABI changed')
  local gui_case=switch_target(rows,2);rows=instructions(gui_case,32)
  assert(rows[1]and rows[1].op=='mov rcx, [rdi+0x60]'and rows[2]and rows[2].op=='mov rdx, r15','Armory callback mapping changed')
  entry_rva=assert(call_target(rows[3]),'Armory on-enter callback unavailable')
  assert(call_target(rows[4],'jmp'),'Armory case must terminate without reading optional payload')
  rows=instructions(entry_rva,1024)
  assert(has(rows,'mov r13, rcx')and has(rows,'mov [rcx+0x28], rdx')and has(rows,'mov r8b, 0x1'),'Armory callback ABI changed')
  local body={};for _,row in ipairs(rows)do if row.op=='int3'then break end;body[#body+1]=row end
  local register_rva=following(body,{'mov rcx, r13'})
  rows=instructions(register_rva,256)
  assert(has(rows,'mov dword [rsp+0x48], 0xe0')and has(rows,'mov eax, [rdx+0x166c]')
   and has(rows,'inc dword [rdx+0x166c]')and has(rows,'add rax, 0x167'),'selected callback is not the proven Armory controller')
  local manager_match=false
  for i,row in ipairs(rows)do
   local sign,delta=row.op:match('^mov rdx, %[rip([+-])0x(%x+)%]$')
   if delta and rows[i+1]and base+rows[i+1].rva+(sign=='-'and -1 or 1)*tonumber(delta,16)==bridge.manager_global then manager_match=true end
  end
  assert(manager_match,'Armory registration uses a different UI manager')
  for _,proof in ipairs(proofs)do assert(image(proof.rva,#proof.bytes)==proof.bytes,'open proof changed during resolution')end
  assert(bridge.verify(),'UI compatibility changed after resolution')
  self.phase='ready';report('debug_open_armory.status','native_call_path_verified')
 end
 local worker=coroutine.create(resolve)
 function self:step()
  if self.phase~='resolving'then return self.phase,self.failure end
  deadline=os.clock()+0.006;local ok,why=coroutine.resume(worker)
  if not ok then self.phase='failed';self.failure=tostring(why);report('debug_open_armory.failure',self.failure)end
  return self.phase,self.failure
 end
 function self:open()
  local ok,value=pcall(function()
   assert(self.phase=='ready','native Armory entry not resolved')
   local intact,why=pcall(function()
    assert(bridge.verify(),'UI compatibility changed')
    for _,proof in ipairs(proofs)do assert(image(proof.rva,#proof.bytes)==proof.bytes,'native entry code/table changed')end
   end)
   if not intact then self.phase='failed';self.failure=tostring(why);error(self.failure,0)end
   local menu_bytes=read(bridge.menu_global,8);local menu=assert(ptr(menu_bytes),'menu manager unavailable')
   local state=read(menu+0x4294,32)
   assert(u32(state,0)==0 and u32(state,4)==0 and u32(state,28)==0,'close the current native menu before opening Armory')
   assert(scene_guard()==true,'current main world is not a verified ship scene')
   backend=backend or native()
   assert(read(bridge.menu_global,8)==menu_bytes and read(menu+0x4294,32)==state and bridge.verify(),'menu context changed before native entry')
   assert(scene_guard()==true,'ship scene changed before native entry')
   backend.invoke(base+push_rva,menu+0x4288,5)
   report('debug_open_armory.native_request',true)
   return 'Native Armory transition invoked; waiting for verified Armory view'
  end)
  if not ok then return nil,tostring(value)end;return true,value
 end
 return self
end
return M

end)()
local NativeArmorProbe = (function()
-- Opt-in read-only inspection of current armor-catalog consumers. No native
-- calls, writes, process-wide memory scan or raw memory export.
local M={}
local decoder=DebugArmory or error('module is not bundled: src.debug_armory')
local function u16(s,o)local a,b=s:byte(o+1,o+2);return a+b*256 end
local function u32(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
local function i32(s,o)local n=u32(s,o);return n>=2147483648 and n-4294967296 or n end
local function f32(s)
 local n=u32(s,0);local sign=n>=2147483648 and -1 or 1;n=n%2147483648
 local e,m=math.floor(n/8388608),n%8388608
 if e==255 then return nil end
 return sign*(e==0 and m*2^-149 or (1+m/8388608)*2^(e-127))
end
function M.new(bridge,report)
 assert(type(bridge)=='table'and type(bridge.read)=='function'and type(bridge.verify)=='function'
  and type(bridge.base)=='number'and type(bridge.armor_catalog)=='number','catalog bridge required')
 report=report or function()end
 local self={phase='resolving'};local base=bridge.base;local sections={};local deadline=0
 local lines={'HD2TRANSMOG_ARMOR_CODE_PROBE 1','read_only=true'}
 local function out(line)assert(#lines<24000,'armor semantic output budget exceeded');lines[#lines+1]=line end
 local function image(rva,n)
  assert(rva>=0 and rva%1==0 and n>=1 and n<=262144,'armor image bounds rejected')
  local bytes=bridge.read(base+rva,n);assert(type(bytes)=='string'and #bytes==n,'armor code unreadable');return bytes
 end
 local function contains(rva,n,exec)
  for _,s in ipairs(sections)do if s.read and (not exec or s.exec)and rva>=s.rva and rva+n<=s.rva+s.size then return true end end
  return false
 end
 local callees={}
 local function inspect(rva,n,title,depth)
  if not contains(rva,n,true)then return end
  local code=image(rva,n);local rows=decoder.decode(code,rva,math.min(1024,n))
  -- The combined equipment display helper uses image-base indexed float tables
  -- and a different slot filter from the gameplay averages. Export typed table
  -- values only after proving that local image-base LEA and the indexed load.
  if depth==0 and rows[1]and rows[1].op:match('^mov r15, %[rip')and contains(rva,1024,true)then
   local window=image(rva,1024);local full=decoder.decode(window,rva,768)
   local facts,bases={},{}
   for _,row in ipairs(full)do facts[row.op]=true end
   if facts['cmp dword [rax+0xc], +0x00']and facts['cmp dword [rax+0x8], +0x00']
    and facts['test eax, 0xfffffff8']and facts['cmp edx, +0x03']then
    local emitted={}
    for index,row in ipairs(full)do
     local reg,sign,delta=row.op:match('^lea (r%d+), %[rip([+-])0x(%x+)%]$')
     if reg and full[index+1]then bases[reg]=full[index+1].rva+(sign=='-'and -1 or 1)*tonumber(delta,16)end
     local table_base,table_offset=row.op:match('^movss xmm0, %[(r%d+)%+r%a+%*4%+0x(%x+)%]$')
     local table_rva=table_offset and bases[table_base]==0 and tonumber(table_offset,16)
     if table_rva and not emitted[table_rva]and contains(table_rva,16,false)then
      emitted[table_rva]=true;local values={}
      for weight=0,3 do values[#values+1]=assert(f32(image(table_rva+weight*4,4)),'display coefficient is not finite')end
      out(string.format('equipment_display_code=0x%08x table=0x%08x values=%.9g,%.9g,%.9g,%.9g helmet_slot=0 body_slots=2,4,5,6,7,8,9 weight_none_excluded=false',
       rva,table_rva,values[1],values[2],values[3],values[4]))
     end
    end
    assert(image(rva,1024)==window,'display coefficient proof changed')
   end
  end
  if depth==0 and rows[2]and rows[2].op=='xor r14d, r14d'and contains(rva,768,true)then
   local window=image(rva,768);local full=decoder.decode(window,rva,512)
   local facts={};for _,row in ipairs(full)do facts[row.op]=true end
   if facts['cmp edx, +0x14']and facts['cmp dword [rax+0xc], +0x00']
    and facts['cmp r8d, +0x03']and facts['addss xmm0, [r10+r8*4]']and facts['divss xmm0, xmm1']then
    for index,row in ipairs(full)do
     local sign,delta=row.op:match('^lea r10, %[rip([+-])0x(%x+)%]$')
     if delta and full[index+1]then
      local table_rva=full[index+1].rva+(sign=='-'and -1 or 1)*tonumber(delta,16)
      if contains(table_rva,12,false)then
       local values={}
       for weight=0,2 do values[#values+1]=assert(f32(image(table_rva+weight*4,4)),'weight coefficient is not finite')end
       out(string.format('weight_average_code=0x%08x table=0x%08x values=%.9g,%.9g,%.9g capacity=20 excluded_weight=3',
        rva,table_rva,values[1],values[2],values[3]))
       break
      end
     end
    end
    assert(image(rva,768)==window,'weight coefficient proof changed')
   end
  end
  local player_map=false
  for _,row in ipairs(rows)do if row.op:find('+0x938]',1,true)then player_map=true end end
  local emit=not(depth==0 and title=='xref'and player_map)
  if emit then out(title..string.format('=0x%08x',rva))end
  for i,row in ipairs(rows)do
   if emit then out(string.format('  0x%08x %s',row.rva,row.op))end
   local at=row.op:match('^call 0x(%x+)$')or row.op:match('^jmp 0x(%x+)$')
   if at and depth==0 then
    local target=tonumber(at,16);if contains(target,768,true)then callees[target]=(callees[target]or 0)+(player_map and 0.05 or 1)end
   end
   local sign,offset=row.op:match('%[rip([+-])0x(%x+)%]')
   if emit and sign and rows[i+1]and row.op:match('^%a*ss ')then
    local target=rows[i+1].rva+(sign=='-'and -1 or 1)*tonumber(offset,16)
    if contains(target,4,false)then
     local value=f32(image(target,4))
     if value then out(string.format('    constant_f32=%.9g source_rva=0x%08x',value,target))end
    end
   end
   if row.op=='int3' then break end
  end
  assert(image(rva,n)==code,'armor code changed during observation')
 end
 local function run()
  assert(bridge.verify(),'catalog code proof changed')
  local dos=image(0,64);assert(dos:sub(1,2)=='MZ','invalid image');local pe=u32(dos,60)
  assert(pe>=64 and pe<=65536,'invalid PE offset');local nt=image(pe,88)
  assert(nt:sub(1,4)=='PE\0\0'and u16(nt,4)==0x8664 and u16(nt,24)==0x20b,'PE64 required')
  local count,opt,size=u16(nt,6),u16(nt,20),u32(nt,80)
  assert(count>=1 and count<=96 and opt>=112 and opt<=4096 and size<=536870912,'PE bounds rejected')
  local total=0
  for i=0,count-1 do
   local h=image(pe+24+opt+i*40,40);local rva,len,flags=u32(h,12),u32(h,8),u32(h,36)
   if len>0 then
    assert(rva>=4096 and rva+len<=size,'section bounds rejected')
    local section={rva=rva,size=len,exec=math.floor(flags/0x20000000)%2==1,read=math.floor(flags/0x40000000)%2==1}
    if section.exec then assert(section.read,'unreadable code');total=total+len end
    sections[#sections+1]=section
   end
  end
  assert(total>0 and total<=134217728,'armor code scan budget exceeded')
  out('image_timestamp='..u32(nt,8));out(string.format('armor_catalog_global=0x%08x',bridge.armor_catalog-base))
  local found,hits={},0
  local labels={{name='armor_rating',bytes='\193\67\183\129'},
   {name='speed',bytes='\235\12\45\92'},{name='stamina_regen',bytes='\59\137\251\16'}}
  for _,s in ipairs(sections)do if s.exec then
   local tail=''
   for offset=0,s.size-1,262144 do
    assert(bridge.verify(),'catalog code proof changed')
    local code=tail..image(s.rva+offset,math.min(262144,s.size-offset));local origin=s.rva+offset-#tail;local at=1
    while true do
     if os.clock()>=deadline then coroutine.yield()end
     local hit=code:find('[\139\141]',at);if not hit or hit+5>#code then break end
     local m=code:byte(hit+1)
     if m<64 and m%8==5 and base+origin+hit+5+i32(code,hit+1)==bridge.armor_catalog then
      local start=hit;local rex=hit>1 and code:byte(hit-1)or 0;if rex>=64 and rex<=79 then start=start-1 end
      local rva=origin+start-1
      if not found[rva]then
       found[rva]=true;hits=hits+1;assert(hits<=1024,'armor xref budget exceeded')
       inspect(rva,256,'xref',0)
      end
     end
     at=hit+1
    end
    for _,label in ipairs(labels)do
     local cursor=1
     while true do
      local hit=code:find(label.bytes,cursor,true);if not hit then break end
      local op=hit>1 and code:byte(hit-1)or 0
      if op>=184 and op<=191 then
       local start=hit-1;local rex=start>1 and code:byte(start-1)or 0
       if rex>=64 and rex<=79 then start=start-1 end
       local rva=origin+start-1
       if not found['label:'..rva]then found['label:'..rva]=true;inspect(rva,384,'label_'..label.name,0)end
      end
      cursor=hit+1
     end
    end
    tail=code:sub(-8);coroutine.yield()
   end
  end end
  out('xref_count='..hits)
  local sorted={};for rva in pairs(callees)do sorted[#sorted+1]=rva end
  table.sort(sorted,function(a,b)if callees[a]~=callees[b]then return callees[a]>callees[b]end;return a<b end)
  for index,rva in ipairs(sorted)do
   if index>48 then out('callee_limit_reached=true');break end
   if os.clock()>=deadline then coroutine.yield()end
   inspect(rva,768,'callee',1)
  end
  assert(bridge.verify(),'catalog proof changed before completion')
  self.phase='ready';report('native_armor_probe.xrefs',hits);report('native_armor_probe.status','semantic_observation_complete')
 end
 local worker=coroutine.create(run)
 function self:step()
  if self.phase~='resolving'then return self.phase,self.failure end
  deadline=os.clock()+0.006;local ok,why=coroutine.resume(worker)
  if not ok then self.phase='failed';self.failure=tostring(why);out('failure='..self.failure);report('native_armor_probe.failure',why)end
  return self.phase,self.failure
 end
 function self:summary()return table.concat(lines,'\n')..'\n'end
 return self
end
return M

end)()
local RenderProbe = (function()
-- Read-only type/boxing evidence for an engine-created Material userdata.
-- A successful pointer conversion is NOT a usable Gui.bitmap argument.
local M={}
local function u32(s,o)
 if type(s)~='string'or #s<o+4 then return nil end
 local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216
end
local function ptr(s,o)
 local lo,hi=u32(s,o),u32(s,o+4)
 if not hi or hi>=32768 then return nil end
 local p=lo+hi*4294967296;return p>=65536 and p or nil
end
local function hash(s)
 if type(s)~='string'or #s~=8 then return nil end
 local out={};for i=8,1,-1 do out[#out+1]=string.format('%02x',s:byte(i))end
 return table.concat(out)
end
function M.inspect(engine,material,bridge,address_of)
 local ok,result=pcall(function()
  assert(material~=nil and bridge.verify(),'existing material and current UI proof required')
  local ffi=require('ffi')
  local result={material_type=type(material),raw_pointer_bitmap_supported=false,candidates={}}
  local id=engine.Material.id64(material)
  local expected=engine.IdString64.to_hex(id):lower()
  assert(expected:match('^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$'),'material resource identity unavailable')
  result.resource=expected
  local at=address_of and address_of(material)or tonumber(ffi.cast('uintptr_t',material))
  assert(type(at)=='number'and at%1==0 and at>=65536 and at<140737488355296,'material userdata address unavailable')
  local raw=bridge.read(at,32);assert(type(raw)=='string'and #raw==32,'material userdata unreadable')
  -- Inspect at most four pointer-sized fields and 128 bytes per candidate.
  -- Publish offsets/resource identities only, never payload bytes or addresses.
  for o=0,24,8 do
   local candidate=ptr(raw,o)
   if candidate then
    local bytes=bridge.read(candidate,128)
    if type(bytes)=='string'and #bytes==128 then
     for p=0,120,8 do
      if hash(bytes:sub(p+1,p+8))==expected then
       result.candidates[#result.candidates+1]={payload_offset=o,resource_offset=p}
      end
     end
     assert(bridge.read(candidate,128)==bytes,'material candidate changed during inspection')
    end
   end
  end
  assert(bridge.read(at,32)==raw and bridge.verify(),'material or UI proof changed during inspection')
  return result
 end)
 if not ok then return nil,tostring(result)end
 return result
end
function M.format(result)
 local rows={'HD2TM_MATERIAL_BOX 1','read_only=true','material_type='..result.material_type,
  'resource='..result.resource,'raw_pointer_bitmap_supported=false'}
 for _,v in ipairs(result.candidates)do
  rows[#rows+1]='payload_offset='..v.payload_offset..' resource_offset='..v.resource_offset
 end
 return table.concat(rows,'\n')..'\n'
end
return M

end)()
local CustomizationRawProbe = (function()
-- THROWAWAY INVESTIGATION PROBE -- not part of the shipped feature set.
-- Read-only hex dump of the native customization manager's per-player region so
-- the unmapped request/cache bytes can be attributed offline. Never writes, never
-- exports pointers: every address is emitted relative to the manager base.
-- Delete this module and its debug command once the field map is recorded.
local Layout=GameCustomizationLayout or error('module is not bundled: src.game.customization_layout')
local Players,Map,Infos,Info,Cache=Layout.players,Layout.player_map,Layout.slot_infos,Layout.slot_info,Layout.cache
local M={}
local function u32(s,o)
 if type(s)~='string' or #s<o+4 then return nil end
 local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216
end
local function ptr(s,o)
 o=o or 0;local lo,hi=u32(s,o),u32(s,o+4)
 if not hi or hi>=32768 then return nil end
 local n=lo+hi*4294967296;return n>=65536 and n or nil
end
local function hex(s)return(s:gsub('.',function(c)return string.format('%02x',c:byte())end))end

-- Region covering the slot-info array, the cache array and the request array,
-- with margin on both sides.
local BASE,SPAN,CHUNK=Layout.per_player_region.base,Layout.per_player_region.span,128
local MAX_SPAN=0x1000

function M.new(bridge)
 assert(type(bridge)=='table' and type(bridge.read)=='function' and type(bridge.verify)=='function','verified read bridge required')
 local self={}
 -- args: optional '<root> <hexbase> <hexspan>', root one of manager|players|player.
 function self:sample(args)
  local root,base,span='manager',BASE,SPAN
  if type(args)=='string' and args~='' then
   local r,b,sp=args:match('^(%a+)%s+(%x+)%s+(%x+)$')
   assert(r and (r=='manager' or r=='players' or r=='player'),'window root must be manager, players or player')
   base,span=tonumber(b,16),tonumber(sp,16)
   assert(base and span and span>0 and span<=MAX_SPAN,'window span rejected')
   root=r
  end
  -- A live session mutates peer records while we read. Retry a bounded number of
  -- times so a moving peer yields a coherent snapshot instead of a hard failure;
  -- the stability assertion itself is never relaxed.
  local ok,result
  for attempt=1,12 do
   ok,result=self:attempt(root,base,span)
   if ok then result.attempts=attempt;break end
   if not tostring(result):find('during observation',1,true) then break end
  end
  if not ok then return nil,tostring(result) end
  return result
 end
 function self:attempt(root,base,span)
  local ok,result=pcall(function()
   assert(bridge.verify(),'customization compatibility changed')
   assert(type(bridge.players)=='number','local-player signature unavailable')
   local watches={};local reads=0
   local function watch(at,n)
    reads=reads+1;assert(reads<=64,'customization read budget exceeded')
    assert(type(at)=='number' and at%1==0 and at>=65536 and at+n<140737488355328 and n>0 and n<=CHUNK,'customization read bounds rejected')
    local s=bridge.read(at,n);assert(type(s)=='string' and #s==n,'customization data unavailable')
    watches[#watches+1]={at=at,bytes=s};return s
   end
   local manager=assert(ptr(watch(bridge.armor_catalog,8)),'customization manager unavailable')
   local players=assert(ptr(watch(bridge.players,8)),'players manager unavailable')
   local counts=watch(players+Players.counts.at,Players.counts.size);local total,locals=u32(counts,Players.counts.total),u32(counts,Players.counts.locals)
   assert(total>=1 and total<=Players.max_total,'implausible player count')
   local player=assert(ptr(watch(players+Players.first_local,8)),'local player unavailable')
   local local_id=u32(watch(player+Layout.player.id,4),0)

   -- Slot occupancy, read through the same info array the local probe uses.
   local slots={}
   for index=0,Layout.slot_count-1 do
    local info=ptr(watch(manager+Infos.base+index*Infos.stride,8))
    local entity=info and u32(watch(info+Info.entity,4),0) or nil
    slots[index]={present=info~=nil,entity=entity,live=entity~=nil and entity~=Info.entity_not_live}
   end

   -- Player id -> slot map, so remote slots can be attributed once peers exist.
   local map=watch(manager+Map.at,Map.size)
   local entries,capacity,empty=ptr(map,Map.entries),u32(map,Map.capacity),u32(map,Map.empty_key)
   local pairs_found={}
   if entries and capacity and capacity>=1 and capacity<=4096 then
    for i=0,math.min(capacity,64)-1 do
     local row=watch(entries+i*Map.row.size,Map.row.size);local key,value=u32(row,Map.row.player_id),u32(row,Map.row.slot)
     if key~=empty then pairs_found[#pairs_found+1]={key=key,slot=value} end
    end
   end

   local anchor=manager
   if root=='players' then anchor=players elseif root=='player' then anchor=player end
   local region={}
   for offset=0,span-1,CHUNK do
    region[#region+1]=watch(anchor+base+offset,math.min(CHUNK,span-offset))
   end
   region=table.concat(region)

   for _,w in ipairs(watches)do
    assert(bridge.read(w.at,#w.bytes)==w.bytes,'customization changed during observation')
   end
   assert(bridge.verify(),'customization compatibility changed during observation')
   return {total=total,locals=locals,local_id=local_id,slots=slots,map=pairs_found,
    root=root,base=base,region=hex(region)}
  end)
  return ok,result
 end
 return self
end

-- THROWAWAY WRITE EXPERIMENT. Local player's slot only, and only the offsets that
-- were observed zero for both a local modded player and a remote vanilla player.
-- Refuses to touch a field that is not currently zero, so real state is never clobbered.
local FREE={[Cache.at_0x14]=true,[Cache.at_0x18]=true,[Cache.at_0x1c]=true,[Cache.at_0x20]=true}
function M.poke(bridge,writer,mode)
 assert(type(writer)=='table' and type(writer.write)=='function','writer required')
 assert(mode=='marker' or mode=='restore','mode must be marker or restore')
 local ok,result=pcall(function()
  assert(bridge.verify(),'customization compatibility changed')
  local manager=assert(ptr(bridge.read(bridge.armor_catalog,8),0),'customization manager unavailable')
  local players=assert(ptr(bridge.read(bridge.players,8),0),'players manager unavailable')
  local counts=bridge.read(players+Players.counts.at,Players.counts.size)
  assert(u32(counts,Players.counts.locals)==1,'exactly one local player required')
  local player=assert(ptr(bridge.read(players+Players.first_local,8),0),'local player unavailable')
  local player_id=u32(bridge.read(player+Layout.player.id,4),0)
  -- Resolve the local player's own slot through the same hash the read path uses.
  local map=bridge.read(manager+Map.at,Map.size)
  local entries,capacity,empty,multiplier=ptr(map,Map.entries),u32(map,Map.capacity),u32(map,Map.empty_key),u32(map,Map.multiplier)
  assert(entries and capacity>=1 and capacity<=4096,'player lookup capacity rejected')
  local start=Map.start(player_id,capacity,multiplier)
  local slot
  for probe=0,math.min(capacity,64)-1 do
   local row=bridge.read(entries+((start+probe)%capacity)*Map.row.size,Map.row.size)
   local key=u32(row,Map.row.player_id)
   if key==player_id then slot=u32(row,Map.row.slot);break end
   if key==empty then break end
  end
  assert(slot and slot<Layout.slot_count,'local customization slot unavailable')
  local base=manager+Cache.base+slot*Cache.stride
  local lines={}
  local markers={[Cache.at_0x14]='5a5a5a5a',[Cache.at_0x18]='a5a5a5a5',[Cache.at_0x1c]='3c3c3c3c',[Cache.at_0x20]='c3c3c3c3'}
  for offset in pairs(FREE) do
   local before=bridge.read(base+offset,4)
   local want
   if mode=='marker' then
    assert(before=='\0\0\0\0',string.format('offset 0x%02x is not zero; refusing to overwrite real state',offset))
    want=(markers[offset]:gsub('..',function(x)return string.char(tonumber(x,16))end))
   else
    want='\0\0\0\0'
   end
   local wrote=writer.write(base+offset,want)
   local after=bridge.read(base+offset,4)
   lines[#lines+1]=string.format('slot=%d offset=0x%02x wrote=%s readback=%s',slot,offset,
    tostring(wrote==true),hex(after))
  end
  table.sort(lines)
  return 'mode='..mode..'\n'..table.concat(lines,'\n')
 end)
 if not ok then return nil,tostring(result) end
 return result
end

function M.format(r)
 if type(r)~='table' then return 'HD2TRANSMOG_CUSTOMIZATION_RAW 1\nstatus=unavailable\n' end
 local out={'HD2TRANSMOG_CUSTOMIZATION_RAW 1',
  'players_total='..r.total,'players_local='..r.locals,'local_player_id='..r.local_id,
  'window_root='..tostring(r.root),'read_attempts='..tostring(r.attempts or 1)}
 for index=0,Layout.slot_count-1 do
  local s=r.slots[index]
  out[#out+1]=string.format('slot%d present=%s live=%s entity=%s',index,
   tostring(s.present),tostring(s.live),s.entity and string.format('%08x',s.entity) or 'none')
 end
 for _,m in ipairs(r.map) do
  out[#out+1]=string.format('map player_id=%08x slot=%d',m.key,m.slot)
 end
 -- 32 bytes per line, offsets relative to the manager base only.
 for i=0,#r.region/2-1,32 do
  out[#out+1]=string.format('+%04x %s',r.base+i,r.region:sub(i*2+1,i*2+64))
 end
 out[#out+1]='status=observed'
 return table.concat(out,'\n')..'\n'
end
return M

end)()
local ClothingRemoteProbe = (function()
-- THROWAWAY PHASE 0 PROBE -- settles two premises that research/94 and /95 assert but
-- never evidence, before ~2000 lines of API 2 are built on them:
--   1. does a modded observer render the remapped carrier at all, or plain B-01?
--   2. does a carrier rebind reach an already-built remote actor, or only a respawned one?
--
-- `observe` is strictly read-only. `rebind` points ONE reserved carrier's body descriptor
-- field at another catalog record's EXISTING descriptors: the record's body array, the
-- same field and the same write/readback/recover discipline clothing_binding.lua already
-- uses. Package identity is never touched, nothing is allocated and nothing is ever
-- unloaded -- the carrier is pointed at descriptors the engine already owns, so the
-- template's resources must already be resident. In practice the template is the armor
-- the observing client is itself wearing, which guarantees residency.
--
-- Delete this module once notes/runtime-evidence-cmog-remote/verification.md is recorded.
local Layout=GameCustomizationLayout or error('module is not bundled: src.game.customization_layout')
local Players,Map,Infos,Info=Layout.players,Layout.player_map,Layout.slot_infos,Layout.slot_info
local Equipment,Request,Cache=Layout.equipment,Layout.request,Layout.cache
local Session,Bucket,Owner=Layout.session,Layout.loadout_bucket,Layout.loadout_owner
local Catalog=GameCatalogLayout or error('module is not bundled: src.game.catalog_layout')
local Array,Object,Kit=Catalog.array,Catalog.object,Catalog.kit
local M={}
local function u32(s,o)
 if type(s)~='string' or #s<o+4 then return nil end
 local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216
end
local function ptr(s,o)
 o=o or 0;local lo,hi=u32(s,o),u32(s,o+4)
 if not hi or hi>=32768 then return nil end
 local n=lo+hi*4294967296;return n>=65536 and n or nil
end
local function hex(s)return(s:gsub('.',function(c)return string.format('%02x',c:byte())end))end
local function id8(n)return string.format('%08x',n)end

local CATEGORY=Catalog.category
local SLOT_OF={[CATEGORY.armor]='armor',[CATEGORY.helmet]='helmet',[CATEGORY.cape]='cape'}

-- Display only. Never ownership, never identity.
local function label(data,labels,item_id)
 local kit=data and data.kits and data.kits[item_id]
 if not kit then return 'unknown' end
 local name=labels and labels.strings and labels.strings[kit.name_cased]
 return name or kit.id or 'unnamed'
end
local function carrier_note(binding,data,item_id)
 local kit=data and data.kits and data.kits[item_id]
 if not (kit and binding and binding.bound) then return '' end
 local bound=binding.bound[kit.id]
 return bound and (' {carrier:'..tostring(bound.id)..'}') or ''
end

-- The object behind bridge.armor_catalog is both the catalog header (the kit
-- array) and the customization manager (the player map onward), exactly as
-- clothing_binding.lua and customization_raw_probe.lua each resolve it.
function M.observe(bridge,data,labels,binding)
 assert(type(bridge)=='table' and type(bridge.read)=='function' and type(bridge.verify)=='function',
  'verified read bridge required')
 -- A live session mutates peer records while we read; retry for a coherent snapshot
 -- rather than relaxing the stability assertion itself.
 local ok,result
 for attempt=1,12 do
  ok,result=pcall(function()return M.attempt(bridge,data,labels,binding)end)
  if ok then result.attempts=attempt;break end
  if not tostring(result):find('during observation',1,true) then break end
 end
 if not ok then return nil,tostring(result) end
 return result
end

function M.attempt(bridge,data,labels,binding)
 assert(bridge.verify(),'customization compatibility changed')
 assert(type(bridge.players)=='number','local-player signature unavailable')
 local watches={}
 local function watch(at,n)
  assert(#watches<64,'customization read budget exceeded')
  assert(type(at)=='number' and at%1==0 and at>=65536 and n>0 and n<=128,'customization read bounds rejected')
  local s=bridge.read(at,n);assert(type(s)=='string' and #s==n,'customization data unavailable')
  watches[#watches+1]={at=at,bytes=s};return s
 end
 local manager=assert(ptr(watch(bridge.armor_catalog,8),0),'customization manager unavailable')
 local players=assert(ptr(watch(bridge.players,8),0),'players manager unavailable')
 local counts=watch(players+Players.counts.at,Players.counts.size);local total,locals=u32(counts,Players.counts.total),u32(counts,Players.counts.locals)
 assert(total>=1 and total<=Players.max_total,'implausible player count')
 local player=assert(ptr(watch(players+Players.first_local,8),0),'local player unavailable')
 local local_id=u32(watch(player+Layout.player.id,4),0)

 -- player_id -> slot, inverted so each occupied slot can be attributed to a player.
 local map=watch(manager+Map.at,Map.size)
 local entries,capacity,empty=ptr(map,Map.entries),u32(map,Map.capacity),u32(map,Map.empty_key)
 local owner={}
 if entries and capacity and capacity>=1 and capacity<=4096 then
  for i=0,math.min(capacity,64)-1 do
   local row=watch(entries+i*Map.row.size,Map.row.size);local key,value=u32(row,Map.row.player_id),u32(row,Map.row.slot)
   if key~=empty and value and value<Layout.slot_count then owner[value]=key end
  end
 end

 local slots={}
 for index=0,Layout.slot_count-1 do
  local info=ptr(watch(manager+Infos.base+index*Infos.stride,8))
  local entity=info and u32(watch(info+Info.entity,4),0) or nil
  local record=info and watch(manager+Cache.base+index*Cache.stride,Cache.stride) or nil
  slots[index]={present=info~=nil,entity=entity,live=entity~=nil and entity~=Info.entity_not_live,
   player_id=owner[index],record=record}
 end

 for _,w in ipairs(watches)do
  assert(bridge.read(w.at,#w.bytes)==w.bytes,'customization changed during observation')
 end
 assert(bridge.verify(),'customization compatibility changed during observation')
 return {total=total,locals=locals,local_id=local_id,slots=slots,data=data,labels=labels,binding=binding}
end

function M.format(r)
 if type(r)~='table' then return 'HD2TM_CLOTHING_OBSERVER 1\nstatus=unavailable\n' end
 local out={'HD2TM_CLOTHING_OBSERVER 1','read_only=true',
  'players_total='..r.total,'players_local='..r.locals,'local_player_id='..id8(r.local_id),
  'read_attempts='..tostring(r.attempts or 1)}
 for index=0,Layout.slot_count-1 do
  local s=r.slots[index]
  if not s.present then
   out[#out+1]=string.format('slot%d present=false',index)
  else
   local rec=s.record
   local body,helmet,cape,armor=u32(rec,Equipment.body_type),u32(rec,Equipment.helmet),u32(rec,Equipment.cape),u32(rec,Equipment.armor)
   local is_local=s.player_id~=nil and s.player_id==r.local_id
   out[#out+1]=string.format('slot%d present=true live=%s local=%s entity=%s player_id=%s body=%s passive=%s torso=%s',
    index,tostring(s.live),tostring(is_local),
    s.entity and id8(s.entity) or 'none',s.player_id and id8(s.player_id) or 'unmapped',
    tostring(body),tostring(u32(rec,Cache.armor_passive)),tostring(u32(rec,Cache.torso_class)))
   for _,piece in ipairs({{'armor',armor},{'helmet',helmet},{'cape',cape}})do
    out[#out+1]=string.format('slot%d.%s=%s [%s]%s',index,piece[1],id8(piece[2]),
     label(r.data,r.labels,piece[2]),carrier_note(r.binding,r.data,piece[2]))
   end
  end
 end
 -- What this client currently believes it has bound, so a capture is self-describing.
 if r.binding and r.binding.bound then
  local ids={};for key in pairs(r.binding.bound)do ids[#ids+1]=key end;table.sort(ids)
  for _,key in ipairs(ids)do
   local item=r.binding.bound[key]
   out[#out+1]=string.format('bound %s slot=%s carrier=%s',tostring(item.id),tostring(item.slot),tostring(key))
  end
 end
 for _,line in ipairs(M.rebind_state())do out[#out+1]=line end
 out[#out+1]='status=observed'
 return table.concat(out,'\n')..'\n'
end

-- Session state for the rebind experiment. `original` is the carrier's bytes as this
-- mod bound them, captured once, so revert restores exactly that and nothing else.
local rebound={}

function M.rebind_state()
 local keys={};for key in pairs(rebound)do keys[#keys+1]=key end;table.sort(keys)
 local out={}
 for _,key in ipairs(keys)do
  local entry=rebound[key]
  out[#out+1]=string.format('rebound carrier=%s template=%s applied=%s',key,entry.template,tostring(entry.applied))
 end
 return out
end

-- Walk the native catalog array once and return {item_id -> {at=,raw=}} for the ids asked for.
local function records(bridge,wanted)
 assert(bridge.verify(),'catalog signature changed')
 local slot=bridge.read(bridge.armor_catalog,8);local cat=assert(ptr(slot,0),'catalog unavailable')
 local head=bridge.read(cat+Object.entries,Array.head);local first,n=ptr(head,Array.pointer),u32(head,Array.count)
 assert(first and n and n>0 and n<=Object.max_entries,'catalog bounds changed')
 local array=bridge.read(first,n*Object.entry_stride);local found={}
 for i=0,n-1 do
  local at=assert(ptr(array,i*Object.entry_stride),'catalog entry unavailable')
  local raw=bridge.read(at,Kit.size);local id=u32(raw,Kit.id)
  if wanted[id] then
   assert(not found[id],'ambiguous native catalog');found[id]={at=at,raw=raw}
  end
 end
 return found,{slot=slot,cat=cat,head=head,first=first,n=n,array=array}
end

-- args: '<slot> <template8>' to rebind, or 'revert' to restore every rebound carrier.
function M.rebind(bridge,writer,data,binding,args)
 local ok,result=pcall(function()
  assert(type(writer)=='table' and type(writer.write)=='function','writer required')
  assert(binding and binding.phase=='ready' and binding.bound,'clothing binding is not ready')
  args=type(args)=='string' and args:match('^%s*(.-)%s*$') or ''
  if args=='revert' then return M.revert(bridge,writer) end

  local slot,template_hex=args:match('^(%a+)%s+(%x+)$')
  assert(slot and CATEGORY[slot],'expected "<armor|helmet|cape> <template8>" or "revert"')
  assert(#template_hex==8,'template must be an eight-digit native id')
  local template_id=tonumber(template_hex,16)

  -- The carrier is the home of the one piece installed for that slot (pool
  -- records are nobody's home).
  local carrier_key,carrier_item
  for key,item in pairs(binding.bound)do
   if item.slot==slot and not item.spare then
    assert(not carrier_key,'more than one piece is installed for this slot');carrier_key,carrier_item=key,item
   end
  end
  assert(carrier_key,'no clothing is bound in the '..slot..' slot')
  local carrier_id
  for item_id,kit in pairs(data.kits)do if kit.id==carrier_key then carrier_id=item_id;break end end
  assert(carrier_id,'bound carrier is absent from the reference catalog')

  local template=assert(data.kits[template_id],'template missing from the reference catalog')
  assert(template.category==CATEGORY[slot],'template category differs from the slot')
  assert(carrier_id~=template_id,'template and carrier are the same record')

  local found=records(bridge,{[carrier_id]=true,[template_id]=true})
  local carrier=assert(found[carrier_id],'carrier record missing from the native catalog')
  local source=assert(found[template_id],'template record missing from the native catalog')

  -- The template's own descriptor field: pointer, body count, zero. Copying it verbatim
  -- points the carrier at descriptors the engine already owns and keeps alive.
  local replacement=source.raw:sub(Kit.bodies+1,Kit.size)
  assert(ptr(replacement,Array.pointer),'template descriptor pointer rejected')
  assert(u32(replacement,Array.count)==#template.bodies and u32(replacement,Array.count_high)==0,
   'template body count differs from the reference catalog')

  local before=carrier.raw:sub(Kit.bodies+1,Kit.size)
  local entry=rebound[carrier_key]
  if entry then
   assert(before==entry.current,'carrier descriptors changed since the last rebind')
  else
   entry={original=before,carrier_id=carrier_id,name=carrier_item.id};rebound[carrier_key]=entry
  end
  if before==replacement then
   entry.template,entry.current,entry.applied=template_hex,replacement,true
   return 'carrier='..carrier_key..' template='..template_hex..' unchanged=true'
  end

  assert(bridge.verify() and bridge.read(carrier.at,Kit.size)==carrier.raw,'catalog changed before rebind')
  local wrote=writer.write(carrier.at+Kit.bodies,replacement)==true
  local after=bridge.read(carrier.at+Kit.bodies,Array.size)
  if not wrote or after~=replacement then
   -- Same attributable-recovery rule as clothing_binding.lua: only restore bytes that
   -- are explainable as ours, and only if nothing else has moved underneath.
   local attributable=after~=before
   for i=1,Array.size do
    if after:byte(i)~=before:byte(i) and after:byte(i)~=replacement:byte(i) then attributable=false end
   end
   if attributable and bridge.verify() and bridge.read(carrier.at+Kit.bodies,Array.size)==after then
    assert(writer.write(carrier.at+Kit.bodies,before)==true and bridge.read(carrier.at+Kit.bodies,Array.size)==before,
     'carrier descriptor recovery required')
   end
   if not entry.applied then rebound[carrier_key]=nil end
   error('carrier descriptor write/readback failed')
  end
  entry.template,entry.current,entry.applied,entry.at=template_hex,replacement,true,carrier.at
  return table.concat({'carrier='..carrier_key,'clothing='..tostring(carrier_item.id),
   'template='..template_hex..' ['..label(data,nil,template_id)..']',
   'wrote='..hex(replacement),'readback='..hex(after),'match=true',
   'note=observer must not open the Armory while rebound; revert first'},'\n')
 end)
 if not ok then return nil,tostring(result) end
 return result
end

-- THROWAWAY SPIKE (2026-09-30): can the observer rebuild a peer's actor itself?
-- Writes the four bytes of ONE remote slot's requested armor in this client's
-- own customization manager -- the field the network layer writes when the
-- peer's equipment replicates -- and lets `read` show whether the cache block
-- (what the actor was last built with) follows. Nothing leaves this machine.
-- The local slot is refused (the headless refresh owns it); absent and dead
-- slots are refused; the original is kept for `restore`; a write that does not
-- read back is recovered when the bytes are attributable to us.
local poked={}        -- slot -> field -> {original=,at=}
local FIELDS={helmet=Equipment.helmet,cape=Equipment.cape,armor=Equipment.armor}
local function p32(n)local r={};for i=1,4 do r[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(r)end
local function slots_of(bridge)
 assert(bridge.verify(),'customization compatibility changed')
 local manager=assert(ptr(bridge.read(bridge.armor_catalog,8),0),'customization manager unavailable')
 local players=assert(ptr(bridge.read(bridge.players,8),0),'players manager unavailable')
 local counts=bridge.read(players+Players.counts.at,Players.counts.size)
 assert(u32(counts,Players.counts.locals)==1,'exactly one local player required')
 local player=assert(ptr(bridge.read(players+Players.first_local,8),0),'local player unavailable')
 local player_id=u32(bridge.read(player+Layout.player.id,4),0)
 local map=bridge.read(manager+Map.at,Map.size)
 local entries,capacity,empty,multiplier=ptr(map,Map.entries),u32(map,Map.capacity),u32(map,Map.empty_key),u32(map,Map.multiplier)
 assert(entries and capacity>=1 and capacity<=4096,'player lookup capacity rejected')
 local start=Map.start(player_id,capacity,multiplier)
 local local_slot
 for probe=0,math.min(capacity,64)-1 do
  local row=bridge.read(entries+((start+probe)%capacity)*Map.row.size,Map.row.size)
  local key=u32(row,Map.row.player_id)
  if key==player_id then local_slot=u32(row,Map.row.slot);break end
  if key==empty then break end
 end
 assert(local_slot and local_slot<Layout.slot_count,'local customization slot unavailable')
 return manager,local_slot
end
local function slot_state(bridge,manager,slot)
 local info=ptr(bridge.read(manager+Infos.base+slot*Infos.stride,8))
 local entity=info and u32(bridge.read(info+Info.entity,4),0) or nil
 local request=bridge.read(manager+Request.base+slot*Request.stride,Equipment.size)
 local cache=bridge.read(manager+Cache.base+slot*Cache.stride,Equipment.size)
 local out={present=info~=nil,live=entity~=nil and entity~=Info.entity_not_live,request={},cache={},at={}}
 for field,offset in pairs(FIELDS)do
  out.request[field]=u32(request,offset);out.cache[field]=u32(cache,offset)
  out.at[field]=manager+Request.base+slot*Request.stride+offset
 end
 return out
end
local function triple(t)return id8(t.armor)..'/'..id8(t.helmet)..'/'..id8(t.cape)end
function M.poke_request(bridge,writer,args)
 local ok,result=pcall(function()
  assert(type(writer)=='table' and type(writer.write)=='function','writer required')
  args=type(args)=='string' and args:match('^%s*(.-)%s*$') or ''
  local manager,local_slot=slots_of(bridge)
  if args=='restore' then
   local keys={};for slot in pairs(poked)do keys[#keys+1]=slot end;table.sort(keys)
   assert(#keys>0,'nothing has been poked this session')
   local lines={}
   for _,slot in ipairs(keys)do
    for _,field in ipairs({'armor','helmet','cape','cache'})do
     local entry=poked[slot][field]
     if entry then
      assert(writer.write(entry.at,p32(entry.original))==true and bridge.read(entry.at,4)==p32(entry.original),'requested '..field..' restore failed')
      lines[#lines+1]=string.format('slot=%d %s restored=%s',slot,field,id8(entry.original))
     end
    end
    poked[slot]=nil
   end
   return table.concat(lines,'\n')
  end
  local usage='expected "<slot> [armor|helmet|cape] <id8>", "local cache <id8>", "read <slot>" or "restore"'
  -- Spike: the LOCAL slot's cache armor, never its request (which replicates).
  local cache_hex=args:match('^local%s+cache%s+(%x+)$')
  if cache_hex then
   assert(#cache_hex==8,'armor must be an eight-digit native id')
   local seen=slot_state(bridge,manager,local_slot)
   local at=manager+Cache.base+local_slot*Cache.stride+Equipment.armor
   local before=bridge.read(at,4);assert(u32(before,0)==seen.cache.armor,'cached armor changed during observation')
   local want=p32(tonumber(cache_hex,16))
   poked[local_slot]=poked[local_slot]or{}
   local entry=poked[local_slot].cache or{original=seen.cache.armor,at=at}
   assert(writer.write(at,want)==true and bridge.read(at,4)==want,'cached armor write/readback failed')
   poked[local_slot].cache=entry
   return string.format('slot=%d cache_armor=%s>%s request_armor=%s original=%s\nnote=read the slot again: request unchanged and cache back on it means the game re-streamed from our write',
    local_slot,id8(seen.cache.armor),cache_hex,id8(seen.request.armor),id8(entry.original))
  end
  assert(not args:match('^local'),'refusing the local slot: the headless refresh owns it (only "local cache <id8>" is allowed)')
  local mode,slot_text,field,id_hex=args:match('^(%a*)%s*(%d)%s*(%a*)%s*(%S*)$')
  assert(slot_text,usage)
  local slot=tonumber(slot_text)
  assert(slot>=0 and slot<Layout.slot_count,'slot must be 0-3')
  local seen=slot_state(bridge,manager,slot)
  assert(seen.present,'slot '..slot..' is not present')
  if mode=='read' then
   return string.format('slot=%d live=%s request=%s cache=%s followed=%s request_armor=%s cache_armor=%s',slot,tostring(seen.live),
    triple(seen.request),triple(seen.cache),tostring(triple(seen.request)==triple(seen.cache)),id8(seen.request.armor),id8(seen.cache.armor))
  end
  assert(mode=='',usage)
  if not FIELDS[field]and id_hex==''then id_hex=field;field='armor'end -- "<slot> <id8>" means the armor
  if field=='' then field='armor' end
  assert(FIELDS[field],'field must be armor, helmet or cape')
  assert(slot~=local_slot,'refusing the local slot: the headless refresh owns it')
  assert(seen.live,'slot '..slot..' is not live')
  assert(#id_hex==8 and id_hex:match('^%x+$'),field..' must be an eight-digit native id')
  local id=tonumber(id_hex,16)
  local at=seen.at[field]
  local before=bridge.read(at,4)
  assert(u32(before,0)==seen.request[field],'requested '..field..' changed during observation')
  local want=p32(id)
  poked[slot]=poked[slot]or{}
  local entry=poked[slot][field]or{original=seen.request[field],at=at}
  local wrote=writer.write(at,want)==true
  local after=bridge.read(at,4)
  if not wrote or after~=want then
   local attributable=after~=before
   for i=1,4 do if after:byte(i)~=before:byte(i) and after:byte(i)~=want:byte(i) then attributable=false end end
   if attributable and bridge.read(at,4)==after then
    assert(writer.write(at,before)==true and bridge.read(at,4)==before,'requested '..field..' recovery required')
   end
   if next(poked[slot])==nil then poked[slot]=nil end
   error('requested '..field..' write/readback failed')
  end
  poked[slot][field]=entry
  return string.format('slot=%d request_%s=%s>%s cache_%s=%s original=%s\nnote=read the slot again in a few seconds: followed=true means the game rebuilt from our write',
   slot,field,id8(seen.request[field]),id_hex,field,id8(seen.cache[field]),id8(entry.original))
 end)
 if not ok then return nil,tostring(result) end
 return result
end

-- READ-ONLY SPIKE (2026-09-30): which customization slot is which lobby member?
-- The link speaks SteamIDs; the manager speaks player ids that differ per
-- machine. The game keeps an 8-byte peer token per loadout slot (in the loadout
-- owner) and one for the local player (in the session). If
-- those are SteamID64s the mapping is a read. `members` are the 16-hex ids the
-- link knows (self first); the session object is scanned for each of them too.
local function id64_hex(raw)
 local out={};for i=8,1,-1 do out[#out+1]=string.format('%02x',raw:byte(i))end;return table.concat(out)
end
function M.session_peers(ui,members)
 local ok,result=pcall(function()
  assert(type(ui)=='table'and type(ui.read)=='function'and type(ui.session_global)=='number'and type(ui.manager_global)=='number','ui bridge required')
  assert(ui.verify==nil or ui.verify(),'ui compatibility changed')
  local known={};for _,id in ipairs(members or{})do if type(id)=='string'and #id==16 then known[id:lower()]=true end end
  local session=assert(ptr(ui.read(ui.session_global,8),0),'session unavailable')
  local lines={}
  local local_peer=id64_hex(ui.read(session+Session.local_peer,Session.peer_size))
  lines[#lines+1]='local_peer='..local_peer..' steamid='..tostring(known[local_peer]==true)
  local window=ui.read(session+Session.scan.base,Session.scan.span)
  for id in pairs(known)do
   local raw={};for i=8,1,-1 do raw[#raw+1]=string.char(tonumber(id:sub(i*2-1,i*2),16))end;raw=table.concat(raw)
   local at=1
   while true do
    local hit=window:find(raw,at,true);if not hit then break end
    lines[#lines+1]=string.format('session+0x%x=%s',Session.scan.base+hit-1,id);at=hit+1
   end
  end
  local bucket=ui.read(ui.manager_global,8)
  local manager=ptr(bucket,0)
  local reg=manager and ui.read(manager+Bucket.at,Bucket.size)
  local owner=reg and u32(reg,Bucket.at_0x00)==Bucket.at_0x00_active and u32(reg,Bucket.type)==Bucket.type_loadout and ptr(reg,Bucket.owner)or nil
  if owner then
   for slot=0,Owner.slot_count-1 do
    local token=id64_hex(ui.read(owner+slot*Owner.slot_stride+Owner.peer,Owner.peer_size))
    lines[#lines+1]=string.format('loadout slot=%d peer=%s steamid=%s',slot,token,tostring(known[token]==true))
   end
  else lines[#lines+1]='loadout=inactive'end
  return table.concat(lines,'\n')
 end)
 if not ok then return nil,tostring(result)end
 return result
end

function M.revert(bridge,writer)
 local keys={};for key in pairs(rebound)do keys[#keys+1]=key end;table.sort(keys)
 assert(#keys>0,'nothing has been rebound this session')
 assert(bridge.verify(),'catalog signature changed')
 local wanted={};for _,key in ipairs(keys)do wanted[rebound[key].carrier_id]=true end
 local found=records(bridge,wanted)
 local lines={}
 for _,key in ipairs(keys)do
  local entry=rebound[key]
  local record=assert(found[entry.carrier_id],'carrier record missing from the native catalog')
  local now=record.raw:sub(Kit.bodies+1,Kit.size)
  if now==entry.original then
   lines[#lines+1]='carrier='..key..' already_original=true'
  else
   assert(now==entry.current,'carrier descriptors changed since the last rebind')
   assert(writer.write(record.at+Kit.bodies,entry.original)==true
    and bridge.read(record.at+Kit.bodies,Array.size)==entry.original,'carrier descriptor restore failed')
   lines[#lines+1]='carrier='..key..' restored=true bytes='..hex(entry.original)
  end
  entry.current,entry.applied=entry.original,false
 end
 return table.concat(lines,'\n')
end
return M

end)()
local SteamProbe = (function()
-- THROWAWAY FEASIBILITY PROBE -- read-only Steam API introspection.
-- Answers three questions and nothing else:
--   1. can the addon sandbox reach the already-loaded steam_api64 in-process?
--   2. is there a live Steam user, and is this really app 553850?
--   3. does the running game maintain a Steam LOBBY we could attach data to?
-- It calls getters only. It never sets lobby data, never opens a P2P session and
-- never sends a packet, so it originates no network traffic whatsoever.
-- Delete this module once the feasibility question is recorded.
local M={}

local INTERFACES={
 user='SteamAPI_SteamUser_v021',
 friends='SteamAPI_SteamFriends_v017',
 matchmaking='SteamAPI_SteamMatchmaking_v009',
 utils='SteamAPI_SteamUtils_v010',
}

local function declare(ffi)
 -- Flat Steam API. CSteamID crosses the boundary as a plain uint64.
 for _,decl in ipairs({
  'typedef struct ISteamUser ISteamUser;',
  'typedef struct ISteamFriends ISteamFriends;',
  'typedef struct ISteamMatchmaking ISteamMatchmaking;',
  'typedef struct ISteamUtils ISteamUtils;',
  'typedef struct { uint64_t m_gameID; uint32_t m_unGameIP; uint16_t m_usGamePort; uint16_t m_usQueryPort; uint64_t m_steamIDLobby; } FriendGameInfo_t;',
  'ISteamUser * SteamAPI_SteamUser_v021(void);',
  'ISteamFriends * SteamAPI_SteamFriends_v017(void);',
  'ISteamMatchmaking * SteamAPI_SteamMatchmaking_v009(void);',
  'ISteamUtils * SteamAPI_SteamUtils_v010(void);',
  'uint64_t SteamAPI_ISteamUser_GetSteamID(ISteamUser*);',
  'uint32_t SteamAPI_ISteamUtils_GetAppID(ISteamUtils*);',
  'const char * SteamAPI_ISteamFriends_GetPersonaName(ISteamFriends*);',
  'bool SteamAPI_ISteamFriends_GetFriendGamePlayed(ISteamFriends*, uint64_t, FriendGameInfo_t*);',
  'int SteamAPI_ISteamMatchmaking_GetNumLobbyMembers(ISteamMatchmaking*, uint64_t);',
  'uint64_t SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex(ISteamMatchmaking*, uint64_t, int);',
  'const char * SteamAPI_ISteamMatchmaking_GetLobbyMemberData(ISteamMatchmaking*, uint64_t, uint64_t, const char*);',
  'int SteamAPI_ISteamMatchmaking_GetLobbyDataCount(ISteamMatchmaking*, uint64_t);',
  'void SteamAPI_ISteamMatchmaking_SetLobbyMemberData(ISteamMatchmaking*, uint64_t, const char*, const char*);',
 })do pcall(ffi.cdef,decl) end
end

-- uint64 cdata -> 16-digit hex. tostring() on these cdata is unreliable and a
-- Lua number cannot hold a SteamID64 exactly, so split into 32-bit halves.
local function u64(value)
 local ffi=require('ffi')
 local n=ffi.cast('uint64_t',value)
 local hi=tonumber(n/ffi.cast('uint64_t',4294967296))
 local lo=tonumber(n%ffi.cast('uint64_t',4294967296))
 return string.format('%08x%08x',hi,lo)
end
local function is_zero(text) return text=='0000000000000000' end

function M.sample()
 local ok,result=pcall(function()
  local ffi=require('ffi')
  declare(ffi)
  -- Already resident in the process; this resolves the loaded module.
  local steam=ffi.load('steam_api64')
  local lines={}
  local function add(k,v) lines[#lines+1]=k..'='..tostring(v) end

  for name,symbol in pairs(INTERFACES) do
   local present=pcall(function() return steam[symbol] end)
   add('interface.'..name,present and symbol or 'unavailable')
  end

  local utils=steam.SteamAPI_SteamUtils_v010()
  add('utils.pointer',utils~=nil)
  if utils~=nil then add('app_id',steam.SteamAPI_ISteamUtils_GetAppID(utils)) end

  local user=steam.SteamAPI_SteamUser_v021()
  add('user.pointer',user~=nil)
  local self_id
  if user~=nil then
   self_id=steam.SteamAPI_ISteamUser_GetSteamID(user)
   add('steam_id',u64(self_id))
  end

  local friends=steam.SteamAPI_SteamFriends_v017()
  add('friends.pointer',friends~=nil)
  if friends~=nil then
   local name=steam.SteamAPI_ISteamFriends_GetPersonaName(friends)
   add('persona',name~=nil and ffi.string(name) or 'unavailable')
  end

  -- The decisive question: does the running game keep a Steam lobby?
  local lobby
  if friends~=nil and self_id~=nil then
   local info=ffi.new('FriendGameInfo_t[1]')
   local got=steam.SteamAPI_ISteamFriends_GetFriendGamePlayed(friends,self_id,info)
   add('game_played.reported',got and true or false)
   if got then
    add('game_played.game_id',u64(info[0].m_gameID))
    lobby=info[0].m_steamIDLobby
    add('lobby.id',u64(lobby))
    add('lobby.present',not is_zero(u64(lobby)))
   end
  end

  local mm=steam.SteamAPI_SteamMatchmaking_v009()
  add('matchmaking.pointer',mm~=nil)
  if mm~=nil and lobby~=nil and not is_zero(u64(lobby)) then
   local mine=steam.SteamAPI_ISteamMatchmaking_GetLobbyMemberData(mm,lobby,self_id,'hd2tm')
   add('lobby.self.hd2tm',mine~=nil and ('"'..ffi.string(mine)..'"') or 'null')
   local n=steam.SteamAPI_ISteamMatchmaking_GetNumLobbyMembers(mm,lobby)
   add('lobby.members',n)
   add('lobby.data_keys',steam.SteamAPI_ISteamMatchmaking_GetLobbyDataCount(mm,lobby))
   for i=0,math.min(n,4)-1 do
    local member=steam.SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex(mm,lobby,i)
    add('lobby.member'..i,u64(member))
    -- Read-only check that member data is reachable for a key we never set.
    local probe=steam.SteamAPI_ISteamMatchmaking_GetLobbyMemberData(mm,lobby,member,'hd2tm')
    add('lobby.member'..i..'.hd2tm',probe~=nil and ('"'..ffi.string(probe)..'"') or 'null')
   end
  end
  return table.concat(lines,'\n')
 end)
 if not ok then return nil,tostring(result) end
 return result
end

-- THROWAWAY WRITE TEST. Publishes one namespaced key on THIS user's own lobby member
-- record. SetLobbyMemberData can only ever write the calling user's own member data, so
-- a peer's record is unreachable by construction. Lobby-level keys (the game owns 22 of
-- them) are never touched. Value is bounded printable ASCII and always read back.
local KEY='hd2tm'
function M.publish(args)
 local ok,result=pcall(function()
  local mode,value
  if args=='clear' or args=='' or args==nil then mode,value='clear',''
  else
   local v=args:match('^set%s+(.+)$')
   assert(v,"payload must be 'set <value>' or 'clear'")
   assert(#v<=256,'value exceeds 256 bytes')
   assert(v:match('^[%w%-%._:/]+$'),'value must be printable ASCII without spaces')
   mode,value='set',v
  end
  local ffi=require('ffi')
  declare(ffi)
  local steam=ffi.load('steam_api64')
  local friends=assert(steam.SteamAPI_SteamFriends_v017(),'friends interface unavailable')
  local user=assert(steam.SteamAPI_SteamUser_v021(),'user interface unavailable')
  local mm=assert(steam.SteamAPI_SteamMatchmaking_v009(),'matchmaking interface unavailable')
  local self_id=steam.SteamAPI_ISteamUser_GetSteamID(user)
  local info=ffi.new('FriendGameInfo_t[1]')
  assert(steam.SteamAPI_ISteamFriends_GetFriendGamePlayed(friends,self_id,info),'no game session reported')
  local lobby=info[0].m_steamIDLobby
  assert(not is_zero(u64(lobby)),'no Steam lobby present; join or wait for one')
  steam.SteamAPI_ISteamMatchmaking_SetLobbyMemberData(mm,lobby,KEY,value)
  local back=steam.SteamAPI_ISteamMatchmaking_GetLobbyMemberData(mm,lobby,self_id,KEY)
  back=back~=nil and ffi.string(back) or 'null'
  return table.concat({'mode='..mode,'lobby='..u64(lobby),'key='..KEY,
   'wrote="'..value..'"','readback="'..back..'"',
   'match='..tostring(back==value)},'\n')
 end)
 if not ok then return nil,tostring(result) end
 return result
end

-- THROWAWAY LINK TEST. Continuous ping-pong over Steam lobby member data so we can
-- measure whether the channel is present, how fast it propagates and whether it stalls.
-- Each side publishes only its OWN member key: "v1-<id6>-<seq>-<ack>", where <ack> echoes
-- the highest sequence it has seen from the peer. A matching echo proves a full round trip.
function M.format(text)
 return 'HD2TRANSMOG_STEAM_PROBE 1\n'..(text or 'status=unavailable')..'\nstatus=observed\n'
end
return M

end)()
local PixelProbe = (function()
-- THROWAWAY PROBE (2026-10-01): can an Armory thumbnail be saved to disk and loaded back?
-- Loaded with the mod at launch; does nothing without the debug marker and a command file.
--
-- Reads the game's working thumbnail atlas back from the GPU, writes it and one
-- 240x240 tile to disk, loads the tile from disk into a new texture through
-- the engine's own RGBA producer, and reads that texture back to compare it
-- byte for byte. Times every step. Binds nothing to the UI and changes no game
-- state: the only native calls are the readback (request/done/take/free), the
-- engine allocator and the texture producer, each behind the same instruction
-- and API-table checks Armory Preview Cache's retired pixel path used
-- (ArmoryPreviewCache/src/pixel_native.lua, pixel_signatures.lua).
--
-- Driven by a command file so every native call is asked for deliberately:
--   <LOCALAPPDATA>\CowboyBingus\Helldivers2\Transmog\probe-pixels.cmd
--     status            check the build and describe the atlas (no native call)
--     run               run probe-pixels.lua from the same folder (engine Lua API experiments)
--     dump              write the code around the readback calls to disk (no native call)
--     readback [n]      n readbacks of the working atlas; the first is saved
--     upload [n]        n uploads of the saved tile, each verified by readback
--     upload_atlas      one upload of the saved full atlas, verified
-- Report: probe-pixels.txt in the same folder (appended, newest last).
local M = {}
local impl, disabled
local function start()
  local ffi = require('ffi')
  local bit = require('bit')

  local DIR = (os.getenv('LOCALAPPDATA') or '.') .. '\\CowboyBingus\\Helldivers2\\Transmog\\'
  local CMD, REPORT = DIR .. 'probe-pixels.cmd', DIR .. 'probe-pixels.txt'
  local ATLAS_FILE, TILE_FILE = DIR .. 'probe-pixels-atlas.rgba', DIR .. 'probe-pixels-tile.rgba'
  local TILE = 240
  local UPLOAD_CAP = 8            -- uploaded payloads are never freed: same cap as the retired path

  pcall(ffi.cdef, [[
    void *GetModuleHandleA(const char *name);
    void *GetCurrentProcess(void);
    int ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);
    int QueryPerformanceCounter(int64_t *count);
    int QueryPerformanceFrequency(int64_t *frequency);
  ]])
  local kernel = ffi.load('kernel32')
  local process = kernel.GetCurrentProcess()
  local qpc, qpf = ffi.new('int64_t[1]'), ffi.new('int64_t[1]')
  kernel.QueryPerformanceFrequency(qpf)
  local function now_ms() kernel.QueryPerformanceCounter(qpc); return tonumber(qpc[0]) * 1000 / tonumber(qpf[0]) end

  local function read(address, size)
    local buffer, count = ffi.new('uint8_t[?]', size), ffi.new('size_t[1]')
    assert(kernel.ReadProcessMemory(process, address, buffer, size, count) ~= 0 and count[0] == size, 'memory unreadable')
    return ffi.string(buffer, size)
  end
  local word = ffi.new('uint32_t[1]')
  local function u32(s, o) ffi.copy(word, s:sub(o + 1, o + 4), 4); return tonumber(word[0]) end
  local function pointer(bytes, offset)
    offset = offset or 0
    local value = ffi.new('uintptr_t[1]'); ffi.copy(value, bytes:sub(offset + 1, offset + 8), 8)
    if value[0] < 0x10000 or value[0] >= 0x800000000000 then return nil end
    return ffi.cast('uint8_t *', value[0])
  end
  local function ptr(address) return pointer(read(address, 8)) end

  local SIGNATURES = {
    {rva=0x31b500,hex='48895c240848896c241048897424185741544155415641574883ec50488b05e5'},
    {rva=0x31ba70,hex='488b0571476f018bd1488b4808488b04d10fb64018c3cccccccccccccccccccc'},
    {rva=0x31bab0,hex='40534883ec208bc2488bd94c8d0cc500000000488b051e476f01488b5008498b'},
    {rva=0x31bb20,hex='40534883ec20488bd94533c0488b0dcd466f01488b5310488b01ff504048c743'},
    {rva=0x31e740,hex='48895c240848896c241056574154415641574883ec50488b1dab1a6f014d8bf9'},
    {rva=0x5c2e10,hex='48895c2408574883ec30488bfa488bd94d85c0751733c048890248894208488b'},
    {rva=0x5c2ed0,hex='4885d274554889742410574883ec20488bf248895c2430488bf948c7c0ffffff'},
  }

  local lines = {}
  local function say(text)
    lines[#lines + 1] = os.date('%H:%M:%S ') .. text
    local h = io.open(REPORT, 'a'); if h then h:write(lines[#lines] .. '\n'); h:close() end
  end

  -- Everything build-locked is checked here before a single native call.
  local native
  local function resolve()
    if native then return native end
    local game = kernel.GetModuleHandleA('game.dll'); assert(game ~= nil, 'game.dll not loaded'); game = ffi.cast('uint8_t *', game)
    local exe = kernel.GetModuleHandleA(nil); assert(exe ~= nil, 'process module unavailable'); exe = ffi.cast('uint8_t *', exe)
    for _, s in ipairs(SIGNATURES) do
      local bytes = s.hex:gsub('..', function(v) return string.char(tonumber(v, 16)) end)
      assert(read(exe + s.rva, #bytes) == bytes, string.format('instruction mismatch at exe+0x%x: another game build', s.rva))
    end
    local root = assert(ptr(game + 0x3326308), 'API root unreadable'); assert(root == exe + 0x27c8d80, 'API root mismatch')
    local app = assert(ptr(root + 16), 'application API unreadable')
    for offset, rva in pairs({[432]=0x31b500, [456]=0x31ba70, [472]=0x31bab0, [480]=0x31bb20}) do
      assert(ptr(app + offset) == exe + rva, 'application API mismatch at ' .. offset)
    end
    local allocator = assert(ptr(exe + 0x1a10200), 'allocator unreadable'); local vtable = assert(ptr(allocator))
    assert(ptr(vtable + 48) == exe + 0x5c2e10 and ptr(vtable + 64) == exe + 0x5c2ed0, 'allocator mismatch')
    native = {
      game = game, exe = exe, allocator = allocator,
      request = ffi.cast('uint32_t (*)(void *,uint16_t)', exe + 0x31b500),
      done = ffi.cast('uint8_t (*)(uint32_t)', exe + 0x31ba70),
      take = ffi.cast('void *(*)(void *,uint32_t)', exe + 0x31bab0),
      free = ffi.cast('void (*)(void *)', exe + 0x31bb20),
      create = ffi.cast('void *(*)(int,int,int,void *)', exe + 0x31e740),
      allocate = ffi.cast('void *(*)(void *,void *,uint64_t,uint64_t)', exe + 0x5c2e10),
    }
    return native
  end

  -- The working atlas as a texture {handle,id,width,height}, with the manager's state.
  local function atlas()
    local n = resolve()
    local tm = assert(ptr(n.game + 0x347cd80), 'thumbnail manager absent: open the Armory')
    local mb = read(tm, 12176)
    local handle = assert(pointer(mb, 11112), 'no working atlas: open an Armory grid')
    local d = read(handle, 104)
    assert(u32(d, 8) == 0 and u32(d, 12) == 0 and u32(d, 28) == 1 and u32(d, 32) == 1 and d:byte(100) == 1,
      'unsupported thumbnail texture descriptor')
    local w, h = u32(d, 20), u32(d, 24)
    assert(w >= 64 and h >= 64 and w <= 4096 and h <= 16384, 'atlas dimensions out of bounds')
    local states = {}
    for c = 0, 5 do states[#states + 1] = u32(mb, c * 1816 + 1832) .. ':' .. u32(mb, c * 1816 + 1836) end
    return {handle = handle, id = d:sub(1, 8), width = w, height = h},
      string.format('atlas=%dx%d kind=%d active=%08x phase=%d cards(state:items)=%s', w, h, u32(mb, 11052),
        u32(mb, 11064), u32(mb, 11096), table.concat(states, ' '))
  end

  local function checksum(pixels, size)
    local words, sum, blank = ffi.cast('uint32_t *', pixels), 0, 0
    for i = 0, size / 4 - 1 do
      local v = words[i]; sum = (sum + v) % 4294967296
      if v == 0 then blank = blank + 1 end
    end
    return string.format('%08x', sum), blank / (size / 4)
  end

  local function save(path, header, pixels, size)
    local started = now_ms()
    local h = assert(io.open(path, 'wb'), 'cannot write ' .. path)
    h:write(header)
    local at = 0
    while at < size do
      local n = math.min(1048576, size - at)
      h:write(ffi.string(pixels + at, n)); at = at + n
    end
    h:close()
    return now_ms() - started
  end

  local function load(path)
    local started = now_ms()
    local h = assert(io.open(path, 'rb'), 'no saved image yet: run readback first')
    local header = h:read(16); local body = h:read('*a'); h:close()
    assert(header and #header == 16 and header:sub(1, 8) == 'HD2TMPX1', 'not a probe image')
    local w, hh = u32(header, 8), u32(header, 12)
    assert(#body == w * hh * 4, 'truncated probe image')
    return w, hh, body, now_ms() - started
  end
  local function header(w, h)
    local dims = ffi.new('uint32_t[2]', w, h); return 'HD2TMPX1' .. ffi.string(dims, 8)
  end

  -- One job at a time, advanced a step per update.
  local job, queue, uploads, frame = nil, {}, 0, 0
  local kept = {}

  local function begin_readback(texture, label, after)
    local n = resolve()
    assert(read(texture.handle, 8) == texture.id, 'texture identity changed')
    local started = now_ms()
    local id = tonumber(n.request(texture.handle, 0)); assert(id > 0 and id < 65536, 'invalid readback job ' .. tostring(id))
    job = {kind = 'readback', id = id, texture = texture, label = label, started = started, frame = frame,
      request_ms = now_ms() - started, after = after}
  end

  local function step_readback()
    if job.kind == 'lua' then
      local step = job.step
      if frame - job.frame > 3600 then job = nil; error('probe-pixels.lua: still running after 3600 frames') end
      if step() == true then job = nil end
      return
    end
    local n = resolve()
    if frame - job.frame > 600 then local label = job.label; job = nil; error(label .. ': readback not done after 600 frames') end
    if n.done(job.id) == 0 then return end
    local done_ms = now_ms() - job.started
    local data = ffi.new('uint64_t[3]'); n.take(data, job.id)
    local d = ffi.cast('uint32_t *', data)
    local w, h, format = tonumber(d[0]), tonumber(d[1]), tonumber(d[2])
    local pixels = ffi.cast('uint8_t *', data[2])
    local finished = job; job = nil
    local ok, why = pcall(function()
      assert(w == finished.texture.width and h == finished.texture.height and format == 0 and pixels ~= nil,
        string.format('unexpected readback result %dx%d format=%d', w, h, format))
      local size = w * h * 4
      local started = now_ms(); local sum, blank = checksum(pixels, size); local sum_ms = now_ms() - started
      say(string.format('%s: readback ok %dx%d bytes=%d request_ms=%.2f latency_ms=%.1f frames=%d checksum=%s blank=%.0f%% checksum_ms=%.1f',
        finished.label, w, h, size, finished.request_ms, done_ms, frame - finished.frame, sum, blank * 100, sum_ms))
      if finished.after then finished.after(pixels, w, h, size, sum) end
    end)
    n.free(data)
    if not ok then error(why) end
  end

  local function upload(path, label)
    local n = resolve()
    assert(uploads < UPLOAD_CAP, 'upload cap reached for this game session (' .. UPLOAD_CAP .. ')')
    local w, h, body, read_ms = load(path)
    local size = #body
    local started = now_ms()
    local out = ffi.new('void *[3]'); n.allocate(n.allocator, out, size, 8); assert(out[0] ~= nil, 'engine allocation failed')
    ffi.copy(out[0], body, size)
    local copy_ms = now_ms() - started
    started = now_ms()
    local handle = n.create(w, h, 0, out[0]); uploads = uploads + 1
    local create_ms = now_ms() - started
    assert(handle ~= nil, 'texture creation failed'); handle = ffi.cast('uint8_t *', handle)
    local expected = checksum(ffi.cast('const uint8_t *', body), size)
    say(string.format('%s: uploaded %dx%d bytes=%d file_read_ms=%.1f alloc_copy_ms=%.2f create_ms=%.2f uploads=%d/%d',
      label, w, h, size, read_ms, copy_ms, create_ms, uploads, UPLOAD_CAP))
    -- Read the new texture back and compare it with what was on disk.
    begin_readback({handle = handle, id = read(handle, 8), width = w, height = h}, label .. ' verify', function(pixels, _, _, n_bytes, sum)
      local same = ffi.string(pixels, n_bytes) == body
      say(string.format('%s: verify %s (disk=%s texture=%s)', label, same and 'IDENTICAL' or 'DIFFERENT', expected, sum))
    end)
  end

  local function run(command)
    local name, arg = command:match('^(%S+)%s*(%S*)')
    local count = math.max(1, math.min(tonumber(arg) or 1, 50))
    if name == 'dump' then
      -- Read-only: the code around the readback calls and the crash site, and the
      -- atlas descriptor, written to disk to be read offline. No native call.
      local n = resolve()
      for _, range in ipairs({{0x31a000, 0x6000}, {0x6ce000, 0x4000}, {0x55c000, 0x2000}, {0x5b3000, 0x1000}, {0x1651000, 0x1000}}) do
        local parts = {}
        for at = 0, range[2] - 1, 0x1000 do parts[#parts + 1] = read(n.exe + range[1] + at, 0x1000) end
        local h = assert(io.open(DIR .. string.format('probe-pixels-code-%x.bin', range[1]), 'wb'))
        h:write(table.concat(parts)); h:close()
      end
      local ok, texture = pcall(atlas)
      if ok then
        local h = assert(io.open(DIR .. 'probe-pixels-descriptor.bin', 'wb')); h:write(read(texture.handle, 512)); h:close()
      end
      say('dump: code ranges written' .. (ok and ', atlas descriptor written' or ', no atlas (' .. tostring(texture) .. ')'))
      return
    end
    if name == 'run' then
      -- Run the Lua in probe-pixels.lua once. It gets `say`, the memory helpers
      -- and a table that lasts for the session; it may return a function to be
      -- called every update until that returns true.
      local h = assert(io.open(DIR .. 'probe-pixels.lua', 'r'), 'no probe-pixels.lua'); local text = h:read('*a'); h:close()
      local chunk = assert(loadstring(text, 'probe-pixels.lua'))
      local every = chunk({say = say, read = read, ptr = ptr, u32 = u32, pointer = pointer, atlas = atlas, resolve = resolve,
        ffi = ffi, now_ms = now_ms, dir = DIR, keep = kept})
      if type(every) == 'function' then
        queue[#queue + 1] = function() job = {kind = 'lua', step = every, frame = frame} end
      end
      return
    end
    if name == 'status' then
      local _, text = atlas(); say('status: build checks passed; ' .. text)
    elseif name == 'readback' then
      for i = 1, count do
        queue[#queue + 1] = function()
          local texture, text = atlas()
          if i == 1 then say('readback: ' .. text) end
          begin_readback(texture, 'atlas ' .. i .. '/' .. count, i == 1 and function(pixels, w, h, size)
            local ms = save(ATLAS_FILE, header(w, h), pixels, size)
            say(string.format('atlas saved bytes=%d write_ms=%.1f', size, ms))
            -- The top-left tile of the first page, row by row.
            local tile = ffi.new('uint8_t[?]', TILE * TILE * 4)
            for y = 0, TILE - 1 do ffi.copy(tile + y * TILE * 4, pixels + y * w * 4, TILE * 4) end
            ms = save(TILE_FILE, header(TILE, TILE), tile, TILE * TILE * 4)
            say(string.format('tile saved bytes=%d write_ms=%.2f', TILE * TILE * 4, ms))
          end or nil)
        end
      end
    elseif name == 'upload' then
      for i = 1, count do queue[#queue + 1] = function() upload(TILE_FILE, 'tile ' .. i .. '/' .. count) end end
    elseif name == 'upload_atlas' then
      queue[#queue + 1] = function() upload(ATLAS_FILE, 'atlas upload') end
    else say('unknown command: ' .. command) end
  end

  local next_poll = 0
  say('pixel probe ready')
  return function()
    frame = frame + 1
    local ok, why = pcall(function()
      if job then step_readback(); return end
      if #queue > 0 then table.remove(queue, 1)(); return end
      if frame < next_poll then return end
      next_poll = frame + 30
      local h = io.open(CMD, 'r'); if not h then return end
      local command = (h:read('*l') or ''):gsub('%s+$', ''); h:close(); os.remove(CMD)
      if command ~= '' then say('> ' .. command); run(command) end
    end)
    if not ok then job = nil; queue = {}; say('ERROR ' .. tostring(why)) end
  end
end
-- One call per game update. Inert unless the debug marker is present.
function M.update()
  if disabled then return end
  if not impl then
    local dir = (os.getenv('LOCALAPPDATA') or '.') .. '\\CowboyBingus\\Helldivers2\\Transmog\\'
    local marker = io.open(dir .. 'debug.enabled', 'r')
    if not marker then disabled = true; return end
    marker:close()
    local ok, step = pcall(start)
    if not ok then disabled = true; return end
    impl = step
  end
  impl()
end
return M

end)()
local IconProbe = (function()
-- Explicit, one-shot passive-icon binding diagnostic. Never used by normal UI.
-- No FFI, addresses, casts, resource loading, gameplay calls, or shared materials.
--
-- local probe=IconProbe.new(engine)
-- probe:draw(sample, '7c818b04a594d8e5') -> true|nil, reason
-- probe:report() -> bounded semantic text; API acceptance is NOT visual proof.
-- probe:metrics() -> counters only
-- probe:clear() -> discard all owned GUIs; does not rearm this probe instance.
-- Construct a new instance for another explicitly requested diagnostic.
-- sample: {kind='armory', font=<hash>,material=<font hash>,atlas=<hash>}

local M={}
local GENERIC='57fcf14ad069020b' -- Installed content/ui/shared/material/gui_diffuse_map.
local BRANCHES={
 {key='direct_hash',label='1  Resource ID'},
 {key='icon_userdata',label='2  Icon material'},
 {key='generic_texture',label='3  Texture binding'},
 {key='configured_icon',label='4  Configured icon'},
}
local function hash(value)return type(value)=='string'and #value==16 and not value:find('[^%x]')end
local function safe(value)
 return tostring(value):gsub('0[xX][%x]+','<address>'):gsub('[\r\n%z]',' '):sub(1,200)
end
function M.new(engine)
 local A,W,G=engine.Application,engine.World,engine.Gui
 local self={guis={},attempted=false,visible=false,branches={},status='not_requested'}
 local counts={draw_requests=0,attempts=0,guis_created=0,guis_destroyed=0,
  material_userdata=0,bitmap_accepted=0}
 local function alive(world)
  for _,candidate in ipairs(A.worlds()or {})do if candidate==world then return true end end
  return false
 end
 function self:clear()
  if alive(self.world)then
   for index=#self.guis,1,-1 do
    if pcall(W.destroy_gui,self.world,self.guis[index])then counts.guis_destroyed=counts.guis_destroyed+1 end
   end
  end
  self.guis={};self.world=nil;self.visible=false
 end
 function self:metrics()
  local out={};for key,value in pairs(counts)do out[key]=value end
  out.visible=self.visible;out.active_guis=#self.guis;return out
 end
 function self:report()
  local lines={'HD2TM_ICON_PROBE 1','status='..self.status,'visual_verified=false',
   'visible='..tostring(self.visible),'raw_pointer_conversions=false',
   'icon_hash='..tostring(self.icon_hash or ''),'configured_uniforms_verified_for=font_material_only'}
  if self.error then lines[#lines+1]='error='..safe(self.error)end
  for _,definition in ipairs(BRANCHES)do
   local branch=self.branches[definition.key]
   if branch then
    lines[#lines+1]='branch='..definition.key..' accepted='..tostring(branch.accepted==true)
      ..' material_available='..tostring(branch.material_available==true)
      ..' texture_available='..tostring(branch.texture_available==true)
      ..' material_type='..tostring(branch.material_type or 'resource_id')
    if branch.error then lines[#lines+1]='branch_error='..definition.key..' '..safe(branch.error)end
   end
  end
  return table.concat(lines,'\n')..'\n'
 end
 function self:draw(sample,icon_hash)
  counts.draw_requests=counts.draw_requests+1
  if self.attempted then return nil,'This icon probe already ran; clear it and create a new probe for another test.'end
  self.attempted=true;counts.attempts=counts.attempts+1
  self.icon_hash=hash(icon_hash)and icon_hash or nil
  local ok,reason=pcall(function()
   assert(type(sample)=='table'and sample.kind=='armory','Open the native Armory before the icon probe.')
   assert(hash(icon_hash)and hash(sample.font)and hash(sample.material)and hash(sample.atlas),'Observed icon/font resource hashes are required.')
   assert(type(G.bitmap)=='function'and type(G.material)=='function','Required engine GUI bindings are unavailable.')
   local width,height=G.resolution();assert(width>=640 and height>=480,'Viewport is too small for the icon probe.')
   for _,world in ipairs(A.worlds()or {})do if world~=A.main_world()then self.world=world;break end end
   assert(self.world,'No current UI world is available.')
   local scale=math.min(width/1920,height/1080)
   local id=engine.IdString64.from_hex
   local function color(r,g,b,a)return engine.Color(a or 255,r,g,b)end
   local function gui()
    local value=assert(W.create_screen_gui(self.world,'scale',1,1),'Screen GUI creation failed.')
    self.guis[#self.guis+1]=value;counts.guis_created=counts.guis_created+1;return value
   end
   local function material(target,resource)
    local value=G.material(target,id(resource))
    assert(type(value)=='userdata','Gui.material did not return original engine userdata.')
    counts.material_userdata=counts.material_userdata+1;return value
   end
   local function available(kind,resource)
    if type(A.can_get)~='function'then return false end
    local checked,value=pcall(A.can_get,kind,id(resource));return checked and value==true
   end
   local function configure(value)
    local function parameter(value)return id(value..'00000000')end
    for _,key in ipairs({'8035c266','5e8455fe','309e7783','82b803a8'})do
     engine.Material.set_scalar(value,parameter(key),0)
    end
    engine.Material.set_vector2(value,parameter('e13777ce'),engine.Vector2(1,-1))
    engine.Material.set_vector4(value,parameter('7701209e'),engine.Color(0,0,0,0))
   end
   local text_gui=gui()
   local ink=material(text_gui,sample.material);configure(ink)
   engine.Material.set_texture(ink,id('88bac99b00000000'),id(sample.atlas))
   local font,font_material=id(sample.font),id(sample.material)
   local x,y,w,h=width-1040*scale,height-395*scale,1010*scale,200*scale
   G.rect(text_gui,engine.Vector3(x,y,990),engine.Vector2(w,h),color(12,17,22))
   local function text(value,tx,ty,size,tint)
    G.text(text_gui,value,font,size*scale,font_material,engine.Vector3(tx,ty,997),tint or color(240,242,245))
   end
   text('PASSIVE ICON PROBE / '..icon_hash,x+12*scale,y+h-24*scale,17,color(255,215,60))
   local column=(w-24*scale)/4
   for index,definition in ipairs(BRANCHES)do
    local cx=x+12*scale+(index-1)*column
    local branch={accepted=false,material_available=false,texture_available=false}
    self.branches[definition.key]=branch
    text(definition.label,cx,y+h-49*scale,14)
    local bx,by,size=cx+column/2-42*scale,y+45*scale,84*scale
    G.rect(text_gui,engine.Vector3(bx,by,991),engine.Vector2(size,size),color(86,86,86))
    local passed,problem=pcall(function()
     local own_gui=gui()
     local resource=definition.key=='generic_texture'and GENERIC or icon_hash
     branch.material_available=available('material',resource)
     branch.texture_available=available('texture',icon_hash)
     assert(branch.material_available,'Material resource is unavailable.')
     local binding
     if definition.key=='direct_hash'then binding=id(icon_hash)
     else
      binding=material(own_gui,resource);branch.material_type=type(binding)
      if definition.key=='generic_texture'then
       assert(branch.texture_available,'Texture resource is unavailable.')
       engine.Material.set_texture(binding,'diffuse_map',id(icon_hash))
      elseif definition.key=='configured_icon'then configure(binding)end
     end
     G.bitmap(own_gui,binding,engine.Vector3(bx,by,995),engine.Vector2(size,size),color(255,255,255))
     branch.accepted=true;counts.bitmap_accepted=counts.bitmap_accepted+1
    end)
    if not passed then branch.error=safe(problem)end
    text(branch.accepted and 'API accepted; inspect image' or 'Unavailable / rejected',cx,y+18*scale,12,
      branch.accepted and color(166,190,169)or color(220,158,120))
   end
   self.status='drawn';self.visible=true
  end)
  if not ok then self.error=safe(reason);self.status='failed';self:clear();return nil,self.error end
  return true
 end
 return self
end
return M

end)()
local BootDev = (function()
-- Stage `dev`: developer tools. The file-command bridge (active only with the
-- debug marker file), the read-only probes it schedules, and the commands
-- that belong to no product stage. Every other stage registers the commands
-- for what it owns; this one polls the registry.
--
-- Provides: dev {poll(), trace(now), work(now), seen(sample, now),
-- producers(grid), opening(), probing(), clear_icon_probe()}: the points at
-- which the UI frame lets the tools run.
local M={name='dev',requires={'session'}}
function M.start(k,env)
 local mods,report=env.modules,env.report
 local fs,engine,scene=k:need('fs'),k:need('engine'),k:need('scene')
 local bridge=mods.DebugBridge and mods.DebugBridge.new(fs,engine,report)
 local opener,open_pending,open_waiting,open_deadline,open_visible_since,open_root_since,open_root_seen
 local armory_probe,armory_probe_written
 local armor_probe,armor_probe_written
 local icon_probe,trace,producer_written
 local function armory()return k:service('armory')end
 local function catalog()return k:service('catalog')end
 -- The Armory's UI resolver, once it is ready.
 local function ui(message)
  local a=armory();local adapter=a and a.adapter()
  assert(adapter and adapter.phase=='ready',message or 'Armory UI evidence not ready')
  return adapter
 end
 -- The catalog's data bridge, once its signatures are resolved.
 local function data(message)
  local c=catalog()
  assert(c and c.ready(),message or 'Native armor catalog is not ready')
  return c.bridge()
 end
 local function result()local c=catalog();return c and c.result end
 local function open_status(kind,message)
  report('debug.open_armory.'..kind,message)
  fs.write_atomic('debug-armory-open.txt','HD2TM_ARMORY_OPEN 1\n'..
   bridge.session..'\n'..kind..'\n'..tostring(message):gsub('[\r\n]',' ')..'\n')
 end
 local dev={}
 function dev.poll()
  if bridge and(not bridge.due or bridge:due())then bridge:poll(k:commands())end
 end
 -- A running thumbnail trace records the manager's state changes.
 function dev.trace(now)
  if not trace then return end
  local a=armory();local grid=a and a.grid()
  local state=grid and grid:thumbnail_state()or'unavailable'
  if state~=trace.last then trace.last=state;trace.lines[#trace.lines+1]=(now-trace.started)..' '..state end
  if now>=trace.deadline or #trace.lines>4000 then
   local lines=trace.lines;trace=nil
   fs.write_atomic('debug-thumbnail-trace.txt',table.concat(lines,'\n')..'\n')
  end
 end
 function dev.opening()return open_pending==true or open_waiting==true end
 function dev.probing()
  return(armory_probe~=nil and not armory_probe_written)or(armor_probe~=nil and not armor_probe_written)
 end
 function dev.clear_icon_probe()
  if icon_probe then icon_probe:clear();icon_probe=nil end
 end
 -- Scheduled work: the native Armory request and the read-only probes.
 function dev.work(now)
  if open_pending then
   local passed,phase,reason=pcall(function()return opener:step()end)
   if not passed or phase=='failed' then
    open_pending=false;open_status('error',reason or phase)
   elseif phase=='ready' then
    open_pending=false
    local called,done,why=pcall(function()return opener:open()end)
    if called and done then
     open_waiting=true;open_deadline=now+45000
     open_status('pending','Native transition sent; awaiting the visible Armory Equipment view')
    else open_status('error',why or done)end
   end
  end
  if armory_probe and not armory_probe_written then
   local phase=armory_probe:step()
   if phase~='resolving' then
    fs.write_atomic('debug-armory.txt',armory_probe:summary());armory_probe_written=true
   end
  end
  if armor_probe and not armor_probe_written then
   local phase=armor_probe:step()
   if phase~='resolving' then
    fs.write_atomic('debug-native-armor.txt',armor_probe:summary());armor_probe_written=true
   end
  end
 end
 -- The screen was read: a requested Armory counts as open once it has been
 -- seen for half a second. Two things are told apart in the status file. The
 -- native call lands on the Armory's root, where no grid is shown: once the
 -- menu has held the Armory on top at depth 1 with its controller registered
 -- for half a second, the fourth line begins with `opened` and the status
 -- stays `pending`, because the tools that read this file know three status
 -- words and refuse a fourth. `ok` still means the Equipment grid was seen.
 function dev.seen(sample,now)
  if not open_waiting then return end
  if not open_root_seen then
   local a=armory();local adapter=a and a.adapter()
   local menu=adapter and type(adapter.menu)=='function'and adapter:menu()
   if type(menu)=='table'and menu.armory and menu.depth==1 and menu.controller then
    open_root_since=open_root_since or now
    if now-open_root_since>=500 then
     open_root_seen=true
     open_status('pending','opened: Armory root held 500 ms (current='..menu.current..' depth='..menu.depth
      ..' controller=1); awaiting the visible Armory Equipment view')
    end
   else open_root_since=nil end
  end
  if sample and sample.kind=='armory' then
   open_visible_since=open_visible_since or now
   if now-open_visible_since>=500 then
    open_waiting=false;open_status('ok','Native Armory Equipment view stably observed')
   end
  else open_visible_since=nil end
  if open_waiting and now>open_deadline then
   open_waiting=false
   open_status('error',open_root_seen and'opened: Armory root was reached, but Equipment visibility was not confirmed'
    or'Native request was sent, but Equipment visibility was not confirmed')
  end
 end
 function dev.producers(grid)
  if producer_written==false and grid.producer_status then
   local phase=grid:producer_status()
   if phase=='complete'or phase=='failed'then
    fs.write_atomic('debug-armory-producers.txt',grid:producer_report());producer_written=true
   end
  end
 end
 k:provide('dev',dev)
 if bridge then k:provide('debug',bridge)end
 k:on_shutdown('dev.icon_probe',function()if icon_probe then icon_probe:clear()end end,60)
 if mods.PixelProbe then
  k:step{phase='pre',name='dev.pixel_probe',order=40,run=function()mods.PixelProbe.update()end}
 end
 k:command('icon_probe',function(args)
  dev.clear_icon_probe()
  if args=='off'then return 'Icon probe cleared'end
  assert(type(args)=='string'and args:match('^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$'),'Expected icon resource hash or off')
  local a=armory();local adapter=a and a.adapter()
  local sample,why=adapter and adapter:sample();assert(sample,why or 'Open the Armory first')
  icon_probe=mods.IconProbe.new(engine)
  local shown,reason=icon_probe:draw(sample,args)
  fs.write_atomic('debug-icon-probe.txt',icon_probe:report())
  assert(shown,reason)
  return 'Four owned-material icon tests drawn once; awaiting visual comparison'
 end)
 k:command('probe_armor',function()
  assert(mods.NativeArmorProbe,'Native armor evidence not ready')
  armor_probe=mods.NativeArmorProbe.new(data('Native armor evidence not ready'),report);armor_probe_written=false
  return 'Read-only native armor-consumer inspection scheduled'
 end)
 k:command('inspect_player_armor',function()
  assert(mods.PlayerCustomizationProbe,'Native armor catalog is not ready')
  data()
  -- The committed profile and pending controller armor ids ride along
  -- so the native-selection check is observable from outside. Nothing
  -- exposed them before, and that blindness is why the lockout took so
  -- long to find. Unavailable outside the Armory, never a failure.
  local a=armory()
  local probe=k:need('actor').new{native_selection=a and a.native_selection or nil}
  local seen,reason=probe:sample();assert(seen,reason)
  assert(fs.write_atomic('debug-player-armor.txt',mods.PlayerCustomizationProbe.format(seen)))
  return 'Current local-player armor request and cache recorded without addresses'
 end)
 k:command('inspect_customization_raw',function(args)
  assert(mods.CustomizationRawProbe,'Native armor catalog is not ready')
  local probe=mods.CustomizationRawProbe.new(data())
  local seen,reason=probe:sample(args);assert(seen,reason)
  assert(fs.write_atomic('debug-customization-raw.txt',mods.CustomizationRawProbe.format(seen)))
  return 'Customization manager region recorded relative to its base'
 end)
 k:command('poke_customization_free',function(args)
  assert(mods.CustomizationRawProbe,'Native armor catalog is not ready')
  local source=data()
  local done,reason=mods.CustomizationRawProbe.poke(source,mods.RuntimeWriter.new(source,nil,k:need('process')),args)
  assert(done,reason)
  assert(fs.write_atomic('debug-customization-poke.txt',done..'\n'))
  return(done:gsub('\n','; '))
 end)
 k:command('inspect_steam',function()
  local probe=assert(mods.SteamProbe,'steam probe unavailable')
  local text,reason=probe.sample();assert(text,reason)
  assert(fs.write_atomic('debug-steam.txt',probe.format(text)))
  return 'Steam interface availability recorded (read-only)'
 end)
 k:command('steam_publish',function(args)
  local probe=assert(mods.SteamProbe,'steam probe unavailable')
  local text,reason=probe.publish(args);assert(text,reason)
  assert(fs.write_atomic('debug-steam-publish.txt',text..'\n'))
  return(text:gsub('\n','; '))
 end)
 k:command('clothing_observer',function()
  local probe=assert(mods.ClothingRemoteProbe,'clothing remote probe unavailable')
  local seen,reason=probe.observe(data(),mods.CatalogData,mods.CatalogLabels,k:service('clothing.owner'))
  assert(seen,reason)
  assert(fs.write_atomic('debug-clothing-observer.txt',probe.format(seen)))
  return 'Every occupied customization slot recorded read-only with resolved identities'
 end)
 k:command('clothing_rebind',function(args)
  local probe=assert(mods.ClothingRemoteProbe,'clothing remote probe unavailable')
  local source=data()
  local binding=assert(k:service('clothing.owner'),'Clothing binding is not ready')
  local done,reason=probe.rebind(source,mods.RuntimeWriter.new(source,nil,k:need('process')),mods.CatalogData,binding,args)
  assert(done,reason)
  assert(fs.write_atomic('debug-clothing-rebind.txt',done..'\n'))
  report('clothing.rebind_experiment',(done:gsub('\n','; ')))
  return(done:gsub('\n','; '))
 end)
 -- Rewrites a remote slot's requested armor here, to see whether the game
 -- rebuilds that actor from the write (research/104).
 k:command('clothing_remote_poke',function(args)
  local probe=assert(mods.ClothingRemoteProbe,'clothing remote probe unavailable')
  local source=data()
  local done,reason=probe.poke_request(source,mods.RuntimeWriter.new(source,nil,k:need('process')),args)
  assert(done,reason)
  assert(fs.write_atomic('debug-clothing-remote-poke.txt',done..'\n'))
  report('clothing.remote_poke',(done:gsub('\n','; ')))
  return(done:gsub('\n','; '))
 end)
 -- Read-only: are the game's per-player peer tokens the lobby SteamIDs?
 k:command('clothing_session_peers',function()
  local probe=assert(mods.ClothingRemoteProbe,'clothing remote probe unavailable')
  local adapter=ui()
  local link=k:service('clothing.link')
  local members={};if link then members[1]=link.self_id;for id in pairs(link:peers())do members[#members+1]=id end end
  local done,reason=probe.session_peers(adapter:debug_bridge(),members)
  assert(done,reason)
  assert(fs.write_atomic('debug-clothing-session-peers.txt',done..'\n'))
  report('clothing.session_peers',(done:gsub('\n','; ')))
  return(done:gsub('\n','; '))
 end)
 -- Read-only evidence for per-variant thumbnails: one dump of the thumbnail
 -- manager and the grid's image records, or `trace <ms>` to record the
 -- manager's state changes for that long.
 k:command('inspect_thumbnails',function(args)
  assert(mods.NativeGrid,'Armory UI evidence not ready');ui()
  local a=armory();local grid=a.ensure_grid()
  local span=tonumber(tostring(args):match('^trace%s+(%d+)$'))
  if span then
   trace={deadline=fs.now()+math.min(span,120000),lines={'HD2TM_THUMBNAIL_TRACE 1'},started=fs.now()}
   return 'Thumbnail manager trace started'
  end
  local text,why=grid:thumbnail_dump(result());assert(text,why)
  local labels={}
  -- The cards are the armor tab's own since every tab became an ArmorySlot; the
  -- shared state no longer holds them.
  local tab=a.armor_tab
  local cards=tab and type(tab.cards)=='function'and tab:cards()or a.state.custom_cards
  for index,card in ipairs(cards or{})do
   labels[#labels+1]=string.format('custom %d kind=%s label=%s',index-1,tostring(card.kind),tostring(card.label))
  end
  assert(fs.write_atomic('debug-thumbnails.txt',text..table.concat(labels,'\n')..'\n'))
  return 'Read-only thumbnail manager observations recorded'
 end)
 k:command('inspect_armory_grid',function()
  assert(mods.NativeGrid,'Armory UI evidence not ready');ui()
  local seen,why=armory().ensure_grid():snapshot(result());assert(seen,why)
  assert(fs.write_atomic('debug-armory-grid.txt',mods.NativeGrid.format(seen)))
  return 'Read-only native armor-grid observations recorded'
 end)
 k:command('inspect_armory_model',function()
  assert(mods.NativeGridModel and mods.NativeGrid,'Armory UI evidence not ready');ui()
  local seen,reason=armory().ensure_grid():inspect_model(result());assert(seen,reason)
  assert(fs.write_atomic('debug-armory-model.txt',mods.NativeGridModel.format(seen)))
  return 'Read-only native logical rows and group boundaries recorded'
 end)
 k:command('inspect_armory_producers',function()
  local a=armory();local grid=a and a.grid()
  assert(grid and grid.phase=='ready','Native grid evidence is not ready')
  local began,reason=grid:start_producer_scan();assert(began,reason)
  producer_written=false
  return 'Bounded read-only native list-builder inspection scheduled'
 end)
 k:command('inspect_api',function()return bridge:inspect()end)
 k:command('inspect_world',function()return bridge:inspect_world()end)
 k:command('open_armory',function()
  assert(mods.DebugOpenArmory,'Armory UI evidence not ready')
  local adapter=ui()
  assert(not open_pending and not open_waiting,'An Armory request is already in progress')
  if not opener then opener=mods.DebugOpenArmory.new(adapter:debug_bridge(),scene.ship,report)end
  open_pending=true
  open_visible_since,open_root_since,open_root_seen=nil,nil,false
  open_status('pending','Resolving and checking the native Armory transition')
  return 'Native Armory request queued; verify the resulting Equipment screen'
 end)
 k:command('probe_armory',function()
  assert(mods.DebugArmory,'Armory UI evidence not ready')
  armory_probe=mods.DebugArmory.new(ui():debug_bridge(),report);armory_probe_written=false
  return 'Read-only native menu inspection scheduled; no menu call made'
 end)
 k:command('inspect_controller',function()
  assert(mods.DebugController,'Armory UI evidence not ready')
  local source=ui():debug_bridge();source.decode=mods.DebugArmory.decode
  local seen,why=mods.DebugController.inspect(source);assert(seen,why)
  fs.write_atomic('debug-controller.txt',mods.DebugController.format(seen))
  return 'Read-only Armory controller metadata recorded'
 end)
 k:command('inspect_native_code',function(args)
  assert(mods.DebugArmory,'Armory UI evidence not ready')
  local adapter=ui()
  local rva,count=args:match('^%s*(%x+)%s+(%d+)%s*$')
  assert(rva,'Expected hexadecimal relative location and decimal byte count')
  local text,why=mods.DebugArmory.inspect_code(adapter:debug_bridge(),tonumber(rva,16),tonumber(count))
  assert(text,why);fs.write_atomic('debug-native-code.txt',text)
  return 'Bounded native instruction semantics recorded; no call made'
 end)
 k:command('inspect_native_switch',function(args)
  assert(mods.DebugArmory,'Armory UI evidence not ready')
  local adapter=ui()
  local rva,count=args:match('^%s*(%x+)%s+(%d+)%s*$')
  assert(rva,'Expected hexadecimal switch table location and decimal count')
  local text,why=mods.DebugArmory.inspect_switch(adapter:debug_bridge(),tonumber(rva,16),tonumber(count))
  assert(text,why);fs.write_atomic('debug-native-switch.txt',text)
  return 'Validated native switch selectors recorded; no call made'
 end)
 k:command('inspect_native_callee',function(args)
  assert(mods.DebugArmory,'Native UI evidence not ready')
  local adapter=ui('Native UI evidence not ready')
  local site,count=args:match('^%s*(%x+)%s+(%d+)%s*$');assert(site,'Expected callsite RVA and byte count')
  local text,reason=mods.DebugArmory.inspect_callee(adapter:debug_bridge(),tonumber(site,16),tonumber(count))
  assert(text,reason);assert(fs.write_atomic('debug-native-callee.txt',text))
  return 'Verified direct-call target inspected read-only; no native call made'
 end)
 -- The game's package leases by hand (research/128): `status [id]`,
 -- `acquire <id>`, `release <id>`, `present <kind> <resource path>`,
 -- `alive <unit hash>`. A lease taken here is the developer's to give back:
 -- nothing else knows of it, and a release that is not owed takes a lease
 -- away from whoever holds the package.
 k:command('package_lease',function(args)
  local game=k:service('game');assert(game and game.packages,'the game stage has no package port')
  local port,why=game.packages();assert(port,why)
  local verb,rest=tostring(args or''):match('^%s*(%a+)%s*(.-)%s*$')
  if verb=='status'then
   local able,reason=port.available()
   local text='available='..tostring(able==true)..(able and''or' reason='..tostring(reason))
   if rest~=''then
    local count,used=port.references(rest);assert(count,used)
    text=text..' references='..tostring(count)..' packages='..tostring(used)
   end
   return text
  elseif verb=='acquire'or verb=='release'then
   -- Timed: a package the game loads inside the call holds the frame that long.
   local process=k:need('process')
   local began=process.now_ms and process.now_ms()
   local count,failure=port[verb](rest);assert(count,failure)
   local took=began and string.format('%.1f',process.now_ms()-began)or'-'
   report('debug.package_lease',verb..' '..rest..' references='..tostring(count)..' ms='..took)
   return verb..' '..rest..' references='..tostring(count)..' ms='..took
  elseif verb=='present'then
   local kind,path=rest:match('^(%a+)%s+(%S+)$');assert(kind,'expected: present <kind> <resource path>')
   return 'present='..tostring(assert(game.resources()).present(kind,path))
  elseif verb=='alive'then
   assert(#rest==16 and not rest:find('[^0-9a-f]'),'expected: alive <16-hex unit hash>')
   return 'alive='..tostring(assert(game.resources()).alive(rest))
  end
  error('expected: status [id] | acquire <id> | release <id> | present <kind> <path> | alive <hash>',0)
 end)
 -- The detail panel taken and given back by hand, as another mod would, to
 -- see the game's own panel and a custom card both ways. Nothing else is
 -- taken here.
 local authority_key
 k:command('equipment_authority',function(args)
  local equipment=assert(k:service('equipment'),'the equipment stage is not running')
  local verb,name=tostring(args or''):match('^%s*(%a+)%s*(%S*)%s*$')
  if verb=='status'and name==''then
   local lines={}
   for held,row in pairs(equipment.authorities())do
    lines[#lines+1]=held..'='..tostring(row.holder)..'/'..(row.settled and'settled'or'unsettled')
   end
   table.sort(lines)
   assert(fs.write_atomic('debug-equipment-authority.txt','HD2TM_EQUIPMENT_AUTHORITY 1\n'..table.concat(lines,'\n')..'\n'))
   return table.concat(lines,' ')
  elseif verb=='take'and name=='detail_panel'then
   authority_key=authority_key or{}
   assert(equipment.join(authority_key,{id='hd2transmog-dev/probe',name='Developer probe',version='1'}))
   assert(equipment.take(authority_key,'detail_panel'))
   return 'detail_panel taken'
  elseif verb=='release'and name=='detail_panel'then
   local given=authority_key~=nil and equipment.release(authority_key,'detail_panel')==true
   return 'detail_panel '..(given and'released'or'was not held here')
  end
  error('expected: status | take detail_panel | release detail_panel',0)
 end)
end
return M

end)()
local EngineTests = (function()
-- The in-engine test suite's registry and runner. This runs inside the game
-- process, so it leans on the kernel, the health model and the process layer
-- and never reaches for a new engine binding of its own: a case that trips an
-- engine assertion halts the game silently, and the only thing that survives
-- is what the result file already has on disk.
--
-- A case is registered with `suite:case{...}` (see 1.2 of research/126) and
-- run one at a time over frames. Before a case runs, `BEGIN <case>` is
-- appended to `engine-tests.txt` and flushed; after it, `END <case>
-- pass|fail|skip <reason>`. A halt or a crash leaves a `BEGIN` without its
-- `END`, which is how the host attributes it to one case. The suite costs
-- nothing per frame when idle: the driving step is registered only while a
-- run is active and removed at `DONE`.
--
-- The command `engine_tests` selects on the first word of its payload: list,
-- run <group> <run_id>, status, stop, scenes, crash <nonce> (the last through
-- the crash module, which is gated and in no group).
local M={NAME='engine-tests.txt',LIST='engine-tests-list.txt',HEADER='HD2TM_ENGINE_TESTS 1',
 DEFAULT_TIMEOUT=3000,RUN_BUDGET=120000,GROUPS={ship=true,armory_root=true,armory=true,armor_tab=true},
 SCENE_ORDER={'ship','armory_root','armory','armor_tab'},
 SHIP_NOTICE='a notice is in the way'}

-- Scenes. Each predicate is read in a pcall immediately before a case begins;
-- a predicate that raises or returns false means the scene is not present and
-- the case is skipped. The game-facing predicates ask only services the mod
-- already builds and calls in normal use (the ship guard, the Armory adapter
-- and grid); none reaches for a new engine binding.
local function armory_shown(k)
 local a=k:service('armory');if not a then return false,'no Armory addon'end
 local adapter=a.adapter and a.adapter()
 if not(adapter and adapter.phase=='ready')then return false,'Armory UI not ready'end
 local sample=adapter.sample and adapter:sample()
 if not(type(sample)=='table'and sample.kind=='armory')then return false,'Armory not shown'end
 return true,a
end
-- The menu as the Armory adapter reads it (presenter on top, depth, whether the
-- Armory controller is registered), or nil and why. `unread` is true when
-- there is nothing to read it with: no Armory addon, or its layout not ready.
local function menu_of(k)
 local a=k:service('armory')
 local adapter=a and a.adapter and a.adapter()
 if not a then return nil,'no Armory addon',true end
 if not(adapter and adapter.phase=='ready'and type(adapter.menu)=='function')then return nil,'Armory UI not ready',true end
 local menu,why=adapter:menu()
 if type(menu)~='table'then return nil,tostring(why or'the menu is unreadable')end
 return menu
end
local SCENES={}
function SCENES.any()return true end
function SCENES.ship(k)
 local scene=k:need('scene')
 if not scene.guard()then return false,'the ship is not loaded'end
 -- The ship and the Armory are told apart so a ship case does not run over the
 -- open Armory, where frame time and some readings differ.
 if armory_shown(k)then return false,'the Armory is open'end
 -- The Armory's root has no grid on show, so the check above passes there: the
 -- menu itself must be idle. Where nothing can read the menu the ship guard
 -- alone decides, as it did before the Armory could be opened by a call.
 local menu,why,unread=menu_of(k)
 if not menu then
  if unread then return true end
  return false,'the menu cannot be read: '..why
 end
 if menu.current~=0 or menu.depth~=0 then return false,'a menu is open (current='..menu.current..' depth='..menu.depth..')'end
 -- Nothing on the stack, yet the grid's own idle-menu reading says no: the
 -- start-up notice, which waits for Escape and refuses the native Armory open
 -- while it is on show. Unreadable (nil) is not a notice.
 local a=k:service('armory');local grid=a and a.grid and a.grid()
 if grid and type(grid.idle_menu)=='function'and grid:idle_menu()==false then return false,M.SHIP_NOTICE end
 return true
end
-- The Armory as the native open leaves it: its presenter on top of the stack
-- and its one controller registered, whatever page or tab is shown. The grid
-- is not asked for, so this holds on the root and in the picker alike.
function SCENES.armory_root(k)
 local menu,why=menu_of(k);if not menu then return false,why end
 if not(menu.armory and menu.depth>=1)then return false,'the Armory is not the current menu (current='..menu.current..' depth='..menu.depth..')'end
 if not menu.controller then return false,'the Armory controller is not registered once ('..tostring(menu.controllers)..')'end
 return true
end
function SCENES.armory(k)
 local ok,why=armory_shown(k);if not ok then return false,why end
 return true
end
function SCENES.armor_tab(k)
 local ok,a=armory_shown(k);if not ok then return false,a end
 local grid=a.grid and a.grid()
 -- Weaker than the host's OCR verdict on purpose: a grid snapshot changes the
 -- selection (notes/AUTONOMOUS-GAME-QA.txt), so the predicate reads only the
 -- grid's phase, never its contents (research/126 section 1.3).
 if not(grid and grid.phase=='ready')then return false,'the armor grid is not ready'end
 -- The picker opens on whichever panel had focus (helmet, seen 2026-10-05): the
 -- armor grid is the picker on category 0, by the extras' own reading of it.
 -- Where nothing can read the category the grid's phase alone decides, as before.
 local extras=k:service('extras');local native=extras and type(extras.native)=='function'and extras:native()
 if native and type(native.context)=='function'then
  local read,context=pcall(native.context,native)
  if read and context and context.category~=nil and context.category~=0 then
   return false,'the picker shows another tab (category='..tostring(context.category)..')'
  end
 end
 return true
end

-- Whether a scene is present now, and why not: the predicate under a pcall.
local function present(name,k)
 local ok,a,b=pcall(SCENES[name],k)
 if not ok then return false,'predicate raised: '..(tostring(a):gsub('^.-%.lua:%d+: ',''))end
 if a~=true then return false,b or'not present'end
 return true
end

-- A verdict is carried as a marked table so the runner tells a deliberate
-- skip or fail from an ordinary error raised inside a case.
local function mark(kind,message)return{__engine=kind,message=message}end
local function verdict_of(ok,result)
 if ok then return'pass',nil end
 if type(result)=='table'and result.__engine=='skip'then return'skip',result.message end
 if type(result)=='table'and result.__engine=='fail'then return'fail',result.message end
 return'fail',(tostring(result):gsub('^.-%.lua:%d+: ',''))
end
local function clean(reason)
 if reason==nil or reason==''then return''end
 return(tostring(reason):gsub('[\t\r\n]',' '):sub(1,400))
end

-- The per-case context handed to run and step. Its assertion helpers raise a
-- marked fail with "got ..., want ...": a case states its invariant and the
-- runner turns a broken one into `fail` with the message.
local function context(suite,k,env,case)
 local fs=suite.fs
 local t={k=k,env=env,mods=env.modules,fs=fs,frames=0}
 local process
 function t.process()if not process then process=k:need('process')end;return process end
 function t.now()return fs.now()end
 function t.ms()
  local p=k:service('process')
  if p and p.now_ms then return p.now_ms()end
  return fs.now()
 end
 local info
 function t:info(key,value)
  info=info or{};info[#info+1]=tostring(key)..'='..tostring(value):gsub('[%s]',' ')
 end
 function t._info()if info then return' '..table.concat(info,' ')end return nil end
 function t:fail(message)error(mark('fail',message),0)end
 function t:skip(reason)error(mark('skip',reason),0)end
 function t:ok(value,message)
  if not value then error(mark('fail',(message or'assertion failed')..': got '..tostring(value)),0)end
  return value
 end
 function t:eq(got,want,message)
  if got~=want then error(mark('fail',(message or'not equal')..': got '..tostring(got)..', want '..tostring(want)),0)end
 end
 function t:is(value,type_name,message)
  if type(value)~=type_name then error(mark('fail',(message or'wrong type')..': got '..type(value)..', want '..type_name),0)end
 end
 function t:range(value,low,high,message)
  if type(value)~='number'or value<low or value>high then
   error(mark('fail',(message or'out of range')..': got '..tostring(value)..', want '..low..'..'..high),0)end
 end
 function t:raises(fn,pattern,message)
  local ok,err=pcall(fn)
  if ok then error(mark('fail',(message or'did not raise')..': got no error, want '..tostring(pattern)),0)end
  if pattern and not tostring(err):find(pattern,1,true)then
   error(mark('fail',(message or'wrong error')..': got '..tostring(err)..', want '..tostring(pattern)),0)end
 end
 return t
end

function M.start(k,env,Cases,Crash)
 local fs=k:need('fs')
 local suite={fs=fs,cases={},by_name={},env=env}
 local log=''
 -- One append that has returned before the next line of Lua runs; where the
 -- host has no append the whole accumulated text is rewritten, which is weaker
 -- only if the process dies inside the write, and no case does that.
 local function emit(text)
  log=log..text
  if type(fs.append)=='function'then fs.append(M.NAME,text)else fs.write(M.NAME,log)end
 end

 function suite:case(spec)
  assert(type(spec)=='table'and type(spec.name)=='string','case needs a name')
  assert(spec.name:match('^[a-z0-9_.]+$'),'case name must be [a-z0-9_.]+: '..spec.name)
  assert(not self.by_name[spec.name],'case already registered: '..spec.name)
  assert(SCENES[spec.scene],'unknown scene: '..tostring(spec.scene))
  assert(spec.safe=='read'or spec.safe=='own'or spec.safe=='normal-use','case safe must be read|own|normal-use: '..spec.name)
  assert(type(spec.run)=='function','case needs a run function: '..spec.name)
  local case={name=spec.name,scene=spec.scene,safe=spec.safe,binding=spec.binding,
   timeout=spec.timeout or M.DEFAULT_TIMEOUT,run=spec.run}
  self.cases[#self.cases+1]=case;self.by_name[spec.name]=case
 end

 if Cases then Cases(suite,k,env)end

 -- Run state: nil when idle. `step_fn` is the case's per-frame function when
 -- its run returned one; `phase` is the transition the next frame performs.
 local run
 local handle
 local function finish_run()
  emit('DONE '..run.id..' pass='..run.pass..' fail='..run.fail..' skip='..run.skip..' ms='..fs.now()..'\n')
  suite.last={id=run.id,group=run.group,pass=run.pass,fail=run.fail,skip=run.skip,at=fs.now()}
  run=nil
  if handle then handle.remove();handle=nil end
 end
 local function record(name,state,reason)
  run[state]=run[state]+1
  local line='END '..name..' '..state
  if reason~=nil and reason~=''then line=line..' '..clean(reason)end
  emit(line..'\n')
 end

 -- One transition per frame, so no two cases begin on the same frame and a
 -- case starts on a frame of its own after the one before it has ended.
 local function advance(now)
  if not run then return end
  if run.phase=='stepping'then
   local case=run.case;local t=run.t
   if now>case.began+case.timeout then
    record(case.name,'fail','timeout after '..(now-case.began)..' ms, '..t.frames..' frames')
    run.phase='gap';return
   end
   t.frames=t.frames+1
   local ok,result=pcall(case.step,t)
   if not ok then
    local info=t._info();if info then emit('INFO '..case.name..info..'\n')end
    local _,message=verdict_of(ok,result);record(case.name,'fail',message);run.phase='gap';return
   end
   if result==true then
    local info=t._info();if info then emit('INFO '..case.name..info..'\n')end
    record(case.name,'pass',nil);run.phase='gap'
   end
   return
  end
  if run.phase=='gap'then run.phase='begin';return end
  -- begin: pick the next case, or end the run.
  run.pos=run.pos+1
  local case=run.queue[run.pos]
  if not case then return finish_run()end
  if run.skip_rest then return record(case.name,'skip',run.skip_rest)end
  if now>run.began+M.RUN_BUDGET then run.skip_rest='run budget exhausted';return record(case.name,'skip',run.skip_rest)end
  local here,why=present(case.scene,k)
  if not here then
   -- No BEGIN is written for a scene that is not present: nothing ran, so
   -- there is nothing to attribute a halt to (research/126 section 1.3).
   return record(case.name,'skip','scene '..case.scene..': '..tostring(why))
  end
  run.case=case;case.began=now
  local t=context(suite,k,env,case);run.t=t
  emit('AT '..fs.now()..' '..os.time()..'\nBEGIN '..case.name..'\n')
  local started,result=pcall(case.run,t)
  if started and type(result)=='function'then case.step=result;run.phase='stepping';return end
  local info=t._info();if info then emit('INFO '..case.name..info..'\n')end
  local state,message=verdict_of(started,result)
  record(case.name,state,message)
  run.phase='gap'
 end

 local function queue_for(group)
  local out={}
  for _,case in ipairs(suite.cases)do
   if case.scene==group or(group=='ship'and case.scene=='any')then out[#out+1]=case end
  end
  return out
 end

 -- Commands ------------------------------------------------------------------
 local crash
 if Crash then
  crash=Crash.new{k=k,env=env,fs=fs,suite=suite,emit=emit,
   heartbeat=function()local alive=k:service('health.alive');return alive and alive()end,
   ship=function()local ok,v=pcall(SCENES.ship,k);return ok and v==true end,
   busy=function()return k.busy.held()end}
 end
 k:command('engine_tests',function(payload)
  local word,rest=tostring(payload or''):match('^(%S*)%s*(.-)%s*$')
  if word=='list'then
   local lines={}
   for _,case in ipairs(suite.cases)do
    lines[#lines+1]=case.name..'\t'..case.scene..'\t'..case.safe..'\t'..tostring(case.binding)
   end
   fs.write(M.LIST,table.concat(lines,'\n')..'\n')
   return #suite.cases..' cases listed'
  elseif word=='status'then
   if run then return'running '..run.id..' '..run.pos..'/'..#run.queue..' '..(run.case and run.case.name or'-')end
   if suite.last then return'done '..suite.last.id..' pass='..suite.last.pass..' fail='..suite.last.fail..' skip='..suite.last.skip end
   return'idle'
  elseif word=='stop'then
   if not run then return'idle'end
   run.skip_rest='stopped'
   return'stopping after '..(run.case and run.case.name or'-')
  elseif word=='run'then
   assert(not run,'a run is already active')
   local group,id=rest:match('^(%S+)%s+(%S+)$')
   assert(group and M.GROUPS[group],'run needs a group of ship|armory_root|armory|armor_tab')
   assert(id and id:match('^[a-z0-9-]+$')and #id<=40,'run_id must be [a-z0-9-]{1,40}')
   local queue=queue_for(group)
   if log==''then emit(M.HEADER..'\n')end
   emit('RUN '..id..' '..group..' session='..(k:service('debug')and k:service('debug').session or'-')
    ..' build='..tostring(env.runtime and env.runtime.build)..' wall='..os.time()..' ms='..fs.now()..' cases='..#queue..'\n')
   run={id=id,group=group,queue=queue,pos=0,phase='begin',began=fs.now(),pass=0,fail=0,skip=0}
   handle=k:step{phase='post',name='engine_tests',order=950,run=advance}
   return'started '..id..' cases='..#queue
  elseif word=='scenes'then
   -- Read-only: each scene's verdict now, so the host can wait for a scene
   -- without running a case. A reason is one word: its spaces are underscores.
   local out={}
   for _,name in ipairs(M.SCENE_ORDER)do
    local here,why=present(name,k)
    out[#out+1]=name..'='..(here and'yes'or'no:'..(clean(why):gsub('%s','_')))
   end
   return table.concat(out,' ')
  elseif word=='crash'then
   assert(crash,'the crash module is not present in this build')
   return crash.arm(rest)
  end
  error('engine_tests needs list|run|status|stop|scenes|crash')
 end)

 return suite
end
return M

end)()
local EngineTestsCases = (function()
-- The case list for the in-engine suite (research/126 sections 2.1 to 2.5 and
-- 2.7). The file returns function(suite, k, env): it registers cases and the
-- generated health cases. Every case body runs under the runner's pcall, so a
-- raise is a `fail` and the suite continues.
--
-- Two rules shape what a case may do. It is read-only, except the two refusal
-- checks, which are refused by the process layer's own rules before anything
-- reaches the game. And it calls no engine binding the mod does not already
-- call in normal use, unless that binding is the only new one in the case and
-- named in `binding=`; today only `string.dump` and `jit.status` are new, and
-- both are LuaJIT library functions, not game bindings. Other addons' modules
-- are reached as `mods.Name`, never by a bare name, so the split build does
-- not pull them into the developer bundle.
local READ_LIMIT=16*1024*1024

-- Little-endian unsigned 32-bit from the first four bytes of a string. byte()
-- is a string's own method; it reads no game memory.
local function u32le(s)
 local a,b,c,d=s:byte(1,4)
 return a+b*256+c*65536+d*16777216
end

-- Percentiles of a plain array, sorted here; mean too. Pure arithmetic.
local function summary(list)
 local n=#list
 if n==0 then return 0,0,0,0 end
 table.sort(list)
 local sum=0;for i=1,n do sum=sum+list[i]end
 local function at(p)return list[math.min(n,math.max(1,math.ceil(p*n)))]end
 return sum/n,at(0.5),at(0.95),list[n]
end

-- Frame time by bracket steps (2.7): two steps per phase at the extreme orders
-- read the millisecond clock into preallocated FFI arrays, so sampling makes
-- no garbage and the scheduler is untouched. A frame whose `pre` was vetoed
-- has no closing reading and is dropped. The brackets live only while the case
-- runs and are removed at the end, so the suite costs nothing per frame idle.
local function frame_time(t,label,N)
 local ffi=require('ffi')
 local clock=t.ms
 local k=t.k
 local pre_s=ffi.new('double[?]',N+2)
 local pre_e=ffi.new('double[?]',N+2)
 local post_s=ffi.new('double[?]',N+2)
 local post_e=ffi.new('double[?]',N+2)
 local ren_s=ffi.new('double[?]',N+2)
 local ren_e=ffi.new('double[?]',N+2)
 local gc_s=ffi.new('double[?]',N+2)
 local gc_e=ffi.new('double[?]',N+2)
 local started=ffi.new('uint8_t[?]',N+2)
 local complete=ffi.new('uint8_t[?]',N+2)
 local has_render=ffi.new('uint8_t[?]',N+2)
 local f=0
 local handles={}
 local function add(phase,order,name,fn)
  handles[#handles+1]=k:step{phase=phase,order=order,name='frame_bracket.'..label..'.'..name,run=fn}
 end
 add('pre',-1e9,'pre_s',function()
  if f>=N then return end
  f=f+1;pre_s[f]=clock();started[f]=1;gc_s[f]=collectgarbage('count')
 end)
 add('pre',1e9,'pre_e',function()if started[f]==1 and pre_e[f]==0 then pre_e[f]=clock()end end)
 add('post',-1e9,'post_s',function()if started[f]==1 and post_s[f]==0 then post_s[f]=clock()end end)
 add('post',1e9,'post_e',function()
  if started[f]==1 and post_e[f]==0 then post_e[f]=clock();complete[f]=1;gc_e[f]=collectgarbage('count')end
 end)
 add('render',-1e9,'ren_s',function()if started[f]==1 and ren_s[f]==0 then ren_s[f]=clock()end end)
 add('render',1e9,'ren_e',function()
  if started[f]==1 and ren_s[f]~=0 and ren_e[f]==0 then ren_e[f]=clock();has_render[f]=1;gc_e[f]=collectgarbage('count')end
 end)
 return function(tt)
  if not(f>=N and complete[N]==1)then return end
  for _,h in ipairs(handles)do h.remove()end
  local own,frame_ms,garbage,dropped,prev=({}),({}),({}),0,nil
  for i=1,N do
   if started[i]==1 and complete[i]==1 then
    local ms=(pre_e[i]-pre_s[i])+(post_e[i]-post_s[i])+(has_render[i]==1 and(ren_e[i]-ren_s[i])or 0)
    own[#own+1]=ms;garbage[#garbage+1]=gc_e[i]-gc_s[i]
    if prev then frame_ms[#frame_ms+1]=pre_s[i]-prev end
    prev=pre_s[i]
   elseif started[i]==1 then dropped=dropped+1 end
  end
  local own_mean,own_p50,own_p95,own_max=summary(own)
  local frame_mean=select(1,summary(frame_ms))
  local garbage_mean=select(1,summary(garbage))
  local fmt=string.format
  tt:info('frames',#own);tt:info('own_mean',fmt('%.3f',own_mean))
  tt:info('own_p50',fmt('%.3f',own_p50));tt:info('own_p95',fmt('%.3f',own_p95))
  tt:info('own_max',fmt('%.3f',own_max));tt:info('frame_mean',fmt('%.3f',frame_mean))
  tt:info('garbage_kb_mean',fmt('%.3f',garbage_mean));tt:info('dropped',dropped);tt:info('target',0.3)
  -- The Armory is open and known to cost more, on its root as in the picker,
  -- so it reports and never fails (goal item 7); only the ship figure is a
  -- verdict.
  if label=='ship'and own_p50>0.3 then tt:fail('own p50 '..fmt('%.3f',own_p50)..' ms over the 0.3 ms target')end
  return true
 end
end

-- Where a frame's own time goes, which `frame.*` does not say. For N frames
-- every scheduled step, and every method of the objects `objects(t)` names,
-- runs under a timer of its own; all of them are taken off at the end. A row
-- is milliseconds / kilobytes of new Lua memory / calls, each per frame, and
-- timers nest: a method's figure holds what it calls. Then what was asked of
-- the process layer (a system call each on Windows) and of the pad library,
-- and what the input sample said: without input the tab draws nothing, so a
-- profile taken unfocused is of another path. The timers cost time themselves;
-- `frame.*` stays the figure for the total.
local PROFILE_ROWS=512
-- A profile ends after this long whatever the frame rate, with the frames it
-- has: its timers must never outlive the case, and a case that times out is
-- not given the chance to take them off.
local PROFILE_LIMIT_MS=12000
local function frame_profile(t,label,N,objects)
 local ffi=require('ffi')
 local clock,k=t.ms,t.k
 local names,slots,on={},0,false
 local ms=ffi.new('double[?]',PROFILE_ROWS+1)
 local kb=ffi.new('double[?]',PROFILE_ROWS+1)
 local calls=ffi.new('double[?]',PROFILE_ROWS+1)
 local function closing(slot,began,held,...)
  ms[slot]=ms[slot]+clock()-began
  local grew=collectgarbage('count')-held
  if grew>0 then kb[slot]=kb[slot]+grew end
  calls[slot]=calls[slot]+1
  return ...
 end
 local function timed(name,fn)
  if slots>=PROFILE_ROWS then return fn end
  slots=slots+1;names[slots]=name
  local slot=slots
  return function(...)
   if not on then return fn(...)end
   return closing(slot,clock(),collectgarbage('count'),fn(...))
  end
 end
 local undo={}
 for _,item in ipairs(objects and objects(t)or{})do
  local prefix,object,only=item[1],item[2],item[3]
  if type(object)=='table'then
   local found={}
   if only then for _,key in ipairs(only)do if type(rawget(object,key))=='function'then found[#found+1]=key end end
   else for key,value in pairs(object)do if type(key)=='string'and type(value)=='function'then found[#found+1]=key end end end
   table.sort(found)
   for _,key in ipairs(found)do
    local original=rawget(object,key)
    rawset(object,key,timed(prefix..'.'..key,original))
    undo[#undo+1]=function()rawset(object,key,original)end
   end
  end
 end
 undo[#undo+1]=k.schedule:instrument(function(name,phase,run)
  if name=='engine_tests'or name:find('^frame_bracket%.')then return run end
  return timed('step.'..phase..'.'..name,run)
 end)
 local fs=t.fs
 local process=k:service('process')
 local counted={}
 local function counts(into)
  local p=process and process.counts or{}
  into.read,into.same,into.query,into.write,into.bytes=p.read or 0,p.same or 0,p.query or 0,p.write or 0,p.bytes or 0
  local pad=fs.pad_counts or{}
  into.pad,into.pad_empty=pad.reads or 0,pad.empty or 0
  return into
 end
 -- Where the reads come from: the three frames of Lua above the process
 -- layer, as file:line, counted for the same N frames. Looking the frames up
 -- costs far more than a read, so the timings of a traced profile are not
 -- comparable with an untraced one; the trace is asked for by name.
 local sites,site_bytes
 local function trace(kind,n)
  if not on then return end
  local key=kind
  for level=3,5 do
   local info=debug.getinfo(level,'Sl')
   if not info then break end
   key=key..'<'..tostring(info.short_src):match('[^/\\]*$')..':'..tostring(info.currentline)
  end
  sites[key]=(sites[key]or 0)+1;site_bytes[key]=(site_bytes[key]or 0)+n
 end
 if t.trace_reads and process then
  sites,site_bytes={},{}
  process.trace=trace
  undo[#undo+1]=function()process.trace=nil end
 end
 local stamp=ffi.new('double[?]',N+2)
 local heap=ffi.new('double[?]',N+2)
 local f,inputs,inside,pads,sampled=0,0,0,0,0
 local first,last
 local handles={}
 handles[1]=k:step{phase='pre',order=-1e9,name='frame_bracket.'..label..'.profile_s',run=function()
  if f>N then return end
  f=f+1;stamp[f]=clock();heap[f]=collectgarbage('count')
  if f==1 then first=counts({});on=true
  elseif f==N+1 or f>2 and stamp[f]-stamp[1]>PROFILE_LIMIT_MS then N=f-1;on=false;last=counts(counted)end
 end}
 -- After the tab has drawn: the sample this frame's work was given, when one
 -- was taken. The profile takes none itself: on the ship nobody samples.
 handles[2]=k:step{phase='post',order=1e9,name='frame_bracket.'..label..'.profile_e',run=function()
  if not on or type(fs.input_seen)~='function'then return end
  local input=fs.input_seen()
  if input~=false then sampled=sampled+1 end
  if input then
   inputs=inputs+1
   if input.cursor_inside then inside=inside+1 end
   if input.controller_source then pads=pads+1 end
  end
 end}
 return function(tt)
  if not last then return end
  for _,h in ipairs(handles)do h.remove()end
  for i=#undo,1,-1 do undo[i]()end
  local fmt=string.format
  local frames,grown={},0
  for i=1,N do
   frames[i]=stamp[i+1]-stamp[i]
   local grew=heap[i+1]-heap[i];if grew>0 then grown=grown+grew end
  end
  local frame_mean,frame_p50,frame_p95=summary(frames)
  local own=0
  local order={}
  for slot=1,slots do
   if calls[slot]>0 then
    order[#order+1]=slot
    if names[slot]:find('^step%.')then own=own+ms[slot]end
   end
  end
  table.sort(order,function(a,b)if ms[a]~=ms[b]then return ms[a]>ms[b]end return names[a]<names[b]end)
  tt:info('frames',N);tt:info('frame_mean',fmt('%.3f',frame_mean));tt:info('frame_p50',fmt('%.3f',frame_p50))
  tt:info('frame_p95',fmt('%.3f',frame_p95));tt:info('own_mean',fmt('%.3f',own/N))
  tt:info('garbage_kb',fmt('%.2f',grown/N))
  for _,key in ipairs({'read','same','query','write','bytes','pad','pad_empty'})do
   tt:info(key,fmt('%.2f',(last[key]-first[key])/N))
  end
  tt:info('sampled',fmt('%.2f',sampled/N));tt:info('input',fmt('%.2f',inputs/N));tt:info('cursor_inside',fmt('%.2f',inside/N));tt:info('pad_present',fmt('%.2f',pads/N))
  tt:info('rows',#order)
  if sites then
   local keys={}
   for key in pairs(sites)do keys[#keys+1]=key end
   table.sort(keys,function(a,b)if sites[a]~=sites[b]then return sites[a]>sites[b]end return a<b end)
   for at=1,math.min(#keys,60)do
    tt:info('site.'..keys[at],fmt('%.2f/%.0f',sites[keys[at]]/N,site_bytes[keys[at]]/N))
   end
  end
  for at,slot in ipairs(order)do
   -- Every step, and whatever else took a microsecond or made a kilobyte.
   if at<=120 and(names[slot]:find('^step%.')or ms[slot]/N>=0.001 or kb[slot]/N>=0.05)then
    tt:info(names[slot],fmt('%.4f/%.2f/%.2f',ms[slot]/N,kb[slot]/N,calls[slot]/N))
   end
  end
  return true
 end
end
-- What the Armory profile times beside the steps: the tabs, the grid, the
-- layout adapter, the extras and their parts, the catalog and the panel.
local function armory_objects(t)
 local k=t.k
 local out={}
 local a=k:service('armory')
 if a then
  for category=0,2 do
   local tab=a.tabs and a.tabs[category]
   if tab then
    out[#out+1]={'tab'..category,tab}
    local flow=type(tab.flow)=='function'and tab:flow()
    if flow then out[#out+1]={'tab'..category..'.flow',flow}end
    local session=type(tab.session)=='function'and tab:session()
    if session then out[#out+1]={'tab'..category..'.session',session}end
   end
  end
  local grid=type(a.grid)=='function'and a.grid()
  if grid then out[#out+1]={'grid',grid}end
  local adapter=type(a.adapter)=='function'and a.adapter()
  if adapter then out[#out+1]={'ui',adapter}end
 end
 local extras=k:service('extras')
 if extras then
  out[#out+1]={'extras',extras}
  local parts=type(extras.parts)=='function'and extras:parts()or{}
  for _,name in ipairs({'native','previews','text','compare','model','service'})do
   if parts[name]then out[#out+1]={'extras.'..name,parts[name]}end
  end
 end
 for _,name in ipairs({'catalog','panel','clothing.owner','clothing.control','clothing.transport','refresh','equipment','respawn'})do
  local service=k:service(name)
  if type(service)=='table'then out[#out+1]={name,service}end
 end
 out[#out+1]={'fs',t.fs,{'sample_input','now','read','write','write_atomic','append'}}
 return out
end

-- 2.5 health: a check's scene and allowed states. A name no clause matches is
-- an `unlisted health check` fail, so this cannot fall behind the code. `use`
-- checks are read in scene `any` (their port's scene is a phase-3 fact).
local function pass_only(t,state)
 if state~='pass'then t:fail('not pass: '..tostring(state))end
end
local function health_plan(name,kind)
 if name:find('^stage%.')then return'any',pass_only end
 if name:find('^step%.')then return'any',function(t)t:fail('a step breaker tripped; its presence is a fail')end end
 if name=='public.surface'or name=='state.saved'then return'any',pass_only end
 if name=='game.catalog'then return'ship',pass_only end
 if name=='clothing'then return'ship',function(t,s,r)
  if s=='partial'then t:info('clothing',r)elseif s~='pass'then t:fail('not pass: '..tostring(s))end end end
 -- The layout check passes once the adapter has resolved, whatever the screen
 -- shows (boot/armory.lua), so the Armory's root is enough to ask it on.
 if name=='game.ui'then return'armory_root',pass_only end
 if name=='game.grid'or name=='armory.extras'then return'armor_tab',pass_only end
 -- A mod that took the helmet and cape passives and never said they were in
 -- place is that mod's trouble, and is said; anything else is ours.
 if name=='equipment.authority'then return'any',function(t,s,r)
  if s=='partial'then t:info('authority',r)elseif s~='pass'then t:fail('not pass: '..tostring(s))end end end
 if name=='diverkit'then return'ship',function(t,s,r)
  if s=='off'then t:info('diverkit',r)elseif s~='pass'then t:fail('not pass or off: '..tostring(s))end end end
 if name:find('^game%.')then return'ship',pass_only end
 if kind=='use'then return'any',function(t,s,r)
  if s=='unknown'then t:info('use',tostring(r))elseif s=='degraded'then t:fail('a recorded operation failed: '..tostring(r))
  elseif s~='pass'then t:fail('unexpected use state: '..tostring(s))end end end
 return nil
end

-- Materials on the ship. Every engine call goes through the material port
-- (src/game/material_calls.lua); unit handles are held only in local tables,
-- never as keys. The cases that rebind a material work on a unit the applier
-- of materials is not working on, and bind the packaged id back at the end or
-- at the first failure.
local function sorted_keys(map)
 local list={};for key in pairs(map or{})do list[#list+1]=key end
 table.sort(list);return list
end
local function equal_rows(a,b)
 if type(a)~='table'or type(b)~='table'or #a~=#b then return false end
 for i=1,#a do
  if a[i].mesh~=b[i].mesh or a[i].index~=b[i].index or a[i].id~=b[i].id then return false end
 end
 return true
end
-- The unit and the one position a case may rebind, with what every other
-- instance of the same resource carries; or skips the case with the reason.
local function material_candidate(t)
 local k=t.k
 local port,why=k:need('game').materials()
 if not port then t:skip('no material port: '..tostring(why))end
 local owner,registry,applier=k:service('clothing.owner'),k:service('clothing.registry'),k:service('clothing.materials')
 if not(owner and registry)then t:skip('no clothing owner in this session')end
 local rows=owner:depictions()
 if#rows==0 then t:skip('no clothing piece is worn')end
 local status=applier and applier:status()
 if status and status.bound>0 then t:skip('the applier of materials holds '..status.bound..' positions')end
 for _,row in ipairs(rows)do if next(row.materials)then t:skip('a worn look binds materials of its own')end end
 local pieces={};for _,piece in ipairs(registry.list())do pieces[piece.uuid]=piece end
 local resources=k:need('game').resources()
 local body=owner:status().body
 local reason='no worn piece declares materials a unit carries'
 for _,row in ipairs(rows)do
  local look=owner:depicts(row.key)
  local piece=look and pieces[look.uuid]
  local declared=piece and piece.binding and piece.binding.materials
  local world=row.world=='main'and port.main()or nil
  if declared and world then
   for _,field in ipairs(piece.toggles or{})do
    for value=1,math.min(field.max or 0,64)do
     local descriptor=registry.resolve(look.uuid,{body=body,toggles={[field.name]=value}})
     for _,packaged in ipairs(sorted_keys(descriptor and descriptor.materials))do
      local alt=descriptor.materials[packaged]
      for _,hash in ipairs(declared[alt]and sorted_keys(row.units)or{})do
       for _,unit in ipairs(port.instances(world,hash)or{})do
        local before=port.alive(unit)and port.bindings(unit)
        for _,position in ipairs(before or{})do
         if position.id==packaged then
          local loaded=true
          for _,path in ipairs(declared[alt].textures or{})do
           if not(resources and resources.present('texture',path))then loaded=false;reason='a texture of the alternative is not loaded: '..path end
          end
          if loaded then
           local others={}
           for _,w in ipairs(port.worlds()or{})do
            for _,other in ipairs(port.instances(w,hash)or{})do
             if not port.is(other,unit)and port.alive(other)then others[#others+1]={unit=other,before=port.bindings(other)}end
            end
           end
           return{port=port,unit=unit,packaged=packaged,alt=alt,position=position,before=before,others=others,
            owner=owner,applier=applier,key=row.key}
          end
         end
        end
       end
      end
     end
    end
   end
  end
 end
 t:skip(reason)
end
-- Binds the alternative on one instance, reads it back two frames later, binds
-- the packaged id again and reads the original ids back. `isolation` asserts
-- only that no other instance moved. The runner drops a step that times out
-- without cleanup, so the step keeps its own deadline: past STALL ms with the
-- alternative still bound, the packaged ids go back and the case fails.
local STALL=3000
local function rebind_case(t,isolation)
 local c=material_candidate(t)
 if isolation and#c.others==0 then t:skip('no second instance of the unit')end
 -- Every position that differs from the start goes back, the packaged one last.
 -- A unit that is gone is not bound on.
 local function restore()
  if not c.port.alive(c.unit)then return end
  for _,row in ipairs(c.port.bindings(c.unit)or{})do
   for _,was in ipairs(c.before)do
    if was.mesh==row.mesh and was.index==row.index and was.id~=row.id
     and not(was.mesh==c.position.mesh and was.index==c.position.index)then
     pcall(c.port.bind,c.unit,was.mesh,was.index,was.id)
    end
   end
  end
  pcall(c.port.bind,c.unit,c.position.mesh,c.position.index,c.packaged)
 end
 local function untouched()
  for _,o in ipairs(c.others)do
   if not equal_rows(c.port.bindings(o.unit),o.before)then return false end
  end
  return true
 end
 local ok,why=c.port.bind(c.unit,c.position.mesh,c.position.index,c.alt)
 if not ok then restore();t:fail('the bind was refused: '..tostring(why))end
 local began,frames,back=t.ms(),0,false
 local function step(tt)
  frames=frames+1
  if not back and t.ms()-began>STALL then tt:fail('the frames stalled with the alternative bound for over '..STALL..' ms')end
  if frames==3 then
   tt:ok(c.port.alive(c.unit),'the unit is gone')
   local busy=c.applier and c.applier:status().bound>0
   for _,row in ipairs(c.owner:depictions())do if row.key==c.key and next(row.materials)then busy=true end end
   -- The runner records an error in a step as a fail, so a skip here is a pass with the reason in INFO.
   if busy then restore();tt:info('skipped','a look changed and the applier of materials took the unit');return true end
   local now=c.port.bindings(c.unit)
   tt:ok(now and#now==#c.before,'the unit cannot be read back')
   if not isolation then
    -- The engine rebinds a slot across the unit's meshes, and a unit may carry
    -- one material in two slots: the bound position carries the alternative,
    -- a position that changed with it was packaged with the id and carries
    -- the alternative too, and every other position is as it was.
    local rebound=0
    for i,row in ipairs(now)do
     local was=c.before[i].id
     local expected=was
     if row.mesh==c.position.mesh and row.index==c.position.index or row.id~=was and was==c.packaged then expected=c.alt end
     tt:eq(row.id,expected,'position '..row.mesh..'/'..row.index..' after the bind')
     if was==c.packaged and row.id==c.alt then rebound=rebound+1 end
    end
    tt:info('rebound',rebound)
    tt:ok(rebound>0,'no position carries the alternative')
   end
   tt:ok(untouched(),'another instance of the unit changed')
   local bound,reason=c.port.bind(c.unit,c.position.mesh,c.position.index,c.packaged)
   tt:ok(bound,'the packaged id was refused: '..tostring(reason))
   back=true
  elseif frames==6 then
   tt:ok(c.port.alive(c.unit),'the unit is gone')
   tt:ok(equal_rows(c.port.bindings(c.unit),c.before),'the unit did not return to its packaged ids')
   tt:ok(untouched(),'another instance changed on the way back')
   return true
  end
 end
 return function(tt)
  local done
  local ok2,err=pcall(function()done=step(tt)end)
  if not ok2 then restore();error(err,0)end
  return done
 end
end

return function(suite,k,env)
 -- 2.1 Lua environment -------------------------------------------------------
 suite:case{name='lua.ffi',scene='any',safe='read',run=function(t)
  local ffi=require('ffi')
  t:eq(ffi.os,'Windows','ffi.os');t:eq(ffi.arch,'x64','ffi.arch');t:ok(ffi.abi('64bit'),'64-bit ABI')
 end}
 suite:case{name='lua.ffi_kernel32',scene='any',safe='read',run=function(t)
  local ffi=require('ffi')
  pcall(ffi.cdef,'uint64_t GetTickCount64(void);')
  local kernel=ffi.load('kernel32')
  t:range(tonumber(kernel.GetTickCount64()),1,2^53,'GetTickCount64')
 end}
 suite:case{name='lua.io',scene='any',safe='read',run=function(t)
  t:is(io.open,'function','io.open')
  local value,why=t.fs.read('engine-tests-absent.txt')
  t:ok(value==nil and why~=nil,'a missing file returns nil and a reason')
 end}
 suite:case{name='lua.os',scene='any',safe='read',run=function(t)
  t:range(os.time(),1767225600,4102444800,'os.time after 2026-01-01')
  local app=os.getenv('LOCALAPPDATA');t:ok(type(app)=='string'and #app>0,'LOCALAPPDATA')
  t:is(os.clock(),'number','os.clock')
 end}
 suite:case{name='lua.loadstring',scene='any',safe='own',binding='string.dump',run=function(t)
  t:eq(loadstring('return 1+1')(),2,'loadstring')
  t:eq(loadstring(string.dump(function()return 7 end))(),7,'string.dump round trip')
 end}
 suite:case{name='lua.jit',scene='any',safe='read',binding='jit.status',run=function(t)
  t:ok(tostring(jit.version):find('LuaJIT 2',1,true),'jit.version')
  t:info('jit.status',tostring(select(1,jit.status())))
 end}
 suite:case{name='lua.string_char',scene='any',safe='own',run=function(t)
  if not t.mods.PreviewPixels then return t:skip('no Armory addon')end
  local ok,why=t.mods.PreviewPixels.selftest();t:ok(ok,why or'string.char self-test failed')
  -- The known miscompile of a multi-argument string.char is not provoked here:
  -- a loop that did so ran in every validation, and the game crashed inside
  -- this case once (2026-10-05). The self-test above is the verdict.
 end}
 suite:case{name='lua.pixels_native',scene='any',safe='own',run=function(t)
  if not t.mods.NativePreviewPixels then return t:skip('no Armory addon')end
  local ok,why=t.mods.NativePreviewPixels.selftest();t:ok(ok,why or'self-test failed')
 end}
 suite:case{name='lua.pixels_colour',scene='any',safe='own',run=function(t)
  if not t.mods.PreviewColour then return t:skip('no Armory addon')end
  local ok,why=t.mods.PreviewColour.selftest();t:ok(ok,why or'self-test failed')
 end}
 suite:case{name='lua.pixels_cutout',scene='any',safe='own',run=function(t)
  if not t.mods.RenderCutout then return t:skip('no Armory addon')end
  local ok,why=t.mods.RenderCutout.selftest();t:ok(ok,why or'self-test failed')
 end}
 suite:case{name='lua.id_string',scene='any',safe='own',run=function(t)
  if not t.mods.IdString then return t:skip('no id-string module')end
  t:ok(t.mods.IdString.selftest(),'identifier hash self-test failed')
 end}

 -- 2.2 Host ------------------------------------------------------------------
 suite:case{name='host.log',scene='any',safe='own',run=function(t)
  local token='engine-tests-'..t.now()
  t.env.report('engine_tests.log_probe',token)
  local dir=t.env.loader and t.env.loader.log_directory
  if not dir then return t:skip('no loader log directory')end
  local file=io.open(dir..'/HD2Transmog.log','rb')
  if not file then return t:skip('the log is not open')end
  local text=file:read('*a');file:close()
  t:ok(text:find(token,1,true),'the report line was not found in the log')
 end}
 suite:case{name='host.files_plain',scene='any',safe='own',run=function(t)
  local x='engine tests plain '..t.now()
  t:ok(t.fs.write('engine-tests-probe.txt',x),'write')
  t:eq(t.fs.read('engine-tests-probe.txt'),x,'round trip')
 end}
 suite:case{name='host.files_append',scene='any',safe='own',run=function(t)
  if type(t.fs.append)~='function'then return t:skip('no append')end
  local a,b='engine tests a '..t.now()..'\n','engine tests b\n'
  t.fs.write('engine-tests-append.txt','')
  t:ok(t.fs.append('engine-tests-append.txt',a),'append a')
  t:ok(t.fs.append('engine-tests-append.txt',b),'append b')
  t:eq(t.fs.read('engine-tests-append.txt'),a..b,'both parts in order')
 end}
 suite:case{name='host.files_atomic',scene='any',safe='own',run=function(t)
  local x='engine tests atomic '..t.now()
  t:ok(t.fs.write_atomic('engine-tests-atomic.txt',x),'write_atomic')
  t:eq(t.fs.read('engine-tests-atomic.txt'),x,'round trip')
  local ok,why=t.fs.write_atomic('bad/name.txt',x)
  t:ok(ok==nil and why=='bad_name','a name with a slash is refused')
 end}
 suite:case{name='host.clock',scene='any',safe='read',run=function(t)
  local first,last=t.now(),t.now()
  return function(tt)
   local n=tt.now();if n<last then tt:fail('fs.now went backwards')end;last=n
   if tt.frames>=3 then tt:range(last-first,1,2000,'fs.now advance over three frames');return true end
  end
 end}
 suite:case{name='host.frame',scene='any',safe='read',run=function(t)
  t:ok(t.k.schedule.installed,'the schedule is not installed')
  t:is(rawget(_G,'update'),'function','the update global')
  local frame0,calls=t.k.frame,0
  return function(tt)
   calls=calls+1
   if calls>=10 then tt:eq(tt.k.frame-frame0,calls,'k.frame grew by our step calls');return true end
  end
 end}
 suite:case{name='host.starter',scene='any',safe='read',run=function(t)
  local loader=t.env.loader
  t:ok(type(loader)=='table'and tonumber(loader.api)and tonumber(loader.api)>=1,'loader api >= 1')
  t:info('version',tostring(loader.version));t:info('api',tostring(loader.api))
 end}
 suite:case{name='host.link',scene='ship',safe='read',run=function(t)
  local link=t.k:service('clothing.link')
  if not link then return t:skip('no clothing link service')end
  t:ok(link.state~='error','link state is error: '..tostring(link.state))
  t:ok(tostring(link.self_id):match('^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$'),'self_id is 16 hex digits')
 end}

 -- 2.3 Process rules against real memory -------------------------------------
 -- Every OS call here is one the backend already makes; no new binding. The
 -- base is game.dll's module handle, the one module the mod resolves anyway.
 suite:case{name='process.backend',scene='any',safe='read',run=function(t)
  local p=t.process()
  t:eq(p.backend,'ffi-windows','backend')
  t:info('has_compare',tostring(p.has_compare));t:info('has_function_entries',tostring(p.has_function_entries))
 end}
 suite:case{name='process.read',scene='any',safe='read',run=function(t)
  local p=t.process();local base=p.module('game.dll')
  t:ok(base,'game.dll module');t:eq(p.read(base,2),'MZ','DOS magic')
  local e=u32le(p.read(base+0x3c,4))
  t:eq(p.read(base+e,4),'PE\0\0','PE signature')
 end}
 suite:case{name='process.read_bounds',scene='any',safe='read',run=function(t)
  local p=t.process();local base=p.module('game.dll')
  -- None of these raises; a short or out-of-range read is nil.
  t:eq(p.read(0,1),nil,'a read below the low bound');t:eq(p.read(0xffff,1),nil,'a read at the low bound')
  t:eq(p.read(base,READ_LIMIT+1),nil,'a read past the size limit')
 end}
 suite:case{name='process.same',scene='any',safe='read',run=function(t)
  local p=t.process();local base=p.module('game.dll')
  t:eq(p.same(base,'MZ'),true,'same holds');t:eq(p.same(base,'ZM'),false,'same differs')
  t:eq(p.same(base,''),false,'same of empty')
 end}
 suite:case{name='process.region_code',scene='any',safe='read',run=function(t)
  local p=t.process();local base=p.module('game.dll')
  local e=u32le(p.read(base+0x3c,4))
  local code=base+u32le(p.read(base+e+0x2c,4))   -- BaseOfCode of the PE32+ header
  local _,_,state=p.region(code)
  t:eq(state,0x1000,'code region is committed');t:eq(p.executable(code,true),true,'code is executable image')
  t:eq(p.data(base),true,'the header holds data')
 end}
 suite:case{name='process.write_refused',scene='any',safe='read',run=function(t)
  -- Cannot reach the game: process.write returns nil,'write range rejected'
  -- from its own writable() check before calling the backend (game/process.lua
  -- self.write), so no byte can reach code even if that rule were broken.
  local p=t.process();local base=p.module('game.dll')
  local e=u32le(p.read(base+0x3c,4))
  local code=base+u32le(p.read(base+e+0x2c,4))
  if p.writable(code,1)~=false then return t:fail('code reported writable; write is not called')end
  local ok,why=p.write(code,p.read(code,1))
  t:eq(ok,nil,'write refused');t:ok(tostring(why):find('write range rejected',1,true),'refusal reason')
 end}
 suite:case{name='process.call_refused',scene='any',safe='own',run=function(t)
  -- Cannot reach the game: process.fn asserts the target is executable before
  -- it casts (game/process.lua self.fn), and a private buffer is data, so no
  -- function value is made and nothing is called.
  local p=t.process()
  local at=p.buffer('HD2TM engine test')
  local ok,err=pcall(p.fn,'void (*)(void)',at)
  t:eq(ok,false,'fn into data raised')
  t:ok(tostring(err):find('native call target is not executable',1,true),'refusal reason')
 end}
 suite:case{name='process.buffer',scene='any',safe='own',run=function(t)
  local p=t.process();local x='HD2TM engine test buffer'
  local at=p.buffer(x);t:is(at,'number','buffer address')
  t:eq(p.read(at,#x),x,'the buffer reads back');t:ok(p.same(at,x),'buffer compares equal')
  t:eq(p.buffer(x),at,'a second buffer of the same bytes is the same address')
  t:eq(p.writable(at,#x),true,'a private buffer is writable memory')
 end}
 suite:case{name='process.clock',scene='any',safe='read',run=function(t)
  local p=t.process();t:ok(p.now_ms,'the backend has no millisecond clock')
  local m0,f0=p.now_ms(),t.fs.now()
  return function(tt)
   if tt.frames>=30 then
    local dm,df=p.now_ms()-m0,tt.fs.now()-f0
    tt:ok(dm>=0,'now_ms decreased');tt:range(dm-df,-40,40,'now_ms disagrees with fs.now')
    return true
   end
  end
 end}

 -- 2.4 Game contract (scene ship) --------------------------------------------
 suite:case{name='contract.ready',scene='ship',safe='read',timeout=20000,run=function(t)
  local game=t.k:need('game')
  return function(tt)
   local c=game.contract()
   if c and c.phase=='ready'then return true end
   if c and c.phase=='failed'then tt:fail('the contract failed: '..tostring(c.failure));return true end
  end
 end}
 suite:case{name='contract.capabilities',scene='ship',safe='read',run=function(t)
  local game=t.k:need('game');local c=game.contract()
  t:ok(c and c.phase=='ready','the contract is not ready')
  for line in c:describe():gmatch('[^\n]+')do
   local name,state,found=line:match('^capability\t([^\t]+)\t([^\t]+)\t(%S+)')
   if name then
    t:info(name,found)
    if state~='pass'then t:fail('capability '..name..' is '..state..': '..line)end
   end
  end
 end}
 suite:case{name='contract.symbols',scene='ship',safe='read',run=function(t)
  local game=t.k:need('game');local c=game.contract()
  t:ok(c and c.phase=='ready','the contract is not ready')
  local missing={}
  for line in c:describe():gmatch('[^\n]+')do
   local name,state=line:match('^symbol\t([^\t]+)\t([^\t]+)')
   if name and state~='unused'then
    local address=game.address(name)
    if not address then missing[#missing+1]=name end
   end
  end
  t:ok(#missing==0,'symbols without an address: '..table.concat(missing,', '))
 end}
 suite:case{name='contract.report',scene='ship',safe='own',run=function(t)
  local game=t.k:need('game')
  local text=game.report()
  t:ok(tostring(text):find('HD2TM_GAME_CONTRACT 1',1,true)==1,'game.report did not write the contract')
  t:ok(tostring(t.fs.read('game-contract.txt')):find('HD2TM_GAME_CONTRACT 1',1,true)==1,'game-contract.txt header')
 end}

 -- 2.4b Package leases (scene ship; research/128) ----------------------------
 -- Read-only: the port is made and the lease table is read. No lease is taken.
 suite:case{name='packages.port',scene='ship',safe='read',run=function(t)
  local game=t.k:need('game')
  local port,why=game.packages()
  t:ok(port~=nil,'the package port was not made: '..tostring(why))
  if not port then return end
  local able,reason=port.available()
  t:ok(able==true,'packages cannot be leased: '..tostring(reason))
  local key=port.table_key()
  t:ok(type(key)=='string'and #key==16,'the lease table has no key')
  -- The login armor's package: one the game declares. How many leases hold it
  -- is the game's business; that the table can be read for it is ours.
  local login=env.modules.GameTerms.login.armor
  local package
  for _,kit in pairs(env.modules.CatalogData.kits)do if kit.id=='armor:'..login then package=kit.package end end
  t:ok(type(package)=='string','the login armor has no package in the catalog')
  local count,used=port.references(package)
  t:ok(type(count)=='number'and type(used)=='number'and used>=1 and used<1024,'the lease table could not be read: '..tostring(used))
  t:info('leases','login package '..tostring(count)..', packages held '..tostring(used))
 end}
 suite:case{name='packages.resources',scene='ship',safe='read',run=function(t)
  local game=t.k:need('game')
  local resources,why=game.resources()
  t:ok(resources~=nil,'the engine cannot be asked about resources: '..tostring(why))
  if not resources then return end
  -- A resource nothing ships is not there, and no unit of it is in a world.
  t:eq(resources.present('unit','mods/hd2transmog/engine-tests/no-such-unit'),false,'a missing unit')
  t:eq(resources.alive('00000000deadbeef'),false,'units of a resource nothing ships')
 end}
 suite:case{name='packages.hosts',scene='ship',safe='read',run=function(t)
  local owner=t.k:service('clothing.owner')
  if not(owner and type(owner.hosts_status)=='function')then t:info('hosts','no clothing owner in this session');return end
  local status=owner:hosts_status()
  if not status then t:info('hosts','no lease holder in this build');return end
  t:info('hosts','held '..#status.hosts..', acquired '..tostring(status.acquires)..', released '..tostring(status.releases)
   ..', lost '..tostring(status.losses))
  local port=t.k:need('game').packages()
  for _,host in ipairs(status.hosts)do
   local count=port and port.references(host.id)
   t:ok(type(count)=='number'and count>=1,'a host held here has no lease in the game: '..host.id)
  end
 end}

 -- 2.4c Materials on one unit instance (scene ship). `materials.port` and
 -- `materials.status` only read; the two others rebind one position of one
 -- instance the applier is not working on and bind the packaged id back.
 suite:case{name='materials.port',scene='ship',safe='read',binding='Mesh.material',run=function(t)
  local port,why=t.k:need('game').materials()
  t:ok(port~=nil,'the material port was not made: '..tostring(why))
  local owner=t.k:service('clothing.owner')
  local rows=owner and owner:depictions()or{}
  if#rows==0 then t:skip('no clothing piece is worn')end
  local worlds=port.worlds()
  t:ok(worlds,'the engine did not list its worlds')
  local main,listed=port.main(),false
  for _,world in ipairs(worlds)do if port.is(world,main)then listed=true end end
  t:ok(listed,'the main world is not among the worlds')
  local seen,positions=0,0
  for _,row in ipairs(rows)do
   for _,hash in ipairs(row.world=='main'and sorted_keys(row.units)or{})do
    local first=port.instances(main,hash)
    t:ok(first,'instances were not answered for '..hash)
    local second=port.instances(main,hash)
    t:ok(second and#second==#first,'a second call found other instances of '..hash)
    for i,unit in ipairs(first)do
     t:ok(port.is(unit,second[i]),'a second call returned another handle for '..hash)
     local list=port.bindings(unit)
     t:ok(list and#list>=1,'a unit of '..hash..' has no material positions')
     for _,position in ipairs(list)do
      t:ok(#position.id==16 and not position.id:find('[^0-9a-f]'),'a material id is not sixteen lowercase hex digits')
     end
     seen=seen+1;positions=positions+#list
    end
   end
  end
  t:info('instances',seen);t:info('positions',positions)
  if seen==0 then t:skip('no instance of a worn unit in the main world')end
 end}
 suite:case{name='materials.apply',scene='ship',safe='own',binding='Unit.set_material',timeout=30000,run=function(t)
  return rebind_case(t,false)
 end}
 suite:case{name='materials.isolation',scene='ship',safe='own',binding='Unit.set_material',timeout=30000,run=function(t)
  return rebind_case(t,true)
 end}
 suite:case{name='materials.status',scene='ship',safe='read',run=function(t)
  local applier=t.k:service('clothing.materials')
  if not applier then t:info('materials','no applier of materials in this session');return end
  local status=applier:status()
  local format=t.mods.ClothingMaterials and t.mods.ClothingMaterials.format
  if format then t:info('status',(format(status):gsub('\n$',''):gsub('\n','; ')))end
  t:info('rows',status.rows);t:info('instances',status.instances);t:info('bound',status.bound)
  t:eq(status.failed,0,'rows of the applier that failed')
  t:eq(status.ambiguous,0,'resources the applier finds ambiguous')
 end}

 -- Equipment API 2 as another mod reads it: the worn set on the ship, the
 -- card under the cursor in the armor list. Read only.
 suite:case{name='equipment.effective',scene='ship',safe='read',run=function(t)
  local equipment=t:ok(t.k:service('equipment'),'the equipment stage is not running')
  local second=false
  for _,api in ipairs(equipment.apis or{})do if api==2 then second=true end end
  t:ok(second,'Equipment API 2 is not announced in apis')
  if equipment.available()~=true then t:skip('the catalog has not been read')end
  local effective,why=equipment.effective()
  t:ok(effective,'the worn set is not described: '..tostring(why))
  local worn=t:ok(equipment.worn(),'the worn set cannot be read')
  for _,slot in ipairs({'armor','helmet','cape'})do
   local row=effective[slot]
   if worn[slot]==nil then t:info(slot,'none')
   else
    t:ok(row and row.id==worn[slot],slot..' is not described as the record that is worn')
    t:is(row.kit,'number',slot..' has no record number')
    if row.custom then t:ok(equipment.owns(row.kit)==true,slot..' carries a variant on a record owns() does not answer for')end
    t:info(slot,row.id..'/'..tostring(row.passive)..'/'..(row.custom and'custom'or'stock'))
   end
  end
  local held={}
  for name,row in pairs(equipment.authorities())do held[#held+1]=name..'='..tostring(row.holder)end
  table.sort(held);t:info('authorities',table.concat(held,' '))
 end}
 suite:case{name='equipment.shown',scene='armor_tab',safe='read',run=function(t)
  local equipment=t:ok(t.k:service('equipment'),'the equipment stage is not running')
  t:eq(equipment.capabilities().shown,true,'the highlighted card cannot be described in this build')
  local shown=t:ok(equipment.shown(),'no card is described while the armor list is open')
  t:eq(shown.screen,'armory','the screen of the highlighted card')
  t:eq(shown.slot,'armor','the slot of the highlighted card')
  t:is(shown.kit,'number','the highlighted card has no record number')
  if not shown.custom then t:eq(shown.stats_kit,shown.kit,'a stock card carries its own stats')end
  t:info('shown',shown.id..'/'..tostring(shown.passive)..'/'..(shown.custom and'custom'or'stock')
   ..'/'..(type(shown.stats_kit)=='number'and string.format('%08x',shown.stats_kit)or'-'))
 end}

 -- The Armory's root, which the native open reaches with no input ------------
 suite:case{name='menu.armory_root',scene='armory_root',safe='read',run=function(t)
  local a=t.k:service('armory');local adapter=t:ok(a and a.adapter and a.adapter(),'the Armory adapter')
  local menu,why=adapter:menu()
  t:ok(menu,'the menu is unreadable: '..tostring(why))
  t:info('current',menu.current);t:info('depth',menu.depth)
  t:ok(menu.armory,'the Armory is the presenter on top')
  t:range(menu.depth,1,5,'the stack depth')
  t:eq(menu.controllers,1,'Armory controllers registered');t:ok(menu.controller,'the Armory controller')
 end}

 -- 2.7 Frame time -----------------------------------------------------------
 suite:case{name='frame.ship',scene='ship',safe='read',timeout=20000,run=function(t)return frame_time(t,'ship',300)end}
 suite:case{name='frame.armory_root',scene='armory_root',safe='read',timeout=20000,run=function(t)return frame_time(t,'armory_root',300)end}
 suite:case{name='frame.armory',scene='armor_tab',safe='read',timeout=20000,run=function(t)return frame_time(t,'armory',300)end}

 -- Profiles: reported, never judged.
 suite:case{name='profile.ship',scene='ship',safe='read',timeout=20000,run=function(t)return frame_profile(t,'ship',300,armory_objects)end}
 suite:case{name='profile.armory',scene='armor_tab',safe='read',timeout=20000,run=function(t)return frame_profile(t,'armory',300,armory_objects)end}
 suite:case{name='profile.armory_reads',scene='armor_tab',safe='read',timeout=30000,run=function(t)
  t.trace_reads=true
  return frame_profile(t,'armory_reads',120,function()return{}end)
 end}

 -- 2.5 Health probes: one generated case per check that exists now ------------
 suite:case{name='health.file',scene='any',safe='own',run=function(t)
  t.k:commands().health()
  t:ok(tostring(t.fs.read('health.txt')):find('HD2TM_HEALTH 2',1,true)==1,'health.txt header')
 end}
 local now=k.now and k.now()or 0
 for _,row in ipairs(k.health:snapshot(now).checks)do
  local name,kind=row.name,row.kind
  local scene,verify=health_plan(name,kind)
  if scene then
   suite:case{name='health.'..name,scene=scene,safe='read',run=function(t)
    local state,reason=t.k.health:state(name,t.now())
    verify(t,state,reason)
   end}
  else
   suite:case{name='health.'..name,scene='any',safe='read',run=function(t)
    t:fail('unlisted health check: '..name)
   end}
  end
 end
end

end)()
local EngineTestsCrash = (function()
-- The one deliberate crash, alone in its own file so its presence in a bundle
-- is a single search. It is in no test group: `run ship` never reaches it; the
-- host sends `engine_tests crash <nonce>` only with its own flag, and only
-- after a clean run. The action is a raw FFI read of an address that is never
-- mapped in a Windows process (below 0x10000): a data access that patches
-- nothing and calls nothing, which the game's own reporter captures as an
-- access violation (research/126 section 3). The read goes through raw FFI,
-- not the process layer, whose ReadProcessMemory cannot fault; in an offline
-- test the read is handed in so the order of effects and the gate can be
-- checked without faulting luajit.
local M={ARM='engine-tests.arm',HEAD='HD2TM_ENGINE_CRASH 1',MARKER=0xDEAD,
 BEGIN_FRAME=30,HEARTBEAT_FRAME=31,FAULT_FRAME=60}

-- The real fault: dereference the unmapped marker address. The value is used
-- (tostring) so nothing can fold the load away. jit is turned off on this
-- function at the call site.
local function real_fault()
 local ffi=require('ffi')
 pcall(ffi.cdef,'typedef unsigned int CrashTransmogU32;')
 local pointer=ffi.cast('const volatile CrashTransmogU32 *',M.MARKER)
 return tostring(pointer[0])
end

-- deps: k, env, fs, suite, emit(text), heartbeat() (health.alive), ship() ->
-- bool, busy() -> bool, and optional fault() for a test.
function M.new(deps)
 local k,env,fs,suite,emit=deps.k,deps.env,deps.fs,deps.suite,deps.emit
 local fault=deps.fault or real_fault
 local armed=false
 local nonce,token,handle,frames
 local function tick(now)
  frames=frames+1
  if frames==M.BEGIN_FRAME then
   emit('RUN '..nonce..' crash session='..token..' build='..tostring(env.runtime and env.runtime.build)
    ..' wall='..os.time()..' ms='..fs.now()..' cases=1\n')
   emit('AT '..fs.now()..' '..os.time()..'\nBEGIN crash\n')
   pcall(env.report,'engine_tests.crash','deliberate invalid read follows')
  elseif frames==M.HEARTBEAT_FRAME then
   pcall(deps.heartbeat)
  elseif frames>=M.FAULT_FRAME then
   -- The step is removed first: if the read returns or raises we still write
   -- an END; if it ends the process there is a BEGIN with no END, as intended.
   if handle then handle.remove();handle=nil end
   if jit and jit.off then pcall(jit.off,fault)end
   local ok,value=pcall(fault)
   if ok then emit('END crash fail read returned '..tostring(value)..'\n')
   else emit('END crash fail fault became a Lua error: '..(tostring(value):gsub('[\t\r\n]',' '):sub(1,400))..'\n')end
   emit('DONE '..nonce..' pass=0 fail=1 skip=0 ms='..fs.now()..'\n')
  end
 end
 local self={}
 -- The gate (research/126 section 3.5): every clause in order, each refusal a
 -- distinct message. Being in this file at all is gate 1 (dev addon only).
 function self.arm(payload)
  local bridge=k:service('debug')
  assert(bridge,'the debug bridge is not live')
  local n=tostring(payload or''):match('^%s*(%S*)%s*$')
  assert(n and n:match('^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$'),'the crash nonce must be 16 hex digits')
  local expected=M.HEAD..'\n'..bridge.session..'\n'..n..'\n'
  assert(fs.read(M.ARM)==expected,'the arm file does not match this launch and nonce')
  local last=suite.last
  assert(last and last.fail==0 and(fs.now()-last.at)<=120000,'no clean run finished in the last 120 s')
  assert(deps.ship(),'the crash test runs only on the ship')
  assert(not deps.busy(),'native work is in flight')
  assert(not armed,'the crash test is already armed in this session')
  armed=true
  nonce,token=n,bridge.session
  -- Overwritten so it cannot arm twice even across a reload of the step.
  fs.write_atomic(M.ARM,M.HEAD..'\nused\n')
  frames=0
  handle=k:step{phase='post',name='engine_tests.crash',order=951,run=tick}
  return'armed '..n
 end
 return self
end
return M

end)()
local MenuProbe = (function()
-- Developer commands about the game's menu: what it shows now, how it changes,
-- and one guarded experiment that writes to the game's input state.
--
--   menu_state   one line, also written to debug-menu-state.txt: the presenter
--                on top, the stack, which page of the Armory is up, and the
--                state byte of five Menu actions in this update.
--   menu_watch   for up to 30 s, follows the same readings every update and
--                writes one line per change to debug-menu-watch.txt, so that
--                keys pressed meanwhile show which action each one drives and
--                in which update, against the update the menu changed in.
--   menu_action  the experiment, below.
--
-- The action state table is the one the consume function clears (the layout
-- says what is known of it and from where). Its owner is the input singleton
-- the grid resolves from that function's code and proves on every asking.
-- The first two commands read through the readers the mod already has and
-- call nothing.
--
-- menu_action <action> <token> [all] is EXPERIMENTAL and UNVERIFIED IN THE
-- GAME. It is the only write here: a data write into the game's per-frame
-- input state, byte 0 of one Menu action's entry set to 1 for one update (with
-- `all`, the first byte of each of the three fields the consume function
-- clears, in case the game keeps more than one copy). When it works it acts
-- exactly like a key press, on whatever the menu has in focus; when it does
-- not, the game recomputes the entry and nothing happens. Which of the two is
-- what the experiment is for. No game code is touched and nothing is called:
-- the write goes through the process layer, which refuses code and anything
-- not writable.
--
-- It must be tried one action per launch, starting with Back (11) on the
-- Armory's root, which can do nothing but close the Armory.
--
-- Every guard is checked in the update of the write, and a refusal names the
-- one that failed:
--   one in flight      a second command while one is being recorded would mix
--                      two causes in one record.
--   token              the host sends this launch's debug session token, so a
--                      request left over from another launch cannot fire.
--   allowed actions    10, 11, 12, 18 and 19 only: the ids the layout names.
--                      Any other id is an action nobody has identified.
--   12 per session     a host that loops cannot hammer the game's input.
--   ship scene         the Armory this is about is the ship's.
--   presenter 5        the ship Armory is on top with its controller
--                      registered: a key press means something else on every
--                      other screen.
--   settled menu       the menu's state block read the same in the update
--                      before: nothing is injected into a transition.
--   Select             10 only on the gear page (the three gear widgets shown)
--                      or with the gear picker up. Select acts on what has
--                      focus, and on another page that could be a purchase.
--   owner and proof    the input singleton is read again and the consume proof
--                      checked in this update, and the entry's address is
--                      computed fresh: no address outlives an update.
--   writable heap      the entry must be committed, writable, non-executable
--                      memory outside every module image.
-- In the next update a byte that still holds what was written is put back to
-- what it held, so the write lasts one update even if the game does not
-- recompute the entry. The write's result and read-back, that restore, and
-- every change of the readings over the next 120 updates are written to
-- debug-menu-action.txt, first right after the write and again at the end.
local M={STATE='debug-menu-state.txt',STATE_HEADER='HD2TM_MENU_STATE 1',
 WATCH='debug-menu-watch.txt',WATCH_HEADER='HD2TM_MENU_WATCH 1',WATCH_SECONDS=30,WATCH_CHANGES=4096,
 ACTION='debug-menu-action.txt',ACTION_HEADER='HD2TM_MENU_ACTION 1',ACTION_FRAMES=120,ACTION_CHANGES=1024,
 WRITE_CAP=12,TRACK_MS=5000}
local ffi=require('ffi')
local function u32(s,o)local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
local function pointer(s)
 if type(s)~='string'or #s~=8 then return nil end
 local hi=u32(s,4);if hi>=32768 then return nil end
 local n=u32(s,0)+hi*4294967296;return n>=65536 and n or nil
end
function M.start(k,env)
 local mods=env.modules
 local fs=k:need('fs')
 local Layout=assert(mods.GameGridLayout,'the grid layout is not bundled')
 local Process=assert(mods.GameProcess,'the process layer is not bundled')
 local Menu,Screen,States,ACTIONS=Layout.menu,Layout.screen,Layout.action_states,Layout.menu_actions
 local NA=#ACTIONS
 for i=2,NA do assert(ACTIONS[i]>ACTIONS[i-1],'menu actions must ascend')end
 local function process()return k:need('process')end
 local function session()local debug=k:service('debug');return debug and debug.session or nil end
 local function armory()return k:service('armory')end
 -- The Armory's layout resolver once it is ready, and its grid.
 local function ui()
  local a=armory();local adapter=a and a.adapter and a.adapter()
  if adapter and adapter.phase=='ready'then return adapter end
  return nil
 end
 local function picker_grid()local a=armory();return a and a.grid and a.grid()or nil end
 -- The extras' native layer, which tells the gear page from the picker.
 local function native()
  local extras=k:service('extras')
  if extras and type(extras.native)=='function'then return extras:native()end
  return nil
 end
 -- Whether the ship Armory's gear page is up (grid hidden, the three gear
 -- widgets shown): true, false, or nil where nothing can say.
 local function gear_page()
  local n=native();if not(n and n.root_context)then return nil end
  local ok,c=pcall(n.root_context,n)
  if not ok then return nil end
  return c~=nil and c.screen_kind~='deployment'
 end
 -- The picker's category and view while it is shown, else nil.
 local function picker()
  local n=native();if not(n and n.context)then return nil end
  local ok,c=pcall(n.context,n)
  if not ok or not c then return nil end
  return c.category,c.mode
 end
 -- The input singleton: the pointer is read again and the consume proof
 -- checked on every asking (native_grid input_owner), so an address is never
 -- kept from one update to the next.
 local function owner()
  local grid=picker_grid()
  if not(grid and grid.phase=='ready'and type(grid.input_owner)=='function')then return nil,'the grid has not resolved the input singleton'end
  return grid:input_owner()
 end
 -- The state entry of a Menu-group action in the singleton at `at`.
 local function entry(at,action)
  return at+States.at+States.stride*(States.group_actions*States.menu_group+action)
 end
 -- What kind of memory holds `at`, by the process layer's own region query.
 local function place(p,at)
  local base,_,_,_,kind=p.region(at)
  if base==nil then return'unknown'end
  return(kind==Process.IMAGE and'image'or'heap')..(p.writable(at,1)and',writable'or',not-writable')
 end

 -- The menu's state from one update to the next --------------------------------
 -- A write is refused unless the menu's state block read the same in the
 -- update before it, so something has to have read it then. This step does,
 -- and only while a command asked for it in the last five seconds: menu_state
 -- and every menu_action start or extend it, and it removes itself. While the
 -- block holds it is compared in place and nothing is made. It runs after the
 -- step that dispatches commands, so a command sees the reading of the update
 -- before, and a step added from a command never moves the one that added it.
 local track
 local function tracking()
  if track then track.expires=fs.now()+M.TRACK_MS;return end
  local t={expires=fs.now()+M.TRACK_MS,stable=0,frame=-1}
  t.handle=k:step{phase='post',name='menu_probe.track',order=890,run=function()
   if fs.now()>t.expires then
    t.handle.remove();if track==t then track=nil end
    return
   end
   local p=process()
   local held=t.block~=nil and t.frame==k.frame-1 and p.same(t.slot_at,t.slot)and p.same(t.at,t.block)
   t.frame=k.frame
   if held then t.stable=t.stable+1;return end
   t.stable=0;t.block=nil
   local adapter=ui();if not adapter then return end
   local ok,bridge=pcall(function()return adapter:debug_bridge()end)
   if not ok or type(bridge)~='table'or type(bridge.verify)~='function'or bridge.verify()~=true then return end
   local slot=p.read(bridge.menu_global,8);local menu=slot and pointer(slot)
   local block=menu and p.read(menu+Menu.state,Menu.state_size)
   if block then t.slot_at,t.slot,t.at,t.block=bridge.menu_global,slot,menu+Menu.state,block end
  end}
  track=t
 end

 -- menu_state ---------------------------------------------------------------
 -- One word per fact, `key=value`, a value's spaces as underscores.
 local function state_line()
  local out={}
  local function put(key,value)out[#out+1]=key..'='..(tostring(value):gsub('%s','_'):sub(1,120))end
  local adapter=ui()
  local menu,why
  if adapter and type(adapter.menu)=='function'then menu,why=adapter:menu()else why='Armory UI not ready'end
  if menu then
   put('current',menu.current);put('depth',menu.depth)
   put('stack',#menu.stack>0 and table.concat(menu.stack,',')or'-')
   put('controller',menu.controller and'yes'or'no:'..tostring(menu.controllers))
  else put('menu','unreadable:'..tostring(why))end
  local root=gear_page()
  put('root',root==nil and'unknown'or root and'yes'or'no')
  local sample,reason
  if adapter then
   local ok,a,b=pcall(adapter.sample,adapter)
   if ok then sample,reason=a,b else reason=a end
  else reason='Armory UI not ready'end
  put('kind',type(sample)=='table'and sample.kind or'-:'..tostring(reason))
  local grid=picker_grid()
  for category=0,2 do
   local verdict,err
   if grid and type(grid.input_scope)=='function'then verdict,err=grid:input_scope(category)else err='no grid'end
   put('scope'..category,verdict==true and'yes'or verdict==false and'no'or'err:'..tostring(err))
  end
  local category,view=picker()
  put('category',category or'-');put('view',view or'-')
  put('grid',grid and grid.phase or'none')
  local at,owner_why=owner()
  if at then
   local p=process()
   for i=1,NA do
    local byte=p.read(entry(at,ACTIONS[i]),1)
    put('a'..ACTIONS[i],byte and byte:byte()or'unreadable')
   end
   put('entry',place(p,entry(at,ACTIONS[1])))
  else put('actions','unreadable:'..tostring(owner_why))end
  return table.concat(out,' ')
 end
 k:command('menu_state',function()
  tracking()
  local line=state_line()
  assert(fs.write_atomic(M.STATE,M.STATE_HEADER..'\n'..tostring(session()or'-')..'\n'..line..'\n'))
  return line
 end)

 -- Recording -----------------------------------------------------------------
 -- What a recording follows, one number each: the presenter on top, the depth,
 -- the picker's category, whether the gear page is up, and byte 0 of the five
 -- actions' entries, read after the game's update (`a<id>`) and before it
 -- (`p<id>`). The two readings of an action tell whether the game evaluates
 -- input inside its update or between two of them. -1 is "could not be read".
 local FIELDS={'current','depth','category','root'}
 local POST=#FIELDS+1
 for i=1,NA do FIELDS[#FIELDS+1]='a'..ACTIONS[i]end
 local PRE=#FIELDS+1
 for i=1,NA do FIELDS[#FIELDS+1]='p'..ACTIONS[i]end
 local NF=#FIELDS
 local function clock()
  local p=process()
  if p.now_ms then return p.now_ms()end
  return fs.now()
 end
 -- One read spans the five entries: from the first action's byte 0 to the last's.
 local function read_actions(into,first)
  local at=owner()
  local raw=at and process().read(entry(at,ACTIONS[1]),States.stride*(ACTIONS[NA]-ACTIONS[1])+1)
  for i=1,NA do into[first+i-1]=raw and raw:byte(States.stride*(ACTIONS[i]-ACTIONS[1])+1)or -1 end
 end
 local function read_menu(into,menu_global,verify)
  local p=process()
  local slot=menu_global and verify()==true and p.read(menu_global,8)
  local menu=slot and pointer(slot)
  local block=menu and p.read(menu+Menu.state,Menu.state_size)
  into[1]=block and u32(block,Menu.screen)or -1
  into[2]=block and u32(block,Menu.depth)or -1
 end
 local function read_page(into)
  local category=picker();into[3]=category or -1
  local root=gear_page();into[4]=root==nil and -1 or root and 1 or 0
 end
 -- A recording keeps the last reading and the changes, in arrays made once:
 -- an update stores numbers and makes no line and no table of its own. (The
 -- readers it asks still return what they read as strings and tables.) At
 -- most `limit` changes are kept; the ones after that are counted. Frame n is
 -- the n-th update after the one the recording began in.
 local function recorder(limit)
  local r={frames=0,changes=0,dropped=0,frame0=k.frame}
  local last,cur=ffi.new('double[?]',NF+1),ffi.new('double[?]',NF+1)
  local at_frame,at_field=ffi.new('int32_t[?]',limit+1),ffi.new('uint8_t[?]',limit+1)
  local at_ms,old,new=ffi.new('double[?]',limit+1),ffi.new('double[?]',limit+1),ffi.new('double[?]',limit+1)
  local menu_global,verify
  do
   local adapter=ui()
   local ok,bridge=pcall(function()return adapter:debug_bridge()end)
   if ok and type(bridge)=='table'and type(bridge.verify)=='function'then menu_global,verify=bridge.menu_global,bridge.verify end
  end
  local began=clock()
  -- The reading every change is measured from, taken where the recording begins.
  read_menu(cur,menu_global,verify);read_page(cur);read_actions(cur,POST)
  for i=0,NA-1 do cur[PRE+i]=cur[POST+i]end
  local start={}
  for i=1,NF do last[i]=cur[i];start[i]=string.format('%d',cur[i])end
  function r.pre()
   if k.frame==r.frame0 then return end
   read_actions(cur,PRE)
  end
  function r.post()
   if k.frame==r.frame0 then return end
   r.frames=r.frames+1
   read_menu(cur,menu_global,verify);read_page(cur);read_actions(cur,POST)
   local ms
   for i=1,NF do
    if cur[i]~=last[i]then
     if r.changes<limit then
      ms=ms or clock()-began
      local n=r.changes+1;r.changes=n
      at_frame[n]=r.frames;at_field[n]=i;at_ms[n]=ms;old[n]=last[i];new[n]=cur[i]
     else r.dropped=r.dropped+1 end
     last[i]=cur[i]
    end
   end
  end
  function r.elapsed()return clock()-began end
  function r.lines(out)
   out[#out+1]='fields '..table.concat(FIELDS,' ')
   out[#out+1]='start '..table.concat(start,' ')
   for n=1,r.changes do
    out[#out+1]=string.format('%d %.1f %s %d -> %d',at_frame[n],at_ms[n],FIELDS[at_field[n]],old[n],new[n])
   end
  end
  return r
 end

 -- menu_watch <seconds> ------------------------------------------------------
 local watch
 local function finish_watch()
  local w=watch;watch=nil
  w.pre.remove();w.post.remove()
  local r=w.r
  local out={M.WATCH_HEADER,string.format('session=%s seconds=%s frames=%d ms=%.1f changes=%d dropped=%d frame0=%d',
   tostring(session()or'-'),tostring(w.seconds),r.frames,r.elapsed(),r.changes,r.dropped,r.frame0)}
  r.lines(out)
  if w.failure then out[#out+1]='error '..(w.failure:gsub('[\r\n]',' '))end
  fs.write_atomic(M.WATCH,table.concat(out,'\n')..'\n')
 end
 k:command('menu_watch',function(payload)
  if watch then return'refused: a menu watch is already running'end
  local seconds=tonumber(tostring(payload or''):match('^%s*(%d+%.?%d*)%s*$'))
  if not(seconds and seconds>0 and seconds<=M.WATCH_SECONDS)then
   return'refused: expected a number of seconds above 0 and at most '..M.WATCH_SECONDS
  end
  local w={r=recorder(M.WATCH_CHANGES),seconds=seconds,deadline=fs.now()+seconds*1000}
  w.pre=k:step{phase='pre',name='menu_probe.watch.pre',order=-1e9,run=function()pcall(w.r.pre)end}
  -- A reading that raises ends the watch with what it has, so a broken reader
  -- cannot leave a watch that refuses every later one.
  w.post=k:step{phase='post',name='menu_probe.watch',order=900,run=function()
   local ok,why=pcall(w.r.post)
   if not ok then w.failure=tostring(why)end
   if w.failure or fs.now()>=w.deadline then finish_watch()end
  end}
  watch=w
  return'watching '..seconds..' s frame='..k.frame
 end)

 -- menu_action <action> <token> [all] ------------------------------------------
 local ALLOWED={};for i=1,NA do ALLOWED[ACTIONS[i]]=true end
 -- The byte written, made in a buffer of our own: the game's LuaJIT returns a
 -- wrong byte from string.char with several arguments in a compiled loop.
 local ONE=ffi.new('uint8_t[1]',1)
 local BYTE0={0}
 local writes,pending=0,nil
 local function action_file(a,state)
  local out={M.ACTION_HEADER,string.format('session=%s action=%d mode=%s frame0=%d write=%d/%d state=%s',
   tostring(session()or'-'),a.action,a.mode,a.r.frame0,a.number,M.WRITE_CAP,state)}
  for _,line in ipairs(a.notes)do out[#out+1]=line end
  a.r.lines(out)
  if state=='done'then out[#out+1]=string.format('end frames=%d changes=%d dropped=%d',a.r.frames,a.r.changes,a.r.dropped)end
  if a.failure then out[#out+1]='error '..(a.failure:gsub('[\r\n]',' '))end
  fs.write_atomic(M.ACTION,table.concat(out,'\n')..'\n')
 end
 -- The update after the write: a byte that still holds what was written is
 -- put back. The singleton is asked for again and must be the one written to;
 -- the menu is not asked, because a write that worked has changed it.
 local function restore(a)
  local p=process()
  local at,why=owner()
  for i,offset in ipairs(a.offsets)do
   local where=a.target+offset
   local seen=p.read(where,1)
   local line='restore +'..offset..' frame='..a.r.frames..' seen='..(seen and seen:byte()or'unreadable')
   if a.wrote[i]~=true or seen~=a.one or a.old[i]==a.one then line=line..' not needed'
   elseif at~=a.owner then line=line..' skipped: '..tostring(why or'the input singleton changed')
   elseif not p.writable(where,1)then line=line..' skipped: the entry is no longer writable'
   else
    local wrote=p.write(where,a.old[i]);local back=p.read(where,1)
    line=line..' wrote='..tostring(wrote)..' readback='..(back and back:byte()or'unreadable')
   end
   a.notes[#a.notes+1]=line
  end
 end
 local function act(payload)
  local function refuse(why)error(why,0)end
  local digits,token,mode=tostring(payload or''):match('^%s*(%d+)%s+(%S+)%s*(%S*)%s*$')
  if not digits or(mode~=''and mode~='all')then refuse('expected <action> <token> and optionally all')end
  local action=tonumber(digits)
  if pending then refuse('a menu action is still being recorded')end
  local current=session()
  if not current or token~=current then refuse('the token is not this session\'s')end
  if not ALLOWED[action]then refuse('action '..action..' is not one of '..table.concat(ACTIONS,', '))end
  if writes>=M.WRITE_CAP then refuse('this session has made its '..M.WRITE_CAP..' writes')end
  if k:need('scene').guard()~=true then refuse('the ship scene guard does not hold')end
  local adapter=ui();if not adapter then refuse('the Armory layout is not ready')end
  local menu,why=adapter:menu()
  if not menu then refuse('the menu is unreadable: '..tostring(why))end
  if not menu.armory then refuse('the presenter on top is '..tostring(menu.current)..', not the ship Armory')end
  if not menu.controller then refuse('the Armory controller is not registered once')end
  local p=process()
  local t=track
  if not(t and t.block and t.frame==k.frame-1 and t.stable>=1 and p.same(t.slot_at,t.slot)and p.same(t.at,t.block))then
   refuse('the menu state was not read unchanged in the update before: send menu_state, wait two updates and retry')
  end
  if u32(t.block,Menu.screen)~=Screen.armory then refuse('the menu state block does not show the ship Armory')end
  if action==States.select then
   -- The gear picker, not any grid: the kind is armor and the view is single.
   local grid=picker_grid();local shown=false
   for category=0,2 do
    if grid and type(grid.input_scope)=='function'and grid:input_scope(category)==true then shown=true end
   end
   if not(gear_page()==true or shown)then refuse('Select is allowed only on the gear page or with the gear picker shown')end
  end
  local at,owner_why=owner()
  if not at then refuse('the input singleton is unavailable: '..tostring(owner_why))end
  local target=entry(at,action)
  local offsets=mode=='all'and States.fields or BYTE0
  local old={}
  for i,offset in ipairs(offsets)do
   local where=target+offset
   local base,_,_,_,kind=p.region(where)
   if base==nil then refuse('the entry\'s memory is unknown')end
   if kind==Process.IMAGE then refuse('the entry lies in a module image, not on the heap')end
   if not(p.writable(where,1)and p.data(where))then refuse('the entry is not writable data')end
   old[i]=p.read(where,1)
   if not old[i]then refuse('the entry is unreadable')end
  end
  local a={action=action,mode=mode=='all'and'all'or'byte',owner=at,target=target,offsets=offsets,old=old,wrote={},notes={},
   one=ffi.string(ONE,1),r=recorder(M.ACTION_CHANGES)}
  -- The last look before the write: the same singleton and the same menu state.
  if owner()~=at then refuse('the input singleton changed in this update')end
  if not(p.same(t.slot_at,t.slot)and p.same(t.at,t.block))then refuse('the menu state changed in this update')end
  writes=writes+1;a.number=writes
  local landed=true
  for i,offset in ipairs(offsets)do
   local wrote,reason=p.write(target+offset,a.one);a.wrote[i]=wrote
   local back=p.read(target+offset,1)
   if wrote~=true or back~=a.one then landed=false end
   a.notes[i]='write +'..offset..' old='..old[i]:byte()..' wrote='..tostring(wrote)..(reason and' ('..reason..')'or'')
    ..' readback='..(back and back:byte()or'unreadable')
  end
  a.pre=k:step{phase='pre',name='menu_probe.action.pre',order=-1e9,run=function()pcall(a.r.pre)end}
  a.post=k:step{phase='post',name='menu_probe.action',order=900,run=function()
   if k.frame==a.r.frame0 then return end
   local ok,reason=pcall(a.r.post)
   if not ok then a.failure=tostring(reason)end
   if not a.restored then
    a.restored=true
    local done,failed=pcall(restore,a)
    if not done then a.notes[#a.notes+1]='restore failed: '..(tostring(failed):gsub('[\r\n]',' '))end
    action_file(a,'recording')
   end
   if a.failure or a.r.frames>=M.ACTION_FRAMES then
    a.pre.remove();a.post.remove();pending=nil
    action_file(a,'done')
   end
  end}
  pending=a
  -- On disk before the game's next update, in case that update is its last.
  action_file(a,'recording')
  if not landed then refuse('the write did not land; '..M.ACTION..' has what was read back')end
  return'written '..action..' frame='..k.frame
 end
 k:command('menu_action',function(payload)
  tracking()
  local ok,answer=pcall(act,payload)
  if ok then return answer end
  return'refused: '..(tostring(answer):gsub('^.-%.lua:%d+: ',''))
 end)
end
return M

end)()
local HD2TM_OWN = {DebugBridge=DebugBridge, DebugArmory=DebugArmory, DebugController=DebugController, DebugOpenArmory=DebugOpenArmory, NativeArmorProbe=NativeArmorProbe, RenderProbe=RenderProbe, CustomizationRawProbe=CustomizationRawProbe, ClothingRemoteProbe=ClothingRemoteProbe, SteamProbe=SteamProbe, PixelProbe=PixelProbe, IconProbe=IconProbe, BootDev=BootDev, EngineTests=EngineTests, EngineTestsCases=EngineTestsCases, EngineTestsCrash=EngineTestsCrash, MenuProbe=MenuProbe}
-- Last lines of the developer tools addon (tools/build.py puts its modules
-- above, as locals, and lists them in HD2TM_OWN): the debug bridge, the probes
-- and the commands that belong to no product stage.
for name, module in pairs(HD2TM_OWN) do
    if rawget(HD2TM_CORE, name) == nil then rawset(HD2TM_CORE, name, module) end
end
local env = HD2TM_KERNEL:need('env')
HD2TM_KERNEL:stage{name=BootDev.name, requires=BootDev.requires, owner='src/boot/dev.lua',
    start=function(k) return BootDev.start(k, env) end}
-- The in-engine test suite, developer addon only. A stage of its own so its
-- command and step withdraw if it fails to start and `stage.engine_tests`
-- reports it.
HD2TM_KERNEL:stage{name='engine_tests', requires={'dev'}, owner='src/engine_tests.lua',
    start=function(k) return EngineTests.start(k, env, EngineTestsCases, EngineTestsCrash) end}
-- The menu probe, developer addon only: commands that read the menu and the
-- input state for the validation host. A stage of its own, like the suite.
HD2TM_KERNEL:stage{name='menu_probe', requires={'dev'}, owner='src/menu_probe.lua',
    start=function(k) return MenuProbe.start(k, env) end}
HD2TM_KERNEL:provide('addon.' .. HD2TM_ADDON, true)
HD2TM_KERNEL:start()
env.off = HD2TM_KERNEL:stopped_stages()
return true
