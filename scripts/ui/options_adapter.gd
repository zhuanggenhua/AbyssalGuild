extends RefCounted
## App-local mappings only. Never changes system/host audio volume or display mode.
var feedback
const WINDOW_SETTLE_MS := 100
const WINDOW_TIMEOUT_MS := 2000
var _window_generation := 0
var _window_request: Dictionary = {}
# Injectable only to verify application outcomes without changing a real display.
class NativeDisplay extends RefCounted:
	func name() -> String: return DisplayServer.get_name()
	func set_window_mode(mode: int) -> void: DisplayServer.window_set_mode(mode)
	func get_window_mode() -> int: return DisplayServer.window_get_mode()
	func get_window_size() -> Vector2i: return DisplayServer.window_get_size()
	func get_screen_size() -> Vector2i: return DisplayServer.screen_get_size()
	func ticks_msec() -> int: return Time.get_ticks_msec()
	func set_vsync(mode: int) -> void: DisplayServer.window_set_vsync_mode(mode)
	func get_vsync() -> int: return DisplayServer.window_get_vsync_mode()
	func set_frame_cap(value: int) -> void: Engine.max_fps = value
var display: RefCounted = NativeDisplay.new()

func configure(audio_feedback, display_adapter: RefCounted = null) -> void:
	cancel_window_observation()
	feedback = audio_feedback
	if display_adapter != null: display = display_adapter

func live_volume_slider(channel: String) -> float:
	if not is_instance_valid(feedback): return -1.0
	if channel == "bgm": return feedback.live_bgm_slider_value()
	if channel == "sfx": return feedback.live_sfx_slider_value()
	return -1.0

func apply(plan: Dictionary) -> Dictionary:
	var capabilities := {"window_mode": false, "vsync": false, "fps_cap": false, "shadow_presets": false}
	if display.name() == "headless":
		cancel_window_observation()
		return {"ok": true, "capabilities": capabilities, "applied": [], "warnings": ["Headless preview: no display, engine cap or audio settings were changed.", "Resolution enumeration and Unity URP shadow mappings are unavailable."], "window_mode": {"id": -1, "status": "unsupported", "reason": "headless"}}
	var values: Dictionary = plan.options
	var warnings: Array = ["Hardware resolution enumeration is unavailable; no hardware/output resolution was applied.", "Unity URP shadow presets are not mapped; source-configured Godot lighting is retained."]
	var applied: Array = []
	if is_instance_valid(feedback):
		# Whole-plan refresh is not a user volume edit. Only the originating
		# source callback (or explicit initialize/reset) may write a live mixer.
		match str(plan.get("intent", "refresh")):
			"initialize", "reset":
				feedback.set_user_gains(float(values.sfx_db), float(values.bgm_db))
				applied.append("audio")
			"sfx":
				feedback.set_user_sfx_gain(float(values.sfx_db))
				applied.append("sfx")
			"bgm":
				feedback.set_user_bgm_gain(float(values.bgm_db))
				applied.append("bgm")
	capabilities.window_mode = true
	capabilities.vsync = true
	capabilities.fps_cap = true
	# Godot's nonexclusive fullscreen is borderless; this changes only our window.
	var requested_mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen == "borderless" else DisplayServer.WINDOW_MODE_WINDOWED
	var window_state := _request_window_mode(requested_mode, str(plan.get("intent", "refresh")))
	if int(values.vsync) == 2:
		warnings.append("Half-refresh VSync is unsupported and was not applied. Existing VSync and FPS application are retained.")
	else:
		var mode: DisplayServer.VSyncMode = DisplayServer.VSYNC_DISABLED if int(values.vsync) == 0 else DisplayServer.VSYNC_ENABLED
		display.set_vsync(mode)
		if display.get_vsync() == mode:
			applied.append("vsync")
			display.set_frame_cap(0 if int(values.vsync) != 0 else maxi(0, int(values.fps_cap)))
			applied.append("fps_cap")
		else:
			warnings.append("The display driver did not accept the requested VSync setting; FPS application was left unchanged.")
	return _with_window_state({"ok": true, "capabilities": capabilities, "applied": applied, "warnings": warnings}, window_state)

# X11 can return MAXIMIZED immediately after leaving fullscreen, then WINDOWED.
# Observe the latest request; no fixed frame wait, timer callback, or repeated setter.
func _now_msec() -> int:
	return int(display.ticks_msec()) if display.has_method("ticks_msec") else Time.get_ticks_msec()

func _window_sample() -> Dictionary:
	return {"mode": display.get_window_mode(), "size": display.get_window_size(), "screen": display.get_screen_size()}

func _window_matches(sample: Dictionary, requested: int) -> bool:
	if int(sample.mode) != requested or sample.size.x <= 0 or sample.size.y <= 0: return false
	return requested != DisplayServer.WINDOW_MODE_FULLSCREEN or (sample.screen.x > 0 and sample.screen.y > 0 and sample.size == sample.screen)

func _window_signature(sample: Dictionary) -> String:
	return str(sample.mode) + ":" + str(sample.size) + ":" + str(sample.screen)

func _request_window_mode(requested: int, intent: String) -> Dictionary:
	if not _window_request.is_empty() and int(_window_request.requested_mode) == requested:
		# Other preference changes must not renew an outstanding deadline.
		if _window_request.status == "pending": return _window_request.duplicate(true)
		if _window_request.status == "failed" and not intent in ["initialize", "fullscreen", "reset", "retry_window"]: return _window_request.duplicate(true)
		if _window_request.status == "succeeded" and _window_matches(_window_sample(), requested): return _window_request.duplicate(true)
	_window_generation += 1
	var now := _now_msec()
	display.set_window_mode(requested)
	var observed := _window_sample()
	_window_request = {"id": _window_generation, "requested_mode": requested, "status": "pending", "reason": "awaiting_observation", "message": "Window mode change pending; the saved preference is not yet confirmed by the window manager.", "started_msec": now, "deadline_msec": now + WINDOW_TIMEOUT_MS, "stable_since_msec": now if _window_matches(observed, requested) else -1, "signature": _window_signature(observed), "observed_mode": observed.mode, "observed_size": [observed.size.x, observed.size.y]}
	return _window_request.duplicate(true)

func poll_window_application(application: Dictionary) -> Dictionary:
	var id: int = int(application.get("window_mode", {}).get("id", -1))
	if _window_request.is_empty() or id != int(_window_request.id): return {}
	if _window_request.status != "pending": return _with_window_state(application, _window_request)
	var now := _now_msec()
	var observed := _window_sample()
	var signature := _window_signature(observed)
	_window_request.observed_mode = observed.mode
	_window_request.observed_size = [observed.size.x, observed.size.y]
	if _window_matches(observed, int(_window_request.requested_mode)):
		if int(_window_request.stable_since_msec) < 0 or signature != _window_request.signature:
			_window_request.stable_since_msec = now
		elif now < int(_window_request.deadline_msec) and now - int(_window_request.stable_since_msec) >= WINDOW_SETTLE_MS:
			_window_request.status = "succeeded"
			_window_request.reason = "observed_stable"
			_window_request.message = ""
	else:
		_window_request.stable_since_msec = -1
	_window_request.signature = signature
	if _window_request.status == "pending" and now >= int(_window_request.deadline_msec):
		_window_request.status = "failed"
		_window_request.reason = "timeout"
		_window_request.message = "Window mode change was not confirmed within 2 seconds. The request may have been refused (for example, embedded preview supports windowed mode only); the saved preference is not the confirmed current window mode."
	return _with_window_state(application, _window_request)

func cancel_window_observation(id: int = -1) -> void:
	if id >= 0 and (_window_request.is_empty() or id != int(_window_request.id)): return
	_window_generation += 1
	_window_request.clear()

func _with_window_state(application: Dictionary, state: Dictionary) -> Dictionary:
	var result := application.duplicate(true)
	var warnings: Array = result.get("warnings", [])
	var old_message := str(result.get("window_warning", ""))
	if not old_message.is_empty(): warnings.erase(old_message)
	var message := str(state.get("message", ""))
	if not message.is_empty(): warnings.append(message)
	result.warnings = warnings
	result.window_warning = message
	result.window_mode = state.duplicate(true)
	var applied: Array = result.get("applied", [])
	applied.erase("window_mode")
	if state.status == "succeeded": applied.append("window_mode")
	result.applied = applied
	return result
