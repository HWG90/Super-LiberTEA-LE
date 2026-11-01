/* Included after lifecycle and boot; the original native cleanup remains in
 * the game caller and eventually invokes native_close_entry. */
static HD2Environment *shutdown_enter(void *address,unsigned stage){
    HD2Environment *e=frame_find(address);
    if(!e||!e->native_owned||e->shutdown_stage!=stage||e->busy||e->frame_active||native_factory_busy||
       (e->boot_bound&&e->boot_stage!=10))
        native_fatal(address,"shutdown","native shutdown is missing, out of order or recursive");
    e->frame_active=1;return e;
}
static void HD2_FRAME_ABI shutdown_call_entry(void *address){
    HD2Environment *e=shutdown_enter(address,0);e->shutdown_stage=1;
    if(!hd2env_call(e,"shutdown",0,0)){
        char message[sizeof(e->error)];snprintf(message,sizeof(message),"%s",e->error);
        e->frame_callbacks.report_error(e->frame_callbacks.context,e,"shutdown",message);
        snprintf(e->error,sizeof(e->error),"%s",message);
    }
    e->shutdown_stage=2;e->frame_active=0;
}
static void HD2_FRAME_ABI shutdown_collect_entry(void *address){
    HD2Environment *e=shutdown_enter(address,2);
    if(!enter(e))native_fatal(address,"shutdown-gc","shutdown collection entry refused");
    e->operation=11;
    if(!dispatch(e))native_fatal(address,"shutdown-gc",e->error[0]?e->error:"shutdown collection failed");
    e->shutdown_stage=3;e->frame_active=0;
}
int hd2env_get_shutdown_targets(HD2ShutdownTargets *out){
    if(!out)return 0;
    HD2ShutdownTargets targets={(uintptr_t)shutdown_call_entry,(uintptr_t)shutdown_collect_entry};*out=targets;return 1;
}
int hd2env_native_shutdown_complete(const HD2Environment *e){
    return e&&same_thread(e->thread)&&e->shutdown_stage==3;
}
