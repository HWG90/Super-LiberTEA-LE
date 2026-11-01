#ifndef HD2_SHUTDOWN_ROUTES_H
#define HD2_SHUTDOWN_ROUTES_H
#include "lifecycle_routes.h"
typedef struct {uintptr_t shutdown,collect;} HD2ShutdownTargets;
typedef struct {
    uint32_t rva;size_t size;
    unsigned char original[160],replacement[160];
} HD2ShutdownPatch;
/* Pure planner for the complete pinned native game destructor. Three patches
 * replace the named Lua call, inline PUC full collection and threshold store.
 * Native hook flags, plugin/service cleanup and environment destruction remain
 * in the captured caller. Refusal leaves output unchanged. No writes/hooks. */
HD2ENV_API int hd2env_plan_shutdown_patches(const void *rva_image,size_t image_size,
    const HD2ShutdownTargets *,HD2ShutdownPatch out[3]);
/* Win64 entries receive native_environment, NOT the game or lua_State pointer.
 * Requires a native-owned association; if boot-bound, boot must be complete.
 * Named shutdown errors are reported through the frame reporter, then collection
 * still runs. Propagated collection errors and invalid/recursive/out-of-order entries call
 * the factory's nonreturning fatal handler. Frames are refused once shutdown
 * begins. LuaJIT handles finalizer errors through its own ERRFIN event; those
 * do not propagate through lua_gc in the pinned runtime. Host/backend data
 * must remain alive through final native close. */
HD2ENV_API int hd2env_get_shutdown_targets(HD2ShutdownTargets *out);
/* Lua shutdown and full collection finished; native cleanup/close follows. */
HD2ENV_API int hd2env_native_shutdown_complete(const HD2Environment *);
#endif
