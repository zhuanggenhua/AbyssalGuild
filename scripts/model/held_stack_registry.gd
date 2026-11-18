extends RefCounted
## One physical held-stack transaction per accepted card root. Contact ownership
## and combat presentation are outside this registry; the mouse API remains single.
const HeldStack = preload("res://scripts/model/held_stack.gd")
var _session: WeakRef
var _legacy := HeldStack.new()
var _contexts: Dictionary = {}
# Admission order also defines the native checkpoint's isolated settlement order.
var _ordered: Array = []

var card_id: int:
	get: return _legacy.card_id
	set(value): _legacy.card_id = value
var stack_id: int:
	get: return _legacy.stack_id
	set(value): _legacy.stack_id = value
var _original_stack_id: int:
	get: return _legacy._original_stack_id
	set(value): _legacy._original_stack_id = value
var transitioning: bool:
	get:
		if _legacy.transitioning: return true
		for hold in _contexts.values():
			if hold.transitioning: return true
		return false
	set(value): _legacy.transitioning = value

func configure(session) -> void:
	_session = weakref(session)
	_legacy.configure(session)
	reset()

func reset() -> void:
	_legacy.reset()
	for hold in _contexts.values():
		hold.reset()
	_contexts.clear()
	_ordered.clear()

func _active_holds() -> Array:
	var holds: Array = []
	for hold in _ordered:
		if hold.active(): holds.append(hold)
	# Compatibility for diagnostic callers assigning the old card_id directly.
	if _legacy.active() and _legacy not in holds: holds.append(_legacy)
	return holds

func active() -> bool:
	if _legacy.active(): return true
	for hold in _contexts.values():
		if hold.active(): return true
	return false

func active_for(root_id: int) -> bool:
	return _context_for(root_id) != null

func held_ids() -> Array:
	var ids: Array = []
	for hold in _active_holds(): ids.append(hold.card_id)
	return ids

func held_stack_id_for(root_id: int) -> int:
	var hold = _context_for(root_id)
	return hold.stack_id if hold != null else -1

func owns_stack(stack: int) -> bool:
	if stack < 0: return false
	for hold in _active_holds():
		if hold.stack_id == stack: return true
	return false

func _context_for(root_id: int):
	if root_id < 0: return null
	if _legacy.card_id == root_id: return _legacy
	var hold = _contexts.get(root_id)
	return hold if hold != null and hold.active() else null

## A later child can split again: the original held root keeps the base stack
## identity while the new root receives a disjoint tail. A previously captured
## paused crafting base, or a stack whose original root has disappeared, remains
## guarded until its separate source-order cases are verified.
## An ordinary release may still attach to another held stack; the source permits it.
func _can_start(root_id: int) -> bool:
	var session = _session.get_ref()
	if not session.cards.has(root_id) or session.equipment.owners.has(root_id) or session.combat.membership.has(root_id):
		return false
	var source = session.stacks.get(session.cards[root_id].stack_id)
	if source == null or root_id not in source.card_ids: return false
	var index: int = source.card_ids.find(root_id)
	for hold in _active_holds():
		if source.id == hold.original_stack_id(): return false
		if source.id == hold.stack_id:
			var existing_index: int = source.card_ids.find(hold.card_id)
			if existing_index < 0 or index <= existing_index: return false
	return true

func can_begin_for(root_id: int) -> bool:
	if transitioning: return false
	var hold = _context_for(root_id)
	return (hold != null and hold != _legacy) or (hold == null and _can_start(root_id))

func begin_for(root_id: int, lifted_position: Variant = null) -> Dictionary:
	if not can_begin_for(root_id): return {"ok": false, "error": "Conflicting or invalid held-stack pickup"}
	var hold = _context_for(root_id)
	if hold != null: return hold.begin(root_id, lifted_position)
	hold = HeldStack.new()
	hold.configure(_session.get_ref())
	_contexts[root_id] = hold
	_ordered.append(hold)
	var result: Dictionary = hold.begin(root_id, lifted_position)
	if not result.ok: _forget_explicit(root_id, hold)
	return result

func original_stack_id_for(root_id: int, incoming_id: int = -1) -> int:
	var hold = _context_for(root_id)
	return hold.original_stack_id(incoming_id) if hold != null else -1

func finish_standard_for(root_id: int, attached_stack_id: int = -1) -> void:
	var hold = _context_for(root_id)
	if hold == null or transitioning: return
	hold.finish_standard(attached_stack_id)
	if hold == _legacy:
		if not _legacy.active(): _ordered.erase(_legacy)
	else:
		_forget_explicit(root_id, hold)

func finish_terminal_for(root_id: int) -> void:
	var hold = _context_for(root_id)
	if hold == null or transitioning: return
	hold.finish_terminal()
	if hold == _legacy:
		if not _legacy.active(): _ordered.erase(_legacy)
	else:
		_forget_explicit(root_id, hold)

func _forget_explicit(root_id: int, hold) -> void:
	if _contexts.get(root_id) == hold: _contexts.erase(root_id)
	_ordered.erase(hold)

## Legacy pointer methods cannot steal a different root's transient ownership.
func begin(id: int, lifted_position: Variant = null) -> Dictionary:
	if transitioning: return {"ok": false, "error": "Held-stack transition in progress"}
	if _legacy.active(): return _legacy.begin(id, lifted_position)
	if not _can_start(id): return {"ok": false, "error": "Conflicting or invalid held-stack pickup"}
	_ordered.erase(_legacy)
	_ordered.append(_legacy)
	var result := _legacy.begin(id, lifted_position)
	if not result.ok: _ordered.erase(_legacy)
	return result

func original_stack_id(incoming_id: int = -1) -> int:
	return _legacy.original_stack_id(incoming_id)

func finish_standard(attached_stack_id: int = -1) -> void:
	finish_standard_for(_legacy.card_id, attached_stack_id)

func finish_terminal() -> void:
	finish_terminal_for(_legacy.card_id)

## Used only to copy transient contexts to an isolated native checkpoint clone.
func copy_hold_from(other) -> void:
	reset()
	for source in other._active_holds():
		var hold = _legacy if source == other._legacy else HeldStack.new()
		hold.configure(_session.get_ref())
		hold.copy_hold_from(source)
		if hold != _legacy: _contexts[hold.card_id] = hold
		_ordered.append(hold)
