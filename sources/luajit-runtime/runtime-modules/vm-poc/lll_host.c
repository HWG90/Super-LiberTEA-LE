/* LLL's in-process Steam service for the embedded LLL in LuaJIT mode: LLL's native/steam_inproc.c (copied unchanged
 * into lll_native/ with steam_pointer.c and steam_keyboard.c; lll_native/SHA256SUMS pins them and names the LLL
 * commit). The embedded LLL's transport_inproc.lua requires hd2.lll_host and casts its three light-userdata C
 * function pointers with ffi, the pattern services.c uses for hd2.memory, so the runtime gains no exports. With it
 * LLL needs no Steam helper, launcher, cffi or nativeinfo DLL. */
#include "lll_native/steam_inproc.c"
#include "lauxlib.h"
#include "lll_host.h"

static int lll_host_module(lua_State *L) {
    lua_createtable(L, 0, 4);
    lua_pushinteger(L, 1); lua_setfield(L, -2, "version");
    lua_pushlightuserdata(L, (void *)(uintptr_t)lll_inproc_exchange); lua_setfield(L, -2, "exchange");
    lua_pushlightuserdata(L, (void *)(uintptr_t)lll_inproc_read_memory); lua_setfield(L, -2, "read_memory");
    lua_pushlightuserdata(L, (void *)(uintptr_t)lll_inproc_module_base); lua_setfield(L, -2, "module_base");
    return 1;
}

/* Runs under lua_cpcall, so a missing table or memory error is returned, not thrown into the handoff. */
static int lll_host_preload(lua_State *L) {
    lua_getfield(L, LUA_GLOBALSINDEX, "package");
    if (!lua_istable(L, -1)) return luaL_error(L, "no package table");
    lua_getfield(L, -1, "preload");
    if (!lua_istable(L, -1)) return luaL_error(L, "no package.preload table");
    lua_pushcfunction(L, lll_host_module);
    lua_setfield(L, -2, "hd2.lll_host");
    return 0;
}

int lll_host_register(lua_State *L, char *why, size_t why_size) {
    int top = lua_gettop(L);
    if (lua_cpcall(L, lll_host_preload, NULL) == 0) {
        lua_settop(L, top);
        return 1;
    }
    if (why && why_size) {
        const char *message = lua_tostring(L, -1);
        snprintf(why, why_size, "LLL in-process service: %s", message ? message : "registration failed");
    }
    lua_settop(L, top);
    return 0;
}
