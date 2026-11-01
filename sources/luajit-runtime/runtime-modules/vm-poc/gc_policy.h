#ifndef HD2_GC_POLICY_H
#define HD2_GC_POLICY_H
#include "environment.h"

typedef struct { float start_growth, growth_range, full_growth, min_ms, max_ms; } HD2GCSettings;
typedef struct { int32_t peak, previous_peak, floor, previous_floor; } HD2GCHistory;
typedef struct {
    void *context;
    int (*frequency)(void *, int64_t *);
    int (*counter)(void *, int64_t *);
} HD2GCClock;
typedef struct {
    int32_t total_kb, estimate_kb;
    float growth, budget_ms;
    unsigned steps, cycles, full;
} HD2GCReport;
/* VM-independent scheduler driver. Callbacks are synchronous, must not reenter
 * the scheduler or throw native exceptions, and return success except step:
 * step returns -1 for failure, 0 for more work, 1 for a completed GC cycle.
 * Driver owns VM protection and stopping automatic GC even on failure. */
typedef struct {
    void *context;
    int (*sample)(void *, int32_t *total_kb, int32_t *estimate_kb);
    int (*full)(void *);
    int (*step)(void *);
    HD2GCClock clock;
} HD2GCDriver;
HD2ENV_API HD2GCSettings hd2gc_defaults(void);
HD2ENV_API HD2GCHistory hd2gc_history(void);
HD2ENV_API int hd2gc_schedule(const HD2GCSettings *, HD2GCHistory *, const HD2GCDriver *, HD2GCReport *);
/* Configure the replacement's scheduler without reading native VM memory.
 * NULL settings/clock select captured defaults and the platform monotonic
 * clock. Resets history. Refused during a frame, shutdown or Lua operation.
 * Supplying a clock is useful for an engine clock; it must outlive the state. */
HD2ENV_API int hd2env_configure_gc(HD2Environment *, const HD2GCSettings *, const HD2GCClock *);
/* Protected native collection; never calls Lua's collectgarbage global.
 * Uses pinned VM headers for read-only live-memory estimates and public Lua
 * APIs for collection. Automatic collection remains stopped on return/error.
 * Partial report/history remain diagnostic after failure. Owner thread only. */
HD2ENV_API int hd2env_collect_frame(HD2Environment *, HD2GCReport *);
HD2ENV_API int hd2env_gc_report(const HD2Environment *, HD2GCReport *);

typedef struct { uint32_t rva; size_t size; unsigned char original[12], replacement[12]; } HD2GCPatch;
/* Complete captured 0x5eb2b0 guard, then replace its entry. Target takes the
 * native collector wrapper address (environment + 0x100148), not lua_State.
 * The original 0x6cd1e0 forwarding wrapper is supported unchanged. */
HD2ENV_API int hd2env_plan_gc_patch(const void *, size_t, uintptr_t target, HD2GCPatch *);
HD2ENV_API uintptr_t hd2env_gc_target(void);
#endif
