/* Friends/Presence Lua entry points. Native helpers receive only native values;
 * they retain the game's existing Steam service, queues and allocators. */
#include "friends_witnesses.h"
static void friends_read(lua_State *L,uintptr_t address,void *out,size_t size){
    HD2Environment *e=environment(L);
    if(!e->friends_ready||!address||size>UINTPTR_MAX-address||
       e->friends_host.read(e->friends_host.context,address,out,size)!=1)
        luaL_error(L,"Friends native memory read refused");
}
static void friends_write(lua_State *L,uintptr_t address,const void *in,size_t size){
    HD2Environment *e=environment(L);
    if(!address||size>UINTPTR_MAX-address||e->friends_host.write(e->friends_host.context,address,in,size)!=1)
        luaL_error(L,"Friends native memory write refused");
}
static uintptr_t friends_callable(lua_State *L,uintptr_t address){
    HD2Environment *e=environment(L);
    if(!e->friends_ready||!address||e->friends_host.callable(e->friends_host.context,address)!=1)
        luaL_error(L,"Friends native function is not callable");
    return address;
}
static uintptr_t friends_native(lua_State *L,uintptr_t rva){
    return friends_callable(L,environment(L)->friends_host.image_base+rva);
}
static uintptr_t friends_service(lua_State *L){
    uintptr_t self;friends_read(L,environment(L)->friends_host.image_base+0x28605f0,&self,8);
    if(!self)luaL_error(L,"Friends native service is unavailable");
    return self;
}
static uintptr_t friends_method(lua_State *L,size_t slot,uintptr_t *self){
    HD2Environment *e=environment(L);uintptr_t getter,context,vtable,fn;
    friends_read(L,e->friends_host.image_base+0x148e7b8,&getter,8);friends_callable(L,getter);
    context=((uintptr_t(HD2_NATIVE_ABI *)(void *))getter)((void *)(e->friends_host.image_base+0x19b65a0));
    friends_read(L,context,self,8);friends_read(L,*self,&vtable,8);
    if(vtable>UINTPTR_MAX-slot)luaL_error(L,"Friends vtable address overflow");
    friends_read(L,vtable+slot,&fn,8);return friends_callable(L,fn);
}
static int friends_string(lua_State *L,uintptr_t text,int empty_absent){
    if(!text){if(empty_absent)return 0;lua_pushnil(L);return 1;}
    luaL_Buffer b;luaL_buffinit(L,&b);
    for(size_t i=0;i<1048576;i++){
        char c;if(text>UINTPTR_MAX-i)return luaL_error(L,"Friends native string address overflow");
        friends_read(L,text+i,&c,1);
        if(!c){if(!i&&empty_absent)return 0;luaL_pushresult(&b);return 1;}luaL_addchar(&b,c);
    }
    return luaL_error(L,"Friends native string exceeds limit");
}
static uint32_t friends_integer(lua_State *L,int index){
    int type=lua_type(L,index);double n=type==LUA_TNUMBER||type==LUA_TSTRING?lua_tonumber(L,index):0;
    return n>=-9223372036854775808.0&&n<9223372036854775808.0?(uint32_t)(int64_t)n:0;
}
static uint64_t friends_hex(lua_State *L,int index){
    const char *s=lua_tostring(L,index);char *end=NULL;
    if(!s){luaL_argerror(L,index,"hexadecimal ID expected");return 0;}
    uint64_t n=strtoull(s,&end,16);
    if(end==s)luaL_argerror(L,index,"hexadecimal ID expected");
    return n;
}
static void friends_push_id(lua_State *L,uint64_t id){
    char text[17];snprintf(text,sizeof(text),"%016llx",(unsigned long long)id);lua_pushstring(L,text);
}
static int friends_num_friends(lua_State *L){
    uint32_t category=lua_gettop(L)?friends_integer(L,1):4;uintptr_t service=friends_service(L),self;
    if(service>UINTPTR_MAX-0xc0)return luaL_error(L,"Friends service address overflow");
    friends_write(L,service+0xc0,&category,4);
    uintptr_t fn=friends_method(L,0x10,&self);
    int32_t count=((int32_t(HD2_NATIVE_ABI *)(void *,uint32_t))fn)((void *)self,category);
    lua_pushnumber(L,count);return 1;
}
static int friends_id(lua_State *L){
    uint32_t index=friends_integer(L,1)-1,category;uintptr_t self,service=friends_service(L);
    if(service>UINTPTR_MAX-0xc0)return luaL_error(L,"Friends service address overflow");
    friends_read(L,service+0xc0,&category,4);uintptr_t fn=friends_method(L,0x18,&self);uint64_t id=0;
    uintptr_t result=((uintptr_t(HD2_NATIVE_ABI *)(void *,uint64_t *,uint32_t,uint32_t))fn)((void *)self,&id,index,category);
    if(result!=(uintptr_t)&id)friends_read(L,result,&id,8);
    friends_push_id(L,id);return 1;
}
static int friends_name(lua_State *L){
    uint64_t id=friends_hex(L,1);uintptr_t fn=friends_native(L,0x7cbc50);
    return friends_string(L,((uintptr_t(HD2_NATIVE_ABI *)(void *,uint64_t))fn)(NULL,id),0);
}
static int friends_enum(lua_State *L,size_t slot){
    uint64_t id=friends_hex(L,1);uintptr_t self,fn=friends_method(L,slot,&self);
    int32_t value=((int32_t(HD2_NATIVE_ABI *)(void *,uint64_t))fn)((void *)self,id);lua_pushnumber(L,value);return 1;
}
static int friends_relationship(lua_State *L){return friends_enum(L,0x20);}
static int friends_status(lua_State *L){return friends_enum(L,0x28);}
static int friends_in_category(lua_State *L){
    uint32_t category=friends_integer(L,2);uint64_t id=friends_hex(L,1);uintptr_t self,fn=friends_method(L,0x80,&self);
    unsigned char value=((unsigned char(HD2_NATIVE_ABI *)(void *,uint64_t,uint32_t))fn)((void *)self,id,category);
    lua_pushboolean(L,value!=0);return 1;
}
static uint32_t friends_u32(const void *p){uint32_t n;memcpy(&n,p,4);return n;}
static uint64_t friends_u64(const void *p){uint64_t n;memcpy(&n,p,8);return n;}
static void friends_number_field(lua_State *L,const char *key,double n){lua_pushnumber(L,n);lua_setfield(L,-2,key);}
static void friends_address(char *out,size_t size,uint32_t ip,int32_t port,int with_port){
    if(with_port)snprintf(out,size,"%u.%u.%u.%u:%d",ip>>24,(ip>>16)&255,(ip>>8)&255,ip&255,port);
    else snprintf(out,size,"%u.%u.%u.%u",ip>>24,(ip>>16)&255,(ip>>8)&255,ip&255);
}
static int friends_playing_game(lua_State *L){
    uint64_t id=friends_hex(L,1);_Alignas(16) unsigned char data[48]={0};uintptr_t fn=friends_native(L,0x7cc110);
    if(!((unsigned char(HD2_NATIVE_ABI *)(void *,uint64_t,void *))fn)(NULL,id,data))return 0;
    int32_t app;memcpy(&app,data+4,4);lua_newtable(L);friends_number_field(L,"app_id",app);
    /* The captured callback uses app_id again here, not native data+8. */
    if(data[0])friends_number_field(L,"mod_id",app);
    if(data[12]){friends_push_id(L,friends_u64(data+16));lua_setfield(L,-2,"lobby");}
    if(data[24]){
        char ip[32];uint16_t server,query;memcpy(&server,data+32,2);memcpy(&query,data+34,2);
        friends_address(ip,sizeof(ip),friends_u32(data+28),0,0);lua_pushstring(L,ip);lua_setfield(L,-2,"ip");
        friends_number_field(L,"server_port",server);friends_number_field(L,"query_port",query);
    }
    return 1;
}
static int friends_invite_result(lua_State *L,const unsigned char *data,int32_t kind,int full){
    lua_pushnumber(L,kind);uint32_t tag=friends_u32(data);
    if(!tag)return 1;
    if(tag==1)friends_push_id(L,friends_u64(data+8));
    else {char address[64];int32_t port;memcpy(&port,data+20,4);friends_address(address,sizeof(address),friends_u32(data+16),port,1);lua_pushstring(L,address);}
    if(!full)return 2;
    const char *message=(const char *)data+64;size_t size=0;while(size<32&&message[size])size++;
    if(size==32)return luaL_error(L,"Friends invitation text is not terminated");
    lua_pushlstring(L,message,size);friends_push_id(L,friends_u64(data+24));return 4;
}
static int friends_next_invite(lua_State *L){
    uintptr_t service=friends_service(L),fn=friends_native(L,0x7cc930);_Alignas(16) unsigned char data[96]={0};
    int32_t kind=((int32_t(HD2_NATIVE_ABI *)(void *,void *))fn)((void *)service,data);
    return friends_invite_result(L,data,kind,1);
}
static int friends_boot_invite(lua_State *L){
    uintptr_t service=friends_service(L);unsigned char data[32];
    if(service>UINTPTR_MAX-0xe8)return luaL_error(L,"Friends service address overflow");
    friends_read(L,service+0xe8,data,sizeof(data));int32_t kind;memcpy(&kind,data,4);
    return friends_invite_result(L,data,kind,0);
}
static const char *friends_optional(lua_State *L,int index){
    return lua_isstring(L,index)?lua_tostring(L,index):"";
}
static int friends_destination(lua_State *L,int index,uint64_t *lobby,uint32_t address[2]){
    int type=lua_type(L,index);
    if((type==LUA_TUSERDATA||type==LUA_TLIGHTUSERDATA)&&lua_touserdata(L,index)&&lua_getmetatable(L,index)){
        lua_getfield(L,LUA_REGISTRYINDEX,"SteamLobby");int match=lua_rawequal(L,-1,-2);lua_pop(L,2);
        if(match){
            uintptr_t object;
            if(type==LUA_TUSERDATA){
                if(lua_objlen(L,index)<8)return luaL_argerror(L,index,"SteamLobby userdata is too small");
                memcpy(&object,lua_touserdata(L,index),8);
            }else friends_read(L,(uintptr_t)lua_touserdata(L,index),&object,8);
            if(object>UINTPTR_MAX-0x178)return luaL_error(L,"SteamLobby address overflow");
            friends_read(L,object+0x178,lobby,8);return 1;
        }
    }
    const char *s=lua_tostring(L,index);
    if(!s)return luaL_argerror(L,index,"lobby ID, SteamLobby or server address expected");
    size_t n=strlen(s),hex=0;while(hex<n&&strchr("0123456789abcdefABCDEF",s[hex]))hex++;
    if(hex==n){*lobby=friends_hex(L,index);return 1;}
    /* scanf %i uses base 0 and retains zero-initialized remaining fields on a
     * partial match. Unsigned arithmetic preserves the original 32-bit shifts. */
    uint32_t parts[5]={0};const char *cursor=s;
    for(int i=0;i<5;i++){
        char *end;unsigned long long value=strtoull(cursor,&end,0);if(end==cursor)break;
        parts[i]=(uint32_t)value;cursor=end;if(i==4||*cursor!=(i==3?':':'.'))break;cursor++;
    }
    address[0]=(((parts[0]<<8)|parts[1])<<8|parts[2])<<8|parts[3];address[1]=parts[4];return 0;
}
static int friends_invite(lua_State *L){
    uint64_t id=friends_hex(L,1),lobby=0;uint32_t address[2]={0};
    int is_lobby=friends_destination(L,2,&lobby,address);const char *extra=friends_optional(L,3);
    if(is_lobby){uintptr_t fn=friends_native(L,0x7cc2c0);((void(HD2_NATIVE_ABI *)(void *,uint64_t,uint64_t,const char *))fn)(NULL,id,lobby,extra);}
    else {const char *password=friends_optional(L,4);uintptr_t fn=friends_native(L,0x7cc5d0);
        ((void(HD2_NATIVE_ABI *)(void *,uint64_t,const void *,const char *,const char *))fn)(NULL,id,address,extra,password);}
    return 0;
}
static int friends_advertise_playing(lua_State *L){
    uint64_t lobby=0;uint32_t address[2]={0};int is_lobby=friends_destination(L,1,&lobby,address);
    const char *extra=friends_optional(L,2);
    if(is_lobby){uintptr_t fn=friends_native(L,0x7ce630);((void(HD2_NATIVE_ABI *)(void *,uint64_t,const char *))fn)(NULL,lobby,extra);}
    else {const char *password=friends_optional(L,3);uintptr_t fn=friends_native(L,0x7ce930);
        ((void(HD2_NATIVE_ABI *)(void *,const void *,const char *,const char *))fn)(NULL,address,extra,password);}
    return 0;
}
static int friends_stop_advertise_playing(lua_State *L){
    uintptr_t self,fn=friends_method(L,0x148,&self);
    ((unsigned char(HD2_NATIVE_ABI *)(void *,const char *,const char *))fn)((void *)self,"connect",NULL);return 0;
}
static int friends_set_presence(lua_State *L){
    const char *value=lua_tostring(L,2),*key=lua_tostring(L,1);uintptr_t self,fn=friends_method(L,0x148,&self);
    ((unsigned char(HD2_NATIVE_ABI *)(void *,const char *,const char *))fn)((void *)self,key,value);return 0;
}
static int friends_presence(lua_State *L){
    const char *key=lua_tostring(L,2);uint64_t id=friends_hex(L,1);uintptr_t self,fn=friends_method(L,0x158,&self);
    return friends_string(L,((uintptr_t(HD2_NATIVE_ABI *)(void *,uint64_t,const char *))fn)((void *)self,id,key),1);
}
static void friends_module(lua_State *L,const char *name){
    lua_getfield(L,LUA_REGISTRYINDEX,name);
    if(!lua_isnil(L,-1))return;
    lua_pop(L,1);lua_newtable(L);lua_pushvalue(L,-1);lua_setfield(L,-2,"__index");
    lua_pushstring(L,name);lua_setfield(L,-2,"_name");lua_pushvalue(L,-1);lua_setfield(L,LUA_REGISTRYINDEX,name);
    lua_getglobal(L,"stingray");
    if(lua_isnil(L,-1)){
        lua_pop(L,1);lua_newtable(L);lua_pushvalue(L,-1);lua_setglobal(L,"stingray");lua_pushvalue(L,-1);lua_setglobal(L,"s3d");
    }
    lua_pushvalue(L,-2);lua_setfield(L,-2,name);lua_pop(L,1);
}
static int friends_registration(lua_State *L,HD2Environment *e){
    const HD2FriendsHost *h=&e->friends_pending;
    if(h->write(h->context,h->image_base+0x28605f0,&e->friends_service,8)!=1)
        return luaL_error(L,"Friends native context store refused");
    e->friends_host=*h;e->friends_ready=1;if(!e->friends_service)return 0;
    friends_module(L,"Friends");
    callback(L,"num_friends",friends_num_friends);callback(L,"id",friends_id);callback(L,"name",friends_name);
    callback(L,"relationship",friends_relationship);callback(L,"status",friends_status);callback(L,"in_category",friends_in_category);
    callback(L,"playing_game",friends_playing_game);callback(L,"invite",friends_invite);callback(L,"next_invite",friends_next_invite);callback(L,"boot_invite",friends_boot_invite);
    lua_pop(L,1);friends_module(L,"Presence");
    callback(L,"advertise_playing",friends_advertise_playing);callback(L,"stop_advertise_playing",friends_stop_advertise_playing);
    callback(L,"set_presence",friends_set_presence);callback(L,"presence",friends_presence);
    lua_pop(L,1);friends_module(L,"Friends");
    for(size_t i=0;i<sizeof(friends_constants)/sizeof(*friends_constants);i++)friends_number_field(L,friends_constants[i].name,friends_constants[i].value);
    return 0;
}
