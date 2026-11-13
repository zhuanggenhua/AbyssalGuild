extends SceneTree
const Stamp = preload("res://scripts/model/save_timestamp.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Slots = preload("res://scripts/model/save_slots.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const SlotView = preload("res://scripts/ui/source_saved_slot.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		printerr("FAIL: ", label)
		failures += 1
func _init() -> void:
	var catalog = Catalog.new()
	catalog.configure({"scenes": [{"name": "Main", "documents": [{"fields": {"questGroups": [], "defaultSpawnCards": []}}]}]})
	var session = Session.new()
	session.configure(catalog, 52)
	var campaign = session.campaign
	var legacy: Dictionary = campaign.capture()
	check(not legacy.has("last_saved"), "new unsaved campaign unknown")
	var known := {"local": "2024-02-29T23:59:58", "utc_offset_minutes": 330}
	check(Stamp.valid(known), "leap day and half hour offset")
	check(Stamp.describe(known) == "2024-02-29 23:59:58 +05:30", "explicit native local format")
	check(not Stamp.valid({}) and not Stamp.valid({"local": known.local, "utc_offset_minutes": 1.5}), "invalid metadata refused")
	check(not Stamp.valid({"local": "2023-02-29T00:00:00", "utc_offset_minutes": 0}) and not Stamp.valid({"local": "2024-13-01T00:00:00", "utc_offset_minutes": 0}), "impossible dates rejected without normalization")
	var saved := legacy.duplicate(true)
	saved.last_saved = known
	check(campaign.restore(saved).ok and campaign.capture().last_saved == known, "restore/capture preserves original clock")
	var corrupt := saved.duplicate(true)
	corrupt.last_saved = "invented"
	check(not campaign.restore(corrupt).ok and campaign.last_saved == known, "invalid restore transactional")
	check(campaign.restore(legacy).ok and campaign.last_saved.is_empty(), "legacy clears prior timestamp")
	var root := "user://timestamp-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var slots = Slots.new()
	slots.configure(campaign, root)
	check(slots.create_slot().ok, "new write succeeds")
	var first := Codec._read(slots.slot_path(1))
	check(first.ok and Stamp.valid(first.snapshot.last_saved), "clock persisted inside committed JSON")
	var entry: Dictionary = slots.list_slots().slots[0]
	check(entry.saved_timestamp.value == first.snapshot.last_saved, "inventory uses saved field")
	check(SlotView.describe(entry).contains("Last Saved:") and not SlotView.describe(entry).contains("File modified:"), "UI consumes saved field, not mtime")
	check(not campaign.save_file(root.path_join("absent/no.json")).ok and Stamp.describe(campaign.last_saved) == Stamp.describe(first.snapshot.last_saved), "failed write does not advance live timestamp")
	check(slots.save_slot(1).ok, "overwrite preserves backup")
	check(Codec._read(slots.slot_path(1)+".bak").snapshot.last_saved == first.snapshot.last_saved, "backup timestamp unchanged")
	var f = FileAccess.open(slots.slot_path(1), FileAccess.WRITE)
	f.store_string("bad"); f.close()
	entry = slots.list_slots().slots[0]
	check(entry.recovered and entry.saved_timestamp.value == first.snapshot.last_saved, "backup displays its own saved clock")
	f = FileAccess.open(slots.slot_path(1), FileAccess.WRITE)
	f.store_string(JSON.stringify(legacy)); f.close()
	entry = slots.list_slots().slots[0]
	check(entry.valid and not entry.has("saved_timestamp"), "legacy remains unknown despite available mtime")
	for filename in DirAccess.get_files_at(root): DirAccess.remove_absolute(root.path_join(filename))
	DirAccess.remove_absolute(root)
	if failures == 0: print("Persisted save timestamp: PASS (%d checks)" % checks)
	quit(0 if failures == 0 else 1)
