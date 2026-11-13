extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const Effect = preload("res://scripts/ui/world_post_process.gd")
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new()
	var isolated := "user://post-process-%d" % Time.get_ticks_usec()
	board.slot_root = isolated + "/slots"
	board.options_path = isolated + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	check(board.data_error == OK, "actual source data required")
	for scene in ["Main", "Island"]:
		var binding := Effect.resolve(board.catalog.data, scene)
		check(binding.source_backed, scene + " enabled source camera/material binding")
	check(not Effect.resolve(board.catalog.data, "Title").source_backed, "title has no gameplay postprocess")
	var effect = board.world_post_process
	check(not effect.rect.visible, "title starts unchanged")
	check(effect.rect.mouse_filter == Control.MOUSE_FILTER_IGNORE, "effect never consumes input")
	check(effect.rect.get_parent().layer < board.hud.get_parent().layer and effect.rect.get_parent().layer < board.scene_shade.get_parent().layer, "world before HUD and fader")
	check(effect.rect.material.shader == Effect.EFFECT_SHADER, "native shader bound")
	board.start_new()
	board.set_process(false)
	check(not effect.rect.visible and effect.grayscale == 0 and effect.vignette == 0, "entry initializes writer; absent/PC renderer pass stays invisible")
	board.session.set_paused(true)
	var elapsed: float = board.session.elapsed
	board._process(0.15)
	check(is_equal_approx(effect.grayscale, 0.75) and board.session.elapsed == elapsed, "real-time tween continues while game clock paused")
	check(is_equal_approx(effect.rect.material.get_shader_parameter("grayscale_amount"), 0.75), "grayscale uniform synchronized")
	board.session.set_paused(false)
	board._process(0.3)
	board.session.cycle.request_end_day()
	check(effect.tracks.has("vignette") and not effect.tracks.has("grayscale"), "automatic day end is silent pause, vignette event only")
	board._process(0.25)
	check(is_equal_approx(effect.vignette, 0.9) and is_zero_approx(effect.grayscale), "day-end OutQuad while paused")
	check(is_equal_approx(effect.rect.material.get_shader_parameter("vignette_power"), 0.9), "vignette uniform synchronized")
	board.session.phase = "ready"
	check(board.session.start_day(), "actual source-style day-start reset")
	board._process(0.5)
	check(is_zero_approx(effect.vignette), "day start reverses vignette")
	board._on_session_event("time_pace_changed", {"pace": 0})
	board._process(0.1)
	board._show_title()
	board._process(9)
	check(not effect.rect.visible and effect.tracks.is_empty(), "title cancels stale work")
	board._enter_game()
	check(not effect.rect.visible and effect.grayscale == 0, "reentry preserves absent/PC pass, does not infer saved paused flag")
	board._on_session_event("day_ended", {})
	board.session.scene_name = "Island"
	board._enter_game()
	check(effect.tracks.is_empty() and effect.vignette == 0 and effect.config.source_backed, "travel scene commit cancels old effect")
	board.session.scene_name = "missing"
	board._enter_game()
	check(not effect.rect.visible and not effect.config.source_backed, "unknown scene passthrough")
	# Use production's shutdown contract before freeing the fixture. A timer
	# alone can consume this slow frame's delta and leave no real audio drain.
	board.process_mode = Node.PROCESS_MODE_DISABLED
	board.feedback.shutdown()
	check(board.feedback.shutting_down and board.feedback.stream_cache.is_empty() and board.feedback.last_played.is_empty(), "teardown closes audio admission and releases cached streams")
	var voices_stopped := true
	for player in board.feedback.find_children("*", "AudioStreamPlayer", true, false):
		voices_stopped = voices_stopped and not player.playing and player.stream == null
	check(voices_stopped and not board.feedback.play_event("Click") and not board.feedback.play_music(), "teardown stops every voice and rejects late playback")
	var deadline_usec: int = Time.get_ticks_usec() + int(Board.QUIT_AUDIO_DRAIN_SECONDS * 1000000)
	var remaining: float = Board.QUIT_AUDIO_DRAIN_SECONDS
	while remaining > 0:
		await create_timer(remaining, true, false, true).timeout
		remaining = float(deadline_usec - Time.get_ticks_usec()) / 1000000.0
	board.queue_free()
	await process_frame
	check(effect.tracks.is_empty(), "teardown cancels all tracks")
	print("World post-process board: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
