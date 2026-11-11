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
t:update(sample{controller_active=true},10.055,true,false)
local half=t:update(sample{controller_active=true},10.10,true,false)
assert(math.abs(half.progress-.5)<.00001)
-- Native4/6 request handoff does not restart the same logical ADS transition.
local native=t:update(sample{controller_active=true,camera_kind=4},10.11,true,false)
assert(native.epoch==enter.epoch and native.progress>half.progress)
local leave=t:update(sample(),10.12,true,false)
assert(leave.epoch>enter.epoch and leave.progress==0 and not leave.ads and leave.continuous)
-- Zoom, action and stance edges early in a blend join it; the same edges
-- after its midpoint, or once it has finished, start their own.
local joined=t:update(sample{zoom_identity=2},10.13,true,false)
assert(joined.epoch==leave.epoch and joined.reason=='ads_leave' and joined.merged=='zoom')
assert(joined.progress>0 and joined.progress<.5 and not joined.ads)
joined=t:update(sample{zoom_identity=2,action='sprint'},10.14,true,false)
assert(joined.epoch==leave.epoch and joined.merged=='action' and joined.progress<.5)
local late=t:update(sample{zoom_identity=2,action='sprint'},10.19,true,false)
late=t:update(sample{zoom_identity=2,action='sprint'},10.23,true,false)
assert(late.epoch==leave.epoch and late.progress>.5 and late.progress<1)
local zoom=t:update(sample{zoom_identity=3,action='sprint'},10.24,true,false)
assert(zoom.epoch>leave.epoch and zoom.reason=='zoom' and zoom.progress==0 and zoom.merged==nil)
for i=1,5 do t:update(sample{zoom_identity=3,action='sprint'},10.24+i*.05,true,false)end
assert(t:result().progress==1)
local action=t:update(sample{zoom_identity=3,action='idle'},10.50,true,false)
assert(action.reason=='action' and action.epoch>zoom.epoch and action.progress==0)
-- An ADS flip always starts its own phase, however early it arrives.
local flip=t:update(sample{zoom_identity=3,action='idle',controller_active=true},10.51,true,false)
assert(flip.reason=='ads_enter' and flip.epoch>action.epoch and flip.ads)
flip=t:update(sample{zoom_identity=2,action='sprint'},10.52,true,false)
assert(flip.reason=='ads_leave' and flip.progress==0)
local seat=t:update(sample{zoom_identity=2,action='sprint',seated=true,camera_kind=9},10.53,true,false)
assert(seat.reason=='seat')
-- Packet consumers cannot mutate the coordinator's authoritative phase.
seat.progress=99;assert(t:result().progress==0)
local swap=t:update(sample{identity='player/body/gun2'},10.54,true,false)
assert(swap.reason=='weapon' and not swap.continuous)
-- Nothing joins a weapon change: the new rig starts its own phase.
local after_swap=t:update(sample{identity='player/body/gun2',action='reload'},10.55,true,false)
assert(after_swap.reason=='action' and after_swap.epoch>swap.epoch)
local body=t:update(sample{identity='other/body/gun',player_identity='other/body'},10.56,true,false)
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
local held;for i=1,4 do held=action_return:update(sample{camera_kind=9},.01+i*.06,true,false)end;assert(held.progress==1)
local returned=action_return:update(sample{camera_kind=6},.26,true,false)
assert(returned.reason=='camera'and returned.epoch>into.epoch and returned.progress==0)
assert(action_return:update(sample{camera_kind=4},.27,true,false).epoch==returned.epoch)
-- One slow frame spends at most a third of a blend; the gap limit still retires.
local slow=Transition.new();slow:update(sample(),0,true,false)
slow:update(sample{controller_active=true},.01,true,false)
local hitched=slow:update(sample{controller_active=true},.21,true,false)
assert(hitched.reason=='ads_enter' and math.abs(hitched.progress-1/3)<.00001)
hitched=slow:update(sample{controller_active=true},.41,true,false)
assert(math.abs(hitched.progress-2/3)<.00001)
assert(slow:update(sample{controller_active=true},.70,true,false).reason=='initial')
-- The motion sampler's own action edge joins a running blend the same way.
local sampled=Transition.new();plain=sample();plain.action=nil
sampled:update(plain,0,true,false);sampled:action('idle',0)
sampled:update(plain,.01,true,false)
plain.shoulder_aim=true;local aimed=sampled:update(plain,.02,true,false);assert(aimed.reason=='shoulder')
local same_blend=sampled:action('aim',.02);assert(same_blend.epoch==aimed.epoch and same_blend.merged=='action')
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
