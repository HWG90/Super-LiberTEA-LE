// Private synthetic buffers and callbacks only: no game process is opened.
#define NADZ_FIXTURE
#include "native_ads_zoom.cpp"
#include <cstdio>
#include <cstdlib>
#include <thread>
#define CHECK(x) do{if(!(x)){std::fprintf(stderr,"FAIL %d: %s error=%u\n",__LINE__,#x,NADZ_Error());std::abort();}}while(0)
static uint64_t active_generation=0,cases=0,selector_calls=0,event_calls=0;
static uint32_t selected=2;
static bool rotate_epoch=false;
static uint32_t synthetic_selector(uint32_t,uint32_t) {++selector_calls;if(rotate_epoch)policy_epoch.fetch_add(1);return selected;}
static float magnifications[3]{1,2.5f,3.5f};
static void synthetic_event(void*,void* request) {
    ++event_calls;auto* bytes_=static_cast<uint8_t*>(request);
    const uint64_t before=fixture_caller;fixture_caller=hook_game+0x110ac74;
    const uint32_t index=selector_hook(policy.c.weapon,1);fixture_caller=before;
    float lens=0,depth=0;std::memcpy(&lens,bytes_+0x84,4);std::memcpy(&depth,bytes_+0x90,4);
    std::memcpy(bytes_+0xa0,&lens,4);std::memcpy(bytes_+0x9c,&depth,4);
    depth=.05f+.15f*(index<3?index:0);std::memcpy(bytes_+0x90,&depth,4);
}
static float synthetic_zoom(void*,uint32_t weapon) {
    const uint64_t before=fixture_caller;fixture_caller=hook_game+0x764f2e;
    const uint32_t index=selector_hook(weapon,1);fixture_caller=before;
    return index<3?magnifications[index]:1;
}
static void pass(const char* name) {++cases;std::printf("PASS %s\n",name);}
static float load_float(uint64_t at) {float out=0;CHECK(value(at,out));return out;}
static bool close(float a,float b) {return std::fabs(a-b)<.00001f;}
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
struct Fixture {
    NADZ_Config c{};uint64_t controller=0,descriptor=0,registry=0,units=0,generations=0,body_object=0,api=0,settings=0;
    Fixture() {
        c.size=sizeof c;c.abi=1;c.game=allocate(0x3382000,PAGE_EXECUTE_READWRITE);c.exe=allocate(0x29fe000);
        fake_image(c.game,0x6ae0e5ff,0x3382000);fake_image(c.exe,0x6ae0964a,0x29fe000);
        literal(c.game+SELECTOR,"40534883ec208bdae853ffffff84c00f84ac0000004c8b1db4926d014533c03b0d");
        literal(c.game+0x764f29,"e8a23cea0085c07434");
        literal(c.game+0x110ac6f,"e85cdf4f00418b55083bc38bf8410f44fee80ba265ff");
        literal(c.game+ZOOM,"48895c24084889742410574883ec203b152ba26d028bda");
        literal(c.game+EVENT,"40554881ec30010000488b05e0a53a014833c448898424d0000000488bea");
        literal(c.game+0x1118731,"f3410f109784000000f30f59155ee81201f30f5e9088c40a00");
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
        fixture_selector=synthetic_selector;fixture_event=synthetic_event;fixture_zoom=synthetic_zoom;
        normal();
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
    }
    void fp() {normal();top(6,2,c.weapon);}
    void begin() {fp();CHECK(NADZ_Begin(&c,&active_generation)==1);}
    NADZ_Stats stats() {NADZ_Stats s{};s.size=sizeof s;s.abi=1;CHECK(NADZ_ReadStats(reserved.load()?active_generation:0,&s)==1);return s;}
};
int main() {
 Fixture f;CHECK(NADZ_Validate(&f.c)==1 && !installed.load());
 CHECK(NADZ_Begin(&f.c,&active_generation)==0 && !active_generation);pass("read-only normal-camera preflight; Begin requires owned native6");
 f.fp();literal(f.c.game+0x1118731,"00");CHECK(NADZ_Validate(&f.c)==0 && NADZ_Error()==CODE_MISMATCH);
 literal(f.c.game+0x1118731,"f3");pass("sensitivity witness drift fails closed before hook installation");
 fixture_hook_failure=HOOK_APPLY+5;CHECK(NADZ_Begin(&f.c,&active_generation)==0 && !reserved.load());
 fixture_hook_failure=0;pass("hook transaction failure is reported without an owned generation");
 selected=UINT32_MAX;uint64_t absent_events=event_calls;
 CHECK(NADZ_Begin(&f.c,&active_generation)==1 && armed.load() && reserved.load() && event_calls==absent_events);
 CHECK(NADZ_Update(active_generation)==1 && NADZ_End(active_generation)==1 && event_calls==absent_events);
 selected=2;pass("firearms without an optic-selection parameter retain first person with a clean native no-op");
 CHECK(NADZ_Begin(&f.c,&active_generation)==1);CHECK(reserved.load() && armed.load() && installed.load());
 CHECK(selected==2 && close(load_float(f.c.request+0x84),90*RAD_PER_DEG));
 CHECK(close(load_float(f.c.request+0x90),.05f) && close(load_float(f.c.request+0x9c),.05f));
 CHECK(close(load_float(f.c.request+0xa0),90*RAD_PER_DEG));pass("Begin snaps current/prior lens and depth to authored first zoom without changing selection");
 const uint64_t before=selector_calls;fixture_caller=f.c.game+0x764f2e;
 CHECK(selector_hook(f.c.weapon,1)==0 && selector_calls==before+1);pass("selector always calls native first, then overrides exact magnification caller");
 rotate_epoch=true;CHECK(selector_hook(f.c.weapon,1)==2);rotate_epoch=false;CHECK(selector_hook(f.c.weapon,1)==0);
 pass("callbacks crossing a lease epoch forward their original result");
 fixture_caller=f.c.game+0x110ac74;CHECK(selector_hook(f.c.weapon,1)==0);pass("native zoom event receives the same baseline coefficient index");
 fixture_caller=f.c.game+0x764f2f;CHECK(selector_hook(f.c.weapon,1)==2);pass("other caller return addresses forward exact native result");
 fixture_caller=f.c.game+0x764f2e;CHECK(selector_hook(f.c.weapon+1,1)==2 && selector_hook(f.c.weapon,2)==2);
 pass("foreign weapons and parameter types remain native");
 selected=UINT32_MAX;CHECK(selector_hook(f.c.weapon,1)==UINT32_MAX);selected=3;CHECK(selector_hook(f.c.weapon,1)==3);
 selected=2;pass("unavailable and unsupported native selection results pass unchanged");
 for(uint32_t i:{0U,1U,2U}) {selected=i;CHECK(selector_hook(f.c.weapon,1)==0);synthetic_event(nullptr,reinterpret_cast<void*>(f.c.request));CHECK(close(load_float(f.c.request+0x90),.05f));}
 pass("changing actual stored zoom through all three levels keeps native presentation depth fixed");
 selected=2;f.controls(0,true);CHECK(selector_hook(f.c.weapon,1)==2);CHECK(NADZ_Update(active_generation)==1);
 CHECK(close(load_float(f.c.request+0x84),90/3.5f*RAD_PER_DEG) && close(load_float(f.c.request+0x90),.35f));
 pass("full ADS immediately forwards selection and update restores native optic lens/depth");
 f.controls();CHECK(NADZ_Update(active_generation)==1 && selector_hook(f.c.weapon,1)==0);
 CHECK(close(load_float(f.c.request+0x84),90*RAD_PER_DEG));pass("return from native ADS restores stable first-person input ratio");
 uint64_t events=event_calls;CHECK(NADZ_Update(active_generation)==1 && event_calls==events);pass("settled updates do not replay native events or writes");
 f.controls(4);CHECK(selector_hook(f.c.weapon,1)==2);f.controls(0,false,true);CHECK(selector_hook(f.c.weapon,1)==2);
 f.controls();put<uint8_t>(f.c.avatar_owner+0x53e896,4);CHECK(selector_hook(f.c.weapon,1)==2);put<uint8_t>(f.c.avatar_owner+0x53e896,0);
 pass("inhibited actions, controller guards and seated state preserve native optics");
 CHECK(NADZ_End(active_generation+1)==0 && NADZ_Error()==TOKEN_MISMATCH);
 NADZ_Stats bad{};bad.size=sizeof bad;bad.abi=1;CHECK(NADZ_ReadStats(active_generation+1,&bad)==0);
 pass("stale generations cannot end or inspect another lease");
 CHECK(NADZ_End(active_generation)==1 && !armed.load() && !reserved.load() && installed.load());
 CHECK(close(load_float(f.c.request+0x84),90/3.5f*RAD_PER_DEG) && close(load_float(f.c.request+0x90),.35f));
 CHECK(selector_hook(f.c.weapon,1)==2 && NADZ_End(active_generation)==1);pass("End restores real selected optics, is idempotent and retains forwarding trampoline");
 CHECK(NADZ_Begin(&f.c,&active_generation)==1);
 const NADZ_Config previous=f.c;f.c.weapon=0x888;f.top(6,3,f.c.weapon);CHECK(NADZ_Bind(active_generation,&f.c)==1);
 CHECK(policy.c.weapon==0x888 && selector_hook(previous.weapon,1)==2 && selector_hook(f.c.weapon,1)==0);
 pass("weapon/request rebind drops old request and applies only the new owned firearm");
 CHECK(NADZ_End(active_generation)==1);
 fixture_fail_write_at=fixture_write_calls+2;
 CHECK(NADZ_Begin(&f.c,&active_generation)==2 && reserved.load() && !armed.load() && policy.normalized);
 fixture_fail_write_at=0;CHECK(NADZ_End(active_generation)==1);
 CHECK(close(load_float(f.c.request+0x84),90/3.5f*RAD_PER_DEG) && close(load_float(f.c.request+0x90),.35f));
 pass("partial normalization retains cleanup ownership and End rebuilds real lens/depth");
 CHECK(NADZ_Begin(&f.c,&active_generation)==1);f.controls(4);
 CHECK(NADZ_End(active_generation)==0 && reserved.load() && !armed.load());f.controls();CHECK(NADZ_End(active_generation)==1);
 pass("unsafe restoration stays reserved until the owned request is safe again");
 CHECK(NADZ_Begin(&f.c,&active_generation)==1);put<uint32_t>(f.descriptor+12,0x400004);
 CHECK(selector_hook(f.c.weapon,1)==2 && !armed.load());events=event_calls;
 CHECK(NADZ_End(active_generation)==1 && event_calls==events);put<uint32_t>(f.descriptor+12,f.c.body);
 pass("retired player disarms immediately; cleanup never replays into a changed owner");
 CHECK(NADZ_Begin(&f.c,&active_generation)==1);f.top(4,4,f.c.weapon);events=event_calls;
 CHECK(NADZ_End(active_generation)==1 && event_calls==events);pass("camera handoff releases without writing an inactive request");
 f.fp();CHECK(NADZ_Begin(&f.c,&active_generation)==1);literal(f.c.game+SELECTOR,"00");
 CHECK(NADZ_Update(active_generation)==0 && !armed.load());events=event_calls;
 CHECK(NADZ_End(active_generation)==0 && reserved.load() && event_calls==events);
 literal(f.c.game+SELECTOR,"40");
 CHECK(NADZ_End(active_generation)==1);pass("installed hook fingerprint changes disarm rather than silently accepting drift");
 std::printf("Native zoom fixture PASS: %llu cases\n",static_cast<unsigned long long>(cases));return 0;
}
