#include "native_friends.h"
#include "friends_witnesses.h"
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#endif
static uint32_t word(const unsigned char *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
int hd2env_probe_friends_host(const HD2FriendsHost *h){
    if(!h||!h->image_base||h->image_base>UINTPTR_MAX-0x29fe000||!h->read||!h->write||!h->callable)return 0;
    unsigned char header[0x1200],buffer[8192];
    if(h->read(h->context,h->image_base,header,sizeof(header))!=1||header[0]!='M'||header[1]!='Z')return 0;
    uint32_t nt=word(header+0x3c);
    if(nt>0x1000||memcmp(header+nt,"PE\0\0",4)||header[nt+4]!=0x64||header[nt+5]!=0x86||
       word(header+nt+8)!=0x6af2d5e6||header[nt+24]!=0x0b||header[nt+25]!=2||word(header+nt+24+56)!=0x29fe000)return 0;
    for(size_t i=0;i<sizeof(friends_regions)/sizeof(*friends_regions);i++){
        if(friends_regions[i].size>sizeof(buffer)||h->read(h->context,h->image_base+friends_regions[i].rva,buffer,friends_regions[i].size)!=1||
           memcmp(buffer,friends_regions[i].bytes,friends_regions[i].size))return 0;
    }
    return 1;
}
#ifdef _WIN32
static int permitted(uintptr_t address,size_t size,int write,int execute){
    if(!address||size>UINTPTR_MAX-address)return 0;
    while(size){
        MEMORY_BASIC_INFORMATION m;if(!VirtualQuery((void *)address,&m,sizeof(m))||m.State!=MEM_COMMIT||
           (m.Protect&(PAGE_GUARD|PAGE_NOACCESS)))return 0;
        DWORD p=m.Protect&0xff;
        if(write&&p!=PAGE_READWRITE&&p!=PAGE_WRITECOPY&&p!=PAGE_EXECUTE_READWRITE&&p!=PAGE_EXECUTE_WRITECOPY)return 0;
        if(execute&&p!=PAGE_EXECUTE_READ&&p!=PAGE_EXECUTE_READWRITE&&p!=PAGE_EXECUTE_WRITECOPY)return 0;
        if(!write&&!execute&&p!=PAGE_READONLY&&p!=PAGE_READWRITE&&p!=PAGE_WRITECOPY&&p!=PAGE_EXECUTE_READ&&
           p!=PAGE_EXECUTE_READWRITE&&p!=PAGE_EXECUTE_WRITECOPY)return 0;
        uintptr_t begin=(uintptr_t)m.BaseAddress;
        if(address<begin||address-begin>=m.RegionSize)return 0;
        size_t span=m.RegionSize-(address-begin);if(span>size)span=size;
        address+=span;size-=span;
    }
    return 1;
}
static int native_read(void *context,uintptr_t address,void *out,size_t size){
    (void)context;if(!permitted(address,size,0,0))return 0;memcpy(out,(void *)address,size);return 1;
}
static int native_write(void *context,uintptr_t address,const void *in,size_t size){
    (void)context;if(!permitted(address,size,1,0))return 0;memcpy((void *)address,in,size);return 1;
}
static int native_callable(void *context,uintptr_t address){(void)context;return permitted(address,1,0,1);}
#endif
int hd2env_current_friends_host(HD2FriendsHost *out){
#ifdef _WIN32
    if(!out)return 0;
    HD2FriendsHost h={NULL,(uintptr_t)GetModuleHandleW(NULL),native_read,native_write,native_callable};
    if(!hd2env_probe_friends_host(&h))return 0;
    *out=h;return 1;
#else
    (void)out;return 0;
#endif
}
