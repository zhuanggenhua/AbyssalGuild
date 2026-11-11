extends RefCounted
## Source CardAI control flow; presentation geometry is injected, never guessed.
const Equipment = preload("res://scripts/model/equipment_system.gd")
var _session: WeakRef
var world
var selected_scene: String = "Main"
var agents: Dictionary = {}
var prefab_by_category: Dictionary = {}
var aggressive_prefab: String = ""
var ai_prefabs: Dictionary = {}
var move_interval: float = 5.0
var move_radius: float = 1.0
var max_attempts: int = 5
## (candidate: Vector2, stack_id: int) -> bool, Board.IsPointValid equivalent.
var point_validator: Callable = Callable()
## () -> Array of world.aggressive_intent combat snapshots.
var combat_geometry: Callable = Callable()
## Optional placement adapter (guid, position, ignored_stack_id) -> spawned ID.
## Used for source CreateCardInstance auto-attachment/overlap resolution.
var produce_spawner: Callable = Callable()

func configure(session, world_rules = null, scene_name: String = "Main") -> void:
	if _session != null:
		var previous = _session.get_ref()
		if previous != null and previous.event_occurred.is_connected(_on_event):
			previous.event_occurred.disconnect(_on_event)
	_session = weakref(session)
	selected_scene = scene_name
	world = world_rules if world_rules != null else session.world
	reset()
	prefab_by_category.clear()
	ai_prefabs.clear()
	aggressive_prefab = ""
	var settings: Dictionary = session.catalog.settings("CardSettings")
	move_interval = float(settings.get("moveInterval", 5.0))
	move_radius = float(settings.get("moveRadius", 1.0))
	max_attempts = int(settings.get("maxAttemptsPerMove", 5))
	for prefab in session.catalog.data.get("referenced_prefabs", []):
		for document in prefab.get("documents", []):
			if document.get("script_class", "") == "CardAI":
				ai_prefabs[str(prefab.guid)] = true
	for scene in session.catalog.data.get("scenes", []):
		if scene.get("name", "") != scene_name:
			continue
		for document in scene.get("documents", []):
			if document.get("script_class", "") != "CardManager":
				continue
			var fields: Dictionary = document.get("fields", {})
			aggressive_prefab = session.catalog.ref_guid(fields.get("aggressiveMobPrefab", {}))
			for entry in fields.get("cardPrefabs", []):
				prefab_by_category[int(entry.get("category", 0))] = session.catalog.ref_guid(entry.get("prefab", {}))
	session.event_occurred.connect(_on_event)
	resync()

func reset() -> void:
	agents.clear()
	if world != null:
		world.production_timers.clear()

func has_ai(card_id: int) -> bool:
	var session = _session.get_ref()
	return session.cards.has(card_id) and _definition_has_ai(session.cards[card_id].definition_guid)

func _definition_has_ai(guid: String) -> bool:
	var fields: Dictionary = _session.get_ref().catalog.fields(guid)
	var category: int = int(fields.get("category", 0))
	var prefab: String = str(prefab_by_category.get(category, ""))
	if category == 9 and fields.get("isAggressive", false) and not aggressive_prefab.is_empty():
		prefab = aggressive_prefab
	return ai_prefabs.has(prefab)

func _on_event(kind: String, payload: Dictionary) -> void:
	if kind == "card_created":
		register(int(payload.get("card_id", -1)))
	elif kind in ["combat_started", "combat_ended"]:
		resync()

## Explicit register is useful for adapters; still checks imported prefab mapping.
func register(card_id: int) -> bool:
	if agents.has(card_id) or not has_ai(card_id):
		return false
	agents[card_id] = {"running": false, "move_timer": 0.0}
	if not _session.get_ref().combat.membership.has(card_id):
		_restart(card_id)
	return true

func _restart(card_id: int) -> void:
	var session = _session.get_ref()
	agents[card_id].running = true
	agents[card_id].move_timer = session.rng.randf_range(0.5, 1.0) + move_interval
	world.start_production(card_id)

func _stop(card_id: int) -> void:
	agents[card_id].running = false
	world.production_timers.erase(card_id)

## Call after load; coroutine timers restart rather than restoring invented progress.
func resync() -> void:
	var session = _session.get_ref()
	for id in agents.keys():
		if not session.cards.has(id) or not has_ai(id):
			agents.erase(id)
			world.production_timers.erase(id)
	for id in session.cards:
		register(id)
	for id in agents:
		var in_combat: bool = session.combat.membership.has(id)
		if in_combat and agents[id].running:
			_stop(id)
		elif not in_combat and not agents[id].running:
			_restart(id)

## Pass the same scaled delta as crafting/combat; caller owns global pause/phase.
func tick(delta: float) -> void:
	if delta <= 0:
		return
	resync()
	var session = _session.get_ref()
	for id in agents.keys():
		if not agents.has(id) or not agents[id].running:
			continue
		agents[id].move_timer -= delta
		if agents[id].move_timer > 0:
			continue
		agents[id].move_timer = move_interval
		if not world.can_act(id) or world.should_stay_in_enclosure(id):
			continue
		_detach(id)
		if session.catalog.fields(session.cards[id].definition_guid).get("isAggressive", false):
			_act_aggressively(id)
		else:
			_patrol(id)
	# EnterCombat stops both coroutines immediately, including a later production
	# wake in this tick. Active combat additions do not emit combat_started.
	resync()
	_tick_production(delta)

func _detach(card_id: int) -> void:
	var session = _session.get_ref()
	var stack = session.stacks.get(session.cards[card_id].stack_id)
	if stack == null:
		Equipment.return_to_board(session, card_id)
		return
	if stack.card_ids.size() <= 1:
		return
	var target: Vector2 = session.card_target_position(card_id)
	Equipment.detach(session, card_id, target)
	Equipment.return_to_board(session, card_id)
	if session.stacks.has(stack.id):
		session._validate_craft(stack)

func _act_aggressively(card_id: int) -> void:
	var session = _session.get_ref()
	var snapshots: Array = combat_geometry.call() if combat_geometry.is_valid() else []
	var intent: Dictionary = world.aggressive_intent(card_id, snapshots)
	match intent.get("action", "patrol"):
		"join_combat":
			var ids: Array = session.stacks[session.cards[card_id].stack_id].card_ids.duplicate()
			session.combat.add_combatants(int(intent.combat_id), ids)
		"approach_combat", "approach_player":
			var start: Vector2 = session.card_target_position(card_id)
			_move_if_valid(card_id, start + start.direction_to(intent.position) * move_radius)
		"attack_player":
			var attacker_stack = session.stacks.get(session.cards[card_id].stack_id)
			var defender_stack = session.stacks.get(session.cards[int(intent.card_id)].stack_id)
			if attacker_stack != null and defender_stack != null:
				var attackers: Array = _combatants(attacker_stack.card_ids)
				var defenders: Array = _combatants(defender_stack.card_ids)
				if not attackers.is_empty() and not defenders.is_empty():
					session.combat.start_combat(attackers, defenders, false)
		_:
			_patrol(card_id)

func _combatants(ids: Array) -> Array:
	var session = _session.get_ref()
	var result: Array = []
	for id in ids:
		if int(session.catalog.fields(session.cards[id].definition_guid).get("category", 0)) in [2, 9]:
			result.append(id)
	return result

func _patrol(card_id: int) -> void:
	var session = _session.get_ref()
	var stack = session.stacks.get(session.cards[card_id].stack_id)
	if stack == null:
		return
	for attempt in range(max_attempts):
		var direction := Vector2(session.rng.randf_range(-1, 1), session.rng.randf_range(-1, 1))
		while direction.length_squared() > 1.0:
			direction = Vector2(session.rng.randf_range(-1, 1), session.rng.randf_range(-1, 1))
		if _move_if_valid(card_id, stack.position + direction.normalized() * move_radius):
			return

func _move_if_valid(card_id: int, target: Vector2) -> bool:
	var session = _session.get_ref()
	var stack = session.stacks.get(session.cards[card_id].stack_id)
	if stack == null or not point_validator.is_valid() or not point_validator.call(target, stack.id):
		return false
	stack.position = target
	for id in stack.card_ids:
		session.cards[id].position = target
	session.changed.emit()
	return true

func _tick_production(delta: float) -> void:
	var session = _session.get_ref()
	for id in world.production_timers.keys():
		if not agents.has(id) or not agents[id].running or not session.cards.has(id):
			world.production_timers.erase(id)
			continue
		world.production_timers[id] -= delta
		if world.production_timers[id] > 0:
			continue
		var fields: Dictionary = session.catalog.fields(session.cards[id].definition_guid)
		world.production_timers[id] = float(fields.get("produceInterval", 10.0))
		var produce: String = session.catalog.ref_guid(fields.get("produceCard", {}))
		if not fields.get("isAggressive", false) and world.can_act(id) and not produce.is_empty():
			var position: Vector2 = session.card_target_position(id)
			if produce_spawner.is_valid():
				produce_spawner.call(produce, position, -1)
			else:
				session.spawn_card(produce, position)
			# Source puffs the producer after CreateCardInstance, not the produce.
			session.request_puff(id)

## Same geometry as Board.IsPointValid: half stack width and half top-card depth,
## not entire stack depth. Bounds and footprint must come from the view/scene.
static func point_in_board(point: Vector2, bounds: Rect2, footprint: Vector2, top_margin: float = 1.5) -> bool:
	var half: Vector2 = footprint * 0.5
	return point.x >= bounds.position.x + half.x and point.x <= bounds.end.x - half.x and point.y >= bounds.position.y + half.y and point.y <= bounds.end.y - half.y and point.y + half.y <= bounds.end.y - top_margin

## Native checkpoint timers intentionally preserve RNG continuity across loads.
## Serialization is read-only: never resync or draw randomness while saving.
func save_state() -> Dictionary:
	var session = _session.get_ref()
	var records: Array = []
	for id in session.cards:
		if not has_ai(id):
			continue
		if not agents.has(id):
			records.append({"card": id, "running": false, "move_timer": 0.0})
			continue
		# A just-joined fight may not yet have reached next-tick reconciliation.
		var running: bool = agents[id].running and not session.combat.membership.has(id)
		var record := {"card": id, "running": running, "move_timer": agents[id].move_timer}
		if running and world.production_timers.has(id):
			record["produce_timer"] = world.production_timers[id]
		records.append(record)
	return {"scene": selected_scene, "agents": records}

func stage_state(raw: Variant, cards: Dictionary) -> Dictionary:
	var invalid := {"ok": false, "error": "Invalid AI snapshot"}
	if not raw is Dictionary or not raw.get("scene") is String or raw.scene != selected_scene or not raw.get("agents") is Array or raw.agents.size() > cards.size():
		return invalid
	var result := {"ok": true, "agents": {}, "production_timers": {}, "unstacked": []}
	var catalog = _session.get_ref().catalog
	for record in raw.agents:
		if not record is Dictionary or not Equipment.valid_integer(record.get("card"), 1) or not record.get("running") is bool or not _valid_timer(record.get("move_timer")):
			return invalid
		var id: int = int(record.card)
		if not cards.has(id) or result.agents.has(id) or not _definition_has_ai(cards[id].definition_guid):
			return invalid
		var fields: Dictionary = catalog.fields(cards[id].definition_guid)
		var produces: bool = record.running and not fields.get("isAggressive", false) and not catalog.ref_guid(fields.get("produceCard", {})).is_empty()
		if record.has("produce_timer") != produces:
			return invalid
		if produces:
			if not _valid_timer(record.produce_timer):
				return invalid
			result.production_timers[id] = float(record.produce_timer)
		result.agents[id] = {"running": record.running, "move_timer": float(record.move_timer)}
	# Every live imported AI prefab must have exactly one checkpoint record.
	for id in cards:
		if _definition_has_ai(cards[id].definition_guid) and not result.agents.has(id):
			return invalid
	return result

static func _valid_timer(value: Variant) -> bool:
	return Equipment.valid_number(value) and float(value) >= 0.0

## Codec calls with staged combat.membership (or empty legacy combat state).
## A stopped, noncombat agent is allowed: next tick performs its pending restart.
static func validate_combat_state(staged: Dictionary, membership: Dictionary) -> bool:
	for id in staged.agents:
		if membership.has(id) and staged.agents[id].running:
			return false
	return true

func apply_state(staged: Dictionary) -> void:
	agents = staged.agents.duplicate(true)
	world.production_timers = staged.production_timers.duplicate(true)
