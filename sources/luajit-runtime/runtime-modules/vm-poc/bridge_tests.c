/* Offline check of the native bridge against a real PUC Lua 5.1.4 library
 * (the reference build, loaded with RTLD_DEEPBIND beside the FR1 LuaJIT core).
 * Build with -DHD2_NATIVE_ABI= so PUC calls bridge callbacks with the host ABI.
 * Exercises calls, errors, callbacks and reentry, identity in both
 * directions, copies with cycles, userdata proxies, release through both
 * collectors and use of a proxy after the environment is destroyed. */
#define _GNU_SOURCE
#include "environment.c"
static char light_anchor;
#include <dlfcn.h>
#ifdef BRIDGE_TEST_STATIC
/* Sanitizer build: PUC 5.1.4 linked statically with its API renamed puc_*. */
#define PUC_NAMES X(lua_gettop) X(lua_settop) X(lua_pushvalue) X(lua_remove) X(lua_insert) X(lua_replace) X(lua_checkstack) X(lua_iscfunction) X(lua_type) X(lua_rawequal) X(lua_tonumber) X(lua_toboolean) X(lua_tolstring) X(lua_objlen) X(lua_tocfunction) X(lua_touserdata) X(lua_topointer) X(lua_pushnil) X(lua_pushnumber) X(lua_pushlstring) X(lua_pushcclosure) X(lua_pushboolean) X(lua_pushlightuserdata) X(lua_gettable) X(lua_getfield) X(lua_rawget) X(lua_rawgeti) X(lua_createtable) X(lua_newuserdata) X(lua_getmetatable) X(lua_settable) X(lua_setfield) X(lua_rawset) X(lua_rawseti) X(lua_setmetatable) X(lua_pcall) X(lua_error) X(lua_next) X(lua_newthread) X(lua_gc) X(luaL_newstate) X(lua_close) X(luaL_openlibs) X(luaL_loadbuffer)
#define X(n) extern void puc_##n(void);
PUC_NAMES
#undef X
static void *puc_symbol(void *library,const char *name){
    (void)library;
#define X(n) if(!strcmp(name,#n))return (void *)puc_##n;
    PUC_NAMES
#undef X
    return NULL;
}
#define dlopen(path,flags) ((void)(path),(void)(flags),(void *)&light_anchor)
#define dlsym puc_symbol
#endif
static HD2PucApi T;
static int (*puc_gc)(HD2PucState *,int,int);
static HD2PucState *(*puc_newstate)(void);
static void (*puc_close)(HD2PucState *);
static int fail(const char *what){fprintf(stderr,"FAIL %s\n",what);return 1;}
static int n_raise(HD2PucState *P,const char *s){T.pushlstring(P,s,strlen(s));return T.error(P);}
static int n_add(HD2PucState *P){T.pushnumber(P,T.tonumber(P,1)+T.tonumber(P,2));return 1;}
static int n_echo(HD2PucState *P){return T.gettop(P);}
static int n_store(HD2PucState *P){T.settop(P,2);T.getfield(P,HD2_PUC_REGISTRYINDEX,"bridge_test");T.insert(P,1);T.settable(P,1);return 0;}
static int n_load(HD2PucState *P){T.settop(P,1);T.getfield(P,HD2_PUC_REGISTRYINDEX,"bridge_test");T.insert(P,1);T.gettable(P,1);return 1;}
static int n_call(HD2PucState *P){
    if(T.pcall(P,T.gettop(P)-1,-1,0))return T.error(P);
    return T.gettop(P);
}
static int n_err(HD2PucState *P){return n_raise(P,"boom");}
static int n_ident(HD2PucState *P){T.pushboolean(P,T.rawequal(P,1,2));return 1;}
static int n_count(HD2PucState *P){int n=0;T.settop(P,1);T.pushnil(P);while(T.next(P,1)){n++;T.settop(P,-2);}T.pushnumber(P,n);return 1;}
static int n_light(HD2PucState *P){T.pushlightuserdata(P,&light_anchor);return 1;}
static int ud_index(HD2PucState *P){T.pushnumber(P,42);return 1;}
static int ud_tostring(HD2PucState *P){T.pushlstring(P,"TestUD",6);return 1;}
static int n_ud(HD2PucState *P){
    *(int *)T.newuserdata(P,sizeof(int))=7;T.getfield(P,HD2_PUC_REGISTRYINDEX,"bridge_test_mt");T.setmetatable(P,-2);return 1;
}
static int n_table(HD2PucState *P){
    T.createtable(P,0,2);T.pushnumber(P,1);T.setfield(P,-2,"x");T.createtable(P,0,1);T.pushnumber(P,2);T.setfield(P,-2,"y");T.setfield(P,-2,"nested");return 1;
}
static int closure_body(HD2PucState *P){T.pushvalue(P,HD2_PUC_UPVALUEINDEX(1));return 1;}
static int n_closure(HD2PucState *P){T.pushcclosure(P,closure_body,1);return 1;}
static void reg(HD2PucState *P,const char *name,HD2PucCFunction f){T.pushcclosure(P,f,0);T.setfield(P,-2,name);}
static const char script[]=
"hd2_bridge_line=0;function hd2_bridge_step()return hd2_bridge_line end\n"
"hd2_bridge_line=1;local T=stingray.Test\n"
"hd2_bridge_line=2;assert(T.add(2,3)==5)\n"
"hd2_bridge_line=3;local a,b,c,d=T.echo(1,'x',true,nil);assert(a==1 and b=='x' and c==true and d==nil and select('#',T.echo(1,nil,nil))==3)\n"
"hd2_bridge_line=4;local t={1,2,{3}};T.store('k',t);assert(T.load('k')==t,'table identity back from native storage')\n"
"hd2_bridge_line=5;local f=function(x)return x*2 end\n"
"hd2_bridge_line=6;assert(T.call(f,21)==42,'callback result');T.store('f',f);assert(T.load('f')==f,'function identity back')\n"
"hd2_bridge_line=7;assert(T.ident(f,f)==true,'cached callback proxy');assert(T.ident(t,t)==true,'one copy per table within a call')\n"
"hd2_bridge_line=8;local ok,err=pcall(T.err);assert(not ok and err:find('boom'),err)\n"
"hd2_bridge_line=9;local ok2,err2=pcall(T.call,function()error('inner')end);assert(not ok2 and err2:find('inner'),err2)\n"
"hd2_bridge_line=10;assert(T.call(function(y)return T.add(y,1)end,9)==10,'reentry')\n"
"hd2_bridge_line=11;assert(T.call(T.call,function(z)return T.call(f,z)end,4)==8,'nested reentry')\n"
"hd2_bridge_line=12;local u=T.ud();assert(type(u)=='userdata' and u.anything==42 and tostring(u)=='TestUD' and T.echo(u)==u and T.ud()~=u)\n"
"hd2_bridge_line=13;assert(T.count({a=1,b=2,3})==3)\n"
"hd2_bridge_line=14;local cyc={};cyc.self=cyc;cyc[cyc]=true;assert(T.count(cyc)==2 and T.echo(cyc)==cyc)\n"
"hd2_bridge_line=15;local mt={__index=function()return 5 end};local inst=setmetatable({},mt);assert(T.echo(inst)==inst)\n"
"hd2_bridge_line=16;assert(T.light()==T.light())\n"
"hd2_bridge_line=17;local r=T.newtable();assert(r.x==1 and r.nested.y==2 and T.newtable()~=r)\n"
"hd2_bridge_line=18;assert(T.echo(T)==T and T.echo(stingray)==stingray and T.echo(T.add)==T.add)\n"
"hd2_bridge_line=19;assert(not pcall(T.echo,coroutine.create(function()end)))\n"
"hd2_bridge_line=20;for i=1,2000 do T.store('tmp',{i,function()return i end});local p=T.closure(i);assert(p()==i) end\n"
"hd2_bridge_line=21;T.store('tmp',nil)\n"
"hd2_bridge_line=22;function hd2_bridge_after_gc()return T.add(1,1)end\n"
"hd2_bridge_line=23;T.store('where',function()return T.where()end)\n";
int main(void){
    void *puc=dlopen("/home/goose/Documents/Codex/2026-10-22/a-2/work/ffi-comparison/liblua514.so",RTLD_NOW|RTLD_LOCAL|RTLD_DEEPBIND);
    if(!puc)return fail(dlerror());
    static const char *names[]={"lua_gettop","lua_settop","lua_pushvalue","lua_remove","lua_insert","lua_replace","lua_checkstack",
        "lua_iscfunction","lua_type","lua_rawequal","lua_tonumber","lua_toboolean","lua_tolstring","lua_objlen","lua_tocfunction",
        "lua_touserdata","lua_topointer","lua_pushnil","lua_pushnumber","lua_pushlstring","lua_pushcclosure","lua_pushboolean",
        "lua_pushlightuserdata","lua_gettable","lua_getfield","lua_rawget","lua_rawgeti","lua_createtable","lua_newuserdata",
        "lua_getmetatable","lua_settable","lua_setfield","lua_rawset","lua_rawseti","lua_setmetatable","lua_pcall","lua_error",
        "lua_next","lua_newthread"};
    _Static_assert(sizeof(names)/sizeof(*names)==sizeof(HD2PucApi)/sizeof(void *),"one name per API field");
    void *entries[sizeof(names)/sizeof(*names)];
    for(size_t i=0;i<sizeof(entries)/sizeof(*entries);i++)if(!(entries[i]=dlsym(puc,names[i])))return fail(names[i]);
    memcpy(&T,entries,sizeof(T));
    *(void **)&puc_gc=dlsym(puc,"lua_gc");*(void **)&puc_newstate=dlsym(puc,"luaL_newstate");*(void **)&puc_close=dlsym(puc,"lua_close");
    HD2PucState *P=puc_newstate();
    void (*puc_openlibs)(HD2PucState *);*(void **)&puc_openlibs=dlsym(puc,"luaL_openlibs");puc_openlibs(P);
    T.createtable(P,0,0);T.setfield(P,HD2_PUC_REGISTRYINDEX,"bridge_test");
    T.createtable(P,0,2);reg(P,"__index",ud_index);reg(P,"__tostring",ud_tostring);T.setfield(P,HD2_PUC_REGISTRYINDEX,"bridge_test_mt");
    T.createtable(P,0,1);T.createtable(P,0,16);
    reg(P,"add",n_add);reg(P,"echo",n_echo);reg(P,"store",n_store);reg(P,"load",n_load);reg(P,"call",n_call);reg(P,"err",n_err);
    reg(P,"ident",n_ident);reg(P,"count",n_count);reg(P,"light",n_light);reg(P,"ud",n_ud);reg(P,"newtable",n_table);reg(P,"closure",n_closure);
    T.setfield(P,-2,"Test");T.setfield(P,HD2_PUC_GLOBALSINDEX,"stingray");
    T.pushcclosure(P,n_add,0);T.setfield(P,HD2_PUC_GLOBALSINDEX,"engine_global_add");
    /* A PUC Lua function: reports which PUC thread runs it. */
    {static const char where[]="stingray.Test.where=function()return tostring(coroutine.running())end";
     int (*puc_loadbuffer)(HD2PucState *,const char *,size_t,const char *);*(void **)&puc_loadbuffer=dlsym(puc,"luaL_loadbuffer");
     if(puc_loadbuffer(P,where,sizeof(where)-1,"=where")||T.pcall(P,0,0,0))return fail("where");}
    HD2Backend backend={0};char error[2048];
    HD2Environment *e=hd2env_create(NULL,0,&backend,error,sizeof(error));
    if(!e)return fail(error);
    /* The image-witness binder is replaced by the reference library here. */
    if(!enter(e))return fail("enter");
    e->puc=T;bridge_api=T;e->puc_main=P;e->bridge_roots="stingray,*";e->operation=20;
    if(!dispatch(e))return fail(hd2env_error(e));
    HD2BridgeStats s;hd2env_bridge_stats(e,&s);
    printf("mirrored roots=%u modules=%u kept=%u functions=%u tables=%u\n",s.roots,s.modules,s.modules_kept,s.functions,s.tables_mirrored);
    if(!hd2env_eval(e,script,sizeof(script)-1,"@bridge-test")){
        fprintf(stderr,"%s\n",hd2env_error(e));HD2Results r={0};
        if(hd2env_invoke(e,"hd2_bridge_step",NULL,0,&r)&&r.count)fprintf(stderr,"script line %g\n",r.values[0].as.number);
        return fail("script");
    }
    hd2env_bridge_stats(e,&s);
    printf("before gc: calls=%llu errors=%llu callbacks=%llu cb_errors=%llu live_lj=%u live_puc=%u to_native=%u from_native=%u\n",
        (unsigned long long)s.calls,(unsigned long long)s.errors,(unsigned long long)s.callbacks,(unsigned long long)s.callback_errors,
        s.live_lj_ids,s.live_puc_ids,s.tables_to_native,s.tables_from_native);
    /* Engine-style call: the main PUC thread calls the stored LuaJIT callback directly. */
    T.getfield(P,HD2_PUC_REGISTRYINDEX,"bridge_test");T.getfield(P,-1,"where");
    if(T.pcall(P,0,1,0))return fail("engine-style callback");
    {size_t wn;const char *w=T.tolstring(P,-1,&wn);printf("nested native thread from main-thread callback: %s\n",w);
     if(strcmp(w,"nil"))return fail("nested native did not run on the calling (main) thread");}
    T.settop(P,0);
    uint32_t before_lj=s.live_lj_ids,before_puc=s.live_puc_ids;
    for(int i=0;i<3;i++){
        puc_gc(P,2,0);
        const char *gc="collectgarbage('collect')";if(!hd2env_eval(e,gc,strlen(gc),"@gc"))return fail(hd2env_error(e));
        HD2Results r={0};if(!hd2env_invoke(e,"hd2_bridge_after_gc",NULL,0,&r))return fail(hd2env_error(e));hd2env_results_free(&r);
    }
    hd2env_bridge_stats(e,&s);
    printf("after gc: live_lj=%u (was %u) live_puc=%u (was %u) lj_released=%u puc_released=%u pending=%u\n",
        s.live_lj_ids,before_lj,s.live_puc_ids,before_puc,s.lj_released,s.puc_released,s.pending);
    if(s.live_lj_ids>64||s.live_puc_ids>64||s.lj_released<4000||s.puc_released<2000)return fail("release through both collectors");
    {   /* '*' mirrored an engine global LuaJIT lacked */
        const char *probe="assert(engine_global_add(20,22)==42,'star root')";
        if(!hd2env_eval(e,probe,strlen(probe),"@star"))return fail(hd2env_error(e));
    }
    {   /* Named forwarders follow the current LuaJIT global on every call. */
        const char *v1="hd2_frames=0;function update(dt)hd2_frames=hd2_frames+dt end";
        if(!hd2env_eval(e,v1,strlen(v1),"@update-v1"))return fail(hd2env_error(e));
        if(!hd2env_bridge_forward(e,"update,render"))return fail(hd2env_error(e));
        if(!hd2env_bridge_timed_gc(e,1))return fail("timed gc");
        T.getfield(P,HD2_PUC_GLOBALSINDEX,"update");T.pushnumber(P,2);if(T.pcall(P,1,0,0))return fail("forwarded update v1");
        const char *v2="local old=update;function update(dt)old(dt*10)end";
        if(!hd2env_eval(e,v2,strlen(v2),"@update-v2"))return fail(hd2env_error(e));
        T.getfield(P,HD2_PUC_GLOBALSINDEX,"update");T.pushnumber(P,3);if(T.pcall(P,1,0,0))return fail("forwarded update v2");
        T.getfield(P,HD2_PUC_GLOBALSINDEX,"render");if(T.pcall(P,0,0,0))return fail("absent LuaJIT render must be a no-op");
        HD2Results r={0};const char *get="function hd2_frames_get()return hd2_frames end";
        if(!hd2env_eval(e,get,strlen(get),"@get")||!hd2env_invoke(e,"hd2_frames_get",NULL,0,&r))return fail(hd2env_error(e));
        double frames=r.values[0].as.number;hd2env_results_free(&r);
        printf("forwarded update total=%g (expected 32)\n",frames);
        if(frames!=32)return fail("forwarder did not follow the current LuaJIT global");
        hd2env_bridge_stats(e,&s);if(s.forwarders!=2)return fail("forwarder count");
        printf("timed gc after forwarded updates: frames=%u failures=%u\n",s.gc_frames,s.gc_failures);
        if(s.gc_frames!=2||s.gc_failures)return fail("timed gc did not run once per forwarded update");
    }
    if(!hd2env_destroy(e))return fail("destroy");
    /* A native caller still holding a LuaJIT callback gets a Lua error, not a crash. */
    T.getfield(P,HD2_PUC_GLOBALSINDEX,"update");T.pushnumber(P,1);
    if(!T.pcall(P,1,0,0))return fail("forwarder after destroy must raise a Lua error");
    T.settop(P,0);
    T.getfield(P,HD2_PUC_REGISTRYINDEX,"bridge_test");T.getfield(P,-1,"f");T.pushnumber(P,1);
    int status=T.pcall(P,1,1,0);size_t n;const char *message=T.tolstring(P,-1,&n);
    printf("stale callback: status=%d message=%s\n",status,message?message:"(none)");
    if(!status||!message||!strstr(message,"bridge closed"))return fail("stale callback");
    T.settop(P,0);puc_gc(P,2,0);puc_close(P);
    printf("PASS bridge offline\n");
    return 0;
}
