#pragma once
#include <stdint.h>
#define NADSN_EXPORT extern "C" __declspec(dllexport)
// Distances are metres. A value at or below the game's own near distance
// forwards the game's value unchanged; full native ADS always forwards it.
struct NADSN_Config {
    uint32_t size,abi;
    uint64_t game,exe,context,camera,avatar_owner;
    uint32_t avatar_index;
    float hip,aim;
    uint32_t reserved;
    uint64_t reserved2;
};
struct NADSN_Stats {
    uint32_t size,abi,installed,armed,error,reserved;
    uint64_t seen,forwarded,replaced,ads_forwarded,aim_applied,other_kind;
    float last_native,last_applied,hip,aim;
};
// Diagnostics: every distinct caller of the slot (return address), any camera.
struct NADSN_Site {
    uint64_t return_address,calls,owned_calls;
    float last_value;
    uint32_t reserved;
};
static_assert(sizeof(NADSN_Config)==72,"NADSN_Config ABI");
static_assert(sizeof(NADSN_Site)==32,"NADSN_Site ABI");
static_assert(sizeof(NADSN_Stats)==88,"NADSN_Stats ABI");
// 0: output generation0/no owned lease; 1: armed; 2: owned cleanup required.
NADSN_EXPORT uint32_t NADSN_Begin(const NADSN_Config*,uint64_t* generation);
NADSN_EXPORT uint32_t NADSN_Set(uint64_t generation,float hip,float aim);
NADSN_EXPORT uint32_t NADSN_End(uint64_t generation);
// Generation0 is valid only while no lease is reserved.
NADSN_EXPORT uint32_t NADSN_ReadStats(uint64_t generation,NADSN_Stats*);
NADSN_EXPORT uint32_t NADSN_Error(void);
// Copies up to capacity rows; returns the number of distinct callers seen.
NADSN_EXPORT uint32_t NADSN_ReadSites(NADSN_Site*,uint32_t capacity);
