if jit then jit.off(true,true) end
local original=assert(POC.original('core/wwise/lua/wwise_bank_reference'))
local make=assert(loadstring(original,'@embedded_stock'))
local refs=make()
refs:add('test');assert(refs:count('test')==1)
local denied,message=loadstring(original,'@text_only','t')
assert(denied==nil and message:find('mode',1,true))
denied,message=loadstring(original:sub(1,-2)..'!', '@changed_chunk')
assert(denied==nil and message:find('translation',1,true))

local cursor=1
make=assert(load(function()
    if cursor>#original then return nil end
    local part=original:sub(cursor,cursor+6);cursor=cursor+7;return part
end,'@fragmented_bytecode','b'))
assert(type(make())=='table')
denied,message=load(function()error('reader failed')end)
assert(denied==nil and tostring(message):find('reader failed',1,true))
denied=load(function()return {}end);assert(denied==nil)

local scope=setmetatable({ANIM_REQUIRES=false},{__index=_G})
assert(loadstring(POC.original('stock/animation_requires'),'@embedded_require','b',scope))()
assert(rawget(scope,'ANIM_REQUIRES')==true)
local dumped=string.dump(function(a)return a*3+1 end)
assert(assert(loadstring(dumped))(4)==13)
if jit then
    assert(not require('ffi').abi('gc64'),'original mod frame layout requires non-GC64')
    assert(dumped:byte(5)%16<8,'native bytecode unexpectedly uses FR2')
end

-- Both loadfile and require must recover embedded PUC chunks without an edit
-- to the caller, including a split-reader load path above.
local filename=os.tmpname()
local oldpath=package.path
local ok,err=pcall(function()
    local file=assert(io.open(filename,'wb'));assert(file:write(original));assert(file:close())
    assert(type(assert(loadfile(filename))())=='table')
    package.path=filename
    assert(type(require('__hd2_puc_module_proof'))=='table')
end)
package.path=oldpath;package.loaded.__hd2_puc_module_proof=nil
assert(os.remove(filename));assert(ok,err)
print('POC_LOADERS embedded=pass reader=pass file=pass require=pass mode=pass unknown_puc_refused=true')
