#include "gc_policy.h"
#include "gc_witnesses.h"
#include <string.h>
int hd2env_plan_gc_patch(const void *image,size_t size,uintptr_t target,HD2GCPatch *out){
    const unsigned char *b=image;
    if(!b||!out||!target||size<0x5eb566||memcmp(b+0x5eb340,gc_caller_witness,sizeof(gc_caller_witness)))return 0;
    HD2GCPatch patch={0};patch.rva=0x5eb340;patch.size=12;
    memcpy(patch.original,b+patch.rva,12);patch.replacement[0]=0x48;patch.replacement[1]=0xb8;
    for(unsigned i=0;i<8;i++)patch.replacement[i+2]=(unsigned char)(target>>(i*8));
    patch.replacement[10]=0xff;patch.replacement[11]=0xe0;*out=patch;return 1;
}
