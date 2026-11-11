#pragma once
#include "zoom_input_math.h"

// Pure candidate math only. All inputs are copied values, never engine data.
// A successful result proposes only preset yaw(+4)/pitch(+8) gains. Raw input,
// all three native history axes, steering, context, lens and camera orientation
// remain native. This bounded inverse deliberately bypasses singular cases.
namespace ZoomGainMath {
using ExpFn=ZoomInputMath::ExpFn;
enum class Reason:uint32_t {ready=0,identity=1,invalid_input=2,unsupported_environment=3,
    exp_unavailable=4,invalid_coefficient=5,singular=6,ill_conditioned=7,
    gain_range=8,unrepresentable=9,gate_mismatch=10,excess_error=11};
constexpr float MIN_GAIN=0.000001f,MAX_GAIN=1000000.0f;
constexpr float MIN_GAIN_RATIO=1.0f/4096.0f,MAX_GAIN_RATIO=4096.0f;
constexpr double MIN_CONDITION=1.0/4096.0;
constexpr double ABS_TOLERANCE=0.0000002,REL_TOLERANCE=0.000002;
constexpr double MAX_INCREMENT_ERROR=0.000002;
// Same native base is independent of gain/look input. Clamp is nonexpansive;
// two float-add ULPs at the bounded native pitch endpoints cover final rounding.
constexpr double PITCH_ADD_BOUND=0.0000002384185791015625;
struct Input {
    float raw[3]{},history[3]{},dt_eval=0,lens_radians=0,tpv_degrees=0;
    float device=0,sign[2]{1,1},steering[2]{},context[2]{},native_gain[2]{},dt_global=0;
    bool pitch_gate=false;
};
struct Pipeline {float before_gate=0,after_gate=0,increment=0;bool gate_zero=false;};
struct Axis {
    float original_gain=0,gain=0,x=0,target=0;
    Pipeline natural{},wanted{},expected{};bool input_dependent=false;
};
struct Prepared {
    float gains[2]{},native_history[3]{},ratio=0,alpha=0,beta=0;
    uint32_t mxcsr=0;bool changed=false,input_dependent=false;Axis axis[2]{};
};
inline bool accepted(Reason r){return r==Reason::ready || r==Reason::identity;}
inline bool gain_valid(float g,float original){
    if(!ZoomInputMath::ordinary(g) || g<MIN_GAIN || g>MAX_GAIN)return false;
    const double relative=static_cast<double>(g)/original;
    return relative>=MIN_GAIN_RATIO && relative<=MAX_GAIN_RATIO;
}
inline bool pipeline(unsigned axis,float value,float gain,float context,float dt_eval,float dt_global,
                     bool pitch_gate,Pipeline& out){
    using namespace ZoomInputMath;
    out=Pipeline{};
    if(dt_eval>0){
        const float divisor=mul(dt_eval,gain);
        if(!ordinary(divisor) || divisor<=0)return false;
        const float contribution=divide(context,divisor);
        if(!bounded(contribution))return false;
        value=add(value,contribution);
    }
    if(!bounded(value))return false;
    out.before_gate=value;out.gate_zero=axis==1 && pitch_gate && value>0;
    out.after_gate=out.gate_zero?0.0f:value;
    // Native yaw XORs the sign before multiplication and then halves the angle.
    const float signed_value=axis==0?-out.after_gate:out.after_gate;
    out.increment=mul(mul(signed_value,gain),dt_global);
    if(axis==0)out.increment=mul(out.increment,0.5f);
    return bounded(out.increment);
}
inline float pitch_after_base(float base,float increment){
    const float angle=ZoomInputMath::add(base,increment);
    constexpr float lower=-1.5707963705062866f,upper=1.5707963705062866f;
    return lower>angle?lower:_mm_cvtss_f32(_mm_min_ss(_mm_set_ss(upper),_mm_set_ss(angle)));
}
inline Reason prepare(const Input& source,ExpFn native_exp,Prepared& output){
    using namespace ZoomInputMath;
    const Input in=source;output=Prepared{};
    for(unsigned i=0;i<2;++i)output.gains[i]=in.native_gain[i];
    if(!ordinary(in.dt_eval) || in.dt_eval< -1 || in.dt_eval>1 || !ordinary(in.dt_global)
        || in.dt_global<0 || in.dt_global>1 || !ordinary(in.device) || in.device<0 || in.device>MAX_COMPONENT
        || !ordinary(in.lens_radians) || in.lens_radians<=0 || in.lens_radians>=3.141592654f
        || !ordinary(in.tpv_degrees) || in.tpv_degrees<1 || in.tpv_degrees>=180)return Reason::invalid_input;
    for(unsigned i=0;i<3;++i)if(!bounded(in.raw[i]) || !bounded(in.history[i]))return Reason::invalid_input;
    for(unsigned i=0;i<2;++i)if((in.sign[i]!=1 && in.sign[i]!=-1) || !bounded(in.steering[i])
        || !bounded(in.context[i]) || !ordinary(in.native_gain[i])
        || in.native_gain[i]<MIN_GAIN || in.native_gain[i]>MAX_GAIN)return Reason::invalid_input;
    const uint32_t csr=_mm_getcsr();
    if((csr&0x6000U)!=0 || (csr&0x1f80U)!=0x1f80U)return Reason::unsupported_environment;
    PreserveEnvironment preserve(csr);
    output.mxcsr=csr;
    output.ratio=divide(mul(in.lens_radians,RAD_TO_DEG),in.tpv_degrees);
    if(!ordinary(output.ratio) || output.ratio<MIN_RATIO || output.ratio>MAX_RATIO)return Reason::invalid_input;
    float a=1;
    if(in.dt_eval>0){
        if(!native_exp)return Reason::exp_unavailable;
        const double e=native_exp(static_cast<double>(mul(in.dt_eval,-75.0f)));
        if((_mm_getcsr()&0xffc0U)!=(csr&0xffc0U))return Reason::unsupported_environment;
        if(!std::isfinite(e) || e<0 || e>1)return Reason::invalid_coefficient;
        a=narrow(_mm_cvtsd_f64(_mm_sub_sd(_mm_set_sd(1.0),_mm_set_sd(e))));
    }
    if(!ordinary(a) || a<0 || a>1)return Reason::invalid_coefficient;
    output.alpha=a;output.beta=sub(1,a);
    for(unsigned i=0;i<3;++i){
        output.native_history[i]=filtered(in.raw[i],in.history[i],a,output.beta);
        if(!bounded(output.native_history[i]))return Reason::unrepresentable;
    }
    for(unsigned i=0;i<2;++i){
        auto& axis=output.axis[i];axis.original_gain=axis.gain=in.native_gain[i];
        axis.input_dependent=in.steering[i]!=0;
        output.input_dependent=output.input_dependent || axis.input_dependent;
        const float inverted=mul(in.sign[i],output.native_history[i]);
        const float unzoomed=mul(in.device,inverted),zoomed=mul(in.device,mul(output.ratio,inverted));
        axis.x=add(zoomed,in.steering[i]);axis.target=add(unzoomed,in.steering[i]);
        if(!bounded(axis.x) || !bounded(axis.target)
            || !pipeline(i,axis.x,axis.original_gain,in.context[i],in.dt_eval,in.dt_global,in.pitch_gate,axis.natural)
            || !pipeline(i,axis.target,axis.original_gain,in.context[i],in.dt_eval,in.dt_global,in.pitch_gate,axis.wanted))return Reason::unrepresentable;
        float centre=0;
        if(!axis.input_dependent){
            // Common S=0: choose the same gain even while input is zero or
            // changes after sampling. No predicted-U inverse or neighbour
            // selection may make this gain depend on raw/history/device/dt.
            centre=divide(axis.original_gain,output.ratio);
        }else{
            if(axis.x==axis.target || (axis.natural.gate_zero==axis.wanted.gate_zero
                && bits(axis.natural.increment)==bits(axis.wanted.increment))){axis.expected=axis.natural;continue;}
            if(axis.x==0 || axis.target==0)return Reason::singular;
            const double x_scale=std::fabs(static_cast<double>(zoomed))+std::fabs(static_cast<double>(in.steering[i]));
            const double target_scale=std::fabs(static_cast<double>(unzoomed))+std::fabs(static_cast<double>(in.steering[i]));
            // Relative cancellation only; no absolute slow-pan epsilon.
            if((x_scale>0 && std::fabs(axis.x)<MIN_CONDITION*x_scale)
                || (target_scale>0 && std::fabs(axis.target)<MIN_CONDITION*target_scale))return Reason::ill_conditioned;
            centre=narrow(static_cast<double>(axis.original_gain)*axis.target/axis.x);
        }
        if(!gain_valid(centre,axis.original_gain))return Reason::gain_range;
        const float candidates[3]{centre,neighbour(centre,false),neighbour(centre,true)};
        bool found=false;double best=std::numeric_limits<double>::infinity();
        const unsigned candidate_count=axis.input_dependent?3:1;
        for(unsigned k=0;k<candidate_count;++k){const float g=candidates[k];if(gain_valid(g,axis.original_gain)){
            Pipeline expected{};
            if(!pipeline(i,axis.x,g,in.context[i],in.dt_eval,in.dt_global,in.pitch_gate,expected))continue;
            if(expected.gate_zero!=axis.wanted.gate_zero)continue;
            const double error=std::fabs(static_cast<double>(expected.increment)-axis.wanted.increment);
            if(std::isfinite(error) && error<best){found=true;best=error;axis.gain=g;axis.expected=expected;}
        }}
        if(!found)return Reason::gate_mismatch;
        if(best>MAX_INCREMENT_ERROR
            || best>ABS_TOLERANCE+REL_TOLERANCE*std::fabs(static_cast<double>(axis.wanted.increment)))return Reason::excess_error;
    }
    for(unsigned i=0;i<2;++i){output.gains[i]=output.axis[i].gain;
        output.changed=output.changed || bits(output.gains[i])!=bits(in.native_gain[i]);}
    return output.changed?Reason::ready:Reason::identity;
}
}
