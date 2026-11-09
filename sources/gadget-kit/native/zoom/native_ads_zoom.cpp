// Native optic selection policy for the owned True First Person camera only.
// MinHook is retained/pinned; disabling the policy leaves its trampoline forwarding.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <intrin.h>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <cmath>
#include "../first_person/native_memory.h"
#include "native_ads_zoom.h"
#if !defined(NADZ_FIXTURE)
#include "vendor/minhook/include/MinHook.h"
#endif
using Selector=uint32_t(*)(uint32_t,uint32_t);
using Event=void(*)(void*,void*);
using Zoom=float(*)(void*,uint32_t);
static SRWLOCK control_lock=SRWLOCK_INIT,policy_lock=SRWLOCK_INIT;
static std::atomic<Selector> original{nullptr};
static std::atomic<uint32_t> installed{0},armed{0},reserved{0},last_error{0};
static std::atomic<uint64_t> seen{0},forwarded{0},replaced{0},immediate_applies{0},binds{0},ads_forwarded{0};
static std::atomic<uint64_t> policy_epoch{0};
static uint64_t hook_game=0,generation_counter=0,owned_generation=0,retired_generation=0;
static uint8_t hooked_bytes[32]{};
static bool install_failed=false;
static constexpr uint32_t SELECTOR=0x1608bd0,EVENT=0x110aa20,ZOOM=0x764e90;
static constexpr float RAD_PER_DEG=.01745329251994329577f;
enum Error:uint32_t {OK=0,INVALID_CONFIG=1,BUSY=2,READ_FAILED=3,IMAGE_MISMATCH=4,CODE_MISMATCH=5,
 API_MISMATCH=6,OWNER_MISMATCH=7,PIN_FAILED=9,CLEANUP_PENDING=13,SOURCE_INVALID=14,TOKEN_MISMATCH=17,
 HOOK_INITIALIZE=0x10000,HOOK_CREATE=0x20000,HOOK_QUEUE=0x30000,HOOK_APPLY=0x40000};
struct Policy {
 NADZ_Config c{};uint64_t controller=0,descriptor=0,registry=0,units=0,generations=0,body_object=0;
 uint8_t descriptor_bytes[20]{};bool shoulder_aim=false,full_ads=false,safe=false;
 bool normalized=false;float last_native=0,last_applied=0,source_degrees=0;
};
static Policy policy;
#if defined(NADZ_FIXTURE)
static Selector fixture_selector=nullptr;static Event fixture_event=nullptr;static Zoom fixture_zoom=nullptr;
static uint64_t fixture_caller=0;static uint32_t fixture_hook_failure=0;
static uint32_t fixture_write_calls=0,fixture_fail_write_at=0;
#endif
static bool read(uint64_t at,void* out,size_t length) {
    if(at<65536 || at>=0x800000000000ULL || length>1024 || at+length>=0x800000000000ULL)return false;
    SIZE_T actual=0;return ReadProcessMemory(GetCurrentProcess(),reinterpret_cast<const void*>(at),out,length,&actual)!=0 && actual==length;
}
template<class T> static bool value(uint64_t at,T& out) {return read(at,&out,sizeof out);}
static bool pointer(uint64_t at,uint64_t& out) {return value(at,out) && out>=65536 && out<0x800000000000ULL;}
static void error(uint32_t code) {last_error.store(code,std::memory_order_release);}
static uint32_t reject(uint32_t code) {error(code);return 0;}
static bool image(uint64_t base,uint32_t stamp,uint32_t length) {
    IMAGE_DOS_HEADER dos{};IMAGE_NT_HEADERS64 nt{};
    return read(base,&dos,sizeof dos) && dos.e_magic==IMAGE_DOS_SIGNATURE && dos.e_lfanew>=64 && dos.e_lfanew<=4096
        && read(base+dos.e_lfanew,&nt,sizeof nt) && nt.Signature==IMAGE_NT_SIGNATURE
        && nt.FileHeader.Machine==IMAGE_FILE_MACHINE_AMD64 && nt.OptionalHeader.Magic==IMAGE_NT_OPTIONAL_HDR64_MAGIC
        && nt.FileHeader.TimeDateStamp==stamp && nt.OptionalHeader.SizeOfImage==length;
}
static bool bytes(uint64_t at,const char* hex) {
    uint8_t actual[64]{};const size_t count=std::strlen(hex)/2;
    if(!count || count>sizeof actual || !read(at,actual,count))return false;
    for(size_t i=0;i<count;++i) {
        auto digit=[](char c)->uint8_t{return static_cast<uint8_t>(c<='9'?c-'0':c-'a'+10);};
        if(actual[i]!=static_cast<uint8_t>((digit(hex[i*2])<<4)|digit(hex[i*2+1])))return false;
    }return true;
}
static bool executable(uint64_t at) {
    MEMORY_BASIC_INFORMATION r{};
    if(VirtualQuery(reinterpret_cast<const void*>(at),&r,sizeof r)!=sizeof r || r.State!=MEM_COMMIT || !pe_section_mapping(r))return false;
    return r.Protect==PAGE_EXECUTE_READ || r.Protect==PAGE_EXECUTE_READWRITE || r.Protect==PAGE_EXECUTE_WRITECOPY;
}
static bool owner(Policy& p,bool capture) {
    const auto& c=p.c;uint64_t ctx=0,camera=0,avatar_owner=0,controller=0,descriptor=0,registry=0,units=0,generations=0,object=0;
    uint32_t count=0,capacity=0;uint8_t d[20]{},flags[24]{},controls[6]{},generation=0,confirmed=0;uint64_t confirmed_object=0;
    const uint32_t index=c.body&0x3fffff;
    if(!pointer(c.game+0x2e287d0,ctx) || ctx!=c.context || !pointer(ctx,camera) || camera!=c.camera
        || !pointer(c.game+0x2ce1ee0,avatar_owner) || avatar_owner!=c.avatar_owner
        || !pointer(c.game+0x2e381a8,controller) || !read(controller,controls,6)
        || !value(avatar_owner+0x6C,count) || count==0 || count>8 || c.avatar_index>=count
        || !pointer(avatar_owner+0x110+static_cast<uint64_t>(c.avatar_index)*8,descriptor) || !read(descriptor,d,20)
        || !read(avatar_owner+0x53e888+static_cast<uint64_t>(c.avatar_index)*0x1240,flags,24)
        || !pointer(c.exe+0x1ab76f8,registry) || !value(registry+0x98,capacity) || capacity==0 || capacity>0x400000 || index>=capacity
        || !pointer(registry+0xA0,generations) || !value(generations+index,generation) || generation!=static_cast<uint8_t>(c.body>>22)
        || !pointer(registry+0x88,units) || !pointer(units+static_cast<uint64_t>(index)*8,object)
        || !value(generations+index,confirmed) || confirmed!=generation
        || !pointer(units+static_cast<uint64_t>(index)*8,confirmed_object) || confirmed_object!=object)return false;
    uint32_t avatar=0,body=0,mask=0;std::memcpy(&avatar,d+8,4);std::memcpy(&body,d+12,4);std::memcpy(&mask,controls,4);
    if(avatar!=c.avatar || body!=c.body)return false;
    if(capture) {
        p.controller=controller;p.descriptor=descriptor;p.registry=registry;p.units=units;p.generations=generations;p.body_object=object;
        std::memcpy(p.descriptor_bytes,d,20);
    } else if(controller!=p.controller || descriptor!=p.descriptor || registry!=p.registry || units!=p.units
        || generations!=p.generations || object!=p.body_object || std::memcmp(d,p.descriptor_bytes,20)!=0)return false;
    // Current normal aim is the agreeing82/125 pair, independent of legacy48.
    // Full native ADS always wins, even while those shoulder flags linger.
    p.full_ads=controls[4]!=0;
    p.shoulder_aim=!p.full_ads && (flags[10]&4)!=0 && (flags[15]&32)!=0;
    p.safe=(mask==0 || mask==2) && controls[5]==0 && (flags[14]&4)==0;
    return true;
}
static bool request_matches(const Policy& p,bool allow_normal=false) {
    uint32_t head=0,tail=0,r[4]{};
    if(!value(p.c.context+0x1F8,head) || !value(p.c.context+0x1FC,tail) || head>=32 || tail>=32)return false;
    const uint64_t at=head==tail?p.c.context+0x1F00:p.c.context+0x200+((tail+31)%32)*0xE8;
    if(at!=p.c.request || !read(at,r,16) || r[1]!=p.c.avatar)return false;
    if(allow_normal && (r[0]&0xffff)==4)return true;
    return head!=tail && (r[0]&0xffff)==6 && r[2]==p.c.weapon && r[3]==p.c.body;
}
static bool fingerprints(const NADZ_Config& c) {
    if(!image(c.game,0x6ae0e5ff,0x3382000) || !image(c.exe,0x6ae0964a,0x29fe000))return reject(IMAGE_MISMATCH)!=0;
    if(installed.load()) {
        uint8_t actual[32]{};
        if(c.game!=hook_game || !read(c.game+SELECTOR,actual,sizeof actual)
            || std::memcmp(actual,hooked_bytes,sizeof actual))return reject(CODE_MISMATCH)!=0;
    } else if(!bytes(c.game+SELECTOR,"40534883ec208bdae853ffffff84c00f84ac0000004c8b1db4926d014533c03b0d"))return reject(CODE_MISMATCH)!=0;
    // Both exact selector call sites, magnification lookup, zoom event and
    // sensitivity's request-lens ratio are independently pinned to this build.
    if(!bytes(c.game+0x764f29,"e8a23cea0085c07434")
        || !bytes(c.game+0x110ac6f,"e85cdf4f00418b55083bc38bf8410f44fee80ba265ff")
        || !bytes(c.game+ZOOM,"48895c24084889742410574883ec203b152ba26d028bda")
        || !bytes(c.game+EVENT,"40554881ec30010000488b05e0a53a014833c448898424d0000000488bea")
        || !bytes(c.game+0x1118731,"f3410f109784000000f30f59155ee81201f30f5e9088c40a00"))return reject(CODE_MISMATCH)!=0;
    return true;
}
static bool config(const NADZ_Config* input,NADZ_Config& c) {
    if(!read(reinterpret_cast<uint64_t>(input),&c,sizeof c) || c.size!=sizeof c || c.abi!=1 || c.reserved
        || c.avatar_index>=8 || !c.avatar || c.avatar==UINT32_MAX || !c.body || c.body==UINT32_MAX
        || !c.weapon || c.weapon==UINT32_MAX || c.context<65536 || c.camera<65536 || c.request<65536)
        return reject(INVALID_CONFIG)!=0;
    return true;
}
static bool pin(const void* at) {
    HMODULE module=nullptr;return GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
        reinterpret_cast<LPCWSTR>(at),&module)!=0;
}
static uint32_t selector_hook(uint32_t weapon,uint32_t type) {
    const uint64_t epoch=policy_epoch.load(std::memory_order_acquire);
    const uint32_t native=original.load(std::memory_order_acquire)(weapon,type);
    seen.fetch_add(1,std::memory_order_relaxed);
    uint64_t caller=reinterpret_cast<uint64_t>(_ReturnAddress());
#if defined(NADZ_FIXTURE)
    caller=fixture_caller;
#endif
    if(!armed.load(std::memory_order_acquire) || type!=1 || native>2) {
        forwarded.fetch_add(1,std::memory_order_relaxed);return native;
    }
    AcquireSRWLockExclusive(&policy_lock);
    struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&policy_lock);}} unlock;
    // Global selector callers, other weapons and non-optic parameter types
    // have exact original results. The actual stored selection is untouched.
    if(armed.load(std::memory_order_acquire) && epoch==policy_epoch.load(std::memory_order_acquire) && weapon==policy.c.weapon
        && (caller==policy.c.game+0x764f2e || caller==policy.c.game+0x110ac74)) {
        if(!owner(policy,false)) {armed.store(0,std::memory_order_release);error(OWNER_MISMATCH);}
        else if(request_matches(policy) && policy.safe) {
            if(policy.full_ads)ads_forwarded.fetch_add(1,std::memory_order_relaxed);
            else {replaced.fetch_add(1,std::memory_order_relaxed);return 0;}
        }
    }
    forwarded.fetch_add(1,std::memory_order_relaxed);return native;
}
static bool install(const NADZ_Config& c) {
    if(installed.load())return c.game==hook_game;
    if(install_failed)return reject(API_MISMATCH)!=0;
    if(!pin(reinterpret_cast<const void*>(&selector_hook)))return reject(PIN_FAILED)!=0;
#if defined(NADZ_FIXTURE)
    if(fixture_hook_failure) {error(fixture_hook_failure);return false;}
    if(!fixture_selector || !fixture_event || !fixture_zoom)return reject(API_MISMATCH)!=0;
    original.store(fixture_selector,std::memory_order_release);
#else
    if(!pin(reinterpret_cast<void*>(c.game)) || !pin(reinterpret_cast<void*>(c.exe)))return reject(PIN_FAILED)!=0;
    const auto target=reinterpret_cast<void*>(c.game+SELECTOR);
    if(!executable(c.game+SELECTOR) || !executable(c.game+EVENT) || !executable(c.game+ZOOM))return reject(CODE_MISMATCH)!=0;
    MH_STATUS result=MH_Initialize();
    if(result!=MH_OK && result!=MH_ERROR_ALREADY_INITIALIZED)return reject(HOOK_INITIALIZE+result)!=0;
    Selector trampoline=nullptr;
    result=MH_CreateHook(target,reinterpret_cast<void*>(&selector_hook),reinterpret_cast<void**>(&trampoline));
    if(result!=MH_OK || !trampoline) {install_failed=true;return reject(HOOK_CREATE+result)!=0;}
    original.store(trampoline,std::memory_order_release);
    // CreateHook leaves the original untouched. Recheck before the queued
    // thread transaction; never release a potentially reached trampoline.
    if(!fingerprints(c)) {install_failed=true;return false;}
    result=MH_QueueEnableHook(target);
    if(result!=MH_OK) {install_failed=true;return reject(HOOK_QUEUE+result)!=0;}
    result=MH_ApplyQueued();
    if(result!=MH_OK) {install_failed=true;return reject(HOOK_APPLY+result)!=0;}
#endif
    hook_game=c.game;
    if(!read(c.game+SELECTOR,hooked_bytes,sizeof hooked_bytes)) {install_failed=true;return reject(READ_FAILED)!=0;}
    installed.store(1,std::memory_order_release);return true;
}
static void drain() {AcquireSRWLockExclusive(&policy_lock);ReleaseSRWLockExclusive(&policy_lock);}
static Policy snapshot() {
    AcquireSRWLockExclusive(&policy_lock);const Policy result=policy;ReleaseSRWLockExclusive(&policy_lock);return result;
}
// control_lock is held; no policy_lock may be held across native engine calls,
// because the event and magnification getter call our selector synchronously.
static bool refresh(Policy& p,bool normalized) {
    if(!fingerprints(p.c))return false;
    if(!owner(p,false) || !request_matches(p) || !p.safe)return false;
    uint64_t settings=0;float degrees=0;
    if(!pointer(p.c.game+0x2ce1508,settings) || !value(settings+0xac488,degrees)
        || !std::isfinite(degrees) || degrees<1 || degrees>179)return reject(SOURCE_INVALID)!=0;
    const uint32_t native_selection=original.load(std::memory_order_acquire)(p.c.weapon,1);
    // UINT32_MAX is vanilla's absent optic-selection parameter. It is a
    // clean no-op capability, not a failure of the first-person camera.
    if(native_selection==UINT32_MAX) {p.normalized=normalized;return true;}
    if(native_selection>2)return reject(SOURCE_INVALID)!=0;
#if defined(NADZ_FIXTURE)
    const Event event=fixture_event;const Zoom zoom=fixture_zoom;
#else
    const auto event=reinterpret_cast<Event>(p.c.game+EVENT);
    const auto zoom=reinterpret_cast<Zoom>(p.c.game+ZOOM);
#endif
    // Reserve uncertain cleanup BEFORE the first native mutation. A failed
    // event/read/partial write still requires End to rebuild real zoom state.
    AcquireSRWLockExclusive(&policy_lock);policy.normalized=true;ReleaseSRWLockExclusive(&policy_lock);
    event(reinterpret_cast<void*>(p.c.context),reinterpret_cast<void*>(p.c.request));
    const float magnification=zoom(reinterpret_cast<void*>(p.c.context),p.c.weapon);
    const float lens=(degrees/magnification)*RAD_PER_DEG;
    float depth=0,native=0;
    if(!std::isfinite(magnification) || magnification<.1f || magnification>100
        || !std::isfinite(lens) || lens<.0002f || lens>2.96f
        || !owner(p,false) || !request_matches(p) || !p.safe
        || !value(p.c.request+0x90,depth) || !std::isfinite(depth) || depth<0 || depth>4
        || !value(p.c.request+0x84,native))return reject(SOURCE_INVALID)!=0;
    // The event recalculates authored depth but leaves the current lens at the
    // previous zoom. Snap only this owned request's lens and prior endpoints;
    // the native next-frame input ratio and rig solve now share one baseline.
    const uint64_t addresses[3]={p.c.request+0x84,p.c.request+0x9c,p.c.request+0xa0};
    const float values[3]={lens,depth,lens};
    for(unsigned i=0;i<3;++i) {
#if defined(NADZ_FIXTURE)
        if(++fixture_write_calls==fixture_fail_write_at)return reject(CLEANUP_PENDING)!=0;
#endif
        SIZE_T actual=0;if(!WriteProcessMemory(GetCurrentProcess(),reinterpret_cast<void*>(addresses[i]),values+i,4,&actual)
            || actual!=4)return reject(CLEANUP_PENDING)!=0;
    }
    p.normalized=normalized;p.last_native=native;p.last_applied=lens;p.source_degrees=degrees;
    immediate_applies.fetch_add(1,std::memory_order_relaxed);return true;
}
static bool update_locked() {
    if(!armed.load(std::memory_order_acquire))return reject(last_error.load()?last_error.load():API_MISMATCH)!=0;
    Policy next=snapshot();
    if(!owner(next,false)) {armed.store(0,std::memory_order_release);drain();return reject(OWNER_MISMATCH)!=0;}
    if(!fingerprints(next.c)) {armed.store(0,std::memory_order_release);drain();return false;}
    if(!request_matches(next) || !next.safe)return true;
    const bool desired=!next.full_ads;
    if(next.normalized==desired)return true;
    // The callback checks fresh full-ADS flags, independently of Lua polling.
    armed.store(1,std::memory_order_release);
    if(!refresh(next,desired)) {armed.store(0,std::memory_order_release);drain();return false;}
    AcquireSRWLockExclusive(&policy_lock);policy=next;ReleaseSRWLockExclusive(&policy_lock);
    return true;
}
static bool write_generation(uint64_t* output,uint64_t value_) {
    SIZE_T count=0;return WriteProcessMemory(GetCurrentProcess(),output,&value_,8,&count)!=0 && count==8;
}
NADZ_EXPORT uint32_t NADZ_Validate(const NADZ_Config* input) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    NADZ_Config c{};if(!config(input,c))return 0;if(reserved.load())return reject(BUSY);
    Policy next{};next.c=c;
    if(!owner(next,true) || !next.safe || !request_matches(next,true))return reject(OWNER_MISMATCH);
    if(!fingerprints(c))return 0;error(OK);return 1;
}
NADZ_EXPORT uint32_t NADZ_Begin(const NADZ_Config* input,uint64_t* output) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(!write_generation(output,0))return reject(INVALID_CONFIG);
    NADZ_Config c{};if(!config(input,c))return 0;if(reserved.load())return reject(BUSY);
    Policy next{};next.c=c;
    if(!owner(next,true) || !next.safe || !request_matches(next))return reject(OWNER_MISMATCH);
    if(!fingerprints(c) || !install(c))return 0;
    if(++generation_counter==0)++generation_counter;
    if(!write_generation(output,generation_counter))return reject(INVALID_CONFIG);
    owned_generation=generation_counter;reserved.store(1,std::memory_order_release);
    policy_epoch.fetch_add(1,std::memory_order_acq_rel);
    seen.store(0);forwarded.store(0);replaced.store(0);immediate_applies.store(0);binds.store(0);ads_forwarded.store(0);
    // Assign before arming: the native refresh re-enters the selector hook.
    AcquireSRWLockExclusive(&policy_lock);policy=next;ReleaseSRWLockExclusive(&policy_lock);
    armed.store(1,std::memory_order_release);
    if(!refresh(next,!next.full_ads)) {armed.store(0,std::memory_order_release);drain();return 2;}
    AcquireSRWLockExclusive(&policy_lock);policy=next;ReleaseSRWLockExclusive(&policy_lock);
    error(OK);return 1;
}
NADZ_EXPORT uint32_t NADZ_Bind(uint64_t generation,const NADZ_Config* input) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(!reserved.load() || !generation || generation!=owned_generation)return reject(TOKEN_MISMATCH);
    NADZ_Config c{};if(!config(input,c))return 0;
    Policy next{};next.c=c;
    const Policy current=snapshot();
    if(c.game!=current.c.game || c.exe!=current.c.exe || c.context!=current.c.context || c.camera!=current.c.camera
        || c.avatar_owner!=current.c.avatar_owner || c.avatar_index!=current.c.avatar_index || c.avatar!=current.c.avatar
        || c.body!=current.c.body)return reject(OWNER_MISMATCH);
    if(!owner(next,true) || !next.safe || !request_matches(next))return reject(OWNER_MISMATCH);
    if(!fingerprints(c))return 0;
    if(c.request==current.c.request && c.weapon==current.c.weapon) {if(!update_locked())return 0;error(OK);return 1;}
    armed.store(0,std::memory_order_release);drain();
    policy_epoch.fetch_add(1,std::memory_order_acq_rel);
    Policy previous=snapshot();
    if(previous.normalized && owner(previous,false) && request_matches(previous) && previous.safe
        && !refresh(previous,false))return 0;
    AcquireSRWLockExclusive(&policy_lock);policy=next;ReleaseSRWLockExclusive(&policy_lock);
    armed.store(1,std::memory_order_release);
    if(!refresh(next,!next.full_ads)) {armed.store(0,std::memory_order_release);drain();return 0;}
    AcquireSRWLockExclusive(&policy_lock);policy=next;ReleaseSRWLockExclusive(&policy_lock);
    binds.fetch_add(1,std::memory_order_relaxed);error(OK);return 1;
}
NADZ_EXPORT uint32_t NADZ_Update(uint64_t generation) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(!reserved.load() || !generation || generation!=owned_generation)return reject(TOKEN_MISMATCH);
    if(!update_locked())return 0;error(OK);return 1;
}
NADZ_EXPORT uint32_t NADZ_End(uint64_t generation) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(!generation || (reserved.load()?generation!=owned_generation:generation!=retired_generation))return reject(TOKEN_MISMATCH);
    if(!reserved.load()) {error(OK);return 1;}
    armed.store(0,std::memory_order_release);drain();
    policy_epoch.fetch_add(1,std::memory_order_acq_rel);
    Policy previous=snapshot();
    if(previous.normalized && owner(previous,false) && request_matches(previous)) {
        if(!previous.safe)return reject(CLEANUP_PENDING);
        if(!refresh(previous,false))return 0;
    }
    AcquireSRWLockExclusive(&policy_lock);policy.normalized=false;ReleaseSRWLockExclusive(&policy_lock);
    retired_generation=owned_generation;owned_generation=0;reserved.store(0,std::memory_order_release);error(OK);return 1;
}
NADZ_EXPORT uint32_t NADZ_ReadStats(uint64_t generation,NADZ_Stats* output) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(reserved.load()?(!generation || generation!=owned_generation):generation!=0)return reject(TOKEN_MISMATCH);
    NADZ_Stats s{};if(!read(reinterpret_cast<uint64_t>(output),&s,sizeof s) || s.size!=sizeof s || s.abi!=1)return reject(INVALID_CONFIG);
    s.installed=installed.load();s.armed=armed.load();s.error=last_error.load();s.reserved=0;
    s.seen=seen.load();s.forwarded=forwarded.load();s.replaced=replaced.load();s.immediate_applies=immediate_applies.load();
    s.binds=binds.load();s.ads_forwarded=ads_forwarded.load();
    AcquireSRWLockExclusive(&policy_lock);s.last_native=policy.last_native;s.last_applied=policy.last_applied;
    s.source_degrees=policy.source_degrees;ReleaseSRWLockExclusive(&policy_lock);s.padding=0;
    SIZE_T count=0;return WriteProcessMemory(GetCurrentProcess(),output,&s,sizeof s,&count)!=0 && count==sizeof s;
}
NADZ_EXPORT uint32_t NADZ_Error(void) {return last_error.load(std::memory_order_acquire);}
