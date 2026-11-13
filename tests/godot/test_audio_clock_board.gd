extends SceneTree
const Feedback = preload("res://scripts/ui/audio_feedback.gd")
class Host extends "res://scripts/ui/board.gd":
	var external_menu := false
	var model_frames := 0
	func _ready() -> void: set_process(false)
	func _sync_source_info() -> void: pass
	func _sync_scene_fader() -> void: pass
	func _advance_running_frame(_delta: float) -> void: model_frames += 1
	func _ui_pause_active() -> bool: return external_menu
	func _exit_tree() -> void: pass
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Host.new()
	root.add_child(board)
	board.add_child(board.feedback)
	board.add_child(board.vendor_unlock)
	board.feedback.requests.set_mixer(0)
	board.feedback.requests.request_interrupt(10)
	board._process(1)
	check(board.feedback.requests.waits[0].remaining == 9, "cold Title retains initial global scale one")
	board.running = true
	board.session.phase = "playing"
	board.session.speed = 2
	board.session.paused = false
	board._process(1)
	check(board.feedback.requests.waits[0].remaining == 7, "Fast scales pending audio wait twice")
	board.external_menu = true
	board._process(2)
	check(board.feedback.requests.waits[0].remaining == 7, "external menu pause freezes audio wait")
	board.external_menu = false
	board.session.paused = true
	board._process(1)
	check(board.feedback.requests.waits[0].remaining == 7, "manual pace pause freezes wait")
	board.session.paused = false
	board.session.phase = "feeding"
	board._process(1)
	check(board.feedback.requests.waits[0].remaining == 7, "day-end source pace zero freezes wait")
	board.session.phase = "playing"
	board.scene_transition.begin(func(): board.running = false)
	var before: int = board.source_audio_clock.advances
	board._process(5)
	check(board.source_audio_clock.advances == before+1 and board.feedback.requests.waits[0].remaining == 7, "oversized departure frame samples once, no post-commit time leaks")
	board._process(2)
	check(board.feedback.requests.waits[0].remaining == 7, "returned Title retains zero global scale with no TimeManager")
	board.scene_transition.cancel()
	board.scene_transition.begin(func():
		board.running = true
		board.session.speed = 1
		board.session.paused = false)
	board._process(1)
	check(board.feedback.requests.waits[0].remaining == 7, "title-to-game commit does not charge prior frozen frame")
	board._process(1)
	check(board.feedback.requests.waits[0].remaining == 6, "new TimeManager Normal releases prior persistent wait")
	board.scene_transition.cancel()
	board.scene_transition.begin(func(): board.session.speed = 1)
	board._process(1)
	board._process(1)
	check(board.feedback.requests.waits[0].remaining == 5, "travel preserves wait and arrival fade advances at Normal")
	check(board.source_audio_clock.advances == 11, "one audio sample for each native root _process invocation")
	# Dictionary-style fake catalog is sufficient: adapter reads catalog.data.
	var catalog: Dictionary = {"data": {"referenced_prefabs": [], "enums": {}}}
	board.feedback.source_initialized = true
	board.feedback.configure(catalog, null)
	check(board.feedback.requests.waits[0].remaining == 5 and board.feedback.requests.mixer_bgm_db == -80, "explicit media reconfigure retains pending singleton wait and live mixer")
	check(is_equal_approx(board.feedback.live_bgm_slider_value(), db_to_linear(-80)), "source slider queries live mixer during mute")
	board.feedback.set_user_gains(0, -6)
	board.feedback.advance_scaled_time(5)
	check(board.feedback.requests.mixer_bgm_db == 0 and board.feedback.user_bgm_db == -6, "completion restores live gain but does not rewrite persisted preference")
	board.feedback.source_settings = {"_defaultMusicVolume": 0.3}
	check(is_equal_approx(board.feedback.music_gain_linear(), 0.3), "restored mixer multiplied once by configured source gain")
	board.feedback.shutdown()
	check(board.feedback.requests.waits.is_empty(), "actual destruction/shutdown cancels lifetime waits")
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Audio board clock: %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
