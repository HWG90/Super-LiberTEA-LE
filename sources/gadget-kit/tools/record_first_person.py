"""Record NativeADSCameraTest.diagnostics() frames from the running game (read-only, via LLtM).
Usage: record_first_person.py <output folder> <kit folder> <seconds>. Writes recording.tsv and recording-status.log."""
import subprocess,time,sys,re
from pathlib import Path
S=Path(sys.argv[1]);KIT=sys.argv[2];DUR=float(sys.argv[3])
FIELDS=['frame','time','enabled','camera_kind','ads','phase','transition_epoch','transition_progress','view_expected','view_visible','camera_blend','pose_blend','fov_native','fov_applied','placement_x','placement_y','placement_z','placement_yaw','placement_pitch','placement_roll','motion_x','motion_y','motion_z','weapon','request','recovering','cleanup_pending','foreign','editor','camera_epoch','fov_epoch','pose_epoch','control_mask','control_guard','safe','aiming','weapon_ready','action','softened','head_calls','camera_gate','head_phase','snapshot_reason','entry_block','reason']
LUA='''local api=rawget(_G,'NativeADSCameraTest')
if not api then out('X noapi');return end
local d=api.diagnostics();local f=d.frames;local since=%d
local keys={%s}
local function fmt(v)if type(v)=='number'then return string.format('%%.6g',v)end;return tostring(v)end
for i=1,#f do local r=f[i]
 if (r.frame or 0)>since then local t={};for j,k in ipairs(keys)do t[j]=fmt(r[k])end;out('R|'..table.concat(t,'|'))end
end
local c=d.counters or {}
out('C|'..tostring(c.frames)..'|'..tostring(c.transition_restarts)..'|'..tostring(c.unexpected_view_frames)..'|'..tostring(c.weapon_changes)..'|'..tostring(c.camera_changes)..'|'..tostring(c.mixed_publication_frames))
out('S|'..tostring((api.status())))
'''
rows=open(S/'recording.tsv','w');rows.write('\t'.join(FIELDS)+'\n')
status=open(S/'recording-status.log','w')
last=0;start=time.time();polls=0;lost=0
while time.time()-start<DUR:
    (S/'rec.lua').write_text(LUA%(last,','.join("'%s'"%k for k in FIELDS)))
    t0=time.time()
    try:out=subprocess.run(['python3','tools/live_first_person.py','--file',str(S/'rec.lua')],cwd=KIT,capture_output=True,timeout=40).stdout.decode('utf-8','replace')
    except Exception as e:out='';status.write('ERR %s\n'%e)
    polls+=1;first=None
    for line in out.splitlines():
        if line.startswith('R|'):
            p=line[2:].split('|')
            if len(p)<len(FIELDS):continue
            fr=int(float(p[0]))
            if fr<=last:continue
            if first is None:
                first=fr
                if last and fr>last+1:lost+=fr-last-1
            last=fr;rows.write('\t'.join(p[:len(FIELDS)-1]+['|'.join(p[len(FIELDS)-1:])])+'\n')
        elif line.startswith(('C|','S|')):status.write('%.1f %s\n'%(time.time()-start,line[:600]))
    rows.flush();status.flush()
    time.sleep(max(0,2.2-(time.time()-t0)))
print('polls',polls,'last frame',last,'frames lost',lost)
