#!/usr/bin/env bash
# Isolate logic tests from scene/editor configuration and writable user-data state.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/abyssal-tests.XXXXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/project" "$TEMP/home" "$TEMP/cache" "$TEMP/config" "$TEMP/data"
printf 'config_version=5\n' > "$TEMP/project/project.godot"
for item in scripts data tests assets scenes; do ln -s "$ROOT/$item" "$TEMP/project/$item"; done
export HOME="$TEMP/home" XDG_CACHE_HOME="$TEMP/cache" XDG_CONFIG_HOME="$TEMP/config" XDG_DATA_HOME="$TEMP/data"
python3 "$ROOT/tools/run_godot_test.py" "${GODOT:-godot}" --headless --path "$TEMP/project" --script "${1:-res://tests/godot/test_runtime.gd}"
