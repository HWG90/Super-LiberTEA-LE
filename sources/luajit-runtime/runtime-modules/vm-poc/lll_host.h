/* LLL's in-process Steam service for the embedded LLL (lll_host.c). */
#ifndef HD2_LLL_HOST_H
#define HD2_LLL_HOST_H
#include <stddef.h>
#include "lua.h"
/* Puts hd2.lll_host in package.preload. 1 on success; 0 with a reason, the state unchanged. */
int lll_host_register(lua_State *L, char *why, size_t why_size);
#endif
