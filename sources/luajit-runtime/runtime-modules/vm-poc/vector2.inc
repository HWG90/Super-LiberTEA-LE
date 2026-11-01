/* Vector2 stores {uint32 tag,float x,float y} in the engine's actual temporary
 * pool. Lua owns only lightuserdata pointers, preserving pointer identity. */
#include <float.h>
typedef struct {uint32_t tag;float x,y;} HD2NativeVector2;
_Static_assert(sizeof(HD2NativeVector2)==12,"native Vector2 layout");
static uintptr_t vector2_read(lua_State *L,int index,HD2NativeVector2 *v) {
    HD2Environment *e=environment(L);
    if(!e->vector2_ready||lua_type(L,index)!=LUA_TLIGHTUSERDATA)
        luaL_argerror(L,index,"native Vector2 expected");
    uintptr_t p=(uintptr_t)lua_touserdata(L,index);
    if(!p||p>UINTPTR_MAX-sizeof(*v)||e->vector_host.read(e->vector_host.context,p,v,sizeof(*v))!=1||v->tag!=0x7796c581)
        luaL_argerror(L,index,"unreadable or expired native Vector2");
    return p;
}
static int vector2_push(lua_State *L,float x,float y) {
    HD2Environment *e=environment(L);
    uintptr_t p=hd2vector2_allocate(&e->vector_host,e->vector_environment);
    HD2NativeVector2 v={0x7796c581,x,y};
    if(!p||e->vector_host.write(e->vector_host.context,p,&v,sizeof(v))!=1)
        return luaL_error(L,"native Vector2 allocation or write refused");
    lua_pushlightuserdata(L,(void *)p);return 1;
}
static int vector2_constructor(lua_State *L){return vector2_push(L,(float)lua_tonumber(L,2),(float)lua_tonumber(L,3));}
static int vector2_zero(lua_State *L){return vector2_push(L,0,0);}
static int vector2_equal(lua_State *L){HD2NativeVector2 a,b;vector2_read(L,1,&a);vector2_read(L,2,&b);lua_pushboolean(L,a.x==b.x&&a.y==b.y);return 1;}
static int vector2_valid(lua_State *L){HD2NativeVector2 a;vector2_read(L,1,&a);lua_pushboolean(L,a.x>-FLT_MAX&&a.x<FLT_MAX&&a.y>-FLT_MAX&&a.y<FLT_MAX);return 1;}
enum { V2_ADD,V2_SUB,V2_MUL_ELEMENTS,V2_DIV_ELEMENTS,V2_MIN,V2_MAX };
static int vector2_binary(lua_State *L) {
    HD2NativeVector2 a,b;vector2_read(L,1,&a);vector2_read(L,2,&b);float x=0,y=0;
    switch(lua_tointeger(L,lua_upvalueindex(1))) {
        case V2_ADD:x=a.x+b.x;y=a.y+b.y;break;
        case V2_SUB:x=a.x-b.x;y=a.y-b.y;break;
        case V2_MUL_ELEMENTS:x=a.x*b.x;y=a.y*b.y;break;
        case V2_DIV_ELEMENTS:x=a.x/b.x;y=a.y/b.y;break;
        /* SSE MINSS/MAXSS select operand two on equality or NaN. */
        case V2_MIN:x=a.x<b.x?a.x:b.x;y=a.y<b.y?a.y:b.y;break;
        case V2_MAX:x=a.x>b.x?a.x:b.x;y=a.y>b.y?a.y:b.y;break;
    }
    return vector2_push(L,x,y);
}
static int vector2_multiply(lua_State *L){HD2NativeVector2 a;vector2_read(L,1,&a);float s=(float)lua_tonumber(L,2);return vector2_push(L,a.x*s,a.y*s);}
static int vector2_divide(lua_State *L){HD2NativeVector2 a;vector2_read(L,1,&a);float s=(float)lua_tonumber(L,2);return vector2_push(L,a.x/s,a.y/s);}
static int vector2_meta_multiply(lua_State *L) {
    if(lua_type(L,1)!=LUA_TLIGHTUSERDATA){lua_pushvalue(L,1);lua_pushvalue(L,2);lua_replace(L,1);lua_replace(L,2);}
    return vector2_multiply(L);
}
static int vector2_negate(lua_State *L){HD2NativeVector2 a;vector2_read(L,1,&a);return vector2_push(L,-a.x,-a.y);}
static int vector2_lerp(lua_State *L) {
    HD2NativeVector2 a,b;vector2_read(L,1,&a);vector2_read(L,2,&b);
    float s=(float)lua_tonumber(L,3),r=1.0f-s;
    float x=s*b.x,y=s*b.y;x=x+r*a.x;y=y+r*a.y;
    return vector2_push(L,x,y);
}
static int vector2_length(lua_State *L){HD2NativeVector2 a;vector2_read(L,1,&a);float v=a.x*a.x+a.y*a.y;lua_pushnumber(L,sqrtf(v));return 1;}
static int vector2_normalize(lua_State *L) {
    HD2NativeVector2 a;vector2_read(L,1,&a);float v=a.x*a.x+a.y*a.y,len=sqrtf(v);
    return (double)len<0.0001?vector2_push(L,0,0):vector2_push(L,a.x/len,a.y/len);
}
static int vector2_dot(lua_State *L){HD2NativeVector2 a,b;vector2_read(L,1,&a);vector2_read(L,2,&b);float v=b.y*a.y+b.x*a.x;lua_pushnumber(L,v);return 1;}
static int vector2_distance(lua_State *L) {
    HD2NativeVector2 a,b;vector2_read(L,1,&a);vector2_read(L,2,&b);float x=a.x-b.x,y=a.y-b.y,v=x*x+y*y;
    lua_pushnumber(L,lua_tointeger(L,lua_upvalueindex(1))?sqrtf(v):v);return 1;
}
static int vector2_to_elements(lua_State *L){HD2NativeVector2 a;vector2_read(L,1,&a);lua_pushnumber(L,a.x);lua_pushnumber(L,a.y);return 2;}
static int vector2_component(lua_State *L){HD2NativeVector2 a;vector2_read(L,1,&a);lua_pushnumber(L,lua_tointeger(L,lua_upvalueindex(1))==1?a.x:a.y);return 1;}
static int vector2_element_index(lua_State *L,int at) {
    double v=lua_tonumber(L,at);
    if(v>=1&&v<3)return (int)v;
    return luaL_argerror(L,at,"Vector2 element must be 1 or 2");
}
static int vector2_element(lua_State *L){HD2NativeVector2 a;vector2_read(L,1,&a);lua_pushnumber(L,vector2_element_index(L,2)==1?a.x:a.y);return 1;}
static int vector2_set_at(lua_State *L,int component,int value) {
    HD2NativeVector2 a;uintptr_t p=vector2_read(L,1,&a);HD2Environment *e=environment(L);float v=(float)lua_tonumber(L,value);
    if(e->vector_host.write(e->vector_host.context,p+(uintptr_t)component*4,&v,4)!=1)return luaL_error(L,"Vector2 write refused");
    return 0;
}
static int vector2_set_component(lua_State *L){return vector2_set_at(L,(int)lua_tointeger(L,lua_upvalueindex(1)),2);}
static int vector2_set_element(lua_State *L){return vector2_set_at(L,vector2_element_index(L,2),3);}
static int vector2_set_xy(lua_State *L){vector2_set_at(L,1,2);return vector2_set_at(L,2,3);}
static int vector2_to_string(lua_State *L) {
    HD2NativeVector2 a;vector2_read(L,1,&a);char out[128];HD2Environment *e=environment(L);
    if(!hd2vector2_format(&e->vector_host,out,a.x,a.y))return luaL_error(L,"Vector2 formatter refused");
    lua_pushstring(L,out);return 1;
}
static int vector2_global_tostring(lua_State *L) {
    /* The engine replaces Lua's tostring: its missing-argument case is a
     * string result, verified live, rather than the standard-library error. */
    if(!lua_gettop(L)){lua_pushliteral(L,"[no value (deleted)]");return 1;}
    if(lua_type(L,1)==LUA_TLIGHTUSERDATA) {
        HD2Environment *e=environment(L);HD2NativeVector2 v;uintptr_t p=(uintptr_t)lua_touserdata(L,1);
        if(p&&p<=UINTPTR_MAX-sizeof(v)&&e->vector_host.read(e->vector_host.context,p,&v,sizeof(v))==1&&v.tag==0x7796c581) {
            vector2_to_string(L);lua_pushfstring(L,"Vector2%s",lua_tostring(L,-1));return 1;
        }
    }
    lua_pushvalue(L,lua_upvalueindex(1));lua_pushvalue(L,1);lua_call(L,1,1);return 1;
}
static int vector2_meta_component(lua_State *L) {
    /* Live helper 0x419c30 examines only the first string byte. Numeric keys
     * use x86 truncation followed by the low 32 bits; other keys are absent. */
    if(lua_type(L,2)==LUA_TSTRING) {
        const char *s=lua_tostring(L,2);return s[0]=='x'?1:s[0]=='y'?2:0;
    }
    if(lua_type(L,2)==LUA_TNUMBER) {
        double x=lua_tonumber(L,2);
        int64_t i=x>=-9223372036854775808.0&&x<9223372036854775808.0?(int64_t)x:INT64_MIN;
        uint32_t low=(uint32_t)i;return low==1?1:low==2?2:0;
    }
    return 0;
}
static int vector2_meta_index(lua_State *L) {
    HD2NativeVector2 a;vector2_read(L,1,&a);int component=vector2_meta_component(L);
    if(component)lua_pushnumber(L,component==1?a.x:a.y);else lua_pushnil(L);
    return 1;
}
static int vector2_meta_newindex(lua_State *L) {
    HD2NativeVector2 a;vector2_read(L,1,&a);int component=vector2_meta_component(L);
    return component?vector2_set_at(L,component,3):0;
}
static void vector2_closure(lua_State *L,const char *name,lua_CFunction fn,int option){lua_pushinteger(L,option);lua_pushcclosure(L,fn,1);lua_setfield(L,-2,name);}
static int vector_temp_count(lua_State *L) {
    HD2Environment *e=environment(L);uint32_t count;
    if(!hd2vector_temp_count(&e->vector_host,e->vector_environment,&count))
        return luaL_error(L,"native temporary checkpoint unavailable");
    lua_pushnumber(L,count);return 1;
}
static int vector_temp_restore(lua_State *L) {
    HD2Environment *e=environment(L);double x=lua_tonumber(L,1);
    int64_t count=x>=-9223372036854775808.0&&x<9223372036854775808.0?(int64_t)x:INT64_MIN;
    if(!hd2vector_temp_restore(&e->vector_host,e->vector_environment,(uint32_t)count))
        return luaL_error(L,"native temporary checkpoint is out of range or unaligned");
    return 0;
}
static int vector2_registration(lua_State *L,HD2Environment *e) {
    e->vector2_ready=1;
    lua_getglobal(L,"stingray");lua_getfield(L,-1,"Vector2");
    if(!lua_istable(L,-1))return luaL_error(L,"Vector2 table unavailable");
    lua_pushvalue(L,-1);lua_setfield(L,-2,"__index");
    lua_pushliteral(L,"Vector2");lua_setfield(L,-2,"_name");
    lua_pushvalue(L,-1);lua_setfield(L,LUA_REGISTRYINDEX,"Vector2");
    lua_newtable(L);callback(L,"__call",vector2_constructor);lua_setmetatable(L,-2);
    callback(L,"zero",vector2_zero);callback(L,"equal",vector2_equal);callback(L,"is_valid",vector2_valid);
    callback(L,"multiply",vector2_multiply);callback(L,"divide",vector2_divide);callback(L,"lerp",vector2_lerp);
    callback(L,"length",vector2_length);callback(L,"normalize",vector2_normalize);callback(L,"dot",vector2_dot);
    callback(L,"to_elements",vector2_to_elements);callback(L,"to_string",vector2_to_string);callback(L,"element",vector2_element);
    callback(L,"set_element",vector2_set_element);callback(L,"set_xy",vector2_set_xy);
    vector2_closure(L,"distance",vector2_distance,1);vector2_closure(L,"distance_squared",vector2_distance,0);
    vector2_closure(L,"x",vector2_component,1);vector2_closure(L,"y",vector2_component,2);
    vector2_closure(L,"set_x",vector2_set_component,1);vector2_closure(L,"set_y",vector2_set_component,2);
    const char *names[]={"add","subtract","multiply_elements","divide_elements","min","max"};
    for(int i=0;i<6;i++)vector2_closure(L,names[i],vector2_binary,i);
    lua_pop(L,2);
    /* Temporary objects use one lightuserdata metatable, as in the original.
     * Dispatch for other native types will be added by their registrars. */
    lua_pushlightuserdata(L,NULL);lua_newtable(L);
    lua_pushliteral(L,"LightUserData");lua_setfield(L,-2,"_name");
    callback(L,"__index",vector2_meta_index);callback(L,"__newindex",vector2_meta_newindex);
    vector2_closure(L,"__add",vector2_binary,V2_ADD);vector2_closure(L,"__sub",vector2_binary,V2_SUB);
    callback(L,"__mul",vector2_meta_multiply);callback(L,"__div",vector2_divide);callback(L,"__unm",vector2_negate);
    lua_pushvalue(L,-1);lua_setfield(L,LUA_REGISTRYINDEX,"LightUserData");
    lua_setmetatable(L,-2);lua_pop(L,1);
    lua_getglobal(L,"tostring");lua_pushcclosure(L,vector2_global_tostring,1);lua_setglobal(L,"tostring");
    lua_getglobal(L,"stingray");lua_getfield(L,-1,"Script");
    if(!lua_istable(L,-1))return luaL_error(L,"Script table unavailable");
    callback(L,"temp_count",vector_temp_count);callback(L,"set_temp_count",vector_temp_restore);
    lua_pop(L,2);
    return 0;
}
