extends SceneTree
## Production cold-entry calls, headless integration only. Optional real saves
## are read-only inputs copied to an isolated user:// slot before any operation.
const Board = preload("res://scripts/ui/board.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Slots = preload("res://scripts/model/save_slots.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const Admission = preload("res://scripts/ui/source_restore_admission.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_kind: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
var serial := 0
var phases: Array = []
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func _init(): call_deferred("run")
func normalized(session) -> Dictionary:
	var data: Dictionary = session.campaign.capture().duplicate(true)
	data.erase("last_saved")
	var active: Dictionary = data.scenes[session.scene_name].session
	for card in active.cards: card.erase("position")
	for stack in active.stacks: stack.erase("position")
	active.stacks.sort_custom(func(a, b): return a.id < b.id)
	return data
func targets(session) -> Array:
	var result: Array = []
	for stack in session.stacks.values(): result.append({"id": stack.id, "cards": stack.card_ids.duplicate(), "position": stack.position})
	return result
func slot_root() -> String:
	serial += 1
	return "user://restore-board-%d-%d" % [Time.get_ticks_usec(), serial]
func fixture(board, scene: String, kind: String):
	var s = Session.new(); s.configure(board.catalog, 912, scene); s.paused = true
	var wood: int = s.spawn_card(board.catalog.find_by_name("Wood"), Vector2(-5.55, 0), -1, {"refuse_attach": true})
	if kind == "multi": s.spawn_card(board.catalog.find_by_name("Wood"), Vector2(-5.55, 0), s.cards[wood].stack_id)
	s.spawn_card(board.catalog.find_by_name("Stone"), Vector2(-5.0, 0.1), -1, {"refuse_attach": true})
	if kind == "equipped":
		s.spawn_card(board.catalog.find_by_name("Stone"), Vector2.ZERO, -1, {"refuse_attach": true})
		var owner: int = s.spawn_card(board.catalog.find_by_name("Villager"), Vector2(3, 1), -1, {"refuse_attach": true})
		for name in ["Sword", "Chainmail", "Vitality Amulet"]:
			var item: int = s.spawn_card(board.catalog.find_by_name(name), Vector2(4, 2), -1, {"refuse_attach": true})
			check(s.equipment.equip(owner, item), "fixture equips " + name)
		s.cards[owner].health = 7
	return s
func load_sequence(board, path: String, label: String):
	var before_bytes := FileAccess.get_file_as_bytes(path)
	var model = Session.new(); model.configure(board.catalog)
	var loaded: Dictionary = model.campaign.load_file(path)
	check(loaded.ok, label + " pure model load")
	if not loaded.ok: return
	var expected := normalized(model)
	board.slot_root = path.get_base_dir()
	board.selected_slot = 1
	board._continue_game()
	check(board.running and board.active_slot == 1, label + " production Continue admits actual slot")
	check(board.source_restore_report.get("ok", false), label + " cold source schedule applied")
	check(normalized(board.session) == expected, label + " IDs/data/RNG/quests/equipment/inactive scene unchanged")
	check(FileAccess.get_file_as_bytes(path) == before_bytes, label + " Continue never writes input slot")
	var entry_targets := targets(board.session)
	for i in 4: board._sync_views(0.0)
	check(targets(board.session) == entry_targets, label + " subsequent entry view frames do not re-run solver")
	check(board.source_restore_entry.is_empty() and board.layout_key == board._layout_signature(), label + " one-shot entry consumed and signature initialized")
	check(board._save_active_slot().ok, label + " normal production save to private copy")
	var saved = Session.new(); saved.configure(board.catalog)
	check(saved.campaign.load_file(path).ok and normalized(saved) == expected, label + " pure re-read retains all nongeometry state")
	var serialized_targets := targets(saved)
	check(serialized_targets == entry_targets, label + " saved exact source target positions")
	board._continue_game()
	check(board.source_restore_report.get("ok", false) and normalized(board.session) == expected, label + " second production Continue remains valid")
	var second_targets := targets(board.session)
	for i in 4: board._sync_views(0.0)
	check(targets(board.session) == second_targets, label + " second entry does not repeat placement each frame")
	phases.append({"case": label, "scene": board.session.scene_name, "cards": board.session.cards.size(), "first_targets": entry_targets, "second_targets": second_targets})
func run():
	var board = Board.new()
	board.feedback.free(); board.feedback = SilentFeedback.new()
	board.slot_root = slot_root(); board.options_path = "user://restore-options.json"; board.legacy_paths.clear()
	root.add_child(board); await process_frame; board.set_process(false)
	check(board.data_error == OK, "source data present")
	if board.data_error != OK: board.queue_free(); await process_frame; quit(1); return
	var empty_session = board.session
	board.selected_slot = 0; board._continue_game()
	check(board.session == empty_session and not board.running, "empty selection keeps original path")
	for scene in ["Main", "Island"]:
		for kind in ["single", "multi", "equipped"]:
			var s = fixture(board, scene, kind)
			var slots = Slots.new(); slots.configure(s.campaign, slot_root())
			var created: Dictionary = slots.create_slot()
			check(created.ok and created.slot == 1, scene + " " + kind + " private fixture saved")
			if not created.ok: continue
			load_sequence(board, slots.slot_path(1), scene + " " + kind)
	for variable in ["SOURCE_RESTORE_REAL_MAIN", "SOURCE_RESTORE_REAL_ISLAND"]:
		var original := OS.get_environment(variable)
		if original.is_empty(): continue
		var hash_before := FileAccess.get_sha256(original)
		var directory := slot_root()
		DirAccess.make_dir_recursive_absolute(directory)
		var path := directory.path_join("SaveSlot001.json")
		var copy := FileAccess.open(path, FileAccess.WRITE); copy.store_buffer(FileAccess.get_file_as_bytes(original)); copy.close()
		load_sequence(board, path, variable)
		check(FileAccess.get_sha256(original) == hash_before, variable + " original remains unchanged")
	var expected_phases: int = 6 + int(not OS.get_environment("SOURCE_RESTORE_REAL_MAIN").is_empty()) + int(not OS.get_environment("SOURCE_RESTORE_REAL_ISLAND").is_empty())
	check(phases.size() == expected_phases, "all requested cold sequences completed")
	var fallback_session = fixture(board, "Main", "single")
	var fallback_slots = Slots.new(); fallback_slots.configure(fallback_session.campaign, slot_root())
	check(fallback_slots.create_slot().ok, "fallback fixture uses normal slot creation")
	board.session = fallback_session; board.source_restore_entry = ""; board._enter_game(); board._sync_views(0.0)
	var old_entry_targets := targets(board.session)
	var source_metadata: Dictionary = board.catalog.data.duplicate(true)
	board.catalog.data["referenced_prefabs"] = []
	board.slot_root = fallback_slots.directory; board.selected_slot = 1
	var fallback_bytes := FileAccess.get_file_as_bytes(fallback_slots.slot_path(1))
	board._continue_game(); board._sync_views(0.0)
	check(not board.source_restore_report.get("ok", true) and targets(board.session) == old_entry_targets, "missing metadata falls back as whole group to unchanged prior entry path")
	check(FileAccess.get_file_as_bytes(fallback_slots.slot_path(1)) == fallback_bytes, "fallback does not rewrite slot")
	board.catalog.data = source_metadata
	for mutation in ["null_panel", "missing_panel", "wrong_target", "unknown_target", "wrong_owner_root", "null_owner_fields"]:
		var altered: Dictionary = source_metadata.duplicate(true)
		for prefab in altered.referenced_prefabs:
			for document in prefab.documents:
				if document.get("script_class", "") != "CardEquipper": continue
				match mutation:
					"null_panel": document.fields.equipmentPanel = {"fileID": "0"}
					"missing_panel": document.fields.erase("equipmentPanel")
					"wrong_target": document.fields.equipmentPanel = {"fileID": document.file_id}
					"unknown_target": document.fields.equipmentPanel = {"fileID": "999999999"}
					"wrong_owner_root": document.fields.m_GameObject = {"fileID": "999999999"}
					"null_owner_fields": document.fields = null
		board.catalog.data = altered
		var unchanged := Codec.capture(board.session)
		check(not Admission.plan(board).ok and Codec.capture(board.session) == unchanged, mutation + " rejects whole plan without partial placement")
	board.catalog.data = source_metadata
	var live = board.session
	var state := Codec.capture(live)
	var old_root: String = board.slot_root
	board.slot_root = slot_root()
	DirAccess.make_dir_recursive_absolute(board.slot_root)
	var invalid_path: String = board.slot_root.path_join("SaveSlot001.json")
	var bad := FileAccess.open(invalid_path, FileAccess.WRITE); bad.store_string("invalid save evidence"); bad.close()
	board.selected_slot = 1; board._continue_game()
	check(board.session == live and Codec.capture(live) == state and FileAccess.get_file_as_string(invalid_path) == "invalid save evidence", "invalid slot unchanged, prior live session preserved")
	board.slot_root = old_root
	var source: Dictionary = board.catalog.data.duplicate(true)
	board.catalog.data["referenced_prefabs"] = []
	var unsupported := Admission.plan(board)
	check(not unsupported.ok and Codec.capture(board.session) == state, "missing source metadata rejects whole plan, no partial placement")
	board.catalog.data = source
	# No source cold marker at ordinary _enter_game or travel; do not silently
	# change traveler random admission or existing deserialization behavior.
	board._enter_game()
	check(board.source_restore_report.is_empty(), "ordinary scene entry is not relabeled as cold restore")
	var rejected_factory = Board.new()
	rejected_factory.catalog = board.catalog
	rejected_factory.session.configure(board.catalog)
	var aggressive := ""
	for definition in board.catalog.data.cards:
		if definition.fields.get("isAggressive", false): aggressive = definition.guid; break
	check(not aggressive.is_empty(), "real aggressive source definition available for rejection guard")
	if not aggressive.is_empty():
		rejected_factory.session.spawn_card(aggressive)
		rejected_factory.session.friendly_mode = true # Deliberately invalid-for-source test state, not a saved game edit.
		var unchanged := Codec.capture(rejected_factory.session)
		check(not Admission.plan(rejected_factory).ok and Codec.capture(rejected_factory.session) == unchanged, "source friendly factory rejection does not fabricate a restored card")
	rejected_factory.feedback.free(); rejected_factory.vendor_unlock.free(); rejected_factory.free()
	board.queue_free(); await process_frame; await process_frame
	var report := {"checks": checks, "failures": failures, "phases": phases, "scope": "Production Board Continue/save/re-read sequence under headless engine; no GUI or Unity execution"}
	var output := OS.get_environment("SOURCE_RESTORE_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE); file.store_string(JSON.stringify(report, "  ", true, true)); file.close()
	print("Source restore board: ", checks, " checks, ", failures, " failures; headless production calls only")
	quit(1 if failures else 0)
