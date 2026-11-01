/* Included after frames.inc; all native lifecycle ownership is thread-local. */
static _Thread_local HD2NativeFactory native_factory;
static _Thread_local size_t native_states;
static _Thread_local unsigned native_factory_busy;
static _Noreturn void native_fatal(void *address,const char *operation,const char *message){
    native_factory_busy++;
    if(native_factory.fatal)native_factory.fatal(native_factory.context,address,operation,message);
    abort();
}
static void HD2_FRAME_ABI native_construct_entry(void *address,void *resources){
    if(!address||!native_factory.create||native_factory_busy||frame_find(address))
        native_fatal(address,"construct","native factory unavailable, recursive or address already bound");
    native_factory_busy++;
    HD2FrameCallbacks frames={0};char error[2048]={0};
    HD2Environment *e=native_factory.create(native_factory.context,address,resources,&frames,error,sizeof(error));
    error[sizeof(error)-1]=0;
    if(!e)native_fatal(address,"construct",error[0]?error:"native factory did not create a state");
    /* A returned environment transfers ownership. Never destroy an invalid
     * foreign-thread or already-bound return; those violate the host contract. */
    if(!same_thread(e->thread)||e->busy||e->frame_active||e->frame_native||e->native_owned)
        native_fatal(address,"construct","factory returned an environment it cannot transfer");
    HD2FrameTargets ignored;
    if(!hd2env_bind_frames(e,address,&frames,&ignored)){
        hd2env_destroy(e);
        if(native_factory.closed)native_factory.closed(native_factory.context,address);
        native_fatal(address,"construct","factory did not provide a valid frame policy and reporter");
    }
    e->native_owned=1;e->native_factory=native_factory;native_states++;
    native_factory_busy--;
}
static void HD2_FRAME_ABI native_close_entry(void *address){
    HD2Environment *e=frame_find(address);
    if(!e||!e->native_owned||e->busy||e->frame_active||e->shutdown_stage==1||e->shutdown_stage==2||native_factory_busy)
        native_fatal(address,"close","native close requires an idle owned environment on its creating thread");
    if(!hd2env_destroy(e))native_fatal(address,"close","native environment could not close");
}
int hd2env_set_native_factory(const HD2NativeFactory *factory,HD2LifecycleTargets *out){
    if(native_states||native_factory_busy||!factory||!factory->create||!factory->fatal||!out)return 0;
    native_factory=*factory;
    HD2LifecycleTargets targets={(uintptr_t)native_construct_entry,(uintptr_t)native_close_entry,
        {(uintptr_t)frame_collect_entry,(uintptr_t)frame_update_entry,(uintptr_t)frame_render_entry}};
    *out=targets;return 1;
}
int hd2env_clear_native_factory(void){
    if(native_states||native_factory_busy)return 0;
    memset(&native_factory,0,sizeof(native_factory));return 1;
}
size_t hd2env_native_state_count(void){return native_states;}
static void native_closed(const HD2NativeFactory *factory,void *address){
    native_states--;
    if(factory->closed)factory->closed(factory->context,address);
}
