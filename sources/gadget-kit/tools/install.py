"""Install the reviewed allowlist into the active current-build kit. Preserve settings."""
from pathlib import Path
import json,shutil,hashlib,datetime
from package import build,ROOT
from install_files import install_file
TARGETS=[Path('/home/goose/.local/share/Steam/steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/LLL/Helldivers2/Mods/goose_temporary_unlocks')]
package=build();stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ');backup=ROOT/'dist/backups'/stamp
receipts=[]
for index,target in enumerate(TARGETS):
 assert (target/'manifest.json').is_file(),target
 assert json.loads((target/'manifest.json').read_text())['id']=='goose_temporary_unlocks'
 changed=[];unchanged=[]
 for name,expected in package['files'].items():
  if install_file(ROOT/name,target/name,expected,backup/str(index)/name):
   changed.append(name)
  else:
   unchanged.append(name)
 receipts.append({'target':str(target),'verified_files':len(changed)+len(unchanged),
                  'changed_files':changed,'unchanged_files':len(unchanged)})
result={'version':package['version'],'backup':str(backup),'targets':receipts,'package_sha256':package['sha256'],'settings_modified':False}
(ROOT/'dist/installation.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
