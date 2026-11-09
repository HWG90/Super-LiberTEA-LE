"""Real default-storage paths and original LLL preference overlays; temporary files only."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = r'''
local p,g=assert(loadfile('tests/support.lua'))().project()
local root=assert(arg[1]);p.dir=root..'/Mods/dbf_modular';p.config_dir=root..'/Settings/dbf_modular'
g.os=setmetatable({getenv=function(key)if key=='APPDATA'then return root end;if key=='LOCALAPPDATA'then return root..'/wrong-fallback'end end},{__index=os})
g.CowboyBingusModLoader={log_directory=root..'/Logs'}
local Store=p.require('settings/store.lua');local store=Store.new(p,g)
assert(store.path==root..'/dbf_modular.cfg')
assert(store:get('native_stratagem_radial.enabled')==false)
assert(store:get('native_stratagem_radial.input_interval_ms')==0)
assert(store:get('native_stratagem_radial.wheel_size')==112.34567)
assert(store:get('native_stratagem_radial.icon_size')==110)
assert(store:get('hud.enabled')==true)
assert(store:set('hud.opacity',82));assert(store:close())
print('default original LLL preference import/reload passed')
'''


@unittest.skipUnless(shutil.which("luajit"), "LuaJIT required")
class OriginalPreferenceTests(unittest.TestCase):
    def test_default_storage_reads_original_project_defaults_and_persisted_overlay_once(self):
        with tempfile.TemporaryDirectory(prefix="dbfm-prefs-") as temporary:
            base = Path(temporary)
            defaults = base / "Mods/divers_best_friend/config/defaults.cfg"
            saved = base / "Settings/divers_best_friend/config.cfg"
            defaults.parent.mkdir(parents=True)
            saved.parent.mkdir(parents=True)
            defaults.write_text(json.dumps({"preferences": {"enabled": True, "wheel_size": 105, "icon_size": 110}}))
            saved.write_text(json.dumps({"preferences": {"enabled": False, "wheel_size": 112.34567,
                                                       "input_interval_ms": 0, "hud.enabled": False}}))
            before = (defaults.read_bytes(), saved.read_bytes())
            runner = base / "probe.lua"
            runner.write_text(SCRIPT)
            command = ["luajit", str(runner), temporary]
            initial = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(initial.returncode, 0, initial.stdout + initial.stderr)
            self.assertEqual((defaults.read_bytes(), saved.read_bytes()), before)
            self.assertTrue((base / "dbf_modular.cfg").read_text().startswith("schema_version=1\n"))
            defaults.write_text("broken original defaults")
            saved.write_text("broken original persisted preferences")
            reloaded = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(reloaded.returncode, 0, reloaded.stdout + reloaded.stderr)
            self.assertEqual(saved.read_text(), "broken original persisted preferences")


if __name__ == "__main__":
    unittest.main()
