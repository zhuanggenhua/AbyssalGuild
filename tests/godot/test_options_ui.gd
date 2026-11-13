extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const OptionsPanel = preload("res://scripts/ui/options_panel.gd")
const OptionsAdapter = preload("res://scripts/ui/options_adapter.gd")
const AudioFeedback = preload("res://scripts/ui/audio_feedback.gd")
var checks: int = 0
var failures: int = 0
var plans: Array = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func fake_apply(plan: Dictionary) -> Dictionary:
	plans.append(plan.duplicate(true))
	return {"ok": true, "capabilities": {"window_mode": true, "vsync": true, "fps_cap": true, "shadow_presets": false}, "warnings": ["Unity shadow presets unavailable."] + (["Half VSync unsupported; not applied."] if plan.options.vsync == 2 else [])}
func _init() -> void: call_deferred("run")
func run() -> void:
	var engine_cap: int = Engine.max_fps
	var master_gain: float = AudioServer.get_bus_volume_db(0)
	var root_path: String = "user://options-ui-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(root_path)
	var board = Board.new()
	board.options_path = root_path + "/options.json"
	board.options_hardware_modes = [[1280, 720], [1920, 1080]]
	board.options_apply_adapter = fake_apply
	board.slot_root = root_path + "/slots"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	check(board.data_error == OK, "real source data loaded")
	if board.data_error != OK: quit(1); return
	var panel = board.options_panel
	check(plans.size() == 1 and not FileAccess.file_exists(board.options_path), "startup loads defaults and sends plan without implicitly saving")
	check(panel.model.values.resolution == [1920, 1080], "resolution comes from verified injected mode list")
	board._open_options()
	check(panel.visible and not board.running, "title opens options without a game")
	panel._volume_changed(0.5, "sfx")
	check(is_equal_approx(panel.model.values.sfx_db, -6.0206), "SFX slider uses source logarithmic conversion")
	check(FileAccess.file_exists(board.options_path) and panel.status_label.text.begins_with("Preferences saved"), "slider change persists immediately")
	panel._volume_changed(0.0, "bgm")
	check(panel.model.values.bgm_db == -80.0 and panel.volume_labels.bgm.text.contains("0%"), "BGM zero uses source -80dB floor")
	panel._cycle("fullscreen")
	check(plans.back().options.fullscreen == "windowed", "window mode change sent through injected adapter")
	panel._cycle("resolution")
	check(plans.back().options.resolution == [1280, 720], "resolution cycles only verified modes")
	panel._cycle("fps_cap")
	check(plans.back().options.fps_cap == 30 and plans.back().fps_overridden_by_vsync and (panel.buttons.fps_cap.text.contains("overridden") or panel.buttons.fps_cap.tooltip_text.contains("overridden")), "VSync precedence is explicit")
	panel._cycle("vsync")
	check(panel.model.values.vsync == 2 and panel.status_label.text.contains("Half VSync unsupported"), "Half VSync reported unsupported rather than silently mapped")
	panel._cycle("vsync")
	check(panel.model.values.vsync == 0 and not plans.back().fps_overridden_by_vsync, "VSync Off enables selected cap in plan")
	var shadow: int = panel.model.values.shadow_preset
	panel._cycle("shadow_preset")
	check(panel.buttons.shadow_preset.disabled and panel.model.values.shadow_preset == shadow, "unverified shadow mapping cannot be applied from UI")
	panel.request_close()
	check(not panel.visible, "successful Close flushes and hides panel")
	board.start_new()
	board.set_process(false)
	var slot_bytes: String = FileAccess.get_file_as_string(board._active_slot_path())
	board.session.set_speed(2.0)
	board.session.elapsed = 20.0
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	board._unhandled_input(escape)
	check(board.pause_overlay.visible and board._ui_pause_active(), "Escape opens external pause menu")
	board._process(3.0)
	check(board.session.elapsed == 20.0 and not board.session.paused and board.session.speed == 2.0, "menu lock stops tick without changing selected pace")
	check(not board._allows_card_actions(), "pause overlay blocks gameplay input")
	board._open_options()
	check(panel.visible and board.pause_overlay.visible, "pause menu opens same options panel")
	DirAccess.make_dir_absolute(board.options_path + ".tmp")
	var prior_options: String = FileAccess.get_file_as_string(board.options_path)
	panel._volume_changed(0.25, "sfx")
	check(panel.dirty and panel.status_label.text.contains("NOT saved") and FileAccess.get_file_as_string(board.options_path) == prior_options, "failed options write preserves disk and reports pending session changes")
	board._handle_escape()
	check(panel.visible and board._ui_pause_active() and panel.status_label.text.contains("Could not save"), "failed Save and Close via Escape keeps options and pause open")
	DirAccess.remove_absolute(board.options_path + ".tmp")
	board._handle_escape()
	check(not panel.visible and board.pause_overlay.visible, "options close returns to pause menu without resuming")
	board._handle_escape()
	check(not board._ui_pause_active() and board.session.speed == 2.0 and not board.session.paused, "second Escape resumes prior pace")
	board.session.set_paused(true)
	board._handle_escape()
	board._handle_escape()
	check(board.session.paused, "menu roundtrip preserves manual pause")
	for phase in ["feeding", "selling", "ready", "game_over"]:
		board.session.phase = phase
		board._handle_escape()
		board._open_options()
		check(not panel.visible and not board.pause_overlay.visible and board.session.phase == phase, phase + " cycle lock blocks Escape/options entry")
	board.session.phase = "playing"
	board._open_options()
	var before_reset: Dictionary = panel.model.snapshot()
	panel._request_reset()
	check(panel.reset_dialog.visible and panel.model.snapshot() == before_reset, "reset asks before changing preferences")
	panel.reset_dialog.hide()
	panel._confirm_reset()
	check(panel.model.values.sfx_db == 0.0 and panel.model.values.bgm_db == 0.0 and panel.model.values.fps_cap == -1, "confirmed reset restores only options defaults")
	check(FileAccess.get_file_as_string(board._active_slot_path()) == slot_bytes, "options reset leaves campaign save untouched")
	panel.request_close()
	board._handle_escape()
	check(Engine.max_fps == engine_cap and is_equal_approx(AudioServer.get_bus_volume_db(0), master_gain), "fake application never changes engine cap or host/app master gain")
	# Backup/default fallbacks are visible and never repaired merely by loading/closing.
	var healthy: String = FileAccess.get_file_as_string(board.options_path)
	var file := FileAccess.open(board.options_path + ".bak", FileAccess.WRITE)
	file.store_string(healthy)
	file.close()
	file = FileAccess.open(board.options_path, FileAccess.WRITE)
	file.store_string("broken options evidence")
	file.close()
	var recovered = OptionsPanel.new()
	root.add_child(recovered)
	var result: Dictionary = recovered.configure(fake_apply, [], board.options_path)
	check(result.ok and result.recovered and recovered.status_label.text.contains("recovered from backup"), "options backup recovery is explained")
	check(FileAccess.get_file_as_string(board.options_path) == "broken options evidence", "options load leaves corrupt primary intact")
	file = FileAccess.open(board.options_path + ".bak", FileAccess.WRITE)
	file.store_string("broken backup evidence")
	file.close()
	result = recovered.configure(fake_apply, [], board.options_path)
	check(not result.ok and recovered.load_warning and recovered.status_label.text.contains("defaults are in use"), "invalid options surface fallback warning")
	recovered.open()
	recovered.request_close()
	check(FileAccess.get_file_as_string(board.options_path) == "broken options evidence" and FileAccess.get_file_as_string(board.options_path + ".bak") == "broken backup evidence", "closing untouched fallback does not overwrite corrupt evidence")
	check(recovered.buttons.resolution.disabled and recovered.buttons.resolution.text.contains("unavailable"), "no hardware modes yields disabled truthful resolution control")
	# Pure gain composition on a detached feedback node; no audio is played.
	var audio = AudioFeedback.new()
	check(is_equal_approx(audio.music_gain_linear(), 0.3), "source default music gain remains 0.3 once")
	check(audio.set_user_gains(-6.0206, -6.0206) and is_equal_approx(audio.music_gain_linear(), 0.15), "user music gain multiplies source clip gain once")
	audio.set_user_gains(-6.0206, -6.0206)
	check(is_equal_approx(audio.music_gain_linear(), 0.15), "reapplying user gain does not compound source gain")
	audio.source_settings["_defaultMusicVolume"] = 0.6
	check(is_equal_approx(audio.music_gain_linear(), 0.3), "imported source music gain composes with user preference")
	check(not audio.set_user_gains(INF, 0) and is_equal_approx(audio.user_sfx_db, -6.0206), "invalid user gain rejected without mutation")
	audio.free()
	var native = OptionsAdapter.new()
	if DisplayServer.get_name() == "headless":
		result = native.apply(panel.model.application_plan())
		check(result.applied.is_empty() and Engine.max_fps == engine_cap, "native adapter headless path never changes engine/display/audio")
	print("Options UI checks: %d passed / %d total" % [checks - failures, checks])
	recovered.queue_free()
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit(0 if failures == 0 else 1)
