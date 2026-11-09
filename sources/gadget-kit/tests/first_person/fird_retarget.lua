local R=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_retarget.lua')
local passed=0
local function test(name,fn)local ok,why=pcall(fn);assert(ok,name..': '..tostring(why));passed=passed+1 end
local function near(a,b)assert(math.abs(a-b)<.000001,tostring(a)..' ~= '..tostring(b))end
local function same(a,b)for i=1,3 do near(a[i],b[i])end end
local function distance(a,b)local n=0;for i=1,3 do n=n+(a[i]-b[i])^2 end;return math.sqrt(n)end
local I={0,0,0,1}
local function frame(x,y,z)return{position={x,y,z},rotation={unpack(I)}}end
local function fixture()
 return{shoulder=frame(0,0,0),elbow=frame(.25,.2,0),hand=frame(.5,0,0)},
  {shoulder=frame(0,0,0),elbow=frame(.3,0,0),hand=frame(.6,0,0)},
  {source={0,0,0},target={0,0,0},source_rotation=I,target_rotation=I}
end
test('TP shoulder seam and native segment lengths stay fixed while the hand reaches the locked FPS grip',function()
 local s,t,l=fixture();local a=assert(R.solve_arm(s,t,l))
 same(a.shoulder.position,t.shoulder.position);same(a.hand.position,s.hand.position)
 near(distance(a.shoulder.position,a.elbow.position),.3);near(distance(a.elbow.position,a.hand.position),.3)
 assert(a.elbow.position[2]>0 and a.reachable);near(a.reach_error,0)
end)
test('different TP limb proportions adapt through the elbow instead of stretching the mesh',function()
 local s,t,l=fixture();t.lengths={upper=.4,lower=.35};local a=assert(R.solve_arm(s,t,l))
 same(a.shoulder.position,{0,0,0});same(a.hand.position,{.5,0,0})
 near(distance(a.shoulder.position,a.elbow.position),.4);near(distance(a.elbow.position,a.hand.position),.35)
end)
local function support_fixture(goal)
 local s={shoulder=frame(0,.15,0),elbow=frame(.35,.25,0),hand=frame(goal or .7,0,0)}
 local t={clavicle=frame(0,0,0),shoulder=frame(0,.15,0),elbow=frame(.3,.15,0),hand=frame(.6,.15,0)}
 return s,t,{source={0,0,0},target={0,0,0},source_rotation=I,target_rotation=I}
end
test('minimal shoulder-support articulation keeps its base and all three TP lengths while reaching the grip',function()
 local s,t,l=support_fixture();local a=assert(R.solve_arm(s,t,l))
 assert(a.reachable and a.clavicle_adjusted and a.shoulder_shift>0)
 same(a.clavicle.position,{0,0,0});same(a.hand.position,{.7,0,0})
 near(distance(a.clavicle.position,a.shoulder.position),.15)
 near(distance(a.shoulder.position,a.elbow.position),.3);near(distance(a.elbow.position,a.hand.position),.3)
 local along=(.15^2-.6^2+.7^2)/(2*.7);local radius=math.sqrt(.15^2-along^2)
 same(a.shoulder.position,{along,radius,0})
 local minimum=distance(t.shoulder.position,a.shoulder.position)
 for degrees=0,360,10 do
  local angle=math.rad(degrees);local candidate={along,radius*math.cos(angle),radius*math.sin(angle)}
  assert(distance(t.shoulder.position,candidate)>=minimum-.0000001,'Support rotation was not the nearest sphere intersection')
 end
end)
test('support articulation remains idle for reachable poses and flags the physical maximum without stretching',function()
 local s,t,l=support_fixture(.5);local a=assert(R.solve_arm(s,t,l))
 assert(a.reachable and not a.clavicle_adjusted);same(a.shoulder.position,t.shoulder.position)
 same(a.clavicle.position,t.clavicle.position);near(a.clavicle_angle,0)
 s,t,l=support_fixture(1.2);a=assert(R.solve_arm(s,t,l))
 assert(not a.reachable);near(a.reach_error,.45);same(a.clavicle.position,{0,0,0})
 same(a.hand.position,{.75,0,0});near(distance(a.clavicle.position,a.shoulder.position),.15)
 near(distance(a.shoulder.position,a.elbow.position),.3);near(distance(a.elbow.position,a.hand.position),.3)
end)
test('copied live TP shoulder-support dimensions recover the observed 8.5cm grip deficit',function()
 local s,t,l=fixture();local upper,lower=.302745,.28718
 s.shoulder=frame(0,0,0);s.elbow=frame(.3,.2,0);s.hand=frame(upper+lower+.085,0,0)
 t.shoulder=frame(184.30209,-95.78657,16.65634);t.clavicle=frame(184.3554,-95.64546,16.61924)
 t.elbow=frame(184.30209+upper,-95.78657,16.65634);t.hand=frame(184.30209+upper+lower,-95.78657,16.65634)
 t.lengths={upper=upper,lower=lower};l.target={unpack(t.shoulder.position)}
 local support_length=distance(t.clavicle.position,t.shoulder.position)
 local a=assert(R.solve_arm(s,t,l));assert(a.reachable and a.clavicle_adjusted);near(a.reach_error,0)
 same(a.clavicle.position,t.clavicle.position);near(distance(a.clavicle.position,a.shoulder.position),support_length)
 near(distance(a.shoulder.position,a.elbow.position),upper);near(distance(a.elbow.position,a.hand.position),lower)
end)
test('the animated FPS elbow plane follows while the torso seam stays attached',function()
 local s,t,l=fixture();local a=assert(R.solve_arm(s,t,l));s.elbow.position[2]=-.2
 local b=assert(R.solve_arm(s,t,l));same(a.hand.position,b.hand.position);same(a.shoulder.position,b.shoulder.position)
 assert(a.elbow.position[2]>0 and b.elbow.position[2]<0)
end)
test('unreachable grip reports its error and preserves both TP lengths',function()
 local s,t,l=fixture();s.hand.position={1.5,0,0};s.elbow.position={.6,.3,0}
 local a,why=R.solve_arm(s,t,l);assert(a and not a.reachable and why)
 near(a.reach_error,.9);same(a.shoulder.position,{0,0,0})
 near(distance(a.shoulder.position,a.elbow.position),.3);near(distance(a.elbow.position,a.hand.position),.3)
 same(a.hand.position,{.6,0,0})
end)
test('minimum reach is bounded without collapsing or lengthening a segment',function()
 local s,t,l=fixture();s.hand.position={.05,0,0};s.elbow.position={.2,.1,0};t.lengths={upper=.5,lower=.2}
 local a=assert(R.solve_arm(s,t,l));assert(not a.reachable);near(a.reach_error,.25)
 near(distance(a.shoulder.position,a.elbow.position),.5);near(distance(a.elbow.position,a.hand.position),.2)
end)
test('independent virtual FPS and moving world TP frames do not share a stale world origin',function()
 local s,t,l=fixture();local q={0,0,math.sin(math.pi/4),math.cos(math.pi/4)}
 l.target={218,-155,25};l.target_rotation=q
 t.shoulder=frame(218,-155,25);t.elbow=frame(218,-154.7,25);t.hand=frame(218,-154.4,25)
 local a=assert(R.solve_arm(s,t,l));same(a.shoulder.position,{218,-155,25});same(a.hand.position,{218,-154.5,25})
 l.target={418,45,125};t.shoulder=frame(418,45,125);t.elbow=frame(418,45.3,125);t.hand=frame(418,45.6,125)
 local b=assert(R.solve_arm(s,t,l));same(b.shoulder.position,{418,45,125});same(b.hand.position,{418,45.5,125})
 near(distance(b.shoulder.position,b.elbow.position),.3);near(distance(b.elbow.position,b.hand.position),.3)
end)
test('finger articulation keeps TP segment length and rejects missing source directions',function()
 local s,t,l=fixture();local a=assert(R.solve_arm(s,t,l))
 local tip=assert(R.finger(a.hand,s.hand,frame(.55,.02,0),.04,l))
 near(distance(a.hand.position,tip.position),.04);assert(tip.position[2]>0)
 assert(R.finger(a.hand,s.hand,s.hand,.04,l)==nil)
end)
test('straight-arm singularity uses an explicit previous pole without inventing an elbow plane',function()
 local s,t,l=fixture();s.elbow.position={.25,0,0}
 assert(R.solve_arm(s,t,l)==nil);local a=assert(R.solve_arm(s,t,l,{0,1,0}));assert(a.elbow.position[2]>0)
end)
test('invalid frames lengths and ambiguous semantic hashes fail before any pose result',function()
 local s,t,l=fixture();s.hand.rotation={0,0,0,0};assert(R.solve_arm(s,t,l)==nil)
 s,t,l=fixture();t.lengths={upper=2,lower=.3};assert(R.solve_arm(s,t,l)==nil)
 assert(R.index({{hash=123},{hash=123}})==nil)
 local index=assert(R.index({{hash=0},{hash=123,node=5}}));assert(index[123]==5 and index[0]==nil)
end)
test('semantic map emits only arm descendants and preserves unmatched TP helpers and torso',function()
 local function inventory(rows)
  local out={by_hash={},by_index={}}
  for _,row in ipairs(rows)do
   local f=frame(row[4],row[5],row[6]);f.node,f.hash,f.parent=row[1],row[2],row[3]
   out.by_hash[f.hash]=f;out.by_index[f.node]=f
  end;return out
 end
 local h=R.hashes
 local s=inventory({{1,h.left.shoulder,nil,0,0,0},{2,h.left.elbow,1,.25,.2,0},{3,h.left.hand,2,.5,0,0},
  {4,0x123,3,.55,.02,0},{5,0x124,4,.58,.04,0},{6,0x125,1,0,0,0},
  {7,h.right.shoulder,nil,0,-.5,0},{8,h.right.elbow,7,.25,-.7,0},{9,h.right.hand,8,.5,-.5,0},
  {10,0x555,nil,-1,0,0},{11,0x129,3,.6,.1,0},{12,0x4FDD3337,nil,0,0,0},
  {13,0x89723B1E,12,2,0,0},{14,0x126,1,.2,0,0}})
 local t=inventory({{10,0x555,nil,10,19,30},{21,h.left.shoulder,10,10,20,30},{22,h.left.elbow,21,10.3,20,30},
  {23,h.left.hand,22,10.6,20,30},{24,0x123,23,10.64,20,30},{25,0x124,24,10.67,20,30},
  {26,0x125,21,10.05,20,30},{27,0x999,21,10.1,20,30},{28,0x129,27,10.15,20,30},{29,0x126,21,11.2,20,30},
  {31,h.right.shoulder,10,10,19.5,30},{32,h.right.elbow,31,10.3,19.5,30},{33,h.right.hand,32,10.6,19.5,30},
  {85,0x4FDD3337,23,10.7,20,30},{86,0x89723B1E,85,12.7,20,30}})
 local bones,stats=R.map(s,t,{source={0,0,0},target={10,20,30},source_rotation=I,target_rotation=I})
 assert(bones,stats);assert(bones[10]==nil and bones[27]==nil and bones[28]==nil and bones[29]==nil)
 assert(bones[85]==nil and bones[86]==nil,'TP hand children in the separate FPS weapon branch are not arm segments')
 same(bones[21].position,t.by_index[21].position);same(bones[23].position,{10.5,20,30})
 near(distance(bones[23].position,bones[24].position),.04);near(distance(bones[24].position,bones[25].position),.03)
 near(distance(bones[26].position,bones[21].position),.05)
 assert(stats.mapped==9 and stats.helpers_preserved==3 and stats.reachable)
 assert(stats.preserved_reasons[0x126]=='TP helper segment exceeds the arm limit')
 s.by_hash[h.right.hand]=nil;assert(R.map(s,t,{source={0,0,0},target={10,20,30},source_rotation=I,target_rotation=I})==nil)
end)
test('semantic map emits only the verified distinct shoulder-support joints without needing FPS counterparts',function()
 local function inventory(rows)
  local out={by_hash={},by_index={}}
  for _,row in ipairs(rows)do local f=frame(row[4],row[5],row[6]);f.node,f.hash,f.parent=row[1],row[2],row[3]
   out.by_hash[f.hash]=f;out.by_index[f.node]=f
  end;return out
 end
 local h=R.hashes
 local s=inventory({{11,h.left.shoulder,nil,0,.15,0},{13,h.left.elbow,11,.35,.25,0},{14,h.left.hand,13,.7,0,0},
  {31,h.right.shoulder,nil,0,-.45,0},{33,h.right.elbow,31,.25,-.65,0},{35,h.right.hand,33,.5,-.45,0}})
 local t=inventory({{29,0x10000,nil,0,-.15,0},{43,0xC4787B4E,29,0,0,0},
  {45,h.left.shoulder,43,0,.15,0},{47,h.left.elbow,45,.3,.15,0},{48,h.left.hand,47,.6,.15,0},
  {66,0xB2BCD839,29,0,-.3,0},{68,h.right.shoulder,66,0,-.45,0},{70,h.right.elbow,68,.3,-.45,0},{72,h.right.hand,70,.6,-.45,0}})
 local l={source={0,0,0},target={0,0,0},source_rotation=I,target_rotation=I}
 local bones,stats=R.map(s,t,l);assert(bones,stats)
 assert(bones[43]and bones[66]and not bones[29]);assert(stats.reachable and stats.mapped==8)
 same(bones[43].position,t.by_index[43].position);same(bones[48].position,{.7,0,0})
 assert(stats.arms.left.clavicle_adjusted and not stats.arms.right.clavicle_adjusted)
 t.by_index[43].hash=0x999
 bones,stats=R.map(s,t,l);assert(bones and not bones[43]and not stats.arms.left.reachable,'Unverified support hash must not articulate')
end)
test('native detail policy retains current TP fingers and unmatched helpers beneath FP primary targets',function()
 local function yaw(a)return{0,0,math.sin(a/2),math.cos(a/2)}end
 local function mul(a,b)return{a[4]*b[1]+a[1]*b[4]+a[2]*b[3]-a[3]*b[2],a[4]*b[2]-a[1]*b[3]+a[2]*b[4]+a[3]*b[1],
  a[4]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[4],a[4]*b[4]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3]}end
 local function inv(q)return{-q[1],-q[2],-q[3],q[4]}end
 local function rotate(q,p)local v=mul(mul(q,{p[1],p[2],p[3],0}),inv(q));return{v[1],v[2],v[3]}end
 local function relative(parent,child)
  local d={};for i=1,3 do d[i]=child.position[i]-parent.position[i]end
  return{position=rotate(inv(parent.rotation),d),rotation=mul(inv(parent.rotation),child.rotation)}
 end
 local function sameq(a,b)local d=0;for i=1,4 do d=d+a[i]*b[i]end;near(math.abs(d),1)end
 local function same_relative(native_parent,native_child,parent,child)
  local a,b=relative(native_parent,native_child),relative(parent,child)
  same(a.position,b.position);sameq(a.rotation,b.rotation)
 end
 local function inventory(rows)
  local out={by_hash={},by_index={}}
  for _,row in ipairs(rows)do local f=frame(row[4],row[5],row[6]);f.node,f.hash,f.parent=row[1],row[2],row[3]
   out.by_hash[f.hash]=f;out.by_index[f.node]=f
  end;return out
 end
 local h=R.hashes
 local s=inventory({{1,h.left.shoulder,nil,0,0,0},{2,h.left.elbow,1,.25,.2,0},{3,h.left.hand,2,.5,0,0},
  {4,0x123,3,.55,.02,0},{7,h.right.shoulder,nil,0,-.5,0},{8,h.right.elbow,7,.25,-.7,0},{9,h.right.hand,8,.5,-.5,0},
  {12,0x129,nil,0,0,0},{13,0x4FDD3337,nil,0,0,0}})
 local t=inventory({{21,h.left.shoulder,nil,10,20,30},{22,h.left.elbow,21,10.3,20,30},{23,h.left.hand,22,10.6,20,30},
  {24,0x123,23,10.64,20.02,30.01},{25,0x999,24,10.67,20.04,30.01},{26,0x129,23,10.7,20,30},
  {31,h.right.shoulder,nil,10,19.5,30},{32,h.right.elbow,31,10.3,19.5,30},{33,h.right.hand,32,10.6,19.5,30},
  {85,0x4FDD3337,23,10.7,20,30},{86,0x89723B1E,85,10.8,20,30}})
 s.by_index[3].rotation=yaw(-.2);s.by_index[4].rotation=yaw(1.1)
 t.by_index[23].rotation=yaw(.3);t.by_index[24].rotation=yaw(.7);t.by_index[25].rotation=yaw(-.1)
 local l={source={0,0,0},target={10,20,30},source_rotation=I,target_rotation=I}
 local function run()local b,why=R.map(s,t,l,nil,{native_details=true});return assert(b,why)end
 local a=run();assert(a[24]and a[25]and not a[26]and not a[85]and not a[86])
 same_relative(t.by_index[23],t.by_index[24],a[23],a[24])
 same_relative(t.by_index[24],t.by_index[25],a[24],a[25])
 s.by_index[4].position={.52,-.08,.03};s.by_index[4].rotation=yaw(-1.3)
 local b=run();same(a[24].position,b[24].position);sameq(a[24].rotation,b[24].rotation)
 t.by_index[24].position={10.63,20.04,30.02};t.by_index[24].rotation=yaw(.9)
 local c=run();assert(distance(c[24].position,b[24].position)>.001)
 same_relative(t.by_index[23],t.by_index[24],c[23],c[24])
 same_relative(t.by_index[24],t.by_index[25],c[24],c[25])
 s.by_index[3].position[2]=.05;s.by_index[3].rotation=yaw(.1)
 local d=run();assert(distance(d[23].position,c[23].position)>.01)
 same(d[23].position,{10.5,20.05,30});sameq(d[23].rotation,s.by_index[3].rotation)
 same_relative(t.by_index[23],t.by_index[24],d[23],d[24])
 same(t.by_index[21].position,{10,20,30});same(t.by_index[23].position,{10.6,20,30})
end)
test('visible arms carry exact FPS primary frames without IK or support articulation and retain TP details',function()
 local P=dofile(NATIVE_ADS_TEST_ROOT..'/src/fird_projection.lua')
 local function yaw(a)return{0,0,math.sin(a/2),math.cos(a/2)}end
 local function sameq(a,b)local d=0;for i=1,4 do d=d+a[i]*b[i]end;near(math.abs(d),1)end
 local function inventory(rows)
  local out={by_hash={},by_index={}}
  for _,row in ipairs(rows)do local f=frame(row[4],row[5],row[6]);f.node,f.hash,f.parent=row[1],row[2],row[3]
   out.by_hash[f.hash]=f;out.by_index[f.node]=f
  end;return out
 end
 local h=R.hashes;local q=yaw(.7)
 local s=inventory({{11,h.left.shoulder,nil,.1,.2,0},{13,h.left.elbow,11,.6,.3,.1},{14,h.left.hand,13,1.2,0,.2},
  {15,0x123,14,1.25,.02,.2},{31,h.right.shoulder,nil,0,-.45,0},{33,h.right.elbow,31,.25,-.65,0},{35,h.right.hand,33,.5,-.45,0}})
 local t=inventory({{29,0x10000,nil,218,-155,25},{43,0xC4787B4E,29,218,-155,25},
  {45,h.left.shoulder,43,218,-154.85,25},{47,h.left.elbow,45,218.3,-154.85,25},{48,h.left.hand,47,218.6,-154.85,25},
  {49,0x123,48,218.64,-154.84,25},{50,0x999,49,218.67,-154.84,25},
  {66,0xB2BCD839,29,218,-155.3,25},{68,h.right.shoulder,66,218,-155.45,25},
  {70,h.right.elbow,68,218.3,-155.45,25},{72,h.right.hand,70,218.6,-155.45,25}})
 s.by_index[14].rotation=yaw(.3);t.by_index[49].rotation=yaw(.4)
 local l={source={0,0,0},target={218,-155,25},source_rotation=I,target_rotation=q,rotation=q}
 local bones,stats=R.map(s,t,l,nil,{visible_arms=true,native_details=true});assert(bones,stats)
 assert(stats.visible_arms and stats.reachable and stats.reach_error==0)
 assert(stats.arms.left.direct and not stats.arms.left.clavicle and not bones[43]and not bones[66])
 for _,pair in ipairs({{11,45},{13,47},{14,48},{31,68},{33,70},{35,72}})do
  local src=s.by_index[pair[1]];local position,rotation=P.apply(l,src.position,src.rotation)
  same(bones[pair[2]].position,position);sameq(bones[pair[2]].rotation,rotation)
 end
 local hand={source=t.by_index[48].position,target=bones[48].position,rotation=yaw(1)}
 local finger,rotation=P.apply(hand,t.by_index[49].position,t.by_index[49].rotation)
 same(bones[49].position,finger);sameq(bones[49].rotation,rotation)
 assert(bones[50],'TP-only secondary helpers must follow the directly placed FPS arm')
 same(s.by_index[14].position,{1.2,0,.2});sameq(s.by_index[14].rotation,yaw(.3))
 for _,src in pairs(s.by_index)do for i=1,3 do src.position[i]=src.position[i]+100 end end
 l.source={100,100,100}
 local moved,why=R.map(s,t,l,nil,{visible_arms=true,native_details=true});assert(moved,why)
 for node,bone in pairs(bones)do same(moved[node].position,bone.position);sameq(moved[node].rotation,bone.rotation)end
 same(t.by_index[45].position,{218,-154.85,25})
end)
print('Fird TP-model retarget: '..passed..' shoulder/grip/length/plane/world-frame/finger/semantic-map cases passed')
