-- The reinforcement weapon record holds an item ID followed by ten category/part ID pairs
-- in two parallel arrays. Entity spawning instead needs the parts' 64-bit ADD hashes.
local M={}
local EMPTY=0xFFFFFFFF
local function word(s,off)
    local a,b,c,d=s:byte(off+1,off+4)
    return a+b*256+c*65536+d*16777216
end
local function le(v)
    return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216))
end
function M.new(data)
    local self={categories={'Underbarrel','Optics','Paint','Muzzle','Magazine','Ammo type','Alternate ammo','Internals','Trigger'}}
    local menus={}
    function self:menu(weapon,category)
        local groups=data.weapons[weapon]
        local ids=groups and groups[category]
        -- Fixed parts still belong in the native weapon record, but have no menu.
        if not ids or #ids<2 then return end
        if not menus[ids] then
            local factory=data.parts[ids[1]]
            local labels={factory and ('Factory ('..factory.name..')') or 'Factory'}
            for i=2,#ids do
                local part=data.parts[ids[i]]
                labels[i]=part.variant or part.name
            end
            menus[ids]={ids=ids,labels=labels,label=(factory and factory.slot_label) or self.categories[category]}
        end
        return menus[ids]
    end
    function self:display(menu,id)
        if id==0 then return menu.labels,1 end
        for i,value in ipairs(menu.ids) do if value==id then return menu.labels,i end end
        if menu.extra_id~=id then
            local labels={unpack(menu.labels)}
            labels[#labels+1]=data.parts[id] and data.parts[id].name or ('Attachment '..id)
            menu.extra_id,menu.extra_labels=id,labels
        end
        return menu.extra_labels,#menu.extra_labels
    end
    function self:selected(record,weapon,category)
        if word(record,0)~=weapon then return 0 end
        for i=0,9 do
            if word(record,4+i*4)==category then return word(record,0x2C+i*4) end
        end
        return 0
    end
    function self:factory(weapon)
        local categories,values={},{}
        local groups=data.weapons[weapon]
        for c=0,9 do
            categories[c+1]=le(groups and next(groups) and c or EMPTY)
            values[c+1]=le(groups and groups[c] and groups[c][1] or 0)
        end
        return le(weapon)..table.concat(categories)..table.concat(values)
    end
    function self:edit(record,weapon,category,id)
        local menu=assert(self:menu(weapon,category),'No attachment slot for this weapon')
        local valid=false
        for _,option in ipairs(menu.ids) do if option==id then valid=true;break end end
        assert(valid,'Attachment does not fit this primary')
        if word(record,0)~=weapon then record=self:factory(weapon) end
        local at,unused
        for i=0,9 do
            local c=word(record,4+i*4)
            if c==category then assert(not at,'Duplicate attachment slot');at=i end
            if c==EMPTY and not unused then unused=i end
        end
        at=assert(at or unused,'No space for this attachment')
        local a,b=4+at*4,0x2C+at*4
        return record:sub(1,a)..le(category)..record:sub(a+5,b)..le(id)..record:sub(b+5)
    end
    function self:spawn_parts(record)
        local overrides,packages,seen={},{},{}
        for i=0,9 do
            local c,id=word(record,4+i*4),word(record,0x2C+i*4)
            if id~=0 then
                local part=assert(data.parts[id],'Unrecognized equipped attachment')
                assert(c==part.category and not overrides[c],'Equipped attachment layout changed')
                overrides[c]=part.modifier
                if part.package and not seen[part.package] then
                    packages[#packages+1]=part.package;seen[part.package]=true
                end
            end
        end
        return overrides,packages
    end
    return self
end
return M
