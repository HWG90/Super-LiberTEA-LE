/* Native Vector3 values share the engine pool and lightuserdata metatable. */
typedef struct {uint32_t tag;float x,y,z;} HD2NativeVector3;
_Static_assert(sizeof(HD2NativeVector3)==16,"native Vector3 layout");
static uintptr_t vector3_read(lua_State *L,int index,HD2NativeVector3 *v) {
    HD2Environment *e=environment(L);
    if(!e->vector3_ready||lua_type(L,index)!=LUA_TLIGHTUSERDATA)luaL_argerror(L,index,"native Vector3 expected");
    uintptr_t p=(uintptr_t)lua_touserdata(L,index);
    if(!p||p>UINTPTR_MAX-sizeof(*v)||e->vector_host.read(e->vector_host.context,p,v,sizeof(*v))!=1||v->tag!=0x02b4dab5)
        luaL_argerror(L,index,"unreadable or expired native Vector3");
    return p;
}
static int vector3_push(lua_State *L,float x,float y,float z) {
    HD2Environment *e=environment(L);uintptr_t p=hd2vector3_allocate(&e->vector_host,e->vector_environment);
    HD2NativeVector3 v={0x02b4dab5,x,y,z};
    if(!p||e->vector_host.write(e->vector_host.context,p,&v,sizeof(v))!=1)return luaL_error(L,"native Vector3 allocation or write refused");
    lua_pushlightuserdata(L,(void *)p);return 1;
}
static uint32_t vector_integer(double x) {
    int64_t i=x>=-9223372036854775808.0&&x<9223372036854775808.0?(int64_t)x:INT64_MIN;return (uint32_t)i;
}
static int vector3_constructor(lua_State *L){return vector3_push(L,(float)lua_tonumber(L,2),(float)lua_tonumber(L,3),(float)lua_tonumber(L,4));}
static int vector3_constant(lua_State *L) {
    int i=(int)lua_tointeger(L,lua_upvalueindex(1));
    return vector3_push(L,i==1?1:i==-1?-1:0,i==2?1:i==-2?-1:0,i==3?1:i==-3?-1:0);
}
static int vector3_base(lua_State *L){uint32_t i=vector_integer(lua_tonumber(L,1));return vector3_push(L,i==1?1:0,i==2?1:0,i==3?1:0);}
static int vector3_equal(lua_State *L){HD2NativeVector3 a,b;vector3_read(L,1,&a);vector3_read(L,2,&b);lua_pushboolean(L,a.x==b.x&&a.y==b.y&&a.z==b.z);return 1;}
static int vector3_valid(lua_State *L){HD2NativeVector3 a;vector3_read(L,1,&a);lua_pushboolean(L,a.x>-FLT_MAX&&a.x<FLT_MAX&&a.y>-FLT_MAX&&a.y<FLT_MAX&&a.z>-FLT_MAX&&a.z<FLT_MAX);return 1;}
static int vector3_binary(lua_State *L) {
    HD2NativeVector3 a,b;vector3_read(L,1,&a);vector3_read(L,2,&b);
    float av[3]={a.x,a.y,a.z},bv[3]={b.x,b.y,b.z},out[3]={0};
    for(int i=0;i<3;i++)switch(lua_tointeger(L,lua_upvalueindex(1))) {
        case V2_ADD:out[i]=av[i]+bv[i];break;
        case V2_SUB:out[i]=av[i]-bv[i];break;
        case V2_MUL_ELEMENTS:out[i]=av[i]*bv[i];break;
        case V2_DIV_ELEMENTS:out[i]=av[i]/bv[i];break;
        case V2_MIN:out[i]=av[i]<bv[i]?av[i]:bv[i];break;
        case V2_MAX:out[i]=av[i]>bv[i]?av[i]:bv[i];break;
    }
    return vector3_push(L,out[0],out[1],out[2]);
}
static int vector3_multiply(lua_State *L){HD2NativeVector3 a;vector3_read(L,1,&a);float s=(float)lua_tonumber(L,2);return vector3_push(L,a.x*s,a.y*s,a.z*s);}
static int vector3_divide(lua_State *L){HD2NativeVector3 a;vector3_read(L,1,&a);float s=(float)lua_tonumber(L,2);return vector3_push(L,a.x/s,a.y/s,a.z/s);}
static int vector3_meta_multiply(lua_State *L) {
    if(lua_type(L,1)!=LUA_TLIGHTUSERDATA){lua_pushvalue(L,1);lua_pushvalue(L,2);lua_replace(L,1);lua_replace(L,2);}
    return vector3_multiply(L);
}
static int vector3_negate(lua_State *L){HD2NativeVector3 a;vector3_read(L,1,&a);return vector3_push(L,-a.x,-a.y,-a.z);}
static float vector3_squared(HD2NativeVector3 a){float v=a.x*a.x+a.y*a.y;return v+a.z*a.z;}
static int vector3_length(lua_State *L){HD2NativeVector3 a;vector3_read(L,1,&a);float v=vector3_squared(a);lua_pushnumber(L,lua_tointeger(L,lua_upvalueindex(1))?sqrtf(v):v);return 1;}
static int vector3_normalize(lua_State *L) {
    HD2NativeVector3 a;vector3_read(L,1,&a);float len=sqrtf(vector3_squared(a));
    return (double)len<0.0001?vector3_push(L,0,0,0):vector3_push(L,a.x/len,a.y/len,a.z/len);
}
static int vector3_dot(lua_State *L){HD2NativeVector3 a,b;vector3_read(L,1,&a);vector3_read(L,2,&b);float v=b.y*a.y+b.x*a.x;v=v+b.z*a.z;lua_pushnumber(L,v);return 1;}
static int vector3_cross(lua_State *L) {
    HD2NativeVector3 a,b;vector3_read(L,1,&a);vector3_read(L,2,&b);
    return vector3_push(L,a.y*b.z-a.z*b.y,b.x*a.z-a.x*b.z,a.x*b.y-b.x*a.y);
}
static int vector3_distance(lua_State *L) {
    HD2NativeVector3 a,b;vector3_read(L,1,&a);vector3_read(L,2,&b);
    float x=a.x-b.x,y=a.y-b.y,z=a.z-b.z;int option=(int)lua_tointeger(L,lua_upvalueindex(1));
    float v=option==0?x*x+y*y:y*y+x*x;if(option!=2)v=v+z*z;
    lua_pushnumber(L,option==1?sqrtf(v):v);return 1;
}
static int vector3_lerp(lua_State *L) {
    HD2NativeVector3 a,b;vector3_read(L,1,&a);vector3_read(L,2,&b);float s=(float)lua_tonumber(L,3),r=1.0f-s;
    return vector3_push(L,r*a.x+s*b.x,r*a.y+s*b.y,r*a.z+s*b.z);
}
static int vector3_make_axes(lua_State *L) {
    HD2NativeVector3 a;vector3_read(L,1,&a);float x,y,z,d;
    if(a.z>-0.5f&&a.z<0.5f) {
        x=-a.y;y=a.x;z=0;
        d=a.x*a.y+x*a.x;d=d+a.z*0.0f;
        x=x-a.x*d;y=y-a.y*d;z=z-a.z*d;
    }else{
        x=0;y=a.z;z=-a.y;
        d=a.y*a.z+a.x*0.0f;d=d+z*a.z;
        x=x-a.x*d;y=y-a.y*d;z=z-a.z*d;
    }
    float squared=y*y+x*x;squared=squared+z*z;float len=sqrtf(squared);
    if((double)len<0.0001){x=0;y=0;z=0;}else{x=x/len;y=y/len;z=z/len;}
    float bx=a.y*z-a.z*y,by=a.z*x-a.x*z,bz=a.x*y-a.y*x;
    vector3_push(L,x,y,z);vector3_push(L,bx,by,bz);return 2;
}
static float vector3_component_value(HD2NativeVector3 a,int component){return component==1?a.x:component==2?a.y:a.z;}
static int vector3_to_elements(lua_State *L){HD2NativeVector3 a;vector3_read(L,1,&a);lua_pushnumber(L,a.x);lua_pushnumber(L,a.y);lua_pushnumber(L,a.z);return 3;}
static int vector3_component(lua_State *L){HD2NativeVector3 a;vector3_read(L,1,&a);lua_pushnumber(L,vector3_component_value(a,(int)lua_tointeger(L,lua_upvalueindex(1))));return 1;}
static int vector3_element_index(lua_State *L,int index){double x=lua_tonumber(L,index);if(x>=1&&x<4)return (int)x;return luaL_argerror(L,index,"Vector3 element must be 1, 2 or 3");}
static int vector3_element(lua_State *L){HD2NativeVector3 a;vector3_read(L,1,&a);lua_pushnumber(L,vector3_component_value(a,vector3_element_index(L,2)));return 1;}
static int vector3_set_at(lua_State *L,int component,int value) {
    HD2NativeVector3 a;uintptr_t p=vector3_read(L,1,&a);HD2Environment *e=environment(L);float v=(float)lua_tonumber(L,value);
    if(e->vector_host.write(e->vector_host.context,p+(uintptr_t)component*4,&v,4)!=1)return luaL_error(L,"Vector3 write refused");
    return 0;
}
static int vector3_set_component(lua_State *L){return vector3_set_at(L,(int)lua_tointeger(L,lua_upvalueindex(1)),2);}
static int vector3_set_element(lua_State *L){return vector3_set_at(L,vector3_element_index(L,2),3);}
static int vector3_set_xyz(lua_State *L){vector3_set_at(L,1,2);vector3_set_at(L,2,3);return vector3_set_at(L,3,4);}
static int vector3_to_string(lua_State *L) {
    HD2NativeVector3 a;vector3_read(L,1,&a);HD2Environment *e=environment(L);char out[128];
    if(!hd2vector3_format(&e->vector_host,out,a.x,a.y,a.z))return luaL_error(L,"Vector3 formatter refused");
    lua_pushstring(L,out);return 1;
}
static int vector3_meta_component(lua_State *L) {
    if(lua_type(L,2)==LUA_TSTRING){const char *s=lua_tostring(L,2);return s[0]=='x'?1:s[0]=='y'?2:s[0]=='z'?3:0;}
    if(lua_type(L,2)==LUA_TNUMBER){uint32_t i=vector_integer(lua_tonumber(L,2));return i>=1&&i<=3?(int)i:0;}
    return 0;
}
static int vector3_meta_index(lua_State *L){HD2NativeVector3 a;vector3_read(L,1,&a);int c=vector3_meta_component(L);if(c)lua_pushnumber(L,vector3_component_value(a,c));else lua_pushnil(L);return 1;}
static int vector3_meta_newindex(lua_State *L){HD2NativeVector3 a;vector3_read(L,1,&a);int c=vector3_meta_component(L);return c?vector3_set_at(L,c,3):0;}
static int vector_kind(lua_State *L,int index) {
    HD2Environment *e=environment(L);uint32_t tag;uintptr_t p=(uintptr_t)lua_touserdata(L,index);
    if(lua_type(L,index)!=LUA_TLIGHTUSERDATA||!p||p>UINTPTR_MAX-4||e->vector_host.read(e->vector_host.context,p,&tag,4)!=1)return 0;
    return tag==0x7796c581?2:tag==0x02b4dab5?3:tag==0x58235806?4:0;
}
static int vector_common_binary(lua_State *L){return vector_kind(L,1)==3?vector3_binary(L):vector2_binary(L);}
static int vector_common_multiply(lua_State *L){int k=vector_kind(L,1);if(!k)k=vector_kind(L,2);return k==3?vector3_meta_multiply(L):vector2_meta_multiply(L);}
static int vector_common_divide(lua_State *L){return vector_kind(L,1)==3?vector3_divide(L):vector2_divide(L);}
static int vector_common_negate(lua_State *L){return vector_kind(L,1)==3?vector3_negate(L):vector2_negate(L);}
static int vector_common_index(lua_State *L){return vector_kind(L,1)==3?vector3_meta_index(L):vector2_meta_index(L);}
static int vector_common_newindex(lua_State *L){return vector_kind(L,1)==3?vector3_meta_newindex(L):vector2_meta_newindex(L);}
static int vector3_global_tostring(lua_State *L) {
    if(!lua_gettop(L)){lua_pushvalue(L,lua_upvalueindex(1));lua_call(L,0,1);return 1;}
    if(vector_kind(L,1)==3){vector3_to_string(L);lua_pushfstring(L,"Vector3%s",lua_tostring(L,-1));return 1;}
    lua_pushvalue(L,lua_upvalueindex(1));lua_pushvalue(L,1);lua_call(L,1,1);return 1;
}
static int vector3_registration(lua_State *L,HD2Environment *e) {
    e->vector3_ready=1;lua_getglobal(L,"stingray");lua_getfield(L,-1,"Vector3");
    if(!lua_istable(L,-1))return luaL_error(L,"Vector3 table unavailable");
    lua_pushvalue(L,-1);lua_setfield(L,-2,"__index");lua_pushliteral(L,"Vector3");lua_setfield(L,-2,"_name");
    lua_pushvalue(L,-1);lua_setfield(L,LUA_REGISTRYINDEX,"Vector3");
    lua_newtable(L);callback(L,"__call",vector3_constructor);lua_setmetatable(L,-2);
    callback(L,"base",vector3_base);callback(L,"equal",vector3_equal);callback(L,"is_valid",vector3_valid);
    callback(L,"multiply",vector3_multiply);callback(L,"divide",vector3_divide);callback(L,"lerp",vector3_lerp);
    callback(L,"normalize",vector3_normalize);callback(L,"dot",vector3_dot);callback(L,"cross",vector3_cross);callback(L,"make_axes",vector3_make_axes);
    callback(L,"to_elements",vector3_to_elements);callback(L,"to_string",vector3_to_string);callback(L,"element",vector3_element);
    callback(L,"set_element",vector3_set_element);callback(L,"set_xyz",vector3_set_xyz);
    vector2_closure(L,"length",vector3_length,1);vector2_closure(L,"length_squared",vector3_length,0);
    vector2_closure(L,"distance",vector3_distance,1);vector2_closure(L,"distance_squared",vector3_distance,0);vector2_closure(L,"distance_xy_squared",vector3_distance,2);
    const char *component[]={"x","y","z"},*set[]={"set_x","set_y","set_z"};
    for(int i=0;i<3;i++){vector2_closure(L,component[i],vector3_component,i+1);vector2_closure(L,set[i],vector3_set_component,i+1);}
    const char *binary[]={"add","subtract","multiply_elements","divide_elements","min","max"};
    for(int i=0;i<6;i++)vector2_closure(L,binary[i],vector3_binary,i);
    const char *constants[]={"zero","right","forward","up","left","backward","down","x_axis","y_axis","z_axis"};
    const int options[]={0,1,2,3,-1,-2,-3,1,2,3};
    for(int i=0;i<10;i++)vector2_closure(L,constants[i],vector3_constant,options[i]);
    lua_pop(L,2);
    lua_getfield(L,LUA_REGISTRYINDEX,"LightUserData");
    if(!lua_istable(L,-1))return luaL_error(L,"shared native vector metatable unavailable");
    callback(L,"__index",vector_common_index);callback(L,"__newindex",vector_common_newindex);
    vector2_closure(L,"__add",vector_common_binary,V2_ADD);vector2_closure(L,"__sub",vector_common_binary,V2_SUB);
    callback(L,"__mul",vector_common_multiply);callback(L,"__div",vector_common_divide);callback(L,"__unm",vector_common_negate);lua_pop(L,1);
    lua_getglobal(L,"tostring");lua_pushcclosure(L,vector3_global_tostring,1);lua_setglobal(L,"tostring");return 0;
}
