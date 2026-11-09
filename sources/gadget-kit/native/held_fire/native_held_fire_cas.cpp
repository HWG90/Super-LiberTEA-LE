#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include "native_held_fire_cas.h"
using AtomicPointer=uint64_t(*)(uint64_t,uint64_t,uint64_t);
static __declspec(noinline) uint64_t atomic_pointer(uint64_t slot,uint64_t expected,uint64_t desired){
    return reinterpret_cast<uint64_t>(InterlockedCompareExchangePointer(
        reinterpret_cast<PVOID volatile*>(slot),reinterpret_cast<void*>(desired),reinterpret_cast<void*>(expected)));
}
// LLVM may remove a SEH scope around an intrinsic-only atomic as nounwind.
// A volatile, constant-initialized private dispatch preserves a real call and
// its SEH scope. This pointer is never changed and is not an engine hook.
static AtomicPointer volatile atomic_dispatch=atomic_pointer;
extern "C" uint32_t NADSHF_CasPointer(uint64_t slot,uint64_t expected,uint64_t desired,uint64_t* observed){
    __try {
        *observed=atomic_dispatch(slot,expected,desired);
        return 1;
    } __except(EXCEPTION_EXECUTE_HANDLER){return 0;}
}
