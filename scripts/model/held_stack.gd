extends RefCounted
## A live pointer hold, deliberately excluded from native save data.
## Geometry, input grants and equipment/combat pickup belong to the board.
const Stack = preload("res://scripts/model/stack.gd")
var _session: WeakRef
var card_id: int = -1
var stack_id: int = -1
var _original_stack_id: int = -1
var transitioning: bool = false

func configure(session) -> void:
	_session = weakref(session)
	reset()

func reset() -> void:
	card_id = -1
	stack_id = -1
	_original_stack_id = -1
	transitioning = false

func active() -> bool:
	return card_id >= 0

## Only the genuine held stack may bypass its original active-craft gate.
## A payment can consume the original leading card while leaving its tail.
func original_stack_id(incoming_id: int = -1) -> int:
	var session = _session.get_ref()
	if not active() or not session.stacks.has(_original_stack_id):
		return -1
	if incoming_id >= 0 and (not session.cards.has(incoming_id) or session.cards[incoming_id].stack_id != stack_id):
		return -1
	return _original_stack_id

## Same-card repeated press is harmless; another press must not orphan a hold.
## A first-card/whole-stack press preserves both its identity and running craft.
func begin(id: int, lifted_position: Variant = null) -> Dictionary:
	var session = _session.get_ref()
	if transitioning:
		return {"ok": false, "error": "Held-stack transition in progress"}
	if active():
		return {"ok": id == card_id, "stack_id": stack_id, "original_stack_id": original_stack_id(), "repeated": true}
	if not session.cards.has(id) or session.equipment.owners.has(id) or session.combat.membership.has(id):
		return {"ok": false, "error": "Card is not a board-stack member"}
	var source = session.stacks.get(session.cards[id].stack_id)
	if source == null or not source.card_ids.has(id):
		return {"ok": false, "error": "Card has no registered stack"}
	var index: int = source.card_ids.find(id)
	var position: Vector2 = session.card_target_position(id)
	if lifted_position is Vector2 and lifted_position.is_finite():
		position = lifted_position
	transitioning = true
	card_id = id
	stack_id = source.id
	if index > 0:
		var tail = Stack.new(session._next_id)
		session._next_id += 1
		tail.position = position
		tail.card_ids = source.card_ids.slice(index)
		source.card_ids = source.card_ids.slice(0, index)
		session.stacks[tail.id] = tail
		stack_id = tail.id
		for member in tail.card_ids:
			session.cards[member].stack_id = tail.id
			session.cards[member].position = position
		if not source.recipe_guid.is_empty():
			_original_stack_id = source.id
			source.paused = true
		else:
			# Source checks the remaining base, never the carried tail, on pickup.
			session._check_recipe(source)
	transitioning = false
	session.changed.emit()
	return {"ok": true, "stack_id": stack_id, "original_stack_id": original_stack_id(), "split": index > 0, "repeated": false}

## Call after ordinary attach/placement, including an invalid target or click.
## A handled chest deposit counts as attachment even if some cards remain.
func finish_standard(attached_stack_id: int = -1) -> void:
	if not active() or transitioning:
		return
	var session = _session.get_ref()
	transitioning = true
	var original = session.stacks.get(_original_stack_id)
	if original != null and not original.recipe_guid.is_empty():
		if attached_stack_id != original.id:
			session._validate_craft(original)
		if not original.recipe_guid.is_empty():
			original.paused = false
	if attached_stack_id < 0:
		var held = session.stacks.get(stack_id)
		if held != null and not held.card_ids.is_empty() and held.recipe_guid.is_empty():
			session._check_recipe(held)
	reset()
	session.changed.emit()

## Only successful terminal trade, equip or combat actions stop the old task.
## Partial vendor payment is not terminal and must use finish_standard instead.
func finish_terminal() -> void:
	if not active() or transitioning:
		return
	var session = _session.get_ref()
	transitioning = true
	var original = session.stacks.get(_original_stack_id)
	if original != null:
		original.cancel_craft()
	reset()
	session.changed.emit()

## Used only on an isolated native checkpoint clone, never serialized itself.
func copy_hold_from(other) -> void:
	card_id = other.card_id
	stack_id = other.stack_id
	_original_stack_id = other._original_stack_id
	transitioning = false
