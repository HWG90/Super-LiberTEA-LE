#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <initializer_list>
#include "native_ads_editor.h"
#define VERIFY(x) do{if(!(x)){std::fprintf(stderr,"FAIL %u %s\n",__LINE__,#x);return 3;}}while(0)
template<class T> static T symbol(HMODULE dll,const char* name){return reinterpret_cast<T>(GetProcAddress(dll,name));}
int main(int argc,char**argv){
    VERIFY(argc==2);HMODULE dll=LoadLibraryA(argv[1]);VERIFY(dll);
    auto error=symbol<uint32_t(*)()>(dll,"NADSE_Error");
    auto validate=symbol<uint32_t(*)(const NADSE_Config*)>(dll,"NADSE_ValidateInput");
    auto begin=symbol<uint32_t(*)(const NADSE_Config*,uint64_t*)>(dll,"NADSE_BeginInput");
    auto steady=symbol<uint32_t(*)(const NADSE_Config*,uint64_t*)>(dll,"NADSE_BeginSteadyInput");
    auto stats=symbol<uint32_t(*)(uint64_t,NADSE_Stats*)>(dll,"NADSE_ReadStats");
    auto depth=symbol<uint32_t(*)(uint64_t,NADSE_DepthStats*)>(dll,"NADSE_ReadDepthStats");
    auto input=symbol<uint32_t(*)(uint64_t,NADSE_InputStats*)>(dll,"NADSE_ReadInputStats");
    auto end=symbol<uint32_t(*)(uint64_t)>(dll,"NADSE_End");
    VERIFY(error&&validate&&begin&&steady&&stats&&depth&&input&&end);
    for(const char* old:{"NADSE_Validate","NADSE_Begin","NADSE_BeginSteady","NADSE_SetPlacement","NADSE_SetADSPlacement","NADSE_SetMotion","NADSE_SetTransform","NADSE_SetAuthoredTransform","NADSE_SetZoomPolicy","NADSE_SetTransition"})VERIFY(GetProcAddress(dll,old));
    VERIFY(sizeof(NADSE_Config)==104&&sizeof(NADSE_Stats)==80&&sizeof(NADSE_DepthStats)==104&&sizeof(NADSE_InputStats)==96);
    NADSE_Stats s{};s.size=sizeof s;s.abi=2;VERIFY(stats(0,&s)==1&&!s.installed&&!s.armed);
    NADSE_DepthStats d{};d.size=sizeof d;d.abi=1;VERIFY(depth(0,&d)==1&&!d.installed&&!d.armed);
    NADSE_InputStats i{};i.size=sizeof i;i.abi=1;VERIFY(input(0,&i)==1&&!i.installed&&!i.active&&!i.pending);
    VERIFY(input(1,&i)==0&&error()==17);i.reserved=1;VERIFY(input(0,&i)==0&&error()==1);i.reserved=0;
    VERIFY(input(0,nullptr)==0&&error()==1);VERIFY(validate(nullptr)==0&&error()==1);
    NADSE_Config c{};c.size=sizeof c;c.abi=2;VERIFY(validate(&c)==0&&error()==1);
    uint64_t token=UINT64_MAX;VERIFY(begin(nullptr,&token)==0&&token==0&&error()==1);
    token=UINT64_MAX;VERIFY(steady(&c,&token)==0&&token==0&&error()==1);
    VERIFY(begin(&c,nullptr)==0&&error()==1);VERIFY(end(1)==0&&error()==17);
    VERIFY(FreeLibrary(dll));std::puts("PASS production DLL actual exports Config104 Stats80 Depth104 Input96 unsafe-owner null-output and stale-token rejection");return 0;
}
