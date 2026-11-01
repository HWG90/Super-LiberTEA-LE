/* Current-build native binding preparation, not a VM installer or detour.
 * The independently traced Unit C API accepts no lua_State at all. */
#include "environment.h"
#include <string.h>
#include "curve_witness.h"
#ifdef _WIN32
#include <windows.h>
#endif

static uint32_t read32(const unsigned char *p) {
    return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;
}
static uint64_t read64(const unsigned char *p) {
    return (uint64_t)read32(p)|((uint64_t)read32(p+4)<<32);
}
static int header_matches(const unsigned char *b) {
    if(b[0]!='M'||b[1]!='Z')return 0;
    uint32_t nt=read32(b+0x3c);
    if(nt>0x1000||memcmp(b+nt,"PE\0\0",4))return 0;
    if(b[nt+4]!=0x64||b[nt+5]!=0x86||read32(b+nt+8)!=0x6ae0964a)return 0;
    return b[nt+24]==0x0b && b[nt+25]==0x02 && read32(b+nt+24+56)==0x29fe000;
}
int hd2env_probe_curve_image(const void *image,size_t size,uintptr_t mapped_base) {
    const unsigned char *b=image;
    if(!b||size<0x29fe000||!header_matches(b))return 0;
    if(mapped_base>UINTPTR_MAX-0x29fe000)return 0;
    if(read64(b+0x2870810)!=(uint64_t)mapped_base+0x1f82f0)return 0;
    return !memcmp(b+0x1f82f0,curve_witness,sizeof(curve_witness));
}

#ifdef _WIN32
static int readable(const void *p,size_t bytes,int executable) {
    MEMORY_BASIC_INFORMATION m;
    if(!VirtualQuery(p,&m,sizeof(m))||m.State!=MEM_COMMIT||(m.Protect&(PAGE_GUARD|PAGE_NOACCESS)))return 0;
    uintptr_t at=(uintptr_t)p,begin=(uintptr_t)m.BaseAddress;
    if(at<begin||at-begin>m.RegionSize||bytes>m.RegionSize-(at-begin))return 0;
    if(executable && !(m.Protect&(PAGE_EXECUTE_READ|PAGE_EXECUTE_READWRITE|PAGE_EXECUTE_WRITECOPY)))return 0;
    return 1;
}
#endif
int hd2env_bind_current_curve(HD2Backend *backend) {
#ifdef _WIN32
    if(!backend)return 0;
    const unsigned char *base=(const unsigned char *)GetModuleHandleW(NULL);
    if(!base||!readable(base,0x1200,0)||!header_matches(base))return 0;
    uintptr_t start=(uintptr_t)base;
    if(start>UINTPTR_MAX-0x29fe000)return 0;
    if(!readable((const void *)(start+0x2870810),8,0)
       ||!readable((const void *)(start+0x1f82f0),sizeof(curve_witness),1))return 0;
    if(!hd2env_probe_curve_image(base,0x29fe000,(uintptr_t)base))return 0;
    uintptr_t entry=(uintptr_t)base+0x1f82f0;
    _Static_assert(sizeof(backend->animation_curve)==sizeof(entry),"Win64 function pointer size");
    memcpy(&backend->animation_curve,&entry,sizeof(entry));
    return 1;
#else
    (void)backend;return 0;
#endif
}
