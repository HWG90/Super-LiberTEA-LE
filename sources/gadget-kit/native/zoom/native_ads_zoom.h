#pragma once
#include <stdint.h>
#define NADZ_EXPORT extern "C" __declspec(dllexport)
struct NADZ_Config {
 uint32_t size,abi;
 uint64_t game,exe,context,camera,avatar_owner,request;
 uint32_t avatar_index,avatar,body,weapon;
 uint64_t reserved;
};
struct NADZ_Stats {
 uint32_t size,abi,installed,armed,error,reserved;
 uint64_t seen,forwarded,replaced,immediate_applies,binds,ads_forwarded;
 float last_native,last_applied,source_degrees,padding;
};
static_assert(sizeof(NADZ_Config)==80,"NADZ_Config ABI");
static_assert(sizeof(NADZ_Stats)==88,"NADZ_Stats ABI");
NADZ_EXPORT uint32_t NADZ_Validate(const NADZ_Config*);
// 0: no owned generation; 1: armed; 2: cleanup-owned generation.
NADZ_EXPORT uint32_t NADZ_Begin(const NADZ_Config*,uint64_t*);
NADZ_EXPORT uint32_t NADZ_Bind(uint64_t,const NADZ_Config*);
NADZ_EXPORT uint32_t NADZ_Update(uint64_t);
NADZ_EXPORT uint32_t NADZ_End(uint64_t);
NADZ_EXPORT uint32_t NADZ_ReadStats(uint64_t,NADZ_Stats*);
NADZ_EXPORT uint32_t NADZ_Error(void);
