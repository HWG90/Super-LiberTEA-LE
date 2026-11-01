"""Pin the verified SteamVoip views and record unresolved native entry evidence."""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'vm-trace'))
from trace import Image

def prepare():
    im=Image('early');digest=hashlib.sha256(im.data).hexdigest()
    assert digest=='6e2751f8690b6aa49060ca4b8d3476d502232d89de93a1b478722b07cb18a92c'
    newer=Path('/home/goose/Projects/Linux HD2 Mods/builds/26251122/runtime/images/exe-26251122.bin');new=newer.read_bytes()
    assert hashlib.sha256(new).hexdigest()=='6e2751f8690b6aa49060ca4b8d3476d502232d89de93a1b478722b07cb18a92c'
    specs=[('room_members',0x7f2460,0x7f2a8e),('broken_members',0x7f2d30,0x7f3306),
           ('room_id',0x7f3310,0x7f3387),('client_members',0x7f3390,0x7f391e),
           ('select_out',0x7f3920,0x7f3a2f),('select_in',0x7f3a30,0x7f3b3f),('broken_host',0x7f3b40,0x7f3b9a)]
    helpers=[('native_select_out_all',0x7d1c20,0x7d1c8c),('native_select_out_one',0x7d1c90,0x7d1d09),
             ('native_select_in_all',0x7d1d10,0x7d1d7c),('native_select_in_one',0x7d1d80,0x7d1df9)]
    regions=[('registrar',0x7f3ba0,0x7f444e),('registry_module',0x4ece60,0x4ed005),('global_module',0x4ecc90,0x4ece51)]+specs+helpers
    lines=['/* Generated from pinned local captures. Partial SteamVoip views only. */']
    for name,a,b in regions:
        assert im.data[a:b]==new[a:b],(name,'captures differ')
        body=list(im.cs.disasm(im.data[a:b],a));assert body[-1].address+body[-1].size==b
        assert body[-1].mnemonic=='ret',(name,body[-1].mnemonic)
        lines.append('static const unsigned char voip_'+name+'_witness[]={'+','.join(map(str,im.data[a:b]))+'};')
    lines.append('static const struct {uintptr_t rva;const unsigned char *bytes;size_t size;} voip_regions[]={')
    for name,a,b in regions:lines.append('{'+hex(a)+',voip_'+name+'_witness,sizeof(voip_'+name+'_witness)},')
    lines.append('};');(ROOT/'work/voip_witnesses.h').write_text('\n'.join(lines)+'\n')
    missing=[('create_room',0x7d4910),('destroy_room',0x7d48f0),('join_room',0x7d4a20),('leave_room',0x7d4ca0),
             ('update',0x7d4dd0),('add_member',0x7c9940),('remove_member',0x7c9a30),('member_hash_lookup',0x7d3a70)]
    evidence={'capture':str(im.path),'capture_sha256':digest,'newer_capture':str(newer),'newer_capture_sha256':hashlib.sha256(new).hexdigest(),
      'status':'partial views only; SteamVoip boot stage remains incomplete',
      'registrar':{'entry':'0x7f3ba0','end':'0x7f444e','services':['0x2860600','0x28605f8'],'null_behavior':'both stores and module registration are unconditional'},
      'bindings':[{'name':n,'entry':hex(a),'end':hex(b),'sha256':hashlib.sha256(im.data[a:b]).hexdigest()} for n,a,b in specs],
      'native_selection_helpers':[{'name':n,'entry':hex(a),'end':hex(b),'sha256':hashlib.sha256(im.data[a:b]).hexdigest()} for n,a,b in helpers],
      'missing_helpers':[{'name':n,'rva':hex(a),'early_prefix':im.data[a:a+32].hex(),'newer_prefix':new[a:a+32].hex(),
          'early_zero':not any(im.data[a:a+32]),'callable_body_verified':False} for n,a in missing],
      'update_callback':{'entry':'0x7f2500','prefix':im.data[0x7f2500:0x7f23c0].hex(),'same_in_newer':im.data[0x7f2500:0x7f23c0]==new[0x7f2500:0x7f23c0],
          'status':'ret 0 at saved entry; native update body and callback invocation ABI unresolved; not treated as a no-op'},
      'layouts':{'manager':'room count uint32 +0x88, pointer array +0x90; first matching room ID +0x10',
          'room_members':'slot count uint32 +0x18, rows +0x20; stride 0x28, ID +0, live when signed tag +0x20 >=0; broken when byte +0x1c ==0',
          'client':'borrowed native pointer in first 8 full/light userdata bytes; room ID +0x38; host broken when byte +0x78 ==0',
          'client_members':'slot count uint32 +0x40, rows +0x48; stride 0x40, ID +0, live when signed tag +0x38 >=0; selection bytes +0x34/+0x35'},
      'semantics':['member arrays preserve physical live-slot order','empty members returns one empty table; empty broken_members returns zero values',
          'select uses Lua truthiness; a third argument selects the native single-member helper even when nil (nil rejected as invalid ID)',
          'native single-member helper calls 0x7d3a70; this lookup still has no verified body',
          'no automatic native release or pointer invalidation is introduced'],
      'limits':'at most 1048576 room/member slots; host stabilizes all native lifetimes and data for the full call',
      'native_service_live_validated':False,'native_windows_tested':False,'in_game_vm_replaced':False}
    (ROOT/'voip-binding-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({'callbacks':len(specs),'native_selection_helpers':len(helpers),'guard_bytes':sum(b-a for _,a,b in regions),'missing_helper_bodies':len(missing)}))
if __name__=='__main__':prepare()
