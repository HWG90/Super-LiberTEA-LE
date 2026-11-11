/* Offline check of the 26251122 runtime against the 26251122 capture, run under Wine.
 * Maps the captured helldivers2.exe image at its real base 0x140000000 (absolute pointers in its tables resolve)
 * and calls the runtime DLL's own probes and patch planners. Read-only: nothing executes captured code, and
 * the planners only compute patch bytes against dummy targets. Build with a non-default image base.
 * Usage: wine probe_harness.exe <runtime.dll> <exe image> */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include "native_steam.h"
#include "native_friends.h"
#include "native_voip.h"
#include "native_vectors.h"
#include "boot_routes.h"
#include "shutdown_routes.h"
#include "gc_policy.h"

static unsigned char *image;
static size_t image_size;
static int image_read(void *c, uintptr_t at, void *out, size_t n) {
    (void)c;
    if (at < (uintptr_t)image || at - (uintptr_t)image > image_size || n > image_size - (at - (uintptr_t)image)) return 0;
    memcpy(out, (void *)at, n);
    return 1;
}
static int image_write(void *c, uintptr_t at, const void *in, size_t n) { (void)c; (void)at; (void)in; (void)n; return 0; }
static int image_callable(void *c, uintptr_t at) { (void)c; return at >= (uintptr_t)image + 0x1000 && at < (uintptr_t)image + 0x148c000; }

#define GET(name) __typeof__(name) *p_##name = (__typeof__(name) *)(void *)GetProcAddress(dll, #name); if (!p_##name) { printf("missing export %s\n", #name); return 2; }
int main(int argc, char **argv) {
    if (argc < 3) return 2;
    HMODULE dll = LoadLibraryA(argv[1]);
    if (!dll) { printf("cannot load runtime: %lu\n", GetLastError()); return 2; }
    HANDLE f = CreateFileA(argv[2], GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) return 2;
    image_size = GetFileSize(f, NULL);
    image = VirtualAlloc((void *)0x140000000, image_size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    if (image != (unsigned char *)0x140000000) { printf("cannot map image at 0x140000000\n"); return 2; }
    DWORD got;
    if (!ReadFile(f, image, (DWORD)image_size, &got, NULL) || got != image_size) return 2;
    CloseHandle(f);
    HD2SteamHost host = {NULL, (uintptr_t)image, image_read, image_write, image_callable};
    GET(hd2env_probe_steam_host);
    GET(hd2env_probe_friends_host);
    GET(hd2env_probe_voip_views_host);
    GET(hd2env_probe_vector2_host);
    GET(hd2env_probe_curve_image);
    GET(hd2env_plan_boot_patches);
    GET(hd2env_plan_frame_patches);
    GET(hd2env_plan_lifecycle_patches);
    GET(hd2env_plan_shutdown_patches);
    GET(hd2env_plan_gc_patch);
    GET(hd2env_gc_target);
    int fails = 0;
#define CHECK(label, expr) do { int ok_ = (expr); printf("%-28s %s\n", label, ok_ ? "pass" : "FAIL"); fails += !ok_; } while (0)
    CHECK("host identity (steam)", p_hd2env_probe_steam_host(&host));
    CHECK("friends bindings", p_hd2env_probe_friends_host(&host));
    CHECK("voip views", p_hd2env_probe_voip_views_host(&host));
    CHECK("vector2 port", p_hd2env_probe_vector2_host(&host));
    CHECK("native curve", p_hd2env_probe_curve_image(image, image_size, (uintptr_t)image));
    uintptr_t dummy = (uintptr_t)image + 0x1000;
    HD2BootTargets boot; for (int i = 0; i < HD2_BOOT_REGISTRARS; i++) boot.registrars[i] = dummy; boot.configure = boot.start = dummy;
    HD2LifecyclePatch bp[HD2_BOOT_PATCHES];
    CHECK("boot route patches", p_hd2env_plan_boot_patches(image, image_size, (uintptr_t)image, &boot, bp));
    HD2FrameTargets frames = {dummy, dummy, dummy}; HD2FramePatch fp[2];
    CHECK("frame route patches", p_hd2env_plan_frame_patches(image, image_size, &frames, fp));
    HD2LifecycleTargets life = {dummy, dummy, {dummy, dummy, dummy}}; HD2LifecyclePatch lp[2];
    CHECK("lifecycle route patches", p_hd2env_plan_lifecycle_patches(image, image_size, (uintptr_t)image, &life, lp));
    HD2ShutdownTargets down = {dummy, dummy}; HD2ShutdownPatch sp[3];
    CHECK("shutdown route patches", p_hd2env_plan_shutdown_patches(image, image_size, &down, sp));
    HD2GCPatch gp;
    CHECK("gc policy patch", p_hd2env_plan_gc_patch(image, image_size, p_hd2env_gc_target(), &gp));
    printf("result: %d failed\n", fails);
    return fails ? 1 : 0;
}
