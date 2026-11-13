extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const Session = preload("res://scripts/model/game_session.gd")
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
	var path := "user://pause-ending-actions-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"; board.options_path = path + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board); await process_frame
	board.start_new(); board.set_process(false)
	var slot: int = board.active_slot
	var source_session = board.session
	var person: int = board.session.spawn_card(board.catalog.find_by_name("Villager"), Vector2(4, 0))
	var food: int = board.session.spawn_card(board.catalog.find_by_name("Berry"), Vector2(-4, 0))
	board.session.cards[person].health = 7
	board.session.cards[food].nutrition = 1
	board.session.elapsed = board.session.day_duration - 0.25
	board._process(0.25); board._toggle_pause_menu(); board._process(0.0)
	check(board.pause_overlay.visible and board.session.phase == "feeding", "real threshold enters feeding with existing Pause")
	var zones: Array = board.trade_zones.duplicate(true)
	for zone in zones:
		if zone.get("kind", "") == "vendor": zone.active = true
	board.vendor_unlock.sequence.on_quest_completed(zones)
	check(board.vendor_unlock.is_active(), "independent vendor pause owns overlapping state")
	board.pause_controls[1].pressed.emit()
	check(board.options_panel.visible and board.pause_overlay.visible, "actual Options button opens over existing Pause during feeding")
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE; cancel.pressed = true
	board._unhandled_input(cancel)
	check(board.options_panel.visible and board.pause_overlay.visible, "ending-cycle Escape cannot dismiss Options or Pause")
	board.options_panel.close_button.pressed.emit()
	check(not board.options_panel.visible and board.pause_overlay.visible, "actual Options Close returns to same Pause")
	check(board.session.paused and board.session.phase == "feeding" and board.vendor_unlock.is_active() and not board._allows_card_actions(), "Options close retains day/vendor/input locks")
	check(FileAccess.file_exists(board.options_path), "Options close persists to test-owned path")
	# Save failure is caused only inside our fresh test-owned directory.
	var blocker := FileAccess.open(path + "/blocker", FileAccess.WRITE)
	blocker.store_string("test-owned file, not a save directory"); blocker.close()
	var slot_root: String = board.slot_root
	board.slot_root = path + "/blocker/slots"
	board.pause_controls[2].pressed.emit()
	check(board.running and board.session == source_session and not board.scene_transition.active() and board.pause_overlay.visible, "actual Title save failure never leaves or starts fade")
	check("Could not save" in board.notice.text and board.vendor_unlock.is_active(), "failure reports error and retains vendor owner")
	board.slot_root = slot_root
	board.pause_controls[2].pressed.emit()
	check(board.scene_transition.active() and board.running, "actual Title saves successfully before fade")
	var saved_path: String = board.slots.slot_path(slot)
	var saved_text := FileAccess.get_file_as_string(saved_path)
	var saved: Dictionary = JSON.parse_string(saved_text)
	check(saved.scenes.Main.session.phase == "feeding" and saved.scenes.Main.session.elapsed == 0.0 and saved.scenes.Main.session.cycle.stage == "await_feed", "real disk checkpoint retains pending feeding and zero source clock")
	var candidate := Session.new(); candidate.configure(board.catalog)
	check(candidate.campaign.restore(saved).ok and candidate.phase == "feeding" and candidate.cycle.stage == "await_feed", "real saved campaign validates and restores pending cycle")
	check(candidate.cards.size() == saved.scenes.Main.session.cards.size(), "restored card count matches saved checkpoint")
	for card in saved.scenes.Main.session.cards:
		var restored = candidate.cards[int(card.id)]
		var equal: bool = restored.definition_guid == card.definition_guid and restored.base_definition_guid == card.base_definition_guid
		for field in ["id", "stack_id", "uses_left", "nutrition", "health", "stored_coins"]:
			equal = equal and int(restored.get(field)) == int(card[field])
		check(equal, "restored saved card identity, stats and membership: " + str(card.id))
	check(candidate.cards[person].health == 7 and candidate.cards[food].nutrition == 1, "feeding checkpoint does not heal or consume before confirmation")
	board.pause_controls[1].pressed.emit(); board.pause_controls[2].pressed.emit()
	check(not board.options_panel.visible and FileAccess.get_file_as_string(saved_path) == saved_text, "transition guards block extra Options/Title actions")
	board._process(1.0); board._process(1.0)
	check(not board.running and board.title_panel.visible and FileAccess.get_file_as_string(saved_path) == saved_text, "fade commits Title without rewriting checkpoint")
	board.selected_slot = slot; board._request_continue_game(); board._process(1.0); board._process(1.0); board.set_process(false)
	check(board.running and board.active_slot == slot and board.session.phase == "feeding" and board.session.cycle.stage == "await_feed", "real Continue reloads saved feeding state")
	# Game-over path keeps its separate confirmation, never saves/deletes on Title click.
	board.session.phase = "game_over"; board.session.cycle.reset(); board.pause_overlay.show()
	board.pause_controls[2].pressed.emit()
	check(board.game_over_dialog.visible and board.running and not board.scene_transition.active(), "actual existing-Pause Title at game over requests confirmation")
	check(FileAccess.get_file_as_string(saved_path) == saved_text, "unconfirmed game over preserves saved slot")
	board.pause_controls[1].pressed.emit(); board.pause_controls[2].pressed.emit()
	check(not board.options_panel.visible and board.game_over_dialog.visible and not board.scene_transition.active(), "modal blocks Options and duplicate Title")
	board.game_over_dialog.canceled.emit()
	check(board.running and FileAccess.file_exists(saved_path), "cancelled game-over archive keeps game and slot")
	board.pause_overlay.hide(); board._open_options(); board._toggle_pause_menu(); board._unhandled_input(cancel)
	check(not board.pause_overlay.visible and not board.options_panel.visible, "ending-cycle new menu/options and Escape remain gated")
	board.pause_overlay.show(); board.pause_controls[2].pressed.emit()
	board.game_over_dialog.confirmed.emit()
	check(board.running and FileAccess.file_exists(saved_path), "confirmed archive waits for transition commit")
	board._process(1.0); board._process(1.0)
	var archives: Dictionary = board.slots.list_archives()
	check(not board.running and not FileAccess.file_exists(saved_path) and archives.ok and not archives.archives.is_empty(), "confirmed game over preserves recoverable archive return path")
	board.queue_free(); await process_frame; await create_timer(0.5).timeout
	print("Pause ending actions: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
