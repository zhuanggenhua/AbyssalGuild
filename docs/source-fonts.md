# Source font identity and private binding

## Verified source, not a system-font substitute

The locked CardLoop commit contains `Assets/TextMesh Pro/Resources/Fonts & Materials/LiberationSans SDF.asset`
and `Assets/TextMesh Pro/Fonts/LiberationSans.ttf`. The previous unavailable-font
assessment confused the sparse working tree with the full source tree.
The SDF metadata GUID `8f586378b4e144a9851e7b34d9b748ee` references TTF GUID
`e3265ab4bf004d28a9537516768c1c75`. Read-only retrieval verified the original Git
blob hashes before private import. The font is Liberation Sans Regular,
Version 2.00.1, with its original SIL OFL 1.1 notice.

The supplement importer keeps the existing StackCraft subtree source lock
unchanged. Its separate private lock supplies repository paths, the same source
commit as the game catalog, and Git blob hashes for the SDF asset, both metadata
files, TTF, license and TMP Settings. It validates all input bytes and the
SDF-to-TTF GUID chain before writing anything. Public fixtures are synthetic.
Original font files, atlas pixels, license copies and derived source metrics
remain under ignored `source/font-supplement/` and `assets/imported/fonts/`.

## Runtime and integration

`SourceFontRegistry` resolves each label's actual source TMP font GUID. It
validates font bytes and metric hashes, handles both raw and imported FontFile
resources, and reports an explicit missing/mismatched-binding status. There is
no view-wide assumption that every source component uses one font.

Bindings cover card titles/stats, damage labels, trading labels, source Title,
Options, Pause, Friendly toggle, day clock, HUD counters, tabs, info and watermark.
Saved rows use the same registry in their separate source adapter. Native
measurement uses the bound font instead of unrelated ThemeDB fallback metrics.
The existing source sizing/auto-size adaptation is not replaced with new guessed
point sizes in this change.

Dynamic journal text requires special treatment: the actual locked TMP Settings
references default font GUID `577d95998db092d44a158b76409858c5`, not Liberation Sans.
Connected source search identifies that GUID in the upstream FantasyWord project
as Silver Medium with a Noto Sans SC Thin fallback. Those original asset paths
and exact blobs were not found in the locked CardLoop full tree. This establishes
the referenced identity, not a working CardLoop binding; no font was borrowed
from the other project. The registry retains the exact GUID and explicit missing
binding rather than using a nearby toggle font.

The exact Unity 6000.5.4f1 uGUI mirror commit
`b394b8ab4f985d25230da1bb02268dcb3c85cb19`,
`Runtime/TMP/TextMeshProUGUI.cs:1219`, shows LoadFontAsset taking the TMP Settings
default, then warning and returning if still null. It does not load LiberationSans
by name; that name occurs in warning text. Text generation also returns for null.
Without running Unity or resolving every package/renamed asset, unresolved is not
a measured runtime null. The current native fallback remains an explicit parity
gap, not proof of the effective original journal font or no-text behavior.

The strict private runner now requires the supplementary manifest, validates
source revision and provenance, checks TTF/metrics/license SHA-256, and copies
only those listed inputs into its disposable project. Missing supplemental files
fail before engine launch; a private binding suite must emit its PASS marker.
The public source-free runner needs no original font and tests explicit fallback.

## What this does not claim

Accurate TTF identity is not TMP glyph layout or SDF pixel parity. The private
manifest exposes original FaceInfo, 250 glyph/character records, pair adjustments,
font weights and fallback references for the next source-equivalent layout step.
Godot currently shapes/rasterizes the TTF; the source SDF atlas is not rendered by
this adapter. Auto-size edge cases, TMP layout/shaping, weights, dynamic fallback
and SDF material behavior remain separate work. The static source font has no
CJK glyphs; the Chinese reference screenshot is not established as the same
revision as this locked English template.
