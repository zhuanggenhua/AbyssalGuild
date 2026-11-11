extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
var checks := 0
var failures := 0
var quits := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var board = Board.new()
	var path := "user://scene-fade-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(path)
	board.slot_root = path + "/slots"
	board.options_path = path + "/options.json"
	board.options_apply_adapter = func(_plan): return {"ok": true, "capabilities": {}, "warnings": []}
	board.quit_callback = func(): quits += 1
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	var error: int = board.data_error
	board.data_error = ERR_FILE_NOT_FOUND
	board._request_new_game()
	check(not board.scene_transition.active(), "missing data never starts fade")
	board.data_error = error
	if error != OK:
		check(false, "licensed imported data required for integration suite")
	else:
		board._request_new_game()
		board._request_new_game()
		board._open_options()
		board._handle_escape()
		board._request_title_quit()
		board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		check(not board.running and not board.options_panel.visible and quits == 0 and not board.quit_dialog.visible, "fade-out blocks menu/quit/repeated new input before commit")
		board._process(0.5)
		check(not board.running and is_equal_approx(board.scene_transition.alpha, 0.5), "old title remains through half fade")
		board._process(0.5)
		check(board.running and board.active_slot > 0 and not board.scene_transition.blocks_input(), "new game commits only at black")
		var slot: int = board.active_slot
		var elapsed: float = board.session.elapsed
		board._process(0.25)
		check(board.session.elapsed > elapsed, "fade-in releases scaled clock")
		board._process(0.75)
		board.session.paused = true
		board.session.speed = 2
		board.pause_overlay.show()
		board._request_return_title()
		var saved_text: String = FileAccess.get_file_as_string(board.slots.slot_path(slot))
		board.session.day += 1
		elapsed = board.session.elapsed
		board._process(0.5)
		check(board.running and board.session.elapsed == elapsed and board.session.paused and board.session.speed == 2, "fade-out retains menu/user pace and stops day clock")
		board._process(0.5)
		board._process(1)
		check(not board.running and board.active_slot == slot, "return saves then title at black")
		check(FileAccess.get_file_as_string(board.slots.slot_path(slot)) == saved_text, "title save occurs before fade and later activity never overwrites checkpoint")
		board.selected_slot = slot
		board._request_continue_game()
		board.selected_slot = 99999 # Pending request keeps its original target.
		board._process(1)
		board._process(1)
		check(board.running and board.active_slot == slot, "load route commits saved slot")
		var old_session = board.session
		var old_root: String = board.slot_root
		board.slot_root = "/proc/invalid-scene-fade"
		board._request_return_title()
		board._process(1)
		board._process(1)
		check(board.running and board.session == old_session and "Could not save" in board.notice.text, "save failure fades back to unchanged live session")
		board.slot_root = old_root
		board._request_travel(-99, "missing")
		board._process(1)
		board._process(1)
		check(board.session == old_session and board.session.scene_name == "Main" and not board.session.travel_pending and "Travel failed" in board.notice.text, "invalid travel is atomic and releases ownership")
		board.pause_overlay.hide()
		var portal: int = board.session.spawn_card(board.catalog.find_by_name("Grand Portal"), Vector2(4, 0))
		var person: int = board.session.spawn_card(board.catalog.find_by_name("Villager"), Vector2(6, 0))
		check(board.session.move_to_stack(person, board.session.cards[portal].stack_id), "travel ingredients assembled")
		var stack = board.session.stacks[board.session.cards[portal].stack_id]
		var recipe: String = stack.recipe_guid
		board.slot_root = "/proc/invalid-departure"
		check(not board._request_travel(stack.id, recipe) and not board.scene_transition.active() and board.session == old_session, "failed departure checkpoint rejects before fading or live swap")
		board.slot_root = old_root
		board.session.crafting.activate(stack)
		var health: int = board.session.cards[person].health
		check(board._request_travel(stack.id, recipe), "valid travel stages request-time candidate")
		board.session.travel_pending = true
		board.session.cards[person].health = health + 7
		board._process(0.5)
		check(board.session == old_session and board.session.scene_name == "Main", "travel does not swap scene during fade-out")
		board._process(0.5)
		var carried := false
		for card in board.session.cards.values():
			if card.definition_guid == board.catalog.find_by_name("Villager") and card.health == health: carried = true
		check(board.session != old_session and board.session.scene_name == "Island" and carried and not old_session.travel_pending, "black swaps captured travelers, not later old-scene changes")
		board._process(1)
		old_session = board.session
		board._return_title()
		board.selected_slot = 99999
		board._request_continue_game()
		board._process(1)
		board._process(1)
		check(not board.running and board.session == old_session and "Cannot continue" in board.title_status.text, "missing save load fades back without swapping session")
		board._request_new_game()
		board._execute_quit()
		board._process(2)
		check(quits == 1 and not board.running and not board.scene_transition.active(), "explicit teardown invalidates pending scene commit")
		board.quit_dispatched = false
		for steps in [[0.5, 0.5], [1.0], [4.0]]:
			board.start_new()
			var owner = board.session
			var hero: int = owner.spawn_card(board.catalog.find_by_name("Villager"), Vector2(-5, 0))
			var enemy_guid := ""
			for definition in board.catalog.data.cards:
				if int(definition.get("fields", {}).get("faction", 0)) == 2:
					enemy_guid = str(definition.guid)
					break
			var enemy: int = owner.spawn_card(enemy_guid, Vector2(5, 0))
			var combat_id: int = owner.combat.start_combat([hero], [enemy])
			owner.combat.tasks[combat_id].progress[hero] = 1000.0
			owner.combat.resolve_turn(combat_id)
			var task: Dictionary = owner.combat.tasks[combat_id]
			# Extend a real execution wait solely to measure the complete clock
			# interval without crossing another coroutine yield boundary.
			task.execution.remaining = 2.0
			owner.cycle._wait("encounter_notification")
			var progress: float = task.progress[hero]
			var day_elapsed: float = owner.elapsed
			var observed: Array = []
			board._request_scene_change(func():
				observed.append([task.execution.remaining, owner.cycle.remaining, owner.elapsed, task.progress[hero]])
				board._show_title())
			for step in steps: board._process(step)
			check(observed.size() == 1 and is_equal_approx(observed[0][0], 1.0) and is_equal_approx(observed[0][1], 1.0), "old real combat/cycle consume full clamped fade-out before commit: " + str(steps))
			check(observed[0][2] == day_elapsed and observed[0][3] == progress and not board.running, "scaled clocks fixed and destination receives no old frame: " + str(steps))
			board._process(1)
	board.queue_free()
	await process_frame
	print("Scene transition board: %d / %d" % [checks-failures, checks])
	quit(1 if failures else 0)
