/* Vector4 and Quaternion share this native tagged payload and metatable. */
typedef struct {uint32_t tag;float x,y,z,w;} HD2NativeVector4;
_Static_assert(sizeof(HD2NativeVector4)==20,"native Vector4 layout");
static uintptr_t vector4_read(lua_State *L,int index,HD2NativeVector4 *v) {
    HD2Environment *e=environment(L);
    if(!e->vector4_ready||lua_type(L,index)!=LUA_TLIGHTUSERDATA)luaL_argerror(L,index,"native Vector4 expected");
    uintptr_t p=(uintptr_t)lua_touserdata(L,index);
    if(!p||p>UINTPTR_MAX-sizeof(*v)||e->vector_host.read(e->vector_host.context,p,v,sizeof(*v))!=1||v->tag!=0x58235806)
        luaL_argerror(L,index,"unreadable or expired native Vector4");
    return p;
}
static int vector4_push(lua_State *L,float x,float y,float z,float w) {
    HD2Environment *e=environment(L);uintptr_t p=hd2vector4_allocate(&e->vector_host,e->vector_environment);
    HD2NativeVector4 v={0x58235806,x,y,z,w};
    if(!p||e->vector_host.write(e->vector_host.context,p,&v,sizeof(v))!=1)return luaL_error(L,"native Vector4 allocation or write refused");
    lua_pushlightuserdata(L,(void *)p);return 1;
}
static int vector4_constructor(lua_State *L){return vector4_push(L,(float)lua_tonumber(L,2),(float)lua_tonumber(L,3),(float)lua_tonumber(L,4),(float)lua_tonumber(L,5));}
static int vector4_zero(lua_State *L){return vector4_push(L,0,0,0,0);}
static int vector4_equal(lua_State *L){HD2NativeVector4 a,b;vector4_read(L,1,&a);vector4_read(L,2,&b);lua_pushboolean(L,a.x==b.x&&a.y==b.y&&a.z==b.z&&a.w==b.w);return 1;}
static int vector4_valid(lua_State *L){HD2NativeVector4 a;vector4_read(L,1,&a);lua_pushboolean(L,a.x>-FLT_MAX&&a.x<FLT_MAX&&a.y>-FLT_MAX&&a.y<FLT_MAX&&a.z>-FLT_MAX&&a.z<FLT_MAX&&a.w>-FLT_MAX&&a.w<FLT_MAX);return 1;}
static int vector4_binary(lua_State *L) {
    HD2NativeVector4 a,b;vector4_read(L,1,&a);vector4_read(L,2,&b);
    float av[4]={a.x,a.y,a.z,a.w},bv[4]={b.x,b.y,b.z,b.w},out[4]={0};
    for(int i=0;i<4;i++)switch(lua_tointeger(L,lua_upvalueindex(1))) {
        case V2_ADD:out[i]=av[i]+bv[i];break;
        case V2_SUB:out[i]=av[i]-bv[i];break;
        case V2_MUL_ELEMENTS:out[i]=av[i]*bv[i];break;
        case V2_DIV_ELEMENTS:out[i]=av[i]/bv[i];break;
        case V2_MIN:out[i]=av[i]<bv[i]?av[i]:bv[i];break;
        case V2_MAX:out[i]=av[i]>bv[i]?av[i]:bv[i];break;
    }
    return vector4_push(L,out[0],out[1],out[2],out[3]);
}
static int vector4_multiply(lua_State *L){HD2NativeVector4 a;vector4_read(L,1,&a);float s=(float)lua_tonumber(L,2);return vector4_push(L,s*a.x,s*a.y,s*a.z,s*a.w);}
static int vector4_divide(lua_State *L){HD2NativeVector4 a;vector4_read(L,1,&a);float s=(float)lua_tonumber(L,2);return vector4_push(L,a.x/s,a.y/s,a.z/s,a.w/s);}
static int vector4_meta_multiply(lua_State *L) {
    if(lua_type(L,1)!=LUA_TLIGHTUSERDATA){lua_pushvalue(L,1);lua_pushvalue(L,2);lua_replace(L,1);lua_replace(L,2);}
    return vector4_multiply(L);
}
static int vector4_negate(lua_State *L){HD2NativeVector4 a;vector4_read(L,1,&a);return vector4_push(L,-a.x,-a.y,-a.z,-a.w);}
static float vector4_squared(HD2NativeVector4 a){float v=a.x*a.x+a.y*a.y;v=v+a.z*a.z;return v+a.w*a.w;}
static int vector4_length(lua_State *L){HD2NativeVector4 a;vector4_read(L,1,&a);lua_pushnumber(L,sqrtf(vector4_squared(a)));return 1;}
static int vector4_normalize(lua_State *L) {
    HD2NativeVector4 a;vector4_read(L,1,&a);float len=sqrtf(vector4_squared(a));
    return (double)len<0.0001?vector4_push(L,0,0,0,0):vector4_push(L,a.x/len,a.y/len,a.z/len,a.w/len);
}
static int vector4_dot(lua_State *L){HD2NativeVector4 a,b;vector4_read(L,1,&a);vector4_read(L,2,&b);float v=b.y*a.y+b.x*a.x;v=v+b.z*a.z;v=v+b.w*a.w;lua_pushnumber(L,v);return 1;}
static int vector4_distance(lua_State *L) {
    HD2NativeVector4 a,b;vector4_read(L,1,&a);vector4_read(L,2,&b);
    float x=a.x-b.x,y=a.y-b.y,z=a.z-b.z,w=a.w-b.w,v=x*x+y*y;v=v+z*z;v=v+w*w;
    lua_pushnumber(L,lua_tointeger(L,lua_upvalueindex(1))?sqrtf(v):v);return 1;
}
static int vector4_lerp(lua_State *L) {
    HD2NativeVector4 a,b;vector4_read(L,1,&a);vector4_read(L,2,&b);float s=(float)lua_tonumber(L,3),r=1.0f-s;
    return vector4_push(L,r*a.x+s*b.x,r*a.y+s*b.y,r*a.z+s*b.z,r*a.w+s*b.w);
}
static float vector4_component_value(HD2NativeVector4 a,int c){return c==1?a.x:c==2?a.y:c==3?a.z:a.w;}
static int vector4_to_elements(lua_State *L){HD2NativeVector4 a;vector4_read(L,1,&a);lua_pushnumber(L,a.x);lua_pushnumber(L,a.y);lua_pushnumber(L,a.z);lua_pushnumber(L,a.w);return 4;}
static int vector4_component(lua_State *L){HD2NativeVector4 a;vector4_read(L,1,&a);lua_pushnumber(L,vector4_component_value(a,(int)lua_tointeger(L,lua_upvalueindex(1))));return 1;}
static int vector4_element_index(lua_State *L,int at){double x=lua_tonumber(L,at);if(x>=1&&x<5)return (int)x;return luaL_argerror(L,at,"Vector4 element must be 1, 2, 3 or 4");}
static int vector4_element(lua_State *L){HD2NativeVector4 a;vector4_read(L,1,&a);lua_pushnumber(L,vector4_component_value(a,vector4_element_index(L,2)));return 1;}
static int vector4_set_at(lua_State *L,int c,int value) {
    HD2NativeVector4 a;uintptr_t p=vector4_read(L,1,&a);HD2Environment *e=environment(L);float v=(float)lua_tonumber(L,value);
    if(e->vector_host.write(e->vector_host.context,p+(uintptr_t)c*4,&v,4)!=1)return luaL_error(L,"Vector4 write refused");
    return 0;
}
static int vector4_set_component(lua_State *L){return vector4_set_at(L,(int)lua_tointeger(L,lua_upvalueindex(1)),2);}
static int vector4_set_element(lua_State *L){return vector4_set_at(L,vector4_element_index(L,2),3);}
static int vector4_set_xyzw(lua_State *L){for(int i=1;i<=4;i++)vector4_set_at(L,i,i+1);return 0;}
static int vector4_to_string(lua_State *L) {
    HD2NativeVector4 a;vector4_read(L,1,&a);HD2Environment *e=environment(L);char out[128];
    if(!hd2vector4_format(&e->vector_host,out,a.x,a.y,a.z,a.w))return luaL_error(L,"Vector4 formatter refused");
    lua_pushstring(L,out);return 1;
}
static int vector4_meta_component(lua_State *L) {
    if(lua_type(L,2)==LUA_TSTRING){const char *s=lua_tostring(L,2);return s[0]=='x'?1:s[0]=='y'?2:s[0]=='z'?3:s[0]=='w'?4:0;}
    if(lua_type(L,2)==LUA_TNUMBER){uint32_t i=vector_integer(lua_tonumber(L,2));return i>=1&&i<=4?(int)i:0;}
    return 0;
}
static int vector4_meta_index(lua_State *L){HD2NativeVector4 a;vector4_read(L,1,&a);int c=vector4_meta_component(L);if(c)lua_pushnumber(L,vector4_component_value(a,c));else lua_pushnil(L);return 1;}
static int vector4_meta_newindex(lua_State *L){HD2NativeVector4 a;vector4_read(L,1,&a);int c=vector4_meta_component(L);return c?vector4_set_at(L,c,3):0;}
static int vector4_common_binary(lua_State *L){return vector_kind(L,1)==4?vector4_binary(L):vector_common_binary(L);}
static int vector4_common_multiply(lua_State *L){int k=vector_kind(L,1);if(!k)k=vector_kind(L,2);return k==4?vector4_meta_multiply(L):vector_common_multiply(L);}
static int vector4_common_divide(lua_State *L){return vector_kind(L,1)==4?vector4_divide(L):vector_common_divide(L);}
static int vector4_common_negate(lua_State *L){return vector_kind(L,1)==4?vector4_negate(L):vector_common_negate(L);}
static int vector4_common_index(lua_State *L){return vector_kind(L,1)==4?vector4_meta_index(L):vector_common_index(L);}
static int vector4_common_newindex(lua_State *L){return vector_kind(L,1)==4?vector4_meta_newindex(L):vector_common_newindex(L);}
static int vector4_global_tostring(lua_State *L) {
    if(!lua_gettop(L)){lua_pushvalue(L,lua_upvalueindex(1));lua_call(L,0,1);return 1;}
    if(vector_kind(L,1)==4){vector4_to_string(L);lua_pushfstring(L,"Vector4%s",lua_tostring(L,-1));return 1;}
    lua_pushvalue(L,lua_upvalueindex(1));lua_pushvalue(L,1);lua_call(L,1,1);return 1;
}
static int vector4_registration(lua_State *L,HD2Environment *e) {
    e->vector4_ready=1;lua_getglobal(L,"stingray");lua_getfield(L,-1,"Vector4");
    if(!lua_istable(L,-1))return luaL_error(L,"Vector4 table unavailable");
    lua_pushvalue(L,-1);lua_setfield(L,-2,"__index");lua_pushliteral(L,"Vector4");lua_setfield(L,-2,"_name");
    lua_pushvalue(L,-1);lua_setfield(L,LUA_REGISTRYINDEX,"Vector4");
    lua_newtable(L);callback(L,"__call",vector4_constructor);lua_setmetatable(L,-2);
    callback(L,"zero",vector4_zero);callback(L,"equal",vector4_equal);callback(L,"is_valid",vector4_valid);
    callback(L,"multiply",vector4_multiply);callback(L,"divide",vector4_divide);callback(L,"lerp",vector4_lerp);
    callback(L,"length",vector4_length);callback(L,"normalize",vector4_normalize);callback(L,"dot",vector4_dot);
    callback(L,"to_elements",vector4_to_elements);callback(L,"to_string",vector4_to_string);callback(L,"element",vector4_element);
    callback(L,"set_element",vector4_set_element);callback(L,"set_xyzw",vector4_set_xyzw);
    vector2_closure(L,"distance",vector4_distance,1);vector2_closure(L,"distance_squared",vector4_distance,0);
    const char *component[]={"x","y","z","w"},*set[]={"set_x","set_y","set_z","set_w"};
    for(int i=0;i<4;i++){vector2_closure(L,component[i],vector4_component,i+1);vector2_closure(L,set[i],vector4_set_component,i+1);}
    const char *binary[]={"add","subtract","multiply_elements","divide_elements","min","max"};
    for(int i=0;i<6;i++)vector2_closure(L,binary[i],vector4_binary,i);
    lua_pop(L,2);lua_getfield(L,LUA_REGISTRYINDEX,"LightUserData");
    if(!lua_istable(L,-1))return luaL_error(L,"shared native vector metatable unavailable");
    callback(L,"__index",vector4_common_index);callback(L,"__newindex",vector4_common_newindex);
    vector2_closure(L,"__add",vector4_common_binary,V2_ADD);vector2_closure(L,"__sub",vector4_common_binary,V2_SUB);
    callback(L,"__mul",vector4_common_multiply);callback(L,"__div",vector4_common_divide);callback(L,"__unm",vector4_common_negate);lua_pop(L,1);
    lua_getglobal(L,"tostring");lua_pushcclosure(L,vector4_global_tostring,1);lua_setglobal(L,"tostring");return 0;
}
