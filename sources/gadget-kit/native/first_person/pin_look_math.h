#pragma once
#include "free_aim_math.h"
#include <cstdint>
namespace PinLook {
constexpr float LIMIT=FreeAim::PI*.5f-.0001f;
struct State {
    bool ready=false;float yaw=0,pitch=0;FreeAim::Q world{};
    void reset(){ready=false;yaw=pitch=0;world={};}
    bool seed(FreeAim::Q q) {
        if(!FreeAim::valid(q))return false;
        const float n=std::sqrt(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w);q={q.x/n,q.y/n,q.z/n,q.w/n};
        float forward[3]{},right[3]{};const float north[3]{0,1,0},east[3]{1,0,0};
        FreeAim::rotate(q,north,forward);FreeAim::rotate(q,east,right);
        const float h=std::sqrt(forward[0]*forward[0]+forward[1]*forward[1]);
        if(h>.00001f)yaw=std::atan2(-forward[0],forward[1]);
        else if(right[0]*right[0]+right[1]*right[1]>.00000001f)yaw=std::atan2(right[1],right[0]);
        else return false;
        pitch=std::max(-LIMIT,std::min(LIMIT,std::asin(FreeAim::limit(forward[2],1))));
        world=FreeAim::look(yaw,pitch);ready=true;return true;
    }
    bool integrate(float x,float y,float dt,float gain_yaw,float gain_pitch) {
        if(!ready || !std::isfinite(x)||!std::isfinite(y)||std::fabs(x)>10000||std::fabs(y)>10000
            || !std::isfinite(dt)||dt<=0||dt>.25f || !std::isfinite(gain_yaw)||!std::isfinite(gain_pitch)
            || gain_yaw<=0||gain_yaw>16||gain_pitch<=0||gain_pitch>16)return false;
        yaw=FreeAim::wrap(yaw-x*dt*gain_yaw);
        pitch=std::max(-LIMIT,std::min(LIMIT,pitch+y*dt*gain_pitch));
        world=FreeAim::look(yaw,pitch);return true;
    }
};
}
