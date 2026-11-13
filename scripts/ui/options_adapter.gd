extends RefCounted
## App-local mappings only. Never changes system/host audio volume or display mode.
var feedback
# Injectable only to verify application outcomes without changing a real display.
class NativeDisplay extends RefCounted:
	func name() -> String: return DisplayServer.get_name()
	func set_window_mode(mode: int) -> void: DisplayServer.window_set_mode(mode)
	func get_window_mode() -> int: return DisplayServer.window_get_mode()
	func set_vsync(mode: int) -> void: DisplayServer.window_set_vsync_mode(mode)
	func get_vsync() -> int: return DisplayServer.window_get_vsync_mode()
	func set_frame_cap(value: int) -> void: Engine.max_fps = value
var display: RefCounted = NativeDisplay.new()

func configure(audio_feedback, display_adapter: RefCounted = null) -> void:
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
		return {"ok": true, "capabilities": capabilities, "applied": [], "warnings": ["Headless preview: no display, engine cap or audio settings were changed.", "Resolution enumeration and Unity URP shadow mappings are unavailable."]}
	var values: Dictionary = plan.options
	var warnings: Array = ["Hardware resolution enumeration is unavailable; no screen mode was changed.", "Unity URP shadow presets are not mapped; source-configured Godot lighting is retained."]
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
	display.set_window_mode(requested_mode)
	if display.get_window_mode() == requested_mode:
		applied.append("window_mode")
	else:
		warnings.append("The window manager did not apply the requested fullscreen mode (for example, embedded preview supports windowed mode only). The saved preference is not the current window mode.")
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
	return {"ok": true, "capabilities": capabilities, "applied": applied, "warnings": warnings}
