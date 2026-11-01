/* Verified room/client portion of SteamVoip. No old Lua state is passed to
 * native helpers. Lifecycle and update are deliberately not registered here. */
#include "voip_witnesses.h"
static uintptr_t voip_offset(lua_State *L,uintptr_t p,size_t offset){
    if(!p||p>UINTPTR_MAX-offset)luaL_error(L,"SteamVoip native address overflow or null");
    return p+offset;
}
static void voip_read(lua_State *L,uintptr_t at,void *out,size_t size){
    HD2Environment *e=environment(L);
    if(!e->voip_ready||!at||size>UINTPTR_MAX-at||e->voip_host.read(e->voip_host.context,at,out,size)!=1)
        luaL_error(L,"SteamVoip native memory read refused");
}
static uintptr_t voip_pointer(lua_State *L,uintptr_t at){uintptr_t p;voip_read(L,at,&p,8);return p;}
static uint64_t voip_hex(lua_State *L,int index){
    const char *s=lua_tostring(L,index);char *end=NULL;
    if(!s){luaL_argerror(L,index,"hexadecimal ID expected");return 0;}
    uint64_t id=strtoull(s,&end,16);if(end==s)luaL_argerror(L,index,"hexadecimal ID expected");return id;
}
static void voip_push_id(lua_State *L,uint64_t id){
    char text[17];snprintf(text,sizeof(text),"%016llx",(unsigned long long)id);lua_pushstring(L,text);
}
static uintptr_t voip_client(lua_State *L){
    void *data=lua_touserdata(L,1);uintptr_t client;
    if(!data)return (uintptr_t)luaL_argerror(L,1,"SteamVoipClient userdata expected");
    if(lua_type(L,1)==LUA_TUSERDATA){
        if(lua_objlen(L,1)<8)return (uintptr_t)luaL_argerror(L,1,"SteamVoipClient userdata is too small");
        memcpy(&client,data,8);
    }else voip_read(L,(uintptr_t)data,&client,8);
    if(!client)luaL_argerror(L,1,"SteamVoipClient native pointer is null");
    return client;
}
static uintptr_t voip_room(lua_State *L){
    uint64_t id=voip_hex(L,1);HD2Environment *e=environment(L);
    uintptr_t manager=voip_pointer(L,e->voip_host.image_base+0x28605f8);uint32_t count;
    voip_read(L,voip_offset(L,manager,0x88),&count,4);
    if(count>1048576)luaL_error(L,"SteamVoip room count exceeds limit");
    if(count){
        uintptr_t rooms=voip_pointer(L,voip_offset(L,manager,0x90));
        for(uint32_t i=0;i<count;i++){
            uintptr_t room=voip_pointer(L,voip_offset(L,rooms,(size_t)i*8));uint64_t candidate;
            voip_read(L,voip_offset(L,room,0x10),&candidate,8);if(candidate==id)return room;
        }
    }
    luaL_argerror(L,1,"SteamVoip room ID is not present");return 0;
}
static int voip_members(lua_State *L,uintptr_t object,int client,int broken){
    uint32_t count;voip_read(L,voip_offset(L,object,client?0x40:0x18),&count,4);
    if(count>1048576)return luaL_error(L,"SteamVoip member count exceeds limit");
    uintptr_t rows=count?voip_pointer(L,voip_offset(L,object,client?0x48:0x20)):0;
    size_t stride=client?0x40:0x28;uint32_t used=0;
    /* Lua owns the snapshot allocation, including error cleanup. Read all IDs
     * before creating result strings/tables, as the original callbacks do. */
    uint64_t *ids=lua_newuserdata(L,(size_t)count*8);
    for(uint32_t i=0;i<count;i++){
        unsigned char row[0x40];int32_t occupied;
        voip_read(L,voip_offset(L,rows,(size_t)i*stride),row,stride);
        memcpy(&occupied,row+(client?0x38:0x20),4);
        if(occupied<0||(broken&&row[0x1c]))continue;
        memcpy(ids+used++,row,8);
    }
    if(broken&&!used)return 0;
    lua_createtable(L,(int)used,0);
    for(uint32_t i=0;i<used;i++){voip_push_id(L,ids[i]);lua_rawseti(L,-2,(int)i+1);}return 1;
}
static int voip_room_members(lua_State *L){return voip_members(L,voip_room(L),0,0);}
static int voip_broken_members(lua_State *L){return voip_members(L,voip_room(L),0,1);}
static int voip_client_members(lua_State *L){return voip_members(L,voip_client(L),1,0);}
static int voip_room_id(lua_State *L){
    uint64_t id;voip_read(L,voip_offset(L,voip_client(L),0x38),&id,8);voip_push_id(L,id);return 1;
}
static int voip_broken_host(lua_State *L){
    unsigned char connected;voip_read(L,voip_offset(L,voip_client(L),0x78),&connected,1);
    lua_pushboolean(L,!connected);return 1;
}
static int voip_select(lua_State *L,int input){
    uintptr_t client=voip_client(L);int selected=lua_toboolean(L,2),one=lua_gettop(L)>2;
    uint64_t id=one?voip_hex(L,3):0;HD2Environment *e=environment(L);
    uintptr_t fn=e->voip_host.image_base+(input?(one?0x7d1d80:0x7d1d10):(one?0x7d1c90:0x7d1c20));
    if(e->voip_host.callable(e->voip_host.context,fn)!=1)
        return luaL_error(L,"SteamVoip selection function is not callable");
    if(one){
        if(e->voip_host.callable(e->voip_host.context,e->voip_host.image_base+0x7d3a70)!=1)
            return luaL_error(L,"SteamVoip native member lookup is unavailable");
        ((void(HD2_NATIVE_ABI *)(void *,unsigned char,uint64_t))fn)((void *)client,(unsigned char)selected,id);
    }else ((void(HD2_NATIVE_ABI *)(void *,unsigned char))fn)((void *)client,(unsigned char)selected);
    return 0;
}
static int voip_select_out(lua_State *L){return voip_select(L,0);}
static int voip_select_in(lua_State *L){return voip_select(L,1);}
static void voip_module(lua_State *L,const char *name){
    lua_getfield(L,LUA_REGISTRYINDEX,name);if(!lua_isnil(L,-1))return;
    lua_pop(L,1);lua_newtable(L);lua_pushvalue(L,-1);lua_setfield(L,-2,"__index");
    lua_pushstring(L,name);lua_setfield(L,-2,"_name");lua_pushvalue(L,-1);lua_setfield(L,LUA_REGISTRYINDEX,name);
    lua_getglobal(L,"stingray");if(lua_isnil(L,-1)){
        lua_pop(L,1);lua_newtable(L);lua_pushvalue(L,-1);lua_setglobal(L,"stingray");lua_pushvalue(L,-1);lua_setglobal(L,"s3d");
    }
    lua_pushvalue(L,-2);lua_setfield(L,-2,name);lua_pop(L,1);
}
static int voip_views_registration(lua_State *L,HD2Environment *e){
    const HD2VoipHost *h=&e->voip_pending;
    if(h->write(h->context,h->image_base+0x28605f8,&e->voip_manager,8)!=1)
        return luaL_error(L,"SteamVoip native manager store refused");
    e->voip_host=*h;e->voip_ready=1;
    voip_module(L,"SteamVoipRoom");callback(L,"members",voip_room_members);callback(L,"broken_members",voip_broken_members);lua_pop(L,1);
    voip_module(L,"SteamVoipClient");callback(L,"room_id",voip_room_id);callback(L,"members",voip_client_members);
    callback(L,"select_out",voip_select_out);callback(L,"select_in",voip_select_in);callback(L,"broken_host",voip_broken_host);return 0;
}
