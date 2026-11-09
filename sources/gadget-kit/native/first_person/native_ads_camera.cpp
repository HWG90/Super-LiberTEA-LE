// Native FPV is forwarded exactly. Qualified normal-camera eye correction only. No Unit writes.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <intrin.h>
#include "native_memory.h"
#include <atomic>
#include <cstdint>
#include <cstring>
#include <cmath>
#include "native_ads_camera.h"
#include "free_aim_math.h"
#include "camera_correction.h"
using Setter=void (*)(void*,uint32_t,const float*);
static SRWLOCK control_lock=SRWLOCK_INIT,policy_lock=SRWLOCK_INIT;
static std::atomic<Setter> original{nullptr};
static std::atomic<uint32_t> installed{0},armed{0},reserved{0},last_error{0};
static std::atomic<uint64_t> callback_generation{0};
static std::atomic<uint64_t> seen{0},forwarded{0},replaced{0},native6_forwarded{0},resets{0},return_address{0};
static uint64_t slot=0,slot_image=0,generation_counter=0,owned_generation=0,retired_generation=0;
static bool possible=false;
static constexpr uint32_t SETTER=0x2dd4f0,CALL=0x110be95,GRAPH_GETTER=0x28d310;
enum Error:uint32_t {OK=0,INVALID_CONFIG=1,BUSY=2,READ_FAILED=3,IMAGE_MISMATCH=4,
    CODE_MISMATCH=5,API_MISMATCH=6,OWNER_MISMATCH=7,UNIT_MISMATCH=8,PIN_FAILED=9,
    SLOT_NOT_WRITABLE=10,CAS_MISMATCH=11,CAS_FAULT=12,CLEANUP_PENDING=13,
    POSE_INVALID=14,SPACE_INVALID=15,GRAPH_MISMATCH=16,TOKEN_MISMATCH=17,ON_FOOT_REQUIRED=18};
struct Policy {
    float side=0;
    uint32_t profile_remaining=0,profile_count=0;double profile_times[1000]{};
    CameraCorrection::State correction{};
    float last_relative[3]{};double last_relative_tick=0;bool relative_valid=false;
    LARGE_INTEGER profile_frequency{};bool presentation_enabled=false;float motion[6]{};uint32_t current_weapon=0;
    FreeAim::State free_aim{};uint64_t free_until=0,free_previous=0,free_applied=0,free_ads=0;uint32_t free_gate=0;
    uint64_t observe_until=0,observe_samples=0,observe_rejected=0;float observe_max_degrees=0;
    bool full_ads=false,shoulder=false,fire=false,kick_enabled=false,kick_fire_previous=false;
    float kick_angle=0;uint64_t kick_previous=0,kick_pulses=0,kick_frames=0;uint64_t free_measured=0;double free_total_us=0,free_max_us=0;
    NADSC_Config c{};uint64_t controller=0,descriptor=0,registry=0,units=0,generations=0;
    uint64_t body_object=0,camera_object=0,hashes=0,links=0,sampled_worlds=0;uint32_t count=0,head_node=0;
    uint64_t foot_instance=0,foot_graph=0,foot_array=0,foot_current=0,foot_definition=0;
    uint8_t descriptor_bytes[20]{};bool safe=false,fallback_safe=false,tracking=false,native6_seen=false;double previous=0,native6_at=0;
    float relative_head[3]{},blend=0,head_distance=0,last_dt=0;
};
static Policy policy;
// A single bounded atomic snapshot keeps display diagnostics independent of
// the renderer's setter lock. Health and generation ownership stay separate.
struct Display {float blend=0,head_distance=0,last_dt=0;};
static Display display_cache; // control_lock only; never touched by callbacks.
static std::atomic<uint32_t> display_sequence{0};
static std::atomic<float> display_blend{0},display_head_distance{0},display_last_dt{0};
static_assert(std::atomic<float>::is_always_lock_free,"Camera diagnostics require lock-free floats");
static void publish_diagnostics(const Policy& p) {
    display_sequence.fetch_add(1,std::memory_order_seq_cst);
    display_blend.store(p.blend,std::memory_order_seq_cst);
    display_head_distance.store(p.head_distance,std::memory_order_seq_cst);
    display_last_dt.store(p.last_dt,std::memory_order_seq_cst);
    display_sequence.fetch_add(1,std::memory_order_seq_cst);
}
static void read_diagnostics(NADSC_Stats& s) {
    const uint32_t before=display_sequence.load(std::memory_order_seq_cst);
    if((before&1)==0) {
        const Display next{display_blend.load(std::memory_order_seq_cst),display_head_distance.load(std::memory_order_seq_cst),
            display_last_dt.load(std::memory_order_seq_cst)};
        if(before==display_sequence.load(std::memory_order_seq_cst))display_cache=next;
    }
    s.blend=display_cache.blend;s.head_distance=display_cache.head_distance;s.last_dt=display_cache.last_dt;
}
#if defined(NADSC_FIXTURE)
static Setter fixture_target=nullptr;
static uint32_t fixture_cas_calls=0,fixture_cas_fail_at=0,fixture_foreign_cas_at=0;
static uint64_t fixture_foreign_value=0;static double fixture_time=1000;
static uint64_t fixture_mutate_after_cas=0;static uint32_t fixture_mutation_value=0;
static uint64_t fixture_bridge_mutation=0;static uint32_t fixture_bridge_value=0;
static uint64_t fixture_before_commit_mutation=0;static uint32_t fixture_before_commit_value=0;
static uint64_t fixture_before_history_mutation=0;static uint32_t fixture_before_history_value=0;
static uint64_t fixture_registry_close_mutation=0;static uint32_t fixture_registry_close_value=0;
static bool fixture_slot_unreadable=false,fixture_slot_readonly=false;
static HANDLE fixture_before_policy_reached=nullptr,fixture_continue_policy=nullptr;
static HANDLE fixture_begin_display_reached=nullptr,fixture_continue_begin=nullptr;
#endif
static double now() {
#if defined(NADSC_FIXTURE)
    return static_cast<double>(fixture_time);
#else
    // QPC provides sub-millisecond phase at high refresh rates; its frequency
    // is process-lifetime constant and is queried only once, never per frame.
    static const double ticks_per_ms=[](){LARGE_INTEGER frequency{};
        return QueryPerformanceFrequency(&frequency)&&frequency.QuadPart>0?static_cast<double>(frequency.QuadPart)/1000.0:0.0;}();
    LARGE_INTEGER sample{};
    return ticks_per_ms>0&&QueryPerformanceCounter(&sample)?static_cast<double>(sample.QuadPart)/ticks_per_ms
        :static_cast<double>(GetTickCount64());
#endif
}
static bool read(uint64_t at,void* out,size_t length) {
    if(at<65536 || at>=0x800000000000ULL || length>4096 || at+length>=0x800000000000ULL)return false;
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
static bool finite3(const float* p) {return std::isfinite(p[0]) && std::isfinite(p[1]) && std::isfinite(p[2]);}
static float distance(const float* a,const float* b) {
    const float x=a[0]-b[0],y=a[1]-b[1],z=a[2]-b[2];return std::sqrt(x*x+y*y+z*z);
}
static bool orthonormal(const float* right,const float* forward,const float* up) {
    if(!finite3(right) || !finite3(forward) || !finite3(up))return false;
    auto dot=[](const float* a,const float* b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];};
    const float cross[3]{right[1]*forward[2]-right[2]*forward[1],right[2]*forward[0]-right[0]*forward[2],right[0]*forward[1]-right[1]*forward[0]};
    return std::fabs(dot(right,right)-1)<.02f && std::fabs(dot(forward,forward)-1)<.02f && std::fabs(dot(up,up)-1)<.02f
        && std::fabs(dot(right,forward))<.02f && std::fabs(dot(right,up))<.02f && std::fabs(dot(forward,up))<.02f
        && dot(cross,up)>.98f;
}
static bool resolve(const Policy& p,uint32_t ref,uint64_t& object,uint32_t capacity=0) {
    const uint32_t index=ref&0x3fffff;uint8_t first=0,last=0;uint64_t again=0;
    return (capacity || value(p.registry+0x98,capacity)) && capacity>0 && capacity<=0x400000 && index<capacity
        && value(p.generations+index,first) && first==static_cast<uint8_t>(ref>>22)
        && pointer(p.units+static_cast<uint64_t>(index)*8,object)
        && value(p.generations+index,last) && last==first
        && pointer(p.units+static_cast<uint64_t>(index)*8,again) && again==object;
}
struct RegistryBlock {uint64_t units,padding;uint32_t capacity,padding2;uint64_t generations;};
static_assert(sizeof(RegistryBlock)==32,"registry read span");
static bool registry_block(uint64_t registry,RegistryBlock& b) {
    return read(registry+0x88,&b,sizeof b) && b.units>=65536 && b.units<0x800000000000ULL
        && b.generations>=65536 && b.generations<0x800000000000ULL && b.capacity>0 && b.capacity<=0x400000;
}
static bool owner(Policy& p,bool capture) {
    const auto& c=p.c;uint64_t ctx=0,camera=0,avatar_owner=0,controller=0,descriptor=0,registry=0,units=0,generations=0;
    uint32_t count=0,camera_unit=0;uint8_t d[20]{},flags[24]{},controls[6]{},context[12]{};RegistryBlock block{};
    if(!pointer(c.game+0x2e287d0,ctx) || ctx!=c.context || !read(ctx,context,sizeof context)
        || (std::memcpy(&camera,context,8),camera!=c.camera)
        || (std::memcpy(&camera_unit,context+8,4),camera_unit!=c.camera_unit)
        || !pointer(c.game+0x2ce1ee0,avatar_owner) || avatar_owner!=c.avatar_owner
        || !pointer(c.game+0x2e381a8,controller) || !read(controller,controls,6)
        || !value(avatar_owner+0x6C,count) || count==0 || count>8 || c.avatar_index>=count
        || !pointer(avatar_owner+0x110+static_cast<uint64_t>(c.avatar_index)*8,descriptor) || !read(descriptor,d,20)
        || !read(avatar_owner+0x53e888+static_cast<uint64_t>(c.avatar_index)*0x1240,flags,24)
        || !pointer(c.exe+0x1ab76f8,registry) || !registry_block(registry,block))return false;
    units=block.units;generations=block.generations;
    uint32_t avatar=0,body=0,mask=0;std::memcpy(&avatar,d+8,4);std::memcpy(&body,d+12,4);std::memcpy(&mask,controls,4);
    if(avatar!=c.avatar || body!=c.body)return false;
    if(capture) {p.controller=controller;p.descriptor=descriptor;p.registry=registry;p.units=units;p.generations=generations;std::memcpy(p.descriptor_bytes,d,20);}
    else if(controller!=p.controller || descriptor!=p.descriptor || registry!=p.registry || units!=p.units
        || generations!=p.generations || std::memcmp(d,p.descriptor_bytes,20)!=0)return false;
    uint64_t body_object=0,camera_object=0;
    if(!resolve(p,c.body,body_object,block.capacity) || !resolve(p,c.camera_unit,camera_object,block.capacity))return false;
#if defined(NADSC_FIXTURE)
    if(fixture_registry_close_mutation) {std::memcpy(reinterpret_cast<void*>(fixture_registry_close_mutation),&fixture_registry_close_value,4);fixture_registry_close_mutation=0;}
#endif
    // Both references used the single bounded header read. Close that header
    // after their generation/object double-checks; never reuse a changed bound.
    RegistryBlock closing{};
    if(!registry_block(registry,closing) || closing.units!=block.units || closing.generations!=block.generations || closing.capacity!=block.capacity)return false;
    if(capture) {p.body_object=body_object;p.camera_object=camera_object;}
    else if(body_object!=p.body_object || camera_object!=p.camera_object)return false;
    // Arming retains the original mask0/2 gate. The captured on-foot vault
    // uses exact mask0x20 with normal4, so only an existing stable camera lease
    // may anchor that fallback after its on-foot and world-space checks pass.
    p.fire=(flags[12]&0x40)!=0;p.full_ads=controls[4]!=0;p.shoulder=!p.full_ads&&(flags[10]&4)!=0&&(flags[15]&32)!=0;
    const bool available=controls[5]==0 && (flags[14]&4)==0;
    p.safe=(mask==0 || mask==2) && available;
    p.fallback_safe=(mask==0 || mask==2 || mask==0x20) && available;
    return true;
}
static bool top(Policy& p,uint32_t& kind) {
    uint32_t ring[2]{},r[4]{};
    if(!read(p.c.context+0x1F8,ring,sizeof ring) || ring[0]>=32 || ring[1]>=32)return false;
    const uint32_t head=ring[0],tail=ring[1];
    const uint64_t at=head==tail?p.c.context+0x1F00:p.c.context+0x200+((tail+31)%32)*0xE8;
    if(!read(at,r,16) || r[1]!=p.c.avatar)return false;kind=r[0]&0xffff;if(kind==6)p.current_weapon=r[2];
    return kind!=6 || (head!=tail && r[3]==p.c.body);
}
static bool graph(Policy& p,bool capture) {
    uint64_t vt=0,getter=0,hashes=0,links=0;uint32_t count=0;uint8_t header[56]{};
    if(!pointer(p.body_object,vt) || !pointer(vt+0xE8,getter) || getter!=p.c.exe+GRAPH_GETTER
        || !bytes(getter,"488d4160c3") || !read(p.body_object+0x70,header,sizeof header))return false;
    std::memcpy(&count,header,4);std::memcpy(&links,header+0x28,8);std::memcpy(&hashes,header+0x30,8);
    if(count==0 || count>512 || links<65536 || links>=0x800000000000ULL || hashes<65536 || hashes>=0x800000000000ULL)return false;
#if !defined(NADSC_FIXTURE)
    if(!executable(getter))return false;
#endif
    if(capture) {
        uint32_t found=UINT32_MAX;
        for(uint32_t i=0;i<count;++i) {uint32_t h=0;if(!value(hashes+static_cast<uint64_t>(i)*4,h))return false;
            if(h==0x8C5570C9) {if(found!=UINT32_MAX)return false;found=i;}}
        if(found==UINT32_MAX)return false;p.hashes=hashes;p.links=links;p.count=count;p.head_node=found;
    } else if(hashes!=p.hashes || links!=p.links || count!=p.count)return false;
    uint32_t head_hash=0,link=0,parent_hash=0;const uint64_t offset=static_cast<uint64_t>(p.head_node)*4;
    if(!value(hashes+offset,head_hash) || head_hash!=0x8C5570C9 || !value(links+offset,link)
        || (link&0xffff)!=1 || (link>>16)>=count || !value(hashes+static_cast<uint64_t>(link>>16)*4,parent_hash)
        || parent_hash!=0xE9ECCA21)return false;
    return true;
}
static bool points(Policy& p,float* root,float* head,float* root_basis=nullptr) {
    float matrix[16]{};uint64_t matrices=0;if(!graph(p,false) || !pointer(p.body_object+0x88,matrices)
        || !read(matrices,matrix,64) || !read(matrices+static_cast<uint64_t>(p.head_node)*0x40+0x30,head,12)
        || !orthonormal(matrix,matrix+4,matrix+8) || !finite3(matrix+12) || !finite3(head))return false;
    p.sampled_worlds=matrices;std::memcpy(root,matrix+12,12);
    if(root_basis)for(unsigned i=0;i<3;++i)std::memcpy(root_basis+i*3,matrix+i*4,12);
    p.head_distance=distance(root,head);return std::isfinite(p.head_distance) && p.head_distance>=.05f && p.head_distance<=3.0f;
}
// Positive current-build on-foot state, rather than an inferred death bit.
// Bridge state3 additionally requires the actual combat role and ship scene;
// ordinary ship role4 never gains a head-camera exception.
// The native state getter maps resource-relative state pointers to indices.
static bool on_foot(Policy& p) {
    uint64_t vt=0,getter=0,resource=0,instance=0,g=0,array=0,current=0;
    uint32_t layers=0,table_offset=0,layer_offset=0,count=0,state_offset=0;
    if(!pointer(p.body_object,vt) || !pointer(vt+0x1B0,getter) || getter!=p.c.exe+0x28d460
        || !bytes(getter,"488b8178010000c3") || !value(p.body_object+0x358,resource) || resource!=0x4D1C334D294DFA97ULL
        || !pointer(p.body_object+0x178,instance) || !pointer(instance+0x28,g) || !value(g+4,layers) || layers!=31
        || !value(g+8,table_offset) || table_offset<12 || table_offset>0x10000)return false;
    const uint64_t table=g+table_offset;
    if(!value(table+4+13*4,layer_offset) || layer_offset<12 || layer_offset>0x1000000)return false;
    const uint64_t definition=table+layer_offset;
    if(!value(definition+8,count) || count<=36 || count>2048 || !value(definition+12+36*4,state_offset)
        || state_offset<12 || state_offset>0x1000000 || !pointer(instance+0x50,array)
        || !pointer(array+13*8,current))return false;
    uint32_t state=36,role=0;uint64_t settings=0;
    const uint64_t role_address=p.c.avatar_owner+0x53e888+static_cast<uint64_t>(p.c.avatar_index)*0x1240;
    if(current!=definition+state_offset) {
        state=3;
        uint32_t scene=0;
        if(!value(definition+12+3*4,state_offset) || state_offset<12 || state_offset>0x1000000
            || current!=definition+state_offset || !value(role_address,role) || (role&6)!=2
            || !pointer(p.c.game+0x2ce1508,settings) || !value(settings+0xac29c,scene) || scene!=3)return false;
    }
    // Match the native first-index lookup even when resources alias states.
    uint32_t prefix[37]{};
    if(!read(definition+12,prefix,(state+1)*sizeof(uint32_t)) || prefix[state]!=state_offset)return false;
    for(uint32_t i=0;i<state;++i)if(prefix[i]<12 || prefix[i]>0x1000000 || prefix[i]==state_offset)return false;
#if defined(NADSC_FIXTURE)
    if(state==3 && fixture_bridge_mutation) {
        std::memcpy(reinterpret_cast<void*>(fixture_bridge_mutation),&fixture_bridge_value,4);fixture_bridge_mutation=0;
    }
#endif
    uint64_t again=0;uint32_t check=0;
    const bool stable=pointer(p.body_object+0x178,again) && again==instance && pointer(instance+0x28,again) && again==g
        && pointer(instance+0x50,again) && again==array && pointer(array+13*8,again) && again==current
        && value(g+4,check) && check==layers && value(g+8,check) && check==table_offset
        && value(table+4+13*4,check) && check==layer_offset && value(definition+8,check) && check==count
        && value(definition+12+static_cast<uint64_t>(state)*4,check) && check==state_offset;
    if(!stable)return false;
    p.foot_instance=instance;p.foot_graph=g;p.foot_array=array;p.foot_current=current;p.foot_definition=definition;
    if(state==36)return true;
    // The bridge exception is live state, never a cached mod toggle. Recheck
    // the role, scene owner and current body generation before substituting.
    uint32_t current_role=0,scene=0;uint64_t current_resource=0;
    return value(role_address,current_role) && current_role==role
        && pointer(p.c.game+0x2ce1508,again) && again==settings && value(settings+0xac29c,scene) && scene==3
        && pointer(p.c.exe+0x1ab76f8,again) && again==p.registry
        && resolve(p,p.c.body,again) && again==p.body_object
        && value(p.body_object+0x358,current_resource) && current_resource==resource;
}
// Local/world coincidence is mandatory: native kind6 uses another parent space.
static bool unparented(const Policy& p) {
    uint64_t parent=1,g=0,locals=0,worlds=0;uint32_t index=0,count=0;float a[3]{},b[3]{};
    if(!value(p.camera_object+0x1D0,parent) || parent!=0 || !pointer(p.c.camera+0x18,g) || g!=p.camera_object+0x60
        || !value(p.c.camera+0x20,index) || !value(g+0x10,count) || count==0 || count>512 || index>=count
        || !pointer(g+0x20,locals) || !pointer(g+0x28,worlds)
        || !read(locals+static_cast<uint64_t>(index)*0x40+0x24,a,12)
        || !read(worlds+static_cast<uint64_t>(index)*0x40+0x30,b,12) || !finite3(a) || !finite3(b))return false;
    return distance(a,b)<=.01f;
}
static bool basis(const Policy& p,float* forward,float* up) {
    float frame[11]{};
    if(!read(p.c.context+0x0C,frame,sizeof frame))return false;
    std::memcpy(forward,frame+4,12);std::memcpy(up,frame+8,12);
    return orthonormal(frame,forward,up);
}
static void reset(Policy& p,bool keep_native6=false) {
    p.tracking=false;p.blend=0;p.last_dt=0;if(!keep_native6){p.native6_seen=false;p.correction.reset();p.relative_valid=false;}
    resets.fetch_add(1,std::memory_order_relaxed);
}
static bool writable_slot(uint64_t at,uint64_t exe) {
    if((at&7)!=0)return false;
#if defined(NADSC_FIXTURE)
    if(fixture_slot_readonly)return false;(void)exe;
#endif
    MEMORY_BASIC_INFORMATION r{};
    if(VirtualQuery(reinterpret_cast<const void*>(at),&r,sizeof r)!=sizeof r || r.State!=MEM_COMMIT || !writable_pe_protection(r.Protect)
        || at+8>reinterpret_cast<uint64_t>(r.BaseAddress)+r.RegionSize)return false;
#if !defined(NADSC_FIXTURE)
    return pe_section_mapping(r) && reinterpret_cast<uint64_t>(r.AllocationBase)==exe;
#else
    return r.Type==MEM_PRIVATE;
#endif
}
static bool slot_read(uint64_t at,uint64_t& out) {
#if defined(NADSC_FIXTURE)
    if(fixture_slot_unreadable)return false;
#endif
    return value(at,out);
}
static bool cas(uint64_t expected,uint64_t desired,uint64_t& observed) {
#if defined(NADSC_FIXTURE)
    if(++fixture_cas_calls==fixture_cas_fail_at)return false;
    if(fixture_cas_calls==fixture_foreign_cas_at)InterlockedExchangePointer(reinterpret_cast<PVOID volatile*>(slot),reinterpret_cast<void*>(fixture_foreign_value));
#endif
    __try {observed=reinterpret_cast<uint64_t>(InterlockedCompareExchangePointer(reinterpret_cast<PVOID volatile*>(slot),
        reinterpret_cast<void*>(desired),reinterpret_cast<void*>(expected)));
#if defined(NADSC_FIXTURE)
        if(fixture_mutate_after_cas)std::memcpy(reinterpret_cast<void*>(fixture_mutate_after_cas),&fixture_mutation_value,4);
#endif
        return true;
    } __except(EXCEPTION_EXECUTE_HANDLER) {return false;}
}
static uint64_t callback();
static bool dispatch_owned(const Policy& p) {
    uint64_t root=0,api=0,target=0;
    return pointer(p.c.game+0x2ce14c8,root) && pointer(root+0x20,api) && api+0x20==slot
        && slot_read(slot,target) && target==callback();
}
// The game consumes quaternion(native+64) at CameraAPI+28. This helper observes
// the current parent read-only; it never edits caller scratch, Units, context,
// input, weapon, muzzle, aim target or projectiles. No extra callback is installed.
// Read the actual external camera parent in the current rig pose. Camera world
// readback can still belong to the preceding frame at this pre-setter stage.
struct ParentProof {uint64_t parent=0,poses=0,links=0,hashes=0,parent_links=0;uint32_t ref=0,link=0;};
static bool parent_current(const Policy& p,const ParentProof& proof) {
    uint64_t again=0;uint32_t check=0;
    return value(p.c.camera+0x20,check)&&check==0
        &&pointer(p.camera_object+0x98,again)&&again==proof.links
        &&value(proof.parent+0x70,check)&&check==63
        &&pointer(p.camera_object+0x1D0,again)&&again==proof.parent
        &&pointer(p.camera_object+0x78,again)&&again==proof.poses
        &&value(proof.links,check)&&check==proof.link
        &&value(p.c.avatar_owner+0x53e9c0+static_cast<uint64_t>(p.c.avatar_index)*0x1240,check)&&check==proof.ref
        &&resolve(p,proof.ref,again)&&again==proof.parent
        &&pointer(proof.parent+0x88,again)&&again==proof.poses
        &&pointer(proof.parent+0x98,again)&&again==proof.parent_links
        &&pointer(proof.parent+0xA0,again)&&again==proof.hashes
        &&value(proof.hashes+50*4,check)&&check==0x60ED8C39
        &&value(proof.parent_links+50*4,check)&&check==0x40001;
}
static bool direct_camera_parent(Policy& p,FreeAim::Q& out,float* position=nullptr,ParentProof* proof=nullptr,float* matrix_basis=nullptr) {
    uint64_t links=0,parent=0,expected=0,poses=0,external=0,hashes=0,parent_links=0;
    uint32_t link=0,ref=0,count=0,hash=0,parent_link=0,index=0;uint8_t header[56]{};
    if(!value(p.c.camera+0x20,index)||index!=0
       ||!pointer(p.camera_object+0x98,links)||!value(links,link)||link!=0x00320002
       ||!pointer(p.camera_object+0x1D0,parent)
       ||!value(p.c.avatar_owner+0x53e9c0+static_cast<uint64_t>(p.c.avatar_index)*0x1240,ref)
       ||!resolve(p,ref,expected)||expected!=parent
       ||!read(parent+0x70,header,sizeof header))return false;
    std::memcpy(&count,header,4);std::memcpy(&poses,header+0x18,8);
    std::memcpy(&parent_links,header+0x28,8);std::memcpy(&hashes,header+0x30,8);
    if(count!=63 || hashes<65536 || hashes>=0x800000000000ULL || parent_links<65536 || parent_links>=0x800000000000ULL
       || poses<65536 || poses>=0x800000000000ULL || !value(hashes+50*4,hash)||hash!=0x60ED8C39
       ||!value(parent_links+50*4,parent_link)||parent_link!=0x40001
       ||!pointer(p.camera_object+0x78,external)||external!=poses)return false;
    float matrix[16]{};
    if(!read(poses+50*64,matrix,64) || !finite3(matrix+12))return false;
    if(matrix_basis) {
        if(!orthonormal(matrix,matrix+4,matrix+8))return false;
        for(unsigned axis=0;axis<3;++axis)std::memcpy(matrix_basis+axis*3,matrix+axis*4,12);
    }else if(!FreeAim::matrix_q(matrix,out))return false;
    if(position)std::memcpy(position,matrix+12,12);
    const ParentProof sampled{parent,poses,links,hashes,parent_links,ref,link};
    if(proof){*proof=sampled;return true;} // caller closes after its remaining sampled reads
    return parent_current(p,sampled);
}
// Read-only native6 reference. The FP parent is current-generation proven;
// the pre-setter camera world matrix is deliberately never used as history.
// Returns false only for loss of the lease owner/dispatch. Unsupported or
// changing parent/request spaces merely discard optional positional history.
static bool remember_native(Policy& p,const float* native,double tick,bool capture=true) {
    FreeAim::Q parent{};float parent_position[3]{},local[3]{},root[16]{},parent_basis[9]{};uint64_t matrices=0;ParentProof proof{};
    const uint32_t weapon=p.current_weapon;uint8_t full_ads=0;
    const bool sampled=capture && value(p.controller+4,full_ads)
        && read(reinterpret_cast<uint64_t>(native),local,12) && finite3(local)
        && pointer(p.body_object+0x88,matrices) && read(matrices,root,64)
        && orthonormal(root,root+4,root+8) && finite3(root+12)
        && direct_camera_parent(p,parent,parent_position,&proof,parent_basis);
#if defined(NADSC_FIXTURE)
    if(fixture_before_history_mutation) {std::memcpy(reinterpret_cast<void*>(fixture_before_history_mutation),&fixture_before_history_value,4);fixture_before_history_mutation=0;}
#endif
    // Read-only sample addresses belong to this lease but may have retired.
    // Nothing is admitted until a single complete fresh owner/dispatch proof;
    // passive owner-loss health is retained even when optional sampling fails.
    if(!owner(p,false) || !dispatch_owned(p)) {p.correction.reset();return false;}
    uint64_t again=0;uint32_t kind=0;
    if(!sampled || !p.safe || !top(p,kind) || kind!=6 || p.current_weapon!=weapon || p.full_ads!=(full_ads!=0)
        || !pointer(p.body_object+0x88,again) || again!=matrices || !parent_current(p,proof)) {p.correction.reset();return true;}
    float offset[3]{},relative[3]{};
    for(unsigned component=0;component<3;++component)for(unsigned axis=0;axis<3;++axis)
        offset[component]+=local[axis]*parent_basis[axis*3+component];
    for(unsigned axis=0;axis<3;++axis)for(unsigned component=0;component<3;++component)
        relative[axis]+=(parent_position[component]+offset[component]-root[12+component])*root[axis*4+component];
    p.correction.remember(relative,p.current_weapon,tick);return true;
}
// Final mutable proof; code/vtable fingerprints were already checked during
// this callback. Repeat owner/generation/request checks and the sampled graph
// identity, topology and world-space parent immediately before fallback use.
static bool commit_current(Policy& p,uint32_t expected_kind) {
#if defined(NADSC_FIXTURE)
    if(fixture_before_commit_mutation) {std::memcpy(reinterpret_cast<void*>(fixture_before_commit_mutation),&fixture_before_commit_value,4);fixture_before_commit_mutation=0;}
#endif
    uint32_t kind=0,count=0,hash=0,link=0,parent_hash=0;uint64_t hashes=0,links=0,matrices=0,parent=1;
    uint8_t header[56]{};uint64_t foot=0;
    if(!pointer(p.body_object+0x178,foot) || foot!=p.foot_instance
        || !pointer(p.foot_instance+0x28,foot) || foot!=p.foot_graph
        || !pointer(p.foot_instance+0x50,foot) || foot!=p.foot_array
        || !pointer(p.foot_array+13*8,foot) || foot!=p.foot_current
        || !owner(p,false) || !p.fallback_safe || !dispatch_owned(p) || !top(p,kind) || kind!=expected_kind
        || !read(p.body_object+0x70,header,sizeof header))return false;
    std::memcpy(&count,header,4);std::memcpy(&matrices,header+0x18,8);
    std::memcpy(&links,header+0x28,8);std::memcpy(&hashes,header+0x30,8);
    return count==p.count && matrices==p.sampled_worlds && links==p.links && hashes==p.hashes
        && value(hashes+static_cast<uint64_t>(p.head_node)*4,hash) && hash==0x8C5570C9
        && value(links+static_cast<uint64_t>(p.head_node)*4,link) && (link&0xffff)==1 && (link>>16)<count
        && value(hashes+static_cast<uint64_t>(link>>16)*4,parent_hash) && parent_hash==0xE9ECCA21
        && value(p.camera_object+0x1D0,parent) && parent==0;
}
static void observe_camera_parent(Policy& p,double tick){
    if(!p.observe_until)return;if(tick>=p.observe_until){p.observe_until=0;return;}
    FreeAim::Q direct{},local{},world{};float l[16]{},w[16]{},basis[16]{};
    uint64_t g=0,locals=0,worlds=0;
    if(!direct_camera_parent(p,direct)||!pointer(p.c.camera+0x18,g)||g!=p.camera_object+0x60
      ||!pointer(g+0x20,locals)||!pointer(g+0x28,worlds)
      ||!read(locals,l,64)||!read(worlds,w,64)||!FreeAim::matrix_q(w,world)){++p.observe_rejected;return;}
    for(unsigned a=0;a<3;++a)for(unsigned b=0;b<3;++b)basis[a*4+b]=l[a*3+b];
    if(!FreeAim::matrix_q(basis,local)){++p.observe_rejected;return;}
    auto inferred=FreeAim::mul(world,FreeAim::inv(local));
    const float dot=std::fabs(direct.x*inferred.x+direct.y*inferred.y+direct.z*inferred.z+direct.w*inferred.w);
    const float degrees=2*std::acos(std::min(1.0f,dot))*180/FreeAim::PI;
    p.observe_max_degrees=fmaxf(p.observe_max_degrees,degrees);++p.observe_samples;
}
static void setter_hook(void* camera,uint32_t unit,const float* native) {
    seen.fetch_add(1,std::memory_order_relaxed);
    const uint64_t entered_generation=callback_generation.load(std::memory_order_acquire);
    if(!armed.load(std::memory_order_acquire) || reinterpret_cast<uint64_t>(_ReturnAddress())!=return_address.load(std::memory_order_relaxed)) {
        forwarded.fetch_add(1,std::memory_order_relaxed);original.load(std::memory_order_acquire)(camera,unit,native);return;
    }
#if defined(NADSC_FIXTURE)
    if(fixture_before_policy_reached) {SetEvent(fixture_before_policy_reached);WaitForSingleObject(fixture_continue_policy,INFINITE);}
#endif
    AcquireSRWLockExclusive(&policy_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&policy_lock);}} unlock;
    LARGE_INTEGER profile_start{};const bool profiling=policy.profile_remaining>0;if(profiling)QueryPerformanceCounter(&profile_start);
    const float* output=native;alignas(16) float adjusted[4]{};bool diagnostics_changed=false;
    if(entered_generation && entered_generation==callback_generation.load(std::memory_order_acquire)
       && armed.load(std::memory_order_acquire) && reinterpret_cast<uint64_t>(camera)==policy.c.camera && unit==policy.c.camera_unit) {
        diagnostics_changed=true;
        uint32_t kind=0;const double tick=now();
        if(policy.native6_seen && (tick<policy.native6_at || tick-policy.native6_at>policy.c.max_gap_ms))policy.native6_seen=false;
        const bool supported=top(policy,kind)&&(kind==4||kind==6);
        if(supported && kind==6) {
            // Read-only sampling can precede the terminal lease proof because
            // this branch ALWAYS forwards the game's entire native frame.
            const bool current=remember_native(policy,native,tick,policy.presentation_enabled);
            native6_forwarded.fetch_add(1,std::memory_order_relaxed);
            if(!current){armed.store(0,std::memory_order_release);reset(policy);error(OWNER_MISMATCH);}
            else {reset(policy,true);policy.native6_seen=true;policy.native6_at=tick;
                observe_camera_parent(policy,tick);error(OK);}
        }else if(!owner(policy,false) || !dispatch_owned(policy)) {
            armed.store(0,std::memory_order_release);reset(policy);error(OWNER_MISMATCH);
        }else if(!supported){policy.free_aim.reset();policy.free_previous=0;reset(policy);}
        else if(!policy.fallback_safe){policy.free_aim.reset();policy.free_previous=0;reset(policy);}
        else if(!on_foot(policy)) {reset(policy);error(ON_FOOT_REQUIRED);}
        else {
            policy.free_aim.reset();policy.free_previous=0;policy.kick_angle=0;policy.kick_fire_previous=policy.fire;
            float root[3]{},head[3]{},forward[3]{},up[3]{},root_basis[9]{};
            if(!points(policy,root,head,root_basis)) {reset(policy);error(GRAPH_MISMATCH);}
            else if(!unparented(policy)) {reset(policy,true);error(SPACE_INVALID);}
            else if(!read(reinterpret_cast<uint64_t>(native),adjusted,16) || !finite3(adjusted) || !basis(policy,forward,up)
                || distance(adjusted,head)>8 || distance(adjusted,root)>10) {
                reset(policy);error(POSE_INVALID);
            } else {
                // Remove current body-root rotation before damping animation.
                // Fresh root translation/rotation is restored after filtering.
                float local_head[3]{};
                for(unsigned axis=0;axis<3;++axis)for(unsigned component=0;component<3;++component)
                    local_head[axis]+=(head[component]-root[component])*root_basis[axis*3+component];
                float dt=0;
                if(policy.tracking && tick>=policy.previous && tick-policy.previous<=policy.c.max_gap_ms)dt=static_cast<float>(tick-policy.previous)/1000;
                else {reset(policy,policy.native6_seen);std::memcpy(policy.relative_head,local_head,12);}
                policy.tracking=true;policy.previous=tick;policy.last_dt=dt;
                const float k=policy.c.smoothing_ms>0?1-std::exp(-dt*1000/policy.c.smoothing_ms):1;
                for(unsigned i=0;i<3;++i)policy.relative_head[i]+=(local_head[i]-policy.relative_head[i])*k;
                float lag[3]{};
                for(unsigned component=0;component<3;++component) {
                    lag[component]=root[component]-head[component];
                    for(unsigned axis=0;axis<3;++axis)lag[component]+=policy.relative_head[axis]*root_basis[axis*3+component];
                }
                const float lag_length=std::sqrt(lag[0]*lag[0]+lag[1]*lag[1]+lag[2]*lag[2]);
                if(lag_length>.06f)for(unsigned i=0;i<3;++i)lag[i]*=.06f/lag_length;
                policy.blend=policy.c.blend_ms>0?fminf(1,policy.blend+dt*1000/policy.c.blend_ms):1;
                // Native6 arguments are parent-local. Never reuse those values
                // for a world-space bridge or expose a TPV frame on retirement.
                if(policy.native6_seen) {policy.blend=1;policy.native6_seen=false;}
                const float weight=policy.blend*policy.blend*(3-2*policy.blend);
                // Pitching/rolling the look direction must not orbit the eye
                // vertically into the helmet. At a vertical look use body yaw.
                float horizontal[3]{forward[0],forward[1],0};
                float horizontal_length=std::sqrt(horizontal[0]*horizontal[0]+horizontal[1]*horizontal[1]);
                if(horizontal_length<.0001f) {
                    horizontal[0]=root_basis[3];horizontal[1]=root_basis[4];
                    horizontal_length=std::sqrt(horizontal[0]*horizontal[0]+horizontal[1]*horizontal[1]);
                }
                if(horizontal_length<.0001f) {reset(policy);error(POSE_INVALID);}
                else {
                    horizontal[0]/=horizontal_length;horizontal[1]/=horizontal_length;
                    for(unsigned i=0;i<3;++i) {
                        const float target=head[i]+lag[i]+horizontal[i]*policy.c.forward+(i==0?horizontal[1]*policy.side:i==1?-horizontal[0]*policy.side:policy.c.up);
                        adjusted[i]+=(target-adjusted[i])*weight;
                    }
                    float desired_relative[3]{},relative[3]{};
                    for(unsigned axis=0;axis<3;++axis)for(unsigned component=0;component<3;++component)
                        desired_relative[axis]+=(adjusted[component]-root[component])*root_basis[axis*3+component];
                    if(policy.presentation_enabled && policy.correction.apply(desired_relative,policy.current_weapon,tick,relative,150,policy.c.max_gap_ms)) {
                        for(unsigned component=0;component<3;++component){adjusted[component]=root[component];
                            for(unsigned axis=0;axis<3;++axis)adjusted[component]+=relative[axis]*root_basis[axis*3+component];}
                    }else std::memcpy(relative,desired_relative,12);
                    // Revalidate mutable ownership, request and graph after all
                    // sampling, directly before making a corrected native call.
                    if(!commit_current(policy,kind)) {reset(policy);error(OWNER_MISMATCH);}
                    else {std::memcpy(policy.last_relative,relative,12);policy.last_relative_tick=tick;policy.relative_valid=true;
                        output=adjusted;replaced.fetch_add(1,std::memory_order_relaxed);error(OK);}
                }
            }
        }

    }
    // Serialize actual adjusted call with End, not just the calculation.
    forwarded.fetch_add(1,std::memory_order_relaxed);original.load(std::memory_order_acquire)(camera,unit,output);
    if(diagnostics_changed)publish_diagnostics(policy);
    if(profiling){LARGE_INTEGER end{};QueryPerformanceCounter(&end);
        if(policy.profile_frequency.QuadPart>0&&policy.profile_count<1000)policy.profile_times[policy.profile_count++]=static_cast<double>(end.QuadPart-profile_start.QuadPart)*1e6/static_cast<double>(policy.profile_frequency.QuadPart);
        --policy.profile_remaining;
    }
}
static uint64_t callback() {return reinterpret_cast<uint64_t>(setter_hook);}
static bool contract(const NADSC_Config& c,Setter& setter,uint64_t& address) {
    if(!image(c.game,0x6ae0e5ff,0x3382000) || !image(c.exe,0x6ae0964a,0x29fe000))return reject(IMAGE_MISMATCH)!=0;
    if(!bytes(c.game+CALL,"41ff5120") || !bytes(c.exe+SETTER,"48895c2408574883ec60488bd9498bf88bcae89931dcff4c8b4b184c8bd04c6343208b4708498bd048c1e206498b4920")
        || !bytes(c.exe+0x1f3020,"40534883ec204863dae872d6eaff488bc84c8b0041ff90e8000000488bcb48c1e10648034828488bc14883c4205bc3")
        || !bytes(c.exe+GRAPH_GETTER,"488d4160c3") || !bytes(c.exe+0x28d460,"488b8178010000c3"))return reject(CODE_MISMATCH)!=0;
    uint64_t root=0,api=0,target=0;
    if(!pointer(c.game+0x2ce14c8,root) || !pointer(root+0x20,api) || !slot_read(api+0x20,target))return reject(API_MISMATCH)!=0;
    address=api+0x20;if(!writable_slot(address,c.exe))return reject(SLOT_NOT_WRITABLE)!=0;
#if defined(NADSC_FIXTURE)
    if(target!=reinterpret_cast<uint64_t>(fixture_target))return reject(API_MISMATCH)!=0;
#else
    if(target!=c.exe+SETTER)return reject(API_MISMATCH)!=0;
#endif
    if(!executable(target))return reject(API_MISMATCH)!=0;setter=reinterpret_cast<Setter>(target);return true;
}
static bool config(const NADSC_Config* input,NADSC_Config& c) {
    if(!read(reinterpret_cast<uint64_t>(input),&c,sizeof c) || c.size!=sizeof c || c.abi!=1 || c.reserved!=0 || c.avatar_index>=8
        || !c.avatar || c.avatar==0xffffffff || !c.body || c.body==0xffffffff || !c.camera_unit || c.camera_unit==0xffffffff
        || c.context<65536 || c.camera<65536 || !std::isfinite(c.forward) || std::fabs(c.forward)>.5f
        || !std::isfinite(c.up) || std::fabs(c.up)>.5f || !std::isfinite(c.smoothing_ms) || c.smoothing_ms<0 || c.smoothing_ms>500
        || !std::isfinite(c.blend_ms) || c.blend_ms<0 || c.blend_ms>1000 || c.max_gap_ms<16 || c.max_gap_ms>1000)return reject(INVALID_CONFIG)!=0;
    return true;
}
static bool prepared(Policy& next) {
    uint32_t kind=0;float root[3]{},head[3]{},f[3]{},u[3]{};
    if(!owner(next,true) || !next.safe || !top(next,kind) || (kind!=4 && kind!=6))return reject(OWNER_MISMATCH)!=0;
    if(!graph(next,true) || !points(next,root,head))return reject(GRAPH_MISMATCH)!=0;
    if(kind==4 && !unparented(next))return reject(SPACE_INVALID)!=0;
    if(!basis(next,f,u))return reject(POSE_INVALID)!=0;return true;
}
static bool pin(const void* address) {
    HMODULE module=nullptr;return GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
        reinterpret_cast<LPCWSTR>(address),&module)!=0;
}
static bool restore_slot() {
    if(possible) {
        uint64_t current=0;if(!slot_read(slot,current))return false;
        if(current==callback()) {
            if(!writable_slot(slot,slot_image))return false;
            uint64_t observed=0;if(!cas(callback(),reinterpret_cast<uint64_t>(original.load()),observed))return false;
        }possible=false;
    }
    installed.store(0,std::memory_order_release);retired_generation=owned_generation;owned_generation=0;reserved.store(0,std::memory_order_release);return true;
}
static bool output_generation(uint64_t* output,uint64_t generation) {
    SIZE_T actual=0;return WriteProcessMemory(GetCurrentProcess(),output,&generation,8,&actual)!=0 && actual==8;
}
static uint32_t failed_begin(uint32_t cause,uint64_t* output) {
    armed.store(0,std::memory_order_release);callback_generation.store(0,std::memory_order_release);AcquireSRWLockExclusive(&policy_lock);ReleaseSRWLockExclusive(&policy_lock);
    if(!restore_slot()) {error(CLEANUP_PENDING);return 2;}output_generation(output,0);return reject(cause);
}
NADSC_EXPORT uint32_t NADSC_Validate(const NADSC_Config* input) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    NADSC_Config c{};if(!config(input,c))return 0;if(reserved.load())return reject(BUSY);
    Policy next{};next.c=c;Setter target=nullptr;uint64_t address=0;
    if(!prepared(next) || !contract(c,target,address))return 0;
    if(!owner(next,false))return reject(OWNER_MISMATCH);error(OK);return 1;
}
NADSC_EXPORT uint32_t NADSC_Begin(const NADSC_Config* input,uint64_t* output) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(!output_generation(output,0))return reject(INVALID_CONFIG);
    NADSC_Config c{};if(!config(input,c))return 0;if(reserved.load())return reject(BUSY);
    Policy next{};next.c=c;Setter target=nullptr;uint64_t address=0;
    if(!prepared(next) || !contract(c,target,address))return 0;
    if(original.load() && original.load()!=target)return reject(API_MISMATCH);
    if(!pin(reinterpret_cast<const void*>(&NADSC_Begin)))return reject(PIN_FAILED);
#if !defined(NADSC_FIXTURE)
    if(!pin(reinterpret_cast<const void*>(c.exe)))return reject(PIN_FAILED);
#endif
    original.store(target,std::memory_order_release);slot=address;slot_image=c.exe;possible=false;
    if(++generation_counter==0)++generation_counter;
    if(!output_generation(output,generation_counter))return reject(INVALID_CONFIG);
    owned_generation=generation_counter;reserved.store(1,std::memory_order_release);possible=true;
    display_cache=Display{next.blend,next.head_distance,next.last_dt};publish_diagnostics(next);
#if defined(NADSC_FIXTURE)
    if(fixture_begin_display_reached) {SetEvent(fixture_begin_display_reached);WaitForSingleObject(fixture_continue_begin,INFINITE);}
#endif
    if(!writable_slot(slot,c.exe))return failed_begin(SLOT_NOT_WRITABLE,output);
    uint64_t observed=0;if(!cas(reinterpret_cast<uint64_t>(target),callback(),observed))return failed_begin(CAS_FAULT,output);
    if(observed!=reinterpret_cast<uint64_t>(target)) {possible=false;return failed_begin(CAS_MISMATCH,output);}
    installed.store(1,std::memory_order_release);
    AcquireSRWLockExclusive(&policy_lock);uint32_t kind=0;
    const bool stable=owner(next,false) && top(next,kind) && (kind==4 || kind==6) && next.safe && graph(next,false) && dispatch_owned(next)
        && (kind!=4 || unparented(next));
    if(stable) {
        policy=next;seen.store(0);forwarded.store(0);replaced.store(0);native6_forwarded.store(0);resets.store(0);
        publish_diagnostics(policy);
        return_address.store(c.game+CALL+4,std::memory_order_relaxed);
        callback_generation.store(owned_generation,std::memory_order_release);armed.store(1,std::memory_order_release);
    }
    ReleaseSRWLockExclusive(&policy_lock);if(!stable)return failed_begin(OWNER_MISMATCH,output);error(OK);return 1;
}
NADSC_EXPORT uint32_t NADSC_End(uint64_t generation) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(!generation)return reject(TOKEN_MISMATCH);
    if(!reserved.load()) {if(generation!=retired_generation)return reject(TOKEN_MISMATCH);error(OK);return 1;}
    if(generation!=owned_generation)return reject(TOKEN_MISMATCH);
    armed.store(0,std::memory_order_release);callback_generation.store(0,std::memory_order_release);AcquireSRWLockExclusive(&policy_lock);reset(policy);publish_diagnostics(policy);ReleaseSRWLockExclusive(&policy_lock);
    if(!restore_slot())return reject(CLEANUP_PENDING);error(OK);return 1;
}
NADSC_EXPORT uint32_t NADSC_ReadStats(uint64_t generation,NADSC_Stats* output) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(reserved.load()?(!generation || generation!=owned_generation):generation!=0)return reject(TOKEN_MISMATCH);
    NADSC_Stats s{};if(!read(reinterpret_cast<uint64_t>(output),&s,sizeof s) || s.size!=sizeof s || s.abi!=1)return reject(INVALID_CONFIG);
    read_diagnostics(s);
    s.reserved=0;s.padding=0;s.installed=installed.load();s.armed=armed.load();s.error=last_error.load();
    s.seen=seen.load();s.forwarded=forwarded.load();s.replaced=replaced.load();s.native6_forwarded=native6_forwarded.load();s.resets=resets.load();
    SIZE_T actual=0;return WriteProcessMemory(GetCurrentProcess(),output,&s,sizeof s,&actual)!=0 && actual==sizeof s;
}
NADSC_EXPORT uint32_t NADSC_Error(void) {return last_error.load(std::memory_order_acquire);}

NADSC_EXPORT uint32_t NADSC_SetOffsets(uint64_t generation,float right,float forward,float up) {
    if(!std::isfinite(right)||!std::isfinite(forward)||!std::isfinite(up)
        ||std::fabs(right)>.5f||std::fabs(forward)>.5f||std::fabs(up)>.5f)return reject(INVALID_CONFIG);
    AcquireSRWLockExclusive(&control_lock);
    struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(!reserved.load()||!armed.load()||generation!=owned_generation)return reject(OWNER_MISMATCH);
    AcquireSRWLockExclusive(&policy_lock);
    const bool current=owner(policy,false);
    if(current){
        if(policy.presentation_enabled && policy.tracking && policy.relative_valid
           && (policy.side!=right || policy.c.forward!=forward || policy.c.up!=up))
            policy.correction.remember(policy.last_relative,policy.current_weapon,policy.last_relative_tick);
        policy.side=right;policy.c.forward=forward;policy.c.up=up;
    }
    ReleaseSRWLockExclusive(&policy_lock);
    if(!current)return reject(OWNER_MISMATCH);
    error(OK);return 1;
}

NADSC_EXPORT uint32_t NADSC_FreeAim(uint64_t generation,uint32_t milliseconds) {
    // Kept as an ABI-compatible cleanup entry. Render-only quaternion edits
    // desynchronise the native rig, so activation is explicitly unsupported.
    if(milliseconds!=0)return reject(INVALID_CONFIG);
    AcquireSRWLockExclusive(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockExclusive(&control_lock);}}unlock;
    if(!reserved.load()||!armed.load()||generation!=owned_generation)return reject(TOKEN_MISMATCH);
    AcquireSRWLockExclusive(&policy_lock);policy.free_aim.reset();policy.free_previous=policy.free_until=0;
    ReleaseSRWLockExclusive(&policy_lock);error(OK);return 1;
}
NADSC_EXPORT uint32_t NADSC_FreeAimStats(uint64_t generation,NADSC_FreeStats* out) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockExclusive(&control_lock);}}unlock;
    if(!reserved.load()||generation!=owned_generation)return 0;
    // One explicit diagnostic call, never a frame-loop subscription.
    AcquireSRWLockShared(&policy_lock);
    const double tick=now();
    NADSC_FreeStats s{sizeof(NADSC_FreeStats),policy.free_gate,policy.free_applied,policy.free_ads,
      policy.free_until>tick?static_cast<uint64_t>(policy.free_until-tick):0,policy.free_aim.offset_yaw,policy.free_aim.offset_pitch,policy.free_measured,policy.free_total_us,policy.free_max_us};
    ReleaseSRWLockShared(&policy_lock);
    SIZE_T done=0;return WriteProcessMemory(GetCurrentProcess(),out,&s,sizeof s,&done)&&done==sizeof s;
}

NADSC_EXPORT uint32_t NADSC_ObserveParent(uint64_t generation,uint32_t milliseconds) {
    if(milliseconds>3000)return 0;
    AcquireSRWLockExclusive(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockExclusive(&control_lock);}}unlock;
    if(!reserved.load()||!armed.load()||generation!=owned_generation)return 0;
    AcquireSRWLockExclusive(&policy_lock);
    const bool safe=policy.free_until==0&&owner(policy,false);
    if(safe){policy.observe_until=milliseconds?now()+milliseconds:0;policy.observe_samples=policy.observe_rejected=0;policy.observe_max_degrees=0;}
    ReleaseSRWLockExclusive(&policy_lock);return safe?1:0;
}
NADSC_EXPORT uint32_t NADSC_ParentStats(uint64_t generation,NADSC_ParentStats45* out) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockExclusive(&control_lock);}}unlock;
    if(!reserved.load()||generation!=owned_generation)return 0;
    AcquireSRWLockShared(&policy_lock);
    const double tick=now();NADSC_ParentStats45 s{policy.observe_samples,policy.observe_rejected,policy.observe_until>tick?static_cast<uint64_t>(policy.observe_until-tick):0,policy.observe_max_degrees,0};
    ReleaseSRWLockShared(&policy_lock);SIZE_T done=0;return WriteProcessMemory(GetCurrentProcess(),out,&s,sizeof s,&done)&&done==sizeof s;
}

NADSC_EXPORT uint32_t NADSC_SetKick46(uint64_t generation,uint32_t enabled) {
    if(enabled!=0)return reject(INVALID_CONFIG);
    AcquireSRWLockExclusive(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockExclusive(&control_lock);}}unlock;
    if(!reserved.load()||!armed.load()||generation!=owned_generation)return reject(TOKEN_MISMATCH);
    AcquireSRWLockExclusive(&policy_lock);policy.kick_enabled=false;policy.kick_angle=0;policy.kick_previous=0;
    ReleaseSRWLockExclusive(&policy_lock);error(OK);return 1;
}
NADSC_EXPORT uint32_t NADSC_KickStats46(uint64_t generation,NADSC_KickStats46Data* out) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockExclusive(&control_lock);}}unlock;
    if(!reserved.load()||generation!=owned_generation)return 0;
    AcquireSRWLockShared(&policy_lock);
    NADSC_KickStats46Data s{policy.kick_pulses,policy.kick_frames,policy.kick_enabled?1U:0U,policy.kick_angle};
    ReleaseSRWLockShared(&policy_lock);SIZE_T done=0;return WriteProcessMemory(GetCurrentProcess(),out,&s,sizeof s,&done)&&done==sizeof s;
}

NADSC_EXPORT uint32_t NADSC_SetPresentation47(uint64_t generation) {
 AcquireSRWLockExclusive(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockExclusive(&control_lock);}}unlock;
 if(!reserved.load()||!armed.load()||generation!=owned_generation)return 0;
 AcquireSRWLockExclusive(&policy_lock);
 const bool ok=owner(policy,false)&&dispatch_owned(policy)&&bytes(policy.c.game+0x110be87,"4c8d45c08b5308488b0b4c8b482041ff5120488b052856bd014c8d45008b5308488b0b4c8b482041ff5128");
 if(ok){policy.presentation_enabled=true;policy.correction.reset();}
 ReleaseSRWLockExclusive(&policy_lock);return ok?1:0;
}
NADSC_EXPORT uint32_t NADSC_SetCameraMotion47(uint64_t generation,float x,float y,float z,float pitch,float yaw,float roll){
 const float values[6]{x,y,z,pitch,yaw,roll};for(float v:values)if(!std::isfinite(v)||v!=0)return reject(INVALID_CONFIG);
 AcquireSRWLockExclusive(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockExclusive(&control_lock);}}unlock;
 if(!reserved.load()||!armed.load()||generation!=owned_generation)return 0;
 AcquireSRWLockExclusive(&policy_lock);std::memcpy(policy.motion,values,sizeof values);ReleaseSRWLockExclusive(&policy_lock);return 1;
}

NADSC_EXPORT uint32_t NADSC_Profile47(uint64_t generation,uint32_t count){
 if(!count||count>1000)return 0;AcquireSRWLockExclusive(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockExclusive(&control_lock);}}unlock;
 if(!reserved.load()||!armed.load()||generation!=owned_generation)return 0;
 AcquireSRWLockExclusive(&policy_lock);policy.profile_count=0;policy.profile_remaining=count;QueryPerformanceFrequency(&policy.profile_frequency);ReleaseSRWLockExclusive(&policy_lock);return 1;
}
NADSC_EXPORT uint32_t NADSC_ProfileStats47(uint64_t generation,NADSC_Profile47Data* out){
 AcquireSRWLockExclusive(&control_lock);struct Unlock{~Unlock(){ReleaseSRWLockExclusive(&control_lock);}}unlock;
 if(!reserved.load()||generation!=owned_generation)return 0;
 double times[1000]{};NADSC_Profile47Data s{};AcquireSRWLockShared(&policy_lock);
 s.remaining=policy.profile_remaining;s.count=policy.profile_count;std::memcpy(times,policy.profile_times,s.count*sizeof(double));ReleaseSRWLockShared(&policy_lock);
 if(s.count){std::sort(times,times+s.count);for(unsigned i=0;i<s.count;++i)s.mean_us+=times[i];s.mean_us/=s.count;s.max_us=times[s.count-1];s.p99_us=times[(s.count-1)*99/100];}
 SIZE_T done=0;return WriteProcessMemory(GetCurrentProcess(),out,&s,sizeof s,&done)&&done==sizeof s;
}
