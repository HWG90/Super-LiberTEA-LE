/* Exercise the public native-to-Lua boundary, including copied result lifetime.
 * The final result is deliberately retained until after lua_close. */
#include "environment.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void check(int value,const char *what,HD2Environment *e) {
    if(!value){fprintf(stderr,"native entry %s: %s\n",what,hd2env_error(e));exit(10);}
    if(hd2env_stack_depth(e)!=0){fprintf(stderr,"native entry stack imbalance\n");exit(10);}
}
HD2Results check_native_entry(HD2Environment *e) {
    static const char check_only[]="error('syntax probe must never execute')";
    check(hd2env_check(e,check_only,sizeof(check_only)-1,"@compile-only"),"compile without execution",e);
    check(!hd2env_check(e,"local =",7,"@bad-source"),"syntax error",e);
    check(!hd2env_check(e,"\x1b" "Lua-invalid",12,"@foreign-bytecode"),"unknown PUC refused",e);
    static const char source[]=
        "function poc_native_echo(...) assert(select('#',...)==6);return ... end\n"
        "function poc_native_bad()return 'partially copied',{} end\n"
        "function poc_native_error()error({native=true})end\n"
        "function poc_native_many()local t={};for i=1,65 do t[i]=i end;return unpack(t)end\n"
        "function poc_native_gc()collectgarbage('collect');return stingray.Application.platform()end\n";
    check(hd2env_eval(e,source,sizeof(source)-1,"@native-entry-tests"),"definitions",e);
    unsigned char marker;const char text[]={'a',0,'z'};
    HD2Value args[]={
        {.type=HD2_VALUE_NUMBER,.as.number=-42.5},
        {.type=HD2_VALUE_NIL},
        {.type=HD2_VALUE_BOOLEAN,.as.boolean=0},
        {.type=HD2_VALUE_STRING,.as.string={text,sizeof(text)}},
        {.type=HD2_VALUE_POINTER,.as.pointer=(uintptr_t)&marker},
        {.type=HD2_VALUE_NIL},
    };
    HD2Results out={0},bad={0};
    check(hd2env_invoke(e,"poc_native_echo",args,6,&out),"roundtrip",e);
    check(out.count==6&&out.values[0].type==HD2_VALUE_NUMBER&&out.values[0].as.number==-42.5
          &&out.values[1].type==HD2_VALUE_NIL&&out.values[2].type==HD2_VALUE_BOOLEAN
          &&out.values[2].as.boolean==0&&out.values[3].type==HD2_VALUE_STRING
          &&out.values[3].as.string.size==3&&!memcmp(out.values[3].as.string.bytes,text,3)
          &&out.values[4].type==HD2_VALUE_POINTER&&out.values[4].as.pointer==(uintptr_t)&marker
          &&out.values[5].type==HD2_VALUE_NIL,"typed values",e);
    check(!hd2env_invoke(e,"poc_native_echo",args,6,&out)&&out.count==6,"nonempty output refused",e);
    check(!hd2env_invoke(e,"poc_native_bad",NULL,0,&bad)&&!bad.values&&!bad.count,"partial copy cleanup",e);
    check(strstr(hd2env_error(e),"unsupported native result type: table")!=NULL,"unsupported result",e);
    check(!hd2env_invoke(e,"poc_native_many",NULL,0,&bad)&&!bad.values&&!bad.count,"result limit",e);
    check(!hd2env_invoke(e,"poc_native_error",NULL,0,&bad)&&!bad.values&&!bad.count,"Lua error",e);
    check(!strcmp(hd2env_error(e),"non-string Lua error"),"non-string error",e);
    check(!hd2env_invoke(e,"poc_native_absent",NULL,0,&bad),"missing callback",e);
    check(!hd2env_invoke(e,"poc_native_echo",args,65,&bad),"argument limit",e);
    HD2Value invalid={.type=HD2_VALUE_STRING,.as.string={NULL,1}};
    check(!hd2env_invoke(e,"poc_native_echo",&invalid,1,&bad),"invalid argument",e);
    check(hd2env_invoke(e,"poc_native_gc",NULL,0,&bad),"native callback and GC",e);
    check(bad.count==1&&bad.values[0].type==HD2_VALUE_STRING&&
          !strcmp(bad.values[0].as.string.bytes,"win32"),"callback result",e);
    hd2env_results_free(&bad);hd2env_results_free(&bad);
    check(!memcmp(out.values[3].as.string.bytes,text,3),"string survives collection",e);
    check(hd2env_invoke(e,"poc_native_echo",args,6,NULL),"discard results",e);
    return out;
}
void check_native_result_after_close(HD2Results *out) {
    if(out->count!=6||out->values[3].as.string.size!=3||memcmp(out->values[3].as.string.bytes,"a\0z",3)){
        fprintf(stderr,"native result lifetime failed\n");exit(10);
    }
    hd2env_results_free(out);
    puts("POC_ENTRY typed_arguments=pass results=pass binary_strings=pass errors=pass gc_lifetime=pass close_lifetime=pass");
}
