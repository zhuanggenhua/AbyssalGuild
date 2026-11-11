extends RefCounted
## Logical combat turns. Presentation delays/rect-overlap detection belong to the view.
const Equipment = preload("res://scripts/model/equipment_system.gd")
var _session: WeakRef
var equipment
var tasks: Dictionary = {}
var membership: Dictionary = {}
var dragged: Dictionary = {}
var advantage_multiplier: float = 1.5
var disadvantage_multiplier: float = 0.75
var _next_id: int = 1

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

func start_combat(attackers: Array, defenders: Array, player_is_attacker: bool = true) -> int:
	var session = _session.get_ref()
	if attackers.is_empty() or defenders.is_empty():
		return -1
	var seen: Dictionary = {}
	for id in attackers + defenders:
		if not session.cards.has(id) or membership.has(id) or seen.has(id):
			return -1
		var fields: Dictionary = session.catalog.fields(session.cards[id].definition_guid)
		var expected: int = 1 if ((id in attackers) == player_is_attacker) else 2
		if int(fields.get("faction", 0)) != expected or int(fields.get("category", 0)) not in [2, 9]:
			return -1
		seen[id] = true
	var task_id: int = _next_id
	_next_id += 1
	tasks[task_id] = {"attackers": attackers.duplicate(), "defenders": defenders.duplicate(), "player_is_attacker": player_is_attacker, "timer": 1.0, "progress": {}}
	for id in attackers + defenders:
		_enter(task_id, id)
	session.event_occurred.emit("combat_started", {"combat_id": task_id})
	return task_id

func _enter(task_id: int, card_id: int) -> void:
	var session = _session.get_ref()
	Equipment.detach(session, card_id)
	membership[card_id] = task_id
	tasks[task_id].progress[card_id] = session.rng.randf_range(0.0, 0.5)

func add_combatants(task_id: int, card_ids: Array) -> bool:
	if not tasks.has(task_id):
		return false
	var session = _session.get_ref()
	var added: bool = false
	for id in card_ids:
		if not session.cards.has(id) or membership.has(id):
			continue
		var faction: int = int(session.catalog.fields(session.cards[id].definition_guid).get("faction", 0))
		if faction not in [1, 2]:
			continue
		var side: String = "attackers" if ((faction == 1) == tasks[task_id].player_is_attacker) else "defenders"
		tasks[task_id][side].append(id)
		_enter(task_id, id)
		added = true
	return added

func tick(delta: float) -> void:
	if delta <= 0:
		return
	var session = _session.get_ref()
	for task_id in tasks.keys():
		if not tasks.has(task_id):
			continue
		var task: Dictionary = tasks[task_id]
		for id in task.attackers + task.defenders:
			if not session.cards.has(id):
				remove_combatant(id, false)
			elif session.cards[id].health > 0:
				task.progress[id] += equipment.stats(id).attackSpeed * delta
		if not tasks.has(task_id):
			continue
		task.timer -= delta
		# Source resolves at most one turn per Update, not one attack per fighter.
		if task.timer <= 0:
			task.timer += 1.0
			resolve_turn(task_id)

func resolve_turn(task_id: int) -> void:
	if not tasks.has(task_id):
		return
	var session = _session.get_ref()
	var task: Dictionary = tasks[task_id]
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
	var result: Dictionary = resolve_attack(actor, target)
	session.cards[target].health = maxi(0, session.cards[target].health - result.damage)
	session.event_occurred.emit("combat_hit", {"attacker_id": actor, "defender_id": target, "result": result})
	task.progress[actor] = 0.0
	if session.cards[target].health <= 0:
		# kill_card owns kill event, equipment drop, loot and external combat removal.
		session.kill_card(target)
		remove_combatant(target, false)
	session.changed.emit()

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
func merge_combats(task_ids: Array) -> int:
	var session = _session.get_ref()
	var players: Array = []
	var mobs: Array = []
	for task_id in task_ids:
		if not tasks.has(task_id):
			return -1
		for id in tasks[task_id].attackers + tasks[task_id].defenders:
			if id in players or id in mobs:
				continue
			var faction: int = int(session.catalog.fields(session.cards[id].definition_guid).get("faction", 0))
			if faction == 1:
				players.append(id)
			elif faction == 2:
				mobs.append(id)
	if players.is_empty() or mobs.is_empty():
		return -1
	for task_id in task_ids:
		if not tasks.has(task_id):
			continue
		for id in tasks[task_id].attackers + tasks[task_id].defenders:
			membership.erase(id)
		tasks.erase(task_id)
	return start_combat(players, mobs, true)

func save_state() -> Dictionary:
	var records: Array = []
	for id in tasks:
		var task: Dictionary = tasks[id]
		var progress: Array = []
		for card_id in task.attackers + task.defenders:
			progress.append({"card": card_id, "value": task.progress[card_id]})
		records.append({"id": id, "attackers": task.attackers.duplicate(), "defenders": task.defenders.duplicate(), "player_is_attacker": task.player_is_attacker, "timer": task.timer, "progress": progress})
	return {"tasks": records, "next_id": _next_id}

func stage_state(raw: Variant, cards: Dictionary) -> Dictionary:
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
		if id < 1 or id >= result.next_id or result.tasks.has(id) or not is_finite(timer) or record.attackers.is_empty() or record.defenders.is_empty():
			return invalid
		var task := {"attackers": [], "defenders": [], "player_is_attacker": record.player_is_attacker, "timer": timer, "progress": {}}
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
		result.tasks[id] = task
	return result

func apply_state(staged: Dictionary) -> void:
	tasks = staged.tasks
	membership = staged.membership
	_next_id = staged.next_id
	dragged.clear()
