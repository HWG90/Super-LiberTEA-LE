/* The native box payload is three floats with no temporary-vector tag. Its
 * userdata header and lifetime belong entirely to this LuaJIT state. */
typedef struct {float x,y,z;} HD2Vector3Box;
_Static_assert(sizeof(HD2Vector3Box)==12,"Vector3Box payload layout");
static HD2Vector3Box *vector3box_test(lua_State *L,int index) {
    if(lua_type(L,index)!=LUA_TUSERDATA||lua_objlen(L,index)!=sizeof(HD2Vector3Box)||!lua_getmetatable(L,index))return NULL;
    lua_getfield(L,LUA_REGISTRYINDEX,"Vector3Box");
    int same=lua_rawequal(L,-1,-2);lua_pop(L,2);
    return same?(HD2Vector3Box *)lua_touserdata(L,index):NULL;
}
static HD2Vector3Box *vector3box_check(lua_State *L,int index) {
    HD2Vector3Box *v=vector3box_test(L,index);
    if(!v)luaL_argerror(L,index,"Vector3Box expected");
    return v;
}
static HD2Vector3Box vector3box_arguments(lua_State *L) {
    HD2Vector3Box b={0,0,0};
    /* Both the callable module and store have self at slot one. The original
     * accepts a temporary Vector3 or exactly three scalar arguments. */
    if(lua_gettop(L)==2){HD2NativeVector3 v;vector3_read(L,2,&v);b.x=v.x;b.y=v.y;b.z=v.z;}
    else if(lua_gettop(L)==4){b.x=(float)lua_tonumber(L,2);b.y=(float)lua_tonumber(L,3);b.z=(float)lua_tonumber(L,4);}
    return b;
}
static int vector3box_constructor(lua_State *L) {
    HD2Vector3Box value=vector3box_arguments(L);
    HD2Vector3Box *b=lua_newuserdata(L,sizeof(*b));*b=value;
    lua_getfield(L,LUA_REGISTRYINDEX,"Vector3Box");lua_setmetatable(L,-2);return 1;
}
static int vector3box_store(lua_State *L) {
    HD2Vector3Box *b=vector3box_check(L,1);*b=vector3box_arguments(L);return 0;
}
static int vector3box_unbox(lua_State *L) {
    HD2Vector3Box *b=vector3box_check(L,1);return vector3_push(L,b->x,b->y,b->z);
}
static int vector3box_index(lua_State *L) {
    HD2Vector3Box *b=vector3box_check(L,1);
    if(lua_type(L,2)==LUA_TSTRING&&lua_objlen(L,2)>1) {
        lua_getmetatable(L,1);lua_pushvalue(L,2);lua_gettable(L,-2);return 1;
    }
    int c=vector3_meta_component(L);
    if(c)lua_pushnumber(L,c==1?b->x:c==2?b->y:b->z);else lua_pushnil(L);
    return 1;
}
static int vector3box_newindex(lua_State *L) {
    HD2Vector3Box *b=vector3box_check(L,1);int c=vector3_meta_component(L);
    float value=(float)lua_tonumber(L,3);
    if(c==1)b->x=value;else if(c==2)b->y=value;else if(c==3)b->z=value;
    return 0;
}
static int vector3box_len(lua_State *L){lua_pushnumber(L,3);return 1;}
static int vector3box_global_tostring(lua_State *L) {
    if(!lua_gettop(L)){lua_pushvalue(L,lua_upvalueindex(1));lua_call(L,0,1);return 1;}
    HD2Vector3Box *b=vector3box_test(L,1);
    if(b) {
        HD2Environment *e=environment(L);char out[128];
        if(!hd2vector3_format(&e->vector_host,out,b->x,b->y,b->z))return luaL_error(L,"Vector3Box formatter refused");
        lua_pushfstring(L,"Vector3Box%s",out);return 1;
    }
    lua_pushvalue(L,lua_upvalueindex(1));lua_pushvalue(L,1);lua_call(L,1,1);return 1;
}
static int vector3box_registration(lua_State *L,HD2Environment *e) {
    lua_getglobal(L,"stingray");lua_getfield(L,-1,"Vector3Box");
    if(!lua_istable(L,-1))return luaL_error(L,"Vector3Box table unavailable");
    lua_pushliteral(L,"Vector3Box");lua_setfield(L,-2,"_name");
    lua_pushvalue(L,-1);lua_setfield(L,LUA_REGISTRYINDEX,"Vector3Box");
    callback(L,"__index",vector3box_index);callback(L,"__newindex",vector3box_newindex);callback(L,"__len",vector3box_len);
    callback(L,"store",vector3box_store);callback(L,"unbox",vector3box_unbox);
    lua_newtable(L);callback(L,"__call",vector3box_constructor);lua_setmetatable(L,-2);lua_pop(L,2);
    lua_getglobal(L,"tostring");lua_pushcclosure(L,vector3box_global_tostring,1);lua_setglobal(L,"tostring");
    e->vector3box_ready=1;return 0;
}
