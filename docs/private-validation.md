# Private imported-resource validation

From the repository root, after importing a licensed catalog and visual/audio
manifest, run:

```sh
bash tools/test_imported.sh
```

Use Godot 4.6.3 with its built-in FBX importer, Python 3, and the existing
`requirements.txt` dependencies. This command does not install anything, access
the network, run Unity, export a game, or publish private content. A different
Godot executable and bounded timeouts can be selected explicitly:

```sh
GODOT=/path/to/godot GODOT_IMPORT_TIMEOUT=180 GODOT_TEST_TIMEOUT=90 \
  bash tools/test_imported.sh
```

Timeouts are per phase, in seconds, greater than zero and at most 3600. Import
gets 180 seconds by default; each test gets 90 seconds. Failures stop the run.
The strict watchdog rejects engine/script errors even with exit status zero,
and terminates the engine process group on timeout or interruption.

## Required local inputs

- `data/stackcraft.json` and `data/manifest.json`, matching the catalog verifier.
- `assets/imported/manifest.json`, schema 1, with complete assets, materials,
  prefabs, and Main/Island scene metadata, and an empty missing-assets report.
- Every PNG, WAV and FBX declared by that manifest, with matching SHA-256 values.
  All three resource types are required. No paths may escape the import folder.
- Current owned scripts, scenes, and Godot tests, including the private probes.

The command rejects missing files, invalid paths, unsupported schemas/types,
changed hashes, symlink inputs, incomplete metadata and missing required test
files. The copied catalog is verified before Godot starts. A public checkout
without licensed inputs **fails this command** rather than reporting success or
silently skipping resource tests. See `data-import.md` and `visual-import.md`
for the separate licensed-input preparation steps.

## Isolation and evidence

The runner copies the necessary project files and only manifest-listed media to
a fresh temporary project. It never imports in the working checkout. Existing
`.godot`, `.import` and `.uid` sidecars, original source trees, exports and
unlisted private files are not reused. Godot regenerates its cache and sidecars
inside the disposable copy. `HOME`, the XDG home/runtime directories and `TMPDIR`
are isolated, so test saves/options and import settings do not use the user's
normal state. Temporary files are removed on success, failure, timeout and
handled interruption. Like other process cleanup, this cannot run after SIGKILL
or a machine crash; remove an abandoned `abyssal-imported-*` temporary directory
only after ensuring its process has stopped.

After headless import, a mandatory probe checks **every declared resource**:

- PNGs are cached `CompressedTexture2D` resources, not raw-image fallbacks.
- WAVs are cached nonempty audio streams.
- FBXs are cached `PackedScene` resources, and runtime model lookup uses them.
- Import remaps resolve to this project's `.godot/imported` directory.

The same imported copy then runs the board mesh, card/pack mesh, card overlays,
equipment interaction, audio mapping, visual bindings, combat sprite/flash,
combat presentation, combat feedback, Puff metadata/math, and UI/board integration suites listed in
`tools/run_imported_tests.py`. These include the real imported mesh/texture and
shader-material binding branches. Every suite must emit its own completion
marker. Any `SKIP`, missing completion marker, unavailable-cache fallback,
engine error, failed assertion, nonzero exit or timeout fails the command.

For synthetic runner guards and orchestration tests without licensed assets:

```sh
python3 -m unittest discover -s tests -p test_imported_runner.py -v
```

These tests cover input rejection, byte-identical original files/cache/sidecars,
disposable copies, import-before-suite ordering, mandatory completion evidence,
strict diagnostic failures, timeout/SIGTERM cleanup and no suites after failed import.
They simulate the engine and do not prove resource import themselves.

## Limits

A pass establishes cache-backed resource loading, data/geometry/UV/material
bindings and the covered headless UI behavior. It is **not GPU-rendered visual
acceptance, pixel parity, manual mouse/keyboard acceptance, typography/lighting
approval, audio listening acceptance, or proof of a distributable export**.
The command verifies private output hashes/catalog consistency; it does not
reimport Unity source, verify redistribution rights, or replace the source-lock
review. The Unity project is never opened.

This is a separate local validation entry point. It does not change
`tools/test_all.sh`, `tools/test_godot.sh`, the public CI workflow, or their
intentional source-free/no-import-cache behavior. Run the existing aggregate
regressions as well when changes require them. Never commit private data, media,
source snapshots, import caches or captured private artifacts.

## Fresh-checkout harness corrections

A fresh source recovery at the locked revision reverified all 1,327 hashes and
regenerated the catalog plus 173 private assets. This exposed two validation
harness differences that source-free checks alone did not cover:

- The imported project retains production canvas stretching. The synthetic
  Starter projection fixture now explicitly owns its logical viewport sizes,
  so its independent equations do not confuse window and canvas coordinates.
  Production stretch/camera settings are unchanged.
- The scene-transition integration script can still have audio-server playback
  references briefly after its board is removed. Six repeated cached-resource
  runs reproduced exit diagnostics in three runs, despite 24/24 assertions.
  It now allows the audio mix thread to drain after normal node teardown, using
  the same half-second cleanup interval as the audio regression. Six consecutive
  repeated runs then completed without leaked-resource or engine diagnostics.

Neither fix suppresses diagnostics or relaxes the runner's fail-on-error and
fail-on-skip behavior. Passing playback/resource checks is not listening
acceptance, and no private source, image, model, sound or screenshot is published.

With these corrections, the strict freshly imported run passed all **45 suites**
on official Godot 4.6.3, with 150 PNG, 19 WAV and 4 FBX inputs. The source-free
regression also passed 102 Python tests and 65 Godot suites. The full-data
ordinary runner completed 105 Godot suites; the corrected transition cleanup
was additionally exercised in the six repeated cached runs and strict private
runner above. These remain automated coverage statements, not final acceptance.
