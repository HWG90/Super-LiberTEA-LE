"""Install (or roll back) the staged LuaJIT boot handoff. Dry run unless --apply.

Replaces LLL's boot archive in its HD2 Arsenal package and the one deployed copy
(identified by exact bytes and single resource f476df93691895fa), and copies the
runtime DLL into LLL's Native folder. It never creates the enable marker: with
the marker absent the patched boot runs LLL in PUC exactly as before.
Requires Helldivers 2 and HD2 Arsenal to be closed. Backups and a manifest go to
boot-handoff/backups/<timestamp>/; --rollback <dir> restores them.
"""
from pathlib import Path
import datetime,hashlib,json,os,shutil,struct,sys,tempfile
HERE=Path(__file__).resolve().parent
STAGE=HERE/'stage'
PACKAGE=Path('/home/goose/.config/hd2arsenal/mods/LiveLuaLoader-R35-26088801-cffi-Arsenal_AR372513/9ba626afa44a3aa3.patch_0')
DATA=Path('/mnt/WORMHOLE/SteamLibrary/steamapps/common/Helldivers 2/data')
NATIVE=Path('/mnt/WORMHOLE/SteamLibrary/steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LLL/Helldivers2/Native')
BOOT=0xf476df93691895fa
def sha(b):return hashlib.sha256(b).hexdigest()
def closed():
    for p in Path('/proc').iterdir():
        if not p.name.isdigit():continue
        try:cmd=(p/'cmdline').read_bytes();exe=os.readlink(p/'exe')
        except(FileNotFoundError,PermissionError,ProcessLookupError):continue
        assert not(exe.endswith('/hd2arsenal') and b'--type=' not in cmd),'Close HD2 Arsenal first'
        assert b'helldivers2.exe' not in cmd[:200].lower() or exe.endswith(('/bash','/zsh','/fish','/python3')),'Close Helldivers 2 first'
def atomic(path,data):
    fd,tmp=tempfile.mkstemp(dir=path.parent,prefix='.luajit-boot-')
    with os.fdopen(fd,'wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
    os.replace(tmp,path)
def single_boot(data):
    try:
        magic,types,count=struct.unpack_from('<III',data)
        return magic==0xf0000011 and types==1 and count==1 and struct.unpack_from('<Q',data,104)[0]==BOOT
    except struct.error:return False
def rollback(directory):
    closed();m=json.loads((directory/'MANIFEST.json').read_text())
    for row in m['replaced']:
        target=Path(row['path']);assert sha(target.read_bytes())==row['after_sha256'],('changed since install',target)
        atomic(target,(directory/row['backup']).read_bytes())
    for row in m['added']:
        p=Path(row);
        if p.exists():p.unlink()
    print('rolled back',len(m['replaced']),'files; removed',len(m['added']))
def main():
    if '--rollback' in sys.argv:return rollback(Path(sys.argv[sys.argv.index('--rollback')+1]))
    apply='--apply' in sys.argv
    receipt=json.loads((STAGE/'STAGE-RECEIPT.json').read_text())
    new=(STAGE/'9ba626afa44a3aa3.patch_0').read_bytes();assert sha(new)==receipt['archive_after_sha256']
    dll=(STAGE/receipt['runtime_dll']).read_bytes();assert sha(dll)==receipt['runtime_sha256']
    old=PACKAGE.read_bytes();assert sha(old)==receipt['archive_before_sha256'],'LLL package changed since staging'
    deployed=[p for p in DATA.glob('9ba626afa44a3aa3.patch_*') if p.suffix.startswith('.patch_') and p.name.count('.')==1 and single_boot(p.read_bytes())]
    assert len(deployed)==1 and deployed[0].read_bytes()==old,('deployed boot archive is not a unique exact copy',[str(p) for p in deployed])
    target_dll=NATIVE/receipt['runtime_dll'];marker=NATIVE/'luajit-boot.enable'
    plan={'apply':apply,'package':str(PACKAGE),'deployed':str(deployed[0]),'runtime':str(target_dll),
          'marker_present':marker.exists(),'before_sha256':sha(old),'after_sha256':sha(new)}
    print(json.dumps(plan,indent=1))
    if not apply:return
    closed()
    backup=HERE/'backups'/datetime.datetime.now().strftime('%Y%m%d-%H%M%S');backup.mkdir(parents=True)
    manifest={'replaced':[],'added':[],'receipt':receipt,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    for i,path in enumerate([PACKAGE,deployed[0]]):
        name='%d-%s'%(i,path.name);(backup/name).write_bytes(path.read_bytes())
        manifest['replaced'].append({'path':str(path),'backup':name,'before_sha256':sha(old),'after_sha256':sha(new)})
    assert not target_dll.exists() or target_dll.read_bytes()==dll
    if not target_dll.exists():manifest['added'].append(str(target_dll))
    (backup/'MANIFEST.json').write_text(json.dumps(manifest,indent=1)+'\n')
    if not target_dll.exists():
        fd,tmp=tempfile.mkstemp(dir=NATIVE,prefix='.luajit-runtime-')
        with os.fdopen(fd,'wb') as f:f.write(dll)
        os.replace(tmp,target_dll)
    for path in [PACKAGE,deployed[0]]:atomic(path,new)
    print('installed; backup and manifest:',backup)
main()
