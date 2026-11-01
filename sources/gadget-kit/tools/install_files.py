"""Replace payload files without changing any inode already mapped by Wine."""
from pathlib import Path
import hashlib
import os
import shutil
import tempfile


def install_file(source: Path, target: Path, expected_hash: str, backup: Path) -> bool:
    data = source.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected_hash:
        raise ValueError(f'Package source changed: {source}')
    if target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == expected_hash:
        return False
    mode = target.stat().st_mode & 0o777 if target.exists() else 0o644
    if target.is_file():
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, backup)
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + target.name + '.', suffix='.tmp', dir=target.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        # A loaded DLL keeps its original inode and relocated import table.
        # Never truncate or write through the destination's existing inode.
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    if hashlib.sha256(target.read_bytes()).hexdigest() != expected_hash:
        raise ValueError(f'Installed payload verification failed: {target}')
    return True
