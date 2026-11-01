#include "gc_policy.h"
/* Local captured constructor/destructor/frame execution; helpers are fixtures. */
#define _GNU_SOURCE
#define HD2_LIFECYCLE_TEST_DATA
#include "lifecycle_routes.h"
#include "lifecycle_witnesses.h"
#include "frame_witnesses.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#define WINCALL
#else
#include <sys/mman.h>
#include <unistd.h>
#define WINCALL __attribute__((ms_abi))
#endif
enum { LIFE_IMAGE_SIZE=0x2861000, LIFE_GAME_SIZE=0x102000 };
typedef void *(WINCALL *Construct)(void *,void *);
typedef void (WINCALL *Close)(void *);
typedef void (WINCALL *Tick)(void *,float);
typedef struct {
    unsigned char *image,*game,*native;
    HD2Environment *e,**out;
    const HD2Asset *assets;size_t asset_count;
    HD2Backend backend;
    void (*original_log)(void *,const char *,size_t);
    uintptr_t allocator_vtable[9],buffers[2];
    unsigned char resources;
    char events[32];unsigned event_count,created,closed,finalized,collections;
    int fail_creation;
} LifeFixture;
static LifeFixture *current;
static void need(int ok,const char *message){
    if(!ok){fprintf(stderr,"LIFECYCLE ERROR: %s\n",message);exit(13);}
}
static void event(char c){
    need(current->event_count+1<sizeof(current->events),"event overflow");
    current->events[current->event_count++]=c;current->events[current->event_count]=0;
}
static void lua_ok(int ok){need(ok,hd2env_error(current->e));need(hd2env_stack_depth(current->e)==0,"stack imbalance");}
static unsigned char *allocate(size_t size){
#ifdef _WIN32
    void *p=VirtualAlloc(NULL,size,MEM_RESERVE|MEM_COMMIT,PAGE_NOACCESS);need(p!=NULL,"VirtualAlloc");
#else
    void *p=mmap(NULL,size,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);need(p!=MAP_FAILED,"mmap");
#endif
    return p;
}
static void protect(void *p,size_t size,int executable){
#ifdef _WIN32
    DWORD old;need(VirtualProtect(p,size,executable?PAGE_EXECUTE_READ:PAGE_READWRITE,&old),"VirtualProtect");
    if(executable)need(FlushInstructionCache(GetCurrentProcess(),p,size),"FlushInstructionCache");
#else
    need(sysconf(_SC_PAGESIZE)==4096,"host page size");
    need(mprotect(p,size,executable?(PROT_READ|PROT_EXEC):(PROT_READ|PROT_WRITE))==0,"mprotect");
    if(executable)__builtin___clear_cache(p,(char *)p+size);
#endif
}
static void dispose(void *p,size_t size){
#ifdef _WIN32
    (void)size;need(VirtualFree(p,0,MEM_RELEASE),"VirtualFree");
#else
    need(munmap(p,size)==0,"munmap");
#endif
}
static uintptr_t pointer(const void *p){uintptr_t value;memcpy(&value,p,sizeof(value));return value;}
static void putptr(void *p,uintptr_t value){memcpy(p,&value,sizeof(value));}
static void put32(void *p,uint32_t value){memcpy(p,&value,sizeof(value));}
static void thunk(unsigned char *p,uintptr_t target){p[0]=0x48;p[1]=0xb8;putptr(p+2,target);p[10]=0xff;p[11]=0xe0;}
static void WINCALL allocator_init(void *object,const char *name,void *parent,unsigned flag){
    LifeFixture *f=current;
    if(object==f->native+8)need(!strcmp(name,"LuaEnvironment")&&parent==&f->resources&&flag==1,"environment allocator arguments");
    else need(object==f->native+0x88&&!strcmp(name,"lua")&&!parent&&!flag,"VM allocator arguments");
    putptr(object,(uintptr_t)f->allocator_vtable);event('I');
}
static void WINCALL allocator_free(void *object,void *memory,unsigned align){
    LifeFixture *f=current;need(object==f->native+8&&align==0,"native deallocation arguments");
    if(memory==f->buffers){need(f->closed==f->created&&f->finalized==f->created,"native array freed before VM close");event('A');}
    else {need(memory==(void *)f->buffers[0]||memory==(void *)f->buffers[1],"native temporary buffer");event('B');}
}
static void WINCALL vm_allocator_close(void *object){need(object==current->native+0x88,"VM allocator close");event('L');}
static void WINCALL environment_allocator_close(void *object){need(object==current->native+8,"environment allocator close");event('N');}
static void WINCALL before_update(float dt){need(dt==1.0f/60,"frame input before Lua");}
static void WINCALL after_update(float dt){need(dt==1.0f/60,"frame input after Lua");}
static void lifecycle_log(void *context,const char *message,size_t size){
    LifeFixture *f=current;
    if(size==23&&!memcmp(message,"POC_LIFECYCLE_FINALIZER",23)){
        need(f->e&&f->closed+1==f->created&&hd2env_native_state_count()==1,"backend not alive during finalizer");
        f->finalized++;event('F');
    }
    if(f->original_log)f->original_log(context,message,size);
}
static int collect(void *context,HD2Environment *e){
    LifeFixture *f=context;need(f==current&&e==f->e,"native collection association");f->collections++;
    return hd2env_collect_frame(e,NULL);
}
static void report(void *context,HD2Environment *e,const char *op,const char *message){
    (void)context;(void)e;fprintf(stderr,"LIFECYCLE routed %s: %s\n",op,message);exit(13);
}
static HD2Environment *create(void *context,void *address,void *resources,HD2FrameCallbacks *frames,char *error,size_t capacity){
    LifeFixture *f=context;need(f==current&&address==f->native&&resources==&f->resources,"constructor arguments");
    need(!hd2env_clear_native_factory(),"factory changed during creation");
    need(pointer(f->native)==0&&pointer(f->native+0x100148)==0,"PUC state was created");
    need(pointer(f->native+0x110)==(uintptr_t)resources,"resource-manager bookkeeping lost");
    need(pointer(f->native+0x100118)==(uintptr_t)(f->native+0x118)&&
         pointer(f->native+0x100120)==(uintptr_t)(f->native+0x118)&&
         pointer(f->native+0x100138)==(uintptr_t)(f->native+8),"native buffer bookkeeping lost");
    need(!memcmp(f->native+0x100160,lifecycle_gc_settings_witness,16)&&
         !memcmp(f->native+0x100170,lifecycle_gc_max_ms_witness,4),"native GC defaults lost");
    if(f->fail_creation){snprintf(error,capacity,"fixture creation failure");return NULL;}
    *frames=(HD2FrameCallbacks){f,collect,report};
    f->e=hd2env_create(f->assets,f->asset_count,&f->backend,error,capacity);*f->out=f->e;
    if(f->e){f->created++;event('V');}
    return f->e;
}
static void closed(void *context,void *address){
    LifeFixture *f=context;need(f==current&&address==f->native,"close context");
    need(f->finalized==f->created&&hd2env_native_state_count()==0,"close notification order");
    need(!hd2env_clear_native_factory(),"factory changed during close callback");
    f->closed++;f->e=NULL;*f->out=NULL;event('C');
}
static void fatal(void *context,void *address,const char *op,const char *message){
    LifeFixture *f=context;
    if(f->fail_creation&&address==f->native&&!strcmp(op,"construct")&&!strcmp(message,"fixture creation failure")){
#ifdef _WIN32
        ExitProcess(42);
#else
        _exit(42);
#endif
    }
    fprintf(stderr,"LIFECYCLE fatal %s: %s\n",op,message);exit(13);
}
static void refused(LifeFixture *f,const HD2LifecycleTargets *targets,uintptr_t base,size_t size){
    HD2LifecyclePatch out[2],saved[2];memset(out,0xa5,sizeof(out));memcpy(saved,out,sizeof(out));
    need(!hd2env_plan_lifecycle_patches(f->image,size,base,targets,out),"unsafe lifecycle plan accepted");
    need(!memcmp(out,saved,sizeof(out)),"refusal changed output");
}
void check_lifecycle_routes(const HD2Asset *assets,size_t count,const HD2Backend *backend,HD2Environment **out,int fail_creation){
    LifeFixture f={0};current=&f;f.assets=assets;f.asset_count=count;f.backend=*backend;f.out=out;
    f.original_log=f.backend.log;f.backend.log=lifecycle_log;f.fail_creation=fail_creation;
    f.image=allocate(LIFE_IMAGE_SIZE);f.game=allocate(LIFE_GAME_SIZE);f.native=f.game+0x190;
    protect(f.game,LIFE_GAME_SIZE,0);
    const uint32_t pages[]={0x1000,0x4ed000,0x4f0000,0x601000,0x602000,0x4f9000,0x6ce000,0x7fa000,0x61000,
                          0x1726000,0x1704000,0x174d000,0x1ab7000,0x2860000,0x1ab6000};
    for(size_t i=0;i<sizeof(pages)/sizeof(*pages);i++)protect(f.image+pages[i],4096,0);
    memcpy(f.image+0x4ed280,lifecycle_construct_witness,sizeof(lifecycle_construct_witness));
    memcpy(f.image+0x4ed570,lifecycle_close_witness,sizeof(lifecycle_close_witness));
    memcpy(f.image+0x4f0780,lifecycle_buffers_witness,sizeof(lifecycle_buffers_witness));
    memcpy(f.image+0x6ce580,frame_update_witness,sizeof(frame_update_witness));
    memcpy(f.image+0x6ce690,frame_render_witness,sizeof(frame_render_witness));
    memcpy(f.image+0x174d764,lifecycle_gc_max_ms_witness,4);memcpy(f.image+0x174dad0,lifecycle_gc_settings_witness,16);
    strcpy((char *)f.image+0x17267c8,"LuaEnvironment");strcpy((char *)f.image+0x17049a8,"lua");
    putptr(f.image+0x1ab7938,(uintptr_t)&f.resources);
    f.allocator_vtable[8]=(uintptr_t)allocator_free;f.buffers[0]=0x21;f.buffers[1]=0x22;
    HD2NativeFactory factory={&f,create,closed,fatal};HD2LifecycleTargets targets;
    need(hd2env_set_native_factory(&factory,&targets),"factory setup");
    thunk(f.image+0x1000,targets.close);targets.close=(uintptr_t)(f.image+0x1000);
    refused(&f,&targets,(uintptr_t)f.image,0x4ed5de);
    refused(&f,&targets,UINTPTR_MAX,LIFE_IMAGE_SIZE);
    HD2LifecycleTargets remote_target=targets;
    remote_target.close=(uintptr_t)f.image+0x4ed58a+UINT64_C(0x80000000);
    refused(&f,&remote_target,(uintptr_t)f.image,LIFE_IMAGE_SIZE);
    for(size_t i=0;i<sizeof(lifecycle_construct_witness);i++){
        f.image[0x4ed280+i]^=1;refused(&f,&targets,(uintptr_t)f.image,LIFE_IMAGE_SIZE);f.image[0x4ed280+i]^=1;
    }
    for(size_t i=0;i<sizeof(lifecycle_close_witness);i++){
        f.image[0x4ed570+i]^=1;refused(&f,&targets,(uintptr_t)f.image,LIFE_IMAGE_SIZE);f.image[0x4ed570+i]^=1;
    }
    HD2LifecyclePatch patches[2];HD2FramePatch frames[2];
    need(hd2env_plan_lifecycle_patches(f.image,LIFE_IMAGE_SIZE,(uintptr_t)f.image,&targets,patches),"lifecycle plan");
    need(hd2env_plan_frame_patches(f.image,LIFE_IMAGE_SIZE,&targets.frames,frames),"frame plan");
    for(unsigned i=0;i<2;i++){
        memcpy(f.image+patches[i].rva,patches[i].replacement,patches[i].size);
        memcpy(f.image+frames[i].rva,frames[i].replacement,frames[i].size);
    }
    thunk(f.image+0x601fb0,(uintptr_t)allocator_init);thunk(f.image+0x6020e0,(uintptr_t)environment_allocator_close);
    thunk(f.image+0x4f9ea0,(uintptr_t)vm_allocator_close);thunk(f.image+0x7faeb0,(uintptr_t)before_update);
    thunk(f.image+0x61850,(uintptr_t)after_update);
    for(unsigned i=0;i<9;i++)protect(f.image+pages[i],4096,1);
    for(unsigned cycle=0;cycle<2;cycle++){
        f.event_count=0;
        void *result=((Construct)(f.image+0x4ed280))(f.native,&f.resources);
        need(result==f.native&&f.e&&hd2env_native_state_count()==1&&!strcmp(f.events,"IIV"),"constructor result/order");
        need(pointer(f.native)==0&&pointer(f.native+0x100148)==0,"state leaked into PUC fields");
        need(!hd2env_set_native_factory(&factory,&targets)&&!hd2env_clear_native_factory()&&!hd2env_unbind_frames(f.e),"owned lifecycle detached");
        const char *setup="function poc_lifecycle_gc() collectgarbage('step',0) end;"
            "poc_native_finalizer=newproxy(true);getmetatable(poc_native_finalizer).__gc=function() print('POC_LIFECYCLE_FINALIZER') end";
        lua_ok(hd2env_eval(f.e,setup,strlen(setup),"@lifecycle-setup"));
#ifndef HD2ENV_PUC_REFERENCE
        if(!cycle)lua_ok(hd2env_require(f.e,"poc/bootstrap_scenarios.lua"));
        else
#endif
        {lua_ok(hd2env_require(f.e,"stock/boot"));lua_ok(hd2env_call(f.e,"init",0,0));}
        unsigned ticks=cycle?1:4000;
        for(unsigned i=0;i<ticks;i++){
#ifndef HD2ENV_PUC_REFERENCE
            if(!cycle)lua_ok(hd2env_call(f.e,"poc_bootstrap_before_frame",0,0));
#endif
            ((Tick)(f.image+0x6ce580))(f.game,1.0f/60);
            ((Close)(f.image+0x6ce690))(f.game);
        }
#ifndef HD2ENV_PUC_REFERENCE
        if(!cycle){lua_ok(hd2env_call(f.e,"poc_trace_report",0,0));lua_ok(hd2env_call(f.e,"poc_bootstrap_finish",0,0));}
        else
#endif
        lua_ok(hd2env_call(f.e,"shutdown",0,0));
        /* Exercise original native buffer cleanup before and after Lua close. */
        put32(f.native+0x100128,2);put32(f.native+0x10012c,2);putptr(f.native+0x100130,(uintptr_t)f.buffers);
        f.event_count=0;((Close)(f.image+0x4ed570))(f.native);
        need(!f.e&&!*out&&!strcmp(f.events,"BBFCALN"),"destructor/finalizer/native cleanup order");
    }
    need(f.created==2&&f.closed==2&&f.finalized==2&&f.collections==4001,"lifecycle counts");
    need(hd2env_native_state_count()==0&&hd2env_clear_native_factory(),"factory teardown");
    protect(f.image+0x4ed000,4096,0);protect(f.image+0x6ce000,4096,0);
    for(unsigned i=0;i<2;i++){
        need(!memcmp(f.image+patches[i].rva,patches[i].replacement,patches[i].size),"lifecycle patch changed");
        memcpy(f.image+patches[i].rva,patches[i].original,patches[i].size);
        memcpy(f.image+frames[i].rva,frames[i].original,frames[i].size);
    }
    need(hd2env_plan_lifecycle_patches(f.image,LIFE_IMAGE_SIZE,(uintptr_t)f.image,&targets,patches)&&
         hd2env_plan_frame_patches(f.image,LIFE_IMAGE_SIZE,&targets.frames,frames),"restored caller guards");
    dispose(f.game,LIFE_GAME_SIZE);dispose(f.image,LIFE_IMAGE_SIZE);current=NULL;
    printf("POC_LIFECYCLE construct=pass close=pass bookkeeping=pass no_puc_state=pass finalizers=pass reuse=pass guards=pass rollback=pass states=2 frames=4001\n");
}
