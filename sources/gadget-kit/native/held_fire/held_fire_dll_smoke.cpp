// Loads the actual production DLL. No synthetic macro or game access.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "native_held_fire.h"
#define CHECK(x) do{if(!(x)){std::fprintf(stderr,"DLL smoke FAIL %d: %s winerr=%lu\n",__LINE__,#x,GetLastError());std::abort();}}while(0)
template<class T> static T proc(HMODULE m,const char* n){auto p=GetProcAddress(m,n);CHECK(p);T f{};static_assert(sizeof f==sizeof p);std::memcpy(&f,&p,sizeof f);return f;}
int main(int argc,char** argv){
    CHECK(argc==3);char path[32768]{};CHECK(GetFullPathNameA(argv[1],sizeof path,path,nullptr));HMODULE m=LoadLibraryA(path);CHECK(m);
    auto begin=proc<uint32_t(*)(const NADSHF_Config*,uint64_t*)>(m,"NADSHF_Begin");
    auto publish=proc<uint32_t(*)(uint64_t,const NADSHF_Config*)>(m,"NADSHF_Publish");
    auto pause=proc<uint32_t(*)(uint64_t)>(m,"NADSHF_Pause");auto end=proc<uint32_t(*)(uint64_t)>(m,"NADSHF_End");
    auto stats=proc<uint32_t(*)(uint64_t,NADSHF_Stats*)>(m,"NADSHF_ReadStats");
    auto error=proc<uint32_t(*)()>(m,"NADSHF_Error");auto last=proc<uint32_t(*)()>(m,"NADSHF_LastError");
    CHECK(sizeof(NADSHF_Config)==144&&sizeof(NADSHF_Stats)==184);
    NADSHF_Stats s{};s.size=sizeof s;s.abi=1;CHECK(stats(0,&s)==1&&s.size==184&&s.abi==1&&!s.installed&&!s.armed&&!s.effective_armed&&!s.generation);
    NADSHF_Config c{};c.size=sizeof c;c.abi=2;uint64_t token=123;
    CHECK(begin(&c,&token)==0&&token==0&&error()==1&&last()==1);
    c.abi=1;c.ttl_ms=251;token=123;CHECK(begin(&c,&token)==0&&token==0&&error()==1);
    CHECK(begin(nullptr,&token)==0&&token==0&&error()==1);CHECK(begin(&c,nullptr)==0&&error()==1);
    CHECK(!publish(1,&c)&&!pause(1)&&!end(1)&&!end(0)&&error()==15);
    s={};s.size=sizeof s;s.abi=1;CHECK(stats(0,&s)==1&&!s.installed&&!s.armed&&!s.effective_armed&&!s.generation&&s.error==15);
    CHECK(!stats(1,&s)&&error()==15);CHECK(!stats(0,nullptr)&&error()==1);
    CHECK(FreeLibrary(m));CHECK(GetFullPathNameA(argv[2],sizeof path,path,nullptr));m=LoadLibraryA(path);CHECK(m);
    auto guarded_cas=proc<uint32_t(*)()>(m,"NADSHF_TestCasReadOnly");CHECK(guarded_cas()==1);CHECK(FreeLibrary(m));
    std::puts("Production held-fire DLL: LoadLibrary, seven exports, ABI144/184, static locks/atomics, invalid-call cleanup and production-flags read-only-page CAS SEH passed; no game access");return 0;
}
