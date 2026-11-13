extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Slots = preload("res://scripts/model/save_slots.gd")
var checks := 0
var failures := 0

class FailingMoves extends Slots:
	var moves := 0
	var fail_on: Array = []
	func _move_file(source: String, target: String) -> Error:
		moves += 1
		if moves in fail_on: return ERR_CANT_CREATE
		return super._move_file(source, target)

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func bytes(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func cleanup(path: String) -> void:
	# Only the unique directory made by this test is passed here.
	var dir := DirAccess.open(path)
	if dir == null: return
	dir.include_hidden = true
	for file in dir.get_files(): DirAccess.remove_absolute(path.path_join(file))
	for child in dir.get_directories():
		if dir.is_link(child): DirAccess.remove_absolute(path.path_join(child))
		else: cleanup(path.path_join(child))
	DirAccess.remove_absolute(path)

func entry_for(inventory: Dictionary, id: String, slot: int) -> Dictionary:
	for archive in inventory.archives:
		if archive.id == id:
			for entry in archive.entries:
				if entry.slot == slot: return entry
	return {}

func _init() -> void:
	var root := "user://test-slot-management-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var catalog = Catalog.new()
	catalog.configure({"scenes": [{"name": "Main", "documents": [{"fields": {"questGroups": [], "defaultSpawnCards": []}}]}]})
	var session = Session.new()
	session.configure(catalog, 812)
	var store = Slots.new()
	store.configure(session.campaign, root)
	check(store.list_archives().ok and store.list_archives().archives.is_empty(), "missing archive lists empty without creating files")
	check(not DirAccess.dir_exists_absolute(root), "archive enumeration never creates store")
	check(store.create_slot().ok, "create test slot one")
	var original: String = bytes(store.slot_path(1))
	session.day = 5
	check(store.save_slot(1).ok and store.create_slot().slot == 2, "test slots and backup created")
	# Archived evidence may be much older than its restored copy. A new staged
	# save deliberately refreshes last_saved, even when it reuses the same slot.
	# Make that difference deterministic rather than relying on a clock-second race.
	var aged_primary: Dictionary = JSON.parse_string(bytes(store.slot_path(1)))
	aged_primary.last_saved = {"local": "2001-02-03T04:05:06", "utc_offset_minutes": 0}
	write(store.slot_path(1), JSON.stringify(aged_primary, "", true, true))
	write(store.slot_path(1) + ".tmp", "interrupted primary")
	write(store.slot_path(1) + ".bak.tmp", "interrupted backup")
	write(store.slot_path(3), "corrupt-only evidence")
	write(store.slot_path(4) + ".tmp", "temporary-only evidence")
	write(root.path_join("options.json"), "options are never save slots")
	write(root.path_join("session.json"), "legacy is not a slot")
	write(root.path_join("SaveSlot0005.json"), "noncanonical slot names ignored")
	var live: String = JSON.stringify(session.campaign.capture(), "", true, true)
	check(not store.prepare_delete_slots([]).ok and not store.prepare_delete_slots([1, 1]).ok and not store.prepare_delete_slots([1.0]).ok and not store.prepare_delete_slots([0]).ok and not store.prepare_delete_slots([9999999]).ok, "invalid and ambiguous delete scopes rejected")
	var prepared: Dictionary = store.prepare_delete_slots([4, 3, 2, 1])
	check(prepared.ok and prepared.plan.slots == [1, 2, 3, 4] and prepared.plan.artifacts.size() == 7, "confirmation fixes exact sorted IDs and primary backup temp scope")
	check(bytes(store.slot_path(1) + ".bak") == original and JSON.stringify(session.campaign.capture(), "", true, true) == live, "preparing confirmation leaves bytes and live state unchanged")
	var single: Dictionary = store.prepare_delete_slots([1])
	var previous: String = bytes(store.slot_path(1))
	write(store.slot_path(1), "changed after confirmation")
	check(not store.delete_slots(single.plan).ok and bytes(store.slot_path(1)) == "changed after confirmation" and bytes(store.slot_path(1) + ".bak") == original, "changed bytes invalidate confirmation without moving any files")
	write(store.slot_path(1), previous)
	write(store.slot_path(2) + ".bak", original)
	check(not store.delete_slots(prepared.plan).ok and FileAccess.file_exists(store.slot_path(1)), "new artifact after confirmation invalidates whole batch")
	DirAccess.remove_absolute(store.slot_path(2) + ".bak")
	write(store.slot_path(2) + ".reserved", "reservation marker")
	check(not store.prepare_delete_slots([1, 2]).ok and not store.save_slot(2).ok, "file reservations block delete and save just like directory reservations")
	DirAccess.remove_absolute(store.slot_path(2) + ".reserved")
	DirAccess.make_dir_absolute(store.slot_path(2) + ".tmp")
	check(not store.prepare_delete_slots([1, 2]).ok and FileAccess.file_exists(store.slot_path(1)), "unexpected directory refuses whole batch before movement")
	DirAccess.remove_absolute(store.slot_path(2) + ".tmp")
	var wrong_root: Dictionary = single.plan.duplicate(true)
	wrong_root.directory = root + "/another-store"
	check(not store.delete_slots(wrong_root).ok, "confirmation from another directory rejected")
	var removed: Dictionary = store.delete_slots(prepared.plan)
	check(removed.ok and removed.slots == [1, 2, 3, 4] and removed.files.size() == 7, "confirmed batch archives exact artifacts together")
	check(store.list_slots().slots.is_empty() and store.next_slot().slot == 1, "archive releases all selected slot IDs without backup resurrection")
	check(bytes(root.path_join("options.json")) == "options are never save slots" and bytes(root.path_join("session.json")) == "legacy is not a slot" and bytes(root.path_join("SaveSlot0005.json")) == "noncanonical slot names ignored", "options legacy and unknown names preserved byte for byte")
	check(not store.delete_slots(prepared.plan).ok, "repeated confirmation cannot archive twice")
	var archive_id: String = removed.archive.get_file()
	var inventory: Dictionary = store.list_archives()
	check(inventory.ok and inventory.archives.size() == 1 and inventory.archives[0].entries.size() == 4, "batch archive lists each original slot")
	check(entry_for(inventory, archive_id, 1).valid and entry_for(inventory, archive_id, 1).day == 5 and not entry_for(inventory, archive_id, 3).valid and not entry_for(inventory, archive_id, 4).valid, "archive validity and metadata distinguish corrupt and temporary-only slots")
	check(JSON.stringify(session.campaign.capture(), "", true, true) == live, "archive and inventory leave live campaign including RNG unchanged")
	check(not store.restore_archive(archive_id, 3).ok and not store.restore_archive(archive_id, 4).ok and not store.restore_archive(archive_id, 99).ok and store.list_slots().slots.is_empty(), "corrupt temporary or missing archive rows cannot create empty replacement saves")
	for invalid in ["../" + archive_id, "/" + archive_id, "slots-1-2/../" + archive_id, "slots-1-2\\outside", "slots-+1-2", "slot-1-2", "slots-1-2-3", "slots-1.2-3"]:
		check(not store.restore_archive(invalid, 1).ok, "archive ID cannot escape or invent format: " + invalid)
	var copy: Dictionary = store.restore_archive(archive_id, 1)
	var copied_snapshot: Dictionary = JSON.parse_string(bytes(copy.path))
	var previous_snapshot: Dictionary = JSON.parse_string(previous)
	check(copy.ok and copy.slot == 1 and not copy.recovered and Session.Campaign.SavedTime.valid(copied_snapshot.last_saved) and copied_snapshot.last_saved != previous_snapshot.last_saved, "validated restore creates first free slot with its own save timestamp")
	copied_snapshot.erase("last_saved")
	previous_snapshot.erase("last_saved")
	check(copied_snapshot == previous_snapshot, "restore preserves every archived campaign field except new-save timestamp")
	var restored_bytes: String = bytes(copy.path)
	copy = store.restore_archive(archive_id, 1)
	check(copy.ok and copy.slot == 2 and bytes(store.slot_path(1)) == restored_bytes, "repeated restore creates a separate copy without overwriting first")
	check(JSON.parse_string(bytes(copy.path)).slot_number == 2 and JSON.stringify(session.campaign.capture(), "", true, true) == live, "fresh copy rewrites slot header only through staged save and keeps live state unchanged")
	check(bytes(removed.archive.path_join("SaveSlot001.json")) == previous and bytes(removed.archive.path_join("SaveSlot001.json.bak")) == original, "restore preserves archive primary and backup bytes")
	write(removed.archive.path_join("SaveSlot001.json"), "archived corrupt primary")
	copy = store.restore_archive(archive_id, 1)
	check(copy.ok and copy.slot == 3 and copy.recovered and JSON.parse_string(bytes(copy.path)).scenes.Main.session.day == 1, "validated archived backup restores when primary is corrupt")
	check(bytes(removed.archive.path_join("SaveSlot001.json")) == "archived corrupt primary" and bytes(removed.archive.path_join("SaveSlot001.json.bak")) == original, "backup restore never repairs archived evidence")
	var foreign: Dictionary = JSON.parse_string(previous)
	foreign.slot_number = 77
	write(removed.archive.path_join("SaveSlot002.json"), JSON.stringify(foreign))
	check(not store.restore_archive(archive_id, 2).ok and store.next_slot().slot == 4, "foreign archived header cannot restore or occupy slot")
	foreign.slot_number = 2
	foreign.scenes.Main.session.day = 0
	write(removed.archive.path_join("SaveSlot002.json"), JSON.stringify(foreign))
	check(not store.restore_archive(archive_id, 2).ok and store.next_slot().slot == 4, "invalid archived session is staged and rejected before commit")
	# Historical single-slot archive format remains restorable.
	var legacy_archive: String = root.path_join(".deleted/slot-8-1700000000-100")
	DirAccess.make_dir_absolute(legacy_archive)
	var legacy_snapshot: Dictionary = JSON.parse_string(original)
	legacy_snapshot.slot_number = 8
	write(legacy_archive.path_join("SaveSlot008.json"), JSON.stringify(legacy_snapshot))
	DirAccess.make_dir_absolute(root.path_join(".deleted/not-an-archive"))
	write(root.path_join(".deleted/readme.txt"), "keep archive notes")
	inventory = store.list_archives()
	check(inventory.ok and inventory.archives.size() == 2 and inventory.ignored.has("not-an-archive") and inventory.ignored.has("readme.txt"), "old single archives supported while unknown objects ignored")
	check(store.restore_archive(legacy_archive.get_file(), 8).slot == 4, "historical archive copied into a fresh free slot")
	# Deliberately simulated rename failures operate only within this test's root.
	var failing = FailingMoves.new()
	failing.configure(session.campaign, root)
	var keep_one: String = bytes(store.slot_path(1))
	var keep_two: String = bytes(store.slot_path(2))
	failing.fail_on = [2]
	prepared = failing.prepare_delete_slots([1, 2])
	var failed: Dictionary = failing.delete_slots(prepared.plan)
	check(not failed.ok and failed.rollback_errors.is_empty() and bytes(store.slot_path(1)) == keep_one and bytes(store.slot_path(2)) == keep_two, "mid-batch rename failure rolls earlier moves back without loss")
	failing.moves = 0
	failing.fail_on = [2, 3]
	failed = failing.delete_slots(prepared.plan)
	check(not failed.ok and failed.rollback_errors == [store.slot_path(1)] and bytes(failed.archive.path_join("SaveSlot001.json")) == keep_one and bytes(store.slot_path(2)) == keep_two, "rollback failure explicitly locates retained recoverable bytes")
	check(store.restore_archive(failed.archive.get_file(), 1).ok, "partial failure archive remains valid for copy recovery")
	# Links are untrusted aliases, never permission to mutate their targets.
	var directory := DirAccess.open(root)
	check(directory.create_link("options.json", "SaveSlot005.json") == OK, "create test-owned file link")
	check(not store._inspect(5).valid and not store.prepare_delete_slots([5]).ok, "linked slot is unavailable and cannot be archived")
	write(store.slot_path(5) + ".bak", original.replace('"slot_number":1', '"slot_number":5'))
	check(store.load_slot(5).ok, "safe backup can load without following linked primary")
	check(not store.save_slot(5).ok and bytes(root.path_join("options.json")) == "options are never save slots", "save never follows or displaces linked artifact")
	check(directory.create_link("missing-target", "SaveSlot006.json") == OK and store.next_slot().slot == 7, "dangling link also reserves its slot instead of being overwritten")
	var archive_dir := DirAccess.open(root.path_join(".deleted"))
	check(archive_dir.create_link(legacy_archive.get_file(), "slots-1-2") == OK, "create test-owned archive-directory link")
	check(store.list_archives().ignored.has("slots-1-2") and not store.restore_archive("slots-1-2", 8).ok, "archive directory links ignored and refused by direct restore")
	# A blocked archive root never moves any selected data.
	var blocked_root: String = root.path_join("blocked-store")
	DirAccess.make_dir_absolute(blocked_root)
	write(blocked_root.path_join(".deleted"), "blocker")
	write(blocked_root.path_join("SaveSlot001.json"), original)
	var blocked = Slots.new()
	blocked.configure(session.campaign, blocked_root)
	check(not blocked.delete_slot(1).ok and not blocked.list_archives().ok and bytes(blocked_root.path_join("SaveSlot001.json")) == original, "file at archive root blocks operation safely")
	cleanup(root)
	check(not DirAccess.dir_exists_absolute(root), "only unique test directory cleaned")
	print("Slot management: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
