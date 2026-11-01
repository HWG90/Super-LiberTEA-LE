/* Included in environment.c: associations share state ownership/lifetime. */
#ifdef _WIN32
#define HD2_FRAME_ABI
#else
#define HD2_FRAME_ABI __attribute__((ms_abi))
#endif
static _Thread_local HD2Environment *frame_environments;
static _Thread_local uint64_t frame_faults;
static void frame_fault(void){if(frame_faults!=UINT64_MAX)frame_faults++;}
static HD2Environment *frame_find(void *address){
    for(HD2Environment *e=frame_environments;e;e=e->frame_next)
        if(e->frame_native==address)return e;
    return NULL;
}
static void frame_remove(HD2Environment *e){
    HD2Environment **p=&frame_environments;
    while(*p&&*p!=e)p=&(*p)->frame_next;
    if(*p)*p=e->frame_next;
    e->frame_next=NULL;e->frame_native=NULL;
    memset(&e->frame_callbacks,0,sizeof(e->frame_callbacks));
}
static void frame_dispatch(void *address,int kind,float dt){
    HD2Environment *e=frame_find(address);
    if(!e||e->busy||e->frame_active||e->shutdown_stage||(e->boot_bound&&e->boot_stage!=10)){frame_fault();return;}
    e->frame_active=1;
    const char *name=kind==0?"gc":kind==1?"update":"render";
    e->error[0]=0;
    int ok;
    if(kind!=0&&e->vector2_ready&&!hd2vector_temp_clear(&e->vector_host,e->vector_environment)) {
        snprintf(e->error,sizeof(e->error),"native temporary pool cleanup refused (invalid ring, overflow or allocator)");
        ok=0;
    } else ok=kind==0?(e->frame_callbacks.collect?e->frame_callbacks.collect(e->frame_callbacks.context,e):hd2env_collect_frame(e,NULL)):
        hd2env_call(e,name,kind==1,(double)dt);
    if(ok!=1){
        /* Reporters can call the public core; preserve diagnostics across that
         * reentry and prevent destroy/unbind until the callback returns. */
        char message[sizeof(e->error)];
        snprintf(message,sizeof(message),"%s",e->error[0]?e->error:"native frame operation failed");
        e->frame_callbacks.report_error(e->frame_callbacks.context,e,name,message);
        snprintf(e->error,sizeof(e->error),"%s",message);
    }
    e->frame_active=0;
}
static void HD2_FRAME_ABI frame_collect_entry(void *address){frame_dispatch(address,0,0);}
static void HD2_FRAME_ABI frame_update_entry(void *address,float dt){frame_dispatch(address,1,dt);}
static void HD2_FRAME_ABI frame_render_entry(void *address){frame_dispatch(address,2,0);}
static void HD2_FRAME_ABI native_gc_entry(void *wrapper){
    for(HD2Environment *e=frame_environments;e;e=e->frame_next){
        uintptr_t address=(uintptr_t)e->frame_native;
        if(address<=UINTPTR_MAX-0x100148&&address+0x100148==(uintptr_t)wrapper){frame_dispatch(e->frame_native,0,0);return;}
    }
    frame_fault();
}
uintptr_t hd2env_gc_target(void){return (uintptr_t)native_gc_entry;}
int hd2env_bind_frames(HD2Environment *e,void *address,const HD2FrameCallbacks *callbacks,HD2FrameTargets *out){
    if(!e||!same_thread(e->thread)||e->busy||e->frame_active||e->frame_native||!address||
       !callbacks||!callbacks->report_error||!out||frame_find(address)||
       (e->vector2_ready&&e->vector_environment!=(uintptr_t)address))return 0;
    e->frame_native=address;e->frame_callbacks=*callbacks;e->frame_next=frame_environments;
    frame_environments=e;
    HD2FrameTargets targets={(uintptr_t)frame_collect_entry,(uintptr_t)frame_update_entry,(uintptr_t)frame_render_entry};
    *out=targets;return 1;
}
int hd2env_unbind_frames(HD2Environment *e){
    if(!e||!same_thread(e->thread)||e->busy||e->frame_active||e->native_owned)return 0;
    frame_remove(e);return 1;
}
uint64_t hd2env_frame_fault_count(void){return frame_faults;}
