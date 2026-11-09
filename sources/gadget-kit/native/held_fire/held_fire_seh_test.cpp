// Test-only DLL, built with EXACT production compiler/linker flags. This seam
// never ships in the mod and only deliberately faults on private test memory.
#include "native_held_fire.cpp"
alignas(8) static uint64_t seh_test_slot=0x1122334455667788ULL;
extern "C" __declspec(dllexport) uint32_t NADSHF_TestCasReadOnly(void){
    HMODULE module=nullptr;
    if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&seh_test_slot),&module))return 0;
    slot=reinterpret_cast<uint64_t>(&seh_test_slot);
    // Exact production page/PE-owner preflight succeeds. Protection then
    // changes to model the narrow race before the actual protected CAS.
    if(!writable_slot(slot,reinterpret_cast<uint64_t>(module))){slot=0;return 0;}
    const uint64_t before=seh_test_slot;DWORD old=0;
    if(!VirtualProtect(&seh_test_slot,8,PAGE_READONLY,&old)){slot=0;return 0;}
    uint64_t observed=UINT64_MAX;const bool did_cas=cas(before,0,observed);
    uint64_t after=0;const bool readable=read(slot,&after,8);DWORD unused=0;
    const bool restored=VirtualProtect(&seh_test_slot,8,old,&unused)!=0;
    if(restored)slot=0;
    return !did_cas&&readable&&before==after&&restored;
}
