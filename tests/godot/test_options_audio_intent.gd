extends SceneTree
const OptionsView = preload("res://scripts/ui/options_panel.gd")
const Adapter = preload("res://scripts/ui/options_adapter.gd")
const Feedback = preload("res://scripts/ui/audio_feedback.gd")
class Display extends RefCounted:
	var mode := 0
	var vsync := 0
	func name() -> String: return "synthetic"
	func set_window_mode(value: int) -> void: mode = value
	func get_window_mode() -> int: return mode
	func set_vsync(value: int) -> void: vsync = value
	func get_vsync() -> int: return vsync
	func set_frame_cap(_value: int) -> void: pass
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var audio = Feedback.new()
	root.add_child(audio)
	audio.configure({"data": {}}, null)
	audio.source_settings = {"_defaultMusicVolume": 0.3}
	var adapter = Adapter.new()
	adapter.configure(audio, Display.new())
	var panel = OptionsView.new()
	root.add_child(panel)
	var path := "user://audio-intent-%d.json" % Time.get_ticks_usec()
	panel.configure(adapter.apply, [], path)
	check(not FileAccess.file_exists(path), "startup apply does not persist options")
	audio.requests.request_interrupt(5)
	check(panel.model.values.bgm_db == 0 and audio.requests.mixer_bgm_db == -80, "fixture separates live mixer from saved preference")
	panel.open()
	check(is_equal_approx(panel.sliders.bgm.value, 0.0001), "first Start reads muted live mixer, not saved zero dB")
	check(is_equal_approx(panel.model.values.bgm_db, -80) and FileAccess.file_exists(path), "first changed slider assignment fires source callback and persists mute")
	check(panel.volume_labels.bgm.text.contains("0%"), "first activation label reflects actual live initial assignment")
	panel._volume_changed(1.0, "bgm")
	audio.requests.request_interrupt(5)
	var count: int = audio.requests.waits.size()
	panel._cycle("fullscreen")
	check(audio.requests.mixer_bgm_db == -80 and audio.requests.waits.size() == count, "graphics intent leaves BGM mute and wait intact")
	panel._volume_changed(0.25, "sfx")
	check(audio.requests.mixer_bgm_db == -80 and is_equal_approx(audio.user_sfx_db, -12.0412), "SFX callback never writes BGM")
	panel._apply_and_save()
	check(audio.requests.mixer_bgm_db == -80, "ordinary whole-plan refresh is not a BGM edit")
	panel.request_close()
	panel.open()
	check(panel.sliders.bgm.value == 1.0 and audio.requests.mixer_bgm_db == -80, "same instance reopen neither resamples nor resets live mute")
	panel._volume_changed(1.0, "bgm")
	check(audio.requests.mixer_bgm_db == 0 and panel.model.values.bgm_db == 0, "explicit same-saved-value BGM intent still writes mixer")
	check(audio.requests.waits.size() == count, "explicit volume edit does not invent coroutine cancellation")
	audio.requests.request_interrupt(5)
	panel.request_close()
	panel.reset_source_lifecycle()
	check(audio.requests.mixer_bgm_db == -80, "scene rebind defers new Start; no eager volume write")
	panel.open()
	check(is_equal_approx(panel.sliders.bgm.value, 0.0001) and is_equal_approx(panel.model.values.bgm_db, -80), "new scene-local Start samples live and invokes changed callback again")
	panel._confirm_reset()
	check(audio.requests.mixer_bgm_db == 0 and audio.user_sfx_db == 0 and audio.user_bgm_db == 0, "explicit Reset initializes both mixer channels")
	check(panel.sliders.bgm.value == 1 and panel.sliders.sfx.value == 1, "Reset reruns source InitVolumeSliders")
	check(not audio.requests.waits.is_empty(), "Reset restores mixer without canceling source persistent waits")
	audio.advance_scaled_time(5)
	check(audio.requests.mixer_bgm_db == 0 and is_equal_approx(audio.music_gain_linear(), 0.3), "completion retains source gain times captured mixer once")
	panel.queue_free()
	audio.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Options audio intent: %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
