extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func fresh(catalog = null, scene_name: String = "Main"):
	if catalog == null:
		catalog = Catalog.new()
		catalog.configure({"cards": [
			{"guid": "p", "script_class": "CardDefinition", "fields": {"id": "p", "category": 2, "faction": 1, "combatType": 1}},
			{"guid": "m", "script_class": "CardDefinition", "fields": {"id": "m", "category": 9, "faction": 2, "combatType": 1}}
		]})
	var s = Session.new()
	s.configure(catalog, 42, scene_name)
	return s
func fixture(s, player: String = "p", mob: String = "m") -> Array:
	var p: int = s.spawn_card(player)
	var m: int = s.spawn_card(mob)
	var later: int = s.spawn_card(player)
	var id: int = s.combat.start_combat([p], [m])
	check(s.combat.add_combatants(id, [later]), "late attacker joins")
	return [p, m, later, id]
func tied_actor(s, ids: Array) -> int:
	var task: Dictionary = s.combat.tasks[ids[3]]
	task.erase("execution")
	task.progress[ids[0]] = 0.0
	task.progress[ids[1]] = 100.0
	task.progress[ids[2]] = 100.0
	s.combat.resolve_turn(ids[3])
	return int(task.execution.actor)
func _init() -> void:
	var s = fresh()
	var ids := fixture(s)
	var task: Dictionary = s.combat.tasks[ids[3]]
	check(task.combatants == ids.slice(0, 3), "historical join order crosses factions")
	check(tied_actor(s, ids) == ids[1], "earlier defender wins progress tie over late attacker")
	task.erase("execution")
	s.combat.dragged[ids[1]] = true
	check(tied_actor(s, ids) == ids[2], "dragged earlier actor is skipped without reordering")
	s.combat.dragged.clear()
	task.erase("execution")
	var snapshot: Dictionary = Codec.capture(s)
	var restored = fresh(s.catalog)
	check(Codec.restore(restored, JSON.parse_string(JSON.stringify(snapshot))).ok, "order survives JSON checkpoint")
	check(restored.combat.tasks[ids[3]].combatants == ids.slice(0, 3), "restored interleaved join order retained")
	check(tied_actor(restored, ids) == ids[1], "restored tie chooses historical defender")
	var before: Dictionary = Codec.capture(restored)
	var malformed: Array = [null, "order", [], [ids[0], ids[1]], [ids[0], ids[1], ids[1]], [ids[0], ids[1], 9999], [ids[0], ids[1], true], [ids[0], ids[1], 1.5], [ids[0], ids[1], ids[2], ids[2]]]
	for order in malformed:
		var bad: Dictionary = snapshot.duplicate(true)
		bad.session.combat.tasks[0].combatants = order
		check(not Codec.restore(restored, bad).ok, "invalid explicit order rejected: " + str(order))
		check(Codec.capture(restored) == before, "invalid explicit order preserves entire state and RNG")
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.session.combat.tasks[0].erase("combatants")
	check(Codec.restore(restored, legacy).ok, "legacy combat snapshot accepted")
	check(restored.combat.tasks[ids[3]].combatants == [ids[0], ids[2], ids[1]], "legacy fallback uses previous grouped order")
	check(tied_actor(restored, ids) == ids[2], "legacy does not invent unavailable join history")
	check(Codec.capture(restored).session.combat.tasks[0].combatants == [ids[0], ids[2], ids[1]], "legacy resave persists fallback explicitly")
	# Nonterminal fleeing removes the old slot; rejoining appends at the tail.
	s.combat.flee(ids[0])
	check(task.combatants == [ids[1], ids[2]], "flee removes historical slot")
	s.combat.add_combatants(ids[3], [ids[0], ids[0]])
	check(task.combatants == [ids[1], ids[2], ids[0]], "rejoin appended once, duplicate addition ignored")
	s.combat.remove_combatant(ids[2])
	check(task.combatants == [ids[1], ids[0]], "external removal preserves remaining order")
	# Merge constructs a fresh source faction-grouped list, not concatenated history.
	var extra: int = s.spawn_card("m")
	var player: int = s.spawn_card("p")
	var other: int = s.combat.start_combat([player], [extra])
	var merged: int = s.combat.merge_combats([ids[3], other])
	var merged_task: Dictionary = s.combat.tasks[merged]
	check(merged_task.combatants == merged_task.attackers + merged_task.defenders, "merge starts fresh faction-grouped source order")
	# Lethal cleanup removes the dead combatant before the scaled death wait.
	merged_task.progress[player] = 10000.0
	s.combat.resolve_turn(merged)
	var target: int = merged_task.execution.target
	s.cards[target].health = 0
	merged_task.execution.phase = "return"
	merged_task.execution.remaining = 0.0
	s.combat.tick(0.0, 0.1)
	check(target not in merged_task.combatants and target not in merged_task.progress, "death cleanup removes both order and progress")
	check(Codec.restore(fresh(s.catalog), Codec.capture(s)).ok, "post-death order checkpoint validates")
	_test_private()
	print("Combat order checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)
func _test_private() -> void:
	if not FileAccess.file_exists("res://data/stackcraft.json"):
		print("SKIP: private source combat order checks (source data unavailable)")
		return
	var catalog = Catalog.new()
	check(catalog.load_file() == OK, "private catalog loads")
	var player := ""
	var mob := ""
	for entry in catalog.data.get("cards", []):
		var f: Dictionary = entry.get("fields", {})
		if int(f.get("combatType", 0)) not in [0, 1]: continue
		if int(f.get("category", 0)) == 2 and int(f.get("faction", 0)) == 1: player = str(entry.guid)
		if int(f.get("category", 0)) == 9 and int(f.get("faction", 0)) == 2: mob = str(entry.guid)
	check(not player.is_empty() and not mob.is_empty(), "actual melee player and mob available")
	if player.is_empty() or mob.is_empty(): return
	for scene_name in ["Main", "Island"]:
		var s = fresh(catalog, scene_name)
		var ids := fixture(s, player, mob)
		check(tied_actor(s, ids) == ids[1], "actual source cards preserve late-join tie order in " + scene_name)
		var restored = fresh(catalog, scene_name)
		check(Codec.restore(restored, JSON.parse_string(JSON.stringify(Codec.capture(s)))).ok, "actual source in-flight order checkpoint restores")
		check(tied_actor(restored, ids) == ids[1], "actual source tie order survives Continue")
