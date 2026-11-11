extends RefCounted
## Source-audited two-clock combat timeline. Rendering and overlap geometry are adapters.
const Equipment = preload("res://scripts/model/equipment_system.gd")
var _session: WeakRef
var equipment
var tasks: Dictionary = {}
var membership: Dictionary = {}
var dragged: Dictionary = {}
var advantage_multiplier: float = 1.5
var disadvantage_multiplier: float = 0.75
var _next_id: int = 1
# Scene adapters own exact geometry; selectors must not mutate combat membership.
var start_overlap_selector: Callable = Callable()
var resize_overlap_selector: Callable = Callable()
var _selecting_geometry: bool = false

func configure(session, equipment_system) -> void:
	_session = weakref(session)
	equipment = equipment_system
	reset()

func reset() -> void:
	tasks.clear()
	membership.clear()
	dragged.clear()
	_next_id = 1

static func advantage(attacker_type: int, defender_type: int) -> int:
	if attacker_type == 0 or defender_type == 0 or attacker_type == defender_type:
		return 0
	return 1 if (attacker_type == 1 and defender_type == 2) or (attacker_type == 2 and defender_type == 3) or (attacker_type == 3 and defender_type == 1) else -1

## Explicit random rolls make edge cases testable without replacing the session RNG.
func resolve_attack(attacker_id: int, defender_id: int, hit_roll: float = -1, crit_roll: float = -1) -> Dictionary:
	var session = _session.get_ref()
	var attacker: Dictionary = equipment.stats(attacker_id)
	var defender: Dictionary = equipment.stats(defender_id)
	if attacker.is_empty() or defender.is_empty():
		return {}
	if hit_roll < 0:
		hit_roll = session.rng.randf()
	var chance: float = clampf((attacker.accuracy - defender.dodge) / 100.0, 0.05, 0.95)
	if hit_roll > chance:
		return {"type": "miss", "damage": 0, "advantage": 0}
	if crit_roll < 0:
		crit_roll = session.rng.randf()
	var critical: bool = crit_roll <= clampf(attacker.criticalChance / 100.0, 0.0, 1.0)
	var edge: int = advantage(int(session.catalog.fields(session.cards[attacker_id].definition_guid).get("combatType", 0)), int(session.catalog.fields(session.cards[defender_id].definition_guid).get("combatType", 0)))
	var damage: int = maxi(1, attacker.attack - defender.defense)
	if edge != 0:
		damage = Equipment.round_even(damage * (advantage_multiplier if edge == 1 else disadvantage_multiplier))
	if critical:
		damage = Equipment.round_even(damage * attacker.criticalMultiplier / 100.0)
	return {"type": "critical" if critical else "normal", "damage": damage, "advantage": edge}

func _valid_new_sides(attackers: Array, defenders: Array, player_is_attacker: bool) -> bool:
	var session = _session.get_ref()
	if attackers.is_empty() or defenders.is_empty():
		return false
	var seen: Dictionary = {}
	for id in attackers + defenders:
		if not Equipment.valid_integer(id, 1) or not session.cards.has(int(id)) or membership.has(int(id)) or seen.has(int(id)):
			return false
		var fields: Dictionary = session.catalog.fields(session.cards[int(id)].definition_guid)
		var expected: int = 1 if ((id in attackers) == player_is_attacker) else 2
		if int(fields.get("faction", 0)) != expected or int(fields.get("category", 0)) not in [2, 9]:
			return false
		seen[int(id)] = true
	return true

## Validate arbitrary selector output before any merge mutation. Preserve task
## registration order, not callback order; repeated IDs are harmless.
func _selected_tasks(raw: Variant, excluded: int = -1) -> Dictionary:
	if not raw is Array:
		return {"ok": false, "ids": []}
	var selected: Dictionary = {}
	for value in raw:
		if not Equipment.valid_integer(value, 1) or not tasks.has(int(value)):
			return {"ok": false, "ids": []}
		if int(value) != excluded:
			selected[int(value)] = true
	var ids: Array = []
	for id in tasks:
		if selected.has(id):
			ids.append(id)
	return {"ok": true, "ids": ids}

func start_combat(attackers: Array, defenders: Array, player_is_attacker: bool = true) -> int:
	if _selecting_geometry or not _valid_new_sides(attackers, defenders, player_is_attacker):
		return -1
	if start_overlap_selector.is_valid():
		_selecting_geometry = true
		var raw = start_overlap_selector.call(attackers.duplicate(), defenders.duplicate())
		_selecting_geometry = false
		var selected: Dictionary = _selected_tasks(raw)
		# The adapter may have observed or removed stale cards; revalidate inputs.
		if not selected.ok or not _valid_new_sides(attackers, defenders, player_is_attacker):
			return -1
		if not selected.ids.is_empty():
			return merge_combats(selected.ids, attackers, defenders)
	return _create_combat(attackers, defenders, player_is_attacker)

## Internal creation never invokes overlap selectors: source merge does not
## recursively merge again, and pre-start merging must not draw progress twice.
func _create_combat(attackers: Array, defenders: Array, player_is_attacker: bool) -> int:
	var session = _session.get_ref()
	var positions: Dictionary = session.capture_card_targets(attackers + defenders)
	var task_id: int = _next_id
	_next_id += 1
	tasks[task_id] = {"attackers": attackers.duplicate(), "defenders": defenders.duplicate(), "player_is_attacker": player_is_attacker, "timer": 1.0, "progress": {}}
	for id in attackers + defenders:
		_enter(task_id, id, positions.get(id))
	session.event_occurred.emit("combat_started", {"combat_id": task_id})
	return task_id

func _enter(task_id: int, card_id: int, position: Variant = null) -> void:
	var session = _session.get_ref()
	Equipment.detach(session, card_id, position)
	membership[card_id] = task_id
	tasks[task_id].progress[card_id] = session.rng.randf_range(0.0, 0.5)

func add_combatants(task_id: int, card_ids: Array) -> bool:
	if _selecting_geometry or not tasks.has(task_id):
		return false
	var session = _session.get_ref()
	var added: bool = false
	var positions: Dictionary = session.capture_card_targets(card_ids)
	for id in card_ids:
		if not Equipment.valid_integer(id, 1) or not session.cards.has(id) or membership.has(id):
			continue
		var faction: int = int(session.catalog.fields(session.cards[id].definition_guid).get("faction", 0))
		if faction not in [1, 2] or int(session.catalog.fields(session.cards[id].definition_guid).get("category", 0)) not in [2, 9]:
			continue
		var side: String = "attackers" if ((faction == 1) == tasks[task_id].player_is_attacker) else "defenders"
		tasks[task_id][side].append(id)
		_enter(task_id, id, positions.get(id))
		added = true
	if added and resize_overlap_selector.is_valid():
		_selecting_geometry = true
		var raw = resize_overlap_selector.call(task_id)
		_selecting_geometry = false
		var selected: Dictionary = _selected_tasks(raw, task_id)
		if tasks.has(task_id) and selected.ok and not selected.ids.is_empty():
			var source: Dictionary = tasks[task_id]
			merge_combats(selected.ids + [task_id], source.attackers, source.defenders)
	return added

## Advance one rendered frame. Real clock drives travel/return even when paused.
## A phase boundary resumes at most once/frame, as with source yielded coroutines.
func tick(delta: float, real_delta: float = -1.0) -> void:
	if real_delta < 0:
		real_delta = delta
	if delta < 0 or real_delta < 0 or (delta == 0 and real_delta == 0):
		return
	var session = _session.get_ref()
	var order: Array = tasks.keys()
	order.reverse() # CombatManager.Update visits newest registered task first.
	for task_id in order:
		if not tasks.has(task_id):
			continue
		var task: Dictionary = tasks[task_id]
		for id in task.attackers + task.defenders:
			if not session.cards.has(id):
				remove_combatant(id, false)
			elif session.cards[id].health > 0: # CardCombatant.AddActionProgress guard.
				task.progress[id] += equipment.stats(id).attackSpeed * delta
		if not tasks.has(task_id):
			continue
		if task.has("execution"):
			var execution: Dictionary = task.execution
			execution.remaining -= delta if execution.phase == "death_wait" else real_delta
			if execution.remaining <= 0:
				match execution.phase:
					"travel": _impact(task_id)
					"return": _after_return(task_id)
					"death_wait": _complete_execution(task_id)
		else:
			task.timer -= delta
			if task.timer <= 0:
				task.timer += 1.0
				resolve_turn(task_id)

func projectile_duration(combat_type: int, scene_name: String = "") -> float:
	var session = _session.get_ref()
	var selected_scene: String = session.scene_name if scene_name.is_empty() else scene_name
	var reference: String = ""
	for scene in session.catalog.data.get("scenes", []):
		if scene.get("name", "") != selected_scene:
			continue
		for document in scene.get("documents", []):
			if document.get("script_class", "") == "CombatManager":
				reference = session.catalog.ref_guid(document.get("fields", {}).get("arrowProjectile" if combat_type == 2 else "magicProjectile", {}))
	for prefab in session.catalog.data.get("referenced_prefabs", []):
		if str(prefab.get("guid", "")) == reference:
			for document in prefab.get("documents", []):
				if document.get("script_class", "") == "CombatProjectile":
					return maxf(0, float(document.get("fields", {}).get("duration", 0.6)))
	return -1.0 # Missing source component is not the C# field-default case.

func resolve_turn(task_id: int) -> void:
	if not tasks.has(task_id) or tasks[task_id].has("execution"):
		return
	var session = _session.get_ref()
	var task: Dictionary = tasks[task_id]
	if task.attackers.is_empty() or task.defenders.is_empty():
		_finish(task_id)
		return
	var actor: int = -1
	var best: float = -INF
	for id in task.attackers + task.defenders:
		if not dragged.get(id, false) and float(task.progress[id]) > best:
			actor = id
			best = task.progress[id]
	if actor < 0:
		return
	var targets: Array = task.defenders if actor in task.attackers else task.attackers
	var target: int = targets[session.rng.randi_range(0, targets.size() - 1)]
	var combat_type: int = int(session.catalog.fields(session.cards[actor].definition_guid).get("combatType", 0))
	var duration: float = 0.3 if combat_type not in [2, 3] else projectile_duration(combat_type)
	if duration < 0:
		# Unity would throw when instantiating its missing prefab. Fail closed,
		# publish a blocker and leave idle rather than invent projectile timing.
		session.event_occurred.emit("combat_attack_blocked", {"combat_id": task_id, "attacker_id": actor, "reason": "Missing scene projectile component"})
		return
	task["execution"] = {"phase": "travel", "remaining": duration, "actor": actor, "target": target, "combat_type": combat_type, "attacker_position": session.cards[actor].position, "defender_position": session.cards[target].position}
	session.event_occurred.emit("combat_attack_started", {"combat_id": task_id, "attacker_id": actor, "defender_id": target, "combat_type": combat_type, "duration": duration, "attacker_position": session.cards[actor].position, "defender_position": session.cards[target].position})

func _impact(task_id: int) -> void:
	if not tasks.has(task_id):
		return
	var session = _session.get_ref()
	var task: Dictionary = tasks[task_id]
	var execution: Dictionary = task.execution
	if not session.cards.has(execution.actor) or not session.cards.has(execution.target):
		_complete_execution(task_id)
		return
	var result: Dictionary = resolve_attack(execution.actor, execution.target)
	session.cards[execution.target].health = maxi(0, session.cards[execution.target].health - result.damage)
	execution.phase = "return"
	execution.remaining = 0.3
	session.event_occurred.emit("combat_hit", {"combat_id": task_id, "attacker_id": execution.actor, "defender_id": execution.target, "combat_type": execution.combat_type, "result": result})
	if tasks.has(task_id) and task.has("execution"):
		session.event_occurred.emit("combat_return_started", {"combat_id": task_id, "attacker_id": execution.actor, "defender_id": execution.target, "combat_type": execution.combat_type, "duration": 0.3})
	session.changed.emit()

func _after_return(task_id: int) -> void:
	var session = _session.get_ref()
	var task: Dictionary = tasks[task_id]
	var target: int = task.execution.target
	if session.cards.has(target) and session.cards[target].health <= 0:
		# Remove first, without generic removal's immediate EndCombat. Source waits
		# a scaled half-second after Kill even when the target was the last enemy.
		task.attackers.erase(target)
		task.defenders.erase(target)
		task.progress.erase(target)
		membership.erase(target)
		dragged.erase(target)
		task.execution.phase = "death_wait"
		task.execution.remaining = 0.5
		task.execution.target = -1
		session.kill_card(target)
	else:
		_complete_execution(task_id)

func _complete_execution(task_id: int) -> void:
	if not tasks.has(task_id):
		return
	var task: Dictionary = tasks[task_id]
	if task.has("execution"):
		var actor: int = task.execution.actor
		if task.progress.has(actor):
			task.progress[actor] = 0.0
		task.erase("execution")
	if task.attackers.is_empty() or task.defenders.is_empty():
		_finish(task_id)

## Source CardController blocks starting a drag while IsAttacking is true.
## The flag clears before the scaled post-death wait, not when the task ends.
func is_attacking(card_id: int) -> bool:
	if not membership.has(card_id):
		return false
	var task: Dictionary = tasks[membership[card_id]]
	return task.has("execution") and task.execution.actor == card_id and task.execution.phase in ["travel", "return"]

func can_drag_combatant(card_id: int) -> bool:
	if not membership.has(card_id):
		return false
	var task: Dictionary = tasks[membership[card_id]]
	return task.player_is_attacker and card_id in task.attackers and not is_attacking(card_id)

func flee(card_id: int) -> bool:
	if not membership.has(card_id):
		return false
	var task: Dictionary = tasks[membership[card_id]]
	if not task.player_is_attacker or card_id not in task.attackers:
		return false
	remove_combatant(card_id)
	return true

func remove_combatant(card_id: int, return_to_board: bool = true) -> void:
	if not membership.has(card_id):
		return
	var task_id: int = membership[card_id]
	var task: Dictionary = tasks[task_id]
	task.attackers.erase(card_id)
	task.defenders.erase(card_id)
	task.progress.erase(card_id)
	if task.has("execution") and card_id in [task.execution.actor, task.execution.target]:
		task.erase("execution") # Safety: cancel dangling attack; never reroll a replacement.
	membership.erase(card_id)
	dragged.erase(card_id)
	if return_to_board:
		Equipment.return_to_board(_session.get_ref(), card_id)
	if task.attackers.is_empty() or task.defenders.is_empty():
		_finish(task_id)

func _finish(task_id: int) -> void:
	var session = _session.get_ref()
	var task: Dictionary = tasks[task_id]
	for id in task.attackers + task.defenders:
		membership.erase(id)
		dragged.erase(id)
		Equipment.return_to_board(session, id)
	tasks.erase(task_id)
	session.event_occurred.emit("combat_ended", {"combat_id": task_id})

## Called by a view after bounds overlap is established. Source merges always
## designate the player faction as attacker, even if a mob initiated either fight.
func merge_combats(task_ids: Array, initial_attackers: Array = [], initial_defenders: Array = []) -> int:
	if _selecting_geometry:
		return -1
	var selected: Dictionary = _selected_tasks(task_ids)
	if not selected.ok or selected.ids.is_empty():
		return -1
	var session = _session.get_ref()
	var players: Array = []
	var mobs: Array = []
	var ordered: Array = initial_attackers + initial_defenders
	for task_id in selected.ids:
		ordered.append_array(tasks[task_id].attackers + tasks[task_id].defenders)
	# Validate the entire replacement before removing any old task or membership.
	for raw_id in ordered:
		if not Equipment.valid_integer(raw_id, 1):
			return -1
		var id: int = int(raw_id)
		if not session.cards.has(id) or (membership.has(id) and membership[id] not in selected.ids):
			return -1
		if id in players or id in mobs:
			continue
		var fields: Dictionary = session.catalog.fields(session.cards[id].definition_guid)
		var faction: int = int(fields.get("faction", 0))
		if int(fields.get("category", 0)) not in [2, 9] or faction not in [1, 2]:
			return -1
		if faction == 1:
			players.append(id)
		else:
			mobs.append(id)
	if players.is_empty() or mobs.is_empty():
		return -1
	for task_id in selected.ids:
		for id in tasks[task_id].attackers + tasks[task_id].defenders:
			membership.erase(id)
			dragged.erase(id)
		# Do not _finish: source cleanup bypasses survivor stacks and end events.
		tasks.erase(task_id)
	return _create_combat(players, mobs, true)

func save_state() -> Dictionary:
	var records: Array = []
	for id in tasks:
		var task: Dictionary = tasks[id]
		var progress: Array = []
		for card_id in task.attackers + task.defenders:
			progress.append({"card": card_id, "value": task.progress[card_id]})
		var record := {"id": id, "attackers": task.attackers.duplicate(), "defenders": task.defenders.duplicate(), "player_is_attacker": task.player_is_attacker, "timer": task.timer, "progress": progress}
		if task.has("execution"):
			if task.execution is Dictionary:
				var execution: Dictionary = task.execution.duplicate(true)
				for key in ["attacker_position", "defender_position"]:
					var value = execution.get(key)
					execution[key] = [value.x, value.y] if value is Vector2 else value
				record["execution"] = execution
			else:
				record["execution"] = task.execution # Preserve invalid state for validator.
		if task.has("layout"):
			# Derived configuration/positions belong to the current scene adapter.
			# Preserve invalid live metadata for validation, never silently discard it.
			if task.layout is Dictionary:
				var layout := {}
				for key in ["center", "cell"]:
					var value = task.layout.get(key)
					layout[key] = [value.x, value.y] if value is Vector2 else value
				record["layout"] = layout
			else:
				record["layout"] = task.layout
		records.append(record)
	return {"tasks": records, "next_id": _next_id}

func stage_state(raw: Variant, cards: Dictionary, scene_name: String = "") -> Dictionary:
	var invalid := {"ok": false, "error": "Invalid combat snapshot"}
	if not raw is Dictionary or not raw.get("tasks", null) is Array:
		return invalid
	if not Equipment.valid_integer(raw.get("next_id"), 1) or raw.tasks.size() > cards.size():
		return invalid
	var result := {"ok": true, "tasks": {}, "membership": {}, "next_id": int(raw.get("next_id", -1)), "unstacked": []}
	if result.next_id < 1:
		return invalid
	var catalog = _session.get_ref().catalog
	for record in raw.tasks:
		if not record is Dictionary or not record.get("attackers", null) is Array or not record.get("defenders", null) is Array or not record.get("progress", null) is Array or not record.get("player_is_attacker", null) is bool:
			return invalid
		if not Equipment.valid_integer(record.get("id"), 1) or not Equipment.valid_number(record.get("timer")) or record.attackers.size() + record.defenders.size() > cards.size() or record.progress.size() > cards.size():
			return invalid
		var id: int = int(record.get("id", -1))
		var timer: float = float(record.get("timer", INF))
		if id < 1 or id >= result.next_id or result.tasks.has(id) or not is_finite(timer) or ((record.attackers.is_empty() or record.defenders.is_empty()) and (not record.get("execution") is Dictionary or record.execution.get("phase") != "death_wait")):
			return invalid
		var task := {"attackers": [], "defenders": [], "player_is_attacker": record.player_is_attacker, "timer": timer, "progress": {}}
		if record.has("layout"):
			if not record.layout is Dictionary or record.layout.size() != 2:
				return invalid
			var layout := {}
			for key in ["center", "cell"]:
				var axes = record.layout.get(key)
				if not axes is Array or axes.size() != 2:
					return invalid
				for axis in axes:
					if not Equipment.valid_number(axis) or absf(float(axis)) > 1.0e20 or (key == "cell" and float(axis) <= 0.0):
						return invalid
				layout[key] = Vector2(float(axes[0]), float(axes[1]))
				# Vector2 may use float32, so reject positive values that underflow.
				if key == "cell" and (layout[key].x <= 0.0 or layout[key].y <= 0.0):
					return invalid
			task["layout"] = layout
		for side in ["attackers", "defenders"]:
			for raw_id in record[side]:
				if not Equipment.valid_integer(raw_id, 1):
					return invalid
				var card_id: int = int(raw_id)
				if not cards.has(card_id) or result.membership.has(card_id) or cards[card_id].stack_id != -1:
					return invalid
				var expected: int = 1 if ((side == "attackers") == record.player_is_attacker) else 2
				var fields: Dictionary = catalog.fields(cards[card_id].definition_guid)
				if int(fields.get("faction", 0)) != expected or int(fields.get("category", 0)) not in [2, 9]:
					return invalid
				task[side].append(card_id)
				result.membership[card_id] = id
				result.unstacked.append(card_id)
		for entry in record.progress:
			if not entry is Dictionary or not Equipment.valid_integer(entry.get("card"), 1) or not Equipment.valid_number(entry.get("value")):
				return invalid
			var card_id: int = int(entry.get("card", -1))
			var value: float = float(entry.get("value", INF))
			if result.membership.get(card_id, -1) != id or task.progress.has(card_id) or not is_finite(value):
				return invalid
			task.progress[card_id] = value
		if task.progress.size() != task.attackers.size() + task.defenders.size():
			return invalid
		if record.has("execution"):
			var raw_execution = record.execution
			if not raw_execution is Dictionary or raw_execution.size() != 7:
				return invalid
			if raw_execution.get("phase") not in ["travel", "return", "death_wait"] or not Equipment.valid_number(raw_execution.get("remaining")) or float(raw_execution.remaining) < 0 or float(raw_execution.remaining) > 3600:
				return invalid
			if not Equipment.valid_integer(raw_execution.get("actor"), 1) or not Equipment.valid_integer(raw_execution.get("target"), -1) or not Equipment.valid_integer(raw_execution.get("combat_type"), 0) or int(raw_execution.combat_type) > 3:
				return invalid
			var execution: Dictionary = raw_execution.duplicate(true)
			execution.actor = int(execution.actor)
			execution.target = int(execution.target)
			execution.combat_type = int(execution.combat_type)
			if execution.actor not in task.attackers + task.defenders:
				return invalid
			if execution.phase == "death_wait":
				if execution.target != -1 or float(execution.remaining) > 0.5:
					return invalid
			else:
				if execution.target not in task.attackers + task.defenders or ((execution.actor in task.attackers) == (execution.target in task.attackers)) or (execution.phase == "return" and float(execution.remaining) > 0.3):
					return invalid
			if execution.phase == "travel":
				var duration: float = 0.3 if execution.combat_type not in [2, 3] else projectile_duration(execution.combat_type, scene_name)
				if duration < 0 or float(execution.remaining) > duration:
					return invalid
			for key in ["attacker_position", "defender_position"]:
				var axes = execution.get(key)
				if not axes is Array or axes.size() != 2:
					return invalid
				for axis in axes:
					if not Equipment.valid_number(axis) or absf(float(axis)) > 1e20:
						return invalid
				execution[key] = Vector2(float(axes[0]), float(axes[1]))
			task["execution"] = execution
		result.tasks[id] = task
	return result

func apply_state(staged: Dictionary) -> void:
	tasks = staged.tasks
	membership = staged.membership
	_next_id = staged.next_id
	dragged.clear()
