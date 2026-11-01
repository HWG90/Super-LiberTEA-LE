#ifndef HD2_NATIVE_PUC_H
#define HD2_NATIVE_PUC_H
#include "native_steam.h"
/* The game's statically linked PUC Lua 5.1 API (build 26088801). Original
 * native callbacks inline PUC stack/TValue layouts, so the bridge runs them
 * unchanged on a dedicated PUC host thread while LuaJIT owns all scripts.
 * Field order matches work/puc_witnesses.h; every entry is witness-checked. */
typedef struct HD2PucState HD2PucState;
typedef int (HD2_NATIVE_ABI *HD2PucCFunction)(HD2PucState *);
typedef struct {
    int (HD2_NATIVE_ABI *gettop)(HD2PucState *);
    void (HD2_NATIVE_ABI *settop)(HD2PucState *,int);
    void (HD2_NATIVE_ABI *pushvalue)(HD2PucState *,int);
    void (HD2_NATIVE_ABI *remove)(HD2PucState *,int);
    void (HD2_NATIVE_ABI *insert)(HD2PucState *,int);
    void (HD2_NATIVE_ABI *replace)(HD2PucState *,int);
    int (HD2_NATIVE_ABI *checkstack)(HD2PucState *,int);
    int (HD2_NATIVE_ABI *iscfunction)(HD2PucState *,int);
    int (HD2_NATIVE_ABI *type)(HD2PucState *,int);
    int (HD2_NATIVE_ABI *rawequal)(HD2PucState *,int,int);
    double (HD2_NATIVE_ABI *tonumber)(HD2PucState *,int);
    int (HD2_NATIVE_ABI *toboolean)(HD2PucState *,int);
    const char *(HD2_NATIVE_ABI *tolstring)(HD2PucState *,int,size_t *);
    size_t (HD2_NATIVE_ABI *objlen)(HD2PucState *,int);
    HD2PucCFunction (HD2_NATIVE_ABI *tocfunction)(HD2PucState *,int);
    void *(HD2_NATIVE_ABI *touserdata)(HD2PucState *,int);
    const void *(HD2_NATIVE_ABI *topointer)(HD2PucState *,int);
    void (HD2_NATIVE_ABI *pushnil)(HD2PucState *);
    void (HD2_NATIVE_ABI *pushnumber)(HD2PucState *,double);
    void (HD2_NATIVE_ABI *pushlstring)(HD2PucState *,const char *,size_t);
    void (HD2_NATIVE_ABI *pushcclosure)(HD2PucState *,HD2PucCFunction,int);
    void (HD2_NATIVE_ABI *pushboolean)(HD2PucState *,int);
    void (HD2_NATIVE_ABI *pushlightuserdata)(HD2PucState *,void *);
    void (HD2_NATIVE_ABI *gettable)(HD2PucState *,int);
    void (HD2_NATIVE_ABI *getfield)(HD2PucState *,int,const char *);
    void (HD2_NATIVE_ABI *rawget)(HD2PucState *,int);
    void (HD2_NATIVE_ABI *rawgeti)(HD2PucState *,int,int);
    void (HD2_NATIVE_ABI *createtable)(HD2PucState *,int,int);
    void *(HD2_NATIVE_ABI *newuserdata)(HD2PucState *,size_t);
    int (HD2_NATIVE_ABI *getmetatable)(HD2PucState *,int);
    void (HD2_NATIVE_ABI *settable)(HD2PucState *,int);
    void (HD2_NATIVE_ABI *setfield)(HD2PucState *,int,const char *);
    void (HD2_NATIVE_ABI *rawset)(HD2PucState *,int);
    void (HD2_NATIVE_ABI *rawseti)(HD2PucState *,int,int);
    int (HD2_NATIVE_ABI *setmetatable)(HD2PucState *,int);
    int (HD2_NATIVE_ABI *pcall)(HD2PucState *,int,int,int);
    int (HD2_NATIVE_ABI *error)(HD2PucState *);
    int (HD2_NATIVE_ABI *next)(HD2PucState *,int);
    HD2PucState *(HD2_NATIVE_ABI *newthread)(HD2PucState *);
} HD2PucApi;
#define HD2_PUC_REGISTRYINDEX (-10000)
#define HD2_PUC_GLOBALSINDEX (-10002)
#define HD2_PUC_UPVALUEINDEX(i) (HD2_PUC_GLOBALSINDEX-(i))
/* Checks PE identity and all 39 entry witnesses, then fills api with entries
 * in the current image. No engine code runs. 0 if refused (api untouched). */
HD2ENV_API int hd2puc_bind(HD2PucApi *api,const HD2SteamHost *host);
typedef struct {
    uint64_t calls,errors,callbacks,callback_errors;
    uint32_t roots,modules,modules_kept,merged,kept,functions,lua_functions,tables_mirrored;
    uint32_t function_proxies,userdata_proxies,tables_from_native,tables_to_native,callbacks_to_native,opaque_to_native;
    uint32_t lj_released,puc_released,live_lj_ids,live_puc_ids,pending,forwarders,gc_frames,gc_failures;
} HD2BridgeStats;
/* Mirrors the comma-separated PUC globals in roots (e.g. "stingray") into this
 * LuaJIT state through the native bridge. puc_state must be the PUC thread that
 * is currently running (the caller is a C function on it); a dedicated host
 * thread is created from it and anchored in the PUC registry. Register the
 * validated ports first: they stay authoritative. Destroying the environment
 * detaches all proxies; native code that later calls one gets a Lua error. */
HD2ENV_API int hd2env_register_bridge(HD2Environment *,const HD2SteamHost *,uintptr_t puc_state,const char *roots);
HD2ENV_API int hd2env_bridge_stats(const HD2Environment *,HD2BridgeStats *);
/* Points each comma-separated PUC global (e.g. "init,update,render,shutdown")
 * at a forwarder that calls the LuaJIT global of that name, resolved per call. */
HD2ENV_API int hd2env_bridge_forward(HD2Environment *,const char *names);
/* After each forwarded engine update, run the engine's timed collector policy
 * (hd2env_collect_frame) for LuaJIT; this stops LuaJIT's automatic GC. */
HD2ENV_API int hd2env_bridge_timed_gc(HD2Environment *,int enabled);
#endif
