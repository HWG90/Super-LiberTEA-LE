"""Package the exact manifest payload and six built native policies (five first-person, near clip)."""
from pathlib import Path
import json,re,hashlib,zipfile
ROOT=Path(__file__).resolve().parents[1]
def build():
 manifest=json.loads((ROOT/'manifest.json').read_text());profile=(ROOT/'src/first_person/profile.lua').read_text()
 helpers=sorted(set(re.findall(r"native/native_ads_[a-z]+_26251122_[a-z0-9]+\.dll",profile)))
 assert len(helpers)==6 and any('native_ads_near_' in h for h in helpers)
 files=['main.lua','manifest.json','config/defaults.cfg','README.md','LICENSE','PORT-STATUS.txt','PORT-PROVENANCE.json',*manifest['lll']['modules'],*helpers,*re.findall(r"native/guarded_reads_[0-9a-f]+\.dll",(ROOT/'src/memory.lua').read_text()),'port51/hd2_nativeinfo_8d03e036881e4ddc.dll']
 assert len(files)==len(set(files))
 out=ROOT/'dist/releases';out.mkdir(parents=True,exist_ok=True)
 archive=out/f"Goose-Gadget-Kit-{manifest['version']}.zip"
 hashes={}
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED)as z:
  for name in files:
   p=ROOT/name;assert p.resolve().is_relative_to(ROOT.resolve())and p.is_file(),name
   blob=p.read_bytes();hashes[name]=hashlib.sha256(blob).hexdigest();z.writestr(manifest['id']+'/'+name,blob)
 receipt={'version':manifest['version'],'archive':str(archive),'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'files':hashes}
 (out/'package.json').write_text(json.dumps(receipt,indent=2)+'\n')
 return receipt
if __name__=='__main__':print(build()['archive'])
