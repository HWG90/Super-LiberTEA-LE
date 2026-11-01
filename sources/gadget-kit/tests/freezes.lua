local F=dofile('src/freezes.lua')
local ffi=require('ffi')
local checks=0
local function check(v) checks=checks+1; assert(v,'freeze check '..checks) end
local function packed(value)
    return ffi.string(ffi.new('float[1]',value),4)
end
local function fixture()
    local c={game=0x10000000,player=0x20000000,world=0x30000000}
    local state,inventory,manager,records=0x40000000,0x50000000,0x60000000,0x70000000
    local director=state+0x8556A8
    local pointers={[c.game+0x2CE1508]=state,[c.game+0x2CE1850]=state+0x1000000,
        [c.game+0x2CE1ED0]=director,[c.game+0x2CE18E8]=inventory,
        [inventory+80]=inventory+1000,[c.game+0x2CE17F8]=manager,[manager+0x50]=records}
    local words={[state+0xAC29C]=4,[state+0x1000008]=1,[director+0x684]=1,
        [director+0x5374C]=0,[c.player+0x3A8]=55,[c.world+0xF349E8]=123,
        [records]=3,[records+4]=30}
    local bytes={[director+0x53748]=packed(300),[records]=string.char(3,0,0,0,30,0,0,0)}
    local inv=ffi.new('uint32_t[12]'); inv[0]=88; inv[7]=1
    bytes[inventory+1000]=ffi.string(inv,48)
    local b={mem={_ffi=ffi},writes=0,valid=true}
    b.refreshes=0
    function b.mem:refresh_health(game,manager,entity)
        assert(game==c.game and manager==0x71000000 and entity==123)
        b.refreshes=b.refreshes+1
        return true
    end
    function b:context() if self.valid then return {game=c.game,player=c.player,world=c.world} end; return nil,'Not solo host' end
    function b:same_context(a,d) return a.world==d.world and a.player==d.player end
    function b.mem:ptr(a) return pointers[a] end
    function b.mem:u32(a) return words[a] end
    b.mem.u8=b.mem.u32
    function b.mem:hashmap(a,k)
        if a==c.world+0xF24990 and k==words[c.player+0x3A8] then return 0 end
        if a==inventory+40 and k==123 then return 0 end
        if a==manager+0x20 and k==88 then return 0 end
    end
    function b.mem:read(a,n)
        for base,v in pairs(bytes) do
            if a>=base and a+n<=base+#v then return v:sub(a-base+1,a-base+n) end
        end
    end
    function b.mem:copy(a,v) b.writes=b.writes+1; if b.fail then return false,'Readback failed' end; for base,old in pairs(bytes) do
            if a>=base and a+#v<=base+#old then
                bytes[base]=old:sub(1,a-base)..v..old:sub(a-base+#v+1); return true
            end
        end
        bytes[a]=v; return true end
    local hm,hd,hr,hx=0x71000000,0x72000000,0x73000000,0x74000000
    pointers[c.game+0x2CE1838]=hm; pointers[hm+0x1048]=hd; pointers[hd]=hd+1000
    pointers[hm+0x1058]=hr; pointers[hm+0x1060]=hx
    words[hm+0x1010]=1024; words[hm+0x1020]=1
    words[hd+1008]=123; words[hd+1012]=55; words[hd+1016]=55
    words[hr+412]=0; words[hr+20]=125; words[hx+20]=125
    bytes[hr+20]=string.char(125,0,0,0)
    bytes[c.game+9631376]=('488bc4488958104889701848897820554154415541564157488d68a14881ecf00000000f2970c8'):gsub('%x%x',function(v)return string.char(tonumber(v,16))end)
    local base_hash=b.mem.hashmap
    function b.mem:hashmap(a,k) if a==hm+0x1030 and k==123 then return 0 end; return base_hash(self,a,k) end
    return F.new(b),b,c,words,bytes,director,records,{address=hr+20,life=hr+412,unit=hd+1016,pointers=pointers}

end
local f,b,c,w,bytes,d,r,p=fixture()
f:update(); check(b.writes==0)
check(not f:set({freeze_health=true}))
check(f:set({freeze_health=true,freeze_timer=true,freeze_ammo=true,no_reload=true}))
f:update(); f:update(); check(b.writes==0)
bytes[d+0x53748]=packed(299); bytes[r]=string.char(2,0,0,0,29,0,0,0); w[p.address]=80; bytes[p.address]=string.char(80,0,0,0)
f:update(); check(b.writes==4 and bytes[d+0x53748]==packed(300) and bytes[p.address]==string.char(125,0,0,0))
f:update(); check(b.writes==4) -- No write when unchanged.
f:set({freeze_health=false,freeze_timer=false,freeze_ammo=false,no_reload=false})
bytes[d+0x53748]=packed(290); w[p.address]=75; bytes[p.address]=string.char(75,0,0,0); f:update()
check(b.writes==4 and bytes[p.address]==string.char(75,0,0,0) and bytes[d+0x53748]==packed(290))
f:set({freeze_health=true,freeze_timer=true,freeze_ammo=true,no_reload=true}); f:update(); f:update()
b.valid=false; f:update(); check(next(f.holds)==nil and b.writes==4)
b.valid=true; f:update(); f:update(); check(f.holds.freeze_health.bytes==string.char(75,0,0,0))
w[c.player+0x3A8]=56; w[p.unit]=56; w[p.address]=100; bytes[p.address]=string.char(100,0,0,0); f:update(); check(f.holds.freeze_health.bytes==string.char(100,0,0,0))
w[d+0x5374C]=1; f:update(); check(f.holds.freeze_timer==nil)
w[p.life]=1; f:update(); check(f.holds.freeze_health==nil)
b.fail=true; bytes[r]=string.char(1,0,0,0,1,0,0,0); f:update()
check(f.holds.freeze_ammo==nil and f:status():find('Readback failed',1,true))
f:stop(); check(next(f.holds)==nil and f:status()=='')
local g,bb,cc,ww=fixture()
g:set({freeze_health=true,freeze_timer=true,freeze_ammo=true,no_reload=true})
ww[0x40000000+0xAC29C]=3; g:update(); g:update(); check(g.holds.freeze_health~=nil and g.holds.freeze_ammo~=nil and g.holds.freeze_timer==nil and bb.writes==0)

-- Middle holds reserves only; right additionally holds the loaded rounds.
local h,hb,hc,hw,hbytes,hd,hr=fixture()
h:set({freeze_health=false,freeze_timer=false,freeze_ammo=true,no_reload=false})
h:update(); h:update()
hbytes[hr]=string.char(2,0,0,0,29,0,0,0); h:update()
check(hbytes[hr]==string.char(3,0,0,0,29,0,0,0) and hb.writes==1)
h:set({freeze_health=false,freeze_timer=false,freeze_ammo=true,no_reload=true}); h:update()
hbytes[hr]=string.char(2,0,0,0,28,0,0,0); h:update()
check(hbytes[hr]==string.char(3,0,0,0,29,0,0,0) and hb.writes==3)
h:set({freeze_health=false,freeze_timer=false,freeze_ammo=false,no_reload=false})
hbytes[hr]=string.char(2,0,0,0,28,0,0,0); h:update()
check(hb.writes==3 and hbytes[hr]==string.char(2,0,0,0,28,0,0,0))
local empty,eb,ec,ew,ebytes,ed,er=fixture()
ew[er+4]=0; ebytes[er]=string.char(3,0,0,0,0,0,0,0)
empty:set({freeze_health=false,freeze_timer=false,freeze_ammo=true,no_reload=true})
empty:update(); empty:update()
check(empty.holds.no_reload==nil and empty.holds.freeze_ammo~=nil and eb.writes==0)
ew[er+4]=30; ebytes[er]=string.char(3,0,0,0,30,0,0,0); empty:update()
check(empty.holds.no_reload~=nil)
-- A per-round weapon has no magazine row: its reserves and loaded rounds
-- occupy +0/+8 of a 20-byte row. Neighboring words must remain untouched.
local pr,pb,pc,pw,pbytes,pd,old,meta=fixture()
local pm,descs,desc,rr=0x75000000,0x76000000,0x77000000,0x78000000
meta.pointers[pc.game+0x2CE17F8]=nil
meta.pointers[pc.game+0x2CE1EB0]=pm
meta.pointers[pm+0x40]=descs;meta.pointers[descs]=desc;meta.pointers[pm+0x58]=rr
pw[desc+8]=88;pw[rr]=72;pw[rr+8]=5
pbytes[pc.game+0x762E4F]=('4c8b255af05702'):gsub('%x%x',function(v)return string.char(tonumber(v,16))end)
pbytes[pc.game+0x763076]=('498b4c24584b8d14b6eb7c'):gsub('%x%x',function(v)return string.char(tonumber(v,16))end)
local original_hash=pb.mem.hashmap
function pb.mem:hashmap(a,k) if a==pm+0x28 and k==88 then return 0 end;return original_hash(self,a,k) end
local function roundrow(reserve,loaded)
    return string.char(reserve,0,0,0)..'KEEP'..string.char(loaded,0,0,0)..'MORETAIL'
end
pbytes[rr]=roundrow(72,5)
pr:set({freeze_health=false,freeze_timer=false,freeze_ammo=true,no_reload=false})
pr:update();pr:update();check(pr.holds.freeze_ammo~=nil)
pbytes[rr]=roundrow(70,4);pw[rr]=70;pw[rr+8]=4;pr:update()
check(pbytes[rr]==roundrow(72,4) and pb.writes==1)
pr:set({freeze_health=false,freeze_timer=false,freeze_ammo=true,no_reload=true});pr:update()
pbytes[rr]=roundrow(71,3);pw[rr]=71;pw[rr+8]=3;pr:update()
check(pbytes[rr]==roundrow(72,4) and pb.writes==3)
pr:set({freeze_health=false,freeze_timer=false,freeze_ammo=false,no_reload=false})
pbytes[rr]=roundrow(70,2);pr:update();check(pb.writes==3 and pbytes[rr]==roundrow(70,2))
pr:set({freeze_health=false,freeze_timer=false,freeze_ammo=true,no_reload=true})
pw[desc+8]=99;pr:update();check(next(pr.holds)==nil and pb.writes==3)
pw[desc+8]=88;pbytes[pc.game+0x762E4F]='bad';pr:update()
check(next(pr.holds)==nil and pb.writes==3)
-- Backpack-fed support reserves belong to the matching worn pack, not the
-- weapon's empty local reserve word. Never write an unrelated pack or neighbor.
local bf,bb,bc,bw,bbytes,bd,localrounds,bmeta=fixture()
local inv=ffi.new('uint32_t[12]');inv[0]=88;inv[2]=88;inv[3]=99;inv[7]=3
bbytes[0x50000000+1000]=ffi.string(inv,48)
local dm,descs,desc,rr=0x79000000,0x7A000000,0x7B000000,0x7C000000
bmeta.pointers[bc.game+0x2CE1798]=dm;bmeta.pointers[dm+0x38]=descs
bmeta.pointers[descs]=desc;bmeta.pointers[dm+0x50]=rr
bw[desc+8]=99;bw[rr]=3;bbytes[rr]=string.char(3,0,0,0)..'PACK'
local function rt(hex)return (hex:gsub('%x%x',function(v)return string.char(tonumber(v,16))end)):reverse()end
bbytes[bc.world+0xF349E0+24]=rt('a8cffb316f0b5c5f');bw[bc.world+0xF349E0+24+8]=88
bbytes[bc.world+0xF349E0+48]=rt('e60ae045e0090f4c');bw[bc.world+0xF349E0+48+8]=99
local oldhash=bb.mem.hashmap
function bb.mem:hashmap(a,k)
    if a==bc.world+0xF1C978 then if k==88 then return 1 elseif k==99 then return 2 end end
    if a==dm+0x20 and k==99 then return 0 end
    return oldhash(self,a,k)
end
bf:set({freeze_health=false,freeze_timer=false,freeze_ammo=true,no_reload=false})
bf:update();bf:update();check(bf.holds.freeze_ammo.address==rr)
bbytes[rr]=string.char(2,0,0,0)..'PACK';bw[rr]=2;bf:update()
check(bbytes[rr]==string.char(3,0,0,0)..'PACK' and bb.writes==1)
bf:update();check(bb.writes==1)
bf:set({freeze_health=false,freeze_timer=false,freeze_ammo=false,no_reload=false})
bbytes[rr]=string.char(2,0,0,0)..'PACK';bf:update();check(bb.writes==1)
bf:set({freeze_health=false,freeze_timer=false,freeze_ammo=true,no_reload=false})
bw[desc+8]=100;bf:update();check(bf.holds.freeze_ammo==nil and bb.writes==1)
bw[desc+8]=99;bbytes[bc.world+0xF349E0+48]='SUPPLYPK';bf:update()
check(bbytes[rr]==string.char(2,0,0,0)..'PACK' and bf.holds.freeze_ammo.address==localrounds)
-- Refresh the engine once at acquisition and after damage; idle updates and
-- disabled/invalid owners must not emit native health notifications.
local nf,nb,nc,nw,nbytes,nd,nr,np=fixture()
nf:set({freeze_health=true,freeze_timer=false,freeze_ammo=false,no_reload=false})
nf:update();nf:update();check(nb.refreshes==1 and nb.writes==0)
nf:update();check(nb.refreshes==1 and nb.writes==0)
nw[np.address]=80;nbytes[np.address]=string.char(80,0,0,0);nf:update()
check(nb.refreshes==2 and nb.writes==1 and nbytes[np.address]==string.char(125,0,0,0))
nbytes[np.address]=string.char(80,0,0,0);nb.fail=true;nf:update()
check(nb.refreshes==2 and nf.holds.freeze_health==nil)
nb.fail=false;nw[np.life]=1;nf:update();check(nb.refreshes==2)
nw[np.life]=0;nb.valid=false;nf:update();check(nb.refreshes==2)
local sf,sb=fixture()
local opened,closed=0,0
function sb.mem:begin_snapshot()opened=opened+1 end
function sb.mem:end_snapshot()closed=closed+1 end
sf:update();check(opened==1 and closed==1)
sf:set({freeze_health=false,freeze_timer=true,freeze_ammo=false,no_reload=false})
sf:update();sf:update();check(opened==3 and closed==3)
sb.valid=false;sf:update();check(opened==4 and closed==4)

-- An unavailable unrelated code page must not prevent the timer hold.
local isolated,ib,ic,iw,ibytes,idirector=fixture()
function ib:validate_gameplay(feature)
    if feature=='freeze_health' then return false,'Health witness unavailable' end
    return true
end
assert(isolated:set({freeze_health=true,freeze_timer=true,freeze_ammo=false,no_reload=false}))
isolated:update();isolated:update()
ibytes[idirector+0x53748]=packed(250);isolated:update()
assert(ibytes[idirector+0x53748]==packed(300))
assert(isolated.messages.freeze_timer=='Holding' and isolated.messages.freeze_health=='Health witness unavailable')
isolated:stop()
ibytes[idirector+0x53748]=packed(249);isolated:update()
assert(ibytes[idirector+0x53748]==packed(249))
print('PASS: timer remains active when unrelated feature witnesses are unavailable; disabling resumes countdown')

return checks
