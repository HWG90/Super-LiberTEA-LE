local M={}
local slots={
    {key='primary', label='Primary', kind=1, index=1},
    {key='secondary', label='Secondary', kind=3, index=2},
    {key='support', label='Support', kind=2, index=3},
    {key='backpack', label='Backpack', kind=6, index=6},
}
for i=1,4 do slots[#slots+1]={key='stratagem_'..i,label='Stratagem '..i,strat=true,index=i} end

function M.new(backend,catalogue)
    local self={message='Open during a solo mission', elapsed=1}
    local menus,names={},{}
    for _,item in ipairs(catalogue.stratagems) do names[item.kind]=item.name end
    for _,slot in ipairs(slots) do
        local menu={items={},names={'Unavailable'},indexes={}}
        for _,item in ipairs(slot.strat and catalogue.stratagems or catalogue.gear) do
            if (slot.strat and item.selectable) or item.kind==slot.kind then menu.items[#menu.items+1]=item end
        end
        table.sort(menu.items,function(a,b)
            if a.name==b.name then return a.id<b.id end
            return a.name<b.name
        end)
        for i,item in ipairs(menu.items) do
            local prev,next_item=menu.items[i-1],menu.items[i+1]
            local duplicate=(prev and prev.name==item.name) or (next_item and next_item.name==item.name)
            menu.names[i+1]=duplicate and (item.name..' ('..tostring(item.id)..')') or item.name
            menu.indexes[slot.strat and item.kind or item.type]=i+1
        end
        menus[slot.key]=menu
    end
    local attachments=backend.attachments
    local primaries={}
    for _,item in ipairs(catalogue.gear) do if item.kind==1 then primaries[item.type]=item end end
    local function primary()
        return self.state and primaries[self.state.gear[1].id]
    end
    local function add_attachments(controls,current,token)
        for category,label in ipairs(attachments.categories) do
            local id='loadout_primary_part_'..category
            controls[#controls+1]={id=id,label=label,column=2,type='choice',presentation='dropdown',
                description='Primary attachment. Reinforcements use this selection.',
                choices={'Factory'},default=1,
                visible_if=function()
                    local item=primary()
                    return item and attachments:menu(item.id,category)~=nil or false
                end,
                enabled_if=function()
                    local item=primary()
                    local menu=item and attachments:menu(item.id,category)
                    return menu~=nil and not self.job
                end,
                on_change=function(value)
                    local item=primary()
                    if self.page_token~=token or not current() or self.job or not item then return end
                    local menu=attachments:menu(item.id,category)
                    local part_id=menu and menu.ids[value]
                    if not part_id then return end
                    local state=self.state
                    self.job={slot=slots[1],item=item,expected=state.gear[1].entity,old_type=item.type,
                        mission=state.mission,owner=state.owner,session=state.session,age=0,
                        category=category,part_id=part_id,weapon_record=state.weapons[1],label=menu.label,
                        selection=menu.labels[value]}
                    self.message='Equipping '..menu.labels[value]
                    self.elapsed=1
                end}
        end
        controls[#controls+1]={type='text',column=2,label='No attachment choices for this primary',
            visible_if=function()
                local item=primary()
                if not item then return false end
                for category=1,#attachments.categories do
                    if attachments:menu(item.id,category) then return false end
                end
                return true
            end}
    end
    local function sync_attachments(record)
        local item=primary()
        local changed=self.display_primary~=(item and item.id)
        self.display_primary=item and item.id
        if not item then return changed end
        for category=1,#attachments.categories do
            local menu=attachments:menu(item.id,category)
            if menu then
                local id='loadout_primary_part_'..category
                local c=record.controls[id]
                local selected=attachments:selected(self.state.weapons[1],item.id,category)
                local labels,index=attachments:display(menu,selected)
                if c and (c.label~=menu.label or c.choices~=labels or record.values[id]~=index) then
                    c.label,c.choices,record.values[id]=menu.label,labels,index
                    changed=true
                end
            end
        end
        return changed
    end
    function self:reset()
        self.state,self.job,self.page_token,self.elapsed=nil,nil,nil,1
        self.message='Open during a solo mission'
    end
    function self:page(current)
        self:reset()
        local token={}
        self.page_token=token
        local controls={}
        for _,slot in ipairs(slots) do
            local menu=menus[slot.key]
            controls[#controls+1]={
                id='loadout_'..slot.key, label=slot.label, type='choice', presentation='dropdown',
                default=1, choices=menu.names,
                enabled_if=function()
                    return not self.job and self.state~=nil and (not slot.strat or self.state.strats[slot.index]~=nil)
                end,
                on_change=function(value)
                    local state,item=self.state,menu.items[value-1]
                    if self.page_token~=token or not current() or not state or self.job or not item then return end
                    local gear,expected
                    if slot.strat then
                        expected=state.strats[slot.index]
                        if expected==nil or expected==item.kind then return end
                    else
                        gear=state.gear[slot.index]
                        if gear.id==item.type then return end
                        expected=gear.entity
                    end
                    self.job={slot=slot,item=item,expected=expected,old_type=gear and gear.id,
                        mission=state.mission,owner=state.owner,session=state.session,age=0}
                    if not slot.strat and slot.index<=2 then self.job.weapon_record=state.weapons[slot.index] end
                    self.message='Equipping '..item.name
                    self.elapsed=1
                end,
            }
            if slot.index==1 and not slot.strat then add_attachments(controls,current,token) end
        end
        controls[#controls+1]={type='text',id='loadout_status',label=self.message}
        return {id='loadout_editor',name='Loadout Editor',require_confirmation=false,controls=controls}
    end
    function self:update(dt,api,record)
        local visible=record and type(api.is_open)=='function' and api.is_open()
        if not visible and not self.job then
            self.state,self.elapsed=nil,1
            return
        end
        dt=math.max(0,math.min(1,tonumber(dt) or 0))
        self.elapsed=self.elapsed+dt
        if self.job then self.job.age=self.job.age+dt end
        if self.elapsed<(self.job and 0.15 or 0.5) then return end
        self.elapsed=0
        local ok,state=pcall(backend.capture,backend)
        local job=self.job
        if not ok then
            self.job,self.state=nil,nil
            self.message=tostring(state):gsub('^.-:%d+: ','')
        else
            if not self.state and not job then self.message='Choose an item to equip it' end
            self.state=state
            if job then
                local done,why
                if not job.swap and job.age>12 then why='Equipment timed out. Select it again to retry.'
                else
                    local called
                    called,done,why=pcall(backend.apply,backend,job,state)
                    if not called then why,done=tostring(done):gsub('^.-:%d+: ',''),nil end
                end
                if done~=false then self.job=nil end
                self.message=done and ((job.label or job.slot.label)..' equipped '..(job.selection or job.item.name)) or (why or 'Loading equipment')
                if done then
                    ok,state=pcall(backend.capture,backend)
                    self.state=ok and state or nil
                end
            end
        end
        if not record then return end
        -- MCM choices are normally preferences. Publish observed values without
        -- invoking their write callbacks or replaying saved dropdown positions.
        local changed=sync_attachments(record)
        for _,slot in ipairs(slots) do
            local id='loadout_'..slot.key
            local c=record.controls[id]
            local state=self.state
            local value,unknown=1,'Unavailable'
            if state then
                local menu=menus[slot.key]
                if slot.strat then
                    local kind=state.strats[slot.index]
                    value=menu.indexes[kind] or 1
                    unknown=kind and (names[kind] or ('Stratagem '..kind)) or 'No equipped slot'
                else
                    local gear=state.gear[slot.index]
                    value=menu.indexes[gear.id] or 1
                    unknown=gear.id and ('Item '..gear.id) or 'Empty'
                end
            end
            if c and (record.values[id]~=value or c.choices[1]~=unknown) then
                record.values[id],c.choices[1]=value,unknown
                changed=true
            end
        end
        for _,page in ipairs(record.pages) do
            if page.id=='loadout_editor' then
                local status=page.controls[#page.controls]
                if status.label~=self.message then status.label=self.message;changed=true end
                break
            end
        end
        if changed then
            if record.handle.refresh_conditions then record.handle.refresh_conditions() end
            api.revision=(api.revision or 0)+1
        end
    end
    return self
end
return M
