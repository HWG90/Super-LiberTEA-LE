#pragma once
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <xmmintrin.h>
#include <emmintrin.h>

// Pure, invocation-local input preparation. No engine reads, stores, pointers,
// ownership decisions or fallback exp implementation live here. Production
// must supply the SAME qualified double(double) exp entry used by native code.
// Each float operation below has the native SSE scalar rounding point; do not
// replace these operations with an FMA or compile with fast-math assumptions.
namespace ZoomInputMath {
using ExpFn=double (*)(double);
enum class Reason:uint32_t { ready=0,identity=1,invalid_input=2,unsupported_environment=3,
    exp_unavailable=4,invalid_coefficient=5,ill_conditioned=6,unrepresentable=7,excess_error=8 };
constexpr float RAD_TO_DEG=57.2957763671875f; // game2246FA0: E02E6542
constexpr float MIN_RATIO=1.0f/4096.0f,MAX_RATIO=16.0f;
constexpr float MAX_COMPONENT=1000000.0f,MIN_ALPHA=0.00001f;
constexpr double ABS_TOLERANCE=0.0000002,REL_TOLERANCE=0.000002;
struct Prepared {
    float raw[3]{},native_history[3]{},expected_history[3]{};
    float ratio=0,alpha=0,beta=0;
    uint32_t mxcsr=0;
    bool redirect=false;
};
inline uint32_t bits(float v){uint32_t b=0;std::memcpy(&b,&v,4);return b;}
inline bool ordinary(float v){const uint32_t a=bits(v)&0x7fffffffU;return a<0x7f800000U && (a==0 || a>=0x00800000U);}
inline bool bounded(float v){return ordinary(v) && std::fabs(v)<=MAX_COMPONENT;}
inline float mul(float a,float b){return _mm_cvtss_f32(_mm_mul_ss(_mm_set_ss(a),_mm_set_ss(b)));}
inline float add(float a,float b){return _mm_cvtss_f32(_mm_add_ss(_mm_set_ss(a),_mm_set_ss(b)));}
inline float sub(float a,float b){return _mm_cvtss_f32(_mm_sub_ss(_mm_set_ss(a),_mm_set_ss(b)));}
inline float divide(float a,float b){return _mm_cvtss_f32(_mm_div_ss(_mm_set_ss(a),_mm_set_ss(b)));}
inline float narrow(double v){return _mm_cvtss_f32(_mm_cvtsd_ss(_mm_setzero_ps(),_mm_set_sd(v)));}
inline float filtered(float raw,float history,float a,float b){return add(mul(a,raw),mul(b,history));}
inline float neighbour(float v,bool upward){
    uint32_t n=bits(v);
    if((n&0x7fffffffU)==0)n=upward?1U:0x80000001U;
    else if((n&0x80000000U)==0)n=upward?n+1:n-1;
    else n=upward?n-1:n+1;
    float result=0;std::memcpy(&result,&n,4);return result;
}
inline bool accepted(Reason r){return r==Reason::ready || r==Reason::identity;}
struct PreserveEnvironment {
    const uint32_t csr;
    explicit PreserveEnvironment(uint32_t v):csr(v){}
    ~PreserveEnvironment(){_mm_setcsr(csr);}
};
inline double residual(float candidate,float wanted,float ratio){
    return std::fabs(static_cast<double>(mul(ratio,candidate))-static_cast<double>(wanted));
}
inline Reason prepare(const float raw[3],const float history[3],float dt_eval,
                      float lens_radians,float tpv_degrees,ExpFn native_exp,Prepared& output) {
    float raw_copy[3]{},history_copy[3]{};
    if(raw && history)for(unsigned i=0;i<3;++i){raw_copy[i]=raw[i];history_copy[i]=history[i];}
    const bool inputs_present=raw && history;raw=raw_copy;history=history_copy;
    output=Prepared{};
    if(!inputs_present || !ordinary(dt_eval) || dt_eval< -1.0f || dt_eval>1.0f
        || !ordinary(lens_radians) || !ordinary(tpv_degrees)
        || lens_radians<=0 || lens_radians>=3.141592654f || tpv_degrees<1 || tpv_degrees>=180)return Reason::invalid_input;
    for(unsigned i=0;i<3;++i)if(!bounded(raw[i]) || !bounded(history[i]))return Reason::invalid_input;
    const uint32_t csr=_mm_getcsr();
    // Nondefault rounding and unmasked exceptions need a separately qualified
    // inverse. FTZ/DAZ are supported with ordinary inputs and exact SSE checks.
    if((csr&0x6000U)!=0 || (csr&0x1f80U)!=0x1f80U)return Reason::unsupported_environment;
    PreserveEnvironment preserve(csr);
    const float ratio=divide(mul(lens_radians,RAD_TO_DEG),tpv_degrees);
    if(!ordinary(ratio) || ratio<MIN_RATIO || ratio>MAX_RATIO)return Reason::invalid_input;
    float a=1;
    if(dt_eval>0) {
        if(!native_exp)return Reason::exp_unavailable;
        const float argument=mul(dt_eval,-75.0f);
        const double exponential=native_exp(static_cast<double>(argument));
        if((_mm_getcsr()&0xffc0U)!=(csr&0xffc0U))return Reason::unsupported_environment;
        if(!std::isfinite(exponential) || exponential<0 || exponential>1)return Reason::invalid_coefficient;
        a=narrow(_mm_cvtsd_f64(_mm_sub_sd(_mm_set_sd(1.0),_mm_set_sd(exponential))));
    }
    if(!ordinary(a) || a<0 || a>1)return Reason::invalid_coefficient;
    if(a<MIN_ALPHA)return Reason::ill_conditioned;
    const float b=sub(1.0f,a);
    Prepared next{};next.ratio=ratio;next.alpha=a;next.beta=b;next.mxcsr=csr;
    for(unsigned i=0;i<3;++i) {
        const float natural=filtered(raw[i],history[i],a,b);
        if(!bounded(natural))return Reason::unrepresentable;
        next.native_history[i]=natural;
        if(ratio==1) {next.raw[i]=raw[i];next.expected_history[i]=natural;continue;}
        const float previous=mul(b,history[i]);
        // Compute the inverse in double, then test the actual native float
        // forward solve. Neighbouring floats address rounding at the two MULs.
        const float centre=narrow((static_cast<double>(natural)/static_cast<double>(ratio)-previous)/a);
        if(!bounded(centre))return Reason::unrepresentable;
        const float choices[3]{centre,neighbour(centre,false),neighbour(centre,true)};
        float best=centre,best_history=filtered(centre,history[i],a,b);
        double error=residual(best_history,natural,ratio);
        for(unsigned k=1;k<3;++k)if(bounded(choices[k])) {
            const float candidate=filtered(choices[k],history[i],a,b);
            const double difference=residual(candidate,natural,ratio);
            if(std::isfinite(difference) && difference<error) {best=choices[k];best_history=candidate;error=difference;}
        }
        if(!bounded(best_history) || !std::isfinite(error)
            || error>ABS_TOLERANCE+REL_TOLERANCE*std::fabs(static_cast<double>(natural)))return Reason::excess_error;
        next.raw[i]=best;next.expected_history[i]=best_history;
    }
    next.redirect=ratio!=1;output=next;
    return next.redirect?Reason::ready:Reason::identity;
}
}
