/* Included only by environment.c: every Lua API operation stays inside its
 * protected same-thread boundary. No private VM layout or C callback is reused. */
typedef struct HeldObject {
    struct HeldObject *next;
    uint64_t identity;
    int reference;
} HeldObject;
struct HD2ObjectStore {
    uint64_t environment, sequence;
    HeldObject *head;
    size_t count;
    int poisoned,initialized;
};
enum { OBJ_VALUE,OBJ_GLOBAL,OBJ_CLONE,OBJ_TYPE,OBJ_READ,OBJ_GET,OBJ_SET,
       OBJ_RELEASE,OBJ_COMPILE,OBJ_CALL,OBJ_FREE };
struct ObjectRequest {
    int kind;
    HD2Object object,key,value;
    const HD2Value *scalar;
    const char *source,*name;
    size_t size,count;
    const HD2Object *args;
    HD2Object *out;
    HD2ObjectKind *type;
    HD2Results *scalar_results;
    HD2ObjectResults *results;
    uint64_t checkpoint;
    char error[2048];
    int lua_error;
};
static atomic_uint_fast64_t object_epoch=ATOMIC_VAR_INIT(1);
static char objects_registry_key;

static uint64_t next_object_epoch(void) {
    uint_fast64_t n=atomic_load(&object_epoch);
    while(n!=UINT64_MAX){
        if(atomic_compare_exchange_weak(&object_epoch,&n,n+1))return (uint64_t)n;
    }
    return 0;
}
static void object_store_free(HD2ObjectStore *s) {
    if(!s)return;
    while(s->head){HeldObject *p=s->head;s->head=p->next;free(p);}
    free(s);
}
static void object_table(lua_State *L) {
    lua_pushlightuserdata(L,&objects_registry_key);lua_rawget(L,LUA_REGISTRYINDEX);
    if(!lua_istable(L,-1))luaL_error(L,"object registry unavailable");
}
static void object_store_init(HD2Environment *e,lua_State *L) {
    if(e->objects&&e->objects->initialized)return;
    if(!e->objects){
        HD2ObjectStore *s=calloc(1,sizeof(*s));
        if(!s)luaL_error(L,"cannot allocate object ownership store");
        s->environment=next_object_epoch();
        if(!s->environment){free(s);luaL_error(L,"object environment identity exhausted");}
        /* Retain an empty C store if Lua allocation fails. Initialization can
         * be retried without losing the unique environment identity. */
        e->objects=s;
    }
    lua_pushlightuserdata(L,&objects_registry_key);lua_createtable(L,16,0);
    lua_pushinteger(L,0);lua_rawseti(L,-2,0);
    lua_rawset(L,LUA_REGISTRYINDEX);
    e->objects->initialized=1;
}
static HeldObject *object_find(HD2Environment *e,lua_State *L,HD2Object o) {
    HD2ObjectStore *s=e->objects;
    if(!s||o.environment!=s->environment||!o.identity)
        luaL_error(L,"foreign or invalid object identity");
    for(HeldObject *p=s->head;p;p=p->next)if(p->identity==o.identity)return p;
    luaL_error(L,"released or unknown object identity");return NULL;
}
static void object_push(HD2Environment *e,lua_State *L,HD2Object o) {
    HeldObject *p=object_find(e,L,o);
    if(p->reference==LUA_REFNIL){lua_pushnil(L);return;}
    if(p->reference==LUA_NOREF)luaL_error(L,"uncommitted object identity");
    object_table(L);lua_rawgeti(L,-1,p->reference);lua_remove(L,-2);
}
static HD2Object object_pin(HD2Environment *e,lua_State *L,int index) {
    HD2ObjectStore *s=e->objects;
    if(s->sequence==UINT64_MAX)luaL_error(L,"object identity exhausted");
    HeldObject *p=calloc(1,sizeof(*p));
    if(!p)luaL_error(L,"cannot allocate owned Lua value");
    p->reference=LUA_NOREF;p->identity=++s->sequence;
    p->next=s->head;s->head=p;s->count++;
    /* Link before luaL_ref so an allocation error is rolled back too. */
    if(index<0)index=lua_gettop(L)+index+1;
    object_table(L);lua_pushvalue(L,index);
    p->reference=luaL_ref(L,-2);lua_pop(L,1);
    return (HD2Object){s->environment,p->identity};
}
static void object_unlink(HD2Environment *e,lua_State *L,HeldObject *p) {
    object_table(L);luaL_unref(L,-1,p->reference);lua_pop(L,1);
    HeldObject **at=&e->objects->head;
    while(*at!=p)at=&(*at)->next;
    *at=p->next;e->objects->count--;free(p);
}
static int object_rollback(lua_State *L) {
    HD2Environment *e=lua_touserdata(L,1);
    if(!e->objects)return 0;
    while(e->objects->head&&e->objects->head->identity>e->object_request->checkpoint)
        object_unlink(e,L,e->objects->head);
    return 0;
}
static void object_error(lua_State *L,ObjectRequest *r) {
    r->lua_error=1;r->results->is_error=1;
    const char *s=lua_type(L,-1)==LUA_TSTRING?lua_tostring(L,-1):"non-string Lua error";
    snprintf(r->error,sizeof(r->error),"%s",s);
}
static void object_collect(HD2Environment *e,lua_State *L,ObjectRequest *r) {
    int n=lua_gettop(L);
    if(!lua_checkstack(L,4))luaL_error(L,"owned result stack unavailable");
    if(!n)return;
    r->results->values=calloc((size_t)n,sizeof(HD2Object));
    if(!r->results->values)luaL_error(L,"cannot allocate owned callback results");
    r->results->count=(size_t)n;
    for(int i=0;i<n;i++)r->results->values[i]=object_pin(e,L,i+1);
}
static int object_operation(HD2Environment *e,lua_State *L) {
    ObjectRequest *r=e->object_request;
    object_store_init(e,L);
    if(e->objects->poisoned)return luaL_error(L,"object store unavailable; destroy environment");
    if(!lua_checkstack(L,r->kind==OBJ_CALL?(int)r->count+8:8))
        return luaL_error(L,"object operation stack unavailable");
    switch(r->kind){
        case OBJ_VALUE:push_value(L,r->scalar);*r->out=object_pin(e,L,-1);break;
        case OBJ_GLOBAL:lua_getglobal(L,r->name);*r->out=object_pin(e,L,-1);break;
        case OBJ_CLONE:object_push(e,L,r->object);*r->out=object_pin(e,L,-1);break;
        case OBJ_TYPE:{
            object_push(e,L,r->object);HD2ObjectKind kind=HD2_OBJECT_OTHER;
            switch(lua_type(L,-1)){
                case LUA_TNIL:kind=HD2_OBJECT_NIL;break;
                case LUA_TBOOLEAN:kind=HD2_OBJECT_BOOLEAN;break;
                case LUA_TNUMBER:kind=HD2_OBJECT_NUMBER;break;
                case LUA_TSTRING:kind=HD2_OBJECT_STRING;break;
                case LUA_TLIGHTUSERDATA:kind=HD2_OBJECT_POINTER;break;
                case LUA_TTABLE:kind=HD2_OBJECT_TABLE;break;
                case LUA_TFUNCTION:kind=HD2_OBJECT_FUNCTION;break;
                case LUA_TUSERDATA:kind=HD2_OBJECT_USERDATA;break;
                case LUA_TTHREAD:kind=HD2_OBJECT_THREAD;break;
            }
            *r->type=kind;break;
        }
        case OBJ_READ:object_push(e,L,r->object);copy_results(L,r->scalar_results);break;
        case OBJ_GET:object_push(e,L,r->object);object_push(e,L,r->key);lua_gettable(L,-2);
            *r->out=object_pin(e,L,-1);break;
        case OBJ_SET:object_push(e,L,r->object);object_push(e,L,r->key);object_push(e,L,r->value);
            lua_settable(L,-3);break;
        case OBJ_RELEASE:object_unlink(e,L,object_find(e,L,r->object));memset(r->out,0,sizeof(*r->out));break;
        case OBJ_FREE:
            /* Validate the whole array first, including duplicate ownership. */
            for(size_t i=0;i<r->results->count;i++){
                object_find(e,L,r->results->values[i]);
                for(size_t j=0;j<i;j++)if(r->results->values[i].identity==r->results->values[j].identity)
                    return luaL_error(L,"duplicate object ownership in results");
            }
            for(size_t i=0;i<r->results->count;i++)object_unlink(e,L,object_find(e,L,r->results->values[i]));
            break;
        case OBJ_COMPILE:
            if(compile(L,(const unsigned char *)r->source,r->size,r->name,"bt"))object_error(L,r);
            object_collect(e,L,r);break;
        case OBJ_CALL:
            object_push(e,L,r->object);
            for(size_t i=0;i<r->count;i++)object_push(e,L,r->args[i]);
            if(lua_pcall(L,(int)r->count,LUA_MULTRET,0))object_error(L,r);
            object_collect(e,L,r);break;
        default:return luaL_error(L,"unknown object operation");
    }
    return 0;
}
static int object_run(HD2Environment *e,ObjectRequest *r) {
    if(!enter(e))return HD2_OBJECT_FAILURE;
    if((r->out&&(r->out->environment||r->out->identity)&&r->kind!=OBJ_RELEASE)||
       (r->results&&(r->results->values||r->results->count||r->results->is_error)&&r->kind!=OBJ_FREE)||
       (r->scalar_results&&(r->scalar_results->values||r->scalar_results->count))){
        snprintf(e->error,sizeof(e->error),"nonempty object output");e->busy=0;return HD2_OBJECT_FAILURE;
    }
    r->checkpoint=e->objects?e->objects->sequence:0;
    e->operation=100;e->object_request=r;
    int ok=dispatch(e);e->object_request=NULL;
    if(!ok){
        if(r->out&&r->kind!=OBJ_RELEASE)memset(r->out,0,sizeof(*r->out));
        if(r->results&&r->kind!=OBJ_FREE){free(r->results->values);memset(r->results,0,sizeof(*r->results));}
        if(r->scalar_results)hd2env_results_free(r->scalar_results);
        return HD2_OBJECT_FAILURE;
    }
    if(r->lua_error){snprintf(e->error,sizeof(e->error),"%s",r->error);return HD2_OBJECT_LUA_ERROR;}
    return HD2_OBJECT_SUCCESS;
}
int hd2env_object_from_value(HD2Environment *e,const HD2Value *v,HD2Object *out) {
    if(!v||!out||v->type<HD2_VALUE_NIL||v->type>HD2_VALUE_POINTER||
       (v->type==HD2_VALUE_STRING&&v->as.string.size&&!v->as.string.bytes))return HD2_OBJECT_FAILURE;
    ObjectRequest r={.kind=OBJ_VALUE,.scalar=v,.out=out};return object_run(e,&r);
}
int hd2env_object_global(HD2Environment *e,const char *name,HD2Object *out) {
    if(!name||!out)return HD2_OBJECT_FAILURE;
    ObjectRequest r={.kind=OBJ_GLOBAL,.name=name,.out=out};return object_run(e,&r);
}
int hd2env_object_clone(HD2Environment *e,HD2Object o,HD2Object *out) {
    if(!out)return HD2_OBJECT_FAILURE;
    ObjectRequest r={.kind=OBJ_CLONE,.object=o,.out=out};return object_run(e,&r);
}
int hd2env_object_type(HD2Environment *e,HD2Object o,HD2ObjectKind *out) {
    if(!out)return HD2_OBJECT_FAILURE;
    ObjectRequest r={.kind=OBJ_TYPE,.object=o,.type=out};return object_run(e,&r);
}
int hd2env_object_read(HD2Environment *e,HD2Object o,HD2Results *out) {
    if(!out)return HD2_OBJECT_FAILURE;
    ObjectRequest r={.kind=OBJ_READ,.object=o,.scalar_results=out};return object_run(e,&r);
}
int hd2env_object_get(HD2Environment *e,HD2Object o,HD2Object key,HD2Object *out) {
    if(!out)return HD2_OBJECT_FAILURE;
    ObjectRequest r={.kind=OBJ_GET,.object=o,.key=key,.out=out};return object_run(e,&r);
}
int hd2env_object_set(HD2Environment *e,HD2Object o,HD2Object key,HD2Object value) {
    ObjectRequest r={.kind=OBJ_SET,.object=o,.key=key,.value=value};return object_run(e,&r);
}
int hd2env_object_release(HD2Environment *e,HD2Object *o) {
    if(!o)return HD2_OBJECT_FAILURE;
    ObjectRequest r={.kind=OBJ_RELEASE,.object=*o,.out=o};return object_run(e,&r);
}
int hd2env_object_compile(HD2Environment *e,const char *source,size_t size,const char *name,HD2ObjectResults *out) {
    if(!source||!name||!out)return HD2_OBJECT_FAILURE;
    ObjectRequest r={.kind=OBJ_COMPILE,.source=source,.size=size,.name=name,.results=out};return object_run(e,&r);
}
int hd2env_object_call(HD2Environment *e,HD2Object o,const HD2Object *args,size_t count,HD2ObjectResults *out) {
    if(!out||count>INT_MAX-8||(count&&!args))return HD2_OBJECT_FAILURE;
    ObjectRequest r={.kind=OBJ_CALL,.object=o,.args=args,.count=count,.results=out};return object_run(e,&r);
}
int hd2env_objects_free(HD2Environment *e,HD2ObjectResults *out) {
    if(!out||(!out->values&&out->count))return HD2_OBJECT_FAILURE;
    if(e&&out->count){
        ObjectRequest r={.kind=OBJ_FREE,.results=out};
        int status=object_run(e,&r);if(status!=HD2_OBJECT_SUCCESS)return status;
    }
    free(out->values);memset(out,0,sizeof(*out));return HD2_OBJECT_SUCCESS;
}
size_t hd2env_object_count(const HD2Environment *e) {
    return e&&same_thread(e->thread)?(e->objects?e->objects->count:0):SIZE_MAX;
}
