"""Pin the verified SteamVoip views and record unresolved native entry evidence."""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'vm-trace'))
from trace import Image

def prepare():
    im=Image('early');digest=hashlib.sha256(im.data).hexdigest()
    assert digest=='1932b56a7670a62ab1dd432dc05ca5dbcfd12e7fa49637068b16512ea75602a7'
    newer=Path('/home/goose/Projects/Linux HD2 Mods/builds/26568081/runtime/images/exe-26568081.bin');new=newer.read_bytes()
    assert hashlib.sha256(new).hexdigest()=='1932b56a7670a62ab1dd432dc05ca5dbcfd12e7fa49637068b16512ea75602a7'
    specs=[('room_members',0x7f2710,0x7f2d3e),('broken_members',0x7f2fe0,0x7f35b6),
           ('room_id',0x7f35c0,0x7f3637),('client_members',0x7f3640,0x7f3bce),
           ('select_out',0x7f3bd0,0x7f3cdf),('select_in',0x7f3ce0,0x7f3def),('broken_host',0x7f3df0,0x7f3e4a)]
    helpers=[('native_select_out_all',0x7d1ec0,0x7d1f2c),('native_select_out_one',0x7d1f30,0x7d1fa9),
             ('native_select_in_all',0x7d1fb0,0x7d201c),('native_select_in_one',0x7d2020,0x7d2099)]
    regions=[('registrar',0x7f3e50,0x7f46fe),('registry_module',0x4ecf30,0x4ed0d5),('global_module',0x4ecd60,0x4ecf21)]+specs+[h for h in helpers if all(any(im.data[q:q+16]) for q in (h[1],h[2]-16))]
    assert [n for n,_,_ in regions[-2:]]==['native_select_out_all','native_select_out_one'],'26568081: only the select_out helpers are captured'
    lines=['/* Generated from pinned local captures. Partial SteamVoip views only. */']
    for name,a,b in regions:
        assert im.data[a:b]==new[a:b],(name,'captures differ')
        body=list(im.cs.disasm(im.data[a:b],a));assert body[-1].address+body[-1].size==b
        assert body[-1].mnemonic=='ret',(name,body[-1].mnemonic)
        lines.append('static const unsigned char voip_'+name+'_witness[]={'+','.join(map(str,im.data[a:b]))+'};')
    lines.append('static const struct {uintptr_t rva;const unsigned char *bytes;size_t size;} voip_regions[]={')
    for name,a,b in regions:lines.append('{'+hex(a)+',voip_'+name+'_witness,sizeof(voip_'+name+'_witness)},')
    lines.append('};');(ROOT/'work/voip_witnesses.h').write_text('\n'.join(lines)+'\n')
    missing=[('create_room',0x7d4bb0),('destroy_room',0x7d4b90),('join_room',0x7d4cc0),('leave_room',0x7d4f40),
             ('update',0x7d5070),('add_member',0x7c9be0),('remove_member',0x7c9cd0),('member_hash_lookup',0x7d3d10)]
    evidence={'capture':str(im.path),'capture_sha256':digest,'newer_capture':str(newer),'newer_capture_sha256':hashlib.sha256(new).hexdigest(),
      'status':'partial views only; SteamVoip boot stage remains incomplete',
      'registrar':{'entry':'0x7f3e50','end':'0x7f46fe','services':['0x2860600','0x28605f8'],'null_behavior':'both stores and module registration are unconditional'},
      'bindings':[{'name':n,'entry':hex(a),'end':hex(b),'sha256':hashlib.sha256(im.data[a:b]).hexdigest()} for n,a,b in specs],
      'native_selection_helpers':[{'name':n,'entry':hex(a),'end':hex(b),'captured':any(im.data[b-16:b]),'sha256':hashlib.sha256(im.data[a:b]).hexdigest() if any(im.data[b-16:b]) else None} for n,a,b in helpers],
      'uncaptured_note':'26568081: native_select_in_all/one are on exe page 0x7d2000, absent from every capture; addresses from the select_in caller, no byte witness',
      'missing_helpers':[{'name':n,'rva':hex(a),'early_prefix':im.data[a:a+32].hex(),'newer_prefix':new[a:a+32].hex(),
          'early_zero':not any(im.data[a:a+32]),'callable_body_verified':False} for n,a in missing],
      'update_callback':{'entry':'0x7f27b0','prefix':im.data[0x7f27b0:0x7f2670].hex(),'same_in_newer':im.data[0x7f27b0:0x7f2670]==new[0x7f27b0:0x7f2670],
          'status':'ret 0 at saved entry; native update body and callback invocation ABI unresolved; not treated as a no-op'},
      'layouts':{'manager':'room count uint32 +0x88, pointer array +0x90; first matching room ID +0x10',
          'room_members':'slot count uint32 +0x18, rows +0x20; stride 0x28, ID +0, live when signed tag +0x20 >=0; broken when byte +0x1c ==0',
          'client':'borrowed native pointer in first 8 full/light userdata bytes; room ID +0x38; host broken when byte +0x78 ==0',
          'client_members':'slot count uint32 +0x40, rows +0x48; stride 0x40, ID +0, live when signed tag +0x38 >=0; selection bytes +0x34/+0x35'},
      'semantics':['member arrays preserve physical live-slot order','empty members returns one empty table; empty broken_members returns zero values',
          'select uses Lua truthiness; a third argument selects the native single-member helper even when nil (nil rejected as invalid ID)',
          'native single-member helper calls 0x7d3d10; this lookup still has no verified body',
          'no automatic native release or pointer invalidation is introduced'],
      'limits':'at most 1048576 room/member slots; host stabilizes all native lifetimes and data for the full call',
      'native_service_live_validated':False,'native_windows_tested':False,'in_game_vm_replaced':False}
    (ROOT/'voip-binding-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({'callbacks':len(specs),'native_selection_helpers':len(helpers),'guard_bytes':sum(b-a for _,a,b in regions),'missing_helper_bodies':len(missing)}))
if __name__=='__main__':prepare()
