#include "boot_routes.h"
#include "boot_witnesses.h"
#include <limits.h>
#include <string.h>
static void put32(unsigned char *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(unsigned char)(n>>(i*8));}
static void put64(unsigned char *p,uint64_t n){for(unsigned i=0;i<8;i++)p[i]=(unsigned char)(n>>(i*8));}
static int rel32(uintptr_t origin,uintptr_t target,uint32_t *out){
    if(target>=origin){if(target-origin>INT32_MAX)return 0;*out=(uint32_t)(target-origin);}
    else {if(origin-target>UINT64_C(2147483648))return 0;*out=0-(uint32_t)(origin-target);}
    return 1;
}
int hd2env_plan_boot_patches(const void *image,size_t size,uintptr_t base,
                           const HD2BootTargets *t,HD2LifecyclePatch out[HD2_BOOT_PATCHES]){
    static const uint32_t sites[]={0x6ce0ac,0x6ce11c,0x6ce12b,0x6ce136,0x6ce13e,0x6ce161,0x6ce16c,0x6ce17b};
    uint32_t offsets[8];const unsigned char *b=image;
    if(!b||size<0x6ce6db||base>UINTPTR_MAX-0x6ce6db||!t||!t->configure||!t->start||!out)return 0;
    for(unsigned i=0;i<8;i++)if(!t->registrars[i]||!rel32(base+sites[i]+5,t->registrars[i],offsets+i))return 0;
    if(memcmp(b+0x6cded0,boot_witness,sizeof(boot_witness)))return 0;
    HD2LifecyclePatch p[HD2_BOOT_PATCHES]={0};
    p[0].rva=0x6cdf0d;p[0].size=0x6cdf52-0x6cdf0d;
    for(unsigned i=0;i<8;i++){p[i+1].rva=sites[i];p[i+1].size=5;}
    p[9].rva=0x6ce250;p[9].size=0x6ce44d-0x6ce250;
    p[10].rva=0x6ce578;p[10].size=9;
    p[11].rva=0x6ce581;p[11].size=0x6ce6b9-0x6ce581;
    p[12].rva=0x6ce6c1;p[12].size=4;
    for(unsigned i=0;i<HD2_BOOT_PATCHES;i++){
        memcpy(p[i].original,b+p[i].rva,p[i].size);memset(p[i].replacement,0x90,p[i].size);
    }
    /* Keep register setup, remove every old-state stack access. */
    const unsigned char setup[]={0x45,0x33,0xed,0x4c,0x8b,0xf9,0x48,0x89,0x5d,0x58,
                                0x4c,0x8d,0xa1,0x88,0x00,0x00,0x00};
    memcpy(p[0].replacement,setup,sizeof(setup));
    for(unsigned i=0;i<8;i++){p[i+1].replacement[0]=0xe8;put32(p[i+1].replacement+1,offsets[i]);}
    unsigned char *q=p[9].replacement;
    /* Original CL -> native network flag is inside the replaced config loop. */
    q[0]=0x88;q[1]=0x0d;put32(q+2,0x1bbad81-(p[9].rva+6));
    const unsigned char config[]={0x48,0x8b,0xce,0x48,0x8b,0x55,0x50,0x48,0xb8};
    memcpy(q+6,config,sizeof(config));put64(q+15,t->configure);q[23]=0xff;q[24]=0xd0;
    const unsigned char minus_one[]={0x49,0xc7,0xc7,0xff,0xff,0xff,0xff};
    memcpy(q+25,minus_one,sizeof(minus_one));q[32]=0xe9;put32(q+33,0x6ce44d-(p[9].rva+37));
    /* Missing boot_script branches land at both 0x418 and 0x41b. Initialize
     * the null pointer explicitly; the original reads an unset stack slot. */
    const unsigned char missing[]={0x45,0x33,0xed,0x33,0xc0,0x45,0x33,0xf6,0x90};
    memcpy(p[10].replacement,missing,sizeof(missing));
    q=p[11].replacement;
    const unsigned char start[]={0x8b,0xf8,0x49,0x03,0xfe,0x48,0x8b,0xce,0x48,0x8b,0xd7,0x48,0xb8};
    memcpy(q,start,sizeof(start));put64(q+13,t->start);q[21]=0xff;q[22]=0xd0;
    q[23]=0xe9;put32(q+24,0x6ce6b9-(p[11].rva+28));
    memcpy(out,p,sizeof(p));return 1;
}
