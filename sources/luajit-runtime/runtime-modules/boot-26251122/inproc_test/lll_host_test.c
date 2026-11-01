/* Offline check of LLL's in-process service as the runtime registers it (../../vm-poc/lll_host.c), under Wine:
 *   lll_host_test.exe <game root> <LLL checkout> <script>
 * Creates a LuaJIT state, registers hd2.lll_host as the handoff does and runs the script (lll_platform_test.lua),
 * which loads LLL's unchanged src/steam/platform.lua over src/steam/transport_inproc.lua. The game root only feeds
 * the handshake's stock hash check, as the running game's own paths do in the runtime. */
#define LLL_INPROC_PATHS test_paths
#include <windows.h>
#include <stdio.h>
#include <wchar.h>
static wchar_t test_root[32768];
static int test_paths(wchar_t executable[32768], wchar_t game[32768]) {
    swprintf_s(executable, 32768, L"%s\\bin\\helldivers2.exe", test_root);
    swprintf_s(game, 32768, L"%s\\data\\game\\game.dll", test_root);
    return 1;
}
#include "../../vm-poc/lll_host.c"
#include "lualib.h"

int wmain(int count, wchar_t **arguments) {
    char why[256], checkout[4 * MAX_PATH], script[4 * MAX_PATH];
    lua_State *L;
    if (count != 4) { printf("usage: lll_host_test.exe <game root> <LLL checkout> <script>\n"); return 2; }
    wcscpy_s(test_root, 32768, arguments[1]);
    WideCharToMultiByte(CP_UTF8, 0, arguments[2], -1, checkout, sizeof(checkout), NULL, NULL);
    WideCharToMultiByte(CP_UTF8, 0, arguments[3], -1, script, sizeof(script), NULL, NULL);
    L = luaL_newstate();
    luaL_openlibs(L);
    if (!lll_host_register(L, why, sizeof(why))) { printf("FAIL %s\n", why); return 1; }
    lua_pushstring(L, checkout); lua_setglobal(L, "LLL_CHECKOUT");
    if (luaL_dofile(L, script)) { printf("FAIL %s\n", lua_tostring(L, -1)); return 1; }
    lua_close(L);
    return 0;
}
