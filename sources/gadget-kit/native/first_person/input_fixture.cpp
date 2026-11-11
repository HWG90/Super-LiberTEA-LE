// Entirely synthetic allocations and local callbacks. No game process.
#define main legacy_editor_main
#include "editor_fixture.cpp"
#undef main
#include <chrono>
static const char* CAPTURE_DIR="Z:/home/goose/Projects/Linux HD2 Mods/builds/26568081/mods/gadget-kit/capture-links/";
static void captured_pins(Fixture& f) {
    for(const auto& pin:INPUT_PINS) {
        const char* configured=std::getenv("TFP_INPUT_CAPTURE_DIR");const char* directory=configured?configured:CAPTURE_DIR;
        const size_t directory_length=std::strlen(directory);const bool separator=directory_length&&(directory[directory_length-1]=='/'||directory[directory_length-1]=='\\');
        char path[1024];std::snprintf(path,sizeof path,"%s%s%s",directory,separator?"":"/",pin.exe?"helldivers2-6af2d5e6-140000000.bin":"game-6af322c1-180000000.bin");
        FILE* file=std::fopen(path,"rb");CHECK(file);CHECK(std::fseek(file,pin.offset,SEEK_SET)==0);
        CHECK(std::fread(reinterpret_cast<void*>((pin.exe?f.c.exe:f.c.game)+pin.offset),1,pin.length,file)==pin.length);std::fclose(file);
    }
    put<uint32_t>(f.c.game+0x22465c4,0x3f800000);put<uint32_t>(f.c.game+0x2247894,0xbf800000);
    put<uint32_t>(f.c.game+0x2246fb0,0x42652ee0);put<uint32_t>(f.c.game+0x22478c8,0xbfc90fdb);put<uint32_t>(f.c.game+0x2246774,0x3fc90fdb);put<uint32_t>(f.c.game+0x2247ab0,0xc2960000);put<uint64_t>(f.c.game+0x2246900,0x3ff0000000000000ULL);
}
static double test_exp(double x){return std::exp(x);}
struct InputFixture {
    Fixture f;uint64_t frame=0,input=0,settings=0,time=0,player=0,buckets=0;uint64_t token=0;
    uint32_t original=3;uint8_t native_preset[144]{};
    InputFixture() {
        captured_pins(f);f.c.duration_ms=0;f.c.offset_x=f.c.offset_y=f.c.offset_z=0;
        put<uint64_t>(f.api+0x90,reinterpret_cast<uint64_t>(synthetic_getter));
        frame=allocate(0x1000);input=allocate(0xa8000);settings=allocate(0xad000);time=allocate(0x1000);player=allocate(0x1000);buckets=allocate(0x1000);
        put<uint64_t>(f.c.game+0x2e38250,input);put<uint64_t>(f.c.game+0x2ce1508,settings);
        put<uint64_t>(f.c.game+0x2ce14f8,time);put<uint64_t>(f.c.game+0x2ce1618,player);
        put<uint32_t>(f.c.game+0x2e3f0e4,f.c.avatar);put<uint32_t>(f.c.game+0x2e3fcb8,UINT32_MAX);
        put<uint64_t>(f.c.avatar_owner+0xf8,buckets);put<uint32_t>(f.c.avatar_owner+0x100,8);
        put<uint32_t>(f.c.avatar_owner+0x104,UINT32_MAX);put<uint32_t>(f.c.avatar_owner+0x108,1);
        for(unsigned i=0;i<8;++i)put<uint64_t>(buckets+i*8,UINT64_MAX);
        put<uint64_t>(buckets+(f.c.avatar&7)*8,static_cast<uint64_t>(f.c.avatar));
        put<uint32_t>(input+0x324,0);put<float>(input+0xa7b50,1.25f);put<float>(input+0xa7b44,.75f);
        put<float>(settings+0xac488,90);put<float>(time,1.0f/60);
        for(unsigned i=0;i<144;++i)native_preset[i]=static_cast<uint8_t>(i*7+1);
        const float gains[2]={.3f,.4f};std::memcpy(native_preset+4,gains,sizeof gains);
        put<uint32_t>(reinterpret_cast<uint64_t>(native_preset)+0x8c,0x76543210);
        std::memcpy(reinterpret_cast<void*>(f.c.game+0x2cb2140+original*144),native_preset,144);
        fixture_input_exp=test_exp;fixture_now=100;
    }
    void begin(){f.normal();CHECK(NADSE_ValidateInput(&f.c)==1);CHECK(NADSE_BeginSteadyInput(&f.c,&token)==1);CHECK(token);f.fpv();reset();}
    void reset(float dt=1.0f/60) {
        put<uint64_t>(frame+0x80,f.c.context);put<uint64_t>(frame+0x48,f.c.avatar_index);put<float>(frame+0xa0,dt);
        put<uint32_t>(f.c.request+0x80,original);put<float>(f.c.request+0x84,.5235987901687622f);put<uint8_t>(f.c.request+0x8c,0);
        const float raw[3]={.2f,-.1f,.3f},history[3]={.07f,-.02f,.13f};
        std::memcpy(reinterpret_cast<void*>(f.c.avatar_owner+0xa7c24),raw,12);std::memcpy(reinterpret_cast<void*>(f.c.request+0x3c),history,12);
    }
    const float* before(uint64_t S=0,uint64_t req=0,uint64_t caller=0) {
        return NADSE_Input90Call(f.c.weapon_unit,0,req?req:f.c.request,S?S:frame,caller?caller:f.c.game+0x111863e);
    }
    void native_history(){CHECK(input_state.pending.ready);std::memcpy(reinterpret_cast<void*>(f.c.request+0x3c),input_state.pending.expected_history,12);}
    void after(uint64_t S=0,uint64_t req=0){CHECK(NADSE_Input00Call(f.c.viewmodel,50,req?req:f.c.request,S?S:frame,f.c.game+0x1119a84)==getter_result);}
    uint32_t index(){uint32_t result=0;CHECK(value(f.c.request+0x80,result));return result;}
    void end(){CHECK(NADSE_End(token)==1);}
};
extern "C" const float* InputFixtureNativeCycle(uint64_t,uint64_t,uint64_t,uint64_t,uint32_t,float);
extern "C" void InputFixtureAfter90();
extern "C" void InputFixtureAfter00();
extern "C" void InputFixtureNativeBetween(uint64_t request,uint64_t S,const float* result) {
    CHECK(result==getter_result&&input_state.pending.ready&&input_state.pending.request==request&&input_state.pending.native_stack==S);
    uint32_t index=0;CHECK(value(request+0x80,index)&&index==input_state.pending.index);
    std::memcpy(reinterpret_cast<void*>(request+0x3c),input_state.pending.expected_history,12);
}
static void continuation(uint64_t at,void (*target)()) {
    literal(at,"49bb");put<uint64_t>(at+2,reinterpret_cast<uint64_t>(target));literal(at+10,"41ffe3");
}
int main(int argc,char** argv){
    if(argc==2&&std::strcmp(argv[1],"--unmap")==0){
        InputFixture isolated;isolated.begin();isolated.before();isolated.native_history();fixture_input_fault_after_query=3;
        CHECK(NADSE_End(isolated.token)==0&&NADSE_Error()==CLEANUP_PENDING&&input_state.pending.ready&&input_possible&&reserved.load());
        CHECK(input_clones[input_state.pending.clone].quarantined);
        std::puts("PASS input actual request unmap after successful writable query is caught and remains pending until process exit");return 0;
    }
    CHECK(legacy_editor_main()==0);
    {const uint64_t atomic_page=allocate(0x1000);put<uint32_t>(atomic_page,77);uint32_t observed=0;
    CHECK(NADSE_InputCompareExchange(atomic_page,77,88,&observed)==1&&observed==77);
    CHECK(NADSE_InputCompareExchange(atomic_page,77,99,&observed)==1&&observed==88);
    DWORD atomic_protection=0;CHECK(VirtualProtect(reinterpret_cast<void*>(atomic_page),0x1000,PAGE_READONLY,&atomic_protection));
    observed=0xdeadbeef;CHECK(NADSE_InputCompareExchange(atomic_page,88,99,&observed)==0&&observed==0xdeadbeef);
    CHECK(VirtualProtect(reinterpret_cast<void*>(atomic_page),0x1000,PAGE_NOACCESS,&atomic_protection));
    CHECK(NADSE_InputCompareExchange(atomic_page,88,99,&observed)==0&&observed==0xdeadbeef);
    CHECK(VirtualFree(reinterpret_cast<void*>(atomic_page),0,MEM_RELEASE));
    CHECK(NADSE_InputCompareExchange(atomic_page,88,99,&observed)==0&&observed==0xdeadbeef);
    pass("input static SEH leaf preserves CAS expected observed semantics and catches readonly noaccess and unmapped faults without writing output");}
    InputFixture x;
    x.begin();CHECK(input_mode&&input_possible);CHECK(x.before()==getter_result);CHECK(input_state.pending.ready&&x.index()!=x.original);
    const auto selected=input_state.pending.clone;const auto& clone=input_clones[selected];
    CHECK(clone.address==x.f.c.game+0x2cb2140+static_cast<uint64_t>(clone.index)*144);
    for(unsigned i=0;i<144;++i)if(i<4||i>=12)CHECK(reinterpret_cast<uint8_t*>(clone.address)[i]==x.native_preset[i]);
    CHECK(std::memcmp(reinterpret_cast<void*>(x.f.c.game+0x2cb2140+x.original*144),x.native_preset,144)==0);
    x.native_history();x.after();CHECK(x.index()==x.original&&!input_state.pending.ready&&input_state.stats.normalized==1);x.end();pass("input private selector preserves full template, source and original getter pointer");
    x.begin();x.before();x.native_history();CHECK(NADSE_End(x.token)==0&&NADSE_Error()==CLEANUP_PENDING);CHECK(reserved.load()&&input_possible&&x.index()==x.original);
    x.after();CHECK(!input_state.pending.ready);x.end();pass("input End retains all callbacks and lease until matching completion after disarm");
    x.begin();x.before();x.native_history();x.after(x.frame+0x100);CHECK(input_state.pending.ready);x.after(0,x.f.c.request+0xe8);CHECK(input_state.pending.ready);
    x.after();x.end();pass("input completion rejects wrong frame and actual R15 request");
    x.begin();x.before();x.native_history();put<uint32_t>(x.f.c.request+0x80,42);x.after();CHECK(x.index()==42&&!input_state.pending.ready);x.end();pass("input foreign selector wins exact CAS cleanup");
    x.begin();put<float>(x.f.c.avatar_owner+0x53e9ac,.01f);x.before();put<float>(x.f.c.request+0x3c,99);x.after();CHECK(x.index()==x.original&&input_state.failed_closed&&!input_state.stats.active);
    x.reset();x.before();CHECK(!input_state.pending.ready);put<float>(x.f.c.avatar_owner+0x53e9ac,0);x.end();pass("input observed history race disables only input-dependent policy until fresh generation");
    x.begin();x.before();CHECK(!input_state.pending.input_dependent);put<float>(x.f.c.request+0x3c,99);x.after();CHECK(x.index()==x.original&&!input_state.failed_closed&&input_state.stats.active);x.end();pass("input S0 inverse gain remains valid after changed raw history without disabling native policy");
    x.begin();put<uint8_t>(x.f.c.context+0x1a9,1);x.before();CHECK(!input_state.pending.ready&&x.index()==x.original);put<uint8_t>(x.f.c.context+0x1a9,0);x.end();pass("input inhibited native context is unsupported without writes");
    x.begin();fixture_input_fail_read=true;x.before();CHECK(!input_state.pending.ready&&x.index()==x.original);fixture_input_fail_read=false;x.end();pass("input read failure never publishes a selector");
    x.begin();put<uint32_t>(x.f.c.request+0x84,0x7fc00001);x.before();CHECK(!input_state.pending.ready&&x.index()==x.original);put<float>(x.f.c.request+0x84,.5235987901687622f);x.end();pass("input unsupported nonfinite lens forwards unchanged");
    x.begin();for(float dt:{0.0f,1.0f/30,1.0f/60,1.0f/144,1.0f/240}){
        x.reset(dt);x.before();CHECK(input_state.pending.ready);x.native_history();x.after();CHECK(x.index()==x.original);
    }x.end();pass("input dt0 direct ADS and 30 60 144 240Hz use matched native lifecycle");
    x.begin();x.before();x.native_history();const uint64_t outer=x.frame;const uint64_t inner=x.frame+0x200;
    x.before(inner);CHECK(x.index()==x.original&&input_state.pending.ready);x.after(inner);CHECK(input_state.pending.ready);x.after(outer);CHECK(!input_state.pending.ready);x.end();pass("input reentry aborts private selector before nested evaluation and drains only outer frame");
    x.begin();x.before();x.native_history();put<uint32_t>(x.f.c.weapon_descriptor+8,0x999);x.after();CHECK(x.index()==x.original&&!input_state.pending.ready);
    put<uint32_t>(x.f.c.weapon_descriptor+8,x.f.c.weapon);x.end();pass("input cleanup survives equipped weapon change while old row remains live");
    x.begin();x.before();x.native_history();x.after();x.reset();
    // These are private fake-image caller blocks, never game code patches.
    literal(x.f.c.game+0x111863c,"ffd0");continuation(x.f.c.game+0x111863e,InputFixtureAfter90);
    literal(x.f.c.game+0x1119a81,"41ffd0");continuation(x.f.c.game+0x1119a84,InputFixtureAfter00);
    CHECK(FlushInstructionCache(GetCurrentProcess(),reinterpret_cast<void*>(x.f.c.game+0x111863c),0x1500));
    CHECK(InputFixtureNativeCycle(x.f.c.request,x.f.c.context,x.f.c.game,x.f.api,x.f.c.viewmodel,1.0f/60)==getter_result);
    CHECK(!input_state.pending.ready&&x.index()==x.original);x.end();captured_pins(x.f);pass("input actual published Win64 thunks capture R15 and same native S through positive matching90 and00 calls");
    x.begin();const auto reads=fixture_reads;const auto observed=input_state.stats.observed;
    for(unsigned i=0;i<1000;++i){CHECK(NADSE_Input90Thunk(x.f.c.weapon_unit,0)==getter_result);CHECK(NADSE_Input00Thunk(x.f.c.viewmodel,50)==getter_result);}
    CHECK(fixture_reads==reads&&input_state.stats.observed==observed);x.end();pass("input actual static thunks perform zero RPM and no policy counters for unrelated callers");
    x.begin();x.before();x.native_history();armed.store(0);active_generation.store(0);
    x.before(x.frame+0x200);CHECK(x.index()==x.original&&input_state.pending.ready);x.after();x.end();pass("input pending-generation reentry restores private index even after End disarms admission");
    x.begin();getter_reached=CreateEventW(nullptr,TRUE,FALSE,nullptr);getter_continue=CreateEventW(nullptr,TRUE,FALSE,nullptr);
    std::thread stale([&](){CHECK(x.before()==getter_result);});CHECK(WaitForSingleObject(getter_reached,5000)==WAIT_OBJECT_0);
    const uint64_t old_token=x.token;x.end();x.begin();CHECK(x.token!=old_token);SetEvent(getter_continue);stale.join();
    CloseHandle(getter_reached);CloseHandle(getter_continue);getter_reached=getter_continue=nullptr;
    CHECK(!input_state.pending.ready&&x.index()==x.original);x.end();pass("input old blocked original90 cannot publish into a fully rearmed replacement generation");
    x.begin();x.before();x.native_history();x.after();
    uint64_t total_reads=0,total_bytes=0;LARGE_INTEGER frequency{},start{},finish{};CHECK(QueryPerformanceFrequency(&frequency));QueryPerformanceCounter(&start);
    for(unsigned i=0;i<200;++i){x.reset();const auto r=fixture_reads,b=fixture_read_bytes;x.before();x.native_history();x.after();total_reads+=fixture_reads-r;total_bytes+=fixture_read_bytes-b;}
    QueryPerformanceCounter(&finish);std::printf("METRIC eligible_eval reads=%.2f bytes=%.2f mean_us=%.3f synthetic_only\n",total_reads/200.0,total_bytes/200.0,1e6*(finish.QuadPart-start.QuadPart)/frequency.QuadPart/200.0);x.end();
    auto benchmark=[&](Getter fn){LARGE_INTEGER a{},b{};QueryPerformanceCounter(&a);for(unsigned i=0;i<200000;++i)CHECK(fn(x.f.c.weapon_unit,0)==getter_result);QueryPerformanceCounter(&b);return 1e9*(b.QuadPart-a.QuadPart)/frequency.QuadPart/200000.0;};
    x.begin();std::printf("METRIC unrelated_getter original_ns=%.3f legacy00_ns=%.3f input90_thunk_ns=%.3f input00_thunk_ns=%.3f synthetic_only\n",benchmark(synthetic_getter),benchmark(position_getter_hook),benchmark(NADSE_Input90Thunk),benchmark(NADSE_Input00Thunk));x.end();pass("input synthetic RPM byte and actual thunk overhead metrics recorded");
    x.f.normal();x.f.c.duration_ms=10;fixture_now=1000;CHECK(NADSE_BeginInput(&x.f.c,&x.token)==1);x.f.fpv();x.reset();
    fixture_now=1009;x.before();CHECK(input_state.pending.ready);x.native_history();x.after();const auto normalized_before=input_state.stats.normalized;
    x.reset();fixture_now=1010;x.before();CHECK(!input_state.pending.ready&&x.index()==x.original&&input_state.stats.normalized==normalized_before);x.end();x.f.c.duration_ms=0;
    pass("input timed lease refuses new selector admission exactly at deadline");
    x.f.normal();DWORD old_protection=0;CHECK(VirtualProtect(reinterpret_cast<void*>(x.f.c.game+0x1118000),0x1000,PAGE_NOACCESS,&old_protection));
    CHECK(NADSE_BeginInput(&x.f.c,&x.token)==1&&input_mode);x.f.fpv();x.reset();x.before();CHECK(!input_state.code_ok&&x.index()==x.original&&armed.load());
    DWORD ignored_protection=0;CHECK(VirtualProtect(reinterpret_cast<void*>(x.f.c.game+0x1118000),0x1000,old_protection,&ignored_protection));fixture_now+=250;
    x.after();CHECK(input_state.code_ok);x.before();CHECK(input_state.pending.ready);x.native_history();x.after();x.end();pass("input cold early native callsite installs guarded forward-only SDK hook then activates after warm without F11 restart");
    x.begin();x.before();x.native_history();DWORD blocked_protection=0;
    CHECK(VirtualProtect(reinterpret_cast<void*>(x.f.c.context),0x1000,PAGE_NOACCESS,&blocked_protection));
    CHECK(NADSE_End(x.token)==0&&NADSE_Error()==CLEANUP_PENDING&&reserved.load()&&input_possible);
    DWORD restored_protection=0;CHECK(VirtualProtect(reinterpret_cast<void*>(x.f.c.context),0x1000,blocked_protection,&restored_protection));
    x.after();CHECK(x.index()==x.original&&!input_state.pending.ready);x.end();pass("input actual unreadable request defers End without unpatching callbacks until readable matched completion");
    x.begin();x.before();x.native_history();fixture_input_fault_after_query=true;
    CHECK(NADSE_End(x.token)==0&&NADSE_Error()==CLEANUP_PENDING&&input_state.pending.ready);
    CHECK(VirtualProtect(reinterpret_cast<void*>(x.f.c.context),0x1000,PAGE_READWRITE,&restored_protection));x.after();x.end();
    pass("input explicit static SEH recovers a real CAS access violation after successful writable query without losing ownership");
    x.begin();x.before();x.native_history();CHECK(VirtualProtect(reinterpret_cast<void*>(x.f.c.context),0x1000,PAGE_READONLY,&blocked_protection));
    CHECK(NADSE_End(x.token)==0&&NADSE_Error()==CLEANUP_PENDING&&input_state.pending.ready);
    CHECK(VirtualProtect(reinterpret_cast<void*>(x.f.c.context),0x1000,blocked_protection,&restored_protection));x.after();x.end();pass("input actual compare-exchange write fault retains pending ownership and later completes safely");
    x.begin();x.before();x.native_history();const auto no_normalization=input_state.stats.normalized;
    std::thread nested([&](){CHECK(x.before(x.frame+0x200)==getter_result);});nested.join();CHECK(x.index()==x.original&&input_state.pending.ready);
    x.after();CHECK(!input_state.pending.ready&&input_state.stats.normalized==no_normalization);x.end();pass("input independent-thread evaluation aborts private selector and cannot be counted as normalized");
    x.begin();const float zero_axes[3]{};std::memcpy(reinterpret_cast<void*>(x.f.c.avatar_owner+0xa7c24),zero_axes,12);std::memcpy(reinterpret_cast<void*>(x.f.c.request+0x3c),zero_axes,12);
    x.before();CHECK(input_state.pending.ready&&!input_state.pending.input_dependent);const auto idle_gain=input_state.stats.yaw_gain;x.native_history();x.after();
    x.reset();x.before();CHECK(input_state.pending.ready&&std::memcmp(&idle_gain,&input_state.stats.yaw_gain,4)==0);x.native_history();x.after();x.end();pass("input S0 idle frame publishes the same inverse gain as subsequent moving input");
    x.f.normal();fixture_foreign_cas_at=fixture_cas_calls+5;fixture_foreign_value=reinterpret_cast<uint64_t>(synthetic_position);
    CHECK(NADSE_BeginInput(&x.f.c,&x.token)==0&&!reserved.load()&&x.token==0);fixture_foreign_cas_at=0;
    uint64_t foreign90=0;CHECK(value(x.f.api+0x90,foreign90)&&foreign90==reinterpret_cast<uint64_t>(synthetic_position));put<uint64_t>(x.f.api+0x90,reinterpret_cast<uint64_t>(synthetic_getter));
    pass("input fifth-slot foreign CAS winner is preserved while earlier hooks roll back");
    // Optional startup must not depend on demand-paged evaluator tails.
    x.f.normal();uint8_t old=0;CHECK(value(x.f.c.game+0x1118b00,old));put<uint8_t>(x.f.c.game+0x1118b00,old^1);
    CHECK(NADSE_BeginInput(&x.f.c,&x.token)==1);x.f.fpv();x.reset();x.before();CHECK(!input_state.code_ok&&!input_state.pending.ready&&armed.load());
    put<uint8_t>(x.f.c.game+0x1118b00,old);fixture_now+=250;x.after();CHECK(input_state.code_ok);x.before();CHECK(input_state.pending.ready);x.native_history();x.after();x.end();pass("input lazy full fingerprint blocks unknown code without preventing pose startup and later activates");
    x.f.normal();put<uint64_t>(x.f.api+0x90,reinterpret_cast<uint64_t>(synthetic_position));
    CHECK(NADSE_BeginInput(&x.f.c,&x.token)==1);CHECK(!input_mode&&!input_possible&&input_state.stats.reason==INPUT_SDK_UNAVAILABLE);CHECK(NADSE_End(x.token)==1);
    put<uint64_t>(x.f.api+0x90,reinterpret_cast<uint64_t>(synthetic_getter));pass("input foreign SDK90 leaves ordinary four-slot pose available");
    x.f.normal();fixture_cas_fail_at=fixture_cas_calls+5;
    CHECK(NADSE_BeginInput(&x.f.c,&x.token)==0&&x.token==0&&!reserved.load());fixture_cas_fail_at=0;
    for(unsigned i=0;i<4;++i){uint64_t current=0;CHECK(value(x.f.api+API_OFFSETS[i],current)&&current==reinterpret_cast<uint64_t>(fixture_targets[i]));}
    pass("input fifth-slot CAS fault rolls all four pose callbacks back cleanly");
    x.begin();x.before();x.native_history();const uint64_t old_camera=policy.camera;put<uint64_t>(x.f.c.context,allocate(0x1000));
    x.after();CHECK(x.index()==x.original&&!input_state.pending.ready);put<uint64_t>(x.f.c.context,old_camera);x.end();pass("input completion restores exact-owned selector despite camera object replacement");
    x.begin();x.before();x.native_history();const uint64_t old_context=x.f.c.context;put<uint64_t>(x.f.c.game+0x2e287d0,allocate(0x3000));
    CHECK(NADSE_End(x.token)==0&&NADSE_Error()==CLEANUP_PENDING);x.after();CHECK(x.index()==x.original&&!input_state.pending.ready);CHECK(NADSE_End(x.token)==1);
    put<uint64_t>(x.f.c.game+0x2e287d0,old_context);pass("input exact native R15 and stack witness finishes cleanup after global context replacement");
    x.begin();x.before();const uint32_t private_index=x.index();const unsigned retired_clone=input_state.pending.clone;
    put<uint32_t>(x.f.c.context+0x1f8,2);put<uint32_t>(x.f.c.context+0x1fc,2);
    CHECK(NADSE_End(x.token)==0&&input_state.pending.ready&&input_clones[retired_clone].quarantined&&x.index()==private_index);
    x.native_history();x.after();CHECK(x.index()==x.original&&!input_state.pending.ready);x.end();
    x.f.normal();pass("input retired row remains pending and quarantined until actual matched native completion restores80");
    NADSE_InputStats stats{};stats.size=sizeof stats;stats.abi=1;CHECK(NADSE_ReadInputStats(0,&stats)==1);CHECK(stats.installed==0&&stats.active==0);CHECK(NADSE_ReadInputStats(x.token,&stats)==0&&NADSE_Error()==TOKEN_MISMATCH);pass("input optional ABI diagnostics reject stale handles");
    x.begin();x.before();x.native_history();const unsigned poisoned_clone=input_state.pending.clone;x.before(x.frame);
    CHECK(input_state.pending.ready&&input_state.pending.poisoned&&input_clones[poisoned_clone].quarantined&&x.index()==x.original);
    x.after();CHECK(input_state.pending.ready);CHECK(NADSE_End(x.token)==0&&NADSE_Error()==CLEANUP_PENDING&&reserved.load());
    pass("input reused identical frame after abnormal nonreturn is quarantined and never falsely acknowledged as drained");
    std::printf("Native input fixture PASS: %llu groups including legacy editor\n",static_cast<unsigned long long>(cases));return 0;
}
