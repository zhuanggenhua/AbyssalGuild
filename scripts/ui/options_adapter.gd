extends RefCounted
## App-local mappings only. Never changes system/host audio volume or display mode.
var feedback

func configure(audio_feedback) -> void:
	feedback = audio_feedback

func apply(plan: Dictionary) -> Dictionary:
	var capabilities := {"window_mode": false, "vsync": false, "fps_cap": false, "shadow_presets": false}
	if DisplayServer.get_name() == "headless":
		return {"ok": true, "capabilities": capabilities, "applied": [], "warnings": ["Headless preview: no display, engine cap or audio settings were changed.", "Resolution enumeration and Unity URP shadow mappings are unavailable."]}
	var values: Dictionary = plan.options
	var warnings: Array = ["Hardware resolution enumeration is unavailable; no screen mode was changed.", "Unity URP shadow presets are not mapped; source-configured Godot lighting is retained."]
	var applied: Array = []
	if is_instance_valid(feedback):
		feedback.set_user_gains(float(values.sfx_db), float(values.bgm_db))
		applied.append("audio")
	capabilities.window_mode = true
	capabilities.vsync = true
	capabilities.fps_cap = true
	# Godot's nonexclusive fullscreen is borderless; this changes only our window.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen == "borderless" else DisplayServer.WINDOW_MODE_WINDOWED)
	applied.append("window_mode")
	if int(values.vsync) == 2:
		warnings.append("Half-refresh VSync is unsupported and was not applied. Existing VSync and FPS application are retained.")
	else:
		var mode: DisplayServer.VSyncMode = DisplayServer.VSYNC_DISABLED if int(values.vsync) == 0 else DisplayServer.VSYNC_ENABLED
		DisplayServer.window_set_vsync_mode(mode)
		if DisplayServer.window_get_vsync_mode() == mode:
			applied.append("vsync")
			Engine.max_fps = 0 if int(values.vsync) != 0 else maxi(0, int(values.fps_cap))
			applied.append("fps_cap")
		else:
			warnings.append("The display driver did not accept the requested VSync setting; FPS application was left unchanged.")
	return {"ok": true, "capabilities": capabilities, "applied": applied, "warnings": warnings}
