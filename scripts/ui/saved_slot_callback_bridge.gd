extends RefCounted
## Select the existing row through its existing signal, then request its action.
## No filesystem write, archive operation, or confirmation implementation lives here.
var selector: OptionButton
var load_action: Callable
var archive_action: Callable
var allowed: Callable
func request(slot: int, archive: bool) -> bool:
	if selector == null or (allowed.is_valid() and not allowed.call()): return false
	for index in selector.item_count:
		if selector.get_item_id(index) != slot: continue
		var metadata: Variant = selector.get_item_metadata(index)
		if not metadata is Dictionary or (not archive and not metadata.get("valid",false)): return false
		var action: Callable = archive_action if archive else load_action
		if not action.is_valid(): return false
		selector.select(index)
		selector.item_selected.emit(index)
		if allowed.is_valid() and not allowed.call(): return false
		action.call()
		return true
	return false # A stale row cannot act on another currently selected save.
