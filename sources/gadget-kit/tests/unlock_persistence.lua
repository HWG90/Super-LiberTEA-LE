local Core=dofile('src/core.lua')
mod={require=function(p)
 if p=='src/core.lua'then return Core end
 assert(p=='src/freezes.lua')
 return {new=function()return {is_clean=function()return true end,set=function()return true end,stop=function()end,status=function()return ''end,update=function()end}end}
end}
local Controller=dofile('src/controller.lua')
local generation,valid=1,true
local rows={{address=100,identity='owned',category='weapons',state=2,amount=1,max_amount=1},
 {address=200,identity='locked',category='weapons',state=1,amount=0,max_amount=1}}
local b={writes=0,captures=0}
function b:context()if valid then return {generation=generation}end;return nil,'Loading' end
function b:same_context(a,c)return a and c and a.generation==c.generation end
function b:capture()
 self.captures=self.captures+1
 local s={context=self:context(),records={}}
 for _,r in ipairs(rows)do local n={};for k,v in pairs(r)do n[k]=v end;s.records[#s.records+1]=n end
 return s
end
function b:adapter(s)
 local io={}
 local function current(row)for _,r in ipairs(rows)do if r.address==row.address and r.identity==row.identity then return r end end end
 function io.matches(row)return current(row)~=nil end
 function io.read(row,field)local r=current(row);return r and r[field]end
 function io.write(row,field,value)
  local r=current(row);if not r then return false end
  if value==2 and not b:same_context(s.context,b:context())then return false end
  b.writes=b.writes+1;r[field]=value;return true
 end
 return io
end
local c=Controller.new(b)
assert(c:set_enabled(true))
local function advance(n)for _=1,n do c:update(.1)end end
advance(30);assert(rows[2].state==2 and rows[2].amount==1)
local captures=b.captures
rows[2].state=1;rows[2].amount=0;advance(30)
assert(rows[2].state==2 and rows[2].amount==1,'Owned overrides must survive in-place refresh')
assert(b.captures==captures,'Repair should not relock/recapture the entire catalogue')
rows[1].state=1;rows[1].amount=0;advance(30)
assert(rows[1].state==2 and rows[1].amount==1,'Initially unlocked rows must be reacquired when relocked')
valid=false;advance(20);generation=generation+1
rows={{address=100,identity='replacement',category='weapons',state=1,amount=0,max_amount=1}}
valid=true;advance(40);assert(rows[1].state==2 and rows[1].amount==1,'Reapply after session loading')
assert(c:set_enabled(false));advance(30)
assert(rows[1].state==1 and rows[1].amount==0 and c:is_clean(),'Disable must still restore owned writes')
rows[1].state=2;rows[1].amount=1
local empty=Controller.new(b);assert(empty:set_enabled(true));for _=1,30 do empty:update(.1)end
rows[1].state=1;for _=1,30 do empty:update(.1)end
assert(rows[1].state==2,'An empty initial plan must not stop maintenance')
print('PASS: refresh repair, newly relocked rows, session reload, identity replacement, disable restoration and empty-plan maintenance')
