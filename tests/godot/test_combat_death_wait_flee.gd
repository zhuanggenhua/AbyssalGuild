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
func fresh():
	var c = Catalog.new()
	c.configure({"cards": [
		{"guid": "p", "script_class": "CardDefinition", "fields": {"id": "p", "category": 2, "faction": 1, "combatType": 1, "maxHealth": 100}},
		{"guid": "m", "script_class": "CardDefinition", "fields": {"id": "m", "category": 9, "faction": 2, "combatType": 1, "maxHealth": 100}}
	]})
	var s = Session.new(); s.configure(c, 42)
	return s
func death_wait(s, last_player: bool = false) -> Array:
	var p1: int = s.spawn_card("p")
	var p2: int = s.spawn_card("p")
	var m1: int = s.spawn_card("m")
	var m2: int = s.spawn_card("m")
	var id: int = s.combat.start_combat([p1] if last_player else [p1, p2], [m1, m2])
	var task: Dictionary = s.combat.tasks[id]
	task.progress[p1] = 10000.0
	s.combat.resolve_turn(id)
	s.cards[task.execution.target].health = 0
	task.execution.phase = "return"; task.execution.remaining = 0.0
	s.combat.tick(0.0, 0.01)
	check(task.execution.phase == "death_wait" and task.execution.remaining == 0.5, "lethal return enters half-second scaled wait")
	return [p1, p2, id]
func checkpoint(s):
	var restored = fresh()
	check(Codec.restore(restored, JSON.parse_string(JSON.stringify(Codec.capture(s), "", true, true))).ok, "in-flight checkpoint restores")
	return restored
func _init() -> void:
	var s = fresh(); var ids := death_wait(s); var task: Dictionary = s.combat.tasks[ids[2]]
	check(s.combat.can_drag_combatant(ids[0]), "source clears attacking flag before death wait")
	check(s.combat.flee(ids[0]) and s.combat.tasks.has(ids[2]), "actor can flee while both sides remain")
	check(task.has("execution") and task.execution.actor == ids[0], "flee retains live former actor and death wait")
	s.combat.tick(0.1, 0.1)
	check(is_equal_approx(task.execution.remaining, 0.4) and task.timer == 1.0, "flee does not start idle timer early")
	s.combat.tick(0.0, 100.0)
	check(is_equal_approx(task.execution.remaining, 0.4), "paused real time cannot consume scaled death wait")
	var restored = checkpoint(s)
	check(restored.combat.tasks[ids[2]].execution.actor == ids[0], "board-owned former actor persists")
	for live in [s, restored]: live.combat.tick(0.41, 0.41)
	check(not task.has("execution") and task.timer == 1.0, "wait completion leaves next turn timer unchanged")
	check(Codec.capture(s) == Codec.capture(restored), "board-owned actor checkpoint has identical continuation")
	# Progress is source card-owned: finishing the old coroutine resets a newly joined fight.
	s = fresh(); ids = death_wait(s); task = s.combat.tasks[ids[2]]
	s.combat.flee(ids[0])
	var foe: int = s.spawn_card("m")
	var next: int = s.combat.start_combat([ids[0]], [foe])
	s.combat.tasks[next].progress[ids[0]] = 250.0
	restored = checkpoint(s)
	for live in [s, restored]: live.combat.tick(0.5, 0.5)
	check(s.combat.tasks[next].progress[ids[0]] == 0.0, "old wait resets actor progress in its new combat")
	check(Codec.capture(s) == Codec.capture(restored), "cross-combat former actor reference continues identically")
	# Rejoining the same task also gets reset only when the original delay expires.
	s = fresh(); ids = death_wait(s); task = s.combat.tasks[ids[2]]
	s.combat.flee(ids[0]); s.combat.add_combatants(ids[2], [ids[0]])
	task.progress[ids[0]] = 250.0
	s.combat.tick(0.25, 0.25)
	check(task.progress[ids[0]] > 250.0 and task.has("execution"), "same-task rejoin retains progress until wait ends")
	s.combat.tick(0.25, 0.25)
	check(task.progress[ids[0]] == 0.0 and not task.has("execution"), "same-task rejoin reset on original completion")
	# Last-side removal terminates immediately, just as source EndCombat stops coroutine.
	s = fresh(); ids = death_wait(s, true)
	check(s.combat.flee(ids[0]) and not s.combat.tasks.has(ids[2]), "last attacker flee ends task immediately")
	check(Codec.restore(fresh(), Codec.capture(s)).ok, "terminal flee checkpoint remains valid")
	# Destruction is explicitly safe rather than retaining a dangling former actor.
	s = fresh(); ids = death_wait(s); task = s.combat.tasks[ids[2]]
	s.combat.flee(ids[0]); s.kill_card(ids[0])
	check(task.execution.actor == -1 and task.execution.remaining == 0.5, "destroyed former actor clears reference but preserves wait")
	restored = checkpoint(s)
	for live in [s, restored]: live.combat.tick(0.5, 0.5)
	check(Codec.capture(s) == Codec.capture(restored), "cleared former actor checkpoint safely completes")
	# A death-wait actor destroyed before fleeing also clears safely, while
	# unrelated survivors keep the old wait alive.
	s = fresh(); ids = death_wait(s); task = s.combat.tasks[ids[2]]
	s.kill_card(ids[0])
	check(task.execution.actor == -1 and task.execution.remaining == 0.5, "destroyed participating actor also preserves delay without stale ID")
	check(Codec.restore(fresh(), Codec.capture(s)).ok, "destroyed participating actor checkpoint validates")
	# Reject unknown live references and invalid sentinels, atomically.
	s = fresh(); ids = death_wait(s); s.combat.flee(ids[0])
	var saved: Dictionary = Codec.capture(s)
	var before: Dictionary = Codec.capture(s)
	for invalid_actor in [0, -2, 9999, true, 1.5, "1"]:
		var bad: Dictionary = saved.duplicate(true)
		bad.session.combat.tasks[0].execution.actor = invalid_actor
		check(not Codec.restore(s, bad).ok, "malformed death-wait actor rejected: " + str(invalid_actor))
		check(Codec.capture(s) == before, "malformed actor preserves state and RNG")
	var noncombat: Dictionary = saved.duplicate(true)
	for row in noncombat.session.cards:
		if int(row.id) == ids[0]:
			row.definition_guid = "ordinary"
			row.base_definition_guid = "ordinary"
	s.catalog.definitions["ordinary"] = {"guid": "ordinary", "script_class": "CardDefinition", "fields": {"id": "ordinary", "category": 0, "faction": 0}}
	check(not Codec.restore(s, noncombat).ok, "existing noncombat card cannot masquerade as former actor")
	check(Codec.capture(s) == before, "noncombat actor rejection preserves state and RNG")
	for phase in ["travel", "return"]:
		var bad: Dictionary = saved.duplicate(true)
		bad.session.combat.tasks[0].execution.phase = phase
		bad.session.combat.tasks[0].execution.remaining = 0.1
		bad.session.combat.tasks[0].execution.target = bad.session.combat.tasks[0].defenders[0]
		check(not Codec.restore(s, bad).ok, "former actor reference never allowed during " + phase)
	print("Combat death-wait flee checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)
