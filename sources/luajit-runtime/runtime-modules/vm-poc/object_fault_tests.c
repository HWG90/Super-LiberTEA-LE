/* Allocation-failure harness. Includes the same core to intercept its C
 * allocations and replace the Lua allocator with public get/setallocf APIs.
 * Production DLL exports no fault switch. Normal suites test the shared DLL. */
#include <stdlib.h>
static struct { size_t calls,fail_at,failures;int enabled; } c_fault;
static void *fault_calloc(size_t count,size_t size) {
    if(c_fault.enabled&&++c_fault.calls>=c_fault.fail_at){c_fault.failures++;return NULL;}
    return calloc(count,size);
}
static void *fault_malloc(size_t size) {
    if(c_fault.enabled&&++c_fault.calls>=c_fault.fail_at){c_fault.failures++;return NULL;}
    return malloc(size);
}
#define calloc fault_calloc
#define malloc fault_malloc
#include "environment.c"
#undef calloc
#undef malloc

typedef struct {
    lua_Alloc original;
    void *context;
    size_t growths,fail_at,failures;
} FailingAllocator;
static void *failing_allocator(void *ud,void *ptr,size_t old_size,size_t size) {
    FailingAllocator *f=ud;
    if(size>old_size&&++f->growths>=f->fail_at){f->failures++;return NULL;}
    return f->original(f->context,ptr,old_size,size);
}
static void verify(int ok,const char *message,HD2Environment *e,size_t iteration) {
    if(!ok){fprintf(stderr,"allocation test %zu %s: %s\n",iteration,message,hd2env_error(e));exit(12);}
}
int main(void) {
    size_t faults=0,recovered=0,poisoned=0,successful=0;
    HD2Backend backend={0};char message[2048];
    for(size_t phase=0;phase<4;phase++)for(size_t at=1;at<=100;at++){
        HD2Environment *e=hd2env_create(NULL,0,&backend,message,sizeof(message));
        verify(e!=NULL,"create",NULL,at);
        HD2ObjectResults compiled={0},result={0};
        if(phase&1){
            const char *code="local t={};for i=1,32 do t[i]={value=string.rep('x',i*3)}end;return unpack(t)";
            verify(hd2env_object_compile(e,code,strlen(code),"@allocation-fault",&compiled)==1,"prepare chunk",e,at);
        }
        size_t before=hd2env_object_count(e);
        FailingAllocator f={0};f.original=lua_getallocf(e->L,&f.context);f.fail_at=phase<2?at:SIZE_MAX;
        c_fault.calls=0;c_fault.failures=0;c_fault.fail_at=at;c_fault.enabled=phase>=2;
        lua_setallocf(e->L,failing_allocator,&f);
        int status=(phase&1)?hd2env_object_call(e,compiled.values[0],NULL,0,&result):
            hd2env_object_compile(e,"return {}",9,"@first-owned-value",&result);
        c_fault.enabled=0;
        lua_setallocf(e->L,f.original,f.context);
        verify(hd2env_stack_depth(e)==0,"stack balance after allocation failure",e,at);
        if(f.failures||c_fault.failures)faults++;
        if(e->objects&&e->objects->poisoned){
            poisoned++;
            verify(status==-1,"poisoned store is a failure",e,at);
            HD2Object out={0};verify(hd2env_object_global(e,"_G",&out)==-1&&!out.identity,"poisoned store refuses reuse",e,at);
            free(result.values);free(compiled.values);
        }else{
            if(status==1)successful++;
            verify(hd2env_objects_free(e,&result)==1,"release successful/error results",e,at);
            verify(hd2env_object_count(e)==before,"no leaked owned values",e,at);
            HD2Object out={0};
            verify(hd2env_object_global(e,"_G",&out)==1,"recovery after allocator restored",e,at);
            verify(hd2env_object_release(e,&out)==1,"release recovery object",e,at);
            verify(hd2env_objects_free(e,&compiled)==1,"release prepared chunk",e,at);
            verify(hd2env_object_count(e)==0,"zero final ownership",e,at);
            if(f.failures||c_fault.failures)recovered++;
        }
        verify(hd2env_destroy(e)==1,"destroy",NULL,at);
    }
    printf("POC_OBJECT_FAULTS cases=400 faulted=%zu recovered=%zu refused_after_rollback_failure=%zu successful=%zu\n",
           faults,recovered,poisoned,successful);
    verify(faults>10&&recovered>10&&successful>0,"allocation faults actually exercised",NULL,0);
    return 0;
}
