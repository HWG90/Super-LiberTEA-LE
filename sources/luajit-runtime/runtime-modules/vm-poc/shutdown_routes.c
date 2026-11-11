#include "shutdown_routes.h"
#include "shutdown_witnesses.h"
#include <string.h>
static void put32(unsigned char *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(unsigned char)(n>>(i*8));}
static void put64(unsigned char *p,uint64_t n){for(unsigned i=0;i<8;i++)p[i]=(unsigned char)(n>>(i*8));}
int hd2env_plan_shutdown_patches(const void *image,size_t size,const HD2ShutdownTargets *targets,HD2ShutdownPatch out[3]){
    const unsigned char *b=image;
    if(!b||size<0x6cd89b||!targets||!targets->shutdown||!targets->collect||!out||
       memcmp(b+0x6cd4a0,shutdown_game_witness,sizeof(shutdown_game_witness)))return 0;
    HD2ShutdownPatch patches[3]={0};
    const uint32_t starts[]={0x6cd4dd,0x6cd4f9,0x6cd591},ends[]={0x6cd4f9,0x6cd58a,0x6cd595};
    for(unsigned i=0;i<3;i++){
        patches[i].rva=starts[i];patches[i].size=ends[i]-starts[i];
        memcpy(patches[i].original,b+starts[i],patches[i].size);memset(patches[i].replacement,0x90,patches[i].size);
        if(i==2)continue; /* NOP old threshold store without touching CMP flags. */
        unsigned char *p=patches[i].replacement;
        /* lea rcx,[r14+0x190]; movabs rax,target; call rax */
        const unsigned char args[]={0x49,0x8d,0x8e,0x90,0x01,0x00,0x00,0x48,0xb8};
        memcpy(p,args,sizeof(args));put64(p+9,i?targets->collect:targets->shutdown);p[17]=0xff;p[18]=0xd0;
        if(i){p[19]=0xe9;put32(p+20,ends[i]-(starts[i]+24));}
    }
    memcpy(out,patches,sizeof(patches));return 1;
}
