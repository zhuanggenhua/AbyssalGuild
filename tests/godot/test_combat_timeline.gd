extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks: int = 0
var failures: int = 0
var s
var events: Array = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func fresh() -> void:
	var c = Catalog.new()
	c.configure({"cards": [
		{"guid": "p", "script_class": "CardDefinition", "fields": {"id": "p", "category": 2, "faction": 1, "combatType": 1, "maxHealth": 100, "attack": 10, "accuracy": 100, "criticalChance": 0}},
		{"guid": "m", "script_class": "CardDefinition", "fields": {"id": "m", "category": 9, "faction": 2, "maxHealth": 100, "defense": 0, "dodge": 0}},
		{"guid": "gear", "script_class": "CardDefinition", "fields": {"id": "gear", "category": 5, "equipmentSlot": 0, "statModifiers": [{"Stat": 1, "value": 5}]}},
		{"guid": "r", "script_class": "CardDefinition", "fields": {"id": "r", "category": 2, "faction": 1, "combatType": 2}}
	], "scenes": [{"name": "Main", "documents": [{"script_class": "CombatManager", "fields": {"arrowProjectile": {"guid": "arrow"}, "magicProjectile": {"guid": "arrow"}}}]}], "referenced_prefabs": [{"guid": "arrow", "documents": [{"script_class": "CombatProjectile", "fields": {"duration": 0.5}}]}]})
	s = Session.new()
	s.configure(c, 123)
	events.clear()
	s.event_occurred.connect(func(kind: String, payload: Dictionary): events.append({"kind": kind, "payload": payload}))
func pair(player: String = "p") -> Array:
	var p: int = s.spawn_card(player)
	var m: int = s.spawn_card("m")
	var id: int = s.combat.start_combat([p], [m])
	s.combat.tasks[id].progress[p] = 1000.0
	s.combat.tasks[id].progress[m] = 0.0
	return [p, m, id]
func ensure_hit() -> void:
	for seed_value in 100:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		if probe.randf() < 0.9 and probe.randf() > 0.01:
			s.rng.seed = seed_value
			return
func _init() -> void:
	fresh()
	var ids: Array = pair()
	var p: int = ids[0]
	var m: int = ids[1]
	var id: int = ids[2]
	var task: Dictionary = s.combat.tasks[id]
	var before: int = s.rng.state
	var probe := RandomNumberGenerator.new()
	probe.state = before
	probe.randi_range(0, 0)
	s.combat.resolve_turn(id)
	check(s.rng.state == probe.state and s.cards[m].health == 100, "selection draws target only; no hit RNG or health before travel")
	check(task.execution.phase == "travel" and task.execution.remaining == 0.3, "melee travel exact duration")
	check(s.combat.is_attacking(p) and not s.combat.can_drag_combatant(p), "travel actor cannot start drag")
	ensure_hit()
	before = s.rng.state
	s.combat.tick(0.2, 0.1)
	check(s.rng.state == before and task.progress[p] == 1020 and task.progress[m] == 20, "progress accrues during travel without impact RNG")
	check(task.timer == 1.0, "idle turn timer frozen while executing")
	var gear: int = s.spawn_card("gear")
	s.equipment.equip(p, gear)
	s.catalog.definitions.p.fields.combatType = 3
	s.combat.tick(0.0, 0.2)
	check(task.execution.phase == "return" and s.cards[m].health == 85, "paused real-time impact uses late equipped attack stats")
	check(task.execution.combat_type == 1, "animation type remains captured at attack start")
	check(task.progress[p] == 1020, "actor not reset at impact")
	check(s.combat.is_attacking(p) and not s.combat.can_drag_combatant(p), "return actor still cannot start drag")
	before = s.rng.state
	s.combat.tick(0.5, 0.3)
	check(not task.has("execution") and task.progress[p] == 0 and task.progress[m] == 70, "reset after return discards actor execution progress only")
	check(s.rng.state == before and task.timer == 1, "return draws nothing and does not consume idle timer")
	fresh()
	ids = pair("r")
	id = ids[2]
	s.combat.resolve_turn(id)
	check(s.combat.tasks[id].execution.remaining == 0.5 and s.combat.projectile_duration(3) == 0.5, "projectile durations read imported serialized fields")
	s.catalog.data.referenced_prefabs[0].documents[0].fields.erase("duration")
	check(s.combat.projectile_duration(2) == 0.6, "present component missing serialized field uses C# default, not guessed half-second")
	s.catalog.data.referenced_prefabs.clear()
	check(s.combat.projectile_duration(2) == -1, "missing projectile is not silently assigned a default delay")
	s.combat.tasks[id].erase("execution")
	s.combat.resolve_turn(id)
	check(not s.combat.tasks[id].has("execution") and events.back().kind == "combat_attack_blocked", "missing projectile blocks attack without fake impact")
	# Lethal hit remains a registered zero-health card during return.
	fresh()
	ids = pair()
	p = ids[0]; m = ids[1]; id = ids[2]
	s.cards[m].health = 1
	s.combat.resolve_turn(id)
	ensure_hit()
	s.combat.tick(0.1, 0.3)
	task = s.combat.tasks[id]
	check(s.cards.has(m) and s.cards[m].health == 0 and s.combat.membership.has(m), "lethal damage does not kill before return")
	var dead_progress: float = task.progress[m]
	s.combat.tick(0.2, 0.1)
	check(task.progress[m] == dead_progress and task.progress[p] > 1000, "zero-health victim guard, living actor still progresses")
	s.combat.tick(0, 0.2)
	check(not s.cards.has(m) and task.execution.phase == "death_wait" and s.combat.tasks.has(id), "kill after return; last enemy does not end before death wait")
	check(not s.combat.is_attacking(p) and s.combat.can_drag_combatant(p), "actor drag flag clears before scaled death wait")
	before = s.rng.state
	s.combat.tick(0, 5)
	check(task.execution.remaining == 0.5 and s.combat.tasks.has(id), "scaled death wait stops while paused")
	var saved: Dictionary = Codec.capture(s)
	var restored = Session.new()
	restored.configure(s.catalog, 999)
	var outcome: Dictionary = Codec.restore(restored, JSON.parse_string(JSON.stringify(saved)))
	if not outcome.ok: print(outcome)
	check(outcome.ok, "atomic full codec accepts death-wait empty enemy side")
	if outcome.ok:
		restored.combat.tick(0.5, 0)
		check(restored.combat.tasks.is_empty() and restored.stacks.has(restored.cards[p].stack_id), "restored lethal wait completes and returns survivor")
	s.combat.tick(0.5, 0)
	check(s.combat.tasks.is_empty() and s.rng.state == before, "scaled completion ends without extra combat draws")
	_test_snapshots()
	_test_order_and_cancel()
	_test_positions()
	_test_lethal_merge_save()
	_test_private_projectiles()
	print("Combat timeline checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
func _test_snapshots() -> void:
	fresh()
	var ids: Array = pair()
	s.combat.resolve_turn(ids[2])
	ensure_hit()
	s.combat.tick(0, 0.1)
	s.paused = true
	var snapshot: Dictionary = Codec.capture(s)
	var restored = Session.new()
	restored.configure(s.catalog)
	var outcome: Dictionary = Codec.restore(restored, JSON.parse_string(JSON.stringify(snapshot)))
	if not outcome.ok: print(outcome)
	check(outcome.ok and restored.paused, "paused mid-travel snapshot restores")
	if outcome.ok:
		s.tick(0.2)
		restored.tick(0.2)
		check(Codec.capture(s) == Codec.capture(restored), "paused resumed impact keeps RNG/health/timing deterministic")
		var return_save: Dictionary = Codec.capture(s)
		check(Codec.restore(restored, return_save).ok, "mid-return snapshot restores without reapplying hit")
		var hp: int = restored.cards[ids[1]].health
		restored.tick(0.3)
		check(restored.cards[ids[1]].health == hp, "restored return does not reroll or damage twice")
	for key in ["actor", "target", "remaining", "phase", "attacker_position"]:
		var corrupt: Dictionary = snapshot.duplicate(true)
		corrupt.session.combat.tasks[0].execution[key] = {} if key != "phase" else "bogus"
		var before: Dictionary = Codec.capture(restored)
		check(not Codec.restore(restored, corrupt).ok and Codec.capture(restored) == before, "corrupt execution rejected atomically: " + key)
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.session.combat.tasks[0].erase("execution")
	check(Codec.restore(restored, legacy).ok and not restored.combat.tasks[ids[2]].has("execution"), "legacy idle combat save still loads")
func _test_order_and_cancel() -> void:
	fresh()
	var first: Array = pair()
	var second: Array = pair()
	var extra_first: int = s.spawn_card("m")
	var extra_second: int = s.spawn_card("m")
	s.combat.add_combatants(first[2], [extra_first])
	s.combat.add_combatants(second[2], [extra_second])
	var sequence := RandomNumberGenerator.new()
	sequence.state = s.rng.state
	var expected_second: int = [second[1], extra_second][sequence.randi_range(0, 1)]
	var expected_first: int = [first[1], extra_first][sequence.randi_range(0, 1)]
	s.combat.tick(1, 1)
	var started: Array = []
	var targets: Array = []
	for event in events:
		if event.kind == "combat_attack_started":
			started.append(event.payload.combat_id)
			targets.append(event.payload.defender_id)
	check(started == [second[2], first[2]], "manager updates newest task first")
	check(targets == [expected_second, expected_first] and s.rng.state == sequence.state, "concurrent target RNG follows reverse registration order")
	var rng_before: int = s.rng.state
	var merged: int = s.combat.merge_combats([first[2], second[2]])
	check(merged > 0 and not s.combat.tasks[merged].has("execution"), "merge cancels in-flight attacks without future impact")
	var extra: int = s.spawn_card("p")
	s.combat.add_combatants(merged, [extra])
	s.combat.tasks[merged].progress[first[0]] = 1e6
	s.combat.resolve_turn(merged)
	var target: int = s.combat.tasks[merged].execution.target
	s.kill_card(target)
	check(not s.combat.tasks[merged].has("execution"), "external target removal cancels dangling attack safely")
	s.combat.tasks[merged].progress[first[0]] = 1e6
	s.combat.resolve_turn(merged)
	check(s.combat.flee(first[0]) and not s.combat.tasks[merged].has("execution"), "actor flee cancels dangling execution while allies remain")
	check(s.rng.state != rng_before, "merge/turns still consume their documented initialization/selection RNG")
func _test_positions() -> void:
	fresh()
	var p: int = s.spawn_card("p", Vector2(2, 3))
	var p2: int = s.spawn_card("p", Vector2.ZERO, s.cards[p].stack_id)
	var p3: int = s.spawn_card("p", Vector2.ZERO, s.cards[p].stack_id)
	var m: int = s.spawn_card("m", Vector2(4, 3))
	var expected: Dictionary = s.capture_card_targets([p, p2, p3, m])
	var id: int = s.combat.start_combat([p, p2, p3], [m])
	check(s.cards[p2].position == expected[p2] and s.cards[p3].position == expected[p3], "creation captures full stack targets before any detach shifts indices")
	var a: int = s.spawn_card("p", Vector2(6, 7))
	var b: int = s.spawn_card("p", Vector2.ZERO, s.cards[a].stack_id)
	expected = s.capture_card_targets([a, b])
	s.combat.add_combatants(id, [a, b])
	check(s.cards[b].position == expected[b], "join captures all entrant poses before detach")

func _test_lethal_merge_save() -> void:
	fresh()
	var first: Array = pair()
	var second: Array = pair()
	s.cards[first[1]].health = 1
	s.combat.resolve_turn(first[2])
	ensure_hit()
	s.combat.tick(0, 0.3)
	check(s.cards[first[1]].health == 0, "lethal return victim prepared for merge")
	var merged: int = s.combat.merge_combats([first[2], second[2]])
	check(s.cards.has(first[1]) and s.combat.membership[first[1]] == merged and not s.combat.tasks[merged].has("execution"), "source merge preserves pending zero-health member and cancels return")
	s.combat.tasks[merged].progress[first[1]] = 1000.0
	s.combat.resolve_turn(merged)
	check(s.combat.tasks[merged].execution.actor == first[1], "preserved zero-health member can act from initial progress after merge")
	var restored = Session.new()
	restored.configure(s.catalog)
	check(Codec.restore(restored, Codec.capture(s)).ok, "native legal zero-health merged actor snapshot remains loadable")

func _test_private_projectiles() -> void:
	if not FileAccess.file_exists("res://data/stackcraft.json"):
		print("SKIP: private Main/Island projectile reference and execution checks (source data unavailable)")
		return
	var catalog = Catalog.new()
	check(catalog.load_file() == OK, "private source catalog loads for projectile lookup")
	var player_guids: Dictionary = {}
	var mob: String = ""
	for entry in catalog.data.get("cards", []):
		var fields: Dictionary = entry.get("fields", {})
		var kind: int = int(fields.get("combatType", 0))
		if int(fields.get("category", 0)) == 2 and int(fields.get("faction", 0)) == 1 and kind in [2, 3]:
			player_guids[kind] = str(entry.guid)
		if int(fields.get("category", 0)) == 9 and int(fields.get("faction", 0)) == 2:
			mob = str(entry.guid)
	check(player_guids.has(2) and player_guids.has(3) and not mob.is_empty(), "private catalog has ranged/magic and enemy combatants")
	if not player_guids.has(2) or not player_guids.has(3) or mob.is_empty():
		return
	for scene_name in ["Main", "Island"]:
		for kind in [2, 3]:
			var live = Session.new()
			live.configure(catalog, 32, scene_name)
			check(live.combat.projectile_duration(kind) == 0.5, "private scene projectile reference resolves serialized duration")
			var actor: int = live.spawn_card(player_guids[kind])
			var target: int = live.spawn_card(mob)
			var task_id: int = live.combat.start_combat([actor], [target])
			live.combat.tasks[task_id].progress[actor] = 10000.0
			live.combat.resolve_turn(task_id)
			live.combat.tick(0, 0.49)
			check(live.combat.tasks[task_id].execution.phase == "travel", "private projectile remains in travel before half second")
			live.combat.tick(0, 0.02)
			check(live.combat.tasks[task_id].execution.phase == "return", "private projectile reaches impact then return after half second")
