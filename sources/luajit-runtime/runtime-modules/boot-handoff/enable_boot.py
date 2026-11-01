"""Enable or disable the LuaJIT boot handoff for the next game start.

enable_boot.py <runtime.dll>   copy the DLL into LLL's Native folder as
                               hd2_luajit_runtime_<sha256[:16]>.dll and write the
                               marker naming it (the patched boot reads it)
enable_boot.py --disable       delete the marker; LLL then boots in PUC as before
Neither touches game files. The change applies at the next game start.
"""
from pathlib import Path
import hashlib,os,sys,tempfile
NATIVE=Path('/mnt/WORMHOLE/SteamLibrary/steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LLL/Helldivers2/Native')
MARKER=NATIVE/'luajit-boot.enable'
def atomic(path,data):
    fd,tmp=tempfile.mkstemp(dir=path.parent,prefix='.luajit-')
    with os.fdopen(fd,'wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
    os.replace(tmp,path)
if sys.argv[1:]==['--disable']:
    if MARKER.exists():MARKER.unlink()
    print('disabled: next start runs LLL in PUC')
else:
    dll=Path(sys.argv[1]).read_bytes();name='hd2_luajit_runtime_%s.dll'%hashlib.sha256(dll).hexdigest()[:16]
    target=NATIVE/name
    if target.exists():assert target.read_bytes()==dll,'existing runtime differs'
    else:atomic(target,dll)
    atomic(MARKER,(name+'\n').encode())
    print('enabled for the next start:',name)
