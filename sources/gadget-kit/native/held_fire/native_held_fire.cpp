// Animation-only hip-fire event admission. Only one writable SDK data pointer
// is exchanged. No executable byte/protection changes and no state setters.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <intrin.h>
#include <atomic>
#include <cstdint>
#include <cstring>
#include "../first_person/native_memory.h"
#include "native_held_fire.h"
#include "native_held_fire_cas.h"
using Event=void (*)(uint32_t,uint32_t);
namespace {
enum Error:uint32_t {OK=0,INVALID_CONFIG=1,BUSY=2,READ_FAILED=3,IMAGE_MISMATCH=4,
    CODE_MISMATCH=5,API_MISMATCH=6,OWNER_MISMATCH=7,TARGET_MISMATCH=8,PIN_FAILED=9,
    SLOT_NOT_WRITABLE=10,CAS_MISMATCH=11,CAS_FAULT=12,CLEANUP_PENDING=13,
    EXPIRED=14,TOKEN_MISMATCH=15};
constexpr uint32_t START=0x6bd9c5e3,END=0x8bcd9161;
constexpr uint64_t API_RVA=0x28703e0,EVENT_RVA=0x1f77c0;
static SRWLOCK control_lock=SRWLOCK_INIT,policy_lock=SRWLOCK_INIT;
static std::atomic<Event> original{nullptr};
static std::atomic<uint32_t> armed{0},installed{0},last_error{0};
static std::atomic<uint64_t> seen{0},forwarded{0},dropped_start{0},dropped_end{0},rejected{0},
    publications{0},pauses{0},in_flight{0},last_caller{0};
static std::atomic<uint32_t> last_event{0};
static uint64_t slot=0,slot_image=0,next_token=0,owned_token=0,retired_token=0;
static bool reserved=false,possible=false;
struct Policy {NADSHF_Config c{};uint64_t controller=0,descriptor=0,deadline=0;uint8_t descriptor_bytes[20]{};};
static Policy policy;
#if defined(NADSHF_FIXTURE)
static Event fixture_target=nullptr;
static uint64_t fixture_time=1000;
static bool fixture_slot_readonly=false,fixture_slot_unreadable=false;
static uint64_t fixture_cas_calls=0,fixture_cas_fail_at=0,fixture_foreign_cas_at=0,fixture_foreign_value=0;
static uint64_t fixture_read_advance_at=0,fixture_read_advance_ms=0;
#endif
static uint64_t tick() {
#if defined(NADSHF_FIXTURE)
    return fixture_time;
#else
    return GetTickCount64();
#endif
}
static bool read(uint64_t at,void* out,size_t n) {
#if defined(NADSHF_FIXTURE)
    if(at==fixture_read_advance_at){fixture_time+=fixture_read_advance_ms;fixture_read_advance_at=0;}
#endif
    if(at<65536 || at>=0x800000000000ULL || n==0 || n>4096 || at+n>=0x800000000000ULL)return false;
    SIZE_T actual=0;return ReadProcessMemory(GetCurrentProcess(),reinterpret_cast<void*>(at),out,n,&actual)!=0 && actual==n;
}
template<class T> static bool value(uint64_t at,T& out){return read(at,&out,sizeof out);}
static bool ptr(uint64_t at,uint64_t& out){return value(at,out)&&out>=65536&&out<0x800000000000ULL;}
static uint32_t reject(uint32_t e){last_error.store(e,std::memory_order_release);return 0;}
static bool bytes(uint64_t at,const char* hex) {
    uint8_t raw[96]{};const size_t n=std::strlen(hex)/2;if(!n||n>sizeof raw||!read(at,raw,n))return false;
    auto digit=[](char c)->uint8_t{return static_cast<uint8_t>(c<='9'?c-'0':c-'a'+10);};
    for(size_t i=0;i<n;++i)if(raw[i]!=(digit(hex[2*i])<<4|digit(hex[2*i+1])))return false;return true;
}
static bool image(uint64_t base,uint32_t stamp,uint32_t length) {
    IMAGE_DOS_HEADER d{};IMAGE_NT_HEADERS64 n{};
    return read(base,&d,sizeof d)&&d.e_magic==IMAGE_DOS_SIGNATURE&&d.e_lfanew>=64&&d.e_lfanew<=4096
        &&read(base+d.e_lfanew,&n,sizeof n)&&n.Signature==IMAGE_NT_SIGNATURE
        &&n.FileHeader.Machine==IMAGE_FILE_MACHINE_AMD64&&n.OptionalHeader.Magic==IMAGE_NT_OPTIONAL_HDR64_MAGIC
        &&n.FileHeader.TimeDateStamp==stamp&&n.OptionalHeader.SizeOfImage==length;
}
static bool executable(uint64_t at) {
    MEMORY_BASIC_INFORMATION r{};
    return VirtualQuery(reinterpret_cast<void*>(at),&r,sizeof r)==sizeof r&&r.State==MEM_COMMIT
        &&
#if defined(NADSHF_FIXTURE)
        (pe_section_mapping(r)||r.Type==MEM_PRIVATE)
#else
        pe_section_mapping(r)
#endif
        &&(r.Protect==PAGE_EXECUTE_READ||r.Protect==PAGE_EXECUTE_READWRITE||r.Protect==PAGE_EXECUTE_WRITECOPY);
}
static bool writable_slot(uint64_t at,uint64_t exe) {
    if(at&7)return false;
#if defined(NADSHF_FIXTURE)
    if(fixture_slot_readonly)return false;
#endif
    MEMORY_BASIC_INFORMATION r{};
    if(VirtualQuery(reinterpret_cast<void*>(at),&r,sizeof r)!=sizeof r||r.State!=MEM_COMMIT
        ||!writable_pe_protection(r.Protect)||at+8>reinterpret_cast<uint64_t>(r.BaseAddress)+r.RegionSize)return false;
#if defined(NADSHF_FIXTURE)
    (void)exe;return r.Type==MEM_PRIVATE;
#else
    return pe_section_mapping(r)&&reinterpret_cast<uint64_t>(r.AllocationBase)==exe;
#endif
}
static bool slot_read(uint64_t at,uint64_t& out) {
#if defined(NADSHF_FIXTURE)
    if(fixture_slot_unreadable)return false;
#endif
    return value(at,out);
}
static bool cas(uint64_t expected,uint64_t desired,uint64_t& observed) {
#if defined(NADSHF_FIXTURE)
    if(++fixture_cas_calls==fixture_cas_fail_at)return false;
    if(fixture_cas_calls==fixture_foreign_cas_at)InterlockedExchangePointer(reinterpret_cast<PVOID volatile*>(slot),reinterpret_cast<void*>(fixture_foreign_value));
#endif
    return NADSHF_CasPointer(slot,expected,desired,&observed)!=0;
}
static void event_hook(uint32_t unit,uint32_t hash);
static uint64_t callback(){return reinterpret_cast<uint64_t>(&event_hook);}
static bool pin(const void* at){HMODULE m=nullptr;return GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(at),&m)!=0;}
static bool code(const NADSHF_Config& c) {
    if(!image(c.game,0x6af322c1,0x3382000)||!image(c.exe,0x6af2d5e6,0x29fe000))return reject(IMAGE_MISMATCH)!=0;
    if(!bytes(c.exe+EVENT_RVA,"48895c2408574883ec208bda8bf9e8fd8eeaff448bc38bd7488b4818488b5c24304883c4205fe90547f3ff")
        ||!bytes(c.exe+0x12bf65,"b801000000f00fc186380017008bc0486bc858c784318800010003000000899c313800010089ac313c000100")
        ||!bytes(c.game+0x83c37f,"4e85a433807854000f84a6000000488b0534514a02bae3c5d96b8bcf4c8b401841ff9070030000")
        ||!bytes(c.game+0x83c782,"4a8b843380785400480fbae0260f83ac0000004380bc37d16a5400000f85d8000000480fbae0120f82cd000000bae3c5d96be9af000000")
        ||!bytes(c.game+0x83c842,"430f108437f86a5400440f2ff8722bf3410f58c4410f2fc77620480fbae0127219ba6191cd8b488b05594c4a028bcf4c8b401841ff9070030000")
        ||!bytes(c.game+0xa6beb1,"48b900000400400000008b50488bc341899504e95300486bd078488b8432807854004823c148b90000000040000000483bc1751b488b05dc552702bae3c5d96b418b4f0c4c8b401841ff9070030000"))return reject(CODE_MISMATCH)!=0;
    return true;
}
static bool api(const NADSHF_Config& c,uint64_t& address) {
    uint64_t root=0,table=0;
    if(!ptr(c.game+0x2ce14c8,root)||!ptr(root+0x18,table)||table!=c.exe+API_RVA)return reject(API_MISMATCH)!=0;
    address=table+0x370;return true;
}
static bool dispatch(const NADSHF_Config& c,bool ours) {
    uint64_t at=0,current=0;if(!api(c,at)||at!=slot||!slot_read(at,current))return false;
#if defined(NADSHF_FIXTURE)
    const uint64_t native=reinterpret_cast<uint64_t>(fixture_target);
#else
    const uint64_t native=c.exe+EVENT_RVA;
#endif
    return current==(ours?callback():native);
}
static bool config(const NADSHF_Config* input,NADSHF_Config& c) {
    if(!read(reinterpret_cast<uint64_t>(input),&c,sizeof c)||c.size!=sizeof c||c.abi!=1||c.reserved[0]||c.reserved[1]
        ||c.avatar_index>=8||!c.avatar||c.avatar==UINT32_MAX||!c.body||c.body==UINT32_MAX||!c.ttl_ms||c.ttl_ms>250)return reject(INVALID_CONFIG)!=0;
    const uint64_t pointers[]{c.game,c.exe,c.context,c.camera,c.avatar_owner,c.request,c.registry,c.units,c.generations,c.body_object,c.instance,c.graph,c.native_world};
    for(auto p:pointers)if(p<65536||p>=0x800000000000ULL)return reject(INVALID_CONFIG)!=0;
    return true;
}
static bool same_body(const NADSHF_Config& a,const NADSHF_Config& b) {
    return a.game==b.game&&a.exe==b.exe&&a.avatar_owner==b.avatar_owner&&a.avatar_index==b.avatar_index&&a.avatar==b.avatar&&a.body==b.body
        &&a.registry==b.registry&&a.units==b.units&&a.generations==b.generations&&a.body_object==b.body_object&&a.instance==b.instance&&a.graph==b.graph&&a.native_world==b.native_world;
}
static bool state_address(const NADSHF_Config& c,uint32_t layer,uint32_t state,uint32_t expected,uint64_t& at) {
    uint32_t offset=0,n=0,d=0,s=0,count=0;
    if(layer<1||layer>31||!value(c.graph+8,offset)||offset<0x10||offset>0x1000000)return false;
    const uint64_t table=c.graph+offset;
    if(!value(table,count)||count!=31||!value(table+4+static_cast<uint64_t>(layer-1)*4,d)||d<128||d>0x1000000)return false;
    const uint64_t def=table+d;
    if(!value(def+8,n)||!n||n>4096||state>=n||(expected&&n!=expected)
        ||!value(def+12+static_cast<uint64_t>(state)*4,s)||s<12+static_cast<uint64_t>(n)*4||s>0x1000000)return false;
    at=def+s;return true;
}
static bool owner(Policy& p,bool capture) {
    const auto& c=p.c;uint64_t v=0,reg=0,units=0,generations=0,object=0,descriptor=0,controller=0;
    uint32_t capacity=0,count=0,unit=0,nodes=0,layers=0,variables=0;uint8_t generation=0,confirmed=0;
    uint64_t resource=0;uint8_t d[20]{},flags[24]{},controls[6]{};
    const uint32_t index=c.body&0x3fffff;
    if(!ptr(c.exe+0x1ab76f8,reg)||reg!=c.registry||!value(reg+0x98,capacity)||!capacity||capacity>0x400000||index>=capacity
        ||!ptr(reg+0x88,units)||units!=c.units||!ptr(reg+0xa0,generations)||generations!=c.generations
        ||!value(generations+index,generation)||generation!=static_cast<uint8_t>(c.body>>22)
        ||!ptr(units+static_cast<uint64_t>(index)*8,object)||object!=c.body_object||!value(object+8,unit)||unit!=c.body
        ||!value(object+0x70,nodes)||nodes!=107||!value(object+0x358,resource)||resource!=0x4d1c334d294dfa97ULL
        ||!ptr(object+0x178,v)||v!=c.instance||!ptr(c.instance+0x28,v)||v!=c.graph||!ptr(object+0x18,v)||v!=c.native_world
        ||!value(c.graph+4,layers)||layers!=31||!value(c.graph+0x14,variables)||variables!=54
        ||!ptr(c.game+0x2ce1ee0,v)||v!=c.avatar_owner||!value(v+0x6c,count)||!count||count>8||c.avatar_index>=count
        ||!ptr(c.avatar_owner+0x110+static_cast<uint64_t>(c.avatar_index)*8,descriptor)||!read(descriptor,d,20))return false;
    uint32_t avatar=0,body=0;std::memcpy(&avatar,d+8,4);std::memcpy(&body,d+12,4);
    if(avatar!=c.avatar||body!=c.body)return false;
    if(!ptr(c.game+0x2e287d0,v)||v!=c.context||!ptr(c.context,v)||v!=c.camera
        ||!ptr(c.game+0x2e381a8,controller)||!read(controller,controls,6)
        ||!read(c.avatar_owner+0x53e888+static_cast<uint64_t>(c.avatar_index)*0x1240,flags,24))return false;
    uint32_t inhibit=0;std::memcpy(&inhibit,controls,4);
    // Unknown camera inhibit masks and either individual aim bit are refused.
    // Firing bit102 is deliberately permitted; this filter changes no flags.
    if(inhibit||controls[4]||controls[5]||(flags[6]&1)||(flags[10]&4)||(flags[15]&32)||(flags[15]&2)||(flags[14]&4)||(flags[9]&4))return false;
    uint32_t head=0,tail=0,request[2]{};
    if(!value(c.context+0x1f8,head)||!value(c.context+0x1fc,tail)||head>=32||tail>=32)return false;
    const uint64_t record=head==tail?c.context+0x1f00:c.context+0x200+static_cast<uint64_t>((tail+31)%32)*0xe8;
    if(record!=c.request||!read(record,request,sizeof request)||(request[0]&0xffff)!=4||request[1]!=c.avatar)return false;
    if(capture){p.controller=controller;p.descriptor=descriptor;std::memcpy(p.descriptor_bytes,d,20);}
    else if(controller!=p.controller||descriptor!=p.descriptor||std::memcmp(d,p.descriptor_bytes,20))return false;
    // Bracket the current active pointers, not stale state indices from Lua.
    uint64_t active=0,current[31]{},again[31]{},a4=0,a24=0,b24=0,a25=0,l14a=0,l14b=0,l3s=0;
    if(!ptr(c.instance+0x50,active)||!read(active,current,sizeof current)
        ||!state_address(c,4,59,78,a4)||!state_address(c,24,1,10,a24)||!state_address(c,24,6,10,b24)||!state_address(c,25,1,4,a25)
        ||current[3]!=a4||(current[23]!=a24&&current[23]!=b24)||current[24]!=a25
        ||!state_address(c,14,36,0,l14a)||!state_address(c,14,3,0,l14b)||!state_address(c,3,71,0,l3s)||current[2]==l3s)return false;
    if(current[13]!=l14a) {
        uint32_t role=0;std::memcpy(&role,flags,4);uint64_t state=0;uint32_t scene=0;
        if(current[13]!=l14b||(role&6)!=2||!ptr(c.game+0x2ce1508,state)||!value(state+0xac29c,scene)||(scene!=3&&scene!=4))return false;
        uint64_t l3b=0,l1a=0,l1b=0;
        if(!state_address(c,3,68,0,l3b)||!state_address(c,1,75,0,l1a)||!state_address(c,1,78,0,l1b)
            ||(current[2]==l3b&&(current[0]==l1a||current[0]==l1b)))return false;
    }
    uint64_t active2=0,object2=0;uint32_t head2=0,tail2=0,request2[2]{};
    uint8_t controls2[6]{},flags2[24]{},d2[20]{};
    if(!read(controller,controls2,6)||std::memcmp(controls,controls2,6)||!read(descriptor,d2,20)||std::memcmp(d,d2,20)
        ||!read(c.avatar_owner+0x53e888+static_cast<uint64_t>(c.avatar_index)*0x1240,flags2,24))return false;
    // Firing may rise/fall during this read-only guard. Action and role facts
    // must remain stable; no unqualified neighboring bits grant admission.
    const unsigned action_bytes[]{0,6,9,10,14,15};const uint8_t action_masks[]{6,1,4,4,4,34};
    for(unsigned i=0;i<6;++i)if((flags[action_bytes[i]]&action_masks[i])!=(flags2[action_bytes[i]]&action_masks[i]))return false;
    return value(generations+index,confirmed)&&confirmed==generation&&ptr(units+static_cast<uint64_t>(index)*8,object2)&&object2==object
        &&ptr(c.game+0x2ce1ee0,v)&&v==c.avatar_owner&&ptr(c.game+0x2e287d0,v)&&v==c.context&&ptr(c.context,v)&&v==c.camera
        &&ptr(c.game+0x2e381a8,v)&&v==controller&&ptr(object+0x178,v)&&v==c.instance&&ptr(c.instance+0x28,v)&&v==c.graph
        &&ptr(object+0x18,v)&&v==c.native_world&&value(object+0x358,resource)&&resource==0x4d1c334d294dfa97ULL
        &&ptr(c.instance+0x50,active2)&&active2==active&&read(active,again,sizeof again)&&std::memcmp(current,again,sizeof current)==0
        &&value(c.context+0x1f8,head2)&&head2==head&&value(c.context+0x1fc,tail2)&&tail2==tail
        &&read(record,request2,sizeof request2)&&std::memcmp(request,request2,sizeof request)==0;
}
static bool effective(Policy& p,uint64_t now) {
    return armed.load(std::memory_order_acquire)&&now<p.deadline&&dispatch(p.c,true)&&code(p.c)&&owner(p,false)
        &&tick()<p.deadline&&armed.load(std::memory_order_acquire);
}
static bool candidate(uint64_t caller,uint32_t hash,const NADSHF_Config& c) {
    if(hash==START)return caller==c.game+0x83c3a6||caller==c.game+0x83c87c||caller==c.game+0xa6bf00;
    return hash==END&&caller==c.game+0x83c87c;
}
struct Flight {Flight(){in_flight.fetch_add(1,std::memory_order_acq_rel);}~Flight(){in_flight.fetch_sub(1,std::memory_order_acq_rel);}};
static void event_call(uint64_t caller,uint32_t unit,uint32_t hash) {
    Flight flight;seen.fetch_add(1,std::memory_order_relaxed);last_caller.store(caller,std::memory_order_relaxed);last_event.store(hash,std::memory_order_relaxed);
    bool suppress=false;
    if(armed.load(std::memory_order_acquire)&&(hash==START||hash==END)) {
        AcquireSRWLockShared(&policy_lock);
        if(armed.load(std::memory_order_acquire)&&unit==policy.c.body&&candidate(caller,hash,policy.c)) {
            const uint64_t now=tick();
            if(now>=policy.deadline){armed.store(0,std::memory_order_release);last_error.store(EXPIRED,std::memory_order_release);rejected.fetch_add(1);}
            else if(!code(policy.c)){armed.store(0,std::memory_order_release);rejected.fetch_add(1);}
            else if(!dispatch(policy.c,true)||!owner(policy,false)){armed.store(0,std::memory_order_release);last_error.store(OWNER_MISMATCH,std::memory_order_release);rejected.fetch_add(1);}
            else if(tick()>=policy.deadline){armed.store(0,std::memory_order_release);last_error.store(EXPIRED,std::memory_order_release);rejected.fetch_add(1);}
            else suppress=armed.load(std::memory_order_acquire)!=0;
        }
        ReleaseSRWLockShared(&policy_lock);
    }
    if(suppress){(hash==START?dropped_start:dropped_end).fetch_add(1,std::memory_order_relaxed);return;}
    forwarded.fetch_add(1,std::memory_order_relaxed);
    const Event next=original.load(std::memory_order_acquire);if(next)next(unit,hash);
}
static void event_hook(uint32_t unit,uint32_t hash){event_call(reinterpret_cast<uint64_t>(_ReturnAddress()),unit,hash);}
static bool output(uint64_t* at,uint64_t token){SIZE_T n=0;return WriteProcessMemory(GetCurrentProcess(),at,&token,8,&n)!=0&&n==8;}
static bool restore_slot() {
    if(possible){uint64_t current=0;if(!slot_read(slot,current))return false;
        if(current==callback()){
            if(!writable_slot(slot,slot_image))return false;uint64_t observed=0;
            if(!cas(callback(),reinterpret_cast<uint64_t>(original.load()),observed))return false;
            // A concurrent foreign replacement is retained, never overwritten.
        }
        possible=false;
    }
    installed.store(0,std::memory_order_release);return true;
}
static void disarm(){armed.store(0,std::memory_order_release);AcquireSRWLockExclusive(&policy_lock);ReleaseSRWLockExclusive(&policy_lock);}
static uint32_t failed_begin(uint32_t error,uint64_t* out) {
    disarm();if(!restore_slot()||in_flight.load()){last_error.store(CLEANUP_PENDING);return 2;}
    reserved=false;retired_token=owned_token;owned_token=0;output(out,0);return reject(error);
}
}
NADSHF_EXPORT uint32_t NADSHF_Begin(const NADSHF_Config* input,uint64_t* token) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockExclusive(&control_lock);}}unlock;
    if(!output(token,0))return reject(INVALID_CONFIG);if(reserved)return reject(BUSY);
    Policy next{};if(!config(input,next.c)||!code(next.c))return 0;
    uint64_t at=0,current=0;if(!api(next.c,at)||!slot_read(at,current))return reject(READ_FAILED);
#if defined(NADSHF_FIXTURE)
    Event native=fixture_target;
#else
    Event native=reinterpret_cast<Event>(next.c.exe+EVENT_RVA);
#endif
    if(current!=reinterpret_cast<uint64_t>(native))return reject(API_MISMATCH);
    if(!writable_slot(at,next.c.exe))return reject(SLOT_NOT_WRITABLE);
    if(!executable(reinterpret_cast<uint64_t>(native)))return reject(API_MISMATCH);
    if(!owner(next,true)||!owner(next,false))return reject(OWNER_MISMATCH);
    if(!pin(reinterpret_cast<void*>(&NADSHF_Begin)))return reject(PIN_FAILED);
#if !defined(NADSHF_FIXTURE)
    if(!pin(reinterpret_cast<void*>(next.c.exe)))return reject(PIN_FAILED);
#endif
    slot=at;slot_image=next.c.exe;original.store(native,std::memory_order_release);
    if(++next_token==0)++next_token;owned_token=next_token;
    if(!output(token,owned_token)){owned_token=0;return reject(INVALID_CONFIG);}
    reserved=true;possible=true;uint64_t observed=0;
    if(!cas(reinterpret_cast<uint64_t>(native),callback(),observed))return failed_begin(CAS_FAULT,token);
    if(observed!=reinterpret_cast<uint64_t>(native)){possible=false;return failed_begin(CAS_MISMATCH,token);}
    installed.store(1,std::memory_order_release);
    AcquireSRWLockExclusive(&policy_lock);next.deadline=tick()+next.c.ttl_ms;policy=next;
    seen.store(0);forwarded.store(0);dropped_start.store(0);dropped_end.store(0);rejected.store(0);publications.store(1);pauses.store(0);last_caller.store(0);last_event.store(0);
    const bool stable=dispatch(policy.c,true)&&owner(policy,false)&&code(policy.c);
    if(stable)armed.store(1,std::memory_order_release);ReleaseSRWLockExclusive(&policy_lock);
    if(!stable)return failed_begin(OWNER_MISMATCH,token);last_error.store(OK);return 1;
}
NADSHF_EXPORT uint32_t NADSHF_Publish(uint64_t token,const NADSHF_Config* input) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockExclusive(&control_lock);}}unlock;
    if(!reserved||!token||token!=owned_token)return reject(TOKEN_MISMATCH);
    Policy next{};if(!config(input,next.c)){disarm();return 0;}
    if(!same_body(next.c,policy.c)){disarm();return reject(OWNER_MISMATCH);}
    if(!code(next.c)){disarm();return 0;}
    next.controller=policy.controller;next.descriptor=policy.descriptor;std::memcpy(next.descriptor_bytes,policy.descriptor_bytes,20);
    if(!dispatch(next.c,true)||!owner(next,false)){disarm();return reject(OWNER_MISMATCH);}
    // A successful publication never creates an unarmed gap between frames.
    // Readers finish against the previous complete policy before this commit.
    AcquireSRWLockExclusive(&policy_lock);
    if(!dispatch(next.c,true)||!owner(next,false)){
        armed.store(0,std::memory_order_release);ReleaseSRWLockExclusive(&policy_lock);return reject(OWNER_MISMATCH);
    }
    next.deadline=tick()+next.c.ttl_ms;policy=next;
    armed.store(1,std::memory_order_release);ReleaseSRWLockExclusive(&policy_lock);publications.fetch_add(1);last_error.store(OK);return 1;
}
NADSHF_EXPORT uint32_t NADSHF_Pause(uint64_t token) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockExclusive(&control_lock);}}unlock;
    if(!reserved||!token||token!=owned_token)return reject(TOKEN_MISMATCH);disarm();pauses.fetch_add(1);last_error.store(OK);return 1;
}
NADSHF_EXPORT uint32_t NADSHF_End(uint64_t token) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockExclusive(&control_lock);}}unlock;
    if(!token)return reject(TOKEN_MISMATCH);
    if(!reserved){if(token!=retired_token)return reject(TOKEN_MISMATCH);last_error.store(OK);return 1;}
    if(token!=owned_token)return reject(TOKEN_MISMATCH);disarm();
    if(!restore_slot()||in_flight.load(std::memory_order_acquire)){last_error.store(CLEANUP_PENDING);return 2;}
    reserved=false;retired_token=owned_token;owned_token=0;last_error.store(OK);return 1;
}
NADSHF_EXPORT uint32_t NADSHF_ReadStats(uint64_t token,NADSHF_Stats* result) {
    AcquireSRWLockShared(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockShared(&control_lock);}}unlock;
    if(reserved?(token!=owned_token):(token!=0))return reject(TOKEN_MISMATCH);
    NADSHF_Stats s{};if(!read(reinterpret_cast<uint64_t>(result),&s,sizeof s)||s.size!=sizeof s||s.abi!=1)return reject(INVALID_CONFIG);
    s={};s.size=sizeof s;s.abi=1;s.installed=installed.load();s.armed=armed.load();s.error=last_error.load();s.generation=owned_token;s.now_ms=tick();
    AcquireSRWLockShared(&policy_lock);
    s.effective_armed=reserved&&effective(policy,s.now_ms);s.now_ms=tick();s.body=policy.c.body;s.body_generation=static_cast<uint8_t>(policy.c.body>>22);
    s.deadline_ms=policy.deadline;s.body_object=policy.c.body_object;s.instance=policy.c.instance;s.graph=policy.c.graph;s.context=policy.c.context;s.camera=policy.c.camera;s.request=policy.c.request;
    ReleaseSRWLockShared(&policy_lock);
    s.seen=seen.load();s.forwarded=forwarded.load();s.suppressed_start=dropped_start.load();s.suppressed_end=dropped_end.load();s.rejected=rejected.load();s.publications=publications.load();s.pauses=pauses.load();s.in_flight=in_flight.load();s.last_caller=last_caller.load();s.last_event=last_event.load();
    SIZE_T n=0;return WriteProcessMemory(GetCurrentProcess(),result,&s,sizeof s,&n)!=0&&n==sizeof s;
}
NADSHF_EXPORT uint32_t NADSHF_Error(void){return last_error.load(std::memory_order_acquire);}
NADSHF_EXPORT uint32_t NADSHF_LastError(void){return NADSHF_Error();}
#if !defined(NADSHF_FIXTURE)
// All globals are constant-initialized POD/atomics. A CRT startup is neither
// required nor used: MinGW's generic pseudo-relocator can change protections.
extern "C" BOOL WINAPI NADSHF_DllMain(HINSTANCE,DWORD reason,LPVOID){
    // The sole function-local initializer is native_memory.h's Wine identity.
    // Warm it under the loader's serialized PROCESS_ATTACH before any export
    // is reachable. The DLL build disables C++ lazy guard-runtime generation.
    if(reason==DLL_PROCESS_ATTACH){MEMORY_BASIC_INFORMATION r{};r.Type=MEM_MAPPED;(void)pe_section_mapping(r);}
    return TRUE;
}
#endif
