-- Nova weapon FOV, build 26251122: live calibration (task 'nova_sweep', at most 300 s).
-- While the player holds a Nova (resource key 73d84eaae8c75342) in full ADS at 1x (request lens
-- +0x84 settled at 90 deg), step the kind-6 request's presentation distance +0x90 through a list
-- of values, about 2 s each, logging each step to LinksLinkToMemory\nova_sweep.log so screenshots
-- can be matched to values. The evaluator at game+0x11192EA reads +0x90 every frame and places the
-- weapon's reference node at that depth (game+0x1119660), so a settled request shows a new value
-- at once. The request's own +0x90 is put back when the sweep ends or the request changes.
local VALUES={0.1565,0.10,0.05,0.0,-0.05,-0.10,-0.15}
local STEP_FRAMES=160
local path=os.getenv('LOCALAPPDATA')..'\\LinksLinkToMemory\\nova_sweep.log'
local log=assert(io.open(path,'a'))
local function line(...) log:write(os.date('%H:%M:%S'),' ',table.concat({...},' '),'\n') log:flush() end
local M=assert(ptr(game+0x2CE1EA0),'weapon manager')
local function is_nova(e)
 local cap,arr=u32(M+0x38),ptr(M+0x30)
 for b=0,cap-1 do if u32(arr+b*8)==e then local v=u32(arr+b*8+4)
  if v~=0xFFFFFFFF then local d=ptr(ptr(M+0x48)+v*8)
   return d and u32(d)==0xe8c75342 and u32(d+4)==0x73d84eaa end end end
 return false
end
local frames,step_i,step_at,held,orig=0,0,0,nil,nil
local function release(why)
 if held and orig and f32(held+0x90)~=orig then write(held+0x90,f32le(orig),'held') end
 if held then line('released',why or '',fmt('D back to %.5f',orig or -1)) end
 held,orig,step_i=nil,nil,0
end
line('sweep started')
local function step()
 frames=frames+1
 if frames>300*80 then release('time') line('sweep ended (time)') return true end
 local O=ptr(game+0x2E287D0);if not O then return false end
 local R=(u32(O+0x1F8)==u32(O+0x1FC)) and O+0x1F00 or O+0x200+((u32(O+0x1FC)-1)%32)*0xE8
 local settled=u16(R)==6 and math.abs(math.deg(f32(R+0x84))-90)<0.01
 if held and (R~=held or not settled) then release('request changed') return false end
 if not settled then return false end
 if not held then
  if not is_nova(u32(R+8)) then return false end
  held,orig,step_i,step_at=R,f32(R+0x90),0,frames
  line(fmt('holding request 0x%X weapon %d D %.5f',R,u32(R+8),orig))
 end
 if step_i==0 or frames-step_at>=STEP_FRAMES then
  step_i=step_i+1
  if step_i>#VALUES then release('done') line('sweep done') return true end
  step_at=frames
  write(R+0x90,f32le(VALUES[step_i]),'held')
  line(fmt('step %d D %.4f',step_i,VALUES[step_i]))
 elseif f32(R+0x90)~=VALUES[step_i] then
  write(R+0x90,f32le(VALUES[step_i]),'held')
 end
 return false
end
return background('nova_sweep',step,function() pcall(function() release('cleanup') line('sweep closed') log:close() end) end)
