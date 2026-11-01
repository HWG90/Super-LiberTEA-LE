#ifndef HD2_STEAM_TEST_FIXTURE_H
#define HD2_STEAM_TEST_FIXTURE_H
#include "native_steam.h"
typedef struct SteamTestFixture SteamTestFixture;
/* image=NULL allocates an owned image. Otherwise caller supplies a fully
 * writable 0x29fe000-byte owned test image, never a real process image. */
SteamTestFixture *steam_test_create(void *image,size_t size);
uintptr_t steam_test_service(SteamTestFixture *);
int steam_test_register(SteamTestFixture *,HD2Environment *,uintptr_t service);
void steam_test_free(SteamTestFixture *);
void check_steam_bindings(const HD2Asset *,size_t,const HD2Backend *);
#endif
