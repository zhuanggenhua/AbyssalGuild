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
	board.slot_root = "user://ui-test-slots-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	board.legacy_paths.clear()
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
	# Source pack spawning may already attach compatible outputs. Isolate the
	# four real cards so this subsequent explicit drag scenario is deterministic.
	var starter_positions: Array[Vector2] = [Vector2(-4, 0), Vector2(0, 0), Vector2(4, 0), Vector2(-2, -2)]
	var starter_ids: Array = board.session.cards.keys()
	for index in range(starter_ids.size()):
		board.session.split_stack(starter_ids[index], starter_positions[index])
	board._refresh()
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
	board._finish_drag(board.camera.unproject_position(Vector3(target_point.x, 0, -target_point.y)))
	check(board.session.cards[villager].stack_id == board.session.cards[bush].stack_id, "drag drop merges real cards")
	board._refresh()
	var stack = board.session.stacks[board.session.cards[bush].stack_id]
	check(not stack.recipe_guid.is_empty(), "stack starts crafting")
	board.dragging = villager
	board.drag_moved = true
	board.drag_delta = Vector2(3, 2) - stack.position
	board._finish_drag(board.camera.unproject_position(Vector3(3, 0, -2)))
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
	check(not board.ledger.get_parsed_text().is_empty(), "discovery ledger renders")
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
	board._finish_drag(board.camera.unproject_position(Vector3(2, 0, -2)))
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
	var healthy_primary: String = FileAccess.get_file_as_string(board._active_slot_path())
	for path in [board._active_slot_path(), board._active_slot_path() + ".bak"]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("not json")
		file.close()
	board._continue_game()
	check(board.session == live and board.running, "failed Continue preserves live session")
	board._save_game()
	check(board.notice.text.begins_with("Save failed"), "corrupt-only slot is not silently overwritten")
	var repaired_fixture := FileAccess.open(board._active_slot_path(), FileAccess.WRITE)
	repaired_fixture.store_string(healthy_primary)
	repaired_fixture.close()
	board._save_game()
	DirAccess.make_dir_absolute(board._active_slot_path() + ".tmp")
	board._return_title()
	check(board.running and board.session == live and not board.title_panel.visible, "failed title-save retains live board")
	check(board.notice.text.begins_with("Could not save"), "failed save is explained")
	DirAccess.remove_absolute(board._active_slot_path() + ".tmp")
	_test_world_and_campaign(board)
	await _test_source_camera_interaction(board)
	print("UI checks: %d passed / %d total" % [checks - failures, checks])
	board.queue_free()
	await process_frame
	# Allow audio-server stop commands to drain before engine teardown.
	await create_timer(0.5).timeout
	quit(0 if failures == 0 else 1)

func _drop_on(board, moving: int, destination: Vector2) -> void:
	board.dragging = moving
	board.drag_moved = true
	board.drag_delta = destination - board.session.cards[moving].position
	board._finish_drag(board.camera.unproject_position(Vector3(destination.x, 0, -destination.y)))

func _scene_quest_ids(board, scene_name: String) -> Array:
	var ids: Array = []
	for scene in board.catalog.data.scenes:
		if scene.name != scene_name: continue
		for document in scene.documents:
			if document.get("script_class", "") != "QuestManager": continue
			for group in document.fields.get("questGroups", []):
				for reference in group.get("Quests", []):
					var id: String = str(board.catalog.fields(board.catalog.ref_guid(reference)).get("id", ""))
					if not ids.has(id): ids.append(id)
	ids.sort()
	return ids

func _check_scene_ui(board, scene_name: String, vendor_count: int) -> void:
	check(board.session.scene_name == scene_name and board.session.campaign.current_scene == scene_name, "campaign and session agree on " + scene_name)
	var vendors: Array = board.SceneConfig.offered_packs(board.catalog, scene_name)
	check(board.vendor_guids == vendors and vendors.size() == vendor_count, scene_name + " uses only its source vendors")
	check(board.vendor_buttons.keys() == vendors, scene_name + " vendor buttons rebuilt without stale vendors")
	check(board.trade_zones.size() == vendor_count + 1 and board.trade_views.size() == vendor_count + 1, scene_name + " source trade zones rebuild without stale scene nodes")
	var actual_quests: Array = board.session.quest_tracker.definitions.keys()
	actual_quests.sort()
	check(actual_quests == _scene_quest_ids(board, scene_name), scene_name + " exact source quest set configured")
	check(board.selected == -1, scene_name + " clears stale selection")
	check(board.session.world.scene_name == scene_name, scene_name + " world rules use destination")
	for id in board.views:
		check(board.session.cards.has(id), scene_name + " view references live card")

func _make_travel_stack(board) -> int:
	var portal: int = board.session.spawn_card(board.catalog.find_by_name("Grand Portal"), Vector2(-6, -5))
	var traveler: int = board.session.spawn_card(board.catalog.find_by_name("Villager"), Vector2(-8, -5))
	_drop_on(board, traveler, Vector2(-6, -5))
	check(board.session.cards[traveler].stack_id == board.session.cards[portal].stack_id, "UI drop assembles travel stack")
	return board.session.cards[portal].stack_id

func _test_world_and_campaign(board) -> void:
	board.friendly_choice.button_pressed = true
	board.start_new()
	board.set_process(false)
	check(board.session.friendly_mode, "title friendly checkbox configures new session")
	var chest_guid: String = ""
	for entry in board.catalog.data.cards:
		if entry.get("script_class", "") == "ChestDefinition":
			chest_guid = entry.guid
			break
	check(not chest_guid.is_empty(), "real source chest definition available")
	var chest: int = board.session.spawn_card(chest_guid, Vector2(6, 6))
	var coin: int = board.session.spawn_card(board.catalog.find_by_name("Coin"), Vector2(-5, 6))
	var currency: int = board.session.stats().currency
	_drop_on(board, coin, Vector2(6, 6))
	check(board.session.cards[chest].stored_coins == 1 and not board.session.cards.has(coin), "actual UI drop deposits and consumes coin")
	check(board.session.stats().currency == currency and board.notice.text == "Stored 1 coins.", "chest drop preserves currency and reports amount")
	board.selected = chest
	board._withdraw_selected()
	check(board.session.cards[chest].stored_coins == 0 and board.session.stats().currency == currency, "UI withdrawal returns stored currency")
	check(board.notice.text == "Withdrew a coin.", "withdrawal reports success")
	var card_count: int = board.session.cards.size()
	board._withdraw_selected()
	check(board.notice.text == "Chest is empty." and board.session.cards.size() == card_count, "empty chest withdrawal is harmless")
	board.selected = -1
	board._withdraw_selected()
	check(board.notice.text.begins_with("Select an unstacked chest"), "invalid chest selection is explained")
	board._save_game()
	board._return_title()
	board._continue_game()
	board.set_process(false)
	check(board.session.friendly_mode, "Continue restores friendly mode")
	# Resolve the real TravelRecipe rather than creating a fixture or bypassing tick.
	var recipe: Dictionary = {}
	for entry in board.catalog.data.recipes:
		if entry.get("script_class", "") == "TravelRecipe": recipe = entry
	check(not recipe.is_empty(), "real travel recipe available")
	var travel_stack: int = _make_travel_stack(board)
	check(board.session.stacks[travel_stack].recipe_guid == str(recipe.guid), "UI stack selects source TravelRecipe")
	# A bad target must report failure without changing scene or replacing the UI.
	var targets: Array = recipe.fields.targetScenes.duplicate()
	recipe.fields.targetScenes = ["Main", "Missing"]
	var live = board.session
	var old_vendor_guids: Array = board.vendor_guids.duplicate()
	board.session.tick(float(recipe.fields.craftingDuration))
	check(board.session == live and board.session.scene_name == "Main", "invalid travel retains live Main session")
	check(board.vendor_guids == old_vendor_guids and board.notice.text.begins_with("Travel failed:"), "invalid travel retains vendors and reports failure")
	check(board.session.stacks.has(travel_stack) and board.session.stacks[travel_stack].recipe_guid.is_empty(), "failed travel cancels recipe without destroying stack")
	recipe.fields.targetScenes = targets
	board.session._check_recipe(board.session.stacks[travel_stack])
	board.session.tick(float(recipe.fields.craftingDuration))
	board._refresh()
	_check_scene_ui(board, "Island", 1)
	check(board.notice.text.begins_with("Arrived at Island") and board.running, "runtime travel event updates running UI")
	check(board.session.elapsed == 0, "travel tick does not advance Island clock")
	check(board.session.campaign.saved_scenes.has("Main"), "Main snapshot retained in campaign")
	check(board.session.friendly_mode, "friendly mode survives travel to Island")
	board._save_game()
	check(board.notice.text == "Saved locally.", "Island campaign save succeeds")
	board._return_title()
	check(board.title_panel.visible and not board.running, "Island save/title stops simulation")
	board._continue_game()
	board.set_process(false)
	_check_scene_ui(board, "Island", 1)
	check(board.session.campaign.saved_scenes.has("Main"), "Island Continue retains inactive Main snapshot")
	check(board.session.friendly_mode, "Island Continue retains friendly mode")
	# Atomic save failures on Island must not reset scene, vendors, or the live model.
	live = board.session
	DirAccess.make_dir_absolute(board._active_slot_path() + ".tmp")
	board._return_title()
	check(board.running and board.session == live and board.session.scene_name == "Island", "failed Island save retains live destination")
	check(board.vendor_guids.size() == 1 and board.notice.text.begins_with("Could not save"), "failed Island save preserves market and explains error")
	DirAccess.remove_absolute(board._active_slot_path() + ".tmp")
	travel_stack = _make_travel_stack(board)
	board.session.tick(float(recipe.fields.craftingDuration))
	board._refresh()
	_check_scene_ui(board, "Main", 8)
	check(board.session.cards.has(chest) and board.session.cards[chest].base_definition_guid == chest_guid, "return Main restores original chest")
	check(board.session.campaign.saved_scenes.has("Island"), "return Main preserves inactive Island")
	check(board.session.friendly_mode, "friendly mode survives return Main")
	board.friendly_choice.button_pressed = false
	board.start_new()
	board.set_process(false)
	check(not board.session.friendly_mode, "unchecked title choice starts normal mode without stale friendly setting")

func _test_source_camera_interaction(board) -> void:
	var source_camera: Dictionary = board.visual_assets.camera_configuration("Main")
	check(not source_camera.is_empty(), "imported Main camera has resolved source configuration")
	check(board.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "source camera uses perspective projection")
	check(is_equal_approx(board.camera.fov, 30.0), "source camera vertical field of view is 30 degrees")
	check(is_equal_approx(board.camera.near, 2.0) and is_equal_approx(board.camera.far, 40.0), "source camera clipping planes are 2 and 40")
	if DirAccess.dir_exists_absolute("res://.godot/imported"):
		check(board.original_board != null, "source board geometry is instantiated with imported project cache")
	else:
		check(board.original_board == null and board.board_mesh.visible, "isolated no-import-cache run uses explicit fallback board")
		print("UI note: source FBX node assertion requires actual project import cache; fallback verified here.")
	if board.original_board != null:
		check(is_equal_approx(board.original_board.scale.z, -1.0), "original board reflects source positive Z to view negative Z")
	for model_point in [Vector2.ZERO, Vector2(2, 1), Vector2(-2, -1)]:
		var screen: Vector2 = board.camera.unproject_position(Vector3(model_point.x, 0, -model_point.y))
		check(board._board_point(screen).distance_to(model_point) < 0.001, "source model/view plane ray roundtrip " + str(model_point))
	var wood: int = board.session.spawn_card(board.catalog.find_by_name("Wood"), Vector2(3, 1))
	board._refresh()
	check(is_equal_approx(board.views[wood].position.z, -board.session.cards[wood].position.y), "card node reflects model Z")
	await physics_frame
	await physics_frame
	var screen: Vector2 = board.camera.unproject_position(board.views[wood].global_position)
	check(board._pick(screen) == wood, "source perspective ray picks rendered card")
	var before_transform: Transform3D = board.camera.global_transform
	var before_fov: float = board.camera.fov
	var before_size: float = board.camera.size
	var zoom := InputEventMouseButton.new()
	zoom.button_index = MOUSE_BUTTON_WHEEL_UP
	zoom.pressed = true
	zoom.position = screen
	board._unhandled_input(zoom)
	board._update_camera_motion(0.016) # Source zoom changes a smoothed target, not an immediate transform.
	check(not board.camera.global_transform.is_equal_approx(before_transform) or not is_equal_approx(board.camera.fov, before_fov) or not is_equal_approx(board.camera.size, before_size), "wheel zoom changes camera")
	var destination := Vector2(4, -1)
	var destination_screen: Vector2 = board.camera.unproject_position(Vector3(destination.x, 0, -destination.y))
	check(board._board_point(destination_screen).distance_to(destination) < 0.001, "model/view plane ray roundtrip survives zoom")
	_drop_on(board, wood, destination)
	check(board.session.cards[wood].position.distance_to(destination) < 0.001, "drag destination survives perspective zoom")
	check(is_equal_approx(board.views[wood].position.z, -destination.y), "dragged card retains reflected position after zoom")
	await physics_frame
	await physics_frame
	screen = board.camera.unproject_position(board.views[wood].global_position)
	check(board._pick(screen) == wood, "rendered card remains pickable after zoom and move")
