extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	var sounds: Array = []
	func play_event(event_name: String) -> bool: sounds.append(event_name); return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",label)
func _init() -> void: call_deferred("run")
func press(board, id: int) -> void:
	board._begin_card_press({"card_id":id,"panel_owner":-1},Vector2.ZERO)
func run() -> void:
	var board = Board.new()
	board.feedback.free(); board.feedback = SilentFeedback.new()
	var path := "user://cycle-board-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"; board.options_path = path + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board); await process_frame
	board.start_new(); board.set_process(false)
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.spawn_target_selector = Callable()
	board.session.spawn_layout_resolver = Callable()
	var person: int = board.session.spawn_card(board.catalog.find_by_name("Villager"),Vector2(-2,0))
	var food: int = board.session.spawn_card(board.catalog.find_by_name("Berry"),Vector2(2,0))
	board.session.cards[food].nutrition = 4
	board._refresh()
	check(board.session.cycle.pose_sampler.is_valid() and board.session.cycle.layout_resolver.is_valid(), "cycle presentation callbacks bound")
	board.session.day = 5 # Actual source guaranteed wandering-villager encounter.
	board.session.elapsed = board.session.day_duration
	board._process(0.01); board._refresh()
	check(board.session.phase == "feeding" and board.session.cycle.stage == "await_feed" and not board.day_button.disabled, "natural day end waits for Feed action")
	board._advance_day()
	check(board.session.cycle.stage == "character_focus" and board.day_button.disabled, "Feed starts nonblocking focus and locks repeated action")
	var remaining: float = board.session.cycle.remaining
	board._advance_day()
	check(board.session.cycle.remaining == remaining, "repeated Feed cannot restart timeline")
	board._process(0.2)
	var normal_root: String = board.slot_root
	var blocker := FileAccess.open(path + "/blocked",FileAccess.WRITE)
	blocker.store_string("owned test blocker"); blocker.close()
	board.slot_root = path + "/blocked/slots"
	var before_failed_save: float = board.session.cycle.remaining
	board._return_title()
	check(board.running and board.session.cycle.remaining == before_failed_save, "failed active-cycle return-title save keeps live timeline")
	board.slot_root = normal_root
	board._save_game()
	check(board.notice.text == "Saved locally.", "active focus has staged save support")
	board._return_title(); board._continue_game(); board.set_process(false)
	check(is_equal_approx(board.session.cycle.remaining,0.3) and is_equal_approx(board.camera_motion.focus.duration,0.3), "Continue resumes only remaining camera focus without replaying full wait")
	board._process(0.3)
	check(board.session.cycle.stage == "food_lift", "focus completion begins food lift")
	var nutrition: int = board.session.cards[food].nutrition
	board._process(0.05)
	var sampled: Vector3 = board._sample_cycle_pose(food)
	check(board.views[food].position.is_equal_approx(Vector3(sampled.x,sampled.y,-sampled.z)), "food rendered pose and source sampler agree with snapshot")
	check(board.session.cards[food].nutrition == nutrition, "lift does not apply consumption early")
	board._save_game(); board._return_title(); board._continue_game(); board.set_process(false)
	check(board.session.cycle.stage == "food_lift" and is_equal_approx(board.session.cycle.remaining,0.05), "mid-food save restores stage and remaining")
	board._process(0.05); board._process(0.2)
	check(board.session.cycle.stage == "food_chew" and board.session.cards[food].nutrition == nutrition, "travel and Eat precede delayed nutrition effect")
	check("CardSwipe" in board.feedback.sounds and "Eat" in board.feedback.sounds, "cycle emits source motion sounds")
	board._process(0.25)
	check(board.session.cards[food].nutrition < nutrition, "model applies food only after chew wait")
	var saw_encounter := false
	for i in 100:
		if board.session.phase in ["ready","game_over","selling"]: break
		if board.session.phase == "encounter":
			saw_encounter = true
			board._refresh()
			check(board.day_button.disabled, "encounter cannot expose Start early")
		board._process(0.5)
	board._refresh()
	check(saw_encounter, "actual day-five encounter was observed before ready")
	check(board.session.phase == "ready" and not board.day_button.disabled, "ready action appears only after complete cycle")
	board._advance_day()
	check(board.session.phase == "playing" and board.session.day == 6 and FileAccess.file_exists(board._active_slot_path()), "Start Day advances and immediately checkpoints")
	# Real pointer grant survives a boundary, but cannot authorize another card.
	var wood: int = board.session.spawn_card(board.catalog.find_by_name("Wood"),Vector2(0,0),-1,{"refuse_attach":true})
	board._refresh(); press(board,wood)
	check(board.drag_grant == wood, "valid pointer-down issues exact-card grant")
	board.session.cycle.request_end_day()
	var buyer: Dictionary = board.trade_zones[0]
	var destination := Vector2(buyer.center.x,buyer.center.z)
	board.drag_moved = true; board.drag_delta = destination-board.session.card_target_position(wood)
	board._finish_drag(Vector2.ZERO)
	check(not board.session.cards.has(wood) and board.drag_grant == -1, "already-carried card can complete buyer trade after day boundary once")
	press(board,food)
	check(board.dragging == -1 and board.drag_grant == -1, "new feeding-phase press cannot obtain a drag grant")
	var position: Vector2 = board.session.cards[food].position
	board.dragging = food; board.drag_moved = true; board.drag_delta = Vector2(2,0)
	board._finish_drag(Vector2.ZERO)
	check(board.session.cards[food].position == position, "ungranted synthetic locked-phase drop is rejected")
	board.session.phase = "playing"; board.session.cycle.reset()
	var pack: int = board.session.spawn_card(str(board.catalog.data.packs[0].guid),Vector2(3,0),-1,{"refuse_attach":true})
	board._refresh(); press(board,pack)
	var uses: int = board.session.cards[pack].uses_left
	board.session.cycle.request_end_day()
	board._finish_drag(Vector2.ZERO)
	check(board.session.cards[pack].uses_left == uses-1, "already-valid pack press draws after day boundary")
	var remaining_uses: int = board.session.cards[pack].uses_left
	press(board,pack); board._finish_drag(Vector2.ZERO)
	check(board.session.cards[pack].uses_left == remaining_uses, "new locked-phase pack press cannot reuse consumed grant")
	board.queue_free(); await process_frame; await create_timer(0.5).timeout
	print("Cycle board checks: %d passed / %d total" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
