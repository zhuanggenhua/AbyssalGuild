extends RefCounted
## Native campaign slot inventory. No implicit migration, autosave, or deletion.
const Codec = preload("res://scripts/model/save_codec.gd")
const Campaign = preload("res://scripts/model/campaign.gd")
const MAX_SLOT = 999999
const SUFFIXES = ["", ".bak", ".tmp", ".bak.tmp"]
var directory: String = "user://slots"
var campaign

func configure(source_campaign, root: String = "user://slots") -> void:
	campaign = source_campaign
	directory = root.trim_suffix("/")

func slot_path(slot: int) -> String:
	return directory.path_join("SaveSlot%03d.json" % slot) if slot >= 1 and slot <= MAX_SLOT else ""

func _slot_from_name(filename: String) -> int:
	var base := filename
	for suffix in [".bak.tmp", ".reserved", ".bak", ".tmp"]:
		if base.ends_with(suffix):
			base = base.trim_suffix(suffix)
			break
	if not base.begins_with("SaveSlot") or not base.ends_with(".json"):
		return -1
	var digits := base.trim_prefix("SaveSlot").trim_suffix(".json")
	if not digits.is_valid_int():
		return -1
	var slot := digits.to_int()
	return slot if not slot_path(slot).is_empty() and base == slot_path(slot).get_file() else -1

func _occupied(slot: int) -> bool:
	var path := slot_path(slot)
	for suffix in SUFFIXES:
		if FileAccess.file_exists(path + suffix) or DirAccess.dir_exists_absolute(path + suffix):
			return true
	return DirAccess.dir_exists_absolute(path + ".reserved") or FileAccess.file_exists(path + ".reserved")

## Every recognized artifact reserves its number, including corrupt/temp-only saves.
func list_slots() -> Dictionary:
	if campaign == null:
		return Codec._fail("Configure a campaign before listing slots")
	if not DirAccess.dir_exists_absolute(directory):
		if FileAccess.file_exists(directory):
			return Codec._fail("Slot directory is a file")
		return {"ok": true, "slots": [], "ignored": []}
	var dir = DirAccess.open(directory)
	if dir == null:
		return Codec._fail("Cannot read slot directory")
	var occupied := {}
	var ignored: Array = []
	dir.list_dir_begin()
	var filename: String = dir.get_next()
	while not filename.is_empty():
		var slot := _slot_from_name(filename)
		if slot > 0:
			occupied[slot] = true
		elif filename != ".deleted":
			ignored.append(filename)
		filename = dir.get_next()
	dir.list_dir_end()
	var ids: Array = occupied.keys()
	ids.sort()
	var entries: Array = []
	for slot in ids:
		entries.append(_inspect(slot))
	return {"ok": true, "slots": entries, "ignored": ignored}

func _inspect(slot: int) -> Dictionary:
	var path := slot_path(slot)
	var entry := {"slot": slot, "path": path, "valid": false, "recovered": false, "errors": [], "artifacts": []}
	for suffix in SUFFIXES:
		if FileAccess.file_exists(path + suffix):
			entry.artifacts.append(path + suffix)
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var read := Codec._read(candidate)
		if read.ok:
			var snapshot = read.snapshot
			if not snapshot is Dictionary or snapshot.get("format") != Campaign.FORMAT or snapshot.get("slot_number") != slot:
				read = Codec._fail("Filename/header slot mismatch or unsupported format")
			else:
				read = campaign._validate_snapshot(snapshot)
				if read.ok and not entry.valid:
					var current: Dictionary = snapshot.scenes[snapshot.current_scene].session
					entry.merge({"valid": true, "recovered": candidate != path, "selected_path": candidate, "scene": snapshot.current_scene, "day": int(current.day), "quest_progress": int(current.quests.QuestProgress), "modified_unix": FileAccess.get_modified_time(candidate)}, true)
		if not read.ok:
			entry.errors.append({"path": candidate, "error": read.error})
	if not entry.valid and entry.errors.is_empty():
		entry.errors.append({"path": path, "error": "No committed primary or backup; temporary/reservation artifacts retained"})
	return entry

## Advisory number only; create_slot performs the occupancy check again.
func next_slot() -> Dictionary:
	var inventory := list_slots()
	if not inventory.ok:
		return inventory
	for slot in range(1, MAX_SLOT + 1):
		if not _occupied(slot):
			return {"ok": true, "slot": slot, "path": slot_path(slot)}
	return Codec._fail("No available slot number")

## Saves current campaign to a fresh slot. Never overwrites an existing artifact.
## One writer per slot store; reservation also protects competing create calls.
func create_slot() -> Dictionary:
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return Codec._fail("Cannot create slot directory: " + error_string(error))
	var selected := next_slot()
	if not selected.ok:
		return selected
	var reservation: String = selected.path + ".reserved"
	if DirAccess.make_dir_absolute(reservation) != OK:
		return Codec._fail("Slot allocation is busy; refresh and retry")
	# Another process may have committed between selection and reservation.
	for suffix in SUFFIXES:
		if FileAccess.file_exists(selected.path + suffix) or DirAccess.dir_exists_absolute(selected.path + suffix):
			DirAccess.remove_absolute(reservation)
			return Codec._fail("Slot became occupied; no overwrite performed")
	var previous: int = campaign.slot_number
	campaign.slot_number = selected.slot
	var result: Dictionary = campaign.save_file(selected.path)
	if not result.ok:
		campaign.slot_number = previous
	else:
		result["slot"] = selected.slot
	DirAccess.remove_absolute(reservation)
	return result

func save_slot(slot: int) -> Dictionary:
	if campaign == null or slot_path(slot).is_empty() or campaign.slot_number != slot:
		return Codec._fail("Campaign slot does not match requested slot")
	if DirAccess.dir_exists_absolute(slot_path(slot) + ".reserved"):
		return Codec._fail("Slot allocation is busy")
	var entry := _inspect(slot)
	if not entry.valid:
		return Codec._fail("Slot has no valid campaign; create a new slot instead")
	# Campaign validation alone accepts any positive slot header. Do not let a
	# foreign but valid primary displace this slot's healthy backup on save.
	if FileAccess.file_exists(slot_path(slot)):
		var primary := Codec._read(slot_path(slot))
		if primary.ok and primary.snapshot is Dictionary and primary.snapshot.get("format") == Campaign.FORMAT and primary.snapshot.get("slot_number") != slot:
			return Codec._fail("Primary belongs to another slot; preserve files and resolve explicitly")
	return campaign.save_file(slot_path(slot))

func load_slot(slot: int) -> Dictionary:
	if campaign == null or slot_path(slot).is_empty():
		return Codec._fail("Invalid slot or unconfigured campaign")
	var entry := _inspect(slot)
	if not entry.valid:
		return {"ok": false, "error": "No valid campaign for slot", "details": entry}
	var result: Dictionary = campaign.load_file(entry.selected_path)
	if result.ok:
		result["slot"] = slot
		result["recovered"] = entry.recovered
	return result

## Explicit logical deletion, implemented as recoverable same-store quarantine.
## Includes backups/temp files so deleted slots cannot reappear through recovery.
func delete_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if path.is_empty():
		return Codec._fail("Invalid slot")
	if DirAccess.dir_exists_absolute(path + ".reserved"):
		return Codec._fail("Cannot delete an allocated/busy slot")
	var paths: Array = []
	for suffix in SUFFIXES:
		if DirAccess.dir_exists_absolute(path + suffix):
			return Codec._fail("Unexpected directory at slot path; no files moved")
		if FileAccess.file_exists(path + suffix):
			paths.append(path + suffix)
	if paths.is_empty():
		return Codec._fail("Slot has no files")
	var archive := directory.path_join(".deleted").path_join("slot-%d-%d-%d" % [slot, Time.get_unix_time_from_system(), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(directory.path_join(".deleted")) != OK or DirAccess.make_dir_absolute(archive) != OK:
		return Codec._fail("Cannot create recoverable deletion archive")
	var moved := {}
	for original in paths:
		var destination := archive.path_join(original.get_file())
		if DirAccess.rename_absolute(original, destination) != OK:
			var rollback_errors: Array = []
			for prior in moved:
				if DirAccess.rename_absolute(moved[prior], prior) != OK:
					rollback_errors.append(prior)
			return {"ok": false, "error": "Slot removal failed", "archive": archive, "rollback_errors": rollback_errors}
		moved[original] = destination
	return {"ok": true, "slot": slot, "archive": archive, "files": moved.values()}
