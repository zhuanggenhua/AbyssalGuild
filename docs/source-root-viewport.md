# Source root viewport and camera pixel units

Base: remote4b6a6e3 / exact tree e305f7244d13778cba0095d5a37d9c135fe75651. Unity source remains a11a89b04cea8370476f2559b639bb9b4cbc08d8.

## Proven missing mapping

The source Main camera has full rect(0,0,1,1), perspective vertical FOV30; HUD reference1920×1080 with ScaleWithScreenSize and MatchHeight1. Title also height-matches1920×1080 but uses Screen Space Camera, not the Main HUD's Overlay mode. These reference dimensions do not impose a camera aspect ratio. GraphicsManager chooses stored/hardware resolution without a16:10 filter. ProjectSettings'1024×768 defaults are not guaranteed startup size or a minimum: native resolution is enabled and GraphicsManager may replace them.

The native shell retained1440×900 with canvas_items and default aspect=keep. The inner HUD conversion fixed UI anchors but could not remove the outer16:10 viewport constraint. A real standalone1364×1024 run displayed1364×852 content with86px top/bottom bands. Production-config headless Window measurements independently reproduced those transforms;1280×720 also had64px side margins and1024×768 had64px top/bottom margins. Previous fixtures that cleared content_scale_size or used only16:10 did not test this boundary.

## Narrow change

Set `window/stretch/aspect="expand"`, keeping canvas_items and its existing minimum design canvas. The3D render area now fills the physical client window; the logical root expands with aspect. Existing Main/Title/pause/options source-height layouts remain responsible for UI scaling. Their physical factor is H/1080; right/bottom anchors use the expanded width. Engine integer viewport rounding can create tiny(<1px) deviations at non-integral sizes such as1364×1024; it is not corrected by hand. No per-label offset, camera FOV, renderer, scene state or asset is changed.

Godot Window input has already been transformed into viewport coordinates. Picking, card dragging, GUI and trade ray queries keep those coordinates. Unity CameraController pan, however, multiplies **physical pointer pixels** by panSpeed×cameraHeight/10. The candidate therefore transforms only a copied camera-pointer event and its two pan-start origins back through the root final transform. Stored camera positions/origins remain in window pixels so resize without a new input event cannot reinterpret an old logical sample. The real event, card pointer and camera ray remain unmodified. Lock/orphan rules remain in the existing source_camera_pointer implementation.

This conversion is for the current root Window and its normal canvas path. Arbitrary embedded SubViewports/custom global canvas transforms are not supported by this claim.

## Executable regressions

Use `GODOT_PROJECT_SETTINGS=production bash tools/test_godot.sh res://tests/godot/test_root_viewport.gd` and the same command for `test_camera_screen_pixels.gd`. This explicit runner mode copies project.godot into a private temporary project rather than replacing it with an empty config. It still isolates HOME/XDG and does not reuse editor state. The default logic-test mode is unchanged. Fresh imported tests already preserve production settings and now run both suites.

Root matrix:1024×768,1280×800,1280×720,1200×600,800×1000,1364×1024 and800×600. Tests check actual root transforms/full coverage, independent physical-height pinhole predictions, corner rays, native physical-event GUI routing, source HUD and Title dimensions/centers, menus/options/pause reachable bounds. A private branch uses actual source card collider geometry and physical Window events to pick/drag a card and drop buyer/vendor payments. Positions and quest unlocks in that branch are explicit test fixtures, not natural progress. Unity PhysX zero-height trade-box behavior is not newly validated.

The camera-pixel suite uses a synthetic empty-board ray to isolate physical20×10px pan displacement, both mouse buttons, lock/unlock accumulation, resize while held, primary touch and scaled multi-contact orphan retention across resize. It is not itself real collider coverage. Existing primary/orphan suites retain their separate coverage.

For native rendering, set `ROOT_VIEWPORT_CAPTURE_DIR` to an existing private directory and run the root suite on a coordinated display. It checks actual PNG dimensions and corner sentinel colors, and writes source Main diagnostic images. **Headless runs do not perform those pixel checks.** The geometry matrix suppresses options' display adapter; an explicit native-only final branch reconnects the production adapter and clicks its real fullscreen control through Window events for a fullscreen/windowed round trip. This diagnostic is not a standalone-release-binary manual smoke.

## Bounds and non-goals

No new minimum window or aspect restriction is invented. The observed Godot root minimum64×64 is retained; the regression verifies it does not exclude the source serialized1024×768 mode.800×600 is covered, but this is not a legibility guarantee at arbitrarily small windows.800×1000 demonstrates full-window projection/source scaling; fixed-width source controls can overlap at narrow aspect ratios exactly because the source has no responsive redesign. No claim of usable portrait layout is made.

This patch does not implement hardware resolution enumeration, alter source pause/zoom/drag locks, change source quest rules/localization/equipment, fix font-raster differences, reproduce unknown Unity SH/GI, or establish visual parity with a screenshot of a possibly later scene.

## Source pointers

- `UIRoot.prefab` blob4925bd36… lines3337–3342; Main blob06f22b65… no camera-rect override.
- `Core/CameraController.prefab` blobd76ff037… lines116–125; `Core/CameraController.cs` blob4a937034… lines96–110.
- `GraphicsManager.cs` blob3add4251… lines88–163; ProjectSettings blob589cf7d5… lines44–45,88,103,114–115.
- Godot4.6.3 [root startup](https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/main/main.cpp), [default aspect](https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/core/config/project_settings.cpp), [Window viewport transform](https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/scene/main/window.cpp).
