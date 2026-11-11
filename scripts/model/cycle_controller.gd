extends RefCounted
## Deterministic realtime day-cycle effects. Rendering never owns completion.
const WAIT_DURATIONS = {"character_focus": 0.5, "food_lift": 0.1, "food_travel": 0.2, "food_chew": 0.25, "leftover_settle": 0.25, "character_wait": 0.5, "encounter_notification": 2.0, "encounter_focus": 0.5, "encounter_wait": 0.5}
const FOOD_STAGES = ["food_lift", "food_travel", "food_chew", "leftover_settle"]
const FEED_STAGES = ["character_focus", "food_lift", "food_travel", "food_chew", "leftover_settle", "character_wait"]
const ENCOUNTER_STAGES = ["encounter_notification", "encounter_focus", "encounter_wait"]
var _session: WeakRef
var _state: Dictionary = empty_state()
var _busy: bool = false
var pose_sampler: Callable = Callable()
var layout_resolver: Callable = Callable()
var stage: String:
	get: return str(_state.stage)
var remaining: float:
	get: return float(_state.remaining)

static func empty_state(selected_stage: String = "idle") -> Dictionary:
	return {"version": 1, "stage": selected_stage, "remaining": 0.0, "characters": [], "foods": [], "cursor": 0, "character_id": -1, "food_id": -1, "need": 0, "hunger": 0, "old_stack_id": -1, "food_origin": [0.0, 0.0, 0.0], "food_target": [0.0, 0.0, 0.0], "focus_target": [0.0, 0.0, 0.0], "encounter_guid": "", "spawn_index": 0, "spawned_ids": []}

func configure(session) -> void:
	_session = weakref(session)
	reset()

func reset() -> void:
	_state = empty_state()
	_busy = false

func camera_available() -> bool:
	var session = _session.get_ref()
	for scene in session.catalog.data.get("scenes", []):
		if str(scene.get("name", "")) != session.scene_name: continue
		for document in scene.get("documents", []):
			if document.get("script_class", "") == "CameraController": return true
			var guid: String = session.catalog.ref_guid(document.get("fields", {}).get("m_SourcePrefab", {}))
			if guid.is_empty(): continue
			for prefab in session.catalog.data.get("referenced_prefabs", []):
				if str(prefab.get("guid", "")) != guid: continue
				for component in prefab.get("documents", []):
					if component.get("script_class", "") == "CameraController": return true
	return false

func request_end_day() -> bool:
	var session = _session.get_ref()
	if _busy or session.phase != "playing": return false
	_busy = true
	_state = empty_state("await_feed")
	session.elapsed = 0.0
	session.paused = true
	session.phase = "feeding"
	session.event_occurred.emit("day_ended", {"day": session.day})
	_announce_stage()
	_busy = false
	return true

func begin_feeding() -> bool:
	var session = _session.get_ref()
	if _busy or session.phase != "feeding" or stage not in ["idle", "await_feed"]: return false
	_busy = true
	session.paused = true
	_state = empty_state()
	_state.hunger = maxi(0, int(session.catalog.settings("CardSettings").get("hungerPerCharacter", 2)))
	for id in session._feeding_card_ids():
		var category: int = int(session.catalog.fields(session.cards[id].definition_guid).get("category", 0))
		if category == 2: _state.characters.append(id)
		elif category == 3 and session.cards[id].nutrition > 0: _state.foods.append(id)
	_start_character()
	_busy = false
	return true

## One expired yielded wait per frame. Overshoot never consumes the next wait.
func advance(real_delta: float) -> void:
	if _busy or real_delta <= 0 or not is_finite(real_delta) or not WAIT_DURATIONS.has(stage): return
	_state.remaining = maxf(0, remaining - real_delta)
	if remaining > 0.000000001: return
	_busy = true
	match stage:
		"character_focus": _choose_food()
		"food_lift": _travel_food()
		"food_travel":
			# Source reflows the old stack here. Native target membership already
			# reflects detachment; exact old-stack animated reflow is an adapter gap.
			_session.get_ref().event_occurred.emit("cycle_sound", {"sound": "Eat"})
			_wait("food_chew")
		"food_chew": _consume_food()
		"leftover_settle":
			if layout_resolver.is_valid(): layout_resolver.call()
			_finish_food()
		"character_wait":
			_state.cursor += 1
			_start_character()
		"encounter_notification": _spawn_encounter_card()
		"encounter_focus": _encounter_puff()
		"encounter_wait": _spawn_encounter_card()
	_busy = false

func _announce_stage() -> void:
	var session = _session.get_ref()
	session.event_occurred.emit("cycle_stage_changed", {"stage": stage, "remaining": remaining})
	session.changed.emit()

func _wait(next_stage: String) -> void:
	_state.stage = next_stage
	_state.remaining = WAIT_DURATIONS[next_stage]
	_announce_stage()

func _focus(position: Vector3, reason: String, card_id: int) -> void:
	_state.focus_target = _array3(position)
	_session.get_ref().event_occurred.emit("cycle_focus_requested", {"target_position": position, "duration": 0.5, "reason": reason, "card_id": card_id})

func focus_state() -> Dictionary:
	if stage not in ["character_focus", "encounter_focus"]: return {}
	return {"target_position": _vector3(_state.focus_target), "duration": remaining, "reason": "feeding" if stage == "character_focus" else "encounter", "card_id": int(_state.character_id if stage == "character_focus" else _state.spawned_ids.back())}

static func _array3(point: Vector3) -> Array:
	return [point.x, point.y, point.z]

static func _vector3(point: Array) -> Vector3:
	return Vector3(float(point[0]), float(point[1]), float(point[2]))

func pose(card_id: int) -> Vector3:
	var feeding_pose: Variant = presentation_pose(card_id)
	if feeding_pose is Vector3: return feeding_pose
	if pose_sampler.is_valid():
		var sampled: Variant = pose_sampler.call(card_id)
		if sampled is Vector3 and sampled.is_finite(): return sampled
	return _session.get_ref().card_target_position_3d(card_id)

func presentation_state() -> Dictionary:
	if stage not in FOOD_STAGES or _state.food_id < 0: return {}
	var origin := _vector3(_state.food_origin)
	var target := _vector3(_state.food_target)
	var lifted := Vector3(origin.x, _drag_height(), origin.z)
	var duration: float = WAIT_DURATIONS[stage]
	return {"stage": stage, "card_id": int(_state.food_id), "from_position": origin if stage == "food_lift" else (lifted if stage == "food_travel" else target), "to_position": lifted if stage == "food_lift" else target, "duration": duration, "elapsed": clampf(duration - remaining, 0.0, duration)}

func presentation_pose(card_id: int) -> Variant:
	if card_id != _state.food_id: return null
	var motion := presentation_state()
	if motion.is_empty(): return null
	var amount: float = clampf(motion.elapsed / motion.duration, 0, 1)
	# DOTween's default movement ease is OutQuad. Effect timing is independent.
	return motion.from_position.lerp(motion.to_position, 1.0 - (1.0 - amount) * (1.0 - amount))

func _motion() -> void:
	_session.get_ref().event_occurred.emit("cycle_food_motion", presentation_state())

func _drag_height() -> float:
	return float(_session.get_ref().catalog.settings("CardSettings").get("dragHeight", 0.1))

func _clear_food() -> void:
	_state.food_id = -1
	_state.old_stack_id = -1
	_state.food_origin = [0.0, 0.0, 0.0]
	_state.food_target = [0.0, 0.0, 0.0]

func _start_character() -> void:
	var session = _session.get_ref()
	_clear_food()
	while _state.cursor < _state.characters.size() and not session.cards.has(_state.characters[_state.cursor]):
		_state.cursor += 1
	if _state.cursor >= _state.characters.size():
		_state = empty_state("game_over" if session.stats().characters <= 0 else "selling")
		session.phase = stage
		if stage == "selling": check_selling()
		_announce_stage()
		return
	_state.character_id = _state.characters[_state.cursor]
	_state.need = _state.hunger
	if camera_available():
		_wait("character_focus")
		_focus(pose(_state.character_id), "feeding", _state.character_id)
	else: _choose_food()

func _choose_food() -> void:
	var session = _session.get_ref()
	if not session.cards.has(_state.character_id):
		_state.cursor += 1
		_start_character()
		return
	if _state.need <= 0:
		_clear_food()
		_wait("character_wait")
		return
	var selected: int = -1
	var distance: float = INF
	var character_position := pose(_state.character_id)
	for id in _state.foods:
		if not session.cards.has(id) or session.cards[id].nutrition <= 0: continue
		var candidate: float = character_position.distance_squared_to(pose(id))
		if candidate < distance:
			distance = candidate
			selected = id
	if selected < 0:
		session.kill_card(_state.character_id, character_position)
		_clear_food()
		_wait("character_wait")
		return
	var selected_origin := pose(selected)
	_state.foods.erase(selected)
	_state.food_id = selected
	_state.food_origin = _array3(selected_origin)
	_state.food_target = _state.food_origin.duplicate()
	var food = session.cards[selected]
	var old_stack = session.stacks.get(food.stack_id)
	_state.old_stack_id = old_stack.id if old_stack != null and old_stack.card_ids.size() > 1 else -1
	# Detach now; movement is derived separately until consumption settles it.
	var origin := _vector3(_state.food_origin)
	session._prepare_food_for_feeding(food, Vector2(origin.x, origin.z))
	_wait("food_lift")
	_motion()

func _travel_food() -> void:
	var session = _session.get_ref()
	if not session.cards.has(_state.character_id) or not session.cards.has(_state.food_id):
		_cancel_food()
		return
	var target := pose(_state.character_id)
	target.y = _drag_height()
	_state.food_target = _array3(target)
	_wait("food_travel")
	session.event_occurred.emit("cycle_sound", {"sound": "CardSwipe"})
	_motion()

func _place_food() -> void:
	var session = _session.get_ref()
	if not session.cards.has(_state.food_id): return
	var position := _vector3(_state.food_target)
	var food = session.cards[_state.food_id]
	food.position = Vector2(position.x, position.z)
	if session.stacks.has(food.stack_id): session.stacks[food.stack_id].position = food.position

func _consume_food() -> void:
	var session = _session.get_ref()
	if not session.cards.has(_state.character_id) or not session.cards.has(_state.food_id):
		_cancel_food()
		return
	var food = session.cards[_state.food_id]
	var character = session.cards[_state.character_id]
	var eaten: int = mini(_state.need, maxi(0, food.nutrition))
	food.nutrition -= eaten
	_state.need -= eaten
	var maximum: int = int(session.equipment.stats(character.id).get("maxHealth", 15))
	if _state.hunger > 0:
		character.health = mini(maximum, character.health + session._round_to_even(float(maximum) * 0.5 * eaten / _state.hunger))
	if food.nutrition <= 0:
		session.kill_card(food.id, _vector3(_state.food_target))
		_finish_food()
	else:
		_place_food()
		_wait("leftover_settle")
		_motion()

func _finish_food() -> void:
	var session = _session.get_ref()
	if session.cards.has(_state.food_id) and session.cards[_state.food_id].nutrition > 0:
		_state.foods.append(_state.food_id)
	_clear_food()
	session._notify_stats_changed()
	_choose_food()

## Native safe cancellation: keep unconsumed food, skip a vanished character,
## and replace missing food only from the original queue. Never charge twice.
func _cancel_food() -> void:
	var session = _session.get_ref()
	_place_food()
	if session.cards.has(_state.food_id) and session.cards[_state.food_id].nutrition > 0:
		_state.foods.append(_state.food_id)
	_clear_food()
	if session.cards.has(_state.character_id): _choose_food()
	else: _wait("character_wait")

func check_selling() -> void:
	var session = _session.get_ref()
	if session.phase != "selling" or session.stats().excess > 0: return
	var was_busy: bool = _busy
	_busy = true
	session.paused = true
	# Claim before any event/spawn can reenter the source stats observer.
	session.phase = "encounter"
	var selected: Dictionary = session.world.claim_day(session.day, session.friendly_mode)
	if selected.is_empty():
		_ready()
	else:
		_state = empty_state("encounter_notification")
		_state.encounter_guid = selected.encounter_guid
		_state.remaining = 2.0 if not str(selected.message).is_empty() else 0.0
		session.event_occurred.emit("encounter", selected)
		if _state.remaining > 0: _announce_stage()
		else: _spawn_encounter_card()
	_busy = was_busy

func _spawn_encounter_card() -> void:
	var session = _session.get_ref()
	var fields: Dictionary = session.catalog.fields(_state.encounter_guid)
	if _state.spawn_index >= maxi(0, int(fields.get("count", 1))):
		var result := {"encounter_guid": _state.encounter_guid, "id": str(fields.get("id", "")), "message": str(fields.get("notificationMessage", "")), "spawned": _state.spawned_ids.duplicate()}
		_ready()
		session.event_occurred.emit("encounter_completed", result)
		return
	var spawned: Dictionary = session.world.spawn_encounter_card(_state.encounter_guid, session.board_bounds, session.board_top_margin)
	_state.spawned_ids.append(spawned.card_id)
	_state.spawn_index += 1
	_state.food_target = [spawned.position.x, 0.0, spawned.position.y]
	if camera_available():
		_wait("encounter_focus")
		_focus(_vector3(_state.food_target), "encounter", spawned.card_id)
	else: _encounter_puff()

func _encounter_puff() -> void:
	var session = _session.get_ref()
	var id: int = int(_state.spawned_ids.back())
	if session.cards.has(id): session.event_occurred.emit("puff_requested", {"card_id": id, "position": pose(id)})
	_wait("encounter_wait")

func _ready() -> void:
	_state = empty_state("ready")
	_session.get_ref().phase = "ready"
	_announce_stage()

func save_state() -> Dictionary:
	if _busy: return {"transitioning": true} # Never persist half a synchronous effect.
	var session = _session.get_ref()
	# Accommodate passive test/legacy callers setting a phase directly.
	if stage == "idle" and session.phase != "playing": return legacy_state(session.phase)
	return _state.duplicate(true)

static func legacy_state(phase: String) -> Dictionary:
	return empty_state({"playing": "idle", "feeding": "await_feed"}.get(phase, phase))

func apply_state(staged: Dictionary) -> void:
	_state = staged.state.duplicate(true)
	_busy = false

static func _integer(value: Variant, low: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= 9007199254740991.0 and floor(float(value)) == float(value)

static func _point(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 1.0e20: return false
	return true

## All context is staged data; validation never reads mutable live card state.
func stage_state(raw: Variant, cards: Dictionary, context: Dictionary) -> Dictionary:
	var invalid := {"ok": false, "error": "Invalid cycle snapshot"}
	if not raw is Dictionary or not _integer(raw.get("version"), 1) or raw.version != 1 or not raw.get("stage") is String: return invalid
	var name: String = raw.stage
	var expected_phase: String = "feeding" if name in FEED_STAGES or name == "await_feed" else ("encounter" if name in ENCOUNTER_STAGES else {"idle": "playing"}.get(name, name))
	if name not in ["idle", "await_feed", "selling", "ready", "game_over"] and not WAIT_DURATIONS.has(name): return invalid
	if expected_phase != context.phase or (WAIT_DURATIONS.has(name) and not context.paused): return invalid
	var seconds = raw.get("remaining")
	if not (seconds is int or seconds is float) or not is_finite(float(seconds)) or seconds < 0 or seconds > float(WAIT_DURATIONS.get(name, 0.0)): return invalid
	for key in ["cursor", "need", "hunger", "spawn_index"]:
		if not _integer(raw.get(key)): return invalid
	for key in ["character_id", "food_id", "old_stack_id"]:
		if not _integer(raw.get(key), -1) or int(raw[key]) == 0 or raw[key] >= context.next_id: return invalid
	if cards.has(int(raw.old_stack_id)) or context.stacks.has(int(raw.food_id)): return invalid
	for key in ["food_origin", "food_target", "focus_target"]:
		if not _point(raw.get(key)): return invalid
	if not raw.get("encounter_guid") is String: return invalid
	var queued := {}
	for key in ["characters", "foods", "spawned_ids"]:
		if not raw.get(key) is Array or raw[key].size() > 100000: return invalid
		var seen := {}
		for value in raw[key]:
			if not _integer(value, -1 if key == "spawned_ids" else 1) or value == 0 or value >= context.next_id: return invalid
			var id: int = int(value)
			if id != -1 and (seen.has(id) or context.stacks.has(id)): return invalid
			seen[id] = true
			if key != "spawned_ids":
				if queued.has(id): return invalid
				queued[id] = true
				if cards.has(id) and int(_session.get_ref().catalog.fields(cards[id].definition_guid).get("category", -1)) != (2 if key == "characters" else 3): return invalid
	if name in FEED_STAGES:
		if raw.cursor >= raw.characters.size() or raw.character_id != raw.characters[int(raw.cursor)] or raw.need > raw.hunger: return invalid
		if raw.hunger != maxi(0, int(_session.get_ref().catalog.settings("CardSettings").get("hungerPerCharacter", 2))): return invalid
		if not str(raw.encounter_guid).is_empty() or raw.spawn_index != 0 or not raw.spawned_ids.is_empty(): return invalid
		if name in FOOD_STAGES:
			if raw.food_id < 1 or raw.food_id in raw.foods or raw.food_id in raw.characters: return invalid
			if name != "leftover_settle" and raw.need <= 0: return invalid
			# A positive leftover means that this bite satisfied all remaining
			# hunger. Restoring a positive need here would charge consumption again.
			if name == "leftover_settle" and raw.need != 0: return invalid
			if cards.has(int(raw.food_id)) and int(_session.get_ref().catalog.fields(cards[int(raw.food_id)].definition_guid).get("category", -1)) != 3: return invalid
		else:
			if raw.food_id != -1 or raw.old_stack_id != -1: return invalid
			if name == "character_wait" and cards.has(int(raw.character_id)) and raw.need != 0: return invalid
		if name == "character_focus" and (not camera_available() or raw.need != raw.hunger): return invalid
	elif name in ENCOUNTER_STAGES:
		var session = _session.get_ref()
		if raw.encounter_guid not in session.world.encounter_guids or not context.world.get("processed_days", {}).has(int(context.day)): return invalid
		var fields: Dictionary = session.catalog.fields(raw.encounter_guid)
		if fields.get("oneTimeOnly", false) and not context.world.get("completed_encounters", {}).has(str(fields.get("id", ""))): return invalid
		if raw.spawn_index != raw.spawned_ids.size() or raw.spawn_index > maxi(0, int(fields.get("count", 1))): return invalid
		var expected_card: String = session.catalog.ref_guid(fields.get("cardToSpawn", {}))
		for id in raw.spawned_ids:
			if cards.has(int(id)) and cards[int(id)].base_definition_guid != expected_card: return invalid
		if name == "encounter_notification" and (raw.spawn_index != 0 or str(fields.get("notificationMessage", "")).is_empty()): return invalid
		if name in ["encounter_focus", "encounter_wait"] and raw.spawn_index < 1: return invalid
		if name == "encounter_focus" and not camera_available(): return invalid
		if not raw.characters.is_empty() or not raw.foods.is_empty() or raw.character_id != -1 or raw.food_id != -1 or raw.old_stack_id != -1 or raw.hunger != 0 or raw.need != 0 or raw.cursor != 0: return invalid
	else:
		# Passive states contain no queued work or effects that could be replayed.
		if not raw.characters.is_empty() or not raw.foods.is_empty() or not raw.spawned_ids.is_empty() or not str(raw.encounter_guid).is_empty(): return invalid
		if raw.cursor != 0 or raw.need != 0 or raw.hunger != 0 or raw.spawn_index != 0 or raw.character_id != -1 or raw.food_id != -1 or raw.old_stack_id != -1: return invalid
		for key in ["food_origin", "food_target", "focus_target"]:
			for value in raw[key]:
				if float(value) != 0.0: return invalid
	var result: Dictionary = raw.duplicate(true)
	result.version = 1
	for key in ["cursor", "need", "hunger", "spawn_index", "character_id", "food_id", "old_stack_id"]: result[key] = int(result[key])
	for key in ["characters", "foods", "spawned_ids"]:
		for index in result[key].size(): result[key][index] = int(result[key][index])
	result.remaining = float(result.remaining)
	return {"ok": true, "state": result, "unstacked": []}
