/* Offline checks for the boot handoff's code witnesses and its LuaEnvironment
 * lookup (build 26251122). hd2env_check_code runs against a fake host and, on
 * Windows (Wine), against real committed no-access, read-only and executable
 * pages. hd2puc_lua_environment and hd2puc_warm_vectors run against the real
 * PUC Lua 5.1.4 reference library on Linux (build with -DHD2_NATIVE_ABI=, as
 * bridge_tests.c). The resource reader's refusal reasons run on Windows over a
 * fake image; the vector probes' reasons run on both over the 26251122 capture.
 * Linux: cc -std=c11 -O2 -g -Wall -Wextra -Werror -DHD2_NATIVE_ABI= -I. -Iwork \
 *          handoff_tests.c engine_steam.c engine_puc.c engine_resources.c engine_vectors.c -ldl -o handoff-tests
 * Wine:  x86_64-w64-mingw32-gcc -std=c11 -O2 -g -Wall -Wextra -Werror -I. -Iwork \
 *          handoff_tests.c engine_steam.c engine_puc.c engine_resources.c engine_vectors.c -o handoff-tests.exe */
#define _GNU_SOURCE
#include "native_puc.h"
#include "native_resources.h"
#include "native_vectors.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif
static unsigned checks;
static void need(int ok,const char *message){if(!ok){fprintf(stderr,"HANDOFF ERROR: %s\n",message);exit(16);}checks++;}
typedef struct {const unsigned char *code;size_t size;int call,read;} Fake;
static int fake_read(void *context,uintptr_t at,void *out,size_t size){
    Fake *f=context;uintptr_t base=(uintptr_t)f->code;
    if(!f->read||at<base||at-base>f->size||size>f->size-(at-base))return 0;
    memcpy(out,(const void *)at,size);return 1;
}
static int fake_write(void *context,uintptr_t at,const void *in,size_t size){(void)context;(void)at;(void)in;(void)size;return 0;}
static int fake_callable(void *context,uintptr_t at){Fake *f=context;return f->call&&at==(uintptr_t)f->code;}
static const unsigned char witness[16]={0x48,0x83,0xec,0x28,0x4c,0x8b,0xd1,0xba,1,0,0,0,0x48,0x8b,0x49,0x20};
static int check(Fake *f,const unsigned char *expected,char *why,size_t size){
    HD2SteamHost h={f,(uintptr_t)f->code,fake_read,fake_write,fake_callable};
    memset(why,'?',size);
    return hd2env_check_code(&h,(uintptr_t)f->code,expected,sizeof(witness),why,size);
}
static void code_witnesses(void){
    unsigned char code[sizeof(witness)];memcpy(code,witness,sizeof(code));
    Fake f={code,sizeof(code),1,1};char why[256];
    need(check(&f,witness,why,sizeof(why))==HD2_CODE_MATCH&&!why[0],"resident matching code matches with an empty reason");
    f.call=0;f.read=0;
    need(check(&f,witness,why,sizeof(why))==HD2_CODE_NOT_RESIDENT,"code neither callable nor readable is not resident");
    need(strstr(why,"not resident")!=NULL,"not-resident reason says so");
    f.call=0;f.read=1;
    need(check(&f,witness,why,sizeof(why))==HD2_CODE_REFUSED,"readable code that is not executable is refused");
    need(strstr(why,"not executable")!=NULL,"not-executable reason says so");
    f.call=1;f.read=0;
    need(check(&f,witness,why,sizeof(why))==HD2_CODE_REFUSED,"executable code that is unreadable is refused");
    need(strstr(why,"unreadable")!=NULL,"unreadable reason says so");
    f.call=1;f.read=1;code[7]^=0xff;
    need(check(&f,witness,why,sizeof(why))==HD2_CODE_REFUSED,"resident code that differs is refused");
    need(strstr(why,"differs")!=NULL&&strstr(why,"byte 7")!=NULL,"difference reason names the first differing byte");
    code[7]^=0xff;
    char small[8];f.call=0;f.read=0;
    need(check(&f,witness,small,sizeof(small))==HD2_CODE_NOT_RESIDENT&&memchr(small,0,sizeof(small)),"a short reason buffer stays terminated");
    HD2SteamHost h={&f,(uintptr_t)code,fake_read,fake_write,fake_callable};f.call=1;f.read=1;
    need(hd2env_check_code(&h,(uintptr_t)code,witness,sizeof(witness),NULL,0)==HD2_CODE_MATCH,"the reason buffer is optional");
}
#ifdef _WIN32
/* Real pages, the way the protection runtime leaves code before first use. */
static int page_read(void *context,uintptr_t at,void *out,size_t size){
    (void)context;SIZE_T copied=0;
    return ReadProcessMemory(GetCurrentProcess(),(const void *)at,out,size,&copied)&&copied==size;
}
static int page_callable(void *context,uintptr_t at){
    (void)context;MEMORY_BASIC_INFORMATION m;
    if(!VirtualQuery((void *)at,&m,sizeof(m))||m.State!=MEM_COMMIT||(m.Protect&(PAGE_GUARD|PAGE_NOACCESS)))return 0;
    DWORD p=m.Protect&0xff;return p==PAGE_EXECUTE_READ||p==PAGE_EXECUTE_READWRITE||p==PAGE_EXECUTE_WRITECOPY;
}
static void real_pages(void){
    unsigned char *page=VirtualAlloc(NULL,4096,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);DWORD old;char why[256];
    need(page!=NULL,"VirtualAlloc test page");memcpy(page,witness,sizeof(witness));
    HD2SteamHost h={NULL,(uintptr_t)page,page_read,fake_write,page_callable};
    need(VirtualProtect(page,4096,PAGE_EXECUTE_READ,&old),"VirtualProtect execute-read");
    need(hd2env_check_code(&h,(uintptr_t)page,witness,sizeof(witness),why,sizeof(why))==HD2_CODE_MATCH,"execute-read page matches");
    need(VirtualProtect(page,4096,PAGE_NOACCESS,&old),"VirtualProtect no-access");
    need(hd2env_check_code(&h,(uintptr_t)page,witness,sizeof(witness),why,sizeof(why))==HD2_CODE_NOT_RESIDENT,"committed no-access page is not resident");
    need(strstr(why,"state 0x1000")&&strstr(why,"protect 0x1,"),"not-resident reason carries the page state and protection");
    need(VirtualProtect(page,4096,PAGE_READONLY,&old),"VirtualProtect read-only");
    need(hd2env_check_code(&h,(uintptr_t)page,witness,sizeof(witness),why,sizeof(why))==HD2_CODE_REFUSED,"read-only page is refused");
    need(strstr(why,"not executable")&&strstr(why,"protect 0x2,"),"read-only reason carries the protection");
    VirtualFree(page,0,MEM_RELEASE);
}
#include "resource_witness.h"
/* A fake LuaEnvironment and ResourceManager around a fake image whose resolver
 * page (0x6321a0) the host serves or refuses. */
typedef struct {unsigned char *image;int call,read;} Resolver;
static int resolver_read(void *context,uintptr_t at,void *out,size_t size){
    Resolver *f=context;uintptr_t fn=(uintptr_t)f->image+0x6321a0;
    if(at<fn+sizeof(resource_witness)&&at+size>fn&&!f->read)return 0;
    memcpy(out,(const void *)at,size);return 1;
}
static int resolver_callable(void *context,uintptr_t at){Resolver *f=context;return f->call&&at==(uintptr_t)f->image+0x6321a0;}
static void resource_reader(void){
    Resolver f={calloc(1,0x6321a0+sizeof(resource_witness)),0,0};
    unsigned char *environment=calloc(1,0x100150),*manager=calloc(1,0x2d0),row[80]={0};
    need(f.image&&environment&&manager,"fake image and environment");
    uintptr_t state=0x5157a7e,m=(uintptr_t)manager,rows=(uintptr_t)row;uint32_t count=1;uint64_t lua=UINT64_C(0xa14e8dfa2cd117e2);
    memcpy(environment,&state,8);memcpy(environment+0x100148,&state,8);memcpy(environment+0x110,&m,8);
    memcpy(manager+0x2c0,&count,4);memcpy(manager+0x2c8,&rows,8);memcpy(row,&lua,8);
    memcpy(f.image+0x6321a0,resource_witness,sizeof(resource_witness));
    HD2SteamHost h={&f,(uintptr_t)f.image,resolver_read,fake_write,resolver_callable};
    need(hd2resources_open(&h,(uintptr_t)environment)==NULL,"a resolver not yet decrypted refuses the reader");
    need(strstr(hd2resources_error(NULL),"resolver witness: not resident")!=NULL,"the refusal says the resolver is not resident");
    f.call=1;f.read=1;f.image[0x6321a0+20]^=0xff;
    need(hd2resources_open(&h,(uintptr_t)environment)==NULL,"a different resolver refuses the reader");
    need(strstr(hd2resources_error(NULL),"resolver witness: code differs from the witness at byte 20")!=NULL,"the refusal names the differing byte");
    f.image[0x6321a0+20]^=0xff;
    need(hd2resources_open(&h,(uintptr_t)environment)!=NULL,"the matching resolver opens the reader");
}
#else
static void real_pages(void){}
static void resource_reader(void){}
#endif
/* The 26251122 capture as the image; the host refuses one page, the way the
 * game leaves a page it has not decrypted yet. */
#ifdef _WIN32
#define CAPTURE "Z:/home/goose/Projects/Linux HD2 Mods/builds/26251122/runtime/images/exe-26251122.bin"
#else
#define CAPTURE "/home/goose/Projects/Linux HD2 Mods/builds/26251122/runtime/images/exe-26251122.bin"
#endif
typedef struct {unsigned char *image;uintptr_t cold;} Capture;
static int cold_page(const Capture *c,uintptr_t at,size_t size){
    uintptr_t page=(uintptr_t)c->image+c->cold;
    return c->cold&&at<page+0x1000&&at+size>page;
}
static int capture_read(void *context,uintptr_t at,void *out,size_t size){
    Capture *c=context;uintptr_t base=(uintptr_t)c->image;
    if(at<base||at-base>0x29fe000||size>0x29fe000-(at-base)||cold_page(c,at,size))return 0;
    memcpy(out,(const void *)at,size);return 1;
}
static int capture_callable(void *context,uintptr_t at){
    Capture *c=context;uintptr_t base=(uintptr_t)c->image;
    return at>=base&&at-base<0x29fe000&&!cold_page(c,at,1);
}
static void vector_probes(void){
    Capture c={malloc(0x29fe000),0};FILE *f=fopen(CAPTURE,"rb");
    need(c.image&&f&&fread(c.image,1,0x29fe000,f)==0x29fe000,"26251122 capture");fclose(f);
    HD2VectorHost h={&c,(uintptr_t)c.image,capture_read,fake_write,capture_callable};
    need(hd2env_probe_vector4_host(&h)&&hd2env_probe_vector3box_host(&h)&&!hd2vector_probe_error()[0],"the capture passes every vector probe with no reason");
    c.cold=0x9f000;
    need(!hd2env_probe_vector2_host(&h),"an undecrypted pool allocator page refuses Vector2");
    need(strstr(hd2vector_probe_error(),"native pool allocator +0x9f900: not resident")!=NULL,"the reason names the pool allocator and says not resident");
    c.cold=0x41b000;
    need(!hd2env_probe_vector2_host(&h)&&strstr(hd2vector_probe_error(),"Vector2 natives +0x41b000: not resident"),"an undecrypted page inside the Vector2 natives is named");
    c.cold=0x4f0000;
    need(!hd2env_probe_vector2_host(&h)&&strstr(hd2vector_probe_error(),"temporary frame cleanup +0x4f03a0: not resident"),"the frame cleanup page is named");
    c.cold=0x424000;
    need(hd2env_probe_vector2_host(&h)&&!hd2env_probe_vector3_host(&h),"a Vector3 page refuses Vector3 only");
    need(strstr(hd2vector_probe_error(),"Vector3 natives +0x424000: not resident")!=NULL,"the reason names the Vector3 page");
    c.cold=0x426000;
    need(!hd2env_probe_vector3box_host(&h)&&strstr(hd2vector_probe_error(),"Vector3Box natives +0x4263c0: not resident"),"the Vector3Box page is named");
    c.cold=0x42b000;
    need(!hd2env_probe_vector4_host(&h)&&strstr(hd2vector_probe_error(),"Vector4 natives +0x42b000: not resident"),"the Vector4 page is named");
    c.cold=0;c.image[0x41c123]^=0xff;
    need(!hd2env_probe_vector2_host(&h)&&strstr(hd2vector_probe_error(),"Vector2 natives +0x41c000: code differs from the witness at byte 291"),"a differing byte is located");
    c.image[0x41c123]^=0xff;
    need(hd2env_probe_vector2_host(&h)&&!hd2vector_probe_error()[0],"a passing probe clears the last reason");
    uint32_t nt;memcpy(&nt,c.image+0x3c,4);c.image[nt+8]^=1;
    need(!hd2env_probe_vector2_host(&h)&&strstr(hd2vector_probe_error(),"image header"),"a different image header is named");
    free(c.image);
}
#ifndef _WIN32
static void *reference_puc(HD2PucApi *T){
    void *puc=dlopen("/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/liblua514.so",RTLD_NOW|RTLD_LOCAL|RTLD_DEEPBIND);
    need(puc!=NULL,"PUC Lua 5.1.4 reference library");
    static const char *names[]={"lua_gettop","lua_settop","lua_pushvalue","lua_remove","lua_insert","lua_replace","lua_checkstack",
        "lua_iscfunction","lua_type","lua_rawequal","lua_tonumber","lua_toboolean","lua_tolstring","lua_objlen","lua_tocfunction",
        "lua_touserdata","lua_topointer","lua_pushnil","lua_pushnumber","lua_pushlstring","lua_pushcclosure","lua_pushboolean",
        "lua_pushlightuserdata","lua_gettable","lua_getfield","lua_rawget","lua_rawgeti","lua_createtable","lua_newuserdata",
        "lua_getmetatable","lua_settable","lua_setfield","lua_rawset","lua_rawseti","lua_setmetatable","lua_pcall","lua_error",
        "lua_next","lua_newthread"};
    _Static_assert(sizeof(names)/sizeof(*names)==sizeof(HD2PucApi)/sizeof(void *),"one name per API field");
    void *entries[sizeof(names)/sizeof(*names)];
    for(size_t i=0;i<sizeof(entries)/sizeof(*entries);i++)need((entries[i]=dlsym(puc,names[i]))!=NULL,names[i]);
    memcpy(T,entries,sizeof(*T));
    return puc;
}
static int (*load_string)(HD2PucState *,const char *);
static int lua_run(const HD2PucApi *T,HD2PucState *P,const char *source,int results){
    if(!load_string(P,source)&&!T->pcall(P,0,results,0))return 1;
    fprintf(stderr,"HANDOFF ERROR: %s\n",T->tolstring(P,-1,NULL));T->settop(P,-2);return 0;
}
static int lua_true(const HD2PucApi *T,HD2PucState *P,const char *expression){
    char source[512];snprintf(source,sizeof(source),"return (%s)",expression);
    if(!lua_run(T,P,source,1))return 0;
    int value=T->toboolean(P,-1);T->settop(P,-2);return value;
}
/* Stand-ins for the game's vector natives: each records its call and raises
 * unless its first argument is a vector of its own type (constants take none). */
static const char warm_fakes[]=
    "calls,bad={},{}\n"
    "local consts={zero=1,up=1,down=1,left=1,right=1,forward=1,backward=1}\n"
    "local function record(name) calls[#calls+1]=name end\n"
    "local operators={}\n"
    "local function object(tag) return setmetatable({tag=tag},operators) end\n"
    "for _,k in ipairs{'__add','__sub','__mul','__div','__unm'} do operators[k]=function(a) record(a.tag..k) return a end end\n"
    "operators.__index=function(o) record(o.tag..'.index') return 1 end\n"
    "local function is(o,tag) return type(o)=='table' and rawget(o,'tag')==tag end\n"
    "local function lib(tag)\n"
    "  return setmetatable({},{__call=function(_,first)\n"
    "      record(tag)\n"
    "      if tag=='Vector3Box' and not is(first,'Vector3') or tag~='Vector3Box' and type(first)~='number' then bad[#bad+1]=tag error('bad constructor argument') end\n"
    "      return object(tag) end,\n"
    "    __index=function(_,name) return function(o)\n"
    "      record(tag..'.'..name)\n"
    "      if not consts[name] and not is(o,tag) then bad[#bad+1]=tag..'.'..name error('bad argument') end\n"
    "      return o end end})\n"
    "end\n"
    "stingray={Vector2=lib('Vector2'),Vector3=lib('Vector3'),Vector3Box=lib('Vector3Box'),Vector4=lib('Vector4'),\n"
    "  Script={temp_count=function() record('temp_count') return 7,8 end,\n"
    "    set_temp_count=function(...) record('set_temp_count '..table.concat({...},',')) end}}\n"
    "function has(name) for _,c in ipairs(calls) do if c==name then return true end end return false end\n"
    "function any(prefix) for _,c in ipairs(calls) do if c:sub(1,#prefix)==prefix then return true end end return false end\n"
    /* One native per page of each witness range (all 26 Vector2 functions: their
     * entries are not in the evidence), the index helpers and the checkpoint pair. */
    "local required={'Vector2','Vector2.index','Vector2.zero','Vector2.equal','Vector2.is_valid','Vector2.multiply',\n"
    "  'Vector2.divide','Vector2.lerp','Vector2.length','Vector2.normalize','Vector2.dot','Vector2.to_elements',\n"
    "  'Vector2.to_string','Vector2.element','Vector2.set_element','Vector2.set_xy','Vector2.distance',\n"
    "  'Vector2.distance_squared','Vector2.x','Vector2.y','Vector2.set_x','Vector2.set_y','Vector2.add','Vector2.subtract',\n"
    "  'Vector2.multiply_elements','Vector2.divide_elements','Vector2.min','Vector2.max',\n"
    "  'Vector3','Vector3.length_squared','Vector3.equal','Vector3.add','Vector3.divide','Vector3.up','Vector3.element',\n"
    "  'Vector3.x','Vector3.set_xyz','Vector3.length','Vector3.cross','Vector3.lerp','Vector3.is_valid',\n"
    "  'Vector3Box','Vector3Box.store','Vector3Box.unbox',\n"
    "  'Vector4','Vector4.equal','Vector4.add','Vector4.to_string','Vector4.divide','Vector4.w','Vector4.set_element',\n"
    "  'Vector4.set_xyzw','Vector4.length','Vector4.dot','Vector4.lerp','Vector4.is_valid'}\n"
    "function missing() for _,n in ipairs(required) do if not has(n) then return n end end return nil end\n";
static void warm_vectors(void){
    HD2PucApi T;void *puc=reference_puc(&T);
    HD2PucState *(*newstate)(void);void (*close)(HD2PucState *),(*openlibs)(HD2PucState *);
    *(void **)&newstate=dlsym(puc,"luaL_newstate");*(void **)&close=dlsym(puc,"lua_close");
    *(void **)&openlibs=dlsym(puc,"luaL_openlibs");*(void **)&load_string=dlsym(puc,"luaL_loadstring");
    need(newstate&&close&&openlibs&&load_string,"PUC reference state functions");
    HD2PucState *P=newstate();need(P!=NULL,"PUC state");openlibs(P);
    need(lua_run(&T,P,warm_fakes,0),"fake vector natives");
    T.pushnumber(P,42);
    int failed=-1;char why[256],count[64];
    int ran=hd2puc_warm_vectors(&T,P,&failed,why,sizeof(why));
    need(T.gettop(P)==1,"the warm-up leaves the stack as it was");
    snprintf(count,sizeof(count),"#calls==%d",ran);
    need(ran>0&&lua_true(&T,P,count),"every call the warm-up makes is counted");
    need(failed==0&&lua_true(&T,P,"#bad==0"),"every original is called with valid arguments");
    need(lua_true(&T,P,"missing()==nil"),"one native runs on every page of the vector witnesses");
    need(lua_true(&T,P,"calls[1]=='temp_count' and calls[#calls]=='set_temp_count 7,8'"),"the warm-up restores the temporary checkpoint it took first");
    need(lua_run(&T,P,"calls,bad={},{} rawset(stingray.Vector3,'cross',function() calls[#calls+1]='Vector3.cross' error('boom') end)",0),"a raising native");
    ran=hd2puc_warm_vectors(&T,P,&failed,why,sizeof(why));
    need(failed==1&&lua_true(&T,P,"has'Vector4.lerp' and calls[#calls]=='set_temp_count 7,8'"),"a native that raises is counted and the rest still run");
    need(lua_run(&T,P,"calls,bad={},{} rawset(stingray.Vector3,'cross',nil)\n"
        "getmetatable(stingray.Vector4).__call=function() calls[#calls+1]='Vector4' error('no Vector4') end\n"
        "getmetatable(stingray.Vector3Box).__call=function() calls[#calls+1]='Vector3Box' error('no box') end",0),"failing constructors");
    ran=hd2puc_warm_vectors(&T,P,&failed,why,sizeof(why));
    need(failed>0&&lua_true(&T,P,"not any'Vector4.' and not any'Vector3Box.' and #bad==0"),"nothing is called on a vector that could not be made");
    need(lua_true(&T,P,"calls[#calls]=='set_temp_count 7,8'"),"the checkpoint is restored after failed constructors");
    need(lua_run(&T,P,"calls={} stingray=nil",0),"no stingray table");
    need(hd2puc_warm_vectors(&T,P,&failed,why,sizeof(why))==0&&failed==0&&T.gettop(P)==1,"without stingray nothing runs");
    need(lua_run(&T,P,"loadstring=nil",0),"no loadstring");
    need(hd2puc_warm_vectors(&T,P,&failed,why,sizeof(why))==-1&&strstr(why,"loadstring")&&T.gettop(P)==1,"without loadstring the warm-up is skipped with a reason");
    close(P);dlclose(puc);
}
static void lua_environment(void){
    HD2PucApi T;void *puc=reference_puc(&T);
    HD2PucState *(*newstate)(void);void (*close)(HD2PucState *);
    *(void **)&newstate=dlsym(puc,"luaL_newstate");*(void **)&close=dlsym(puc,"lua_close");
    HD2PucState *P=newstate();need(P!=NULL,"PUC state");
    T.pushnumber(P,1);T.pushnumber(P,2);T.pushnumber(P,3);
    void *block=T.newuserdata(P,64);T.rawseti(P,HD2_PUC_REGISTRYINDEX,1);
    need(hd2puc_lua_environment(&T,P)==block,"full userdata in registry[1] gives its block");
    need(T.gettop(P)==3,"the lookup leaves the stack as it was");
    static char anchor;T.pushlightuserdata(P,&anchor);T.rawseti(P,HD2_PUC_REGISTRYINDEX,1);
    need(hd2puc_lua_environment(&T,P)==&anchor,"light userdata in registry[1] gives its pointer");
    T.pushnumber(P,7);T.rawseti(P,HD2_PUC_REGISTRYINDEX,1);
    need(hd2puc_lua_environment(&T,P)==NULL,"a number in registry[1] gives no environment");
    T.pushnil(P);T.rawseti(P,HD2_PUC_REGISTRYINDEX,1);
    need(hd2puc_lua_environment(&T,P)==NULL,"an empty registry[1] gives no environment");
    need(T.gettop(P)==3,"every lookup leaves the stack as it was");
    T.settop(P,0);
    HD2PucState *thread=T.newthread(P);block=T.newuserdata(P,8);T.rawseti(P,HD2_PUC_REGISTRYINDEX,1);
    need(hd2puc_lua_environment(&T,thread)==block,"a coroutine sees the shared registry");
    close(P);dlclose(puc);
}
#else
static void warm_vectors(void){}
static void lua_environment(void){}
#endif
int main(void){
    code_witnesses();real_pages();resource_reader();vector_probes();warm_vectors();lua_environment();
    printf("HANDOFF_TESTS pass: %u checks%s\n",checks,
#ifdef _WIN32
        " (Windows pages; PUC lookup runs on Linux)"
#else
        " (PUC 5.1.4 reference; Windows pages run under Wine)"
#endif
    );
    return 0;
}
