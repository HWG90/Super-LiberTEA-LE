/* Protected public-API translation of the traced native dynamic-config loop.
 * Memory is read only through the host reader. Names are C strings, as in the
 * original loop; the stored name count only distinguishes the empty name.
 * Caps reject malformed inputs rather than scanning unbounded native memory. */
static void boot_read(lua_State *L,HD2Environment *e,uintptr_t base,size_t offset,void *out,size_t size){
    if(!base||offset>UINTPTR_MAX-base||size>UINTPTR_MAX-(base+offset)||
       e->boot_callbacks.read_native(e->boot_callbacks.context,base+offset,out,size)!=1)
        luaL_error(L,"native boot memory read refused");
}
static void boot_string(lua_State *L,HD2Environment *e,uintptr_t address){
    luaL_Buffer buffer;luaL_buffinit(L,&buffer);
    for(size_t i=0;i<65536;i++){
        char c;boot_read(L,e,address,i,&c,1);
        if(!c){luaL_pushresult(&buffer);return;}
        luaL_addchar(&buffer,c);
    }
    luaL_error(L,"native boot name exceeds 65535 bytes");
}
static int boot_config_operation(lua_State *L,HD2Environment *e){
    uint32_t tag,count;uintptr_t object,rows;
    boot_read(L,e,e->boot_data,0,&tag,4);
    if((tag&7)!=6)return 0;
    boot_read(L,e,e->boot_data,0x10,&object,8);
    boot_read(L,e,object,0,&count,4);
    if(count>1048576)return luaL_error(L,"native boot config exceeds row limit");
    if(!count)return 0;
    boot_read(L,e,object,8,&rows,8);
    for(uint32_t i=0;i<count;i++){
        size_t offset=(size_t)i*0x38;int32_t marker;
        boot_read(L,e,rows,offset+0x30,&marker,4);
        if(marker<0)continue;
        boot_read(L,e,rows,offset+0x18,&tag,4);tag&=7;
        if(tag!=1&&tag!=2)continue;
        uint32_t name_count;boot_read(L,e,rows,offset,&name_count,4);
        if(name_count<=1)lua_pushliteral(L,"");
        else {uintptr_t name;boot_read(L,e,rows,offset+8,&name,8);boot_string(L,e,name);}
        if(tag==1){unsigned char boolean;boot_read(L,e,rows,offset+0x20,&boolean,1);lua_pushboolean(L,boolean!=0);}
        else {double number;boot_read(L,e,rows,offset+0x20,&number,8);lua_pushnumber(L,(double)(float)number);}
        lua_settable(L,LUA_GLOBALSINDEX);
    }
    return 0;
}
static int boot_start_operation(lua_State *L,HD2Environment *e){
    if(!e->boot_data)return luaL_error(L,"native boot_script is missing");
    lua_getglobal(L,"require");boot_string(L,e,e->boot_data);lua_call(L,1,0);
    lua_getglobal(L,"init");
    if(!lua_isfunction(L,-1))return luaL_error(L,"missing global callback: init");
    lua_call(L,0,0);return 0;
}
