extends SceneTree
## Source-backed UI routing checks, not a claim of rendered or manual acceptance.
const Board = preload("res://scripts/ui/board.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	var sounds: Array[String] = []
	func play_event(event_name: String) -> bool: sounds.append(event_name); return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func press(board, id: int) -> void:
	board._begin_card_press({"card_id":id, "panel_owner":-1}, Vector2.ZERO)
func click(board, id: int) -> void:
	press(board, id); board._finish_drag(Vector2.ZERO)
func reset_cards(board) -> void:
	board.dragging = -1; board.drag_grant = -1; board.drag_delta = Vector2.ZERO
	board.session.combat.dragged.clear()
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.spawn_target_selector = Callable()
	board.session.spawn_layout_resolver = Callable()
	board.session.elapsed = 0.0; board.session.phase = "playing"
	board.session.paused = false; board.session.cycle.reset()
	board.session.speed = 1.0; board.session.day = 1
func spawn(board, name: String, position := Vector2.ZERO) -> int:
	return board.session.spawn_card(board.catalog.find_by_name(name), position, -1, {"refuse_attach":true})
func chest_fixture(board) -> int:
	reset_cards(board)
	var id := spawn(board, "Card_Chest_WoodenChest")
	board.session.cards[id].stored_coins = 2
	board._refresh()
	return id
func action_count(board) -> int:
	var count := 0
	for button in board.hud.find_children("*", "Button", true, false):
		for connection in button.get_signal_connection_list("pressed"):
			if connection.callable == board._advance_day: count += 1
	return count
func check_panels(board, label: String) -> void:
	for market in [false, true]:
		for details in [false, true]:
			board.market_panel.visible = market; board.detail_panel.visible = details
			check(board.day_button.is_visible_in_tree(), "%s action visible with market=%s/details=%s" % [label,market,details])
func run() -> void:
	root.size = Vector2i(1440, 900)
	var board = Board.new()
	board.feedback.free(); board.feedback = SilentFeedback.new()
	var path := "user://cycle-action-visibility-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"; board.options_path = path + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board); await process_frame
	check(board.data_error == OK, "licensed source data loaded for UI regression")
	if board.data_error != OK:
		board.queue_free(); await process_frame; quit(1); return
	check(not board.day_button.is_visible_in_tree(), "title hides gameplay action")
	board.start_new(); board.set_process(false)
	await process_frame
	check(not board.market_panel.visible and not board.detail_panel.visible, "both sidebars start collapsed")
	check(board.day_button.is_visible_in_tree() and not board.day_button.disabled, "one End Day action remains available outside collapsed market")
	check(not board.market_panel.is_ancestor_of(board.day_button) and not board.detail_panel.is_ancestor_of(board.day_button), "day action has no collapsible sidebar ancestor")
	check(action_count(board) == 1, "exactly one HUD button dispatches the day action")
	var rect: Rect2 = board.day_button.get_global_rect()
	check(Rect2(Vector2.ZERO, Vector2(1440,900)).encloses(rect) and rect.size.x >= 300 and rect.size.y >= 34, "day action stays inside logical viewport with usable bounds")
	check(not board.status.get_global_rect().intersects(rect), "two-line status and day action do not overlap")
	check(board.speed_buttons.size() == 2 and board.speed_buttons.has(1.0) and board.speed_buttons.has(2.0), "pace controls expose only source Normal and Fast")
	var invalid_buttons: Array = board.hud.find_children("*", "Button", true, false).filter(func(b): return b.text == "3x")
	check(invalid_buttons.is_empty(), "no inert 3x control exists")
	board.speed_buttons[2.0].pressed.emit()
	check(board.session.speed == 2.0 and not board.session.paused and board.status.text.contains("2x"), "Fast control changes speed and refreshes status")
	board._toggle_pause(); board.speed_buttons[1.0].pressed.emit()
	check(board.session.speed == 1.0 and not board.session.paused and board.status.text.contains("1x"), "Normal control resumes manual pause at normal speed")
	# Real natural day-end path, including deferred event refresh without a test
	# call to _refresh after the transition.
	reset_cards(board)
	spawn(board, "Villager", Vector2(-2,0))
	var food := spawn(board, "Berry", Vector2(2,0))
	board.session.cards[food].nutrition = 4
	board.market_panel.hide(); board.detail_panel.hide()
	board.session.elapsed = board.session.day_duration
	board._process(0.01); await process_frame
	check(board.session.phase == "feeding" and board.session.cycle.stage == "await_feed", "natural clock boundary waits for explicit Feed")
	check(board.day_button.text == "Feed villagers" and not board.day_button.disabled and board.day_button.is_visible_in_tree(), "natural boundary exposes enabled visible Feed without opening market")
	check_panels(board, "Feed")
	board.day_button.pressed.emit()
	check(board.session.cycle.stage == "character_focus" and board.day_button.disabled, "Feed starts timeline and disables same action immediately")
	var remaining: float = board.session.cycle.remaining
	board.day_button.pressed.emit()
	check(board.session.cycle.remaining == remaining, "repeated Feed cannot restart timeline")
	for frame in 200:
		if board.session.phase in ["ready", "selling", "game_over"]: break
		board._process(0.1)
	await process_frame
	check(board.session.phase == "ready" and board.day_button.text == "Start next day" and not board.day_button.disabled, "completed cycle exposes Start Day")
	check_panels(board, "Start Day")
	board.market_panel.hide(); board.detail_panel.hide()
	board.day_button.pressed.emit()
	check(board.session.phase == "playing" and board.session.day == 2, "visible Start Day begins exactly the next day")
	check(JSON.parse_string(FileAccess.get_file_as_string(board._active_slot_path())).scenes.Main.session.day == 2, "Start Day still checkpoints through existing slot adapter")
	# Synthetic phase fixtures cover every lock without changing model timings.
	for phase in ["feeding", "selling", "encounter", "ready", "game_over"]:
		board.session.phase = phase; board.session.cycle.stage = "await_feed" if phase == "feeding" else "idle"
		board._refresh()
		check(board.speed_buttons[1.0].disabled and board.speed_buttons[2.0].disabled, phase + " disables both pace controls")
		board.speed_buttons[2.0].pressed.emit()
		check(board.session.speed == 1.0, phase + " rejects direct stale pace callbacks")
		board._handle_escape(); board._open_options()
		check(not board._ui_pause_active(), phase + " preserves menu/Options entry locks")
		if phase in ["selling", "encounter"]:
			board.day_button.pressed.emit()
			check(board.day_button.disabled and board.session.phase == phase, phase + " shows nonactionable status without advancing")
	# Natural starvation produces the required Game Over action while collapsed.
	reset_cards(board)
	spawn(board, "Villager")
	board.market_panel.hide(); board.detail_panel.hide()
	board.session.elapsed = board.session.day_duration
	board._process(0.01); await process_frame
	board.day_button.pressed.emit()
	for frame in 200:
		if board.session.phase == "game_over": break
		board._process(0.1)
	await process_frame
	check(board.session.phase == "game_over" and not board.day_button.disabled, "starvation exposes required Game Over return action")
	check_panels(board, "Game Over")
	var saved: String = FileAccess.get_file_as_string(board._active_slot_path())
	board.day_button.pressed.emit(); board.day_button.pressed.emit()
	check(board.game_over_dialog.visible and board.running and FileAccess.get_file_as_string(board._active_slot_path()) == saved, "repeated Game Over action asks once and does not archive without confirmation")
	board.game_over_dialog.hide(); board.game_over_dialog.canceled.emit()
	check(board.day_button.is_visible_in_tree() and board.running, "canceling Game Over retains visible retry action")
	# Native chest click uses the same placement and withdrawal helper as the
	# explicit inspection command, with the exact-card carried grant.
	var chest := chest_fixture(board)
	click(board, chest)
	check(board.session.cards[chest].stored_coins == 1 and board.session.cards.size() == 2, "singleton source Wooden Chest click withdraws one real coin")
	check(board.notice.text == "Withdrew a coin." and board.feedback.sounds.has("Coin"), "confirmed withdrawal reports and requests source Coin sound")
	board._finish_drag(Vector2.ZERO); board._finish_drag(Vector2.ZERO)
	check(board.session.cards[chest].stored_coins == 1 and board.session.cards.size() == 2, "repeated release cannot withdraw again")
	board.selected = chest; board._withdraw_selected()
	check(board.session.cards[chest].stored_coins == 0 and board.session.cards.size() == 3, "explicit inspection withdrawal uses same behavior")
	click(board, chest)
	check(board.notice.text == "Chest is empty." and board.session.cards.size() == 3, "empty chest click creates no phantom currency")
	chest = chest_fixture(board)
	board.session.spawn_card(board.catalog.find_by_name("Wood"), Vector2.ZERO, board.session.cards[chest].stack_id)
	board._refresh(); click(board, chest)
	check(board.session.cards[chest].stored_coins == 2, "stacked chest click does not withdraw")
	chest = chest_fixture(board)
	press(board, chest); board.drag_moved = true; board.drag_delta = Vector2.ZERO
	board._finish_drag(Vector2.ZERO)
	check(board.session.cards[chest].stored_coins == 2, "drag returned to press origin is not misclassified as click")
	press(board, chest); board.drag_moved = true; board.drag_delta = Vector2(2,0)
	board._finish_drag(Vector2.ZERO)
	check(board.session.cards[chest].stored_coins == 2, "ordinary chest movement does not withdraw")
	for phase in ["feeding", "encounter", "ready", "game_over"]:
		board.session.phase = phase
		click(board, chest)
		check(board.session.cards[chest].stored_coins == 2 and board.drag_grant == -1, phase + " rejects new chest click")
		board.selected = chest; board._withdraw_selected()
		check(board.session.cards[chest].stored_coins == 2, phase + " rejects explicit withdrawal too")
	board.session.phase = "selling"
	click(board, chest)
	check(board.session.cards[chest].stored_coins == 1, "selling phase still allows chest clicks")
	chest = chest_fixture(board)
	press(board, chest); board.session.cycle.request_end_day()
	board._finish_drag(Vector2.ZERO)
	check(board.session.cards[chest].stored_coins == 1 and board.drag_grant == -1, "valid held chest press survives natural day lock once")
	board._finish_drag(Vector2.ZERO); click(board, chest)
	check(board.session.cards[chest].stored_coins == 1, "consumed boundary grant cannot authorize repeated or fresh locked clicks")
	chest = chest_fixture(board)
	press(board, chest); board._toggle_pause_menu()
	check(board.day_button.disabled and board.speed_buttons[2.0].disabled, "pause menu immediately disables background action controls")
	board.day_button.pressed.emit(); board.speed_buttons[2.0].pressed.emit(); board._finish_drag(Vector2.ZERO)
	check(board.session.phase == "playing" and board.session.speed == 1.0 and board.session.cards[chest].stored_coins == 2, "menu interruption rejects stale day/speed/chest callbacks")
	board._toggle_pause_menu()
	check(not board.day_button.disabled and not board.speed_buttons[2.0].disabled, "resuming restores allowed controls immediately")
	press(board, chest); board._open_options(); board._finish_drag(Vector2.ZERO)
	board.day_button.pressed.emit(); board.speed_buttons[2.0].pressed.emit()
	check(board.session.phase == "playing" and board.session.speed == 1.0 and board.session.cards[chest].stored_coins == 2, "Options interruption cancels chest grant and blocks background controls")
	board.options_panel.request_close(); board._toggle_pause_menu()
	board._return_title()
	check(not board.day_button.is_visible_in_tree(), "return to title hides single gameplay action")
	board._continue_game(); board.set_process(false)
	check(board.day_button.is_visible_in_tree() and action_count(board) == 1, "Continue restores exactly one reachable day action")
	board.queue_free(); await process_frame; await create_timer(0.3).timeout
	print("Cycle action visibility: %d passed / %d total" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
