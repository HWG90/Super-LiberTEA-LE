"""Recover all inventoried stock chunks and snapshot an unchanged existing mod.

Stock source is decompiled, not presumed equivalent. Differential execution is
performed by validate.py. Generated stock data stays in ignored local work/.
"""
from pathlib import Path
import hashlib
import json
import struct
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parent
LLL = Path('/home/goose/Documents/Codex/2026-10-22/a-2/work/LLL')
GAME = Path('/mnt/WORMHOLE/SteamLibrary/steamapps/common/Helldivers 2')
sys.path.insert(0, str(LLL/'tools'))
from archive import LUA_TYPE
from lua51_chunk import convert
from steam_resources import SteamResources
import build_poll_cache
from assemble_bootstrap import assemble

JAR_NAME = 'unluac_2025_12_23.jar'
JAR_SHA = '98be0fa84ac73ca66dce2842a2e4512226f4c611b6500dc96415571fc5538fcc'
URL = 'https://downloads.sourceforge.net/project/unluac/Unstable/' + JAR_NAME
ARCHIVE = '9ba626afa44a3aa3'
NAMES = {
    0x0d4816de1d4771f1: 'core/animation/lua/runtime/animationflowcallbacks',
    0x19bc198a3e7bb327: 'core/wwise/lua/wwise_bank_reference',
    0x2e42becd00d0b9d9: 'stock/wwise_visualization',
    0x405896b911013778: 'stock/animation_requires',
    0x78796ae20bb32759: 'stock/wwise_preview',
    0xf476df93691895fa: 'stock/boot',
}

def digest(b):
    return hashlib.sha256(b).hexdigest()

def murmur(s):
    s=s.encode();m=0xc6a4a7935bd1e995;mask=(1<<64)-1;h=(len(s)*m)&mask
    end=len(s)//8*8
    for p in range(0,end,8):
        k=int.from_bytes(s[p:p+8],'little');k=k*m&mask;k^=k>>47;k=k*m&mask
        h=(h^k)*m&mask
    if end<len(s):h=(h^int.from_bytes(s[end:],'little'))*m&mask
    h^=h>>47;h=h*m&mask;h^=h>>47
    return h

def prepare():
    work=ROOT/'work';stock_dir=work/'stock';stock_dir.mkdir(parents=True,exist_ok=True)
    jar=ROOT/'vendor'/JAR_NAME;jar.parent.mkdir(exist_ok=True)
    if not jar.exists():jar.write_bytes(urllib.request.urlopen(URL,timeout=45).read())
    assert digest(jar.read_bytes())==JAR_SHA, 'unluac fingerprint changed'
    for name,want in {
        'bin/helldivers2.exe':'b434f6f326b7759978265f5863ef72e3c5edd4aa5315cc1ef4b640d204eae0bb',
        'data/game/game.dll':'08b756f535cdb9bdd1b4953fba53c3dfacd25730a155ea6593e5de63211acf5f',
    }.items():assert digest((GAME/name).read_bytes())==want, 'Game build changed: '+name
    inventory=json.loads((ROOT.parent/'vm-trace/runtime-inventory.json').read_text())
    assert not inventory['failures'], 'archive inventory is incomplete'
    assets={};receipt={'stock':[],'mod':{},'lll_dependencies':{},
                       'unluac_sha256':JAR_SHA,'decompiler_url':URL}
    stock=SteamResources(GAME/'data')
    assert digest(stock.index)==inventory['bundle_index_sha256'], 'bundle index changed; repeat inventory'
    receipt['bundle_index_sha256']=inventory['bundle_index_sha256']
    receipt['stock_archives_inventoried']=inventory['archives_by_origin']['bundled-stock']
    seen=set()
    for entry in inventory['resources']:
        if entry['origin']!='bundled-stock' or entry['id'] in seen:continue
        seen.add(entry['id'])
        identity=int(entry['id'],16)
        name=NAMES.get(identity,'stock/'+entry['id'])
        if name.startswith('core/'):assert murmur(name)==identity
        resource=stock.read(entry['archive'],entry['offset'],entry['resource_size'])
        assert digest(resource)==entry['resource_sha256'], 'stock resource changed'
        size,version=struct.unpack_from('<II',resource)
        assert version==1 and size==len(resource)-8
        chunk=resource[8:];binary=stock_dir/f'{identity:016x}.luac';binary.write_bytes(chunk)
        result=subprocess.run(['java','-jar',str(jar),'--nodebug',str(binary)],check=True,capture_output=True)
        source=result.stdout;binary.with_suffix('.lua').write_bytes(source)
        assets[name]=(source,convert(chunk,8),chunk,identity)
        receipt['stock'].append({'id':f'{identity:016x}','archive':entry['archive'],'loader_name':name,
            'name_kind':'hash-verified engine path' if name.startswith('core/') else 'test alias',
            'resource_sha256':digest(resource),'source_sha256':digest(source),'source_bytes':len(source)})
    assert len(receipt['stock'])==inventory['unique_resource_variants']['bundled-stock']
    version,mod=build_poll_cache.runtime_files()
    receipt['mod']['name']='LLL Poll Cache';receipt['mod']['version']=version
    receipt['mod']['origin']=str(LLL);receipt['mod']['files']={}
    for name,body in mod.items():
        path=work/'mod'/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(body)
        assets['mods/lll_poll_cache/'+name]=(body,None,None,0)
        receipt['mod']['files'][name]=digest(body)
    # The current source factors this helper into LLL itself. Supply the real
    # dependency to the host, without editing/replacing the mod's module.
    for name in ['catalog_watch','project','metadata','config','live','manager',
                 'cleanup_queue','after_startup','capabilities']:
        path=LLL/'src'/f'{name}.lua';body=path.read_bytes()
        assets[f'src/{name}.lua']=(body,None,None,0)
        receipt['lll_dependencies'][str(path)]=digest(body)
    bootstrap,bootstrap_receipt=assemble(assets['stock/boot'][2])
    (work/'bootstrap.lua').write_bytes(bootstrap)
    (work/'BOOTSTRAP.json').write_text(json.dumps(bootstrap_receipt,indent=2)+'\n')
    assets['poc/bootstrap.lua']=(bootstrap,None,None,0)
    for name in ['scenarios.lua','trace.lua','loader_scenarios.lua',
                 'bootstrap_scenarios.lua','bootstrap_memory.lua']:
        assets['poc/'+name]=((ROOT/name).read_bytes(),None,None,0)
    compat=(ROOT/'load_compat.lua').read_bytes()
    (work/'load_compat.h').write_text('static const unsigned char load_compat_source[] = {'+
                                   ','.join(str(x) for x in compat)+',0};\n')
    lines=['/* Generated from locally owned stock files and unchanged mod sources. */']
    rows=[]
    for i,(name,(source,reference,original,identity)) in enumerate(sorted(assets.items())):
        for suffix,body in [('source',source),('reference',reference),('original',original)]:
            if body is not None:
                lines.append(f'static const unsigned char a{i}_{suffix}[] = {{')
                for at in range(0,len(body),24):lines.append(','.join(str(x) for x in body[at:at+24])+',')
                lines.append('0};')
        rows.append('{'+json.dumps(name)+f',a{i}_source,{len(source)},'+
                    (f'a{i}_reference,{len(reference)}' if reference is not None else 'NULL,0')+','+
                    (f'a{i}_original,{len(original)}' if original is not None else 'NULL,0')+
                    f',UINT64_C(0x{identity:016x})'+'}')
    lines += ['static const HD2Asset assets[] = {',',\n'.join(rows),'};']
    (work/'assets.h').write_text('\n'.join(lines)+'\n')
    curve=json.loads((ROOT/'native-curve-evidence.json').read_text())
    witness=bytes.fromhex(curve['function_hex'])
    assert digest(witness)==curve['function_sha256']
    (work/'curve_witness.h').write_text('static const unsigned char curve_witness[] = {'+
                                      ','.join(str(x) for x in witness)+'};\n')
    (work/'PROVENANCE.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'stock_chunks':len(receipt['stock']),'unchanged_mod':receipt['mod']['name'],
                      'mod_files':len(mod),'assets':len(assets)}))

if __name__=='__main__':prepare()
