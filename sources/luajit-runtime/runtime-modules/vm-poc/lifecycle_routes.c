#include "lifecycle_routes.h"
#include "lifecycle_witnesses.h"
#include <limits.h>
#include <string.h>
static void put32(unsigned char *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(unsigned char)(n>>(i*8));}
static void put64(unsigned char *p,uint64_t n){for(unsigned i=0;i<8;i++)p[i]=(unsigned char)(n>>(i*8));}
static int rel32(uintptr_t origin,uintptr_t target,uint32_t *out){
    if(target>=origin){if(target-origin>INT32_MAX)return 0;*out=(uint32_t)(target-origin);}
    else {if(origin-target>UINT64_C(2147483648))return 0;*out=0-(uint32_t)(origin-target);}
    return 1;
}
int hd2env_plan_lifecycle_patches(const void *image,size_t size,uintptr_t base,
                                const HD2LifecycleTargets *targets,HD2LifecyclePatch out[2]){
    const unsigned char *b=image;uint32_t displacement;
    if(!b||size<0x4ed5ff||base>UINTPTR_MAX-0x4ed5aa||!targets||!targets->construct||!targets->close||!out||
       !rel32(base+0x4ed5aa,targets->close,&displacement))return 0;
    if(memcmp(b+0x4ed2a0,lifecycle_construct_witness,sizeof(lifecycle_construct_witness))||
       memcmp(b+0x4ed590,lifecycle_close_witness,sizeof(lifecycle_close_witness)))return 0;
    HD2LifecyclePatch patches[2]={0};
    patches[0].rva=0x4ed3c2;patches[0].size=0x4ed56f - 0x4ed3c2;
    patches[1].rva=0x4ed5a2;patches[1].size=8;
    for(unsigned i=0;i<2;i++){
        memcpy(patches[i].original,b+patches[i].rva,patches[i].size);
        memset(patches[i].replacement,0x90,patches[i].size);
    }
    /* RCX=native environment (R14), RDX=resource manager at native+0x110. */
    const unsigned char args[]={0x49,0x8b,0xce,0x49,0x8b,0x96,0x10,0x01,0x00,0x00,0x48,0xb8};
    unsigned char *p=patches[0].replacement;memcpy(p,args,sizeof(args));put64(p+12,targets->construct);
    p[20]=0xff;p[21]=0xd0;p[22]=0xe9;put32(p+23,0x4ed56f-(patches[0].rva+27));
    /* Preserve the original destructor's preceding buffer cleanup. */
    p=patches[1].replacement;p[0]=0x48;p[1]=0x8b;p[2]=0xcf;p[3]=0xe8;put32(p+4,displacement);
    memcpy(out,patches,sizeof(patches));return 1;
}
