#ifndef HD2_LUA_ENVIRONMENT_H
#define HD2_LUA_ENVIRONMENT_H
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32) && defined(HD2ENV_DLL)
#define HD2ENV_API __declspec(dllexport)
#elif defined(__GNUC__)
#define HD2ENV_API __attribute__((visibility("default")))
#else
#define HD2ENV_API
#endif

/* The embedding engine retains assets and backend context until destruction.
 * Every entry must run on the creating thread. No PUC lua_State, closure,
 * registry index or TValue may cross this interface. */
typedef struct HD2Environment HD2Environment;
/* VM-independent values for replacing engine call sites. Strings in arguments
 * are borrowed for the synchronous call; returned strings are copied and stay
 * valid through GC/state destruction. Full userdata, tables, functions and Lua
 * internal pointers are deliberately not representable here. */
typedef enum {
    HD2_VALUE_NIL, HD2_VALUE_BOOLEAN, HD2_VALUE_NUMBER, HD2_VALUE_STRING,
    HD2_VALUE_POINTER
} HD2ValueType;
typedef struct {
    HD2ValueType type;
    union {
        int boolean;
        double number;
        struct { const char *bytes; size_t size; } string;
        uintptr_t pointer;
    } as;
} HD2Value;
typedef struct { HD2Value *values; size_t count; } HD2Results;
/* Owned Lua values. These are opaque identities, never state pointers, stack
 * indexes or Lua registry references. A bitwise copy borrows the same owner;
 * object_clone creates independent ownership. Release on the creating thread,
 * or destroy the environment to release every outstanding object. */
typedef struct { uint64_t environment, identity; } HD2Object;
typedef enum {
    HD2_OBJECT_NIL, HD2_OBJECT_BOOLEAN, HD2_OBJECT_NUMBER, HD2_OBJECT_STRING,
    HD2_OBJECT_POINTER, HD2_OBJECT_TABLE, HD2_OBJECT_FUNCTION,
    HD2_OBJECT_USERDATA, HD2_OBJECT_THREAD, HD2_OBJECT_OTHER
} HD2ObjectKind;
typedef struct {
    HD2Object *values;
    size_t count;
    int is_error; /* One retained error value on a Lua compilation/call error. */
} HD2ObjectResults;
/* Entries in a result array are borrowed from that array's ownership. Clone an
 * entry to keep it independently; dispose the array with hd2env_objects_free. */
enum { HD2_OBJECT_FAILURE=-1, HD2_OBJECT_LUA_ERROR=0, HD2_OBJECT_SUCCESS=1 };
typedef struct {
    const char *name;
    const unsigned char *source;
    size_t source_size;
    const unsigned char *reference_puc;
    size_t reference_size;
    const unsigned char *original_puc;
    size_t original_size;
    uint64_t resource_id; /* Zero for assets addressed only by name. */
} HD2Asset;

typedef struct {
    const unsigned char *bytes;
    size_t size;
    int framed; /* Engine resource: uint32 length, uint32 version, payload. */
} HD2Resource;

typedef struct {
    void *context;
    const char *(*build)(void *context);
    void (*log)(void *context, const char *message, size_t size);
    /* Actual UnitCApi ABI: id32 names and a float out parameter. A verified
     * current-build engine function can be assigned directly here. */
    int (*animation_curve)(uint32_t unit, uint32_t object_id32,
                           uint32_t parameter_id32, uint32_t index, float *value);
    uintptr_t (*wwise_world)(void *, uint32_t world);
    int (*wwise_enabled)(void *, uintptr_t world);
    int (*bank)(void *, const char *name, int load);
    uint32_t (*trigger_event)(void *, uintptr_t world, const char *name);
    int (*stop_event)(void *, uintptr_t world, uint32_t playing_id);
    int (*is_playing)(void *, uintptr_t world, uint32_t playing_id);
    void (*console_event)(void *, const char *bank, const char *event);
    /* Resolve using the engine's mount order. 1=found, 0=absent, -1=error.
     * Bytes remain valid until this host operation returns. Do not reenter Lua.
     * No cached stock variant overrides a resource returned by this resolver. */
    int (*read_resource)(void *, const char *name, HD2Resource *result);
} HD2Backend;

HD2ENV_API HD2Environment *hd2env_create(const HD2Asset *, size_t, const HD2Backend *,
                                       char *error, size_t capacity);
HD2ENV_API int hd2env_require(HD2Environment *, const char *resource);
HD2ENV_API int hd2env_call(HD2Environment *, const char *function, int has_dt, double dt);
/* out must be zero initialized; release successful results before reusing it.
 * Up to 64 arguments/results; a failed operation produces no result values.
 * A nonempty out is refused without modifying existing results. No Lua state
 * or object is exposed. Null out discards results, as hd2env_call does. */
HD2ENV_API int hd2env_invoke(HD2Environment *, const char *function,
                           const HD2Value *arguments, size_t count, HD2Results *out);
HD2ENV_API void hd2env_results_free(HD2Results *);
HD2ENV_API int hd2env_eval(HD2Environment *, const char *source, size_t, const char *name);
/* Compile and discard, without executing; replaces syntax-only entry paths. */
HD2ENV_API int hd2env_check(HD2Environment *, const char *source, size_t, const char *name);
/* Object outputs must start zeroed. Operations below return 1 on success and
 * -1 on an invalid handle, host contract error or infrastructure failure.
 * Compile/call may additionally return 0 with is_error=1 and the actual Lua
 * error value retained. Successful calls preserve every result and trailing nil.
 * Arguments are borrowed. Counts are bounded by Lua's own stack/API limits. */
HD2ENV_API int hd2env_object_from_value(HD2Environment *, const HD2Value *, HD2Object *out);
HD2ENV_API int hd2env_object_global(HD2Environment *, const char *name, HD2Object *out);
HD2ENV_API int hd2env_object_clone(HD2Environment *, HD2Object, HD2Object *out);
HD2ENV_API int hd2env_object_type(HD2Environment *, HD2Object, HD2ObjectKind *out);
HD2ENV_API int hd2env_object_read(HD2Environment *, HD2Object, HD2Results *out);
/* Indexing honors Lua metamethods. All three values belong to this environment. */
HD2ENV_API int hd2env_object_get(HD2Environment *, HD2Object table, HD2Object key, HD2Object *out);
HD2ENV_API int hd2env_object_set(HD2Environment *, HD2Object table, HD2Object key, HD2Object value);
HD2ENV_API int hd2env_object_release(HD2Environment *, HD2Object *);
HD2ENV_API int hd2env_object_compile(HD2Environment *, const char *, size_t, const char *name,
                                   HD2ObjectResults *out);
HD2ENV_API int hd2env_object_call(HD2Environment *, HD2Object function,
                                const HD2Object *arguments, size_t count, HD2ObjectResults *out);
/* Use a live environment to release result ownership. After its destruction,
 * pass NULL to free only the array; its Lua objects were released by destroy.
 * Never pass NULL while that environment is still alive. */
HD2ENV_API int hd2env_objects_free(HD2Environment *, HD2ObjectResults *);
HD2ENV_API size_t hd2env_object_count(const HD2Environment *);
HD2ENV_API int hd2env_set_jit(HD2Environment *, int enabled);
HD2ENV_API const char *hd2env_error(const HD2Environment *);
HD2ENV_API int hd2env_stack_depth(const HD2Environment *);
HD2ENV_API int hd2env_destroy(HD2Environment *);
/* Probe an RVA-layout image without executing native code. The live binder
 * resolves only the current EXE and only updates animation_curve on success.
 * It never constructs a state, patches an engine call or invokes the function. */
HD2ENV_API int hd2env_probe_curve_image(const void *, size_t, uintptr_t mapped_base);
HD2ENV_API int hd2env_bind_current_curve(HD2Backend *);
#endif
