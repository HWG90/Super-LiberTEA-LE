#ifndef HD2_NATIVE_STEAM_H
#define HD2_NATIVE_STEAM_H
#include "environment.h"
/* Overridable only for tests that substitute a host-ABI PUC library. */
#ifndef HD2_NATIVE_ABI
#if defined(_WIN32)
#define HD2_NATIVE_ABI
#else
#define HD2_NATIVE_ABI __attribute__((ms_abi))
#endif
#endif
/* Synchronous native memory/function access. The host keeps the image, service
 * object, vtable, code and returned strings alive on the creating thread.
 * read/write return 1 only after transferring the entire region. callable
 * validates an executable entry. None may reenter Lua or throw exceptions. */
typedef struct {
    void *context;
    uintptr_t image_base;
    int (*read)(void *,uintptr_t,void *,size_t);
    int (*write)(void *,uintptr_t,const void *,size_t);
    int (*callable)(void *,uintptr_t);
} HD2SteamHost;
/* Checks PE identity and full pinned registrar/callback/helper witnesses plus
 * the language table. No engine code runs and no memory is modified. */
HD2ENV_API int hd2env_probe_steam_host(const HD2SteamHost *);
/* Supplies guarded access to the current Windows EXE. Refused output is intact.
 * Linux hosts can provide explicit owned-image access for isolated execution. */
HD2ENV_API int hd2env_current_steam_host(HD2SteamHost *out);
/* Port of registrar 0x7f4ac0. Stores service in EXE+0x2860608, creates/reuses
 * the registry module and installs all eleven replacement callbacks. Null
 * service only stores null, matching the original. Calls use Win64 vtable ABI,
 * never a PUC initializer or lua_State. Native slot lifetime is engine-owned;
 * destroying this environment does not clear it. Registration failure may leave
 * partial Lua table changes, as with the original; native boot must fail closed.
 * Host callback/context ownership remains with the embedding application. */
HD2ENV_API int hd2env_register_steam(HD2Environment *,const HD2SteamHost *,uintptr_t service);
#endif
