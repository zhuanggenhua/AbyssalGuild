#!/usr/bin/env bash
# Intentionally source-free. Use test_all.sh in a separately licensed local setup.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

python3 - <<'PY'
from pathlib import Path

# Fail instead of silently using private inputs or a developer's import cache.
for name in ("source", "third_party", "data", "assets/imported", ".godot", "build", "artifacts"):
    path = Path(name)
    if path.exists() or path.is_symlink():
        raise SystemExit(f"PUBLIC-CI REFUSED: {name} exists; use a clean public checkout.")
for path in Path(".").glob(".env*"):
    raise SystemExit(f"PUBLIC-CI REFUSED: {path.name} exists; use a clean public checkout.")
print("Public checkout guard: PASS (no private input directories or project cache)")
PY

TEMP="$(mktemp -d "${TMPDIR:-/tmp}/abyssal-public-ci.XXXXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/home" "$TEMP/cache" "$TEMP/config" "$TEMP/data"
export HOME="$TEMP/home" XDG_CACHE_HOME="$TEMP/cache" XDG_CONFIG_HOME="$TEMP/config" XDG_DATA_HOME="$TEMP/data"
export GODOT="${GODOT:-godot}"
version="$("$GODOT" --version)"
if [[ "$version" != "4.6.3.stable.official.7d41c59c4" ]]; then
  printf 'PUBLIC-CI REFUSED: expected official Godot 4.6.3, got %s\n' "$version" >&2
  exit 1
fi
printf 'Godot version: %s\n' "$version"
printf '%s\n' \
  'SKIP: source-data suites in tools/test_all.sh (licensed data is intentionally absent).' \
  'SKIP: imported-data branches of mixed suites, including camera/audio/board/combat layout and UI gameplay.' \
  'SKIP: source FBX mesh checks and real gameplay/visual/input acceptance.'

# Assert failures in SceneTree scripts can hang or log an error without a nonzero
# engine exit status. Bound execution and reject engine/test error diagnostics.
timeout --kill-after=10s 300s bash tools/test_all.sh 2>&1 | tee "$TEMP/tests.log"
if grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:|FAIL:|Assertion failed)' "$TEMP/tests.log"; then
  echo 'PUBLIC-CI FAILED: engine or test error appeared in the log.' >&2
  exit 1
fi
if ! grep -q '^SOURCE-DATA SUITES SKIPPED:' "$TEMP/tests.log"; then
  echo 'PUBLIC-CI FAILED: expected source-data skip was not reported.' >&2
  exit 1
fi
echo 'Public source-free regression: PASS (licensed-content checks remain skipped).'
