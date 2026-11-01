#ifndef HD2_NATIVE_RESOURCES_H
#define HD2_NATIVE_RESOURCES_H
#include "native_steam.h"
/* The engine's mounted Lua resources for build 26088801, read through the
 * original ResourceManager resolver 0x6321a0 (live-proven by resource_bridge,
 * batch 787). Resolution honors every installed patch archive. Returned bytes
 * are copied before Lua resumes and stay valid until the next lookup. */
typedef struct HD2EngineResources HD2EngineResources;
/* environment is the native LuaEnvironment (ResourceManager at +0x110). */
HD2ENV_API HD2EngineResources *hd2resources_open(const HD2SteamHost *,uintptr_t environment);
/* Installs read_resource; the backend must not already have a context. */
HD2ENV_API int hd2resources_bind(HD2EngineResources *,HD2Backend *);
HD2ENV_API const char *hd2resources_error(const HD2EngineResources *);
HD2ENV_API unsigned hd2resources_found(const HD2EngineResources *);
#endif
