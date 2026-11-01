/* QuaternionBox and Matrix4x4Box: LuaJIT-owned persistent userdata with no
 * temporary tag (16 and 64 bytes). The module table is the instance metatable
 * and its own __index, as in the original; there is no __newindex or __len.
 * Traced from build 26088801 (QuaternionBox __call 0x42fc20, store 0x42fee0,
 * unbox 0x430210; Matrix4x4Box __call 0x437290, store 0x437460, unbox 0x437560).
 * The original reads arguments unchecked (any lightuserdata, or a full
 * userdata's payload at a fixed offset); here sources must be native
 * Quaternion/Vector4 or Matrix4x4 temporaries and targets must be boxes. */
typedef struct {float x,y,z,w;} HD2QuaternionBox;
typedef struct {float m[16];} HD2Matrix4x4Box;
_Static_assert(sizeof(HD2QuaternionBox)==16,"QuaternionBox payload layout");
_Static_assert(sizeof(HD2Matrix4x4Box)==64,"Matrix4x4Box payload layout");
static void *box_test(lua_State *L,int index,const char *name,size_t size) {
    if(lua_type(L,index)!=LUA_TUSERDATA||lua_objlen(L,index)!=size||!lua_getmetatable(L,index))return NULL;
    lua_getfield(L,LUA_REGISTRYINDEX,name);
    int same=lua_rawequal(L,-1,-2);lua_pop(L,2);
    return same?lua_touserdata(L,index):NULL;
}
static void *box_check(lua_State *L,int index,const char *name,size_t size) {
    void *b=box_test(L,index,name,size);
    if(!b)luaL_argerror(L,index,lua_pushfstring(L,"%s expected",name));
    return b;
}
static void *box_new(lua_State *L,const char *name,size_t size) {
    void *b=lua_newuserdata(L,size);lua_getfield(L,LUA_REGISTRYINDEX,name);lua_setmetatable(L,-2);return b;
}
/* Argument count includes self (constructor) or the box (store): two copies a
 * Quaternion, five reads four numbers, anything else is identity. */
static HD2QuaternionBox quaternionbox_arguments(lua_State *L) {
    HD2QuaternionBox b={0,0,0,1};int n=lua_gettop(L);
    if(n==2){HD2NativeVector4 q;vector4_read(L,2,&q);b.x=q.x;b.y=q.y;b.z=q.z;b.w=q.w;}
    else if(n==5){b.x=(float)lua_tonumber(L,2);b.y=(float)lua_tonumber(L,3);b.z=(float)lua_tonumber(L,4);b.w=(float)lua_tonumber(L,5);}
    return b;
}
static int quaternionbox_constructor(lua_State *L) {
    HD2QuaternionBox v=quaternionbox_arguments(L);
    *(HD2QuaternionBox *)box_new(L,"QuaternionBox",sizeof(v))=v;return 1;
}
static int quaternionbox_store(lua_State *L) {
    HD2QuaternionBox *b=box_check(L,1,"QuaternionBox",sizeof(*b));*b=quaternionbox_arguments(L);return 0;
}
static int quaternionbox_unbox(lua_State *L) {
    HD2QuaternionBox *b=box_check(L,1,"QuaternionBox",sizeof(*b));return vector4_push(L,b->x,b->y,b->z,b->w);
}
static int matrix4x4box_constructor(lua_State *L) {
    HD2Matrix4x4Box v;memcpy(v.m,matrix_identity_rows,sizeof(v.m));
    if(lua_gettop(L)==2){HD2NativeMatrix4x4 a;matrix_read(L,2,&a);memcpy(v.m,a.m,sizeof(v.m));}
    *(HD2Matrix4x4Box *)box_new(L,"Matrix4x4Box",sizeof(v))=v;return 1;
}
static int matrix4x4box_store(lua_State *L) {
    HD2Matrix4x4Box *b=box_check(L,1,"Matrix4x4Box",sizeof(*b));HD2NativeMatrix4x4 a;matrix_read(L,2,&a);
    memcpy(b->m,a.m,sizeof(b->m));return 0;
}
static int matrix4x4box_unbox(lua_State *L) {
    HD2Matrix4x4Box *b=box_check(L,1,"Matrix4x4Box",sizeof(*b));return matrix_push(L,b->m);
}
static int boxes_global_tostring(lua_State *L) {
    if(lua_gettop(L)) {
        HD2QuaternionBox *q=box_test(L,1,"QuaternionBox",sizeof(*q));
        if(q) {
            char out[128];
            if(!hd2vector4_format(&environment(L)->vector_host,out,q->x,q->y,q->z,q->w))return luaL_error(L,"QuaternionBox formatter refused");
            lua_pushfstring(L,"QuaternionBox%s",out);return 1;
        }
        HD2Matrix4x4Box *m=box_test(L,1,"Matrix4x4Box",sizeof(*m));
        if(m)return matrix_push_long_string(L,"Matrix4x4Box(\n",m->m);
    }
    lua_pushvalue(L,lua_upvalueindex(1));lua_insert(L,1);lua_call(L,lua_gettop(L)-1,LUA_MULTRET);return lua_gettop(L);
}
static int box_registration(lua_State *L,const char *name,lua_CFunction constructor,lua_CFunction store,lua_CFunction unbox) {
    lua_getglobal(L,"stingray");lua_getfield(L,-1,name);
    if(lua_isnil(L,-1)){lua_pop(L,1);lua_newtable(L);lua_pushvalue(L,-1);lua_setfield(L,-3,name);}
    if(!lua_istable(L,-1))return luaL_error(L,"%s table unavailable",name);
    lua_pushstring(L,name);lua_setfield(L,-2,"_name");lua_pushvalue(L,-1);lua_setfield(L,-2,"__index");
    lua_pushvalue(L,-1);lua_setfield(L,LUA_REGISTRYINDEX,name);
    callback(L,"store",store);callback(L,"unbox",unbox);
    lua_newtable(L);callback(L,"__call",constructor);lua_setmetatable(L,-2);lua_pop(L,2);return 0;
}
static int boxes_registration(lua_State *L,HD2Environment *e) {
    box_registration(L,"QuaternionBox",quaternionbox_constructor,quaternionbox_store,quaternionbox_unbox);
    box_registration(L,"Matrix4x4Box",matrix4x4box_constructor,matrix4x4box_store,matrix4x4box_unbox);
    lua_getglobal(L,"tostring");lua_pushcclosure(L,boxes_global_tostring,1);lua_setglobal(L,"tostring");
    e->boxes_ready=1;return 0;
}
