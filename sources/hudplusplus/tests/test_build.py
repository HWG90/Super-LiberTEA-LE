import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hud_build", ROOT / "tools/build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class BundleTests(unittest.TestCase):
    def fixture(self, root):
        (root / "src").mkdir()
        (root / "build").mkdir()
        (root / "src/entry.lua").write_text("return {}\n")
        (root / "src/addon.lua").write_text("return {}\n")
        (root / "build/bundle.lua").write_bytes((ROOT / "build/bundle.lua").read_bytes())

    def test_render_is_deterministic(self):
        self.assertEqual(build.render(), build.render())

    def test_module_order_does_not_depend_on_creation_order(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root)
            (root / "src/z.lua").write_text("return 2\n")
            (root / "src/a.lua").write_text("return 1\n")
            bundle, mapping = build.render(root)
            self.assertLess(bundle.index(b'modules["a"]'), bundle.index(b'modules["z"]'))
            self.assertNotIn(b'modules["addon"]', bundle)
            import json
            for entry in json.loads(mapping)["modules"]:
                first, last = entry["first_line"], entry["last_line"]
                source = (root / entry["source"]).read_text().rstrip().splitlines()
                self.assertEqual(bundle.decode().splitlines()[first - 1:last], source)

    def test_source_changes_reach_bundle(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root)
            before = build.render(root)
            (root / "src/entry.lua").write_text("return {enabled = true}\n")
            self.assertNotEqual(before, build.render(root))

    def test_invalid_module_names_are_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root)
            (root / "src/bad-name.lua").write_text("return {}\n")
            with self.assertRaisesRegex(ValueError, "invalid module"):
                build.render(root)

    def test_incomplete_template_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root)
            (root / "build/bundle.lua").write_text("-- no insertion markers\n")
            with self.assertRaisesRegex(ValueError, "insertion marker"):
                build.render(root)

    def test_missing_entry_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root)
            (root / "src/entry.lua").unlink()
            with self.assertRaisesRegex(ValueError, "missing entry"):
                build.render(root)
