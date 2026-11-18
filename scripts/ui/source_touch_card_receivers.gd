extends RefCounted
## Scene-scoped card pointerPress ledger. A receiver is independent of a
## CardController accepting its own down; up goes to the original view, not
## the hovered view or the current global Pointer. No drag/GUI policy here.
## The input adapter must supply admitted UI edges from its actual event route.

var _receivers: Dictionary = {}

func capture(index: int, card_view: Object) -> bool:
	if index < 0 or _receivers.has(index) or not is_instance_valid(card_view):
		return false
	_receivers[index] = weakref(card_view)
	return true

func release(index: int) -> Object:
	if not _receivers.has(index): return null
	var former: WeakRef = _receivers[index]
	_receivers.erase(index)
	return former.get_ref()

func owns(index: int) -> bool:
	return _receivers.has(index)

func reset() -> void:
	_receivers.clear()
