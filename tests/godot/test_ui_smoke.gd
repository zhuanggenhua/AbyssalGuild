extends SceneTree
## Headless scene/model integration smoke. This is NOT a visual/input acceptance test.
const Board = preload("res://scripts/ui/board.gd")
var failures: int = 0
var checks: int = 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", description)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var board = Board.new()
	root.add_child(board)
	await process_frame
	check(board.title_panel.visible and not board.running, "title appears before simulation")
	check(board.camera != null, "3D board camera exists")
	if board.data_error != OK:
		check(board.title_status.text.contains("Import your licensed"), "missing source has actionable instructions")
		board.start_new()
		check(not board.running, "missing source cannot launch a mock game")
		print("UI missing-data checks: %d/%d" % [checks - failures, checks])
		board.queue_free()
		await process_frame
		quit(0 if failures == 0 else 1)
		return
	check(board.vendor_guids.size() == 8, "Main scene offers exactly its eight configured packs")
	board.start_new()
	board.set_process(false)
	check(board.running and not board.title_panel.visible, "new game enters board")
	check(board.views.size() == 1 and board.session.cards.size() == 1, "starter geometry matches model")
	var pack: int = board.session.cards.keys()[0]
	for i in range(4):
		board.dragging = pack
		board.drag_moved = false
		board._finish_drag(Vector2.ZERO)
	check(board.session.cards.size() == 4 and board.views.size() == 4, "clicking starter creates all four real cards and views")
	var villager: int = -1
	var bush: int = -1
	var wood: int = -1
	for id in board.session.cards:
		match board._name(board.session.cards[id].definition_guid):
			"Villager": villager = id
			"Berry Bush": bush = id
			"Wood": wood = id
	check(villager >= 0 and bush >= 0 and wood >= 0, "starter content is source-backed")
	board.selected = villager
	board._refresh()
	check(board.inspection.text.contains("Villager"), "selection populates inspection")
	board.dragging = villager
	board.drag_moved = true
	board.drag_delta = board.session.cards[bush].position - board.session.cards[villager].position
	var target_point: Vector2 = board.session.cards[bush].position
	board._finish_drag(board.camera.unproject_position(Vector3(target_point.x, 0, target_point.y)))
	check(board.session.cards[villager].stack_id == board.session.cards[bush].stack_id, "drag drop merges real cards")
	board._refresh()
	var stack = board.session.stacks[board.session.cards[bush].stack_id]
	check(not stack.recipe_guid.is_empty(), "stack starts crafting")
	board.dragging = villager
	board.drag_moved = true
	board.drag_delta = Vector2(3, 2) - stack.position
	board._finish_drag(board.camera.unproject_position(Vector3(3, 0, 2)))
	board._refresh()
	check(is_equal_approx(board.views[villager].position.x, 3.0), "split is reflected on 3D board")
	board._toggle_pause()
	check(board.session.paused, "pause button pauses model")
	board._toggle_pause()
	board.selected = wood
	board._sell_selected()
	check(not board.session.cards.has(wood), "sell control removes card")
	board.active_tab = "recipes"
	board._refresh_ledger()
	check(not board.ledger.text.is_empty(), "discovery ledger renders")
	# Exercise day controls with actual source cards, not a substituted catalog.
	while board.session.stats().nutrition < board.session.stats().nutrition_need:
		board.session.spawn_card(board.catalog.find_by_name("Berry"), Vector2(4, 4))
	var excess_cards: Array[int] = []
	while board.session.stats().excess < 3:
		excess_cards.append(board.session.spawn_card(board.catalog.find_by_name("Wood"), Vector2(5, 5)))
	board._advance_day()
	check(board.session.phase == "selling" and board.day_button.disabled, "day feeding requires selling excess before continuing")
	for id in excess_cards:
		if board.session.phase != "selling": break
		board.selected = id
		board._sell_selected()
	check(board.session.phase == "ready", "selling excess enables next day")
	board._advance_day()
	check(board.session.day == 2 and board.session.phase == "playing", "day button starts next day")
	board.session.set_speed(2.0)
	board._refresh()
	check(board.status.text.contains("2x"), "HUD shows selected pace")
	board._save_game()
	check(board.notice.text == "Saved locally.", "UI save succeeds")
	var before: int = board.session.cards.size()
	board._return_title()
	check(not board.running and board.title_panel.visible, "save and title stops simulation")
	board._continue_game()
	board.set_process(false)
	check(board.running and board.session.cards.size() == before, "Continue restores saved model")
	check(board.views.size() == before, "Continue rebuilds visible card nodes")
	for view in board.views.values(): check(view.visible, "restored card visible")
	# Repeat New after Continue: old node IDs must not retain old card labels.
	board.start_new()
	board.set_process(false)
	check(board.views.size() == 1, "repeat new game removes prior views")
	check(board.views.values()[0].caption.text.contains("Starter"), "new starter is not stale reused geometry")
	# Equipment and combat detach cards from stacks: renderers must retain fighters
	# and hide gear without retaining an invisible clickable physics body.
	var wearer: int = board.session.spawn_card(board.catalog.find_by_name("Villager"), Vector2(2, 2))
	var equipment_guid: String = ""
	var enemy_guid: String = ""
	for entry in board.catalog.data.cards:
		if int(entry.fields.get("category", 0)) == 5 and equipment_guid.is_empty(): equipment_guid = entry.guid
		if int(entry.fields.get("category", 0)) == 9 and int(entry.fields.get("faction", 0)) == 2 and enemy_guid.is_empty(): enemy_guid = entry.guid
	var gear: int = board.session.spawn_card(equipment_guid, Vector2(-3, -3))
	board.dragging = gear
	board.drag_moved = true
	board.drag_delta = Vector2(5, 5)
	board._finish_drag(board.camera.unproject_position(Vector3(2, 0, 2)))
	check(board.session.equipment.owners.get(gear, -1) == wearer, "drop equipment onto character equips it")
	check(not board.views[gear].visible, "equipped item hidden from board")
	board.selected = wearer
	board._refresh()
	check(board.inspection.text.contains("Equipped:"), "inspection lists equipped gear")
	var enemy: int = board.session.spawn_card(enemy_guid, Vector2(4, 2))
	board.selected = enemy
	board._engage_selected()
	check(board.session.combat.membership.has(enemy), "explicit enemy engagement starts combat")
	check(board.views[enemy].visible and board.views[wearer].visible, "detached combatants retain views")
	board._save_game()
	board._return_title()
	board._continue_game()
	board.set_process(false)
	check(board.session.equipment.owners.get(gear, -1) == wearer, "Continue restores equipment")
	check(board.session.combat.membership.has(enemy), "Continue restores combat")
	check(board.views[enemy].visible and not board.views[gear].visible, "Continue renders fighters but not attached equipment")
	# Corrupt both candidates: failed Continue must preserve the live session.
	var live = board.session
	for path in ["user://session.json", "user://session.json.bak"]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("not json")
		file.close()
	board._continue_game()
	check(board.session == live and board.running, "failed Continue preserves live session")
	board._save_game()
	DirAccess.make_dir_absolute("user://session.json.tmp")
	board._return_title()
	check(board.running and board.session == live and not board.title_panel.visible, "failed title-save retains live board")
	check(board.notice.text.begins_with("Could not save"), "failed save is explained")
	DirAccess.remove_absolute("user://session.json.tmp")
	print("UI checks: %d passed / %d total" % [checks - failures, checks])
	board.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
