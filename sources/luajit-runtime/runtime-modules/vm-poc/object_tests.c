/* Native object ownership, metamethod, error and cross-state integration tests.
 * No engine memory or private Lua layout is inspected. */
#include "environment.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static void check(HD2Environment *e,int ok,const char *message) {
    if(!ok||hd2env_stack_depth(e)!=0){
        fprintf(stderr,"object test %s: %s\n",message,hd2env_error(e));exit(11);
    }
}
static HD2Object scalar(HD2Environment *e,HD2Value value) {
    HD2Object out={0};check(e,hd2env_object_from_value(e,&value,&out)==1,"create scalar");return out;
}
static HD2Object text(HD2Environment *e,const char *s) {
    return scalar(e,(HD2Value){.type=HD2_VALUE_STRING,.as.string={s,strlen(s)}});
}
static double number(HD2Environment *e,HD2Object o) {
    HD2Results out={0};check(e,hd2env_object_read(e,o,&out)==1,"read number");
    check(e,out.count==1&&out.values[0].type==HD2_VALUE_NUMBER,"number type");
    double n=out.values[0].as.number;hd2env_results_free(&out);return n;
}
static void release(HD2Environment *e,HD2Object *o) {
    check(e,hd2env_object_release(e,o)==1&&!o->identity&&!o->environment,"release and clear");
}
static void eval(HD2Environment *e,const char *s) {
    check(e,hd2env_eval(e,s,strlen(s),"@object-tests")==1,"evaluate");
}
static HD2ObjectResults compile(HD2Environment *e,const char *s) {
    HD2ObjectResults out={0};check(e,hd2env_object_compile(e,s,strlen(s),"@object-test-chunk",&out)==1,"compile");
    check(e,out.count==1&&!out.is_error,"compiled closure");return out;
}
void check_objects(HD2Environment *e,const HD2Asset *assets,size_t count,const HD2Backend *backend) {
    check(e,hd2env_object_count(e)==0,"initial ownership");
    HD2ObjectResults chunk=compile(e,
        "local u=newproxy(true);getmetatable(u).__gc=function()OBJECT_FINALIZERS=(OBJECT_FINALIZERS or 0)+1 end\n"
        "local t={value=7};t.self=t\n"
        "setmetatable(t,{__index=function(_,k)if k=='computed' then return 21 end;error({key=k})end,\n"
        "__newindex=function(_,k,v)if k=='virtual' then rawset(t,'value',v)else error('set refused')end end})\n"
        "local f=function(...)assert(select('#',...)==3);local n,v,z=...;assert(v==u and z==nil);t.value=t.value+n;return t,u,nil end\n"
        "return t,f,nil,u,coroutine.create(function()return t end),jit and require('ffi').new('int[1]',42) or false");
    HD2ObjectResults values={0};
    check(e,hd2env_object_call(e,chunk.values[0],NULL,0,&values)==1,"execute owned chunk");
    check(e,values.count==6&&!values.is_error,"six arbitrary values");
    HD2ObjectKind kind;
    HD2ObjectKind kinds[]={HD2_OBJECT_TABLE,HD2_OBJECT_FUNCTION,HD2_OBJECT_NIL,HD2_OBJECT_USERDATA,HD2_OBJECT_THREAD};
    for(size_t i=0;i<5;i++)check(e,hd2env_object_type(e,values.values[i],&kind)==1&&kind==kinds[i],"owned type");
    check(e,hd2env_objects_free(e,&chunk)==1,"release compiled closure");
    eval(e,"collectgarbage('collect');assert(OBJECT_FINALIZERS==nil)");
    HD2Object key=text(e,"value"),result={0};
    check(e,hd2env_object_get(e,values.values[0],key,&result)==1&&number(e,result)==7,"table lookup");
    HD2Object stale=result;release(e,&result);
    check(e,hd2env_object_type(e,stale,&kind)==-1,"stale identity refused");
    HD2Object another=scalar(e,(HD2Value){.type=HD2_VALUE_NUMBER,.as.number=123});
    check(e,another.identity!=stale.identity&&hd2env_object_type(e,stale,&kind)==-1,"reused registry slot does not revive identity");
    release(e,&another);
    HD2Object computed=text(e,"computed");
    check(e,hd2env_object_get(e,values.values[0],computed,&result)==1&&number(e,result)==21,"index metamethod");
    release(e,&result);release(e,&computed);
    HD2Object virtual_key=text(e,"virtual"),n=scalar(e,(HD2Value){.type=HD2_VALUE_NUMBER,.as.number=10});
    check(e,hd2env_object_set(e,values.values[0],virtual_key,n)==1,"newindex metamethod");
    HD2Object args[]={n,values.values[3],values.values[2]};HD2ObjectResults called={0};
    check(e,hd2env_object_call(e,values.values[1],args,3,&called)==1&&called.count==3,"owned arguments/trailing nil");
    check(e,hd2env_object_get(e,called.values[0],key,&result)==1&&number(e,result)==20,"table identity across call");
    release(e,&result);
    HD2Object clone={0};check(e,hd2env_object_clone(e,called.values[0],&clone)==1,"independent ownership");
    check(e,hd2env_objects_free(e,&called)==1,"release call results");
    check(e,hd2env_object_get(e,clone,key,&result)==1&&number(e,result)==20,"clone survives original release");
    release(e,&result);
    size_t held=hd2env_object_count(e);
    HD2Object absent=text(e,"absent");
    for(int i=0;i<20;i++)check(e,hd2env_object_get(e,clone,absent,&result)==-1&&!result.identity,"metamethod error recovery");
    check(e,hd2env_object_count(e)==held+1,"failed lookup ownership balance");
    release(e,&absent);
    HD2Results non_scalar={0};check(e,hd2env_object_read(e,clone,&non_scalar)==-1&&!non_scalar.values,"object not converted to pointer");
    HD2ObjectResults error_chunk=compile(e,"local t={reason='kept',code=73};error(t)");
    HD2ObjectResults error={0};
    check(e,hd2env_object_call(e,error_chunk.values[0],NULL,0,&error)==0&&error.is_error&&error.count==1,"retained non-string error");
    check(e,!strcmp(hd2env_error(e),"non-string Lua error"),"error diagnostic");
    check(e,hd2env_object_type(e,error.values[0],&kind)==1&&kind==HD2_OBJECT_TABLE,"actual error table retained");
    HD2Object code=text(e,"code");
    check(e,hd2env_object_get(e,error.values[0],code,&result)==1&&number(e,result)==73,"error inspection");
    release(e,&result);release(e,&code);
    check(e,hd2env_objects_free(e,&error)==1&&hd2env_objects_free(e,&error_chunk)==1,"error ownership cleanup");
    HD2ObjectResults bad={0};
    check(e,hd2env_object_compile(e,"local =",7,"@syntax-error",&bad)==0&&bad.is_error&&bad.count==1,"retained syntax error");
    check(e,hd2env_objects_free(e,&bad)==1,"syntax error cleanup");
    HD2ObjectResults many=compile(e,"local a={};for i=1,65 do a[i]={}end;return unpack(a)");
    size_t before=hd2env_object_count(e);
    check(e,hd2env_object_call(e,many.values[0],NULL,0,&bad)==1&&bad.count==65,"many results preserved");
    check(e,hd2env_object_count(e)==before+65,"many results owned");
    check(e,hd2env_objects_free(e,&bad)==1&&hd2env_objects_free(e,&many)==1,"many results cleanup");
    many=compile(e,"return select('#',...),select(65,...)");
    HD2Object many_args[65];for(size_t i=0;i<65;i++)many_args[i]=values.values[2];many_args[64]=n;
    check(e,hd2env_object_call(e,many.values[0],many_args,65,&bad)==1&&bad.count==2,"many arguments");
    check(e,number(e,bad.values[0])==65&&number(e,bad.values[1])==10,"last argument preserved");
    check(e,hd2env_objects_free(e,&bad)==1&&hd2env_objects_free(e,&many)==1,"many arguments cleanup");
    /* Preserve the exact userdata/cdata identity when it passes back into Lua. */
    HD2ObjectResults identity=compile(e,"return function(a,b) assert(rawequal(a,b)); if type(a)=='cdata' then assert(a[0]==42) end end");
    HD2ObjectResults identity_fn={0};
    check(e,hd2env_object_call(e,identity.values[0],NULL,0,&identity_fn)==1,"identity function");
    for(size_t i=0;i<values.count;i++){
        HD2Object pair[]={values.values[i],values.values[i]};
        check(e,hd2env_object_call(e,identity_fn.values[0],pair,2,&bad)==1&&bad.count==0,"exact Lua identity roundtrip");
    }
    check(e,hd2env_objects_free(e,&identity_fn)==1&&hd2env_objects_free(e,&identity)==1,"identity closure cleanup");
    char message[2048];HD2Environment *other=hd2env_create(assets,count,backend,message,sizeof(message));
    check(e,other!=NULL,"second environment created");
    HD2Object foreign=text(other,"foreign");HD2Object old_foreign=foreign;
    check(e,hd2env_object_type(e,foreign,&kind)==-1,"cross-environment use refused");
    check(other,hd2env_object_type(other,clone,&kind)==-1,"reverse cross-environment use refused");
    HD2ObjectResults after_close=compile(other,"return {alive=true}");
    check(e,hd2env_destroy(other)==1,"second environment destroyed");
    check(e,hd2env_objects_free(NULL,&after_close)==1&&!after_close.values&&!after_close.count,"array disposal after environment destruction");
    other=hd2env_create(assets,count,backend,message,sizeof(message));
    check(e,other!=NULL,"replacement environment created");
    foreign=text(other,"new");
    check(other,foreign.environment!=old_foreign.environment&&hd2env_object_type(other,old_foreign,&kind)==-1,"destroyed environment identity not reused");
    release(other,&foreign);check(e,hd2env_destroy(other)==1,"replacement environment destroyed");
    release(e,&clone);release(e,&key);release(e,&virtual_key);release(e,&n);
    check(e,hd2env_objects_free(e,&values)==1&&hd2env_object_count(e)==0,"all owned values released");
    eval(e,"collectgarbage('collect');collectgarbage('collect');assert(OBJECT_FINALIZERS==1)");
    const HD2Asset *stock=NULL;
    for(size_t i=0;i<count;i++)if(!strcmp(assets[i].name,"stock/animation_requires")){stock=assets+i;break;}
    check(e,stock&&stock->original_puc,"stock bytecode asset present");
    check(e,hd2env_object_compile(e,(const char *)stock->original_puc,stock->original_size,
                                "@owned-stock-bytecode",&chunk)==1,"owned stock translation");
    check(e,hd2env_object_call(e,chunk.values[0],NULL,0,&values)==1,"execute owned stock closure");
    check(e,hd2env_objects_free(e,&values)==1&&hd2env_objects_free(e,&chunk)==1,"owned stock cleanup");
    eval(e,"assert(ANIM_REQUIRES==true)");
    chunk=compile(e,"return stingray.Wwise.wwise_world(42),stingray.WwiseWorld.enabled");
    check(e,hd2env_object_call(e,chunk.values[0],NULL,0,&values)==1&&values.count==2,"retain adapter userdata and C function");
    check(e,hd2env_object_call(e,values.values[1],values.values,1,&called)==1&&called.count==1,"owned native callback");
    HD2Results enabled={0};
    check(e,hd2env_object_read(e,called.values[0],&enabled)==1&&enabled.count==1&&
          enabled.values[0].type==HD2_VALUE_BOOLEAN&&enabled.values[0].as.boolean,"native callback result");
    hd2env_results_free(&enabled);
    check(e,hd2env_objects_free(e,&called)==1,"native result cleanup");
    HD2Object wrong=scalar(e,(HD2Value){.type=HD2_VALUE_NIL});
    check(e,hd2env_object_call(e,values.values[1],&wrong,1,&called)==0&&called.is_error,"native userdata rejection preserved");
    release(e,&wrong);
    check(e,hd2env_objects_free(e,&called)==1&&hd2env_objects_free(e,&values)==1&&
          hd2env_objects_free(e,&chunk)==1,"native ownership cleanup");
    check(e,hd2env_object_count(e)==0,"no surviving object ownership");
    puts("POC_OBJECTS ownership=pass identity=pass metamethods=pass errors=pass collection=pass stale=pass foreign=pass");
}
