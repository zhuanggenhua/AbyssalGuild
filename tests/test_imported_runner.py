"""Synthetic private-runner guards/orchestration; no Godot or licensed assets."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import run_imported_tests as runner

MARKERS = {
    "test_held_stack_board": "Held stack board checks: 1 passed / 1 total",
    "test_cycle_action_visibility": "Cycle action visibility: 1 passed / 1 total",
    "test_imported_resources": "Private imported resources: PASS (1 PNG, 1 WAV, 1 FBX)",
    "test_source_board_mesh": "Source board mesh: PASS (2 models, synthetic)",
    "test_card_mesh_binding": "Source card/pack mesh: PASS (3 bindings; actual cached FBX synthetic)",
    "test_card_overlays": "Private card overlays: PASS (2 labels, 1 panels; actual cached FBX)",
    "test_puff_view": "Private native Puff view: PASS",
    "test_puff_simulation": "Private Puff simulation: PASS (synthetic)",
    "test_equipment_display": "Private equipment interaction: PASS",
    "test_audio_feedback": "Private source audio: 1 SFX decoded and playback-start checked",
    "test_visual_assets": "Visual source bindings: PASS",
    "test_combat_sprite_binding": "Private combat sprites: PASS (synthetic)",
    "test_combat_presentation": "Combat presentation checks: 1 passed",
}
for name, prefix in (
    ("test_combat_feedback_ui", "Combat feedback UI"), ("test_ui_smoke", "UI"),
    ("test_cycle_board", "Cycle board"), ("test_puff_board", "Puff board"),
    ("test_camera_board", "Camera board"), ("test_board_integration", "Board integration"), ("test_trade_collection_ui", "Trade/collection UI"),
    ("test_options_ui", "Options UI"), ("test_equipment_board", "Equipment board"),
    ("test_slot_management_ui", "Slot management UI"),
    ("test_slot_ui", "Slot UI"), ("test_combat_board", "Combat board"),
):
    MARKERS[name] = prefix + " checks: 1 passed / 1 total"

FAKE_ENGINE = r'''
import json
import os
from pathlib import Path
import sys
import time
project = Path(sys.argv[sys.argv.index("--path") + 1])
assert sys.argv[1] == "--headless"
assert project != Path(os.environ["FIXTURE_ROOT"])
assert not any(p.is_symlink() for p in project.rglob("*"))
for key in ("HOME", "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR", "TMPDIR"):
    assert Path(os.environ[key]).is_dir()
    assert Path(os.environ[key]).parent == project.parent
assert not (project / "source").exists()
assert not (project / "assets/imported/unlisted.txt").exists()
if "--import" in sys.argv:
    phase = "import"
    assert "--editor" in sys.argv and "--script" not in sys.argv
    assert not (project / ".godot").exists()
    assert not any(project.rglob("*.import"))
    (project / ".godot/imported").mkdir(parents=True)
    (project / "assets/imported/image.png.import").write_text("new disposable sidecar")
else:
    phase = Path(sys.argv[sys.argv.index("--script") + 1]).stem
    assert (project / ".godot/imported").is_dir()
    assert (project / "assets/imported/image.png.import").read_text() == "new disposable sidecar"
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps({"phase": phase, "project": str(project), "pid": os.getpid()}) + "\n")
mode = os.environ.get("FAKE_MODE", "success")
if phase == os.environ.get("FAIL_PHASE", "import"):
    if mode == "timeout":
        time.sleep(30)
    if mode == "error":
        print("SCRIPT ERROR: synthetic zero-exit diagnostic")
    if mode == "nonzero":
        sys.exit(17)
    if mode == "skip":
        print("Private required branch: SKIP (synthetic)")
    if mode == "silent":
        sys.exit(0)
if phase != "import":
    print(json.loads(os.environ["FAKE_MARKERS"])[phase])
'''


def canonical(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()


class ImportedRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="abyssal-private-runner-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "checkout"
        for directory in ("tools", "tests/godot", "scripts", "scenes", "data", "assets/imported", ".godot", "source"):
            (self.root / directory).mkdir(parents=True)
        for name in ("test_imported.sh", "run_imported_tests.py", "run_godot_test.py", "verify_source.py", "import_stackcraft.py"):
            shutil.copyfile(ROOT / "tools" / name, self.root / "tools" / name)
        (self.root / "project.godot").write_text("config_version=5\n")
        (self.root / ".godot/untouched").write_text("original cache")
        (self.root / "source/untouched").write_text("never copied")
        for name, _ in runner.SUITES:
            (self.root / "tests/godot" / (name + ".gd")).write_text("# fake suite\n")
        self.manifest = {"schema_version": 1, "missing": [], "assets": {}, "materials": {"m": {}},
                         "prefabs": {"p": {}}, "scenes": {"Main": {}, "Island": {}}}
        for kind, name in (("png", "image.png"), ("wav", "sound.wav"), ("fbx", "model.fbx")):
            data = ("synthetic " + kind).encode()
            (self.root / "assets/imported" / name).write_bytes(data)
            self.manifest["assets"][kind] = {"path": name, "kind": kind, "sha256": hashlib.sha256(data).hexdigest()}
        (self.root / "assets/imported/image.png.import").write_text("original sidecar")
        (self.root / "assets/imported/unlisted.txt").write_text("do not copy")
        self.save_manifest()
        groups = ("cards", "packs", "recipes", "quests", "encounters", "settings", "scenes", "referenced_prefabs")
        catalog = {"schema_version": 1, "provenance": {"source_commit": "synthetic"}, "counts": {}, "guid_index": {}}
        for group in groups:
            catalog[group] = []
            catalog["counts"][group] = 0
        payload = canonical(catalog)
        (self.root / "data/stackcraft.json").write_bytes(payload)
        data_manifest = {"schema_version": 1, "source_commit": "synthetic", "counts": catalog["counts"],
                         "stackcraft_json_sha256": hashlib.sha256(payload).hexdigest(), "source_files_sha256": {},
                         "references": {"total": 0, "resolved": 0, "unresolved_external": []}}
        (self.root / "data/manifest.json").write_bytes(canonical(data_manifest))
        self.engine = self.base / "fake engine"
        self.engine.write_text(f"#!{sys.executable}\n" + FAKE_ENGINE)
        self.engine.chmod(0o700)
        self.log = self.base / "calls.jsonl"

    def save_manifest(self):
        (self.root / "assets/imported/manifest.json").write_bytes(canonical(self.manifest))

    def run_fixture(self, **extra):
        before = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        environment = dict(os.environ, GODOT=str(self.engine), TMPDIR=str(self.base), GODOT_IMPORT_TIMEOUT="5",
                           GODOT_TEST_TIMEOUT="5", FIXTURE_ROOT=str(self.root), CALL_LOG=str(self.log),
                           FAKE_MARKERS=json.dumps(MARKERS))
        environment.update(extra)
        result = subprocess.run(["bash", str(self.root / "tools/test_imported.sh")], env=environment,
                                capture_output=True, text=True, timeout=15)
        after = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        self.assertEqual(before, after, "checkout files/caches/sidecars stay byte-identical")
        self.assertEqual([], list(self.base.glob("abyssal-imported-*")), "disposable project is removed")
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, calls

    def test_import_then_all_suites_share_disposable_cache(self):
        result, calls = self.run_fixture()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(["import"] + [name for name, _ in runner.SUITES], [c["phase"] for c in calls])
        self.assertEqual(1, len({c["project"] for c in calls}))
        self.assertIn("PRIVATE IMPORTED VALIDATION: PASS", result.stdout)

    def test_missing_private_inputs_fail_before_engine(self):
        for relative in ("data/stackcraft.json", "data/manifest.json", "assets/imported/manifest.json", "assets/imported/model.fbx"):
            with self.subTest(relative=relative):
                path = self.root / relative
                content = path.read_bytes()
                path.unlink()
                result, calls = self.run_fixture()
                self.assertNotEqual(0, result.returncode)
                self.assertIn("Missing required", result.stderr)
                self.assertEqual([], calls)
                path.write_bytes(content)

    def test_invalid_manifest_path_hash_missing_report_and_kind_fail_closed(self):
        import copy
        original = copy.deepcopy(self.manifest)
        mutations = (
            lambda m: m["assets"]["png"].update(path="../escape.png"),
            lambda m: m["assets"]["png"].update(path="/absolute.png"),
            lambda m: m["assets"]["png"].update(path="res://image.png"),
            lambda m: m["assets"]["png"].update(path="image\\bad.png"),
            lambda m: m["assets"]["png"].update(sha256="0" * 64),
            lambda m: m.update(missing=["missing image"]),
            lambda m: m["assets"].pop("fbx"),
            lambda m: m.update(schema_version=2),
            lambda m: m.update(assets=[]),
        )
        for change in mutations:
            with self.subTest(change=change):
                self.manifest = copy.deepcopy(original)
                change(self.manifest)
                self.save_manifest()
                result, calls = self.run_fixture()
                self.assertNotEqual(0, result.returncode)
                self.assertEqual([], calls)

    def test_symlink_input_rejected_without_import(self):
        target = self.root / "assets/imported/model.fbx"
        content = target.read_bytes()
        target.unlink()
        outside = self.base / "outside.fbx"
        outside.write_bytes(content)
        target.symlink_to(outside)
        result, calls = self.run_fixture()
        self.assertNotEqual(0, result.returncode)
        self.assertIn("Symlink", result.stderr)
        self.assertEqual([], calls)
        self.assertEqual(content, outside.read_bytes())

    def test_catalog_hash_checked_before_import(self):
        path = self.root / "data/stackcraft.json"
        path.write_text(path.read_text() + " ")
        result, calls = self.run_fixture()
        self.assertNotEqual(0, result.returncode)
        self.assertIn("Data SHA-256 mismatch", result.stderr)
        self.assertEqual([], calls)

    def test_import_errors_nonzero_and_timeouts_stop_without_suites(self):
        for mode, code in (("error", 1), ("nonzero", 17), ("timeout", 124)):
            with self.subTest(mode=mode):
                self.log.unlink(missing_ok=True)
                result, calls = self.run_fixture(FAKE_MODE=mode, GODOT_IMPORT_TIMEOUT="0.2")
                self.assertEqual(code, result.returncode, result.stdout + result.stderr)
                self.assertEqual(["import"], [c["phase"] for c in calls])

    def test_suite_skip_or_missing_marker_cannot_pass(self):
        for mode in ("skip", "silent"):
            with self.subTest(mode=mode):
                self.log.unlink(missing_ok=True)
                result, calls = self.run_fixture(FAKE_MODE=mode, FAIL_PHASE="test_card_mesh_binding")
                self.assertEqual(1, result.returncode)
                self.assertEqual("test_card_mesh_binding", calls[-1]["phase"])
                self.assertNotIn("PRIVATE IMPORTED VALIDATION: PASS", result.stdout)

    def test_missing_suite_and_invalid_timeout_never_launch_engine(self):
        path = self.root / "tests/godot/test_imported_resources.gd"
        content = path.read_bytes()
        path.unlink()
        result, calls = self.run_fixture()
        self.assertNotEqual(0, result.returncode)
        self.assertEqual([], calls)
        path.write_bytes(content)
        result, calls = self.run_fixture(GODOT_IMPORT_TIMEOUT="nan")
        self.assertEqual(2, result.returncode)
        self.assertEqual([], calls)

    def test_sigterm_stops_import_and_cleans_disposable_project(self):
        environment = dict(os.environ, GODOT=str(self.engine), TMPDIR=str(self.base), GODOT_IMPORT_TIMEOUT="5",
                           GODOT_TEST_TIMEOUT="5", FIXTURE_ROOT=str(self.root), CALL_LOG=str(self.log),
                           FAKE_MARKERS=json.dumps(MARKERS), FAKE_MODE="timeout")
        process = subprocess.Popen(["bash", str(self.root / "tools/test_imported.sh")], env=environment,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while not self.log.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(self.log.exists(), "synthetic import started")
            process.terminate()
            output, errors = process.communicate(timeout=5)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)
        self.assertEqual(130, process.returncode, output + errors)
        self.assertEqual([], list(self.base.glob("abyssal-imported-*")))
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(["import"], [c["phase"] for c in calls])
        with self.assertRaises(ProcessLookupError):
            os.kill(calls[0]["pid"], 0)
        self.assertEqual("original cache", (self.root / ".godot/untouched").read_text())
        self.assertEqual("original sidecar", (self.root / "assets/imported/image.png.import").read_text())

    def test_suite_errors_and_timeouts_are_watchdog_failures(self):
        for mode, code in (("error", 1), ("timeout", 124)):
            with self.subTest(mode=mode):
                self.log.unlink(missing_ok=True)
                result, calls = self.run_fixture(FAKE_MODE=mode, FAIL_PHASE="test_imported_resources", GODOT_TEST_TIMEOUT="0.2")
                self.assertEqual(code, result.returncode)
                self.assertEqual("test_imported_resources", calls[-1]["phase"])


if __name__ == "__main__":
    unittest.main()
