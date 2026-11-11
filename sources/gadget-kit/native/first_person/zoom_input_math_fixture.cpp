#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#if defined(_WIN32)
#include <windows.h>
#endif
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <initializer_list>
#include "zoom_input_math.h"
static_assert(sizeof(void*)==8,"Windows x64 fixture required");
static uint32_t cases=0,provider_calls=0;static uint64_t argument_bits=0;
static void check(bool okay,const char* what){if(!okay){std::printf("FAIL %s\n",what);std::exit(1);}}
static double crt_exp(double x){return std::exp(x);}
static ZoomInputMath::ExpFn math_exp=crt_exp;
#if defined(_MSC_VER)
#define MATH_NOINLINE __declspec(noinline)
#else
#define MATH_NOINLINE __attribute__((noinline))
#endif
MATH_NOINLINE static double provider(double x){++provider_calls;std::memcpy(&argument_bits,&x,8);return math_exp(x);}
static double bad_provider(double){return std::numeric_limits<double>::quiet_NaN();}
static double one_provider(double){return 1.0;}
static double negative_provider(double){return -1.0;}
static double environment_provider(double x){_mm_setcsr(_mm_getcsr()|0x2000);return std::exp(x);}
static uint32_t fb(float v){uint32_t out=0;std::memcpy(&out,&v,4);return out;}
static float sm(float a,float b){__m128 x=_mm_set_ss(a);x=_mm_mul_ss(x,_mm_set_ss(b));return _mm_cvtss_f32(x);}
static float sa(float a,float b){__m128 x=_mm_set_ss(a);x=_mm_add_ss(x,_mm_set_ss(b));return _mm_cvtss_f32(x);}
static float ss(float a,float b){return _mm_cvtss_f32(_mm_sub_ss(_mm_set_ss(a),_mm_set_ss(b)));}
static float nd(double v){return _mm_cvtss_f32(_mm_cvtsd_ss(_mm_setzero_ps(),_mm_set_sd(v)));}
static float oracle_alpha(float dt){return dt<=0?1.0f:nd(1.0-math_exp(static_cast<double>(sm(dt,-75.0f))));}
static float oracle_filter(float r,float h,float a){return sa(sm(a,r),sm(ss(1,a),h));}
static uint32_t random_state=0x38a47611;
static float random_value(){random_state=random_state*1664525U+1013904223U;return static_cast<float>(static_cast<int32_t>(random_state))/2147483648.0f;}
static void verify(const float raw[3],const float history[3],float dt,float lens,float degrees,uint32_t& accepted,uint32_t& bypassed,double& worst){
    const uint32_t csr=_mm_getcsr();ZoomInputMath::Prepared p{};
    const auto r=ZoomInputMath::prepare(raw,history,dt,lens,degrees,provider,p);
    check(_mm_getcsr()==csr,"MXCSR preserved by prepare");
    if(!ZoomInputMath::accepted(r)){++bypassed;return;}++accepted;
    const float alpha=oracle_alpha(dt);
    check(fb(alpha)==fb(p.alpha),"native SSE coefficient bits");
    const float ratio=_mm_cvtss_f32(_mm_div_ss(_mm_set_ss(sm(lens,57.2957763671875f)),_mm_set_ss(degrees)));
    check(fb(ratio)==fb(p.ratio),"native SSE ratio bits");
    for(unsigned i=0;i<3;++i){
        const float natural=oracle_filter(raw[i],history[i],alpha),changed=oracle_filter(p.raw[i],history[i],alpha);
        check(fb(natural)==fb(p.native_history[i]),"restoration is original native history bits");
        check(fb(changed)==fb(p.expected_history[i]),"claim matches actual changed native history bits");
        const double error=std::fabs(static_cast<double>(sm(ratio,changed))-natural);
        check(error<=ZoomInputMath::ABS_TOLERANCE+ZoomInputMath::REL_TOLERANCE*std::fabs(static_cast<double>(natural)),"scaled input within bounded tolerance");
        if(error>worst)worst=error;
    }
    _mm_setcsr(csr);
}
#if defined(_WIN32)
// Test-only execution of copied math code in a separate Windows process.
// Production does not allocate executable pages or change page protections.
static ZoomInputMath::ExpFn captured_exp=nullptr;
static uint32_t captured_calls=0;
static double counted_captured_exp(double x){
    check(std::isfinite(x)&&x>=-75&&x<=0,"captured exp argument stays in call-free finite path");
    ++captured_calls;return captured_exp(x);
}
static bool avx_fma_available(){
#if defined(_MSC_VER)
    int cpu[4]{};__cpuid(cpu,1);const uint32_t c=static_cast<uint32_t>(cpu[2]);
    if((c&((1U<<12)|(1U<<19)|(1U<<27)|(1U<<28)))!=((1U<<12)|(1U<<19)|(1U<<27)|(1U<<28)))return false;
    return (_xgetbv(0)&6)==6;
#else
    uint32_t a=1,b=0,c=0,d=0;
    __asm__ volatile("cpuid":"+a"(a),"=b"(b),"=c"(c),"=d"(d));
    if((c&((1U<<12)|(1U<<19)|(1U<<27)|(1U<<28)))!=((1U<<12)|(1U<<19)|(1U<<27)|(1U<<28)))return false;
    __asm__ volatile("xgetbv":"=a"(a),"=d"(d):"c"(0));
    return (a&6)==6;
#endif
}
static void read_span(FILE* source,unsigned char* destination,uint32_t offset,uint32_t size){
    check(std::fseek(source,static_cast<long>(offset),SEEK_SET)==0,"seek captured span");
    check(std::fread(destination+offset,1,size,source)==size,"complete captured span");
}
static uint32_t native_provider_suite(const char* path,uint32_t& accepted,uint32_t& bypassed,double& worst){
    FILE* source=std::fopen(path,"rb");check(source!=nullptr,"open mapped capture read-only");
    check(std::fseek(source,0,SEEK_END)==0&&std::ftell(source)==0x3382000,"exact mapped image size");
    unsigned char header[1024]{};check(std::fseek(source,0,SEEK_SET)==0&&std::fread(header,1,sizeof header,source)==sizeof header,"mapped image header");
    uint32_t pe=0,stamp=0,size=0;std::memcpy(&pe,header+0x3c,4);
    check(header[0]=='M'&&header[1]=='Z'&&pe>=64&&pe+84<sizeof header,"mapped DOS/header bound");
    std::memcpy(&stamp,header+pe+8,4);std::memcpy(&size,header+pe+80,4);
    check(std::memcmp(header+pe,"PE\0\0",4)==0&&stamp==0x6af322c1&&size==0x3382000,"exact captured build header");
    auto* image=static_cast<unsigned char*>(VirtualAlloc(nullptr,0x3382000,MEM_RESERVE,PAGE_NOACCESS));
    check(image!=nullptr,"reserve private fixture image");
    check(VirtualAlloc(image+0x1f8f000,0x2000,MEM_COMMIT,PAGE_READWRITE)==image+0x1f8f000,"private exp code pages");
    check(VirtualAlloc(image+0x224d000,0x4000,MEM_COMMIT,PAGE_READWRITE)==image+0x224d000,"private exp constant pages");
    check(VirtualAlloc(image+0x2ce1000,0x1000,MEM_COMMIT,PAGE_READWRITE)==image+0x2ce1000,"private fixture dispatch flag");
    read_span(source,image,0x1f8f000,0x2000);read_span(source,image,0x224d000,0x4000);std::fclose(source);
    const unsigned char prefix[]{0x48,0x83,0xec,0x38,0xf3,0x0f,0x7e,0xc0,0x66,0x48,0x0f,0x7e,0xc2};
    check(std::memcmp(image+0x1f8ff70,prefix,sizeof prefix)==0&&image[0x1f90204]==0xc3,"captured exp entry/end witness");
    double maximum=0,minimum=0;std::memcpy(&maximum,image+0x224d610,8);std::memcpy(&minimum,image+0x224d618,8);
    check(minimum< -744&&maximum>709,"finite-path exceptional bounds");
    DWORD ignored=0;check(VirtualProtect(image+0x1f8f000,0x2000,PAGE_EXECUTE_READ,&ignored)!=0,"private fixture code RX");
    check(VirtualProtect(image+0x224d000,0x4000,PAGE_READONLY,&ignored)!=0,"private fixture constants read-only");
    check(FlushInstructionCache(GetCurrentProcess(),image+0x1f8f000,0x2000)!=0,"private fixture code flush");
    captured_exp=reinterpret_cast<ZoomInputMath::ExpFn>(image+0x1f8ff70);math_exp=counted_captured_exp;
    auto* isa=reinterpret_cast<uint32_t*>(image+0x2ce1490);
    const bool avx=avx_fma_available();uint32_t alpha_differences=0,groups=0;
    const float dts[]{0,-.01f,1e-7f,1e-5f,.001f,1.0f/240,1.0f/120,1.0f/60,1.0f/30,.1f,.25f,1};
    for(uint32_t mode=0;mode<=(avx?1U:0U);++mode){
        *isa=mode;
        for(float dt:dts){
            const uint32_t before=captured_calls;
            const float native=oracle_alpha(dt);if(dt<=0)check(captured_calls==before,"captured exp not called for zero/negative dt");
            const float reference=dt<=0?1:nd(1.0-std::exp(static_cast<double>(sm(dt,-75))));
            if(fb(native)!=fb(reference))++alpha_differences;
            for(unsigned n=0;n<1024;++n){float r[3],h[3];for(unsigned i=0;i<3;++i){r[i]=random_value();h[i]=random_value();}
                verify(r,h,dt,.01f,75,accepted,bypassed,worst);}
        }
        ++groups;std::printf("PASS captured native exp private provider: %s\n",mode?"AVX/FMA":"SSE2");
    }
    math_exp=crt_exp;captured_exp=nullptr;check(VirtualFree(image,0,MEM_RELEASE)!=0,"release private fixture image after calls");
    std::printf("NATIVE_EXP_SCOPE {\"private_fixture_pages\":true,\"game_process_calls\":false,\"sse_provider\":true,\"avx_provider\":%s,\"captured_calls\":%u,\"alpha_crt_bit_mismatches\":%u}\n",avx?"true":"false",captured_calls,alpha_differences);
    return groups;
}
#endif
int main(int argc,char** argv){
    const uint32_t original=_mm_getcsr();_mm_setcsr(0x1f80);
    const float raw[3]{.13f,-.32f,.087f},history[3]{-.2f,.17f,.33f};
    ZoomInputMath::Prepared p{};uint32_t accepted=0,bypassed=0;double worst=0;
    {const float dt=.01f;provider_calls=0;const auto r=ZoomInputMath::prepare(raw,history,dt,.5f,75,provider,p);
     check(ZoomInputMath::accepted(r)&&provider_calls==1,"Win64 double provider called once");
     const double expected=static_cast<double>(sm(dt,-75.0f));uint64_t b=0;std::memcpy(&b,&expected,8);
     check(b==argument_bits,"Win64 exp argument is double of rounded float product");++cases;}
    {provider_calls=0;verify(raw,history,0,.5f,75,accepted,bypassed,worst);check(provider_calls==0,"dt0 does not call exp");++cases;}
    {provider_calls=0;verify(raw,history,-.01f,.5f,75,accepted,bypassed,worst);check(provider_calls==0,"negative dt uses alpha1");++cases;}
    {const float lens=75.0f/57.2957763671875f;const auto r=ZoomInputMath::prepare(raw,history,.01f,lens,75,provider,p);
     check(r==ZoomInputMath::Reason::identity&&!p.redirect,"exact ratio1 is no redirect");
     for(unsigned i=0;i<3;++i){check(fb(raw[i])==fb(p.raw[i]),"identity raw bits unchanged");}++cases;}
    const float dts[]{0,-.01f,1.0f/30,1.0f/60,1.0f/120,1.0f/240,1.0f/1000,.1f,.25f,1};
    const float lenses[]{.003f,.01f,.05f,.1f,.5f,1.0f,1.8f};
    {for(float dt:dts){for(float lens:lenses){
        for(unsigned n=0;n<2048;++n){float r[3],h[3];for(unsigned i=0;i<3;++i){r[i]=random_value();h[i]=random_value();}
            verify(r,h,dt,lens,75,accepted,bypassed,worst);}
    }}
    ++cases;}
    {const float r[3]{0,-0.0f,1e-12f},h[3]{0,1e-12f,-1e-12f};for(float dt:dts)verify(r,h,dt,.01f,75,accepted,bypassed,worst);++cases;}
    {const float zero[3]{};const float steering[3]{.37f,-.42f,.08f};
     for(float lens:lenses){check(ZoomInputMath::accepted(ZoomInputMath::prepare(zero,zero,.01f,lens,75,provider,p)),"steering case prepared");
       for(unsigned i=0;i<3;++i){const float contribution=sa(sm(2.0f,sm(p.ratio,p.expected_history[i])),steering[i]);
         check(fb(contribution)==fb(steering[i]),"native steering term remains unscaled when user input zero");}}
     ++cases;}
    {const float steering[3]{.37f,-.42f,.08f},context[3]{.003f,-.007f,.001f};
     for(float lens:lenses){check(ZoomInputMath::accepted(ZoomInputMath::prepare(raw,history,.01f,lens,75,provider,p)),"device/native-term case prepared");
       for(float device:{.25f,1.0f,2.0f})for(float gain:{.1f,1.0f,10.0f})for(unsigned i=0;i<3;++i){
         const float native_context=_mm_cvtss_f32(_mm_div_ss(_mm_set_ss(context[i]),_mm_set_ss(sm(.01f,gain))));
         const float wanted=sa(sa(sm(device,p.native_history[i]),steering[i]),native_context);
         const float adjusted=sa(sa(sm(device,sm(p.ratio,p.expected_history[i])),steering[i]),native_context);
         const double limit=8.0*device*(ZoomInputMath::ABS_TOLERANCE+ZoomInputMath::REL_TOLERANCE*std::fabs(p.native_history[i]))+2e-7;
         check(std::fabs(static_cast<double>(adjusted)-wanted)<=limit,"device preferences, native gain, steering and context kept in original locations");}}
     ++cases;}
    {const float r[3]{10000,-10000,900000},h[3]{-10000,10000,-900000};verify(r,h,.001f,.5f,75,accepted,bypassed,worst);++cases;}
    {const float dt=.001f,a=oracle_alpha(dt),b=ss(1,a);const float r[3]{-b/a,-b/a,-b/a},h[3]{1,1,1};
     verify(r,h,dt,.001f,75,accepted,bypassed,worst);++cases;}
    {for(uint32_t mode:{0U,0x40U,0x8000U,0x8040U}){_mm_setcsr(0x1f80|mode);for(float dt:dts)verify(raw,history,dt,.05f,75,accepted,bypassed,worst);}_mm_setcsr(0x1f80);++cases;}
    {for(uint32_t round:{0x2000U,0x4000U,0x6000U}){_mm_setcsr(0x1f80|round);check(ZoomInputMath::prepare(raw,history,.01f,.5f,75,provider,p)==ZoomInputMath::Reason::unsupported_environment,"nondefault rounding bypass");}
     _mm_setcsr(0x1f80);++cases;}
    {_mm_setcsr(0x1f80&~0x200U);check(ZoomInputMath::prepare(raw,history,.01f,.5f,75,provider,p)==ZoomInputMath::Reason::unsupported_environment,"unmasked exceptions bypass");_mm_setcsr(0x1f80);++cases;}
    {check(ZoomInputMath::prepare(raw,history,.01f,.5f,75,nullptr,p)==ZoomInputMath::Reason::exp_unavailable,"no silent exp fallback");++cases;}
    {check(ZoomInputMath::prepare(raw,history,.01f,.5f,75,bad_provider,p)==ZoomInputMath::Reason::invalid_coefficient,"NaN provider bypass");++cases;}
    {check(ZoomInputMath::prepare(raw,history,.01f,.5f,75,one_provider,p)==ZoomInputMath::Reason::ill_conditioned,"zero alpha bypass");++cases;}
    {check(ZoomInputMath::prepare(raw,history,.01f,.5f,75,negative_provider,p)==ZoomInputMath::Reason::invalid_coefficient,"negative exp bypass");++cases;}
    {const uint32_t csr=_mm_getcsr();check(ZoomInputMath::prepare(raw,history,.01f,.5f,75,environment_provider,p)==ZoomInputMath::Reason::unsupported_environment,"provider control mutation bypass");
     check(_mm_getcsr()==csr,"provider mutated environment restored");++cases;}
    {check(ZoomInputMath::prepare(raw,history,1e-10f,.5f,75,provider,p)==ZoomInputMath::Reason::ill_conditioned,"tiny alpha bypass");++cases;}
    {for(float bad:{std::numeric_limits<float>::quiet_NaN(),std::numeric_limits<float>::infinity(),-std::numeric_limits<float>::infinity()}){
      float r[3]{raw[0],bad,raw[2]};check(ZoomInputMath::prepare(r,history,.01f,.5f,75,provider,p)==ZoomInputMath::Reason::invalid_input,"invalid axis bypass");
      check(ZoomInputMath::prepare(raw,r,.01f,.5f,75,provider,p)==ZoomInputMath::Reason::invalid_input,"invalid history bypass");
      check(ZoomInputMath::prepare(raw,history,bad,.5f,75,provider,p)==ZoomInputMath::Reason::invalid_input,"invalid dt bypass");
      check(ZoomInputMath::prepare(raw,history,.01f,bad,75,provider,p)==ZoomInputMath::Reason::invalid_input,"invalid lens bypass");
      check(ZoomInputMath::prepare(raw,history,.01f,.5f,bad,provider,p)==ZoomInputMath::Reason::invalid_input,"invalid degree bypass");}++cases;}
    {float r[3]{raw[0],std::numeric_limits<float>::denorm_min(),raw[2]};check(ZoomInputMath::prepare(r,history,.01f,.5f,75,provider,p)==ZoomInputMath::Reason::invalid_input,"subnormal input bypass");++cases;}
    {for(float lens:{0.0f,-1.0f,4.0f,1e-8f})check(ZoomInputMath::prepare(raw,history,.01f,lens,75,provider,p)==ZoomInputMath::Reason::invalid_input,"unsupported lens bypass");++cases;}
    {float r[3]{1000001,0,0};check(ZoomInputMath::prepare(r,history,.01f,.5f,75,provider,p)==ZoomInputMath::Reason::invalid_input,"raw range bypass");++cases;}
    {float r[3]{999999,999999,999999},h[3]{};const auto r0=ZoomInputMath::prepare(r,h,0,.001f,75,provider,p);
     check(r0==ZoomInputMath::Reason::unrepresentable,"compensated raw range bypass");++cases;}
    {check(ZoomInputMath::prepare(nullptr,history,.01f,.5f,75,provider,p)==ZoomInputMath::Reason::invalid_input,"null vector bypass");++cases;}
    {ZoomInputMath::Prepared alias{};for(unsigned i=0;i<3;++i){alias.raw[i]=raw[i];alias.native_history[i]=history[i];}
     check(ZoomInputMath::accepted(ZoomInputMath::prepare(alias.raw,alias.native_history,.01f,.5f,75,provider,alias)),"input/output alias copied safely");++cases;}
    check(accepted>100000,"substantial successful independent SSE sweep");_mm_setcsr(original);
#if defined(_WIN32)
    if(argc==2){_mm_setcsr(0x1f80);cases+=native_provider_suite(argv[1],accepted,bypassed,worst);_mm_setcsr(original);}
#else
    (void)argc;(void)argv;
#endif
    std::printf("PASS zoom input pure math: %u cases, %u accepted samples, %u safe bypasses, max_abs_error=%.9g\n",cases,accepted,bypassed,worst);
#if defined(_WIN32)
    std::printf("MATH_SCOPE {\"actual_sse_filter\":true,\"windows_x64_provider_abi\":true,\"captured_exp_executed_privately\":%s,\"game_process_calls\":false}\n",argc==2?"true":"false");
#else
    std::printf("MATH_SCOPE {\"actual_sse_filter\":true,\"windows_x64_provider_abi\":false,\"captured_exp_executed_privately\":false,\"game_process_calls\":false}\n");
#endif
    return 0;
}
