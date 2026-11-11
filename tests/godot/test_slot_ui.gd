extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
var checks: int = 0
var failures: int = 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func disk(board) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(board._active_slot_path()))
func run() -> void:
	var board = Board.new()
	var root_path: String = "user://slot-ui-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	board.slot_root = root_path + "/slots"
	board.legacy_paths.clear()
	board.legacy_paths.append(root_path + "/session.json")
	root.add_child(board)
	await process_frame
	check(board.data_error == OK, "real source loaded")
	if board.data_error != OK: quit(1); return
	check(board.continue_button.disabled and not board.legacy_button.visible, "empty title has no Continue or legacy adoption")
	board.start_new()
	board.set_process(false)
	var first_path: String = board._active_slot_path()
	check(board.active_slot == 1 and FileAccess.file_exists(first_path), "New commits lowest free slot")
	check(disk(board).slot_number == 1, "filename and campaign slot identity agree")
	var first_bytes: String = FileAccess.get_file_as_string(first_path)
	board.start_new()
	board.set_process(false)
	check(board.active_slot == 2 and FileAccess.get_file_as_string(first_path) == first_bytes, "second New preserves first slot")
	board.session.collection.mark_card(board.catalog.find_by_name("Wood"))
	board.session.day = 7
	board._return_title()
	check(not board.running and board.slot_picker.item_count == 2, "Return saves and lists both slots")
	board.selected_slot = 1
	board._continue_game()
	board.set_process(false)
	check(board.active_slot == 1 and board.session.day == 1, "picker loads chosen slot")
	check(not board.session.collection.is_card_discovered(board.catalog.find_by_name("Wood")), "loading first slot replaces rather than unions second-slot collection")
	board.selected_slot = 2
	board._continue_game()
	board.set_process(false)
	check(board.session.day == 7 and board.active_slot == 2, "second slot has independent day")
	check(board.session.collection.is_card_discovered(board.catalog.find_by_name("Wood")), "second-slot discovery retained independently")
	board.session.phase = "ready"
	board.session.paused = true
	board._advance_day()
	check(board.session.day == 8 and board.session.phase == "playing", "Start Day transitions runtime")
	check(int(disk(board).scenes.Main.session.day) == 8 and disk(board).scenes.Main.session.phase == "playing", "Start Day saves AFTER transition")
	DirAccess.make_dir_absolute(board._active_slot_path() + ".tmp")
	board.session.phase = "ready"
	board._advance_day()
	check(board.session.day == 9 and board.running and board.notice.text.contains("SAVE FAILED"), "failed checkpoint preserves advanced live day")
	check(int(disk(board).scenes.Main.session.day) == 8, "failed checkpoint leaves old disk save")
	check(not board._prepare_quit() and board.running, "playing quit save failure blocks exit")
	DirAccess.remove_absolute(board._active_slot_path() + ".tmp")
	board.session.paused = true
	var card: int = board.session.spawn_card(board.catalog.find_by_name("Wood"), Vector2(3, 0), -1, {"refuse_attach": true})
	board.selected = card
	check(board._allows_card_actions() and board._can_drag_card(card), "pause keeps playing interactions")
	for phase in ["feeding", "ready", "game_over"]:
		board.session.phase = phase
		var snapshot: String = JSON.stringify(board.session.campaign.capture())
		board._sell_selected()
		board._sell_selected_stack()
		board._buy(board.vendor_guids[0])
		board._withdraw_selected()
		board.dragging = card
		board.drag_moved = true
		board.drag_delta = Vector2(2, 0)
		board._finish_drag(Vector2.ZERO)
		check(not board._can_drag_card(card) and JSON.stringify(board.session.campaign.capture()) == snapshot, phase + " blocks card mutations")
		var saved_bytes: String = FileAccess.get_file_as_string(board._active_slot_path())
		check(board._prepare_quit() and FileAccess.get_file_as_string(board._active_slot_path()) == saved_bytes, phase + " skips quit autosave")
	board.session.phase = "selling"
	check(board._allows_card_actions() and board._can_drag_card(card), "selling permits card actions")
	board._sell_selected()
	check(not board.session.cards.has(card), "selling sale works")
	board.session.phase = "playing"
	board._save_game()
	check(board.notice.text == "Saved locally.", "manual slot save works")
	var live = board.session
	var corrupt_path: String = board.slots.slot_path(3)
	var file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	file.store_string("corrupt slot evidence")
	file.close()
	board.selected_slot = 3
	board._continue_game()
	check(board.session == live and board.active_slot == 2 and board.running, "bad Continue preserves live game")
	check(FileAccess.get_file_as_string(corrupt_path) == "corrupt slot evidence", "bad slot preserved")
	var normal_root: String = board.slot_root
	var blocker: String = root_path + "/not-a-directory"
	file = FileAccess.open(blocker, FileAccess.WRITE)
	file.store_string("blocker")
	file.close()
	board.slot_root = blocker
	board.start_new()
	check(board.session == live and board.running and board.notice.text.contains("Cannot create"), "failed New preserves live game")
	board.slot_root = normal_root
	var legacy: String = board.legacy_paths[0]
	check(board.session.campaign.save_file(legacy).ok, "test-owned legacy created")
	var legacy_bytes: String = FileAccess.get_file_as_string(legacy)
	board._refresh_slots()
	check(board.legacy_button.visible, "explicit legacy copy offered")
	board.slot_root = blocker
	board._adopt_legacy(legacy)
	check(board.session == live and FileAccess.get_file_as_string(legacy) == legacy_bytes, "failed legacy allocation preserves live game and original")
	board.slot_root = normal_root
	board._adopt_legacy(legacy)
	board.set_process(false)
	check(board.active_slot == 4 and board.session.day == 9, "adoption skips occupied corrupt slot")
	check(FileAccess.get_file_as_string(legacy) == legacy_bytes, "legacy bytes unchanged")
	check(board.notice.text.contains("Original and backup were kept"), "adoption explains preservation")
	live = board.session
	file = FileAccess.open(legacy, FileAccess.WRITE)
	file.store_string("invalid legacy")
	file.close()
	board._adopt_legacy(legacy)
	check(board.session == live and board.active_slot == 4 and board.title_status.text.begins_with("Legacy copy failed"), "invalid legacy cannot replace live game")
	# Departure checkpoint failure aborts travel; successful arrival saves both scenes.
	board.session.phase = "playing"
	board.session.paused = false
	var portal: int = board.session.spawn_card(board.catalog.find_by_name("Grand Portal"), Vector2(-3, -2), -1, {"refuse_attach": true})
	var traveler: int = board.session.spawn_card(board.catalog.find_by_name("Villager"), Vector2(-5, -2), -1, {"refuse_attach": true})
	board.session.move_to_stack(traveler, board.session.cards[portal].stack_id)
	var travel_stack: int = board.session.cards[portal].stack_id
	var recipe_guid: String = board.session.stacks[travel_stack].recipe_guid
	check(not recipe_guid.is_empty() and board.session.campaign.before_travel.is_valid(), "UI binds staged travel checkpoint")
	var before_travel: String = JSON.stringify(board.session.campaign.capture())
	DirAccess.make_dir_absolute(board._active_slot_path() + ".tmp")
	var blocked: Dictionary = board.session.campaign.travel(travel_stack, recipe_guid)
	check(not blocked.ok and JSON.stringify(board.session.campaign.capture()) == before_travel, "departure save failure aborts travel transaction")
	check(board.session.scene_name == "Main" and board.running and board.notice.text.contains("SAVE FAILED"), "failed departure visibly preserves Main")
	DirAccess.remove_absolute(board._active_slot_path() + ".tmp")
	var traveled: Dictionary = board.session.campaign.travel(travel_stack, recipe_guid)
	check(traveled.ok and board.session.scene_name == "Island" and disk(board).current_scene == "Island", "successful arrival checkpoints current scene")
	var departure: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(board._active_slot_path() + ".bak"))
	check(departure.current_scene == "Main" and disk(board).scenes.has("Main"), "departure backup and destination envelope preserve prior scene")
	# Backup recovery is surfaced and does not repair the corrupt primary implicitly.
	var recovered_path: String = board._active_slot_path()
	var recovery_bytes: String = FileAccess.get_file_as_string(recovered_path)
	file = FileAccess.open(recovered_path + ".bak", FileAccess.WRITE)
	file.store_string(recovery_bytes)
	file.close()
	file = FileAccess.open(recovered_path, FileAccess.WRITE)
	file.store_string("corrupt primary evidence")
	file.close()
	board.selected_slot = board.active_slot
	board._continue_game()
	board.set_process(false)
	check(board.running and board.session.scene_name == "Island" and board.notice.text.contains("Recovered from backup"), "selected slot backup recovery is reported")
	check(FileAccess.get_file_as_string(recovered_path) == "corrupt primary evidence", "Continue never silently repairs corrupt primary")
	file = FileAccess.open(recovered_path, FileAccess.WRITE)
	file.store_string(recovery_bytes)
	file.close()
	var ended_path: String = board._active_slot_path()
	var checkpoint_bytes: String = FileAccess.get_file_as_string(ended_path)
	board.session.phase = "game_over"
	board._refresh()
	board._save_game()
	check(FileAccess.get_file_as_string(ended_path) == checkpoint_bytes, "death does not overwrite checkpoint")
	board._return_title()
	check(board.running and board.game_over_dialog.visible and FileAccess.file_exists(ended_path), "game-over Return requires confirmation")
	board.game_over_dialog.hide()
	DirAccess.make_dir_absolute(ended_path + ".tmp")
	board._confirm_game_over_return()
	check(board.running and board.active_slot == 4 and board.notice.text.begins_with("Could not archive"), "archive failure preserves ended game")
	DirAccess.remove_absolute(ended_path + ".tmp")
	board._confirm_game_over_return()
	check(not board.running and board.active_slot == 0 and not FileAccess.file_exists(ended_path), "confirmed Return archives ended slot")
	check(not FileAccess.file_exists(ended_path + ".bak") and board.title_status.text.contains("archived locally"), "archive prevents backup resurrection")
	check(FileAccess.file_exists(first_path) and FileAccess.file_exists(corrupt_path), "archive leaves unrelated saves alone")
	print("Slot UI checks: %d passed / %d total" % [checks - failures, checks])
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit(0 if failures == 0 else 1)
