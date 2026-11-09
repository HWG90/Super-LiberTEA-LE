#include "camera_correction.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <limits>
#include <cstring>
#include <algorithm>
#define CHECK(x) do{if(!(x)){std::fprintf(stderr,"FAIL %d: %s\n",__LINE__,#x);std::abort();}}while(0)
using CameraCorrection::State;
static unsigned cases=0;
static void pass(const char* name){++cases;std::printf("PASS %s\n",name);}
static bool near(float a,float b,float e=.000003f){return std::fabs(a-b)<=e;}
static bool same(const float a[3],const float b[3]){return std::memcmp(a,b,12)==0;}
static void finite(const float p[3]){for(unsigned i=0;i<3;++i)CHECK(std::isfinite(p[i]));}
static std::vector<double> times(unsigned fps,std::vector<double> checkpoints={}) {
    std::vector<double> result{0,150};
    for(unsigned frame=1;frame<fps;++frame){const double t=frame*1000.0/fps;if(t<150)result.push_back(t);}
    result.insert(result.end(),checkpoints.begin(),checkpoints.end());std::sort(result.begin(),result.end());
    result.erase(std::unique(result.begin(),result.end()),result.end());return result;
}
int main(){
    const float native[3]{.12f,-.1f,1.62f},desired[3]{0,.08f,1.7f};float out[3]{};
    State s;CHECK(s.apply(desired,1,1000,out)&&same(out,desired)&&!s.active&&s.progress==1);
    CHECK(s.remember(native,1,1000));CHECK(s.apply(desired,1,1001,out)&&same(out,native)&&s.active&&s.progress==0);
    CHECK(s.apply(desired,1,1076,out));finite(out);
    for(unsigned i=0;i<3;++i)CHECK(near(out[i],native[i]+(desired[i]-native[i])*.5f));
    CHECK(s.apply(desired,1,1151,out)&&same(out,desired)&&!s.active&&s.progress==1);
    const float later[3]{.1f,.1f,1.8f};CHECK(s.apply(later,1,1152,out)&&same(out,later));
    pass("first normal4 frame preserves the observed native6 endpoint, finishes exactly, then returns all fresh motion unfiltered");

    std::vector<std::vector<float>> comparisons;
    for(unsigned fps:{30U,60U,144U,240U}) {
        State state;CHECK(state.remember(native,7,2000));std::vector<float> checkpoints;
        for(double t:times(fps,{37,75,112})) {
            CHECK(state.apply(desired,7,2000+t,out));finite(out);
            for(unsigned i=0;i<3;++i) {
                const float low=std::min(native[i],desired[i]),high=std::max(native[i],desired[i]);CHECK(out[i]>=low-.000001f&&out[i]<=high+.000001f);
            }
            if(t==37||t==75||t==112)checkpoints.insert(checkpoints.end(),out,out+3);
        }
        CHECK(!state.active&&state.progress==1&&same(out,desired));comparisons.push_back(checkpoints);
    }
    for(unsigned sample=1;sample<comparisons.size();++sample)for(unsigned i=0;i<comparisons[0].size();++i)CHECK(near(comparisons[0][i],comparisons[sample][i]));
    pass("30,60,144 and240FPS at true fractional cadence produce the same stationary-target trajectory at common timestamps, with no overshoot");

    s.reset();CHECK(s.remember(native,1,3000));CHECK(s.apply(desired,1,3000,out));CHECK(s.apply(desired,1,3050,out));
    float before_jump[3]{};std::memcpy(before_jump,out,12);
    const float late[3]{.2f,.05f,1.68f};CHECK(s.apply(late,1,3050,out)&&same(out,before_jump));
    CHECK(s.apply(late,1,3075,out));finite(out);
    for(unsigned i=0;i<3;++i)CHECK(out[i]>=std::min(before_jump[i],late[i])-.000001f&&out[i]<=std::max(before_jump[i],late[i])+.000001f);
    CHECK(s.apply(late,1,3150,out)&&same(out,late));
    pass("a late native solve cannot bypass handoff continuity at an unchanged timestamp and still completes within the finite deadline");

    s.reset();CHECK(s.remember(native,1,4000));CHECK(s.apply(desired,1,4000,out));CHECK(s.apply(desired,1,4050,out));
    const float resumed_native[3]{.08f,-.02f,1.65f};CHECK(s.remember(resumed_native,1,4051)&&!s.active);
    CHECK(s.apply(desired,1,4052,out)&&same(out,resumed_native)&&s.active&&s.progress==0);
    CHECK(s.apply(desired,1,4202,out)&&same(out,desired)&&!s.active);
    pass("rapid ADS/native6 reversal uses the newly observed endpoint, never a stale prior correction");

    for(unsigned mode=0;mode<3;++mode) {
        s.reset();CHECK(s.remember(native,1,5000));CHECK(s.apply(desired,1,5000,out));
        const unsigned tick=mode==0?4999:mode==1?5251:5010;const unsigned weapon=mode==2?2:1;
        CHECK(s.apply(later,weapon,tick,out)&&same(out,later)&&!s.active&&s.progress==1);
        CHECK(s.apply(desired,weapon,tick+1,out)&&same(out,desired));
    }
    pass("clock rollback, a frame hitch and a weapon replacement discard all carried correction instead of catching up");

    s.reset();CHECK(s.remember(native,1,6000));CHECK(s.apply(desired,1,6251,out)&&same(out,desired)&&!s.active);
    CHECK(s.remember(native,1,7000));CHECK(s.apply(desired,2,7001,out)&&same(out,desired)&&!s.active);
    CHECK(s.remember(native,2,7002));CHECK(s.apply(desired,2,7003,out)&&same(out,native)&&s.active);
    pass("stale or differently owned native6 history is ignored; a fresh new-weapon observation may start its own handoff");

    s.reset();CHECK(s.remember(native,1,8000));const float teleport[3]{2,0,1.7f};
    CHECK(s.apply(teleport,1,8001,out)&&same(out,teleport)&&!s.active);
    CHECK(s.remember(native,1,8100));CHECK(s.apply(desired,1,8101,out));
    CHECK(s.apply(teleport,1,8102,out)&&same(out,teleport)&&!s.active);
    CHECK(s.apply(desired,1,8103,out)&&same(out,desired));
    pass("oversized initial or mid-handoff residuals reset immediately without interpolating through world geometry");

    for(float bad:{std::numeric_limits<float>::quiet_NaN(),std::numeric_limits<float>::infinity(),17.0f}) {
        float value[3]{bad,0,1.7f};CHECK(!s.remember(value,1,9000)&&!s.active);
        CHECK(s.remember(native,1,9001));CHECK(!s.apply(value,1,9002,out)&&!s.active);
        CHECK(s.apply(desired,1,9003,out)&&same(out,desired));
    }
    CHECK(!s.remember(native,0,9004));CHECK(!s.remember(native,UINT32_MAX,9004));
    CHECK(!s.remember(nullptr,1,9004));CHECK(!s.apply(desired,1,9004,nullptr));
    pass("invalid vectors, invalid weapon tokens and missing buffers cannot leave an armed correction");

    for(float duration:{-1.0f,501.0f,std::numeric_limits<float>::quiet_NaN()}) {
        CHECK(s.remember(native,1,10000));CHECK(!s.apply(desired,1,10001,out,duration)&&same(out,desired)&&!s.active);
    }
    for(unsigned gap:{0U,15U,1001U}) {CHECK(s.remember(native,1,10002));CHECK(!s.apply(desired,1,10003,out,150,gap)&&same(out,desired)&&!s.active);}
    CHECK(s.remember(native,1,10004));CHECK(s.apply(desired,1,10005,out,0)&&same(out,desired)&&!s.active);
    pass("duration and gap bounds fail safely; zero duration explicitly returns immediate fresh presentation");

    CHECK(s.remember(native,1,11000));CHECK(s.apply(desired,1,11000,out));CHECK(s.apply(desired,1,11075,out));
    float held[3]{};std::memcpy(held,out,12);
    for(unsigned i=0;i<100;++i)CHECK(s.apply(desired,1,11075,out)&&same(out,held));
    CHECK(s.apply(desired,1,11150,out)&&same(out,desired));
    CHECK(s.remember(native,1,12000));CHECK(!s.remember(native,1,11999));CHECK(s.apply(desired,1,12001,out)&&same(out,desired));
    pass("repeated renderer callbacks do not spend phase twice, and a reversed native timestamp retires its record");

    CHECK(s.remember(native,1,13000));CHECK(s.apply(desired,1,13000,out,500));CHECK(s.apply(desired,1,13200,out,500));
    CHECK(s.active&&s.progress<1);s.reset();CHECK(s.progress==1&&!s.active);CHECK(s.apply(later,1,13201,out)&&same(out,later));
    CHECK(s.remember(native,1,14000));CHECK(s.apply(desired,1,14000,out,1));CHECK(s.apply(desired,1,14001,out,1)&&same(out,desired)&&!s.active);
    pass("explicit stop drops presentation history and all supported durations terminate at their target");
    CHECK(s.remember(native,1,15000));CHECK(s.apply(desired,1,15000,out,150));
    CHECK(s.apply(desired,1,15075,out,500));CHECK(near(s.progress,.5f));
    CHECK(s.apply(desired,1,15150,out,500)&&same(out,desired)&&!s.active);
    pass("a live duration edit cannot rewind progress or extend an already-started handoff");
    comparisons.clear();
    for(unsigned fps:{30U,60U,144U,240U}) {
        State state;CHECK(state.remember(native,17,16000.125));std::vector<float> checkpoints;
        for(double t:times(fps,{.125,37.125,75.125,112.125})) {
            CHECK(state.apply(desired,17,16000.125+t,out));finite(out);
            if(t==.125)CHECK(state.progress>0&&!same(out,native));
            if(t==37.125||t==75.125||t==112.125)checkpoints.insert(checkpoints.end(),out,out+3);
        }
        CHECK(!state.active&&same(out,desired));comparisons.push_back(checkpoints);
    }
    for(unsigned sample=1;sample<comparisons.size();++sample)for(unsigned i=0;i<comparisons[0].size();++i)CHECK(near(comparisons[0][i],comparisons[sample][i]));
    CHECK(s.remember(native,1,17000.125));CHECK(s.apply(desired,1,17000.125,out));
    CHECK(s.apply(desired,1,17000.125+1000.0/240,out));CHECK(near(s.progress,static_cast<float>((1000.0/240)/150),.0000001f));
    pass("fractional clock origins and submillisecond progress retain equivalent30,60,144,240Hz paths without integer-millisecond quantization");
    for(double tick:{-1.0,std::numeric_limits<double>::quiet_NaN(),std::numeric_limits<double>::infinity()}) {
        CHECK(!s.remember(native,1,tick)&&!s.active);
        CHECK(s.remember(native,1,18000.25));CHECK(!s.apply(desired,1,tick,out)&&same(out,desired)&&!s.active);
    }
    pass("negative and nonfinite high-resolution clock samples retire history and fail the timestamp contract");
    std::printf("Camera correction fixture PASS: %u groups\n",cases);return 0;
}
