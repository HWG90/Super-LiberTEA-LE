-- Read-only bounded presentation history. Store copied scalars, never live
-- snapshots, SDK handles, callback closures or native generation pointers.
local M={}
local fields={time=true,enabled=true,player=true,weapon=true,request=true,camera_kind=true,
    ads=true,foreign=true,editor=true,phase=true,transition_epoch=true,transition_progress=true,
    pinned=true,pin_expected=true,camera_retired=true,view_expected=true,view_visible=true,recovering=true,fov_native=true,fov_applied=true,
    camera_blend=true,pose_blend=true,camera_epoch=true,fov_epoch=true,pose_epoch=true,look_sequence=true,look_samples=true,look_skipped=true,
    cleanup_pending=true,reason=true,policy=true,event=true,
    placement_x=true,placement_y=true,placement_z=true,placement_yaw=true,placement_pitch=true,placement_roll=true,
    motion_x=true,motion_y=true,motion_z=true,look_yaw=true,look_pitch=true,ads_rebases=true,
    -- Why the view is or is not in native first person on this frame.
    control_mask=true,control_guard=true,safe=true,aiming=true,snapshot_reason=true,
    weapon_ready=true,entry_block=true,action=true,softened=true,head_calls=true,camera_gate=true,head_phase=true}
local function scalar(v)
    local t=type(v)
    if t=='boolean'then return v end
    if t=='string'then return v:sub(1,200)end
    if t=='number'and v==v and math.abs(v)<math.huge then return v end
end
local function copy(t)local out={};for k,v in pairs(t)do out[k]=v end;return out end
function M.new(options)
    options=options or{};local cap=options.capacity or 360
    assert(type(cap)=='number'and cap%1==0 and cap>=16 and cap<=4096)
    local self={};local ring={};local head,count=1,0;local previous,last_frame
    local totals={frames=0,duplicate_frames=0,out_of_order_frames=0,events=0,overwritten=0,
        player_changes=0,weapon_changes=0,request_changes=0,camera_changes=0,
        transition_restarts=0,mixed_publication_frames=0,unexpected_view_frames=0,look_duplicates=0,cleanup_frames=0}
    local function insert(row)
        local index=(head+count-1)%cap+1
        if count==cap then index=head;head=head%cap+1;totals.overwritten=totals.overwritten+1
        else count=count+1 end
        ring[index]=row
    end
    local function row_of(frame,sample)
        local row={frame=frame}
        for key in pairs(fields)do row[key]=scalar(sample[key])end
        return row
    end
    function self:record(frame,sample)
        if type(frame)~='number'or frame%1~=0 or frame<1 or type(sample)~='table'then return false end
        if last_frame and frame<=last_frame then
            local key=frame==last_frame and 'duplicate_frames'or'out_of_order_frames'
            totals[key]=totals[key]+1;return false
        end
        local row=row_of(frame,sample);last_frame=frame;totals.frames=totals.frames+1
        if previous then
            for key,counter in pairs({player='player_changes',weapon='weapon_changes',request='request_changes',camera_kind='camera_changes'})do
                if row[key]~=nil and previous[key]~=nil and row[key]~=previous[key]then totals[counter]=totals[counter]+1 end
            end
            if row.transition_epoch and previous.transition_epoch and row.transition_epoch~=previous.transition_epoch
                and (previous.transition_progress or 1)<1 then totals.transition_restarts=totals.transition_restarts+1 end
            if row.look_sequence and previous.look_sequence==row.look_sequence and row.enabled and not row.foreign and not row.editor
                and row.look_samples and previous.look_samples and row.look_samples>previous.look_samples then
                totals.look_duplicates=totals.look_duplicates+1
            end
        end
        if (row.pin_expected==true and row.pinned==false or row.view_expected==true and row.view_visible==false)
            and row.foreign~=true and row.editor~=true and row.recovering~=true then
            totals.unexpected_view_frames=totals.unexpected_view_frames+1
        end
        if row.fov_epoch and row.pose_epoch and row.recovering~=true
            and (row.fov_epoch~=row.pose_epoch or row.camera_epoch and row.camera_epoch~=row.pose_epoch)then
            totals.mixed_publication_frames=totals.mixed_publication_frames+1
        end
        if row.cleanup_pending then totals.cleanup_frames=totals.cleanup_frames+1 end
        insert(row);previous=copy(row);return true
    end
    function self:event(frame,name,sample)
        if type(frame)~='number'or frame%1~=0 or frame<1 or type(name)~='string'then return false end
        local row=row_of(frame,type(sample)=='table'and sample or{});row.event=name:sub(1,64)
        totals.events=totals.events+1;insert(row);return true
    end
    function self:snapshot()
        local rows={};for i=1,count do rows[i]=copy(ring[(head+i-2)%cap+1])end
        return {capacity=cap,count=count,counters=copy(totals),frames=rows}
    end
    function self:clear()
        ring={};head,count=1,0;previous,last_frame=nil,nil
        for key in pairs(totals)do totals[key]=0 end
    end
    return self
end
return M
