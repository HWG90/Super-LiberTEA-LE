#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>

// A short handoff correction in the caller's positively validated body-root
// coordinates. It never reads an engine object, stores a pointer, changes an
// orientation, samples input, or filters a native6 camera. Timestamps are
// finite nonnegative DOUBLE milliseconds; no integer quantization is applied.
// The caller must call
// reset when its body/root identity retires; native6 is remembered read-only.
namespace CameraCorrection {
constexpr float MAX_RESIDUAL_METRES=1.0f;
constexpr float MAX_RELATIVE_COMPONENT=16.0f;
inline bool finite_relative(const float p[3]) {
    if(!p)return false;
    for(unsigned i=0;i<3;++i)if(!std::isfinite(p[i])||std::fabs(p[i])>MAX_RELATIVE_COMPONENT)return false;
    return true;
}
inline bool within_residual(const float a[3],const float b[3]) {
    double distance=0;
    for(unsigned i=0;i<3;++i) {const double d=static_cast<double>(a[i])-b[i];distance+=d*d;}
    return distance<=static_cast<double>(MAX_RESIDUAL_METRES)*MAX_RESIDUAL_METRES;
}
inline double ease(double x){return x*x*(3-2*x);}
struct State {
    float progress=1;
    bool active=false;
private:
    bool remembered=false,observed=false;
    uint32_t current_weapon=0;
    double native_tick=0,last_tick=0,started=0;
    double used=0;float handoff_duration_ms=150;
    float native_relative[3]{},last_presented[3]{};
    static bool weapon_valid(uint32_t weapon){return weapon!=0 && weapon!=UINT32_MAX;}
    static void copy(const float source[3],float destination[3]){for(unsigned i=0;i<3;++i)destination[i]=source[i];}
public:
    void reset(){*this=State{};}
    bool remember(const float relative[3],uint32_t weapon,double tick) {
        if(!finite_relative(relative)||!weapon_valid(weapon)||!std::isfinite(tick)||tick<0) {reset();return false;}
        if(observed&&tick<last_tick) {reset();return false;}
        // A different positively validated firearm starts a new record. None
        // of the previous firearm's correction/presentation follows it.
        reset();remembered=observed=true;current_weapon=weapon;
        native_tick=last_tick=tick;copy(relative,native_relative);return true;
    }
    // True means a valid fresh desired position was returned, corrected or
    // exactly passed through. Missing/stale history, clock discontinuity,
    // weapon changes and large solve jumps pass that fresh position through.
    // False is an invalid vector/parameter contract; no engine fallback is
    // implied. A finite desired input is still copied to out when possible.
    bool apply(const float desired_relative[3],uint32_t weapon,double tick,float out[3],
               float duration_ms=150,uint32_t max_gap_ms=250) {
        const bool valid=finite_relative(desired_relative);
        if(out&&valid)copy(desired_relative,out);
        if(!out||!valid||!weapon_valid(weapon)||!std::isfinite(tick)||tick<0||!std::isfinite(duration_ms)||duration_ms<0||duration_ms>500
            ||max_gap_ms<16||max_gap_ms>1000) {reset();return false;}
        if(duration_ms==0) {reset();return true;}
        if(observed&&(weapon!=current_weapon||tick<last_tick||tick-last_tick>max_gap_ms)) {reset();return true;}
        if(remembered) {
            if(tick<native_tick||tick-native_tick>max_gap_ms||!within_residual(native_relative,desired_relative)) {
                reset();return true;
            }
            remembered=false;active=true;started=tick;used=0;progress=0;handoff_duration_ms=duration_ms;
            copy(native_relative,last_presented);
        }
        if(!active)return true;
        if(!within_residual(last_presented,desired_relative)) {reset();return true;}
        const double fraction=std::min(1.0,(tick-started)/handoff_duration_ms);
        progress=static_cast<float>(fraction);last_tick=tick;observed=true;
        if(fraction>=1) {active=false;used=1;copy(desired_relative,last_presented);return true;}
        const double current=ease(fraction);
        const double step=std::max(0.0,std::min(1.0,(current-used)/std::max(1e-12,1-used)));
        // Only the correction is carried. Rebase it from the last actual
        // presentation against each fresh solve; repeated timestamps retain
        // exact presentation rather than accumulating another filter step.
        if(step==0)copy(last_presented,out);
        else for(unsigned i=0;i<3;++i)out[i]=static_cast<float>(last_presented[i]+(desired_relative[i]-last_presented[i])*step);
        copy(out,last_presented);used=current;return true;
    }
};
}
