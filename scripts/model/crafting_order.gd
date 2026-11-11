extends RefCounted
## Source tasks activate independently of stack registration. Newest ticks first.
## Each frame retains task identities, not just stack IDs: callback-created work
## (including a replacement on the same stack) starts advancing next frame.
var _session: WeakRef
var _tasks: Array = []

func configure(session) -> void:
	_session = weakref(session)
	reset()

func reset() -> void:
	_tasks.clear()

## Register a newly selected/restored task, preserving its current timer/pause.
## Ordinary selection owns recipe choice and RNG; this helper never draws RNG.
func activate(stack) -> void:
	stack.craft_generation += 1
	_prune()
	if not stack.recipe_guid.is_empty():
		_tasks.append({"stack": stack, "generation": stack.craft_generation, "recipe": stack.recipe_guid})

func _current(task: Dictionary) -> bool:
	var session = _session.get_ref()
	var stack = task.stack
	return session != null and session.stacks.get(stack.id) == stack and not stack.recipe_guid.is_empty() and stack.craft_generation == task.generation and stack.recipe_guid == task.recipe

func _live_tasks() -> Array:
	return _tasks.filter(func(task): return _current(task))

func _prune() -> void:
	_tasks = _live_tasks()

## Returns true on a scene transition; caller must not advance destination time.
func advance(step: float) -> bool:
	var session = _session.get_ref()
	if session.get("travel_pending") == true: return true
	var scene: String = session.scene_name
	var frame: Array = _live_tasks()
	for index in range(frame.size() - 1, -1, -1):
		var task: Dictionary = frame[index]
		if not _current(task):
			continue
		var stack = task.stack
		var duration: float = float(session.catalog.fields(task.recipe).get("craftingDuration", 5))
		# Source does not add delta to a task that was already complete. Pausing
		# prevents progress, not the action of an already-complete restored task.
		if not stack.paused and stack.progress < duration:
			stack.progress += step
		if stack.progress >= duration:
			session._complete_recipe(stack)
			if session.get("travel_pending") == true or session.scene_name != scene:
				return true
	_prune()
	return false

func save_state() -> Dictionary:
	var order: Array = []
	for task in _live_tasks():
		order.append(task.stack.id)
	return {"activation_order": order}

## Earlier native v1 files never stored task activation history. The saved stack
## row order is the deterministic fallback activation order, NOT recovered history.
static func legacy_state(stacks: Dictionary) -> Dictionary:
	var order: Array = []
	for stack in stacks.values():
		if not stack.recipe_guid.is_empty():
			order.append(stack.id)
	return {"activation_order": order}

static func stage_state(raw: Variant, stacks: Dictionary) -> Dictionary:
	if not raw is Dictionary or not raw.get("activation_order") is Array or raw.activation_order.size() > 100000:
		return {"ok": false, "error": "Invalid crafting activation order"}
	var order: Array = []
	var seen := {}
	for id in raw.activation_order:
		if not (id is int or id is float) or not is_finite(float(id)) or float(id) != floor(float(id)) or float(id) < 1 or float(id) > 9007199254740991.0:
			return {"ok": false, "error": "Invalid crafting stack ID"}
		var key: int = int(id)
		if seen.has(key) or not stacks.has(key) or stacks[key].recipe_guid.is_empty():
			return {"ok": false, "error": "Unknown, duplicate or inactive crafting stack"}
		seen[key] = true
		order.append(key)
	for stack in stacks.values():
		# An incomplete paused original can legitimately lack held ingredients.
		# Zero progress is an active task too. Neither case changes task identity.
		if not stack.recipe_guid.is_empty() and not seen.has(stack.id):
			return {"ok": false, "error": "Missing active crafting stack"}
	return {"ok": true, "activation_order": order}

func apply_state(staged: Dictionary) -> void:
	reset()
	var session = _session.get_ref()
	# Staged references are already unique/live. Rebuild in linear time rather
	# than pruning the growing list once per restored task.
	for id in staged.activation_order:
		var stack = session.stacks[id]
		stack.craft_generation += 1
		_tasks.append({"stack": stack, "generation": stack.craft_generation, "recipe": stack.recipe_guid})
