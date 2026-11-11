extends SceneTree
const Options = preload("res://scripts/model/user_options.gd")
var checks := 0
var failures := 0
var adapter_calls := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func write(path: String, content: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
func _init() -> void:
	var options = Options.new()
	check(options.configure().ok and options.values.resolution.is_empty(), "no hardware modes means no invented resolution")
	check(not options.cycle("resolution").ok, "missing hardware list refuses resolution cycle")
	check(options.configure([[2560, 1440], [1280, 720], [1920, 1080], [1280, 720]]).ok, "hardware modes configured")
	check(options.resolutions == [[1280, 720], [1920, 1080], [2560, 1440]], "hardware modes deduplicated and sorted")
	check(options.values == {"sfx_db": 0.0, "bgm_db": 0.0, "resolution": [1920, 1080], "fullscreen": "borderless", "vsync": 1, "fps_cap": -1, "shadow_preset": 3}, "actual source defaults")
	var before: Dictionary = options.snapshot()
	check(not options.configure([[0, 1080]]).ok and options.snapshot() == before, "bad hardware list rejected without mutation")
	check(options.set_volume("sfx", 0).ok and options.values.sfx_db == -80.0, "slider zero reaches source mute floor")
	check(is_equal_approx(options.volume_slider("sfx"), 0.0001), "mute floor slider inverse follows source")
	check(options.set_volume("sfx", 0.0001).ok and options.values.sfx_db == -80.0, "floor threshold inclusive")
	check(options.set_volume("sfx", 0.5).ok and is_equal_approx(options.values.sfx_db, -6.020599913), "source logarithmic volume conversion")
	check(options.set_volume("bgm", 1).ok and options.values.bgm_db == 0.0, "music user mixer gain distinct from source gain")
	for value in [-1, 1.1, null, {}, "0.5", NAN, INF, true]:
		before = options.snapshot()
		check(not options.set_volume("bgm", value).ok and options.snapshot() == before, "invalid volume rejected")
	check(not options.set_volume("master", 0.5).ok, "no invented master slider")
	options.reset_defaults()
	check(options.cycle("fullscreen").ok and options.values.fullscreen == "windowed", "fullscreen to windowed")
	options.cycle("fullscreen")
	check(options.values.fullscreen == "borderless", "fullscreen mode wraps")
	for cap in [30, 60, 120, 144, 240, -1]:
		options.cycle("fps_cap")
		check(options.values.fps_cap == cap, "source frame cap sequence")
	for vsync in [2, 0, 1]:
		options.cycle("vsync")
		check(options.values.vsync == vsync, "source VSync sequence")
	for shadow in [4, 0, 1, 2, 3]:
		options.cycle("shadow_preset")
		check(options.values.shadow_preset == shadow, "source shadow sequence")
	options.cycle("resolution")
	check(options.values.resolution == [2560, 1440], "verified resolution cycle")
	var copy = Options.new()
	copy.configure(options.resolutions)
	check(copy.restore(JSON.parse_string(JSON.stringify(options.snapshot()))).ok and copy.snapshot() == options.snapshot(), "native JSON roundtrip")
	for key in options.values:
		for value in [null, {}, NAN, true]:
			var bad: Dictionary = options.snapshot()
			bad.options[key] = value
			before = copy.snapshot()
			check(not copy.restore(bad).ok and copy.snapshot() == before, "invalid field rejected transactionally: " + key)
	for pair in [["sfx_db", -81], ["bgm_db", 1], ["vsync", 3], ["fps_cap", 90], ["shadow_preset", 5], ["resolution", [1920]], ["resolution", [20000, 1080]], ["fullscreen", "exclusive"]]:
		var bad: Dictionary = options.snapshot()
		bad.options[pair[0]] = pair[1]
		check(not copy.restore(bad).ok, "out of domain option rejected")
	options.cycle("vsync")
	var plan: Dictionary = options.application_plan()
	check(plan.unsupported.has("half_vsync") and plan.unsupported.has("unity_shadow_preset") and plan.fps_overridden_by_vsync, "unsupported source display semantics explicit")
	check(not options.apply_with(Callable()).ok, "no implicit host adapter")
	check(options.apply_with(func(received):
		adapter_calls += 1
		received.options.sfx_db = -20
		return {"ok": true}
	).ok and adapter_calls == 1 and options.values.sfx_db == 0.0, "injected adapter gets detached plan only")
	var path := "user://test-user-options-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(options.save_file(path).ok, "first atomic config save")
	options.set_volume("sfx", 0.5)
	check(options.save_file(path).ok, "second config save creates backup")
	options.set_volume("sfx", 0.25)
	check(options.save_file(path).ok, "third config save replaces backup")
	check(copy.load_file(path).ok and is_equal_approx(copy.volume_slider("sfx"), 0.25), "primary options loaded")
	write(path, "{bad")
	var loaded: Dictionary = copy.load_file(path)
	check(loaded.ok and loaded.recovered and is_equal_approx(copy.volume_slider("sfx"), 0.5), "invalid primary recovers backup")
	check(FileAccess.get_file_as_string(path) == "{bad", "fallback does not overwrite corrupt primary")
	var backup: String = FileAccess.get_file_as_string(path + ".bak")
	check(options.save_file(path).ok and FileAccess.get_file_as_string(path + ".bak") == backup, "saving after corruption keeps healthy backup")
	write(path, "[]")
	write(path + ".bak", "null")
	loaded = copy.load_file(path)
	check(not loaded.ok and loaded.used_defaults and copy.values == copy.defaults(), "invalid primary and backup reset to defaults with error")
	check(adapter_calls == 1, "load reset and save never call host adapter")
	check(FileAccess.get_file_as_string(path) == "[]" and FileAccess.get_file_as_string(path + ".bak") == "null", "invalid files preserved on default fallback")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	loaded = copy.load_file(path)
	check(loaded.ok and loaded.used_defaults, "missing config is clean first-run default")
	check(not copy.save_file(path + "/nonexistent/options.json").ok, "unwritable config path reports error")
	check(adapter_calls == 1, "tests never changed host audio or display")
	print("User options: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
