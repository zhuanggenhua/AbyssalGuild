extends SceneTree
const Codec = preload("res://scripts/model/save_codec.gd")
class BoardAdapter extends "res://scripts/ui/board.gd":
	var hit := {"card_id": -1, "panel_owner": -1}
	func _pick_target(_point: Vector2) -> Dictionary: return hit
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_event: String) -> bool: return false
	func play_music() -> bool: return false
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func same(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a, "", true, true) == JSON.stringify(b, "", true, true)
func card_named(board, name: String) -> int:
	var guid: String = board.catalog.find_by_name(name)
	for id in board.session.cards:
		if board.session.cards[id].definition_guid == guid: return id
	return -1
func finish_reveals(board) -> void:
	for step in 50:
		if not board.vendor_unlock.is_active(): return
		board._process(board.vendor_unlock.sequence.remaining + 0.00001)
	check(false, "Reveal queue drains within bounded frames")
func complete_until(board, count: int) -> void:
	for step in 100:
		if board.session.completed_quests >= count: return
		var active: Array = board.session.quest_tracker.active_quests
		if active.is_empty(): break
		var instance: Dictionary = active[0]
		instance.current_amount = int(board.session.quest_tracker.definitions[instance.id].targetAmount)
		board.session.quest_tracker._check(instance, board.session)
	check(board.session.completed_quests >= count, "Actual tracker has enough reachable quest completions")

func run() -> void:
	var board := BoardAdapter.new()
	board.feedback.free()
	board.feedback = SilentFeedback.new()
	var path := "user://vendor-unlock-board-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"
	board.options_path = path + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	check(board.data_error == OK, "Real source catalog loads")
	if board.data_error != OK: quit(1); return
	board.start_new()
	board.set_process(false)
	check(not board.vendor_unlock.is_active() and not board.vendor_unlock.info_panel.visible, "New scene starts without fabricated unlock")
	# Actual first three source quests, rather than a synthetic completion event.
	var starter: int = board.session.cards.keys()[0]
	board.session.rng.seed = 81482
	for step in 4: board.session.open_pack(starter)
	var starter_index: int = 0
	for id in board.session.cards.keys():
		board.session.split_stack(id, Vector2(-4 + starter_index * 1.5, -2))
		starter_index += 1
	var villager: int = card_named(board, "Villager")
	var bush: int = card_named(board, "Berry Bush")
	var rock: int = card_named(board, "Rock")
	check(board.session.move_to_stack(villager, board.session.cards[bush].stack_id), "Source berry recipe discovery completes second quest")
	board.session.tick(10)
	# Spread the harvest output and starter cards so a nearby auto-attached
	# result cannot become an unintended extra mining ingredient.
	var spread_index: int = 0
	for id in board.session.cards.keys():
		board.session.split_stack(id, Vector2(-4 + spread_index * 1.5, -2))
		spread_index += 1
	check(board.session.move_to_stack(villager, board.session.cards[rock].stack_id), "Source mining recipe starts")
	var mining = board.session.stacks[board.session.cards[rock].stack_id]
	board.session.tick(float(board.catalog.fields(mining.recipe_guid).get("craftingDuration", 5)))
	check(board.session.completed_quests == 3 and board.vendor_unlock.is_active(), "Actual source craft quest triggers vendor reveal immediately")
	check(board.trade_zones[1].active and board.trade_views[1].highlighted and board.vendor_unlock.sequence.current.index == 1, "Beginning activates before its reveal and owns highlight")
	check(board.vendor_unlock.info_label.text.contains("Pack Unlocked") and board.vendor_unlock.info_label.text.contains(board.trade_zones[1].title), "Reveal names the actual newly available source pack")
	board.session.speed = 2
	board.session.elapsed = 19
	var saved: Dictionary = Codec.capture(board.session)
	if board.camera_motion.focus.is_empty():
		board.queue_free()
		await process_frame
		quit(1)
		return
	var focus_end: Vector3 = board.camera_motion.focus.end
	var target: Vector3 = board.camera_motion.target
	board._zoom_camera(1)
	check(not board._camera_input_enabled() and board.camera_motion.target == target and not board._allows_card_actions(), "Reveal blocks camera navigation and new convenience transactions")
	board.hit.card_id = villager
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	board._unhandled_input(press)
	check(board.dragging == -1 and board.drag_grant == -1, "Reveal blocks a new card pointer-down")
	board.hit = {"card_id": villager, "panel_owner": villager}
	board._begin_card_press(board.hit, Vector2.ZERO)
	check(board._allows_equipment_panel_input() and board.pressed_panel == villager, "Equipment-panel pointer route remains independent of reveal input lock")
	board._finish_drag(Vector2.ZERO)
	check(board.pressed_panel == -1 and board.dragging == -1, "Equipment-panel release remains routed without starting a card drag")
	board.hit = {"card_id": villager, "panel_owner": -1}
	board._process(0.5)
	check(board.camera.position.is_equal_approx(focus_end) and board.vendor_unlock.sequence.stage == "hold", "Unscaled source camera move completes while gameplay is externally paused")
	check(same(Codec.capture(board.session), saved), "Half-second focus does not advance model time, crafting, RNG or selected pace")
	# Pace UI remains available, but chosen pace cannot defeat the external pause.
	board._set_speed(1.0)
	check(board.session.speed == 1.0 and board.vendor_unlock.is_active(), "Selected pace UI remains usable during reveal")
	board._handle_escape()
	check(board.pause_overlay.visible and board._ui_pause_active(), "Escape menu remains independently available")
	board._process(2.0)
	check(not board.vendor_unlock.is_active() and board._ui_pause_active() and board.session.elapsed == 19, "Reveal finishes in realtime without releasing the menu's pause")
	board._process(0.3)
	check(board.session.elapsed == 19, "Remaining menu pause still freezes scaled gameplay")
	board._handle_escape()
	board._process(0.1)
	check(is_equal_approx(board.session.elapsed, 19.1) and board.session.speed == 1, "Closing final external pause resumes selected pace")
	# Queue multiple eligibility changes in offered order, and preserve a held drag.
	board._begin_card_press({"card_id": villager, "panel_owner": -1}, board.camera.unproject_position(board.views[villager].position))
	var granted: int = board.drag_grant
	complete_until(board, int(board.trade_zones[3].min_quests))
	check(board.vendor_unlock.is_active() and granted == villager and board.drag_grant == villager, "Later quests start reveal without revoking an existing drag grant")
	var queued: Array = board.vendor_unlock.sequence.pending.duplicate()
	var active_index: int = int(board.vendor_unlock.sequence.current.index)
	check(not queued.is_empty() and int(queued[0]) > active_index, "Multiple source thresholds queue later offered vendors")
	board.session.quest_tracker.quest_completed.emit({})
	check(board.vendor_unlock.sequence.pending == queued and board.vendor_unlock.sequence.current.index == active_index, "Repeated quest notification does not duplicate queue")
	board.drag_moved = true
	board.drag_delta = Vector2(-1, -1)
	board._finish_drag(board.camera.unproject_position(Vector3(-2, 0, 1)))
	check(board.drag_grant == -1 and board.dragging == -1 and not board.session.drag.active(), "Granted pointer-up finishes even while a new reveal lock is active")
	# Save/title/Continue must retain model state but discard ephemeral presentation.
	board.session.vendor_payments[str(board.trade_zones[1].pack_guid)] = 1
	board.session.set_paused(true)
	DirAccess.make_dir_absolute(board._active_slot_path() + ".tmp")
	board._return_title()
	check(board.running and board.vendor_unlock.is_active() and board.notice.text.begins_with("Could not save"), "Failed title checkpoint preserves live reveal and its visible save error")
	DirAccess.remove_absolute(board._active_slot_path() + ".tmp")
	board._save_game()
	check(board.notice.text == "Saved locally." and board.vendor_unlock.is_active(), "Native save can persist safely during reveal")
	var slot: int = board.active_slot
	board._return_title()
	check(not board.running and not board.vendor_unlock.is_active() and not board.vendor_unlock.info_panel.visible, "Title clears active and queued presentation")
	board.selected_slot = slot
	board._continue_game()
	board.set_process(false)
	check(board.running and not board.vendor_unlock.is_active() and board.session.paused, "Continue restores selected pause with no unlock replay")
	check(int(board.session.vendor_payments.get(str(board.trade_zones[1].pack_guid), 0)) == 1 and board.trade_zones[1].active, "Continue restores payment and unlocked eligibility silently")
	for view in board.trade_views.values(): check(not view.highlighted, "Restored vendor has no stale reveal highlight")
	# Real travel interrupts the old scene even if its sequence is active.
	complete_until(board, 30)
	check(board.vendor_unlock.is_active(), "Additional source thresholds provide a pending travel interruption")
	var recipe: Dictionary = {}
	for entry in board.catalog.data.recipes:
		if entry.get("script_class", "") == "TravelRecipe": recipe = entry; break
	var portal: int = board.session.spawn_card(board.catalog.find_by_name("Grand Portal"), Vector2(1, -2), -1, {"refuse_attach": true})
	var travel_stack: int = board.session.cards[portal].stack_id
	board.session.spawn_card(board.catalog.find_by_name("Villager"), Vector2(1, -2), travel_stack)
	var travelled: Dictionary = board.session.campaign.travel(travel_stack, str(recipe.guid))
	check(travelled.ok and board.session.scene_name == "Island" and not board.vendor_unlock.is_active(), "Travel commits destination then discards departure reveal and queue")
	check(board.trade_zones.size() == 2 and not board.vendor_unlock.info_panel.visible, "Island binds its own silent vendor baseline")
	_test_clock_interleaving(board)
	board._show_title()
	board.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("Vendor unlock board checks: %d passed / %d total" % [checks - failures, checks])
	quit(1 if failures else 0)

func _test_clock_interleaving(board) -> void:
	board.start_new()
	board.set_process(false)
	var player: int = board.session.spawn_card(board.catalog.find_by_name("Villager"), Vector2(-2, -1), -1, {"refuse_attach": true})
	var enemy_guid: String = ""
	for entry in board.catalog.data.cards:
		if int(entry.fields.get("category", 0)) == 9 and int(entry.fields.get("faction", 0)) == 2:
			enemy_guid = entry.guid
			break
	var enemy: int = board.session.spawn_card(enemy_guid, Vector2(2, -1), -1, {"refuse_attach": true})
	var combat_id: int = board.session.combat.start_combat([player], [enemy])
	var task: Dictionary = board.session.combat.tasks[combat_id]
	task.progress[player] = 1000.0
	task.progress[enemy] = 0.0
	board.session.combat.resolve_turn(combat_id)
	complete_until(board, 3)
	check(board.vendor_unlock.is_active(), "Combat clock fixture starts actual vendor reveal")
	var progress: Dictionary = task.progress.duplicate(true)
	var elapsed: float = board.session.elapsed
	board._process(float(task.execution.remaining))
	check(task.execution.phase == "return" and task.progress == progress and board.session.elapsed == elapsed, "Combat travel/impact uses realtime while action accumulation/day clock stay paused")
	board.session.cards[enemy].health = 0
	board._process(0.3)
	check(task.execution.phase == "death_wait" and not board.session.cards.has(enemy), "Combat return and kill still finish during unlock")
	board._process(0.2)
	check(task.execution.remaining == 0.5 and board.session.combat.tasks.has(combat_id), "Scaled lethal combat wait remains frozen by reveal")
	finish_reveals(board)
	board._process(0.5)
	check(not board.session.combat.tasks.has(combat_id), "Scaled combat wait resumes only after reveal releases its pause")
	board.start_new()
	board.set_process(false)
	board.session.spawn_card(board.catalog.find_by_name("Villager"), Vector2(-2, -1), -1, {"refuse_attach": true})
	board.session.spawn_card(board.catalog.find_by_name("Berry"), Vector2(2, -1), -1, {"refuse_attach": true})
	board.session.end_day()
	complete_until(board, 3)
	var remaining: float = board.session.cycle.remaining
	var stage: String = board.session.cycle.stage
	check(board.vendor_unlock.is_active() and board.session.phase == "feeding" and remaining > 0, "Cycle clock fixture overlaps feeding and vendor reveal")
	board._process(0.1)
	check(board.session.cycle.stage == stage and is_equal_approx(board.session.cycle.remaining, remaining - 0.1), "Cycle yielded wait continues in realtime under vendor external pause")
	check(not board.vendor_unlock.info_panel.visible and board.session.paused, "Cycle modal outranks unlock notice without losing automatic pace pause")
