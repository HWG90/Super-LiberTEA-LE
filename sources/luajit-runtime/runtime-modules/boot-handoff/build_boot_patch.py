"""Stage the LuaJIT boot handoff for build 26088801 (no installation).

Composes prologue.lua with LLL's exact boot source, compiles it with a 32-bit
stock Lua 5.1.4 (which reproduces the installed LLL chunk byte for byte) under
LLL's chunk name, and rebuilds LLL's single-resource archive with only the
resource body, size fields and padding changed. Output: stage/ plus a receipt.
"""
from pathlib import Path
import hashlib,json,shutil,struct,subprocess,sys
HERE=Path(__file__).resolve().parent
LUA32=Path(sys.argv[1]) if __name__=='__main__' else HERE/'tools'/'lua32'  # 32-bit stock Lua 5.1.4 interpreter
DLL=Path(sys.argv[2]) if __name__=='__main__' else None  # runtime candidate
LLL_SOURCE=Path('/home/goose/Documents/ChatGPT/Linux HD2/native-work/cffi-pointerfix-current/runtime-source-fixed.lua')
LLL_SHA256='dc66664dedc4a5c8f42d8bd13a6d65d758f7a6b0a2dce189538b7aa453747fc7'
# LLL R35's original boot archive (as shipped in its HD2 Arsenal package).
PACKAGE=HERE/'original'/'9ba626afa44a3aa3.patch_0'
PACKAGE_SHA256='8c63e0c9b8d39711c49d4c1ddd0021a6994a25ed68a458035d05db8877b25423'
BOOT=0xf476df93691895fa;LUA=0xa14e8dfa2cd117e2
def sha(b):return hashlib.sha256(b).hexdigest()
def dump(src,name,out):
    script=HERE/'stage'/'dump.lua'
    script.write_text("local src,name,out=...\nlocal f=assert(io.open(src,'rb'));local s=f:read('*a');f:close()\n"
                      "local fn=assert(loadstring(s,name))\nlocal o=assert(io.open(out,'wb'));o:write(string.dump(fn));o:close()\n")
    subprocess.run([str(LUA32),str(script),str(src),name,str(out)],check=True)
    return out.read_bytes()
def archive(original,chunk):
    magic,types,count=struct.unpack_from('<III',original)
    assert magic==0xf0000011 and types==1 and count==1
    e=list(struct.unpack_from('<7Q6I',original,104))
    assert e[0]==BOOT and e[1]==LUA and e[2]==0xc0
    length,kind=struct.unpack_from('<II',original,e[2]);assert kind==1 and length==e[7]-8
    assert struct.unpack_from('<I',original,32)[0]==len(original)
    body=struct.pack('<II',len(chunk),kind)+chunk
    total=e[2]+len(body);total+=(-total)%16
    out=bytearray(original[:e[2]])
    struct.pack_into('<I',out,32,total)
    e[7]=len(body);struct.pack_into('<7Q6I',out,104,*e)
    out+=body;out+=b'\0'*(total-len(out))
    return bytes(out)
def main():
    stage=HERE/'stage';stage.mkdir(exist_ok=True)
    lll=LLL_SOURCE.read_bytes();assert sha(lll)==LLL_SHA256,'LLL boot source changed'
    original=PACKAGE.read_bytes();assert sha(original)==PACKAGE_SHA256,'pinned original LLL archive changed'
    # The current archive must be exactly LLL's chunk from this source.
    e=struct.unpack_from('<7Q6I',original,104);length,_=struct.unpack_from('<II',original,e[2])
    assert dump(LLL_SOURCE,'@native-font-repair',stage/'lll-reproduced.luac')==original[e[2]+8:e[2]+8+length],'installed LLL chunk not reproduced'
    dll=DLL.read_bytes();runtime='hd2_luajit_runtime_%s.dll'%sha(dll)[:16]
    prologue=(HERE/'prologue.lua').read_text()
    assert '@RUNTIME_DLL@' not in prologue
    combined=prologue.encode()+lll
    (stage/'boot-source.lua').write_bytes(combined)
    chunk=dump(stage/'boot-source.lua','@native-font-repair',stage/'boot.luac')
    assert chunk[:12]==original[e[2]+8:e[2]+20],'bytecode header differs from the game ABI'
    patch=archive(original,chunk)
    (stage/'9ba626afa44a3aa3.patch_0').write_bytes(patch);shutil.copyfile(DLL,stage/runtime)
    receipt={'purpose':'LuaJIT boot handoff, staged only','build':'26088801','runtime_dll':runtime,'runtime_sha256':sha(dll),
     'runtime_source_candidate':str(DLL),'lll_source_sha256':LLL_SHA256,'lll_chunk_reproduced':True,
     'prologue_sha256':sha(prologue.encode()),'boot_source_sha256':sha(combined),'boot_chunk_sha256':sha(chunk),'boot_chunk_bytes':len(chunk),
     'archive_before_sha256':sha(original),'archive_after_sha256':sha(patch),'archive_bytes':len(patch),
     'gate':'%LOCALAPPDATA%/LLL/Helldivers2/Native/luajit-boot.enable naming the runtime DLL on its first line (absent: LLL runs in PUC exactly as before)'}
    (stage/'STAGE-RECEIPT.json').write_text(json.dumps(receipt,indent=1)+'\n')
    print(json.dumps(receipt,indent=1))
if __name__=='__main__':main()
