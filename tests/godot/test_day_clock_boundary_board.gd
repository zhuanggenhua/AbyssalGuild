extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_name: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board := Board.new()
	board.feedback.free(); board.feedback = SilentFeedback.new()
	var path := "user://day-boundary-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"; board.options_path = path + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board); await process_frame
	board.start_new(); board.set_process(false)
	check(board.data_error == OK, "source catalog loaded")
	for mode in ["normal", "menu", "vendor", "overlap"]:
		board.pause_overlay.hide()
		board.vendor_unlock.sequence.restore(board.trade_zones)
		board.session.cycle.reset()
		board.session.phase = "playing"; board.session.paused = false
		board.session.day_duration = 1.0; board.session.elapsed = 0.75
		board._process(0.25)
		check(board.session.phase == "playing" and board.session.elapsed == 1.0 and board._allows_card_actions(), "board threshold crossing stays unlocked: " + mode)
		if mode in ["menu", "overlap"]: board._toggle_pause_menu()
		if mode in ["vendor", "overlap"]:
			var zones: Array = board.trade_zones.duplicate(true)
			for zone in zones:
				if zone.get("kind", "") == "vendor": zone.active = true
			board.vendor_unlock.sequence.on_quest_completed(zones)
			check(board.vendor_unlock.is_active(), "real vendor sequence owns external pause")
		board._process(0.0)
		check(board.session.phase == "feeding" and board.session.elapsed == 0.0 and not board._allows_card_actions(), "board zero-delta dispatch reaches threshold under " + mode)
		check(board.session.cycle.stage == "await_feed", "board threshold does not consume food")
		if mode in ["menu", "overlap"]: check(board.pause_overlay.visible, "day boundary does not silently release menu owner")
		if mode in ["vendor", "overlap"]: check(board.vendor_unlock.is_active(), "day boundary does not silently release vendor owner")
		if mode in ["menu", "overlap"]:
			var cancel := InputEventKey.new()
			cancel.keycode = KEY_ESCAPE; cancel.pressed = true
			board._unhandled_input(cancel)
			check(board.pause_overlay.visible, "ending-cycle Escape cannot close menu: " + mode)
			board.pause_controls[0].pressed.emit()
			check(not board.pause_overlay.visible, "actual Continue button closes existing menu during day end: " + mode)
			check(board.session.paused and board.session.phase == "feeding" and not board._allows_card_actions(), "Continue retains day owner: " + mode)
			if mode == "overlap": check(board.vendor_unlock.is_active(), "Continue retains independent vendor owner")
			board.pause_controls[0].pressed.emit()
			board._unhandled_input(cancel)
			check(not board.pause_overlay.visible, "repeated hidden Continue and ending-cycle Escape cannot reopen menu")
			board._toggle_pause_menu()
			check(not board.pause_overlay.visible, "ordinary menu opening stays day-gated")
		board.pause_overlay.hide()
		board.vendor_unlock.sequence.cancel()
		check(not board._allows_card_actions(), "removing external owners does not release day lock")
	board.queue_free(); await process_frame; await create_timer(0.5).timeout
	print("Day clock boundary board: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
