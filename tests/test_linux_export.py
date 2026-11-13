"""Synthetic Linux export guards. Does not download templates or use private media."""

import hashlib
from contextlib import redirect_stdout
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import export_linux as runner


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()


class LinuxExportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="abyssal-export-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "checkout"
        self.output = self.base / "private-install"
        for directory in ("scripts", "scenes", "tools", "data", "assets/imported", "source", ".godot", "tests"):
            (self.root / directory).mkdir(parents=True)
        for path, text in {"project.godot": "config_version=5\n", "export_presets.cfg": "synthetic preset",
                           "scripts/main.gd": "# owned", "scenes/main.tscn": "# owned scene",
                           "scripts/main.gd.uid": "uid://existing", "scripts/private.txt": "never copy",
                           "tools/export_smoke.gd": "# external probe", "source/private.cs": "never copy",
                           ".godot/cache": "never reuse", "tests/probe.gd": "never pack", ".env": "never copy"}.items():
            (self.root / path).write_text(text)
        manifest = {"schema_version": 1, "assets": {}, "materials": {"m": {}}, "prefabs": {"p": {}},
                    "scenes": {"Main": {}, "Island": {}}, "missing": []}
        for kind in ("png", "wav", "fbx"):
            content = ("synthetic " + kind).encode()
            (self.root / "assets/imported" / ("asset." + kind)).write_bytes(content)
            manifest["assets"][kind] = {"kind": kind, "path": "asset." + kind, "sha256": hashlib.sha256(content).hexdigest()}
        (self.root / "assets/imported/manifest.json").write_bytes(encoded(manifest))
        (self.root / "assets/imported/unlisted.png").write_text("never copy")
        font_root = self.root / "assets/imported/fonts"
        font_root.mkdir()
        metrics = encoded({"source_font_guid": "synthetic-font", "source_ttf_guid": "synthetic-ttf"})
        blobs = {"source.ttf": b"synthetic font", "metrics.json": metrics, "LICENSE.txt": b"synthetic license"}
        for name, payload in blobs.items(): (font_root / name).write_bytes(payload)
        font_manifest = {"schema_version": 1, "source_commit": "synthetic", "missing": [],
                         "inputs": {"font": {"sha256": "a" * 64, "git_blob_sha1": "b" * 40, "repository_path": "Assets/synthetic.ttf"}},
                         "fonts": {"synthetic-font": {"ttf_guid": "synthetic-ttf", "font_path": "source.ttf", "metrics_path": "metrics.json", "license_path": "LICENSE.txt",
                                   "ttf_sha256": hashlib.sha256(blobs["source.ttf"]).hexdigest(), "metrics_sha256": hashlib.sha256(metrics).hexdigest(), "license_sha256": hashlib.sha256(blobs["LICENSE.txt"]).hexdigest()}}}
        (font_root / "manifest.json").write_bytes(encoded(font_manifest))
        pipeline = {"schema_version": 1, "source_commit": "synthetic", "target_platform": "Standalone", "inputs": font_manifest["inputs"]}
        pipeline_bytes = encoded(pipeline)
        (self.root / "assets/imported/render_pipeline.json").write_bytes(pipeline_bytes)
        (self.root / "assets/imported/render_pipeline.json.sha256").write_text(hashlib.sha256(pipeline_bytes).hexdigest() + "\n")
        catalog = {"schema_version": 1, "provenance": {"source_commit": "synthetic"}, "counts": {}, "guid_index": {}}
        for group in ("cards", "packs", "recipes", "quests", "encounters", "settings", "scenes", "referenced_prefabs"):
            catalog[group] = []
            catalog["counts"][group] = 0
        payload = encoded(catalog)
        (self.root / "data/stackcraft.json").write_bytes(payload)
        (self.root / "data/manifest.json").write_bytes(encoded({"schema_version": 1, "source_commit": "synthetic",
            "counts": catalog["counts"], "stackcraft_json_sha256": hashlib.sha256(payload).hexdigest(),
            "source_files_sha256": {}, "references": {"total": 0, "resolved": 0, "unresolved_external": []}}))
        self.archive = self.base / "templates.tpz"
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("templates/version.txt", runner.TEMPLATE_VERSION + "\n")
            archive.writestr(runner.TEMPLATE_MEMBER, "fake ELF")
            archive.writestr("templates/windows.exe", "not extracted")
            archive.writestr("../outside", "not extracted")

    def digest(self):
        return runner.sha256(self.archive)

    def test_pinned_archive_digest_rejects_changed_input(self):
        with self.assertRaisesRegex(runner.ValidationError, "SHA-256 mismatch"):
            runner.install_template(self.archive, self.base / "templates")
        self.assertFalse((self.base / "templates").exists())

    def test_extracts_only_verified_linux_member(self):
        destination = self.base / "templates"
        with patch.object(runner, "TEMPLATE_SHA256", self.digest()), patch.object(runner, "TEMPLATE_SIZE", 8):
            runner.install_template(self.archive, destination)
        self.assertEqual(["linux_release.x86_64", "version.txt"], sorted(p.name for p in destination.iterdir()))
        self.assertTrue(os.access(destination / "linux_release.x86_64", os.X_OK))
        self.assertFalse((self.base / "outside").exists())

    def test_template_size_is_checked(self):
        with patch.object(runner, "TEMPLATE_SHA256", self.digest()):
            with self.assertRaisesRegex(runner.ValidationError, "template size"):
                runner.install_template(self.archive, self.base / "templates")

    def test_template_symlink_is_rejected(self):
        link = self.base / "linked.tpz"
        link.symlink_to(self.archive)
        with self.assertRaisesRegex(runner.ValidationError, "regular official"):
            runner.install_template(link, self.base / "templates")

    def test_copy_only_runtime_allowlist_without_generated_files(self):
        project = self.base / "project"
        runner.copy_export_project(self.root, project, runner.private_inputs(self.root))
        self.assertTrue((project / "scripts/main.gd").is_file())
        self.assertTrue((project / "assets/imported/fonts/source.ttf").is_file())
        self.assertTrue((project / "assets/imported/fonts/LICENSE.txt").is_file())
        self.assertTrue((project / "assets/imported/render_pipeline.json").is_file())
        self.assertTrue((project / "assets/imported/render_pipeline.json.sha256").is_file())
        for path in ("source", "tests", "tools", ".godot", ".env", "scripts/main.gd.uid", "scripts/private.txt", "assets/imported/unlisted.png"):
            self.assertFalse((project / path).exists(), path)

    def test_owned_symlink_rejected(self):
        (self.root / "scripts/link.gd").symlink_to(self.root / "scripts/main.gd")
        with self.assertRaisesRegex(runner.ValidationError, "Symlink owned"):
            runner.copy_export_project(self.root, self.base / "project", runner.private_inputs(self.root))

    def test_existing_install_is_never_overwritten(self):
        self.output.mkdir()
        (self.output / "save").write_text("keep me")
        with self.assertRaisesRegex(runner.ValidationError, "already exists"):
            runner.run(self.archive, self.output, self.root)
        self.assertEqual("keep me", (self.output / "save").read_text())

    def test_checkout_destination_rejected(self):
        with self.assertRaisesRegex(runner.ValidationError, "outside the source"):
            runner.validate_output(self.root / "build/install", self.root)

    def test_other_git_checkout_destination_rejected(self):
        other = self.base / "other"
        other.mkdir()
        subprocess.run(["git", "init", "-q", str(other)], check=True)
        with self.assertRaisesRegex(runner.ValidationError, "outside Git"):
            runner.validate_output(other / "install", self.root)

    def test_symlink_destination_parent_rejected(self):
        link = self.base / "linked"
        link.symlink_to(self.base, target_is_directory=True)
        with self.assertRaisesRegex(runner.ValidationError, "must not contain symlinks"):
            runner.run(self.archive, link / "install", self.root)

    def test_public_checkout_fails_before_engine_or_template_work(self):
        (self.root / "data/stackcraft.json").unlink()
        with patch.object(runner, "install_template") as install:
            with self.assertRaisesRegex(runner.ValidationError, "Missing required"):
                runner.run(self.archive, self.output, self.root)
            install.assert_not_called()
        self.assertFalse(self.output.exists())

    def test_isolation_restores_environment_and_cwd_after_failure(self):
        before, cwd = dict(os.environ), Path.cwd()
        with self.assertRaisesRegex(RuntimeError, "fixture"):
            with runner.isolated(self.base):
                for name in runner.VARIABLES:
                    self.assertEqual(self.base, Path(os.environ[name]).parent)
                raise RuntimeError("fixture")
        self.assertEqual(before, dict(os.environ))
        self.assertEqual(cwd, Path.cwd())

    def test_export_order_source_removal_and_fresh_install(self):
        calls, projects = [], []
        before = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        def step(command, label, **kwargs):
            calls.append(label)
            if "--import" in command:
                projects.append(Path(command[command.index("--path") + 1]))
            if "--export-release" in command:
                Path(command[-1]).write_text("fake binary")
                Path(command[-1]).with_suffix(".pck").write_text("fake PCK")
            if "--main-pack" in command:
                self.assertFalse(projects[0].exists(), "source copy gone before PCK probe")
                self.assertEqual(runner.SMOKE_MARKER, kwargs["expected"])
        def native_startup(binary):
            self.assertEqual("native-state", Path(os.environ["HOME"]).parent.name)
            self.assertEqual([], list(Path(os.environ["XDG_DATA_HOME"]).iterdir()))
            self.assertEqual(projects[0].parent / "install", binary.parent)
        with patch.object(runner, "install_template"), patch.object(runner, "run_step", side_effect=step), patch.object(runner, "release_startup", side_effect=native_startup) as startup:
            runner.run(self.archive, self.output, self.root)
        self.assertEqual(4, len(calls))
        startup.assert_called_once()
        self.assertFalse(projects[0].parent.exists(), "temporary import and test saves are removed")
        self.assertFalse((self.output / ".user-data").exists(), "fresh installation has no QA saves")
        self.assertEqual(before, {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file()})
        self.assertEqual("passed", json.loads((self.output / "validation.json").read_text())["exported_pck_probe_editor_host"])

    def test_failed_export_retains_no_final_install(self):
        def fail(*args, **kwargs):
            raise runner.ValidationError("synthetic export failed")
        with patch.object(runner, "install_template"), patch.object(runner, "run_step", side_effect=fail):
            with self.assertRaisesRegex(runner.ValidationError, "synthetic"):
                runner.run(self.archive, self.output, self.root)
        self.assertFalse(self.output.exists())

    def fake_binary(self, code):
        binary = self.base / "fake-release"
        binary.write_text(f"#!{sys.executable}\n" + code)
        binary.chmod(0o700)
        return binary

    def test_native_early_exit_is_not_liveness(self):
        with tempfile.TemporaryFile(mode="w+") as log, redirect_stdout(log):
            with self.assertRaisesRegex(runner.ValidationError, "exited before"):
                runner.release_startup(self.fake_binary("pass\n"), seconds=0.2)

    def test_native_errors_fail_even_when_process_stays_alive(self):
        binary = self.fake_binary("import time\nprint('ERROR: fixture', flush=True)\ntime.sleep(30)\n")
        with tempfile.TemporaryFile(mode="w+") as log, redirect_stdout(log):
            with self.assertRaisesRegex(runner.ValidationError, "engine errors"):
                runner.release_startup(binary, seconds=0.2)

    def test_native_liveness_is_bounded_and_terminated(self):
        runner.release_startup(self.fake_binary("import time\ntime.sleep(30)\n"), seconds=0.2)

    def test_launcher_is_syntactically_valid_and_uses_private_state(self):
        runner.write_launcher(self.base)
        subprocess.run(["bash", "-n", str(self.base / "run-isolated.sh")], check=True)
        text = (self.base / "run-isolated.sh").read_text()
        for name in runner.VARIABLES:
            self.assertIn("export " + name + "=", text)
        self.assertIn('.user-data/', text)
        self.assertNotIn('--path', text)

    def test_preset_explicitly_includes_json_and_excludes_provenance(self):
        preset = (ROOT / "export_presets.cfg").read_text()
        self.assertIn('include_filter="data/stackcraft.json,assets/imported/manifest.json,assets/imported/render_pipeline.json,assets/imported/render_pipeline.json.sha256,assets/imported/fonts/*"', preset)
        self.assertIn('data/manifest.json"', preset)
        self.assertIn('binary_format/embed_pck=false', preset)


if __name__ == "__main__":
    unittest.main()
