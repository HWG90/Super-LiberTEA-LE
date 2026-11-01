#ifndef HD2_LIFECYCLE_ROUTES_H
#define HD2_LIFECYCLE_ROUTES_H
#include "frame_routes.h"

typedef struct { uintptr_t construct,close;HD2FrameTargets frames; } HD2LifecycleTargets;
typedef struct {
    uint32_t rva;
    size_t size;
    unsigned char original[512],replacement[512];
} HD2LifecyclePatch;
typedef struct {
    void *context;
    /* Return a fresh, unbound environment on this thread, transferring its
     * ownership to the bridge. Fill its frame policy/reporter. On failure,
     * return NULL and write a diagnostic. The host retains asset/backend data. */
    HD2Environment *(*create)(void *context,void *native_environment,void *resource_manager,
                             HD2FrameCallbacks *,char *error,size_t capacity);
    /* Called after Lua finalizers and core destruction; release host backend
     * data here. Native object/allocator memory still belongs to the engine. */
    void (*closed)(void *context,void *native_environment);
    /* Required failure handler. The bridge aborts if it returns: a partially
     * constructed/closed engine environment must not continue. */
    void (*fatal)(void *context,void *native_environment,const char *operation,const char *message);
} HD2NativeFactory;

/* Prepare this creating thread before any native constructors run. No hooks
 * are installed. Configuration cannot change while it owns any states or a
 * factory callback is active. Entry points use Win64 ABI on x64 hosts.
 * They never write a state pointer into the native environment. */
HD2ENV_API int hd2env_set_native_factory(const HD2NativeFactory *,HD2LifecycleTargets *out);
HD2ENV_API int hd2env_clear_native_factory(void);
HD2ENV_API size_t hd2env_native_state_count(void);

/* Pure planner for the pinned constructor and destructor. Constructor native
 * bookkeeping and destructor native cleanup stay intact. The close target must
 * be reachable by rel32 from image_base+0x4ed4da; the embedding host may supply
 * a nearby leaf jump stub. No such stub is allocated or installed here.
 * Complete function witnesses are checked; refused output is unchanged.
 * These routes alone are not a complete or installable VM replacement. */
HD2ENV_API int hd2env_plan_lifecycle_patches(const void *rva_image,size_t image_size,
    uintptr_t image_base,const HD2LifecycleTargets *,HD2LifecyclePatch out[2]);
#endif
