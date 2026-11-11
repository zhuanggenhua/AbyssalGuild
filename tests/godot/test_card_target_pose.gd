extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Equipment = preload("res://scripts/model/equipment_system.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func make():
	var catalog := Catalog.new()
	var rows: Array = []
	for item in [["base",1,0],["hero",2,1],["mob",9,2],["food",3,0],["gear",5,0],["coin",7,0]]:
		rows.append({"guid": item[0], "script_class": "CardDefinition", "fields": {"id": item[0], "category": item[1], "faction": item[2], "maxHealth": 15, "nutrition": 2, "attackRadius": 0.1, "aggroRadius": 5, "equipmentSlot": 0}})
	catalog.configure({"cards": rows, "settings": [
		{"guid": "wrong", "script_class": "CardSettings", "fields": {"stackStep": {"z": -9}}},
		{"guid": "settings", "script_class": "CardSettings", "fields": {"stackStep": {"x": 0, "y": 0.002, "z": -0.18}, "hungerPerCharacter": 2}}],
		"scenes": [{"name": "Main", "documents": [{"script_class": "CardManager", "fields": {"cardSettings": {"guid": "settings"}, "defaultSpawnCards": []}}, {"script_class": "TradeManager", "fields": {"currencyCard": {"guid": "coin"}}}]}]})
	var session := Session.new()
	session.configure(catalog, 55)
	return session
func group(session, root: Vector2, names: Array) -> Array:
	var ids: Array = []
	var stack_id := -1
	for name in names:
		var id: int = session.spawn_card(name, root, stack_id)
		ids.append(id)
		stack_id = session.cards[id].stack_id
	return ids
func _init() -> void:
	var session = make()
	var ids := group(session, Vector2(2, 3), ["base", "base", "hero"])
	var state_before := Codec.capture(session)
	check(session.card_target_position_3d(ids[2]).is_equal_approx(Vector3(2, 0.004, 2.64)), "Active scene settings override first catalog settings")
	check(session.card_target_position(ids[0]) == Vector2(2, 3), "Index zero remains root")
	check(session.cards[ids[2]].position == Vector2(2, 3), "Stored member positions not rewritten")
	check(Codec.capture(session) == state_before, "Accessor does not mutate serialized state")
	check(session.card_target_position(-99) == Vector2.ZERO, "Missing accessor ID returns zero")
	check(session.capture_card_targets([ids[0], -99]).keys() == [ids[0]], "Batch snapshot omits missing IDs")
	var restored = make()
	check(Codec.restore(restored, state_before).ok, "Legacy root-valued card positions restore")
	check(Codec.capture(restored) == state_before, "Legacy save roundtrip unchanged")
	check(restored.card_target_position(ids[2]).is_equal_approx(Vector2(2, 2.64)), "Legacy save derives correct settled pose")
	# Existing independent position must remain authoritative when membership ends.
	Equipment.detach(session, ids[2], session.card_target_position(ids[2]))
	check(session.cards[ids[2]].position.is_equal_approx(Vector2(2, 2.64)), "Individual detach preserves settled target")
	check(session.card_target_position_3d(ids[2]).is_equal_approx(Vector3(2, 0, 2.64)), "Independent pose falls back to stored XZ")
	Equipment.return_to_board(session, ids[2])
	check(session.stacks[session.cards[ids[2]].stack_id].position.is_equal_approx(Vector2(2, 2.64)), "Independent singleton starts at detached target")
	var batch := session.capture_card_targets(ids.slice(0, 2))
	for id in ids.slice(0, 2): Equipment.detach(session, id, batch[id])
	check(session.cards[ids[1]].position.is_equal_approx(Vector2(2, 2.82)), "Snapshot before batch removal prevents index collapse")
	state_before = Codec.capture(session)
	# Detached cards must be registered or assigned to combat/equipment for valid saves.
	for id in ids: Equipment.return_to_board(session, id)
	state_before = Codec.capture(session)
	check(Codec.restore(restored, state_before).ok and Codec.capture(restored) == state_before, "Detached then returned positions survive save roundtrip")

	session = make()
	ids = group(session, Vector2.ZERO, ["base", "base", "base", "base", "hero"])
	var near_visible: int = session.spawn_card("food", Vector2(0, -0.7))
	var near_root: int = session.spawn_card("food", Vector2(0, 0.1))
	session.end_day()
	check(not session.cards.has(near_visible) and session.cards.has(near_root), "Feeding chooses food nearest actual stack member, not root")
	check(session.cards.has(ids[4]) and session.phase == "ready", "Feeding completes without changing phase semantics")

	session = make()
	ids = group(session, Vector2.ZERO, ["base", "base", "base", "base", "hero"])
	var other: int = session.spawn_card("hero", Vector2(0, -0.5))
	var mob: int = session.spawn_card("mob", Vector2(0, -0.7))
	var intent: Dictionary = session.world.aggressive_intent(mob)
	check(intent.card_id == ids[4] and intent.action == "attack_player", "AI chooses visible member over closer-root competitor")
	check(intent.position.is_equal_approx(Vector2(0, -0.72)), "AI intent carries target member coordinate")
	session.ai._detach(ids[4])
	check(session.stacks[session.cards[ids[4]].stack_id].position.is_equal_approx(Vector2(0, -0.72)), "AI detach does not jump to former root")
	check(session.stacks[session.cards[ids[0]].stack_id].card_ids.size() == 4, "AI detach preserves remaining group")
	# Normal source spawn roots remain unchanged; explicit target position caller owns root.
	check(session.cards[other].position == Vector2(0, -0.5), "Unrelated singleton unaffected")
	var gear_ids := group(session, Vector2(3, 4), ["base", "gear"])
	check(session.equipment.equip(other, gear_ids[1]), "Equipment individual detach path works")
	session.equipment.unequip(other, 0)
	check(session.card_target_position(gear_ids[1]) == session.card_target_position(other), "Unequip uses wearer's settled pose")

	# Production reads the producer member pose without mutating its stack root.
	session = make()
	session.catalog.fields("mob").produceCard = {"guid": "food"}
	session.catalog.fields("mob").produceInterval = 1
	ids = group(session, Vector2(4, 5), ["base", "mob"])
	session.world.production_timers[ids[1]] = 0.1
	var produced: Array = session.world.tick_production(0.2)
	check(produced.size() == 1 and session.cards[produced[0]].position.is_equal_approx(Vector2(4, 4.82)), "World production uses settled producer pose")
	var positions: Array = []
	session.ai.agents[ids[1]] = {"running": true}
	session.ai.produce_spawner = func(_guid, point, _ignored): positions.append(point)
	session.world.production_timers[ids[1]] = 0.1
	session.ai._tick_production(0.2)
	check(positions.size() == 1 and positions[0].is_equal_approx(Vector2(4, 4.82)), "AI production adapter receives settled producer pose")
	session.ai.produce_spawner = Callable()
	check(session.stacks[session.cards[ids[1]].stack_id].position == Vector2(4, 5), "Production preserves stack root")
	# Pure 3D distance includes stack height, independently of the XZ projection.
	session = make()
	session.catalog.fields("settings").stackStep = {"x": 0.1, "y": 2, "z": -0.2}
	ids = group(session, Vector2.ZERO, ["base", "hero"])
	check(session.card_target_position_3d(ids[1]) == Vector3(0.1, 2, -0.2), "All source step components supported")
	mob = session.spawn_card("mob", Vector2(0.1, -0.2))
	check(session.world.aggressive_intent(mob).action == "approach_player", "AI range includes per-card height, not only planar coincidence")
	# Optional actual source data verification, without changing public test coverage.
	var source := Catalog.new()
	if source.load_file() == OK:
		var live := Session.new()
		live.configure(source, 3)
		ids = group(live, Vector2(1, 2), [source.find_by_name("Wood"), source.find_by_name("Villager")])
		check(live.card_target_position_3d(ids[1]).is_equal_approx(Vector3(1, 0.002, 1.82)), "Imported source card settings")
		var saved := Codec.capture(live)
		var loaded := Session.new()
		loaded.configure(source, 8)
		check(Codec.restore(loaded, saved).ok and loaded.card_target_position(ids[1]).is_equal_approx(Vector2(1, 1.82)), "Source-data save roundtrip derives pose")
	else:
		print("Card target pose: private source checks skipped")
	print("Card target pose: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
