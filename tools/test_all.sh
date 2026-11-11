#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -p 'test_*.py' -v
for test in test_combat test_save_codec test_ui_smoke; do
  bash tools/test_godot.sh "res://tests/godot/$test.gd"
done
if [[ -f data/stackcraft.json ]]; then
  python3 tools/verify_source.py --data data
  for test in test_runtime test_special_recipes test_quests test_quest_integration; do
    bash tools/test_godot.sh "res://tests/godot/$test.gd"
  done
else
  echo 'SOURCE-DATA SUITES SKIPPED: import licensed data for full domain regression checks.'
fi
