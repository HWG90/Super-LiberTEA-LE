#ifndef HD2_BOOT_ROUTES_H
#define HD2_BOOT_ROUTES_H
#include "lifecycle_routes.h"
enum { HD2_BOOT_CORE, HD2_BOOT_STEAM, HD2_BOOT_LEADERBOARD, HD2_BOOT_ACHIEVEMENTS,
       HD2_BOOT_CLOUD, HD2_BOOT_NETWORK, HD2_BOOT_FRIENDS, HD2_BOOT_VOIP, HD2_BOOT_REGISTRARS };
enum { HD2_BOOT_PATCHES=13 };
typedef struct { uintptr_t registrars[HD2_BOOT_REGISTRARS],configure,start; } HD2BootTargets;
typedef struct {
    void *context;
    /* Required replacement for each original registrar, in the order above.
     * args are borrowed native context values, never PUC objects. Network has
     * five args: service, peer, session, borrowed config view, boolean. The host
     * must port both bindings and native context stores; calling an old PUC
     * registrar is invalid. This interface does not supply those ports. */
    int (*register_stage)(void *context,HD2Environment *,unsigned stage,
                          const uintptr_t *args,size_t count);
    /* Read exactly size bytes into out, returning 1, or return 0. The host must
     * validate native memory and keep it stable for this synchronous call.
     * No native address is dereferenced by the replacement core itself. */
    int (*read_native)(void *context,uintptr_t address,void *out,size_t size);
} HD2BootCallbacks;
/* Bind once on the creating thread before native boot. A native factory can
 * bind its fresh environment before returning it. Callback data lives through
 * destruction. Frames are refused until all registration/config/init stages
 * complete; a bad native entry or failed stage invokes the factory fatal path.
 * Host callbacks may call the public core but cannot destroy the environment. */
HD2ENV_API int hd2env_bind_boot(HD2Environment *,const HD2BootCallbacks *);
HD2ENV_API int hd2env_boot_complete(const HD2Environment *);
HD2ENV_API int hd2env_get_boot_targets(HD2BootTargets *);
/* Pure planner, no installation. Whole boot-function witness required. The
 * eight registrar targets must be reachable by rel32 (use nearby leaf stubs).
 * Output remains unchanged on refusal. Native setup/plugin calls are kept;
 * their VM interactions still need auditing before live installation. */
HD2ENV_API int hd2env_plan_boot_patches(const void *image,size_t size,uintptr_t base,
                                      const HD2BootTargets *,HD2LifecyclePatch out[HD2_BOOT_PATCHES]);
#endif
