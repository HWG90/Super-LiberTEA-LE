/* Only this private adapter reads the replacement VM's own GC estimate. No
 * game/PUC pointer crosses into LuaJIT and no hard-coded VM offset is used. */
static int gc_sample(void *p,int32_t *total,int32_t *estimate){
    HD2Environment *e=p;
#ifdef HD2ENV_PUC_REFERENCE
    uint64_t bytes=G(e->L)->totalbytes,live=G(e->L)->estimate;
#else
    uint64_t bytes=G(e->L)->gc.total,live=G(e->L)->gc.estimate;
#endif
    uint64_t public_bytes=(uint64_t)lua_gc(e->L,LUA_GCCOUNT,0)*1024+(unsigned)lua_gc(e->L,LUA_GCCOUNTB,0);
    if(bytes!=public_bytes||(bytes>>10)>INT32_MAX||(live>>10)>INT32_MAX)return 0;
    *total=(int32_t)(bytes>>10);*estimate=(int32_t)(live>>10);return 1;
}
static int gc_full(void *p){lua_gc(((HD2Environment *)p)->L,LUA_GCCOLLECT,0);return 1;}
static int gc_step(void *p){return lua_gc(((HD2Environment *)p)->L,LUA_GCSTEP,0);}
static int gc_frequency(void *p,int64_t *out){
    (void)p;
#ifdef _WIN32
    LARGE_INTEGER v;if(!QueryPerformanceFrequency(&v))return 0;*out=v.QuadPart;
#else
    *out=1000000000;
#endif
    return 1;
}
static int gc_counter(void *p,int64_t *out){
    (void)p;
#ifdef _WIN32
    LARGE_INTEGER v;if(!QueryPerformanceCounter(&v))return 0;*out=v.QuadPart;
#else
    struct timespec v;if(clock_gettime(CLOCK_MONOTONIC,&v)||v.tv_sec<0||v.tv_sec>INT64_MAX/1000000000)return 0;
    *out=(int64_t)v.tv_sec*1000000000+v.tv_nsec;
#endif
    return 1;
}
static int gc_operation(lua_State *L,HD2Environment *e){
    lua_gc(L,LUA_GCSTOP,0);
    HD2GCDriver driver={e,gc_sample,gc_full,gc_step,e->gc_clock};
    if(!driver.clock.counter){HD2GCClock clock={NULL,gc_frequency,gc_counter};driver.clock=clock;}
    if(!hd2gc_schedule(&e->gc_settings,&e->gc_history,&driver,&e->gc_report))
        return luaL_error(L,"native GC scheduler or clock failed");
    return 0;
}
int hd2env_configure_gc(HD2Environment *e,const HD2GCSettings *settings,const HD2GCClock *clock){
    HD2GCSettings s=settings?*settings:hd2gc_defaults();
    if(!e||!same_thread(e->thread)||e->busy||e->frame_active||e->shutdown_stage||!gc_settings_valid(&s)||
       (clock&&(!clock->frequency||!clock->counter)))return 0;
    e->gc_settings=s;e->gc_history=hd2gc_history();memset(&e->gc_report,0,sizeof(e->gc_report));
    if(clock)e->gc_clock=*clock;else memset(&e->gc_clock,0,sizeof(e->gc_clock));return 1;
}
int hd2env_collect_frame(HD2Environment *e,HD2GCReport *out){
    if(!e||!same_thread(e->thread)||e->shutdown_stage||(e->boot_bound&&e->boot_stage!=10)||!enter(e))return 0;
    lua_gc(e->L,LUA_GCSTOP,0);e->operation=12;int ok=dispatch(e);
    /* lua_gc(STOP) cannot allocate/throw; run after the protected boundary so
     * PUC finalizer errors cannot accidentally leave automatic GC enabled. */
    lua_gc(e->L,LUA_GCSTOP,0);if(out)*out=e->gc_report;return ok;
}
int hd2env_gc_report(const HD2Environment *e,HD2GCReport *out){
    if(!e||!out||!same_thread(e->thread)||e->busy)return 0;
    *out=e->gc_report;return 1;
}
