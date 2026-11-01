#include "native_puc.h"
#include "puc_witnesses.h"
#include <string.h>
_Static_assert(sizeof(HD2PucApi)==sizeof(puc_witnesses)/sizeof(puc_witnesses[0])*sizeof(void *),"HD2PucApi fields follow puc_witnesses");
static int puc_read(const HD2SteamHost *h,uintptr_t p,void *out,size_t n) {
    return p&&n<=UINTPTR_MAX-p&&h->read(h->context,p,out,n)==1;
}
static uint32_t puc_word(const unsigned char *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
int hd2puc_bind(HD2PucApi *api,const HD2SteamHost *h) {
    if(!api||!h||!h->image_base||h->image_base>UINTPTR_MAX-0x29fe000||!h->read||!h->callable)return 0;
    unsigned char header[0x400];
    if(!puc_read(h,h->image_base,header,sizeof(header))||memcmp(header,"MZ",2))return 0;
    uint32_t nt=puc_word(header+0x3c);
    if(nt>sizeof(header)-0x80||memcmp(header+nt,"PE\0\0",4)||puc_word(header+nt+8)!=0x6ae0964a||
       puc_word(header+nt+24+56)!=0x29fe000)return 0;
    void *entries[sizeof(puc_witnesses)/sizeof(puc_witnesses[0])];
    for(size_t i=0;i<sizeof(entries)/sizeof(entries[0]);i++) {
        uintptr_t at=h->image_base+puc_witnesses[i].rva;unsigned char actual[32];
        if(h->callable(h->context,at)!=1||!puc_read(h,at,actual,32)||memcmp(actual,puc_witnesses[i].bytes,32))return 0;
        entries[i]=(void *)at;
    }
    /* The engine's own LuaApi table must still publish the same core entries. */
    uintptr_t slot=0;
    if(!puc_read(h,h->image_base+HD2_PUC_LUAAPI_TABLE+13*8,&slot,8)||slot!=h->image_base+0x796a60)return 0;
    memcpy(api,entries,sizeof(entries));
    return 1;
}
