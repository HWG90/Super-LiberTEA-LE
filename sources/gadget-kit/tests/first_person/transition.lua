local root=assert(NATIVE_ADS_TEST_ROOT)
local Transition=dofile(root..'/src/transition.lua')
local function sample(changes)
 local s={identity='player/body/gun',player_identity='player/body',controller_active=false,camera_kind=6,seated=false,zoom_identity=1,action='idle'}
 for k,v in pairs(changes or{})do s[k]=v end;return s
end
local t=Transition.new();local initial=t:update(sample(),10,true,false)
assert(initial.progress==1 and initial.reason=='initial')
local enter=t:update(sample{controller_active=true},10.01,true,false)
assert(enter.epoch>initial.epoch and enter.progress==0 and enter.ads)
local half=t:update(sample{controller_active=true},10.10,true,false)
assert(math.abs(half.progress-.5)<.00001)
-- Native4/6 request handoff does not restart the same logical ADS transition.
local native=t:update(sample{controller_active=true,camera_kind=4},10.11,true,false)
assert(native.epoch==enter.epoch and native.progress>half.progress)
local leave=t:update(sample(),10.12,true,false)
assert(leave.epoch>enter.epoch and leave.progress==0 and not leave.ads and leave.continuous)
local zoom=t:update(sample{zoom_identity=2},10.13,true,false)
assert(zoom.epoch>leave.epoch and zoom.reason=='zoom')
local action=t:update(sample{zoom_identity=2,action='sprint'},10.14,true,false)
assert(action.reason=='action')
local seat=t:update(sample{zoom_identity=2,action='sprint',seated=true,camera_kind=9},10.15,true,false)
assert(seat.reason=='seat')
-- Packet consumers cannot mutate the coordinator's authoritative phase.
seat.progress=99;assert(t:result().progress==0)
local swap=t:update(sample{identity='player/body/gun2'},10.16,true,false)
assert(swap.reason=='weapon' and not swap.continuous)
local body=t:update(sample{identity='other/body/gun',player_identity='other/body'},10.17,true,false)
assert(body.reason=='initial' and body.progress==1 and not body.continuous)
local hitch=t:update(sample{identity='other/body/gun',player_identity='other/body'},11,true,false)
assert(hitch.reason=='initial' and hitch.progress==1)
assert(t:update(sample(),11.01,true,true)==nil and t:result()==nil)
assert(t:update(sample(),11.02,false,false)==nil)
assert(t:update({},11.03,true,false)==nil)
local back=t:update(sample(),12,true,false);assert(back.progress==1)
local clock=t:update(sample(),11.9,true,false);assert(clock.reason=='initial'and clock.progress==1)
-- Progress is frame-rate independent, bounded, and held clocks never advance.
for _,fps in ipairs{30,60,144}do
 local c=Transition.new();c:update(sample(),0,true,false)
 local edge=c:update(sample{controller_active=true},.01,true,false)
 local p=c:update(sample{controller_active=true},.01,true,false);assert(p.progress==0 and p.epoch==edge.epoch)
 for i=1,math.ceil(.18*fps)do p=c:update(sample{controller_active=true},.01+i/fps,true,false)end
 assert(p.progress==1)
end
local observer=Transition.new();local plain=sample();plain.action=nil
observer:update(plain,0,true,false);observer:action('idle',0)
observer:update(plain,.01,true,false)
local changed=observer:action('reload',.01)
assert(changed.reason=='action'and changed.progress==0)
observer:update(plain,.02,true,false)
assert(observer:action('reload',.02).epoch==changed.epoch)
local resume=observer:resume(plain.identity,plain.player_identity,.02);assert(resume.reason=='reacquire')
assert(observer:resume('wrong',plain.player_identity,.02)==nil)
local action_return=Transition.new();action_return:update(sample(),0,true,false)
local into=action_return:update(sample{camera_kind=9},.01,true,false);assert(into.reason=='camera')
action_return:update(sample{camera_kind=9},.11,true,false);local held=action_return:update(sample{camera_kind=9},.21,true,false);assert(held.progress==1)
local returned=action_return:update(sample{camera_kind=6},.22,true,false)
assert(returned.reason=='camera'and returned.epoch>into.epoch and returned.progress==0)
assert(action_return:update(sample{camera_kind=4},.23,true,false).epoch==returned.epoch)
print('Shared presentation phase: ADS reversal, native request, zoom/action/seat, identity retirement, hitch, immutable copy and frame rate cases passed')

-- Rendering-only action flags never become firearm ADS authority.
do
 local T=dofile(NATIVE_ADS_TEST_ROOT..'/src/first_person/transition.lua')
 local function ads(mask,seated,guard,flag)
  return T.native_ads({controller_active=true,seated=seated,controller_bytes=string.char(mask,0,0,0,flag or 1,guard or 0)})
 end
 assert(ads(0,false)and ads(2,false))
 assert(not ads(0,true)and not ads(32,false)and not ads(0,false,1)and not ads(0,false,0,0))
 assert(not T.native_ads({controller_active=true,seated=false}))
 print('Shared/native ADS classification: on-foot mask0/2 only; seat/action/unavailable refuse')
end
