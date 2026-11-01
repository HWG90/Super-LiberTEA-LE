#ifndef HD2_FRAME_ROUTES_H
#define HD2_FRAME_ROUTES_H
#include "environment.h"

/* Win64 callback ABI required. gc/update/render receive the native environment
 * address, not a lua_State. update's second argument is float (XMM1), not double.
 * Targets resolve that address to the replacement environment. */
typedef struct { uintptr_t gc,update,render; } HD2FrameTargets;
typedef struct {
    void *context;
    /* Optional collection override. NULL uses the captured timed scheduler
     * backed by LuaJIT. Return 1 on success, 0 on failure. Public core operations
     * may be called here; no PUC state or direct VM access needed. */
    int (*collect)(void *context,HD2Environment *);
    /* Required new reporter; never pass these arguments to the old LuaObject
     * reporter. Message is borrowed for this call. Native exceptions must not
     * escape either callback. Original engine TLS/error parity is not supplied. */
    void (*report_error)(void *context,HD2Environment *,const char *operation,const char *message);
} HD2FrameCallbacks;
typedef struct {
    uint32_t rva;
    size_t size;
    unsigned char original[192],replacement[192];
} HD2FramePatch;

/* Pure planner: checks complete captured callers and emits two byte patches.
 * It never changes memory/protections or runs code. All output is unchanged on
 * refusal. These patches are only part of the required integration, not an
 * installer; no stock process should run with only these routes replaced. */
HD2ENV_API int hd2env_plan_frame_patches(const void *rva_image,size_t image_size,
                                        const HD2FrameTargets *,HD2FramePatch out[2]);
/* Associate an opaque native environment address with its replacement on the
 * creating thread. With native vectors registered, this must be their owning
 * environment: update/render invalidate its temporary pool through the checked
 * host before calling Lua. Without that binding, addresses remain opaque.
 * One association per state
 * and address; bindings are removed by unbind or environment destruction.
 * Callbacks/context must outlive the association. No memory is patched.
 * Successful output uses Win64 entry ABI even when built on x64 Linux.
 * Refusals leave targets unchanged. Unbind/destroy are refused inside a frame
 * route, including its collection and reporting callbacks. Factory-owned states
 * cannot be unbound separately from their native lifecycle destruction. */
HD2ENV_API int hd2env_bind_frames(HD2Environment *,void *native_environment,
                                const HD2FrameCallbacks *,HD2FrameTargets *out);
HD2ENV_API int hd2env_unbind_frames(HD2Environment *);
/* Per-thread, saturating counter for missing/wrong-thread associations and
 * recursive entries. Such calls perform no Lua operation. Embedding must
 * monitor this counter; a missing association has no reporter to call. */
HD2ENV_API uint64_t hd2env_frame_fault_count(void);
#endif
