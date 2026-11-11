/* Boot handoff (build 26088801). The patched boot script calls
 * luaopen_hd2_luajit_boot through package.loadlib while the engine is still in
 * require(boot_script), on its PUC VM. It creates LuaJIT, keeps the validated
 * ports, bridges every other native, runs LLL's exact boot source in LuaJIT and
 * points the engine's named callbacks (init/update/render/shutdown) at LuaJIT.
 * It returns false, message when it fails before LLL starts in LuaJIT. The
 * environment is then destroyed and the caller runs LLL in PUC as before.
 * Boot-time memory access uses the runtime's own checked in-process host, as
 * approved by the user; Link's Link to Memory is not loaded yet at boot. */
#include "native_resources.h"
#include "handoff_assets.h"
#ifdef HD2ENV_LLL_HOST
#include "lll_host.h"
#endif
#include <stdarg.h>
static HD2Environment *handoff_env;
static void handoff_log(const char *format,...) {
    const char *base=getenv("LOCALAPPDATA");char path[1024];
    if(!base||snprintf(path,sizeof(path),"%s/LLL/Helldivers2/Logs/LuaJITBoot.log",base)>=(int)sizeof(path))return;
    FILE *f=fopen(path,"ab");if(!f)return;
    time_t now=time(NULL);char stamp[32];strftime(stamp,sizeof(stamp),"%Y-%m-%d %H:%M:%S",localtime(&now));
    fprintf(f,"%s ",stamp);va_list a;va_start(a,format);vfprintf(f,format,a);va_end(a);fputc('\n',f);fclose(f);
}
/* Runs in LuaJIT before LLL. The scratch globals are set from PUC just before
 * bridging and removed again here. */
static const char handoff_setup[]=
"local puc_loadlib,puc_path,puc_cpath=__hd2_puc_loadlib,__hd2_puc_path,__hd2_puc_cpath\n"
"__hd2_puc_loadlib,__hd2_puc_path,__hd2_puc_cpath=nil,nil,nil\n"
"POC,Wwise=nil,nil\n"
"assert(type(puc_loadlib)=='function','PUC package.loadlib unavailable')\n"
"if type(puc_path)=='string' then package.path=puc_path end\n"
"if type(puc_cpath)=='string' then package.cpath=puc_cpath end\n"
"local ffi=require('ffi')\n"
"-- LLL's cffi loader checks cdef/load/typeof/new/cast/tonumber. LuaJIT's ffi\n"
"-- provides all but tonumber, which LuaJIT handles with the global.\n"
"local cffi=setmetatable({tonumber=tonumber},{__index=ffi})\n"
"-- C modules were built for the game's PUC VM: they stay there, reached\n"
"-- through the bridge. Passing them a LuaJIT state would corrupt memory.\n"
"package.loadlib=function(path,symbol)\n"
" if symbol=='luaopen_hd2_cffi' then return function()return cffi end end\n"
" return puc_loadlib(path,symbol)\n"
"end\n"
"local function c_loader(name)\n"
" local path,why=package.searchpath(name,package.cpath)\n"
" if not path then return '\\n\\t'..tostring(why) end\n"
" local entry,err=puc_loadlib(path,'luaopen_'..name:gsub('%.','_'))\n"
" if not entry then error(err,2) end\n"
" return entry\n"
"end\n"
"local loaders=package.loaders\n"
"for i=#loaders,4,-1 do loaders[i]=nil end\n"
"loaders[4]=c_loader\n";
/* The two LuaJIT-side boot steps, also exported so live probes run the exact
 * embedded chunks. */
HD2ENV_API int hd2env_handoff_setup(HD2Environment *e) {
    return hd2env_eval(e,handoff_setup,sizeof(handoff_setup)-1,"@hd2/luajit_handoff")&&
           hd2env_eval(e,(const char *)handoff_discovery_source,sizeof(handoff_discovery_source),"@src/discovery_hash.lua");
}
HD2ENV_API int hd2env_handoff_run_lll(HD2Environment *e) {
    return hd2env_eval(e,(const char *)handoff_lll_source,HANDOFF_LLL_SIZE,"@native-font-repair");
}
/* The boot's translation table (stock PUC chunks and legacy FR1 mod chunks),
 * for probes that must create environments exactly as the boot does. */
HD2ENV_API const HD2Asset *hd2env_handoff_assets(size_t *count) {
    if(count)*count=sizeof(handoff_assets)/sizeof(*handoff_assets);
    return handoff_assets;
}
/* The engine's shutdown, forwarded like the other callbacks, with log lines so
 * a missing LuaJIT shutdown is visible after the fact. */
static int HD2_NATIVE_ABI handoff_shutdown(HD2PucState *P) {
    handoff_log("engine shutdown: forwarding to LuaJIT");
    int r=puc_call_into_lj(P,bridge_api.touserdata(P,HD2_PUC_UPVALUEINDEX(1)),"shutdown");
    handoff_log("engine shutdown: LuaJIT shutdown returned");
    return r;
}
static int handoff_fail(HD2PucState *P,const HD2PucApi *api,const char *message) {
    handoff_log("handoff refused: %s",message);
    if(handoff_env){hd2env_destroy(handoff_env);handoff_env=NULL;}
    if(api){
        static const char *scratch[]={"__hd2_puc_loadlib","__hd2_puc_path","__hd2_puc_cpath"};
        for(size_t i=0;i<3;i++){api->pushnil(P);api->setfield(P,HD2_PUC_GLOBALSINDEX,scratch[i]);}
        api->pushboolean(P,0);api->pushlstring(P,message,strlen(message));return 2;
    }
    return 0;
}
HD2ENV_API int HD2_NATIVE_ABI luaopen_hd2_luajit_boot(HD2PucState *P) {
    HD2SteamHost host;HD2PucApi api;
    if(handoff_env)return 0; /* one handoff per process */
    if(!hd2env_current_steam_host(&host)){handoff_log("handoff refused: host identity (build 26568081 required)");return 0;}
    if(!hd2puc_bind(&api,&host)){handoff_log("handoff refused: PUC API witnesses");return 0;}
    /* With --use-d3d11 the boot script can run before code on the vector ports'
     * pages has (2026-11-04: Vector2 refused on the pool allocator's page
     * +0x9f000, the getter's). Calling each original vector native once makes
     * the game decrypt those pages, as stock scripts would moments later; every
     * witness below is then checked as on a normal start. */
    {
        char why[256];int failed=0,ran=hd2puc_warm_vectors(&api,P,&failed,why,sizeof(why));
        if(ran<0)handoff_log("vector warm-up skipped: %s",why);
        else handoff_log("vector warm-up: %d original calls, %d raised",ran,failed);
    }
    /* The LuaEnvironment getter exe+0x9fc00 is registry[1] as a userdata pointer
     * (hd2puc_lua_environment, through the witnessed API). The game decrypts code
     * on first use, and with --use-d3d11 the getter's page can still be no-access
     * when the boot script runs (reported 2026-11-03). A resident getter must
     * match its witness and agree with registry[1]; a page not yet decrypted
     * leaves registry[1] alone, whose layout the resource reader checks next. */
    char reason[256],message[320];uintptr_t getter=host.image_base+0x9fc00;
    uintptr_t environment=(uintptr_t)hd2puc_lua_environment(&api,P);
    switch(hd2env_check_code(&host,getter,handoff_getter_witness,sizeof(handoff_getter_witness),reason,sizeof(reason))){
    case HD2_CODE_MATCH:
        if((uintptr_t)((void *(HD2_NATIVE_ABI *)(void *))getter)(P)!=environment)
            return handoff_fail(P,&api,"LuaEnvironment getter and registry[1] differ");
        handoff_log("LuaEnvironment: getter witness matches and agrees with registry[1]");
        break;
    case HD2_CODE_NOT_RESIDENT:
        handoff_log("LuaEnvironment getter %s: environment taken from registry[1] through the PUC API",reason);
        break;
    default:
        snprintf(message,sizeof(message),"LuaEnvironment getter witness: %s",reason);
        return handoff_fail(P,&api,message);
    }
    if(!environment)return handoff_fail(P,&api,"native LuaEnvironment unavailable");
    HD2EngineResources *resources=hd2resources_open(&host,environment);
    if(!resources){
        snprintf(message,sizeof(message),"engine resource reader refused: %s",hd2resources_error(NULL));
        return handoff_fail(P,&api,message);
    }
    HD2Backend backend={0};
    if(!hd2resources_bind(resources,&backend))return handoff_fail(P,&api,hd2resources_error(resources));
    char error[2048];
    handoff_env=hd2env_create(handoff_assets,sizeof(handoff_assets)/sizeof(*handoff_assets),&backend,error,sizeof(error));
    if(!handoff_env)return handoff_fail(P,&api,error);
    HD2Environment *e=handoff_env;
#define HANDOFF_STEP(call) do{if(!(call))return handoff_fail(P,&api,hd2env_error(e));}while(0)
    HANDOFF_STEP(hd2env_register_vector2(e,&host,environment));
    HANDOFF_STEP(hd2env_register_vector3(e));HANDOFF_STEP(hd2env_register_vector3box(e));
    HANDOFF_STEP(hd2env_register_vector4(e));
    /* Quaternion and Matrix4x4 call engine helpers on pages the game unpacks on
     * first execution; at boot those can still be unreadable, so the witness
     * check refuses (first LuaJIT boot, 21:01). The bridge then serves the
     * original natives for Quaternion, Matrix4x4 and both box types, which is
     * exact by construction. Each later port depends on the one before it. */
    const char *ported="Quaternion, Matrix4x4, QuaternionBox, Matrix4x4Box";
    if(!hd2env_register_quaternion(e)){handoff_log("Quaternion port deferred, originals bridged: %s",hd2env_error(e));ported="none";}
    else if(!hd2env_register_matrix4x4(e)){handoff_log("Matrix4x4 port deferred, originals bridged: %s",hd2env_error(e));ported="Quaternion";}
    else if(!hd2env_register_boxes(e)){handoff_log("box ports deferred, originals bridged: %s",hd2env_error(e));ported="Quaternion, Matrix4x4";}
    handoff_log("ports: Vector2, Vector3, Vector3Box, Vector4; optional ports registered: %s",ported);
    int top=api.gettop(P);
    api.getfield(P,HD2_PUC_GLOBALSINDEX,"package");
    if(api.type(P,-1)!=5){api.settop(P,top);return handoff_fail(P,&api,"PUC package table unavailable");}
    api.getfield(P,-1,"loadlib");api.setfield(P,HD2_PUC_GLOBALSINDEX,"__hd2_puc_loadlib");
    api.getfield(P,-1,"path");api.setfield(P,HD2_PUC_GLOBALSINDEX,"__hd2_puc_path");
    api.getfield(P,-1,"cpath");api.setfield(P,HD2_PUC_GLOBALSINDEX,"__hd2_puc_cpath");
    api.settop(P,top);
    HANDOFF_STEP(hd2env_register_bridge(e,&host,(uintptr_t)P,"stingray,print,print_warning,*"));
    static const char *scratch[]={"__hd2_puc_loadlib","__hd2_puc_path","__hd2_puc_cpath"};
    for(size_t i=0;i<3;i++){api.pushnil(P);api.setfield(P,HD2_PUC_GLOBALSINDEX,scratch[i]);}
    HANDOFF_STEP(hd2env_handoff_setup(e));
#ifdef HD2ENV_LLL_HOST
    /* The embedded LLL's Steam service runs in-process (lll_host.c). Without it that LLL cannot start, so a failure
     * here refuses the handoff and PUC LLL runs with its helper as before. */
    {char why[256];if(!lll_host_register(e->L,why,sizeof(why)))return handoff_fail(P,&api,why);}
    handoff_log("LLL in-process service registered: hd2.lll_host v1 (no Steam helper, launcher, cffi or nativeinfo DLL)");
#endif
    handoff_log("LuaJIT ready: %s; running LLL boot source %s (%u bytes)",LUAJIT_VERSION,HANDOFF_LLL_SHA256,HANDOFF_LLL_SIZE);
    /* LLL's finish() runs the stock boot first and then start() under pcall, so
     * a failure here precedes LLL itself: PUC LLL is still a clean fallback. */
    HANDOFF_STEP(hd2env_handoff_run_lll(e));
    HANDOFF_STEP(hd2env_bridge_forward(e,"init,update,render,shutdown"));
    HANDOFF_STEP(hd2env_bridge_timed_gc(e,1));
    {
        HD2PucState *H=e->puc_host;int top=api.gettop(H);
        puc_new_guard(e,H,0);api.pushcclosure(H,handoff_shutdown,1);
        api.setfield(H,HD2_PUC_GLOBALSINDEX,"shutdown");api.settop(H,top);
    }
#undef HANDOFF_STEP
    HD2BridgeStats st;hd2env_bridge_stats(e,&st);
    handoff_log("handoff complete: %u modules mirrored, %u ports kept, %u natives, %u forwarders, timed GC on",
        st.modules,st.modules_kept,st.functions,st.forwarders);
    api.pushboolean(P,1);return 1;
}
