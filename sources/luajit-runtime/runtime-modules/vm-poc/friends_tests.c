/* Captured original Lua callback bodies compared with replacement callbacks.
 * Native helper bodies, Steam interfaces and PUC/CRT support are fixtures. */
#define _GNU_SOURCE
#include "friends_test_fixture.h"
#include "friends_witnesses.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#endif
enum { FRIENDS_IMAGE_SIZE=0x29fe000 };
typedef struct {union {double number;uintptr_t pointer;int boolean;} value;int type,padding;} FValue;
typedef struct {char key[32];FValue value;} Field;
typedef struct {Field fields[8];size_t count;} FTable;
typedef struct {
    unsigned char state[0x100],global[0x100];FValue values[32];
    unsigned char strings[64][512];unsigned used;FTable table;
} FState;
typedef struct {
    unsigned method,calls;uint64_t id,lobby;uint32_t index,category,address[2];
    int null_key,null_value;char key[128],value[128];
} FEvent;
struct FriendsTestFixture {
    unsigned char *image;int owned,refuse_write,refuse_call,refuse_service,reference;
    HD2FriendsHost host;uintptr_t vtable[44],interface_object,interface_pointer;
    unsigned char services[2][0x110],lobby_object[0x180];uintptr_t lobby_pointer;
    FEvent event;int32_t count,relationship,status;uint64_t id;
    unsigned char category_result,playing_result;int null_name,null_presence;
    char name[128],presence[128];_Alignas(16) unsigned char playing[48],invite[96];int32_t invite_return;
    unsigned cases;
};
static FriendsTestFixture *active;
static void need(int ok,const char *message){if(!ok){fprintf(stderr,"FRIENDS ERROR: %s\n",message);exit(16);}}
static void putptr(void *p,uintptr_t n){memcpy(p,&n,8);}
static void put32(void *p,uint32_t n){memcpy(p,&n,4);}
static uintptr_t pointer(const void *p){uintptr_t n;memcpy(&n,p,8);return n;}
static int contains(uintptr_t base,size_t length,uintptr_t at,size_t size){return at>=base&&at-base<=length&&size<=length-(at-base);}
static void protect(void *p,size_t size,int execute){
    uintptr_t begin=(uintptr_t)p&~(uintptr_t)4095;size_t n=(((uintptr_t)p+size+4095)&~(uintptr_t)4095)-begin;
#ifdef _WIN32
    DWORD old;need(VirtualProtect((void *)begin,n,execute?PAGE_EXECUTE_READ:PAGE_READWRITE,&old),"VirtualProtect");
    if(execute)need(FlushInstructionCache(GetCurrentProcess(),(void *)begin,n),"FlushInstructionCache");
#else
    need(!mprotect((void *)begin,n,execute?PROT_READ|PROT_EXEC:PROT_READ|PROT_WRITE),"mprotect");
    if(execute)__builtin___clear_cache((void *)begin,(char *)begin+n);
#endif
}
static void thunk(unsigned char *p,uintptr_t target){p[0]=0x48;p[1]=0xb8;putptr(p+2,target);p[10]=0xff;p[11]=0xe0;}
static int read_memory(void *context,uintptr_t at,void *out,size_t size){
    FriendsTestFixture *f=context;
    if(f->refuse_service&&contains((uintptr_t)f->services,sizeof(f->services),at,size))return 0;
    if(!contains((uintptr_t)f->image,FRIENDS_IMAGE_SIZE,at,size)&&!contains((uintptr_t)f,sizeof(*f),at,size))return 0;
    memcpy(out,(void *)at,size);return 1;
}
static int write_memory(void *context,uintptr_t at,const void *in,size_t size){
    FriendsTestFixture *f=context;if(f->refuse_write)return 0;
    int allowed=at==(uintptr_t)f->image+0x28605f0&&size==8;
    for(int i=0;i<2;i++)allowed|=at==(uintptr_t)f->services[i]+0xc0&&size==4;
    if(!allowed)return 0;
    memcpy((void *)at,in,size);return 1;
}
static int callable(void *context,uintptr_t at){
    FriendsTestFixture *f=context;if(f->refuse_call)return 0;
    for(size_t i=0;i<44;i++)if(at&&at==f->vtable[i])return 1;
    if(at==pointer(f->image+0x148e7b8))return 1;
    const uintptr_t helpers[]={0x7cbaf0,0x7cbfb0,0x7cc160,0x7cc470,0x7cc7d0,0x7ce4d0,0x7ce7d0};
    for(size_t i=0;i<7;i++)if(at==(uintptr_t)f->image+helpers[i])return 1;
    return 0;
}
static FriendsTestFixture *called(void *self,unsigned method){
    need(active&&self==&active->interface_object,"Steam interface this pointer");active->event.method=method;active->event.calls++;return active;
}
static uintptr_t HD2_NATIVE_ABI context_get(void *descriptor){
    need(active&&descriptor==active->image+0x19b65a0,"Steam context descriptor");return (uintptr_t)&active->interface_pointer;
}
static int32_t HD2_NATIVE_ABI num_friends(void *self,uint32_t flags){FriendsTestFixture *f=called(self,0x10);f->event.category=flags;return f->count;}
static uintptr_t HD2_NATIVE_ABI friend_id(void *self,uint64_t *out,uint32_t index,uint32_t flags){
    FriendsTestFixture *f=called(self,0x18);f->event.index=index;f->event.category=flags;*out=f->id;return (uintptr_t)out;
}
static int32_t HD2_NATIVE_ABI relationship(void *self,uint64_t id){FriendsTestFixture *f=called(self,0x20);f->event.id=id;return f->relationship;}
static int32_t HD2_NATIVE_ABI status(void *self,uint64_t id){FriendsTestFixture *f=called(self,0x28);f->event.id=id;return f->status;}
static unsigned char HD2_NATIVE_ABI category(void *self,uint64_t id,uint32_t flags){FriendsTestFixture *f=called(self,0x80);f->event.id=id;f->event.category=flags;return f->category_result;}
static void copy_text(char *out,const char *text){if(text)snprintf(out,128,"%s",text);}
static unsigned char HD2_NATIVE_ABI set_presence(void *self,const char *key,const char *value){
    FriendsTestFixture *f=called(self,0x148);f->event.null_key=!key;f->event.null_value=!value;copy_text(f->event.key,key);copy_text(f->event.value,value);return 1;
}
static uintptr_t HD2_NATIVE_ABI presence(void *self,uint64_t id,const char *key){
    FriendsTestFixture *f=called(self,0x158);f->event.id=id;f->event.null_key=!key;copy_text(f->event.key,key);return f->null_presence?0:(uintptr_t)f->presence;
}
static FriendsTestFixture *helper(unsigned method){need(active!=NULL,"native helper context");active->event.method=method;active->event.calls++;return active;}
static uintptr_t HD2_NATIVE_ABI native_name(void *unused,uint64_t id){(void)unused;FriendsTestFixture *f=helper(0x7cbaf0);f->event.id=id;return f->null_name?0:(uintptr_t)f->name;}
static unsigned char HD2_NATIVE_ABI native_playing(void *unused,uint64_t id,void *out){
    (void)unused;FriendsTestFixture *f=helper(0x7cbfb0);f->event.id=id;memcpy(out,f->playing,36);return f->playing_result;
}
static void HD2_NATIVE_ABI invite_lobby(void *unused,uint64_t id,uint64_t lobby,const char *text){
    (void)unused;FriendsTestFixture *f=helper(0x7cc160);f->event.id=id;f->event.lobby=lobby;copy_text(f->event.key,text);
}
static void HD2_NATIVE_ABI invite_server(void *unused,uint64_t id,const void *address,const char *text,const char *password){
    (void)unused;FriendsTestFixture *f=helper(0x7cc470);f->event.id=id;memcpy(f->event.address,address,8);copy_text(f->event.key,text);copy_text(f->event.value,password);
}
static void HD2_NATIVE_ABI advertise_lobby(void *unused,uint64_t lobby,const char *text){
    (void)unused;FriendsTestFixture *f=helper(0x7ce4d0);f->event.lobby=lobby;copy_text(f->event.key,text);
}
static void HD2_NATIVE_ABI advertise_server(void *unused,const void *address,const char *text,const char *password){
    (void)unused;FriendsTestFixture *f=helper(0x7ce7d0);memcpy(f->event.address,address,8);copy_text(f->event.key,text);copy_text(f->event.value,password);
}
static int32_t HD2_NATIVE_ABI next_invite(void *self,void *out){
    FriendsTestFixture *f=helper(0x7cc7d0);need(self==f->services[0]||self==f->services[1],"Friends queue this pointer");
    need(!((uintptr_t)out&15),"native invitation result alignment");memcpy(out,f->invite,96);return f->invite_return;
}
static const struct {uint32_t rva;uintptr_t function;} helper_thunks[]={
    {0x7cbaf0,(uintptr_t)native_name},{0x7cbfb0,(uintptr_t)native_playing},{0x7cc160,(uintptr_t)invite_lobby},
    {0x7cc470,(uintptr_t)invite_server},{0x7cc7d0,(uintptr_t)next_invite},{0x7ce4d0,(uintptr_t)advertise_lobby},{0x7ce7d0,(uintptr_t)advertise_server}};
static void install_helpers(FriendsTestFixture *f){
    for(size_t i=0;i<7;i++){unsigned char *p=f->image+helper_thunks[i].rva;protect(p,12,0);thunk(p,helper_thunks[i].function);protect(p,12,1);}
}
FriendsTestFixture *friends_test_create(void *image,size_t size){
    FriendsTestFixture *f=calloc(1,sizeof(*f));need(f!=NULL,"fixture allocation");active=f;
    if(image){need(size>=FRIENDS_IMAGE_SIZE,"fixture image size");f->image=image;}
    else {
#ifdef _WIN32
        f->image=VirtualAlloc(NULL,FRIENDS_IMAGE_SIZE,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);need(f->image!=NULL,"VirtualAlloc");
#else
        f->image=mmap(NULL,FRIENDS_IMAGE_SIZE,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);need(f->image!=MAP_FAILED,"mmap");
#endif
        f->owned=1;
    }
    unsigned char *b=f->image;protect(b,0x1200,0);b[0]='M';b[1]='Z';put32(b+0x3c,0x80);memcpy(b+0x80,"PE\0\0",4);
    b[0x84]=0x64;b[0x85]=0x86;put32(b+0x88,0x6ad78c0d);b[0x98]=0x0b;b[0x99]=2;put32(b+0x98+56,FRIENDS_IMAGE_SIZE);
    for(size_t i=0;i<sizeof(friends_regions)/sizeof(*friends_regions);i++){
        protect(b+friends_regions[i].rva,friends_regions[i].size,0);memcpy(b+friends_regions[i].rva,friends_regions[i].bytes,friends_regions[i].size);
    }
    const struct {uint32_t rva;const char *text;} strings[]={
        {0x1717d70,"%016llx"},{0x1709320,"%llx"},{0x172f238,"%i.%i.%i.%i"},{0x172f120,"%i.%i.%i.%i:%i"},
        {0x1704344,"app_id"},{0x173b038,"mod_id"},{0x1723cec,"lobby"},{0x173b034,"ip"},
        {0x173b028,"server_port"},{0x173b018,"query_port"},{0x1739d38,"SteamLobby"},
        {0x173b000,"0123456789abcdefABCDEF"},{0x1739760,"connect"},{0x16ed088,""}};
    for(size_t i=0;i<sizeof(strings)/sizeof(*strings);i++){protect(b+strings[i].rva,strlen(strings[i].text)+1,0);strcpy((char *)b+strings[i].rva,strings[i].text);}
    protect(b+0x148e7b8,8,0);putptr(b+0x148e7b8,(uintptr_t)context_get);
    f->host=(HD2FriendsHost){f,(uintptr_t)b,read_memory,write_memory,callable};
    f->vtable[2]=(uintptr_t)num_friends;f->vtable[3]=(uintptr_t)friend_id;f->vtable[4]=(uintptr_t)relationship;f->vtable[5]=(uintptr_t)status;
    f->vtable[16]=(uintptr_t)category;f->vtable[41]=(uintptr_t)set_presence;f->vtable[43]=(uintptr_t)presence;
    f->interface_object=(uintptr_t)f->vtable;f->interface_pointer=(uintptr_t)&f->interface_object;f->lobby_pointer=(uintptr_t)f->lobby_object;
    putptr(f->lobby_object+0x178,UINT64_C(0x1234567890abcdef));f->id=UINT64_C(0xfedcba9876543210);
    f->count=7;f->relationship=-1;f->status=6;f->category_result=9;f->playing_result=1;
    strcpy(f->name,"Fixture friend");strcpy(f->presence,"playing");return f;
}
uintptr_t friends_test_service(FriendsTestFixture *f){return (uintptr_t)f->services[0];}
int friends_test_register(FriendsTestFixture *f,HD2Environment *e,uintptr_t service){
    active=f;
    /* Temporarily restore native helper witnesses for registration, then use
     * controlled helpers in the isolated image. Original Lua callbacks stay intact. */
    for(size_t i=0;i<7;i++)for(size_t k=0;k<sizeof(friends_regions)/sizeof(*friends_regions);k++)if(friends_regions[k].rva==helper_thunks[i].rva){
        protect(f->image+friends_regions[k].rva,friends_regions[k].size,0);
        memcpy(f->image+friends_regions[k].rva,friends_regions[k].bytes,friends_regions[k].size);
    }
    int ok=hd2env_register_friends(e,&f->host,service);install_helpers(f);return ok;
}
void friends_test_free(FriendsTestFixture *f){
    if(f->owned){
#ifdef _WIN32
        need(VirtualFree(f->image,0,MEM_RELEASE),"VirtualFree");
#else
        need(!munmap(f->image,FRIENDS_IMAGE_SIZE),"munmap");
#endif
    }
    if(active==f)active=NULL;
    free(f);
}
static FValue *top(FState *s){return (FValue *)pointer(s->state+0x10);}
static void advance(FState *s){putptr(s->state+0x10,(uintptr_t)(top(s)+1));}
static uintptr_t string(FState *s,const char *text,size_t n){
    need(s->used<64&&n<488,"reference string capacity");unsigned char *p=s->strings[s->used++];memcpy(p+24,text,n);p[24+n]=0;return (uintptr_t)p;
}
static FValue *HD2_NATIVE_ABI ref_index(FState *s,int index){
    static FValue nil;FValue *p=index<0?top(s)+index:s->values+index-1;
    return p>=s->values&&p<top(s)?p:&nil;
}
static void HD2_NATIVE_ABI ref_push(FState *s,const char *text,size_t n){FValue *v=top(s);v->type=4;v->value.pointer=string(s,text,n);advance(s);}
static uintptr_t HD2_NATIVE_ABI ref_intern(FState *s,const char *text,size_t n){return string(s,text,n);}
static int HD2_NATIVE_ABI ref_tostring(FState *s,FValue *v){
    if(v->type!=3)return 0;
    char text[64];int n=snprintf(text,sizeof(text),"%.14g",v->value.number);v->type=4;v->value.pointer=string(s,text,(size_t)n);return 1;
}
static int HD2_NATIVE_ABI ref_number(const char *s,double *out){char *end;*out=strtod(s,&end);while(*end==' ')end++;return end!=s&&!*end;}
static int HD2_NATIVE_ABI ref_scan(const char *s,const char *format,void *a,void *b,void *c,void *d,void *e){
    need(s!=NULL,"reference null scan input");
    if(!strcmp(format,"%llx")){char *end;uint64_t n=strtoull(s,&end,16);if(end==s)return 0;memcpy(a,&n,8);return 1;}
    need(!strcmp(format,"%i.%i.%i.%i:%i"),"reference address scan format");return sscanf(s,format,(int *)a,(int *)b,(int *)c,(int *)d,(int *)e);
}
static int HD2_NATIVE_ABI ref_format(char *text,const char *format,uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e){
    if(!strcmp(format,"%016llx"))return sprintf(text,"%016llx",(unsigned long long)a);
    if(!strcmp(format,"%i.%i.%i.%i"))return sprintf(text,"%d.%d.%d.%d",(int)a,(int)b,(int)c,(int)d);
    need(!strcmp(format,"%i.%i.%i.%i:%i"),"reference address format");return sprintf(text,"%d.%d.%d.%d:%d",(int)a,(int)b,(int)c,(int)d,(int)e);
}
static uintptr_t HD2_NATIVE_ABI ref_table(FState *s,int a,int b){(void)a;(void)b;return (uintptr_t)&s->table;}
static void HD2_NATIVE_ABI ref_set(FState *s,FValue *table,FValue *key,FValue *value){
    need(table->type==5&&table->value.pointer==(uintptr_t)&s->table&&key->type==4,"reference table set");
    need(s->table.count<8,"reference table capacity");Field *f=s->table.fields+s->table.count++;
    snprintf(f->key,sizeof(f->key),"%s",(char *)key->value.pointer+24);f->value=*value;
}
static int HD2_NATIVE_ABI ref_metatable(FState *s,int index){
    if(ref_index(s,index)->type!=2)return 0;
    FValue *v=top(s);v->type=5;v->value.pointer=0xabcdef;advance(s);return 1;
}
static void HD2_NATIVE_ABI ref_get(FState *s,void *registry,FValue *key,FValue *out){
    (void)registry;need(key->type==4&&!strcmp((char *)key->value.pointer+24,"SteamLobby"),"reference registry metatable");
    out->type=5;out->value.pointer=0xabcdef;(void)s;
}
static int HD2_NATIVE_ABI ref_equal(FValue *a,FValue *b){return a->type==b->type&&a->value.pointer==b->value.pointer;}
static void prepare_reference(FriendsTestFixture *f){
    const struct {uint32_t rva;uintptr_t function;} helpers[]={
      {0x7965e0,(uintptr_t)ref_index},{0x797170,(uintptr_t)ref_push},{0x79c8c0,(uintptr_t)ref_tostring},{0x79b900,(uintptr_t)ref_number},
      {0x7a1810,(uintptr_t)ref_intern},{0x3a0b20,(uintptr_t)ref_scan},{0x704f0,(uintptr_t)ref_format},{0x79af20,(uintptr_t)ref_table},
      {0x79cd50,(uintptr_t)ref_set},{0x797580,(uintptr_t)ref_metatable},{0x79cb80,(uintptr_t)ref_get},{0x79b890,(uintptr_t)ref_equal}};
    for(size_t i=0;i<sizeof(helpers)/sizeof(*helpers);i++){
        protect(f->image+helpers[i].rva,12,0);thunk(f->image+helpers[i].rva,helpers[i].function);protect(f->image+helpers[i].rva,12,1);
    }
    protect(f->image+0x7ef000,0x4000,1);install_helpers(f);f->reference=1;
}
static HD2Value str(const char *s){return (HD2Value){.type=HD2_VALUE_STRING,.as.string={s,strlen(s)}};}
static HD2Value num(double n){return (HD2Value){.type=HD2_VALUE_NUMBER,.as.number=n};}
static HD2Value ptr(void *p){return (HD2Value){.type=HD2_VALUE_POINTER,.as.pointer=(uintptr_t)p};}
static void eval(HD2Environment *e,const char *s){need(hd2env_eval(e,s,strlen(s),"@friends-test"),hd2env_error(e));}
static void differential(FriendsTestFixture *f,HD2Environment *e,const char *name,uintptr_t rva,const HD2Value *args,size_t count){
    FState s={0};putptr(s.state+0x10,(uintptr_t)(s.values+count));putptr(s.state+0x18,(uintptr_t)s.values);putptr(s.state+0x20,(uintptr_t)s.global);putptr(s.global+0x70,1);
    for(size_t i=0;i<count;i++){
        switch(args[i].type){
        case HD2_VALUE_NIL:s.values[i].type=0;break;
        case HD2_VALUE_BOOLEAN:s.values[i].type=1;s.values[i].value.boolean=args[i].as.boolean;break;
        case HD2_VALUE_POINTER:s.values[i].type=2;s.values[i].value.pointer=(uintptr_t)args[i].as.pointer;break;
        case HD2_VALUE_NUMBER:s.values[i].type=3;s.values[i].value.number=args[i].as.number;break;
        case HD2_VALUE_STRING:s.values[i].type=4;s.values[i].value.pointer=string(&s,args[i].as.string.bytes,args[i].as.string.size);break;
        }
    }
    unsigned char service_before[sizeof(f->services)];memcpy(service_before,f->services,sizeof(f->services));
    memset(&f->event,0,sizeof(f->event));int n=((int(HD2_NATIVE_ABI *)(FState *))(f->image+rva))(&s);
    need(n>=0&&n<=4&&top(&s)==s.values+count+n,"reference stack results");FEvent expected=f->event;
    unsigned char service_after[sizeof(f->services)];memcpy(service_after,f->services,sizeof(f->services));memcpy(f->services,service_before,sizeof(f->services));
    FValue *values=s.values+count;FValue fields[6]={0};
    if(n==1&&values->type==5){
        const char *keys[]={"app_id","mod_id","lobby","ip","server_port","query_port"};
        for(int i=0;i<6;i++)for(size_t j=0;j<s.table.count;j++)if(!strcmp(keys[i],s.table.fields[j].key))fields[i]=s.table.fields[j].value;
        values=fields;n=6;
    }
    memset(&f->event,0,sizeof(f->event));HD2Results actual={0};char function[64];snprintf(function,sizeof(function),"friends_%s",name);
    need(hd2env_invoke(e,function,args,count,&actual),hd2env_error(e));
    if(actual.count!=(size_t)n||memcmp(&expected,&f->event,sizeof(expected))||memcmp(service_after,f->services,sizeof(f->services))){fprintf(stderr,"case %s: expected %d results, got %zu; method %x/%x\n",name,n,actual.count,expected.method,f->event.method);need(0,"native arguments/results/state diverged");}
    for(int i=0;i<n;i++){
        FValue *v=values+i;HD2Value *a=actual.values+i;
        if(v->type==0)need(a->type==HD2_VALUE_NIL,"nil result");
        else if(v->type==1)need(a->type==HD2_VALUE_BOOLEAN&&a->as.boolean==v->value.boolean,"boolean result");
        else if(v->type==3)need(a->type==HD2_VALUE_NUMBER&&a->as.number==v->value.number,"number result");
        else if(v->type==4){const char *text=(const char *)v->value.pointer+24;need(a->type==HD2_VALUE_STRING&&a->as.string.size==strlen(text)&&!memcmp(a->as.string.bytes,text,strlen(text)),"string result");}
        else need(0,"unsupported reference result");
    }
    hd2env_results_free(&actual);need(!hd2env_stack_depth(e),"replacement stack balance");f->cases++;
}
void check_friends_bindings(const HD2Asset *assets,size_t count,const HD2Backend *backend){
    FriendsTestFixture *f=friends_test_create(NULL,0);char error[2048];
    HD2Environment *e=hd2env_create(assets,count,backend,error,sizeof(error));need(e!=NULL,error);
    HD2FriendsHost current,saved;memset(&current,0xa5,sizeof(current));saved=current;
    need(!hd2env_current_friends_host(&current)&&!memcmp(&current,&saved,sizeof(current)),"standalone EXE accepted");
    need(hd2env_probe_friends_host(&f->host),"complete image probe");unsigned mutations=0;
    for(size_t r=0;r<sizeof(friends_regions)/sizeof(*friends_regions);r++)for(size_t i=0;i<friends_regions[r].size;i++){
        unsigned char *p=f->image+friends_regions[r].rva+i;*p^=1;need(!hd2env_probe_friends_host(&f->host),"changed native code accepted");*p^=1;mutations++;
    }
    f->image[0x88]^=1;need(!hd2env_register_friends(e,&f->host,friends_test_service(f))&&!pointer(f->image+0x28605f0),"unverified image wrote context");f->image[0x88]^=1;
    need(friends_test_register(f,e,0),"null registration");eval(e,"assert(stingray.Friends==nil and stingray.Presence==nil)");
    f->refuse_write=1;need(!friends_test_register(f,e,friends_test_service(f)),"refused context write");f->refuse_write=0;
    need(friends_test_register(f,e,friends_test_service(f)),hd2env_error(e));
    eval(e,"for _,n in ipairs({'Friends','Presence'}) do local t=stingray[n];assert(t==debug.getregistry()[n] and t.__index==t and t._name==n);for k,v in pairs(t) do if type(v)=='function' then _G['friends_'..k]=v end end end;friends_saved=stingray.Friends;presence_saved=stingray.Presence;friends_saved.kept=true;"
      "friends_playing_game=function(...) local t=stingray.Friends.playing_game(...);if not t then return end;return t.app_id,t.mod_id,t.lobby,t.ip,t.server_port,t.query_port end;"
      "function friends_set_lobby(p) debug.getregistry().SteamLobby={};debug.setmetatable(p,debug.getregistry().SteamLobby) end");
    for(size_t i=0;i<sizeof(friends_constants)/sizeof(*friends_constants);i++){
        char source[160];snprintf(source,sizeof(source),"assert(stingray.Friends.%s==%d)",friends_constants[i].name,friends_constants[i].value);eval(e,source);
    }
    need(friends_test_register(f,e,friends_test_service(f)),"repeat registration");eval(e,"assert(friends_saved==stingray.Friends and presence_saved==stingray.Presence and friends_saved.kept)");
    prepare_reference(f);
    differential(f,e,"num_friends",0x7ef770,NULL,0);
    const double numbers[]={1,4,-1,-1.9,4294967297.0,9223372036854775808.0,-9223372036854775808.0};
    for(size_t i=0;i<sizeof(numbers)/sizeof(*numbers);i++){HD2Value a=num(numbers[i]);differential(f,e,"num_friends",0x7ef770,&a,1);differential(f,e,"id",0x7ef840,&a,1);}
    uint64_t special[]={UINT64_C(0x7ff8000000000000),UINT64_C(0x7ff0000000000000),UINT64_C(0xfff0000000000000)};
    for(size_t i=0;i<3;i++){double n;memcpy(&n,special+i,8);HD2Value a=num(n);differential(f,e,"num_friends",0x7ef770,&a,1);differential(f,e,"id",0x7ef840,&a,1);}
    HD2Value a=str("3.9");differential(f,e,"id",0x7ef840,&a,1);a=str("bad");differential(f,e,"num_friends",0x7ef770,&a,1);
    a=(HD2Value){.type=HD2_VALUE_BOOLEAN,.as.boolean=1};differential(f,e,"id",0x7ef840,&a,1);differential(f,e,"id",0x7ef840,NULL,0);
    const char *ids[]={"fedcba9876543210","0Xffffffffffffffff","  +0x1234 tail","-1","0000"};
    for(size_t i=0;i<5;i++){
        a=str(ids[i]);differential(f,e,"name",0x7ef930,&a,1);differential(f,e,"relationship",0x7ef9f0,&a,1);differential(f,e,"status",0x7efab0,&a,1);
        HD2Value args[]={a,num(4294967297.0)};differential(f,e,"in_category",0x7efb70,args,2);
    }
    a=num(123);differential(f,e,"name",0x7ef930,&a,1);f->null_name=1;differential(f,e,"name",0x7ef930,&a,1);f->null_name=0;
    a=str("1234");f->playing_result=0;differential(f,e,"playing_game",0x7efca0,&a,1);f->playing_result=1;
    for(unsigned flags=0;flags<8;flags++){
        memset(f->playing,0,sizeof(f->playing));f->playing[0]=flags&1;f->playing[12]=flags&2;f->playing[24]=flags&4;
        put32(f->playing+4,0x80000001);put32(f->playing+8,999);putptr(f->playing+16,UINT64_C(0xfedcba9876543210));
        put32(f->playing+28,0x7f000001);put32(f->playing+32,0xffff1234);differential(f,e,"playing_game",0x7efca0,&a,1);
    }
    for(unsigned kind=0;kind<4;kind++){
        memset(f->invite,0,sizeof(f->invite));put32(f->invite,kind);putptr(f->invite+8,UINT64_C(0xabcdef1234567890));
        put32(f->invite+16,0xc0a80aff);put32(f->invite+20,0x80000001);putptr(f->invite+24,UINT64_C(0xffffffffffffffff));
        strcpy((char *)f->invite+64,"fixture invite");f->invite_return=(int32_t)kind;memcpy(f->services[0]+0xe8,f->invite,32);
        differential(f,e,"next_invite",0x7f05c0,NULL,0);differential(f,e,"boot_invite",0x7f0740,NULL,0);
    }
    const char *destinations[]={"1234abcd","127.0.0.1:27015","0300.0250.1.2:010","1.2","host:7","-1.256.0.2:-3","0x10"};
    for(size_t i=0;i<7;i++){
        HD2Value args[]={str("ff"),str(destinations[i]),str("payload"),num(42)};
        differential(f,e,"invite",0x7f0090,args,4);differential(f,e,"advertise_playing",0x7f0840,args+1,3);
        args[2]=(HD2Value){.type=HD2_VALUE_BOOLEAN,.as.boolean=1};args[3]=(HD2Value){.type=HD2_VALUE_NIL};
        differential(f,e,"invite",0x7f0090,args,4);differential(f,e,"advertise_playing",0x7f0840,args+1,3);
    }
    HD2Value lobby=ptr(&f->lobby_pointer);need(hd2env_invoke(e,"friends_set_lobby",&lobby,1,NULL),hd2env_error(e));
    HD2Value args[]={str("ff"),lobby,str("lobby data")};differential(f,e,"invite",0x7f0090,args,3);differential(f,e,"advertise_playing",0x7f0840,args+1,2);
    differential(f,e,"stop_advertise_playing",0x7f0d10,NULL,0);
    HD2Value presence_args[]={str("key"),str("value")};differential(f,e,"set_presence",0x7f0d40,presence_args,2);
    presence_args[0]=num(123);presence_args[1]=num(456);differential(f,e,"set_presence",0x7f0d40,presence_args,2);
    presence_args[0]=(HD2Value){.type=HD2_VALUE_NIL};presence_args[1]=(HD2Value){.type=HD2_VALUE_BOOLEAN};differential(f,e,"set_presence",0x7f0d40,presence_args,2);
    presence_args[0]=str("abcdef");presence_args[1]=str("status");differential(f,e,"presence",0x7f0e20,presence_args,2);
    f->presence[0]=0;differential(f,e,"presence",0x7f0e20,presence_args,2);f->null_presence=1;differential(f,e,"presence",0x7f0e20,presence_args,2);
    eval(e,"assert(not pcall(friends_name,'not-an-id'));assert(not pcall(friends_name,false));assert(not pcall(friends_invite,'ff',false));assert(not pcall(friends_advertise_playing,''))");
    f->refuse_call=1;eval(e,"assert(not pcall(friends_num_friends))");f->refuse_call=0;
    f->refuse_service=1;eval(e,"assert(not pcall(friends_boot_invite))");f->refuse_service=0;
    f->refuse_write=1;eval(e,"assert(not pcall(friends_num_friends,1))");f->refuse_write=0;
    need(friends_test_register(f,e,0),"null re-registration");eval(e,"assert(stingray.Friends==friends_saved and stingray.Presence==presence_saved);assert(not pcall(friends_boot_invite))");
    need(friends_test_register(f,e,friends_test_service(f)),"restore context");
    HD2Environment *e2=hd2env_create(assets,count,backend,error,sizeof(error));need(e2!=NULL,error);eval(e2,"stingray=nil;s3d=nil");
    put32(f->services[1]+0xe8,2);put32(f->services[1]+0xf8,0x7f000001);put32(f->services[1]+0xfc,7);
    need(friends_test_register(f,e2,(uintptr_t)f->services[1]),"second context");eval(e2,"assert(stingray==s3d and stingray.Friends==debug.getregistry().Friends)");
    eval(e,"local k,a=friends_boot_invite();assert(k==2 and a=='127.0.0.1:7')");need(hd2env_destroy(e2),"second environment destruction");
    need(pointer(f->image+0x28605f0)==(uintptr_t)f->services[1],"destruction cleared engine-owned slot");need(hd2env_destroy(e),"Friends environment destruction");
    HD2Environment *e3=hd2env_create(assets,count,backend,error,sizeof(error));need(e3!=NULL,error);
    eval(e3,"registration_order='';stingray=setmetatable({},{__newindex=function(t,k,v) "
        "registration_order=registration_order..k..';';if k=='Presence' then assert(type(t.Friends.invite)=='function' and t.Friends.FRIEND_FLAG==nil) end;rawset(t,k,v) end})");
    need(friends_test_register(f,e3,friends_test_service(f)),hd2env_error(e3));
    eval(e3,"assert(registration_order=='Friends;Presence;' and stingray.Friends.FRIEND_FLAG==4)");need(hd2env_destroy(e3),"registration observer environment destruction");
    printf("POC_FRIENDS callbacks=14 constants=28 differential_cases=%u guards=%u registration=pass order=pass contexts=pass errors=pass original_helpers=fixtures live_service=false\n",f->cases,mutations);
    friends_test_free(f);
}
