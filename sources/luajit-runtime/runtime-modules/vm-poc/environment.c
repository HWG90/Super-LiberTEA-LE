#ifndef _WIN32
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#endif
#include "environment.h"
#include "gc_policy.h"
#include "frame_routes.h"
#include "lifecycle_routes.h"
#include "boot_routes.h"
#include "shutdown_routes.h"
#include "native_steam.h"
#include "native_friends.h"
#include "native_voip.h"
#include "native_vectors.h"
#include "native_puc.h"
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#ifndef HD2ENV_PUC_REFERENCE
#include "luajit.h"
#define LUAJIT_DISABLE_GC64
#include "lj_obj.h"
_Static_assert(!LJ_GC64,"collector adapter requires the pinned FR1 runtime");
#else
#include "lstate.h"
#endif
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>
#include <stdatomic.h>
#include <math.h>
#include <time.h>
#include "load_compat.h"
#ifdef _WIN32
#include <windows.h>
typedef DWORD OwnerThread;
static OwnerThread owner_thread(void) { return GetCurrentThreadId(); }
static int same_thread(OwnerThread t) { return t == owner_thread(); }
#else
#include <pthread.h>
typedef pthread_t OwnerThread;
static OwnerThread owner_thread(void) { return pthread_self(); }
static int same_thread(OwnerThread t) { return pthread_equal(t, owner_thread()); }
#endif

typedef struct HD2ObjectStore HD2ObjectStore;
typedef struct ObjectRequest ObjectRequest;
struct HD2Environment {
    lua_State *L;
    const HD2Asset *assets;
    size_t count;
    HD2Backend backend;
    OwnerThread thread;
    int busy;
    char error[2048];
    /* Borrowed, synchronous operation arguments; never retained across calls. */
    const char *name, *source;
    size_t size;
    int operation, has_dt;
    double dt;
    const HD2Value *arguments;
    size_t argument_count;
    HD2Results *results;
    HD2ObjectStore *objects;
    ObjectRequest *object_request;
    void *frame_native;
    HD2FrameCallbacks frame_callbacks;
    HD2Environment *frame_next;
    int frame_active;
    int native_owned;
    HD2GCSettings gc_settings;
    HD2GCHistory gc_history;
    HD2GCClock gc_clock;
    HD2GCReport gc_report;
    unsigned shutdown_stage;
    HD2NativeFactory native_factory;
    HD2BootCallbacks boot_callbacks;
    int boot_bound;unsigned boot_stage;
    uintptr_t boot_data;
    HD2SteamHost steam_host,steam_pending;
    uintptr_t steam_service;int steam_ready;
    HD2FriendsHost friends_host,friends_pending;
    uintptr_t friends_service;int friends_ready;
    HD2VoipHost voip_host,voip_pending;
    uintptr_t voip_manager;int voip_ready;
    HD2VectorHost vector_host;
    uintptr_t vector_environment;int vector2_ready,vector3_ready,vector3box_ready,vector4_ready,quaternion_ready,matrix4x4_ready,boxes_ready;
    HD2PucApi puc;struct HD2PucState *puc_main,*puc_host;struct BridgeLink *bridge_link;int bridge_ready;const char *bridge_roots;
    lua_State *bridge_current; /* LuaJIT thread inside an outbound native call */
    struct HD2PucState *bridge_puc_current; /* PUC thread inside an inbound callback */
    int bridge_timed_gc;
    int *bridge_lj_release,*bridge_puc_release;size_t bridge_lj_count,bridge_lj_capacity,bridge_puc_count,bridge_puc_capacity;
    int bridge_next_lj,bridge_next_puc;HD2BridgeStats bridge_stats;
};
static char registry_key, world_cache_key, object_rollback_key;
static uint64_t string_id64(const unsigned char *,size_t);
static int object_rollback(lua_State *);

static HD2Environment *environment(lua_State *L) {
    lua_pushlightuserdata(L, &registry_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    HD2Environment *e=lua_touserdata(L,-1);
    lua_pop(L,1);
    if (!e || !same_thread(e->thread)) luaL_error(L,"LuaEnvironment thread mismatch");
    return e;
}
static const HD2Asset *asset(HD2Environment *e, const char *name) {
    for (size_t i=0;i<e->count;i++) if (!strcmp(e->assets[i].name,name)) return e->assets+i;
    uint64_t id=string_id64((const unsigned char *)name,strlen(name));
    for (size_t i=0;i<e->count;i++) if (e->assets[i].resource_id==id) return e->assets+i;
    return NULL;
}
static int compile(lua_State *L,const unsigned char *data,size_t size,const char *name,const char *mode) {
    HD2Environment *e=environment(L);
    int binary=size>0&&data[0]==0x1b;
    if(mode&&!strchr(mode,binary?'b':'t')) {
        lua_pushliteral(L,"chunk format rejected by load mode");return LUA_ERRSYNTAX;
    }
    if(size>=4&&!memcmp(data,"\x1b" "Lua",4)) {
        const HD2Asset *match=NULL;
        for(size_t i=0;i<e->count;i++){
            const HD2Asset *a=e->assets+i;
            if((a->original_puc&&size==a->original_size&&!memcmp(data,a->original_puc,size))
               ||(a->reference_puc&&size==a->reference_size&&!memcmp(data,a->reference_puc,size))){match=a;break;}
        }
        if(!match){
#ifdef HD2ENV_PUC_REFERENCE
            /* Native reference bytecode produced by string.dump needs no
             * source translation. The game-format four-byte input still does. */
            if(size>=12&&data[8]==sizeof(size_t))return luaL_loadbuffer(L,(const char *)data,size,name);
#endif
            lua_pushliteral(L,"no verified source translation for PUC bytecode");return LUA_ERRSYNTAX;
        }
#ifdef HD2ENV_PUC_REFERENCE
        data=match->reference_puc;size=match->reference_size;
#else
        /* An exact byte match selects locally recovered source, never a header
         * rewrite or a resource-name-only match that could lose mod overrides. */
        data=match->source;size=match->source_size;mode="t";
#endif
    }
#ifndef HD2ENV_PUC_REFERENCE
    else if(size>=3&&!memcmp(data,"\x1b" "LJ",3)) {
        /* Legacy LuaJIT mod bytecode (FR1) cannot load in the GC64 runtime. Its
         * exact original bytes select source verified to reproduce them; any
         * other LuaJIT bytecode goes to the loader unchanged. */
        for(size_t i=0;i<e->count;i++){
            const HD2Asset *a=e->assets+i;
            if(a->original_puc&&size==a->original_size&&!memcmp(data,a->original_puc,size)){
                data=a->source;size=a->source_size;mode="t";break;
            }
        }
    }
#endif
#ifdef HD2ENV_PUC_REFERENCE
    return luaL_loadbuffer(L,(const char *)data,size,name);
#else
    return luaL_loadbufferx(L,(const char *)data,size,name,mode);
#endif
}
static int compile_compat(lua_State *L) {
    size_t size;const char *data=luaL_checklstring(L,1,&size);
    const char *name=luaL_optstring(L,2,data),*mode=luaL_optstring(L,3,"bt");
    lua_settop(L,4);
    if(compile(L,(const unsigned char *)data,size,name,mode)){
        lua_pushnil(L);lua_insert(L,-2);return 2;
    }
    if(lua_istable(L,4)&&lua_isfunction(L,-1)){lua_pushvalue(L,4);lua_setfenv(L,-2);}
    return 1;
}
static int load_resource(lua_State *L,const char *name,int *found) {
    HD2Environment *e=environment(L);const unsigned char *data;size_t size;
    *found=0;
    if(e->backend.read_resource){
        HD2Resource r={0};int result=e->backend.read_resource(e->backend.context,name,&r);
        if(result==0)return 0;
        *found=1;
        if(result!=1||!r.bytes){lua_pushliteral(L,"engine resource resolver failed");return LUA_ERRRUN;}
        data=r.bytes;size=r.size;
        if(r.framed){
            if(size<8){lua_pushliteral(L,"truncated engine resource");return LUA_ERRSYNTAX;}
            uint32_t length=0,version=0;
            for(unsigned i=0;i<4;i++){length|=(uint32_t)data[i]<<(i*8);version|=(uint32_t)data[i+4]<<(i*8);}
            if((version!=1&&version!=2)||length>size-8){lua_pushliteral(L,"invalid engine resource frame");return LUA_ERRSYNTAX;}
            data+=8;size=length;
        }
    }else{
        const HD2Asset *a=asset(e,name);
        if(!a)return 0;
        *found=1;
        data=a->original_puc?a->original_puc:a->source;
        size=a->original_puc?a->original_size:a->source_size;
    }
    lua_pushfstring(L,"@%s",name);
    int status=compile(L,data,size,lua_tostring(L,-1),"bt");
    lua_remove(L,-2);return status;
}
static int resource_loader(lua_State *L) {
    const char *name=luaL_checkstring(L,1);
    int found;
    if(load_resource(L,name,&found))return lua_error(L);
    if(!found){lua_pushfstring(L,"\n\tno engine resource '%s'",name);return 1;}
    return 1;
}
static int resource_dofile(lua_State *L) {
    const char *name=luaL_checkstring(L,1);
    lua_settop(L,1);int found;
    if(load_resource(L,name,&found))return lua_error(L);
    if(!found)return luaL_error(L,"engine resource not found: %s",name);
    lua_call(L,0,LUA_MULTRET);
    return lua_gettop(L)-1;
}
static int resource_original(lua_State *L) {
    const HD2Asset *a=asset(environment(L),luaL_checkstring(L,1));
    if(!a||!a->original_puc){lua_pushnil(L);return 1;}
    lua_pushlstring(L,(const char *)a->original_puc,a->original_size);return 1;
}
static int resource_read(lua_State *L) {
    const HD2Asset *a=asset(environment(L),luaL_checkstring(L,1));
    if (!a) {lua_pushnil(L);return 1;}
    lua_pushlstring(L,(const char *)a->source,a->source_size);
    return 1;
}
static int engine_print(lua_State *L) {
    HD2Environment *e=environment(L);
    int n=lua_gettop(L);
    luaL_Buffer b;luaL_buffinit(L,&b);
    for (int i=1;i<=n;i++) {
        lua_getglobal(L,"tostring");lua_pushvalue(L,i);lua_call(L,1,1);
        if (!lua_isstring(L,-1)) return luaL_error(L,"tostring must return a string");
        if (i>1) luaL_addchar(&b,'\t');
        luaL_addvalue(&b);
    }
    luaL_pushresult(&b);
    size_t size;const char *s=lua_tolstring(L,-1,&size);
    if (e->backend.log) e->backend.log(e->backend.context,s,size);
    return 0;
}
static int application_build(lua_State *L) {
    HD2Environment *e=environment(L);
    if (!e->backend.build) return luaL_error(L,"Application.build backend unavailable");
    const char *name=e->backend.build(e->backend.context);
    if (!name) return luaL_error(L,"Application.build backend failed");
    lua_pushstring(L,name);return 1;
}
static int application_platform(lua_State *L) {
    /* Build 26088801 wrapper at 0x3cff90 pushes the five-byte constant at
     * 0x17026f8. This is the Windows game platform, including under Proton. */
    lua_pushliteral(L,"win32");return 1;
}
static uint32_t u32(lua_State *L,int index) {
    double n=luaL_checknumber(L,index);
    if (!(n>=0 && n<=UINT32_MAX) || n!=(double)(uint32_t)n)
        luaL_argerror(L,index,"uint32 handle required");
    return (uint32_t)n;
}
static uint64_t string_id64(const unsigned char *s,size_t length) {
    const uint64_t m=UINT64_C(0xc6a4a7935bd1e995);
    uint64_t h=(uint64_t)length*m;
    while(length>=8){
        uint64_t k=0;
        for(unsigned i=0;i<8;i++)k|=(uint64_t)s[i]<<(i*8);
        k*=m;k^=k>>47;k*=m;h=(h^k)*m;s+=8;length-=8;
    }
    if(length){
        uint64_t k=0;
        for(size_t i=0;i<length;i++)k|=(uint64_t)s[i]<<(i*8);
        h=(h^k)*m;
    }
    h^=h>>47;h*=m;h^=h>>47;return h;
}
static uint32_t name_id(lua_State *L,int index) {
    /* The verified string path. Boxed Idstring32/64 representations require
     * separate adapters and are deliberately rejected by this first port. */
    luaL_checktype(L,index,LUA_TSTRING);
    size_t n;const char *s=lua_tolstring(L,index,&n);
    return (uint32_t)(string_id64((const unsigned char *)s,n)>>32);
}
static int fixture_unit(lua_State *L) {
    uint32_t id=u32(L,1);
    if(id>0x3fffffff)return luaL_argerror(L,1,"unit handle outside encoded range");
    lua_pushlightuserdata(L,(void *)((uintptr_t)id<<2));return 1;
}
static uint32_t unit_ref(lua_State *L,int index) {
    if(lua_type(L,index)!=LUA_TLIGHTUSERDATA)luaL_argerror(L,index,"tagged Unit lightuserdata required");
    uintptr_t raw=(uintptr_t)lua_touserdata(L,index);
    if(raw>UINT32_MAX||(raw&3))luaL_argerror(L,index,"invalid Unit tag");
    return (uint32_t)raw>>2;
}
static int animation_curve(lua_State *L) {
    HD2Environment *e=environment(L);float value=0;
    uint32_t unit=unit_ref(L,1),object=name_id(L,2),parameter=name_id(L,3);
    uint32_t index=lua_isnoneornil(L,4)?0:u32(L,4);
    if (!e->backend.animation_curve) return luaL_error(L,"animation curve backend unavailable");
    int exists=e->backend.animation_curve(unit,object,parameter,index,&value);
    if (exists<0) return luaL_error(L,"animation curve backend failed");
    lua_pushboolean(L,exists);lua_pushnumber(L,value);return 2;
}
static uintptr_t world(lua_State *L,int index) {
    return *(uintptr_t *)luaL_checkudata(L,index,"HD2.WwiseWorld");
}
static int wwise_world(lua_State *L) {
    HD2Environment *e=environment(L);uint32_t id=u32(L,1);
    if (!e->backend.wwise_world) return luaL_error(L,"Wwise world backend unavailable");
    uintptr_t handle=e->backend.wwise_world(e->backend.context,id);
    if (!handle) return luaL_error(L,"Wwise world unavailable");
    lua_pushlightuserdata(L,&world_cache_key);lua_rawget(L,LUA_REGISTRYINDEX);
    lua_pushlightuserdata(L,(void *)handle);lua_rawget(L,-2);
    if (!lua_isnil(L,-1)) return 1;
    lua_pop(L,1);
    uintptr_t *value=lua_newuserdata(L,sizeof(*value));*value=handle;
    luaL_getmetatable(L,"HD2.WwiseWorld");lua_setmetatable(L,-2);
    lua_pushlightuserdata(L,(void *)handle);lua_pushvalue(L,-2);lua_rawset(L,-4);
    return 1;
}
static int wwise_enabled(lua_State *L) {
    HD2Environment *e=environment(L);uintptr_t w=world(L,1);
    if (!e->backend.wwise_enabled) return luaL_error(L,"Wwise enabled backend unavailable");
    int result=e->backend.wwise_enabled(e->backend.context,w);
    if (result<0) return luaL_error(L,"Wwise enabled backend failed");
    lua_pushboolean(L,result);return 1;
}
static int bank(lua_State *L) {
    HD2Environment *e=environment(L);const char *name=luaL_checkstring(L,1);
    int loading=lua_toboolean(L,lua_upvalueindex(1));
    if (!e->backend.bank || !e->backend.bank(e->backend.context,name,loading))
        return luaL_error(L,"Wwise bank backend failed: %s",name);
    return 0;
}
static int trigger(lua_State *L) {
    HD2Environment *e=environment(L);uintptr_t w=world(L,1);
    const char *name=luaL_checkstring(L,2);
    if (!e->backend.trigger_event) return luaL_error(L,"Wwise trigger backend unavailable");
    uint32_t id=e->backend.trigger_event(e->backend.context,w,name);
    if (!id) return luaL_error(L,"Wwise trigger failed");
    lua_pushnumber(L,id);return 1;
}
static int stop(lua_State *L) {
    HD2Environment *e=environment(L);uintptr_t w=world(L,1);uint32_t id=u32(L,2);
    if (!e->backend.stop_event || !e->backend.stop_event(e->backend.context,w,id))
        return luaL_error(L,"Wwise stop failed");
    return 0;
}
static int playing(lua_State *L) {
    HD2Environment *e=environment(L);uintptr_t w=world(L,1);uint32_t id=u32(L,2);
    if (!e->backend.is_playing) return luaL_error(L,"Wwise playing backend unavailable");
    int result=e->backend.is_playing(e->backend.context,w,id);
    if (result<0) return luaL_error(L,"Wwise playing backend failed");
    lua_pushboolean(L,result);return 1;
}
static int console_send(lua_State *L) {
    HD2Environment *e=environment(L);luaL_checktype(L,1,LUA_TTABLE);
    lua_getfield(L,1,"type");const char *type=luaL_checkstring(L,-1);
    if (strcmp(type,"wwise_event_finished")) return luaL_error(L,"unsupported console event: %s",type);
    lua_getfield(L,1,"bank_resource_name");const char *b=luaL_checkstring(L,-1);
    lua_getfield(L,1,"event_name");const char *n=luaL_checkstring(L,-1);
    if (!e->backend.console_event) return luaL_error(L,"console event backend unavailable");
    e->backend.console_event(e->backend.context,b,n);return 0;
}
static int unsupported(lua_State *L) {
    return luaL_error(L,"native callback not ported: %s",lua_tostring(L,lua_upvalueindex(1)));
}
static void callback(lua_State *L,const char *name,lua_CFunction function) {
    lua_pushcfunction(L,function);lua_setfield(L,-2,name);
}
static void missing(lua_State *L,const char *name) {
    lua_pushstring(L,name);lua_pushcclosure(L,unsupported,1);lua_setfield(L,-2,name);
}
static int initialize(lua_State *L) {
    HD2Environment *e=lua_touserdata(L,1);lua_settop(L,0);
    lua_pushlightuserdata(L,&registry_key);lua_pushlightuserdata(L,e);lua_rawset(L,LUA_REGISTRYINDEX);
    /* Keep the rollback closure ready before any object operation can fail.
     * PUC lua_cpcall allocates a closure per call, which cannot be relied on
     * while unwinding an allocation failure. */
    lua_pushlightuserdata(L,&object_rollback_key);lua_pushcfunction(L,object_rollback);lua_rawset(L,LUA_REGISTRYINDEX);
    luaL_openlibs(L);
    lua_pushcfunction(L,compile_compat);lua_setglobal(L,"_HD2_COMPILE");
    if(compile(L,load_compat_source,sizeof(load_compat_source)-1,"@hd2/load_compat.lua","t"))return lua_error(L);
    lua_call(L,0,0);
    lua_pushnil(L);lua_setglobal(L,"_HD2_COMPILE");
    lua_gc(L,LUA_GCSETPAUSE,200);lua_gc(L,LUA_GCSETSTEPMUL,20);
    lua_getglobal(L,"package");lua_getfield(L,-1,"loaders");
    int n=(int)lua_objlen(L,-1);
    for(int i=n;i>=2;i--){lua_rawgeti(L,-1,i);lua_rawseti(L,-2,i+1);}
    lua_pushcfunction(L,resource_loader);lua_rawseti(L,-2,2);lua_pop(L,2);
    lua_pushcfunction(L,resource_dofile);lua_setglobal(L,"dofile");
    lua_pushcfunction(L,engine_print);lua_setglobal(L,"print");
    lua_pushcfunction(L,engine_print);lua_setglobal(L,"print_warning");
    luaL_newmetatable(L,"HD2.WwiseWorld");lua_pop(L,1);
    lua_pushlightuserdata(L,&world_cache_key);lua_newtable(L);lua_rawset(L,LUA_REGISTRYINDEX);
    lua_newtable(L); /* stingray */
    lua_newtable(L);callback(L,"build",application_build);callback(L,"platform",application_platform);callback(L,"console_send",console_send);
    lua_setfield(L,-2,"Application");
    lua_newtable(L);callback(L,"animation_get_curve_value",animation_curve);
    missing(L,"animation_wanted_root_pose");missing(L,"local_position");missing(L,"local_rotation");
    missing(L,"get_data");missing(L,"has_data");missing(L,"alive");lua_setfield(L,-2,"Unit");
    lua_newtable(L);callback(L,"wwise_world",wwise_world);
    lua_pushboolean(L,1);lua_pushcclosure(L,bank,1);lua_setfield(L,-2,"load_bank");
    lua_pushboolean(L,0);lua_pushcclosure(L,bank,1);lua_setfield(L,-2,"unload_bank");
    missing(L,"has_event");lua_setfield(L,-2,"Wwise");
    lua_newtable(L);callback(L,"enabled",wwise_enabled);callback(L,"trigger_event",trigger);
    callback(L,"stop_event",stop);callback(L,"is_playing",playing);lua_setfield(L,-2,"WwiseWorld");
    /* These libraries are referenced when defining visualization functions.
     * Unsupported operations fail explicitly if called, never report success. */
    const char *tables[]={"Vector2","Vector3","Vector3Box","Vector4","Matrix4x4","Quaternion","LineObject","Color", "World", "Gui",
                          "EntityManager","DataComponent","TransformComponent","VectorField","Light","Material","Math","Window","Keyboard","Mouse"};
    for(size_t i=0;i<sizeof(tables)/sizeof(*tables);i++){lua_newtable(L);lua_setfield(L,-2,tables[i]);}
    lua_newtable(L);missing(L,"type_name");lua_setfield(L,-2,"Script");
    lua_setglobal(L,"stingray");
    lua_getglobal(L,"stingray");lua_getfield(L,-1,"Wwise");lua_setglobal(L,"Wwise");lua_pop(L,1);
    lua_newtable(L);callback(L,"read",resource_read);callback(L,"original",resource_original);callback(L,"unit",fixture_unit);
#ifdef HD2ENV_PUC_REFERENCE
    lua_pushboolean(L,1);
#else
    lua_pushboolean(L,0);
#endif
    lua_setfield(L,-2,"reference");lua_setglobal(L,"POC");
    return 0;
}
void hd2env_results_free(HD2Results *r) {
    if(!r)return;
    for(size_t i=0;i<r->count;i++)
        if(r->values[i].type==HD2_VALUE_STRING)free((void *)r->values[i].as.string.bytes);
    free(r->values);r->values=NULL;r->count=0;
}
static void push_value(lua_State *L,const HD2Value *v) {
    switch(v->type){
        case HD2_VALUE_NIL:lua_pushnil(L);break;
        case HD2_VALUE_BOOLEAN:lua_pushboolean(L,v->as.boolean);break;
        case HD2_VALUE_NUMBER:lua_pushnumber(L,v->as.number);break;
        case HD2_VALUE_STRING:lua_pushlstring(L,v->as.string.bytes?v->as.string.bytes:"",v->as.string.size);break;
        case HD2_VALUE_POINTER:lua_pushlightuserdata(L,(void *)v->as.pointer);break;
        default:luaL_error(L,"unsupported native argument type");
    }
}
static void copy_results(lua_State *L,HD2Results *out) {
    int count=lua_gettop(L);
    if(count>64)luaL_error(L,"too many native callback results");
    if(!count)return;
    out->values=calloc((size_t)count,sizeof(*out->values));
    if(!out->values)luaL_error(L,"cannot allocate native callback results");
    out->count=(size_t)count;
    for(int i=0;i<count;i++){
        HD2Value *v=out->values+i;
        switch(lua_type(L,i+1)){
            case LUA_TNIL:v->type=HD2_VALUE_NIL;break;
            case LUA_TBOOLEAN:v->type=HD2_VALUE_BOOLEAN;v->as.boolean=lua_toboolean(L,i+1);break;
            case LUA_TNUMBER:v->type=HD2_VALUE_NUMBER;v->as.number=lua_tonumber(L,i+1);break;
            case LUA_TLIGHTUSERDATA:v->type=HD2_VALUE_POINTER;v->as.pointer=(uintptr_t)lua_touserdata(L,i+1);break;
            case LUA_TSTRING:{
                size_t size;const char *s=lua_tolstring(L,i+1,&size);
                if(size==SIZE_MAX)luaL_error(L,"native result string too large");
                char *copy=malloc(size+1);
                if(!copy)luaL_error(L,"cannot copy native result string");
                memcpy(copy,s,size);copy[size]=0;
                v->type=HD2_VALUE_STRING;v->as.string.bytes=copy;v->as.string.size=size;break;
            }
            default:luaL_error(L,"unsupported native result type: %s",lua_typename(L,lua_type(L,i+1)));
        }
    }
}
static int enter(HD2Environment *);
static int dispatch(HD2Environment *);
#include "gc_policy.inc"
#include "gc_runtime.inc"
#include "objects.inc"
#include "boot_config.inc"
#include "steam.inc"
#include "friends.inc"
#include "voip.inc"
#include "vector2.inc"
#include "vector3.inc"
#include "vector3box.inc"
#include "vector4.inc"
#include "quaternion.inc"
#include "matrix4x4.inc"
#include "boxes.inc"
#include "bridge.inc"
#ifndef HD2ENV_PUC_REFERENCE
#include "handoff.inc"
#endif
static int operation(lua_State *L) {
    HD2Environment *e=lua_touserdata(L,1);lua_settop(L,0);
    if(e->operation==100)return object_operation(e,L);
    if(e->operation==6)return boot_config_operation(L,e);
    if(e->operation==7)return boot_start_operation(L,e);
    if(e->operation==8)return steam_registration(L,e);
    if(e->operation==9)return friends_registration(L,e);
    if(e->operation==10)return voip_views_registration(L,e);
    if(e->operation==11){lua_gc(L,LUA_GCCOLLECT,0);return 0;}
    if(e->operation==12)return gc_operation(L,e);
    if(e->operation==13)return vector2_registration(L,e);
    if(e->operation==14)return vector3_registration(L,e);
    if(e->operation==15)return vector3box_registration(L,e);
    if(e->operation==16)return vector4_registration(L,e);
    if(e->operation==17)return quat_registration(L,e);
    if(e->operation==18)return matrix_registration(L,e);
    if(e->operation==19)return boxes_registration(L,e);
    if(e->operation==20)return bridge_registration(L,e);
    if(e->operation==21)return bridge_forwarders(L,e);
    if(e->operation==1){lua_getglobal(L,"require");lua_pushstring(L,e->name);lua_call(L,1,0);}
    else if(e->operation==2){
        lua_getglobal(L,e->name);
        if(!lua_isfunction(L,-1))return luaL_error(L,"missing global callback: %s",e->name);
        if(e->has_dt)lua_pushnumber(L,e->dt);
        lua_call(L,e->has_dt?1:0,0);
    } else if(e->operation==4){
        if(!lua_checkstack(L,(int)e->argument_count+1))return luaL_error(L,"native call stack unavailable");
        lua_getglobal(L,e->name);
        if(!lua_isfunction(L,-1))return luaL_error(L,"missing global callback: %s",e->name);
        for(size_t i=0;i<e->argument_count;i++)push_value(L,e->arguments+i);
        lua_call(L,(int)e->argument_count,e->results?LUA_MULTRET:0);
        if(e->results)copy_results(L,e->results);
    } else {
        if(compile(L,(const unsigned char *)e->source,e->size,e->name,"bt"))return lua_error(L);
        if(e->operation!=5)lua_call(L,0,0);
    }
    return 0;
}
static int capture_error(HD2Environment *e) {
    const char *s=lua_type(e->L,-1)==LUA_TSTRING?lua_tostring(e->L,-1):"non-string Lua error";
    snprintf(e->error,sizeof(e->error),"%s",s);return 0;
}
static int enter(HD2Environment *e) {
    if(!e)return 0;
    if(!same_thread(e->thread))return 0; /* no cross-thread writes to environment */
    if(e->busy){snprintf(e->error,sizeof(e->error),"reentrant host entry refused");return 0;}
    e->busy=1;e->error[0]=0;return 1;
}
static int dispatch(HD2Environment *e) {
    int top=lua_gettop(e->L);int status=lua_cpcall(e->L,operation,e);
    if(status){
        capture_error(e);
        if(e->object_request && e->objects && e->objects->head &&
           e->objects->head->identity>e->object_request->checkpoint){
            /* Existing registry entries, already-interned lightuserdata, and
             * the reserved error stack need no new closure allocation. */
            lua_pushlightuserdata(e->L,&object_rollback_key);lua_rawget(e->L,LUA_REGISTRYINDEX);
            lua_pushlightuserdata(e->L,e);
            if(lua_pcall(e->L,1,0,0)){
                e->objects->poisoned=1;
                snprintf(e->error,sizeof(e->error),"object rollback failed; destroy environment");
            }
        }
    }
    else e->error[0]=0;
    lua_settop(e->L,top);e->busy=0;e->source=e->name=NULL;
    e->arguments=NULL;e->argument_count=0;e->results=NULL;
    return status==0;
}
HD2Environment *hd2env_create(const HD2Asset *a,size_t count,const HD2Backend *b,char *error,size_t capacity) {
    if(error&&capacity)error[0]=0;
    if((count&&!a)||!b)return NULL;
    HD2Environment *e=calloc(1,sizeof(*e));
    if(e){e->assets=a;e->count=count;e->backend=*b;e->thread=owner_thread();e->L=luaL_newstate();}
    if(!e||!e->L){free(e);if(error&&capacity)snprintf(error,capacity,"cannot allocate LuaJIT state");return NULL;}
    /* Captured constructor selects these once, before native registration.
     * Later mod changes through collectgarbage must remain effective. */
    lua_gc(e->L,LUA_GCSETSTEPMUL,20);lua_gc(e->L,LUA_GCSETPAUSE,200);
    if(lua_cpcall(e->L,initialize,e)){
        capture_error(e);if(error&&capacity)snprintf(error,capacity,"%s",e->error);
        lua_close(e->L);free(e);return NULL;
    }
    e->gc_settings=hd2gc_defaults();e->gc_history=hd2gc_history();
    return e;
}
int hd2env_register_steam(HD2Environment *e,const HD2SteamHost *host,uintptr_t service){
    if(!enter(e))return 0;
    if(!hd2env_probe_steam_host(host)){
        snprintf(e->error,sizeof(e->error),"Steam native image witness or host refused");e->busy=0;return 0;
    }
    e->steam_pending=*host;e->steam_service=service;e->operation=8;
    return dispatch(e);
}
int hd2env_require(HD2Environment *e,const char *name) {
    if(!name||!enter(e))return 0;
    e->operation=1;e->name=name;return dispatch(e);
}
int hd2env_register_vector2(HD2Environment *e,const HD2VectorHost *host,uintptr_t native_environment) {
    if(!enter(e))return 0;
    /* The probe's reason names the witness and page (2026-11-04, --use-d3d11). */
    const char *why=e->vector2_ready?"already installed":
        e->frame_native&&(uintptr_t)e->frame_native!=native_environment?"another native environment owns the frames":
        !hd2env_probe_vector2_host(host)?hd2vector_probe_error():
        !hd2vector2_pool_valid(host,native_environment)?"native pool unavailable":NULL;
    if(why) {
        snprintf(e->error,sizeof(e->error),"Vector2 binding already installed, image differs or native pool unavailable: %s",why);e->busy=0;return 0;
    }
    e->vector_host=*host;e->vector_environment=native_environment;e->operation=13;return dispatch(e);
}
int hd2env_register_vector3(HD2Environment *e) {
    if(!enter(e))return 0;
    const char *why=!e->vector2_ready?"no Vector2 host":e->vector3_ready?"already installed":
        !hd2env_probe_vector3_host(&e->vector_host)?hd2vector_probe_error():NULL;
    if(why) {
        snprintf(e->error,sizeof(e->error),"Vector3 requires the Vector2 host, matching witnesses and a fresh binding: %s",why);e->busy=0;return 0;
    }
    e->operation=14;return dispatch(e);
}
int hd2env_register_vector3box(HD2Environment *e) {
    if(!enter(e))return 0;
    const char *why=!e->vector3_ready?"no Vector3":e->vector3box_ready?"already installed":
        !hd2env_probe_vector3box_host(&e->vector_host)?hd2vector_probe_error():NULL;
    if(why) {
        snprintf(e->error,sizeof(e->error),"Vector3Box requires Vector3, matching witnesses and a fresh binding: %s",why);e->busy=0;return 0;
    }
    e->operation=15;return dispatch(e);
}
int hd2env_register_vector4(HD2Environment *e) {
    if(!enter(e))return 0;
    const char *why=!e->vector3_ready?"no Vector3":e->vector4_ready?"already installed":
        !hd2env_probe_vector4_host(&e->vector_host)?hd2vector_probe_error():NULL;
    if(why) {
        snprintf(e->error,sizeof(e->error),"Vector4 requires Vector3, matching witnesses and a fresh binding: %s",why);e->busy=0;return 0;
    }
    e->operation=16;return dispatch(e);
}
int hd2env_register_quaternion(HD2Environment *e) {
    if(!enter(e))return 0;
    if(!e->vector4_ready||e->quaternion_ready||!hd2env_probe_quaternion_host(&e->vector_host)) {
        snprintf(e->error,sizeof(e->error),"Quaternion requires Vector4, matching witnesses and a fresh binding");e->busy=0;return 0;
    }
    e->operation=17;return dispatch(e);
}
int hd2env_register_matrix4x4(HD2Environment *e) {
    if(!enter(e))return 0;
    if(!e->quaternion_ready||e->matrix4x4_ready||!hd2env_probe_matrix4x4_host(&e->vector_host)) {
        snprintf(e->error,sizeof(e->error),"Matrix4x4 requires Quaternion, matching witnesses and a fresh binding");e->busy=0;return 0;
    }
    e->operation=18;return dispatch(e);
}
int hd2env_register_boxes(HD2Environment *e) {
    if(!enter(e))return 0;
    if(!e->matrix4x4_ready||e->boxes_ready||!hd2env_probe_matrix4x4_host(&e->vector_host)) {
        snprintf(e->error,sizeof(e->error),"QuaternionBox/Matrix4x4Box require Matrix4x4, matching witnesses and a fresh binding");e->busy=0;return 0;
    }
    e->operation=19;return dispatch(e);
}
int hd2env_register_friends(HD2Environment *e,const HD2FriendsHost *host,uintptr_t service){
    if(!enter(e))return 0;
    if(!hd2env_probe_friends_host(host)){
        snprintf(e->error,sizeof(e->error),"Friends native image witness or host refused");e->busy=0;return 0;
    }
    e->friends_pending=*host;e->friends_service=service;e->operation=9;return dispatch(e);
}
int hd2env_register_voip_views(HD2Environment *e,const HD2VoipHost *host,uintptr_t manager){
    if(!enter(e))return 0;
    if(!hd2env_probe_voip_views_host(host)){
        snprintf(e->error,sizeof(e->error),"SteamVoip native image witness or host refused");e->busy=0;return 0;
    }
    e->voip_pending=*host;e->voip_manager=manager;e->operation=10;return dispatch(e);
}
int hd2env_call(HD2Environment *e,const char *name,int has_dt,double dt) {
    if(!name||!enter(e))return 0;
    e->operation=2;e->name=name;e->has_dt=has_dt;e->dt=dt;return dispatch(e);
}
int hd2env_invoke(HD2Environment *e,const char *name,const HD2Value *args,size_t count,HD2Results *out) {
    if(!name||!enter(e))return 0;
    if(count>64||(count&&!args)||(out&&(out->values||out->count))){
        snprintf(e->error,sizeof(e->error),"invalid native call arguments or nonempty results");e->busy=0;return 0;
    }
    for(size_t i=0;i<count;i++){
        if(args[i].type<HD2_VALUE_NIL||args[i].type>HD2_VALUE_POINTER||
           (args[i].type==HD2_VALUE_STRING&&args[i].as.string.size&&!args[i].as.string.bytes)){
            snprintf(e->error,sizeof(e->error),"invalid native argument value");e->busy=0;return 0;
        }
    }
    e->operation=4;e->name=name;e->arguments=args;e->argument_count=count;e->results=out;
    int ok=dispatch(e);
    if(!ok)hd2env_results_free(out);
    return ok;
}
int hd2env_eval(HD2Environment *e,const char *source,size_t size,const char *name) {
    if(!source||!name||!enter(e))return 0;
    e->operation=3;e->source=source;e->size=size;e->name=name;return dispatch(e);
}
int hd2env_check(HD2Environment *e,const char *source,size_t size,const char *name) {
    if(!source||!name||!enter(e))return 0;
    e->operation=5;e->source=source;e->size=size;e->name=name;return dispatch(e);
}
int hd2env_set_jit(HD2Environment *e,int enabled) {
    if(!enter(e))return 0;
#ifdef HD2ENV_PUC_REFERENCE
    (void)enabled;int result=0;
#else
    luaJIT_setmode(e->L,0,LUAJIT_MODE_ENGINE|LUAJIT_MODE_FLUSH);
    int result=luaJIT_setmode(e->L,0,LUAJIT_MODE_ENGINE|(enabled?LUAJIT_MODE_ON:LUAJIT_MODE_OFF));
#endif
    e->busy=0;return result;
}
const char *hd2env_error(const HD2Environment *e) {return e?e->error:"no environment";}
int hd2env_stack_depth(const HD2Environment *e) {return e&&same_thread(e->thread)?lua_gettop(e->L):-1;}
#include "frames.inc"
#include "lifecycle.inc"
#include "boot.inc"
#include "shutdown.inc"
int hd2env_destroy(HD2Environment *e) {
    if(!e)return 1;
    if(!same_thread(e->thread)||e->busy||e->frame_active||e->shutdown_stage==1||e->shutdown_stage==2)return 0;
    HD2NativeFactory factory=e->native_factory;
    int owned=e->native_owned;void *address=e->frame_native;
    if(owned)native_factory_busy++;
    frame_remove(e);
    bridge_close(e);
    e->busy=1;lua_close(e->L);object_store_free(e->objects);
    free(e->bridge_lj_release);free(e->bridge_puc_release);free(e);
    if(owned){native_closed(&factory,address);native_factory_busy--;}
    return 1;
}
