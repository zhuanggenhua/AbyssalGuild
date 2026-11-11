extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	var sounds: Array = []
	func play_event(kind: String) -> bool: sounds.append(kind); return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func clear_cards(board) -> void:
	board.session.drag.reset(); board.dragging = -1; board.drag_grant = -1; board.drag_delta = Vector2.ZERO
	board.session.combat.dragged.clear()
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.phase = "playing"; board.session.paused = false; board.session.cycle.reset()
	board.session.elapsed = 0; board.session.speed = 1
	board.session.spawn_target_selector = Callable(); board.session.spawn_layout_resolver = Callable()
	board.pause_overlay.hide(); board.options_panel.hide()
	board._refresh()
func spawn(board, name: String, position: Vector2, target: int = -1) -> int:
	return board.session.spawn_card(board.catalog.find_by_name(name), position, target, {"refuse_attach": true})
func fruit(board, progress: float = 3) -> Array:
	clear_cards(board)
	var apple: int = spawn(board, "Apple", Vector2(-3, -1))
	var berry: int = spawn(board, "Berry", Vector2(-1, -1))
	board.session.move_to_stack(berry, board.session.cards[apple].stack_id)
	var stack = board.session.stacks[board.session.cards[apple].stack_id]
	stack.progress = progress
	board._refresh()
	return [apple, berry, stack]
func press(board, id: int) -> void:
	var point: Vector3 = board.views[id].global_position
	board._begin_card_press({"card_id": id, "panel_owner": -1}, board.camera.unproject_position(point))
func drop(board, id: int, destination: Vector2) -> void:
	board.drag_moved = true
	board.drag_delta = destination - board.session.card_target_position(id)
	board._finish_drag(board.camera.unproject_position(Vector3(destination.x, 0, -destination.y)))
func run() -> void:
	var board = Board.new()
	board.feedback.free(); board.feedback = SilentFeedback.new()
	var path := "user://held-board-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"; board.options_path = path + "/options.json"; board.legacy_paths.clear()
	root.add_child(board); await process_frame
	check(board.data_error == OK, "real source data available")
	if board.data_error != OK: board.queue_free(); quit(1); return
	board.start_new(); board.set_process(false)
	var ids := fruit(board, 9.9)
	var origin: Vector2 = ids[2].position
	press(board, ids[1])
	var held_stack: int = board.session.drag.stack_id
	check(ids[2].card_ids == [ids[0]] and ids[2].paused and board.session.cards[ids[1]].stack_id != ids[2].id, "actual pointer press splits and pauses before any motion")
	board._process(0.2)
	check(board.session.cards.has(ids[1]) and ids[2].progress == 9.9 and board.dragging == ids[1], "board tick cannot consume held Berry at 9.9 seconds")
	check(ids[2].position == origin, "pickup does not resolve overlaps and push original away")
	var next_id: int = board.session._next_id
	press(board, ids[1]); press(board, ids[0])
	check(board.dragging == ids[1] and board.drag_grant == ids[1] and board.session._next_id == next_id, "repeated and replacement presses preserve exact original grant")
	board._finish_drag(Vector2.ZERO)
	check(board.session.cards[ids[1]].stack_id == ids[2].id and ids[2].card_ids == [ids[0], ids[1]], "unmoved ordinary click returns tail through normal attachment")
	check(not ids[2].paused and ids[2].progress == 9.9 and not board.session.stacks.has(held_stack), "click-return keeps progress and removes absorbed held stack")
	check(not board.session.drag.active() and board.dragging == -1 and board.drag_grant == -1, "release clears model and pointer state")
	board._finish_drag(Vector2.ZERO)
	check(ids[2].progress == 9.9, "duplicate pointer-up has no effect")
	# Drag away, then return to the original before release.
	ids = fruit(board)
	press(board, ids[1]); board.drag_moved = true
	board._set_board_card_position(ids[1], Vector2(3, -1))
	drop(board, ids[1], ids[2].position)
	check(ids[2].progress == 3 and not ids[2].paused and board.session.cards[ids[1]].stack_id == ids[2].id, "away-and-back drop resumes rather than restarting")
	# Genuine mouse motion updates registered position, including while menu-paused.
	ids = fruit(board); press(board, ids[1]); board._toggle_pause_menu()
	check(board.dragging == ids[1] and board.drag_grant == ids[1] and ids[2].paused, "menu toggle preserves an already held split and grant")
	var motion := InputEventMouseMotion.new()
	motion.position = board.camera.unproject_position(Vector3(2, 0, 1)); board._input(motion)
	var held_position: Vector2 = board.session.card_target_position(ids[1])
	check(held_position.x > 1.9 and board.drag_delta == Vector2.ZERO, "captured motion crosses GUI/menu and updates actual held stack pose")
	board._save_game()
	check(board.notice.text == "Saved locally." and ids[2].paused and board.session.drag.active(), "save during menu-held drag preserves live interaction")
	var restored = Session.new(); restored.configure(board.catalog, 17)
	check(Codec.restore(restored, Codec.capture(board.session)).ok, "moved-held model capture restores")
	check(restored.card_target_position(ids[1]) == held_position and not restored.drag.active(), "saved held location is real current pose, not pre-press drawing position")
	var release := InputEventMouseButton.new(); release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false; release.position = motion.position
	board._input(release)
	check(board.dragging == -1 and not board.session.drag.active() and ids[2].recipe_guid.is_empty(), "actual global GUI pointer-up settles invalid original exactly once")
	check(board.session.cards[ids[1]].stack_id != ids[2].id, "menu release does not invent rollback/reattachment")
	board._toggle_pause_menu()
	# Whole-stack first-card drag remains active and does not allocate replacement.
	ids = fruit(board); var original_id: int = ids[2].id; next_id = board.session._next_id
	press(board, ids[0]); board._process(0.25)
	check(not ids[2].paused and ids[2].progress == 3.25 and board.session._next_id == next_id, "first-card press keeps running craft and stable stack ID")
	drop(board, ids[0], Vector2(2, -1))
	check(board.session.cards[ids[0]].stack_id == original_id and ids[2].progress == 3.25, "whole-stack empty-board drop moves without restarting")
	ids = fruit(board, 9.9); press(board, ids[0]); board._process(0.2)
	check(not board.session.cards.has(ids[0]) and board.dragging == -1 and not board.session.drag.active(), "whole-stack craft may complete while held and removes stale pointer safely")
	# A matrix-invalid original cannot be forcibly rejoined by original context.
	ids = fruit(board); press(board, ids[1])
	var matrix: Dictionary = board.catalog.settings("StackingRulesMatrix"); var rules: Variant = matrix.rules
	matrix.rules = []
	board._finish_drag(Vector2.ZERO); matrix.rules = rules
	check(ids[2].recipe_guid.is_empty() and board.session.cards[ids[1]].stack_id != ids[2].id, "invalid original drop cancels only broken craft and preserves detached membership")
	# A source terminal sale must stop original even when valid excess remains.
	clear_cards(board)
	var station: int = spawn(board, "Sawmill", Vector2(-3, -1))
	check(station >= 0, "real Sawmill present")
	var stack = board.session.stacks[board.session.cards[station].stack_id]
	for i in 4: spawn(board, "Wood", Vector2.ZERO, stack.id)
	board.session._check_recipe(stack); stack.progress = 2; board._refresh()
	var excess: int = stack.card_ids.back(); press(board, excess)
	var buyer: Dictionary = board.trade_zones[0]
	drop(board, excess, Vector2(buyer.center.x, buyer.center.z))
	check(not board.session.cards.has(excess) and stack.recipe_guid.is_empty() and not stack.paused, "terminal buyer drop clears paused original despite valid remaining ingredients")
	# Successful chest click's source early return gets explicit native cleanup.
	for valid in [true, false]:
		clear_cards(board)
		station = spawn(board, "Sawmill", Vector2(-3, -1))
		stack = board.session.stacks[board.session.cards[station].stack_id]
		for i in 4: spawn(board, "Wood", Vector2.ZERO, stack.id)
		var chest: int = spawn(board, "Card_Chest_WoodenChest", Vector2.ZERO, stack.id)
		board.session.cards[chest].stored_coins = 2
		board.session._check_recipe(stack); stack.progress = 2; board._refresh(); press(board, chest)
		if not valid:
			for member in stack.card_ids.duplicate():
				if member != station: board.session._remove_card(member)
		var rng_before: int = board.session.rng.state
		board._finish_drag(Vector2.ZERO)
		check(board.session.cards[chest].stored_coins == 1 and not board.session.drag.active(), "successful lifted-chest click withdraws once and clears held context")
		check(not stack.paused and (not stack.recipe_guid.is_empty() if valid else stack.recipe_guid.is_empty()), "successful chest click validates original instead of leaving orphan pause")
		board._finish_drag(Vector2.ZERO)
		check(board.session.cards[chest].stored_coins == 1 and board.session.rng.state == rng_before, "duplicate chest release has no extra withdrawal or RNG draw")
	# Already-carried tail retains source release permission across end-day.
	ids = fruit(board); press(board, ids[1]); board.session.cycle.request_end_day()
	drop(board, ids[1], Vector2(3, -1))
	check(not board.session.drag.active() and ids[2].recipe_guid.is_empty() and board.session.phase == "feeding", "held-tail release survives day lock without advancing cycle")
	press(board, ids[1]); check(board.dragging == -1 and board.drag_grant == -1, "new locked-phase press cannot reuse old hold")
	# Disappearing held cards are cleaned during sync, without waiting for mouse-up.
	ids = fruit(board); press(board, ids[1]); board.session.kill_card(ids[1]); board._sync_views()
	check(board.dragging == -1 and board.drag_grant == -1 and not board.session.drag.active() and not ids[2].paused, "destroyed held card cannot strand a pointer or paused original")
	board.queue_free(); await process_frame; await create_timer(0.3).timeout
	print("Held stack board checks: %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
