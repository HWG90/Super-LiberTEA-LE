#include "native_voip.h"
#include "voip_witnesses.h"
#include <string.h>
static uint32_t word(const unsigned char *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
int hd2env_probe_voip_views_host(const HD2VoipHost *h){
    if(!h||!h->image_base||h->image_base>UINTPTR_MAX-0x29fe000||!h->read||!h->write||!h->callable)return 0;
    unsigned char header[0x1200],buffer[8192];
    if(h->read(h->context,h->image_base,header,sizeof(header))!=1||header[0]!='M'||header[1]!='Z')return 0;
    uint32_t nt=word(header+0x3c);
    if(nt>0x1000||memcmp(header+nt,"PE\0\0",4)||header[nt+4]!=0x64||header[nt+5]!=0x86||
       word(header+nt+8)!=0x6af2d5e6||header[nt+24]!=0x0b||header[nt+25]!=2||word(header+nt+24+56)!=0x29fe000)return 0;
    for(size_t i=0;i<sizeof(voip_regions)/sizeof(*voip_regions);i++){
        if(voip_regions[i].size>sizeof(buffer)||h->read(h->context,h->image_base+voip_regions[i].rva,buffer,voip_regions[i].size)!=1||
           memcmp(buffer,voip_regions[i].bytes,voip_regions[i].size))return 0;
    }
    return 1;
}
