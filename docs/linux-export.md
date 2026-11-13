# Private Linux export

This local-only workflow builds a Godot **4.6.3 Linux x86_64 release** from
licensed imported data. It does not publish, upload, run Unity, install a system
package, or use the source checkout's import cache or normal save directories.
The resulting PCK contains licensed media and generated content. Keep it private
until redistribution rights are confirmed; public CI must not upload it.

## Later renderer-batch pack-only verification

The renderer-routing snapshot `a77407f` (local content-equivalent `bea7c17`)
passed a separate normal `--export-pack` flow on 2026-11-13. That command exports
project data only and did not require the otherwise unavailable full template
archive. It does not bypass the release workflow's template checks: no release
executable was built or tested by this route.

The existing private-input/hash checks, isolated runtime-only copy, fresh import,
export preset and strict external `export_smoke.gd` probe were retained. The
copied project was removed before the official editor loaded the resulting PCK.
The probe passed 776 checks with 150 PNG, 19 WAV and four FBX; the 555-file runtime
allowlist and New/Save/Continue/production Quit passed. It also loaded and checked
the new rendering graph and the selected PC renderer's absent custom pass. Every
owned packaged input matched the stated commit; later audio changes are not
covered. All package files and detailed input/hash records remain private.

This narrows packaged-resource acceptance only. It is not standalone release
execution, a new binary installation test, GPU equivalence or listening evidence.

## Prerequisites

- Linux x86_64, Python 3.10+, Git and the existing `requirements.txt` dependency.
- The official Godot editor `4.6.3.stable.official.7d41c59c4`.
- A complete private import prepared according to [recovery](recovery.md),
  [data import](data-import.md) and [visual import](visual-import.md).
- The standard, non-Mono official export-template archive. Download it from
  [Godot's 4.6.3 release](https://github.com/godotengine/godot/releases/tag/4.6.3-stable).

The archive is `Godot_v4.6.3-stable_export_templates.tpz` (1,255,918,323 bytes).
Its pinned SHA-256 is:

```text
3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8
```

This is the digest published by the
[official release asset API](https://api.github.com/repos/godotengine/godot/releases/assets/425557321),
checked on 2026-11-12. The entire archive was downloaded from the official release
and verified in the live validation. No mirror, custom template or locally
compiled engine was substituted. The runner itself never downloads anything.

## Build and validate

From the repository root, select an **unused private directory outside Git
checkouts** for the installation:

```sh
GODOT=/absolute/path/to/godot python3 tools/export_linux.py \
  --templates /private/downloads/Godot_v4.6.3-stable_export_templates.tpz \
  --output /private/exports/abyssal-linux-001
```

An existing output directory is refused, including its existing saves. Nothing
is overwritten to make a rerun succeed; use a new directory. A public checkout
without complete licensed data fails before Godot starts. Corrupt hashes,
missing PNG/WAV/FBX assets, symlink inputs and incomplete manifests also fail.

The runner:

1. Verifies the complete template archive, then extracts only the fixed Linux
   x86_64 release member and version into a disposable Godot template directory.
2. Copies owned runtime scripts/scenes, the validated catalog and only
   manifest-listed media into a temporary project. It rechecks the copied
   content. Original source, tests, tools, docs, credentials, saves, existing
   `.godot`, `.uid` and `.import` files are not copied.
3. Imports from scratch, then exports the `Linux private` preset. JSON runtime
   files are explicitly included. `data/manifest.json` is explicitly excluded:
   Godot recognizes JSON resources, so an include filter alone does not omit it.
4. Deletes the entire temporary project before checking the exported PCK.
   An external probe runs with the official editor hosting that exact PCK.
   It audits every packed file against the runtime allowlist, loads every PNG,
   WAV and FBX through its packed import cache, and exercises the main title,
   New, isolated Save, Continue and production Quit. The probe is not packaged.
5. Starts the actual standalone release executable with a second, fresh isolated
   user directory (without the PCK probe's saves), headlessly for three seconds,
   rejecting early exit or engine errors, then stops its process group with
   SIGTERM. This is a bounded **startup/liveness observation**, not normal Quit
   or a completed gameplay test on the release executable.
6. Retains only the executable, PCK, validation report and isolated launcher
   after all gates succeed. Temporary projects, templates and probe saves are
   removed. The final installation starts with no QA saves.

Import and export each default to 180 seconds. Set `GODOT_IMPORT_TIMEOUT` and
`GODOT_EXPORT_TIMEOUT` to change those phase limits. The PCK probe defaults to
90 seconds via `GODOT_TEST_TIMEOUT`. Limits must be greater than zero and at
most 3600 seconds. Existing strict watchdog checks reject engine/script errors,
failed assertions, skipped required coverage, missing completion markers,
nonzero exit and timeout. SIGTERM/interruption unwinds the temporary copy;
SIGKILL or a machine crash can leave an abandoned temporary directory.

The retained `validation.json` records engine/template versions, owned-input
and output SHA-256 hashes, and the precise automated coverage. It does not claim
bit-identical exports across repeated builds. Do not share the private PCK,
binary, generated report, local logs or saves as public CI artifacts.

## Launch independently of the source tree

```sh
/private/exports/abyssal-linux-001/run-isolated.sh
```

The launcher runs the adjacent executable and PCK, without the editor or a
`--path` pointing back at the source. `HOME`, XDG directories and `TMPDIR` are
installation-local under `.user-data/`. Each installation therefore has its
own test saves/options. A native display session is still needed. Do not run
multiple instances against the same installation's saves.

Native acceptance must separately cover title/New, opening and dragging cards,
Save & Title, Quit, relaunch and Continue, plus graphics, sound and input. The
export runner does not claim those desktop observations.

## Important testing limits

Official 4.6.3 release templates disable command-line path overrides. `--script`
is ignored rather than executing the external test. The runner therefore does
not use that flag on the release binary or mislabel an editor-hosted probe as a
release-binary gameplay pass. See the
[official startup code](https://github.com/godotengine/godot/blob/4.6.3-stable/main/main.cpp)
for the `OVERRIDE_PATH_ENABLED` behavior.

Using `--quit-after` to forcibly tear down the live title reproduced one retained
audio resource diagnostic. That is not accepted as a clean-shutdown test and is
not suppressed. The editor-hosted PCK probe uses the production Quit flow and
requires a clean complete log. The actual release binary's normal Quit must be
observed through native interaction separately.

On 2026-11-12 the real export and editor-hosted PCK probe passed **700 checks**
with **150 PNG, 19 WAV and 4 FBX**, including a **486-file** runtime-only audit.
The standalone release remained alive for the three-second headless observation
without an engine error before harness termination. These results do not prove
GPU rendering, visual parity, listening quality, mouse/keyboard acceptance,
Windows behavior, cross-machine installation, or redistribution permission.

## Source-free harness regression

```sh
python3 -m unittest discover -s tests -p test_linux_export.py -v
```

Nineteen synthetic checks cover archive digest/member guards, runtime copy
allowlists, symlinks, private output locations, existing-file preservation,
missing private data, environment restoration, export/probe ordering, source
copy removal, fresh final saves, failure cleanup, bounded native process checks
and launcher syntax. They do not download or execute a real template. These are
also discovered by the existing aggregate Python suite.


## Actual release native-window verification

The exported executable and adjacent PCK were then launched directly from the
separate private installation on the native Linux desktop, without the editor,
source project path or external test script. This was a fresh game rather than
one of the combat prerequisite fixtures. Ordinary pointer and keyboard input
verified title → New preferences → Confirm, all four Starter draws, wheel zoom,
card dragging/tail splitting, and the ten-second Villager/Berry Bush harvest.
The resulting five cards included one earned Berry and the separated Wood.

Normal Save & Title and confirmed Quit closed the release. A cold relaunch and
ordinary Load/Continue restored the five cards, all three stacks, active craft
progress (2.261523 seconds), day elapsed time and paused state. Whole-campaign
JSON before and after continuation matched exactly. A second normal Save & Title
and confirmed Quit also closed cleanly. Both complete native logs contained
only the known unsupported-VSync warning, with no script, engine or leaked
resource diagnostics.

This narrows the actual Linux release input/render/save/shutdown gap separately
from the editor-hosted PCK probe. The native run used llvmpipe Compatibility and
Dummy audio, so it does not prove sound quality, other distributions/machines,
Windows/controller/touch support or original Unity rendering. The same exported
bytes were used for both launches. Their private hashes, screenshots and save
comparisons are retained locally, not published in the public repository.


## Source-font PCK follow-up (2026-11-12)

The source-component snapshot was imported into a fresh isolated project and
exported as a private PCK with the official Godot 4.6.3 editor. After deleting the
copied project, the editor-hosted pack probe passed 754 checks, including source
font/metrics/license presence, 150 PNG, 19 WAV, four FBX and New/Save/Continue/
production-Quit model paths. The runtime-only allowlist audited 535 pack files.
The pack and licensed media remain outside Git and must not be published.

This follow-up did not build a new standalone release executable: the verified
export-template archive was not available at the checked locations. It proves
pack inclusion and editor-hosted loading, not release-binary installation, GPU
rendering or listening acceptance.
