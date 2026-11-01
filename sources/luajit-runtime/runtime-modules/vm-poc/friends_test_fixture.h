#ifndef HD2_FRIENDS_TEST_FIXTURE_H
#define HD2_FRIENDS_TEST_FIXTURE_H
#include "native_friends.h"
typedef struct FriendsTestFixture FriendsTestFixture;
/* Owned fixture images only. Never supply an actual game image. */
FriendsTestFixture *friends_test_create(void *image,size_t size);
uintptr_t friends_test_service(FriendsTestFixture *);
int friends_test_register(FriendsTestFixture *,HD2Environment *,uintptr_t);
void friends_test_free(FriendsTestFixture *);
void check_friends_bindings(const HD2Asset *,size_t,const HD2Backend *);
#endif
