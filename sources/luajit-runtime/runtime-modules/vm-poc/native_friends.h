#ifndef HD2_NATIVE_FRIENDS_H
#define HD2_NATIVE_FRIENDS_H
#include "native_steam.h"
/* Same synchronous guarded native access contract as the Steam adapter.
 * The host keeps all service/interface/returned memory alive for each call. */
typedef HD2SteamHost HD2FriendsHost;
HD2ENV_API int hd2env_probe_friends_host(const HD2FriendsHost *);
HD2ENV_API int hd2env_current_friends_host(HD2FriendsHost *out);
/* Port of 0x7f0e10: Friends and Presence, fourteen callbacks and 28 constants.
 * Stores the engine-owned service slot even when null. Null does not remove
 * existing Lua modules. Errors may leave partial registration, requiring boot
 * to fail closed. No native helper accepts or receives a Lua state. */
HD2ENV_API int hd2env_register_friends(HD2Environment *,const HD2FriendsHost *,uintptr_t service);
#endif
