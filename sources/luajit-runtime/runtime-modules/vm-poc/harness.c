/* Standalone test backend. None of these fixtures is a live engine binding. */
#include "environment.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#endif
#include "assets.h"
#include "steam_test_fixture.h"
#include "friends_test_fixture.h"
#include "voip_test_fixture.h"
#include "shutdown_test_fixture.h"
HD2Results check_native_entry(HD2Environment *);
void check_native_result_after_close(HD2Results *);
void check_objects(HD2Environment *,const HD2Asset *,size_t,const HD2Backend *);
void check_frame_routes(HD2Environment *);
void check_gc(HD2Environment *);
void check_boot_routes(const HD2Asset *,size_t,const HD2Backend *,HD2Environment **,const char *);
void check_lifecycle_routes(const HD2Asset *,size_t,const HD2Backend *,HD2Environment **,int);

typedef struct {
    unsigned build_calls,curve_calls,world_calls,loads,unloads,triggers,stops,console;
    unsigned char playing[64];
    unsigned char world_handle;
    HD2Environment *environment;
    unsigned reentrant_refused;
} Fixture;
/* The real UnitCApi callback has no opaque context argument. */
static Fixture *curve_fixture;
static const char *build(void *p){((Fixture *)p)->build_calls++;return "release";}
static void log_message(void *p,const char *s,size_t n){
    Fixture *f=p;
    if(n==11 && !memcmp(s,"POC_REENTER",11)){
        if(!hd2env_call(f->environment,"init",0,0)&&
           !hd2env_invoke(f->environment,"init",NULL,0,NULL))f->reentrant_refused++;
    }
    fwrite(s,1,n,stdout);fputc('\n',stdout);
}
static int curve(uint32_t unit,uint32_t object,uint32_t param,uint32_t index,float *out){
    Fixture *f=curve_fixture;f->curve_calls++;
    if(unit!=7||object!=UINT32_C(0xbccf91e5)||param!=UINT32_C(0x2c1c82c8))return -1;
    *out=index==0?3.5:0;return index==0;
}
static uintptr_t world(void *p,uint32_t id){Fixture *f=p;f->world_calls++;return id==42?(uintptr_t)&f->world_handle:0;}
static int enabled(void *p,uintptr_t w){return w==(uintptr_t)&((Fixture *)p)->world_handle?1:-1;}
static int bank(void *p,const char *name,int load){Fixture *f=p;if(!name||!*name)return 0;if(load)f->loads++;else f->unloads++;return 1;}
static uint32_t trigger(void *p,uintptr_t w,const char *name){
    Fixture *f=p;if(enabled(p,w)!=1||!name||!*name||f->triggers>=63)return 0;
    f->triggers++;f->playing[f->triggers]=1;return f->triggers;
}
static int stop(void *p,uintptr_t w,uint32_t id){
    Fixture *f=p;if(enabled(p,w)!=1||id>=64)return 0;
    f->stops++;f->playing[id]=0;return 1;
}
static int is_playing(void *p,uintptr_t w,uint32_t id){
    Fixture *f=p;return enabled(p,w)==1&&id<64?f->playing[id]:-1;
}
static void console_event(void *p,const char *bank,const char *event){
    Fixture *f=p;if(bank&&event)f->console++;
}
static void require_ok(HD2Environment *e,int ok){
    if(!ok){fprintf(stderr,"ENV ERROR: %s\n",hd2env_error(e));exit(2);}
    if(hd2env_stack_depth(e)!=0){fprintf(stderr,"stack imbalance\n");exit(3);}
}
typedef struct { HD2Environment *e;int refused; } ThreadCheck;
#ifdef _WIN32
static DWORD WINAPI other_thread(LPVOID pointer){
#else
static void *other_thread(void *pointer){
#endif
    ThreadCheck *test=pointer;
    HD2Object foreign_thread_object={0};
    test->refused=!hd2env_call(test->e,"init",0,0)
        && !hd2env_invoke(test->e,"init",NULL,0,NULL)
        && hd2env_object_global(test->e,"init",&foreign_thread_object)==HD2_OBJECT_FAILURE
        && !foreign_thread_object.identity && hd2env_object_count(test->e)==SIZE_MAX
        && hd2env_stack_depth(test->e)==-1 && !hd2env_destroy(test->e);
    return 0;
}
static int check_thread(HD2Environment *e){
    ThreadCheck test={e,0};
#ifdef _WIN32
    HANDLE thread=CreateThread(NULL,0,other_thread,&test,0,NULL);
    if(!thread)return 0;
    WaitForSingleObject(thread,INFINITE);CloseHandle(thread);
#else
    pthread_t thread;if(pthread_create(&thread,NULL,other_thread,&test))return 0;
    pthread_join(thread,NULL);
#endif
    return test.refused;
}
typedef struct { unsigned char framed[2048];size_t size;unsigned calls; } ResourceFixture;
static void fixture_frame(ResourceFixture *r,HD2Resource *result,const unsigned char *data,size_t size,unsigned version){
    if(size+8>sizeof(r->framed))exit(9);
    for(unsigned i=0;i<4;i++)r->framed[i]=(unsigned char)(size>>(i*8));
    r->framed[4]=(unsigned char)version;r->framed[5]=r->framed[6]=r->framed[7]=0;
    memcpy(r->framed+8,data,size);
    result->bytes=r->framed;result->size=size+8;result->framed=1;
}
static int resolve_resource(void *context,const char *name,HD2Resource *result){
    ResourceFixture *r=context;r->calls++;
    static const unsigned char override[]="return {override=true}";
    if(!strcmp(name,"core/wwise/lua/wwise_bank_reference")){
        fixture_frame(r,result,override,sizeof(override)-1,2);return 1;
    }
    if(!strcmp(name,"engine/error"))return -1;
    if(strncmp(name,"engine/",7))return 0;
    if(!strcmp(name,"engine/absent"))return 0;
    const HD2Asset *stock=NULL;
    for(size_t i=0;i<sizeof(assets)/sizeof(*assets);i++){
        if(!strcmp(assets[i].name,"core/wwise/lua/wwise_bank_reference")){stock=assets+i;break;}
    }
    if(!stock||stock->original_size+8>sizeof(r->framed))return -1;
    size_t size=stock->original_size;
    fixture_frame(r,result,stock->original_puc,size,1);
    if(!strcmp(name,"engine/mutated"))r->framed[size+7]^=1;
    if(!strcmp(name,"engine/bad-length"))r->framed[3]=127;
    if(!strcmp(name,"engine/bad-version"))r->framed[4]=99;
    return 1;
}
static void check_provider(void){
    ResourceFixture fixture={0};HD2Backend backend={0};char error[2048];
    backend.context=&fixture;backend.read_resource=resolve_resource;
    HD2Environment *e=hd2env_create(assets,sizeof(assets)/sizeof(*assets),&backend,error,sizeof(error));
    if(!e){fprintf(stderr,"provider environment: %s\n",error);exit(9);}
    const char *script=
        "assert(require('core/wwise/lua/wwise_bank_reference').override==true)\n"
        "local r=require('engine/stock');assert(r:count('absent')==0)\n"
        "assert(require('engine/stock')==r)\n"
        "for _,name in ipairs({'engine/error','engine/absent','engine/mutated','engine/bad-length','engine/bad-version','stock/boot'}) do\n"
        "assert(not pcall(require,name),'resolver accepted '..name) end\n";
    require_ok(e,hd2env_eval(e,script,strlen(script),"@provider-tests"));
    if(!hd2env_destroy(e))exit(9);
    printf("POC_PROVIDER framed_stock=pass override_precedence=pass invalid_rejected=pass\n");
}
int main(int argc,char **argv){
    check_provider();
    int jit_enabled=argc<2||strcmp(argv[1],"off");
    Fixture f={0};char error[2048];
    curve_fixture=&f;
    HD2Backend backend={&f,build,log_message,curve,world,enabled,bank,trigger,stop,is_playing,console_event,NULL};
    if(argc>1&&!strcmp(argv[1],"steam")){check_steam_bindings(assets,sizeof(assets)/sizeof(*assets),&backend);return 0;}
    if(argc>1&&!strncmp(argv[1],"shutdown",8)){check_shutdown_routes(assets,sizeof(assets)/sizeof(*assets),&backend,&f.environment,argv[1]);return 0;}
    if(argc>1&&!strcmp(argv[1],"voip-views")){check_voip_views(assets,sizeof(assets)/sizeof(*assets),&backend);return 0;}
    if(argc>1&&!strcmp(argv[1],"friends")){check_friends_bindings(assets,sizeof(assets)/sizeof(*assets),&backend);return 0;}
    if(argc>1&&!strncmp(argv[1],"boot",4)&&strcmp(argv[1],"bootstrap")){
        check_boot_routes(assets,sizeof(assets)/sizeof(*assets),&backend,&f.environment,argv[1]);return 0;
    }
    if(argc>1&&(!strcmp(argv[1],"lifecycle")||!strcmp(argv[1],"lifecycle-fail"))){
        check_lifecycle_routes(assets,sizeof(assets)/sizeof(*assets),&backend,&f.environment,!strcmp(argv[1],"lifecycle-fail"));
        return 0;
    }
    if(hd2env_bind_current_curve(&backend)||backend.animation_curve!=curve){
        fprintf(stderr,"live binding accepted a standalone test executable\n");return 8;
    }
    HD2Environment *e=hd2env_create(assets,sizeof(assets)/sizeof(*assets),&backend,error,sizeof(error));
    if(!e){fprintf(stderr,"CREATE ERROR: %s\n",error);return 1;}
    f.environment=e;
    HD2Results retained=check_native_entry(e);
    check_objects(e,assets,sizeof(assets)/sizeof(*assets),&backend);
    if(argc>1&&!strcmp(argv[1],"gc")){
        check_gc(e);if(!hd2env_destroy(e))return 18;
        check_native_result_after_close(&retained);return 0;
    }
    if(argc>1&&!strcmp(argv[1],"frames")){
        check_frame_routes(e);
        if(!hd2env_destroy(e))return 6;
        check_native_result_after_close(&retained);
        return 0;
    }
    if(argc>1&&!strcmp(argv[1],"objects")){
        if(!hd2env_destroy(e))return 6;
        check_native_result_after_close(&retained);
        return 0;
    }
    if(argc>1&&!strcmp(argv[1],"bootstrap")){
        require_ok(e,hd2env_require(e,"poc/bootstrap_scenarios.lua"));
        HD2Object frame={0},dt={0};HD2Value delta={.type=HD2_VALUE_NUMBER,.as.number=1.0/60};
        require_ok(e,hd2env_object_global(e,"poc_bootstrap_step",&frame)==1);
        require_ok(e,hd2env_object_from_value(e,&delta,&dt)==1);
        for(int i=0;i<4000;i++){
            HD2ObjectResults results={0};
            require_ok(e,hd2env_object_call(e,frame,&dt,1,&results)==1);
            require_ok(e,results.count==0&&hd2env_objects_free(e,&results)==1);
        }
        require_ok(e,hd2env_object_release(e,&frame)==1&&hd2env_object_release(e,&dt)==1);
        require_ok(e,hd2env_object_count(e)==0);
        require_ok(e,hd2env_call(e,"poc_trace_report",0,0));
        require_ok(e,hd2env_call(e,"poc_bootstrap_finish",0,0));
        if(!hd2env_destroy(e))return 6;
        check_native_result_after_close(&retained);
        return 0;
    }
#ifndef HD2ENV_PUC_REFERENCE
    require_ok(e,hd2env_set_jit(e,jit_enabled));
#else
    (void)jit_enabled;
#endif
    require_ok(e,hd2env_require(e,"poc/scenarios.lua"));
    if(f.reentrant_refused!=1||!check_thread(e)){fprintf(stderr,"ownership guards failed\n");return 7;}
    require_ok(e,hd2env_require(e,"poc/trace.lua"));
    if(hd2env_call(e,"poc_fail",0,0)||hd2env_stack_depth(e)!=0){fprintf(stderr,"error boundary failed\n");return 4;}
    if(strcmp(hd2env_error(e),"non-string Lua error")){fprintf(stderr,"wrong error preservation\n");return 5;}
    require_ok(e,hd2env_call(e,"poc_recovery",0,0));
    clock_t started=clock();
    for(int i=0;i<4000;i++)require_ok(e,hd2env_call(e,"poc_step",1,1.0/60));
    double elapsed=(double)(clock()-started)/CLOCKS_PER_SEC;
    require_ok(e,hd2env_call(e,"poc_trace_report",0,0));
    require_ok(e,hd2env_call(e,"poc_finish",0,0));
    if(!hd2env_destroy(e))return 6;
    check_native_result_after_close(&retained);
    printf("POC_NATIVE build=%u curve=%u world=%u bank_load=%u bank_unload=%u trigger=%u stop=%u console=%u\n",
           f.build_calls,f.curve_calls,f.world_calls,f.loads,f.unloads,f.triggers,f.stops,f.console);
    printf("POC_TIME cpu_seconds=%.6f frames=4000\n",elapsed);
    printf("POC_OWNERSHIP reentrant_refused=%u cross_thread_refused=1\n",f.reentrant_refused);
    return 0;
}
