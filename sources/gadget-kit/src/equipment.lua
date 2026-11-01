-- Persist stable equipment IDs, never native addresses or live inventory rows.
local M={}
M.fields={'primary','pistol','grenade','helmet','cape','armor'}
local function valid(s)
 if type(s)~='table' or s.version~=1 then return false end
 for _,key in ipairs(M.fields)do local n=s[key];if type(n)~='number' or n%1~=0 or n<=0 or n>4294967295 then return false end end
 return true
end
local function copy(s)local r={version=1};for _,key in ipairs(M.fields)do r[key]=s[key]end;return r end
local function same(a,b)
 if not valid(a)or not valid(b)then return false end
 for _,key in ipairs(M.fields)do if a[key]~=b[key]then return false end end
 return true
end
function M.new(io,host,log)
 local stored=host.config and host.config.last_equipment
 local saved=valid(stored)and copy(stored)or nil
 local self={pending=saved~=nil}
 local elapsed,last,stable,notice=0,nil,0,nil
 log=log or function()end
 local function report(text)if notice~=text then notice=text;log('Remember equipment: '..text)end end
 function self:update(dt,ready,categories)
  if not ready then last,stable=nil,0;return end
  elapsed=elapsed+math.max(0,math.min(1,tonumber(dt)or 0))
  if elapsed<.5 then return end;elapsed=0
  local ok,current,why=pcall(io.capture,io)
  if not ok or not valid(current)then last,stable=nil,0;report(ok and (why or 'Waiting for equipment')or tostring(current));return end
  stable=same(current,last)and stable+1 or 1;last=copy(current)
  if stable<3 then return end
  if self.pending then
   local called,done,problem=pcall(io.restore,io,saved,categories,current)
   if not called or done~=true then report(called and (problem or 'Waiting to restore')or tostring(done));return end
   self.pending=false;last,stable=nil,0;report('Saved weapons and armor restored');return
  end
  if same(current,saved)then return end
  local called,done,problem=pcall(host.set,'last_equipment',copy(current))
  if not called or done~=true then report(called and (problem or 'Save failed')or tostring(done));return end
  saved=copy(current);report('Weapons and armor saved for next startup')
 end
 function self:shutdown()last,stable=nil,0 end
 return self
end
M.valid,M.same=valid,same
return M
