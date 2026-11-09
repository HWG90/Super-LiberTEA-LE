#pragma once
#include <stdint.h>
// Separate Windows-SEH translation unit; contains no C++ exception runtime.
extern "C" uint32_t NADSHF_CasPointer(uint64_t,uint64_t,uint64_t,uint64_t*);
