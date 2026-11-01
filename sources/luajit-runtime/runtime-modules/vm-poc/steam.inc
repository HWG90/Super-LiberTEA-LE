/* Lua-facing port of all callbacks registered by native Steam registrar.
 * Native calls use the traced Win64 vtable interface, not old Lua wrappers. */
#include "steam_witnesses.h"
static void steam_read(lua_State *L,HD2Environment *e,uintptr_t address,void *out,size_t size){
    if(!address||size>UINTPTR_MAX-address||e->steam_host.read(e->steam_host.context,address,out,size)!=1)
        luaL_error(L,"Steam native memory read refused");
}
static uintptr_t steam_method(lua_State *L,size_t slot,uintptr_t *self){
    HD2Environment *e=environment(L);uintptr_t vtable,fn;
    if(!e->steam_ready)luaL_error(L,"Steam native service is not registered");
    steam_read(L,e,e->steam_host.image_base+0x2860608,self,8);
    steam_read(L,e,*self,&vtable,8);
    if(vtable>UINTPTR_MAX-slot)luaL_error(L,"Steam vtable address overflow");
    steam_read(L,e,vtable+slot,&fn,8);
    if(!fn||e->steam_host.callable(e->steam_host.context,fn)!=1)luaL_error(L,"Steam native method is not callable");
    return fn;
}
static void steam_string(lua_State *L,uintptr_t address){
    if(!address){lua_pushnil(L);return;}
    HD2Environment *e=environment(L);luaL_Buffer buffer;luaL_buffinit(L,&buffer);
    for(size_t i=0;i<1048576;i++){
        char c;if(address>UINTPTR_MAX-i)luaL_error(L,"Steam string address overflow");
        steam_read(L,e,address+i,&c,1);
        if(!c){luaL_pushresult(&buffer);return;}luaL_addchar(&buffer,c);
    }
    luaL_error(L,"Steam native string exceeds limit");
}
static int steam_boolean(lua_State *L,size_t slot){
    uintptr_t self;uintptr_t fn=steam_method(L,slot,&self);
    unsigned char value=((unsigned char(HD2_NATIVE_ABI *)(void *))fn)((void *)self);
    lua_pushboolean(L,value!=0);return 1;
}
static int steam_connected(lua_State *L){return steam_boolean(L,0x38);}
static int steam_client_running(lua_State *L){return steam_boolean(L,0x40);}
static int steam_overlay_active(lua_State *L){return steam_boolean(L,0x48);}
static uint64_t steam_user(lua_State *L){
    uintptr_t self;uintptr_t fn=steam_method(L,0x18,&self);
    return ((uint64_t(HD2_NATIVE_ABI *)(void *))fn)((void *)self);
}
static int steam_user_id(lua_State *L){
    char text[17];snprintf(text,sizeof(text),"%016llx",(unsigned long long)steam_user(L));lua_pushstring(L,text);return 1;
}
static int steam_user_name(lua_State *L){
    uint64_t id;
    if(!lua_gettop(L))id=steam_user(L);
    else {
        const char *text=lua_tostring(L,1);char *end=NULL;
        if(!text)return luaL_argerror(L,1,"hexadecimal user ID expected");
        id=strtoull(text,&end,16);
        if(end==text)return luaL_argerror(L,1,"hexadecimal user ID expected");
    }
    uintptr_t self;uintptr_t fn=steam_method(L,0x28,&self);
    uintptr_t text=((uintptr_t(HD2_NATIVE_ABI *)(void *,uint64_t))fn)((void *)self,id);
    steam_string(L,text);return 1;
}
static int steam_language(lua_State *L){
    uintptr_t self;uintptr_t fn=steam_method(L,0x50,&self);
    uintptr_t text=((uintptr_t(HD2_NATIVE_ABI *)(void *))fn)((void *)self);
    HD2Environment *e=environment(L);unsigned char buffer[20]={0};
    for(size_t i=0;i<sizeof(buffer);i++){
        if(text>UINTPTR_MAX-i)return luaL_error(L,"Steam language address overflow");
        steam_read(L,e,text+i,buffer+i,1);if(!buffer[i])break;
    }
    size_t last=19;
    while((buffer[last]&0x80)&&(buffer[last]&0xc0)!=0xc0){buffer[last]=0;if(!last)break;last--;}
    buffer[last]=0;
    for(size_t i=0;buffer[i];i++)if(buffer[i]>='A'&&buffer[i]<='Z')buffer[i]+='a'-'A';
    for(size_t i=0;i<20;i++)if(!strcmp((char *)buffer,steam_languages[i][0])){
        lua_pushstring(L,steam_languages[i][1]);return 1;
    }
    if(e->backend.log){char warning[96];int n=snprintf(warning,sizeof(warning),"Failed to find language code for: `%s`",buffer);
        e->backend.log(e->backend.context,warning,(size_t)n);}
    lua_pushliteral(L,"en");return 1;
}
static int steam_app_boolean(lua_State *L,size_t slot){
    double number=0;uint32_t app=0;
    int type=lua_type(L,1);if(type==LUA_TNUMBER||type==LUA_TSTRING)number=lua_tonumber(L,1);
    /* Match CVTTSD2SI r64 then MOV edx,eax, including indefinite result's low
     * zero word for NaN/infinity/out-of-range. Avoid undefined C conversions. */
    if(number>=-9223372036854775808.0&&number<9223372036854775808.0)app=(uint32_t)(int64_t)number;
    uintptr_t self;uintptr_t fn=steam_method(L,slot,&self);
    unsigned char value=((unsigned char(HD2_NATIVE_ABI *)(void *,uint32_t))fn)((void *)self,app);
    lua_pushboolean(L,value!=0);return 1;
}
static int steam_is_installed(lua_State *L){return steam_app_boolean(L,0x70);}
static int steam_owns_app(lua_State *L){return steam_app_boolean(L,0x98);}
static int steam_install_event(lua_State *L){
    uintptr_t self;uintptr_t fn=steam_method(L,0xa0,&self);int32_t app=0;
    unsigned char present=((unsigned char(HD2_NATIVE_ABI *)(void *,int32_t *))fn)((void *)self,&app);
    if(present)lua_pushnumber(L,(double)app);else lua_pushnil(L);return 1;
}
static int steam_app_id(lua_State *L){
    uintptr_t self;uintptr_t fn=steam_method(L,0xa8,&self);
    int32_t app=((int32_t(HD2_NATIVE_ABI *)(void *))fn)((void *)self);lua_pushnumber(L,(double)app);return 1;
}
static int steam_open_url(lua_State *L){
    const char *url=lua_tostring(L,1);uintptr_t self;uintptr_t fn=steam_method(L,0xb0,&self);
    ((void(HD2_NATIVE_ABI *)(void *,const char *))fn)((void *)self,url);return 0;
}
static int steam_registration(lua_State *L,HD2Environment *e){
    const HD2SteamHost *h=&e->steam_pending;
    if(h->write(h->context,h->image_base+0x2860608,&e->steam_service,8)!=1)
        return luaL_error(L,"Steam native context store refused");
    e->steam_host=*h;e->steam_ready=1;
    if(!e->steam_service)return 0;
    lua_getfield(L,LUA_REGISTRYINDEX,"Steam");
    if(lua_isnil(L,-1)){
        lua_pop(L,1);lua_newtable(L);lua_pushvalue(L,-1);lua_setfield(L,-2,"__index");
        lua_pushliteral(L,"Steam");lua_setfield(L,-2,"_name");
        lua_pushvalue(L,-1);lua_setfield(L,LUA_REGISTRYINDEX,"Steam");
        lua_getglobal(L,"stingray");
        if(lua_isnil(L,-1)){
            lua_pop(L,1);lua_newtable(L);lua_pushvalue(L,-1);lua_setglobal(L,"stingray");
            lua_pushvalue(L,-1);lua_setglobal(L,"s3d");
        }
        lua_pushvalue(L,-2);lua_setfield(L,-2,"Steam");lua_pop(L,1);
    }
    callback(L,"connected",steam_connected);callback(L,"client_running",steam_client_running);
    callback(L,"overlay_active",steam_overlay_active);callback(L,"user_id",steam_user_id);
    callback(L,"user_name",steam_user_name);callback(L,"language",steam_language);
    callback(L,"is_installed",steam_is_installed);callback(L,"owns_app",steam_owns_app);
    callback(L,"install_event",steam_install_event);callback(L,"app_id",steam_app_id);callback(L,"open_url",steam_open_url);
    return 0;
}
