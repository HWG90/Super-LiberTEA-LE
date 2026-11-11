// Synthetic local buffers only. No game process or installed files are touched.
#define NADSC_FIXTURE
#include "native_ads_camera.cpp"
#include <cstdio>
#include <cstdlib>
#include <thread>
#define CHECK(x) do{if(!(x)){std::fprintf(stderr,"FAIL %d: %s error=%u\n",__LINE__,#x,NADSC_Error());std::abort();}}while(0)
static uint64_t active_generation=0,cases=0,calls=0,camera_local=0,camera_world=0;
struct Record {void* camera;uint32_t unit,bits[4];const float* input;};static Record records[4096]{};
static HANDLE setter_reached=nullptr,setter_continue=nullptr;
__declspec(noinline) static void synthetic_setter(void* camera,uint32_t unit,const float* point) {
    CHECK(calls<4096);auto& r=records[calls++];r.camera=camera;r.unit=unit;r.input=point;std::memcpy(r.bits,point,16);
    std::memcpy(reinterpret_cast<void*>(camera_local),point,12);std::memcpy(reinterpret_cast<void*>(camera_world),point,12);
    if(setter_reached) {SetEvent(setter_reached);WaitForSingleObject(setter_continue,INFINITE);}
}
__declspec(noinline) static void foreign_setter(void*,uint32_t,const float*) {}
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
static uint32_t begin_current(const NADSC_Config* c) {
    uint64_t token=UINT64_MAX;const uint32_t result=NADSC_Begin(c,&token);
    if(result==0)CHECK(token==0);else {CHECK((result==1 || result==2) && token && token!=active_generation);active_generation=token;}
    return result;
}
static uint32_t end_current() {return NADSC_End(active_generation);}
static float last(unsigned axis) {float f=0;std::memcpy(&f,&records[calls-1].bits[axis],4);return f;}
static bool approximately(float a,float b) {return std::fabs(a-b)<.0001f;}
static void pass(const char* name) {++cases;std::printf("PASS %s\n",name);}
// The seam changes protection only on our VirtualAlloc data, then calls the
// production ReadProcessMemory path. No stack, executable or game pages are used.
static void fail_rpm_once(uint64_t at,bool restore_readable=true) {
    CHECK(fixture_rpm_failure_remaining==0);
    fixture_rpm_failure_at=at;fixture_rpm_failure_remaining=1;
    fixture_rpm_restore_readable=restore_readable;
}
static void clear_rpm_failure() {
    fixture_rpm_failure_at=0;fixture_rpm_failure_remaining=0;fixture_rpm_restore_readable=true;
}
static void recovery_event(const char* stage,uint32_t result,uint32_t native_error,uint64_t token,
                           uint64_t cas_changes,bool exact_native=false,const NADSC_Stats* stats=nullptr) {
    std::printf("RECOVERY_EVENT {\"stage\":\"%s\",\"result\":%u,\"native_error\":%u,\"token\":%llu,"
        "\"cas_changes\":%llu,\"rpm_failures\":%llu,\"exact_native\":%s,\"armed\":%u,\"installed\":%u,\"reserved\":%u}\n",
        stage,result,native_error,static_cast<unsigned long long>(token),static_cast<unsigned long long>(cas_changes),
        static_cast<unsigned long long>(fixture_rpm_failures),exact_native?"true":"false",
        stats?stats->armed:armed.load(),stats?stats->installed:installed.load(),reserved.load());
}
struct Fixture {
    NADSC_Config c{};uint64_t controller=0,descriptor=0,registry=0,units=0,generations=0,body_object=0,camera_object=0;
    uint64_t api=0,hashes=0,links=0,body_world=0,body_vtable=0,camera_locals=0,camera_worlds=0,request=0;
    uint64_t anim_instance=0,anim_graph=0,anim_current=0,anim_definition=0,settings=0;
    Setter invoke=nullptr;float input[4]{-2,0,1,0};
    Fixture() {
        c.size=sizeof c;c.abi=1;c.game=allocate(0x3382000,PAGE_EXECUTE_READWRITE);c.exe=allocate(0x29fe000);
        fake_image(c.game,0x6af322c1,0x3382000);fake_image(c.exe,0x6af2d5e6,0x29fe000);
        // Independent literal captures from batches1616/1627, not production constants.
        literal(c.exe+0x2dd5a0,"48895c2408574883ec60488bd9498bf88bcae81931dcff4c8b4b184c8bd04c6343208b4708498bd048c1e206498b4920");
        literal(c.exe+0x1f30e0,"40534883ec204863dae8e2d5eaff488bc84c8b0041ff90e8000000488bcb48c1e10648034828488bc14883c4205bc3");
        literal(c.exe+0x28d3c0,"488d4160c3");
        literal(c.exe+0x28d510,"488b8178010000c3");
        c.context=allocate(0x3000);c.camera=allocate(0x1000);c.avatar_owner=allocate(0x540000);
        c.avatar_index=0;c.avatar=0x333;c.body=0x400003;c.camera_unit=0x400004;
        c.forward=.18f;c.up=.04f;c.blend_ms=150;c.smoothing_ms=100;c.max_gap_ms=250;
        controller=allocate(0x1000);descriptor=allocate(0x1000);registry=allocate(0x1000);units=allocate(0x1000);
        generations=allocate(0x1000);body_object=allocate(0x1000);camera_object=allocate(0x1000);body_vtable=allocate(0x1000);
        put<uint64_t>(c.game+0x2e287d0,c.context);put<uint64_t>(c.context,c.camera);put<uint32_t>(c.context+8,c.camera_unit);
        put<uint64_t>(c.game+0x2ce1ee0,c.avatar_owner);put<uint64_t>(c.game+0x2e381a8,controller);
        settings=allocate(0xAD000);put<uint64_t>(c.game+0x2ce1508,settings);
        put<uint32_t>(c.avatar_owner+0x6C,1);put<uint64_t>(c.avatar_owner+0x110,descriptor);
        put<uint32_t>(descriptor+8,c.avatar);put<uint32_t>(descriptor+12,c.body);
        put<uint64_t>(c.exe+0x1ab76f8,registry);put<uint32_t>(registry+0x98,16);
        put<uint64_t>(registry+0x88,units);put<uint64_t>(registry+0xA0,generations);
        put<uint8_t>(generations+3,1);put<uint64_t>(units+3*8,body_object);
        put<uint8_t>(generations+4,1);put<uint64_t>(units+4*8,camera_object);
        put<uint64_t>(body_object,body_vtable);put<uint64_t>(body_vtable+0xE8,c.exe+0x28d3c0);
        hashes=allocate(0x1000);links=allocate(0x1000);body_world=allocate(107*64);
        put<uint32_t>(body_object+0x70,107);put<uint64_t>(body_object+0xA0,hashes);put<uint64_t>(body_object+0x98,links);
        put<uint64_t>(body_object+0x88,body_world);put<uint32_t>(hashes+90*4,0x8C5570C9);put<uint32_t>(hashes+89*4,0xE9ECCA21);
        put<uint32_t>(links+90*4,(89u<<16)|1u);
        anim_instance=allocate(0x1000);anim_graph=allocate(0x20000);anim_current=allocate(0x1000);anim_definition=anim_graph+0x200;
        put<uint64_t>(body_vtable+0x1B0,c.exe+0x28d510);put<uint64_t>(body_object+0x178,anim_instance);
        put<uint64_t>(body_object+0x358,0x4D1C334D294DFA97ULL);put<uint64_t>(anim_instance+0x28,anim_graph);
        put<uint64_t>(anim_instance+0x50,anim_current);put<uint32_t>(anim_graph+4,31);put<uint32_t>(anim_graph+8,0x100);
        put<uint32_t>(anim_graph+0x100+4+13*4,0x100);put<uint32_t>(anim_definition+8,128);
        for(uint32_t i=0;i<128;++i)put<uint32_t>(anim_definition+12+i*4,0x1000+i*16);
        camera_locals=allocate(0x1000);camera_worlds=allocate(0x1000);
        put<uint64_t>(c.camera+0x18,camera_object+0x60);put<uint32_t>(c.camera+0x20,0);put<uint32_t>(camera_object+0x70,1);
        put<uint64_t>(camera_object+0x80,camera_locals);put<uint64_t>(camera_object+0x88,camera_worlds);
        camera_local=camera_locals+0x24;camera_world=camera_worlds+0x30;
        const uint64_t root=allocate(0x1000);api=allocate(0x1000);put<uint64_t>(c.game+0x2ce14c8,root);put<uint64_t>(root+0x20,api);
        put<uint64_t>(api+0x20,reinterpret_cast<uint64_t>(synthetic_setter));fixture_target=synthetic_setter;
        // sub rsp,28; mov r9,API; call [r9+20]; add rsp,28; ret.
        const uint64_t site=c.game+0x110bff5;literal(site-14,"4883ec2849b9");put<uint64_t>(site-8,api);
        literal(site,"41ff51204883c428c3");CHECK(FlushInstructionCache(GetCurrentProcess(),reinterpret_cast<void*>(site-14),23));
        invoke=reinterpret_cast<Setter>(site-14);normal();
    }
    void controls(uint32_t mask=0,bool active=false,bool guard=false) {put<uint32_t>(controller,mask);put<uint8_t>(controller+4,active?1:0);put<uint8_t>(controller+5,guard?1:0);}
    void point(uint64_t at,float x,float y,float z) {put<float>(at,x);put<float>(at+4,y);put<float>(at+8,z);}
    void body(float x=0,float y=0,float z=0,float head_z=1.5f) {point(body_world+0x30,x,y,z);point(body_world+90*64+0x30,x,y,z+head_z);}
    void body_yaw(float radians=0) {
        const float cosine=std::cos(radians),sine=std::sin(radians);
        point(body_world,cosine,sine,0);point(body_world+0x10,-sine,cosine,0);point(body_world+0x20,0,0,1);
    }
    void top(uint32_t kind) {put<uint32_t>(c.context+0x1F8,0);put<uint32_t>(c.context+0x1FC,1);request=c.context+0x200;
        put<uint32_t>(request,kind);put<uint32_t>(request+4,c.avatar);put<uint32_t>(request+8,0x444);put<uint32_t>(request+12,c.body);}
    void normal() {
        controls();top(4);body();body_yaw();put<uint8_t>(c.avatar_owner+0x53e896,0);put<uint64_t>(camera_object+0x1D0,0);
        put<uint32_t>(c.avatar_owner+0x53e888,0);put<uint32_t>(settings+0xac29c,0);
        put<uint64_t>(anim_current+13*8,anim_definition+0x1000+36*16);
        point(c.context+0x0C,1,0,0);point(c.context+0x1C,0,1,0);point(c.context+0x2C,0,0,1);
        point(camera_local,0,0,0);point(camera_world,0,0,0);input[0]=-2;input[1]=0;input[2]=1;input[3]=0;
    }
    void begin() {normal();CHECK(begin_current(&c)==1);}
    void sample(double elapsed=16) {fixture_time+=elapsed;invoke(reinterpret_cast<void*>(c.camera),c.camera_unit,input);}
    void settle() {sample();sample(150);CHECK(approximately(policy.blend,1));}
    NADSC_Stats stats() {NADSC_Stats s{};s.size=sizeof s;s.abi=1;CHECK(NADSC_ReadStats(reserved.load()?active_generation:0,&s)==1);return s;}
};
int main() {
    Fixture f;CHECK(f.stats().installed==0);CHECK(NADSC_Validate(&f.c)==1 && fixture_cas_calls==0);
    CHECK(begin_current(&f.c)==1 && calls==0);CHECK(end_current()==1);pass("read-only preflight; Begin owns dispatch without out-of-frame camera writes");

    // A real failed RPM on an otherwise readable owner span is the only new
    // retryable result. Neither preflight may acquire a token or alter dispatch.
    f.normal();const auto recovery_cas=fixture_cas_calls;const auto recovery_failures=fixture_rpm_failures;
    const auto native_slot=*reinterpret_cast<const uint64_t*>(f.api+0x20);
    fail_rpm_once(f.controller);
    const uint32_t validate_read=NADSC_Validate(&f.c),validate_error=NADSC_Error();
    CHECK(validate_read==0 && validate_error==READ_FAILED && fixture_rpm_failure_remaining==0);
    CHECK(fixture_rpm_failures==recovery_failures+1 && reserved.load()==0 && fixture_cas_calls==recovery_cas);
    CHECK(*reinterpret_cast<const uint64_t*>(f.api+0x20)==native_slot);
    recovery_event("validate_read_failed",validate_read,validate_error,0,fixture_cas_calls-recovery_cas);
    clear_rpm_failure();CHECK(NADSC_Validate(&f.c)==1 && NADSC_Error()==OK);
    fail_rpm_once(f.controller);uint64_t rejected_token=UINT64_MAX;
    const uint32_t begin_read=NADSC_Begin(&f.c,&rejected_token),begin_error=NADSC_Error();
    CHECK(begin_read==0 && begin_error==READ_FAILED && rejected_token==0 && reserved.load()==0);
    CHECK(fixture_rpm_failures==recovery_failures+2 && fixture_rpm_failure_remaining==0 && fixture_cas_calls==recovery_cas);
    CHECK(*reinterpret_cast<const uint64_t*>(f.api+0x20)==native_slot);
    recovery_event("begin_read_failed",begin_read,begin_error,rejected_token,fixture_cas_calls-recovery_cas);
    clear_rpm_failure();pass("real transient owner RPM failure returns code3 without token dispatch mutation or sticky success error");

    // Restore=false leaves a committed inaccessible page. That is an unsafe
    // ownership failure, as are semantic mismatch, invalid and unmapped owners.
    fail_rpm_once(f.controller,false);CHECK(NADSC_Validate(&f.c)==0 && NADSC_Error()==OWNER_MISMATCH);
    CHECK(fixture_rpm_failure_remaining==0 && fixture_rpm_failures==recovery_failures+3);
    MEMORY_BASIC_INFORMATION inaccessible{};CHECK(VirtualQuery(reinterpret_cast<void*>(f.controller),&inaccessible,sizeof inaccessible)==sizeof inaccessible);
    CHECK(inaccessible.State==MEM_COMMIT && inaccessible.Protect==PAGE_NOACCESS);
    DWORD discarded=0;CHECK(VirtualProtect(reinterpret_cast<void*>(f.controller),0x1000,PAGE_READWRITE,&discarded));clear_rpm_failure();
    f.controls(0x20);CHECK(NADSC_Validate(&f.c)==0 && NADSC_Error()==OWNER_MISMATCH);
    rejected_token=UINT64_MAX;CHECK(NADSC_Begin(&f.c,&rejected_token)==0 && rejected_token==0 && NADSC_Error()==OWNER_MISMATCH);
    f.controls();put<uint64_t>(f.c.game+0x2e381a8,1);
    CHECK(NADSC_Validate(&f.c)==0 && NADSC_Error()==OWNER_MISMATCH);
    const uint64_t unmapped=allocate(0x1000);CHECK(VirtualFree(reinterpret_cast<void*>(unmapped),0,MEM_RELEASE));
    put<uint64_t>(f.c.game+0x2e381a8,unmapped);CHECK(NADSC_Validate(&f.c)==0 && NADSC_Error()==OWNER_MISMATCH);
    put<uint64_t>(f.c.game+0x2e381a8,f.controller);
    const uint8_t original_code=*reinterpret_cast<const uint8_t*>(f.c.exe+0x2dd5a0);
    put<uint8_t>(f.c.exe+0x2dd5a0,0);CHECK(NADSC_Validate(&f.c)==0 && NADSC_Error()==CODE_MISMATCH);
    put<uint8_t>(f.c.exe+0x2dd5a0,original_code);
    CHECK(fixture_cas_calls==recovery_cas && reserved.load()==0 && *reinterpret_cast<const uint64_t*>(f.api+0x20)==native_slot);
    CHECK(NADSC_Validate(&f.c)==1 && NADSC_Error()==OK);
    pass("inaccessible mapped unmapped invalid semantic and code failures remain unsafe after a transient read error");

    // The armed path must forward the original native6 frame and keep its lease
    // only for cleanup; classification comes from the public stats export.
    f.begin();f.top(6);float recovery_frame[20]{.12f,.04f,1.38f};recovery_frame[3]=-.0f;
    const uint32_t recovery_nan=0x7fc01234;std::memcpy(recovery_frame+17,&recovery_nan,4);
    uint8_t recovery_copy[80]{};std::memcpy(recovery_copy,recovery_frame,80);
    const auto armed_cas=fixture_cas_calls;const auto armed_failures=fixture_rpm_failures;fail_rpm_once(f.controller);
    fixture_time+=16;f.invoke(reinterpret_cast<void*>(f.c.camera),f.c.camera_unit,recovery_frame);
    const auto read_fault_stats=f.stats();
    const bool recovery_exact=records[calls-1].input==recovery_frame && std::memcmp(records[calls-1].bits,recovery_copy,16)==0
        && std::memcmp(recovery_frame,recovery_copy,80)==0;
    CHECK(recovery_exact && read_fault_stats.armed==0 && read_fault_stats.installed==1 && read_fault_stats.error==READ_FAILED);
    CHECK(fixture_rpm_failure_remaining==0 && fixture_rpm_failures==armed_failures+1 && fixture_cas_calls==armed_cas && reserved.load()==1);
    recovery_event("callback_read_failed",1,read_fault_stats.error,active_generation,fixture_cas_calls-armed_cas,recovery_exact,&read_fault_stats);
    clear_rpm_failure();CHECK(end_current()==1 && reserved.load()==0 && NADSC_Error()==OK);
    CHECK(NADSC_Validate(&f.c)==1 && NADSC_Error()==OK);
    pass("armed native6 owner RPM failure forwards the exact native frame and disarms with code3 until acknowledged End");

    // Start both request classes directly from an actual code3 callback, so a
    // failed legacy bool export cannot expose an unrelated old retryable error.
    for(bool invalid_output:{false,true}) {
        f.begin();f.top(6);fail_rpm_once(f.controller);f.sample();
        CHECK(f.stats().error==READ_FAILED && !armed.load());clear_rpm_failure();
        if(invalid_output) {
            CHECK(NADSC_KickStats46(active_generation,reinterpret_cast<NADSC_KickStats46Data*>(1))==0);
            CHECK(NADSC_Error()==INVALID_CONFIG);
            CHECK(NADSC_FreeAim(active_generation+1,0)==0 && NADSC_Error()==TOKEN_MISMATCH);
        }else {
            NADSC_FreeStats stale_stats{};
            CHECK(NADSC_FreeAimStats(active_generation+1,&stale_stats)==0 && NADSC_Error()==TOKEN_MISMATCH);
            CHECK(NADSC_Profile47(active_generation,1001)==0 && NADSC_Error()==INVALID_CONFIG);
        }
        CHECK(end_current()==1);
    }
    pass("legacy stale-token invalid-output and out-of-range requests replace prior actual code3 with their own code17 or1");

    // Optional handoff-history reads have no authority to make a later semantic
    // owner mismatch retryable. The +4 address is the allocated controller page,
    // but is read here by optional sampling rather than the terminal owner proof.
    for(bool lose_owner:{false,true}) {
        f.begin();f.top(6);
        // This behavior-only fixture invokes a synthetic machine-code caller,
        // not the captured presentation callsite required by the public API.
        // Enable optional history privately, as the existing handoff cases do;
        // Validate/Begin/ReadStats fault evidence above uses actual exports.
        policy.presentation_enabled=true;
        const auto optional_failures=fixture_rpm_failures;fail_rpm_once(f.controller+4);
        uint32_t saved_generation_word=0;
        if(lose_owner){CHECK(value(f.generations+3,saved_generation_word));fixture_before_history_mutation=f.generations+3;fixture_before_history_value=2;}
        fixture_time+=16;f.invoke(reinterpret_cast<void*>(f.c.camera),f.c.camera_unit,recovery_frame);
        const auto optional_stats=f.stats();
        CHECK(records[calls-1].input==recovery_frame && std::memcmp(recovery_frame,recovery_copy,80)==0);
        CHECK(fixture_rpm_failure_remaining==0 && fixture_rpm_failures==optional_failures+1);
        CHECK(optional_stats.armed==(lose_owner?0u:1u) && optional_stats.error==(lose_owner?OWNER_MISMATCH:OK));
        if(lose_owner){CHECK(fixture_before_history_mutation==0);put<uint32_t>(f.generations+3,saved_generation_word);}
        clear_rpm_failure();CHECK(end_current()==1);
    }
    pass("optional native6 history RPM failure neither disarms a valid owner nor taints a later semantic owner mismatch as retryable");

    f.begin();f.settle();const auto offsets_cas=fixture_cas_calls;
    CHECK(NADSC_SetOffsets(active_generation,.1f,-.1f,.02f)==1);f.sample();
    CHECK(approximately(last(0),.1f)&&approximately(last(1),-.1f)&&approximately(last(2),1.52f));
    CHECK(policy.blend==1 && fixture_cas_calls==offsets_cas);
    CHECK(NADSC_SetOffsets(active_generation+1,.2f,0,0)==0 && policy.side==.1f);
    CHECK(NADSC_SetOffsets(active_generation,.6f,0,0)==0 && policy.side==.1f);
    f.top(6);f.sample();CHECK(records[calls-1].input==f.input);
    CHECK(end_current()==1);CHECK(NADSC_SetOffsets(active_generation,0,0,0)==0);
    pass("owned live XYZ offsets preserve blend and dispatch, reject stale/range writes, and leave native ADS exact");
    for(uint32_t kind:{4u,6u}) {
        f.normal();f.top(kind);f.controls(0x20);const auto prior_cas=fixture_cas_calls;uint64_t rejected=99;
        CHECK(NADSC_Validate(&f.c)==0 && NADSC_Error()==OWNER_MISMATCH);
        CHECK(NADSC_Begin(&f.c,&rejected)==0 && rejected==0 && reserved.load()==0 && fixture_cas_calls==prior_cas);
    }pass("observed vault mask cannot Validate or Begin a camera lease in either camera kind");
    f.begin();f.sample();CHECK(approximately(last(0),-2) && approximately(last(2),1));f.sample(75);
    CHECK(approximately(policy.blend,.5f) && approximately(last(0),-1) && approximately(last(1),.09f));
    f.sample(75);CHECK(approximately(last(0),0) && approximately(last(1),.18f) && approximately(last(2),1.54f));
    CHECK(f.stats().replaced==3 && f.stats().head_distance==1.5f);pass("smoothstep ingress uses fresh head and current native offset");
    float before[4]{};std::memcpy(before,f.input,16);f.body(10,20,3);f.input[0]=8;f.input[1]=20;f.input[2]=4;
    f.sample();CHECK(approximately(last(0),10) && approximately(last(1),20.18f) && approximately(last(2),4.54f));
    std::memcpy(before,f.input,16);f.sample();CHECK(std::memcmp(before,f.input,16)==0 && approximately(last(0),10));
    pass("root movement tracks immediately; source untouched and no positional accumulation");CHECK(end_current()==1);
    f.begin();f.point(f.body_world+90*64+0x30,.2f,.1f,1.5f);f.settle();
    CHECK(approximately(last(0),.2f) && approximately(last(1),.28f));
    f.body(10,20,3);f.body_yaw(1.5707963268f);f.point(f.body_world+90*64+0x30,9.9f,20.2f,4.5f);
    f.input[0]=8;f.input[1]=20;f.input[2]=4;f.sample();
    CHECK(approximately(last(0),9.9f) && approximately(last(1),20.38f) && approximately(last(2),4.54f));
    CHECK(approximately(policy.relative_head[0],.2f) && approximately(policy.relative_head[1],.1f));
    pass("fresh body-root translation and rotation carry damped local head without turn or movement lag");CHECK(end_current()==1);
    f.begin();f.settle();f.body(0,0,0,.7f);f.sample(16);CHECK(last(2)<=.80f && last(2)>=.73f);
    pass("head-relative bob smoothing lag is capped at six centimeters");CHECK(end_current()==1);
    f.begin();f.settle();
    for(unsigned frame=0;frame<60;++frame) {
        const float x=static_cast<float>(frame)*.01f,bob=frame%2?.02f:-.02f;
        f.body(x,0,0,1.5f+bob);f.input[0]=x-2;f.sample();
        CHECK(approximately(last(0),x) && std::fabs(last(2)-1.54f)<.004f);
    }
    pass("rapid small action bob is damped while fresh root travel remains exact");CHECK(end_current()==1);
    f.begin();f.settle();const uint32_t nan=0x7fc01234;std::memcpy(&f.input[3],&nan,4);f.sample();CHECK(records[calls-1].bits[3]==nan);
    pass("padding W stays bit-exact including NaN sentinel");CHECK(end_current()==1);
    f.begin();f.settle();f.point(f.c.context+0x1C,1,0,0);f.point(f.c.context+0x0C,0,-1,0);f.sample();
    CHECK(approximately(last(0),.18f) && approximately(last(1),0));pass("bounded forward/up offset uses verified native view basis");CHECK(end_current()==1);
    f.begin();f.settle();
    for(float pitch:{-.9f,.9f,1.5707963268f}) {
        const float c=std::cos(pitch),s=std::sin(pitch);
        f.point(f.c.context+0x0C,1,0,0);f.point(f.c.context+0x1C,0,c,s);f.point(f.c.context+0x2C,0,-s,c);f.sample();
        CHECK(approximately(last(0),0) && approximately(last(1),.18f) && approximately(last(2),1.54f));
    }
    f.point(f.c.context+0x0C,.8f,0,-.6f);f.point(f.c.context+0x1C,0,1,0);f.point(f.c.context+0x2C,.6f,0,.8f);f.sample();
    CHECK(approximately(last(0),0) && approximately(last(1),.18f) && approximately(last(2),1.54f));
    pass("pitch and roll do not orbit the clearance or eye height; vertical view uses current body yaw");CHECK(end_current()==1);
    f.begin();f.settle();const uint64_t old_replaced=replaced.load();f.top(6);put<uint64_t>(f.camera_object+0x1D0,0x1234);
    f.sample();CHECK(records[calls-1].input==f.input && std::memcmp(records[calls-1].bits,f.input,16)==0);
    CHECK(f.stats().native6_forwarded==1 && replaced.load()==old_replaced && armed.load()==1);
    pass("native6 forwards exact pointer and bits even in another parent space");
    f.top(4);put<uint64_t>(f.camera_object+0x1D0,0);f.sample();
    CHECK(policy.blend==1 && approximately(last(0),0) && approximately(last(1),.18f) && approximately(last(2),1.54f));
    pass("first normal4 frame after native6 is at fresh head without TPV retreat or local-space reuse");CHECK(end_current()==1);
    f.begin();f.top(6);f.sample();f.top(4);put<uint64_t>(f.camera_object+0x1D0,0x1234);f.sample();
    CHECK(policy.native6_seen && records[calls-1].input==f.input);put<uint64_t>(f.camera_object+0x1D0,0);f.sample();
    CHECK(policy.blend==1 && approximately(last(2),1.54f));pass("brief parent-space settling preserves recent native6 handoff");CHECK(end_current()==1);
    for(unsigned mode=0;mode<5;++mode) {
        f.begin();f.top(6);f.sample();f.top(4);
        if(mode==0)f.top(12);if(mode==1)f.controls(1);if(mode==2)put<uint64_t>(f.anim_current+13*8,f.anim_definition+0x1000+103*16);
        if(mode==3)put<uint32_t>(f.request+4,f.c.avatar+1);f.sample(mode==4?500:16);
        CHECK(!policy.native6_seen);f.top(4);f.controls();put<uint64_t>(f.anim_current+13*8,f.anim_definition+0x1000+36*16);
        f.sample();CHECK(policy.blend<1 && records[calls-1].input!=nullptr);CHECK(end_current()==1);
    }pass("unsupported foreign unsafe death and long gaps discard stale native6 ingress shortcut");
    f.begin();f.settle();f.sample(500);CHECK(policy.blend==0 && records[calls-1].bits[0]==*reinterpret_cast<uint32_t*>(f.input));
    pass("long frame gap resets interpolation instead of replaying old world positions");CHECK(end_current()==1);
    f.begin();f.settle();for(uint32_t mask:{1u,3u,4u,8u,0x10u,0x22u,0x30u,0x40u,0x60u,0x80u}) {f.controls(mask);f.sample();CHECK(records[calls-1].input==f.input && armed.load()==1);}
    f.controls(0,false,true);f.sample();CHECK(records[calls-1].input==f.input);f.controls(2);f.sample();f.sample(150);
    CHECK(approximately(last(2),1.54f));put<uint8_t>(f.c.avatar_owner+0x53e896,4);f.sample();CHECK(records[calls-1].input==f.input);
    pass("mask2 allows normal head anchor; unknown masks guard and seated states forward");CHECK(end_current()==1);
    f.begin();f.top(6);f.controls(0x20);float vault_source[4]{};std::memcpy(vault_source,f.input,16);f.sample();
    CHECK(records[calls-1].input==f.input && std::memcmp(records[calls-1].bits,vault_source,16)==0 && replaced.load()==0);
    f.top(4);f.sample();
    CHECK(armed.load()==1 && policy.safe==false && policy.fallback_safe && policy.blend==1 && replaced.load()==1);
    CHECK(approximately(last(0),0) && approximately(last(1),.18f) && approximately(last(2),1.54f) && std::memcmp(vault_source,f.input,16)==0);
    pass("owned native6 to on-foot vault normal4 anchors the first frame while native6 and input remain exact");CHECK(end_current()==1);
    f.begin();f.top(6);f.sample();f.top(4);f.controls(0x20);put<uint64_t>(f.camera_object+0x1D0,0x1234);f.sample();
    CHECK(policy.native6_seen && records[calls-1].input==f.input && NADSC_Error()==SPACE_INVALID);
    put<uint64_t>(f.camera_object+0x1D0,0);f.sample();CHECK(policy.blend==1 && approximately(last(2),1.54f));
    pass("vault fallback waits for verified world space without exposing a fresh TPV ingress");CHECK(end_current()==1);
    for(unsigned mode=0;mode<8;++mode) {
        f.begin();f.settle();f.controls(0x20);const auto unchanged=replaced.load();uint32_t saved_hash=0;
        if(mode==0)put<uint64_t>(f.anim_current+13*8,f.anim_definition+0x1000+103*16);
        if(mode==1)f.controls(0x20,false,true);if(mode==2)put<uint8_t>(f.c.avatar_owner+0x53e896,4);
        if(mode==3)put<uint64_t>(f.camera_object+0x1D0,0x1234);if(mode==4)f.point(camera_world,1,0,0);
        if(mode==5) {CHECK(value(f.hashes+90*4,saved_hash));put<uint32_t>(f.hashes+90*4,0);}
        if(mode==6)f.top(7);if(mode==7)put<uint32_t>(f.request+4,f.c.avatar+1);
        f.sample();CHECK(armed.load()==1 && records[calls-1].input==f.input && replaced.load()==unchanged);
        if(mode==5)put<uint32_t>(f.hashes+90*4,saved_hash);CHECK(end_current()==1);
    }pass("vault exception retains on-foot graph owner space guard and seated exclusions");
    f.begin();f.settle();for(uint64_t state:{f.anim_definition+0x1000+103*16,static_cast<uint64_t>(0),f.anim_definition+0x1FFFF}) {
        put<uint64_t>(f.anim_current+13*8,state);f.sample();CHECK(armed.load()==1 && records[calls-1].input==f.input && NADSC_Error()==ON_FOOT_REQUIRED);}
    put<uint64_t>(f.anim_current+13*8,f.anim_definition+0x1000+36*16);f.sample();f.sample(150);CHECK(approximately(last(2),1.54f));
    put<uint32_t>(f.anim_definition+12,0x1000+36*16);f.sample();CHECK(records[calls-1].input==f.input);
    put<uint32_t>(f.anim_definition+12,0x1000);put<uint32_t>(f.anim_graph+4,30);f.sample();CHECK(records[calls-1].input==f.input);
    put<uint32_t>(f.anim_graph+4,31);pass("positive on-foot state36 required; death103 null unknown aliased and wrong graph states forward");CHECK(end_current()==1);
    f.normal();put<uint64_t>(f.anim_current+13*8,f.anim_definition+0x1000+3*16);
    put<uint32_t>(f.c.avatar_owner+0x53e888,0x220A);put<uint32_t>(f.settings+0xac29c,3);
    CHECK(NADSC_Validate(&f.c)==1 && begin_current(&f.c)==1);f.settle();
    CHECK(armed.load()==1 && approximately(last(2),1.54f) && NADSC_Error()==OK);
    f.top(6);f.sample();CHECK(records[calls-1].input==f.input && native6_forwarded.load()==1);
    f.top(4);f.sample();CHECK(approximately(last(2),1.54f) && policy.blend==1);
    CHECK(end_current()==1);pass("observed bridge state3 with scene3 and actual combat-role2 anchors normal4 and preserves native6 exactly");
    for(uint32_t role:{0U,4U,6U,0x220CU,0x220EU}) {
        f.begin();f.settle();put<uint64_t>(f.anim_current+13*8,f.anim_definition+0x1000+3*16);
        put<uint32_t>(f.c.avatar_owner+0x53e888,role);put<uint32_t>(f.settings+0xac29c,3);f.sample();
        CHECK(records[calls-1].input==f.input && NADSC_Error()==ON_FOOT_REQUIRED && armed.load()==1 && !policy.tracking);
        CHECK(end_current()==1);
    }pass("ordinary ship role4, absent role and conflicting role bits never receive the bridge exception");
    for(unsigned mode=0;mode<5;++mode) {
        f.begin();f.settle();put<uint64_t>(f.anim_current+13*8,f.anim_definition+0x1000+(mode==3?4:3)*16);
        put<uint32_t>(f.c.avatar_owner+0x53e888,0x220A);put<uint32_t>(f.settings+0xac29c,mode<3?mode:3);
        if(mode==4)put<uint32_t>(f.anim_definition+12,0x1000+3*16);
        f.sample();CHECK(records[calls-1].input==f.input && NADSC_Error()==ON_FOOT_REQUIRED && armed.load()==1);
        if(mode==4)put<uint32_t>(f.anim_definition+12,0x1000);CHECK(end_current()==1);
    }pass("bridge permission does not admit other scenes, unknown states or first-index aliases");
    for(unsigned mutation=0;mutation<5;++mutation) {
        f.begin();f.settle();put<uint64_t>(f.anim_current+13*8,f.anim_definition+0x1000+3*16);
        put<uint32_t>(f.c.avatar_owner+0x53e888,0x220A);put<uint32_t>(f.settings+0xac29c,3);
        fixture_bridge_mutation=mutation==0?f.c.avatar_owner+0x53e888:mutation==1?f.settings+0xac29c
            :mutation==2?f.generations+3:mutation==3?f.anim_graph+4:f.body_object+0x358;
        uint32_t saved=0;CHECK(value(fixture_bridge_mutation,saved));const uint64_t changed_at=fixture_bridge_mutation;
        fixture_bridge_value=mutation==0?0x220C:mutation==1?4:mutation==2?saved+1:mutation==3?30:0;
        f.sample();CHECK(fixture_bridge_mutation==0 && records[calls-1].input==f.input && NADSC_Error()==ON_FOOT_REQUIRED && armed.load()==1);
        put<uint32_t>(changed_at,saved);CHECK(end_current()==1);
    }pass("bridge gate rereads role scene body generation resource and graph before any head substitution");
    f.begin();f.settle();put<uint32_t>(f.c.avatar_owner+0x53e888,0x220A);put<uint32_t>(f.settings+0xac29c,3);
    f.sample();CHECK(approximately(last(2),1.54f) && NADSC_Error()==OK);
    put<uint32_t>(f.c.avatar_owner+0x53e888,0x220C);put<uint64_t>(f.c.game+0x2ce1508,0);
    f.sample();CHECK(approximately(last(2),1.54f) && NADSC_Error()==OK);CHECK(end_current()==1);
    put<uint64_t>(f.c.game+0x2ce1508,f.settings);
    pass("mission state36 remains independent of bridge scene reads and control-role bits");
    f.begin();f.settle();const auto replaced_before=replaced.load();setter_hook(reinterpret_cast<void*>(f.c.camera),f.c.camera_unit,f.input);
    f.invoke(reinterpret_cast<void*>(f.c.camera+64),f.c.camera_unit,f.input);f.invoke(reinterpret_cast<void*>(f.c.camera),f.c.camera_unit+1,f.input);
    CHECK(replaced.load()==replaced_before && armed.load()==1 && records[calls-1].input==f.input);
    pass("foreign caller camera and UnitRef forward exactly without changing own state");CHECK(end_current()==1);
    f.begin();f.settle();for(uint32_t kind:{0u,1u,7u,12u}) {f.top(kind);f.sample();CHECK(armed.load()==1 && policy.blend==0 && records[calls-1].input==f.input);}
    f.top(4);put<uint32_t>(f.request+4,f.c.avatar+1);f.sample();CHECK(armed.load()==1 && records[calls-1].input==f.input);
    put<uint32_t>(f.request+4,f.c.avatar);f.sample();f.sample(150);CHECK(approximately(last(2),1.54f));
    pass("unsupported or foreign request is native pass-through; stable own camera resumes");CHECK(end_current()==1);
    f.begin();f.settle();const auto stale=active_generation;CHECK(end_current()==1);f.begin();uint64_t busy=99;
    CHECK(NADSC_Begin(&f.c,&busy)==0 && busy==0 && NADSC_End(stale)==0 && armed.load()==1);
    NADSC_Stats s{};s.size=sizeof s;s.abi=1;CHECK(NADSC_ReadStats(0,&s)==0 && NADSC_ReadStats(stale,&s)==0);
    pass("BUSY and stale tokens cannot affect a later reservation");CHECK(end_current()==1);
    for(unsigned mode=0;mode<6;++mode) {
        f.begin();f.settle();uint64_t at=0;uint64_t saved=0;size_t length=0;
        if(mode==0){at=f.descriptor;length=4;}if(mode==1){at=f.generations+3;length=1;}if(mode==2){at=f.units+3*8;length=8;}
        if(mode==3){at=f.c.context;length=8;}if(mode==4){at=f.generations+4;length=1;}if(mode==5){at=f.c.context+8;length=4;}
        if(mode==6){at=f.request+4;length=4;}std::memcpy(&saved,reinterpret_cast<void*>(at),length);
        const uint64_t changed=saved+1;std::memcpy(reinterpret_cast<void*>(at),&changed,length);f.sample();
        CHECK(armed.load()==0 && records[calls-1].input==f.input);std::memcpy(reinterpret_cast<void*>(at),&saved,length);CHECK(end_current()==1);
    }pass("avatar body camera generation object and context ownership changes disarm passively");
    for(unsigned mode=0;mode<4;++mode) {
        f.begin();f.settle();uint64_t at=mode==0?f.hashes+90*4:mode==1?f.links+90*4:mode==2?f.body_object+0x70:f.body_object+0xA0;
        const size_t length=mode==3?8:4;uint64_t saved=0;std::memcpy(&saved,reinterpret_cast<void*>(at),length);
        const uint64_t changed=saved+1;std::memcpy(reinterpret_cast<void*>(at),&changed,length);f.sample();
        CHECK(armed.load()==1 && NADSC_Error()==GRAPH_MISMATCH && records[calls-1].input==f.input);
        std::memcpy(reinterpret_cast<void*>(at),&saved,length);CHECK(end_current()==1);
    }pass("per-frame head hash parent graph count and array identity guards");
    f.normal();put<uint32_t>(f.hashes+91*4,0x8C5570C9);CHECK(NADSC_Validate(&f.c)==0);put<uint32_t>(f.hashes+91*4,0);
    put<uint32_t>(f.hashes+90*4,0);CHECK(NADSC_Validate(&f.c)==0);put<uint32_t>(f.hashes+90*4,0x8C5570C9);
    pass("duplicate or absent head cannot arm");
    f.begin();f.settle();put<uint64_t>(f.camera_object+0x1D0,0x111);f.sample();CHECK(armed.load()==1 && NADSC_Error()==SPACE_INVALID);CHECK(end_current()==1);
    f.normal();f.point(camera_world,1,0,0);CHECK(NADSC_Validate(&f.c)==0 && NADSC_Error()==SPACE_INVALID);
    pass("parented or different local/world camera positions refuse head world coordinates");
    for(unsigned mode=0;mode<4;++mode) {f.begin();f.settle();if(mode==0)f.input[0]=NAN;
        if(mode==1)f.point(f.c.context+0x1C,1,1,1);if(mode==2)f.body(0,0,0,4);if(mode==3)f.input[0]=100;
        f.sample();CHECK(armed.load()==1 && records[calls-1].input==f.input);CHECK(end_current()==1);}
    pass("nonfinite invalid basis implausible head and remote camera forward while retaining stable lease");
    f.begin();f.settle();f.point(f.body_world,2,0,0);f.sample();
    CHECK(records[calls-1].input==f.input && armed.load()==1 && NADSC_Error()==GRAPH_MISMATCH);
    pass("invalid body-root basis forwards native instead of damping in an unproven frame");CHECK(end_current()==1);
    for(uint64_t at:{f.c.exe+0x2dd5a0,f.c.exe+0x1f30e0,f.c.exe+0x28d3c0,f.c.game+0x110bff5}) {
        f.normal();uint8_t b=0;CHECK(value(at,b));put<uint8_t>(at,b^1);CHECK(begin_current(&f.c)==0 && reserved.load()==0);put<uint8_t>(at,b);
    }pass("independent captured setter world-pose graph-getter and callsite bytes required");
    f.normal();fixture_slot_readonly=true;CHECK(begin_current(&f.c)==0);fixture_slot_readonly=false;
    fixture_foreign_cas_at=fixture_cas_calls+1;fixture_foreign_value=reinterpret_cast<uint64_t>(foreign_setter);CHECK(begin_current(&f.c)==0 && reserved.load()==0);
    uint64_t slot_value=0;CHECK(value(f.api+0x20,slot_value) && slot_value==fixture_foreign_value);fixture_foreign_cas_at=0;
    put<uint64_t>(f.api+0x20,reinterpret_cast<uint64_t>(synthetic_setter));pass("read-only slot and foreign CAS owner reject without overwriting foreign dispatch");
    f.normal();fixture_mutate_after_cas=f.request+4;fixture_mutation_value=f.c.avatar+1;fixture_cas_fail_at=fixture_cas_calls+2;
    CHECK(begin_current(&f.c)==2 && active_generation && reserved.load()==1 && armed.load()==0);
    fixture_mutate_after_cas=0;fixture_cas_fail_at=0;fixture_slot_unreadable=true;CHECK(end_current()==0 && reserved.load()==1);
    fixture_slot_unreadable=false;CHECK(end_current()==1 && reserved.load()==0);pass("partial Begin2 retains token for retryable owned cleanup");
    f.begin();fixture_slot_readonly=true;CHECK(end_current()==0 && reserved.load()==1);fixture_slot_readonly=false;CHECK(end_current()==1);
    f.begin();put<uint64_t>(f.api+0x20,reinterpret_cast<uint64_t>(foreign_setter));CHECK(end_current()==1);
    CHECK(value(f.api+0x20,slot_value) && slot_value==reinterpret_cast<uint64_t>(foreign_setter));put<uint64_t>(f.api+0x20,reinterpret_cast<uint64_t>(synthetic_setter));
    pass("End retries its own read-only slot and preserves foreign replacement");
    f.begin();f.settle();const auto calls_before_end=calls;CHECK(end_current()==1 && calls==calls_before_end);
    f.sample();CHECK(records[calls-1].input==f.input);pass("End performs no cached position replay and resident cached callbacks forward");
    f.begin();f.settle();const NADSC_Stats completed=f.stats();f.body(0,0,0,1.6f);
    setter_reached=CreateEventW(nullptr,TRUE,FALSE,nullptr);setter_continue=CreateEventW(nullptr,TRUE,FALSE,nullptr);
    HANDLE stats_done=CreateEventW(nullptr,TRUE,FALSE,nullptr);CHECK(setter_reached && setter_continue && stats_done);
    std::thread display_writer([&]{f.sample();});CHECK(WaitForSingleObject(setter_reached,1000)==WAIT_OBJECT_0);
    armed.store(0,std::memory_order_release);error(OWNER_MISMATCH);
    NADSC_Stats concurrent{};concurrent.size=sizeof concurrent;concurrent.abi=1;uint32_t stats_result=0;
    std::thread display_reader([&]{stats_result=NADSC_ReadStats(active_generation,&concurrent);SetEvent(stats_done);});
    CHECK(WaitForSingleObject(stats_done,1000)==WAIT_OBJECT_0);
    CHECK(stats_result==1 && concurrent.installed==1 && concurrent.armed==0 && concurrent.error==OWNER_MISMATCH
        && concurrent.blend==completed.blend && concurrent.head_distance==completed.head_distance && concurrent.last_dt==completed.last_dt);
    NADSC_Stats invalid{};invalid.size=sizeof invalid;invalid.abi=1;
    CHECK(NADSC_ReadStats(active_generation+1,&invalid)==0 && NADSC_Error()==TOKEN_MISMATCH);
    invalid.abi=2;CHECK(NADSC_ReadStats(active_generation,&invalid)==0 && NADSC_Error()==INVALID_CONFIG);
    invalid.abi=1;invalid.size=sizeof invalid-4;CHECK(NADSC_ReadStats(active_generation,&invalid)==0);
    CHECK(NADSC_ReadStats(active_generation,reinterpret_cast<NADSC_Stats*>(1))==0);
    SetEvent(setter_continue);display_writer.join();display_reader.join();
    CloseHandle(setter_reached);CloseHandle(setter_continue);CloseHandle(stats_done);setter_reached=nullptr;setter_continue=nullptr;
    const auto newly_completed=f.stats();CHECK(newly_completed.head_distance==1.6f && newly_completed.armed==0);
    CHECK(end_current()==1);const auto ended_display=f.stats();CHECK(ended_display.blend==0 && ended_display.last_dt==0);
    pass("camera ReadStats completes while setter is blocked; health is fresh and diagnostics publish only after completion; End publishes reset");

    f.begin();f.settle();const auto coherent=f.stats();display_sequence.fetch_add(1,std::memory_order_seq_cst);
    display_head_distance.store(2.9f,std::memory_order_seq_cst);const auto interrupted=f.stats();
    CHECK(interrupted.blend==coherent.blend && interrupted.head_distance==coherent.head_distance && interrupted.last_dt==coherent.last_dt);
    display_head_distance.store(policy.head_distance,std::memory_order_seq_cst);display_sequence.fetch_add(1,std::memory_order_seq_cst);
    CHECK(end_current()==1);f.begin();const auto fresh_display=f.stats();
    CHECK(fresh_display.blend==0 && fresh_display.last_dt==0 && fresh_display.head_distance==1.5f);
    uint64_t busy_display=UINT64_MAX;CHECK(NADSC_Begin(&f.c,&busy_display)==0 && busy_display==0);
    const auto after_busy=f.stats();CHECK(after_busy.blend==fresh_display.blend && after_busy.head_distance==fresh_display.head_distance
        && after_busy.last_dt==fresh_display.last_dt && after_busy.error==BUSY);
    CHECK(end_current()==1);pass("camera odd publication uses complete cache; new generation resets and BUSY preserves the current tuple");

    f.begin();f.settle();
    fixture_before_policy_reached=CreateEventW(nullptr,TRUE,FALSE,nullptr);fixture_continue_policy=CreateEventW(nullptr,TRUE,FALSE,nullptr);
    fixture_begin_display_reached=CreateEventW(nullptr,TRUE,FALSE,nullptr);fixture_continue_begin=CreateEventW(nullptr,TRUE,FALSE,nullptr);
    CHECK(fixture_before_policy_reached && fixture_continue_policy && fixture_begin_display_reached && fixture_continue_begin);
    std::thread queued_callback([&]{f.sample();});CHECK(WaitForSingleObject(fixture_before_policy_reached,1000)==WAIT_OBJECT_0);
    CHECK(end_current()==1);f.normal();f.body(0,0,0,1.9f);uint32_t new_begin_result=0;
    std::thread new_begin([&]{new_begin_result=begin_current(&f.c);});
    CHECK(WaitForSingleObject(fixture_begin_display_reached,1000)==WAIT_OBJECT_0);
    const uint32_t new_sequence=display_sequence.load(std::memory_order_seq_cst);
    CHECK(display_head_distance.load(std::memory_order_seq_cst)==1.9f);
    SetEvent(fixture_continue_policy);queued_callback.join();
    CHECK(display_sequence.load(std::memory_order_seq_cst)==new_sequence && display_head_distance.load(std::memory_order_seq_cst)==1.9f);
    SetEvent(fixture_continue_begin);new_begin.join();CHECK(new_begin_result==1);
    CloseHandle(fixture_before_policy_reached);CloseHandle(fixture_continue_policy);
    CloseHandle(fixture_begin_display_reached);CloseHandle(fixture_continue_begin);
    fixture_before_policy_reached=nullptr;fixture_continue_policy=nullptr;fixture_begin_display_reached=nullptr;fixture_continue_begin=nullptr;
    CHECK(f.stats().head_distance==1.9f && f.stats().blend==0 && end_current()==1);
    pass("a callback queued before End cannot publish old diagnostics over a new reserved generation");

    f.begin();f.settle();setter_reached=CreateEventW(nullptr,TRUE,FALSE,nullptr);setter_continue=CreateEventW(nullptr,TRUE,FALSE,nullptr);
    std::thread writer([&]{f.sample();});CHECK(WaitForSingleObject(setter_reached,1000)==WAIT_OBJECT_0);
    std::atomic<bool> finished{false};std::thread ending([&]{CHECK(end_current()==1);finished.store(true);});
    Sleep(20);CHECK(!finished.load());SetEvent(setter_continue);writer.join();ending.join();
    CloseHandle(setter_reached);CloseHandle(setter_continue);setter_reached=nullptr;setter_continue=nullptr;
    pass("End drains the actual adjusted native setter before restoring dispatch");

    const uint64_t fps=allocate(0x1000),fps_world=allocate(63*64),fps_hashes=allocate(63*4),fps_links=allocate(63*4);
    put<uint64_t>(f.units+5*8,fps);put<uint8_t>(f.generations+5,1);put<uint32_t>(f.c.avatar_owner+0x53e9c0,0x400005);
    put<uint32_t>(fps+0x70,63);put<uint64_t>(fps+0x88,fps_world);put<uint64_t>(fps+0xA0,fps_hashes);put<uint64_t>(fps+0x98,fps_links);
    put<uint32_t>(fps_hashes+50*4,0x60ED8C39);put<uint32_t>(fps_links+50*4,0x40001);
    const float world_identity[16]{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};
    FreeAim::Q native_q{};
    // The old optional render-only features must never affect a native6 frame.
    f.normal();f.begin();f.top(6);put<uint64_t>(f.camera_object+0x1D0,fps);
    put<uint64_t>(f.camera_object+0x78,fps_world);put<uint64_t>(f.camera_object+0x98,f.links);put<uint32_t>(f.links,0x00320002);
    put(fps_world+50*64,world_identity);put<uint32_t>(f.c.avatar_owner+0x53e9c0,0x400005);
    CHECK(NADSC_FreeAim(active_generation,1000)==0 && NADSC_Error()==INVALID_CONFIG);
    CHECK(NADSC_SetKick46(active_generation,1)==0 && NADSC_Error()==INVALID_CONFIG);
    CHECK(NADSC_SetCameraMotion47(active_generation,.01f,0,0,0,0,0)==0 && NADSC_Error()==INVALID_CONFIG);
    CHECK(NADSC_FreeAim(active_generation,0)==1 && NADSC_SetKick46(active_generation,0)==1);
    CHECK(NADSC_SetCameraMotion47(active_generation,0,0,0,0,0,0)==1);
    pass("legacy render-only activation rejects honestly while zero cleanup remains ABI compatible");
    // Set directly to prove even already-active legacy requests cannot mutate.
    policy.presentation_enabled=true;policy.free_until=fixture_time+3000;policy.kick_enabled=true;
    for(unsigned a=0;a<6;++a)policy.motion[a]=.02f;
    float native_frame[20]{.12f,.04f,1.38f};native_frame[3]=-.0f;
    native_q=FreeAim::look(2.4f,-.8f);std::memcpy(native_frame+16,&native_q,16);
    uint8_t frame_copy[80]{};std::memcpy(frame_copy,native_frame,80);
    for(bool ads:{false,true}) {
        f.controls(0,ads);fixture_time+=16;f.invoke(reinterpret_cast<void*>(f.c.camera),f.c.camera_unit,native_frame);
        CHECK(records[calls-1].input==native_frame && std::memcmp(frame_copy,native_frame,80)==0);
        CHECK(std::memcmp(records[calls-1].bits,native_frame,16)==0 && policy.free_applied==0 && policy.kick_frames==0);
    }
    pass("native6 hip and full ADS position quaternion padding remain exact despite active legacy motion free-aim and kick requests");
    put<uint64_t>(f.camera_object+0x1D0,0x1234);f.controls(0,true);fixture_time+=16;
    f.invoke(reinterpret_cast<void*>(f.c.camera),f.c.camera_unit,native_frame);
    CHECK(records[calls-1].input==native_frame && std::memcmp(frame_copy,native_frame,80)==0 && !policy.correction.active);
    pass("unavailable optional FPS parent history never changes or blocks exact native6 ADS");
    CHECK(end_current()==1);

    // Rebuild the qualified parent and use the actual native6->4 callback path.
    f.normal();f.begin();f.top(6);put<uint64_t>(f.camera_object+0x1D0,fps);
    put<uint64_t>(f.camera_object+0x78,fps_world);put(fps_world+50*64,world_identity);
    policy.presentation_enabled=true;std::memcpy(native_frame,frame_copy,80);
    fixture_time+=16;f.invoke(reinterpret_cast<void*>(f.c.camera),f.c.camera_unit,native_frame);
    CHECK(records[calls-1].input==native_frame);
    f.top(4);put<uint64_t>(f.camera_object+0x1D0,0);f.sample();
    CHECK(policy.correction.active && approximately(last(0),native_frame[0]) && approximately(last(1),native_frame[1]) && approximately(last(2),native_frame[2]));
    // A late normal4 origin jump must not contaminate the eye correction.
    f.input[0]=-3;f.input[1]=.6f;f.input[2]=.7f;f.body(10,20,3);f.body_yaw(1.5707963268f);
    f.input[0]+=10;f.input[1]+=20;f.input[2]+=3;f.sample(75);
    CHECK(policy.correction.active && approximately(last(0),9.98f) && approximately(last(1),20.15f) && approximately(last(2),4.46f));
    // Caller quaternion follows its fresh native recoil/look without filtering.
    native_q=FreeAim::look(-1.1f,.7f);std::memcpy(native_frame+16,&native_q,16);
    std::memcpy(native_frame,f.input,16);fixture_time+=75;
    f.invoke(reinterpret_cast<void*>(f.c.camera),f.c.camera_unit,native_frame);
    CHECK(!policy.correction.active && std::memcmp(native_frame+16,&native_q,16)==0);
    CHECK(approximately(last(0),10) && approximately(last(1),20.18f) && approximately(last(2),4.54f));
    pass("ADS exit corrects only eye-relative displacement; fresh body travel rotation native recoil and late normal4 origins stay authoritative");
    CHECK(end_current()==1);


    // Matrix-space mapping is checked against an independent rotated parent.
    f.normal();f.begin();f.top(6);put<uint64_t>(f.camera_object+0x1D0,fps);
    put<uint64_t>(f.camera_object+0x78,fps_world);policy.presentation_enabled=true;
    native_frame[0]=.12f;native_frame[1]=.04f;native_frame[2]=1.38f;
    const float turned_parent[16]{0,1,0,0,-1,0,0,0,0,0,1,0,.1f,.3f,.1f,1};
    put(fps_world+50*64,turned_parent);fixture_time+=16;f.invoke(reinterpret_cast<void*>(f.c.camera),f.c.camera_unit,native_frame);
    f.top(4);put<uint64_t>(f.camera_object+0x1D0,0);f.sample();
    CHECK(policy.correction.active && approximately(last(0),.06f) && approximately(last(1),.42f) && approximately(last(2),1.48f));
    CHECK(end_current()==1);pass("current FPS matrix basis maps native local position independently of stale camera world and native quaternion");

    for(unsigned fps_rate:{30u,60u,144u,240u}) {
        f.normal();f.begin();f.top(6);put<uint64_t>(f.camera_object+0x1D0,fps);
        put<uint64_t>(f.camera_object+0x78,fps_world);put(fps_world+50*64,world_identity);
        policy.presentation_enabled=true;native_frame[0]=.12f;native_frame[1]=.04f;native_frame[2]=1.38f;
        fixture_time+=.125;f.invoke(reinterpret_cast<void*>(f.c.camera),f.c.camera_unit,native_frame);
        f.top(4);put<uint64_t>(f.camera_object+0x1D0,0);f.sample(.125);const double started=fixture_time;
        CHECK(policy.correction.active && approximately(last(0),.12f));
        const double frame_ms=1000.0/fps_rate;
        f.sample(frame_ms);CHECK(policy.correction.progress>0 && std::fabs(policy.correction.progress-frame_ms/150)<1e-5);
        for(unsigned frame=2;frame*frame_ms<150;++frame)f.sample(frame_ms);
        f.sample(150.001-(fixture_time-started));
        CHECK(!policy.correction.active && approximately(last(0),0) && approximately(last(1),.18f) && approximately(last(2),1.54f));
        CHECK(NADSC_SetOffsets(active_generation,.1f,.18f,.08f)==1);const float previous_x=last(0);f.sample(.125);
        CHECK(policy.correction.active && approximately(last(0),previous_x));f.sample(150);
        CHECK(!policy.correction.active && approximately(last(0),.1f) && approximately(last(2),1.58f));
        CHECK(end_current()==1);
    }
    pass("production callback uses fractional30 60 144 240Hz phase and finite offset handoff without timer quantization");

    for(unsigned mutation=0;mutation<7;++mutation) {
        f.normal();f.begin();f.top(6);put<uint64_t>(f.camera_object+0x1D0,fps);
        put<uint64_t>(f.camera_object+0x78,fps_world);put(fps_world+50*64,world_identity);policy.presentation_enabled=true;
        uint64_t at=mutation==0?f.generations+5:mutation==1?f.request+8:mutation==2?f.request:mutation==3?fps_hashes+50*4
            :mutation==4?f.camera_object+0x1D0:mutation==5?f.generations+3:f.controller+4;
        uint32_t saved=0;CHECK(value(at,saved));fixture_before_history_mutation=at;fixture_before_history_value=saved+1;
        fixture_time+=16;f.invoke(reinterpret_cast<void*>(f.c.camera),f.c.camera_unit,native_frame);
        CHECK(fixture_before_history_mutation==0 && records[calls-1].input==native_frame);put<uint32_t>(at,saved);
        if(mutation==5) {CHECK(!armed.load() && NADSC_Error()==OWNER_MISMATCH);CHECK(end_current()==1);continue;}
        f.top(4);put<uint64_t>(f.camera_object+0x1D0,0);f.sample();
        CHECK(!policy.correction.active && approximately(last(0),0) && approximately(last(2),1.54f));
        CHECK(end_current()==1);
    }
    pass("late native history owner weapon request parent generation hash and ADS changes retire mixed-epoch history while native6 remains exact");
    // New mutable checks occur after sampling, directly before fallback use.
    for(unsigned mode=0;mode<6;++mode) {
        f.begin();f.settle();const auto replaced_before=replaced.load();uint64_t at=0;uint32_t original_value=0;
        if(mode==0){at=f.generations+3;original_value=1;fixture_before_commit_value=2;}
        if(mode==1){at=f.request+4;original_value=f.c.avatar;fixture_before_commit_value=f.c.avatar+1;}
        if(mode==2){at=f.hashes+90*4;original_value=0x8C5570C9;fixture_before_commit_value=0;}
        if(mode==3){at=f.camera_object+0x1D0;original_value=0;fixture_before_commit_value=0x1234;}
        if(mode==4){at=f.controller;original_value=0;fixture_before_commit_value=1;}
        if(mode==5){at=f.anim_current+13*8;original_value=static_cast<uint32_t>(f.anim_definition+0x1000+36*16);fixture_before_commit_value=static_cast<uint32_t>(f.anim_definition+0x1000+103*16);}
        CHECK(value(at,original_value));fixture_before_commit_mutation=at;f.sample();
        CHECK(records[calls-1].input==f.input && replaced.load()==replaced_before && NADSC_Error()==OWNER_MISMATCH);
        put<uint32_t>(at,original_value);CHECK(end_current()==1);
    }
    pass("late generation request graph parent controller and native action-state changes cannot commit a sampled fallback");

    for(uint32_t kind:{4u,6u})for(uint64_t field:{0x88ULL,0x98ULL,0xA0ULL}) {
        f.begin();f.top(kind);uint32_t original_header=0;const uint64_t at=f.registry+field;CHECK(value(at,original_header));
        fixture_registry_close_mutation=at;fixture_registry_close_value=original_header+1;f.sample();
        CHECK(fixture_registry_close_mutation==0 && records[calls-1].input==f.input && !armed.load() && NADSC_Error()==OWNER_MISMATCH);
        put<uint32_t>(at,original_header);CHECK(end_current()==1);
    }
    pass("batched registry capacity and table headers close after both generation-object proofs before admission");

    f.begin();f.settle();
    fixture_before_policy_reached=CreateEventW(nullptr,TRUE,FALSE,nullptr);fixture_continue_policy=CreateEventW(nullptr,TRUE,FALSE,nullptr);
    std::thread old_callback([&]{f.sample();});CHECK(WaitForSingleObject(fixture_before_policy_reached,1000)==WAIT_OBJECT_0);
    const auto old_generation=active_generation;CHECK(end_current()==1);f.normal();f.body(0,0,0,1.8f);CHECK(begin_current(&f.c)==1);
    CHECK(active_generation!=old_generation && armed.load());const auto new_display_sequence=display_sequence.load();
    const auto new_replaced=replaced.load();SetEvent(fixture_continue_policy);old_callback.join();
    CHECK(records[calls-1].input==f.input && replaced.load()==new_replaced && display_sequence.load()==new_display_sequence);
    CloseHandle(fixture_before_policy_reached);CloseHandle(fixture_continue_policy);fixture_before_policy_reached=nullptr;fixture_continue_policy=nullptr;
    CHECK(end_current()==1);
    pass("callback queued under retired generation forwards unchanged after same-identity replacement fully arms");
    std::printf("Native camera fixture PASS: %llu cases\n",static_cast<unsigned long long>(cases));return 0;
}

