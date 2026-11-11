import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("check_source_lock", Path(__file__).parents[1] / "tools/check_source_lock.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

class SourceLockTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.lock = {"files": [{"path": "sample.txt", "bytes": 3, "sha256": hashlib.sha256(b"abc").hexdigest()}]}
        (self.root / "sample.txt").write_bytes(b"abc")

    def test_exact_copy(self):
        self.assertEqual([], MODULE.verify(self.root, self.lock))

    def test_same_length_change(self):
        (self.root / "sample.txt").write_bytes(b"xyz")
        self.assertEqual(["内容不同: sample.txt"], MODULE.verify(self.root, self.lock))

    def test_missing_file(self):
        (self.root / "sample.txt").unlink()
        self.assertEqual(["缺失: sample.txt"], MODULE.verify(self.root, self.lock))

    def test_unexpected_file(self):
        (self.root / "extra.txt").write_bytes(b"")
        self.assertEqual(["多余: extra.txt"], MODULE.verify(self.root, self.lock))

if __name__ == "__main__":
    unittest.main()
