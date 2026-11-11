// Hip/shoulder and FirdPerson projection policies share one existing API slot.
// Neither policy changes camera/weapon transforms or saved game settings.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <intrin.h>
#include "native_memory.h"
#include <atomic>
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <cmath>
#include "native_ads_fov.h"
using Setter=void (*)(void*,float);
static SRWLOCK control_lock=SRWLOCK_INIT,policy_lock=SRWLOCK_INIT;
static std::atomic<Setter> original{nullptr};
static std::atomic<uint32_t> installed{0},armed{0},reserved{0},last_error{0};
static std::atomic<uint64_t> seen{0},forwarded{0},replaced{0},immediate_applies{0},binds{0},ads_forwarded{0},return_address{0};
static uint64_t slot=0,slot_image=0,generation_counter=0,owned_generation=0,retired_generation=0;
static bool possible=false;
static constexpr uint32_t SETTER=0x2dd080,GETTER=0x2dd070,CALL=0x110bfda;
static constexpr float RAD_PER_DEG=0.01745329251994329577f;
enum Error:uint32_t { OK=0,INVALID_CONFIG=1,BUSY=2,READ_FAILED=3,IMAGE_MISMATCH=4,
    CODE_MISMATCH=5,API_MISMATCH=6,OWNER_MISMATCH=7,UNIT_MISMATCH=8,PIN_FAILED=9,
    SLOT_NOT_WRITABLE=10,CAS_MISMATCH=11,CAS_FAULT=12,CLEANUP_PENDING=13,
    SOURCE_INVALID=14,TOKEN_MISMATCH=17,REQUEST_SOURCE_MISMATCH=18,REQUEST_FIELD_INVALID=19 };
struct RequestField {
    uint64_t request=0,tag=0,tail=0;uint32_t before=0,last=0;bool active=false;
};
struct Policy {
    NADSF_Config c{};uint64_t controller=0,descriptor=0,registry=0,units=0,generations=0,body_object=0;
    uint8_t descriptor_bytes[20]{};bool shoulder_aim=false,full_ads=false,safe=false;
    bool shoulder_target=false,shoulder_clock=false;double shoulder_previous=0;
    float shoulder_weight=0;
    float last_native=0,last_applied=0,source_degrees=0;
    bool fird=false;float captured_radians=0;
    RequestField input_lens{};
    bool lens_ready=false,lens_ads=false,lens_blending=false;
    double lens_start=0;float lens_from=0,lens_last=0;
    bool shared_phase=false,shared_ads=false,shared_started=false,shared_ads_transition=false;
    uint64_t shared_epoch=0;float shared_progress=1,shared_used=0;double shared_at=0;
};
static Policy policy;
// Diagnostics must never make the update thread wait for an in-flight camera
// setter. Writers are serialized by policy_lock (or a disarmed new Begin).
// One bounded sequence check returns either a complete new tuple or the last
// complete tuple; lifecycle/health fields are read separately and stay fresh.
struct Display {float native=0,applied=0,degrees=0;};
static Display display_cache; // control_lock only; never accessed by a setter.
static std::atomic<uint32_t> display_sequence{0};
static std::atomic<float> display_native{0},display_applied{0},display_degrees{0};
static_assert(std::atomic<float>::is_always_lock_free,"FOV diagnostics require lock-free floats");
static void publish_diagnostics(const Policy& p) {
    display_sequence.fetch_add(1,std::memory_order_seq_cst);
    display_native.store(p.last_native,std::memory_order_seq_cst);
    display_applied.store(p.last_applied,std::memory_order_seq_cst);
    display_degrees.store(p.source_degrees,std::memory_order_seq_cst);
    display_sequence.fetch_add(1,std::memory_order_seq_cst);
}
static void read_diagnostics(NADSF_Stats& s) {
    const uint32_t before=display_sequence.load(std::memory_order_seq_cst);
    if((before&1)==0) {
        const Display next{display_native.load(std::memory_order_seq_cst),display_applied.load(std::memory_order_seq_cst),
            display_degrees.load(std::memory_order_seq_cst)};
        if(before==display_sequence.load(std::memory_order_seq_cst))display_cache=next;
    }
    s.last_native=display_cache.native;s.last_applied=display_cache.applied;s.source_degrees=display_cache.degrees;
}
#if defined(NADSF_FIXTURE)
static Setter fixture_target=nullptr;
static uint32_t fixture_cas_calls=0,fixture_cas_fail_at=0,fixture_foreign_cas_at=0;
static uint64_t fixture_foreign_value=0;
static bool fixture_slot_unreadable=false,fixture_slot_readonly=false;
static HANDLE fixture_before_arm_reached=nullptr,fixture_continue_arm=nullptr;
static uint64_t fixture_rpm_failure_at=0,fixture_rpm_failures=0,fixture_failure_queries=0;
static uint32_t fixture_rpm_failure_remaining=0;
static bool fixture_rpm_restore_readable=true;
static double fixture_now=0;static uint64_t fixture_clock_reads=0;
static bool fixture_clock_ok=true;
#endif
static bool seconds(double& out) {
#if defined(NADSF_FIXTURE)
    ++fixture_clock_reads;out=fixture_now;return fixture_clock_ok && std::isfinite(out);
#else
    static const double frequency=[]() {
        LARGE_INTEGER f{};return QueryPerformanceFrequency(&f) && f.QuadPart>0?static_cast<double>(f.QuadPart):0.0;
    }();
    LARGE_INTEGER ticks{};
    if(frequency<=0 || !QueryPerformanceCounter(&ticks))return false;
    out=static_cast<double>(ticks.QuadPart)/frequency;return std::isfinite(out);
#endif
}
static void reset_shoulder(Policy& p) {
    p.shoulder_weight=0;p.shoulder_target=false;p.shoulder_clock=false;
}
static float shoulder_lens(Policy& p,float hip) {
    const float target=p.shoulder_aim?1.0f:0.0f;
    if(p.shared_phase) {
        // The shared phase supplies the entire normal-aim lens handoff too;
        // stacking the former local tween would put the lens behind the rig.
        p.shoulder_weight=target;p.shoulder_target=p.shoulder_aim;p.shoulder_clock=false;
        return target==0?hip:2*std::atan(std::tan(hip*.5f)/1.05f);
    }
    // Settled hip is bit-exact TPV, without clock sampling or trigonometry.
    // A settled shoulder also needs no clock until the aim state changes.
    if(p.shoulder_weight!=target) {
        double now=0;
        if(!seconds(now)) {reset_shoulder(p);return hip;}
        if(!p.shoulder_clock || p.shoulder_target!=p.shoulder_aim) {
            p.shoulder_target=p.shoulder_aim;p.shoulder_clock=true;
        } else {
            const double elapsed=now-p.shoulder_previous;
            // Rebase after a pause/rollback; never integrate an unbounded gap.
            if(elapsed>=0 && elapsed<=.25) {
                const float step=static_cast<float>(fmin(elapsed,.12)/.12);
                p.shoulder_weight=p.shoulder_aim?fminf(1,p.shoulder_weight+step):fmaxf(0,p.shoulder_weight-step);
            }
        }
        p.shoulder_previous=now;
    }
    if(p.shoulder_weight==0)return hip;
    const float w=p.shoulder_weight*p.shoulder_weight*(3-2*p.shoulder_weight);
    return 2*std::atan(std::tan(hip*.5f)/(1+.05f*w));
}
// Opt-in handoff on this already-owned camera. Blend focal magnification,
// preserving the fresh native lens and exact settled values, including zoom.
static void reset_lens(Policy& p) {p.lens_ready=false;p.lens_blending=false;}
static float phase_ease(float x) {return x*x*(3-2*x);}
static bool shared_lens(Policy& p,float target,bool ads,float& result) {
    if(!p.shared_phase)return false;
    double now=0;
    if(!seconds(now) || now<p.shared_at || now-p.shared_at>.25) {
        // An interrupted Lua producer must not freeze a native sight halfway.
        p.shared_phase=false;reset_lens(p);result=target;return true;
    }
    if(p.shared_ads!=ads) {
        // Native ownership is authoritative while the qualified token catches
        // up to a mode change. Never delay ADS using a token for the old mode.
        p.shared_started=false;p.lens_ready=true;p.lens_ads=ads;
        p.lens_blending=false;p.lens_last=target;result=target;return true;
    }
    if(!p.shared_started) {p.shared_started=true;p.shared_used=0;}
    result=target;
    if(p.lens_ready && p.shared_progress<1) {
        if(p.shared_progress==p.shared_used)result=p.lens_last;
        else {
        const float prior=phase_ease(p.shared_used),current=phase_ease(p.shared_progress);
        const float step=std::min(1.0f,std::max(0.0f,(current-prior)/std::max(.000001f,1-prior)));
        // Rebase every solve on the actual prior presentation. A new zoom or
        // late native lens solve cannot jump around the shared handoff curve.
        const float from=1/std::tan(p.lens_last*.5f),to=1/std::tan(target*.5f);
        result=2*std::atan(1/(from+(to-from)*step));
        }
    }
    p.shared_used=p.shared_progress;p.lens_ready=true;p.lens_ads=ads;
    p.lens_blending=p.shared_ads_transition && p.shared_progress<1;p.lens_last=result;return true;
}
static float handoff_lens(Policy& p,float target,bool ads) {
    if(!p.c.reserved || p.fird)return target;
    if(!std::isfinite(target) || target<=0 || target>=3.14159265f){reset_lens(p);return target;}
    float shared=target;if(shared_lens(p,target,ads,shared))return shared;
    if(!p.lens_ready){p.lens_ready=true;p.lens_ads=ads;p.lens_last=target;return target;}
    double now=0;
    if(ads!=p.lens_ads) {
        if(!seconds(now)){reset_lens(p);return target;}
        p.lens_ads=ads;p.lens_from=p.lens_last;p.lens_start=now;p.lens_blending=true;
    }
    float result=target;
    if(p.lens_blending) {
        if(!now && !seconds(now)){reset_lens(p);return target;}
        const double elapsed=now-p.lens_start,duration=static_cast<double>(p.c.reserved)/1000;
        if(elapsed<0 || elapsed>=duration){p.lens_blending=false;}
        else {
            const float t=static_cast<float>(elapsed/duration),w=t*t*(3-2*t);
            const float from=1/std::tan(p.lens_from*.5f),to=1/std::tan(target*.5f);
            result=2*std::atan(1/(from+(to-from)*w));
        }
    }
    p.lens_last=result;return result;
}
// Fault evidence belongs to one explicit owner-data guard. Successful reads
// take the original RPM path; only an actual failure queries memory mappings.
// Optional history/code/diagnostic reads outside this scope cannot taint it.
struct OwnerReadProbe;
static thread_local OwnerReadProbe* owner_read_probe=nullptr;
struct OwnerReadProbe {
    OwnerReadProbe* previous;bool transport=false,unsafe=false;
    OwnerReadProbe():previous(owner_read_probe){owner_read_probe=this;}
    ~OwnerReadProbe(){owner_read_probe=previous;}
    OwnerReadProbe(const OwnerReadProbe&)=delete;
    OwnerReadProbe& operator=(const OwnerReadProbe&)=delete;
};
static bool readable_span(uint64_t at,size_t length) {
    const uint64_t end=at+length;uint64_t cursor=at;
    for(unsigned regions=0;cursor<end && regions<4;++regions) {
#if defined(NADSF_FIXTURE)
        ++fixture_failure_queries;
#endif
        MEMORY_BASIC_INFORMATION region{};
        if(VirtualQuery(reinterpret_cast<const void*>(cursor),&region,sizeof region)!=sizeof region
            || region.State!=MEM_COMMIT || (region.Protect&(PAGE_GUARD|PAGE_NOACCESS)))return false;
        const DWORD protection=region.Protect&0xff;
        if(protection!=PAGE_READONLY && protection!=PAGE_READWRITE && protection!=PAGE_WRITECOPY
            && protection!=PAGE_EXECUTE_READ && protection!=PAGE_EXECUTE_READWRITE && protection!=PAGE_EXECUTE_WRITECOPY)return false;
        const uint64_t base=reinterpret_cast<uint64_t>(region.BaseAddress),next=base+region.RegionSize;
        if(base>cursor || next<=cursor || next>0x800000000000ULL)return false;
        cursor=next<end?next:end;
    }
    return cursor==end;
}
static bool read(uint64_t at,void* out,size_t length) {
    if(at<65536 || at>=0x800000000000ULL || length==0 || length>1024 || at+length>=0x800000000000ULL) {
        if(owner_read_probe)owner_read_probe->unsafe=true;return false;
    }
#if defined(NADSF_FIXTURE)
    // Real OS failure on a private fixture data page, never the game/stack.
    DWORD fixture_old_protection=0;
    const bool fixture_fault=fixture_rpm_failure_remaining && at==fixture_rpm_failure_at;
    const bool fixture_protected=fixture_fault && (--fixture_rpm_failure_remaining,
        VirtualProtect(reinterpret_cast<void*>(at),length,PAGE_NOACCESS,&fixture_old_protection)!=0);
#endif
    SIZE_T actual=0;
    const bool complete=ReadProcessMemory(GetCurrentProcess(),reinterpret_cast<const void*>(at),out,length,&actual)!=0 && actual==length;
#if defined(NADSF_FIXTURE)
    if(fixture_protected) {
        if(!complete)++fixture_rpm_failures;
        if(fixture_rpm_restore_readable) {DWORD ignored=0;VirtualProtect(reinterpret_cast<void*>(at),length,fixture_old_protection,&ignored);}
    }
#endif
    if(complete)return true;
    if(owner_read_probe) {
        if(readable_span(at,length))owner_read_probe->transport=true;
        else owner_read_probe->unsafe=true;
    }
    return false;
}
template<class T> static bool value(uint64_t at,T& out) {return read(at,&out,sizeof out);}
static bool pointer(uint64_t at,uint64_t& out) {
    if(!value(at,out))return false;
    if(out>=65536 && out<0x800000000000ULL)return true;
    if(owner_read_probe)owner_read_probe->unsafe=true;return false;
}
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
// Only an invocation-local owner-data failure may produce retryable code3.
// Code, source, dispatch, configuration and diagnostic reads are unclassified.
static uint32_t owner_status(Policy& p,bool capture) {
    OwnerReadProbe probe;
    if(owner(p,capture))return OK;
    return probe.transport && !probe.unsafe?READ_FAILED:OWNER_MISMATCH;
}
static bool checked_owner(Policy& p,bool capture,uint32_t& failure) {
    failure=owner_status(p,capture);return failure==OK;
}
static bool current_request(const Policy& p,uint64_t& at,uint32_t (&r)[4],bool& queued) {
    uint32_t head=0,tail=0;
    if(!value(p.c.context+0x1F8,head) || !value(p.c.context+0x1FC,tail) || head>=32 || tail>=32)return false;
    queued=head!=tail;at=queued?p.c.context+0x200+((tail+31)%32)*0xE8:p.c.context+0x1F00;
    return read(at,r,16) && r[1]==p.c.avatar;
}
static bool request_matches(const Policy& p,bool allow_normal=false) {
    uint64_t at=0;uint32_t r[4]{};bool queued=false;
    if(!current_request(p,at,r,queued) || at!=p.c.request)return false;
    if(p.fird)return (r[0]&0xffff)==4;
    if(allow_normal && (r[0]&0xffff)==4)return true;
    return queued && (r[0]&0xffff)==6 && r[2]==p.c.weapon && r[3]==p.c.body;
}
static bool native_ads_request(const Policy& p) {
    uint64_t at=0;uint32_t r[4]{};bool queued=false;
    return current_request(p,at,r,queued) && queued && (r[0]&0xffff)==6;
}
static bool captured_lens(float radians) {
    return std::isfinite(radians) && radians>=10*RAD_PER_DEG && radians<=170*RAD_PER_DEG;
}
// Normal4 input selects the FIRST normal request from the ring head, whereas
// presentation binds the top request. They can be different owned normal4
// rows during a fade; only the actual input source needs normalization.
static bool fird_request_field(const Policy& p,uint64_t& at,uint64_t& tag,uint64_t& tail_tag) {
    if(!p.fird || !request_matches(p))return false;
    uint32_t head=0,tail=0;
    if(!value(p.c.context+0x1F8,head) || !value(p.c.context+0x1FC,tail) || head>=32 || tail>=32)return false;
    uint64_t request=p.c.request;
    if(head!=tail) {
        bool found=false;
        for(uint32_t index=head;index!=tail;index=(index+1)%32) {
            const uint64_t row=p.c.context+0x200+static_cast<uint64_t>(index)*0xE8;uint16_t kind=0;
            if(!value(row,kind))return false;
            if(kind==4) {request=row;found=true;break;}
        }
        if(!found)return false;
    }
    uint64_t header[2]{};
    if(!read(request,header,sizeof header) || static_cast<uint16_t>(header[0])!=4 || static_cast<uint32_t>(header[0]>>32)!=p.c.avatar)return false;
    tag=header[0];tail_tag=header[1];
    at=request+0x3C;return true;
}
static bool active_normal_request(const Policy& p,uint64_t request,uint64_t tag,uint64_t tail_tag) {
    uint32_t head=0,tail=0;uint64_t actual[2]{};
    if(!value(p.c.context+0x1F8,head) || !value(p.c.context+0x1FC,tail) || head>=32 || tail>=32)return false;
    bool active=head==tail && request==p.c.context+0x1F00;
    for(uint32_t index=head;!active && index!=tail;index=(index+1)%32)
        active=request==p.c.context+0x200+static_cast<uint64_t>(index)*0xE8;
    return active && read(request,actual,sizeof actual) && actual[0]==tag && actual[1]==tail_tag
        && static_cast<uint16_t>(actual[0])==4 && static_cast<uint32_t>(actual[0]>>32)==p.c.avatar;
}
static bool writable_request_field(uint64_t at) {
    MEMORY_BASIC_INFORMATION r{};
    if((at&3)!=0 || VirtualQuery(reinterpret_cast<const void*>(at),&r,sizeof r)!=sizeof r || r.State!=MEM_COMMIT
        || (r.Protect!=PAGE_READWRITE && r.Protect!=PAGE_WRITECOPY)
        || at+4>reinterpret_cast<uint64_t>(r.BaseAddress)+r.RegionSize)return false;
    return true;
}
static bool finite_request_lens(uint32_t bits) {
    float radians=0;std::memcpy(&radians,&bits,4);
    return std::isfinite(radians) && radians>0 && radians<3.14159265358979323846f;
}
static bool request_cas(uint64_t at,uint32_t expected,uint32_t desired,uint32_t& observed) {
    __try {
        observed=static_cast<uint32_t>(InterlockedCompareExchange(reinterpret_cast<volatile LONG*>(at),
            static_cast<LONG>(desired),static_cast<LONG>(expected)));return true;
    } __except(EXCEPTION_EXECUTE_HANDLER) {return false;}
}
static bool validate_fird_request_field(const Policy& p) {
    uint64_t at=0,tag=0,tail_tag=0;uint32_t native=0;
    return fird_request_field(p,at,tag,tail_tag) && value(at,native) && finite_request_lens(native) && writable_request_field(at);
}
static bool restore_fird_request(Policy& p);
// policy_lock owns the ledger. A new native evaluation can replace our value;
// keep its freshest finite value for End, and compare before every data write.
static bool normalize_fird_request(Policy& p,bool post_evaluation=false,uint32_t* owner_failure=nullptr) {
    uint64_t at=0,tag=0,tail_tag=0;uint32_t native=0,fixed=0;
    if(!fird_request_field(p,at,tag,tail_tag)) {error(REQUEST_SOURCE_MISMATCH);return false;}
    if(!value(at,native) || !finite_request_lens(native) || !writable_request_field(at)) {error(REQUEST_FIELD_INVALID);return false;}
    std::memcpy(&fixed,&p.captured_radians,4);
    auto& l=p.input_lens;
    if(l.active && (l.request!=at-0x3C || l.tag!=tag || l.tail!=tail_tag)) {
        // A setter callback follows native evaluation, but an older queue row
        // can have returned early. Its equal value cannot prove freshness or
        // ownership; retire without replay. Immediate Begin/Bind can compare-
        // restore the still-owned old source because they do not evaluate it.
        if(post_evaluation)l=RequestField{};
        else if(!restore_fird_request(p)) {error(CLEANUP_PENDING);return false;}
        if(!value(at,native) || !finite_request_lens(native)) {error(REQUEST_FIELD_INVALID);return false;}
    }
    // The verified callback follows evaluation, but a normal4 row can return
    // early. Equality with our last value is therefore ambiguous: conservatively
    // retain the observed value and never replay an older native lens. Begin/
    // Bind do not evaluate and can preserve their existing restoration value.
    const uint32_t before=!post_evaluation && l.active && native==l.last?l.before:native;
    uint64_t checked_at=0,checked_tag=0,checked_tail=0;
    const uint32_t failure=owner_status(p,false);
    if(owner_failure)*owner_failure=failure;
    if(failure!=OK || p.full_ads || !p.safe || !fird_request_field(p,checked_at,checked_tag,checked_tail)
        || checked_at!=at || checked_tag!=tag || checked_tail!=tail_tag) {
        error(failure==OK?OWNER_MISMATCH:failure);return false;
    }
    uint32_t observed=0;
    if(!request_cas(at,native,fixed,observed)) {error(CAS_FAULT);return false;}
    if(observed!=native) {l=RequestField{};error(CAS_MISMATCH);return false;}
    l.request=at-0x3C;l.tag=tag;l.tail=tail_tag;l.before=before;l.last=fixed;l.active=true;return true;
}
// Lost/replaced requests are never replayed. Retain cleanup ownership only
// when this same live normal4 field still equals our last authored value and
// a bounded read/CAS cannot yet complete.
static bool restore_fird_request(Policy& p) {
    auto& l=p.input_lens;if(!l.active)return true;
    const uint64_t at=l.request+0x3C;
    if(!owner(p,false) || !active_normal_request(p,l.request,l.tag,l.tail)) {
        l=RequestField{};return true;
    }
    uint32_t current=0;if(!value(at,current))return false;
    if(current!=l.last || l.before==l.last) {l=RequestField{};return true;}
    if(!writable_request_field(at))return false;
    if(!owner(p,false) || !active_normal_request(p,l.request,l.tag,l.tail)) {
        l=RequestField{};return true;
    }
    uint32_t observed=0;if(!request_cas(at,l.last,l.before,observed))return false;
    l=RequestField{};return true;
}
static bool source(Policy& p,float& radians) {
    uint64_t settings=0;float degrees=0;
    if(!pointer(p.c.game+0x2ce1508,settings) || !value(settings+0xac488,degrees)
        || !std::isfinite(degrees) || degrees<1 || degrees>179)return false;
    radians=degrees*RAD_PER_DEG;p.source_degrees=degrees;return std::isfinite(radians);
}
static bool writable_slot(uint64_t at,uint64_t exe) {
    if((at&7)!=0)return false;
#if defined(NADSF_FIXTURE)
    if(fixture_slot_readonly)return false;
    (void)exe;
#endif
    MEMORY_BASIC_INFORMATION r{};
    if(VirtualQuery(reinterpret_cast<const void*>(at),&r,sizeof r)!=sizeof r || r.State!=MEM_COMMIT || !writable_pe_protection(r.Protect)
        || at+8>reinterpret_cast<uint64_t>(r.BaseAddress)+r.RegionSize)return false;
#if !defined(NADSF_FIXTURE)
    return pe_section_mapping(r) && reinterpret_cast<uint64_t>(r.AllocationBase)==exe;
#else
    return r.Type==MEM_PRIVATE;
#endif
}
static bool slot_read(uint64_t at,uint64_t& out) {
#if defined(NADSF_FIXTURE)
    if(fixture_slot_unreadable)return false;
#endif
    return value(at,out);
}
static bool cas(uint64_t expected,uint64_t desired,uint64_t& observed) {
#if defined(NADSF_FIXTURE)
    if(++fixture_cas_calls==fixture_cas_fail_at)return false;
    if(fixture_cas_calls==fixture_foreign_cas_at)InterlockedExchangePointer(reinterpret_cast<PVOID volatile*>(slot),reinterpret_cast<void*>(fixture_foreign_value));
#endif
    __try {
        observed=reinterpret_cast<uint64_t>(InterlockedCompareExchangePointer(reinterpret_cast<PVOID volatile*>(slot),
            reinterpret_cast<void*>(desired),reinterpret_cast<void*>(expected)));return true;
    } __except(EXCEPTION_EXECUTE_HANDLER) {return false;}
}
static bool binary_contract(const NADSF_Config& c) {
    if(!image(c.game,0x6af322c1,0x3382000) || !image(c.exe,0x6af2d5e6,0x29fe000))return reject(IMAGE_MISMATCH)!=0;
    if(!bytes(c.game+CALL,"ff9280000000") || !bytes(c.exe+SETTER,"f30f114934c7415000000000e92f6c1f00")
        || !bytes(c.exe+GETTER,"f30f104134c3"))return reject(CODE_MISMATCH)!=0;
    return true;
}
static bool fird_input_contract(const NADSF_Config& c) {
    // Current-build evaluator dispatch precedes the shared CameraAPI setter.
    // Normal4 publishes radians at3C after its input read; the next input pass
    // selects the first kind4 and scales by radians*RAD2DEG/live TP degrees.
    if(!bytes(c.game+0x110b4db,"e8e0fc0000")
        || !bytes(c.game+0x111e3ce,"f3450f119c24c4000000f3450f115c243c")
        || !bytes(c.game+0x111ba5e,"f3410f1044243c")
        || !bytes(c.game+0x111ba70,"448bc14969c0e8000000664283bc300002000004740bffc183e11f3bca75e1eb11")
        || !bytes(c.game+0x111ba91,"4969c0e8000000f3420f1084303c020000")
        || !bytes(c.game+0x111baa2,"f30f590506b51201488d55a0488b05535abc01f30f5e8088c40a00f30f59d8f30f59d0f30f59c8"))
        return reject(CODE_MISMATCH)!=0;
    return true;
}
static bool contract(const NADSF_Config& c,Setter& setter,uint64_t& address) {
    if(!binary_contract(c))return false;
    uint64_t root=0,api=0,target=0,getter=0;
    if(!pointer(c.game+0x2ce14c8,root) || !pointer(root+0x20,api) || !slot_read(api+0x80,target)
        || !pointer(api+0x78,getter) || getter!=c.exe+GETTER)return reject(API_MISMATCH)!=0;
    address=api+0x80;
    if(!writable_slot(address,c.exe))return reject(SLOT_NOT_WRITABLE)!=0;
#if defined(NADSF_FIXTURE)
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
    return pointer(p.c.game+0x2ce14c8,root) && pointer(root+0x20,api) && api+0x80==slot
        && pointer(api+0x78,getter) && getter==p.c.exe+GETTER && slot_read(slot,target) && target==callback();
}
// Called under policy_lock. It invokes the pinned original, never the API slot.
static bool apply_immediately(Policy& p,uint32_t& failure) {
    if(!checked_owner(p,false,failure) || !request_matches(p) || !p.safe || !dispatch_owned(p))return false;
    if(p.full_ads) {reset_shoulder(p);return true;}
    float radians=p.captured_radians;
    if(!p.fird) {if(!source(p,radians))return false;radians=shoulder_lens(p,radians);}
    else if(!normalize_fird_request(p,false,&failure))return false;
    radians=handoff_lens(p,radians,false);
    original.load(std::memory_order_acquire)(reinterpret_cast<void*>(p.c.camera),radians);
    p.last_applied=radians;immediate_applies.fetch_add(1,std::memory_order_relaxed);return true;
}
static void setter_hook(void* camera,float native) {
    seen.fetch_add(1,std::memory_order_relaxed);
    if(!armed.load(std::memory_order_acquire) || reinterpret_cast<uint64_t>(_ReturnAddress())!=return_address.load(std::memory_order_relaxed)) {
        forwarded.fetch_add(1,std::memory_order_relaxed);original.load(std::memory_order_acquire)(camera,native);return;
    }
    AcquireSRWLockExclusive(&policy_lock);
    struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&policy_lock);}} unlock;
    float applied=native;bool diagnostics_changed=false;
    if(armed.load(std::memory_order_acquire) && reinterpret_cast<uint64_t>(camera)==policy.c.camera) {
        const uint32_t failure=owner_status(policy,false);
        if(failure!=OK) {armed.store(0,std::memory_order_release);error(failure);}
        else if(!dispatch_owned(policy)) {armed.store(0,std::memory_order_release);error(API_MISMATCH);}
        else {
        if(policy.fird && (native_ads_request(policy) || (policy.full_ads && request_matches(policy)))) {
            // Camera6 can precede the controller's full-ADS bit. The current
            // request itself takes priority over the retained normal4 lease.
            policy.last_native=policy.last_applied=native;
            policy.input_lens=RequestField{};
            ads_forwarded.fetch_add(1,std::memory_order_relaxed);diagnostics_changed=true;
        } else if(!policy.fird && policy.c.reserved && policy.full_ads && policy.safe && [&]() {
            uint64_t at=0;uint32_t r[4]{};bool queued=false;
            return current_request(policy,at,r,queued) && queued && (r[0]&0xffff)==6
                && r[2]==policy.c.weapon && r[3]==policy.c.body;
        }()) {
            reset_shoulder(policy);applied=handoff_lens(policy,native,true);
            policy.last_native=native;policy.last_applied=applied;
            ads_forwarded.fetch_add(1,std::memory_order_relaxed);diagnostics_changed=true;
        } else if(!policy.fird && policy.c.reserved && policy.safe && policy.lens_ready
            && (policy.lens_ads || policy.lens_blending) && [&]() {
                uint64_t at=0;uint32_t r[4]{};bool queued=false;
                return current_request(policy,at,r,queued) && ((r[0]&0xffff)==4
                    || (queued && (r[0]&0xffff)==6 && r[2]==policy.c.weapon && r[3]==policy.c.body));
            }()) {
            reset_shoulder(policy);float target=native;
            uint64_t at=0;uint32_t r[4]{};bool queued=false;
            if(current_request(policy,at,r,queued) && (r[0]&0xffff)==6)source(policy,target);
            applied=handoff_lens(policy,target,false);
            policy.last_native=native;policy.last_applied=applied;diagnostics_changed=true;
        } else if(request_matches(policy) && policy.safe) {
            policy.last_native=native;
            if(policy.full_ads) {reset_shoulder(policy);ads_forwarded.fetch_add(1,std::memory_order_relaxed);}
            else if(policy.fird) {
                if(normalize_fird_request(policy,true)) {
                    applied=policy.captured_radians;replaced.fetch_add(1,std::memory_order_relaxed);
                } else {
                    policy.input_lens=RequestField{};armed.store(0,std::memory_order_release);
                }
            } else if(source(policy,applied)) {
                applied=shoulder_lens(policy,applied);replaced.fetch_add(1,std::memory_order_relaxed);
            } else reset_shoulder(policy);
            applied=handoff_lens(policy,applied,policy.full_ads);
            policy.last_applied=applied;
            diagnostics_changed=true;
        } else {
            reset_shoulder(policy);reset_lens(policy);
            if(policy.fird)policy.input_lens=RequestField{};
        }
        }
    }
    forwarded.fetch_add(1,std::memory_order_relaxed);original.load(std::memory_order_acquire)(camera,applied);
    if(diagnostics_changed)publish_diagnostics(policy);
}
static uint64_t callback() {return reinterpret_cast<uint64_t>(setter_hook);}
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
        }
        possible=false;
    }
    installed.store(0,std::memory_order_release);retired_generation=owned_generation;owned_generation=0;
    reserved.store(0,std::memory_order_release);return true;
}
static bool output_generation(uint64_t* output,uint64_t generation) {
    SIZE_T actual=0;return WriteProcessMemory(GetCurrentProcess(),output,&generation,8,&actual)!=0 && actual==8;
}
static uint32_t failed_begin(uint32_t cause,uint64_t* output) {
    armed.store(0,std::memory_order_release);
    AcquireSRWLockExclusive(&policy_lock);const bool restored=restore_fird_request(policy);ReleaseSRWLockExclusive(&policy_lock);
    if(!restored) {error(CLEANUP_PENDING);return 2;}
    if(!restore_slot()) {error(CLEANUP_PENDING);return 2;}
    output_generation(output,0);return reject(cause);
}
static bool config(const NADSF_Config* input,NADSF_Config& c,bool fird=false) {
    if(!read(reinterpret_cast<uint64_t>(input),&c,sizeof c) || c.size!=sizeof c || c.abi!=1 || (c.reserved!=0 && (fird || c.reserved<80 || c.reserved>500))
        || c.avatar_index>=8 || !c.avatar || c.avatar==0xffffffff || !c.body || c.body==0xffffffff
        || (!fird && (!c.weapon || c.weapon==0xffffffff)) || c.context<65536 || c.camera<65536 || c.request<65536)return reject(INVALID_CONFIG)!=0;
    return true;
}
NADSF_EXPORT uint32_t NADSF_Validate(const NADSF_Config* input) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    NADSF_Config c{};if(!config(input,c))return 0;if(reserved.load())return reject(BUSY);
    Policy next{};next.c=c;Setter target=nullptr;uint64_t address=0;float radians=0;
    uint32_t failure=OK;
    if(!checked_owner(next,true,failure) || !next.safe || !request_matches(next,true))return reject(failure==OK?OWNER_MISMATCH:failure);
    if(!contract(c,target,address))return 0;if(!source(next,radians))return reject(SOURCE_INVALID);
    if(!checked_owner(next,false,failure) || !next.safe || !request_matches(next,true))return reject(failure==OK?OWNER_MISMATCH:failure);
    error(OK);return 1;
}
NADSF_EXPORT uint32_t NADSF_ValidateFird(const NADSF_Config* input) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    NADSF_Config c{};if(!config(input,c,true))return 0;if(reserved.load())return reject(BUSY);
    Policy next{};next.c=c;next.fird=true;Setter target=nullptr;uint64_t address=0;
    uint32_t failure=OK;
    if(!checked_owner(next,true,failure) || !next.safe || next.full_ads || !request_matches(next))return reject(failure==OK?OWNER_MISMATCH:failure);
    if(!contract(c,target,address) || !fird_input_contract(c))return 0;
    if(!validate_fird_request_field(next))return reject(REQUEST_FIELD_INVALID);
    if(!checked_owner(next,false,failure) || !next.safe || next.full_ads || !request_matches(next))return reject(failure==OK?OWNER_MISMATCH:failure);
    error(OK);return 1;
}
static uint32_t begin_policy(const NADSF_Config* input,uint64_t* output,bool fird,float captured) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(!output_generation(output,0))return reject(INVALID_CONFIG);
    NADSF_Config c{};if(!config(input,c,fird))return 0;if(reserved.load())return reject(BUSY);
    Policy next{};next.c=c;Setter target=nullptr;uint64_t address=0;float radians=0;
    next.fird=fird;next.captured_radians=captured;
    if(fird) {if(!captured_lens(captured))return reject(SOURCE_INVALID);next.source_degrees=captured/RAD_PER_DEG;}
    uint32_t failure=OK;
    if(!checked_owner(next,true,failure) || !next.safe || (fird && next.full_ads) || !request_matches(next))return reject(failure==OK?OWNER_MISMATCH:failure);
    if(!contract(c,target,address))return 0;
    if(fird && (!fird_input_contract(c) || !validate_fird_request_field(next)))return reject(REQUEST_FIELD_INVALID);
    if(!fird && !source(next,radians))return reject(SOURCE_INVALID);
    if(original.load() && original.load()!=target)return reject(API_MISMATCH);
    if(!pin(reinterpret_cast<const void*>(&NADSF_Begin)))return reject(PIN_FAILED);
#if !defined(NADSF_FIXTURE)
    if(!pin(reinterpret_cast<const void*>(c.exe)))return reject(PIN_FAILED);
#endif
    original.store(target,std::memory_order_release);slot=address;slot_image=c.exe;possible=false;
    if(++generation_counter==0)++generation_counter;
    if(!output_generation(output,generation_counter))return reject(INVALID_CONFIG);
    owned_generation=generation_counter;reserved.store(1,std::memory_order_release);possible=true;
    display_cache=Display{0,0,next.source_degrees};publish_diagnostics(next);
    if(!writable_slot(slot,c.exe))return failed_begin(SLOT_NOT_WRITABLE,output);
    uint64_t observed=0;if(!cas(reinterpret_cast<uint64_t>(target),callback(),observed))return failed_begin(CAS_FAULT,output);
    if(observed!=reinterpret_cast<uint64_t>(target)) {possible=false;return failed_begin(CAS_MISMATCH,output);}
    installed.store(1,std::memory_order_release);
    if(!dispatch_owned(next))return failed_begin(CAS_MISMATCH,output);
    AcquireSRWLockExclusive(&policy_lock);
    policy=next;seen.store(0);forwarded.store(0);replaced.store(0);immediate_applies.store(0);binds.store(0);ads_forwarded.store(0);
    const bool applied=apply_immediately(policy,failure);
    const bool stable=applied && checked_owner(policy,false,failure) && request_matches(policy) && policy.safe && (!fird || !policy.full_ads) && dispatch_owned(policy);
    publish_diagnostics(policy);
    return_address.store(c.game+CALL+6,std::memory_order_relaxed);
#if defined(NADSF_FIXTURE)
    if(fixture_before_arm_reached) {SetEvent(fixture_before_arm_reached);WaitForSingleObject(fixture_continue_arm,INFINITE);}
#endif
    if(stable)armed.store(1,std::memory_order_release);
    ReleaseSRWLockExclusive(&policy_lock);
    if(!stable)return failed_begin(failure==OK?OWNER_MISMATCH:failure,output);
    error(OK);return 1;
}
NADSF_EXPORT uint32_t NADSF_Begin(const NADSF_Config* input,uint64_t* output) {
    return begin_policy(input,output,false,0);
}
NADSF_EXPORT uint32_t NADSF_BeginFird(const NADSF_Config* input,float captured,uint64_t* output) {
    return begin_policy(input,output,true,captured);
}
NADSF_EXPORT uint32_t NADSF_Bind(uint64_t generation,uint64_t request,uint32_t weapon) {
    AcquireSRWLockExclusive(&control_lock);struct UnlockControl {~UnlockControl(){ReleaseSRWLockExclusive(&control_lock);}} unlock_control;
    if(!generation || !reserved.load() || generation!=owned_generation)return reject(TOKEN_MISMATCH);
    if(request<65536 || !weapon || weapon==0xffffffff)return reject(INVALID_CONFIG);
    AcquireSRWLockExclusive(&policy_lock);struct UnlockPolicy {~UnlockPolicy(){ReleaseSRWLockExclusive(&policy_lock);}} unlock_policy;
    if(!armed.load() || policy.fird)return reject(OWNER_MISMATCH);
    Policy next=policy;next.c.request=request;next.c.weapon=weapon;
    uint32_t failure=OK;
    if(!checked_owner(next,false,failure) || !next.safe || !request_matches(next))return reject(failure==OK?OWNER_MISMATCH:failure);
    if(!binary_contract(next.c) || !dispatch_owned(next))return reject(API_MISMATCH);
    if(!apply_immediately(next,failure) || !checked_owner(next,false,failure) || !request_matches(next) || !next.safe || !dispatch_owned(next))return reject(failure==OK?OWNER_MISMATCH:failure);
    policy=next;publish_diagnostics(policy);binds.fetch_add(1,std::memory_order_relaxed);error(OK);return 1;
}
NADSF_EXPORT uint32_t NADSF_BindFird(uint64_t generation,uint64_t request) {
    AcquireSRWLockExclusive(&control_lock);struct UnlockControl {~UnlockControl(){ReleaseSRWLockExclusive(&control_lock);}} unlock_control;
    if(!generation || !reserved.load() || generation!=owned_generation)return reject(TOKEN_MISMATCH);
    if(request<65536)return reject(INVALID_CONFIG);
    AcquireSRWLockExclusive(&policy_lock);struct UnlockPolicy {~UnlockPolicy(){ReleaseSRWLockExclusive(&policy_lock);}} unlock_policy;
    if(!armed.load() || !policy.fird)return reject(OWNER_MISMATCH);
    Policy next=policy;next.c.request=request;
    uint32_t failure=OK;
    if(!checked_owner(next,false,failure) || !next.safe || next.full_ads || !request_matches(next))return reject(failure==OK?OWNER_MISMATCH:failure);
    if(!binary_contract(next.c) || !fird_input_contract(next.c) || !dispatch_owned(next))return reject(API_MISMATCH);
    // Persist the ledger before the immediate setter: a racing owner change
    // after its data CAS still leaves this generation responsible for cleanup.
    policy=next;
    if(!apply_immediately(policy,failure) || !checked_owner(policy,false,failure) || !request_matches(policy) || !policy.safe || policy.full_ads || !dispatch_owned(policy)) {
        armed.store(0,std::memory_order_release);return reject(failure==OK?OWNER_MISMATCH:failure);
    }
    publish_diagnostics(policy);binds.fetch_add(1,std::memory_order_relaxed);error(OK);return 1;
}
NADSF_EXPORT uint32_t NADSF_SetTransition(uint64_t generation,uint64_t epoch,float progress,uint32_t ads) {
    AcquireSRWLockExclusive(&control_lock);struct UnlockControl {~UnlockControl(){ReleaseSRWLockExclusive(&control_lock);}} unlock_control;
    if(!generation || !reserved.load() || generation!=owned_generation)return reject(TOKEN_MISMATCH);
    if(!epoch || !std::isfinite(progress) || progress<0 || progress>1 || ads>1)return reject(INVALID_CONFIG);
    AcquireSRWLockExclusive(&policy_lock);struct UnlockPolicy {~UnlockPolicy(){ReleaseSRWLockExclusive(&policy_lock);}} unlock_policy;
    if(!armed.load() || policy.fird || !policy.c.reserved)return reject(OWNER_MISMATCH);
    const uint32_t failure=owner_status(policy,false);if(failure!=OK)return reject(failure);
    if(!dispatch_owned(policy))return reject(API_MISMATCH);
    if(epoch<policy.shared_epoch || (epoch==policy.shared_epoch && (progress<policy.shared_progress || (ads!=0)!=policy.shared_ads)))
        return reject(INVALID_CONFIG);
    double now=0;if(!seconds(now))return reject(SOURCE_INVALID);
    if(epoch!=policy.shared_epoch || !policy.shared_phase) {
        policy.shared_started=false;policy.shared_used=0;
        policy.shared_ads_transition=policy.lens_ready && (policy.lens_ads!=(ads!=0) || policy.lens_blending);
    }
    policy.shared_phase=true;policy.shared_epoch=epoch;policy.shared_progress=progress;policy.shared_ads=ads!=0;policy.shared_at=now;
    error(OK);return 1;
}
NADSF_EXPORT uint32_t NADSF_End(uint64_t generation) {
    AcquireSRWLockExclusive(&control_lock);struct Unlock {~Unlock(){ReleaseSRWLockExclusive(&control_lock);}} unlock;
    if(!generation)return reject(TOKEN_MISMATCH);
    if(!reserved.load()) {if(generation!=retired_generation)return reject(TOKEN_MISMATCH);error(OK);return 1;}
    if(generation!=owned_generation)return reject(TOKEN_MISMATCH);
    armed.store(0,std::memory_order_release);AcquireSRWLockExclusive(&policy_lock);
    const bool restored=restore_fird_request(policy);ReleaseSRWLockExclusive(&policy_lock);
    if(!restored)return reject(CLEANUP_PENDING);
    if(!restore_slot())return reject(CLEANUP_PENDING);error(OK);return 1;
}
NADSF_EXPORT uint32_t NADSF_ReadStats(uint64_t generation,NADSF_Stats* output) {
    AcquireSRWLockExclusive(&control_lock);struct UnlockControl {~UnlockControl(){ReleaseSRWLockExclusive(&control_lock);}} unlock_control;
    if(reserved.load()?(!generation || generation!=owned_generation):generation!=0)return reject(TOKEN_MISMATCH);
    NADSF_Stats s{};if(!read(reinterpret_cast<uint64_t>(output),&s,sizeof s) || s.size!=sizeof s || s.abi!=1)return reject(INVALID_CONFIG);
    read_diagnostics(s);
    s.reserved=0;s.padding=0;s.installed=installed.load();s.armed=armed.load();s.error=last_error.load();
    s.seen=seen.load();s.forwarded=forwarded.load();s.replaced=replaced.load();s.immediate_applies=immediate_applies.load();s.binds=binds.load();s.ads_forwarded=ads_forwarded.load();
    SIZE_T actual=0;return WriteProcessMemory(GetCurrentProcess(),output,&s,sizeof s,&actual)!=0 && actual==sizeof s;
}
NADSF_EXPORT uint32_t NADSF_Error(void) {return last_error.load(std::memory_order_acquire);}
