#!/usr/bin/env python3
"""Validate licensed resources in a disposable, fully copied Godot project."""

from contextlib import redirect_stderr, redirect_stdout
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import sys
import tempfile

sys.dont_write_bytecode = True
import run_godot_test as watchdog


ROOT = Path(__file__).resolve().parents[1]
# Completion evidence is deliberate: exit(0) alone must not turn an early return
# or a private-resource skip into a successful validation.
SUITES = (
    ("test_imported_resources", r"Private imported resources: PASS \([1-9]\d* PNG, [1-9]\d* WAV, [1-9]\d* FBX\)"),
    ("test_source_board_mesh", r"Source board mesh: PASS \([1-9]\d* models,"),
    ("test_card_mesh_binding", r"Source card/pack mesh: PASS \([1-9]\d* bindings; actual cached FBX"),
    ("test_card_overlays", r"Private card overlays: PASS \([1-9]\d* labels, [1-9]\d* panels; actual cached FBX\)"),
    ("test_puff_view", r"Private native Puff view: PASS"),
    ("test_puff_simulation", r"Private Puff simulation: PASS"),
    ("test_equipment_display", r"Private equipment interaction: PASS"),
    ("test_audio_feedback", r"Private source audio: [1-9]\d* SFX decoded and playback-start checked"),
    ("test_visual_assets", r"Visual source bindings: PASS"),
    ("test_combat_sprite_binding", r"Private combat sprites: PASS"),
    ("test_combat_presentation", r"Combat presentation checks: [1-9]\d* passed"),
    ("test_combat_feedback_ui", r"Combat feedback UI checks: [1-9]\d* passed / [1-9]\d* total"),
    ("test_ui_smoke", r"UI checks: [1-9]\d* passed / [1-9]\d* total"),
    ("test_held_stack_board", r"Held stack board checks: [1-9]\d* passed / [1-9]\d* total"),
    ("test_cycle_action_visibility", r"Cycle action visibility: [1-9]\d* passed / [1-9]\d* total"),
    ("test_cycle_board", r"Cycle board checks: [1-9]\d* passed / [1-9]\d* total"),
    ("test_puff_board", r"Puff board checks: [1-9]\d* passed / [1-9]\d* total"),
    ("test_camera_board", r"Camera board checks: [1-9]\d* passed / [1-9]\d* total"),
    ("test_board_integration", r"Board integration checks: [1-9]\d* passed / [1-9]\d* total"),
    ("test_trade_collection_ui", r"Trade/collection UI checks: [1-9]\d* passed / [1-9]\d* total"),
    ("test_vendor_unlock_board", r"Vendor unlock board checks: [1-9]\d* passed / [1-9]\d* total"),
    ("test_navigation_ui", r"Navigation UI checks: [1-9]\d* passed / [1-9]\d* total"),
    ("test_options_ui", r"Options UI checks: [1-9]\d* passed / [1-9]\d* total"),
    ("test_equipment_board", r"Equipment board checks: [1-9]\d* passed / [1-9]\d* total"),
    ("test_slot_management_ui", r"Slot management UI checks: [1-9]\d* passed / [1-9]\d* total"),
    ("test_slot_ui", r"Slot UI checks: [1-9]\d* passed / [1-9]\d* total"),
    ("test_combat_board", r"Combat board checks: [1-9]\d* passed / [1-9]\d* total"),
)
SKIPPED = re.compile(r"\bSKIP(?:PED)?\b|source data unavailable|FBX unavailable|fallback verified here", re.I)


class ValidationError(Exception):
    def __init__(self, message, code=1):
        super().__init__(message)
        self.code = code


def require_regular(path, base):
    """Reject symlinks, including parent links, before copying any input."""
    for part in (path, *path.parents):
        if part == base:
            break
        if part.is_symlink():
            raise ValidationError(f"Symlink input is not supported: {part.relative_to(base)}")
    if not path.is_file():
        raise ValidationError(f"Missing required private/project file: {path.relative_to(base)}")


def read_json(path, base):
    require_regular(path, base)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, UnicodeError) as error:
        raise ValidationError(f"Invalid JSON: {path.relative_to(base)}: {error}") from error
    if not isinstance(value, dict) or value.get("schema_version") != 1:
        raise ValidationError(f"Unsupported/missing schema: {path.relative_to(base)}")
    return value


def private_inputs(root):
    """Fail before launching Godot when the private input set is incomplete."""
    read_json(root / "data/stackcraft.json", root)
    read_json(root / "data/manifest.json", root)
    manifest = read_json(root / "assets/imported/manifest.json", root)
    for name in ("assets", "materials", "prefabs", "scenes"):
        if not isinstance(manifest.get(name), dict) or not manifest[name]:
            raise ValidationError(f"Private visual manifest needs nonempty {name}")
    if manifest.get("missing") != []:
        raise ValidationError("Private visual manifest reports missing assets (or lacks a missing report)")
    if not {"Main", "Island"} <= manifest["scenes"].keys():
        raise ValidationError("Private visual manifest needs Main and Island scenes")
    paths, kinds = set(), set()
    for entry in manifest["assets"].values():
        if not isinstance(entry, dict):
            raise ValidationError("Private asset record must be an object")
        relative = entry.get("path", "")
        if (not isinstance(relative, str) or not relative or ".." in relative
                or "\\" in relative or ":" in relative or PurePosixPath(relative).is_absolute()
                or PurePosixPath(relative).as_posix() != relative):
            raise ValidationError(f"Unsafe private resource path: {relative!r}")
        kind = entry.get("kind")
        if kind not in ("png", "wav", "fbx") or Path(relative).suffix.lower() != "." + kind:
            raise ValidationError(f"Unsupported private resource type: {relative}")
        if relative in paths:
            raise ValidationError(f"Duplicate private resource path: {relative}")
        path = root / "assets/imported" / relative
        require_regular(path, root)
        digest = entry.get("sha256", "")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ValidationError(f"Missing/invalid private resource SHA-256: {relative}")
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValidationError(f"Private resource SHA-256 mismatch: {relative}")
        paths.add(relative)
        kinds.add(kind)
    if kinds != {"png", "wav", "fbx"}:
        raise ValidationError("Private validation requires PNG, WAV and FBX assets")
    return sorted(paths)


def copy_file(source, destination, root):
    require_regular(source, root)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def copy_project(root, project, paths):
    for relative in ("project.godot", "data/stackcraft.json", "data/manifest.json",
                     "assets/imported/manifest.json"):
        copy_file(root / relative, project / relative, root)
    for relative in paths:
        relative = "assets/imported/" + relative
        copy_file(root / relative, project / relative, root)
    # Copy owned code only. Do not reuse generated imports, UIDs, editor caches,
    # source snapshots, exports, or arbitrary private files beside the manifest.
    for directory in ("scripts", "scenes", "tests/godot"):
        source = root / directory
        if not source.is_dir() or source.is_symlink():
            raise ValidationError(f"Missing or symlink project directory: {directory}")
        for path in source.rglob("*"):
            if path.is_symlink():
                raise ValidationError(f"Symlink input is not supported: {path.relative_to(root)}")
            if path.is_file() and path.suffix not in (".uid", ".import", ".pyc"):
                copy_file(path, project / path.relative_to(root), root)
    for name, _ in SUITES:
        require_regular(project / "tests/godot" / (name + ".gd"), project)


def run_step(command, label, expected=None, timeout=None):
    print(f"\n=== {label} ===", flush=True)
    previous = os.environ.get("GODOT_TEST_TIMEOUT")
    if timeout is not None:
        os.environ["GODOT_TEST_TIMEOUT"] = timeout
    try:
        # Reuse the strict watchdog in-process, including its process-tree kill
        # and zero-exit diagnostic checks. Keep each phase's evidence separate.
        with tempfile.TemporaryFile(mode="w+", encoding="utf-8", errors="replace") as log:
            with redirect_stdout(log), redirect_stderr(log):
                code = watchdog.main(command)
            log.seek(0)
            output = log.read()
    finally:
        if previous is None:
            os.environ.pop("GODOT_TEST_TIMEOUT", None)
        else:
            os.environ["GODOT_TEST_TIMEOUT"] = previous
    print(output, end="", flush=True)
    if code:
        raise ValidationError(f"{label} failed (exit {code})", code)
    clean = watchdog.ANSI_ESCAPE.sub(b"", output.encode()).decode()
    if SKIPPED.search(clean):
        raise ValidationError(f"{label} skipped required private coverage")
    if expected and not re.search(expected, clean):
        raise ValidationError(f"{label} did not report required completion evidence")


def run(root=ROOT):
    paths = private_inputs(root)
    engine = os.environ.get("GODOT", "godot")
    # Resolve a relative executable path before changing the engine's cwd.
    engine = shutil.which(engine) or str(Path(engine).absolute())
    with tempfile.TemporaryDirectory(prefix="abyssal-imported-") as temporary:
        base = Path(temporary)
        project = base / "project"
        copy_project(root, project, paths)
        for variable, directory in (("HOME", "home"), ("XDG_CACHE_HOME", "cache"),
                                    ("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data"),
                                    ("XDG_STATE_HOME", "state"), ("XDG_RUNTIME_DIR", "runtime"),
                                    ("TMPDIR", "tmp")):
            path = base / directory
            path.mkdir(mode=0o700)
            os.environ[variable] = str(path)
        # Revalidate the copied bytes, not only the possibly changing checkout.
        private_inputs(project)
        from verify_source import verify
        verify(project / "data")
        print("Private input hashes/catalog: PASS", flush=True)
        command = [engine, "--headless", "--path", str(project)]
        run_step(command + ["--editor", "--import"], "Import private resources",
                 timeout=os.environ.get("GODOT_IMPORT_TIMEOUT", "180"))
        for name, expected in SUITES:
            run_step(command + ["--script", f"res://tests/godot/{name}.gd"], name, expected)
        print(f"\nPRIVATE IMPORTED VALIDATION: PASS ({len(SUITES)} suites; no GPU/manual/listening acceptance)")


def main():
    if sys.argv[1:]:
        print("Usage: bash tools/test_imported.sh\nEnvironment: GODOT, GODOT_IMPORT_TIMEOUT (default 180), GODOT_TEST_TIMEOUT (default 90).")
        return 0 if sys.argv[1:] in (["--help"], ["-h"]) else 2
    # Let the watchdog stop the engine tree, then unwind the temporary directory.
    def interrupt(*_):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupt)
    try:
        run()
    except ValidationError as error:
        print(f"PRIVATE IMPORTED VALIDATION FAILED: {error}", file=sys.stderr)
        return error.code
    except (OSError, ValueError, KeyError, ImportError) as error:
        print(f"PRIVATE IMPORTED VALIDATION FAILED: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("PRIVATE IMPORTED VALIDATION INTERRUPTED", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
