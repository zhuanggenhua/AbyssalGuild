#!/usr/bin/env bash
# Private cache-backed validation; never imports into the working checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -B "$ROOT/tools/run_imported_tests.py" "$@"
