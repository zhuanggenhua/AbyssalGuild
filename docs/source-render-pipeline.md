# Renderer-pass admission, not a new visual effect

## Distinguish the template from its host project

The source template supports **Built-in and URP**. Its documentation describes
pause grayscale/day-end vignette and provides an optional renderer switcher.
The locked `CardLoop` host happens to select a different PC URP renderer. That is
the same Unity repository the user identified. The reference screenshot alone
does not establish the active scene, pipeline settings, or runtime state. No
different source version or project variant is inferred to explain the visual
difference. This correction does not claim to match the screenshot's colors.

The locked host's Standalone platform-default quality is PC, whose pipeline
references `PC_Renderer`. That renderer has SSAO, but not the StackCraft custom
post-process feature. Mobile uses another renderer with no features. Conversely,
the template's own `URP_Renderer` contains the active custom feature, and its
Built-in path uses `BuiltInPostProcess.OnRenderImage`.

Formerly `world_post_process.gd` enabled a screen rectangle whenever it found an
active `BuiltInPostProcess` component. This incorrectly equated **writing material
parameters** with **a renderer sampling that material**. The component's event
subscriptions and grayscale/vignette tweens can run in URP while its Built-in-only
`OnRenderImage` callback is not the rendering route.

## Implementation and scope

The runtime retains the source writer's initialization/events/tween values. It
separately resolves screen-pass admission:

- Built-in selected pipeline and active source component: use the mapped pass.
- Recognized URP renderer-list schema: resolve the camera renderer override, or
  the pipeline's default renderer; locate an active custom feature whose exact
  material GUID **and subasset file ID** match the writer. A match establishes
  routing only and is currently **unknown**, not enabled: the locked custom pass
  overrides `RecordRenderGraph` but not compatibility-mode `Execute`. The profile
  does not resolve the active URP global RenderGraph/Compatibility setting.
- The locked host PC/Standalone profile: no such feature, so the material still
  updates but no grayscale/vignette rectangle is displayed.
- The template URP feature queues its pass regardless of the camera's standard
  `m_RenderPostProcessing` toggle. That toggle is not a substitute for the actual
  renderer-feature chain.

No pipeline GUID is hardcoded in the adapter. The custom feature identity is
resolved from the hash-locked C# metadata and cross-checked against the source
catalog. The pipeline reader is bounded to the serialized renderer-list and
renderer-feature schemas; it does not implement arbitrary URP renderer features.

Quality selection uses `m_PerPlatformDefaultQuality.Standalone`, not the editor's
`m_CurrentQuality`; all source quality overrides and the GraphicsSettings fallback
are retained. The locked StackCraft runtime changes shadow parameters but does not
call `SetQualityLevel` or switch render pipelines. The only such switcher is an
Editor menu script. Native Linux/Windows/macOS may use this Standalone profile.
Other platforms require their own explicit mapping; they are not silently treated
as PC. New quality/pipeline-switch functionality must resolve/reconfigure this
profile rather than retain an old visible pass.

Missing/old profiles, wrong source revisions, failed hashes, unknown pipeline
schemas, ambiguous/out-of-range camera overrides, multiple custom passes, and a
custom feature using a different material are explicit unsupported/unknown states.
They do not manufacture a screen effect. An active writer with unknown admission
emits a warning; its diagnostic remains in `config.render_pass`. Independent
feature materials without an active mapped writer are not implemented by this
bounded adapter. Hidden is not a claim that unknown source rendering had no pass.

## Private input and export contract

`tools/import_render_pipeline.py` consumes a separate private source bundle and
lock, modeled after the font supplement. Every input is checked by Git blob SHA;
its repository-relative path is preserved. The lock's source commit must match
`data/stackcraft.json`. Inputs include GraphicsSettings, QualitySettings, all
referenced quality pipeline/renderer assets and their metadata, plus the source
custom-feature script and metadata. Additional project/package settings may be
retained as hash-checked provenance. These files remain under ignored `source/`.

```
python3 tools/import_render_pipeline.py \
  --source source/render-pipeline-supplement \
  --lock source/render-pipeline-supplement/lock.json \
  --catalog data/stackcraft.json \
  --output assets/imported/render_pipeline.json \
  --target-platform Standalone --acknowledge-license
```

The generated graph and SHA-256 sidecar are private ignored files. The source
bundle uses the same commit, not guessed upstream replacements. The source lock
format has `source_commit`, `custom_feature_script`, and `files`; every file entry
has `repository_path` and `git_blob_sha1`. Import validates everything before
writing outputs. The public repository contains only the converter, adapters,
synthetic tests and this explanation, not the source bundle or generated graph.

The strict private runner verifies same-revision provenance and the content hash,
then copies both generated files into its disposable project. The private export
allowlist includes both files. The exported-pack probe requires loading the graph
and checks that the locked host's absent custom pass stays absent in a real Board.
An editor-only success is not allowed to mask a missing file in a private pack.

## Evidence and remaining boundaries

Synthetic tests cover arbitrary GUIDs, platform-vs-editor selection, fallback and
overrides, disabled/null/different-material features, multiple-pass rejection,
Built-in admission, custom URP unknown-mode rejection, and actual component/scene
override wiring.
Private tests load the locked host profile and actual Board, showing that pause
and day-end events update source material parameters without inventing a render
pass. These are behavioral/data tests, not rendered Unity/Godot image equivalence.

The board FBX material slots were independently checked against raw FBX material
connections and cached Godot surfaces: Body and Header are not swapped. Official
Godot Compatibility sources already perform color-space conversion on albedo,
ambient and light colors; no justified extra gamma correction was identified.
Godot BRDF, URP GI/SSAO, shadow filtering and color-management output remain separate
unmapped fidelity work. No board tint, light intensity, or camera parameter was
changed to imitate the screenshot.

### Deliberate validation limits in this batch

The real private runtime test covers the selected locked-host PC/Standalone chain.
The alternative Built-in and feature-equipped URP branches are synthetic routing
fixtures. The latter deliberately remains unknown until execution-mode evidence
is integrated; a matching material must not manufacture a screen effect. Although the private evidence bundle retains the template URP assets,
the derived graph traverses only GraphicsSettings/quality-referenced pipelines;
unselected template assets are not automatically inserted or activated. This is
not a real-template-URP rendered acceptance result.

Matching feature/writer material references proves routing only. The adapter does
not independently verify the generated GPU shader identity, every shader keyword,
render-event ordering against arbitrary other passes, or all renderer features.
It models one known custom pass; a different material, multiple passes, and
independent feature materials have explicit unsupported boundaries. Importing a
profile does not establish full URP/Built-in shader or pixel equivalence.

### Prior checkpoint (before RenderGraph admission correction)

The final isolated candidate passed 155 Python tests, 146 full-data Godot groups,
94 clean source-free Godot groups and 77 strict private-import suites on official
Godot 4.6.3. Every owned file and all 182 private input files matched the tested
snapshot before publication. The full suite also exposed an older timestamp-flaky
archive-restore test: restore correctly writes a fresh `last_saved`, so its test
now checks all other campaign fields exactly and validates the refreshed timestamp
separately. No production save behavior was changed to satisfy that test.

A bounded cloud-native run at 1280 × 800 followed New Game, the unchanged 120-second
day/OFF preferences, Starter draws and Space pause. The pause icon changed while
the Villager title/body retained color, as required by the selected PC renderer's
absent custom pass. Actual before/paused captures are kept privately; the game
was stopped without saving this transient campaign. This is not a same-state
Unity comparison, alternative-pipeline acceptance, or audio listening test.

At this checkpoint the export allowlist/probe tests passed, but no fresh PCK had
yet been built. A later pack-only check of the published renderer batch now
verifies packaged execution; see the follow-up below. It is not a new standalone
release executable validation.

### RenderGraph admission correction

Static inspection of the locked `CustomPostProcessFeature.CustomPass` confirms
that it implements `RecordRenderGraph` only, with no `Execute` override. Enqueueing
this pass and matching its material do not establish that the pipeline executes
that method. The current private import does not lock/resolve the active global
settings chain or its compatibility-mode option. Consequently an otherwise
matching URP feature now returns explicit `unknown`; its material state continues
to update but the native screen rectangle stays hidden. No absent setting is
assumed to mean RenderGraph enabled. Unvalidated ad-hoc mode hints are ignored.

This is a conservative unsupported boundary, not a claim that the template URP
effect is absent or disabled in the original. Future admission requires source-
revision-locked global settings resolution and the relevant URP execution branch.
The proven no-feature PC branch remains disabled, and the separate Built-in
`OnRenderImage` branch remains enabled.

### Final aggregate verification

After that correction, the final frozen code passed all 155 Python tests,
146 full-data Godot groups, 94 clean public groups and 77 strict private-import
suites again. The 1327-file original source lock also passed. The native capture
above predates the conservative unknown-URP guard; it verifies the unchanged
PC/no-feature branch, not an enabled URP feature.

An additional repeated run exposed a test-only audio-drain race: a slow setup
frame could consume a newly created 0.5-second SceneTreeTimer in 17–21 ms. The
private pipeline test now rechecks a monotonic deadline, matching the existing
production Quit drain, and asserts the actual duration. Ten cached-project
repetitions passed without leaked instances, each waiting at least 500000 µs.
The final aggregate results include this test correction. No engine diagnostic
was suppressed and no production audio/quit behavior was changed.

### Separate light-equation audit

The source graph targets UniversalLit. Official Unity Graphics package 17.5.0
implementation evidence shows a nonmetallic diffuse input of `0.96 * albedo`
and Lambert direct diffuse; Godot's StandardMaterial3D default is Burley diffuse.
Equal color/metallic/roughness inputs therefore do not establish equal lighting.
This is a proven mapping gap, not a quantified or unique explanation of the
reference screenshot's brightness. The same audit found no evidence for an
extra gamma conversion, exposure adjustment or additional division by pi.

Flat ambient/SH consumption, the source PC renderer's SSAO, and shadow bias/filter
settings also remain separately unmapped. The Unity evidence is the official
`Unity-Technologies/Graphics` `6000.5/staging` implementation declaring package
17.5.0, not a byte-for-byte verification of a local package cache. A future shader
mapping needs explicit source-equation and render-state tests; simply switching
Godot's diffuse mode or tuning a tint is not full equivalence.

### Pack-only follow-up

The exact `a77407f` / local `bea7c17` owned runtime was subsequently exported with
Godot's supported `--export-pack` command. No export template or release binary
was installed or substituted. After removing the temporary source project, the
existing strict external probe loaded that PCK with the official editor host:
776 checks passed, including 150 PNG, 19 WAV, four FBX, a 555-file runtime allowlist,
New/Save/Continue/production Quit and the rendering graph's hash/no-PC-pass checks.
All captured owned inputs matched that commit. The package and original media
remain private. This proves that renderer batch's packaged resource route, not
later audio changes, standalone release execution, GPU parity or listening.
