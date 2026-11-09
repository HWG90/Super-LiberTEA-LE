#pragma once
#include <cmath>
#include <cstdint>
#include <algorithm>
// A published, generation-owned Lua Update phase. This object never samples
// input or advances a timer from a renderer callback. Progress is shared by
// camera, native rig additions and FOV; every consumer keeps its own last
// actually displayed scalar/pose and spends the same remaining fraction.
namespace PresentationPhase {
inline float eased(float p){return p*p*(3-2*p);}
struct State {
    uint64_t epoch=0,used_epoch=0,published_at=0;
    float progress=1,used=0;
    bool ads=false;
    bool publish(uint64_t e,float p,uint32_t a,uint64_t now=0){
        if(!e || !std::isfinite(p)||p<0||p>1||a>1||e<epoch
            ||(e==epoch&&(p<progress||ads!=(a!=0))))return false;
        epoch=e;progress=p;ads=a!=0;published_at=now;return true;
    }
    bool matches(bool actual_ads,uint64_t now=0)const{return epoch!=0&&ads==actual_ads&&(!now||!published_at||(now>=published_at&&now-published_at<=250));}
    float step(bool actual_ads){
        if(!matches(actual_ads))return 1;
        if(used_epoch!=epoch){used_epoch=epoch;used=0;}
        const float current=eased(progress);
        const float amount=progress>=1?1:std::max(0.0f,std::min(1.0f,(current-used)/std::max(.000001f,1-used)));
        used=current;return amount;
    }
    void reset(){*this=State{};}
};
}
