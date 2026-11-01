import hashlib
import mmap
from pathlib import Path
import tempfile
import unittest
from install_files import install_file

class InstallFilesTests(unittest.TestCase):
    def test_identical_dll_keeps_loaded_inode(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);source=root/'source';target=root/'helper.dll';backup=root/'backup'
            source.write_bytes(b'original DLL');target.write_bytes(source.read_bytes())
            before=target.stat()
            self.assertFalse(install_file(source,target,hashlib.sha256(source.read_bytes()).hexdigest(),backup))
            after=target.stat()
            self.assertEqual((before.st_ino,before.st_mtime_ns),(after.st_ino,after.st_mtime_ns))
            self.assertFalse(backup.exists())

    def test_changed_dll_preserves_existing_memory_mapping(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);source=root/'source';target=root/'helper.dll';backup=root/'backup'
            old=b'old mapped DLL';new=b'new mapped DLL'
            target.write_bytes(old);source.write_bytes(new);inode=target.stat().st_ino
            with target.open('rb') as stream, mmap.mmap(stream.fileno(),0,access=mmap.ACCESS_READ) as loaded:
                self.assertTrue(install_file(source,target,hashlib.sha256(new).hexdigest(),backup))
                self.assertEqual(loaded[:],old)
                self.assertEqual(target.read_bytes(),new)
                self.assertNotEqual(target.stat().st_ino,inode)
                self.assertEqual(backup.read_bytes(),old)
            self.assertEqual(list(root.glob('*.tmp')),[])

    def test_changed_package_source_cannot_touch_destination(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);source=root/'source';target=root/'helper.dll'
            source.write_bytes(b'changed');target.write_bytes(b'original')
            with self.assertRaises(ValueError):
                install_file(source,target,'0'*64,root/'backup')
            self.assertEqual(target.read_bytes(),b'original')

if __name__=='__main__':unittest.main()
