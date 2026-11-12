#!/usr/bin/env python3
"""Build and smoke-test a private Linux x86_64 export without touching the checkout.

No network, installation, publication, Unity, or desktop automation is performed.
The official archive must already be available. See docs/linux-export.md.
"""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import zipfile

sys.dont_write_bytecode = True
from run_imported_tests import ValidationError, copy_file, private_inputs, run_step
import run_godot_test as watchdog
from verify_source import verify

ROOT = Path(__file__).resolve().parents[1]
ENGINE_VERSION = "4.6.3.stable.official.7d41c59c4"
TEMPLATE_VERSION = "4.6.3.stable"
TEMPLATE_SHA256 = "3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8"
TEMPLATE_MEMBER = "templates/linux_release.x86_64"
TEMPLATE_SIZE = 71075864
BINARY = "AbyssalGuild.x86_64"
SMOKE_MARKER = r"LINUX EXPORTED PACK SMOKE: PASS \([1-9]\d* checks; [1-9]\d* PNG, [1-9]\d* WAV, [1-9]\d* FBX; New/Save/Continue/production Quit\)"
VARIABLES = {"HOME": "home", "XDG_CACHE_HOME": "cache", "XDG_CONFIG_HOME": "config",
             "XDG_DATA_HOME": "data", "XDG_STATE_HOME": "state", "XDG_RUNTIME_DIR": "runtime", "TMPDIR": "tmp"}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validate_output(output, root):
    if output.exists() or output.is_symlink():
        raise ValidationError("Output already exists; choose a new private installation directory")
    if root == output or root in output.parents:
        raise ValidationError("Export output must be outside the source checkout")
    parent = next(parent for parent in output.parents if parent.is_dir())
    result = subprocess.run(["git", "-C", str(parent), "rev-parse", "--show-toplevel"],
                            capture_output=True, timeout=10)
    if result.returncode == 0:
        raise ValidationError("Export output must be outside Git repositories; it contains private licensed media")


def install_template(archive, destination):
    if not archive.is_file() or archive.is_symlink():
        raise ValidationError("Supply a regular official template archive with --templates")
    if sha256(archive) != TEMPLATE_SHA256:
        raise ValidationError("Official Godot 4.6.3 template archive SHA-256 mismatch")
    with zipfile.ZipFile(archive) as source:
        if source.read("templates/version.txt").decode().strip() != TEMPLATE_VERSION:
            raise ValidationError("Unexpected export template version")
        # Never extractall: only this fixed Linux executable is materialized.
        info = source.getinfo(TEMPLATE_MEMBER)
        if info.file_size != TEMPLATE_SIZE:
            raise ValidationError("Unexpected Linux release template size")
        destination.mkdir(parents=True, mode=0o700)
        template = destination / "linux_release.x86_64"
        with source.open(info) as reader, template.open("wb") as writer:
            shutil.copyfileobj(reader, writer)
        template.chmod(0o700)
        (destination / "version.txt").write_text(TEMPLATE_VERSION + "\n")


def copy_export_project(root, project, paths):
    for relative in ("project.godot", "export_presets.cfg", "data/stackcraft.json", "data/manifest.json",
                     "assets/imported/manifest.json"):
        copy_file(root / relative, project / relative, root)
    for relative in paths:
        relative = "assets/imported/" + relative
        copy_file(root / relative, project / relative, root)
    for directory in ("scripts", "scenes"):
        source = root / directory
        if not source.is_dir() or source.is_symlink():
            raise ValidationError("Missing or symlink owned project directory: " + directory)
        for path in sorted(source.rglob("*")):
            if path.is_symlink():
                raise ValidationError("Symlink owned input: " + str(path.relative_to(root)))
            if path.is_file() and path.suffix in (".gd", ".gdshader", ".tscn", ".tres"):
                copy_file(path, project / path.relative_to(root), root)


@contextmanager
def isolated(base):
    previous = {name: os.environ.get(name) for name in VARIABLES}
    cwd = Path.cwd()
    try:
        for name, directory in VARIABLES.items():
            path = base / directory
            path.mkdir(mode=0o700)
            os.environ[name] = str(path)
        os.chdir(base)
        yield
    finally:
        os.chdir(cwd)
        for name, value in previous.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value


def write_launcher(install):
    lines = ['#!/usr/bin/env bash', 'set -euo pipefail',
             'cd -- "$(dirname -- "${BASH_SOURCE[0]}")"', 'umask 077',
             '# Private installation-local state, separate from normal Godot saves.']
    for name, directory in VARIABLES.items():
        lines += [f'export {name}="$PWD/.user-data/{directory}"', f'mkdir -p -- "${name}"']
    lines += [f'exec "./{BINARY}" "$@"', '']
    launcher = install / "run-isolated.sh"
    launcher.write_text("\n".join(lines))
    launcher.chmod(0o700)


def release_startup(binary, seconds=3):
    """Observe bounded native startup, then stop it; do not claim normal Quit."""
    print("\n=== Standalone release startup/liveness (harness termination, not Quit) ===", flush=True)
    process = subprocess.Popen([str(binary), "--headless", "--verbose"],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        output = watchdog.stop_process_tree(process)
    except BaseException:
        watchdog.stop_process_tree(process)
        raise
    else:
        watchdog.relay(output)
        raise ValidationError("Standalone release exited before the startup observation completed")
    watchdog.relay(output)
    if watchdog.FAILURE.search(watchdog.ANSI_ESCAPE.sub(b"", output)):
        raise ValidationError("Standalone release startup emitted engine errors")
    print(f"Release startup/liveness: observed {seconds:g}s, then harness SIGTERM; no clean-Quit claim", flush=True)


def run(archive, output, root=ROOT):
    root = root.resolve()
    output = output.absolute()
    # Refuse symlink parents rather than silently exporting elsewhere.
    if any(parent.is_symlink() for parent in (output, *output.parents)):
        raise ValidationError("Output path must not contain symlinks")
    output = output.resolve()
    validate_output(output, root)
    paths = private_inputs(root)
    engine = os.environ.get("GODOT", "godot")
    engine = shutil.which(engine) or str(Path(engine).absolute())
    archive = archive.absolute()
    with tempfile.TemporaryDirectory(prefix="abyssal-export-") as temporary:
        base = Path(temporary)
        with isolated(base):
            install_template(archive, base / "data/godot/export_templates" / TEMPLATE_VERSION)
            run_step([engine, "--headless", "--version"], "Verify official editor version",
                     expected=r"(?m)^" + ENGINE_VERSION.replace(".", r"\.") + r"$", timeout="15")
            project = base / "project"
            copy_export_project(root, project, paths)
            private_inputs(project)
            verify(project / "data")
            code_hashes = {str(path.relative_to(project)): sha256(path)
                           for path in sorted(project.rglob("*")) if path.is_file()
                           and path.parts[len(project.parts)] not in ("data", "assets")}
            print("Private input hashes/catalog: PASS", flush=True)
            command = [engine, "--headless", "--path", str(project)]
            run_step(command + ["--editor", "--import"], "Import isolated export resources",
                     timeout=os.environ.get("GODOT_IMPORT_TIMEOUT", "180"))
            install = base / "install"
            install.mkdir(mode=0o700)
            run_step(command + ["--export-release", "Linux private", str(install / BINARY)],
                     "Export Linux release", timeout=os.environ.get("GODOT_EXPORT_TIMEOUT", "180"))
            if sorted(path.name for path in install.iterdir()) != ["AbyssalGuild.pck", BINARY]:
                raise ValidationError("Export must produce only the standalone Linux executable and PCK")
            if any(not path.is_file() or path.is_symlink() or path.stat().st_size == 0 for path in install.iterdir()):
                raise ValidationError("Missing/empty/unsafe standalone export")
            # Remove the entire imported project before running the binary. It
            # must load only its PCK, never this checkout's .godot or raw assets.
            shutil.rmtree(project)
            probe = base / "export_smoke.gd"
            copy_file(root / "tools/export_smoke.gd", probe, root)
            # Official release templates disable --script/--main-pack overrides.
            # Run the exact PCK with the official editor as a separate check.
            run_step([engine, "--headless", "--main-pack", str(install / "AbyssalGuild.pck"), "--script", str(probe)],
                     "Run exported PCK probe (editor host)", expected=SMOKE_MARKER,
                     timeout=os.environ.get("GODOT_TEST_TIMEOUT", "90"))
            native_state = base / "native-state"
            native_state.mkdir(mode=0o700)
            with isolated(native_state):
                release_startup(install / BINARY)
            report = {"schema_version": 1, "engine_version": ENGINE_VERSION,
                      "template_archive_sha256": TEMPLATE_SHA256, "owned_inputs_sha256": code_hashes,
                      "export_sha256": {p.name: sha256(p) for p in sorted(install.iterdir())},
                      "exported_pck_probe_editor_host": "passed",
                      "release_startup": "observed 3 seconds; harness SIGTERM; not normal Quit",
                      "gpu_manual_audio_acceptance": "not performed"}
            (install / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
            write_launcher(install)
            # Publication is never part of this command. Retain only a private
            # local installation after every gate has passed, with fresh saves.
            validate_output(output, root)
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(install, output)
            output.chmod(0o700)
    print(f"LINUX PRIVATE EXPORT: PASS\nInstallation: {output}\nLaunch: {output / 'run-isolated.sh'}")
    print("Contains licensed private content. Do not upload. GPU/manual/listening acceptance remains separate.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--templates", required=True, type=Path, help="verified official 4.6.3 export_templates.tpz")
    parser.add_argument("--output", required=True, type=Path, help="new private directory outside Git checkouts")
    args = parser.parse_args(argv)
    def interrupt(*_):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupt)
    try:
        run(args.templates, args.output)
    except ValidationError as error:
        print(f"LINUX EXPORT FAILED: {error}", file=sys.stderr)
        return error.code
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print(f"LINUX EXPORT FAILED: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("LINUX EXPORT INTERRUPTED", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
