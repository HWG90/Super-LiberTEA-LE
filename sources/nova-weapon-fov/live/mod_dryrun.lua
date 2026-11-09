-- Nova weapon FOV, build 26251122: read-only dry run of the staged mod's src/nova.lua against the
-- live game. Its io reads through LLtM, refuses every write, and reports each Nova row it finds
-- with whether its terms are vanilla, patched or something else.
local dir='Z:/home/goose/Projects/Linux HD2 Mods/.claude/worktrees/transmog-armor-equip-bug-c59577/builds/26251122/mods/nova-weapon-fov/stage/goose_nova_weapon_fov/'
local f=assert(io.open(dir..'src/nova.lua','rb'));local src=f:read('*a');f:close()
local Nova=assert(loadstring(src,'@nova.lua'))()
local adapter={}
function adapter:read(address,size) return read(address,size) end
function adapter:write() return false,'dry run: writes refused' end
function adapter:module(name)
 local pe=u32(game+0x3C)
 return game,u32(game+pe+0x50),u32(game+pe+8)
end
local n=Nova.new(adapter)
local ok,rows=pcall(n.rows,n)
if not ok then out('rows failed:',rows) return false end
out('Nova rows found',#rows)
for _,r in ipairs(rows) do
 local t=read(r+0x13C,20)
 out(fmt('row 0x%X terms %s',r,t==Nova.VANILLA and 'vanilla' or t==Nova.PATCH and 'patched' or ('other '..hex(t))))
end
local ok2,why=pcall(n.apply,n)
out('apply with refused writes:',ok2 and ('wrote '..tostring(why)) or tostring(why))
return #rows
