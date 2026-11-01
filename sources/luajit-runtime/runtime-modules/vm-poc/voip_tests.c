/* Original captured Lua callbacks and four original selection helpers execute
 * unchanged. PUC/CRT/allocation and the unavailable native hash lookup are
 * fixtures; this does not validate voice lifecycle, update or live services. */
#define _GNU_SOURCE
#include "voip_test_fixture.h"
#include "voip_witnesses.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#endif
enum { IMAGE_SIZE=0x29fe000, SLOTS=40 };
typedef struct {union {double number;uintptr_t pointer;int boolean;} value;int type,padding;} Value;
typedef struct {
    unsigned char state[0x100],global[0x100];Value stack[128],table[64];size_t length;
    unsigned char strings[128][128];unsigned used;unsigned char userdata[0x30];
} State;
typedef struct {
    unsigned char *image;HD2VoipHost host;unsigned char managers[2][0xa0],rooms[3][0x30],client[0x80];
    uintptr_t room_ptrs[3],client_ptr;unsigned char room_rows[SLOTS][0x28],client_rows[SLOTS][0x40];
    unsigned cases,allocations,lookup_calls;uint64_t lookup_id;int refuse_write,refuse_read,refuse_call,refuse_lookup;
} Fixture;
static Fixture *active;
static void need(int ok,const char *why){if(!ok){fprintf(stderr,"VOIP ERROR: %s\n",why);exit(17);}}
static void putptr(void *p,uintptr_t n){memcpy(p,&n,8);}
static void put32(void *p,uint32_t n){memcpy(p,&n,4);}
static uintptr_t pointer(const void *p){uintptr_t n;memcpy(&n,p,8);return n;}
static uint32_t u32(const void *p){uint32_t n;memcpy(&n,p,4);return n;}
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
static int read_memory(void *ctx,uintptr_t at,void *out,size_t size){
    Fixture *f=ctx;if(f->refuse_read&&contains((uintptr_t)f,sizeof(*f),at,size))return 0;
    if(!contains((uintptr_t)f->image,IMAGE_SIZE,at,size)&&!contains((uintptr_t)f,sizeof(*f),at,size))return 0;
    memcpy(out,(void *)at,size);return 1;
}
static int write_memory(void *ctx,uintptr_t at,const void *in,size_t size){
    Fixture *f=ctx;if(f->refuse_write||at!=(uintptr_t)f->image+0x28605f8||size!=8)return 0;
    memcpy((void *)at,in,size);return 1;
}
static int callable(void *ctx,uintptr_t at){
    Fixture *f=ctx;if(f->refuse_call)return 0;
    if(at==(uintptr_t)f->image+0x7d3bb0)return !f->refuse_lookup;
    const uint32_t rvas[]={0x7d1d60,0x7d1dd0,0x7d1e50,0x7d1ec0};
    for(size_t i=0;i<4;i++)if(at==(uintptr_t)f->image+rvas[i])return 1;
    return 0;
}
static Value *top(State *s){return (Value *)pointer(s->state+0x10);}
static void advance(State *s){putptr(s->state+0x10,(uintptr_t)(top(s)+1));}
static uintptr_t string(State *s,const char *text,size_t n){
    need(s->used<128&&n<104,"oracle string capacity");unsigned char *p=s->strings[s->used++];memcpy(p+24,text,n);p[24+n]=0;return (uintptr_t)p;
}
static Value *HD2_NATIVE_ABI ref_index(State *s,int index){
    static Value nil;Value *v=index<0?top(s)+index:s->stack+index-1;return v>=s->stack&&v<top(s)?v:&nil;
}
static void HD2_NATIVE_ABI ref_push(State *s,const char *text,size_t n){Value *v=top(s);v->type=4;v->value.pointer=string(s,text,n);advance(s);}
static uintptr_t HD2_NATIVE_ABI ref_intern(State *s,const char *text,size_t n){return string(s,text,n);}
static int HD2_NATIVE_ABI ref_tostring(State *s,Value *v){
    if(v->type!=3)return 0;
    char text[64];int n=snprintf(text,sizeof(text),"%.14g",v->value.number);v->type=4;v->value.pointer=string(s,text,(size_t)n);return 1;
}
static int HD2_NATIVE_ABI ref_scan(const char *text,const char *format,uint64_t *out){
    need(text&&!strcmp(format,"%llx"),"oracle scan input");char *end;*out=strtoull(text,&end,16);return end!=text;
}
static int HD2_NATIVE_ABI ref_format(char *out,const char *format,uint64_t id){
    need(!strcmp(format,"%016llx"),"oracle format");return sprintf(out,"%016llx",(unsigned long long)id);
}
static uintptr_t HD2_NATIVE_ABI ref_table(State *s,int array,int hash){(void)array;(void)hash;return (uintptr_t)s->table;}
static void HD2_NATIVE_ABI ref_rawseti(State *s,int index,int key){
    Value *t=ref_index(s,index);need(t->type==5&&t->value.pointer==(uintptr_t)s->table&&key>0&&key<=64,"oracle table index");
    s->table[key-1]=top(s)[-1];if(s->length<(size_t)key)s->length=(size_t)key;putptr(s->state+0x10,(uintptr_t)(top(s)-1));
}
static void *HD2_NATIVE_ABI ref_alloc(void *self,void **out,uint32_t size,uint32_t alignment){
    (void)self;need(size&&alignment==8,"oracle array allocation");*out=calloc(1,size);need(*out!=NULL,"oracle allocation failed");active->allocations++;return out;
}
static void HD2_NATIVE_ABI ref_free(void *self,void *data,uint32_t unused){
    (void)self;(void)unused;if(data){need(active->allocations>0,"oracle allocation balance");active->allocations--;free(data);}
}
static void HD2_NATIVE_ABI ref_clear(void *array,uint32_t count){need(!count,"oracle clear count");put32(array,0);}
static void *HD2_NATIVE_ABI ref_copy(void *out,const void *in,size_t n){return memmove(out,in,n);}
static uint32_t HD2_NATIVE_ABI ref_lookup(const unsigned char *map,const uint64_t *id){
    need(map==active->client+0x40,"native hash lookup map");active->lookup_calls++;active->lookup_id=*id;
    uint32_t count=u32(map);const unsigned char *rows=(void *)pointer(map+8);
    for(uint32_t i=0;i<count;i++)if((int32_t)u32(rows+i*0x40+0x38)>=0&&pointer(rows+i*0x40)==*id)return i;
    return 0x7fffffff;
}
static void prepare_reference(Fixture *f){
    const struct {uint32_t rva;uintptr_t fn;} helpers[]={
        {0x7965e0,(uintptr_t)ref_index},{0x797170,(uintptr_t)ref_push},{0x79c8c0,(uintptr_t)ref_tostring},
        {0x7a1810,(uintptr_t)ref_intern},{0x3a0b20,(uintptr_t)ref_scan},{0x704f0,(uintptr_t)ref_format},
        {0x79af20,(uintptr_t)ref_table},{0x7977a0,(uintptr_t)ref_rawseti},{0x11bda0,(uintptr_t)ref_clear},
        {0x12ee160,(uintptr_t)ref_copy},{0x7d3bb0,(uintptr_t)ref_lookup}};
    for(size_t i=0;i<sizeof(helpers)/sizeof(*helpers);i++){
        protect(f->image+helpers[i].rva,12,0);thunk(f->image+helpers[i].rva,helpers[i].fn);protect(f->image+helpers[i].rva,12,1);
    }
    putptr(f->image+0x17001d0+0x30,(uintptr_t)ref_alloc);putptr(f->image+0x17001d0+0x40,(uintptr_t)ref_free);
    strcpy((char *)f->image+0x1717d70,"%016llx");strcpy((char *)f->image+0x1709320,"%llx");
    protect(f->image+0x7f2000,0x3000,1);protect(f->image+0x7d1000,0x1000,1);
}
static HD2Value str(const char *s){return (HD2Value){.type=HD2_VALUE_STRING,.as.string={s,strlen(s)}};}
static HD2Value num(double n){return (HD2Value){.type=HD2_VALUE_NUMBER,.as.number=n};}
static HD2Value ptr(void *p){return (HD2Value){.type=HD2_VALUE_POINTER,.as.pointer=(uintptr_t)p};}
static void eval(HD2Environment *e,const char *s){need(hd2env_eval(e,s,strlen(s),"@voip-views-test"),hd2env_error(e));}
static uintptr_t full_client(void *context,uint32_t id){(void)context;(void)id;return (uintptr_t)active->client;}
static void reset_rows(Fixture *f,unsigned count,unsigned pattern){
    memset(f->room_rows,0,sizeof(f->room_rows));memset(f->client_rows,0,sizeof(f->client_rows));
    for(unsigned i=0;i<count;i++){
        uint64_t id=UINT64_C(0xfedcba0000000000)+i;
        putptr(f->room_rows[i],id);putptr(f->client_rows[i],id);
        uint32_t tag=pattern==1?UINT32_MAX:pattern==2?(i%3==1?UINT32_MAX:0):i;
        put32(f->room_rows[i]+0x20,tag);put32(f->client_rows[i]+0x38,tag);
        f->room_rows[i][0x1c]=pattern==3?1:(unsigned char)(i%2);
        f->client_rows[i][0x34]=0x44;f->client_rows[i][0x35]=0x55;
    }
    put32(f->rooms[1]+0x18,count);put32(f->client+0x40,count);
}
static void differential(Fixture *f,HD2Environment *e,const char *name,uintptr_t rva,const HD2Value *args,size_t count,int full){
    State *s=calloc(1,sizeof(*s));need(s!=NULL,"oracle state allocation");
    putptr(s->state+0x10,(uintptr_t)(s->stack+count));putptr(s->state+0x18,(uintptr_t)s->stack);
    putptr(s->state+0x20,(uintptr_t)s->global);putptr(s->global+0x70,1);
    for(size_t i=0;i<count;i++)switch(args[i].type){
    case HD2_VALUE_NIL:break;
    case HD2_VALUE_BOOLEAN:s->stack[i].type=1;s->stack[i].value.boolean=args[i].as.boolean;break;
    case HD2_VALUE_POINTER:s->stack[i].type=2;s->stack[i].value.pointer=args[i].as.pointer;break;
    case HD2_VALUE_NUMBER:s->stack[i].type=3;s->stack[i].value.number=args[i].as.number;break;
    case HD2_VALUE_STRING:s->stack[i].type=4;s->stack[i].value.pointer=string(s,args[i].as.string.bytes,args[i].as.string.size);break;
    }
    if(full){s->stack[0].type=7;s->stack[0].value.pointer=(uintptr_t)s->userdata;putptr(s->userdata+0x28,f->client_ptr);}
    unsigned char before[sizeof(f->client_rows)],after[sizeof(f->client_rows)];memcpy(before,f->client_rows,sizeof(before));
    f->lookup_calls=0;f->lookup_id=0;
    int n=((int(HD2_NATIVE_ABI *)(State *))(f->image+rva))(s);
    need(n>=0&&n<=1&&top(s)==s->stack+count+n,"oracle results and stack balance");need(!f->allocations,"oracle temporary memory leak");
    unsigned lookups=f->lookup_calls;uint64_t id=f->lookup_id;memcpy(after,f->client_rows,sizeof(after));memcpy(f->client_rows,before,sizeof(before));
    Value flat[65]={0};Value *values=s->stack+count;
    if(n==1&&values->type==5){flat[0].type=3;flat[0].value.number=(double)s->length;memcpy(flat+1,s->table,s->length*sizeof(Value));values=flat;n=(int)s->length+1;}
    HD2Results result={0};char fn[80];snprintf(fn,sizeof(fn),"voip_%s%s",full?"full_":"",name);f->lookup_calls=0;f->lookup_id=0;
    need(hd2env_invoke(e,fn,args,count,&result),hd2env_error(e));
    if(result.count!=(size_t)n){fprintf(stderr,"callback %s: original results %d, replacement %zu\n",name,n,result.count);need(0,"result arity");}
    need(!memcmp(after,f->client_rows,sizeof(after))&&lookups==f->lookup_calls&&id==f->lookup_id,"native selection writes or lookup arguments");
    for(int i=0;i<n;i++){
        const HD2Value *a=result.values+i;Value *v=values+i;
        if(v->type==1)need(a->type==HD2_VALUE_BOOLEAN&&a->as.boolean==v->value.boolean,"boolean result");
        else if(v->type==3)need(a->type==HD2_VALUE_NUMBER&&a->as.number==v->value.number,"number result");
        else if(v->type==4){const char *text=(char *)v->value.pointer+24;need(a->type==HD2_VALUE_STRING&&a->as.string.size==strlen(text)&&!memcmp(a->as.string.bytes,text,strlen(text)),"string result");}
        else need(0,"unsupported result");
    }
    hd2env_results_free(&result);free(s);need(!hd2env_stack_depth(e),"replacement stack leak");f->cases++;
}
void check_voip_views(const HD2Asset *assets,size_t count,const HD2Backend *backend){
    Fixture *f=calloc(1,sizeof(*f));need(f!=NULL,"fixture allocation");active=f;
#ifdef _WIN32
    f->image=VirtualAlloc(NULL,IMAGE_SIZE,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE);need(f->image!=NULL,"image allocation");
#else
    f->image=mmap(NULL,IMAGE_SIZE,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);need(f->image!=MAP_FAILED,"image allocation");
#endif
    unsigned char *b=f->image;b[0]='M';b[1]='Z';put32(b+0x3c,0x80);memcpy(b+0x80,"PE\0\0",4);
    b[0x84]=0x64;b[0x85]=0x86;put32(b+0x88,0x6ad78c0d);b[0x98]=0x0b;b[0x99]=2;put32(b+0x98+56,IMAGE_SIZE);
    for(size_t i=0;i<sizeof(voip_regions)/sizeof(*voip_regions);i++)memcpy(b+voip_regions[i].rva,voip_regions[i].bytes,voip_regions[i].size);
    f->host=(HD2VoipHost){f,(uintptr_t)b,read_memory,write_memory,callable};
    for(int i=0;i<3;i++){f->room_ptrs[i]=(uintptr_t)f->rooms[i];putptr(f->rooms[i]+0x10,(uintptr_t)i+0x122);putptr(f->rooms[i]+0x20,(uintptr_t)f->room_rows);}
    put32(f->managers[0]+0x88,3);putptr(f->managers[0]+0x90,(uintptr_t)f->room_ptrs);
    f->client_ptr=(uintptr_t)f->client;putptr(f->client+0x38,UINT64_C(0xfedcba9876543210));putptr(f->client+0x48,(uintptr_t)f->client_rows);
    char error[2048];HD2Backend local=*backend;local.wwise_world=full_client;
    HD2Environment *e=hd2env_create(assets,count,&local,error,sizeof(error));need(e!=NULL,error);
    need(hd2env_probe_voip_views_host(&f->host),"valid host probe");unsigned mutations=0;
    for(size_t r=0;r<sizeof(voip_regions)/sizeof(*voip_regions);r++)for(size_t i=0;i<voip_regions[r].size;i++){
        unsigned char *p=b+voip_regions[r].rva+i;*p^=1;need(!hd2env_probe_voip_views_host(&f->host),"changed code accepted");*p^=1;mutations++;
    }
    b[0x88]^=1;need(!hd2env_register_voip_views(e,&f->host,(uintptr_t)f->managers[0])&&!pointer(b+0x28605f8),"invalid image wrote manager");b[0x88]^=1;
    f->refuse_write=1;need(!hd2env_register_voip_views(e,&f->host,0),"refused context write accepted");f->refuse_write=0;
    need(hd2env_register_voip_views(e,&f->host,0),"null manager registration");
    eval(e,"assert(stingray.SteamVoip==nil);for _,n in ipairs({'SteamVoipRoom','SteamVoipClient'}) do local t=stingray[n];assert(t==debug.getregistry()[n] and t.__index==t and t._name==n and t.__gc==nil) end;assert(stingray.SteamVoipRoom.add_member==nil and stingray.SteamVoipRoom.remove_member==nil)");
    need(hd2env_register_voip_views(e,&f->host,(uintptr_t)f->managers[0]),hd2env_error(e));
    eval(e,"local C,R=stingray.SteamVoipClient,stingray.SteamVoipRoom;local function flat(f,...) local t=f(...);if t==nil then return end;return #t,unpack(t) end;"
        "voip_room_members=function(...) return flat(R.members,...) end;voip_broken_members=function(...) return flat(R.broken_members,...) end;"
        "voip_client_members=function(...) return flat(C.members,...) end;"
        "for _,k in ipairs({'room_id','select_out','select_in','broken_host'}) do _G['voip_'..k]=C[k] end;"
        "voip_saved=C;voip_room_saved=R;C.kept=true;"
        "voip_full=stingray.Wwise.wwise_world(1);for _,k in ipairs({'room_id','select_out','select_in','broken_host','client_members'}) do local f=_G['voip_'..k];_G['voip_full_'..k]=function(_,...) return f(voip_full,...) end end");
    need(hd2env_register_voip_views(e,&f->host,(uintptr_t)f->managers[0]),"repeat registration");eval(e,"assert(voip_saved==stingray.SteamVoipClient and voip_room_saved==stingray.SteamVoipRoom and voip_saved.kept)");
    prepare_reference(f);
    HD2Value room=str("123"),client=ptr(&f->client_ptr);
    const unsigned counts[]={0,1,3,9,40};
    for(unsigned p=0;p<4;p++)for(unsigned j=0;j<5;j++){
        reset_rows(f,counts[j],p);differential(f,e,"room_members",0x7f25b0,&room,1,0);differential(f,e,"broken_members",0x7f2e80,&room,1,0);
        differential(f,e,"client_members",0x7f34e0,&client,1,0);differential(f,e,"client_members",0x7f34e0,&client,1,1);
    }
    const char *rooms[]={"  +0x123 tail","00000123"};for(unsigned j=0;j<2;j++){HD2Value a=str(rooms[j]);differential(f,e,"room_members",0x7f25b0,&a,1,0);}
    HD2Value numeric=num(123);differential(f,e,"room_members",0x7f25b0,&numeric,1,0);
    for(int full=0;full<2;full++){
        differential(f,e,"room_id",0x7f3460,&client,1,full);
        const unsigned char flags[]={0,1,255};for(unsigned j=0;j<3;j++){f->client[0x78]=flags[j];differential(f,e,"broken_host",0x7f3c90,&client,1,full);}
        HD2Value truth[]={ {.type=HD2_VALUE_NIL},{.type=HD2_VALUE_BOOLEAN,.as.boolean=0},{.type=HD2_VALUE_BOOLEAN,.as.boolean=1},num(0),str("") };
        for(unsigned j=0;j<5;j++)for(unsigned direction=0;direction<2;direction++){
            reset_rows(f,9,2);HD2Value a[]={client,truth[j],str("fedcba0000000002")};const char *name=direction?"select_in":"select_out";uintptr_t rva=direction?0x7f3b80:0x7f3a70;
            differential(f,e,name,rva,a,2,full);differential(f,e,name,rva,a,3,full);
            a[2]=str("fedcba0000000001");differential(f,e,name,rva,a,3,full);a[2]=str("ffff");differential(f,e,name,rva,a,3,full);
        }
        differential(f,e,"select_out",0x7f3a70,&client,1,full);differential(f,e,"select_in",0x7f3b80,&client,1,full);
    }
    eval(e,"assert(not pcall(voip_room_members,'999'));assert(not pcall(voip_room_members,'not-an-id'));assert(not pcall(voip_room_members,false));"
        "assert(not pcall(voip_room_id,{}));assert(not pcall(voip_room_id,newproxy(true)));assert(not pcall(voip_select_out,voip_full,true,nil))");
    f->client_ptr=0;need(!hd2env_invoke(e,"voip_room_id",&client,1,NULL),"null native client accepted");f->client_ptr=(uintptr_t)f->client;
    put32(f->managers[0]+0x88,1048577);eval(e,"assert(not pcall(voip_room_members,'123'))");put32(f->managers[0]+0x88,3);
    f->refuse_read=1;eval(e,"assert(not pcall(voip_room_id,voip_full))");f->refuse_read=0;
    f->refuse_call=1;eval(e,"assert(not pcall(voip_select_out,voip_full,true))");f->refuse_call=0;
    f->refuse_lookup=1;eval(e,"assert(not pcall(voip_select_out,voip_full,true,'123'))");f->refuse_lookup=0;
    put32(f->client+0x40,1048577);eval(e,"assert(not pcall(stingray.SteamVoipClient.members,voip_full))");put32(f->client+0x40,1);
    putptr(f->client+0x48,UINTPTR_MAX-8);eval(e,"assert(not pcall(stingray.SteamVoipClient.members,voip_full))");putptr(f->client+0x48,(uintptr_t)f->client_rows);
    need(hd2env_register_voip_views(e,&f->host,0),"null manager repeated registration");eval(e,"assert(stingray.SteamVoipClient==voip_saved and not pcall(voip_room_members,'123'))");
    need(hd2env_register_voip_views(e,&f->host,(uintptr_t)f->managers[0]),"restore first manager");
    eval(e,"assert(voip_room_members('123')>0)");
    HD2Environment *e2=hd2env_create(assets,count,&local,error,sizeof(error));need(e2!=NULL,error);eval(e2,"stingray=nil;s3d=nil");
    need(hd2env_register_voip_views(e2,&f->host,(uintptr_t)f->managers[1]),"second shared manager");eval(e2,"assert(stingray==s3d and stingray.SteamVoipRoom==debug.getregistry().SteamVoipRoom)");
    eval(e,"assert(not pcall(voip_room_members,'123'))");need(hd2env_destroy(e2),"second state close");
    need(pointer(b+0x28605f8)==(uintptr_t)f->managers[1],"destructor cleared native slot");need(hd2env_destroy(e),"state close");
    printf("POC_VOIP_VIEWS callbacks=7 differential_cases=%u guards=%u queries=pass selection=pass userdata=pass contexts=pass errors=pass hash_lookup=fixture complete_registrar=false live_service=false\n",f->cases,mutations);
#ifdef _WIN32
    need(VirtualFree(b,0,MEM_RELEASE),"image free");
#else
    need(!munmap(b,IMAGE_SIZE),"image free");
#endif
    free(f);active=NULL;
}
