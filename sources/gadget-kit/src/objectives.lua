-- Mission Modification: complete every unfinished objective the way the game does.
-- ObjectiveComponent manager at game+0x2CE1F68: constructed objectives below +0x24,
-- entity pointers at +0x50, 0x1078-byte instances at +0x60 (local state +0x1018),
-- 0x64-byte replicated records at +0x68 (state +0x20: 0 active, 1 inactive,
-- 2 completed, 3 failed) and the entity key -> row map at +0x38. 5E1720(manager, key)
-- is the host's completion step that about 170 objective types reach through 4DEE60:
-- progress to its target, state 2, both replicated, discovered, completion flow event.
-- Its gate (5E23B0) indexes the instances with whatever the map returns, so a key is
-- passed only while its map entry names its own row. Entities without the authority
-- bit (+0x14 bit 0) are left alone, as the game's own state writes do (5DF688).
local M={}
local MANAGER,INSTANCE,RECORD,MAX_ROWS=0x2CE1F68,0x1078,0x64,256
local PINS={
 {0x5E1720,'48895c24184889742420574883ec203b159bd985028bfa488bf17507bbffffffffeb5f448b494033c0448b5148440fafd748896c2430418d69ff4585c974394c8b59388b594466660f1f8400000000008bcd428d14104823d1418b0cd34d8d04d33bcb0f84080100003bcf0f8408010000ffc0413bc172d8bbffffffff488b6c24308bd7488bcee8040c000084c00f84cd000000'},
 {0x5E17B4,'488b4660488b4e68448bc34969d078100000496bd8644c897424384e8d34c5000000008b840214100000ba4821920f89440b18488b46504c8b46684983c0184c03c3498b0c068b4910e8de808800488b4668bacc567b0bc744032002000000488b46504c8b46684983c0204c03c3498b0c068b4910e8b2808800'},
 {0x5E23B0,'4883ec083b1516cd85024c8bd17507b8ffffffffeb72448b49404533c048895c24108b594848896c24180fafda418d69ff488974242048893c24'},
 {0x5E2438,'8bc8498b42604869d1781000008b8c021810000083e90283f9010f97c04883c408'},
 {0x5DC365,'443961240f86af0e0000904d8b78608bf8498b40504869cf78100000488b34f84c03f948894d98498bc84c897df8488975888b5e088bd3895c2470e87ba500004c8b74243041898744100000418b871810000083f801751c498b4668486bcf648b44012083f8010f84330e00004189871810000085c00f85'},
 {0x5DF680,'498b4550488b0cd8f641140174304584c0742b498b45684d8d442420bacc567b0b42c744202003000000'},
 {0x5E95E4,'488b3d7d896f02488bea8b77203b7740'},
}
for _,p in ipairs(PINS)do p.bytes=p[2]:gsub('%x%x',function(v)return string.char(tonumber(v,16))end)end
local TERMINAL={[2]=true,[3]=true}
local function i32(v)if v and v>=2147483648 then return v-4294967296 end;return v end

function M.new(backend,log)
 local self={message='Ready',pending=false}
 local mem,elapsed,result=backend.mem,1,nil
 log=log or function()end
 function self:request()
  if self.pending then return false,'A request is already queued' end
  self.pending=true;self.message='Completing objectives';return true
 end
 function self:shutdown()self.pending=false;self.message='Off'end
 function self:status()return self.message end
 local function mission(c)
  local state,mode=mem:ptr(c.game+0x2CE1508),mem:ptr(c.game+0x2CE1850)
  return state and mode and mem:u32(state+0xAC29C)==4 and mem:u32(mode+8)==1
 end
 -- One objective row: its key, whether it is still open to this host, or why not.
 local function row(o,i)
  local entity=mem:ptr(o.entities+i*8)
  local key,flags=entity and mem:u32(entity+8),entity and mem:u8(entity+0x14)
  local state=i32(mem:u32(o.records+i*RECORD+0x20))
  local mirror=i32(mem:u32(o.instances+i*INSTANCE+0x1018))
  if not key or not flags or not state or not mirror then return nil,'Objective row is unreadable' end
  if state<0 or state>3 or mirror<0 or mirror>3 then return nil,'Objective state layout changed' end
  local unfinished=not TERMINAL[state] and not TERMINAL[mirror]
  return {key=key,state=state,open=unfinished and flags%2==1,foreign=unfinished and flags%2==0}
 end
 local function objectives(c)
  local manager=mem:ptr(c.game+MANAGER)
  if not manager then return nil,'Objectives are unavailable' end
  local cap,total,live=mem:u32(manager+0x18),mem:u32(manager+0x20),mem:u32(manager+0x24)
  if not cap or not total or not live or live>total or total>cap or cap>MAX_ROWS then
   return nil,'Objective manager bounds changed'
  end
  local o={manager=manager,live=live,entities=mem:ptr(manager+0x50),
   instances=mem:ptr(manager+0x60),records=mem:ptr(manager+0x68),rows={},done=0}
  if not o.entities or not o.instances or not o.records then return nil,'Objective arrays are unavailable' end
  for i=0,live-1 do
   local r,why=row(o,i)
   if not r then return nil,why end
   if TERMINAL[r.state] then o.done=o.done+1 end
   o.rows[#o.rows+1]=r
  end
  return o
 end
 -- The map entry must still name this row, and the row must still be open.
 local function still_open(o,i,key)
  if mem:ptr(MANAGER+o.game)~=o.manager or mem:u32(o.manager+0x24)~=o.live
   or mem:ptr(o.manager+0x50)~=o.entities or mem:ptr(o.manager+0x60)~=o.instances
   or mem:ptr(o.manager+0x68)~=o.records or mem:hashmap(o.manager+0x38,key)~=i then return false end
  local r=row(o,i)
  return r and r.key==key and r.open
 end
 function self:update(dt)
  elapsed=elapsed+math.max(0,math.min(1,tonumber(dt)or 0))
  if not self.pending and elapsed<.5 then return end
  elapsed=0
  local requested=self.pending
  self.pending=false
  local c,why=backend:gameplay_context()
  if not c then result=nil;self.message=why or 'Session unavailable';return end
  if not mission(c)then result=nil;self.message='Waiting for a mission';return end
  local o
  o,why=objectives(c)
  if not o then self.message=why;return end
  o.game=c.game
  if #o.rows==0 then self.message='No objectives in this mission';return end
  if not requested then
   self.message=string.format('%d of %d objectives complete',o.done,#o.rows)..(result and '; '..result or '')
   return
  end
  for _,pin in ipairs(PINS)do
   local bytes=mem:read(c.game+pin[1],#pin.bytes)
   if bytes~=pin.bytes then
    self.message=string.format(bytes and 'Objective code mismatch at game+%X' or 'Objective code at game+%X is not loaded yet',pin[1])
    return
   end
  end
  local fresh=backend:gameplay_context()
  if not fresh or not backend:same_context(c,fresh)then self.message='Session changed; try again';return end
  local completed,skipped,foreign=0,0,0
  for i,r in ipairs(o.rows)do
   if r.foreign then foreign=foreign+1 end
   if r.open then
    if still_open(o,i-1,r.key)then
     local ok,problem=mem:complete_objective(c.game,o.manager,r.key)
     if not ok then self.message=problem or 'Objective completion failed';return end
     completed=completed+1
    else skipped=skipped+1 end
   end
  end
  if completed==0 then
   self.message=skipped>0 and 'Objectives changed; try again'
    or foreign>0 and 'Another player owns the remaining objectives' or 'All objectives are already complete'
   return
  end
  result=string.format('completed %d now',completed)
  self.message=string.format('Completed %d objective%s',completed,completed==1 and '' or 's')
  log('Mission Modification: '..self.message..(foreign>0 and string.format('; %d owned by another player',foreign) or ''))
 end
 return self
end
M.fingerprints=PINS
return M
