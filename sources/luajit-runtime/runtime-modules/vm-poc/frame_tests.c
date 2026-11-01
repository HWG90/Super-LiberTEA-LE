#include "gc_policy.h"
/* Execute captured callers only in an owned image. Every transitive native
 * callee is a test stub. No game process, module or filesystem is patched. */
#define _GNU_SOURCE
#include "frame_routes.h"
#include "frame_witnesses.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <float.h>
#ifdef _WIN32
#include <windows.h>
#define WINCALL
#else
#include <sys/mman.h>
#include <unistd.h>
#include <pthread.h>
#define WINCALL __attribute__((ms_abi))
#endif

enum { IMAGE_SIZE=0x2861000, GAME_SIZE=0x102000 };
typedef void (WINCALL *Update)(void *,float);
typedef void (WINCALL *Render)(void *);
typedef struct {
    HD2Environment *env;
    unsigned char *image,*game,*guard;
    uintptr_t vtable[2],object[1],plugin[19];
    unsigned char second_object[256];
    char order[16],error[2048];
    unsigned at,errors,updates,renders,gcs;
    unsigned check_reentry;
    HD2FrameTargets targets;
    float dt;
} FrameFixture;
static FrameFixture *active;
static void need(int ok,const char *message){
    if(!ok){fprintf(stderr,"FRAME ERROR: %s\n",message);exit(12);}
}
static void lua_ok(HD2Environment *e,int ok){
    need(ok,hd2env_error(e));need(hd2env_stack_depth(e)==0,"Lua stack imbalance");
}
static unsigned char *allocate(size_t size){
#ifdef _WIN32
    void *p=VirtualAlloc(NULL,size,MEM_RESERVE|MEM_COMMIT,PAGE_NOACCESS);
    need(p!=NULL,"VirtualAlloc");
#else
    void *p=mmap(NULL,size,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
    need(p!=MAP_FAILED,"mmap");
#endif
    return p;
}
static void protect(unsigned char *p,size_t size,int executable){
    /* All requests cover complete 4K pages on these x64 test hosts. */
#ifdef _WIN32
    DWORD old;
    need(VirtualProtect(p,size,executable?PAGE_EXECUTE_READ:PAGE_READWRITE,&old),"VirtualProtect");
    if(executable)need(FlushInstructionCache(GetCurrentProcess(),p,size),"FlushInstructionCache");
#else
    need(sysconf(_SC_PAGESIZE)==4096,"unsupported host page size");
    need(mprotect(p,size,executable?(PROT_READ|PROT_EXEC):(PROT_READ|PROT_WRITE))==0,"mprotect");
    if(executable)__builtin___clear_cache((char *)p,(char *)p+size);
#endif
}
static void dispose(unsigned char *p,size_t size){
#ifdef _WIN32
    (void)size;need(VirtualFree(p,0,MEM_RELEASE),"VirtualFree");
#else
    need(munmap(p,size)==0,"munmap");
#endif
}
static void pointer(unsigned char *where,uintptr_t value){memcpy(where,&value,sizeof(value));}
static void event(char c){
    need(active->at+1<sizeof(active->order),"event overflow");
    active->order[active->at++]=c;active->order[active->at]=0;
}
static void same_dt(float dt){need(!memcmp(&dt,&active->dt,sizeof(dt)),"Win64 float argument changed");}
static void WINCALL before_a(void *object){need(object==active->object,"virtual hook receiver");event('A');}
static void WINCALL before_b(void *object){need(object==active->second_object+0x80,"secondary hook receiver");event('B');}
static void WINCALL before_backend(float dt){same_dt(dt);event('C');}
static void WINCALL after_update(float dt){same_dt(dt);event('T');}
static void WINCALL after_render(void){event('P');}
static int collect(void *context,HD2Environment *e){
    FrameFixture *f=context;need(f==active&&e==f->env,"native environment association");
    f->gcs++;event('G');
    if(f->check_reentry){
        uint64_t faults=hd2env_frame_fault_count();f->check_reentry=0;
        need(!hd2env_unbind_frames(e)&&!hd2env_destroy(e),"frame lifetime guard");
        ((Update)f->targets.update)(f->game+0x190,f->dt);
        need(hd2env_frame_fault_count()==faults+1,"recursive frame not refused");
    }
    return hd2env_collect_frame(e,NULL);
}
static void report_error(void *context,HD2Environment *e,const char *operation,const char *message){
    FrameFixture *f=context;need(f==active&&e==f->env,"error context");
    need(!strcmp(operation,"update")||!strcmp(operation,"render"),"error operation");
    f->errors++;snprintf(f->error,sizeof(f->error),"%s",message);
    need(!hd2env_unbind_frames(e)&&!hd2env_destroy(e),"reporter lifetime guard");
    const char *source="assert(true)";
    lua_ok(e,hd2env_eval(e,source,strlen(source),"@frame-error-reporter"));
    need(!strcmp(message,f->error),"reporter's borrowed diagnostic changed");
}
static void thunk(unsigned char *p,uintptr_t target){
    p[0]=0x48;p[1]=0xb8;pointer(p+2,target);p[10]=0xff;p[11]=0xe0;
}
static void hooks(FrameFixture *f,int enabled){
    pointer(f->image+0x28605a8,enabled?(uintptr_t)f->object:0);
    pointer(f->image+0x28605c0,enabled?(uintptr_t)f->second_object:0);
    f->image[0x1ab6d88]=(unsigned char)enabled;
}
static void frame(FrameFixture *f,float dt,int enabled){
    unsigned errors=f->errors;
    f->at=0;f->order[0]=0;f->dt=dt;
    ((Update)(f->image+0x6ce580))(f->game,dt);
    f->updates++;
    need(!strcmp(f->order,enabled?"ABCGT":"CGT"),"update hook order");
    f->at=0;f->order[0]=0;
    ((Render)(f->image+0x6ce690))(f->game);
    f->renders++;
    need(!strcmp(f->order,enabled?"P":""),"render hook order");
    need(f->errors==errors,"unexpected routed Lua error");
    need(hd2env_stack_depth(f->env)==0,"unbalanced routed Lua call");
}
static void refused(FrameFixture *f,const HD2FrameTargets *targets,size_t size){
    HD2FramePatch out[2],before[2];memset(out,0xa5,sizeof(out));memcpy(before,out,sizeof(out));
    need(!hd2env_plan_frame_patches(f->image,size,targets,out),"unsafe plan accepted");
    need(!memcmp(out,before,sizeof(out)),"refusal changed output");
}
typedef struct { HD2Environment *e;HD2FrameTargets targets;void *address;int passed; } FrameThread;
#ifdef _WIN32
static DWORD WINAPI frame_thread(LPVOID p){
#else
static void *frame_thread(void *p){
#endif
    FrameThread *t=p;uint64_t faults=hd2env_frame_fault_count();
    ((Update)t->targets.update)(t->address,1.0f);
    t->passed=hd2env_frame_fault_count()==faults+1&&!hd2env_unbind_frames(t->e);
    return 0;
}
static void associations(FrameFixture *f,const HD2FrameCallbacks *callbacks){
    HD2FrameTargets sentinel={1,2,3},out=sentinel;
    need(!hd2env_bind_frames(f->env,f->game+0x190,callbacks,&out)&&
         !memcmp(&out,&sentinel,sizeof(out)),"duplicate binding changed output");
    HD2Backend backend={0};char error[2048];
    HD2Environment *other=hd2env_create(NULL,0,&backend,error,sizeof(error));need(other!=NULL,error);
    need(!hd2env_bind_frames(other,f->game+0x190,callbacks,&out),"native address alias accepted");
    HD2FrameCallbacks missing=*callbacks;missing.report_error=NULL;
    need(!hd2env_bind_frames(other,f->game+0x198,&missing,&out),"missing GC policy accepted");
    missing=*callbacks;missing.report_error=NULL;
    need(!hd2env_bind_frames(other,f->game+0x198,&missing,&out),"missing reporter accepted");
    need(!hd2env_bind_frames(other,NULL,callbacks,&out),"null native address accepted");
    need(!memcmp(&out,&sentinel,sizeof(out)),"binding refusal changed output");
    need(hd2env_bind_frames(other,f->game+0x198,callbacks,&out),"second association");
    need(hd2env_destroy(other),"bound environment destruction");
    uint64_t faults=hd2env_frame_fault_count();
    ((Update)out.update)(f->game+0x198,1.0f);
    need(hd2env_frame_fault_count()==faults+1,"destroy left a stale association");
    FrameThread test={f->env,f->targets,f->game+0x190,0};faults=hd2env_frame_fault_count();
#ifdef _WIN32
    HANDLE thread=CreateThread(NULL,0,frame_thread,&test,0,NULL);need(thread!=NULL,"frame thread creation");
    need(WaitForSingleObject(thread,INFINITE)==WAIT_OBJECT_0,"frame thread join");CloseHandle(thread);
#else
    pthread_t thread;need(pthread_create(&thread,NULL,frame_thread,&test)==0,"frame thread creation");
    need(pthread_join(thread,NULL)==0,"frame thread join");
#endif
    need(test.passed&&hd2env_frame_fault_count()==faults,"frame thread isolation");
}
void check_frame_routes(HD2Environment *e){
    FrameFixture f={0};HD2FramePatch patches[2];active=&f;f.env=e;
    f.image=allocate(IMAGE_SIZE);f.game=allocate(GAME_SIZE);f.guard=allocate(4096);
    const uint32_t pages[]={0x6ce000,0x674000,0x7fa000,0x61000,0x2860000,0x1ab6000};
    for(size_t i=0;i<sizeof(pages)/sizeof(*pages);i++)protect(f.image+pages[i],4096,0);
    protect(f.game,4096,0);protect(f.game+0x100000,4096,0);
    pointer(f.game+0x190,(uintptr_t)f.guard);pointer(f.game+0x1002d8,(uintptr_t)f.guard);
    memcpy(f.image+0x6ce580,frame_update_witness,sizeof(frame_update_witness));
    memcpy(f.image+0x6ce690,frame_render_witness,sizeof(frame_render_witness));
    HD2FrameCallbacks callbacks={&f,collect,report_error};
    need(hd2env_bind_frames(e,f.game+0x190,&callbacks,&f.targets),"library frame binding");
    associations(&f,&callbacks);f.check_reentry=1;
    HD2FrameTargets targets=f.targets;
    refused(&f,&targets,0x6ce6ef);
    HD2FrameTargets missing=targets;missing.gc=0;refused(&f,&missing,IMAGE_SIZE);
    missing=targets;missing.update=0;refused(&f,&missing,IMAGE_SIZE);
    missing=targets;missing.render=0;refused(&f,&missing,IMAGE_SIZE);
    refused(&f,NULL,IMAGE_SIZE);
    /* Every byte, including untouched prefixes/suffixes, is part of the guard. */
    for(size_t i=0;i<sizeof(frame_update_witness);i++){
        f.image[0x6ce580+i]^=1;refused(&f,&targets,IMAGE_SIZE);f.image[0x6ce580+i]^=1;
    }
    for(size_t i=0;i<sizeof(frame_render_witness);i++){
        f.image[0x6ce690+i]^=1;refused(&f,&targets,IMAGE_SIZE);f.image[0x6ce690+i]^=1;
    }
    need(hd2env_plan_frame_patches(f.image,IMAGE_SIZE,&targets,patches),"valid plan refused");
    for(unsigned i=0;i<2;i++)memcpy(f.image+patches[i].rva,patches[i].replacement,patches[i].size);
    f.vtable[1]=(uintptr_t)before_a;f.object[0]=(uintptr_t)f.vtable;
    f.plugin[18]=(uintptr_t)after_render;pointer(f.image+0x1ab6d70,(uintptr_t)f.plugin);
    thunk(f.image+0x6741b0,(uintptr_t)before_b);thunk(f.image+0x7faeb0,(uintptr_t)before_backend);
    thunk(f.image+0x61850,(uintptr_t)after_update);
    for(unsigned i=0;i<4;i++)protect(f.image+pages[i],4096,1);
    const char *setup=
        "function poc_frame_gc() collectgarbage('step',0) end\n"
        "function poc_frame_expect(dt) frame_expected=dt end\n"
        "frame_updates=0;frame_renders=0\n"
        "function update(...) assert(select('#',...)==1);local dt=...;assert(dt==frame_expected);frame_updates=frame_updates+1 end\n"
        "function render(...) assert(select('#',...)==0);frame_renders=frame_renders+1 end\n";
    lua_ok(e,hd2env_eval(e,setup,strlen(setup),"@frame-tests"));
    const float deltas[]={0.0f,-0.0f,1.0f/60,123.125f,-2.75f,FLT_MAX,FLT_MIN};
    for(unsigned enabled=0;enabled<2;enabled++){
        hooks(&f,(int)enabled);
        for(size_t i=0;i<sizeof(deltas)/sizeof(*deltas);i++){
            lua_ok(e,hd2env_call(e,"poc_frame_expect",1,(double)deltas[i]));
            frame(&f,deltas[i],(int)enabled);
        }
    }
    const char *counts="assert(frame_updates==14 and frame_renders==14)";
    lua_ok(e,hd2env_eval(e,counts,strlen(counts),"@frame-counts"));
    const char *failure="function update() error({frame=true}) end;function render() error('render-error') end";
    lua_ok(e,hd2env_eval(e,failure,strlen(failure),"@frame-errors"));
    f.at=0;((Update)(f.image+0x6ce580))(f.game,f.dt);f.updates++;
    need(f.errors==1&&!strcmp(f.error,"non-string Lua error")&&!strcmp(f.order,"ABCGT"),"update error boundary");
    need(!strcmp(hd2env_error(e),f.error),"update error lost during reporting");
    f.at=0;((Render)(f.image+0x6ce690))(f.game);f.renders++;
    need(f.errors==2&&strstr(f.error,"render-error")&&!strcmp(f.order,"P"),"render error boundary");
    need(!strcmp(hd2env_error(e),f.error),"render error lost during reporting");
    /* Replacing globals after a failure proves that callbacks aren't frozen. */
    const char *recovery="function update() frame_recovered=(frame_recovered or 0)+1 end;function render() end";
    lua_ok(e,hd2env_eval(e,recovery,strlen(recovery),"@frame-recovery"));
    frame(&f,1.0f/60,1);
    const char *recovered="assert(frame_recovered==1);update=nil;render=nil";
    lua_ok(e,hd2env_eval(e,recovered,strlen(recovered),"@frame-recovered"));
#ifndef HD2ENV_PUC_REFERENCE
    lua_ok(e,hd2env_require(e,"poc/bootstrap_scenarios.lua"));
    for(unsigned i=0;i<4000;i++){
        lua_ok(e,hd2env_call(e,"poc_bootstrap_before_frame",0,0));
        frame(&f,1.0f/60,1);
    }
    lua_ok(e,hd2env_call(e,"poc_trace_report",0,0));
    lua_ok(e,hd2env_call(e,"poc_bootstrap_finish",0,0));
#endif
    protect(f.image+0x6ce000,4096,0);
    for(unsigned i=0;i<2;i++){
        need(!memcmp(f.image+patches[i].rva,patches[i].replacement,patches[i].size),"patch altered during execution");
        memcpy(f.image+patches[i].rva,patches[i].original,patches[i].size);
    }
    need(!memcmp(f.image+0x6ce580,frame_update_witness,sizeof(frame_update_witness))&&
         !memcmp(f.image+0x6ce690,frame_render_witness,sizeof(frame_render_witness)),"caller restoration");
    need(hd2env_plan_frame_patches(f.image,IMAGE_SIZE,&targets,patches),"restored callers failed guard");
    need(hd2env_object_count(e)==0,"frame ownership leak");
    need(hd2env_unbind_frames(e),"frame unbind");
    uint64_t faults=hd2env_frame_fault_count();((Update)targets.update)(f.game+0x190,0);
    need(hd2env_frame_fault_count()==faults+1,"unbind left a stale association");
    dispose(f.guard,4096);dispose(f.game,GAME_SIZE);dispose(f.image,IMAGE_SIZE);active=NULL;
    printf("POC_FRAMES callers=2 guards=pass float_abi=pass hooks=pass old_state_inaccessible=pass errors=pass rebind=pass rollback=pass associations=pass thread=pass lifetime=pass recursion=pass updates=%u renders=%u collections=%u\n",f.updates,f.renders,f.gcs);
}
