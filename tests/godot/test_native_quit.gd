extends SceneTree
## Exercises production SceneTree.quit, not the request-only quit_callback seam.
## The watchdog must inspect the completed engine log, including exit diagnostics.
const Main = preload("res://scenes/main.tscn")
const Catalog = preload("res://scripts/model/catalog.gd")
var checks := 0
var failures := 0
var board
var quit_started_usec: int = 0
var shutdown_probe_complete := false
var imported := false
var cached_audio := false
var checkpoint_path := ""
var checkpoint := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func sample() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 8000
	var silence := PackedByteArray()
	silence.resize(8000 * 2 * 30)
	stream.data = silence
	return stream

func configure_synthetic_audio() -> void:
	var catalog = Catalog.new()
	catalog.data = {"enums": {"AudioId": {"Click": 0, "Coin": 1}}, "referenced_prefabs": [{"documents": [{"script_class": "AudioManager", "fields": {
		"_SFXDataList": [{"audioId": 0, "audioClip": {"guid": "click"}}, {"audioId": 1, "audioClip": {"guid": "coin"}}],
		"_SFXPoolSize": 1, "_SFXCooldown": 0.0, "_randomizeSFXPitch": false,
		"_BGMClip": {"guid": "music"}, "_defaultMusicVolume": 0.3,
	}}]}]}
	board.feedback.configure(catalog, null)
	for guid in ["click", "coin", "music"]: board.feedback.stream_cache[guid] = sample()
	check(board.feedback.play_music(), "synthetic long-running music starts")

func _init() -> void: call_deferred("run")

func run() -> void:
	root.gui_embed_subwindows = true
	board = Main.instantiate()
	var directory := "user://native-quit-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	board.slot_root = directory + "/slots"
	board.options_path = directory + "/options.json"
	board.options_apply_adapter = func(_plan): return {"ok": true, "capabilities": {}, "warnings": []}
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	imported = board.data_error == OK and board.feedback.music != null
	if not imported: configure_synthetic_audio()
	board.feedback.cooldown = 0
	check(not board.quit_callback.is_valid() and board.feedback.music.playing, "live main scene has music and no quit interception")

	board.title_quit_button.pressed.emit()
	board.quit_dialog.canceled.emit()
	board.quit_dialog.confirmed.emit()
	board._confirm_quit()
	check(not board.quit_dispatched and not board.feedback.shutting_down and board.feedback.music.playing, "canceled/stale title quit leaves audio and scene alive")

	board._open_options()
	DirAccess.make_dir_absolute(board.options_path + ".tmp")
	board.options_panel._volume_changed(0.25, "sfx")
	board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(board.options_panel.visible and board.options_panel.dirty and not board.quit_dispatched and not board.feedback.shutting_down and board.feedback.music.playing, "failed options save never starts shutdown")
	DirAccess.remove_absolute(board.options_path + ".tmp")
	board.options_panel.request_close()

	if imported:
		board.start_new()
		check(board.running and board.active_slot > 0, "licensed game starts before quit regression")
		checkpoint_path = board._active_slot_path()
		checkpoint = FileAccess.get_file_as_string(checkpoint_path)
		DirAccess.make_dir_absolute(checkpoint_path + ".tmp")
		board.session.elapsed += 1.0
		board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		check(not board.quit_dispatched and not board.feedback.shutting_down and board.feedback.music.playing and FileAccess.get_file_as_string(checkpoint_path) == checkpoint, "failed gameplay quit save retains live music and old checkpoint")
		DirAccess.remove_absolute(checkpoint_path + ".tmp")
		board.session.phase = "ready"
		board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		board.quit_dialog.canceled.emit()
		board._confirm_quit()
		check(not board.quit_dispatched and not board.feedback.shutting_down and board.feedback.music.playing and FileAccess.get_file_as_string(checkpoint_path) == checkpoint, "canceled/stale day-end quit preserves music and checkpoint")
		board.session.phase = "playing"
		board._request_return_title()
		board._process(1.0)
		board._process(1.0)
		check(not board.running and not board.scene_transition.active(), "Save & Title completes before production quit")
		checkpoint = FileAccess.get_file_as_string(checkpoint_path)

	# Keep both base and overlapping voices active when quit is admitted.
	for event_name in board.feedback.clips:
		check(board.feedback.play_event(event_name), "SFX active before real quit: " + event_name)
	check(board.feedback.play_event("Click"), "same-slot overlap active before real quit")
	cached_audio = imported
	for stream in board.feedback.stream_cache.values():
		if stream.resource_path.is_empty(): cached_audio = false
	board.title_quit_button.pressed.emit()
	check(board.quit_dialog.visible, "real title confirmation is visible")
	quit_started_usec = Time.get_ticks_usec()
	# Shutdown must progress even when gameplay/engine time has stopped.
	Engine.time_scale = 0.0
	paused = true
	board.quit_dialog.confirmed.emit()
	check(board.quit_dispatched and board.process_mode == Node.PROCESS_MODE_DISABLED and board.feedback.shutting_down, "confirmed production quit closes audio admission and freezes the board")
	check(board.feedback.stream_cache.is_empty() and board.feedback.last_played.is_empty(), "quit releases cached streams before engine teardown, including post-action Click")
	check(not board.feedback.play_event("Click") and not board.feedback.play_music(), "late SFX/music requests cannot restart shutdown audio")
	board.feedback.music.finished.emit()
	board.feedback.shutdown() # Idempotence while still attached to the live tree.
	for player in board.feedback.pool:
		for voice in board.feedback._slot_voices(player):
			check(not voice.playing and voice.stream == null, "base/overlap voice stopped and detached before engine exit")
	check(not board.feedback.music.playing and board.feedback.music.stream == null, "queued music completion cannot restart music")
	board._execute_quit()
	board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	board.quit_dialog.confirmed.emit()
	check(not board.scene_transition.active() and not board.session.travel_pending, "repeated quit leaves no pending scene work")
	if imported: check(FileAccess.get_file_as_string(checkpoint_path) == checkpoint, "shutdown does not rewrite the committed checkpoint")
	await create_timer(0.05, true, false, true).timeout
	shutdown_probe_complete = true
	# No test-owned free, drain, or quit: production must finish engine shutdown.

func _finalize() -> void:
	check(shutdown_probe_complete, "production quit kept engine alive for audio drain")
	check(quit_started_usec > 0 and Time.get_ticks_usec() - quit_started_usec >= 450000, "shutdown uses a real-time drain even while paused at zero time scale")
	if imported and cached_audio and failures == 0: print("Private native quit: PASS (Save & Title, cached WAV playback, actual engine exit)")
	print("Native quit: %d checks, %d failures" % [checks, failures])
