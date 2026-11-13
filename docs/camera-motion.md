# Source camera movement adapter

CameraController.cs and the scene-referenced CameraController prefab were statically audited. The prefab declares panSpeed0.01, smoothTime0.15, panPadding0.5, zoomSpeed1, minDistance5 and maxDistance20. CameraMotion resolves that scene's prefab and matching component overrides. It does not replace imported camera pose, projection, FOV30, near2 or far40.

Pointer pan changes a target using pixel displacement and current camera height/10. Screen-Y and world-Z reflections preserve the source direction. Left pan starts on empty board outside the GUI; middle pan is routed before GUI consumption. A card/panel press does not start a competing pan. Release is observed before GUI consumption when source input is enabled. Target X/Z is clamped to reflected board bounds plus source padding. Changed/shrinking bounds clamp the target immediately, not the current smoothed position. Zoom adds forward×scroll×zoomSpeed to target and rejects the complete step if its ground distance is outside5..20.

Movement uses the standard critically damped SmoothDamp polynomial (0.48/0.235 coefficients), retained velocity and overshoot prevention, evaluated with real frame delta. This is an independent numerical port, not a guarantee of identical Unity floating-point results. Manual gameplay pause does not freeze camera smoothing. Feeding, encounter, ready, game-over, vendor reveal and scene transitions block new camera input and ordinary smoothing. PauseMenu/Options only externally pause time and do not acquire InputManager locks; camera zoom, middle pan and unscaled smoothing remain active. Selling removes the source day-cycle input lock and permits camera movement, while Escape still checks the separate ending-cycle flag. Source Update returns before HandlePan while locked, preserving dragOrigin/isDragging. The native adapter now likewise preserves them; unlock samples accumulated pointer displacement, and a release while locked is not retroactively replayed.

`_focus_camera_position(source_position: Vector3, duration=0.5)` preserves source height and reflects Z. `_focus_camera(Vector2,duration)` is a ground-plane convenience wrapper. Focus runs with real time independently of ordinary input locks, toward target−forward×8, since source desired distance is lerp(20,5,0.8). Completion replaces target without an arbitrary board clamp. Only later pan/zoom or changed bounds clamps it. The interpolation uses explicit OutQuad matching the source default tween intent; arbitrary global DOTween overrides are not imported. No cycle event is wired in this batch and focus completion never drives model progression.

Combat shake remains independent camera h/v offsets. The unsupported native WASD camera extension has been removed. Source focus uses a controller parent and camera child; the native imported camera's flattened pose and camera-only shake offsets approximate this hierarchy. Pointer physics hit ordering, rendered framing, exact easing/floating-point parity and GPU/manual acceptance remain unverified.

Tests: camera_motion20 covers pan, clamping, zoom rejection, smoothing, source overrides and lock-independent focus. camera_board28 uses real imported source data and temporary local save/preferences; it covers lens preservation, manual pause, every cycle lock,3D focus, pointer routing and independent shake offsets. Existing smoke advances one camera frame before testing zoom/ray/drag roundtrips, reflecting the newly restored target smoothing instead of asserting the former instantaneous jump.

## Input routing correction evidence

CameraController.Update checks only InputManager.IsInputEnabled. HandleZoom never
calls IsPointerBlocked; only the left-press clause of HandlePan does. The middle
clause bypasses GUI, and neither clause depends on Time.timeScale. PauseMenu's
ToggleActiveState only calls TimeManager.SetExternalPause. InputManager uses a
HashSet of lock owners; DayCycleManager owns its phase lock and TradeManager
PlayActivationSequence independently owns tradeSequenceLock. Releasing day lock
while vendor reveal remains active cannot unlock camera input.

Wheel now enters via _input before GUI, not _unhandled_input. It is not consumed,
so the same event may scroll a panel and zoom, as source allows. The old tooltip
regression asserting no zoom was corrected rather than used to justify a deviation.
New tests push actual viewport GUI wheel events, verify exactly-once camera dispatch,
pause zoom/middle pan, independent lock release, preserved drag during locks and
transition gating. Card left-press remains GUI-blocked. Starting a blocked left
press does not cancel a previously active middle drag, matching the source clauses.

Cross-platform hardware scroll-unit calibration remains unverified: StackCraftInput
returns Mouse.scroll.ReadValue directly; Godot's event.factor supplies native wheel
units. This batch fixes routing/gating and preserves magnitude rather than inventing
a multiplier or claiming device-level raw-delta identity.

Verified: camera_board28, camera_motion20, card_feedback_board71, vendor_unlock_board47,
source camera pose/projection PASS. No Unity or manual GPU/input acceptance claimed.
