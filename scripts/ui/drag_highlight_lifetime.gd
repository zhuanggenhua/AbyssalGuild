extends RefCounted
## Event-driven source manager lists. No tick, GUI, lock or eligibility recheck.
var cards: Array[WeakRef] = []
var zones: Array[WeakRef] = []
var last_error: Dictionary = {}
func _write(target: Object,value: bool) -> void:
	if target.has_method("set_drag_target"): target.set_drag_target(value)
	else: target.set_highlighted(value)
func capture(session, views: Dictionary, zone_records: Array, zone_views: Dictionary, lifted_id: int) -> Dictionary:
	var captured: Dictionary = {}
	var lifted = session.cards[lifted_id]
	for stack in session.stacks.values():
		if stack.card_ids.is_empty(): continue
		var bottom_id: int = stack.card_ids.back()
		var bottom = session.cards[bottom_id]
		var compatible: bool = session.can_stack(lifted.definition_guid,bottom.definition_guid)
		if compatible and bottom_id != lifted_id and stack.id != lifted.stack_id and stack.recipe_guid.is_empty():
			if not views.has(bottom_id):
				last_error={"error":"missing_live_target","id":bottom_id}
				continue
			_write(views[bottom_id],true)
			cards.append(weakref(views[bottom_id]))
			captured[bottom_id]={"stack_id":stack.id,"card_id":bottom_id}
	var held: Array = session.stacks[lifted.stack_id].card_ids
	for zone in zone_records:
		var valid: bool = zone.kind == "buyer" or (zone.kind == "vendor" and zone.active)
		if not valid: continue
		for id in held:
			var card = session.cards[id]
			var fields: Dictionary = session.catalog.fields(card.definition_guid)
			var chest: bool = session.world._is_chest(id)
			if zone.kind == "buyer": valid=bool(fields.get("isSellable",true)) and (not chest or card.stored_coins<=0)
			else: valid=int(fields.get("category",0))==7 or (chest and card.stored_coins>0)
			if not valid: break
		if valid and zone_views.has(int(zone.index)):
			_write(zone_views[int(zone.index)],true)
			zones.append(weakref(zone_views[int(zone.index)]))
	return captured
func _clear(entries: Array[WeakRef]) -> bool:
	for i in entries.size():
		var object: Object=entries[i].get_ref()
		if object==null or not is_instance_valid(object):
			last_error={"error":"source_missing_reference","index":i}
			return false
		_write(object,false)
	entries.clear()
	return true
func accepted_up() -> bool:
	return _clear(cards) and _clear(zones)
func enter_combat() -> bool: return _clear(cards)
func dispose() -> void:
	cards.clear(); zones.clear(); last_error.clear()
