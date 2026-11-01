#include "gc_policy.h"
/* Complete captured game destructor execution, with native services/allocators
 * replaced by fixtures. The original cleanup instructions remain untouched. */
#define _GNU_SOURCE
#define HD2_LIFECYCLE_TEST_DATA
#include "shutdown_test_fixture.h"
#include "shutdown_routes.h"
#include "boot_routes.h"
#include "shutdown_witnesses.h"
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
enum { IMAGE_SIZE=0x29fe000,GAME_SIZE=0x102000 };
typedef void (WINCALL *Entry)(void *);
typedef void *(WINCALL *Construct)(void *,void *);
typedef void (WINCALL *Tick)(void *,float);
typedef struct {
    unsigned char *image,*game,*native;HD2Environment *e,**out;
    HD2Backend backend;const HD2Asset *assets;size_t count;
    void (*original_log)(void *,const char *,size_t);
    HD2LifecycleTargets life;HD2ShutdownTargets targets;
    uintptr_t allocator_vtable[9],global_allocator,pool_allocator,service_vtable[1];
    uintptr_t native_hook[21],plugin_api[3][21],plugin_rows[12],plugin_objects[3],services[8],buffers[2];
    char events[2048];size_t used;
    unsigned cycle,created,closed,dead_finalized,live_finalized,reports,frames,gc_steps;
    int armed,cleaning,service_mode,lua_error;const char *mode;
} Fixture;
static Fixture *current;
static void need(int ok,const char *why){if(!ok){fprintf(stderr,"SHUTDOWN ERROR: %s\n",why);exit(18);}}
static void event(const char *name){
    Fixture *f=current;size_t n=strlen(name);need(f->used+n+2<sizeof(f->events),"event buffer");
    memcpy(f->events+f->used,name,n);f->used+=n;f->events[f->used++]=';';f->events[f->used]=0;
}
static void lua_ok(int ok){need(ok,hd2env_error(current->e));need(!hd2env_stack_depth(current->e),"Lua stack balance");}
static int mode(const char *name){return !strcmp(current->mode,name);}
static uintptr_t pointer(const void *p){uintptr_t n;memcpy(&n,p,8);return n;}
static void putptr(void *p,uintptr_t n){memcpy(p,&n,8);}
static void put32(void *p,uint32_t n){memcpy(p,&n,4);}
static unsigned char *allocate(size_t size){
#ifdef _WIN32
    void *p=VirtualAlloc(NULL,size,MEM_RESERVE|MEM_COMMIT,PAGE_NOACCESS);need(p!=NULL,"VirtualAlloc");
#else
    void *p=mmap(NULL,size,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);need(p!=MAP_FAILED,"mmap");
#endif
    return p;
}
static void protect(void *p,size_t size,int execute){
#ifdef _WIN32
    DWORD old;need(VirtualProtect(p,size,execute?PAGE_EXECUTE_READ:PAGE_READWRITE,&old),"VirtualProtect");
    if(execute)need(FlushInstructionCache(GetCurrentProcess(),p,size),"FlushInstructionCache");
#else
    need(!mprotect(p,size,execute?PROT_READ|PROT_EXEC:PROT_READ|PROT_WRITE),"mprotect");
    if(execute)__builtin___clear_cache(p,(char *)p+size);
#endif
}
static void dispose(void *p,size_t size){
#ifdef _WIN32
    (void)size;need(VirtualFree(p,0,MEM_RELEASE),"VirtualFree");
#else
    need(!munmap(p,size),"munmap");
#endif
}
static void thunk(unsigned char *p,uintptr_t target){p[0]=0x48;p[1]=0xb8;putptr(p+2,target);p[10]=0xff;p[11]=0xe0;}
static void guard_lifetime(void){
    Fixture *f=current;need(f->e&&hd2env_native_state_count()==1,"environment lifetime");
    need(!hd2env_destroy(f->e)&&!hd2env_unbind_frames(f->e)&&!hd2env_clear_native_factory(),"active shutdown lifetime guard");
}
static void log_message(void *context,const char *text,size_t size){
    Fixture *f=current;
    if(size==12&&!memcmp(text,"POC_SHUT_LUA",12)){
        need(f->armed&&!f->cleaning&&!hd2env_native_shutdown_complete(f->e),"shutdown call phase");event("lua");guard_lifetime();
        uint64_t faults=hd2env_frame_fault_count();((Entry)f->life.frames.render)(f->native);need(hd2env_frame_fault_count()==faults+1,"frame entered during shutdown");
        if(mode("shutdown-fail-recursive"))((Entry)f->targets.shutdown)(f->native);
    }else if(size==13&&!memcmp(text,"POC_SHUT_DEAD",13)){
        need(f->armed&&!f->cleaning&&!hd2env_native_shutdown_complete(f->e),"full collection phase");guard_lifetime();f->dead_finalized++;event("gc");
    }else if(size==13&&!memcmp(text,"POC_SHUT_LIVE",13)){
        need(f->cleaning&&f->e&&hd2env_native_state_count()==1,"reachable finalizer before close/backend release");
        f->live_finalized++;event("close-finalizer");
    }
    if(f->original_log)f->original_log(context,text,size);
}
static int step(void *context,HD2Environment *e){
    Fixture *f=context;need(e==f->e&&!f->armed,"timed collection during shutdown");f->gc_steps++;
    return hd2env_collect_frame(e,NULL);
}
static void report(void *context,HD2Environment *e,const char *op,const char *message){
    Fixture *f=context;need(e==f->e&&f->lua_error&&!strcmp(op,"shutdown")&&strstr(message,"fixture shutdown Lua failure"),"shutdown diagnostic");
    guard_lifetime();f->reports++;event("error");
    lua_ok(hd2env_eval(e,"shutdown_reported=true",22,"@shutdown-reporter"));
}
static int unused_register(void *context,HD2Environment *e,unsigned stage,const uintptr_t *args,size_t count){(void)context;(void)e;(void)stage;(void)args;(void)count;return 0;}
static int unused_read(void *context,uintptr_t at,void *out,size_t size){(void)context;(void)at;(void)out;(void)size;return 0;}
static HD2Environment *create(void *context,void *address,void *resources,HD2FrameCallbacks *frames,char *error,size_t capacity){
    Fixture *f=context;need(address==f->native&&resources==&f->global_allocator,"factory arguments");
    need(!pointer(f->native)&&!pointer(f->native+0x100148),"constructor created PUC state");
    *frames=(HD2FrameCallbacks){f,step,report};
    f->e=hd2env_create(f->assets,f->count,&f->backend,error,capacity);*f->out=f->e;
    if(f->e){f->created++;if(mode("shutdown-fail-boot")){HD2BootCallbacks callbacks={f,unused_register,unused_read};need(hd2env_bind_boot(f->e,&callbacks),"unfinished boot binding");}}
    return f->e;
}
static void closed(void *context,void *address){
    Fixture *f=context;need(address==f->native&&f->live_finalized==f->created&&hd2env_native_state_count()==0,"close notification order");
    need(!hd2env_clear_native_factory(),"factory changed during close notification");f->closed++;event("closed");f->e=NULL;*f->out=NULL;
}
static void fatal(void *context,void *address,const char *operation,const char *message){
    Fixture *f=context;need(address==f->native&&!f->cleaning,"fatal continued to native cleanup");
    int expected=(mode("shutdown-finalizer-error")&&!strcmp(operation,"shutdown-gc")&&strstr(message,"fixture shutdown GC failure"))||
      (mode("shutdown-fail-close")&&!strcmp(operation,"close"))||
      ((mode("shutdown-fail-unbound")||mode("shutdown-fail-order")||mode("shutdown-fail-recursive")||mode("shutdown-fail-duplicate")||mode("shutdown-fail-boot"))&&!strcmp(operation,"shutdown")&&strstr(message,"out of order"));
    if(!expected){fprintf(stderr,"SHUTDOWN unexpected fatal %s: %s\n",operation,message);exit(18);}
    printf("POC_SHUTDOWN_FAILURE mode=%s operation=%s\n",f->mode,operation);fflush(stdout);
#ifdef _WIN32
    ExitProcess(42);
#else
    _exit(42);
#endif
}
static void WINCALL allocator_init(void *object,const char *name,void *parent,unsigned flag){
    Fixture *f=current;
    if(object==f->native+8)need(!strcmp(name,"LuaEnvironment")&&parent==&f->global_allocator&&flag==1,"environment allocator init");
    else need(object==f->native+0x88&&!strcmp(name,"lua")&&!parent&&!flag,"VM allocator init");
    putptr(object,(uintptr_t)f->allocator_vtable);
}
static void before_native_cleanup(void){
    Fixture *f=current;need(f->e&&hd2env_native_shutdown_complete(f->e)&&f->dead_finalized==f->created&&f->live_finalized==f->closed,"native cleanup before full collection");
    if(!f->cleaning){
        uint64_t faults=hd2env_frame_fault_count();((Tick)f->life.frames.update)(f->native,1.0f/60);((Entry)f->life.frames.gc)(f->native);
        need(hd2env_frame_fault_count()==faults+2,"frame or timed GC entered after shutdown");f->cleaning=1;
    }
}
static void WINCALL native_hook(void){before_native_cleanup();event("hook");}
static void WINCALL plugin_shutdown(void *api){
    before_native_cleanup();need(api==current->plugin_api[0]||api==current->plugin_api[2],"plugin shutdown this");event("plugin");
}
static const char *service_name(void *object){
    Fixture *f=current;
    const char *names[]={"voip","friends","leaderboard","stats","cloud","steam","extra","platform"};
    for(unsigned i=0;i<8;i++)if(object==f->services+i)return names[i];
    if(object==f->plugin_objects||object==f->plugin_objects+2)return "plugin-object";
    need(0,"unknown native object");return "";
}
static void WINCALL native_delete(void *object,unsigned flags){before_native_cleanup();need(!flags,"delete flags");event(service_name(object));}
static void WINCALL voip_delete(void *object){need(object==current->services,"voice destructor this");native_delete(object,0);}
static void WINCALL friends_delete(void *object){need(object==current->services+1,"friends destructor this");native_delete(object,0);}
static void WINCALL cloud_delete(void *object){need(object==current->services+4,"cloud destructor this");native_delete(object,0);}
static void WINCALL native_free(void *allocator,void *memory,unsigned alignment){
    Fixture *f=current;need(!alignment,"native free alignment");
    if(allocator==f->native+8){
        if(memory==f->buffers){need(!f->e&&f->closed==f->created,"buffer array before Lua close");event("buffer-array");}
        else{need(memory==(void *)f->buffers[0]||memory==(void *)f->buffers[1],"native buffer pointer");before_native_cleanup();event("buffer");}
        return;
    }
    need(allocator==&f->global_allocator||allocator==&f->pool_allocator,"native allocator this");
    before_native_cleanup();const char *name=service_name(memory);
    if(memory==f->services||memory==f->plugin_objects||memory==f->plugin_objects+2)need(allocator==&f->global_allocator,"global allocator ownership");
    else need(allocator==&f->pool_allocator,"pool allocator ownership");
    event(name);event("free");
}
static void WINCALL release_handle(void *handle,unsigned flag){
    before_native_cleanup();need(!flag&&(handle==(void *)0x111||handle==(void *)0x222),"native handle release");event("handle");
}
static void WINCALL global_cleanup(void){
    Fixture *f=current;before_native_cleanup();
    const uint32_t zeroed[]={0x1ab6eb0,0x1ab7720,0x1ab6ea8,0x1ab7718,0x1ab7710};
    for(unsigned i=0;i<5;i++)need(!pointer(f->image+zeroed[i]),"native global reset");
    need(!f->image[0x1ab6c6e]&&!f->image[0x1a741c2],"native flag reset");event("globals");
}
static void WINCALL after_services(void){before_native_cleanup();need(!pointer(current->image+0x286d9c8),"native pointer reset");event("services-done");}
static void WINCALL game_buffer(void *object,unsigned zero){
    before_native_cleanup();need(object==current->game+0x100350&&!zero&&!pointer(current->image+0x2860918),"game buffer cleanup");event("game-buffer");
}
static void WINCALL mutex_close(void *object){before_native_cleanup();need(object==current->game+0x100318,"mutex cleanup this");event("mutex");}
static void WINCALL vm_allocator_close(void *object){need(object==current->native+0x88&&!current->e,"VM allocator after close");event("vm-allocator");}
static void WINCALL allocator_close(void *object){
    Fixture *f=current;need(!f->e&&f->closed==f->created,"allocator teardown before close");
    if(object==f->native+8)event("env-allocator");
    else if(object==f->game+0x108)event("game-allocator-1");
    else if(object==f->game+0x88)event("game-allocator-2");
    else {need(object==f->game+8,"game allocator this");event("game-allocator-3");}
}
static void WINCALL before_frame(float dt){need(dt==1.0f/60&&!current->armed,"before frame after shutdown");}
static void WINCALL after_frame(float dt){need(dt==1.0f/60&&!current->armed,"after frame after shutdown");current->frames++;}
static void refused(Fixture *f,const HD2ShutdownTargets *t,size_t size){
    HD2ShutdownPatch out[3],saved[3];memset(out,0xa5,sizeof(out));memcpy(saved,out,sizeof(out));
    need(!hd2env_plan_shutdown_patches(f->image,size,t,out)&&!memcmp(out,saved,sizeof(out)),"unsafe plan or changed refusal output");
}
static void prepare_cleanup(Fixture *f){
    unsigned char *b=f->image;f->service_mode=f->cycle%2==0;
    f->native_hook[20]=(uintptr_t)native_hook;putptr(b+0x1ab6d70,(uintptr_t)f->native_hook);
    b[0x1ab6d89]=(unsigned char)(f->cycle/2);putptr(b+0x1ab6d78,f->cycle%2);
    put32(b+0x1a741c8,f->service_mode?3:0);putptr(b+0x19b0d68,(uintptr_t)f->plugin_rows);
    for(unsigned i=0;i<3;i++){
        f->plugin_rows[i*4+1]=(uintptr_t)f->plugin_api[i];f->plugin_api[i][20]=i==1?0:(uintptr_t)plugin_shutdown;
        f->plugin_objects[i]=(uintptr_t)f->service_vtable;putptr(b+0x1a751d0+i*8,i==1?0:(uintptr_t)(f->plugin_objects+i));
    }
    b[0x1ab6c6e]=(unsigned char)f->service_mode;putptr(b+0x2409048,0x111);putptr(b+0x24091a8,0x222);
    putptr(b+0x19e2e88,(uintptr_t)release_handle);putptr(b+0x148d370,(uintptr_t)mutex_close);
    const uint32_t globals[]={0x1ab6eb0,0x1ab7720,0x1ab6ea8,0x1ab7718,0x1ab7710,0x286d9c8,0x2860918};
    for(unsigned i=0;i<7;i++)putptr(b+globals[i],0x1234);
    b[0x1a741c2]=1;
    const uint32_t slots[]={0x2860598,0x28605b0,0x28605a0,0x28605b8,0x28605c0,0x28605a8,0x286d9c0,0x1bbb760};
    for(unsigned i=0;i<8;i++){f->services[i]=(uintptr_t)f->service_vtable;putptr(b+slots[i],f->service_mode?(uintptr_t)(f->services+i):0);}
    f->buffers[0]=0x31;f->buffers[1]=0x32;put32(f->native+0x100128,2);put32(f->native+0x10012c,2);putptr(f->native+0x100130,(uintptr_t)f->buffers);
}
static void check_events(Fixture *f){
    char expected[2048]="lua;";
    if(f->lua_error)strcat(expected,"error;");
    strcat(expected,"gc;");
    if(f->cycle==3)strcat(expected,"hook;");
    if(f->service_mode)strcat(expected,"plugin;plugin-object;plugin-object;free;plugin;plugin-object;plugin-object;free;handle;handle;");
    strcat(expected,"globals;");
    if(f->service_mode)strcat(expected,"voip;voip;free;friends;friends;free;leaderboard;leaderboard;free;stats;stats;free;cloud;cloud;free;steam;steam;free;extra;extra;free;platform;platform;free;");
    strcat(expected,"services-done;game-buffer;mutex;buffer;buffer;close-finalizer;closed;buffer-array;vm-allocator;env-allocator;game-allocator-1;game-allocator-2;game-allocator-3;");
    if(strcmp(expected,f->events)){fprintf(stderr,"expected: %s\nactual:   %s\n",expected,f->events);need(0,"native teardown order");}
    need(f->image[0x1ab6d89]==(f->cycle==2?1:0),"native hook condition flags changed");
    if(f->service_mode)for(unsigned i=0;i<3;i++)need(!pointer(f->image+0x1a751d0+i*8),"plugin ownership slot not cleared");
    need(pointer(f->game)==(uintptr_t)f->image+0x1730ca8,"final native vtable");
}
void check_shutdown_routes(const HD2Asset *assets,size_t count,const HD2Backend *backend,HD2Environment **out,const char *which){
    Fixture f={0};current=&f;f.assets=assets;f.count=count;f.backend=*backend;f.out=out;f.mode=which;
    f.original_log=f.backend.log;f.backend.log=log_message;f.image=allocate(IMAGE_SIZE);f.game=allocate(GAME_SIZE);f.native=f.game+0x190;protect(f.game,GAME_SIZE,0);
    const uint32_t codepages[]={0x1000,0x4ed000,0x4f0000,0x4f9000,0x601000,0x602000,0x6cd000,0x6ce000,0x61000,0x7fa000,0x1c4000,0x7d4000,0x7cb000,0x7d0000,0x12ae000};
    const uint32_t datapages[]={0x1726000,0x1704000,0x174d000,0x1ab7000,0x1ab6000,0x2860000,0x286d000,0x1bbb000,0x1bba000,
        0x1a74000,0x1a75000,0x19b0000,0x19e2000,0x2409000,0x148d000};
    for(size_t i=0;i<sizeof(codepages)/sizeof(*codepages);i++)protect(f.image+codepages[i],4096,0);
    for(size_t i=0;i<sizeof(datapages)/sizeof(*datapages);i++)protect(f.image+datapages[i],4096,0);
    memcpy(f.image+0x6cd470,shutdown_game_witness,sizeof(shutdown_game_witness));
    memcpy(f.image+0x4ed280,lifecycle_construct_witness,sizeof(lifecycle_construct_witness));memcpy(f.image+0x4ed570,lifecycle_close_witness,sizeof(lifecycle_close_witness));
    memcpy(f.image+0x4f0780,lifecycle_buffers_witness,sizeof(lifecycle_buffers_witness));memcpy(f.image+0x174d764,lifecycle_gc_max_ms_witness,4);memcpy(f.image+0x174dad0,lifecycle_gc_settings_witness,16);
    memcpy(f.image+0x6ce580,frame_update_witness,sizeof(frame_update_witness));memcpy(f.image+0x6ce690,frame_render_witness,sizeof(frame_render_witness));
    strcpy((char *)f.image+0x17267c8,"LuaEnvironment");strcpy((char *)f.image+0x17049a8,"lua");
    f.allocator_vtable[8]=(uintptr_t)native_free;f.global_allocator=f.pool_allocator=(uintptr_t)f.allocator_vtable;f.service_vtable[0]=(uintptr_t)native_delete;
    putptr(f.image+0x1ab7938,(uintptr_t)&f.global_allocator);putptr(f.image+0x1bba3a0,(uintptr_t)&f.pool_allocator);
    HD2NativeFactory factory={&f,create,closed,fatal};need(hd2env_set_native_factory(&factory,&f.life),"native factory");need(hd2env_get_shutdown_targets(&f.targets),"shutdown targets");
    need(!hd2env_get_shutdown_targets(NULL)&&!hd2env_native_shutdown_complete(NULL),"null API requests");
    refused(&f,&f.targets,0x6cd86a);HD2ShutdownTargets invalid=f.targets;invalid.collect=0;refused(&f,&invalid,IMAGE_SIZE);invalid=f.targets;invalid.shutdown=0;refused(&f,&invalid,IMAGE_SIZE);
    for(size_t i=0;i<sizeof(shutdown_game_witness);i++){f.image[0x6cd470+i]^=1;refused(&f,&f.targets,IMAGE_SIZE);f.image[0x6cd470+i]^=1;}
    HD2ShutdownPatch patches[3];HD2LifecyclePatch life[2];HD2FramePatch frames[2];
    need(hd2env_plan_shutdown_patches(f.image,IMAGE_SIZE,&f.targets,patches),"shutdown plan");
    thunk(f.image+0x1000,f.life.close);HD2LifecycleTargets nearby=f.life;nearby.close=(uintptr_t)(f.image+0x1000);
    need(hd2env_plan_lifecycle_patches(f.image,IMAGE_SIZE,(uintptr_t)f.image,&nearby,life),"lifecycle plan");need(hd2env_plan_frame_patches(f.image,IMAGE_SIZE,&f.life.frames,frames),"frame plan");
    for(unsigned i=0;i<3;i++)memcpy(f.image+patches[i].rva,patches[i].replacement,patches[i].size);
    for(unsigned i=0;i<2;i++){memcpy(f.image+life[i].rva,life[i].replacement,life[i].size);memcpy(f.image+frames[i].rva,frames[i].replacement,frames[i].size);}
    const struct {uint32_t rva;uintptr_t fn;} helpers[]={
        {0x601fb0,(uintptr_t)allocator_init},{0x6020e0,(uintptr_t)allocator_close},{0x4f9ea0,(uintptr_t)vm_allocator_close},
        {0x7faeb0,(uintptr_t)before_frame},{0x61850,(uintptr_t)after_frame},{0x1c4cc0,(uintptr_t)global_cleanup},
        {0x7d4670,(uintptr_t)voip_delete},{0x7cb8d0,(uintptr_t)friends_delete},{0x7d0af0,(uintptr_t)cloud_delete},
        {0x12aefb0,(uintptr_t)after_services},{0x6cef90,(uintptr_t)game_buffer}};
    for(size_t i=0;i<sizeof(helpers)/sizeof(*helpers);i++)thunk(f.image+helpers[i].rva,helpers[i].fn);
    for(size_t i=0;i<sizeof(codepages)/sizeof(*codepages);i++)protect(f.image+codepages[i],4096,1);
    if(mode("shutdown-fail-unbound"))((Entry)f.targets.shutdown)(f.native);
    for(f.cycle=0;f.cycle<4;f.cycle++){
        f.armed=f.cleaning=0;f.used=0;f.events[0]=0;f.lua_error=f.cycle==2;
        f.image[0x1ab6d89]=0;putptr(f.image+0x1ab6d78,0);put32(f.image+0x1a741c8,0);
        /* A fresh game boot replaces services. This fixture constructs directly,
         * so clear the previous cycle's borrowed service slots before frames. */
        const uint32_t old_services[]={0x2860598,0x28605b0,0x28605a0,0x28605b8,0x28605c0,0x28605a8,0x286d9c0,0x1bbb760};
        for(unsigned i=0;i<8;i++)putptr(f.image+old_services[i],0);
        need(((Construct)(f.image+0x4ed280))(f.native,&f.global_allocator)==f.native&&f.e,"captured constructor");
        if(mode("shutdown-fail-order"))((Entry)f.targets.collect)(f.native);
        if(mode("shutdown-fail-boot"))((Entry)f.targets.shutdown)(f.native);
#ifndef HD2ENV_PUC_REFERENCE
        if(!f.cycle)lua_ok(hd2env_require(f.e,"poc/bootstrap_scenarios.lua"));else
#endif
        {lua_ok(hd2env_require(f.e,"stock/boot"));lua_ok(hd2env_call(f.e,"init",0,0));}
        unsigned ticks=f.cycle?1:4000;
        for(unsigned i=0;i<ticks;i++){
#ifndef HD2ENV_PUC_REFERENCE
            if(!f.cycle)lua_ok(hd2env_call(f.e,"poc_bootstrap_before_frame",0,0));
#endif
            ((Tick)(f.image+0x6ce580))(f.game,1.0f/60);((Entry)(f.image+0x6ce690))(f.game);
        }
#ifndef HD2ENV_PUC_REFERENCE
        if(!f.cycle){lua_ok(hd2env_call(f.e,"poc_trace_report",0,0));lua_ok(hd2env_call(f.e,"poc_bootstrap_before_shutdown",0,0));}
#endif
        prepare_cleanup(&f);
        /* Both old state fields point into an inaccessible image page. */
        putptr(f.native,(uintptr_t)f.image+0x2000);putptr(f.native+0x100148,(uintptr_t)f.image+0x2000);
        const char *setup="collectgarbage('stop');collectgarbage=function() error('Lua collection global must not be used') end;"
            "shutdown_dead=newproxy(true);getmetatable(shutdown_dead).__gc=function() print('POC_SHUT_DEAD') end;"
            "shutdown_live=newproxy(true);getmetatable(shutdown_live).__gc=function() print('POC_SHUT_LIVE') end;"
            "local old=shutdown;shutdown=function() print('POC_SHUT_LUA');shutdown_dead=nil;old();"
            "if poc_bootstrap_after_shutdown then poc_bootstrap_after_shutdown() end end";
        lua_ok(hd2env_eval(f.e,setup,strlen(setup),"@shutdown-test"));
        if(f.lua_error){setup="shutdown=function() print('POC_SHUT_LUA');shutdown_dead=nil;error('fixture shutdown Lua failure') end";lua_ok(hd2env_eval(f.e,setup,strlen(setup),"@shutdown-error"));}
        if(mode("shutdown-finalizer-error")){setup="getmetatable(shutdown_dead).__gc=function() print('POC_SHUT_DEAD');error('fixture shutdown GC failure') end";lua_ok(hd2env_eval(f.e,setup,strlen(setup),"@shutdown-gc-error"));}
        f.armed=1;
        if(mode("shutdown-fail-duplicate")||mode("shutdown-fail-close")){
            ((Entry)f.targets.shutdown)(f.native);
            if(mode("shutdown-fail-duplicate"))((Entry)f.targets.shutdown)(f.native);else ((Entry)f.life.close)(f.native);
        }
        ((Entry)(f.image+0x6cd470))(f.game);
        need(!f.e&&!*out&&!hd2env_native_state_count(),"captured shutdown did not close environment");check_events(&f);
    }
    need(f.created==4&&f.closed==4&&f.dead_finalized==4&&f.live_finalized==4&&f.reports==1&&f.frames==4003&&f.gc_steps==4003,"shutdown totals");
    need(hd2env_clear_native_factory(),"factory release");
    protect(f.image+0x6cd000,4096,0);protect(f.image+0x4ed000,4096,0);protect(f.image+0x6ce000,4096,0);
    for(unsigned i=0;i<3;i++){need(!memcmp(f.image+patches[i].rva,patches[i].replacement,patches[i].size),"shutdown patch changed");memcpy(f.image+patches[i].rva,patches[i].original,patches[i].size);}
    for(unsigned i=0;i<2;i++){memcpy(f.image+life[i].rva,life[i].original,life[i].size);memcpy(f.image+frames[i].rva,frames[i].original,frames[i].size);}
    need(hd2env_plan_shutdown_patches(f.image,IMAGE_SIZE,&f.targets,patches)&&hd2env_plan_lifecycle_patches(f.image,IMAGE_SIZE,(uintptr_t)f.image,&nearby,life)&&
         hd2env_plan_frame_patches(f.image,IMAGE_SIZE,&f.life.frames,frames),"restored byte witnesses");
    dispose(f.game,GAME_SIZE);dispose(f.image,IMAGE_SIZE);current=NULL;
    puts("POC_SHUTDOWN lua=pass full_gc=pass native_order=pass hook_flags=pass errors=pass lifetime=pass frame_gate=pass guards=pass rollback=pass states=4 frames=4003");
}
