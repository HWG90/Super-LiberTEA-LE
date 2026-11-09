// Private synthetic buffers and callbacks only. No game process or module.
#define NADSHF_FIXTURE
#include "native_held_fire_cas.cpp"
#include "native_held_fire.cpp"
#include <cstdio>
#include <cstdlib>
#define CHECK(x) do{if(!(x)){std::fprintf(stderr,"FAIL %d: %s error=%u\n",__LINE__,#x,NADSHF_Error());std::abort();}}while(0)
static uint64_t cases=0,calls=0;static uint32_t recorded_unit=0,recorded_hash=0;
static HANDLE entered=nullptr,continue_forward=nullptr;
__declspec(noinline) static void synthetic_event(uint32_t unit,uint32_t hash) {
    ++calls;recorded_unit=unit;recorded_hash=hash;
    if(entered){SetEvent(entered);CHECK(WaitForSingleObject(continue_forward,10000)==WAIT_OBJECT_0);}
}
__declspec(noinline) static void foreign_event(uint32_t,uint32_t){}
template<class T> static void put(uint64_t at,const T& v){std::memcpy(reinterpret_cast<void*>(at),&v,sizeof v);}
static uint64_t allocate(size_t n,DWORD protect=PAGE_READWRITE){void* p=VirtualAlloc(nullptr,n,MEM_COMMIT|MEM_RESERVE,protect);CHECK(p);return reinterpret_cast<uint64_t>(p);}
static void literal(uint64_t at,const char* h){auto d=[](char c)->uint8_t{return static_cast<uint8_t>(c<='9'?c-'0':c-'a'+10);};for(size_t i=0;i<std::strlen(h)/2;++i)put<uint8_t>(at+i,static_cast<uint8_t>(d(h[i*2])<<4|d(h[i*2+1])));}
static void fake_image(uint64_t at,uint32_t stamp,uint32_t length){IMAGE_DOS_HEADER d{};d.e_magic=IMAGE_DOS_SIGNATURE;d.e_lfanew=128;IMAGE_NT_HEADERS64 n{};n.Signature=IMAGE_NT_SIGNATURE;n.FileHeader.Machine=IMAGE_FILE_MACHINE_AMD64;n.FileHeader.TimeDateStamp=stamp;n.OptionalHeader.Magic=IMAGE_NT_OPTIONAL_HDR64_MAGIC;n.OptionalHeader.SizeOfImage=length;put(at,d);put(at+128,n);}
static void pass(const char* name){++cases;std::printf("PASS %s\n",name);}
struct Fixture {
    NADSHF_Config c{};uint64_t token=0,controller=0,descriptor=0,root=0,active=0,table=0;Event invoke[3]{};
    Fixture(){
        c.size=sizeof c;c.abi=1;c.ttl_ms=250;c.game=allocate(0x3382000,PAGE_EXECUTE_READWRITE);c.exe=allocate(0x29fe000);
        fake_image(c.game,0x6ae0e5ff,0x3382000);fake_image(c.exe,0x6ae0964a,0x29fe000);
        literal(c.exe+EVENT_RVA,"48895c2408574883ec208bda8bf9e88d8feaff448bc38bd7488b4818488b5c24304883c4205fe99547f3ff");
        literal(c.exe+0x12bf35,"b801000000f00fc186380017008bc0486bc858c784318800010003000000899c313800010089ac313c000100");
        literal(c.game+0x83c37f,"4e85a433807854000f84a6000000488b0534514a02bae3c5d96b8bcf4c8b401841ff9070030000");
        literal(c.game+0x83c782,"4a8b843380785400480fbae0260f83ac0000004380bc37d16a5400000f85d8000000480fbae0120f82cd000000bae3c5d96be9af000000");
        literal(c.game+0x83c842,"430f108437f86a5400440f2ff8722bf3410f58c4410f2fc77620480fbae0127219ba6191cd8b488b05594c4a028bcf4c8b401841ff9070030000");
        literal(c.game+0xa6be81,"48b900000400400000008b50488bc341899504e95300486bd078488b8432807854004823c148b90000000040000000483bc1751b488b050c562702bae3c5d96b418b4f0c4c8b401841ff9070030000");
        c.context=allocate(0x3000);c.camera=allocate(0x1000);c.request=c.context+0x1f00;c.avatar_owner=allocate(0x550000);
        c.avatar_index=0;c.avatar=17;c.body=(3<<22)|7;controller=allocate(0x1000);descriptor=allocate(0x1000);
        c.registry=allocate(0x1000);c.units=allocate(0x1000);c.generations=allocate(0x1000);c.body_object=allocate(0x1000);
        c.instance=allocate(0x1000);c.graph=allocate(0x100000);c.native_world=allocate(0x1000);active=allocate(0x1000);
        put(c.game+0x2e287d0,c.context);put(c.context,c.camera);put(c.game+0x2ce1ee0,c.avatar_owner);put(c.game+0x2e381a8,controller);
        put<uint32_t>(c.avatar_owner+0x6c,1);put(c.avatar_owner+0x110,descriptor);put(descriptor+8,c.avatar);put(descriptor+12,c.body);
        put(c.exe+0x1ab76f8,c.registry);put<uint32_t>(c.registry+0x98,128);put(c.registry+0x88,c.units);put(c.registry+0xa0,c.generations);
        put<uint8_t>(c.generations+7,3);put(c.units+7*8,c.body_object);put(c.body_object+8,c.body);put<uint32_t>(c.body_object+0x70,107);
        put<uint64_t>(c.body_object+0x358,0x4d1c334d294dfa97ULL);put(c.body_object+0x178,c.instance);put(c.body_object+0x18,c.native_world);
        put(c.instance+0x28,c.graph);put(c.instance+0x50,active);put<uint32_t>(c.graph+4,31);put<uint32_t>(c.graph+0x14,54);put<uint32_t>(c.graph+8,0x100);
        table=c.graph+0x100;put<uint32_t>(table,31);
        for(uint32_t layer=1;layer<=31;++layer){
            const uint32_t off=0x1000+layer*0x4000;put<uint32_t>(table+4+(layer-1)*4,off);
            const uint64_t def=table+off;const uint32_t n=layer==4?78:layer==24?10:layer==25?4:100;put(def+8,n);
            for(uint32_t i=0;i<n;++i)put<uint32_t>(def+12+i*4,0x1000+i*16);
            set(layer,0);
        }
        normal();root=allocate(0x1000);put(c.game+0x2ce14c8,root);put<uint64_t>(root+0x18,c.exe+API_RVA);
        put<uint64_t>(c.exe+API_RVA+0x370,reinterpret_cast<uint64_t>(synthetic_event));fixture_target=synthetic_event;
        const uint32_t sites[]{0x83c39f,0x83c875,0xa6bec9};
        for(unsigned i=0;i<3;++i){
            const uint64_t stub=c.game+0x1000+i*0x40,site=c.game+sites[i];literal(stub,"4883ec2849b8");put<uint64_t>(stub+6,c.exe+API_RVA);put<uint8_t>(stub+14,0xe9);
            put<int32_t>(stub+15,static_cast<int32_t>(site-(stub+19)));literal(site+7,"4883c428c3");invoke[i]=reinterpret_cast<Event>(stub);
        }
        CHECK(FlushInstructionCache(GetCurrentProcess(),reinterpret_cast<void*>(c.game),0x3382000));
    }
    uint64_t address(uint32_t layer,uint32_t state){uint64_t at=0;CHECK(state_address(c,layer,state,0,at));return at;}
    void set(uint32_t layer,uint32_t state){put(active+(layer-1)*8,address(layer,state));}
    void normal(){std::memset(reinterpret_cast<void*>(controller),0,6);std::memset(reinterpret_cast<void*>(c.avatar_owner+0x53e888),0,24);put<uint32_t>(c.request,4);put(c.request+4,c.avatar);put<uint32_t>(c.context+0x1f8,0);put<uint32_t>(c.context+0x1fc,0);set(4,59);set(24,1);set(25,1);set(14,36);set(3,67);set(1,59);}
    uint64_t slot_value(){uint64_t x=0;CHECK(value(c.exe+API_RVA+0x370,x));return x;}
    void begin(){CHECK(NADSHF_Begin(&c,&token)==1&&token&&slot_value()==callback());}
    void end(){CHECK(NADSHF_End(token)==1&&slot_value()==reinterpret_cast<uint64_t>(synthetic_event));}
    NADSHF_Stats stats(){NADSHF_Stats s{};s.size=sizeof s;s.abi=1;CHECK(NADSHF_ReadStats(reserved?token:0,&s));return s;}
    void sample(unsigned site,uint32_t hash=START,uint32_t unit=0){invoke[site](unit?unit:c.body,hash);}
};
static DWORD WINAPI forwarding_thread(void* data){auto f=static_cast<Fixture*>(data);reinterpret_cast<Event>(callback())(f->c.body,0x1234);return 0;}
int main(){
    Fixture f;CHECK(sizeof(NADSHF_Config)==144&&sizeof(NADSHF_Stats)==184);CHECK(f.stats().effective_armed==0);
    f.begin();auto s=f.stats();CHECK(s.installed&&s.armed&&s.effective_armed&&s.body==f.c.body&&s.body_generation==3&&s.deadline_ms==fixture_time+250);
    const uint64_t before=calls;for(unsigned i=0;i<3;++i)f.sample(i);f.sample(1,END);
    CHECK(calls==before&&f.stats().suppressed_start==3&&f.stats().suppressed_end==1);f.end();pass("both events are suppressed only at all four qualified call/hash combinations");
    f.begin();f.sample(0,END);f.sample(2,END);f.sample(1,0x4f5fb830);f.sample(1,0x15bcea4e);f.sample(1,START,f.c.body+1);
    reinterpret_cast<Event>(callback())(f.c.body,START);s=f.stats();CHECK(s.seen==6&&s.forwarded==6&&s.suppressed_start==0&&calls==before+6);f.end();pass("other hashes, units and callers forward exactly once including actual aim events");
    f.begin();put<uint8_t>(f.c.avatar_owner+0x53e888+12,64);f.sample(1);f.sample(1,END);CHECK(f.stats().effective_armed&&f.stats().suppressed_start==1);f.end();f.normal();pass("raw firing bit102 is allowed without any native state or flag write");
    f.begin();const auto cas_before=fixture_cas_calls;for(unsigned i=0;i<200;++i){++fixture_time;CHECK(NADSHF_Publish(f.token,&f.c)==1);CHECK(f.stats().effective_armed);}
    CHECK(fixture_cas_calls==cas_before&&f.stats().publications==201);f.end();pass("steady publications refresh expiry without pointer churn or native state calls");
    f.begin();fixture_time+=250;s=f.stats();CHECK(s.armed&&!s.effective_armed);const uint64_t c0=calls;f.sample(1);CHECK(calls==c0+1&&!f.stats().armed&&NADSHF_Error()==EXPIRED);
    CHECK(NADSHF_Publish(f.token,&f.c)==1&&f.stats().effective_armed);f.end();pass("TTL expires at the exact deadline and a qualified fresh publication can resume");
    f.begin();fixture_read_advance_at=f.c.instance+0x50;fixture_read_advance_ms=250;CHECK(!f.stats().effective_armed);f.end();
    f.begin();fixture_read_advance_at=f.c.instance+0x50;fixture_read_advance_ms=250;f.sample(1);CHECK(f.stats().forwarded==1&&!f.stats().armed&&NADSHF_Error()==EXPIRED);f.end();pass("expiry during protected guard reads cannot produce a stale positive proof or suppress an event");
    f.begin();CHECK(NADSHF_Pause(f.token)==1&&f.stats().installed&&!f.stats().armed&&!f.stats().effective_armed);f.sample(1);CHECK(f.stats().forwarded==1);
    CHECK(NADSHF_Publish(f.token,&f.c)==1);f.sample(1);CHECK(f.stats().suppressed_start==1);f.end();pass("Pause retains installed data slot and forwards until qualified publication");
    const unsigned bytes_at[]{6,10,15,15,14,9};const uint8_t masks[]{1,4,32,2,4,4};
    for(unsigned i=0;i<6;++i){f.begin();put<uint8_t>(f.c.avatar_owner+0x53e888+bytes_at[i],masks[i]);CHECK(!f.stats().effective_armed);f.sample(1);CHECK(!f.stats().armed&&f.stats().forwarded==1);f.end();f.normal();}
    pass("either aim bit, legacy aim, reload, seat and gait sprint fail open immediately");
    for(unsigned i=0;i<3;++i){f.begin();if(i==0)put<uint32_t>(f.controller,2);if(i==1)put<uint8_t>(f.controller+4,1);if(i==2)put<uint8_t>(f.controller+5,1);
        CHECK(!f.stats().effective_armed);CHECK(NADSHF_Publish(f.token,&f.c)==0&&!f.stats().armed);f.end();f.normal();}
    pass("weapon-transition inhibit, native ADS and unknown controller guard pause admission");
    for(auto layer:{4u,24u,25u}){f.begin();f.set(layer,0);CHECK(!f.stats().effective_armed);f.sample(1);CHECK(!f.stats().armed&&f.stats().forwarded==1);f.end();f.normal();}
    f.set(24,6);f.begin();f.sample(1);CHECK(f.stats().suppressed_start==1);f.end();f.normal();pass("only current59 plus either aimed24 member and25=1 admit events");
    f.begin();f.set(3,71);CHECK(!f.stats().effective_armed);f.sample(1);f.end();f.normal();pass("native sprint state inhibits even without the gait bit");
    f.begin();put<uint8_t>(f.c.generations+7,4);CHECK(!f.stats().effective_armed);f.sample(1);CHECK(f.stats().forwarded==1&&!f.stats().armed);put<uint8_t>(f.c.generations+7,3);CHECK(!f.stats().effective_armed);f.end();pass("generation retirement disarms and cannot resurrect without publication");
    f.begin();put<uint64_t>(f.c.body_object+0x178,f.c.instance+8);CHECK(!f.stats().effective_armed);f.sample(1);put(f.c.body_object+0x178,f.c.instance);f.end();pass("body graph replacement never receives the old admission");
    f.begin();put<uint32_t>(f.descriptor+12,f.c.body+1);CHECK(!f.stats().effective_armed);f.sample(1);put(f.descriptor+12,f.c.body);f.end();pass("avatar descriptor must retain the exact full body reference");
    f.begin();put<uint32_t>(f.c.request,6);CHECK(!f.stats().effective_armed);f.sample(1);f.end();f.normal();pass("native camera6 always forwards");
    f.begin();put<uint64_t>(f.c.context,f.c.camera+16);CHECK(!f.stats().effective_armed);f.sample(1);put(f.c.context,f.c.camera);f.end();pass("retired camera owner disarms even while request kind stays4");
    f.begin();put<uint64_t>(f.c.exe+API_RVA+0x370,reinterpret_cast<uint64_t>(foreign_event));CHECK(!f.stats().effective_armed);CHECK(NADSHF_End(f.token)==1);
    CHECK(f.slot_value()==reinterpret_cast<uint64_t>(foreign_event));put<uint64_t>(f.c.exe+API_RVA+0x370,reinterpret_cast<uint64_t>(synthetic_event));pass("cleanup preserves a foreign replacement without writing over it");
    f.begin();put<uint8_t>(f.c.game+0x83c782,0);CHECK(!f.stats().effective_armed);f.sample(1);CHECK(!f.stats().armed&&NADSHF_Error()==CODE_MISMATCH);put<uint8_t>(f.c.game+0x83c782,0x4a);f.end();pass("fresh code drift invalidates stats and callback admission before Publish");
    f.begin();NADSHF_Config wrong=f.c;wrong.body_object+=16;CHECK(NADSHF_Publish(f.token,&wrong)==0&&!f.stats().armed&&f.stats().installed);CHECK(NADSHF_Publish(f.token,&f.c)==1);f.end();pass("bad Publish pauses but retains cleanup token and installed slot");
    f.begin();uint64_t other=UINT64_MAX;CHECK(NADSHF_Begin(&f.c,&other)==0&&other==0&&NADSHF_Error()==BUSY);
    CHECK(!NADSHF_Publish(f.token+1,&f.c)&&!NADSHF_Pause(f.token+1)&&!NADSHF_End(f.token+1));CHECK(f.stats().armed);f.end();CHECK(NADSHF_End(f.token)==1);pass("generation tokens protect Begin Publish Pause End and retired idempotency");
    auto invalid=f.c;invalid.ttl_ms=251;other=123;CHECK(!NADSHF_Begin(&invalid,&other)&&!other);invalid=f.c;invalid.reserved[1]=1;CHECK(!NADSHF_Begin(&invalid,&other));invalid=f.c;invalid.size=0;CHECK(!NADSHF_Begin(&invalid,&other));pass("ABI reserved fields and TTL bounds fail without a lease");
    const uint64_t cb=fixture_cas_calls;fixture_slot_readonly=true;CHECK(!NADSHF_Begin(&f.c,&other)&&!other&&NADSHF_Error()==SLOT_NOT_WRITABLE);fixture_slot_readonly=false;
    put<uint64_t>(f.c.exe+API_RVA+0x370,reinterpret_cast<uint64_t>(foreign_event));CHECK(!NADSHF_Begin(&f.c,&other)&&!other&&NADSHF_Error()==API_MISMATCH);put<uint64_t>(f.c.exe+API_RVA+0x370,reinterpret_cast<uint64_t>(synthetic_event));CHECK(fixture_cas_calls==cb);pass("foreign or protected slots are refused before compare-exchange");
    fixture_cas_fail_at=fixture_cas_calls+1;CHECK(!NADSHF_Begin(&f.c,&other)&&!other&&!reserved);fixture_cas_fail_at=0;
    fixture_foreign_cas_at=fixture_cas_calls+1;fixture_foreign_value=reinterpret_cast<uint64_t>(foreign_event);CHECK(!NADSHF_Begin(&f.c,&other)&&!other&&!reserved);fixture_foreign_cas_at=0;
    CHECK(f.slot_value()==fixture_foreign_value);put<uint64_t>(f.c.exe+API_RVA+0x370,reinterpret_cast<uint64_t>(synthetic_event));pass("CAS failure and a concurrent initial foreign owner leave no false lease");
    f.begin();fixture_slot_unreadable=true;CHECK(NADSHF_End(f.token)==2&&reserved&&!armed.load());fixture_slot_unreadable=false;f.end();pass("unreadable restoration retains the disarmed cleanup token");
    f.begin();entered=CreateEventW(nullptr,TRUE,FALSE,nullptr);continue_forward=CreateEventW(nullptr,TRUE,FALSE,nullptr);CHECK(entered&&continue_forward);
    HANDLE worker=CreateThread(nullptr,0,forwarding_thread,&f,0,nullptr);CHECK(worker&&WaitForSingleObject(entered,10000)==WAIT_OBJECT_0);
    CHECK(NADSHF_End(f.token)==2&&reserved&&!installed.load()&&!armed.load());SetEvent(continue_forward);CHECK(WaitForSingleObject(worker,10000)==WAIT_OBJECT_0);
    CloseHandle(worker);CloseHandle(entered);CloseHandle(continue_forward);entered=nullptr;continue_forward=nullptr;CHECK(NADSHF_End(f.token)==1);pass("End restores slot but retains token until an in-flight forwarded callback returns");
    reinterpret_cast<Event>(callback())(f.c.body,START);CHECK(!reserved);pass("a cached retired callback remains valid and forwards while disarmed");
    std::printf("Held-fire native filter: %llu cases passed; synthetic buffers only\n",static_cast<unsigned long long>(cases));return 0;
}
