extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Slots = preload("res://scripts/model/save_slots.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func write(path: String, value: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func cleanup(path: String) -> void:
	# Called only on the unique directory created by this test.
	var dir = DirAccess.open(path)
	if dir == null: return
	dir.include_hidden = true
	for file in dir.get_files(): DirAccess.remove_absolute(path.path_join(file))
	for child in dir.get_directories(): cleanup(path.path_join(child))
	DirAccess.remove_absolute(path)

func _init() -> void:
	var root := "user://test-save-slots-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var catalog = Catalog.new()
	catalog.configure({"scenes": [{"name": "Main", "documents": [{"fields": {"questGroups": [], "defaultSpawnCards": []}}]}]})
	var session = Session.new()
	session.configure(catalog, 52)
	var slots = Slots.new()
	slots.configure(session.campaign, root)
	check(slots.list_slots().ok and slots.list_slots().slots.is_empty(), "missing slot directory lists empty")
	check(slots.next_slot().slot == 1, "lowest slot begins at one")
	check(slots.slot_path(1).ends_with("SaveSlot001.json") and slots.slot_path(1000).ends_with("SaveSlot1000.json"), "canonical source-style slot filenames")
	check(slots.slot_path(0).is_empty() and slots.slot_path(-1).is_empty(), "invalid slot path refused")
	var created: Dictionary = slots.create_slot()
	check(created.ok and created.slot == 1, "create fresh campaign slot")
	var initial: String = FileAccess.get_file_as_string(slots.slot_path(1))
	var state_before: String = JSON.stringify(Codec.capture(session), "", true, true)
	var inventory: Dictionary = slots.list_slots()
	check(inventory.ok and inventory.slots.size() == 1 and inventory.slots[0].valid, "list only committed valid slot")
	check(inventory.slots[0].scene == "Main" and inventory.slots[0].day == 1 and inventory.slots[0].quest_progress == 0 and inventory.slots[0].modified_unix > 0, "native display metadata")
	check(JSON.stringify(Codec.capture(session), "", true, true) == state_before, "enumeration does not alter live state or RNG")
	write(slots.slot_path(2), "{corrupt")
	write(slots.slot_path(3) + ".tmp", "interrupted")
	write(root.path_join("unrelated.json"), "untouched")
	DirAccess.make_dir_absolute(slots.slot_path(4) + ".reserved")
	check(slots.next_slot().slot == 5, "corrupt temporary and reserved slots are occupied")
	inventory = slots.list_slots()
	check(inventory.slots.size() == 4 and not inventory.slots[1].valid and not inventory.slots[1].errors.is_empty(), "corrupt entry reported rather than discarded")
	check(inventory.ignored.has("unrelated.json"), "unrecognized files reported but ignored")
	check(FileAccess.get_file_as_string(slots.slot_path(2)) == "{corrupt", "enumeration leaves corruption untouched")
	check(slots.create_slot().slot == 5, "new slot does not overwrite corrupt or interrupted saves")
	check(FileAccess.get_file_as_string(slots.slot_path(1)) == initial, "new allocation preserves existing slot bytes")
	check(not slots.save_slot(1).ok, "save refuses campaign/slot mismatch")
	check(slots.load_slot(1).ok and session.campaign.slot_number == 1, "load selected campaign slot")
	session.day = 7
	check(slots.save_slot(1).ok, "save existing slot via campaign")
	check(FileAccess.file_exists(slots.slot_path(1) + ".bak"), "existing slot save retains backup")
	write(slots.slot_path(1), "broken primary")
	inventory = slots.list_slots()
	check(inventory.slots[0].valid and inventory.slots[0].recovered and inventory.slots[0].day == 1 and not inventory.slots[0].errors.is_empty(), "backup metadata usable while corrupt primary reported")
	var loaded: Dictionary = slots.load_slot(1)
	check(loaded.ok and loaded.recovered and session.day == 1, "slot load recovers selected backup")
	check(FileAccess.get_file_as_string(slots.slot_path(1)) == "broken primary", "recovery is read only")
	var before: String = JSON.stringify(Codec.capture(session), "", true, true)
	check(not slots.load_slot(2).ok and JSON.stringify(Codec.capture(session), "", true, true) == before, "corrupt slot load leaves session intact")
	var wrong = JSON.parse_string(initial)
	wrong.slot_number = 9
	write(slots.slot_path(6), JSON.stringify(wrong))
	check(not slots.load_slot(6).ok, "filename header mismatch refused")
	write(slots.slot_path(7) + ".bak", initial.replace('"slot_number":1', '"slot_number":7'))
	check(slots.load_slot(7).ok, "backup-only committed slot is recoverable")
	write(slots.slot_path(7), JSON.stringify(wrong))
	var healthy_backup: String = FileAccess.get_file_as_string(slots.slot_path(7) + ".bak")
	check(not slots.save_slot(7).ok, "foreign primary cannot replace healthy matching backup")
	check(FileAccess.get_file_as_string(slots.slot_path(7) + ".bak") == healthy_backup, "foreign-primary save rejection preserves backup bytes")
	var old_slot: int = session.campaign.slot_number
	var old_day: int = session.day
	session.day = 0
	check(not slots.create_slot().ok and session.campaign.slot_number == old_slot, "failed fresh save restores campaign slot number")
	check(slots.next_slot().slot == 8, "failed save releases reservation without occupying slot")
	session.day = old_day
	check(not slots.delete_slot(4).ok, "active reservation cannot be deleted")
	var removed: Dictionary = slots.delete_slot(1)
	check(removed.ok and removed.files.size() == 2, "explicit deletion quarantines primary and backup")
	check(not FileAccess.file_exists(slots.slot_path(1)) and not FileAccess.file_exists(slots.slot_path(1) + ".bak"), "deleted slot cannot resurrect via backup")
	check(FileAccess.file_exists(removed.archive.path_join("SaveSlot001.json.bak")), "deletion archive retains recoverable bytes")
	check(slots.next_slot().slot == 1, "lowest released slot reused")
	check(not slots.delete_slot(1).ok, "repeated delete reports absence")
	check(FileAccess.get_file_as_string(root.path_join("unrelated.json")) == "untouched", "delete never touches unrelated files")
	check(slots.create_slot().slot == 1, "fresh allocation safely reuses released number")
	# A legacy single session is intentionally not adopted just by listing files.
	write(root.path_join("session.json"), JSON.stringify(Codec.capture(session)))
	check(slots.list_slots().ignored.has("session.json"), "legacy single-session file requires explicit adoption")
	check(FileAccess.file_exists(root.path_join("session.json")), "legacy file remains untouched")
	var blocked = Slots.new()
	blocked.configure(session.campaign, root.path_join("unrelated.json"))
	check(not blocked.list_slots().ok and not blocked.create_slot().ok, "unwritable directory errors reported")
	cleanup(root)
	check(not DirAccess.dir_exists_absolute(root), "test removes only its own temporary store")
	print("Save slots: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
