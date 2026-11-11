# World camera post-processing

Independent native implementation based on static inspection of the locked source `BuiltInPostProcess`, `CustomPostProcess`, and `TimeManager`. No Unity source code or shader/material asset is redistributed by this implementation.

The active scene's prefab reference selects the component. Resolution checks the effect's enabled flag, its same-object enabled Camera, active GameObject ancestry, and a nonzero material reference present as a material in the source GUID index. Relevant prefab instance overrides are applied before resolution. GUIDs and prefab names are not hardcoded. Missing or disabled binding produces an explicit `source_backed: false` passthrough configuration. The native shader implements the identified behavior; loading the private Unity material into Godot is not required or claimed.

- Explicit `time_pace_changed`: grayscale target 1 for paused, otherwise 0, over 0.3 seconds.
- `day_ended` / `day_started`: vignette target 1.2 / 0 over 0.5 seconds.
- Separate OutQuad tracks advance using real frame delta. Replacement starts from the current interpolated value, with no stale completion callbacks.
- Source day-end sets pace silently before emitting its day-ended event. Source day-start resets pace silently before emitting day-started. Neither operation synthesizes a grayscale event. External menu/reveal/transition pauses do not change grayscale.
- Source `TimeManager.HandleSceneDataReady` restores elapsed time/day, not a pace-change event. Source post-process `Start` subscribes then initializes component intensities. Native entry likewise resets to serialized component values (default zero) rather than deriving a value from saved paused/phase state. This also makes load/travel cancel departing tweens. Title and teardown clear all tracks and hide the effect.

A screen-reading native CanvasItem shader is on CanvasLayer 0, after the 3D world and before the HUD (layer 1), options, and scene fader (100). It ignores mouse input and uses the project's compatibility renderer. Luminance weights are 0.299/0.587/0.114. The radial factor is `1 - smoothstep(0.2, 0.8, distance * power)`, algebraically the source reversed-edge smoothstep with defined ascending edges. Alpha is preserved. Journal and scene-fader clocks are unchanged; departing-world updates use the existing fade-boundary-clamped real delta.

## Checks and limits

`test_world_post_process.gd`: synthetic unequal references, active scene and enabled binding, overrides, missing material/data, component initialization, independent and reentrant OutQuad tracks, invalid delta, cancellation, grayscale/vignette pure math.

`test_world_post_process_board.gd`: actual imported Main/Island references, Title exclusion, layer/input/shader/uniform binding, real paused clock, silent day-end ordering, day-start reversal, entry/load/travel/title/teardown cancellation and missing scene fallback.

Headless checks establish logic and resource binding only. They do not establish GPU shader output, visible frame composition, physical input, or Windows acceptance. No Unity editor/display was launched.
