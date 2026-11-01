#ifndef HD2_NATIVE_VOIP_H
#define HD2_NATIVE_VOIP_H
#include "native_steam.h"
/* Native objects, collections and code must remain stable for the whole call.
 * This adapter borrows client pointers; it neither releases nor owns them. */
typedef HD2SteamHost HD2VoipHost;
HD2ENV_API int hd2env_probe_voip_views_host(const HD2VoipHost *);
/* Partial registrar: Room.members/broken_members and all five Client bindings.
 * This is NOT the SteamVoip boot registrar: room lifecycle, member mutation and
 * update/callback bridging still need verified native helper bodies.
 * Stores the engine-owned manager slot, including null, then registers views.
 * Null managers do not suppress registration in the captured registrar. */
HD2ENV_API int hd2env_register_voip_views(HD2Environment *,const HD2VoipHost *,uintptr_t manager);
#endif
