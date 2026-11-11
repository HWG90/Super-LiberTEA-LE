// Reuse the already reviewed test-only SSE and private captured-exp harness.
// Its original standalone main is compiled under a different name, never run.
#define main zoom_raw_fixture_original_main
#include "zoom_input_math_fixture.cpp"
#undef main
#include "zoom_gain_math.h"
static uint32_t gain_cases=0,gain_accepted=0,gain_bypassed=0,reason_counts[12]{};
static double gain_worst=0,pitch_worst=0;
static ZoomGainMath::Input input(){
    ZoomGainMath::Input in{};in.raw[0]=.13f;in.raw[1]=-.32f;in.raw[2]=.087f;
    in.history[0]=-.2f;in.history[1]=.17f;in.history[2]=.33f;
    in.dt_eval=in.dt_global=1.0f/60;in.lens_radians=.5f;in.tpv_degrees=75;in.device=1;
    in.native_gain[0]=2;in.native_gain[1]=3;return in;
}
static float sd(float a,float b){return _mm_cvtss_f32(_mm_div_ss(_mm_set_ss(a),_mm_set_ss(b)));}
static ZoomGainMath::Pipeline oracle_pipeline(unsigned axis,float value,float g,const ZoomGainMath::Input& in){
    ZoomGainMath::Pipeline p{};
    if(in.dt_eval>0)value=sa(value,sd(in.context[axis],sm(in.dt_eval,g)));
    p.before_gate=value;p.gate_zero=axis==1&&in.pitch_gate&&value>0;p.after_gate=p.gate_zero?0.0f:value;
    p.increment=sm(sm(axis==0?-p.after_gate:p.after_gate,g),in.dt_global);
    if(axis==0)p.increment=sm(p.increment,.5f);
    return p;
}
static float oracle_clamp(float base,float increment){
    const float value=sa(base,increment);
    if(-1.5707963705062866f>value)return -1.5707963705062866f;
    return _mm_cvtss_f32(_mm_min_ss(_mm_set_ss(1.5707963705062866f),_mm_set_ss(value)));
}
static void same_pipeline(const ZoomGainMath::Pipeline& a,const ZoomGainMath::Pipeline& b){
    check(fb(a.before_gate)==fb(b.before_gate)&&fb(a.after_gate)==fb(b.after_gate)
        &&fb(a.increment)==fb(b.increment)&&a.gate_zero==b.gate_zero,"independent SSE pipeline bits");
}
static ZoomGainMath::Reason gain_verify(const ZoomGainMath::Input& in,ZoomGainMath::Prepared* result=nullptr){
    unsigned char before[sizeof in]{};std::memcpy(before,&in,sizeof in);
    const uint32_t csr=_mm_getcsr();ZoomGainMath::Prepared p{};
    const auto reason=ZoomGainMath::prepare(in,provider,p);
    check(std::memcmp(&in,before,sizeof in)==0,"all input/raw/history/steering/context bytes unchanged");
    check(_mm_getcsr()==csr,"gain preparation preserves MXCSR");
    ++reason_counts[static_cast<unsigned>(reason)];
    if(!ZoomGainMath::accepted(reason)){
        ++gain_bypassed;check(!p.changed,"bypass never claims a changed preset");
        for(unsigned i=0;i<2;++i)check(fb(p.gains[i])==fb(in.native_gain[i]),"bypass retains original published gains");
        if(result)*result=p;
        return reason;
    }
    ++gain_accepted;const float alpha=oracle_alpha(in.dt_eval);
    check(fb(alpha)==fb(p.alpha),"gain model native filter alpha bits");
    const float ratio=sd(sm(in.lens_radians,57.2957763671875f),in.tpv_degrees);
    check(fb(ratio)==fb(p.ratio),"gain model native ratio bits");
    for(unsigned i=0;i<3;++i)check(fb(oracle_filter(in.raw[i],in.history[i],alpha))==fb(p.native_history[i]),"all three native history axes exact and unmodified");
    for(unsigned i=0;i<2;++i){
        const float signed_input=sm(in.sign[i],p.native_history[i]);
        const float x=sa(sm(in.device,sm(ratio,signed_input)),in.steering[i]);
        const float target=sa(sm(in.device,signed_input),in.steering[i]);
        check(fb(x)==fb(p.axis[i].x)&&fb(target)==fb(p.axis[i].target),"actual D after R operation order");
        const auto natural=oracle_pipeline(i,x,in.native_gain[i],in),wanted=oracle_pipeline(i,target,in.native_gain[i],in),expected=oracle_pipeline(i,x,p.gains[i],in);
        same_pipeline(natural,p.axis[i].natural);same_pipeline(wanted,p.axis[i].wanted);same_pipeline(expected,p.axis[i].expected);
        check(expected.gate_zero==wanted.gate_zero,"native pitch polarity gate preserved");
        const double error=std::fabs(static_cast<double>(expected.increment)-wanted.increment);
        const double tolerance=ZoomGainMath::ABS_TOLERANCE+ZoomGainMath::REL_TOLERANCE*std::fabs(static_cast<double>(wanted.increment));
        check(error<=tolerance&&error<=ZoomGainMath::MAX_INCREMENT_ERROR,"full context/gate/gain/global-dt residual bounded");if(error>gain_worst)gain_worst=error;
        check(p.gains[i]>0&&ZoomGainMath::gain_valid(p.gains[i],in.native_gain[i]),"positive bounded gains only");
        check(p.axis[i].input_dependent==(in.steering[i]!=0),"per-axis prediction dependence accurately tagged");
        if(in.steering[i]==0)check(fb(p.gains[i])==fb(sd(in.native_gain[i],p.ratio)),"S0 gain is unconditionally g over R");
        if(i==1){
            const float bases[]{-1.570797f,-1.5707963705062866f,-1.57079625f,-.25f,0,.25f,1.57079625f,1.5707963705062866f,1.570797f};
            for(float base:bases){
                const float actual=oracle_clamp(base,expected.increment),desired=oracle_clamp(base,wanted.increment);
                check(fb(actual)==fb(ZoomGainMath::pitch_after_base(base,expected.increment)),"native SSE add/clamp ordering");
                const double difference=std::fabs(static_cast<double>(actual)-desired);
                check(difference<=tolerance+ZoomGainMath::PITCH_ADD_BOUND,"same independent base/clamp bound");if(difference>pitch_worst)pitch_worst=difference;
            }
        }
    }
    check(p.input_dependent==(in.steering[0]!=0||in.steering[1]!=0),"aggregate input dependence accurately tagged");
    if(result)*result=p;
    _mm_setcsr(csr);return reason;
}
static void sweep(unsigned count){
    const float dts[]{0,-.01f,1e-7f,.001f,1.0f/240,1.0f/120,1.0f/60,1.0f/30,.1f,.25f,1};
    const float lenses[]{.003f,.01f,.05f,.5f,1,1.8f};
    for(float dt:dts)for(float lens:lenses)for(unsigned n=0;n<count;++n){
        auto in=input();in.dt_eval=dt;in.dt_global=n%3==0?0:(n%3==1?1.0f/240:1.0f/60);in.lens_radians=lens;
        in.device=.05f+std::fabs(random_value())*3;in.pitch_gate=n%2;
        for(unsigned i=0;i<3;++i){in.raw[i]=random_value();in.history[i]=random_value();}
        for(unsigned i=0;i<2;++i){in.sign[i]=n%4==i?-1.0f:1.0f;in.steering[i]=random_value()*.25f;
            in.context[i]=random_value()*.01f;in.native_gain[i]=.01f+std::fabs(random_value())*10;}
        gain_verify(in);
    }
}
#if defined(_WIN32)
static void captured_gain_suite(const char* path){
    FILE* source=std::fopen(path,"rb");check(source!=nullptr,"gain capture file read-only");
    check(std::fseek(source,0,SEEK_END)==0&&std::ftell(source)==0x3382000,"gain capture exact length");
    auto* image=static_cast<unsigned char*>(VirtualAlloc(nullptr,0x3382000,MEM_RESERVE,PAGE_NOACCESS));check(image!=nullptr,"gain private fixture image");
    check(VirtualAlloc(image+0x1f8f000,0x2000,MEM_COMMIT,PAGE_READWRITE)==image+0x1f8f000,"gain private code");
    check(VirtualAlloc(image+0x224d000,0x4000,MEM_COMMIT,PAGE_READWRITE)==image+0x224d000,"gain private constants");
    check(VirtualAlloc(image+0x2ce1000,0x1000,MEM_COMMIT,PAGE_READWRITE)==image+0x2ce1000,"gain private ISA flag");
    read_span(source,image,0x1f8f000,0x2000);read_span(source,image,0x224d000,0x4000);std::fclose(source);
    const unsigned char prefix[]{0x48,0x83,0xec,0x38,0xf3,0x0f,0x7e,0xc0,0x66,0x48,0x0f,0x7e,0xc2};
    check(std::memcmp(image+0x1f8ff70,prefix,sizeof prefix)==0&&image[0x1f90204]==0xc3,"gain captured exp witnesses");
    DWORD ignored=0;check(VirtualProtect(image+0x1f8f000,0x2000,PAGE_EXECUTE_READ,&ignored)!=0,"gain private code RX");
    check(VirtualProtect(image+0x224d000,0x4000,PAGE_READONLY,&ignored)!=0,"gain private constants R");
    check(FlushInstructionCache(GetCurrentProcess(),image+0x1f8f000,0x2000)!=0,"gain private fixture cache flush");
    captured_exp=reinterpret_cast<ZoomInputMath::ExpFn>(image+0x1f8ff70);math_exp=counted_captured_exp;
    const bool avx=avx_fma_available();
    for(uint32_t mode=0;mode<=(avx?1U:0U);++mode){*reinterpret_cast<uint32_t*>(image+0x2ce1490)=mode;sweep(128);++gain_cases;
        std::printf("PASS gain captured private exp provider: %s\n",mode?"AVX/FMA":"SSE2");}
    math_exp=crt_exp;captured_exp=nullptr;check(VirtualFree(image,0,MEM_RELEASE)!=0,"gain private fixture release");
    std::printf("GAIN_NATIVE_EXP {\"private_fixture_pages\":true,\"game_process_calls\":false,\"sse\":true,\"avx_fma\":%s,\"captured_calls\":%u}\n",avx?"true":"false",captured_calls);
}
#endif
int main(int argc,char** argv){
    const uint32_t original=_mm_getcsr();_mm_setcsr(0x1f80);
    {check(ZoomGainMath::accepted(gain_verify(input())),"ordinary gain case supported");++gain_cases;}
    {auto in=input();in.lens_radians=75.0f/57.2957763671875f;ZoomGainMath::Prepared p{};
     check(gain_verify(in,&p)==ZoomGainMath::Reason::identity&&!p.changed,"ratio1 identity");++gain_cases;}
    {auto in=input();for(unsigned i=0;i<3;++i){in.raw[i]=i?-.000000000001f:.000000000001f;in.history[i]=in.raw[i];}
     check(gain_verify(in)==ZoomGainMath::Reason::ready,"slow pan S0 has no absolute-epsilon bypass");++gain_cases;}
    {auto in=input();in.steering[0]=.27f;in.steering[1]=-.19f;in.context[0]=.004f;in.context[1]=-.002f;
     check(ZoomGainMath::accepted(gain_verify(in)),"well-conditioned native steering and context supported");++gain_cases;}
    {auto in=input();in.dt_eval=0;in.dt_global=.02f;in.context[0]=10000;in.context[1]=-10000;provider_calls=0;
     check(ZoomGainMath::accepted(gain_verify(in))&&provider_calls==0,"dt0 skips context and exp but not global dt");++gain_cases;}
    {auto in=input();in.dt_eval=-.01f;provider_calls=0;check(ZoomGainMath::accepted(gain_verify(in))&&provider_calls==0,"negative eval dt native branch");++gain_cases;}
    {auto in=input();in.dt_eval=0;in.raw[0]=1;in.raw[1]=0;in.lens_radians=37.5f/57.2957763671875f;in.steering[0]=-.5f;
     check(gain_verify(in)==ZoomGainMath::Reason::singular,"zero denominator honest bypass");++gain_cases;}
    {auto in=input();in.dt_eval=0;in.raw[0]=1;in.raw[1]=0;in.steering[0]=-1;
     check(gain_verify(in)==ZoomGainMath::Reason::singular,"zero desired numerator no zero-gain publish");++gain_cases;}
    {auto in=input();in.dt_eval=0;in.raw[0]=1;in.raw[1]=0;in.lens_radians=37.5f/57.2957763671875f;in.steering[0]=-.75f;
     check(gain_verify(in)==ZoomGainMath::Reason::gain_range,"opposed sign does not publish negative gain");++gain_cases;}
    {auto in=input();in.dt_eval=0;in.raw[0]=0;in.raw[1]=1;in.pitch_gate=true;in.lens_radians=37.5f/57.2957763671875f;in.steering[1]=-.75f;
     check(gain_verify(in)==ZoomGainMath::Reason::gain_range,"negative pitch candidate cannot invert pre-gain clamp branch");++gain_cases;}
    {auto in=input();in.dt_eval=0;in.raw[0]=1;in.raw[1]=0;in.lens_radians=37.5f/57.2957763671875f;in.steering[0]=-.499999f;
     check(gain_verify(in)==ZoomGainMath::Reason::ill_conditioned,"relative cancellation bypass");++gain_cases;}
    {auto in=input();in.device=0;in.steering[0]=.2f;in.context[0]=.03f;check(ZoomGainMath::accepted(gain_verify(in)),"zero device preference retains native terms");++gain_cases;}
    {auto in=input();in.raw[0]=in.raw[1]=in.raw[2]=0;in.history[0]=in.history[1]=in.history[2]=0;
     ZoomGainMath::Prepared p{};check(gain_verify(in,&p)==ZoomGainMath::Reason::ready&&!p.input_dependent,"idle S0 still preselects g over R");++gain_cases;}
    {auto idle=input();idle.dt_eval=0;for(unsigned i=0;i<3;++i)idle.raw[i]=idle.history[i]=0;
     ZoomGainMath::Prepared baseline{};check(gain_verify(idle,&baseline)==ZoomGainMath::Reason::ready&&!baseline.input_dependent,"idle preset is input independent");
     const float values[]{0,1e-12f,-1e-12f,.125f,-.125f,.5f};
     for(float u:values){for(float h:values){for(float dt:{0.0f,1.0f/240,1.0f/60,.25f}){for(float c:{0.0f,.003f,-.007f}){
        auto changed=idle;changed.dt_eval=dt;changed.context[0]=c;changed.context[1]=-c;
        for(unsigned i=0;i<3;++i){changed.raw[i]=i==1?-u:u;changed.history[i]=i==1?-h:h;}
        ZoomGainMath::Prepared p{};check(ZoomGainMath::accepted(gain_verify(changed,&p)),"zero to nonzero raw/history/dt/context remains supported");
        for(unsigned i=0;i<2;++i)check(fb(p.gains[i])==fb(baseline.gains[i]),"same S0 preset remains valid independently of predicted input");
     }}}}
     ++gain_cases;}
    {sweep(512);++gain_cases;}
    {for(uint32_t mode:{0U,0x40U,0x8000U,0x8040U}){_mm_setcsr(0x1f80|mode);check(ZoomGainMath::accepted(gain_verify(input())),"FTZ/DAZ ordinary domain");}_mm_setcsr(0x1f80);++gain_cases;}
    {for(uint32_t mode:{0x2000U,0x4000U,0x6000U}){_mm_setcsr(0x1f80|mode);check(gain_verify(input())==ZoomGainMath::Reason::unsupported_environment,"unsupported rounding bypass");}_mm_setcsr(0x1f80);++gain_cases;}
    {auto in=input();in.native_gain[0]=0;check(gain_verify(in)==ZoomGainMath::Reason::invalid_input,"zero original gain bypass");in.native_gain[0]=-1;
     check(gain_verify(in)==ZoomGainMath::Reason::invalid_input,"negative original gain bypass");++gain_cases;}
    {for(float bad:{std::numeric_limits<float>::quiet_NaN(),std::numeric_limits<float>::infinity(),-std::numeric_limits<float>::infinity()}){
      auto in=input();in.steering[1]=bad;check(gain_verify(in)==ZoomGainMath::Reason::invalid_input,"nonfinite steering bypass");in=input();in.raw[0]=bad;
      check(gain_verify(in)==ZoomGainMath::Reason::invalid_input,"nonfinite raw bypass");in=input();in.dt_global=bad;check(gain_verify(in)==ZoomGainMath::Reason::invalid_input,"nonfinite global time bypass");}++gain_cases;}
    {auto in=input();in.context[0]=1000001;check(gain_verify(in)==ZoomGainMath::Reason::invalid_input,"context numeric domain bypass");++gain_cases;}
    {auto in=input();in.native_gain[0]=1000000;check(gain_verify(in)==ZoomGainMath::Reason::gain_range,"absolute candidate gain range bypass");++gain_cases;}
    {auto in=input();in.sign[0]=0;check(gain_verify(in)==ZoomGainMath::Reason::invalid_input,"inversion coefficient contract");in=input();in.device=-1;
     check(gain_verify(in)==ZoomGainMath::Reason::invalid_input,"negative preference domain bypass");++gain_cases;}
    {auto in=input();in.history[2]=std::numeric_limits<float>::quiet_NaN();check(gain_verify(in)==ZoomGainMath::Reason::invalid_input,"invalid third history axis still bypasses");in=input();in.lens_radians=0;
     check(gain_verify(in)==ZoomGainMath::Reason::invalid_input,"zero lens bypass");++gain_cases;}
    {_mm_setcsr(0x1f80&~0x200U);check(gain_verify(input())==ZoomGainMath::Reason::unsupported_environment,"unmasked exceptions bypass");_mm_setcsr(0x1f80);++gain_cases;}
    {ZoomGainMath::Prepared p{};const auto in=input();
     check(ZoomGainMath::accepted(ZoomGainMath::prepare(in,one_provider,p)),"alpha0 does not require raw inverse or divide by alpha");
     for(unsigned i=0;i<3;++i){check(fb(p.native_history[i])==fb(in.history[i]),"alpha0 history exactly native");}++gain_cases;}
    {ZoomGainMath::Prepared p{};check(ZoomGainMath::prepare(input(),nullptr,p)==ZoomGainMath::Reason::exp_unavailable,"gain no exp fallback");
     check(ZoomGainMath::prepare(input(),bad_provider,p)==ZoomGainMath::Reason::invalid_coefficient,"bad exact provider bypass");++gain_cases;}
#if defined(_WIN32)
    if(argc==2)captured_gain_suite(argv[1]);
#else
    (void)argc;(void)argv;
#endif
    check(gain_accepted>20000,"substantial accepted dynamic-gain independent SSE cases");_mm_setcsr(original);
    std::printf("PASS zoom gain pure math: %u cases, %u accepted, %u honest bypasses, max_increment_error=%.9g, max_clamped_pitch_error=%.9g\n",gain_cases,gain_accepted,gain_bypassed,gain_worst,pitch_worst);
    std::printf("GAIN_REASONS");for(unsigned i=0;i<12;++i)std::printf(" %u:%u",i,reason_counts[i]);std::printf("\n");return 0;
}
