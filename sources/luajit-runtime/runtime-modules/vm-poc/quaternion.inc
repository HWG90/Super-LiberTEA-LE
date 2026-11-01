/* Quaternion shares the Vector4 payload (tag 0x58235806) and LightUserData
 * metatable. Every port follows the original float operation order, traced from
 * build 26088801. normalize/inverse/conjugate/dot/lerp/slerp live on a page that
 * is packed on disk; it was traced from a read-only in-game dump instead.
 * slerp and the Euler/look conversions call the game's own CRT and basis
 * helpers, so results stay bit-identical. Matrix conversions raise an explicit
 * error until Matrix4x4 is ported. */
static int quat_identity(lua_State *L){return vector4_push(L,0,0,0,1);}
static int quat_axis_angle_at(lua_State *L,int axis,int angle) {
    HD2NativeVector3 v;vector3_read(L,axis,&v);float h=(float)lua_tonumber(L,angle)*0.5f;
    float s=sinf(h),c=cosf(h);return vector4_push(L,s*v.x,s*v.y,s*v.z,c);
}
static int quat_call(lua_State *L){return quat_axis_angle_at(L,2,3);}
static int quat_axis_angle(lua_State *L){return quat_axis_angle_at(L,1,2);}
static int quat_from_elements(lua_State *L){return vector4_push(L,(float)lua_tonumber(L,1),(float)lua_tonumber(L,2),(float)lua_tonumber(L,3),(float)lua_tonumber(L,4));}
static int quat_multiply(lua_State *L) {
    HD2NativeVector4 a,b;vector4_read(L,1,&a);vector4_read(L,2,&b);
    float x=b.x*a.w+a.x*b.w;x=x+a.y*b.z;x=x-a.z*b.y;
    float y=b.y*a.w+a.y*b.w;y=y+a.z*b.x;y=y-b.z*a.x;
    float z=b.z*a.w+a.z*b.w;z=z+b.y*a.x;z=z-a.y*b.x;
    float w=a.w*b.w-b.x*a.x;w=w-b.y*a.y;w=w-a.z*b.z;
    return vector4_push(L,x,y,z,w);
}
static int quat_norm(lua_State *L) {
    HD2NativeVector4 a;vector4_read(L,1,&a);float v=a.x*a.x+a.y*a.y;v=v+a.z*a.z;v=v+a.w*a.w;
    lua_pushnumber(L,sqrtf(v));return 1;
}
static int quat_conjugate(lua_State *L){HD2NativeVector4 a;vector4_read(L,1,&a);return vector4_push(L,-a.x,-a.y,-a.z,a.w);}
/* Shared tail of normalize, lerp and slerp's near-parallel branch. */
static int quat_push_normalized(lua_State *L,float x,float y,float z,float w) {
    float n=y*y+x*x;n=n+z*z;n=n+w*w;n=sqrtf(n);
    if(n==0)return vector4_push(L,0,0,0,1);
    float r=1.0f/n;return vector4_push(L,x*r,y*r,z*r,w*r);
}
/* A zero quaternion is treated as unit length rather than dividing by zero. */
static int quat_inverse(lua_State *L) {
    HD2NativeVector4 a;vector4_read(L,1,&a);float n=vector4_squared(a);if(n==0)n=1.0f;
    float s=-1.0f/n;return vector4_push(L,a.x*s,a.y*s,a.z*s,a.w*-s);
}
static int quat_normalize(lua_State *L){HD2NativeVector4 a;vector4_read(L,1,&a);return quat_push_normalized(L,a.x,a.y,a.z,a.w);}
static int quat_dot(lua_State *L){HD2NativeVector4 a,b;vector4_read(L,1,&a);vector4_read(L,2,&b);float v=a.x*b.x+a.y*b.y;v=v+a.z*b.z;v=v+a.w*b.w;lua_pushnumber(L,v);return 1;}
/* Linear blend toward b, or toward -a when the quaternions point apart. */
static int quat_blend(lua_State *L,HD2NativeVector4 a,HD2NativeVector4 b,float t) {
    float d=a.x*b.x+b.y*a.y;d=d+b.z*a.z;d=d+b.w*a.w;
    if(0>d)return quat_push_normalized(L,(a.x+b.x)*t-a.x,(b.y+a.y)*t-a.y,(b.z+a.z)*t-a.z,(b.w+a.w)*t-a.w);
    return quat_push_normalized(L,(b.x-a.x)*t+a.x,(b.y-a.y)*t+a.y,(b.z-a.z)*t+a.z,(b.w-a.w)*t+a.w);
}
static int quat_lerp(lua_State *L) {
    HD2NativeVector4 a,b;vector4_read(L,1,&a);vector4_read(L,2,&b);return quat_blend(L,a,b,(float)lua_tonumber(L,3));
}
static float quat_native_unary(lua_State *L,int (*fn)(const HD2VectorHost *,float,float *),float x) {
    float v;if(!fn(&environment(L)->vector_host,x,&v))luaL_error(L,"native trigonometry helper refused");
    return v;
}
/* Shortest path (negating b); |dot| >= 0.95f blends linearly. The weighted sum
 * is divided by sin(theta) last, exactly as the original. */
static int quat_slerp(lua_State *L) {
    HD2NativeVector4 a,b;vector4_read(L,1,&a);vector4_read(L,2,&b);float t=(float)lua_tonumber(L,3);
    float d=a.x*b.x+b.y*a.y;d=d+b.z*a.z;d=d+b.w*a.w;
    if(0>d){d=-d;b.x*=-1.0f;b.y*=-1.0f;b.z*=-1.0f;b.w*=-1.0f;}
    if(!(0.949999988f>d))return quat_blend(L,a,b,t);
    float c=-1.0f>d?-1.0f:d;c=1.0f<c?1.0f:c;
    float th=quat_native_unary(L,hd2quaternion_acosf,c),s=quat_native_unary(L,hd2quaternion_sinf,th);
    float kb=quat_native_unary(L,hd2quaternion_sinf,th*t),ka=quat_native_unary(L,hd2quaternion_sinf,(1.0f-t)*th);
    return vector4_push(L,(a.x*ka+b.x*kb)/s,(a.y*ka+b.y*kb)/s,(a.z*ka+b.z*kb)/s,(a.w*ka+b.w*kb)/s);
}
/* --- traced from build 26088801 disassembly; float order follows the original --- */
static int quat_rotate(lua_State *L) {
    HD2NativeVector4 q;HD2NativeVector3 v;vector4_read(L,1,&q);vector3_read(L,2,&v);
    const float zero=0.0f;float nx=-q.x,ny=-q.y,nz=-q.z;
    float tx=q.w*v.x+q.x*zero;tx=tx+q.y*v.z;tx=tx-v.y*q.z;
    float ty=q.w*v.y+q.y*zero;ty=ty+q.z*v.x;ty=ty-q.x*v.z;
    float tz=q.w*v.z+q.z*zero;tz=tz+q.x*v.y;tz=tz-q.y*v.x;
    float tw=q.w*zero-q.x*v.x;tw=tw-v.y*q.y;tw=tw-v.z*q.z;
    float rx=tw*nx+q.w*tx;rx=rx+ty*nz;rx=rx-tz*ny;
    float ry=tw*ny+q.w*ty;ry=ry+tz*nx;ry=ry-nz*tx;
    float rz=q.w*tz+tw*nz;rz=rz+ny*tx;rz=rz-ty*nx;
    return vector3_push(L,rx,ry,rz);
}
/* forward/up/right: rows of the rotation matrix scaled by 2/|q|^2 (1 when zero). */
static float quat_axis_scale(HD2NativeVector4 q){float n=q.x*q.x+q.y*q.y;n=n+q.z*q.z;n=n+q.w*q.w;return n==0?1.0f:2.0f/n;}
static int quat_forward(lua_State *L) {
    HD2NativeVector4 q;vector4_read(L,1,&q);float s=quat_axis_scale(q),xs=q.x*s,ys=q.y*s,zs=q.z*s;
    return vector3_push(L,q.x*ys-q.w*zs,(1.0f-q.x*xs)-q.z*zs,q.y*zs+q.w*xs);
}
static int quat_up(lua_State *L) {
    HD2NativeVector4 q;vector4_read(L,1,&q);float s=quat_axis_scale(q),xs=q.x*s,ys=q.y*s,zs=q.z*s;
    return vector3_push(L,q.x*zs+q.w*ys,q.y*zs-q.w*xs,(1.0f-q.x*xs)-q.y*ys);
}
static int quat_right(lua_State *L) {
    HD2NativeVector4 q;vector4_read(L,1,&q);float s=quat_axis_scale(q),ys=q.y*s,zs=q.z*s;
    return vector3_push(L,(1.0f-q.y*ys)-q.z*zs,q.x*ys+q.w*zs,q.x*zs-q.w*ys);
}
static float quat_atan2(lua_State *L,float y,float x) {
    float v;if(!hd2quaternion_atan2f(&environment(L)->vector_host,y,x,&v))luaL_error(L,"native atan2f helper refused");
    return v;
}
static float quat_vector_length(HD2NativeVector4 q){float v=q.y*q.y+q.x*q.x;v=v+q.z*q.z;return sqrtf(v);}
static int quat_angle(lua_State *L) {
    HD2NativeVector4 q;vector4_read(L,1,&q);float a=quat_atan2(L,quat_vector_length(q),q.w);
    lua_pushnumber(L,a+a);return 1;
}
static int quat_decompose(lua_State *L) {
    HD2NativeVector4 q;vector4_read(L,1,&q);float s=quat_vector_length(q),a=quat_atan2(L,s,q.w);a=a+a;
    if(s==0)vector3_push(L,1,0,0);else vector3_push(L,q.x/s,q.y/s,q.z/s);
    lua_pushnumber(L,a);return 2;
}
/* Unlike lerp, no shortest-path negation; zero length yields identity. */
static int quat_lerp_wrap(lua_State *L) {
    HD2NativeVector4 a,b;vector4_read(L,1,&a);vector4_read(L,2,&b);float t=(float)lua_tonumber(L,3);
    float x=t*(b.x-a.x)+a.x,y=(b.y-a.y)*t+a.y,z=(b.z-a.z)*t+a.z,w=t*(b.w-a.w)+a.w;
    float n=x*x+y*y;n=n+z*z;n=n+w*w;n=sqrtf(n);
    if(n==0)return vector4_push(L,0,0,0,1);
    float r=1.0f/n;return vector4_push(L,x*r,y*r,z*r,w*r);
}
static int quat_to_euler(lua_State *L) {
    HD2NativeVector4 q;vector4_read(L,1,&q);float x2=q.x*q.x,y2=q.y*q.y,z2=q.z*q.z,w2=q.w*q.w,v;
    float rx=((w2-x2)-y2)+z2,ry=(q.z*q.y-q.x*q.w)*-2.0f;
    lua_pushnumber(L,quat_atan2(L,ry,rx)*180.0f/3.14159274f);
    if(!hd2quaternion_asinf(&environment(L)->vector_host,(q.x*q.z+q.w*q.y)*2.0f,&v))return luaL_error(L,"native asinf helper refused");
    lua_pushnumber(L,v*180.0f/3.14159274f);
    float zx=((x2+w2)-y2)-z2,zy=(q.x*q.y-q.w*q.z)*-2.0f;
    lua_pushnumber(L,quat_atan2(L,zy,zx)*180.0f/3.14159274f);return 3;
}
static int quat_from_euler(lua_State *L) {
    float d[3]={(float)lua_tonumber(L,1),(float)lua_tonumber(L,2),(float)lua_tonumber(L,3)},q[4];
    if(!hd2quaternion_from_euler(&environment(L)->vector_host,d,q))return luaL_error(L,"native Euler helper refused");
    return vector4_push(L,q[0],q[1],q[2],q[3]);
}
/* Orthonormal basis (right, forward, up rows) through the native basis helper. */
static int quat_look(lua_State *L) {
    HD2NativeVector3 d;vector3_read(L,1,&d);float ux=0,uy=0,uz=1;
    if(lua_gettop(L)>=2){HD2NativeVector3 u;vector3_read(L,2,&u);ux=u.x;uy=u.y;uz=u.z;}
    if((d.x==0&&d.y==0&&d.z==0)||(ux==0&&uy==0&&uz==0))return vector4_push(L,0,0,0,1);
    float dx=d.x,dy=d.y,dz=d.z,l=dy*dy+dx*dx;l=sqrtf(l+dz*dz);
    if(0.0001>(double)l)dx=dy=dz=0;else{dx/=l;dy/=l;dz/=l;}
    float dot=dy*uy+dx*ux;dot=dot+dz*uz;ux=ux-dx*dot;uy=uy-dy*dot;uz=uz-dz*dot;
    l=uy*uy+ux*ux;l=sqrtf(l+uz*uz);
    if(0.0001>(double)l)ux=uy=uz=0;else{ux/=l;uy/=l;uz/=l;}
    const float m[16]={uz*dy-uy*dz,ux*dz-uz*dx,uy*dx-ux*dy,0, dx,dy,dz,0, ux,uy,uz,0, 0,0,0,1};float q[4];
    if(!hd2quaternion_from_basis(&environment(L)->vector_host,m,q))return luaL_error(L,"native basis helper refused");
    return vector4_push(L,q[0],q[1],q[2],q[3]);
}
static int quat_registration(lua_State *L,HD2Environment *e) {
    e->quaternion_ready=1;lua_getglobal(L,"stingray");lua_getfield(L,-1,"Quaternion");
    if(!lua_istable(L,-1))return luaL_error(L,"Quaternion table unavailable");
    lua_pushvalue(L,-1);lua_setfield(L,-2,"__index");lua_pushliteral(L,"Quaternion");lua_setfield(L,-2,"_name");
    lua_pushvalue(L,-1);lua_setfield(L,LUA_REGISTRYINDEX,"Quaternion");
    lua_newtable(L);callback(L,"__call",quat_call);lua_setmetatable(L,-2);
    callback(L,"identity",quat_identity);callback(L,"axis_angle",quat_axis_angle);callback(L,"from_elements",quat_from_elements);
    callback(L,"multiply",quat_multiply);callback(L,"norm",quat_norm);callback(L,"negate",vector4_negate);
    callback(L,"equal",vector4_equal);callback(L,"is_valid",vector4_valid);callback(L,"to_elements",vector4_to_elements);
    callback(L,"set_xyzw",vector4_set_xyzw);
    callback(L,"conjugate",quat_conjugate);callback(L,"inverse",quat_inverse);callback(L,"normalize",quat_normalize);
    callback(L,"dot",quat_dot);callback(L,"lerp",quat_lerp);callback(L,"slerp",quat_slerp);
    callback(L,"rotate",quat_rotate);callback(L,"forward",quat_forward);callback(L,"up",quat_up);callback(L,"right",quat_right);
    callback(L,"angle",quat_angle);callback(L,"decompose",quat_decompose);callback(L,"lerp_wrap",quat_lerp_wrap);
    callback(L,"to_euler_angles_xyz",quat_to_euler);callback(L,"from_euler_angles_xyz",quat_from_euler);
    callback(L,"look",quat_look);callback(L,"to_string",vector4_to_string);
    /* Matrix4x4 values require the Matrix4x4 family, which is not ported yet. */
    const char *pending[]={"matrix4x4","from_matrix4x4"};
    for(size_t i=0;i<sizeof(pending)/sizeof(*pending);i++)missing(L,pending[i]);
    lua_pop(L,2);return 0;
}
