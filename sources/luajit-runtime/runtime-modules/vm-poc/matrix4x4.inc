/* Matrix4x4: tag 0x7fd2e074, then 16 row-major floats. Rows are x/right,
 * y/forward, z/up and translation. Values share the temporary pool and
 * LightUserData metatable with the vectors. Traced from build 26088801.
 * rotation/scale/set_scale bodies are mechanical one-operation-per-statement
 * translations of the original SSE (x<n> = xmm<n>, s_<off> = stack slot).
 * multiply is a lane-tracked translation (packing resolved mechanically).
 * Index arguments are range-checked: the original reads/writes unchecked.
 * Known gap: the original LightUserData metamethods treat a Matrix4x4 by its
 * leading floats (m.x reads m00, -m yields a Vector4); here they are refused. */
typedef struct {uint32_t tag;float m[16];} HD2NativeMatrix4x4;
_Static_assert(sizeof(HD2NativeMatrix4x4)==68,"native Matrix4x4 layout");
static uintptr_t matrix_read(lua_State *L,int index,HD2NativeMatrix4x4 *v) {
    HD2Environment *e=environment(L);
    if(!e->matrix4x4_ready||lua_type(L,index)!=LUA_TLIGHTUSERDATA)luaL_argerror(L,index,"native Matrix4x4 expected");
    uintptr_t p=(uintptr_t)lua_touserdata(L,index);
    if(!p||p>UINTPTR_MAX-sizeof(*v)||e->vector_host.read(e->vector_host.context,p,v,sizeof(*v))!=1||v->tag!=0x7fd2e074)
        luaL_argerror(L,index,"unreadable or expired native Matrix4x4");
    return p;
}
static int matrix_push(lua_State *L,const float m[16]) {
    HD2Environment *e=environment(L);uintptr_t p=hd2matrix4x4_allocate(&e->vector_host,e->vector_environment);
    HD2NativeMatrix4x4 v={0x7fd2e074,{0}};memcpy(v.m,m,sizeof(v.m));
    if(!p||e->vector_host.write(e->vector_host.context,p,&v,sizeof(v))!=1)return luaL_error(L,"native Matrix4x4 allocation or write refused");
    lua_pushlightuserdata(L,(void *)p);return 1;
}
static int matrix_write(lua_State *L,uintptr_t p,const HD2NativeMatrix4x4 *v) {
    HD2Environment *e=environment(L);
    if(e->vector_host.write(e->vector_host.context,p,v,sizeof(*v))!=1)return luaL_error(L,"Matrix4x4 write refused");
    return 0;
}
static const float matrix_identity_rows[16]={1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};
static int matrix_call(lua_State *L) {
    float m[16];
    for(int r=0;r<4;r++){for(int c=0;c<3;c++)m[r*4+c]=(float)lua_tonumber(L,2+r*3+c);m[r*4+3]=r==3?1.0f:0.0f;}
    return matrix_push(L,m);
}
static int matrix_zero(lua_State *L){const float m[16]={0};return matrix_push(L,m);}
static int matrix_identity(lua_State *L){return matrix_push(L,matrix_identity_rows);}
static int matrix_from_translation(lua_State *L) {
    HD2NativeVector3 v;vector3_read(L,1,&v);float m[16];memcpy(m,matrix_identity_rows,sizeof(m));
    m[12]=v.x;m[13]=v.y;m[14]=v.z;return matrix_push(L,m);
}
static int matrix_copy(lua_State *L){HD2NativeMatrix4x4 a;matrix_read(L,1,&a);return matrix_push(L,a.m);}
static int matrix_equal(lua_State *L) {
    HD2NativeMatrix4x4 a,b;matrix_read(L,2,&b);matrix_read(L,1,&a);int same=1;
    for(int i=0;i<16&&same;i++)same=b.m[i]==a.m[i];
    lua_pushboolean(L,same);return 1;
}
static int matrix_valid(lua_State *L) {
    HD2NativeMatrix4x4 a;matrix_read(L,1,&a);int ok=1;
    for(int i=0;i<16&&ok;i++)ok=a.m[i]==a.m[i]&&a.m[i]<FLT_MAX&&a.m[i]>-FLT_MAX;
    lua_pushboolean(L,ok);return 1;
}
/* The original body is `xor eax,eax; ret`: it returns no values. */
static int matrix_valid_for_physics(lua_State *L){(void)L;return 0;}
static int matrix_row(lua_State *L) {
    HD2NativeMatrix4x4 a;matrix_read(L,1,&a);int r=(int)lua_tointeger(L,lua_upvalueindex(1));
    return vector3_push(L,a.m[r*4],a.m[r*4+1],a.m[r*4+2]);
}
static int matrix_set_row_at(lua_State *L,int r,int value) {
    HD2NativeVector3 v;vector3_read(L,value,&v);HD2NativeMatrix4x4 a;uintptr_t p=matrix_read(L,1,&a);
    a.m[r*4]=v.x;a.m[r*4+1]=v.y;a.m[r*4+2]=v.z;return matrix_write(L,p,&a);
}
static int matrix_set_row(lua_State *L){return matrix_set_row_at(L,(int)lua_tointeger(L,lua_upvalueindex(1)),2);}
static int matrix_index(lua_State *L,int at) {
    double x=lua_tonumber(L,at);if(x>=1&&x<5)return (int)x-1;
    return luaL_argerror(L,at,"Matrix4x4 index must be 1, 2, 3 or 4");
}
static int matrix_axis(lua_State *L){int r=matrix_index(L,2);HD2NativeMatrix4x4 a;matrix_read(L,1,&a);return vector3_push(L,a.m[r*4],a.m[r*4+1],a.m[r*4+2]);}
static int matrix_set_axis(lua_State *L){return matrix_set_row_at(L,matrix_index(L,2),3);}
static int matrix_element(lua_State *L) {
    int r=matrix_index(L,2),c=matrix_index(L,3);HD2NativeMatrix4x4 a;matrix_read(L,1,&a);
    lua_pushnumber(L,a.m[r*4+c]);return 1;
}
static int matrix_set_element(lua_State *L) {
    float v=(float)lua_tonumber(L,4);int r=matrix_index(L,2),c=matrix_index(L,3);HD2NativeMatrix4x4 a;uintptr_t p=matrix_read(L,1,&a);
    a.m[r*4+c]=v;return matrix_write(L,p,&a);
}
/* v * M as a row vector; the translation row is added unless upvalue is 0. */
static int matrix_transform(lua_State *L) {
    HD2NativeMatrix4x4 a;HD2NativeVector3 v;matrix_read(L,1,&a);vector3_read(L,2,&v);const float *m=a.m;
    float x=v.y*m[4]+v.x*m[0];x=x+v.z*m[8];
    float y=v.x*m[1]+v.y*m[5];y=y+v.z*m[9];
    float z=v.x*m[2]+v.y*m[6];z=z+v.z*m[10];
    if(lua_tointeger(L,lua_upvalueindex(1))){x=x+m[12];y=y+m[13];z=z+m[14];}
    return vector3_push(L,x,y,z);
}
static int matrix_inverse(lua_State *L) {
    HD2NativeMatrix4x4 a;matrix_read(L,1,&a);float r[16];
    if(!hd2matrix4x4_inverse(&environment(L)->vector_host,a.m,r))return luaL_error(L,"native Matrix4x4 inverse helper refused");
    return matrix_push(L,r);
}
static int matrix_rotation(lua_State *L) {
    HD2NativeMatrix4x4 a;matrix_read(L,1,&a);float q[4];
    if(!hd2matrix4x4_rotation(&environment(L)->vector_host,a.m,q))return luaL_error(L,"native Matrix4x4 rotation helper refused");
    return vector4_push(L,q[0],q[1],q[2],q[3]);
}
/* Rotation rows from a quaternion (Quaternion.matrix4x4 0x434aa9..0x434bd4,
 * identical terms in Matrix4x4.set_rotation): rows 0..2, fourth column zero. */
static void matrix_rotation_rows(const float Q[4],float out[12]) {
    __attribute__((unused)) float x0,x1,x2,x3,x4,x5,x6,x7,x8,x9,x10,x11,x12,x13,x14,x15;
    x13=Q[1];
    x10=Q[0];
    x0=x13;
    x14=Q[2];
    x2=x10;
    x9=Q[3];
    x1=x14;
    x15=1.0f;
    x2=x2*x10;
    x0=x0*x13;
    x1=x1*x14;
    x2=x2+x0;
    x0=x9;
    x0=x0*x9;
    x2=x2+x1;
    x1=0.0f;
    x2=x2+x0;
    if(x2==0)x3=x15;else{x3=2.0f;x3=x3/x2;}
    x4=x10;
    x0=x13;
    x4=x4*x3;
    x0=x0*x3;
    x11=x10;
    x12=x10;
    x5=x9;
    x2=x13;
    x10=x10*x4;
    x2=x2*x0;
    x1=x14;
    x1=x1*x3;
    x6=x15;
    x3=x9;
    x11=x11*x0;
    x15=x15-x10;
    x3=x3*x0;
    x9=x9*x1;
    x6=x6-x2;
    x12=x12*x1;
    x7=x11;
    x13=x13*x1;
    x7=x7+x9;
    x14=x14*x1;
    x11=x11-x9;
    x5=x5*x4;
    x0=0.0f;
    x9=x15;
    x8=x12;
    x10=x13;
    x6=x6-x14;
    x9=x9-x14;
    x8=x8-x3;
    x10=x10+x5;
    x12=x12+x3;
    x13=x13-x5;
    x15=x15-x2;
    const float rows[12]={x6,x7,x8,0, x11,x9,x10,0, x12,x13,x15,0};memcpy(out,rows,sizeof(rows));
}
static int matrix_from_quaternion_rows(lua_State *L) {
    HD2NativeVector4 q;vector4_read(L,1,&q);const float Q[4]={q.x,q.y,q.z,q.w};float m[16];
    matrix_rotation_rows(Q,m);m[12]=0;m[13]=0;m[14]=0;m[15]=1;return matrix_push(L,m);
}
/* Rotation replaced, translation kept, m33 forced to 1; any scale is dropped. */
static int matrix_set_rotation(lua_State *L) {
    HD2NativeVector4 q;HD2NativeMatrix4x4 a;uintptr_t p=matrix_read(L,1,&a);vector4_read(L,2,&q);
    const float Q[4]={q.x,q.y,q.z,q.w};matrix_rotation_rows(Q,a.m);a.m[15]=1.0f;return matrix_write(L,p,&a);
}
/* Signed axis lengths: negated when the 4x4 determinant is negative (0x43bf33..0x43c30f). */
static int matrix_scale(lua_State *L) {
    HD2NativeMatrix4x4 a;matrix_read(L,1,&a);const float *M=a.m;
    __attribute__((unused)) float s_20,s_24,s_28,s_30,s_34,s_38,s_110,s_118,s_120,s_128,x0,x1,x2,x3,x4,x5,x6,x7,x8,x9,x10,x11,x12,x13,x14,x15;
    x0=M[0];
    x12=M[1];
    x2=x0;
    x11=M[2];
    x2=x2*x0;
    x1=x11;
    x0=x12;
    x1=x1*x11;
    x0=x0*x12;
    s_110=x12;
    x2=x2+x0;
    x0=0.0f;
    x2=x2+x1;
    x7=0.0f;
    x7=sqrtf(x2);
    x8=M[4];
    x0=0.0f;
    x1=M[5];
    x3=x8;
    x2=M[6];
    x3=x3*x8;
    x1=x1*x1;
    x2=x2*x2;
    x3=x3+x1;
    s_118=x7;
    x3=x3+x2;
    x6=0.0f;
    x6=sqrtf(x3);
    x0=M[8];
    x1=M[9];
    x3=x0;
    x2=M[10];
    x3=x3*x0;
    x0=0.0f;
    x1=x1*x1;
    x2=x2*x2;
    x3=x3+x1;
    s_120=x6;
    x3=x3+x2;
    x0=0.0f;
    x0=sqrtf(x3);
    x2=M[12];
    x1=M[6];
    x15=M[5];
    x14=x1;
    x9=M[3];
    x13=x15;
    x10=M[7];
    x3=x9;
    x5=M[13];
    x4=x10;
    x3=x3*x1;
    x1=x1*M[0];
    s_128=x0;
    s_38=x0;
    x0=M[9];
    s_20=x1;
    x1=M[4];
    x1=x1*s_110;
    x4=x4*x11;
    s_34=x6;
    x6=x15;
    x15=x15*M[0];
    s_24=x1;
    x1=x0;
    x1=x1*x3;
    x0=x0*x4;
    x1=x1*x2;
    x0=x0*x2;
    x6=x6*x9;
    x1=x1-x0;
    s_30=x7;
    x7=x10;
    x14=x14*x12;
    x10=x10*M[0];
    x7=x7*x12;
    x12=x8;
    x12=x12*M[2];
    s_110=x1;
    x0=s_110;
    x1=M[10];
    x1=x1*x6;
    x13=x13*x11;
    x11=M[11];
    x1=x1*x2;
    x9=x9*x8;
    x8=M[14];
    x0=x0-x1;
    s_28=x15;
    x15=M[15];
    s_110=x0;
    x1=s_110;
    x0=M[10];
    x0=x0*x7;
    x0=x0*x2;
    x1=x1+x0;
    s_110=x1;
    x1=x11;
    x0=s_110;
    x1=x1*x13;
    x1=x1*x2;
    x0=x0+x1;
    s_110=x0;
    x0=x11;
    x0=x0*x14;
    x0=x0*x2;
    x2=s_110;
    x2=x2-x0;
    x0=M[8];
    x1=x0;
    x0=x0*x4;
    x1=x1*x3;
    x0=x0*x5;
    x1=x1*x5;
    x2=x2-x1;
    x2=x2+x0;
    x0=M[10];
    x1=x0;
    x0=x0*x10;
    x1=x1*x9;
    x1=x1*x5;
    x2=x2+x1;
    x3=M[9];
    x1=x11;
    x0=x0*x5;
    x1=x1*x12;
    x2=x2-x0;
    x0=x11;
    x0=x0*s_20;
    x1=x1*x5;
    x0=x0*x5;
    x2=x2-x1;
    x1=M[8];
    x1=x1*x6;
    x6=M[8];
    x2=x2+x0;
    x1=x1*x8;
    x0=x6;
    x0=x0*x7;
    x2=x2+x1;
    x1=x3;
    x1=x1*x9;
    x0=x0*x8;
    x1=x1*x8;
    x2=x2-x0;
    x0=x3;
    x0=x0*x10;
    x2=x2-x1;
    x0=x0*x8;
    x1=x11;
    x11=x11*s_28;
    x1=x1*s_24;
    x2=x2+x0;
    x0=x6;
    x11=x11*x8;
    x0=x0*x13;
    x1=x1*x8;
    x0=x0*x15;
    x2=x2+x1;
    x6=x6*x14;
    x1=M[10];
    x6=x6*x15;
    x2=x2-x11;
    x2=x2-x0;
    x0=x3;
    x3=x3*s_20;
    x0=x0*x12;
    x2=x2+x6;
    x3=x3*x15;
    x0=x0*x15;
    x2=x2+x0;
    x0=x1;
    x0=x0*s_24;
    x1=x1*s_28;
    x2=x2-x3;
    x0=x0*x15;
    x1=x1*x15;
    x2=x2-x0;
    x0=0.0f;
    x2=x2+x1;
    if(0.0f>x2){x3=s_118;x2=s_120;x3=-x3;x1=s_128;x2=-x2;x1=-x1;s_30=x3;s_34=x2;s_38=x1;}
    return vector3_push(L,s_30,s_34,s_38);
}
/* Rescales rows 0..2 in place by v[i]/signed length (0x43c469..0x43c931). */
static int matrix_set_scale(lua_State *L) {
    HD2NativeVector3 v;vector3_read(L,2,&v);HD2NativeMatrix4x4 a;uintptr_t p=matrix_read(L,1,&a);
    float *M=a.m;const float V[3]={v.x,v.y,v.z};
    __attribute__((unused)) float s_20,s_24,s_28,s_2c,s_30,s_34,s_100,s_108,s_110,s_118,x0,x1,x2,x3,x4,x5,x6,x7,x8,x9,x10,x11,x12,x13,x14,x15;
    x12=M[1];
    x8=M[0];
    x0=x12;
    x11=M[2];
    x2=x8;
    x2=x2*x8;
    x1=x11;
    x0=x0*x12;
    x1=x1*x11;
    x2=x2+x0;
    s_24=x12;
    x0=0.0f;
    s_20=x8;
    s_28=x11;
    x2=x2+x1;
    x4=0.0f;
    x4=sqrtf(x2);
    s_108=x4;
    x0=M[4];
    x1=M[5];
    x3=x0;
    x2=M[6];
    x3=x3*x0;
    x0=0.0f;
    x1=x1*x1;
    x2=x2*x2;
    x3=x3+x1;
    x3=x3+x2;
    x4=0.0f;
    x4=sqrtf(x3);
    s_110=x4;
    x0=M[8];
    x1=M[9];
    x3=x0;
    x2=M[10];
    x3=x3*x0;
    x0=0.0f;
    x1=x1*x1;
    x2=x2*x2;
    x3=x3+x1;
    x3=x3+x2;
    x0=0.0f;
    x0=sqrtf(x3);
    x2=M[12];
    x1=M[6];
    x15=M[5];
    x14=x1;
    x9=M[3];
    x6=x15;
    x10=M[7];
    x3=x9;
    x5=M[13];
    x4=x10;
    x3=x3*x1;
    x13=x15;
    x15=x15*s_20;
    x7=x10;
    x1=x1*x8;
    s_118=x0;
    x0=M[9];
    s_2c=x1;
    x1=M[4];
    x1=x1*s_24;
    x4=x4*x11;
    s_30=x1;
    x1=x0;
    x1=x1*x3;
    x0=x0*x4;
    x1=x1*x2;
    x0=x0*x2;
    x7=x7*x12;
    x1=x1-x0;
    x6=x6*x9;
    x14=x14*x12;
    x12=M[4];
    s_100=x1;
    x0=s_100;
    x1=M[10];
    x1=x1*x6;
    x13=x13*x11;
    x11=M[11];
    x1=x1*x2;
    x9=x9*x12;
    x12=x12*s_28;
    x0=x0-x1;
    x10=x10*x8;
    x8=M[14];
    s_100=x0;
    x1=s_100;
    x0=M[10];
    x0=x0*x7;
    s_34=x15;
    x15=M[15];
    x0=x0*x2;
    x1=x1+x0;
    s_100=x1;
    x1=x11;
    x0=s_100;
    x1=x1*x13;
    x1=x1*x2;
    x0=x0+x1;
    s_100=x0;
    x0=x11;
    x0=x0*x14;
    x0=x0*x2;
    x2=s_100;
    x2=x2-x0;
    x0=M[8];
    x1=x0;
    x0=x0*x4;
    x1=x1*x3;
    x0=x0*x5;
    x1=x1*x5;
    x2=x2-x1;
    x2=x2+x0;
    x0=M[10];
    x1=x0;
    x0=x0*x10;
    x1=x1*x9;
    x0=x0*x5;
    x1=x1*x5;
    x2=x2+x1;
    x1=x11;
    x2=x2-x0;
    x3=M[9];
    x0=x11;
    x0=x0*s_2c;
    x1=x1*x12;
    x0=x0*x5;
    x1=x1*x5;
    x2=x2-x1;
    x1=M[8];
    x1=x1*x6;
    x6=M[8];
    x2=x2+x0;
    x1=x1*x8;
    x0=x6;
    x0=x0*x7;
    x2=x2+x1;
    x1=x3;
    x1=x1*x9;
    x0=x0*x8;
    x1=x1*x8;
    x2=x2-x0;
    x0=x3;
    x0=x0*x10;
    x2=x2-x1;
    x0=x0*x8;
    x1=x11;
    x11=x11*s_34;
    x1=x1*s_30;
    x2=x2+x0;
    x0=x6;
    x11=x11*x8;
    x0=x0*x13;
    x1=x1*x8;
    x0=x0*x15;
    x2=x2+x1;
    x6=x6*x14;
    x1=M[10];
    x6=x6*x15;
    x2=x2-x11;
    x2=x2-x0;
    x0=x3;
    x3=x3*s_2c;
    x0=x0*x12;
    x2=x2+x6;
    x3=x3*x15;
    x0=x0*x15;
    x2=x2+x0;
    x0=x1;
    x0=x0*s_30;
    x1=x1*s_34;
    x2=x2-x3;
    x0=x0*x15;
    x1=x1*x15;
    x2=x2-x0;
    x0=0.0f;
    x2=x2+x1;
    if(0.0f>x2){x1=s_108;x1=-x1;s_108=x1;x1=s_110;x1=-x1;s_110=x1;x1=s_118;x1=-x1;s_118=x1;}
    x0=V[0];
    x0=x0/s_108;
    x1=s_20;
    x1=x1*x0;
    M[0]=x1;
    x1=s_24;
    x1=x1*x0;
    M[1]=x1;
    x1=s_28;
    x1=x1*x0;
    M[2]=x1;
    x2=V[1];
    x2=x2/s_110;
    x0=x2;
    x1=x2;
    x0=x0*M[4];
    x1=x1*M[5];
    x2=x2*M[6];
    M[4]=x0;
    M[5]=x1;
    M[6]=x2;
    x3=V[2];
    x3=x3/s_118;
    x0=x3;
    x1=x3;
    x0=x0*M[8];
    x1=x1*M[9];
    x3=x3*M[10];
    M[8]=x0;
    M[9]=x1;
    M[10]=x3;
    return matrix_write(L,p,&a);
}
/* A*B for row vectors (multiply 0x439f20, lane-tracked translation of the original). */
static void matrix_multiply_rows(const float *A,const float *B,float o[16]) {
 float t1=A[2]*B[8];
 float t2=A[0]*B[0];
 float t3=A[1]*B[4];
 float t4=t2+t3;
 float t5=A[3]*B[12];
 float t6=t4+t1;
 float t7=B[9]*A[2];
 float t8=t6+t5;
 float t9=B[1]*A[0];
 float t10=B[5]*A[1];
 float t11=t9+t10;
 float t12=B[13]*A[3];
 float t13=t11+t7;
 float t14=B[10]*A[2];
 float t15=t13+t12;
 float t16=B[2]*A[0];
 float t17=B[6]*A[1];
 float t18=t16+t17;
 float t19=B[14]*A[3];
 float t20=t18+t14;
 float t21=t20+t19;
 float t22=B[3]*A[0];
 float t23=B[7]*A[1];
 float t24=t22+t23;
 float t25=B[15]*A[3];
 float t26=B[11]*A[2];
 float t27=t24+t26;
 float t28=A[4]*B[0];
 float t29=t27+t25;
 float t30=A[5]*B[4];
 float t31=t28+t30;
 float t32=A[6]*B[8];
 float t33=A[7]*B[12];
 float t34=A[4]*B[1];
 float t35=t31+t32;
 float t36=A[6]*B[9];
 float t37=t35+t33;
 float t38=A[5]*B[5];
 float t39=A[4]*B[3];
 float t40=t34+t38;
 float t41=A[4]*B[2];
 float t42=A[7]*B[13];
 float t43=t40+t36;
 float t44=A[6]*B[10];
 float t45=A[6]*B[11];
 float t46=t43+t42;
 float t47=A[5]*B[6];
 float t48=A[5]*B[7];
 float t49=t41+t47;
 float t50=t39+t48;
 float t51=A[7]*B[14];
 float t52=t49+t44;
 float t53=A[7]*B[15];
 float t54=t50+t45;
 float t55=t52+t51;
 float t56=A[10]*B[8];
 float t57=A[9]*B[4];
 float t58=t54+t53;
 float t59=A[8]*B[1];
 float t60=A[8]*B[0];
 float t61=t60+t57;
 float t62=B[12]*A[11];
 float t63=t61+t56;
 float t64=A[10]*B[9];
 float t65=t63+t62;
 float t66=A[9]*B[5];
 float t67=A[8]*B[2];
 float t68=A[8]*B[3];
 float t69=t59+t66;
 float t70=B[13]*A[11];
 float t71=t69+t64;
 float t72=A[10]*B[10];
 float t73=t71+t70;
 float t74=A[9]*B[6];
 float t75=A[9]*B[7];
 float t76=t67+t74;
 float t77=B[14]*A[11];
 float t78=t76+t72;
 float t79=t78+t77;
 float t80=t68+t75;
 float t81=B[15]*A[11];
 float t82=B[4]*A[13];
 float t83=B[0]*A[12];
 float t84=B[6]*A[13];
 float t85=t83+t82;
 float t86=A[10]*B[11];
 float t87=B[7]*A[13];
 float t88=t80+t86;
 float t89=B[15]*A[15];
 float t90=t88+t81;
 float t91=B[8]*A[14];
 float t92=B[10]*A[14];
 float t93=t85+t91;
 float t94=B[11]*A[14];
 float t95=B[12]*A[15];
 float t96=t93+t95;
 float t97=B[1]*A[12];
 float t98=B[5]*A[13];
 float t99=t97+t98;
 float t100=B[9]*A[14];
 float t101=t99+t100;
 float t102=B[13]*A[15];
 float t103=t101+t102;
 float t104=B[2]*A[12];
 float t105=t104+t84;
 float t106=B[3]*A[12];
 float t107=t105+t92;
 float t108=t106+t87;
 float t109=t108+t94;
 float t110=B[14]*A[15];
 float t111=t109+t89;
 float t112=t107+t110;
 o[0]=t8;
 o[1]=t15;
 o[2]=t21;
 o[3]=t29;
 o[4]=t37;
 o[5]=t46;
 o[6]=t55;
 o[7]=t58;
 o[8]=t65;
 o[9]=t73;
 o[10]=t79;
 o[11]=t90;
 o[12]=t96;
 o[13]=t103;
 o[14]=t112;
 o[15]=t111;
}
static int matrix_multiply(lua_State *L) {
    HD2NativeMatrix4x4 a,b;matrix_read(L,2,&b);matrix_read(L,1,&a);float o[16];
    matrix_multiply_rows(a.m,b.m,o);return matrix_push(L,o);
}
static int matrix_from_elements(lua_State *L) {
    float m[16];
    for(int r=0;r<4;r++){for(int c=0;c<3;c++)m[r*4+c]=(float)lua_tonumber(L,1+r*3+c);m[r*4+3]=r==3?1.0f:0.0f;}
    return matrix_push(L,m);
}
/* Twelve numbers: the first three columns of each row. */
static int matrix_to_elements(lua_State *L) {
    HD2NativeMatrix4x4 a;matrix_read(L,1,&a);
    for(int r=0;r<4;r++)for(int c=0;c<3;c++)lua_pushnumber(L,a.m[r*4+c]);
    return 12;
}
static int matrix_from_axes(lua_State *L) {
    float m[16];memcpy(m,matrix_identity_rows,sizeof(m));
    for(int r=0;r<4;r++){HD2NativeVector3 v;vector3_read(L,r+1,&v);m[r*4]=v.x;m[r*4+1]=v.y;m[r*4+2]=v.z;}
    return matrix_push(L,m);
}
static int matrix_from_quaternion_position(lua_State *L) {
    HD2NativeVector4 q;HD2NativeVector3 v;vector4_read(L,1,&q);vector3_read(L,2,&v);
    const float Q[4]={q.x,q.y,q.z,q.w};float m[16];matrix_rotation_rows(Q,m);
    m[12]=v.x;m[13]=v.y;m[14]=v.z;m[15]=1.0f;return matrix_push(L,m);
}
static void matrix_format_values(lua_State *L,luaL_Buffer *b,const float *v,int count,const char *separator) {
    char text[64];
    for(int i=0;i<count;i++) {
        if(!hd2vector_format_float(&environment(L)->vector_host,text,v[i]))luaL_error(L,"Matrix4x4 formatter refused");
        if(i)luaL_addstring(b,separator);
        luaL_addstring(b,text);
    }
}
/* "x = [a, b, c]\n" for x, y, z and t rows (first three columns). */
static int matrix_to_string(lua_State *L) {
    HD2NativeMatrix4x4 a;matrix_read(L,1,&a);luaL_Buffer b;luaL_buffinit(L,&b);
    const char *names[]={"x = [","y = [","z = [","t = ["};
    for(int r=0;r<4;r++){luaL_addstring(&b,names[r]);matrix_format_values(L,&b,a.m+r*4,3,", ");luaL_addstring(&b,"]\n");}
    luaL_pushresult(&b);return 1;
}
/* "<prefix>    16 values, four per line\n)", shared with Matrix4x4Box. */
static int matrix_push_long_string(lua_State *L,const char *prefix,const float *m) {
    luaL_Buffer b;luaL_buffinit(L,&b);luaL_addstring(&b,prefix);
    for(int r=0;r<4;r++){luaL_addstring(&b,"    ");matrix_format_values(L,&b,m+r*4,4,", ");luaL_addstring(&b,r<3?",\n":"\n");}
    luaL_addstring(&b,")");luaL_pushresult(&b);return 1;
}
/* tostring(m): "Matrix4x4(\n    16 values, four per line\n)". */
static int matrix_global_tostring(lua_State *L) {
    HD2Environment *e=environment(L);HD2NativeMatrix4x4 a;uintptr_t p=(uintptr_t)lua_touserdata(L,1);
    if(lua_gettop(L)&&lua_type(L,1)==LUA_TLIGHTUSERDATA&&p&&p<=UINTPTR_MAX-sizeof(a)&&
       e->vector_host.read(e->vector_host.context,p,&a,sizeof(a))==1&&a.tag==0x7fd2e074) {
        return matrix_push_long_string(L,"Matrix4x4(\n",a.m);
    }
    lua_pushvalue(L,lua_upvalueindex(1));lua_insert(L,1);lua_call(L,lua_gettop(L)-1,LUA_MULTRET);return lua_gettop(L);
}
static int quat_matrix4x4(lua_State *L){return matrix_from_quaternion_rows(L);}
static int quat_from_matrix4x4(lua_State *L){return matrix_rotation(L);}
static void matrix_closure(lua_State *L,const char *name,lua_CFunction f,int up) {
    lua_pushinteger(L,up);lua_pushcclosure(L,f,1);lua_setfield(L,-2,name);
}
static int matrix_registration(lua_State *L,HD2Environment *e) {
    e->matrix4x4_ready=1;lua_getglobal(L,"stingray");lua_getfield(L,-1,"Matrix4x4");
    if(!lua_istable(L,-1))return luaL_error(L,"Matrix4x4 table unavailable");
    lua_pushvalue(L,-1);lua_setfield(L,-2,"__index");lua_pushliteral(L,"Matrix4x4");lua_setfield(L,-2,"_name");
    lua_pushvalue(L,-1);lua_setfield(L,LUA_REGISTRYINDEX,"Matrix4x4");
    lua_newtable(L);callback(L,"__call",matrix_call);lua_setmetatable(L,-2);
    callback(L,"zero",matrix_zero);callback(L,"identity",matrix_identity);callback(L,"from_translation",matrix_from_translation);
    callback(L,"copy",matrix_copy);callback(L,"equal",matrix_equal);callback(L,"is_valid",matrix_valid);
    callback(L,"is_valid_for_physics",matrix_valid_for_physics);
    const char *rows[]={"x","y","z","right","forward","up","translation"},*sets[]={"set_x","set_y","set_z","set_right","set_forward","set_up","set_translation"};
    const int index[]={0,1,2,0,1,2,3};
    for(int i=0;i<7;i++){matrix_closure(L,rows[i],matrix_row,index[i]);matrix_closure(L,sets[i],matrix_set_row,index[i]);}
    callback(L,"axis",matrix_axis);callback(L,"set_axis",matrix_set_axis);
    callback(L,"element",matrix_element);callback(L,"set_element",matrix_set_element);
    matrix_closure(L,"transform",matrix_transform,1);matrix_closure(L,"transform_without_translation",matrix_transform,0);
    callback(L,"inverse",matrix_inverse);callback(L,"rotation",matrix_rotation);callback(L,"set_rotation",matrix_set_rotation);
    callback(L,"scale",matrix_scale);callback(L,"set_scale",matrix_set_scale);
    callback(L,"multiply",matrix_multiply);callback(L,"from_elements",matrix_from_elements);
    callback(L,"to_elements",matrix_to_elements);callback(L,"from_axes",matrix_from_axes);
    callback(L,"from_quaternion",matrix_from_quaternion_rows);callback(L,"from_quaternion_position",matrix_from_quaternion_position);
    callback(L,"to_string",matrix_to_string);
    /* lerp decomposes both matrices (scale, rotation, translation); traced, not yet ported. */
    const char *pending[]={"lerp"};
    for(size_t i=0;i<sizeof(pending)/sizeof(*pending);i++)missing(L,pending[i]);
    lua_pop(L,2);lua_getglobal(L,"stingray");lua_getfield(L,-1,"Quaternion");
    if(!lua_istable(L,-1))return luaL_error(L,"Quaternion table unavailable");
    callback(L,"matrix4x4",quat_matrix4x4);callback(L,"from_matrix4x4",quat_from_matrix4x4);lua_pop(L,2);
    lua_getglobal(L,"tostring");lua_pushcclosure(L,matrix_global_tostring,1);lua_setglobal(L,"tostring");return 0;
}
