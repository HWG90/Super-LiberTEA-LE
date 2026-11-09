#pragma once
#include <stdint.h>
#define NADSHF_EXPORT extern "C" __declspec(dllexport)
// Win64 ABI, natural 8-byte packing. All pointers identify current owned data.
// TTL is measured by the helper's GetTickCount64, never by the caller's clock.
struct NADSHF_Config {
    uint32_t size,abi;
    uint64_t game,exe,context,camera,avatar_owner,request;
    uint64_t registry,units,generations,body_object,instance,graph,native_world;
    uint32_t avatar_index,avatar,body,ttl_ms;
    uint64_t reserved[2];
};
struct NADSHF_Stats {
    uint32_t size,abi,installed,armed,error,effective_armed,body,body_generation;
    uint64_t generation,deadline_ms,now_ms,seen,forwarded,suppressed_start,suppressed_end;
    uint64_t rejected,publications,pauses,in_flight,last_caller;
    uint64_t body_object,instance,graph,context,camera,request;
    uint32_t last_event,reserved;
};
static_assert(sizeof(NADSHF_Config)==144,"NADSHF_Config ABI");
static_assert(sizeof(NADSHF_Stats)==184,"NADSHF_Stats ABI");
// Begin: 0=no lease/output0, 1=installed+armed/nonzero token,
// 2=nonzero token retained; End must finish cleanup.
NADSHF_EXPORT uint32_t NADSHF_Begin(const NADSHF_Config*,uint64_t* token);
// Publish validates a fresh target59 binding and refreshes TTL (1..250ms).
// A failed Publish always leaves the reserved slot installed but paused.
NADSHF_EXPORT uint32_t NADSHF_Publish(uint64_t token,const NADSHF_Config*);
// Pause disarms and drains filter decisions without replacing the slot.
NADSHF_EXPORT uint32_t NADSHF_Pause(uint64_t token);
// End: 1=clean (also idempotent for the retired token), 2=cleanup pending,
// 0=wrong token. Never overwrites a foreign replacement of the data slot.
NADSHF_EXPORT uint32_t NADSHF_End(uint64_t token);
// token0 is accepted only while unreserved. effective_armed is a fresh,
// side-effect-free expiry+slot+owner+target check, not merely the armed bit.
NADSHF_EXPORT uint32_t NADSHF_ReadStats(uint64_t token,NADSHF_Stats*);
NADSHF_EXPORT uint32_t NADSHF_Error(void);
NADSHF_EXPORT uint32_t NADSHF_LastError(void);
