#define _GNU_SOURCE
#include "gc_policy.h"
#include "frame_routes.h"
#include "gc_witnesses.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#ifdef _WIN32
#include <windows.h>
#define ABI
#else
#include <sys/mman.h>
#include <unistd.h>
#include <pthread.h>
#define ABI __attribute__((ms_abi))
#endif
#define IMAGE_SIZE 0x1750000
/* Real native scheduler sees only these synthetic PUC-shaped fields. */
typedef struct { void *L; HD2GCHistory history; HD2GCSettings settings; } Native;
typedef struct {
    Native native;
    unsigned char state[64],global[160];
    int64_t frequency,start,tick,increment;
    unsigned clock_calls,fulls,raw_steps,period,inner,profile_calls;
    float profile[4];
    int frequency_fail,counter_fail,step_fail,full_fail,sample_fail;
} Mock;
static Mock *active;
static unsigned errors;
static void need(int ok,const char *s){if(!ok){fprintf(stderr,"GC ERROR: %s\n",s);exit(18);}}
static void put64(void *p,uint64_t n){memcpy(p,&n,8);}
static uint64_t get64(const void *p){uint64_t n;memcpy(&n,p,8);return n;}
static void mock_init(Mock *m,int32_t total,int32_t estimate,HD2GCHistory h,HD2GCSettings s,unsigned variant){
    memset(m,0,sizeof(*m));m->native.L=m->state;m->native.history=h;m->native.settings=s;
    put64(m->state+0x20,(uintptr_t)m->global);put64(m->global+0x78,(uint64_t)total*1024);put64(m->global+0x80,(uint64_t)estimate*1024);
    m->frequency=1000000;m->start=12345;m->tick=m->start;
    m->increment=variant==0?0:variant==1?100:100000;
    m->period=variant==0?0:variant==1?7:3;m->inner=variant==1?2:1;
}
static int freq(void *p,int64_t *out){Mock *m=p;*out=m->frequency;return !m->frequency_fail;}
static int counter(void *p,int64_t *out){Mock *m=p;*out=m->tick;m->tick+=m->increment;m->clock_calls++;return !m->counter_fail;}
static int sample(void *p,int32_t *total,int32_t *estimate){Mock *m=p;*total=(int32_t)(get64(m->global+0x78)>>10);*estimate=(int32_t)(get64(m->global+0x80)>>10);return !m->sample_fail;}
static int full(void *p){Mock *m=p;m->fulls++;return !m->full_fail;}
static void one_step(Mock *m){
    m->raw_steps++;int cycle=m->period&&m->raw_steps%m->period==0;
    m->global[0x21]=cycle?0:1;
    put64(m->global+0x70,get64(m->global+0x78)+(cycle||m->raw_steps%m->inner==0?1:0));
}
static int step(void *p){
    Mock *m=p;if(m->step_fail)return -1;
    do{one_step(m);}while(m->global[0x21]&&get64(m->global+0x70)<=get64(m->global+0x78));
    return m->global[0x21]==0;
}
static void ABI native_step(void *L){need(L==active->state,"native step state");one_step(active);}
static int ABI native_full(void *L,int what,int data){need(L==active->state&&what==2&&data==0,"native full arguments");return full(active);}
static int ABI native_frequency(int64_t *out){return freq(active,out);}
static int ABI native_counter(int64_t *out){return counter(active,out);}
static void ABI profile(const char *name,float value){
    static const char *names[]={"lua.gc.total","lua.gc.estimate","lua.gc.percentage","lua.gc.collection_ms"};
    need(active->profile_calls<4&&!strcmp(name,names[active->profile_calls]),"profiler ordering");
    active->profile[active->profile_calls++]=value;
}
static unsigned char *memory(void){
#ifdef _WIN32
    void *p=VirtualAlloc(NULL,IMAGE_SIZE,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE);need(p!=NULL,"allocate");
#else
    void *p=mmap(NULL,IMAGE_SIZE,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);need(p!=MAP_FAILED,"allocate");
#endif
    return p;
}
static void protect(void *p,size_t n,int mode){
#ifdef _WIN32
    DWORD old;need(VirtualProtect(p,n,mode==0?PAGE_NOACCESS:mode==1?PAGE_READWRITE:PAGE_EXECUTE_READ,&old),"protect");
    if(mode==2)need(FlushInstructionCache(GetCurrentProcess(),p,n),"flush");
#else
    need(mprotect(p,n,mode==0?PROT_NONE:mode==1?(PROT_READ|PROT_WRITE):(PROT_READ|PROT_EXEC))==0,"protect");
    if(mode==2)__builtin___clear_cache(p,(char *)p+n);
#endif
}
static void release(void *p){
#ifdef _WIN32
    need(VirtualFree(p,0,MEM_RELEASE),"free");
#else
    need(munmap(p,IMAGE_SIZE)==0,"free");
#endif
}
static void thunk(unsigned char *im,unsigned rva,uintptr_t target){im[rva]=0x48;im[rva+1]=0xb8;put64(im+rva+2,target);im[rva+10]=0xff;im[rva+11]=0xe0;}
static void code_page(unsigned char *im,unsigned rva,int mode){protect(im+(rva&~4095u),4096,mode);}
static void lua_ok(HD2Environment *e,int ok){need(ok,hd2env_error(e));need(hd2env_stack_depth(e)==0,"Lua stack");}
static void eval(HD2Environment *e,const char *s){lua_ok(e,hd2env_eval(e,s,strlen(s),"@gc-test"));}
static void report(void *p,HD2Environment *e,const char *operation,const char *message){
    (void)p;(void)e;need(!strcmp(operation,"gc")&&strstr(message,"scheduler"),"GC error report");errors++;
}
typedef struct { HD2Environment *e; uintptr_t native; int refused; } Thread;
#ifdef _WIN32
static DWORD WINAPI other_thread(void *p){
#else
static void *other_thread(void *p){
#endif
    Thread *t=p;HD2GCReport r={0};r.steps=123;
    uint64_t faults=hd2env_frame_fault_count();
    ((void(ABI *)(void *))hd2env_gc_target())((void *)t->native);
    t->refused=!hd2env_collect_frame(t->e,&r)&&r.steps==123&&!hd2env_configure_gc(t->e,NULL,NULL)&&
        !hd2env_gc_report(t->e,&r)&&hd2env_frame_fault_count()==faults+1;
    return 0;
}
static int reenter_counter(void *p,int64_t *out){
    HD2Environment *e=p;HD2GCReport r={0};
    need(!hd2env_collect_frame(e,&r)&&!hd2env_destroy(e)&&!hd2env_configure_gc(e,NULL,NULL),"GC reentry/lifetime");
    *out=1;return 1;
}
static int fixed_freq(void *p,int64_t *out){(void)p;*out=1000;return 1;}
void check_gc(HD2Environment *e){
    _Static_assert(offsetof(Native,history)==8&&offsetof(Native,settings)==24,"native fixture layout");
    unsigned char *im=memory();memcpy(im+0x5eb310,gc_caller_witness,sizeof(gc_caller_witness));
    memcpy(im+0x6cd140,gc_forward_witness,sizeof(gc_forward_witness));
    float one=1.0f,thousand=1000.0f;memcpy(im+0x174d560,&one,4);memcpy(im+0x174d828,&thousand,4);
    const unsigned names[]={0x172c678,0x172c6c0,0x172c6a8,0x172c5f8};
    const char *strings[]={"lua.gc.total","lua.gc.estimate","lua.gc.percentage","lua.gc.collection_ms"};
    for(unsigned i=0;i<4;i++)strcpy((char *)im+names[i],strings[i]);
    thunk(im,0x74cf0,(uintptr_t)profile);thunk(im,0x797d40,(uintptr_t)native_full);thunk(im,0x7a1020,(uintptr_t)native_step);
    put64(im+0x148d340,(uintptr_t)native_frequency);put64(im+0x148d368,(uintptr_t)native_counter);
    const unsigned pages[]={0x5eb310,0x6cd140,0x74cf0,0x797d40,0x7a1020};
    for(unsigned i=0;i<5;i++)code_page(im,pages[i],2);
    HD2GCSettings settings=hd2gc_defaults();need(!memcmp(&settings,gc_settings_witness,16)&&!memcmp(&settings.max_ms,gc_maximum_witness,4),"default settings");
    const int32_t totals[]={0,1,90,100,110,160,210,211,1024,INT32_MAX};
    const int32_t estimates[]={0,1,100,256,INT32_MAX};
    unsigned cases=0;
    for(unsigned a=0;a<10;a++)for(unsigned b=0;b<5;b++)for(unsigned variant=0;variant<3;variant++)for(unsigned history=0;history<2;history++){
        HD2GCHistory h=hd2gc_history();if(history){h.peak=120;h.previous_peak=220;h.floor=500;h.previous_floor=90;}
        HD2GCSettings s=settings;if(history){s.min_ms=0.25f;s.max_ms=2.0f;}
        Mock original,port;mock_init(&original,totals[a],estimates[b],h,s,variant);mock_init(&port,totals[a],estimates[b],h,s,variant);
        active=&original;((void(ABI *)(Native *))(im+0x5eb310))(&original.native);
        HD2GCDriver d={&port,sample,full,step,{&port,freq,counter}};HD2GCReport r;
        need(hd2gc_schedule(&s,&port.native.history,&d,&r),"scheduler execution");
        need(!memcmp(&port.native.history,&original.native.history,sizeof(h)),"cycle history differs");
        need(port.raw_steps==original.raw_steps&&port.fulls==original.fulls&&port.clock_calls==original.clock_calls,"scheduler call counts differ");
        need(!memcmp(&r.growth,&original.profile[2],4)&&!memcmp(&r.budget_ms,&original.profile[3],4),"float policy differs");
        need(get64(original.global+0x70)==UINT64_MAX-2,"original stop threshold");
        need(r.steps>=1&&r.steps<=5000,"step bounds");if(!variant)need(r.steps==5000,"hard step cap");cases++;
    }
    /* Validate malformed settings/clock/driver failures without invoking an
     * undefined native float-to-integer conversion in the original oracle. */
    Mock m;mock_init(&m,100,100,hd2gc_history(),settings,2);
    HD2GCDriver d={&m,sample,full,step,{&m,freq,counter}};HD2GCHistory h=hd2gc_history();HD2GCReport r;
    HD2GCSettings invalid=settings;invalid.growth_range=0;need(!hd2gc_schedule(&invalid,&h,&d,&r),"zero range");
    invalid=settings;invalid.min_ms=NAN;need(!hd2gc_schedule(&invalid,&h,&d,&r),"NaN settings");
    m.frequency=0;need(!hd2gc_schedule(&settings,&h,&d,&r),"bad frequency");m.frequency=1000;
    m.counter_fail=1;need(!hd2gc_schedule(&settings,&h,&d,&r),"bad clock");m.counter_fail=0;
    m.step_fail=1;need(!hd2gc_schedule(&settings,&h,&d,&r),"step failure");m.step_fail=0;
    m.sample_fail=1;need(!hd2gc_schedule(&settings,&h,&d,&r),"sample failure");m.sample_fail=0;
    m.tick=100;m.increment=-1;need(!hd2gc_schedule(&settings,&h,&d,&r),"backward clock");
    m.tick=INT64_MAX;settings.min_ms=settings.max_ms=1;need(!hd2gc_schedule(&settings,&h,&d,&r),"deadline overflow");settings=hd2gc_defaults();
    /* Guard every captured caller byte and preserve output on refusal. */
    HD2GCPatch patch,sentinel;memset(&sentinel,0xa5,sizeof(sentinel));uintptr_t target=hd2env_gc_target();
    need(hd2env_plan_gc_patch(im,IMAGE_SIZE,target,&patch),"plan");
    code_page(im,0x5eb310,1);
    for(unsigned i=0;i<sizeof(gc_caller_witness);i++){
        im[0x5eb310+i]^=1;HD2GCPatch out=sentinel;
        need(!hd2env_plan_gc_patch(im,IMAGE_SIZE,target,&out)&&!memcmp(&out,&sentinel,sizeof(out)),"guard refusal");im[0x5eb310+i]^=1;
    }
    memcpy(im+patch.rva,patch.replacement,patch.size);code_page(im,0x5eb310,2);
    /* All old VM access and old collector stubs become inaccessible. The
     * patched entry/unchanged forwarding wrapper use opaque association only. */
    protect(im+0x2000,4096,0);code_page(im,0x797d40,0);code_page(im,0x7a1020,0);
    HD2FrameCallbacks callbacks={NULL,NULL,report};HD2FrameTargets targets;
    void *native=im+0x2000;lua_ok(e,hd2env_bind_frames(e,native,&callbacks,&targets));
    eval(e,"gc_saved=collectgarbage;collectgarbage('stop');collectgarbage=function() error('Lua GC global called') end; gc_dead=0; for i=1,100 do local u=newproxy(true); getmetatable(u).__gc=function() gc_dead=gc_dead+1 end end");
    eval(e,"assert(gc_saved('setstepmul',37)==20);assert(gc_saved('setpause',333)==200)");
    settings.min_ms=settings.max_ms=0;lua_ok(e,hd2env_configure_gc(e,&settings,NULL));
    for(unsigned i=0;i<1000;i++)((void(ABI *)(void *))(im+0x6cd140))(native);
    lua_ok(e,hd2env_gc_report(e,&r));need(r.steps>=1&&r.steps<=5000,"real GC steps");
    eval(e,"assert(gc_dead==100);assert(gc_saved('count')>=0);assert(gc_saved('setstepmul',37)==37);assert(gc_saved('setpause',333)==333)");
#ifndef HD2ENV_PUC_REFERENCE
    eval(e,"assert(gc_saved('isrunning')==false)");
#endif
    eval(e,"gc_bad_count=0;local u=newproxy(true);getmetatable(u).__gc=function() gc_bad_count=gc_bad_count+1;error('timed GC finalizer failure') end");
    unsigned failures=0;
    for(unsigned i=0;i<1000;i++){
        if(!hd2env_collect_frame(e,&r)){need(strstr(hd2env_error(e),"timed GC finalizer failure")!=NULL,"finalizer error capture");failures++;}
        need(hd2env_stack_depth(e)==0,"finalizer error stack");
    }
    eval(e,"assert(gc_bad_count==1)");
#ifdef HD2ENV_PUC_REFERENCE
    need(failures==1,"PUC finalizer propagation");
#else
    need(failures==0,"LuaJIT ERRFIN behavior");eval(e,"assert(gc_saved('isrunning')==false)");
#endif
    Mock failed;mock_init(&failed,0,0,hd2gc_history(),settings,2);failed.counter_fail=1;
    HD2GCClock clock={&failed,freq,counter};lua_ok(e,hd2env_configure_gc(e,&settings,&clock));
    ((void(ABI *)(void *))targets.gc)(native);need(errors==1&&strstr(hd2env_error(e),"scheduler"),"reported clock failure");
    clock=(HD2GCClock){e,fixed_freq,reenter_counter};lua_ok(e,hd2env_configure_gc(e,&settings,&clock));
    lua_ok(e,hd2env_collect_frame(e,&r));need(r.steps==5000,"reentry test step cap");
    Thread t={e,(uintptr_t)native+0x100148,0};
#ifdef _WIN32
    HANDLE thread=CreateThread(NULL,0,other_thread,&t,0,NULL);need(thread!=NULL,"thread");WaitForSingleObject(thread,INFINITE);CloseHandle(thread);
#else
    pthread_t thread;need(!pthread_create(&thread,NULL,other_thread,&t),"thread");need(!pthread_join(thread,NULL),"join");
#endif
    need(t.refused,"foreign thread");lua_ok(e,hd2env_unbind_frames(e));
    uint64_t faults=hd2env_frame_fault_count();((void(ABI *)(void *))(im+0x6cd140))(native);
    need(hd2env_frame_fault_count()==faults+1,"unbound route");
    lua_ok(e,hd2env_configure_gc(e,NULL,NULL));eval(e,"collectgarbage=gc_saved;gc_saved=nil");
    code_page(im,0x5eb310,1);memcpy(im+patch.rva,patch.original,patch.size);
    need(hd2env_plan_gc_patch(im,IMAGE_SIZE,target,&patch),"rollback");release(im);
    printf("POC_GC differential_cases=%u guards=550 history=pass budget=pass full=pass cap=pass real_gc=pass finalizers=100 finalizer_errors=pass native_routes=2 errors=pass thread=pass reentry=pass rollback=pass\n",cases);
}
