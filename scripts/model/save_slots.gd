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
		if FileAccess.file_exists(path + suffix) or DirAccess.dir_exists_absolute(path + suffix) or _is_link(path + suffix):
			return true
	return _exists(path + ".reserved") or _is_link(path + ".reserved")

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
	return _inspect_at(slot, directory)

func _inspect_at(slot: int, root: String) -> Dictionary:
	var path := root.path_join(slot_path(slot).get_file())
	var entry := {"slot": slot, "path": path, "valid": false, "recovered": false, "errors": [], "artifacts": []}
	for suffix in SUFFIXES:
		if FileAccess.file_exists(path + suffix):
			entry.artifacts.append(path + suffix)
	for candidate in [path, path + ".bak"]:
		if _is_link(candidate):
			entry.errors.append({"path": candidate, "error": "Linked save files are not supported"})
			continue
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
					if snapshot.has("last_saved"):
						entry["saved_timestamp"] = {"provenance": "persisted_save_field", "display": Campaign.SavedTime.describe(snapshot.last_saved), "value": snapshot.last_saved.duplicate(true)}
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
		if _exists(selected.path + suffix) or _is_link(selected.path + suffix):
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
	if _exists(slot_path(slot) + ".reserved") or _is_link(slot_path(slot) + ".reserved"):
		return Codec._fail("Slot allocation is busy")
	for suffix in SUFFIXES:
		if _is_link(slot_path(slot) + suffix):
			return Codec._fail("Linked slot artifacts are not supported; files preserved")
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

## Read-only confirmation snapshot. Only these exact slot artifacts are in scope.
## An altered/missing artifact or a new backup/temp invalidates confirmation.
func prepare_delete_slots(ids: Array) -> Dictionary:
	if ids.is_empty():
		return Codec._fail("No slots selected")
	var selected: Array = []
	for value in ids:
		if not value is int or slot_path(value).is_empty() or selected.has(value):
			return Codec._fail("Invalid or duplicate selected slot")
		selected.append(value)
	selected.sort()
	var artifacts: Array = []
	for slot in selected:
		var path := slot_path(slot)
		if _exists(path + ".reserved") or _is_link(path + ".reserved"):
			return Codec._fail("Cannot archive an allocated/busy slot")
		var found := false
		for suffix in SUFFIXES:
			var original: String = path + suffix
			if _is_link(original) or DirAccess.dir_exists_absolute(original):
				return Codec._fail("Unexpected directory or link at slot path; no files moved")
			if not FileAccess.file_exists(original):
				continue
			var digest := FileAccess.get_sha256(original)
			if digest.is_empty():
				return Codec._fail("Cannot read slot artifact; no files moved")
			artifacts.append({"name": original.get_file(), "sha256": digest})
			found = true
		if not found:
			return Codec._fail("Slot %d has no files" % slot)
	return {"ok": true, "plan": {"directory": directory, "slots": selected, "artifacts": artifacts}}

## Explicit logical deletion, implemented as recoverable same-store quarantine.
## Includes backups/temp files so archived slots cannot reappear through recovery.
func delete_slot(slot: int) -> Dictionary:
	var prepared := prepare_delete_slots([slot])
	if not prepared.ok:
		return prepared
	var result := delete_slots(prepared.plan)
	if result.ok:
		result["slot"] = slot
	return result

## Caller displays prepare_delete_slots.plan.slots and confirms before invoking.
## Preflights the whole batch and refuses a stale confirmation before any move.
func delete_slots(plan: Dictionary) -> Dictionary:
	if not plan.get("slots") is Array:
		return Codec._fail("Invalid archive confirmation")
	var current := prepare_delete_slots(plan.slots)
	if not current.ok:
		return current
	if current.plan != plan:
		return Codec._fail("Selected save files changed; refresh and confirm again")
	var archive_root := directory.path_join(".deleted")
	if _is_link(archive_root) or FileAccess.file_exists(archive_root):
		return Codec._fail("Archive directory is unavailable; no files moved")
	var archive := archive_root.path_join("slots-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(archive_root) != OK or DirAccess.make_dir_absolute(archive) != OK:
		return Codec._fail("Cannot create recoverable deletion archive")
	var moved := {}
	for artifact in plan.artifacts:
		var original := directory.path_join(artifact.name)
		var destination := archive.path_join(artifact.name)
		if _move_file(original, destination) != OK:
			var rollback_errors: Array = []
			for prior in moved:
				# Never overwrite a file that appeared during rollback.
				if _exists(prior) or _is_link(prior) or _move_file(moved[prior], prior) != OK:
					rollback_errors.append(prior)
			return {"ok": false, "error": "Slot archive failed; inspect retained archive if rollback was incomplete", "archive": archive, "rollback_errors": rollback_errors}
		moved[original] = destination
	return {"ok": true, "slots": plan.slots.duplicate(), "archive": archive, "files": moved.values()}

func _move_file(source: String, target: String) -> Error:
	return DirAccess.rename_absolute(source, target)

func _exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)

func _is_link(path: String) -> bool:
	var parent := DirAccess.open(path.get_base_dir())
	return parent != null and parent.is_link(path.get_file())

## Only internal archive basenames, never caller-supplied paths, are accepted.
func _archive_path(id: String) -> String:
	var pieces := id.split("-")
	if pieces.size() != 3 and pieces.size() != 4:
		return ""
	if (pieces[0] == "slots" and pieces.size() != 3) or (pieces[0] == "slot" and pieces.size() != 4) or pieces[0] not in ["slot", "slots"]:
		return ""
	for piece in pieces.slice(1):
		if piece.is_empty(): return ""
		for character in piece:
			if character < "0" or character > "9": return ""
	return directory.path_join(".deleted").path_join(id)

## Read-only inventory, including corrupt archives for diagnostics, never repairs.
## Both pre-existing slot-* archives and the new batch slots-* format are read.
func list_archives() -> Dictionary:
	if campaign == null:
		return Codec._fail("Configure a campaign before listing archives")
	var archive_root := directory.path_join(".deleted")
	if _is_link(archive_root) or FileAccess.file_exists(archive_root):
		return Codec._fail("Archive directory is unavailable")
	if not DirAccess.dir_exists_absolute(archive_root):
		return {"ok": true, "archives": [], "ignored": []}
	var root := DirAccess.open(archive_root)
	if root == null:
		return Codec._fail("Cannot read archives")
	root.include_hidden = true
	var archives: Array = []
	var ignored: Array = Array(root.get_files())
	for id in root.get_directories():
		var path := _archive_path(id)
		if path.is_empty() or root.is_link(id):
			ignored.append(id)
			continue
		var inspected := _inspect_archive(id)
		if not inspected.ok:
			return inspected
		archives.append(inspected.archive)
	return {"ok": true, "archives": archives, "ignored": ignored}

func _inspect_archive(id: String) -> Dictionary:
	var path := _archive_path(id)
	if path.is_empty() or _is_link(directory.path_join(".deleted")) or _is_link(path):
		return Codec._fail("Invalid archive identifier or linked archive")
	var folder := DirAccess.open(path)
	if folder == null:
		return Codec._fail("Cannot read selected archive")
	folder.include_hidden = true
	var ids := {}
	var ignored: Array = Array(folder.get_directories())
	for filename in folder.get_files():
		var slot := _slot_from_name(filename)
		if slot > 0 and not filename.ends_with(".reserved"):
			ids[slot] = true
		else:
			ignored.append(filename)
	var sorted_ids: Array = ids.keys()
	sorted_ids.sort()
	var entries: Array = []
	for slot in sorted_ids:
		entries.append(_inspect_at(slot, path))
	return {"ok": true, "archive": {"id": id, "path": path, "entries": entries, "ignored": ignored}}

## Added native safety feature, not a Unity parity claim. Keeps the archive intact
## and allocates fresh storage; never loads into or changes the live campaign.
func restore_archive(id: String, archived_slot: int) -> Dictionary:
	if campaign == null or slot_path(archived_slot).is_empty():
		return Codec._fail("Invalid slot or unconfigured campaign")
	var inspected := _inspect_archive(id)
	if not inspected.ok:
		return inspected
	var entry: Dictionary = {}
	for candidate in inspected.archive.entries:
		if candidate.slot == archived_slot:
			entry = candidate
	if entry.is_empty() or not entry.valid:
		return Codec._fail("Selected archive has no valid primary or backup for this slot")
	var read := Codec._read(entry.selected_path)
	if not read.ok:
		return read
	if not read.snapshot is Dictionary or read.snapshot.get("format") != Campaign.FORMAT or read.snapshot.get("slot_number") != archived_slot:
		return Codec._fail("Archived filename/header slot mismatch")
	var candidate = campaign._temporary(campaign.current_scene)
	var restored: Dictionary = candidate.campaign.restore(read.snapshot)
	if not restored.ok:
		return restored
	var store = get_script().new()
	store.configure(candidate.campaign, directory)
	var created: Dictionary = store.create_slot()
	if created.ok:
		created["archive"] = inspected.archive.path
		created["source_slot"] = archived_slot
		created["recovered"] = entry.recovered
	return created
