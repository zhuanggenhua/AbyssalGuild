extends SceneTree
const Adapter = preload("res://scripts/ui/options_adapter.gd")
const Options = preload("res://scripts/model/user_options.gd")
class FakeDisplay extends RefCounted:
	var display_name := "synthetic"
	var allow_window := true
	var allow_vsync := true
	var mode: int = DisplayServer.WINDOW_MODE_WINDOWED
	var vsync: int = DisplayServer.VSYNC_DISABLED
	var cap := 17
	var calls: Array = []
	func name() -> String: return display_name
	func set_window_mode(value: int) -> void:
		calls.append(["window",value])
		if allow_window: mode = value
	func get_window_mode() -> int: return mode
	func set_vsync(value: int) -> void:
		calls.append(["vsync",value])
		if allow_vsync: vsync = value
	func get_vsync() -> int: return vsync
	func set_frame_cap(value: int) -> void:
		calls.append(["fps",value])
		cap = value
class FakeAudio extends RefCounted:
	var gains: Array = []
	func set_user_gains(sfx: float,bgm: float) -> void: gains.append([sfx,bgm])
var checks := 0
var failures := 0
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",label)
func _init() -> void:
	var host_cap := Engine.max_fps
	var options = Options.new()
	options.configure()
	var original: Dictionary = options.snapshot()
	var platform := FakeDisplay.new()
	var audio := FakeAudio.new()
	var adapter = Adapter.new()
	adapter.configure(audio,platform)
	var result: Dictionary = adapter.apply(options.application_plan("initialize"))
	check(result.applied == ["audio","window_mode","vsync","fps_cap"],"accepted mappings recorded")
	check(platform.mode == DisplayServer.WINDOW_MODE_FULLSCREEN and platform.cap == 0,"source borderless/VSync precedence mapped")
	check(not result.capabilities.shadow_presets,"no invented URP shadow adapter")
	platform.allow_window = false
	platform.mode = DisplayServer.WINDOW_MODE_WINDOWED
	result = adapter.apply(options.application_plan())
	check(not result.applied.has("window_mode"),"embedded rejection is not reported applied")
	check("\n".join(result.warnings).contains("not apply the requested fullscreen"),"rejection disclosed separately from saved preference")
	check(options.snapshot() == original,"observing rejection never rewrites desired preference")
	platform.allow_vsync = false
	platform.vsync = DisplayServer.VSYNC_DISABLED
	platform.cap = 17
	result = adapter.apply(options.application_plan())
	check(not result.applied.has("vsync") and not result.applied.has("fps_cap") and platform.cap == 17,"VSync rejection retains prior cap")
	options.values.vsync = 2
	platform.calls.clear()
	result = adapter.apply(options.application_plan())
	check(not result.applied.has("vsync") and not result.applied.has("fps_cap"),"Half VSync remains unsupported")
	check(platform.calls == [["window",DisplayServer.WINDOW_MODE_FULLSCREEN]],"Half never substitutes adaptive or fixed FPS")
	platform.allow_vsync = true
	options.values.vsync = 0
	options.values.fps_cap = 60
	result = adapter.apply(options.application_plan())
	check(platform.cap == 60 and result.applied.has("fps_cap"),"VSync Off applies source selected cap")
	platform.display_name = "headless"
	platform.calls.clear()
	audio.gains.clear()
	result = adapter.apply(options.application_plan())
	check(result.applied.is_empty() and platform.calls.is_empty() and audio.gains.is_empty(),"headless changes no platform state")
	check(Engine.max_fps == host_cap,"synthetic tests never change host frame cap")
	print("Options application outcomes: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)
