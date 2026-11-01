#include "native_vectors.h"
#include "vector2_witnesses.h"
#include "vector3_witnesses.h"
#include "vector3box_witnesses.h"
#include "vector4_witnesses.h"
#include "quaternion_witnesses.h"
#include "matrix4x4_witnesses.h"
#include <string.h>
#include <stdlib.h>
static int vector_read(const HD2VectorHost *h,uintptr_t p,void *out,size_t n) {
    return p&&n<=UINTPTR_MAX-p&&h->read(h->context,p,out,n)==1;
}
static int vector_witness(const HD2VectorHost *h,unsigned rva,const unsigned char *bytes,size_t size) {
    unsigned char actual[0x5000];
    return size<=sizeof(actual)&&vector_read(h,h->image_base+rva,actual,size)&&!memcmp(actual,bytes,size);
}
/* Required prefixes must match. Optional ones (callbacks the port replaces, on
 * pages the game unpacks on first execution) may be unreadable, but must match
 * whenever they can be read. */
static int vector_witness_entry(const HD2VectorHost *h,unsigned rva,int required,const unsigned char *bytes) {
    unsigned char actual[32];
    if(!required&&!vector_read(h,h->image_base+rva,actual,32))return 1;
    return vector_witness(h,rva,bytes,32);
}
static uint32_t vector_word(const unsigned char *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static int temp_allocator_valid(const HD2VectorHost *,uintptr_t);
int hd2env_probe_vector2_host(const HD2VectorHost *h) {
    if(!h||!h->image_base||h->image_base>UINTPTR_MAX-0x29fe000||!h->read||!h->write||!h->callable)return 0;
    unsigned char header[0x1200];
    if(!vector_read(h,h->image_base,header,sizeof(header))||memcmp(header,"MZ",2))return 0;
    uint32_t nt=vector_word(header+0x3c);
    if(nt>0x1000||memcmp(header+nt,"PE\0\0",4)||header[nt+4]!=0x64||header[nt+5]!=0x86||
       vector_word(header+nt+8)!=0x6ae0964a||header[nt+24]!=0x0b||header[nt+25]!=2||vector_word(header+nt+24+56)!=0x29fe000)return 0;
    return vector_witness(h,0x9f900,vector_pool_witness,sizeof(vector_pool_witness))&&
           vector_witness(h,0x704e0,vector_format_witness,sizeof(vector_format_witness))&&
           vector_witness(h,0x419fb0,vector2_witness,sizeof(vector2_witness))&&
           vector_witness(h,0x48f290,temp_count_witness,sizeof(temp_count_witness))&&
           vector_witness(h,0x48f3a0,temp_set_witness,sizeof(temp_set_witness))&&
           vector_witness(h,0x4f03a0,temp_cleanup_witness,sizeof(temp_cleanup_witness))&&
           vector_witness(h,0x4f06d0,temp_overflow_clear_witness,sizeof(temp_overflow_clear_witness));
}
int hd2vector2_pool_valid(const HD2VectorHost *h,uintptr_t e) {
    if(!h||!e||e>UINTPTR_MAX-0x100148)return 0;
    uintptr_t start=0,cursor=0;const uintptr_t first=e+0x118,last=e+0x100118;
    return vector_read(h,e+0x100118,&start,8)&&vector_read(h,e+0x100120,&cursor,8)&&
           start>=first&&start<=last&&cursor>=first&&cursor<=last;
}
static uintptr_t vector_allocate(const HD2VectorHost *h,uintptr_t e,uint32_t size) {
    uintptr_t fn=h->image_base+0x9f900;
    if(!hd2vector2_pool_valid(h,e)||h->callable(h->context,fn)!=1||
       !vector_witness(h,0x9f900,vector_pool_witness,sizeof(vector_pool_witness)))return 0;
    uintptr_t start,cursor;
    if(!vector_read(h,e+0x100118,&start,8)||!vector_read(h,e+0x100120,&cursor,8))return 0;
    if(cursor+size>e+0x100118)cursor=e+0x118;
    uint32_t used=(uint32_t)(cursor-start)+(cursor<start?0x100000u:0);
    if(used+size>=0x100000u&&!temp_allocator_valid(h,e))return 0;
    return ((uintptr_t(HD2_NATIVE_ABI *)(void *,uint32_t))fn)((void *)e,size);
}
uintptr_t hd2vector2_allocate(const HD2VectorHost *h,uintptr_t e){return vector_allocate(h,e,12);}
uintptr_t hd2vector3_allocate(const HD2VectorHost *h,uintptr_t e){return vector_allocate(h,e,16);}
uintptr_t hd2vector4_allocate(const HD2VectorHost *h,uintptr_t e){return vector_allocate(h,e,20);}
uintptr_t hd2matrix4x4_allocate(const HD2VectorHost *h,uintptr_t e){return vector_allocate(h,e,68);}
int hd2env_probe_vector3_host(const HD2VectorHost *h) {
    return hd2env_probe_vector2_host(h)&&
        vector_witness(h,0x41f400,vector3_a_witness,sizeof(vector3_a_witness))&&
        vector_witness(h,0x422740,vector3_b_witness,sizeof(vector3_b_witness));
}
int hd2env_probe_vector3box_host(const HD2VectorHost *h) {
    return hd2env_probe_vector3_host(h)&&
        vector_witness(h,0x4263c0,vector3box_witness,sizeof(vector3box_witness));
}
int hd2env_probe_vector4_host(const HD2VectorHost *h) {
    return hd2env_probe_vector3_host(h)&&
        vector_witness(h,0x4270a0,vector4_a_witness,sizeof(vector4_a_witness))&&
        vector_witness(h,0x429f40,vector4_b_witness,sizeof(vector4_b_witness));
}
int hd2vector2_format(const HD2VectorHost *h,char *out,float x,float y) {
    uintptr_t fn=h->image_base+0x704e0;
    if(h->callable(h->context,fn)!=1||!vector_witness(h,0x704e0,vector_format_witness,sizeof(vector_format_witness)))return 0;
    /* The original uses this formatter with %.9g for each float. Preserve its
     * exponent/NaN spelling and process locale rather than the host C runtime. */
    int count=((int(HD2_NATIVE_ABI *)(char *,const char *,...))fn)(out,"(%.9g, %.9g)",(double)x,(double)y);
    return count>=0&&count<128;
}
int hd2vector3_format(const HD2VectorHost *h,char *out,float x,float y,float z) {
    uintptr_t fn=h->image_base+0x704e0;
    if(h->callable(h->context,fn)!=1||!vector_witness(h,0x704e0,vector_format_witness,sizeof(vector_format_witness)))return 0;
    int count=((int(HD2_NATIVE_ABI *)(char *,const char *,...))fn)(out,"(%.9g, %.9g, %.9g)",(double)x,(double)y,(double)z);
    return count>=0&&count<128;
}
int hd2vector_format_float(const HD2VectorHost *h,char *out,float x) {
    uintptr_t fn=h->image_base+0x704e0;
    if(h->callable(h->context,fn)!=1||!vector_witness(h,0x704e0,vector_format_witness,sizeof(vector_format_witness)))return 0;
    int count=((int(HD2_NATIVE_ABI *)(char *,const char *,...))fn)(out,"%.9g",(double)x);
    return count>=0&&count<64;
}
int hd2vector4_format(const HD2VectorHost *h,char *out,float x,float y,float z,float w) {
    uintptr_t fn=h->image_base+0x704e0;
    if(h->callable(h->context,fn)!=1||!vector_witness(h,0x704e0,vector_format_witness,sizeof(vector_format_witness)))return 0;
    int count=((int(HD2_NATIVE_ABI *)(char *,const char *,...))fn)(out,"(%.9g, %.9g, %.9g, %.9g)",(double)x,(double)y,(double)z,(double)w);
    return count>=0&&count<128;
}
typedef struct {
    uintptr_t start,cursor;
    uint32_t pages,capacity;
    uintptr_t page_array,allocator,overflow_cursor;
} HD2TempPool;
_Static_assert(sizeof(HD2TempPool)==48,"temporary pool metadata layout");
static int temp_pool(const HD2VectorHost *h,uintptr_t e,HD2TempPool *p) {
    if(!h||!h->read||!h->write||!e||e>UINTPTR_MAX-0x100148||
       !vector_read(h,e+0x100118,p,sizeof(*p)))return 0;
    uintptr_t first=e+0x118,last=e+0x100118;
    return p->start>=first&&p->start<=last&&p->cursor>=first&&p->cursor<=last&&
           !(p->start&3)&&!(p->cursor&3)&&p->pages<=p->capacity;
}
static uint32_t temp_used(const HD2TempPool *p) {
    return (uint32_t)(p->cursor-p->start)+(p->cursor<p->start?0x100000u:0);
}
static int temp_allocator_valid(const HD2VectorHost *h,uintptr_t e) {
    uintptr_t vt,allocate,release,size,underlying,underlying_vt,target;
    if(!h->callable||!vector_read(h,e+8,&vt,8)||vt!=h->image_base+0x172b360||
       !vector_read(h,vt+0x30,&allocate,8)||allocate!=h->image_base+0x602110||
       !vector_read(h,vt+0x40,&release,8)||release!=h->image_base+0x6021d0||
       !vector_read(h,vt+8,&size,8)||size!=h->image_base+0x4f9d40||
       !vector_witness(h,0x602110,temp_allocator_witness,sizeof(temp_allocator_witness))||
       !vector_witness(h,0x6021d0,temp_deallocator_witness,sizeof(temp_deallocator_witness))||
       !vector_witness(h,0x4f9d40,temp_size_witness,sizeof(temp_size_witness))||
       !vector_read(h,e+0x28,&underlying,8)||!underlying||
       !vector_read(h,underlying,&underlying_vt,8)||!underlying_vt||underlying_vt>UINTPTR_MAX-0x48)return 0;
    const unsigned slots[]={8,0x30,0x40};
    for(unsigned i=0;i<3;i++)if(!vector_read(h,underlying_vt+slots[i],&target,8)||h->callable(h->context,target)!=1)return 0;
    return h->callable(h->context,allocate)==1&&h->callable(h->context,release)==1&&h->callable(h->context,size)==1;
}
static int temp_pointer_compare(const void *a,const void *b) {
    uintptr_t x=*(const uintptr_t *)a,y=*(const uintptr_t *)b;return x<y?-1:x>y;
}
static int temp_overflow_valid(const HD2VectorHost *h,uintptr_t e,const HD2TempPool *p) {
    if(!p->pages)return 1;
    size_t size=(size_t)p->pages*sizeof(uintptr_t);
    if(!p->page_array||size>UINTPTR_MAX-p->page_array||p->allocator!=e+8||
       !temp_allocator_valid(h,e)||h->callable(h->context,h->image_base+0x4f06d0)!=1||
       !vector_witness(h,0x4f06d0,temp_overflow_clear_witness,sizeof(temp_overflow_clear_witness)))return 0;
    uintptr_t *pages=malloc(size);if(!pages)return 0;
    int ok=0;unsigned char byte;
    if(!vector_read(h,p->page_array,pages,size))goto done;
    uintptr_t last=pages[p->pages-1];
    if(!last||last>UINTPTR_MAX-0x100000||p->overflow_cursor<last||p->overflow_cursor>last+0x100000)goto done;
    qsort(pages,p->pages,sizeof(*pages),temp_pointer_compare);
    for(uint32_t i=0;i<p->pages;i++) {
        uintptr_t page=pages[i];
        if(!page||page>UINTPTR_MAX-0x100000||(page&7)||
           (i&&page-pages[i-1]<0x100000)||
           (page<e+0x100148&&page+0x100000>e)||
           (page<p->page_array+size&&page+0x100000>p->page_array)||
           !vector_read(h,page,&byte,1)||!vector_read(h,page+0xfffff,&byte,1))goto done;
    }
    ok=1;
done:
    free(pages);return ok;
}
int hd2vector_temp_count(const HD2VectorHost *h,uintptr_t e,uint32_t *out) {
    HD2TempPool p;
    if(!out||!temp_pool(h,e,&p))return 0;
    *out=temp_used(&p);return 1;
}
int hd2vector_temp_restore(const HD2VectorHost *h,uintptr_t e,uint32_t count) {
    HD2TempPool p;
    if(!temp_pool(h,e,&p)||count>temp_used(&p)||count>=0x100000u||(count&3))return 0;
    uintptr_t cursor=p.start+count;
    if(cursor>=e+0x100118)cursor-=0x100000;
    return h->write(h->context,e+0x100120,&cursor,8)==1;
}
int hd2vector_temp_clear(const HD2VectorHost *h,uintptr_t e) {
    HD2TempPool p,check;
    if(!temp_pool(h,e,&p)||!temp_overflow_valid(h,e,&p)||
       !vector_witness(h,0x4f03a0,temp_cleanup_witness,sizeof(temp_cleanup_witness)))return 0;
    uint32_t used=temp_used(&p);
    if(used>=0x100000)return 0;
    size_t first=(size_t)(e+0x100118-p.start);
    if(first>used)first=used;
    unsigned char *bytes=used?malloc(used):NULL;
    if(used&&!bytes)return 0;
    int ok=0;
    if((first&&!vector_read(h,p.start,bytes,first))||
       (used>first&&!vector_read(h,e+0x118,bytes+first,used-first)))goto done;
    /* Validate and invalidate a private snapshot first, so an unknown tag or
     * truncated object never causes a partial mutation or an endless walk. */
    for(size_t at=0;at<used;) {
        size_t boundary=at<first?first:used,span=boundary-at,stride=0;
        if(span<4)goto done;
        uint32_t tag=vector_word(bytes+at),poison=0x7f800000;
        if(tag==0x29d243c5) {
            if(at>=first)goto done;
            at=first;continue;
        }
        switch(tag) {
            case 0x2203c134:stride=8;poison=UINT32_MAX;break;
            case 0x02b4dab5:stride=16;break;
            case 0x58235806:stride=20;break;
            case 0x7796c581:stride=12;break;
            case 0x6f6f4d64:stride=16;break;
            case 0x7fd2e074:stride=68;break;
            default:goto done;
        }
        if(stride>span)goto done;
        uint32_t expired=tag+1;memcpy(bytes+at,&expired,4);
        if(tag==0x6f6f4d64){uint64_t dead=UINT64_MAX;memcpy(bytes+at+8,&dead,8);}
        else memcpy(bytes+at+4,&poison,4);
        at+=stride;
    }
    if(!temp_pool(h,e,&check)||memcmp(&p,&check,sizeof(p)))goto done;
    if(p.pages) {
        /* This helper owns only native pages and never accesses a Lua state.
         * Retain the pointer array/capacity, as the native environment does. */
        ((void(HD2_NATIVE_ABI *)(void *))(h->image_base+0x4f06d0))((void *)e);
        if(!temp_pool(h,e,&check)||check.pages||check.overflow_cursor||
           check.start!=p.start||check.cursor!=p.cursor||check.capacity!=p.capacity||
           check.page_array!=p.page_array||check.allocator!=p.allocator)goto done;
    }
    if((first&&h->write(h->context,p.start,bytes,first)!=1)||
       (used>first&&h->write(h->context,e+0x118,bytes+first,used-first)!=1))goto done;
    /* With no pages, the native helper's only effect is resetting its cursor.
     * Advance inline start, preserving the allocator's current position. */
    uintptr_t zero=0;
    if(h->write(h->context,e+0x100140,&zero,8)!=1||
       h->write(h->context,e+0x100118,&p.cursor,8)!=1)goto done;
    ok=1;
done:
    free(bytes);return ok;
}
/* Pure game math helpers (CRT atan2f/asinf, Euler and basis conversion). They
 * read/write only the float buffers passed here and never touch a Lua state.
 * Calling them keeps the replacement bit-identical with the original callbacks. */
static int quaternion_helper(const HD2VectorHost *h,unsigned rva) {
    for(size_t i=0;i<sizeof(quaternion_witnesses)/sizeof(*quaternion_witnesses);i++)
        if(quaternion_witnesses[i].rva==rva)
            return h->callable(h->context,h->image_base+rva)==1&&vector_witness(h,rva,quaternion_witnesses[i].bytes,32);
    return 0;
}
int hd2quaternion_atan2f(const HD2VectorHost *h,float y,float x,float *out) {
    if(!quaternion_helper(h,HD2_QUATERNION_ATAN2F))return 0;
    *out=((float(HD2_NATIVE_ABI *)(float,float))(h->image_base+HD2_QUATERNION_ATAN2F))(y,x);return 1;
}
int hd2quaternion_asinf(const HD2VectorHost *h,float x,float *out) {
    if(!quaternion_helper(h,HD2_QUATERNION_ASINF))return 0;
    *out=((float(HD2_NATIVE_ABI *)(float))(h->image_base+HD2_QUATERNION_ASINF))(x);return 1;
}
int hd2quaternion_acosf(const HD2VectorHost *h,float x,float *out) {
    if(!quaternion_helper(h,HD2_QUATERNION_ACOSF))return 0;
    *out=((float(HD2_NATIVE_ABI *)(float))(h->image_base+HD2_QUATERNION_ACOSF))(x);return 1;
}
int hd2quaternion_sinf(const HD2VectorHost *h,float x,float *out) {
    if(!quaternion_helper(h,HD2_QUATERNION_SINF))return 0;
    *out=((float(HD2_NATIVE_ABI *)(float))(h->image_base+HD2_QUATERNION_SINF))(x);return 1;
}
int hd2quaternion_from_euler(const HD2VectorHost *h,const float degrees[3],float out[4]) {
    if(!quaternion_helper(h,HD2_QUATERNION_QUATERNION_FROM_EULER_DEGREES))return 0;
    _Alignas(16) float in[4]={degrees[0],degrees[1],degrees[2],0};_Alignas(16) float q[4];
    ((void *(HD2_NATIVE_ABI *)(float *,const float *))(h->image_base+HD2_QUATERNION_QUATERNION_FROM_EULER_DEGREES))(q,in);
    memcpy(out,q,sizeof(q));return 1;
}
int hd2quaternion_from_basis(const HD2VectorHost *h,const float matrix[16],float out[4]) {
    if(!quaternion_helper(h,HD2_QUATERNION_QUATERNION_FROM_BASIS))return 0;
    _Alignas(16) float in[16];_Alignas(16) float q[4];memcpy(in,matrix,sizeof(in));
    ((void *(HD2_NATIVE_ABI *)(float *,const float *))(h->image_base+HD2_QUATERNION_QUATERNION_FROM_BASIS))(q,in);
    memcpy(out,q,sizeof(q));return 1;
}
int hd2env_probe_quaternion_host(const HD2VectorHost *h) {
    if(!hd2env_probe_vector4_host(h))return 0;
    for(size_t i=0;i<sizeof(quaternion_witnesses)/sizeof(*quaternion_witnesses);i++)
        if(!vector_witness_entry(h,quaternion_witnesses[i].rva,quaternion_witnesses[i].required,quaternion_witnesses[i].bytes))return 0;
    return 1;
}
static int matrix4x4_helper(const HD2VectorHost *h,unsigned rva) {
    for(size_t i=0;i<sizeof(matrix4x4_witnesses)/sizeof(*matrix4x4_witnesses);i++)
        if(matrix4x4_witnesses[i].rva==rva)
            return h->callable(h->context,h->image_base+rva)==1&&vector_witness(h,rva,matrix4x4_witnesses[i].bytes,32);
    return 0;
}
int hd2env_probe_matrix4x4_host(const HD2VectorHost *h) {
    if(!hd2env_probe_quaternion_host(h))return 0;
    for(size_t i=0;i<sizeof(matrix4x4_witnesses)/sizeof(*matrix4x4_witnesses);i++)
        if(!vector_witness_entry(h,matrix4x4_witnesses[i].rva,matrix4x4_witnesses[i].required,matrix4x4_witnesses[i].bytes))return 0;
    return 1;
}
/* Pure game helpers on 16 row-major floats: general inverse, and rotation
 * extraction (scale removed) as a quaternion. Buffers only; no Lua state. */
int hd2matrix4x4_inverse(const HD2VectorHost *h,const float in[16],float out[16]) {
    if(!matrix4x4_helper(h,HD2_MATRIX4X4_MATRIX_INVERSE))return 0;
    _Alignas(16) float a[16],r[16];memcpy(a,in,sizeof(a));
    ((void *(HD2_NATIVE_ABI *)(float *,const float *))(h->image_base+HD2_MATRIX4X4_MATRIX_INVERSE))(r,a);
    memcpy(out,r,sizeof(r));return 1;
}
int hd2matrix4x4_rotation(const HD2VectorHost *h,const float in[16],float out[4]) {
    if(!matrix4x4_helper(h,HD2_MATRIX4X4_MATRIX_ROTATION))return 0;
    _Alignas(16) float a[16],q[4];memcpy(a,in,sizeof(a));
    ((void *(HD2_NATIVE_ABI *)(float *,const float *))(h->image_base+HD2_MATRIX4X4_MATRIX_ROTATION))(q,a);
    memcpy(out,q,sizeof(q));return 1;
}
