/* Actual replacement callbacks vs captured original callback bodies. Native
 * service and PUC helper functions are isolated fixtures; no Steam requests. */
#define _GNU_SOURCE
#include "steam_test_fixture.h"
#include "steam_witnesses.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#endif
enum { STEAM_IMAGE_SIZE=0x29fe000 };
typedef struct { union { double number;uintptr_t pointer;int boolean; } value;int type,padding; } RefValue;
typedef struct {
    unsigned char state[0x100],global[0x100];RefValue values[32];
    unsigned char strings[32][512];unsigned used;
} RefState;
typedef struct {uintptr_t vtable;struct SteamTestFixture *owner;int second;} Service;
typedef struct {unsigned method,calls;uint64_t id;uint32_t app;int null_url;char url[128];} Event;
struct SteamTestFixture {
    unsigned char *image;int owned,refuse_write,refuse_call,refuse_service;
    HD2SteamHost host;uintptr_t vtable[23];Service services[2];Event event;
    unsigned char connected,client,overlay,installed,owns,event_present;
    int32_t app,event_app;uint64_t id;
    char language[128],name[128];int null_name;
    unsigned cases;
};
static void need(int ok,const char *message){if(!ok){fprintf(stderr,"STEAM ERROR: %s\n",message);exit(15);}}
static void putptr(void *p,uintptr_t n){memcpy(p,&n,8);}
static void put32(void *p,uint32_t n){memcpy(p,&n,4);}
static uintptr_t pointer(const void *p){uintptr_t n;memcpy(&n,p,8);return n;}
static void thunk(unsigned char *p,uintptr_t target){p[0]=0x48;p[1]=0xb8;putptr(p+2,target);p[10]=0xff;p[11]=0xe0;}
static void executable(void *p,size_t size){
#ifdef _WIN32
    DWORD old;need(VirtualProtect(p,size,PAGE_EXECUTE_READ,&old),"VirtualProtect reference code");need(FlushInstructionCache(GetCurrentProcess(),p,size),"FlushInstructionCache");
#else
    need(!mprotect(p,size,PROT_READ|PROT_EXEC),"mprotect reference code");__builtin___clear_cache(p,(char *)p+size);
#endif
}
static void writable(void *p,size_t size){
    uintptr_t start=(uintptr_t)p&~(uintptr_t)4095;
    size_t length=(((uintptr_t)p+size+4095)&~(uintptr_t)4095)-start;
#ifdef _WIN32
    DWORD old;need(VirtualProtect((void *)start,length,PAGE_READWRITE,&old),"VirtualProtect fixture data");
#else
    need(!mprotect((void *)start,length,PROT_READ|PROT_WRITE),"mprotect fixture data");
#endif
}
static int contains(uintptr_t start,size_t capacity,uintptr_t at,size_t size){return at>=start&&at-start<=capacity&&size<=capacity-(at-start);}
static int read_memory(void *context,uintptr_t at,void *out,size_t size){
    SteamTestFixture *f=context;
    if(f->refuse_service&&contains((uintptr_t)f->services,sizeof(f->services),at,size))return 0;
    if(!contains((uintptr_t)f->image,STEAM_IMAGE_SIZE,at,size)&&!contains((uintptr_t)f,sizeof(*f),at,size))return 0;
    memcpy(out,(void *)at,size);return 1;
}
static int write_memory(void *context,uintptr_t at,const void *in,size_t size){
    SteamTestFixture *f=context;if(f->refuse_write||at!=(uintptr_t)f->image+0x2860608||size!=8)return 0;
    memcpy((void *)at,in,size);return 1;
}
static int callable(void *context,uintptr_t at){
    SteamTestFixture *f=context;if(f->refuse_call)return 0;
    for(size_t i=0;i<23;i++)if(at&&f->vtable[i]==at)return 1;
    return 0;
}
static SteamTestFixture *called(void *self,unsigned method){
    Service *service=self;SteamTestFixture *f=service->owner;
    need(self==f->services||self==f->services+1,"native this pointer");f->event.method=method;f->event.calls++;return f;
}
static unsigned char HD2_NATIVE_ABI connected(void *s){return called(s,0x38)->connected;}
static unsigned char HD2_NATIVE_ABI client(void *s){return called(s,0x40)->client;}
static unsigned char HD2_NATIVE_ABI overlay(void *s){return called(s,0x48)->overlay;}
static uint64_t HD2_NATIVE_ABI user(void *s){SteamTestFixture *f=called(s,0x18);return f->id+((Service *)s)->second;}
static uintptr_t HD2_NATIVE_ABI user_name(void *s,uint64_t id){SteamTestFixture *f=called(s,0x28);f->event.id=id;return f->null_name?0:(uintptr_t)f->name;}
static uintptr_t HD2_NATIVE_ABI language(void *s){return (uintptr_t)called(s,0x50)->language;}
static unsigned char HD2_NATIVE_ABI installed(void *s,uint32_t app){SteamTestFixture *f=called(s,0x70);f->event.app=app;return f->installed;}
static unsigned char HD2_NATIVE_ABI owns(void *s,uint32_t app){SteamTestFixture *f=called(s,0x98);f->event.app=app;return f->owns;}
static unsigned char HD2_NATIVE_ABI install_event(void *s,int32_t *app){SteamTestFixture *f=called(s,0xa0);*app=f->event_app;return f->event_present;}
static int32_t HD2_NATIVE_ABI app_id(void *s){return called(s,0xa8)->app;}
static void HD2_NATIVE_ABI open_url(void *s,const char *url){SteamTestFixture *f=called(s,0xb0);f->event.null_url=!url;if(url)snprintf(f->event.url,sizeof(f->event.url),"%s",url);}
SteamTestFixture *steam_test_create(void *image,size_t size){
    SteamTestFixture *f=calloc(1,sizeof(*f));need(f!=NULL,"fixture allocation");
    if(image){need(size>=STEAM_IMAGE_SIZE,"fixture image size");f->image=image;}
    else {
#ifdef _WIN32
        f->image=VirtualAlloc(NULL,STEAM_IMAGE_SIZE,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);need(f->image!=NULL,"VirtualAlloc");
#else
        f->image=mmap(NULL,STEAM_IMAGE_SIZE,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);need(f->image!=MAP_FAILED,"mmap");
#endif
        f->owned=1;
    }
    unsigned char *b=f->image;
    writable(b,0x1200);
    for(size_t i=0;i<sizeof(steam_regions)/sizeof(*steam_regions);i++)writable(b+steam_regions[i].rva,steam_regions[i].size);
    writable(b+0x16faa60,40*8);
    for(size_t i=0;i<20;i++)for(size_t k=0;k<2;k++)writable(b+steam_language_rvas[i][k],strlen(steam_languages[i][k])+1);
    writable(b+0x1717d70,8);writable(b+0x1709320,5);writable(b+0x173b3e0,64);
    b[0]='M';b[1]='Z';put32(b+0x3c,0x80);memcpy(b+0x80,"PE\0\0",4);
    b[0x84]=0x64;b[0x85]=0x86;put32(b+0x88,0x6ad78c0d);b[0x98]=0x0b;b[0x99]=2;put32(b+0x98+56,STEAM_IMAGE_SIZE);
    for(size_t i=0;i<sizeof(steam_regions)/sizeof(*steam_regions);i++)memcpy(b+steam_regions[i].rva,steam_regions[i].bytes,steam_regions[i].size);
    for(size_t i=0;i<20;i++)for(size_t k=0;k<2;k++){
        putptr(b+0x16faa60+i*16+k*8,(uintptr_t)b+steam_language_rvas[i][k]);
        strcpy((char *)b+steam_language_rvas[i][k],steam_languages[i][k]);
    }
    strcpy((char *)b+0x1717d70,"%016llx");strcpy((char *)b+0x1709320,"%llx");
    strcpy((char *)b+0x173b3e0,"Failed to find language code for: `%s`");
    f->host=(HD2SteamHost){f,(uintptr_t)b,read_memory,write_memory,callable};
    f->vtable[3]=(uintptr_t)user;f->vtable[5]=(uintptr_t)user_name;f->vtable[7]=(uintptr_t)connected;
    f->vtable[8]=(uintptr_t)client;f->vtable[9]=(uintptr_t)overlay;f->vtable[10]=(uintptr_t)language;
    f->vtable[14]=(uintptr_t)installed;f->vtable[19]=(uintptr_t)owns;f->vtable[20]=(uintptr_t)install_event;
    f->vtable[21]=(uintptr_t)app_id;f->vtable[22]=(uintptr_t)open_url;
    for(int i=0;i<2;i++)f->services[i]=(Service){(uintptr_t)f->vtable,f,i};
    f->connected=7;f->overlay=1;f->installed=3;f->owns=1;f->event_present=1;f->event_app=-1;f->app=553850;
    f->id=UINT64_C(0xfedcba9876543210);strcpy(f->language,"English");strcpy(f->name,"Fixture user");return f;
}
uintptr_t steam_test_service(SteamTestFixture *f){return (uintptr_t)f->services;}
int steam_test_register(SteamTestFixture *f,HD2Environment *e,uintptr_t service){return hd2env_register_steam(e,&f->host,service);}
void steam_test_free(SteamTestFixture *f){
    if(f->owned){
#ifdef _WIN32
        need(VirtualFree(f->image,0,MEM_RELEASE),"VirtualFree");
#else
        need(!munmap(f->image,STEAM_IMAGE_SIZE),"munmap");
#endif
    }
    free(f);
}
/* The oracle's minimal PUC storage is owned, never passed to LuaJIT. Helpers
 * implement only the operations used here. Original machine-code bodies do
 * argument-count branching, conversion selection, vtable dispatch and results. */
static RefValue *ref_top(RefState *s){return (RefValue *)pointer(s->state+0x10);}
static void ref_next(RefState *s){putptr(s->state+0x10,(uintptr_t)(ref_top(s)+1));}
static uintptr_t ref_string(RefState *s,const char *bytes,size_t n){
    need(s->used<32&&n<512-24,"reference string capacity");unsigned char *v=s->strings[s->used++];memcpy(v+24,bytes,n);v[24+n]=0;return (uintptr_t)v;
}
static RefValue *HD2_NATIVE_ABI ref_index(RefState *s,int index){
    static RefValue nil;need(index==1,"reference index");return s->values<ref_top(s)?s->values:&nil;
}
static void HD2_NATIVE_ABI ref_push(RefState *s,const char *text,size_t n){RefValue *v=ref_top(s);v->type=4;v->value.pointer=ref_string(s,text,n);ref_next(s);}
static uintptr_t HD2_NATIVE_ABI ref_intern(RefState *s,const char *text,size_t n){return ref_string(s,text,n);}
static int HD2_NATIVE_ABI ref_tostring(RefState *s,RefValue *v){
    if(v->type!=3)return 0;
    char b[64];int n=snprintf(b,sizeof(b),"%.14g",v->value.number);v->type=4;v->value.pointer=ref_string(s,b,(size_t)n);return 1;
}
static int HD2_NATIVE_ABI ref_number(const char *text,double *out){char *end;*out=strtod(text,&end);while(*end==' ')end++;return end!=text&&!*end;}
static int HD2_NATIVE_ABI ref_scan(const char *text,const char *format,uint64_t *out){
    need(text&&!strcmp(format,"%llx"),"reference ID scan");char *end;*out=strtoull(text,&end,16);return end!=text;
}
static int HD2_NATIVE_ABI ref_format(char *text,const char *format,uint64_t value){need(!strcmp(format,"%016llx"),"reference ID format");return sprintf(text,"%016llx",(unsigned long long)value);}
static char *HD2_NATIVE_ABI ref_copy(char *out,const char *in,size_t n){return strncpy(out,in,n);}
static int HD2_NATIVE_ABI ref_lower(int c){return c>='A'&&c<='Z'?c+'a'-'A':c;}
static void HD2_NATIVE_ABI ref_warning(const char *format,const char *language_name){(void)format;(void)language_name;}
static void prepare_reference(SteamTestFixture *f){
    const struct {uint32_t rva;uintptr_t target;} helpers[]={
        {0x7965e0,(uintptr_t)ref_index},{0x797170,(uintptr_t)ref_push},{0x79c8c0,(uintptr_t)ref_tostring},
        {0x79b900,(uintptr_t)ref_number},{0x7a1810,(uintptr_t)ref_intern},{0x3a0b20,(uintptr_t)ref_scan},
        {0x704f0,(uintptr_t)ref_format},{0x147f0c0,(uintptr_t)ref_copy},{0x1343ba0,(uintptr_t)ref_lower},
        {0x600a50,(uintptr_t)ref_warning}};
    for(size_t i=0;i<sizeof(helpers)/sizeof(*helpers);i++)thunk(f->image+helpers[i].rva,helpers[i].target);
    const uint32_t pages[]={0x7f4000,0x7f5000,0x796000,0x797000,0x79c000,0x79b000,0x7a1000,0x3a0000,0x70000,0x147f000,0x1343000,0x600000};
    for(size_t i=0;i<sizeof(pages)/sizeof(*pages);i++)executable(f->image+pages[i],4096);
}
static HD2Value str(const char *s){return (HD2Value){.type=HD2_VALUE_STRING,.as.string={s,strlen(s)}};}
static HD2Value num(double n){return (HD2Value){.type=HD2_VALUE_NUMBER,.as.number=n};}
static void differential(SteamTestFixture *f,HD2Environment *e,const char *name,uintptr_t rva,const HD2Value *args,size_t count){
    RefState s={0};putptr(s.state+0x10,(uintptr_t)(s.values+count));putptr(s.state+0x18,(uintptr_t)s.values);
    putptr(s.state+0x20,(uintptr_t)s.global);putptr(s.global+0x70,1);
    for(size_t i=0;i<count;i++){
        switch(args[i].type){
        case HD2_VALUE_NIL:s.values[i].type=0;break;
        case HD2_VALUE_BOOLEAN:s.values[i].type=1;s.values[i].value.boolean=args[i].as.boolean;break;
        case HD2_VALUE_NUMBER:s.values[i].type=3;s.values[i].value.number=args[i].as.number;break;
        case HD2_VALUE_STRING:s.values[i].type=4;s.values[i].value.pointer=ref_string(&s,args[i].as.string.bytes,args[i].as.string.size);break;
        default:need(0,"unsupported reference argument");
        }
    }
    memset(&f->event,0,sizeof(f->event));
    int n=((int(HD2_NATIVE_ABI *)(RefState *))(f->image+rva))(&s);
    need(n>=0&&n<2&&ref_top(&s)==s.values+count+n,"reference stack result");Event expected=f->event;
    memset(&f->event,0,sizeof(f->event));HD2Results actual={0};char function[64];snprintf(function,sizeof(function),"steam_%s",name);
    need(hd2env_invoke(e,function,args,count,&actual),hd2env_error(e));
    need(actual.count==(size_t)n&&!memcmp(&expected,&f->event,sizeof(expected)),"native arguments/result count diverged");
    for(int i=0;i<n;i++){
        RefValue *v=s.values+count+i;HD2Value *a=actual.values+i;
        if(v->type==0)need(a->type==HD2_VALUE_NIL,"nil result");
        else if(v->type==1)need(a->type==HD2_VALUE_BOOLEAN&&a->as.boolean==v->value.boolean,"boolean result");
        else if(v->type==3)need(a->type==HD2_VALUE_NUMBER&&a->as.number==v->value.number,"number result");
        else if(v->type==4){const char *b=(const char *)v->value.pointer+24;need(a->type==HD2_VALUE_STRING&&a->as.string.size==strlen(b)&&!memcmp(a->as.string.bytes,b,strlen(b)),"string result");}
        else need(0,"unknown reference result");
    }
    hd2env_results_free(&actual);need(!hd2env_stack_depth(e),"replacement stack imbalance");f->cases++;
}
static void eval(HD2Environment *e,const char *text){need(hd2env_eval(e,text,strlen(text),"@steam-test"),hd2env_error(e));}
void check_steam_bindings(const HD2Asset *assets,size_t count,const HD2Backend *backend){
    SteamTestFixture *f=steam_test_create(NULL,0);char error[2048];
    HD2Environment *e=hd2env_create(assets,count,backend,error,sizeof(error));need(e!=NULL,error);
    HD2SteamHost current,saved;memset(&current,0xa5,sizeof(current));saved=current;
    need(!hd2env_current_steam_host(&current)&&!memcmp(&current,&saved,sizeof(current)),"standalone current EXE accepted");
    need(hd2env_probe_steam_host(&f->host),"complete host probe");unsigned mutations=0;
    for(size_t r=0;r<sizeof(steam_regions)/sizeof(*steam_regions);r++)for(size_t i=0;i<steam_regions[r].size;i++){
        unsigned char *p=f->image+steam_regions[r].rva+i;*p^=1;
        need(!hd2env_probe_steam_host(&f->host),"changed function accepted");*p^=1;mutations++;
    }
    f->image[0x16faa60]^=1;need(!hd2env_probe_steam_host(&f->host),"changed language pointer accepted");f->image[0x16faa60]^=1;
    f->image[steam_language_rvas[0][0]]^=1;need(!hd2env_probe_steam_host(&f->host),"changed language bytes accepted");f->image[steam_language_rvas[0][0]]^=1;
    f->image[0x88]^=1;need(!steam_test_register(f,e,steam_test_service(f))&&!pointer(f->image+0x2860608),"unverified registration wrote context");f->image[0x88]^=1;
    need(steam_test_register(f,e,0),"null service registration");eval(e,"assert(stingray.Steam==nil and debug.getregistry().Steam==nil)");
    f->refuse_write=1;need(!steam_test_register(f,e,steam_test_service(f))&&!pointer(f->image+0x2860608),"refused context write continued");f->refuse_write=0;
    need(steam_test_register(f,e,steam_test_service(f)),hd2env_error(e));
    eval(e,"assert(stingray.Steam==debug.getregistry().Steam);assert(stingray.Steam.__index==stingray.Steam and stingray.Steam._name=='Steam');"
           "for k,v in pairs(stingray.Steam) do if type(v)=='function' then _G['steam_'..k]=v end end;steam_saved=stingray.Steam;steam_saved.kept=true");
    need(steam_test_register(f,e,steam_test_service(f)),"repeat registration");eval(e,"assert(steam_saved==stingray.Steam and steam_saved.kept)");
    prepare_reference(f);
    differential(f,e,"connected",0x7f4650,NULL,0);differential(f,e,"client_running",0x7f4690,NULL,0);differential(f,e,"overlay_active",0x7f46d0,NULL,0);
    differential(f,e,"user_id",0x7f4710,NULL,0);f->id=7;differential(f,e,"user_id",0x7f4710,NULL,0);
    differential(f,e,"user_name",0x7f4770,NULL,0);
    const char *ids[]={"000000000000001f","0Xffffffffffffffff","  +0x1234 tail","-1","0000"};
    for(size_t i=0;i<sizeof(ids)/sizeof(*ids);i++){HD2Value a=str(ids[i]);differential(f,e,"user_name",0x7f4770,&a,1);}
    HD2Value a=num(123);differential(f,e,"user_name",0x7f4770,&a,1);f->null_name=1;differential(f,e,"user_name",0x7f4770,NULL,0);f->null_name=0;
    for(size_t i=0;i<20;i++){
        strcpy(f->language,steam_languages[i][0]);for(char *p=f->language;*p;p++)if(*p>='a'&&*p<='z')*p-='a'-'A';
        differential(f,e,"language",0x7f4850,NULL,0);
    }
    strcpy(f->language,"unknown language beyond limit");differential(f,e,"language",0x7f4850,NULL,0);
    strcpy(f->language,"abcdefghijklmnopqr\xe2\x82\xac");differential(f,e,"language",0x7f4850,NULL,0);
    const double numbers[]={553850,4294967295.0,4294967297.0,-1,-1.9,553850.75,9223372036854775808.0,-9223372036854775808.0};
    for(size_t i=0;i<sizeof(numbers)/sizeof(*numbers);i++){
        a=num(numbers[i]);differential(f,e,"is_installed",0x7f49b0,&a,1);differential(f,e,"owns_app",0x7f4a50,&a,1);
    }
    uint64_t specials[]={UINT64_C(0x7ff8000000000000),UINT64_C(0x7ff0000000000000),UINT64_C(0xfff0000000000000)};
    for(size_t i=0;i<3;i++){double n;memcpy(&n,specials+i,8);a=num(n);differential(f,e,"is_installed",0x7f49b0,&a,1);}
    a=str("553850.75");differential(f,e,"owns_app",0x7f4a50,&a,1);a=str("not-a-number");differential(f,e,"owns_app",0x7f4a50,&a,1);
    a=(HD2Value){.type=HD2_VALUE_BOOLEAN,.as.boolean=1};differential(f,e,"is_installed",0x7f49b0,&a,1);
    differential(f,e,"owns_app",0x7f4a50,NULL,0);
    differential(f,e,"install_event",0x7f4af0,NULL,0);f->event_present=0;differential(f,e,"install_event",0x7f4af0,NULL,0);
    differential(f,e,"app_id",0x7f4b60,NULL,0);f->app=-2147483647-1;differential(f,e,"app_id",0x7f4b60,NULL,0);
    a=str("https://example.invalid/fixture");differential(f,e,"open_url",0x7f4ba0,&a,1);a=num(123);differential(f,e,"open_url",0x7f4ba0,&a,1);
    a=(HD2Value){.type=HD2_VALUE_NIL};differential(f,e,"open_url",0x7f4ba0,&a,1);
    eval(e,"assert(not pcall(steam_user_name,'not-an-id'));assert(not pcall(steam_user_name,false))");
    f->refuse_call=1;eval(e,"local ok,err=pcall(steam_connected);assert(not ok and err:find('not callable'))");f->refuse_call=0;
    f->refuse_service=1;eval(e,"local ok,err=pcall(steam_connected);assert(not ok and err:find('read refused'))");f->refuse_service=0;
    need(steam_test_register(f,e,0),"unavailable service");eval(e,"assert(stingray.Steam==steam_saved);assert(not pcall(steam_connected))");
    need(steam_test_register(f,e,steam_test_service(f)),"restore service");eval(e,"assert(steam_connected()==true)");
    HD2Environment *e2=hd2env_create(assets,count,backend,error,sizeof(error));need(e2!=NULL,error);
    eval(e2,"stingray=nil;s3d=nil");need(steam_test_register(f,e2,(uintptr_t)(f->services+1)),"second environment registration");
    eval(e2,"assert(stingray==s3d and stingray.Steam==debug.getregistry().Steam)");
    eval(e,"assert(steam_user_id()=='0000000000000008')");need(hd2env_destroy(e2),"second environment destruction");
    need(pointer(f->image+0x2860608)==(uintptr_t)(f->services+1),"environment destruction cleared engine-owned context");
    need(hd2env_destroy(e),"Steam environment destruction");
    printf("POC_STEAM callbacks=11 differential_cases=%u guards=%u registration=pass contexts=pass errors=pass original_helpers=fixtures live_service=false\n",f->cases,mutations);
    steam_test_free(f);
}
