#include "native_puc.h"
#include "puc_witnesses.h"
#include <string.h>
#include <stdio.h>
_Static_assert(sizeof(HD2PucApi)==sizeof(puc_witnesses)/sizeof(puc_witnesses[0])*sizeof(void *),"HD2PucApi fields follow puc_witnesses");
static int puc_read(const HD2SteamHost *h,uintptr_t p,void *out,size_t n) {
    return p&&n<=UINTPTR_MAX-p&&h->read(h->context,p,out,n)==1;
}
static uint32_t puc_word(const unsigned char *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
int hd2puc_bind(HD2PucApi *api,const HD2SteamHost *h) {
    if(!api||!h||!h->image_base||h->image_base>UINTPTR_MAX-0x29fe000||!h->read||!h->callable)return 0;
    unsigned char header[0x400];
    if(!puc_read(h,h->image_base,header,sizeof(header))||memcmp(header,"MZ",2))return 0;
    uint32_t nt=puc_word(header+0x3c);
    if(nt>sizeof(header)-0x80||memcmp(header+nt,"PE\0\0",4)||puc_word(header+nt+8)!=0x6af2d5e6||
       puc_word(header+nt+24+56)!=0x29fe000)return 0;
    void *entries[sizeof(puc_witnesses)/sizeof(puc_witnesses[0])];
    for(size_t i=0;i<sizeof(entries)/sizeof(entries[0]);i++) {
        uintptr_t at=h->image_base+puc_witnesses[i].rva;unsigned char actual[32];
        if(h->callable(h->context,at)!=1||!puc_read(h,at,actual,32)||memcmp(actual,puc_witnesses[i].bytes,32))return 0;
        entries[i]=(void *)at;
    }
    /* The engine's own LuaApi table must still publish the same core entries. */
    uintptr_t slot=0;
    if(!puc_read(h,h->image_base+HD2_PUC_LUAAPI_TABLE+13*8,&slot,8)||slot!=h->image_base+0x796ab0)return 0;
    memcpy(api,entries,sizeof(entries));
    return 1;
}
/* exe+0x9fc00 pushes luaH_getnum(registry,1), takes a light userdata's pointer
 * or a full userdata's block (+0x28), and pops: rawgeti, touserdata, settop. */
void *hd2puc_lua_environment(const HD2PucApi *api,HD2PucState *P){
    if(!api||!P)return NULL;
    int top=api->gettop(P);api->rawgeti(P,HD2_PUC_REGISTRYINDEX,1);
    void *environment=api->touserdata(P,-1);api->settop(P,top);
    return environment;
}
/* One call per page of the vector witnesses (hd2env_probe_vector*_host): all 26
 * Vector2 functions (the evidence does not list their entries) and the index
 * helpers, one Vector3/Vector4 function per page, the Vector3Box callbacks and
 * the temporary checkpoint pair. Every argument is valid for the original, and
 * nothing is called on a vector that could not be made: some originals read
 * their arguments unchecked. */
static const char warm_source[]=
    "local s=stingray\n"
    "if type(s)~='table' then return 0,0 end\n"
    "local V2,V3,B,V4,S=s.Vector2,s.Vector3,s.Vector3Box,s.Vector4,s.Script\n"
    "local ran,failed=0,0\n"
    "local function try(f,...)\n"
    "  ran=ran+1\n"
    "  local ok,value=pcall(f,...)\n"
    "  if not ok then failed=failed+1 return nil end\n"
    "  return value\n"
    "end\n"
    "local function each(lib,names,...) for _,n in ipairs(names) do try(lib[n],...) end end\n"
    "local mark\n"
    "if type(S)=='table' then\n"
    "  ran=ran+1 mark={pcall(S.temp_count)}\n"
    "  if not mark[1] then failed=failed+1 mark=nil end\n"
    "end\n"
    "local a,b=try(V2,1,2),try(V2,3,4)\n"
    "if a and b then\n"
    "  try(V2.zero)\n"
    "  each(V2,{'is_valid','length','normalize','to_elements','to_string','x','y'},a)\n"
    "  each(V2,{'equal','dot','distance','distance_squared','add','subtract','multiply_elements','divide_elements','min','max'},a,b)\n"
    "  try(V2.multiply,a,2) try(V2.divide,a,2) try(V2.lerp,a,b,0.5) try(V2.element,a,1) try(V2.set_element,a,1,0)\n"
    "  try(V2.set_xy,a,1,2) try(V2.set_x,a,1) try(V2.set_y,a,1)\n"
    "  try(function() return a.x end) try(function() return a+b end) try(function() return a-b end)\n"
    "  try(function() return a*2 end) try(function() return -a end)\n"
    "end\n"
    "local c,d=try(V3,1,2,3),try(V3,4,5,6)\n"
    "if c and d then\n"
    "  each(V3,{'zero','up','down','left','right','forward','backward'})\n"
    "  each(V3,{'is_valid','length','length_squared','normalize','to_elements','to_string','x','y','z'},c)\n"
    "  each(V3,{'equal','dot','cross','distance','distance_squared','distance_xy_squared','add','subtract',\n"
    "    'multiply_elements','divide_elements','min','max'},c,d)\n"
    "  try(V3.multiply,c,2) try(V3.divide,c,2) try(V3.lerp,c,d,0.5) try(V3.element,c,1) try(V3.set_element,c,1,0)\n"
    "  try(V3.set_x,c,1) try(V3.set_y,c,1) try(V3.set_z,c,1) try(V3.set_xyz,c,1,2,3)\n"
    "  local box=try(B,c)\n"
    "  if box then try(B.store,box,d) try(B.unbox,box) end\n"
    "end\n"
    "local e,f=try(V4,1,2,3,4),try(V4,5,6,7,8)\n"
    "if e and f then\n"
    "  try(V4.zero)\n"
    "  each(V4,{'is_valid','length','normalize','to_elements','to_string','x','y','z','w'},e)\n"
    "  each(V4,{'equal','dot','distance','distance_squared','add','subtract','multiply_elements','divide_elements','min','max'},e,f)\n"
    "  try(V4.multiply,e,2) try(V4.divide,e,2) try(V4.lerp,e,f,0.5) try(V4.element,e,1) try(V4.set_element,e,1,0)\n"
    "  try(V4.set_x,e,1) try(V4.set_y,e,1) try(V4.set_z,e,1) try(V4.set_w,e,1) try(V4.set_xyzw,e,1,2,3,4)\n"
    "end\n"
    "if mark and #mark>1 then\n"
    "  ran=ran+1\n"
    "  if not pcall(S.set_temp_count,unpack(mark,2)) then failed=failed+1 end\n"
    "end\n"
    "return ran,failed\n";
int hd2puc_warm_vectors(const HD2PucApi *api,HD2PucState *P,int *failed,char *why,size_t why_size){
    char none[1];int ignored;
    if(!why||!why_size){why=none;why_size=sizeof(none);}
    if(!failed)failed=&ignored;
    why[0]=0;*failed=0;
    if(!api||!P){snprintf(why,why_size,"no PUC state");return -1;}
    int top=api->gettop(P),ran=-1;
    api->getfield(P,HD2_PUC_GLOBALSINDEX,"loadstring");
    if(api->type(P,-1)!=6){snprintf(why,why_size,"loadstring unavailable");goto done;} /* 6: function */
    api->pushlstring(P,warm_source,sizeof(warm_source)-1);
    api->pushlstring(P,"=hd2_warm_vectors",17);
    if(api->pcall(P,2,2,0)||api->type(P,-2)!=6){
        const char *error=api->tolstring(P,-1,NULL);
        snprintf(why,why_size,"warm-up does not compile: %s",error?error:"no message");goto done;
    }
    api->settop(P,-2);
    if(api->pcall(P,0,2,0)){
        const char *error=api->tolstring(P,-1,NULL);
        snprintf(why,why_size,"warm-up raised: %s",error?error:"no message");goto done;
    }
    ran=(int)api->tonumber(P,-2);*failed=(int)api->tonumber(P,-1);
done:
    api->settop(P,top);return ran;
}
