local Render=dofile(NATIVE_ADS_TEST_ROOT..'/src/first_person/fird_render.lua')
local cases=0
local function pass()cases=cases+1 end
local function fixture(bridged)
    local f={calls=0,native=0,other=0,logs={},active=true,foreign=false,order={}}
    local globals={}
    local function original(...)
        f.native=f.native+1;f.order[#f.order+1]='native'
        if f.native_error then error(f.native_error,0)end
        return select('#',...),nil,...
    end
    globals.render=original;f.original=original;f.globals=globals
    if bridged then
        local entries,ordered={},{};local bridge={api=1,errors={}}
        local function rebuild()
            ordered={};for id,entry in pairs(entries)do ordered[#ordered+1]={id,entry}end
            table.sort(ordered,function(a,b)return a[1]<b[1]end)
        end
        bridge.subscribe=function(id,callback)
            f.subscribes=(f.subscribes or 0)+1
            local entry={callback=callback};entries[id]=entry;rebuild()
            f.retained=callback
            if f.subscribe_during then callback('during install')end
            if f.subscribe_error then error('subscription uncertain')end
            if f.subscribe_missing then return nil end
            return function()
                f.unsubscribes=(f.unsubscribes or 0)+1
                if f.unsubscribe_error then error('unsubscribe failed')end
                if f.unsubscribe_pending then return false end
                if entries[id]==entry then entries[id]=nil;rebuild()end
            end
        end
        globals.HUDRenderBridge=bridge
        globals.render=function(...)
            local frame=ordered
            for _,item in ipairs(frame)do
                local id,entry=item[1],item[2]
                if entries[id]==entry then
                    local ok,why=pcall(entry.callback,...)
                    if not ok then entries[id]=nil;bridge.errors[id]=tostring(why);rebuild()end
                end
            end
            return original(...)
        end
        bridge.subscribe('other',function()f.other=f.other+1;f.order[#f.order+1]='other'end)
        f.subscribes=0;f.dispatch=globals.render;f.bridge=bridge
    end
    local callback=function(...)
        f.calls=f.calls+1;f.order[#f.order+1]='pose';f.args={n=select('#',...),...}
        if f.during then f.during()end
        if f.callback_error then error(f.callback_error,0)end
        if f.callback_refuse then return false,'placement refused'end
        return true
    end
    f.deps={active=function()if f.gate_error then error('active gate failed')end;return f.active end,
        foreign=function()if f.foreign_error then error('foreign gate failed')end;return f.foreign end}
    f.r=Render.new(globals,callback,function(message)f.logs[#f.logs+1]=message;if f.log_error then error('log failed')end end,f.deps)
    return f
end
for _,bridged in ipairs({true,false})do
    local f=fixture(bridged);assert(f.r:is_clean()and f.r:start())
    local a,b,c,d,e=f.globals.render(10,nil,30)
    assert(a==3 and b==nil and c==10 and d==nil and e==30 and f.calls==1 and f.native==1)
    assert(f.args.n==3 and f.args[1]==10 and f.args[2]==nil and f.args[3]==30)
    assert(f.order[1]=='pose'and f.order[#f.order]=='native')
    assert(f.r:result().source==(bridged and'bridge'or'wrapper')and f.r:result().frames==1)
    assert(f.r:start());f.globals.render();assert(f.calls==2 and f.r:result().frames==2)
    if bridged then assert(f.subscribes==1 and f.other==2 and f.globals.render==f.dispatch)end
    assert(f.r:stop()and f.r:is_clean()and f.r:stop());f.globals.render();assert(f.calls==2 and f.native==3)
    if bridged then assert(f.other==3 and f.unsubscribes==1)else assert(f.globals.render==f.original)end
    pass()

    f=fixture(bridged);assert(f.r:start());f.active=false;f.globals.render();f.active=true;f.foreign=true;f.globals.render()
    f.foreign=nil;f.globals.render();assert(f.calls==0 and f.native==3 and f.r:result().skipped==3)
    f.foreign=false;f.globals.render();assert(f.calls==1);assert(f.r:stop());pass()

    f=fixture(bridged);assert(f.r:start());f.during=function()f.during=nil;f.globals.render('nested')end
    f.globals.render('outer');assert(f.calls==1 and f.native==2 and f.r:result().reentrant==1)
    assert(f.args[1]=='outer'and f.r:stop());pass()

    f=fixture(bridged);assert(f.r:start());f.callback_error='pose sentinel';f.globals.render()
    assert(f.calls==1 and f.native==1 and f.r:is_clean()and not f.r:result().active)
    assert(f.r:result().errors==1 and f.r:result().last_error=='pose sentinel'and #f.logs==1)
    f.globals.render();assert(f.calls==1 and f.native==2)
    if bridged then assert(f.other==2 and next(f.bridge.errors)==nil)end
    pass()

    f=fixture(bridged);assert(f.r:start());f.callback_refuse=true;f.globals.render()
    assert(f.r:is_clean()and f.r:result().reason=='placement refused'and f.native==1);pass()

    f=fixture(bridged);assert(f.r:start());f.gate_error=true;f.globals.render()
    assert(f.calls==0 and f.native==1 and f.r:is_clean()and f.r:result().errors==1);pass()

    f=fixture(bridged);assert(f.r:start());f.foreign_error=true;f.log_error=true;f.globals.render()
    assert(f.calls==0 and f.native==1 and f.r:is_clean()and f.r:result().errors==1);pass()

    f=fixture(bridged);assert(f.r:start());local sentinel={native='error'};f.native_error=sentinel
    local ok,why=pcall(f.globals.render);assert(not ok and why==sentinel and f.calls==1)
    assert(f.r:result().errors==0 and f.r:stop());pass()

    f=fixture(bridged);assert(f.r:start());f.during=function()assert(f.r:stop());f.during=nil end
    f.globals.render();assert(f.calls==1 and f.native==1 and f.r:is_clean());pass()
end
local f=fixture(false);assert(f.r:start());local retained=f.globals.render
local foreign=function(...)return retained(...)end;f.globals.render=foreign
assert(f.r:stop()and f.globals.render==foreign and f.r:is_clean());f.globals.render();assert(f.calls==0)
assert(f.r:start());f.globals.render();assert(f.calls==1 and f.native==2)
assert(f.r:stop()and f.globals.render==foreign);f.globals.render();assert(f.calls==1 and f.native==3);pass()
f=fixture(true);assert(f.r:start());local retained_bridge=f.retained
f.globals.HUDRenderBridge={api=1,subscribe=function()error('Replacement must never be subscribed')end}
f.globals.render();assert(f.calls==0 and f.r:is_clean()and f.other==1 and f.r:result().errors==1)
retained_bridge();assert(f.calls==0);pass()
f=fixture(true);assert(f.r:start());f.bridge.subscribe=function()error('Replacement subscriber must never be called')end
f.globals.render();assert(f.calls==0 and f.other==1 and f.r:is_clean());pass()
f=fixture(true);f.subscribe_during=true;assert(f.r:start());assert(f.calls==0)
f.globals.render();assert(f.calls==1 and f.r:stop());pass()
for _,key in ipairs({'subscribe_error','subscribe_missing'})do
    f=fixture(true);f[key]=true;assert(not f.r:start()and f.r:is_clean())
    f.retained();f.globals.render();assert(f.calls==0 and f.native==1 and f.other==1);pass()
end
for _,key in ipairs({'unsubscribe_error','unsubscribe_pending'})do
    f=fixture(true);assert(f.r:start());f[key]=true;assert(not f.r:stop()and not f.r:is_clean())
    assert(not f.r:start());f.globals.render();assert(f.calls==0 and f.other==1)
    f[key]=false;assert(f.r:stop()and f.r:is_clean()and f.unsubscribes==2);pass()
end
f=fixture(true);assert(f.r:start());f.unsubscribe_error=true;f.callback_error='pose sentinel';f.globals.render()
assert(not f.r:is_clean()and f.r:result().phase=='cleanup pending'and f.other==1 and f.native==1)
f.globals.render();assert(f.calls==1 and f.other==2);f.unsubscribe_error=false;assert(f.r:stop());pass()
f=fixture(false);f.globals.HUDRenderBridge={api=2,subscribe=function()error('Unsupported API')end}
assert(not f.r:start()and f.r:is_clean()and f.globals.render==f.original);pass()
f=fixture(false);f.globals.render=nil;assert(not f.r:start()and f.r:is_clean());pass()
f=fixture(true);f.globals.render=nil;assert(not f.r:start()and f.r:is_clean()and f.subscribes==0);pass()
f=fixture(true);local second=Render.new(f.globals,function()f.second=(f.second or 0)+1 end,function()end,f.deps)
assert(f.r:start()and second:start()and f.subscribes==2);f.globals.render();assert(f.calls==1 and f.second==1 and f.other==1)
assert(f.r:stop());f.globals.render();assert(f.calls==1 and f.second==2 and f.other==2 and second:stop());pass()
print('Fird render boundary: '..cases..' bridge/wrapper ownership, ordering, tuples, errors, gates, reentrancy and tombstone cases passed')
