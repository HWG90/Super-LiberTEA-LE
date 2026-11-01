#include "native_resources.h"
#include "resource_witness.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#ifdef _WIN32
#include <windows.h>
struct HD2EngineResources {
    HD2SteamHost host;
    uintptr_t environment,state,manager;
    DWORD owner;
    unsigned char *bytes;
    size_t capacity;
    unsigned calls,found;
    int busy;
    char error[160];
};
static int read_at(HD2EngineResources *r,uintptr_t p,void *out,size_t size) {
    return p&&size<=UINTPTR_MAX-p&&r->host.read(r->host.context,p,out,size)==1;
}
static int failure(HD2EngineResources *r,const char *message){snprintf(r->error,sizeof(r->error),"%s",message);return 0;}
static const uint64_t lua_type_id=UINT64_C(0xa14e8dfa2cd117e2);
static int verify(HD2EngineResources *r) {
    if(r->owner!=GetCurrentThreadId())return failure(r,"Resource reader thread mismatch");
    uintptr_t state=0,second=0,manager=0;
    if(!read_at(r,r->environment,&state,8)||!read_at(r,r->environment+0x100148,&second,8)||
       !read_at(r,r->environment+0x110,&manager,8)||state!=r->state||second!=state||manager!=r->manager)
        return failure(r,"Native environment ownership changed");
    unsigned char code[sizeof(resource_witness)];uintptr_t fn=r->host.image_base+0x6321a0;
    if(r->host.callable(r->host.context,fn)!=1||!read_at(r,fn,code,sizeof(code))||memcmp(code,resource_witness,sizeof(code)))
        return failure(r,"Native resource resolver witness differs");
    /* The resolver dereferences its type row even for a missing name. */
    uint32_t count=0;uintptr_t types=0;
    if(!read_at(r,manager+0x2c0,&count,4)||!read_at(r,manager+0x2c8,&types,8)||!count||count>1024)
        return failure(r,"Resource type table unavailable");
    for(uint32_t i=0;i<count;i++){
        uint64_t type=0;
        if(!read_at(r,types+(uintptr_t)i*80,&type,8))return failure(r,"Resource type row unreadable");
        if(type==lua_type_id)return 1;
    }
    return failure(r,"Lua resource type absent");
}
static uint64_t name_id(const unsigned char *s,size_t length) {
    const uint64_t m=UINT64_C(0xc6a4a7935bd1e995);uint64_t h=(uint64_t)length*m;
    while(length>=8){
        uint64_t k=0;for(unsigned i=0;i<8;i++)k|=(uint64_t)s[i]<<(i*8);
        k*=m;k^=k>>47;k*=m;h=(h^k)*m;s+=8;length-=8;
    }
    if(length){uint64_t k=0;for(size_t i=0;i<length;i++)k|=(uint64_t)s[i]<<(i*8);h=(h^k)*m;}
    h^=h>>47;h*=m;h^=h>>47;return h;
}
static int resolve(void *context,const char *name,HD2Resource *out) {
    HD2EngineResources *r=context;
    if(!r||!name||!out||r->busy||!verify(r))return -1;
    size_t length=strlen(name);
    if(!length||length>4096){failure(r,"Resource name length refused");return -1;}
    r->busy=1;r->error[0]=0;r->calls++;
    uint64_t requested=name_id((const unsigned char *)name,length),resolved=0;
    typedef const unsigned char *(*Resolver)(void *,const uint64_t *,const uint64_t *,uint64_t *);
    const unsigned char *resource=((Resolver)(r->host.image_base+0x6321a0))((void *)r->manager,&lua_type_id,&requested,&resolved);
    int status=-1;uint32_t header[2];
    if(!resource){status=0;goto done;}
    if(!read_at(r,(uintptr_t)resource,header,sizeof(header))||!header[0]||header[0]>16*1024*1024||(header[1]!=1&&header[1]!=2)){
        failure(r,"Mounted resource frame refused");goto done;
    }
    size_t size=(size_t)header[0]+8;
    if(r->capacity<size){
        unsigned char *next=realloc(r->bytes,size);
        if(!next){failure(r,"Resource copy allocation failed");goto done;}
        r->bytes=next;r->capacity=size;
    }
    if(!read_at(r,(uintptr_t)resource,r->bytes,size)){failure(r,"Mounted resource copy failed");goto done;}
    out->bytes=r->bytes;out->size=size;out->framed=1;r->found++;status=1;
done:
    r->busy=0;return status;
}
HD2EngineResources *hd2resources_open(const HD2SteamHost *h,uintptr_t environment) {
    if(!h||!h->read||!h->callable||!environment||environment>UINTPTR_MAX-0x100150)return NULL;
    HD2EngineResources *r=calloc(1,sizeof(*r));if(!r)return NULL;
    r->host=*h;r->environment=environment;r->owner=GetCurrentThreadId();
    if(!read_at(r,environment,&r->state,8)||!r->state||!read_at(r,environment+0x110,&r->manager,8)||!r->manager||!verify(r)){free(r);return NULL;}
    return r;
}
int hd2resources_bind(HD2EngineResources *r,HD2Backend *b) {
    if(!r||!b||b->context||b->read_resource||!verify(r))return 0;
    b->context=r;b->read_resource=resolve;return 1;
}
const char *hd2resources_error(const HD2EngineResources *r){return r?r->error:"no resource reader";}
unsigned hd2resources_found(const HD2EngineResources *r){return r?r->found:0;}
#else
HD2EngineResources *hd2resources_open(const HD2SteamHost *h,uintptr_t environment){(void)h;(void)environment;return NULL;}
int hd2resources_bind(HD2EngineResources *r,HD2Backend *b){(void)r;(void)b;return 0;}
const char *hd2resources_error(const HD2EngineResources *r){(void)r;return "engine resources require the Windows game";}
unsigned hd2resources_found(const HD2EngineResources *r){(void)r;return 0;}
#endif
