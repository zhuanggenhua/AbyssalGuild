extends SceneTree
## Synthetic signal/request traces, not listening or visual acceptance.
const TextFeedback = preload("res://scripts/ui/text_button_feedback.gd")
const Board = preload("res://scripts/ui/board.gd")
class SpyAudio extends "res://scripts/ui/audio_feedback.gd":
	var event_requests: Array[String] = []
	func play_event(event: String) -> bool:
		event_requests.append(event)
		return super.play_event(event)
var checks := 0
var failures := 0
var trace: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	root.gui_embed_subwindows = true
	var button = TextFeedback.new()
	root.add_child(button)
	button.configure(func(): trace.append("action"); button.hide(), func(): trace.append("Click"))
	button.pressed.emit()
	check(trace == ["action", "Click"], "callback-before-sound even when callback hides")
	button.pressed.emit()
	button.show(); button.disabled = true; button.pressed.emit()
	check(trace.size() == 2, "hidden and disabled stale signals silent")
	button.disabled = false
	button.configure(Callable(), func(): trace.append("Click"))
	button.pressed.emit(); button.mouse_entered.emit()
	check(trace.size() == 2 and button.underline, "no callback means silent; hover underlines")
	button.mouse_exited.emit(); check(not button.underline, "exit clears underline")
	button.mouse_entered.emit(); button.disabled = true; button._process(0)
	check(not button.underline, "disable clears underline")
	button.disabled = false; button.mouse_entered.emit(); button.hide()
	check(not button.underline, "hide clears underline")
	var dialog := ConfirmationDialog.new()
	root.add_child(dialog)
	TextFeedback.bind_modal(dialog, func(): trace.append("accept"), func(): trace.append("decline"), func(): trace.append("Click"))
	trace.clear(); dialog.confirmed.emit(); check(trace.is_empty(), "hidden modal stale confirmation inert")
	dialog.popup_centered(); dialog.get_ok_button().pressed.emit()
	check(trace == ["accept", "Click"] and not dialog.visible, "modal accept exactly one ordered request")
	trace.clear(); dialog.popup_centered(); dialog.get_cancel_button().pressed.emit()
	check(trace == ["decline", "Click"] and not dialog.visible, "modal decline exactly one ordered request")
	var board = Board.new()
	board.feedback.free()
	var spy := SpyAudio.new()
	board.feedback = spy
	var path := "user://ui-click-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(path)
	board.slot_root = path + "/slots"; board.options_path = path + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	spy.event_requests.clear()
	board.title_new_button.pressed.emit(); board.title_new_button.pressed.emit()
	check(spy.event_requests == ["Click"], "title one request; stale hidden repeat none")
	spy.event_requests.clear(); board.friendly_choice.toggled.emit(true)
	check(spy.event_requests == ["Click"] and board.friendly_choice.text.contains("ON"), "friendly listener label then Click")
	board.title_cancel_button.pressed.emit(); spy.event_requests.clear()
	board.friendly_choice.toggled.emit(false)
	check(spy.event_requests.is_empty(), "hidden friendly stale signal silent")
	for gamepad in [false, true]:
		board._request_title_quit()
		await process_frame
		spy.event_requests.clear()
		var event: InputEvent
		if gamepad:
			var joy := InputEventJoypadButton.new()
			joy.button_index = JOY_BUTTON_B; joy.pressed = true; event = joy
		else:
			var key := InputEventKey.new()
			key.keycode = KEY_ESCAPE; key.pressed = true; event = key
		root.push_input(event)
		await process_frame
		check(not board.quit_dialog.visible and board.pending_quit.is_empty() and spy.event_requests == ["Click"], "viewport cancel clears pending intent and clicks once: %s" % gamepad)
	board._open_options(); spy.event_requests.clear()
	board.title_new_button.pressed.emit()
	check(spy.event_requests.is_empty(), "options overlay blocks title")
	board.options_panel.capabilities.fps_cap = true
	board.options_panel.buttons.fps_cap.disabled = false
	board.options_panel.buttons.fps_cap.pressed.emit()
	check(spy.event_requests == ["Click"], "options cycle single request")
	spy.event_requests.clear(); board.options_panel.reset_dialog.popup_centered()
	board.options_panel.buttons.fps_cap.pressed.emit()
	check(spy.event_requests.is_empty(), "reset modal blocks options controls")
	board.options_panel.reset_dialog.get_ok_button().pressed.emit()
	check(spy.event_requests == ["Click"], "reset confirmation one request after application")
	board.options_panel.request_close()
	if board.data_error == OK:
		board.start_new(); board.scene_transition.cancel(); board.hud.show(); board.title_panel.hide()
		spy.event_requests.clear(); board.day_clock.pressed.emit()
		check(spy.event_requests.count("Click") == 1, "existing day-clock owner not duplicated")
		spy.event_requests.clear(); board.detail_toggle.pressed.emit()
		check(spy.event_requests.count("Click") == 1, "existing journal-slide owner not duplicated")
		board.journal_slide.advance(0.5)
		board.detail_panel.show(); spy.event_requests.clear()
		board._show_journal_tab("quests")
		check(spy.event_requests == ["Click"], "MenuView show request")
		spy.event_requests.clear(); board.ledger_visible_groups["synthetic"] = true
		board._on_ledger_group_clicked({"journal_group": "synthetic"})
		check(spy.event_requests == ["Click"], "group header single request")
		spy.event_requests.clear(); board.ledger_visible_ids["synthetic"] = true
		board._on_ledger_hover("synthetic")
		check(spy.event_requests.is_empty(), "per-row mark-read silent")
		board.pause_overlay.show(); board.ledger_visible_groups["synthetic"] = true
		board._on_ledger_group_clicked({"journal_group": "synthetic"})
		check(spy.event_requests.is_empty(), "blocked group stale signal silent")
		board.pause_overlay.hide(); board.journal_slide.reset(false); spy.event_requests.clear()
		board.day_button.disabled = false; board.day_button.show(); board.day_button.pressed.emit()
		check(spy.event_requests.count("Click") == 1, "day action one request")
	else:
		print("SKIP: 7 private gameplay UI click checks require imported source data")
	var missing := preload("res://scripts/ui/audio_feedback.gd").new()
	root.add_child(missing)
	check(not missing.play_event("Click") and missing.pool.is_empty(), "missing private audio silent")
	board.free(); button.free(); dialog.free(); missing.free()
	await process_frame
	await create_timer(0.6).timeout
	print("Text button feedback: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
