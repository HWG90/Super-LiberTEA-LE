#include "gc_policy.h"
/* Execute the captured boot function in an owned image. Native engine services
 * and registrar bodies remain explicit fixtures; old PUC pages are absent. */
#define _GNU_SOURCE
#include "boot_routes.h"
#include "steam_test_fixture.h"
#include "friends_test_fixture.h"
#include "boot_witnesses.h"
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
enum { BOOT_IMAGE_SIZE=0x29fe000,BOOT_GAME_SIZE=0x102000 };
typedef void (WINCALL *Entry)(void *);
typedef void (WINCALL *Create)(void *,void *);
typedef void (WINCALL *Boot)(void *,void *,void *);
typedef void (WINCALL *Tick)(void *,float);
typedef struct {
    unsigned char *image,*game,*native;
    unsigned char app[0x600],platform[0x160],network[0x1170],binary_config[512];
    unsigned char options[24],object[16],rows[9*0x38];
    char names[9][64];
    uintptr_t allocator[9],plugin[20],plugin_rows[8];
    void *allocations[3];
    const HD2Asset *assets;size_t asset_count;HD2Backend backend;
    SteamTestFixture *steam;
    FriendsTestFixture *friends;
    HD2Environment *e,**out;HD2LifecycleTargets life;HD2BootTargets targets;
    unsigned allocation_count,freed,api_setup,registered,plugins,render_plugins,collections,closed;
    const char *mode;int cycle;
} BootFixture;
static BootFixture *current;
static void need(int ok,const char *why){if(!ok){fprintf(stderr,"BOOT ERROR: %s\n",why);exit(14);}}
static void lua_ok(int ok){need(ok,hd2env_error(current->e));need(hd2env_stack_depth(current->e)==0,"stack imbalance");}
static uintptr_t pointer(const void *p){uintptr_t n;memcpy(&n,p,8);return n;}
static uint32_t word(const void *p){uint32_t n;memcpy(&n,p,4);return n;}
static void putptr(void *p,uintptr_t n){memcpy(p,&n,8);}
static void put32(void *p,uint32_t n){memcpy(p,&n,4);}
static void thunk(unsigned char *p,uintptr_t target){p[0]=0x48;p[1]=0xb8;putptr(p+2,target);p[10]=0xff;p[11]=0xe0;}
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
static int mode(const char *m){return !strcmp(current->mode,m);}
static int read_native(void *context,uintptr_t address,void *out,size_t size){
    BootFixture *f=context;
    if(mode("boot-fail-config")&&address==(uintptr_t)f->rows+0x30)return 0;
    /* Only fixture-owned data may be read. This also checks overflow. */
    const uintptr_t starts[]={(uintptr_t)f->options,(uintptr_t)f->object,(uintptr_t)f->rows,
                             (uintptr_t)f->names,(uintptr_t)f->binary_config};
    const size_t sizes[]={sizeof(f->options),sizeof(f->object),sizeof(f->rows),sizeof(f->names),sizeof(f->binary_config)};
    for(unsigned i=0;i<5;i++)if(address>=starts[i]&&address-starts[i]<=sizes[i]&&size<=sizes[i]-(address-starts[i])){
        memcpy(out,(void *)address,size);return 1;
    }
    return 0;
}
static int collect(void *context,HD2Environment *e){
    BootFixture *f=context;need(e==f->e&&hd2env_boot_complete(e),"collection before complete boot");f->collections++;
    return hd2env_collect_frame(e,NULL);
}
static void report(void *context,HD2Environment *e,const char *op,const char *message){
    (void)context;(void)e;fprintf(stderr,"BOOT frame %s: %s\n",op,message);exit(14);
}
static int register_stage(void *context,HD2Environment *e,unsigned stage,const uintptr_t *args,size_t count){
    BootFixture *f=context;need(e==f->e&&stage==f->registered++&&!hd2env_boot_complete(e),"registration order");
    need(!hd2env_destroy(e)&&!hd2env_unbind_frames(e)&&!hd2env_clear_native_factory(),"registration lifetime guard");
    uintptr_t expected[5]={0};size_t n=0;
    switch(stage){
    case 0:expected[0]=(uintptr_t)f->app;expected[1]=(uintptr_t)(f->game+0x88);n=2;break;
    case 1:expected[0]=steam_test_service(f->steam);n=1;break;
    case 2:expected[0]=0x16;n=1;break;
    case 3:expected[0]=0x17;n=1;break;
    case 4:break;
    case 5:
        expected[0]=0x21;expected[1]=0x22;expected[2]=0x23;n=5;
        need(count==5&&pointer((void *)args[3])==(uintptr_t)f->binary_config&&
             word((void *)(args[3]+8))==6&&word((void *)(args[3]+12))==8,"borrowed network config view");
        expected[3]=args[3];expected[4]=1;break;
    case 6:expected[0]=friends_test_service(f->friends);n=1;break;
    case 7:expected[0]=0x21;expected[1]=0x19;n=2;break;
    }
    need(count==n&&(!n||!memcmp(args,expected,n*sizeof(*args))),"registrar ABI arguments");
    if(mode("boot-fail-recursive")&&stage==0)((Entry)f->targets.registrars[4])(f->native);
    if(mode("boot-fail-registration")&&stage==3)return 0;
    if(stage==1){
        lua_ok(steam_test_register(f->steam,e,args[0]));
        const char *check="assert(stingray.Steam.connected()==true and #stingray.Steam.user_id()==16 and stingray.Steam==debug.getregistry().Steam)";
        lua_ok(hd2env_eval(e,check,strlen(check),"@boot-steam-port"));
    }
    if(stage==6){
        lua_ok(friends_test_register(f->friends,e,args[0]));
        const char *check="assert(stingray.Friends.num_friends()==7 and #stingray.Friends.id(1)==16 and stingray.Friends.FRIEND_FLAG==4 and stingray.Presence==debug.getregistry().Presence)";
        lua_ok(hd2env_eval(e,check,strlen(check),"@boot-friends-port"));
    }
    if(stage==0){
        const char *setup="package.preload['poc/init_fail']=function() init=function() error('fixture init failure') end return true end";
        lua_ok(hd2env_eval(e,setup,strlen(setup),"@boot-register-fixture"));
        if(mode("boot-fail-config-error")){
            setup="setmetatable(_G,{__newindex=function() error('fixture config assignment failure') end})";
            lua_ok(hd2env_eval(e,setup,strlen(setup),"@boot-error-fixture"));
        }
    }
    return 1;
}
static HD2Environment *create(void *context,void *address,void *resources,HD2FrameCallbacks *frames,char *error,size_t size){
    BootFixture *f=context;need(address==f->native&&resources==f->app,"factory arguments");
    f->e=hd2env_create(f->assets,f->asset_count,&f->backend,error,size);*f->out=f->e;
    *frames=(HD2FrameCallbacks){f,collect,report};
    if(f->e){HD2BootCallbacks callbacks={f,register_stage,read_native};need(hd2env_bind_boot(f->e,&callbacks),"bind boot");
        need(!hd2env_bind_boot(f->e,&callbacks),"duplicate boot binding");}
    return f->e;
}
static void closed(void *context,void *address){BootFixture *f=context;need(address==f->native,"close address");f->closed++;f->e=NULL;*f->out=NULL;}
static void fatal(void *context,void *address,const char *op,const char *message){
    BootFixture *f=context;need(address==f->native,"fatal address");
    int expected=(mode("boot-fail-registration")&&!strcmp(op,"boot-register")&&!strcmp(message,"native boot adapter failed"))||
        (mode("boot-fail-config")&&!strcmp(op,"boot-config")&&strstr(message,"memory read refused"))||
        (mode("boot-fail-config-error")&&!strcmp(op,"boot-config")&&strstr(message,"fixture config assignment failure"))||
        (mode("boot-fail-limit")&&!strcmp(op,"boot-config")&&strstr(message,"row limit"))||
        (mode("boot-fail-missing")&&!strcmp(op,"boot-start")&&strstr(message,"boot_script is missing"))||
        (mode("boot-fail-require")&&!strcmp(op,"boot-start")&&strstr(message,"module 'poc/absent' not found"))||
        (mode("boot-fail-init")&&!strcmp(op,"boot-start")&&strstr(message,"fixture init failure"))||
        ((mode("boot-fail-order")||mode("boot-fail-recursive"))&&!strcmp(op,"boot")&&strstr(message,"out of order"));
    if(!expected){fprintf(stderr,"BOOT unexpected fatal %s: %s\n",op,message);exit(14);}
    printf("POC_BOOT_FAILURE mode=%s operation=%s\n",f->mode,op);fflush(stdout);
#ifdef _WIN32
    ExitProcess(42);
#else
    _exit(42);
#endif
}
static void *WINCALL native_allocate(void *allocator,void **result,size_t size,unsigned alignment){
    BootFixture *f=current;const size_t sizes[]={24,64,40};
    need(allocator==f->game+0x88&&alignment==8&&f->allocation_count<3&&size==sizes[f->allocation_count],"native allocate arguments");
    *result=calloc(1,size);need(*result!=NULL,"fixture allocation");f->allocations[f->allocation_count++]=*result;return result;
}
static void WINCALL native_free(void *allocator,void *memory,unsigned alignment){
    BootFixture *f=current;need(allocator==f->game+0x88&&!memory&&!alignment,"native free arguments");f->freed++;
}
static void WINCALL api_setup(void *app,void *allocator){need(app==current->app&&allocator==current->game+0x88,"native API setup arguments");current->api_setup++;}
static int WINCALL native_compare(const char *a,const char *b){return strcmp(a,b);}
static void WINCALL plugin_setup(void *getter){
    BootFixture *f=current;need(getter==f->image+0xa6f70&&f->registered==8&&!hd2env_boot_complete(f->e),"plugin setup order");
    const char *check="assert(boot_enabled==true and boot_false==false and boot_number==16777216 and boot_deleted==nil and boot_ignored==nil and boot_nan~=boot_nan and _G['']==false)";
    lua_ok(hd2env_eval(f->e,check,strlen(check),"@boot-config-check"));f->plugins++;
}
static uintptr_t WINCALL render_plugin(void){current->render_plugins++;return 0x1234;}
static void WINCALL before_update(float dt){need(dt==1.0f/60,"before update delta");}
static void WINCALL after_update(float dt){need(dt==1.0f/60,"after update delta");}
static void row(BootFixture *f,unsigned i,const char *name,uint32_t tag,double number,int boolean,int deleted){
    unsigned char *p=f->rows+i*0x38;strcpy(f->names[i],name);put32(p,(uint32_t)strlen(name)+1);putptr(p+8,(uintptr_t)f->names[i]);
    put32(p+0x18,tag);if((tag&7)==2)memcpy(p+0x20,&number,8);else p[0x20]=(unsigned char)boolean;
    put32(p+0x30,deleted?UINT32_MAX:0);
}
static void refused(BootFixture *f,const HD2BootTargets *t,uintptr_t base,size_t size){
    HD2LifecyclePatch out[HD2_BOOT_PATCHES],saved[HD2_BOOT_PATCHES];memset(out,0xa5,sizeof(out));memcpy(saved,out,sizeof(out));
    need(!hd2env_plan_boot_patches(f->image,size,base,t,out),"unsafe boot plan accepted");need(!memcmp(out,saved,sizeof(out)),"refusal changed output");
}
void check_boot_routes(const HD2Asset *assets,size_t count,const HD2Backend *backend,HD2Environment **out,const char *test_mode){
    BootFixture f={0};current=&f;f.assets=assets;f.asset_count=count;f.backend=*backend;f.out=out;f.mode=test_mode;
    f.image=allocate(BOOT_IMAGE_SIZE);f.game=allocate(BOOT_GAME_SIZE);f.native=f.game+0x190;protect(f.game,BOOT_GAME_SIZE,0);
    const uint32_t code_pages[]={0x1000,0x6cd000,0x6ce000,0x2df000,0x147f000,0x7fa000,0x61000};
    const uint32_t data_pages[]={0x1ab7000,0x2408000,0x2860000,0x1bba000,0x1bbb000,0x286d000,0x1ab6000,0x1a74000,0x19b0000,0x1730000};
    for(unsigned i=0;i<sizeof(code_pages)/sizeof(*code_pages);i++)protect(f.image+code_pages[i],4096,0);
    for(unsigned i=0;i<sizeof(data_pages)/sizeof(*data_pages);i++)protect(f.image+data_pages[i],4096,0);
    f.steam=steam_test_create(f.image,BOOT_IMAGE_SIZE);
    f.friends=friends_test_create(f.image,BOOT_IMAGE_SIZE);
    memcpy(f.image+0x6cdd70,boot_witness,sizeof(boot_witness));
    memcpy(f.image+0x6ce580,frame_update_witness,sizeof(frame_update_witness));
    memcpy(f.image+0x6ce690,frame_render_witness,sizeof(frame_render_witness));
    HD2NativeFactory factory={&f,create,closed,fatal};need(hd2env_set_native_factory(&factory,&f.life),"native factory setup");
    need(hd2env_get_boot_targets(&f.targets),"boot targets");HD2BootTargets nearby=f.targets;
    for(unsigned i=0;i<8;i++){thunk(f.image+0x1000+i*16,f.targets.registrars[i]);nearby.registrars[i]=(uintptr_t)(f.image+0x1000+i*16);}
    refused(&f,&nearby,(uintptr_t)f.image,0x6ce57a);refused(&f,&nearby,UINTPTR_MAX,BOOT_IMAGE_SIZE);
    HD2BootTargets bad=nearby;bad.registrars[0]=(uintptr_t)f.image+0x6cdf51+UINT64_C(0x80000000);refused(&f,&bad,(uintptr_t)f.image,BOOT_IMAGE_SIZE);
    for(size_t i=0;i<sizeof(boot_witness);i++){
        f.image[0x6cdd70+i]^=1;refused(&f,&nearby,(uintptr_t)f.image,BOOT_IMAGE_SIZE);f.image[0x6cdd70+i]^=1;
    }
    HD2LifecyclePatch patches[HD2_BOOT_PATCHES];HD2FramePatch frames[2];
    need(hd2env_plan_boot_patches(f.image,BOOT_IMAGE_SIZE,(uintptr_t)f.image,&nearby,patches),"boot plan");
    need(hd2env_plan_frame_patches(f.image,BOOT_IMAGE_SIZE,&f.life.frames,frames),"frame plan");
    for(unsigned i=0;i<HD2_BOOT_PATCHES;i++)memcpy(f.image+patches[i].rva,patches[i].replacement,patches[i].size);
    for(unsigned i=0;i<2;i++)memcpy(f.image+frames[i].rva,frames[i].replacement,frames[i].size);
    thunk(f.image+0x2df8c0,(uintptr_t)api_setup);thunk(f.image+0x147f3f0,(uintptr_t)native_compare);
    thunk(f.image+0x7faeb0,(uintptr_t)before_update);thunk(f.image+0x61850,(uintptr_t)after_update);
    strcpy((char *)f.image+0x1730ba8,"boot_script");
    for(unsigned i=0;i<sizeof(code_pages)/sizeof(*code_pages);i++)protect(f.image+code_pages[i],4096,1);
    f.allocator[6]=(uintptr_t)native_allocate;f.allocator[8]=(uintptr_t)native_free;
    putptr(f.game+0x88,(uintptr_t)f.allocator);putptr(f.game+0x188,(uintptr_t)f.app);
    putptr(f.app+0x280,(uintptr_t)f.platform);putptr(f.app+0x2a0,(uintptr_t)f.binary_config);putptr(f.app+0x338,(uintptr_t)f.network);
    putptr(f.app+0x5d0,0x21);putptr(f.app+0x3f8,0x22);putptr(f.app+0x320,0x23);putptr(f.app+0x410,0x24);
    putptr(f.network+0x1138,0x25);f.platform[0x15d]=1;
    putptr(f.image+0x28605a8,steam_test_service(f.steam));putptr(f.image+0x28605a0,0x16);putptr(f.image+0x28605b8,0x17);
    putptr(f.image+0x28605b0,friends_test_service(f.friends));putptr(f.image+0x2860598,0x19);
    put32(f.binary_config,6);put32(f.binary_config+4,8);put32(f.binary_config+8,2);
    put32(f.binary_config+12,64);put32(f.binary_config+20,128);strcpy((char *)f.binary_config+64,"unrelated");
    put32(f.binary_config+24,80);put32(f.binary_config+32,128);strcpy((char *)f.binary_config+80,mode("boot-fail-missing")?"absent":"boot_script");
    strcpy((char *)f.binary_config+128,mode("boot-fail-init")?"poc/init_fail":mode("boot-fail-require")?"poc/absent":"stock/boot");
    put32(f.options,14);putptr(f.options+0x10,(uintptr_t)f.object);put32(f.object,9);putptr(f.object+8,(uintptr_t)f.rows);
    row(&f,0,"boot_enabled",9,0,0,0);row(&f,1,"boot_false",1,0,0,0);
    row(&f,2,"boot_number",2,16777217.0,0,0);row(&f,3,"boot_deleted",1,0,1,1);
    row(&f,4,"boot_ignored",4,0,1,0);row(&f,5,"",1,0,1,0);
    row(&f,6,"boot_enabled",1,0,7,0);row(&f,7,"",1,0,0,0);put32(f.rows+7*0x38,0);
    uint64_t nanbits=UINT64_C(0x7ff8000000000000);double nan;memcpy(&nan,&nanbits,8);row(&f,8,"boot_nan",2,nan,0,0);
    if(mode("boot-fail-limit"))put32(f.object,1048577);
    f.plugin[11]=(uintptr_t)plugin_setup;f.plugin[19]=(uintptr_t)render_plugin;
    f.plugin_rows[1]=(uintptr_t)f.plugin;f.plugin_rows[5]=(uintptr_t)f.plugin;
    putptr(f.image+0x19b0d68,(uintptr_t)f.plugin_rows);put32(f.image+0x1a741c8,2);
    putptr(f.image+0x1ab6d70,(uintptr_t)f.plugin);f.image[0x1ab6d88]=1;
    for(f.cycle=0;f.cycle<2;f.cycle++){
        ((Create)f.life.construct)(f.native,f.app);need(f.e&&!hd2env_boot_complete(f.e),"fresh boot state");
        uint64_t faults=hd2env_frame_fault_count();((Entry)f.life.frames.render)(f.native);
        need(hd2env_frame_fault_count()==faults+1,"frame before boot allowed");
        if(mode("boot-fail-order"))((Create)f.targets.start)(f.native,f.binary_config+128);
        ((Boot)(f.image+0x6cdd70))(f.game,NULL,f.options);
        if(f.cycle){const char *empty="assert(boot_enabled==nil and boot_number==nil)";lua_ok(hd2env_eval(f.e,empty,strlen(empty),"@empty-options"));}
        need(hd2env_boot_complete(f.e)&&f.registered==8&&f.allocation_count==3&&f.freed==1&&f.api_setup==1,"boot completion/native work");
        need(pointer(f.native)==0&&pointer(f.native+0x100148)==0,"old PUC state accessed/created");
        need(pointer(f.image+0x1ab77f8)==(uintptr_t)f.native&&pointer(f.image+0x1ab77e0)==(uintptr_t)(f.game+0x88)&&
             pointer(f.image+0x1ab7808)==(uintptr_t)f.app&&f.image[0x1bbad81]==1,"native context stores lost");
        need(pointer(f.game+0x100308)==(uintptr_t)(f.image+0x6ce710)&&pointer(f.game+0x100310)==(uintptr_t)f.game,"native reporter bookkeeping lost");
        need(f.plugins==(f.cycle?0:3)&&f.render_plugins==(f.cycle?0:1),"plugin initialization lost");
        if(!f.cycle)need(pointer(f.image+0x1ab6d80)==0x1234&&f.image[0x1ab6d89]==1,"render plugin result lost");
#ifndef HD2ENV_PUC_REFERENCE
        if(!f.cycle)lua_ok(hd2env_require(f.e,"poc/bootstrap_scenarios.lua"));
#endif
        unsigned ticks=f.cycle?1:4000;
        /* The optional plugin's frame callback fields are null in this fixture. */
        f.image[0x1ab6d88]=0;putptr(f.image+0x28605a8,0);
        for(unsigned i=0;i<ticks;i++){
#ifndef HD2ENV_PUC_REFERENCE
            if(!f.cycle)lua_ok(hd2env_call(f.e,"poc_bootstrap_before_frame",0,0));
#endif
            ((Tick)(f.image+0x6ce580))(f.game,1.0f/60);((Entry)(f.image+0x6ce690))(f.game);
        }
#ifndef HD2ENV_PUC_REFERENCE
        if(!f.cycle){lua_ok(hd2env_call(f.e,"poc_trace_report",0,0));lua_ok(hd2env_call(f.e,"poc_bootstrap_finish",0,0));}
        else
#endif
        lua_ok(hd2env_call(f.e,"shutdown",0,0));
        ((Entry)f.life.close)(f.native);need(!f.e&&!*out&&!hd2env_native_state_count(),"close after boot");
        for(unsigned i=0;i<3;i++)free(f.allocations[i]);
        f.allocation_count=f.freed=f.api_setup=f.registered=f.plugins=f.render_plugins=0;
        put32(f.options,0);put32(f.image+0x1a741c8,0);putptr(f.image+0x28605a8,steam_test_service(f.steam));
    }
    need(f.closed==2&&f.collections==4001&&hd2env_clear_native_factory(),"boot lifecycle counts/teardown");
    protect(f.image+0x6cd000,8192,0);
    for(unsigned i=0;i<HD2_BOOT_PATCHES;i++){
        need(!memcmp(f.image+patches[i].rva,patches[i].replacement,patches[i].size),"boot patch changed");
        memcpy(f.image+patches[i].rva,patches[i].original,patches[i].size);
    }
    for(unsigned i=0;i<2;i++)memcpy(f.image+frames[i].rva,frames[i].original,frames[i].size);
    need(hd2env_plan_boot_patches(f.image,BOOT_IMAGE_SIZE,(uintptr_t)f.image,&nearby,patches),"boot restoration");
    friends_test_free(f.friends);steam_test_free(f.steam);dispose(f.game,BOOT_GAME_SIZE);dispose(f.image,BOOT_IMAGE_SIZE);current=NULL;
    puts("POC_BOOT native_setup=pass registrations=pass steam=pass friends=pass config=pass plugins=pass stock=pass guards=pass rollback=pass states=2 frames=4001");
}
