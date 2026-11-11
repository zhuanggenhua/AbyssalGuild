# Puff metadata and CPU simulation checkpoint

This checkpoint adds private metadata and independently written presentation math. It does **not** render particles, play audio, emit model events or change the board. There is no Unity/GPU launch or manual visual acceptance. Original prefab/material/image records remain in ignored private inputs and output.

## Source and event audit

`Settings/Default_Card_Settings.asset` is not a global lookup shortcut. The importer follows each scene's CardManager `cardSettings` GUID and component ID, then that settings component's `puffParticle` GUID and component ID. ParticleSystem and ParticleSystemRenderer must belong to that referenced component's GameObject. Tests use two unequal settings/prefab chains rather than relying on Main and Island sharing the same source default.

Relevant source methods:

- `Scripts/Card/CardInstance.cs`, `PlayPuffParticle`: instantiate the referenced prefab at the card's current world position with identity rotation.
- `CardInstance.Kill`: notify first, clean up equipment/combat and spawn loot, then Puff immediately before removal. Depleted food and exhausted packs also call Kill. Direct ingredient destruction and sale do not imply Puff.
- `Scripts/Crafting/Definitions/RecipeDefinition.cs`, `Execute`: top-card Puff, then Pop audio, before input consumption, including when no output is configured. Growth, Research, Exploration and Travel overrides do not call this base implementation.
- `Scripts/Card/Behaviors/ChestLogic.cs`: valid deposit attempt puffs even when capacity prevents a deposit; successful withdrawals puff even with `spawnOnBoard=false`.
- `Scripts/Card/Components/CardAI.cs`, `SpawnProduce`: Puff after creating produce.
- `Scripts/Encounter/EncounterManager.cs`, spawn coroutine: create card, await camera focus, Puff, then wait 0.5 real seconds. This site was verified separately from Card/Combat source searches.
- `Scripts/Card/VFX/PuffParticle.cs`, `Awake`: play Puff immediately and schedule destruction at particle-system duration plus 0.1 scaled seconds.

Future event integration must preserve these distinct locations. Keep the early `card_killed` semantic notification; a separate `puff_requested` event belongs after cleanup/loot and before removal. Base-recipe Puff belongs before consumption, not on the existing post-spawn `crafted` event. A board handler should capture the existing view's current world position, otherwise use a captured source-coordinate position reflected once on Z. Sound must not depend on optional visual resources being present.

## Supported private data

`Prefabs/VFX/PuffParticle.prefab` has one immediate burst of 30, no continuous emission, system duration 1, particle lifetime 0.15..0.6, speed 0.5..0.6 and uniform initial size 0.3..0.7. Start color is black with alpha 0.8. Gravity and rotation are zero.

Its full Circle has radius 0.15, full radius thickness, shape offset Y=0.15 and shape rotation X=-90 degrees. Spherize Direction is 1, with no additional random direction/position. Root and shape scales are identity. Renderer mode is horizontal billboard. Disabled velocity, force, noise, collision, trail and similar modules are not interpreted as active behavior.

The active size curve has three keys, with weighted tangents at the middle key. `puff_simulation.gd` evaluates weighted cubic Bézier segments by solving their time coordinate, then evaluating their value coordinate. It does not replace the curve with a triangle or silently discard tangent weights. Unweighted sides use one-third handles. Alpha remains 1 until normalized time 58982/65535, then falls to zero; the initial alpha multiplies this ramp. Colored/gamma-dependent ramps are outside this checkpoint's supported subset.

The importer retains exact material references, built-in shader identity and renderer limits. PNG entries also retain filtering, wrap, mipmap, color-space and alpha-import settings, with `.meta` input hashes. `Materials/Effects/Puff.mat` references `Textures/Puff.png`, already copied privately. This image is a texture, not a single-sprite asset.

Unknown enabled modules, unsupported time/shape/emission modes, nonidentity scale, malformed ranges/curves or unresolved ownership yield unsupported metadata with reasons, rather than guessed runtime settings.

## API and clock contract

- `VisualAssets.puff_configuration(scene_name)` returns a copy of a supported record for that scene, otherwise an empty dictionary. It does not require a renderable texture, because the simulation has no renderer.
- `PuffSimulation.configure(record, presentation_seed)` resets old state, validates the record, and creates the one-time birth states. Failure leaves an empty, expired simulation.
- `birth_states()` returns a deep copy containing index, reflected local position, velocity, lifetime and initial size.
- `advance(unscaled_delta, scaled_delta)` advances both clocks. Invalid/negative/nonfinite input is rejected without partially advancing either. Zero scaled time still permits particle aging. No draws occur during frame updates or sampling.
- `sample_states()` returns current survivors as copies: index, age, normalized age, local position, size and particle color. Positions are relative to the captured world spawn origin. Add that origin only in the eventual renderer. Sampling cannot mutate birth state.
- `is_expired()` reports scaled object destruction, not the absence of live particles. `reset()` drops all transient state.

The particle clock is unscaled but object destruction is scaled. At pause, particles finish while the object remains pending. At source Fast=2, the 1.1-scaled-second destruction can truncate particles at 0.55 real seconds. A renderer must not collapse the two clocks or automatically equate “no live particles” with source destruction.

## Deliberate differences and unresolved work

Births use an explicit private RandomNumberGenerator seed, uniform-area disk sampling and outward velocity from the system origin including the shape offset. Unity's [Shape documentation](https://docs.unity3d.com/2022.3/Documentation/Manual/PartSysShapeModule.html) describes Spherize Direction in terms of the Transform center. The adapter follows that documented interpretation, but neither engine RNG sequences, distribution internals, random draw ordering nor individual trajectories are claimed identical. Unity Euler composition is applied explicitly as Y×X×Z, then world Z is reflected. Global and Session RNG are untouched.

Weighted-curve math is independently tested against analytic Bézier values, not against a running Unity AnimationCurve. It is a numeric adapter, not a claim of bit-identical engine evaluation.

The source material references a built-in shader absent from the supplied source tree. Stored blend floats and old invalid keywords are insufficient to establish its active color/blend equation. The simulation returns particle color only and never claims that color is the final pixel. Built-in shader behavior, transparency, color-space processing, mipmaps, horizontal-billboard details, screen-relative particle-size limiting and renderer sorting/culling remain unaccepted. A future reversible native renderer may approximate these only with those limits stated explicitly.

## Verification

- Python discovery: 102 tests passed in the current workspace, including seven new Puff metadata tests.
- New Godot suite: 226 synthetic checks in a truly source-free project, with an explicit private skip. Private no-FBX-cache and actual cached projects both pass 434 checks, covering scene references, births, source ranges/planes, weighted segment midpoints, material/texture references and the two clocks.
- Synthetic tests additionally cover mixed-axis rotation/reflection, weighted-time inversion, seed reproducibility, zero global/frame RNG consumption, frame partition invariance, immutable snapshots, malformed input, scaled truncation and area-uniform disk sampling.
- Private regeneration: 173 assets, zero missing. Original-source lock: all 1,327 files unchanged. Tests use the existing timeout/engine-error guard.

Private completion marker: `Private Puff simulation: PASS (both scene references, birth ranges, weighted curves, two clocks, material/texture references)`.

These are focused metadata/math checks, not acceptance of a full concurrent project snapshot or a visible particle effect.
