// First-person near clip: one generation-owned CameraAPI slot; no camera
// transforms, settings, executable writes or protection changes.
// game.dll 6AE0E5FF sets the gameplay camera's near distance to its .rdata
// 0.05 (0x2245EEC) through CameraAPI+0x68 from several call sites (0x110DCAB,
// 0x11107AF, 0x1107B90, 0x1144971 load that constant). Only a game.dll caller
// setting exactly that value on the owned camera, with the first-person
// request (kind 6) current and full ADS released, receives the configured
// distance instead. Every distinct caller is counted for diagnosis.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <intrin.h>
#include "../first_person/native_memory.h"
#include <atomic>
#include <cstdint>
#include <cstring>
#include <cmath>
#include "native_ads_near.h"
using Setter=void (*)(void*,float);
static SRWLOCK control_lock=SRWLOCK_INIT,policy_lock=SRWLOCK_INIT;
static std::atomic<Setter> original{nullptr};
static std::atomic<uint32_t> installed{0},armed{0},reserved{0},last_error{0};
static std::atomic<uint64_t> seen{0},forwarded{0},replaced{0},ads_forwarded{0},aim_applied{0},other_kind{0},text_low{0},text_high{0};
static std::atomic<float> hip_meters{0},aim_meters{0},last_native{0},last_applied{0};
static_assert(std::atomic<float>::is_always_lock_free,"Near clip requires lock-free floats");
static uint64_t slot=0,slot_image=0,generation_counter=0,owned_generation=0,retired_generation=0;
static bool possible=false;
static constexpr uint32_t SETTER=0x2dcfa0,GETTER=0x2dcf80,SITE=0x110dc8c,NATIVE_NEAR=0x2245eec,TEXT=0x1000,TEXT_END=0x1f99000;
static constexpr uint32_t NATIVE_BITS=0x3d4ccccd;
static constexpr float MAX_METERS=1.0f;
enum Error:uint32_t { OK=0,INVALID_CONFIG=1,BUSY=2,READ_FAILED=3,IMAGE_MISMATCH=4,
    CODE_MISMATCH=5,API_MISMATCH=6,OWNER_MISMATCH=7,PIN_FAILED=9,
    SLOT_NOT_WRITABLE=10,CAS_MISMATCH=11,CAS_FAULT=12,CLEANUP_PENDING=13,TOKEN_MISMATCH=17 };
struct Policy {uint64_t game=0,exe=0,context=0,camera=0,avatar_owner=0;uint32_t avatar_index=0;};
static Policy policy;
struct SiteRow {std::atomic<uint64_t> address{0},calls{0},owned{0};std::atomic<float> value{0};};
static SiteRow site_rows[16];
static std::atomic<uint32_t> site_overflow{0};
static void note_site(uint64_t ret,bool owned,float value) {
    for(auto& row:site_rows) {
        uint64_t current=row.address.load(std::memory_order_acquire);
        if(current==0) {
            uint64_t expected=0;
            if(row.address.compare_exchange_strong(expected,ret,std::memory_order_acq_rel))current=ret;else current=expected;
        }
        if(current==ret) {
            row.calls.fetch_add(1,std::memory_order_relaxed);if(owned)row.owned.fetch_add(1,std::memory_order_relaxed);
            row.value.store(value,std::memory_order_relaxed);return;
        }
    }
    site_overflow.fetch_add(1,std::memory_order_relaxed);
}
#if defined(NADSN_FIXTURE)
static Setter fixture_target=nullptr;
static uint32_t fixture_cas_calls=0,fixture_cas_fail_at=0,fixture_foreign_cas_at=0;
static uint64_t fixture_foreign_value=0;
static bool fixture_slot_readonly=false;
#endif
static bool read(uint64_t at,void* out,size_t length) {
    if(at<65536 || at>=0x800000000000ULL || length>1024 || at+length>=0x800000000000ULL)return false;
    SIZE_T actual=0;return ReadProcessMemory(GetCurrentProcess(),reinterpret_cast<const void*>(at),out,length,&actual)!=0 && actual==length;
}
template<class T> static bool value(uint64_t at,T& out) {return read(at,&out,sizeof out);}
static bool pointer(uint64_t at,uint64_t& out) {return value(at,out) && out>=65536 && out<0x800000000000ULL;}
static void error(uint32_t code) {last_error.store(code,std::memory_order_release);}
static uint32_t reject(uint32_t code) {error(code);return 0;}
static bool meters(float v) {return std::isfinite(v) && v>=0 && v<=MAX_METERS;}
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
enum class View {LOST,OTHER,ADS,SHOULDER,HIP};
// LOST: the owned camera, context or avatar row is no longer current.
// OTHER: not the first-person request (kind 6) or its state is unreadable.
static View observe(const Policy& p) {
    uint64_t ctx=0,camera=0,owner=0,controller=0;uint32_t count=0,head=0,tail=0,kind=0;
    uint8_t controls[6]{},flags[24]{};
    if(!pointer(p.game+0x2e287d0,ctx) || ctx!=p.context || !pointer(ctx,camera) || camera!=p.camera
        || !pointer(p.game+0x2ce1ee0,owner) || owner!=p.avatar_owner
        || !value(owner+0x6C,count) || count==0 || count>8 || p.avatar_index>=count)return View::LOST;
    if(!value(ctx+0x1F8,head) || !value(ctx+0x1FC,tail) || head>=32 || tail>=32)return View::OTHER;
    const uint64_t at=head==tail?ctx+0x1F00:ctx+0x200+((tail+31)%32)*0xE8;
    if(!value(at,kind) || (kind&0xffff)!=6)return View::OTHER;
    if(!pointer(p.game+0x2e381a8,controller) || !read(controller,controls,6))return View::OTHER;
    if(controls[4]!=0)return View::ADS;
    if(!read(owner+0x53e888+static_cast<uint64_t>(p.avatar_index)*0x1240,flags,24))return View::OTHER;
    // Current normal aim is the agreeing82/125 pair, as in the FOV policy.
    return (flags[10]&4)!=0 && (flags[15]&32)!=0?View::SHOULDER:View::HIP;
}
static bool writable_slot(uint64_t at,uint64_t exe) {
    if((at&7)!=0)return false;
#if defined(NADSN_FIXTURE)
    if(fixture_slot_readonly)return false;
    (void)exe;
#endif
    MEMORY_BASIC_INFORMATION r{};
    if(VirtualQuery(reinterpret_cast<const void*>(at),&r,sizeof r)!=sizeof r || r.State!=MEM_COMMIT || !writable_pe_protection(r.Protect)
        || at+8>reinterpret_cast<uint64_t>(r.BaseAddress)+r.RegionSize)return false;
#if !defined(NADSN_FIXTURE)
    return pe_section_mapping(r) && reinterpret_cast<uint64_t>(r.AllocationBase)==exe;
#else
    return r.Type==MEM_PRIVATE;
#endif
}
static bool cas(uint64_t expected,uint64_t desired,uint64_t& observed) {
#if defined(NADSN_FIXTURE)
    if(++fixture_cas_calls==fixture_cas_fail_at)return false;
    if(fixture_cas_calls==fixture_foreign_cas_at)InterlockedExchangePointer(reinterpret_cast<PVOID volatile*>(slot),reinterpret_cast<void*>(fixture_foreign_value));
#endif
    __try {
        observed=reinterpret_cast<uint64_t>(InterlockedCompareExchangePointer(reinterpret_cast<PVOID volatile*>(slot),
            reinterpret_cast<void*>(desired),reinterpret_cast<void*>(expected)));return true;
    } __except(EXCEPTION_EXECUTE_HANDLER) {return false;}
}
static bool binary_contract(const NADSN_Config& c) {
    if(!image(c.game,0x6ae0e5ff,0x3382000) || !image(c.exe,0x6ae0964a,0x29fe000))return reject(IMAGE_MISMATCH)!=0;
    // mov rax,[api root]; movss xmm1,[0.05]; mov rcx,[r15]; movaps; mov rdx,[rax+20]; call [rdx+68]
    if(!bytes(c.game+SITE,"488b053538bd01f30f100d51821301498b0f440f29bc2490010000488b5020ff5268")
        || !bytes(c.game+NATIVE_NEAR,"cdcc4c3d") || !bytes(c.exe+SETTER,"f30f114928e9966b1f00")
        || !bytes(c.exe+GETTER,"f30f104128c3"))return reject(CODE_MISMATCH)!=0;
    return true;
}
static bool contract(const NADSN_Config& c,Setter& setter,uint64_t& address) {
    if(!binary_contract(c))return false;
    uint64_t root=0,api=0,target=0,getter=0;
    if(!pointer(c.game+0x2ce14c8,root) || !pointer(root+0x20,api) || !value(api+0x68,target)
        || !pointer(api+0x58,getter) || getter!=c.exe+GETTER)return reject(API_MISMATCH)!=0;
    address=api+0x68;
    if(!writable_slot(address,c.exe))return reject(SLOT_NOT_WRITABLE)!=0;
#if defined(NADSN_FIXTURE)
    if(target!=reinterpret_cast<uint64_t>(fixture_target))return reject(API_MISMATCH)!=0;
#else
    if(target!=c.exe+SETTER || !executable(getter))return reject(API_MISMATCH)!=0;
#endif
    if(!executable(target))return reject(API_MISMATCH)!=0;
    setter=reinterpret_cast<Setter>(target);return true;
}
static uint64_t callback();
static bool dispatch_owned(const Policy& p) {
    uint64_t root=0,api=0,target=0,getter=0;
    return pointer(p.game+0x2ce14c8,root) && pointer(root+0x20,api) && api+0x68==slot
        && pointer(api+0x58,getter) && getter==p.exe+GETTER && value(slot,target) && target==callback();
}
static void setter_hook(void* camera,float native) {
    seen.fetch_add(1,std::memory_order_relaxed);
    const uint64_t ret=reinterpret_cast<uint64_t>(_ReturnAddress());
    float applied=native;bool owned=false;
    if(armed.load(std::memory_order_acquire)) {
        AcquireSRWLockShared(&policy_lock);
        uint32_t bits=0;std::memcpy(&bits,&native,4);
        owned=armed.load(std::memory_order_acquire) && reinterpret_cast<uint64_t>(camera)==policy.camera;
        if(owned && bits==NATIVE_BITS && ret>=text_low.load(std::memory_order_relaxed) && ret<text_high.load(std::memory_order_relaxed)) {
            const View view=observe(policy);
            if(view==View::LOST) {armed.store(0,std::memory_order_release);error(OWNER_MISMATCH);}
            else if(view==View::OTHER)other_kind.fetch_add(1,std::memory_order_relaxed);
            else if(view==View::ADS)ads_forwarded.fetch_add(1,std::memory_order_relaxed);
            else {
                const bool aim=view==View::SHOULDER;
                const float wanted=(aim?aim_meters:hip_meters).load(std::memory_order_relaxed);
                if(meters(wanted) && wanted>native) {
                    applied=wanted;replaced.fetch_add(1,std::memory_order_relaxed);
                    if(aim)aim_applied.fetch_add(1,std::memory_order_relaxed);
                }
            }
            last_native.store(native,std::memory_order_relaxed);last_applied.store(applied,std::memory_order_relaxed);
        }
        ReleaseSRWLockShared(&policy_lock);
    }
    note_site(ret,owned,native);
    forwarded.fetch_add(1,std::memory_order_relaxed);original.load(std::memory_order_acquire)(camera,applied);
}
static uint64_t callback() {return reinterpret_cast<uint64_t>(setter_hook);}
static bool pin(const void* address) {
    HMODULE module=nullptr;return GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
        reinterpret_cast<LPCWSTR>(address),&module)!=0;
}
static bool restore_slot() {
    if(possible) {
        uint64_t current=0;if(!value(slot,current))return false;
        if(current==callback()) {
            if(!writable_slot(slot,slot_image))return false;
            uint64_t observed=0;if(!cas(callback(),reinterpret_cast<uint64_t>(original.load()),observed))return false;
        }
        possible=false;
    }
    installed.store(0,std::memory_order_release);retired_generation=owned_generation;owned_generation=0;
    reserved.store(0,std::memory_order_release);return true;
}
static bool output_generation(uint64_t* output,uint64_t generation) {
    SIZE_T actual=0;return WriteProcessMemory(GetCurrentProcess(),output,&generation,8,&actual)!=0 && actual==8;
}
// Disarm, drain in-flight callbacks, then put back only our own pointer.
static bool drain_and_restore() {
    armed.store(0,std::memory_order_release);
    AcquireSRWLockExclusive(&policy_lock);ReleaseSRWLockExclusive(&policy_lock);
    return restore_slot();
}
static uint32_t failed_begin(uint32_t cause,uint64_t* output) {
    if(!drain_and_restore()) {error(CLEANUP_PENDING);return 2;}
    output_generation(output,0);return reject(cause);
}
static bool config(const NADSN_Config* input,NADSN_Config& c) {
    if(!read(reinterpret_cast<uint64_t>(input),&c,sizeof c) || c.size!=sizeof c || c.abi!=1 || c.reserved!=0 || c.reserved2!=0
        || c.avatar_index>=8 || c.context<65536 || c.camera<65536 || c.avatar_owner<65536
        || !meters(c.hip) || !meters(c.aim))return reject(INVALID_CONFIG)!=0;
    return true;
}
NADSN_EXPORT uint32_t NADSN_Begin(const NADSN_Config* input,uint64_t* output) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(!output_generation(output,0))return reject(INVALID_CONFIG);
    NADSN_Config c{};if(!config(input,c))return 0;if(reserved.load())return reject(BUSY);
    Policy next{};next.game=c.game;next.exe=c.exe;next.context=c.context;next.camera=c.camera;
    next.avatar_owner=c.avatar_owner;next.avatar_index=c.avatar_index;
    if(observe(next)==View::LOST)return reject(OWNER_MISMATCH);
    Setter target=nullptr;uint64_t address=0;if(!contract(c,target,address))return 0;
    if(original.load() && original.load()!=target)return reject(API_MISMATCH);
    if(!pin(reinterpret_cast<const void*>(&NADSN_Begin)))return reject(PIN_FAILED);
#if !defined(NADSN_FIXTURE)
    if(!pin(reinterpret_cast<const void*>(c.exe)))return reject(PIN_FAILED);
#endif
    original.store(target,std::memory_order_release);slot=address;slot_image=c.exe;possible=false;
    if(++generation_counter==0)++generation_counter;
    if(!output_generation(output,generation_counter))return reject(INVALID_CONFIG);
    owned_generation=generation_counter;reserved.store(1,std::memory_order_release);possible=true;
    AcquireSRWLockExclusive(&policy_lock);
    policy=next;hip_meters.store(c.hip);aim_meters.store(c.aim);last_native.store(0);last_applied.store(0);
    seen.store(0);forwarded.store(0);replaced.store(0);ads_forwarded.store(0);aim_applied.store(0);other_kind.store(0);
    text_low.store(c.game+TEXT,std::memory_order_relaxed);text_high.store(c.game+TEXT_END,std::memory_order_relaxed);
    ReleaseSRWLockExclusive(&policy_lock);
    if(!writable_slot(slot,c.exe))return failed_begin(SLOT_NOT_WRITABLE,output);
    uint64_t observed=0;if(!cas(reinterpret_cast<uint64_t>(target),callback(),observed))return failed_begin(CAS_FAULT,output);
    if(observed!=reinterpret_cast<uint64_t>(target)) {possible=false;return failed_begin(CAS_MISMATCH,output);}
    installed.store(1,std::memory_order_release);
    if(!dispatch_owned(next))return failed_begin(CAS_MISMATCH,output);
    if(observe(next)==View::LOST)return failed_begin(OWNER_MISMATCH,output);
    armed.store(1,std::memory_order_release);error(OK);return 1;
}
NADSN_EXPORT uint32_t NADSN_Set(uint64_t generation,float hip,float aim) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(!generation || !reserved.load() || generation!=owned_generation)return reject(TOKEN_MISMATCH);
    if(!meters(hip) || !meters(aim))return reject(INVALID_CONFIG);
    hip_meters.store(hip,std::memory_order_relaxed);aim_meters.store(aim,std::memory_order_relaxed);error(OK);return 1;
}
// Some callers run only on entry/exit, so the game may not write its own
// distance again soon: put 0.05 back if the owned camera still holds ours.
static void restore_distance() {
    const float applied=last_applied.load(),native=last_native.load();float current=0;uint64_t ctx=0,camera=0;
    if(applied<=native || !pointer(policy.game+0x2e287d0,ctx) || ctx!=policy.context || !pointer(ctx,camera)
        || camera!=policy.camera || !value(camera+0x28,current) || current!=applied)return;
    original.load(std::memory_order_acquire)(reinterpret_cast<void*>(camera),native);
}
NADSN_EXPORT uint32_t NADSN_End(uint64_t generation) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(!generation)return reject(TOKEN_MISMATCH);
    if(!reserved.load()) {if(generation!=retired_generation)return reject(TOKEN_MISMATCH);error(OK);return 1;}
    if(generation!=owned_generation)return reject(TOKEN_MISMATCH);
    if(!drain_and_restore())return reject(CLEANUP_PENDING);
    restore_distance();error(OK);return 1;
}
NADSN_EXPORT uint32_t NADSN_ReadSites(NADSN_Site* output,uint32_t capacity) {
    uint32_t count=0;
    for(auto& row:site_rows) {
        const uint64_t address=row.address.load(std::memory_order_acquire);if(!address)break;
        if(count<capacity) {
            NADSN_Site r{};r.return_address=address;r.calls=row.calls.load();r.owned_calls=row.owned.load();r.last_value=row.value.load();
            SIZE_T actual=0;if(!WriteProcessMemory(GetCurrentProcess(),output+count,&r,sizeof r,&actual) || actual!=sizeof r)return reject(INVALID_CONFIG);
        }
        ++count;
    }
    return count;
}
NADSN_EXPORT uint32_t NADSN_ReadStats(uint64_t generation,NADSN_Stats* output) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(reserved.load()?(!generation || generation!=owned_generation):generation!=0)return reject(TOKEN_MISMATCH);
    NADSN_Stats s{};if(!read(reinterpret_cast<uint64_t>(output),&s,sizeof s) || s.size!=sizeof s || s.abi!=1)return reject(INVALID_CONFIG);
    s.reserved=0;s.installed=installed.load();s.armed=armed.load();s.error=last_error.load();
    s.seen=seen.load();s.forwarded=forwarded.load();s.replaced=replaced.load();s.ads_forwarded=ads_forwarded.load();
    s.aim_applied=aim_applied.load();s.other_kind=other_kind.load();
    s.last_native=last_native.load();s.last_applied=last_applied.load();s.hip=hip_meters.load();s.aim=aim_meters.load();
    SIZE_T actual=0;return WriteProcessMemory(GetCurrentProcess(),output,&s,sizeof s,&actual)!=0 && actual==sizeof s;
}
NADSN_EXPORT uint32_t NADSN_Error(void) {return last_error.load(std::memory_order_acquire);}
