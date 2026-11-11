# Native Puff renderer

This slice adds a small native renderer on top of the separately validated [Puff metadata/CPU simulation checkpoint](puff-simulation.md). It uses the private, scene-referenced Puff PNG and source particle state, but **standard-alpha rendering is an explicit approximation** of the unresolved Unity built-in particle shader. No original media, material export or prefab data is published.

## Construction and lifecycle

`VisualAssets.create_puff(scene_name, presentation_seed)` returns an unparented `PuffView` Node3D or null. It resolves that scene's supported Puff configuration, the referenced material and its `_MainTex` PNG. There is no generated replacement image. Missing metadata/material/color/texture or unsupported renderer settings safely return null.

The caller adds the node at the captured Godot world origin and keeps its root basis identity. CPU positions already reflect source Z, so add the origin once and do not reflect the particle positions again. Future events can prefer an existing card view's current world position, falling back to the model event's captured source position with one Z reflection.

Call `advance(unscaled_delta, scaled_delta)` exactly once per presentation frame. The view has no autonomous `_process`, audio calls or model writes. It forwards the two deltas to the unchanged CPU simulation, then updates visible particles. Invalid input does not partly advance either clock. A zero tick consumes no randomness and causes no drift.

Particle death hides its plane. An empty effect remains alive while scaled destruction is paused. At scaled expiry, the effect hides and queues itself for deletion. `is_expired()` exposes that state; the caller should remove queued/freed references from its collection. Scene/title changes should destroy the whole collection. An effect queued for deletion cannot be revived by reconfiguration.

Puff sound must remain independent of optional visual availability. Event ordering and board collection ownership are separate integration work, not hidden side effects of this resource adapter.

## Geometry and material

Each burst particle uses a unit horizontal PlaneMesh, scaled on X/Z to its CPU-computed size and translated to its CPU position. The zero-size birth endpoint is hidden instead of creating a singular transform. Planes are unlit, double-sided and cast no shadows. They are horizontal surfaces, not camera-facing billboards. Particle material instances are independent so one particle's alpha cannot affect another; the private PNG can be shared.

The native material uses ordinary alpha transparency and mixed blending, with depth testing enabled and transparent depth writes disabled. Its albedo multiplies the texture, imported `_Color` and CPU particle color. This is a declared native choice: it does not claim to implement the source built-in shader's blend/color equation, invalid legacy keywords or premultiplication behavior.

Nearest/bilinear filtering, mipmap requests and equal repeat/clamp wrap settings come from the private texture importer record. The adapter currently requires identity texture scale/offset, zero renderer pivot/flip and no shadows. Unsupported settings do not receive guessed replacements. The PNG import/cache can differ from Unity in mipmap generation, compression and color processing; inspecting these requested settings is not proof of pixel equivalence.

Source screen-relative particle-size limiting, engine sorting/culling, billboard roll and exact blend/color-space behavior are not reproduced or visually accepted. The independently seeded CPU births and weighted-curve adapter retain their documented limits. Gameplay state, positions, timers and gameplay RNG are untouched.

## Validation

`tests/godot/test_puff_view.gd` passes:

- 115 synthetic checks in a truly source-free project, with an explicit private-resource skip.
- 673 checks with private PNGs in both isolated/no-FBX-cache and actual cached projects, covering both scene bindings, horizontal geometry, texture identity, per-particle state/materials, clock behavior, cleanup and optional-resource failures.
- Synthetic metadata is round-tripped through JSON so numeric float decoding is exercised without private inputs. This caught and guards against comparing float-valued UV dictionaries with integer dictionaries.

Existing focused regressions passed: 434 Puff simulation checks, 260 cached combat-sprite checks and 102 Python tests. Tests use the timeout/engine-error guarded runner. The CPU simulation/importer files were not changed by this renderer slice.

Private completion marker: `Private native Puff view: PASS (both scene textures, horizontal geometry, per-particle state, two-clock cleanup; alpha approximation)`.

These tests validate construction and mathematical/material state, not a rendered screenshot. No Unity/GPU launch, pixel comparison or manual visual acceptance is claimed.
