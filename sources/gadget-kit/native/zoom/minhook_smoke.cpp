// Real MinHook transaction against one local synthetic function, never game code.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <thread>
#include "vendor/minhook/include/MinHook.h"
#define CHECK(x) do{if(!(x)){std::fprintf(stderr,"MinHook smoke FAIL %d: %s\n",__LINE__,#x);std::abort();}}while(0)
using Function=uint32_t(*)(uint32_t);
static std::atomic<uint64_t> calls{0};
static std::atomic<bool> armed{false};
static Function original=nullptr;
extern "C" __declspec(noinline) uint32_t synthetic_optic(uint32_t value) {
    calls.fetch_add(1,std::memory_order_relaxed);return value*3+1;
}
extern "C" __declspec(noinline) uint32_t synthetic_detour(uint32_t value) {
    const uint32_t native=original(value);return armed.load(std::memory_order_acquire)?native+7:native;
}
int main() {
    Function volatile invoke=synthetic_optic;
    uint8_t baseline[32]{};std::memcpy(baseline,reinterpret_cast<void*>(synthetic_optic),sizeof baseline);
    CHECK(invoke(4)==13 && calls.load()==1);
    CHECK(MH_Initialize()==MH_OK);
    CHECK(MH_CreateHook(reinterpret_cast<void*>(synthetic_optic),reinterpret_cast<void*>(synthetic_detour),
        reinterpret_cast<void**>(&original))==MH_OK && original);
    CHECK(invoke(4)==13 && !std::memcmp(baseline,reinterpret_cast<void*>(synthetic_optic),sizeof baseline));
    std::atomic<bool> stop{false};std::atomic<uint64_t> samples{0};
    std::thread worker([&](){while(!stop.load(std::memory_order_acquire)) {
        const uint32_t result=invoke(4);CHECK(result==13 || result==20);samples.fetch_add(1,std::memory_order_relaxed);
    }});
    while(!samples.load())SwitchToThread();
    CHECK(MH_QueueEnableHook(reinterpret_cast<void*>(synthetic_optic))==MH_OK && MH_ApplyQueued()==MH_OK);
    CHECK(invoke(4)==13);armed.store(true,std::memory_order_release);CHECK(invoke(4)==20);
    CHECK(original(4)==13);armed.store(false,std::memory_order_release);CHECK(invoke(4)==13);
    CHECK(MH_QueueDisableHook(reinterpret_cast<void*>(synthetic_optic))==MH_OK && MH_ApplyQueued()==MH_OK);
    stop.store(true,std::memory_order_release);worker.join();
    CHECK(invoke(4)==13 && original(4)==13);
    CHECK(!std::memcmp(baseline,reinterpret_cast<void*>(synthetic_optic),sizeof baseline));
    CHECK(MH_RemoveHook(reinterpret_cast<void*>(synthetic_optic))==MH_OK && MH_Uninitialize()==MH_OK);
    CHECK(invoke(4)==13);
    std::printf("Real MinHook smoke PASS: install, original forwarding, armed override, queued thread transaction, exact code restoration (%llu concurrent calls)\n",
        static_cast<unsigned long long>(samples.load()));return 0;
}
