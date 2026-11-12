extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",label)
func write(path: String, text: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text); file.close()
func select_archive(board, id: String, slot: int) -> bool:
	for index in board.archive_picker.item_count:
		var row: Variant = board.archive_picker.get_item_metadata(index)
		if row is Dictionary and row.archive_id == id and row.slot == slot:
			board.archive_picker.select(index); board._select_archive(index); return true
	return false
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new()
	var path := "user://slot-management-ui-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"
	board.options_path = path + "/options.json"
	board.legacy_paths.clear()
	board.legacy_paths.append(board.slot_root + "/session.json")
	root.add_child(board); await process_frame
	check(board.archive_selected_button.disabled and board.archive_all_button.disabled and board.restore_archive_button.disabled, "empty title disables archive/restore actions")
	board.start_new(); board.set_process(false)
	board._request_archive_selected()
	check(board.pending_archive_plan.is_empty(), "title archive actions cannot remove a live running slot")
	board._return_title()
	board.start_new(); board.set_process(false)
	board.session.day = 9; board._return_title()
	write(board.slot_root + "/options.json","owned options marker")
	write(board.legacy_paths[0],"owned legacy marker")
	var first: String = board.slots.slot_path(1)
	var second: String = board.slots.slot_path(2)
	var first_bytes: String = FileAccess.get_file_as_string(first)
	board.selected_slot = 1
	board._request_archive_selected()
	check(board.pending_archive_plan.slots == [1] and board.archive_dialog.dialog_text.contains("Archive 1 listed slot(s): 1"), "selected confirmation shows exact slot and count")
	check(board.archive_dialog.dialog_text.contains("backups") and board.archive_dialog.dialog_text.contains("Options, legacy saves and existing archives are excluded"), "confirmation explains artifact scope and exclusions")
	check(FileAccess.get_file_as_string(first) == first_bytes, "preparing confirmation is read-only")
	board._cancel_archive_slots(); board.archive_dialog.hide(); board._confirm_archive_slots()
	check(FileAccess.file_exists(first) and board.pending_archive_plan.is_empty(), "cancellation and repeated confirm cannot archive")
	board._request_archive_selected()
	write(first, first_bytes + "\n")
	board._confirm_archive_slots()
	check(FileAccess.file_exists(first) and FileAccess.file_exists(second) and board.title_status.text.begins_with("Archive failed:"), "stale file change prevents any archive move")
	check(board.pending_archive_plan.is_empty(), "stale confirmation cannot be silently retried")
	board.selected_slot = 1; board._request_archive_selected(); board._confirm_archive_slots()
	check(not FileAccess.file_exists(first) and FileAccess.file_exists(second), "fresh confirmation archives only selected slot")
	var inventory: Dictionary = board.slots.list_archives()
	var archive: Dictionary = inventory.archives[0]
	var archived_path: String = archive.path + "/" + first.get_file()
	var archive_bytes: String = FileAccess.get_file_as_string(archived_path)
	check(select_archive(board,archive.id,1) and not board.restore_archive_button.disabled, "valid archived slot can be selected for restore")
	var live = board.session
	var before: String = JSON.stringify(board.session.campaign.capture())
	board._restore_archive_copy()
	check(not board.running and board.session == live and JSON.stringify(board.session.campaign.capture()) == before, "restore-copy stays at title without loading or changing live campaign")
	check(board.selected_slot == 1 and FileAccess.file_exists(first), "restore uses fresh lowest unoccupied slot and selects it")
	check(FileAccess.get_file_as_string(archived_path) == archive_bytes, "restore preserves archived original bytes")
	board._restore_archive_copy()
	check(board.selected_slot == 3 and FileAccess.file_exists(board.slots.slot_path(3)), "repeated explicit restore allocates another copy rather than overwrite")
	var backup_path: String = archived_path + ".bak"
	var had_backup: bool = FileAccess.file_exists(backup_path)
	var backup_bytes: String = FileAccess.get_file_as_string(backup_path) if had_backup else ""
	write(archived_path,"changed after selection")
	if had_backup: write(backup_path,"changed backup")
	var before_failed_restore: String = JSON.stringify(board.session.campaign.capture())
	var occupied: int = board.slots.list_slots().slots.size()
	board._restore_archive_copy()
	check(board.title_status.text.begins_with("Restore failed:") and board.slots.list_slots().slots.size() == occupied and JSON.stringify(board.session.campaign.capture()) == before_failed_restore, "changed archive fails fresh validation without allocating or replacing live game")
	write(archived_path,archive_bytes)
	if had_backup: write(backup_path,backup_bytes)
	board._refresh_archives()
	# Archive all means exactly the listing/plan, not files arriving afterward.
	write(board.slots.slot_path(4) + ".tmp", "invalid temp-only save")
	board._refresh_slots(); board._request_archive_all()
	check(board.pending_archive_plan.slots == [1,2,3,4] and board.archive_dialog.dialog_text.contains("invalid or temp-only"), "all-listed scope explicitly includes temp-only invalid slots")
	write(board.slots.slot_path(5),"newly arrived unlisted slot")
	board._confirm_archive_slots()
	check(FileAccess.file_exists(board.slots.slot_path(5)) and not FileAccess.file_exists(second), "unlisted new slot survives confirmed exact batch")
	check(FileAccess.get_file_as_string(board.slot_root + "/options.json") == "owned options marker" and FileAccess.get_file_as_string(board.legacy_paths[0]) == "owned legacy marker", "options and legacy bytes survive archive-all")
	check(FileAccess.get_file_as_string(archived_path) == archive_bytes, "old archives excluded from archive-all")
	inventory = board.slots.list_archives()
	var batch_id := ""
	for entry in inventory.archives:
		for slot in entry.entries:
			if slot.slot == 4: batch_id = entry.id
	check(select_archive(board,batch_id,4) and board.restore_archive_button.disabled, "invalid archived entry remains diagnostic with Restore disabled")
	var count_before: int = board.slots.list_slots().slots.size()
	board._restore_archive_copy()
	check(board.slots.list_slots().slots.size() == count_before, "invalid archive cannot create a replacement save")
	# Interrupt a prepared flow by entering a game; old approval must not survive.
	board._refresh_slots(); board.selected_slot = 5; board._request_archive_selected()
	board.start_new(); board.set_process(false)
	check(board.running and board.pending_archive_plan.is_empty() and not board.archive_dialog.visible, "entering gameplay invalidates pending archive confirmation")
	board._confirm_archive_slots()
	check(FileAccess.file_exists(board.slots.slot_path(5)), "interrupted confirmation cannot remove its old target")
	board._return_title()
	var ancestor: Node = board.slot_picker.get_parent()
	while ancestor != null and not ancestor is ScrollContainer: ancestor = ancestor.get_parent()
	check(ancestor is ScrollContainer and board.title_panel.is_ancestor_of(ancestor), "title save controls remain accessible in a scroll container")
	board.queue_free(); await process_frame; await create_timer(0.5).timeout
	print("Slot management UI checks: %d passed / %d total" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
