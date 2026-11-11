// Synthetic private buffers and local callbacks only; never accesses the game.
#define NADSF_FIXTURE
#include "native_ads_fov.cpp"
#include <cstdio>
#include <cstdlib>
#include <thread>
#define CHECK(x) do{if(!(x)){std::fprintf(stderr,"FAIL %d: %s error=%u\n",__LINE__,#x,NADSF_Error());std::abort();}}while(0)
static uint64_t active_generation=0,cases=0,calls=0;
struct Record {void* camera;uint32_t bits;};static Record records[4096]{};
static HANDLE setter_reached=nullptr,setter_continue=nullptr;
static uint64_t mutation_address=0;static uint32_t mutation_value=0;
static uint64_t fail_owner_after_original=0;
__declspec(noinline) static void synthetic_setter(void* camera,float fov) {
    CHECK(calls<4096);records[calls].camera=camera;std::memcpy(&records[calls++].bits,&fov,4);
    if(mutation_address)std::memcpy(reinterpret_cast<void*>(mutation_address),&mutation_value,4);
    if(fail_owner_after_original) {
        fixture_rpm_failure_at=fail_owner_after_original;fixture_rpm_failure_remaining=1;
        fixture_rpm_restore_readable=true;fail_owner_after_original=0;
    }
    if(setter_reached) {SetEvent(setter_reached);WaitForSingleObject(setter_continue,INFINITE);}
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
static uint32_t begin_current(const NADSF_Config* c) {
    uint64_t token=UINT64_MAX;const uint32_t result=NADSF_Begin(c,&token);
    if(result==0)CHECK(token==0);else {CHECK((result==1 || result==2) && token && token!=active_generation);active_generation=token;}
    return result;
}
static uint32_t begin_fird(const NADSF_Config* c,float lens) {
    uint64_t token=UINT64_MAX;const uint32_t result=NADSF_BeginFird(c,lens,&token);
    if(result==0)CHECK(token==0);else {CHECK((result==1 || result==2) && token && token!=active_generation);active_generation=token;}
    return result;
}
static uint32_t end_current() {return NADSF_End(active_generation);}
static float last() {float f=0;std::memcpy(&f,&records[calls-1].bits,4);return f;}
static bool approximately(float a,float b) {return std::fabs(a-b)<.00001f;}
static float lens(double degrees,double magnification) {
    return static_cast<float>(2*std::atan(std::tan(degrees*3.14159265358979323846/360)/magnification));
}
static void pass(const char* name) {++cases;std::printf("PASS %s\n",name);}

// Real private VirtualAlloc pages only; production RPM executes unchanged.
static void fail_rpm_once(uint64_t at,bool restore_readable=true) {
    CHECK(fixture_rpm_failure_remaining==0);fixture_rpm_failure_at=at;
    fixture_rpm_failure_remaining=1;fixture_rpm_restore_readable=restore_readable;
}
static void clear_rpm_failure() {
    fixture_rpm_failure_at=0;fixture_rpm_failure_remaining=0;fixture_rpm_restore_readable=true;
}
static void recovery_event(const char* stage,uint32_t result,uint32_t native_error,uint64_t token,
                           uint64_t cas_changes,bool exact_native=false,const NADSF_Stats* stats=nullptr) {
    std::printf("RECOVERY_EVENT {\"stage\":\"%s\",\"result\":%u,\"native_error\":%u,\"token\":%llu,"
        "\"cas_changes\":%llu,\"rpm_failures\":%llu,\"exact_native\":%s,\"armed\":%u,\"installed\":%u,\"reserved\":%u}\n",
        stage,result,native_error,static_cast<unsigned long long>(token),static_cast<unsigned long long>(cas_changes),
        static_cast<unsigned long long>(fixture_rpm_failures),exact_native?"true":"false",
        stats?stats->armed:armed.load(),stats?stats->installed:installed.load(),reserved.load());
}
struct Fixture {
    NADSF_Config c{};uint64_t controller=0,descriptor=0,registry=0,units=0,generations=0,body_object=0,api=0,settings=0;
    Setter invoke=nullptr;
    Fixture() {
        c.size=sizeof c;c.abi=1;c.game=allocate(0x3382000,PAGE_EXECUTE_READWRITE);c.exe=allocate(0x29fe000);
        fake_image(c.game,0x6af322c1,0x3382000);fake_image(c.exe,0x6af2d5e6,0x29fe000);
        // Independent literal read-only capture from live-fov-api.txt.
        literal(c.exe+0x2dd080,"f30f114934c7415000000000e92f6c1f00");literal(c.exe+0x2dd070,"f30f104134c3");
        c.context=allocate(0x3000);c.camera=allocate(0x1000);c.avatar_owner=allocate(0x540000);
        c.avatar_index=0;c.avatar=0x333;c.body=0x400003;c.weapon=0x444;
        controller=allocate(0x1000);descriptor=allocate(0x1000);registry=allocate(0x1000);units=allocate(0x1000);
        generations=allocate(0x1000);body_object=allocate(0x1000);settings=allocate(0xAD000);
        put<uint64_t>(c.game+0x2e287d0,c.context);put<uint64_t>(c.context,c.camera);
        put<uint64_t>(c.game+0x2ce1ee0,c.avatar_owner);put<uint64_t>(c.game+0x2e381a8,controller);
        put<uint32_t>(c.avatar_owner+0x6C,1);put<uint64_t>(c.avatar_owner+0x110,descriptor);
        put<uint32_t>(descriptor+8,c.avatar);put<uint32_t>(descriptor+12,c.body);
        put<uint64_t>(c.exe+0x1ab76f8,registry);put<uint32_t>(registry+0x98,16);
        put<uint64_t>(registry+0x88,units);put<uint64_t>(registry+0xA0,generations);
        put<uint8_t>(generations+3,1);put<uint64_t>(units+3*8,body_object);
        put<uint64_t>(c.game+0x2ce1508,settings);degrees(90);
        const uint64_t root=allocate(0x1000);api=allocate(0x1000);
        put<uint64_t>(c.game+0x2ce14c8,root);put<uint64_t>(root+0x20,api);
        put<uint64_t>(api+0x78,c.exe+0x2dd070);put<uint64_t>(api+0x80,reinterpret_cast<uint64_t>(synthetic_setter));fixture_target=synthetic_setter;
        // sub rsp,28; mov rdx,API; call [rdx+80]; add rsp,28; ret.
        const uint64_t site=c.game+0x110bfda;literal(site-14,"4883ec2848ba");put<uint64_t>(site-8,api);
        literal(site,"ff92800000004883c428c3");CHECK(FlushInstructionCache(GetCurrentProcess(),reinterpret_cast<void*>(site-14),25));
        // Independent current-build normal4 capture: dispatch, late3C write,
        // first-kind4 input selection and radians/live-TP sensitivity ratio.
        literal(c.game+0x110b4db,"e8e0fc0000");
        literal(c.game+0x111e3ce,"f3450f119c24c4000000f3450f115c243c");
        literal(c.game+0x111ba5e,"f3410f1044243c");
        literal(c.game+0x111ba70,"448bc14969c0e8000000664283bc300002000004740bffc183e11f3bca75e1eb11");
        literal(c.game+0x111ba91,"4969c0e8000000f3420f1084303c020000");
        literal(c.game+0x111baa2,"f30f590506b51201488d55a0488b05535abc01f30f5e8088c40a00f30f59d8f30f59d0f30f59c8");
        invoke=reinterpret_cast<Setter>(site-14);normal();
    }
    void degrees(float f) {put<float>(settings+0xac488,f);}
    void shoulder(bool held) {put<uint8_t>(c.avatar_owner+0x53e892,held?4:0);put<uint8_t>(c.avatar_owner+0x53e897,held?32:0);}
    void controls(uint32_t mask=0,bool active=false,bool guard=false) {
        put<uint32_t>(controller,mask);put<uint8_t>(controller+4,active?1:0);put<uint8_t>(controller+5,guard?1:0);
    }
    void normal() {controls();shoulder(false);put<uint8_t>(c.avatar_owner+0x53e88e,0);put<uint8_t>(c.avatar_owner+0x53e896,0);top(4,1,c.weapon);}
    void top(uint32_t kind,uint32_t tail,uint32_t weapon) {
        put<uint32_t>(c.context+0x1F8,0);put<uint32_t>(c.context+0x1FC,tail);
        c.request=c.context+0x200+((tail+31)%32)*0xE8;
        put<uint32_t>(c.request,kind);put<uint32_t>(c.request+4,c.avatar);put<uint32_t>(c.request+8,weapon);put<uint32_t>(c.request+12,c.body);
        put<float>(c.request+0x3C,90*RAD_PER_DEG);
    }
    void fp() {normal();top(6,2,c.weapon);}
    void begin() {fp();CHECK(begin_current(&c)==1);}
    void sample(float f=.785398185f) {invoke(reinterpret_cast<void*>(c.camera),f);}
    NADSF_Stats stats() {NADSF_Stats s{};s.size=sizeof s;s.abi=1;CHECK(NADSF_ReadStats(reserved.load()?active_generation:0,&s)==1);return s;}
};

static void owner_read_failures(Fixture& f) {
    f.normal();const uint64_t initial_cas=fixture_cas_calls,initial_failures=fixture_rpm_failures;
    const uint64_t native_slot=*reinterpret_cast<const uint64_t*>(f.api+0x80);
    fail_rpm_once(f.controller);
    const auto validated=NADSF_Validate(&f.c),validate_error=NADSF_Error();
    CHECK(validated==0 && validate_error==READ_FAILED && fixture_rpm_failure_remaining==0);
    CHECK(fixture_rpm_failures==initial_failures+1 && fixture_failure_queries>0 && !reserved.load() && fixture_cas_calls==initial_cas);
    CHECK(*reinterpret_cast<const uint64_t*>(f.api+0x80)==native_slot);
    recovery_event("validate_read_failed",validated,validate_error,0,fixture_cas_calls-initial_cas);
    clear_rpm_failure();CHECK(NADSF_Validate(&f.c)==1 && NADSF_Error()==OK);
    f.fp();
    fail_rpm_once(f.controller);uint64_t token=UINT64_MAX;
    const auto began=NADSF_Begin(&f.c,&token),begin_error=NADSF_Error();
    CHECK(began==0 && token==0 && begin_error==READ_FAILED && !reserved.load() && fixture_cas_calls==initial_cas);
    recovery_event("begin_read_failed",began,begin_error,token,fixture_cas_calls-initial_cas);
    clear_rpm_failure();pass("real owner RPM faults in Validate and Begin report3 without a token or dispatch change; later healthy validation clears the error");

    for(uint64_t at:{f.controller,f.descriptor,f.generations+3}) {
        f.begin();const uint64_t prior_queries=fixture_failure_queries,prior_failures=fixture_rpm_failures,prior_cas=fixture_cas_calls;
        fail_rpm_once(at);f.sample(.271f);
        const auto stats=f.stats();const bool exact=last()==.271f;
        CHECK(exact && stats.error==READ_FAILED && stats.armed==0 && stats.installed==1 && reserved.load()==1);
        CHECK(fixture_rpm_failure_remaining==0 && fixture_rpm_failures==prior_failures+1 && fixture_failure_queries>prior_queries);
        CHECK(fixture_cas_calls==prior_cas);
        if(at==f.controller)recovery_event("callback_read_failed",1,stats.error,active_generation,fixture_cas_calls-prior_cas,exact,&stats);
        clear_rpm_failure();f.sample(.271f);
        CHECK(fixture_failure_queries>prior_queries && fixture_cas_calls==prior_cas);
        CHECK(end_current()==1 && !reserved.load() && NADSF_Error()==OK);
    }
    pass("callback owner faults pass the native value exactly and retain only cleanup; controller descriptor and Unit generation scopes are retryable");

    f.begin();const auto healthy_queries=fixture_failure_queries;
    for(unsigned i=0;i<10;++i){f.sample(.271f);}
    CHECK(fixture_failure_queries==healthy_queries);CHECK(end_current()==1);
    pass("healthy owner reads perform no failure-classification VirtualQuery");

    f.normal();fail_rpm_once(f.controller,false);
    CHECK(NADSF_Validate(&f.c)==0 && NADSF_Error()==OWNER_MISMATCH && fixture_rpm_failure_remaining==0);
    DWORD discarded=0;CHECK(VirtualProtect(reinterpret_cast<void*>(f.controller),0x1000,PAGE_READWRITE,&discarded));clear_rpm_failure();
    const auto unsafe_queries=fixture_failure_queries;
    put<uint64_t>(f.c.game+0x2e381a8,1);CHECK(NADSF_Validate(&f.c)==0 && NADSF_Error()==OWNER_MISMATCH);
    const uint64_t gone=allocate(0x1000);CHECK(VirtualFree(reinterpret_cast<void*>(gone),0,MEM_RELEASE));
    put<uint64_t>(f.c.game+0x2e381a8,gone);CHECK(NADSF_Validate(&f.c)==0 && NADSF_Error()==OWNER_MISMATCH);
    put<uint64_t>(f.c.game+0x2e381a8,f.controller);
    put<uint32_t>(f.c.avatar_owner+0x6C,9);const auto semantic_queries=fixture_failure_queries;
    CHECK(NADSF_Validate(&f.c)==0 && NADSF_Error()==OWNER_MISMATCH && fixture_failure_queries==semantic_queries);
    put<uint32_t>(f.c.avatar_owner+0x6C,1);CHECK(fixture_failure_queries>=unsafe_queries);
    CHECK(NADSF_Validate(&f.c)==1 && NADSF_Error()==OK);
    pass("inaccessible unmapped invalid-numeric and readable semantic owners remain unsafe; no previous read fault can taint a later guard");

    SYSTEM_INFO info{};GetSystemInfo(&info);const size_t page=info.dwPageSize;
    const uint64_t split=allocate(page*2),crossing=split+page-12;
    std::memcpy(reinterpret_cast<void*>(crossing),reinterpret_cast<void*>(f.descriptor),20);
    put<uint64_t>(f.c.avatar_owner+0x110,crossing);f.begin();
    CHECK(VirtualProtect(reinterpret_cast<void*>(split+page),page,PAGE_NOACCESS,&discarded));
    const auto cross_queries=fixture_failure_queries;f.sample(.271f);
    CHECK(f.stats().error==OWNER_MISMATCH && !armed.load() && fixture_failure_queries>=cross_queries+2);
    CHECK(VirtualProtect(reinterpret_cast<void*>(split+page),page,PAGE_READWRITE,&discarded));
    put<uint64_t>(f.c.avatar_owner+0x110,f.descriptor);CHECK(end_current()==1);
    CHECK(VirtualFree(reinterpret_cast<void*>(split),0,MEM_RELEASE));
    pass("a readable first page never certifies an attempted owner span crossing into an unreadable page");

    f.normal();const auto nonowner_queries=fixture_failure_queries;
    const uint64_t copy=allocate(0x1000);put(copy,f.c);fail_rpm_once(copy);
    CHECK(NADSF_Validate(reinterpret_cast<const NADSF_Config*>(copy))==0 && NADSF_Error()==INVALID_CONFIG);
    CHECK(fixture_rpm_failure_remaining==0 && fixture_failure_queries==nonowner_queries);clear_rpm_failure();
    fail_rpm_once(f.c.exe+0x2dd080);CHECK(NADSF_Validate(&f.c)==0 && NADSF_Error()==CODE_MISMATCH);
    CHECK(fixture_failure_queries==nonowner_queries);clear_rpm_failure();
    fail_rpm_once(f.settings+0xac488);CHECK(NADSF_Validate(&f.c)==0 && NADSF_Error()==SOURCE_INVALID);
    CHECK(fixture_failure_queries==nonowner_queries);clear_rpm_failure();
    CHECK(VirtualFree(reinterpret_cast<void*>(copy),0,MEM_RELEASE));
    f.begin();fail_rpm_once(f.api+0x80);f.sample(.271f);
    CHECK(f.stats().error==API_MISMATCH && !armed.load() && fixture_failure_queries==nonowner_queries);
    clear_rpm_failure();CHECK(NADSF_End(active_generation+1)==0 && NADSF_Error()==TOKEN_MISMATCH);
    CHECK(end_current()==1);
    pass("actual RPM failures in config code source and dispatch and invalid tokens never become retryable owner3");

    f.fp();
    fail_owner_after_original=f.controller;token=UINT64_MAX;const auto after_cas=fixture_cas_calls;
    const auto after_result=NADSF_Begin(&f.c,&token),after_error=NADSF_Error();
    CHECK(after_result==0 && token==0 && after_error==READ_FAILED && !reserved.load() && !armed.load());
    CHECK(fixture_rpm_failure_remaining==0 && fixture_cas_calls==after_cas+2);
    recovery_event("post_call_begin_read_failed",after_result,after_error,token,fixture_cas_calls-after_cas);
    clear_rpm_failure();CHECK(NADSF_Validate(&f.c)==1 && NADSF_Error()==OK);
    pass("an owner RPM failure after the actual immediate setter rolls Begin back with its fresh causal3");
}
int main() {
    Fixture f;CHECK(f.stats().installed==0);CHECK(NADSF_Validate(&f.c)==1 && fixture_cas_calls==0);
    CHECK(begin_current(&f.c)==0 && reserved.load()==0);pass("normal4 read-only preflight; Begin requires owned6");
    fixture_now=0;f.begin();f.shoulder(true);uint8_t legacy=1;CHECK(value(f.c.avatar_owner+0x53e88e,legacy) && legacy==0);
    f.sample();fixture_now=.06;f.sample();CHECK(approximately(last(),lens(90,1.025)));
    fixture_now=.12;f.sample();CHECK(approximately(last(),lens(90,1.05)) && f.stats().ads_forwarded==0);
    CHECK(end_current()==1);pass("agreeing82/125 with legacy48false produces the complete shoulder zoom");

    fixture_now=0;f.begin();put<uint8_t>(f.c.avatar_owner+0x53e88e,1);const uint64_t legacy_reads=fixture_clock_reads;
    for(double time:{0.0,.06,.12,.24}) {fixture_now=time;f.sample(.321f);CHECK(last()==90*RAD_PER_DEG);}
    CHECK(fixture_clock_reads==legacy_reads && f.stats().ads_forwarded==0 && armed.load()==1 && end_current()==1);
    pass("legacy48 alone neither starts shoulder zoom nor masquerades as full ADS");

    for(unsigned selected=0;selected<2;++selected)for(unsigned old=0;old<2;++old) {
        fixture_now=0;f.begin();put<uint8_t>(f.c.avatar_owner+0x53e88e,static_cast<uint8_t>(old));
        put<uint8_t>(f.c.avatar_owner+0x53e892,selected==0?4:0);
        put<uint8_t>(f.c.avatar_owner+0x53e897,selected==1?32:0);
        f.sample();fixture_now=.12;f.sample();CHECK(last()==90*RAD_PER_DEG && f.stats().ads_forwarded==0 && armed.load()==1);
        f.controls(0,true);f.sample(.213f);CHECK(last()==.213f && f.stats().ads_forwarded==1 && end_current()==1);
    }
    pass("mismatched82/125 never acquires shoulder zoom or vetoes native full ADS");

    fixture_now=0;f.begin();f.shoulder(true);f.sample();fixture_now=.06;f.sample();const float paired_half=last();
    put<uint8_t>(f.c.avatar_owner+0x53e88e,1);f.sample();CHECK(last()==paired_half);
    fixture_now=.12;f.sample();CHECK(approximately(last(),lens(90,1.05)));
    f.controls(0,true);f.sample(.271f);CHECK(last()==.271f && f.stats().ads_forwarded==1 && end_current()==1);
    pass("legacy48 changes do not veto the paired shoulder tween; full ADS still wins both flags");

    fixture_now=0;f.begin();const uint64_t clock_before=fixture_clock_reads;
    const float exact_hip=90*RAD_PER_DEG;uint32_t exact_hip_bits=0;std::memcpy(&exact_hip_bits,&exact_hip,4);
    for(unsigned i=0;i<100;++i) {fixture_now+=.016;f.sample();CHECK(records[calls-1].bits==exact_hip_bits);}
    CHECK(fixture_clock_reads==clock_before && end_current()==1);
    pass("settled hip stays bit-exact live TPV with no clock or shoulder tween");

    fixture_now=0;f.begin();f.shoulder(true);f.sample();CHECK(last()==exact_hip);
    float previous=last();
    for(double time:{.03,.06,.09,.12}) {
        fixture_now=time;f.sample();CHECK(last()<previous && last()>1.5f);previous=last();
        if(time==.06)CHECK(approximately(last(),lens(90,1.025)));
    }
    CHECK(approximately(last(),1.522025508f) && approximately(last(),lens(90,1.05)));
    const uint64_t settled_reads=fixture_clock_reads;
    for(unsigned i=0;i<100;++i) {fixture_now+=.016;f.sample();CHECK(approximately(last(),lens(90,1.05)));}
    CHECK(fixture_clock_reads==settled_reads && end_current()==1);
    pass("shoulder aim eases to five-percent focal magnification in120ms and rests without clock reads");

    fixture_now=0;f.begin();f.shoulder(true);f.sample();fixture_now=.06;f.sample();
    fixture_now=.12;f.sample();f.shoulder(false);f.sample();CHECK(approximately(last(),lens(90,1.05)));
    fixture_now=.18;f.sample();CHECK(approximately(last(),lens(90,1.025)));
    fixture_now=.24;f.sample();CHECK(records[calls-1].bits==exact_hip_bits);
    const uint64_t released_reads=fixture_clock_reads;fixture_now=.3;f.sample();CHECK(fixture_clock_reads==released_reads);
    CHECK(end_current()==1);pass("shoulder release follows the same120ms lens easing to exact hip");

    fixture_now=0;f.begin();f.shoulder(true);f.sample();fixture_now=.06;f.sample();
    const float half=last();f.shoulder(false);fixture_now=.07;f.sample();CHECK(last()==half);
    fixture_now=.10;f.sample();CHECK(approximately(last(),lens(90,1.0078125)));
    fixture_now=.13;f.sample();CHECK(approximately(last(),exact_hip));CHECK(end_current()==1);
    pass("mid-transition shoulder reversal is continuous and never overshoots hip");

    fixture_now=0;f.begin();f.shoulder(true);f.sample();fixture_now=.06;f.sample();
    f.degrees(105);f.sample();CHECK(approximately(last(),lens(105,1.025)));
    float unchanged_degrees=0;CHECK(value(f.settings+0xac488,unchanged_degrees) && unchanged_degrees==105);
    fixture_now=.12;f.sample();CHECK(approximately(last(),lens(105,1.05)));
    CHECK(end_current()==1);f.degrees(90);pass("shoulder magnification uses the fresh live TPV setting without changing its source");

    fixture_now=0;f.begin();f.shoulder(true);f.sample();fixture_now=.12;f.sample();
    f.controls(0,true);f.sample(.211f);CHECK(last()==.211f && f.stats().ads_forwarded==1);
    f.controls();fixture_now=.13;f.sample();CHECK(records[calls-1].bits==exact_hip_bits);
    fixture_now=.19;f.sample();CHECK(approximately(last(),lens(90,1.025)));
    f.controls(0,true);f.shoulder(false);f.sample(.299f);CHECK(last()==.299f);
    f.controls();f.sample();CHECK(records[calls-1].bits==exact_hip_bits && end_current()==1);
    pass("full ADS forwards native zoom immediately and discards shoulder blend on both exit paths");

    fixture_now=0;f.begin();f.shoulder(true);f.sample();fixture_now=.06;f.sample();
    fixture_now=.01;f.sample();CHECK(approximately(last(),lens(90,1.025)));
    fixture_now=10;f.sample();CHECK(approximately(last(),lens(90,1.025)));
    fixture_now=10.06;f.sample();CHECK(approximately(last(),lens(90,1.05)) && end_current()==1);
    fixture_now=0;f.begin();f.shoulder(true);f.sample();fixture_now=.06;f.sample();
    fixture_clock_ok=false;f.sample();CHECK(records[calls-1].bits==exact_hip_bits);
    fixture_clock_ok=true;f.sample();CHECK(records[calls-1].bits==exact_hip_bits);
    fixture_now=.12;f.sample();CHECK(approximately(last(),lens(90,1.025)) && end_current()==1);
    pass("backward and long clock gaps rebase; failed QPC falls back to exact hip and restarts cleanly");

    fixture_now=0;f.begin();f.shoulder(true);f.sample();fixture_now=.12;f.sample();
    f.controls(32);f.sample(.333f);CHECK(last()==.333f && armed.load()==1);
    f.controls();f.sample();CHECK(records[calls-1].bits==exact_hip_bits);
    fixture_now=.18;f.sample();CHECK(approximately(last(),lens(90,1.025)));
    f.top(4,3,f.c.weapon);f.sample(.444f);CHECK(last()==.444f);
    f.top(6,4,f.c.weapon+1);CHECK(NADSF_Bind(active_generation,f.c.request,f.c.weapon+1)==1);
    CHECK(records[calls-1].bits==exact_hip_bits && end_current()==1);
    pass("unsupported actions and unbound camera requests forward native and reset shoulder tween");

    f.fp();f.shoulder(true);uint64_t before_aim=calls;
    CHECK(begin_current(&f.c)==1 && calls==before_aim+1 && approximately(last(),90*RAD_PER_DEG));CHECK(end_current()==1);
    f.fp();f.controls(0,true);before_aim=calls;
    CHECK(begin_current(&f.c)==1 && calls==before_aim);f.sample(.2f);CHECK(last()==.2f);CHECK(end_current()==1);
    pass("Begin starts shoulder easing from exact hip and never overwrites full ADS zoom");
    uint8_t code_before[64]{};CHECK(read(reinterpret_cast<uint64_t>(synthetic_setter),code_before,64));
    uint64_t start=calls;f.begin();CHECK(calls==start+1 && approximately(last(),1.5707963268f));
    CHECK(f.stats().immediate_applies==1 && armed.load()==1);pass("Begin immediately applies live90 hip FOV through original setter");
    f.sample();CHECK(approximately(last(),1.5707963268f));float source_value=0;CHECK(value(f.settings+0xac488,source_value) && source_value==90);
    CHECK(f.stats().replaced==1 && f.stats().last_native==.785398185f);f.degrees(105);f.sample();CHECK(approximately(last(),105*RAD_PER_DEG));
    CHECK(value(f.settings+0xac488,source_value) && source_value==105);pass("live105 honored; source settings and native request untouched");
    for(float valid:{1.0f,179.0f}) {f.degrees(valid);f.sample();CHECK(approximately(last(),valid*RAD_PER_DEG));}
    const uint32_t invalid_bits[]={0,0x43340000,0x7F800000,0x7FC12345};
    for(uint32_t bits:invalid_bits) {put<uint32_t>(f.settings+0xac488,bits);f.sample(.123f);CHECK(last()==.123f);}
    f.degrees(90);pass("finite1..179 accepted; invalid source forwards native exactly");
    f.shoulder(true);f.sample(.25f);
    CHECK(approximately(last(),90*RAD_PER_DEG) && f.stats().ads_forwarded==0);
    pass("shoulder edge starts at live hip before its gradual magnification");
    f.controls(0,true);f.sample(.3f);CHECK(last()==.3f && f.stats().ads_forwarded==1);
    f.shoulder(false);f.sample(.31f);CHECK(last()==.31f && f.stats().ads_forwarded==2);
    f.controls();pass("only native controller full ADS forwards native zoom with explicit counter");
    f.controls(2);f.sample();CHECK(approximately(last(),90*RAD_PER_DEG) && armed.load()==1);
    for(uint32_t mask:{1U,3U,4U}) {f.controls(mask);f.sample(.4f);CHECK(last()==.4f && armed.load()==1);}
    f.controls(2,false,true);f.sample(.41f);CHECK(last()==.41f);f.controls();put<uint8_t>(f.c.avatar_owner+0x53e896,4);f.sample(.42f);CHECK(last()==.42f);
    put<uint8_t>(f.c.avatar_owner+0x53e896,0);pass("mask2 retains hip FOV; other masks guard and seated states forward");
    const uint32_t nan_bits=0x7FC12345;float nan=0;std::memcpy(&nan,&nan_bits,4);
    reinterpret_cast<Setter>(callback())(reinterpret_cast<void*>(f.c.camera),nan);CHECK(records[calls-1].bits==nan_bits);
    f.invoke(reinterpret_cast<void*>(f.c.camera+8),nan);CHECK(records[calls-1].camera==reinterpret_cast<void*>(f.c.camera+8) && records[calls-1].bits==nan_bits);
    CHECK(armed.load()==1 && f.stats().ads_forwarded==2);pass("wrong caller or camera bit-exact forward without foreign ADS counts");
    // Native exit/entry can occur before the host binds its new request.
    f.top(4,3,f.c.weapon);f.sample(.5f);CHECK(last()==.5f && armed.load()==1);
    f.top(6,4,f.c.weapon+1);f.sample(.6f);CHECK(last()==.6f && armed.load()==1);
    f.shoulder(true);
    start=calls;CHECK(NADSF_Bind(active_generation,f.c.request,f.c.weapon+1)==1 && calls==start+1 && approximately(last(),90*RAD_PER_DEG));
    f.sample();CHECK(approximately(last(),90*RAD_PER_DEG) && f.stats().binds==1);pass("type4/new unbound6 pass through; Bind starts shoulder easing from hip in the same update");
    f.top(6,5,f.c.weapon+2);f.controls(0,true);start=calls;
    CHECK(NADSF_Bind(active_generation,f.c.request,f.c.weapon+2)==1 && calls==start);f.sample(.2f);CHECK(last()==.2f);
    f.controls();pass("Bind during ADS does not overwrite native zoom");
    start=calls;CHECK(NADSF_Bind(active_generation,f.c.request+0xE8,f.c.weapon+2)==0 && calls==start);
    CHECK(NADSF_Bind(active_generation,f.c.request,f.c.weapon+3)==0 && calls==start);pass("Bind rejects noncurrent record or mismatched weapon without immediate write");
    start=calls;CHECK(end_current()==1 && calls==start && f.stats().installed==0);CHECK(end_current()==1 && calls==start);
    reinterpret_cast<Setter>(callback())(reinterpret_cast<void*>(f.c.camera),.7f);CHECK(last()==.7f);pass("End restores slot without cached FOV restore; cached callbacks remain forwarding");
    const uint64_t stale=active_generation;f.begin();CHECK(active_generation!=stale);start=calls;
    CHECK(NADSF_Bind(stale,f.c.request,f.c.weapon)==0 && NADSF_End(stale)==0 && armed.load()==1 && calls==start);
    NADSF_Stats bad{};bad.size=sizeof bad;bad.abi=1;CHECK(NADSF_ReadStats(0,&bad)==0 && NADSF_ReadStats(stale,&bad)==0);
    uint64_t busy=UINT64_MAX;CHECK(NADSF_Begin(&f.c,&busy)==0 && busy==0);CHECK(end_current()==1);pass("stale token and BUSY cannot affect another session");
    for(unsigned failure=0;failure<5;++failure) {
        f.begin();
        if(failure==0)put<uint8_t>(f.generations+3,2);
        if(failure==1)put<uint64_t>(f.units+3*8,f.body_object+8);
        if(failure==2)put<uint32_t>(f.descriptor,1);
        if(failure==3)put<uint64_t>(f.c.context,f.c.camera+8);
        if(failure==4)put<uint64_t>(f.c.game+0x2e287d0,f.c.context+8);
        f.sample(.8f);CHECK(last()==.8f && armed.load()==0);start=calls;CHECK(end_current()==1 && calls==start);
        if(failure==0)put<uint8_t>(f.generations+3,1);
        if(failure==1)put<uint64_t>(f.units+3*8,f.body_object);
        if(failure==2)put<uint32_t>(f.descriptor,0);
        if(failure==3)put<uint64_t>(f.c.context,f.c.camera);
        if(failure==4)put<uint64_t>(f.c.game+0x2e287d0,f.c.context);
    }pass("avatar descriptor/body generation/object/current camera lifetime changes disarm and forward");
    f.normal();
    for(uint64_t address:{f.c.game+0x110bfda,f.c.exe+0x2dd080,f.c.exe+0x2dd070,f.c.exe+0x88}) {
        uint8_t old=0;CHECK(value(address,old));put<uint8_t>(address,old^1);fixture_cas_calls=0;
        CHECK(NADSF_Validate(&f.c)==0 && begin_current(&f.c)==0 && fixture_cas_calls==0);put<uint8_t>(address,old);
    }pass("literal callsite getter setter and PE drift refuse before CAS");
    fixture_slot_readonly=true;f.fp();fixture_cas_calls=0;CHECK(begin_current(&f.c)==0 && fixture_cas_calls==0);fixture_slot_readonly=false;
    fixture_cas_calls=0;fixture_foreign_cas_at=1;fixture_foreign_value=reinterpret_cast<uint64_t>(foreign_setter);
    CHECK(begin_current(&f.c)==0 && reserved.load()==0);uint64_t actual=0;CHECK(value(f.api+0x80,actual) && actual==fixture_foreign_value);
    fixture_foreign_cas_at=0;put<uint64_t>(f.api+0x80,reinterpret_cast<uint64_t>(synthetic_setter));pass("read-only slots rejected; CAS preserves foreign pointer replacements");
    // Successful install, uncertain immediate apply result, failed rollback.
    f.fp();mutation_address=f.c.request+8;mutation_value=f.c.weapon+1;fixture_cas_calls=0;fixture_cas_fail_at=2;
    CHECK(begin_current(&f.c)==2 && reserved.load()==1 && armed.load()==0 && active_generation==owned_generation);
    mutation_address=0;fixture_cas_fail_at=0;fixture_slot_unreadable=true;CHECK(NADSF_End(active_generation)==0 && owned_generation==active_generation);
    CHECK(f.stats().installed==1);fixture_slot_unreadable=false;start=calls;CHECK(end_current()==1 && calls==start);pass("partial Begin2 retains generation until End repairs pointer with no FOV replay");
    f.begin();fixture_slot_readonly=true;start=calls;CHECK(end_current()==0 && reserved.load()==1 && armed.load()==0 && calls==start);
    fixture_slot_readonly=false;CHECK(end_current()==1 && calls==start);pass("End protection failure retains only its own cleanup reservation");
    f.begin();start=calls;put<uint64_t>(f.api+0x80,reinterpret_cast<uint64_t>(foreign_setter));CHECK(end_current()==1 && calls==start);
    CHECK(value(f.api+0x80,actual) && actual==reinterpret_cast<uint64_t>(foreign_setter));put<uint64_t>(f.api+0x80,reinterpret_cast<uint64_t>(synthetic_setter));
    pass("End never overwrites a foreign slot owner");
    f.begin();put<uint32_t>(f.c.avatar_owner+0x53e9c0,0xffffffff);f.controls(2);f.sample();CHECK(approximately(last(),90*RAD_PER_DEG));
    CHECK(end_current()==1);pass("no weapon/model generation dependency during pose suspension");
    f.begin();f.sample(.111f);const NADSF_Stats completed=f.stats();f.degrees(105);
    setter_reached=CreateEventW(nullptr,TRUE,FALSE,nullptr);setter_continue=CreateEventW(nullptr,TRUE,FALSE,nullptr);
    HANDLE stats_done=CreateEventW(nullptr,TRUE,FALSE,nullptr);CHECK(setter_reached && setter_continue && stats_done);
    std::thread blocked_setter([&]{f.sample(.222f);});CHECK(WaitForSingleObject(setter_reached,3000)==WAIT_OBJECT_0);
    // Simulate a freshly published health failure while the camera setter still
    // owns policy_lock. Diagnostics may be old; health must not be cached.
    armed.store(0,std::memory_order_release);error(OWNER_MISMATCH);
    NADSF_Stats concurrent{};concurrent.size=sizeof concurrent;concurrent.abi=1;uint32_t stats_result=0;
    std::thread reading([&]{stats_result=NADSF_ReadStats(active_generation,&concurrent);SetEvent(stats_done);});
    CHECK(WaitForSingleObject(stats_done,1000)==WAIT_OBJECT_0);
    CHECK(stats_result==1 && concurrent.installed==1 && concurrent.armed==0 && concurrent.error==OWNER_MISMATCH);
    CHECK(concurrent.last_native==completed.last_native && concurrent.last_applied==completed.last_applied
        && concurrent.source_degrees==completed.source_degrees);
    NADSF_Stats invalid{};invalid.size=sizeof invalid;invalid.abi=1;
    CHECK(NADSF_ReadStats(active_generation+1,&invalid)==0 && NADSF_Error()==TOKEN_MISMATCH);
    invalid.abi=2;CHECK(NADSF_ReadStats(active_generation,&invalid)==0 && NADSF_Error()==INVALID_CONFIG);
    invalid.abi=1;invalid.size=sizeof invalid-4;
    CHECK(NADSF_ReadStats(active_generation,&invalid)==0 && NADSF_Error()==INVALID_CONFIG);
    CHECK(NADSF_ReadStats(active_generation,reinterpret_cast<NADSF_Stats*>(1))==0);
    SetEvent(setter_continue);blocked_setter.join();reading.join();
    CloseHandle(setter_reached);CloseHandle(setter_continue);CloseHandle(stats_done);setter_reached=nullptr;setter_continue=nullptr;
    const NADSF_Stats after_setter=f.stats();CHECK(after_setter.last_native==.222f && after_setter.source_degrees==105
        && after_setter.last_applied==105*RAD_PER_DEG && after_setter.armed==0);
    CHECK(end_current()==1);f.degrees(90);
    pass("ReadStats completes during a blocked setter with fresh health, completed angles, and strict token/ABI/pointer guards");

    f.begin();f.sample(.333f);const NADSF_Stats coherent=f.stats();
    // An interrupted atomic publication must yield the cached whole tuple in
    // one attempt, rather than spin or combine different setter frames.
    display_sequence.fetch_add(1,std::memory_order_seq_cst);
    display_native.store(.999f,std::memory_order_seq_cst);display_degrees.store(179,std::memory_order_seq_cst);
    const NADSF_Stats interrupted=f.stats();
    CHECK(interrupted.last_native==coherent.last_native && interrupted.last_applied==coherent.last_applied
        && interrupted.source_degrees==coherent.source_degrees);
    display_native.store(policy.last_native,std::memory_order_seq_cst);display_degrees.store(policy.source_degrees,std::memory_order_seq_cst);
    display_sequence.fetch_add(1,std::memory_order_seq_cst);
    CHECK(end_current()==1);pass("in-progress diagnostic publication returns the last complete tuple without spinning");

    f.fp();f.degrees(105);f.controls(0,true);start=calls;
    CHECK(begin_current(&f.c)==1 && calls==start);const NADSF_Stats new_display=f.stats();
    CHECK(new_display.last_native==0 && new_display.last_applied==0 && new_display.source_degrees==105);
    f.sample(.456f);const NADSF_Stats before_busy=f.stats();uint64_t busy_display=UINT64_MAX;
    CHECK(NADSF_Begin(&f.c,&busy_display)==0 && busy_display==0);const NADSF_Stats after_busy=f.stats();
    CHECK(after_busy.last_native==before_busy.last_native && after_busy.last_applied==before_busy.last_applied
        && after_busy.source_degrees==before_busy.source_degrees && after_busy.error==BUSY);
    CHECK(end_current()==1);f.degrees(90);
    pass("new generations reset old display angles while BUSY Begin preserves the active owner's tuple");
    f.begin();setter_reached=CreateEventW(nullptr,TRUE,FALSE,nullptr);setter_continue=CreateEventW(nullptr,TRUE,FALSE,nullptr);
    CHECK(setter_reached && setter_continue);std::atomic<uint32_t> ended{0};
    std::thread in_flight([&]{f.sample();});CHECK(WaitForSingleObject(setter_reached,3000)==WAIT_OBJECT_0);
    std::thread ending([&]{CHECK(end_current()==1);ended.store(1);});while(armed.load())SwitchToThread();CHECK(ended.load()==0);
    SetEvent(setter_continue);in_flight.join();ending.join();CloseHandle(setter_reached);CloseHandle(setter_continue);setter_reached=nullptr;setter_continue=nullptr;
    CHECK(ended.load()==1);pass("End drains in-flight overridden setter before restoring owned slot");
    const uint32_t saved_weapon=f.c.weapon;f.c.weapon=0;f.normal();fixture_cas_calls=0;
    CHECK(NADSF_ValidateFird(&f.c)==1 && fixture_cas_calls==0);
    const float captured=72*RAD_PER_DEG;start=calls;
    CHECK(begin_fird(&f.c,captured)==1 && calls==start+1 && last()==captured && armed.load()==1);
    f.shoulder(true);f.degrees(115);fixture_now=100;f.sample(.111f);CHECK(last()==captured);
    CHECK(approximately(f.stats().source_degrees,72) && f.stats().replaced==1);
    float untouched_setting=0;CHECK(value(f.settings+0xac488,untouched_setting) && untouched_setting==115);
    pass("Fird normal4 uses the exact captured projection immediately, without weapon ownership, shoulder scaling or setting edits");
    const uint64_t fird_token=active_generation;f.top(4,3,0);put<uint32_t>(f.c.request+4,f.c.avatar+1);
    f.sample(.222f);CHECK(last()==.222f && armed.load()==1);start=calls;
    CHECK(NADSF_BindFird(fird_token,f.c.request)==0 && calls==start);
    put<uint32_t>(f.c.request+4,f.c.avatar);CHECK(NADSF_BindFird(fird_token,f.c.request)==1 && last()==captured);
    f.invoke(reinterpret_cast<void*>(f.c.camera+8),.223f);CHECK(last()==.223f);
    reinterpret_cast<Setter>(callback())(reinterpret_cast<void*>(f.c.camera),.224f);CHECK(last()==.224f);
    pass("Fird unrelated avatar request, foreign camera and foreign caller forward without projection edits");
    f.top(6,4,saved_weapon);f.controls();start=calls;f.sample(.31f);
    CHECK(last()==.31f && calls==start+1 && f.stats().ads_forwarded==1 && armed.load()==1);
    CHECK(NADSF_BindFird(fird_token,f.c.request)==0);f.controls(0,true);f.sample(.32f);
    CHECK(last()==.32f && f.stats().ads_forwarded==2 && armed.load()==1);
    f.normal();f.top(4,5,0);f.sample(.33f);CHECK(last()==.33f);
    start=calls;CHECK(NADSF_BindFird(fird_token,f.c.request)==1 && calls==start+1 && last()==captured);
    CHECK(NADSF_Bind(fird_token,f.c.request,saved_weapon)==0);
    CHECK(NADSF_BindFird(fird_token,f.c.request)==1);f.sample(.34f);CHECK(last()==captured);
    CHECK(end_current()==1);
    pass("Fird camera6 forwards before and after the ADS bit; normal4 rebind immediately restores the same captured lens");
    for(float invalid:{9*RAD_PER_DEG,171*RAD_PER_DEG,INFINITY,NAN}) {
        f.normal();fixture_cas_calls=0;CHECK(begin_fird(&f.c,invalid)==0 && fixture_cas_calls==0 && reserved.load()==0);
    }
    for(float valid:{10*RAD_PER_DEG,170*RAD_PER_DEG}) {f.normal();CHECK(begin_fird(&f.c,valid)==1 && last()==valid && end_current()==1);}
    f.fp();CHECK(NADSF_ValidateFird(&f.c)==0 && begin_fird(&f.c,captured)==0);
    f.normal();f.controls(0,true);CHECK(begin_fird(&f.c,captured)==0);f.controls();
    pass("Fird rejects nonfinite or out-of-range captured lenses and camera6/full-ADS entry before installing a slot");
    f.normal();CHECK(begin_fird(&f.c,captured)==1);put<uint8_t>(f.generations+3,2);f.sample(.4f);
    CHECK(last()==.4f && armed.load()==0 && end_current()==1);put<uint8_t>(f.generations+3,1);
    pass("Fird body generation loss disarms and forwards immediately");
    f.normal();mutation_address=f.c.request+4;mutation_value=f.c.avatar+1;fixture_cas_calls=0;fixture_cas_fail_at=2;
    CHECK(begin_fird(&f.c,captured)==2 && reserved.load()==1 && armed.load()==0);
    mutation_address=0;fixture_cas_fail_at=0;put<uint32_t>(f.c.request+4,f.c.avatar);fixture_slot_unreadable=true;
    CHECK(end_current()==0 && reserved.load()==1);fixture_slot_unreadable=false;start=calls;
    CHECK(end_current()==1 && calls==start);
    f.normal();CHECK(begin_fird(&f.c,captured)==1);put<uint64_t>(f.api+0x80,reinterpret_cast<uint64_t>(foreign_setter));
    CHECK(end_current()==1);CHECK(value(f.api+0x80,actual) && actual==reinterpret_cast<uint64_t>(foreign_setter));
    put<uint64_t>(f.api+0x80,reinterpret_cast<uint64_t>(synthetic_setter));f.c.weapon=saved_weapon;f.degrees(90);
    pass("Fird partial Begin retains cleanup ownership and End preserves foreign pointer replacements without FOV replay");
    f.normal();const uint64_t normal_input=f.c.request;put<uint8_t>(f.c.avatar_owner+0x53e88e,1);
    CHECK(begin_fird(&f.c,captured)==1);float input_lens=0;
    CHECK(value(normal_input+0x3C,input_lens) && input_lens==captured);
    for(float zoom_lens:{30*RAD_PER_DEG,12*RAD_PER_DEG,3*RAD_PER_DEG}) {
        // Input precedes the next native evaluation and therefore sees the
        // previous callback's fixed request lens even with legacy48 enabled.
        CHECK(value(normal_input+0x3C,input_lens) && approximately(input_lens/RAD_PER_DEG/90,72.0f/90));
        put<float>(normal_input+0x3C,zoom_lens);f.sample(zoom_lens);
        CHECK(value(normal_input+0x3C,input_lens) && input_lens==captured && last()==captured);
    }
    CHECK(end_current()==1);CHECK(value(normal_input+0x3C,input_lens) && input_lens==3*RAD_PER_DEG);
    pass("Fird legacy48 and changing zoom lenses retain one input ratio; End restores the freshest native3C");

    f.normal();put<float>(f.c.request+0x3C,.6f);CHECK(begin_fird(&f.c,captured)==1);
    put<float>(f.c.request+0x3C,captured);f.sample(captured);
    CHECK(NADSF_BindFird(active_generation,f.c.request)==1 && end_current()==1);
    CHECK(value(f.c.request+0x3C,input_lens) && input_lens==captured);
    pass("Fird post-evaluation native3C equal to our fixed lens replaces an older restoration value; immediate Bind preserves it");

    f.normal();const uint64_t first=f.c.request;put<float>(first+0x3C,.4f);
    f.top(4,2,saved_weapon);const uint64_t top=f.c.request;put<float>(top+0x3C,.8f);
    CHECK(begin_fird(&f.c,captured)==1);
    CHECK(value(first+0x3C,input_lens) && input_lens==captured);
    CHECK(value(top+0x3C,input_lens) && input_lens==.8f);
    // A newly active earlier normal4 becomes the exact input source while
    // the former source is still a live owned queue row, so retire it first.
    const uint64_t earlier=f.c.context+0x200+31*0xE8;
    put<uint32_t>(earlier,4);put<uint32_t>(earlier+4,f.c.avatar);put<float>(earlier+0x3C,.6f);
    put<uint32_t>(f.c.context+0x1F8,31);CHECK(NADSF_BindFird(active_generation,top)==1);
    CHECK(value(first+0x3C,input_lens) && input_lens==.4f);
    CHECK(value(earlier+0x3C,input_lens) && input_lens==captured && armed.load()==1);
    CHECK(value(top+0x3C,input_lens) && input_lens==.8f);
    CHECK(end_current()==1);CHECK(value(earlier+0x3C,input_lens) && input_lens==.6f);
    pass("Fird immediate normal4 fade handoff normalizes the first input row and restores a still-active former input row");

    f.normal();const uint64_t equal_former=f.c.request;put<float>(equal_former+0x3C,.4f);
    f.top(4,2,saved_weapon);CHECK(begin_fird(&f.c,captured)==1);
    put<uint32_t>(earlier,4);put<uint32_t>(earlier+4,f.c.avatar);put<float>(earlier+0x3C,.6f);
    put<uint32_t>(f.c.context+0x1F8,31);
    // Both rows have just been evaluated. The former source's new native
    // result happens to equal our previous fixed value, so do not replay .4.
    put<float>(equal_former+0x3C,captured);f.sample(.6f);
    CHECK(value(equal_former+0x3C,input_lens) && input_lens==captured);
    CHECK(value(earlier+0x3C,input_lens) && input_lens==captured && armed.load()==1);
    CHECK(end_current()==1);CHECK(value(earlier+0x3C,input_lens) && input_lens==.6f);
    pass("Fird post-evaluation fade retirement preserves a fresh native result equal to the previously authored lens");

    f.normal();const uint64_t lost=f.c.request;put<float>(lost+0x3C,.45f);CHECK(begin_fird(&f.c,captured)==1);
    f.top(4,2,saved_weapon);put<uint32_t>(f.c.context+0x1F8,1);
    CHECK(end_current()==1);CHECK(value(lost+0x3C,input_lens) && input_lens==captured);
    f.normal();put<float>(f.c.request+0x3C,.5f);CHECK(begin_fird(&f.c,captured)==1);
    put<float>(f.c.request+0x3C,.63f);CHECK(end_current()==1);
    CHECK(value(f.c.request+0x3C,input_lens) && input_lens==.63f);
    pass("Fird End never writes a retired request or overwrites a native/foreign replacement");

    f.normal();const uint64_t ads_base=f.c.request;put<float>(ads_base+0x3C,.7f);CHECK(begin_fird(&f.c,captured)==1);
    f.top(6,2,saved_weapon);const uint64_t ads_request=f.c.request;
    put<float>(ads_request+0x3C,.18f);put<float>(ads_request+0x84,.29f);
    put<float>(ads_base+0x3C,.7f);f.controls(0,true);f.sample(.29f);
    CHECK(value(ads_request+0x3C,input_lens) && input_lens==.18f);
    CHECK(value(ads_request+0x84,input_lens) && input_lens==.29f && last()==.29f);
    CHECK(!policy.input_lens.active);
    CHECK(end_current()==1);CHECK(value(ads_base+0x3C,input_lens) && input_lens==.7f);
    CHECK(value(ads_request+0x84,input_lens) && input_lens==.29f);
    pass("Fird camera6 request3C/84 remain untouched and its underlying normal4 ledger retires without stale replay");

    for(uint64_t offset:{8ULL,12ULL}) {
        f.normal();const uint64_t recycled=f.c.request;put<float>(recycled+0x3C,.61f);
        CHECK(begin_fird(&f.c,captured)==1);uint32_t old=0;CHECK(value(recycled+offset,old));
        put<uint32_t>(recycled+offset,old+1);CHECK(end_current()==1);
        CHECK(value(recycled+0x3C,input_lens) && input_lens==captured);
    }
    pass("Fird same-avatar/kind request replacement at header8 or12 is never restored from a prior ledger");

    f.normal();put<float>(f.c.request+0x3C,.55f);CHECK(begin_fird(&f.c,captured)==1);
    DWORD previous_protection=0;CHECK(VirtualProtect(reinterpret_cast<void*>(f.c.context),0x3000,PAGE_READONLY,&previous_protection));
    CHECK(end_current()==0 && reserved.load()==1 && armed.load()==0 && policy.input_lens.active);
    DWORD ignored_protection=0;CHECK(VirtualProtect(reinterpret_cast<void*>(f.c.context),0x3000,previous_protection,&ignored_protection));
    CHECK(end_current()==1);CHECK(value(f.c.request+0x3C,input_lens) && input_lens==.55f);
    pass("Fird unreadable/nonwritable cleanup retains the generation and retries its input field before restoring the dispatch slot");

    f.normal();put<float>(f.c.request+0x3C,NAN);fixture_cas_calls=0;
    CHECK(NADSF_ValidateFird(&f.c)==0 && begin_fird(&f.c,captured)==0 && fixture_cas_calls==0);
    put<float>(f.c.request+0x3C,.7f);
    for(uint64_t address:{f.c.game+0x110b4db,f.c.game+0x111e3d8,f.c.game+0x111ba5e,f.c.game+0x111ba7a,f.c.game+0x111ba91,f.c.game+0x111bab5}) {
        uint8_t old=0;CHECK(value(address,old));put<uint8_t>(address,old^1);fixture_cas_calls=0;
        CHECK(NADSF_ValidateFird(&f.c)==0 && begin_fird(&f.c,captured)==0 && fixture_cas_calls==0);
        put<uint8_t>(address,old);
    }
    f.normal();const uint64_t foreign_first=f.c.request;f.top(4,2,saved_weapon);
    put<uint32_t>(foreign_first+4,f.c.avatar+1);fixture_cas_calls=0;
    CHECK(begin_fird(&f.c,captured)==0 && fixture_cas_calls==0);
    put<uint32_t>(foreign_first+4,f.c.avatar);f.normal();
    pass("Fird input lenses, first-row avatar ownership and dispatch/write/input-ratio code pins reject drift before any install");
    f.fp();f.c.reserved=180;fixture_now=100;
    CHECK(begin_current(&f.c)==1);const float hip180=last();
    f.controls(0,true);f.top(6,3,f.c.weapon);f.sample(.3f);CHECK(approximately(last(),hip180));
    fixture_now=100.09;f.sample(.3f);CHECK(last()>.3f && last()<hip180);
    fixture_now=100.18;f.sample(.3f);CHECK(last()==.3f);
    f.sample(.25f);CHECK(last()==.25f);
    pass("opt-in native ADS on a new owned request eases from hip and settles to fresh exact native zoom");
    f.controls();f.top(4,4,f.c.weapon);f.sample(hip180);CHECK(approximately(last(),.25f));
    fixture_now=100.27;f.sample(hip180);const float halfway=last();CHECK(halfway>.25f && halfway<hip180);
    f.top(6,5,f.c.weapon);f.sample(.7f);CHECK(approximately(last(),halfway));
    CHECK(NADSF_Bind(active_generation,f.c.request,f.c.weapon)==1);CHECK(approximately(last(),halfway));
    fixture_now=100.37;f.sample(.7f);CHECK(last()==hip180);CHECK(end_current()==1);
    pass("native ADS exit preserves lens continuity across normal4 fallback and manual6 rebind without delaying settled hip");
    f.fp();fixture_now=200;CHECK(begin_current(&f.c)==1);f.controls(0,true);f.sample(.3f);
    fixture_now=200.06;f.sample(.3f);const float before_reverse=last();
    f.controls();f.sample(.7f);CHECK(approximately(last(),before_reverse));fixture_now=200.25;f.sample(.7f);CHECK(last()==hip180);
    f.controls(0,true);f.sample(.3f);fixture_clock_ok=false;f.sample(.3f);CHECK(last()==.3f);fixture_clock_ok=true;
    CHECK(end_current()==1);pass("reversing ADS starts at the current lens; unavailable transition clock forwards native safely");
    f.fp();fixture_now=300;CHECK(begin_current(&f.c)==1);f.controls(0,true);f.top(6,6,f.c.weapon+1);f.sample(.4f);CHECK(last()==.4f);
    f.top(6,7,f.c.weapon);f.controls(32);f.sample(.45f);CHECK(last()==.45f);CHECK(end_current()==1);
    f.c.reserved=0;pass("unrelated weapons and unsupported actions never receive handoff smoothing");
    f.fp();f.c.reserved=180;fixture_now=400;CHECK(begin_current(&f.c)==1);
    const float shared_hip=last();
    CHECK(NADSF_SetTransition(active_generation,10,1,0)==1);
    f.sample(.7f);CHECK(last()==shared_hip);
    CHECK(NADSF_SetTransition(active_generation,11,0,1)==1);
    f.controls(0,true);f.top(6,2,f.c.weapon);f.sample(.3f);CHECK(last()==shared_hip);
    f.sample(.2f);CHECK(last()==shared_hip);
    CHECK(NADSF_SetTransition(active_generation,11,.5f,1)==1);f.sample(.2f);
    const float shared_half=last();CHECK(shared_half>.2f && shared_half<shared_hip);
    f.sample(.1f);CHECK(last()==shared_half);
    CHECK(NADSF_SetTransition(active_generation,11,.75f,1)==1);f.sample(.1f);
    CHECK(last()>.1f && last()<shared_half);
    CHECK(NADSF_SetTransition(active_generation,11,1,1)==1);f.sample(.12f);CHECK(last()==.12f);
    f.sample(.15f);CHECK(last()==.15f);
    pass("shared phase owns focal handoff, coalesces repeated phases, follows late native targets and settles exactly");
    CHECK(NADSF_SetTransition(active_generation,12,0,0)==1);f.controls();f.top(4,3,f.c.weapon);f.sample(shared_hip);
    CHECK(last()==.15f);CHECK(NADSF_SetTransition(active_generation,12,.5f,0)==1);f.sample(shared_hip);
    const float shared_exit=last();CHECK(shared_exit>.15f && shared_exit<shared_hip);
    CHECK(NADSF_SetTransition(active_generation,13,0,1)==1);f.controls(0,true);f.top(6,4,f.c.weapon);f.sample(.2f);
    CHECK(last()==shared_exit);CHECK(NADSF_SetTransition(active_generation,13,1,1)==1);f.sample(.2f);CHECK(last()==.2f);
    pass("shared ADS reversal and request rebind start from the lens actually presented without older-lens replay");
    const auto before_bad_phase=calls;
    CHECK(NADSF_SetTransition(active_generation,12,1,0)==0);
    CHECK(NADSF_SetTransition(active_generation,13,.5f,1)==0);
    CHECK(NADSF_SetTransition(active_generation,13,1,0)==0);
    CHECK(NADSF_SetTransition(active_generation,14,NAN,1)==0);
    CHECK(NADSF_SetTransition(active_generation,14,-.1f,1)==0);
    CHECK(NADSF_SetTransition(active_generation,14,1.1f,1)==0);
    CHECK(NADSF_SetTransition(active_generation,14,.5f,2)==0);
    CHECK(NADSF_SetTransition(active_generation+1,14,.5f,1)==0);
    CHECK(calls==before_bad_phase && armed.load()==1);
    CHECK(NADSF_SetTransition(active_generation,14,.5f,1)==1);f.sample(.3f);
    pass("shared phase rejects stale epochs, regression, mode mutation, malformed progress and foreign generation without setter calls");
    f.controls();f.top(4,5,f.c.weapon);f.sample(shared_hip);CHECK(last()==shared_hip);
    CHECK(NADSF_SetTransition(active_generation,15,0,0)==1);f.sample(shared_hip);CHECK(last()==shared_hip);
    f.top(6,6,f.c.weapon);CHECK(NADSF_Bind(active_generation,f.c.request,f.c.weapon)==1);
    f.shoulder(true);CHECK(NADSF_SetTransition(active_generation,16,0,0)==1);f.sample(.7f);CHECK(last()==shared_hip);
    CHECK(NADSF_SetTransition(active_generation,16,.5f,0)==1);f.sample(.7f);
    const float shared_shoulder=last();CHECK(shared_shoulder<shared_hip && shared_shoulder>lens(90,1.05));
    CHECK(NADSF_SetTransition(active_generation,16,1,0)==1);f.sample(.7f);CHECK(approximately(last(),lens(90,1.05)));
    pass("native mode wins an old token and normal-shoulder lens consumes the same phase without a stacked120ms tween");
    CHECK(NADSF_SetTransition(active_generation,17,0,0)==1);fixture_now=400.251;
    f.controls(0,true);f.sample(.23f);CHECK(last()==.23f && !policy.shared_phase);
    CHECK(NADSF_SetTransition(active_generation,18,0,1)==1);fixture_clock_ok=false;f.sample(.21f);
    CHECK(last()==.21f && !policy.shared_phase);fixture_clock_ok=true;
    CHECK(end_current()==1);CHECK(NADSF_SetTransition(active_generation,19,0,0)==0);
    pass("expired or unavailable phase clocks return exact native view, and retired generations cannot publish a phase");
    f.normal();f.c.reserved=0;CHECK(begin_fird(&f.c,captured)==1);CHECK(NADSF_SetTransition(active_generation,20,.5f,0)==0);
    CHECK(end_current()==1);f.c.reserved=0;
    pass("Fird captured projection rejects the TrueFP shared-phase control");
    owner_read_failures(f);
    uint8_t code_after[64]{};CHECK(read(reinterpret_cast<uint64_t>(synthetic_setter),code_after,64));CHECK(std::memcmp(code_before,code_after,64)==0);
    pass("setter executable bytes unchanged");std::printf("Native FOV fixture PASS: %llu cases\n",static_cast<unsigned long long>(cases));return 0;
}
