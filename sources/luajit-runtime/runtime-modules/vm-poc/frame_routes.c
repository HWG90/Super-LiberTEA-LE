#include "frame_routes.h"
#include <string.h>
#include "frame_witnesses.h"

static void put64(unsigned char *p,uint64_t v){for(unsigned i=0;i<8;i++)p[i]=(unsigned char)(v>>(8*i));}
static void put32(unsigned char *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(unsigned char)(v>>(8*i));}
static void emit(HD2FramePatch *p,size_t *at,const unsigned char *bytes,size_t n){
    memcpy(p->replacement+*at,bytes,n);*at+=n;
}
static void call(HD2FramePatch *p,size_t *at,uintptr_t target){
    const unsigned char mov[]={0x48,0xb8};emit(p,at,mov,sizeof(mov));
    put64(p->replacement+*at,target);*at+=8;
    const unsigned char invoke[]={0xff,0xd0};emit(p,at,invoke,sizeof(invoke));
}
static void finish(HD2FramePatch *p,size_t at,uint32_t resume){
    p->replacement[at]=0xe9;
    put32(p->replacement+at+1,resume-(p->rva+(uint32_t)at+5));
}
int hd2env_plan_frame_patches(const void *image,size_t size,const HD2FrameTargets *targets,HD2FramePatch out[2]){
    const unsigned char *b=image;
    if(!b||!targets||!out||size<0x6ce790||!targets->gc||!targets->update||!targets->render)return 0;
    if(memcmp(b+0x6ce620,frame_update_witness,sizeof(frame_update_witness))||
       memcmp(b+0x6ce730,frame_render_witness,sizeof(frame_render_witness)))return 0;
    HD2FramePatch patches[2]={0};
    patches[0].rva=0x6ce664;patches[0].size=0x6ce70e - 0x6ce664;
    patches[1].rva=0x6ce734;patches[1].size=0x6ce770 - 0x6ce734;
    for(unsigned i=0;i<2;i++){
        memcpy(patches[i].original,b+patches[i].rva,patches[i].size);
        memset(patches[i].replacement,0x90,patches[i].size);
    }
    size_t at=0;
    const unsigned char env_from_rdi[]={0x48,0x8d,0x8f,0x90,0x01,0x00,0x00};
    const unsigned char float_dt[]={0x0f,0x28,0xce}; /* movaps xmm1,xmm6 */
    emit(&patches[0],&at,env_from_rdi,sizeof(env_from_rdi));call(&patches[0],&at,targets->gc);
    emit(&patches[0],&at,env_from_rdi,sizeof(env_from_rdi));emit(&patches[0],&at,float_dt,sizeof(float_dt));
    call(&patches[0],&at,targets->update);finish(&patches[0],at,0x6ce70e);
    at=0;
    const unsigned char env_from_rcx[]={0x48,0x8d,0x89,0x90,0x01,0x00,0x00};
    emit(&patches[1],&at,env_from_rcx,sizeof(env_from_rcx));call(&patches[1],&at,targets->render);
    finish(&patches[1],at,0x6ce770);
    memcpy(out,patches,sizeof(patches));return 1;
}
