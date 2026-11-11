# Original StackCraft static-data import

This is a **static source-audit slice**, not a completed Unity-to-Godot gameplay port. It neither launches Unity nor executes the original scripts. It is based on the original `Assets/StackCraft` tree supplied from CardLoop commit `a11a89b04cea8370476f2559b639bb9b4cbc08d8`, not a later migration package.

## Licensing boundary

Generated JSON contains source-derived names, descriptions, values, configuration, and identifiers. Conversion does not grant redistribution rights. Keep `data/stackcraft.json` and `data/manifest.json` local and ignored until source and third-party licensing are cleared. Do not commit original `.cs`, `.asset`, `.prefab`, textures, audio, fonts, PDFs, or the source tree. The public automated tests below use entirely synthetic fixtures. The importer records `license_status: not_cleared_for_redistribution` regardless of where it runs.

## Reproduce

Requires Python 3.10+ and PyYAML 6.x (validated with 6.0.3):

```sh
python -m pip install 'PyYAML==6.0.3'
python tools/import_stackcraft.py --source /path/to/original/Assets/StackCraft --output data
python tools/verify_source.py --data data --source /path/to/original/Assets/StackCraft
python -m unittest discover -s tests -p test_import_stackcraft.py -v
```

No source files are changed. Only the output directory is created or overwritten. There are no timestamps, local absolute paths, random IDs, or machine-dependent fields in output. Output is UTF-8 canonical, sorted-key JSON with stable file ordering. Repeated imports of the same inputs are byte-identical. `--source-commit` is an attribution label, **not proof of Git ancestry**: confirm the source checkout/archive independently. SHA-256 checks demonstrate the exact files used and detect subsequent drift.

For verification without the original source:

```sh
python tools/verify_source.py --data data
```

This checks hashes, counts, unique record GUIDs and gameplay IDs, GUID-to-path mappings, source-hash consistency, the stacking matrix, and the complete reference report. With `--source`, it also hashes every recorded input and fully reimports for byte-for-byte comparison. A manifest is an integrity ledger, not a cryptographic signature or an independent authenticity guarantee.

## Version 1 schema

`stackcraft.json` contains:

- `schema_version`: `1`.
- `provenance`: project, commit label, relative source root, licensing status, scope.
- `counts`: number of records in each collection.
- `cards`, `packs`, `recipes`, `quests`, `encounters`, `settings`: ordered record arrays.
- `enums`: named integer mappings parsed from the original script declarations. Numeric serialized enums remain numeric.
- `guid_index`: all GUIDs found in the StackCraft tree's `.meta` files, mapped to `source_path`, `kind`, and, for imported gameplay assets, `group`. An index entry proves the source exists, **not** that a Godot art/resource conversion exists.
- `scenes`: all three source scenes, including Title's initial gameplay choices.
- `referenced_prefabs`: recursively referenced prefabs reached from those scenes. Cycles are deduplicated. This is not every unrelated prefab in the project.

Gameplay asset record:

```json
{
  "guid": "original-asset-meta-guid",
  "source_path": "Resources/Cards/Example.asset",
  "source_sha256": "sha256-of-original-file",
  "script_class": "CardDefinition",
  "name": "Card_Example",
  "file_id": "11400000",
  "fields": { "id": "original-gameplay-id", "displayName": "Example" },
  "unity_fields": { "m_Script": { "fileID": "11500000", "guid": "original-script-guid", "type": 3 } }
}
```

All serialized gameplay properties are retained under `fields`, including subclass fields such as travel targets, chest capacity and pack slots. Unity `m_` metadata is retained separately under `unity_fields`; nothing is silently replaced with a new identifier. Nested lists and their order, weights, numeric values and reference objects are preserved. Unity's empty YAML scalar maps to JSON `null`, which consumers should interpret according to the original field's type. Unity booleans serialized as `0` and `1` remain integers.

**Every `fileID` and document `file_id` is a decimal string.** Unity object IDs can exceed the exact integer range of Godot JSON numbers. Cross-asset lookup should use `guid`; use the string `fileID` only to select an object within an asset. A null reference is `{ "fileID": "0" }`, not a missing record.

**Absent fields are not default zero.** This importer captures serialized source data, not an emulation of the Unity constructor/deserializer. Some older assets omit newer declaration fields. For example, CardDefinition's missing `produceCard` has a null default and missing `produceInterval` has a 10-second initializer. A gameplay implementation must apply original type defaults and behavior, and distinguish them from explicitly serialized zero values. No inheritance or property-getter semantics are executed by this importer.

`StackingRulesMatrix.fields.rules` preserves the original packed hexadecimal string; `decoded.rules` provides little-endian signed int32 values, `decoded.size` is the number of CardCategory members, and the index is `bottom_category * size + top_category`. Packed numeric-looking strings are deliberately not interpreted as YAML octal integers.

Scene/prefab record:

```json
{
  "guid": "original-meta-guid",
  "name": "Main",
  "source_path": "Scenes/Main.unity",
  "source_sha256": "sha256-of-original-file",
  "documents": [
    {
      "class_id": 114,
      "file_id": "123456",
      "object_type": "MonoBehaviour",
      "script_class": "CardManager",
      "fields": {}
    }
  ]
}
```

`script_class` is provided when a script GUID resolves inside StackCraft, using its source filename. Documents preserve all serialized properties, including GameObjects, Transforms, Cameras, board render settings, prefab source links and prefab modifications. **Prefab overrides are retained, not flattened**: to recreate a scene, apply its modifications to the referenced prefab's matching object IDs. The data is an audit representation rather than a drop-in Godot scene.

`manifest.json` records source-file SHA-256 values for all metadata, all StackCraft C# scripts used for definition/enum auditing, imported assets, scene files and reached prefabs. It also hashes the canonical JSON, records counts, explicitly lists excluded assets and reports every unresolved GUID with its field path. It does not hash or embed all source texture/audio bytes, and it does not prove fileID-level subasset validity for those binary resources.

## Validated source inventory

- Cards: 103
- Packs: 11
- Recipes: 90
- Quests: 66
- Encounters: 3
- Gameplay settings: 2
- Scenes: 3 (Island, Main, Title)
- Recursively reached prefabs: 31
- GUID reference occurrences: 2,407
- References resolved within StackCraft: 2,019
- External GUID occurrences explicitly reported: 388
- Unresolved gameplay-asset GUID occurrences: 0

The three `Settings/URP/*.asset` files are deliberately excluded from gameplay import and listed with hashes and reasons in the manifest. Unity rendering-pipeline settings cannot be applied as Godot gameplay settings. The 388 external references occur in scene/prefab documents, including Unity package scripts and resources outside this source subtree; they are not silently declared migrated. Resolving every external package and verifying binary subassets is a later task.

## Initial setup evidence for runtime integration

Use `scenes[].documents[].script_class` to find `CardManager` and `QuestManager`. Their fields retain settings references, ordered quest groups, spawn assets and positions.

- Main `defaultSpawnCards`: GUID `51c2d41ab5d413649adfbe0e3bb29d85`; position `(-3.5, 0, 0.6)`; radius `1.2`.
- Island `defaultSpawnCards`: GUID `413f08c4a1c64ed46a8b1aac38a088f6`; position `(-3, 0, 1)`; radius `1`.
- CardSettings GUID: `33732890bf898dd4ab50492bb20510a2`; base card limit `24`; hunger per character `2`.
- Title's `GameplayPrefsUI.durationSlider` points to the Slider whose `m_MinValue=60`, `m_MaxValue=180`, `m_Value=120` seconds. The friendly-mode toggle begins with `m_IsOn=0`.
- Day length is selected by the title UI and passed through GameplayPrefs to TimeManager. It is **not** a serialized DayCycleManager field.
- Vendor definitions and placements may be prefab modifications, not direct standalone components. Preserve the source prefab plus the scene's `m_Modifications` when rebuilding them.

These facts identify where values came from. They do not validate screen layout, drag/stack behavior, combat, crafting, saves, or visual parity in Godot.

## Automated coverage

Fourteen synthetic tests cover type preservation, enum values, repeatability, standalone and source-backed verification, corrupted output, changed source, tampered counts, dangling gameplay references, duplicate GUIDs, duplicate YAML keys, multiple Unity documents, large object IDs, explicit external-reference reporting, null references, and recursive/cyclic prefab dependencies. The same verifier additionally passed against the original source snapshot. No test fixture embeds template source or art.

## Explicit logic-only recovery

When a read connector can restore all text inputs but not large binary media,
`--allow-missing-visual-assets` permits a **logic-only** import. It retains each
missing file's real `.meta` GUID, creates no substitute source files, and records
sorted `missing_visual_assets` in both provenance and manifest. Only known binary
media extensions can be absent; scripts, definitions, prefabs and scenes remain
mandatory. The default import remains strict. `verify_source.py --source ...`
reimports with the recorded mode and checks the missing-file report too.

```sh
python3 tools/import_stackcraft.py --source /path/to/Assets/StackCraft --allow-missing-visual-assets
python3 tools/verify_source.py --source /path/to/Assets/StackCraft
```

This does **not** make a partial source pass `check_source_lock.py`, prove visual
parity, or grant redistribution permission. The 2026-11-11 cloud recovery checked
1324 available files byte-for-byte against the lock; missing originals were
`Documentation.pdf`, `Sounds/KingsFeast.wav`, and `Sprites/Artwork.png`. All 275
serialized gameplay entries, 3 scenes and 31 prefabs reimported successfully.
