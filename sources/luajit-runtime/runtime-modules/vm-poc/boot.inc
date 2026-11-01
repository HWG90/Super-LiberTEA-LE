/* Included after lifecycle.inc. Native entry failures never resume boot. */
static HD2Environment *boot_enter(void *address,unsigned stage){
    HD2Environment *e=frame_find(address);
    if(!e||!e->native_owned||!e->boot_bound||e->boot_stage!=stage||e->busy||e->frame_active||e->shutdown_stage||native_factory_busy)
        native_fatal(address,"boot","native boot stage missing, out of order or recursive");
    e->frame_active=1;return e;
}
static void boot_leave(HD2Environment *e,int ok,const char *operation){
    if(ok!=1)native_fatal(e->frame_native,operation,e->error[0]?e->error:"native boot adapter failed");
    e->boot_stage++;e->frame_active=0;
}
static void boot_register(void *address,unsigned stage,const uintptr_t *args,size_t count){
    HD2Environment *e=boot_enter(address,stage);e->error[0]=0;
    int ok=e->boot_callbacks.register_stage(e->boot_callbacks.context,e,stage,args,count);
    boot_leave(e,ok,"boot-register");
}
static void HD2_FRAME_ABI boot_core(void *p,uintptr_t a,uintptr_t b){uintptr_t args[]={a,b};boot_register(p,0,args,2);}
static void HD2_FRAME_ABI boot_steam(void *p,uintptr_t a){boot_register(p,1,&a,1);}
static void HD2_FRAME_ABI boot_leaderboard(void *p,uintptr_t a){boot_register(p,2,&a,1);}
static void HD2_FRAME_ABI boot_achievements(void *p,uintptr_t a){boot_register(p,3,&a,1);}
static void HD2_FRAME_ABI boot_cloud(void *p){boot_register(p,4,NULL,0);}
static void HD2_FRAME_ABI boot_network(void *p,uintptr_t a,uintptr_t b,uintptr_t c,uintptr_t d,unsigned char flag){
    uintptr_t args[]={a,b,c,d,flag};boot_register(p,5,args,5);
}
static void HD2_FRAME_ABI boot_friends(void *p,uintptr_t a){boot_register(p,6,&a,1);}
static void HD2_FRAME_ABI boot_voip(void *p,uintptr_t a,uintptr_t b){uintptr_t args[]={a,b};boot_register(p,7,args,2);}
static void boot_operation(void *address,unsigned stage,int operation,uintptr_t data,const char *name){
    HD2Environment *e=boot_enter(address,stage);
    if(!enter(e))native_fatal(address,name,"native boot entry refused");
    e->operation=operation;e->boot_data=data;
    int ok=dispatch(e);e->boot_data=0;boot_leave(e,ok,name);
}
static void HD2_FRAME_ABI boot_configure(void *address,uintptr_t options){boot_operation(address,8,6,options,"boot-config");}
static void HD2_FRAME_ABI boot_start(void *address,uintptr_t name){boot_operation(address,9,7,name,"boot-start");}
int hd2env_bind_boot(HD2Environment *e,const HD2BootCallbacks *callbacks){
    if(!e||!same_thread(e->thread)||e->busy||e->frame_active||e->boot_bound||e->frame_native||e->native_owned||
       !callbacks||!callbacks->register_stage||!callbacks->read_native)return 0;
    e->boot_callbacks=*callbacks;e->boot_bound=1;e->boot_stage=0;return 1;
}
int hd2env_boot_complete(const HD2Environment *e){return e&&same_thread(e->thread)&&e->boot_bound&&e->boot_stage==10;}
int hd2env_get_boot_targets(HD2BootTargets *out){
    if(!out)return 0;
    HD2BootTargets t={{(uintptr_t)boot_core,(uintptr_t)boot_steam,(uintptr_t)boot_leaderboard,
        (uintptr_t)boot_achievements,(uintptr_t)boot_cloud,(uintptr_t)boot_network,
        (uintptr_t)boot_friends,(uintptr_t)boot_voip},(uintptr_t)boot_configure,(uintptr_t)boot_start};
    *out=t;return 1;
}
