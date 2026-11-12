"""Synthetic process tests; never load Godot or licensed project content."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
FAKE_ENGINE = r'''
import os
from pathlib import Path
import sys
import time

mode = os.environ.get("FAKE_GODOT_MODE", "success")
project = Path(sys.argv[sys.argv.index("--path") + 1])
assert sys.argv[1] == "--headless"
assert sys.argv[sys.argv.index("--script") + 1] == "res://tests/godot/synthetic.gd"
assert project.joinpath("project.godot").read_text() == "config_version=5\n"
assert all(project.joinpath(item).is_symlink() for item in ("scripts", "data", "tests", "assets", "scenes"))
assert not project.joinpath(".godot").exists()
assert all(Path(os.environ[key]).is_dir() for key in ("HOME", "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME"))
assert Path(os.environ["HOME"]).parent == project.parent
print("synthetic stdout", flush=True)
print("synthetic stderr", file=sys.stderr, flush=True)
if mode == "error":
    print(os.environ["FAKE_GODOT_ERROR"], flush=True)
elif mode == "nonzero":
    sys.exit(17)
elif mode == "timeout":
    time.sleep(30)
elif mode == "ignore-term":
    import signal
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(30)
elif mode == "partial":
    os.write(1, b"partial stdout without newline")
'''


class GodotRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="abyssal-runner-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.engine = self.root / "fake engine"
        self.engine.write_text(f"#!{sys.executable}\n" + FAKE_ENGINE)
        self.engine.chmod(0o700)

    def run_engine(self, mode="success", **extra):
        environment = dict(os.environ, GODOT=str(self.engine), TMPDIR=str(self.root),
                           GODOT_TEST_TIMEOUT="5", FAKE_GODOT_MODE=mode)
        environment.update(extra)
        result = subprocess.run(
            ["bash", str(ROOT / "tools/test_godot.sh"), "res://tests/godot/synthetic.gd"],
            env=environment, capture_output=True, text=True, timeout=10,
        )
        self.assertEqual([], list(self.root.glob("abyssal-tests.*")), "isolated test directories cleaned")
        return result

    def test_success_relays_both_streams_and_preserves_isolation(self):
        result = self.run_engine()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("synthetic stdout", result.stdout)
        self.assertIn("synthetic stderr", result.stdout)

    def test_nonzero_exit_is_preserved(self):
        self.assertEqual(17, self.run_engine("nonzero").returncode)

    def test_logged_errors_fail_even_with_zero_engine_exit(self):
        for message in ("SCRIPT ERROR: synthetic", "ERROR: synthetic", "FAIL: synthetic",
                        "Assertion failed: synthetic", "Assertionfailed: synthetic",
                        "WARNING: ObjectDB instances leaked at exit",
                        "Resource still in use: synthetic.wav (AudioStreamWAV)",
                        "\x1b[31mSCRIPT ERROR:\x1b[0m synthetic"):
            with self.subTest(message=message):
                result = self.run_engine("error", FAKE_GODOT_ERROR=message)
                self.assertEqual(1, result.returncode)
                self.assertIn(message, result.stdout)
                self.assertIn("engine/test error", result.stderr)

    def test_timeout_stops_engine_and_relays_partial_output(self):
        start = time.monotonic()
        result = self.run_engine("timeout", GODOT_TEST_TIMEOUT="0.2")
        self.assertEqual(124, result.returncode)
        self.assertLess(time.monotonic() - start, 5)
        self.assertIn("synthetic stdout", result.stdout)
        self.assertIn("TIMEOUT", result.stderr)

    def test_timeout_force_kills_uncooperative_engine(self):
        start = time.monotonic()
        result = self.run_engine("ignore-term", GODOT_TEST_TIMEOUT="0.2")
        self.assertEqual(124, result.returncode)
        self.assertLess(time.monotonic() - start, 5)

    def test_invalid_timeout_is_rejected(self):
        for value in ("bad", "nan", "inf", "0", "-1", "3601"):
            with self.subTest(value=value):
                result = self.run_engine(GODOT_TEST_TIMEOUT=value)
                self.assertEqual(2, result.returncode)
                self.assertNotIn("synthetic stdout", result.stdout)

    def test_missing_engine_has_explicit_failure(self):
        result = self.run_engine(GODOT=str(self.root / "missing-engine"))
        self.assertEqual(127, result.returncode)
        self.assertIn("could not start engine", result.stderr)

    def test_output_without_newline_is_preserved(self):
        result = self.run_engine("partial")
        self.assertEqual(0, result.returncode)
        self.assertTrue(result.stdout.endswith("partial stdout without newline"))


if __name__ == "__main__":
    unittest.main()
