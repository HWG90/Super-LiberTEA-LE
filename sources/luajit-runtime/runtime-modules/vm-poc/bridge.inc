/* Generic native bridge. Original engine callbacks inline PUC Lua 5.1 stack and
 * TValue layouts, so they run unchanged on a dedicated PUC host thread of the
 * game's own statically linked VM; LuaJIT owns every script. Values cross by
 * conversion, with identity preserved in both directions:
 *  - LuaJIT functions/userdata become cached PUC proxies; LuaJIT tables become
 *    PUC copies. Each maps back to the original LuaJIT object when it returns
 *    (Unit.set_data/get_data, callback objects, flow callbacks). A PUC guard
 *    userdata ties the LuaJIT reference to the proxy's PUC lifetime.
 *  - PUC functions/userdata become cached LuaJIT bridge closures/proxies that
 *    map back to the PUC original. PUC tables are copied, except mirrored
 *    module tables, which keep identity.
 * Validated ports (vectors, boxes, Quaternion, Matrix4x4) stay authoritative;
 * partial ports (Script, Steam, Friends, SteamVoip) gain only missing natives.
 * Collector callbacks only queue releases; they are applied at the next
 * crossing, never inside either collector. */
enum {R_OBJS=1,R_PROXYID,R_LJID,R_LJPROXY,R_THREAD,R_GUARDMT,R_SEEN};
enum {J_OBJS=1,J_PROXYID,J_PROXY,J_PUCID,J_UDMT,J_GUARDMT,J_SEEN};
typedef struct BridgeLink BridgeLink;
struct BridgeLink {HD2Environment *e;int guards;};
typedef struct {BridgeLink *link;int id;} PucGuard;    /* PUC object stands for LuaJIT J_OBJS[id] */
typedef struct {HD2Environment *e;int id;} LjGuard;     /* LuaJIT object stands for PUC R_OBJS[id] */
typedef struct {int depth,slots,mirror;char error[192];} BridgeCtx;
static char bridge_key;
static HD2PucApi bridge_api; /* one game image per process; used where only a PUC state is available */
#define BA (&e->puc)
static int bridge_call(lua_State *);

static int bridge_fail(BridgeCtx *c,const char *message,const char *detail) {
    if(!c->error[0])snprintf(c->error,sizeof(c->error),"%s%s",message,detail?detail:"");
    return 0;
}
static void bridge_queue(int **items,size_t *count,size_t *capacity,int id) {
    if(*count==*capacity){
        size_t n=*capacity?*capacity*2:64;int *grown=realloc(*items,n*sizeof(int));
        if(!grown)return; /* keeps the reference alive; never frees early */
        *items=grown;*capacity=n;
    }
    (*items)[(*count)++]=id;
}
/* PUC side helpers: absolute indices only. */
static void puc_root(HD2Environment *e,HD2PucState *P){BA->pushlightuserdata(P,e->bridge_link);BA->rawget(P,HD2_PUC_REGISTRYINDEX);}
static void puc_root_get(HD2Environment *e,HD2PucState *P,int k){puc_root(e,P);BA->rawgeti(P,-1,k);BA->remove(P,-2);}
static void puc_weak(HD2Environment *e,HD2PucState *P,const char *mode) {
    BA->createtable(P,0,0);BA->createtable(P,0,1);BA->pushlstring(P,mode,1);BA->setfield(P,-2,"__mode");BA->setmetatable(P,-2);
}
static int puc_number_at(HD2Environment *e,HD2PucState *P,int k,int idx) {
    puc_root_get(e,P,k);BA->pushvalue(P,idx);BA->rawget(P,-2);
    int id=BA->type(P,-1)==3?(int)BA->tonumber(P,-1):0;BA->settop(P,-3);return id;
}
static int puc_guard_id(HD2Environment *e,HD2PucState *P,int idx) {
    if(BA->type(P,idx)==7&&BA->getmetatable(P,idx)){
        puc_root_get(e,P,R_GUARDMT);int same=BA->rawequal(P,-1,-2);BA->settop(P,-3);
        if(same){PucGuard *g=BA->touserdata(P,idx);return g->link==e->bridge_link?g->id:0;}
    }
    puc_root_get(e,P,R_LJID);BA->pushvalue(P,idx);BA->rawget(P,-2);int id=0;
    if(BA->type(P,-1)==7){PucGuard *g=BA->touserdata(P,-1);if(g&&g->link==e->bridge_link)id=g->id;}
    BA->settop(P,-3);return id;
}
static void puc_set_id(HD2Environment *e,HD2PucState *P,int k,int id,int vidx) {
    puc_root_get(e,P,k);BA->pushvalue(P,vidx);BA->rawseti(P,-2,id);BA->settop(P,-2);
}
static void puc_set_key(HD2Environment *e,HD2PucState *P,int k,int kidx,int vidx) {
    puc_root_get(e,P,k);BA->pushvalue(P,kidx);BA->pushvalue(P,vidx);BA->rawset(P,-3);BA->settop(P,-2);
}
static int puc_new_object(HD2Environment *e,HD2PucState *P,int idx) {
    int id=++e->bridge_next_puc;BA->pushnumber(P,id);int n=BA->gettop(P);
    puc_set_id(e,P,R_OBJS,id,idx);puc_set_key(e,P,R_PROXYID,idx,n);BA->settop(P,-2);return id;
}
static int puc_push_object(HD2Environment *e,HD2PucState *P,int id,BridgeCtx *c) {
    puc_root_get(e,P,R_OBJS);BA->rawgeti(P,-1,id);BA->remove(P,-2);
    if(BA->type(P,-1)==0){BA->settop(P,-2);return bridge_fail(c,"native object was released",NULL);}
    return 1;
}
static int puc_new_guard(HD2Environment *e,HD2PucState *P,int lj_id) {
    PucGuard *g=BA->newuserdata(P,sizeof(*g));g->link=e->bridge_link;g->id=lj_id;e->bridge_link->guards++;
    puc_root_get(e,P,R_GUARDMT);BA->setmetatable(P,-2);return BA->gettop(P);
}
/* LuaJIT side helpers. */
static void lj_root_get(lua_State *L,int k){lua_pushlightuserdata(L,&bridge_key);lua_rawget(L,LUA_REGISTRYINDEX);lua_rawgeti(L,-1,k);lua_remove(L,-2);}
static void lj_weak(lua_State *L,const char *mode){lua_newtable(L);lua_createtable(L,0,1);lua_pushstring(L,mode);lua_setfield(L,-2,"__mode");lua_setmetatable(L,-2);}
static int lj_new_object(HD2Environment *e,lua_State *L,int idx,int cache) {
    int id=++e->bridge_next_lj;lj_root_get(L,J_OBJS);lua_pushvalue(L,idx);lua_rawseti(L,-2,id);lua_pop(L,1);
    if(cache){lj_root_get(L,J_PROXYID);lua_pushvalue(L,idx);lua_pushnumber(L,id);lua_rawset(L,-3);lua_pop(L,1);}
    return id;
}
static int lj_number_at(lua_State *L,int k,int idx) {
    lj_root_get(L,k);lua_pushvalue(L,idx);lua_rawget(L,-2);int id=lua_type(L,-1)==LUA_TNUMBER?(int)lua_tonumber(L,-1):0;lua_pop(L,2);return id;
}
static LjGuard *lj_new_guard(HD2Environment *e,lua_State *L,int puc_id,int meta) {
    LjGuard *g=lua_newuserdata(L,sizeof(*g));g->e=e;g->id=puc_id;lj_root_get(L,meta);lua_setmetatable(L,-2);return g;
}
/* The PUC id a LuaJIT value stands for, or 0. */
static int lj_target(lua_State *L,int idx) {
    int type=lua_type(L,idx);
    if(type==LUA_TFUNCTION&&lua_tocfunction(L,idx)==bridge_call){
        lua_getupvalue(L,idx,2);LjGuard *g=lua_touserdata(L,-1);lua_pop(L,1);return g?g->id:0;
    }
    if(type==LUA_TUSERDATA&&lua_getmetatable(L,idx)){
        lj_root_get(L,J_UDMT);int same=lua_rawequal(L,-1,-2);lua_pop(L,2);
        if(same){LjGuard *g=lua_touserdata(L,idx);return g->id;}
        return 0;
    }
    if(type==LUA_TTABLE){
        lj_root_get(L,J_PUCID);lua_pushvalue(L,idx);lua_rawget(L,-2);int id=0;
        if(lua_type(L,-1)==LUA_TUSERDATA){LjGuard *g=lua_touserdata(L,-1);id=g->id;}
        lua_pop(L,2);return id;
    }
    return 0;
}
static void bridge_ctx_end(HD2Environment *e,lua_State *L,HD2PucState *P,BridgeCtx *c) {
    if(!c->slots)return;
    lua_pushlightuserdata(L,&bridge_key);lua_rawget(L,LUA_REGISTRYINDEX);lua_pushnil(L);lua_rawseti(L,-2,J_SEEN);lua_pop(L,1);
    puc_root(e,P);BA->pushnil(P);BA->rawseti(P,-2,R_SEEN);BA->settop(P,-2);c->slots=0;
}
static void bridge_seen_begin(HD2Environment *e,lua_State *L,HD2PucState *P,BridgeCtx *c) {
    if(c->slots)return;
    lua_pushlightuserdata(L,&bridge_key);lua_rawget(L,LUA_REGISTRYINDEX);lua_newtable(L);lua_rawseti(L,-2,J_SEEN);lua_pop(L,1);
    puc_root(e,P);BA->createtable(P,0,0);BA->rawseti(P,-2,R_SEEN);BA->settop(P,-2);
}
static int to_puc(HD2Environment *e,lua_State *L,int idx,HD2PucState *P,BridgeCtx *c);
static int to_lj(HD2Environment *e,HD2PucState *P,int idx,lua_State *L,BridgeCtx *c);

static int HD2_NATIVE_ABI puc_guard_gc(HD2PucState *P) {
    PucGuard *g=bridge_api.touserdata(P,1);BridgeLink *k=g?g->link:NULL;
    if(!k)return 0;
    if(k->e&&g->id)bridge_queue(&k->e->bridge_lj_release,&k->e->bridge_lj_count,&k->e->bridge_lj_capacity,g->id);
    g->link=NULL;
    if(--k->guards==0&&!k->e)free(k);
    return 0;
}
static int lj_guard_gc(lua_State *L) {
    LjGuard *g=lua_touserdata(L,1);
    if(g&&g->e&&g->id){
        HD2Environment *e=g->e;bridge_queue(&e->bridge_puc_release,&e->bridge_puc_count,&e->bridge_puc_capacity,g->id);g->id=0;
    }
    return 0;
}
/* Applies queued releases. The queues are detached first: collector callbacks
 * triggered by this work append to fresh queues. */
static void bridge_flush(HD2Environment *e,lua_State *L) {
    if(e->bridge_lj_count){
        int *ids=e->bridge_lj_release;size_t n=e->bridge_lj_count;
        e->bridge_lj_release=NULL;e->bridge_lj_count=e->bridge_lj_capacity=0;
        lj_root_get(L,J_OBJS);lj_root_get(L,J_PROXYID);int objs=lua_gettop(L)-1,cache=objs+1;
        for(size_t i=0;i<n;i++){
            lua_rawgeti(L,objs,ids[i]);
            if(!lua_isnil(L,-1)){
                lua_pushvalue(L,-1);lua_rawget(L,cache);
                if(lua_tonumber(L,-1)==ids[i]){lua_pushvalue(L,-2);lua_pushnil(L);lua_rawset(L,cache);}
                lua_pop(L,1);
            }
            lua_pop(L,1);lua_pushnil(L);lua_rawseti(L,objs,ids[i]);
        }
        lua_pop(L,2);free(ids);e->bridge_stats.lj_released+=(uint32_t)n;
    }
    if(e->bridge_puc_count&&e->puc_host){
        int *ids=e->bridge_puc_release;size_t n=e->bridge_puc_count;HD2PucState *P=e->puc_host;
        e->bridge_puc_release=NULL;e->bridge_puc_count=e->bridge_puc_capacity=0;
        int top=BA->gettop(P);
        if(BA->checkstack(P,8)){
            puc_root_get(e,P,R_OBJS);puc_root_get(e,P,R_PROXYID);int objs=top+1,cache=top+2;
            for(size_t i=0;i<n;i++){
                BA->rawgeti(P,objs,ids[i]);
                if(BA->type(P,-1)!=0){
                    BA->pushvalue(P,-1);BA->rawget(P,cache);
                    if(BA->type(P,-1)==3&&BA->tonumber(P,-1)==ids[i]){BA->pushvalue(P,-2);BA->pushnil(P);BA->rawset(P,cache);}
                    BA->settop(P,-2);
                }
                BA->settop(P,-2);BA->pushnil(P);BA->rawseti(P,objs,ids[i]);
            }
            e->bridge_stats.puc_released+=(uint32_t)n;
        }
        BA->settop(P,top);free(ids);
    }
}

/* ---- LuaJIT value -> PUC ---- */
static int puc_proxy_for(HD2Environment *e,lua_State *L,int idx,HD2PucState *P,int function);
static int copy_to_puc(HD2Environment *e,lua_State *L,int idx,HD2PucState *P,BridgeCtx *c) {
    if(++c->depth>200)return bridge_fail(c,"table nesting too deep for a native call",NULL);
    bridge_seen_begin(e,L,P,c);
    lj_root_get(L,J_SEEN);lua_pushvalue(L,idx);lua_rawget(L,-2);
    if(lua_type(L,-1)==LUA_TNUMBER){
        int slot=(int)lua_tonumber(L,-1);lua_pop(L,2);
        puc_root_get(e,P,R_SEEN);BA->rawgeti(P,-1,slot);BA->remove(P,-2);c->depth--;return 1;
    }
    lua_pop(L,1);
    BA->createtable(P,0,0);int copy=BA->gettop(P);int slot=++c->slots;
    lua_pushvalue(L,idx);lua_pushnumber(L,slot);lua_rawset(L,-3);lua_pop(L,1);
    puc_root_get(e,P,R_SEEN);BA->pushvalue(P,copy);BA->rawseti(P,-2,slot);BA->settop(P,-2);
    lua_pushnil(L);
    while(lua_next(L,idx)){
        int top=lua_gettop(L);
        if(!to_puc(e,L,top-1,P,c)||!to_puc(e,L,top,P,c))return 0;
        if(BA->type(P,-2)==0){BA->settop(P,-3);lua_pop(L,1);continue;}
        BA->rawset(P,copy);lua_pop(L,1);
    }
    if(lua_getmetatable(L,idx)){
        if(!to_puc(e,L,lua_gettop(L),P,c))return 0;
        if(BA->type(P,-1)==5)BA->setmetatable(P,copy);else BA->settop(P,-2);
        lua_pop(L,1);
    }
    /* The copy maps back to the original LuaJIT table for its PUC lifetime. */
    int id=lj_new_object(e,L,idx,0);int g=puc_new_guard(e,P,id);
    puc_set_key(e,P,R_LJID,copy,g);BA->settop(P,copy);
    e->bridge_stats.tables_to_native++;c->depth--;return 1;
}
static int to_puc(HD2Environment *e,lua_State *L,int idx,HD2PucState *P,BridgeCtx *c) {
    if(c->error[0])return 0;
    if(!BA->checkstack(P,12))return bridge_fail(c,"native stack overflow",NULL);
    switch(lua_type(L,idx)){
    case LUA_TNIL:BA->pushnil(P);return 1;
    case LUA_TBOOLEAN:BA->pushboolean(P,lua_toboolean(L,idx));return 1;
    case LUA_TNUMBER:BA->pushnumber(P,lua_tonumber(L,idx));return 1;
    case LUA_TSTRING:{size_t n;const char *s=lua_tolstring(L,idx,&n);BA->pushlstring(P,s,n);return 1;}
    case LUA_TLIGHTUSERDATA:BA->pushlightuserdata(P,lua_touserdata(L,idx));return 1;
    case LUA_TFUNCTION:case LUA_TUSERDATA:case LUA_TTABLE:{
        int id=lj_target(L,idx);
        if(id)return puc_push_object(e,P,id,c);
        if(lua_type(L,idx)==LUA_TTABLE)return copy_to_puc(e,L,idx,P,c);
        return puc_proxy_for(e,L,idx,P,lua_type(L,idx)==LUA_TFUNCTION);
    }
    default:return bridge_fail(c,"value cannot cross into native code: ",lua_typename(L,lua_type(L,idx)));
    }
}

/* ---- PUC value -> LuaJIT ---- */
static void lj_push_proxy(HD2Environment *e,lua_State *L,HD2PucState *P,int idx,int type,int mirror) {
    int id=puc_number_at(e,P,R_PROXYID,idx);
    if(id){
        lj_root_get(L,J_PROXY);lua_rawgeti(L,-1,id);lua_remove(L,-2);
        if(!lua_isnil(L,-1))return;
        lua_pop(L,1);
    }
    id=puc_new_object(e,P,idx);
    if(type==6){
        lua_pushlightuserdata(L,e);lj_new_guard(e,L,id,J_GUARDMT);lua_pushcclosure(L,bridge_call,2);
        if(mirror){if(BA->iscfunction(P,idx))e->bridge_stats.functions++;else e->bridge_stats.lua_functions++;}
        else e->bridge_stats.function_proxies++;
    } else {lj_new_guard(e,L,id,J_UDMT);e->bridge_stats.userdata_proxies++;}
    lj_root_get(L,J_PROXY);lua_pushvalue(L,-2);lua_rawseti(L,-2,id);lua_pop(L,1);
}
static int copy_to_lj(HD2Environment *e,HD2PucState *P,int idx,lua_State *L,BridgeCtx *c) {
    if(++c->depth>200)return bridge_fail(c,"native table nesting too deep",NULL);
    if(!lua_checkstack(L,8))return bridge_fail(c,"LuaJIT stack overflow",NULL);
    int id=puc_number_at(e,P,R_PROXYID,idx);
    if(id){ /* a mirrored module or an object already seen as a mirror */
        lj_root_get(L,J_PROXY);lua_rawgeti(L,-1,id);lua_remove(L,-2);
        if(!lua_isnil(L,-1)){c->depth--;return 1;}
        lua_pop(L,1);
    }
    if(c->mirror){
        id=puc_new_object(e,P,idx);lua_newtable(L);int t=lua_gettop(L);
        lj_root_get(L,J_PROXY);lua_pushvalue(L,t);lua_rawseti(L,-2,id);lua_pop(L,1);
        lj_root_get(L,J_PUCID);lua_pushvalue(L,t);lj_new_guard(e,L,id,J_GUARDMT);lua_rawset(L,-3);lua_pop(L,1);
        e->bridge_stats.tables_mirrored++;
    } else {
        bridge_seen_begin(e,L,P,c);
        puc_root_get(e,P,R_SEEN);BA->pushvalue(P,idx);BA->rawget(P,-2);
        if(BA->type(P,-1)==3){
            int slot=(int)BA->tonumber(P,-1);BA->settop(P,-3);
            lj_root_get(L,J_SEEN);lua_rawgeti(L,-1,slot);lua_remove(L,-2);c->depth--;return 1;
        }
        BA->settop(P,-3);lua_newtable(L);int slot=++c->slots;
        puc_root_get(e,P,R_SEEN);BA->pushvalue(P,idx);BA->pushnumber(P,slot);BA->rawset(P,-3);BA->settop(P,-2);
        lj_root_get(L,J_SEEN);lua_pushvalue(L,-2);lua_rawseti(L,-2,slot);lua_pop(L,1);
        e->bridge_stats.tables_from_native++;
    }
    int t=lua_gettop(L);
    if(!BA->checkstack(P,8))return bridge_fail(c,"native stack overflow",NULL);
    BA->pushnil(P);
    while(BA->next(P,idx)){
        int top=BA->gettop(P);
        if(!to_lj(e,P,top-1,L,c)||!to_lj(e,P,top,L,c))return 0;
        lua_rawset(L,t);BA->settop(P,-2);
    }
    if(BA->getmetatable(P,idx)){
        if(!to_lj(e,P,BA->gettop(P),L,c))return 0;
        if(lua_istable(L,-1))lua_setmetatable(L,t);else lua_pop(L,1);
        BA->settop(P,-2);
    }
    c->depth--;return 1;
}
static int to_lj(HD2Environment *e,HD2PucState *P,int idx,lua_State *L,BridgeCtx *c) {
    if(c->error[0])return 0;
    if(!lua_checkstack(L,12))return bridge_fail(c,"LuaJIT stack overflow",NULL);
    int type=BA->type(P,idx);
    switch(type){
    case 0:lua_pushnil(L);return 1;
    case 1:lua_pushboolean(L,BA->toboolean(P,idx));return 1;
    case 2:lua_pushlightuserdata(L,BA->touserdata(P,idx));return 1;
    case 3:lua_pushnumber(L,BA->tonumber(P,idx));return 1;
    case 4:{size_t n;const char *s=BA->tolstring(P,idx,&n);lua_pushlstring(L,s,n);return 1;}
    case 5:case 6:case 7:{
        int id=puc_guard_id(e,P,idx);
        if(id){
            lj_root_get(L,J_OBJS);lua_rawgeti(L,-1,id);lua_remove(L,-2);
            if(lua_isnil(L,-1)){lua_pop(L,1);return bridge_fail(c,"LuaJIT object was released",NULL);}
            return 1;
        }
        if(type==5)return copy_to_lj(e,P,idx,L,c);
        if(!BA->checkstack(P,8))return bridge_fail(c,"native stack overflow",NULL);
        lj_push_proxy(e,L,P,idx,type,c->mirror);return 1;
    }
    default:return bridge_fail(c,"native thread values cannot cross into LuaJIT",NULL);
    }
}

/* ---- Calls ---- */
/* Target callable at PUC index top+1; LuaJIT arguments first..last. */
static int bridge_invoke(lua_State *L,HD2Environment *e,HD2PucState *P,int top,int first,int last) {
    BridgeCtx c={0};
    for(int i=first;i<=last;i++)if(!to_puc(e,L,i,P,&c))break;
    bridge_ctx_end(e,L,P,&c);
    if(c.error[0]){BA->settop(P,top);return luaL_error(L,"%s",c.error);}
    lua_State *outer=e->bridge_current;e->bridge_current=L;
    int status=BA->pcall(P,last-first+1,-1,0);
    e->bridge_current=outer;e->bridge_stats.calls++;
    BridgeCtx r={0};
    if(status){
        e->bridge_stats.errors++;
        if(BA->type(P,-1)==4){size_t n;const char *s=BA->tolstring(P,-1,&n);lua_pushlstring(L,s,n);}
        else if(!to_lj(e,P,BA->gettop(P),L,&r))lua_pushstring(L,"native error object could not be converted");
        bridge_ctx_end(e,L,P,&r);BA->settop(P,top);return lua_error(L);
    }
    int n=BA->gettop(P)-top;
    if(!lua_checkstack(L,n+8)){BA->settop(P,top);return luaL_error(L,"too many native results");}
    for(int i=1;i<=n;i++)if(!to_lj(e,P,top+i,L,&r))break;
    bridge_ctx_end(e,L,P,&r);BA->settop(P,top);
    if(r.error[0])return luaL_error(L,"%s",r.error);
    return n;
}
static HD2PucState *bridge_enter(lua_State *L,HD2Environment *e,int *top) {
    if(!e->bridge_ready||!e->puc_host)luaL_error(L,"native bridge closed");
    if(!same_thread(e->thread))luaL_error(L,"native bridge thread mismatch");
    bridge_flush(e,L);
    /* Inside an engine-to-LuaJIT call, nested natives run on the calling PUC
     * thread (the engine's main thread for update/render), as they would have
     * in the original VM; otherwise on the idle host thread. */
    HD2PucState *P=e->bridge_puc_current?e->bridge_puc_current:e->puc_host;*top=BA->gettop(P);
    if(!BA->checkstack(P,lua_gettop(L)+16))luaL_error(L,"native call stack unavailable");
    return P;
}
static int bridge_call(lua_State *L) {
    HD2Environment *e=lua_touserdata(L,lua_upvalueindex(1));LjGuard *g=lua_touserdata(L,lua_upvalueindex(2));
    int top;HD2PucState *P=bridge_enter(L,e,&top);BridgeCtx c={0};
    if(!g->id||!puc_push_object(e,P,g->id,&c)){BA->settop(P,top);return luaL_error(L,"native function was released");}
    return bridge_invoke(L,e,P,top,1,lua_gettop(L));
}
static int HD2_NATIVE_ABI puc_op_index(HD2PucState *P){bridge_api.settop(P,2);bridge_api.gettable(P,1);return 1;}
static int HD2_NATIVE_ABI puc_op_newindex(HD2PucState *P){bridge_api.settop(P,3);bridge_api.settable(P,1);return 0;}
static int lj_ud_op(lua_State *L,HD2PucCFunction op,int nargs) {
    HD2Environment *e=((LjGuard *)lua_touserdata(L,1))->e;lua_settop(L,nargs);
    int top;HD2PucState *P=bridge_enter(L,e,&top);BA->pushcclosure(P,op,0);
    return bridge_invoke(L,e,P,top,1,nargs);
}
/* Pushes the LuaJIT mirror of the __index table in the PUC metatable of the
 * object behind proxy u, or returns 0. Mods extend engine modules in LuaJIT;
 * the original metatable never sees those additions. */
static int lj_ud_mirror_index(lua_State *L,HD2Environment *e,int u) {
    LjGuard *g=lua_touserdata(L,u);int top,found=0;BridgeCtx c={0};
    if(!g->id)return 0;
    HD2PucState *P=bridge_enter(L,e,&top);
    if(puc_push_object(e,P,g->id,&c)&&BA->getmetatable(P,-1)){
        BA->pushlstring(P,"__index",7);BA->rawget(P,-2);
        if(BA->type(P,-1)==5){
            int id=puc_number_at(e,P,R_PROXYID,BA->gettop(P));
            if(id){lj_root_get(L,J_PROXY);lua_rawgeti(L,-1,id);lua_remove(L,-2);found=lua_istable(L,-1);if(!found)lua_pop(L,1);}
        }
    }
    BA->settop(P,top);return found;
}
static int lj_ud_index(lua_State *L) {
    HD2Environment *e=((LjGuard *)lua_touserdata(L,1))->e;lua_settop(L,2);
    int n=lj_ud_op(L,puc_op_index,2);
    if(n>=1&&lua_isnil(L,-1)&&lj_ud_mirror_index(L,e,1)){lua_pushvalue(L,2);lua_gettable(L,-2);return 1;}
    return n;
}
static int lj_ud_newindex(lua_State *L){return lj_ud_op(L,puc_op_newindex,3);}
static int lj_ud_call(lua_State *L) {
    LjGuard *g=lua_touserdata(L,1);HD2Environment *e=g->e;
    int top;HD2PucState *P=bridge_enter(L,e,&top);BridgeCtx c={0};
    if(!g->id||!puc_push_object(e,P,g->id,&c)){BA->settop(P,top);return luaL_error(L,"native object was released");}
    return bridge_invoke(L,e,P,top,2,lua_gettop(L));
}
static int lj_ud_tostring(lua_State *L) {
    HD2Environment *e=((LjGuard *)lua_touserdata(L,1))->e;lua_settop(L,1);
    int top;HD2PucState *P=bridge_enter(L,e,&top);BA->getfield(P,HD2_PUC_GLOBALSINDEX,"tostring");
    return bridge_invoke(L,e,P,top,1,1);
}
/* PUC proxy for a LuaJIT function or userdata, cached per object. */
static int HD2_NATIVE_ABI puc_proxy_call(HD2PucState *P);
static int puc_proxy_for(HD2Environment *e,lua_State *L,int idx,HD2PucState *P,int function) {
    int id=lj_number_at(L,J_PROXYID,idx);
    if(id){
        puc_root_get(e,P,R_LJPROXY);BA->rawgeti(P,-1,id);BA->remove(P,-2);
        if(BA->type(P,-1)!=0)return 1;
        BA->settop(P,-2);
    }
    id=lj_new_object(e,L,idx,1);int g=puc_new_guard(e,P,id);
    if(function){
        /* The closure keeps its guard as an upvalue; R_LJID maps it back. */
        BA->pushvalue(P,g);BA->pushcclosure(P,puc_proxy_call,1);int proxy=BA->gettop(P);
        puc_set_key(e,P,R_LJID,proxy,g);puc_set_id(e,P,R_LJPROXY,id,proxy);BA->replace(P,g);
        e->bridge_stats.callbacks_to_native++;
    } else {
        /* The guard itself is the opaque proxy and identifies itself by metatable. */
        puc_set_id(e,P,R_LJPROXY,id,g);e->bridge_stats.opaque_to_native++;
    }
    return 1;
}
/* An engine-to-LuaJIT call: P is the calling PUC thread. The target is the
 * LuaJIT object behind the proxy (name NULL) or the current LuaJIT global name
 * (forwarders for the engine's named callbacks, re-resolved on every call). */
static int puc_call_into_lj(HD2PucState *P,PucGuard *g,const char *name) {
    HD2Environment *e=g&&g->link?g->link->e:NULL;
    if(!e||!e->bridge_ready){bridge_api.pushlstring(P,"LuaJIT bridge closed",20);return bridge_api.error(P);}
    if(!same_thread(e->thread)){BA->pushlstring(P,"LuaJIT bridge thread mismatch",29);return BA->error(P);}
    lua_State *L=e->bridge_current?e->bridge_current:e->L;
    int n=BA->gettop(P),base=lua_gettop(L);
    if(!lua_checkstack(L,n+16)){BA->pushlstring(P,"LuaJIT stack unavailable",24);return BA->error(P);}
    bridge_flush(e,L);
    if(name){
        lua_getglobal(L,name);
        if(!lua_isfunction(L,-1)){lua_settop(L,base);return 0;} /* absent callback: nothing to run */
    } else {
        lj_root_get(L,J_OBJS);lua_rawgeti(L,-1,g->id);lua_remove(L,-2);
        if(lua_isnil(L,-1)){lua_settop(L,base);BA->pushlstring(P,"LuaJIT callback was released",28);return BA->error(P);}
    }
    BridgeCtx c={0};
    for(int i=1;i<=n;i++)if(!to_lj(e,P,i,L,&c))break;
    bridge_ctx_end(e,L,P,&c);
    if(c.error[0]){lua_settop(L,base);BA->pushlstring(P,c.error,strlen(c.error));return BA->error(P);}
    e->bridge_stats.callbacks++;
    HD2PucState *outer=e->bridge_puc_current;e->bridge_puc_current=P;
    int status=lua_pcall(L,n,LUA_MULTRET,0);
    e->bridge_puc_current=outer;
    if(status){
        size_t len;const char *s=lua_tolstring(L,-1,&len);
        if(!s){s="non-string LuaJIT error";len=strlen(s);}
        BA->pushlstring(P,s,len);lua_settop(L,base);e->bridge_stats.callback_errors++;return BA->error(P);
    }
    int r=lua_gettop(L)-base;BridgeCtx o={0};
    if(!BA->checkstack(P,r+8)){lua_settop(L,base);BA->pushlstring(P,"native stack unavailable",24);return BA->error(P);}
    for(int i=1;i<=r;i++)if(!to_puc(e,L,base+i,P,&o))break;
    bridge_ctx_end(e,L,P,&o);lua_settop(L,base);
    if(o.error[0]){BA->settop(P,n);BA->pushlstring(P,o.error,strlen(o.error));return BA->error(P);}
    /* The engine runs its timed collector once per frame for the VM it owns;
     * after the forwarded update returns (LuaJIT off the stack), the same
     * policy runs for LuaJIT's heap. */
    if(name&&e->bridge_timed_gc&&!strcmp(name,"update")&&L==e->L){
        if(hd2env_collect_frame(e,NULL))e->bridge_stats.gc_frames++;
        else e->bridge_stats.gc_failures++;
    }
    return r;
}
static int HD2_NATIVE_ABI puc_proxy_call(HD2PucState *P) {
    return puc_call_into_lj(P,bridge_api.touserdata(P,HD2_PUC_UPVALUEINDEX(1)),NULL);
}
static int HD2_NATIVE_ABI puc_forward_call(HD2PucState *P) {
    const char *name=bridge_api.tolstring(P,HD2_PUC_UPVALUEINDEX(2),NULL);
    return puc_call_into_lj(P,bridge_api.touserdata(P,HD2_PUC_UPVALUEINDEX(1)),name);
}

/* ---- Registration ---- */
static int bridge_owned(HD2Environment *e,const char *name,int *merge) {
    static const char *vectors[]={"Vector2","Vector3","Vector3Box","Vector4","Quaternion","Matrix4x4","QuaternionBox","Matrix4x4Box"};
    const int ready[]={e->vector2_ready,e->vector3_ready,e->vector3box_ready,e->vector4_ready,e->quaternion_ready,e->matrix4x4_ready,e->boxes_ready,e->boxes_ready};
    *merge=0;
    for(size_t i=0;i<sizeof(vectors)/sizeof(*vectors);i++)if(!strcmp(name,vectors[i])&&ready[i])return 1;
    /* Partial ports keep their replacements and gain the remaining natives. */
    if((!strcmp(name,"Script")&&e->vector2_ready)||(!strcmp(name,"Steam")&&e->steam_ready)||
       ((!strcmp(name,"Friends")||!strcmp(name,"Presence"))&&e->friends_ready)||
       ((!strcmp(name,"SteamVoipRoom")||!strcmp(name,"SteamVoipClient"))&&e->voip_ready)){*merge=1;return 1;}
    return 0;
}
/* Records LuaJIT table t as the mirror of the PUC table at idx. */
static void bridge_adopt(HD2Environment *e,lua_State *L,int t,HD2PucState *P,int idx) {
    if(puc_number_at(e,P,R_PROXYID,idx))return;
    int id=puc_new_object(e,P,idx);
    lj_root_get(L,J_PROXY);lua_pushvalue(L,t);lua_rawseti(L,-2,id);lua_pop(L,1);
    lj_root_get(L,J_PUCID);lua_pushvalue(L,t);lj_new_guard(e,L,id,J_GUARDMT);lua_rawset(L,-3);lua_pop(L,1);
}
static int bridge_merge(HD2Environment *e,lua_State *L,int t,HD2PucState *P,int idx,BridgeCtx *c) {
    BA->pushnil(P);
    while(BA->next(P,idx)){
        int top=BA->gettop(P);
        if(BA->type(P,top-1)==4){
            const char *key=BA->tolstring(P,top-1,NULL);lua_getfield(L,t,key);
            int replace=lua_isnil(L,-1)||lua_tocfunction(L,-1)==unsupported;lua_pop(L,1);
            if(replace){if(!to_lj(e,P,top,L,c))return 0;lua_setfield(L,t,key);e->bridge_stats.merged++;}
            else e->bridge_stats.kept++;
        }
        BA->settop(P,top-1);
    }
    return 1;
}
/* Upvalues: LuaJIT's previous tostring, the engine's tostring (bridged). */
static int bridge_tostring(lua_State *L) {
    int engine=lua_gettop(L)>=1&&lua_type(L,1)==LUA_TLIGHTUSERDATA;
    lua_pushvalue(L,lua_upvalueindex(engine?2:1));lua_insert(L,1);
    lua_call(L,lua_gettop(L)-1,LUA_MULTRET);return lua_gettop(L);
}
static int bridge_registration(lua_State *L,HD2Environment *e) {
    HD2PucState *M=e->puc_main;
#ifdef _WIN32
    /* PUC keeps guard finalizers and proxy closures that point into this
     * library after the environment closes; it must never be unloaded. After
     * batch 902 the game crashed executing a guard __gc in an unloaded copy. */
    HMODULE self;
    if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,(LPCWSTR)(void *)bridge_call,&self))
        return luaL_error(L,"native bridge could not pin its library");
#endif
    BridgeLink *k=calloc(1,sizeof(*k));if(!k)return luaL_error(L,"native bridge allocation failed");
    k->e=e;e->bridge_link=k;
    int top=BA->gettop(M);if(!BA->checkstack(M,16))return luaL_error(L,"native registration stack unavailable");
    BA->pushlightuserdata(M,k);BA->createtable(M,8,0);int root=top+2;
    BA->createtable(M,0,0);BA->rawseti(M,root,R_OBJS);
    puc_weak(e,M,"k");BA->rawseti(M,root,R_PROXYID);
    puc_weak(e,M,"k");BA->rawseti(M,root,R_LJID);
    puc_weak(e,M,"v");BA->rawseti(M,root,R_LJPROXY);
    BA->createtable(M,0,1);BA->pushcclosure(M,puc_guard_gc,0);BA->setfield(M,-2,"__gc");BA->rawseti(M,root,R_GUARDMT);
    e->puc_host=BA->newthread(M);BA->rawseti(M,root,R_THREAD);
    BA->rawset(M,HD2_PUC_REGISTRYINDEX);BA->settop(M,top);
    lua_pushlightuserdata(L,&bridge_key);lua_createtable(L,8,0);int lr=lua_gettop(L);
    lua_newtable(L);lua_rawseti(L,lr,J_OBJS);
    lj_weak(L,"k");lua_rawseti(L,lr,J_PROXYID);
    lj_weak(L,"v");lua_rawseti(L,lr,J_PROXY);
    lj_weak(L,"k");lua_rawseti(L,lr,J_PUCID);
    lua_createtable(L,0,5);callback(L,"__gc",lj_guard_gc);callback(L,"__index",lj_ud_index);callback(L,"__newindex",lj_ud_newindex);
    callback(L,"__call",lj_ud_call);callback(L,"__tostring",lj_ud_tostring);lua_rawseti(L,lr,J_UDMT);
    lua_createtable(L,0,1);callback(L,"__gc",lj_guard_gc);lua_rawseti(L,lr,J_GUARDMT);
    lua_rawset(L,LUA_REGISTRYINDEX);
    e->bridge_ready=1;
    HD2PucState *P=e->puc_host;BridgeCtx c={0};c.mirror=1;
    for(const char *r=e->bridge_roots;r&&*r;){
        const char *end=strchr(r,',');size_t n=end?(size_t)(end-r):strlen(r);char name[64];
        if(!n||n>=sizeof(name))return luaL_error(L,"invalid native bridge root");
        memcpy(name,r,n);name[n]=0;r=end?end+1:r+n;
        if(!strcmp(name,"*")){
            /* Every engine global LuaJIT lacks (print_* family, s3d, ...). */
            int pt=BA->gettop(P);BA->pushnil(P);
            while(BA->next(P,HD2_PUC_GLOBALSINDEX)){
                int kt=BA->gettop(P);
                if(BA->type(P,kt-1)==4){
                    const char *key=BA->tolstring(P,kt-1,NULL);
                    lua_getglobal(L,key);int missing=lua_isnil(L,-1);lua_pop(L,1);
                    if(missing){if(!to_lj(e,P,kt,L,&c))break;lua_setglobal(L,key);e->bridge_stats.roots++;}
                }
                BA->settop(P,kt-1);
            }
            BA->settop(P,pt);
            if(c.error[0])return luaL_error(L,"%s",c.error);
            continue;
        }
        int pt=BA->gettop(P);BA->getfield(P,HD2_PUC_GLOBALSINDEX,name);
        lua_getglobal(L,name);int lt=lua_gettop(L);
        if(BA->type(P,pt+1)==5&&lua_istable(L,lt)){
            /* Merge one level: keep validated ports, replace fixtures. */
            bridge_adopt(e,L,lt,P,pt+1);
            BA->pushnil(P);
            while(BA->next(P,pt+1)){
                int kt=BA->gettop(P);int merge=0;
                if(BA->type(P,kt-1)==4){
                    const char *key=BA->tolstring(P,kt-1,NULL);
                    if(bridge_owned(e,key,&merge)){
                        lua_getfield(L,lt,key);
                        if(lua_istable(L,-1)&&BA->type(P,kt)==5){
                            bridge_adopt(e,L,lua_gettop(L),P,kt);
                            if(merge&&!bridge_merge(e,L,lua_gettop(L),P,kt,&c))break;
                        }
                        lua_pop(L,1);e->bridge_stats.modules_kept++;
                    } else {
                        if(!to_lj(e,P,kt,L,&c))break;
                        lua_setfield(L,lt,key);e->bridge_stats.modules++;
                    }
                } else {
                    if(!to_lj(e,P,kt-1,L,&c)||!to_lj(e,P,kt,L,&c))break;
                    lua_rawset(L,lt);
                }
                BA->settop(P,kt-1);
            }
        } else if(BA->type(P,pt+1)!=0){
            if(to_lj(e,P,pt+1,L,&c))lua_setglobal(L,name);
            e->bridge_stats.roots++;
        }
        lua_settop(L,lt-1);BA->settop(P,pt);
        if(c.error[0])return luaL_error(L,"%s",c.error);
    }
    /* Engine lightuserdata (matrices, handles and any type without a LuaJIT
     * port) format through the engine's own global tostring, exactly as the
     * original VM did. Everything else keeps LuaJIT's tostring chain. */
    {
        int pt=BA->gettop(P);BA->getfield(P,HD2_PUC_GLOBALSINDEX,"tostring");
        if(BA->type(P,pt+1)==6&&to_lj(e,P,pt+1,L,&c)){
            lua_getglobal(L,"tostring");lua_insert(L,-2);lua_pushcclosure(L,bridge_tostring,2);lua_setglobal(L,"tostring");
        }
        BA->settop(P,pt);
        if(c.error[0])return luaL_error(L,"%s",c.error);
    }
    return 0;
}
static void bridge_close(HD2Environment *e) {
    BridgeLink *k=e->bridge_link;
    if(!k)return;
    HD2PucState *P=e->puc_host?e->puc_host:e->puc_main;
    if(P){
        int top=BA->gettop(P);
        if(BA->checkstack(P,4)){BA->pushlightuserdata(P,k);BA->pushnil(P);BA->rawset(P,HD2_PUC_REGISTRYINDEX);}
        BA->settop(P,top);
    }
    e->bridge_ready=0;k->e=NULL;e->bridge_link=NULL;e->puc_host=NULL;
    if(!k->guards)free(k);
}
int hd2env_register_bridge(HD2Environment *e,const HD2SteamHost *host,uintptr_t puc_state,const char *roots) {
    if(!enter(e))return 0;
    HD2PucApi api;
    if(e->bridge_link||!puc_state||!roots||!hd2puc_bind(&api,host)){
        snprintf(e->error,sizeof(e->error),"native bridge already installed, PUC state missing or image witnesses refused");e->busy=0;return 0;
    }
    e->puc=api;bridge_api=api;e->puc_main=(HD2PucState *)puc_state;e->bridge_roots=roots;e->operation=20;
    int ok=dispatch(e);e->bridge_roots=NULL;
    return ok;
}
/* Sets each named PUC global to a forwarder into the LuaJIT global of the same
 * name. The engine's named-call helper resolves these globals raw. */
static int bridge_forwarders(lua_State *L,HD2Environment *e) {
    HD2PucState *P=e->puc_host;
    for(const char *r=e->bridge_roots;r&&*r;){
        const char *end=strchr(r,',');size_t n=end?(size_t)(end-r):strlen(r);
        if(!n||n>=64)return luaL_error(L,"invalid forwarder name");
        int top=BA->gettop(P);if(!BA->checkstack(P,6))return luaL_error(L,"native stack unavailable");
        puc_new_guard(e,P,0);BA->pushlstring(P,r,n);BA->pushcclosure(P,puc_forward_call,2);
        char name[64];memcpy(name,r,n);name[n]=0;BA->setfield(P,HD2_PUC_GLOBALSINDEX,name);BA->settop(P,top);
        e->bridge_stats.forwarders++;r=end?end+1:r+n;
    }
    return 0;
}
int hd2env_bridge_timed_gc(HD2Environment *e,int enabled) {
    if(!e||!same_thread(e->thread)||e->busy||!e->bridge_ready)return 0;
    e->bridge_timed_gc=enabled!=0;return 1;
}
int hd2env_bridge_forward(HD2Environment *e,const char *names) {
    if(!enter(e))return 0;
    if(!e->bridge_ready||!names){snprintf(e->error,sizeof(e->error),"native bridge not installed");e->busy=0;return 0;}
    e->bridge_roots=names;e->operation=21;int ok=dispatch(e);e->bridge_roots=NULL;return ok;
}
int hd2env_bridge_stats(const HD2Environment *e,HD2BridgeStats *out) {
    if(!e||!out||!same_thread(e->thread))return 0;
    *out=e->bridge_stats;out->live_lj_ids=(uint32_t)(e->bridge_next_lj-out->lj_released);
    out->live_puc_ids=(uint32_t)(e->bridge_next_puc-out->puc_released);out->pending=(uint32_t)(e->bridge_lj_count+e->bridge_puc_count);
    return 1;
}
#undef BA
