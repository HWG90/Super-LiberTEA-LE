#include "native_steam.h"
#include "steam_witnesses.h"
#include <string.h>
#include <stdio.h>
#ifdef _WIN32
#include <windows.h>
#endif
static uint32_t word(const unsigned char *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
int hd2env_probe_steam_host(const HD2SteamHost *h){
    if(!h||!h->image_base||h->image_base>UINTPTR_MAX-0x29fe000||!h->read||!h->write||!h->callable)return 0;
    unsigned char header[0x1200],buffer[2048];
    if(h->read(h->context,h->image_base,header,sizeof(header))!=1||header[0]!='M'||header[1]!='Z')return 0;
    uint32_t nt=word(header+0x3c);
    if(nt>0x1000||memcmp(header+nt,"PE\0\0",4)||header[nt+4]!=0x64||header[nt+5]!=0x86||
       word(header+nt+8)!=0x6af2d5e6||header[nt+24]!=0x0b||header[nt+25]!=2||word(header+nt+24+56)!=0x29fe000)return 0;
    for(size_t i=0;i<sizeof(steam_regions)/sizeof(*steam_regions);i++){
        if(steam_regions[i].size>sizeof(buffer)||h->read(h->context,h->image_base+steam_regions[i].rva,buffer,steam_regions[i].size)!=1||
           memcmp(buffer,steam_regions[i].bytes,steam_regions[i].size))return 0;
    }
    for(size_t i=0;i<20;i++)for(size_t k=0;k<2;k++){
        uintptr_t address;size_t n=strlen(steam_languages[i][k])+1;
        if(h->read(h->context,h->image_base+0x16fa8b0+i*16+k*8,&address,8)!=1||
           address!=h->image_base+steam_language_rvas[i][k]||
           h->read(h->context,address,buffer,n)!=1||memcmp(buffer,steam_languages[i][k],n))return 0;
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
    (void)context;
    if(!address||size>UINTPTR_MAX-address||(!out&&size))return 0;
    /* A Steam method under Proton can return a string in a native Unix
     * mapping. VirtualQuery reports that address as MEM_FREE even though
     * ReadProcessMemory safely transfers it. Require a complete checked read
     * instead of dereferencing after a Windows-only allocation query. */
    SIZE_T copied=0;
    return ReadProcessMemory(GetCurrentProcess(),(const void *)address,out,size,&copied)&&copied==size;
}
static int native_write(void *context,uintptr_t address,const void *in,size_t size){
    (void)context;if(!permitted(address,size,1,0))return 0;memcpy((void *)address,in,size);return 1;
}
static int native_callable(void *context,uintptr_t address){(void)context;return permitted(address,1,0,1);}
#endif
int hd2env_current_steam_host(HD2SteamHost *out){
#ifdef _WIN32
    if(!out)return 0;
    HD2SteamHost h={NULL,(uintptr_t)GetModuleHandleW(NULL),native_read,native_write,native_callable};
    if(!hd2env_probe_steam_host(&h))return 0;
    *out=h;return 1;
#else
    (void)out;return 0;
#endif
}
/* The page holding address, for refusal reasons (Windows: this process's view). */
static void code_page(const HD2SteamHost *h,uintptr_t address,char *out,size_t size){
    out[0]=0;
#ifdef _WIN32
    MEMORY_BASIC_INFORMATION m;
    if(!VirtualQuery((void *)address,&m,sizeof(m))){snprintf(out,size,"; page state unavailable");return;}
    uintptr_t page=(uintptr_t)m.BaseAddress;
    snprintf(out,size,"; page %s0x%llx state 0x%lx, protect 0x%lx, type 0x%lx",page>=h->image_base?"+":"",
        (unsigned long long)(page>=h->image_base?page-h->image_base:page),m.State,m.Protect,m.Type);
#else
    (void)h;(void)address;(void)size;
#endif
}
int hd2env_check_code(const HD2SteamHost *h,uintptr_t address,const unsigned char *witness,size_t size,char *why,size_t why_size){
    char none[1],page[128];unsigned char code[1024];
    if(!why||!why_size){why=none;why_size=sizeof(none);}
    why[0]=0;
    if(!h||!h->read||!h->callable||!address||!witness||!size||size>sizeof(code)){snprintf(why,why_size,"no code to check");return HD2_CODE_REFUSED;}
    int callable=h->callable(h->context,address)==1,readable=h->read(h->context,address,code,size)==1;
    if(callable&&readable){
        for(size_t i=0;i<size;i++)if(code[i]!=witness[i]){
            code_page(h,address,page,sizeof(page));
            snprintf(why,why_size,"code differs from the witness at byte %u%s",(unsigned)i,page);return HD2_CODE_REFUSED;
        }
        return HD2_CODE_MATCH;
    }
    code_page(h,address,page,sizeof(page));
    if(!callable&&!readable){snprintf(why,why_size,"not resident (neither callable nor readable: not decrypted yet)%s",page);return HD2_CODE_NOT_RESIDENT;}
    snprintf(why,why_size,callable?"executable but unreadable%s":"readable but not executable%s",page);
    return HD2_CODE_REFUSED;
}
