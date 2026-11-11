// Synthetic private buffers and local callbacks only; never accesses the game.
#define NADSN_FIXTURE
#include "native_ads_near.cpp"
#include <cstdio>
#include <cstdlib>
#define CHECK(x) do{if(!(x)){std::fprintf(stderr,"FAIL %d: %s error=%u\n",__LINE__,#x,NADSN_Error());std::abort();}}while(0)
static uint64_t active_generation=0,cases=0,calls=0;
struct Record {void* camera;float value;};static Record records[4096]{};
__declspec(noinline) static void synthetic_setter(void* camera,float value) {
    CHECK(calls<4096);records[calls].camera=camera;records[calls++].value=value;
    std::memcpy(static_cast<char*>(camera)+0x28,&value,4);
}
__declspec(noinline) static void foreign_setter(void*,float) {}
template<class T> static void put(uint64_t at,const T& v) {std::memcpy(reinterpret_cast<void*>(at),&v,sizeof v);}
static uint64_t allocate(size_t n,DWORD protection=PAGE_READWRITE) {
    const auto p=VirtualAlloc(nullptr,n,MEM_COMMIT|MEM_RESERVE,protection);CHECK(p);return reinterpret_cast<uint64_t>(p);
}
static void literal(uint64_t at,const char* hex) {
    auto digit=[](char c)->uint8_t{return static_cast<uint8_t>(c<='9'?c-'0':c-'a'+10);};
    for(size_t i=0;i<std::strlen(hex)/2;++i)put<uint8_t>(at+i,static_cast<uint8_t>((digit(hex[i*2])<<4)|digit(hex[i*2+1])));
}
static void fake_image(uint64_t base,uint32_t stamp,uint32_t size) {
    IMAGE_DOS_HEADER dos{};dos.e_magic=IMAGE_DOS_SIGNATURE;dos.e_lfanew=128;
    IMAGE_NT_HEADERS64 nt{};nt.Signature=IMAGE_NT_SIGNATURE;nt.FileHeader.Machine=IMAGE_FILE_MACHINE_AMD64;
    nt.FileHeader.TimeDateStamp=stamp;nt.OptionalHeader.Magic=IMAGE_NT_OPTIONAL_HDR64_MAGIC;nt.OptionalHeader.SizeOfImage=size;
    put(base,dos);put(base+128,nt);
}
static uint32_t begin_current(const NADSN_Config* c) {
    uint64_t token=UINT64_MAX;const uint32_t result=NADSN_Begin(c,&token);
    if(result==0)CHECK(token==0);else {CHECK((result==1 || result==2) && token && token!=active_generation);active_generation=token;}
    return result;
}
static uint32_t end_current() {return NADSN_End(active_generation);}
static float last() {return records[calls-1].value;}
static void pass(const char* name) {++cases;std::printf("PASS %s\n",name);}
static constexpr float NATIVE=.05f;
struct Fixture {
    NADSN_Config c{};uint64_t controller=0,api=0,slot_address=0,second_site=0;Setter invoke=nullptr,invoke_second=nullptr;
    Fixture() {
        c.size=sizeof c;c.abi=1;c.game=allocate(0x3382000,PAGE_EXECUTE_READWRITE);c.exe=allocate(0x29fe000);
        fake_image(c.game,0x6af322c1,0x3382000);fake_image(c.exe,0x6af2d5e6,0x29fe000);
        // Independent literal read-only capture: LLtM batch 4457 and the 26251122 game.dll capture.
        literal(c.exe+0x2dd050,"f30f114928e9c66b1f00");literal(c.exe+0x2dd030,"f30f104128c3");
        literal(c.game+0x2245efc,"cdcc4c3d");
        literal(c.game+0x110ddec,"488b05d536bd01f30f100d01811301498b0f440f29bc2490010000488b5020ff5268");
        c.context=allocate(0x3000);c.camera=allocate(0x1000);c.avatar_owner=allocate(0x540000);c.avatar_index=0;
        controller=allocate(0x1000);
        put<uint64_t>(c.game+0x2e287d0,c.context);put<uint64_t>(c.context,c.camera);
        put<uint64_t>(c.game+0x2ce1ee0,c.avatar_owner);put<uint32_t>(c.avatar_owner+0x6C,1);
        put<uint64_t>(c.game+0x2e381a8,controller);
        const uint64_t root=allocate(0x1000);api=allocate(0x1000);slot_address=api+0x68;
        put<uint64_t>(c.game+0x2ce14c8,root);put<uint64_t>(root+0x20,api);
        put<uint64_t>(api+0x58,c.exe+0x2dd030);put<uint64_t>(slot_address,reinterpret_cast<uint64_t>(synthetic_setter));
        fixture_target=synthetic_setter;
        // Stub: sub rsp,28; mov rdx,API; jmp into the real call [rdx+68] at 0x110DE0B,
        // whose return address 0x110DE0E then holds add rsp,28; ret.
        const uint64_t stub=c.game+0x1000,site=c.game+0x110de0b;
        literal(stub,"4883ec2848ba");put<uint64_t>(stub+6,api);put<uint8_t>(stub+14,0xe9);
        put<int32_t>(stub+15,static_cast<int32_t>(site-(stub+19)));literal(site+3,"4883c428c3");
        CHECK(FlushInstructionCache(GetCurrentProcess(),reinterpret_cast<void*>(c.game),0x3382000));
        invoke=reinterpret_cast<Setter>(stub);c.hip=.15f;c.aim=0;normal();
        // A second game.dll caller (like 0x111090F): sub rsp,28; mov rdx,API; call [rdx+68]; add rsp,28; ret.
        const uint64_t second=c.game+0x2000;literal(second,"4883ec2848ba");put<uint64_t>(second+6,api);
        literal(second+14,"ff52684883c428c3");second_site=second+17;
        CHECK(FlushInstructionCache(GetCurrentProcess(),reinterpret_cast<void*>(second),32));
        invoke_second=reinterpret_cast<Setter>(second);
    }
    void shoulder(bool held) {put<uint8_t>(c.avatar_owner+0x53e892,held?4:0);put<uint8_t>(c.avatar_owner+0x53e897,held?32:0);}
    void ads(bool held) {put<uint8_t>(controller+4,held?1:0);}
    void top(uint32_t kind,uint32_t tail) {
        put<uint32_t>(c.context+0x1F8,0);put<uint32_t>(c.context+0x1FC,tail);
        put<uint32_t>(c.context+0x200+((tail+31)%32)*0xE8,kind);put<uint32_t>(c.context+0x1F00,4);
    }
    void normal() {ads(false);shoulder(false);top(4,0);}
    void fp() {ads(false);shoulder(false);top(6,2);}
    void begin() {fp();CHECK(begin_current(&c)==1);}
    uint64_t slot() {uint64_t v=0;std::memcpy(&v,reinterpret_cast<void*>(slot_address),8);return v;}
    // A second passes before each ordinary sample, so it lands at once;
    // frame() advances by a real frame time and exercises the ease.
    void sample(float f=NATIVE,uint64_t camera=0) {fixture_now_us+=1000000;invoke(reinterpret_cast<void*>(camera?camera:c.camera),f);}
    void sample_second(float f=NATIVE) {fixture_now_us+=1000000;invoke_second(reinterpret_cast<void*>(c.camera),f);}
    float frame(uint64_t microseconds=16667) {fixture_now_us+=microseconds;invoke(reinterpret_cast<void*>(c.camera),NATIVE);return records[calls-1].value;}
    float distance() {float v=0;std::memcpy(&v,reinterpret_cast<void*>(c.camera+0x28),4);return v;}
    NADSN_Stats stats() {NADSN_Stats s{};s.size=sizeof s;s.abi=1;CHECK(NADSN_ReadStats(reserved.load()?active_generation:0,&s)==1);return s;}
};
int main() {
    Fixture f;CHECK(f.stats().installed==0);

    f.begin();CHECK(f.slot()==callback() && f.stats().installed==1 && f.stats().armed==1);
    f.sample();CHECK(last()==.15f && records[calls-1].camera==reinterpret_cast<void*>(f.c.camera) && f.stats().replaced==1);
    CHECK(f.stats().last_native==NATIVE && f.stats().last_applied==.15f);
    CHECK(end_current()==1 && f.slot()==reinterpret_cast<uint64_t>(synthetic_setter) && f.stats().installed==0);
    pass("first-person hip receives the configured distance at the game's own call; End restores the slot");

    f.begin();f.top(4,0);f.sample();CHECK(last()==NATIVE && f.stats().other_kind==1 && f.stats().armed==1);
    f.top(6,2);f.sample();CHECK(last()==.15f);CHECK(end_current()==1);
    pass("the normal third-person request keeps the game's distance while the lease stays armed");

    f.begin();f.ads(true);f.sample();CHECK(last()==NATIVE && f.stats().ads_forwarded==1);
    f.shoulder(true);f.sample();CHECK(last()==NATIVE && f.stats().ads_forwarded==2 && f.stats().aim_applied==0);
    f.ads(false);f.shoulder(false);f.sample();CHECK(last()==.15f);CHECK(end_current()==1);
    pass("full ADS always forwards the game's distance, even with normal-aim flags set");

    f.begin();f.shoulder(true);f.sample();CHECK(last()==NATIVE && f.stats().aim_applied==0);
    CHECK(NADSN_Set(active_generation,.15f,.1f)==1);f.sample();CHECK(last()==.1f && f.stats().aim_applied==1);
    put<uint8_t>(f.c.avatar_owner+0x53e897,0);f.sample();CHECK(last()==.15f);
    CHECK(end_current()==1);pass("normal aim uses the aim distance (zero keeps the game's); a lone flag is hip");

    f.begin();CHECK(NADSN_Set(active_generation,.03f,.02f)==1);f.sample();CHECK(last()==NATIVE && f.stats().replaced==0);
    f.sample(.5f);CHECK(last()==.5f);CHECK(NADSN_Set(active_generation,.4f,0)==1);f.sample();CHECK(last()==.4f);
    CHECK(end_current()==1);pass("a distance at or below the game's forwards its value unchanged; Set applies live");

    f.begin();reinterpret_cast<Setter>(f.slot())(reinterpret_cast<void*>(f.c.camera),NATIVE);CHECK(last()==NATIVE);
    const uint64_t other=allocate(0x1000);f.sample(NATIVE,other);CHECK(last()==NATIVE && records[calls-1].camera==reinterpret_cast<void*>(other));
    CHECK(f.stats().replaced==0 && f.stats().forwarded==2 && f.stats().armed==1);CHECK(end_current()==1);
    pass("other callers and other cameras pass through the slot unchanged");

    f.begin();const uint64_t replacement=allocate(0x1000);put<uint64_t>(f.c.context,replacement);
    f.sample();CHECK(last()==NATIVE && f.stats().armed==0 && f.stats().error==OWNER_MISMATCH && f.stats().installed==1);
    f.sample();CHECK(last()==NATIVE);put<uint64_t>(f.c.context,f.c.camera);f.sample();CHECK(last()==NATIVE);
    CHECK(end_current()==1 && f.slot()==reinterpret_cast<uint64_t>(synthetic_setter));
    f.begin();put<uint32_t>(f.c.avatar_owner+0x6C,0);f.sample();CHECK(last()==NATIVE && f.stats().armed==0);
    put<uint32_t>(f.c.avatar_owner+0x6C,1);CHECK(end_current()==1);
    pass("a replaced camera or retired avatar row disarms permanently until End");

    f.begin();put<uint64_t>(f.slot_address,reinterpret_cast<uint64_t>(foreign_setter));CHECK(end_current()==1);
    CHECK(f.slot()==reinterpret_cast<uint64_t>(foreign_setter) && f.stats().installed==0);
    put<uint64_t>(f.slot_address,reinterpret_cast<uint64_t>(synthetic_setter));
    pass("End preserves a foreign replacement of the slot");

    f.begin();const uint64_t owned=active_generation;uint64_t token=UINT64_MAX;
    CHECK(NADSN_Begin(&f.c,&token)==0 && token==0 && NADSN_Error()==BUSY);
    CHECK(NADSN_Set(owned+1,.2f,0)==0 && NADSN_Error()==TOKEN_MISMATCH);
    CHECK(NADSN_Set(owned,1.5f,0)==0 && NADSN_Error()==INVALID_CONFIG);
    CHECK(NADSN_Set(owned,.2f,NAN)==0 && NADSN_Error()==INVALID_CONFIG);
    NADSN_Stats s{};s.size=sizeof s;s.abi=1;CHECK(NADSN_ReadStats(0,&s)==0 && NADSN_ReadStats(owned+1,&s)==0);
    CHECK(end_current()==1 && NADSN_End(owned)==1 && NADSN_End(owned+1)==0);
    pass("BUSY while reserved; Set/ReadStats/End only accept the owned generation; bounds enforced");

    const uint64_t before=fixture_cas_calls;
    f.fp();literal(f.c.game+0x2245efc,"0000803f");CHECK(begin_current(&f.c)==0 && NADSN_Error()==CODE_MISMATCH);
    literal(f.c.game+0x2245efc,"cdcc4c3d");literal(f.c.game+0x110de0b,"ff5270");CHECK(begin_current(&f.c)==0 && NADSN_Error()==CODE_MISMATCH);
    literal(f.c.game+0x110de0b,"ff5268");literal(f.c.exe+0x2dd050,"f30f114934");CHECK(begin_current(&f.c)==0 && NADSN_Error()==CODE_MISMATCH);
    literal(f.c.exe+0x2dd050,"f30f114928");put<uint32_t>(f.c.game+128+8,0);CHECK(begin_current(&f.c)==0 && NADSN_Error()==IMAGE_MISMATCH);
    put<uint32_t>(f.c.game+128+8,0x6af322c1);
    put<uint64_t>(f.slot_address,reinterpret_cast<uint64_t>(foreign_setter));CHECK(begin_current(&f.c)==0 && NADSN_Error()==API_MISMATCH);
    put<uint64_t>(f.slot_address,reinterpret_cast<uint64_t>(synthetic_setter));
    put<uint64_t>(f.api+0x58,f.c.exe+0x2dd040);CHECK(begin_current(&f.c)==0 && NADSN_Error()==API_MISMATCH);
    put<uint64_t>(f.api+0x58,f.c.exe+0x2dd030);
    fixture_slot_readonly=true;CHECK(begin_current(&f.c)==0 && NADSN_Error()==SLOT_NOT_WRITABLE);fixture_slot_readonly=false;
    CHECK(fixture_cas_calls==before && f.slot()==reinterpret_cast<uint64_t>(synthetic_setter));
    pass("changed constant, call site, setter, image, slot or getter is refused before any slot write");

    NADSN_Config bad=f.c;bad.hip=2;CHECK(begin_current(&bad)==0 && NADSN_Error()==INVALID_CONFIG);
    bad=f.c;bad.aim=-1;CHECK(begin_current(&bad)==0);bad=f.c;bad.abi=2;CHECK(begin_current(&bad)==0);
    bad=f.c;bad.reserved=1;CHECK(begin_current(&bad)==0);bad=f.c;bad.avatar_index=8;CHECK(begin_current(&bad)==0);
    put<uint64_t>(f.c.context,allocate(0x1000));CHECK(begin_current(&f.c)==0 && NADSN_Error()==OWNER_MISMATCH);
    put<uint64_t>(f.c.context,f.c.camera);CHECK(fixture_cas_calls==before && reserved.load()==0);
    pass("invalid configuration or an unowned camera is refused without a lease");

    fixture_cas_fail_at=fixture_cas_calls+1;CHECK(begin_current(&f.c)==0 && NADSN_Error()==CAS_FAULT && reserved.load()==0);
    CHECK(f.slot()==reinterpret_cast<uint64_t>(synthetic_setter));fixture_cas_fail_at=0;
    fixture_foreign_value=reinterpret_cast<uint64_t>(foreign_setter);fixture_foreign_cas_at=fixture_cas_calls+1;
    CHECK(begin_current(&f.c)==0 && NADSN_Error()==CAS_MISMATCH && reserved.load()==0);
    CHECK(f.slot()==reinterpret_cast<uint64_t>(foreign_setter));fixture_foreign_cas_at=0;
    put<uint64_t>(f.slot_address,reinterpret_cast<uint64_t>(synthetic_setter));
    pass("an install fault or a foreign racer leaves no lease and never overwrites the racer");

    f.begin();f.sample_second();CHECK(last()==.15f && f.distance()==.15f);f.sample_second(1.0f);CHECK(last()==1.0f);
    f.sample_second(.05000001f);CHECK(last()==.05000001f);f.ads(true);f.sample_second();CHECK(last()==NATIVE);f.ads(false);
    CHECK(end_current()==1);pass("any game.dll caller setting exactly the game's 0.05 is covered; other values pass through");

    f.begin();f.sample();CHECK(f.distance()==.15f);const uint64_t before_end=calls;CHECK(end_current()==1);
    CHECK(calls==before_end+1 && last()==NATIVE && f.distance()==NATIVE && records[calls-1].camera==reinterpret_cast<void*>(f.c.camera));
    f.begin();f.sample();f.sample(.3f);const uint64_t foreign_end=calls;CHECK(end_current()==1 && calls==foreign_end && f.distance()==.3f);
    f.begin();f.sample();put<uint64_t>(f.c.context,allocate(0x1000));const uint64_t moved_end=calls;CHECK(end_current()==1 && calls==moved_end);
    put<uint64_t>(f.c.context,f.c.camera);
    pass("End puts the game's distance back only while the owned camera still holds ours");

    NADSN_Site rows[16]{};const uint32_t count=NADSN_ReadSites(rows,16);bool first=false,second=false;
    for(uint32_t i=0;i<count && i<16;++i) {
        if(rows[i].return_address==f.c.game+0x110de0e)first=rows[i].calls>0 && rows[i].owned_calls>0;
        if(rows[i].return_address==f.second_site)second=rows[i].calls>=4;
    }
    CHECK(count>=3 && first && second && NADSN_ReadSites(rows,0)==count);
    pass("every distinct caller of the slot is counted for diagnosis");

    // Hip to normal aim to full ADS and back: monotonic, bounded per frame,
    // exact at both ends, never below the game's distance.
    f.begin();CHECK(NADSN_Set(active_generation,.15f,.08f)==1);CHECK(f.frame()==.15f);
    for(unsigned i=0;i<30;++i)CHECK(f.frame()==.15f);
    f.shoulder(true);float previous=.15f;unsigned frames=0;
    for(;;) {const float v=f.frame();++frames;CHECK(v<previous && v>=.08f && previous-v<.03f);previous=v;if(v==.08f)break;CHECK(frames<40);}
    CHECK(frames>=5 && frames<=16 && f.frame()==.08f && f.stats().aim_applied>0);
    f.shoulder(false);f.ads(true);frames=0;
    for(;;) {const float v=f.frame();++frames;CHECK(v<previous && v>=NATIVE);previous=v;if(v==NATIVE)break;CHECK(frames<40);}
    CHECK(frames>=3 && f.frame()==NATIVE && f.distance()==NATIVE && f.stats().ads_forwarded>frames);
    f.ads(false);frames=0;
    for(;;) {const float v=f.frame();++frames;CHECK(v>previous && v<=.15f && v-previous<.04f);previous=v;if(v==.15f)break;CHECK(frames<40);}
    CHECK(frames>=5 && frames<=20);CHECK(end_current()==1);
    pass("the distance eases between hip, normal aim and full ADS and lands exactly");

    // Frame rate: the same glide takes the same time at 30, 60 and 144 FPS.
    for(const uint64_t step:{33333ULL,16667ULL,6944ULL}) {
        f.begin();CHECK(f.frame(step)==.15f);f.ads(true);uint64_t elapsed=0;
        while(f.frame(step)!=NATIVE) {elapsed+=step;CHECK(elapsed<400000);}
        CHECK(elapsed>=100000 && elapsed<=260000);f.ads(false);CHECK(end_current()==1);
    }
    pass("the ease lasts the same time at 30, 60 and 144 FPS");

    // A hitch spends one bounded step; a longer gap, a third-person request
    // or a fresh lease applies the target at once.
    f.begin();CHECK(f.frame()==.15f);f.ads(true);const float hitch=f.frame(200000);CHECK(hitch<.15f && hitch>.07f);
    CHECK(f.frame(300000)==NATIVE);f.ads(false);CHECK(f.frame(300000)==.15f);
    f.ads(true);CHECK(f.frame()<.15f);f.top(4,0);CHECK(f.frame()==NATIVE);f.top(6,2);f.ads(false);CHECK(f.frame()==.15f);
    f.ads(true);const float partial=f.frame();CHECK(partial<.15f && partial>NATIVE);
    const uint64_t eased_end=calls;CHECK(end_current()==1 && calls==eased_end+1 && f.distance()==NATIVE);
    f.begin();CHECK(f.frame()==.15f);CHECK(end_current()==1);
    pass("hitches stretch the ease; gaps, other requests and new leases start clean; End restores mid-ease");

    // Changing the distances while playing glides to the new value.
    f.begin();CHECK(f.frame()==.15f);CHECK(NADSN_Set(active_generation,.30f,0)==1);
    const float raised=f.frame();CHECK(raised>.15f && raised<.30f);
    for(unsigned i=0;i<40;++i)f.frame();CHECK(f.frame()==.30f);
    CHECK(NADSN_Set(active_generation,.03f,0)==1);for(unsigned i=0;i<40;++i)f.frame();
    CHECK(f.frame()==NATIVE && f.distance()==NATIVE);CHECK(end_current()==1);
    pass("live distance changes ease; a distance at or below the game's settles on the game's value");

    f.begin();for(unsigned i=0;i<200;++i) {f.sample();CHECK(last()==.15f);}
    CHECK(f.stats().replaced==200 && end_current()==1);
    f.begin();f.sample();CHECK(last()==.15f && end_current()==1);
    pass("repeated frames and a fresh generation after End keep working");

    std::printf("near fixture: %llu cases passed\n",static_cast<unsigned long long>(cases));return 0;
}
