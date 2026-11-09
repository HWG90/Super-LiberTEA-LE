#pragma once
#include <stdint.h>
#define NADSF_EXPORT extern "C" __declspec(dllexport)
struct NADSF_Config {
    uint32_t size,abi;
    uint64_t game,exe,context,camera,avatar_owner,request;
    uint32_t avatar_index,avatar,body,weapon;
    uint64_t reserved; // 0: native ADS passthrough; 80..500: owned ADS handoff milliseconds.
};
struct NADSF_Stats {
    uint32_t size,abi,installed,armed,error,reserved;
    uint64_t seen,forwarded,replaced,immediate_applies,binds,ads_forwarded;
    float last_native,last_applied,source_degrees,padding;
};
static_assert(sizeof(NADSF_Config)==80,"NADSF_Config ABI");
static_assert(sizeof(NADSF_Stats)==88,"NADSF_Stats ABI");
// Validate permits current normal4 for read-only preflight; Begin requires6.
NADSF_EXPORT uint32_t NADSF_Validate(const NADSF_Config*);
// 0: output generation0/no owned lease; 1: armed; 2: owned cleanup required.
NADSF_EXPORT uint32_t NADSF_Begin(const NADSF_Config*,uint64_t* generation);
NADSF_EXPORT uint32_t NADSF_Bind(uint64_t generation,uint64_t request,uint32_t weapon);
// FirdPerson leases the captured display projection on owned normal camera4.
// It shares the existing setter dispatch slot; native camera6 is forwarded.
NADSF_EXPORT uint32_t NADSF_ValidateFird(const NADSF_Config*);
NADSF_EXPORT uint32_t NADSF_BeginFird(const NADSF_Config*,float captured_radians,uint64_t* generation);
NADSF_EXPORT uint32_t NADSF_BindFird(uint64_t generation,uint64_t request);
// Optional presentation phase from the qualified Lua Update coordinator.
// No structure ABI or camera setter interception changes. Epochs increase;
// progress is raw normalized0..1 and never regresses within an epoch.
NADSF_EXPORT uint32_t NADSF_SetTransition(uint64_t generation,uint64_t epoch,float progress,uint32_t ads);
NADSF_EXPORT uint32_t NADSF_End(uint64_t generation);
// Generation0 is valid only while no lease is reserved. Health/counters are
// atomic; display angles use the latest complete nonblocking diagnostic tuple.
NADSF_EXPORT uint32_t NADSF_ReadStats(uint64_t generation,NADSF_Stats*);
NADSF_EXPORT uint32_t NADSF_Error(void);
