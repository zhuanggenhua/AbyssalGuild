extends RefCounted
## QuestsView button lifetime, separate from QuestManager/save state.
## A caption is created once; only the source completion signal appends its mark.
const Groups = preload("res://scripts/ui/journal_groups.gd")
signal changed
var order: Array[String] = []
var _rows: Dictionary = {}
var _tracker: WeakRef
var _populating := false

func bind(tracker) -> void:
	clear()
	_tracker = weakref(tracker)
	tracker.quest_activated.connect(_created)
	tracker.quest_completed.connect(_completed)
	# Source PopulateView visits Completed + Active, inserting after the header.
	_populating = true
	for instance in tracker.all_quests(): _created(instance)
	_populating = false

func clear() -> void:
	var tracker = _tracker.get_ref() if _tracker != null else null
	if tracker != null:
		if tracker.quest_activated.is_connected(_created): tracker.quest_activated.disconnect(_created)
		if tracker.quest_completed.is_connected(_completed): tracker.quest_completed.disconnect(_completed)
	_tracker = null
	_rows.clear()
	order.clear()

func _created(instance: Dictionary) -> void:
	var tracker = _tracker.get_ref() if _tracker != null else null
	if tracker == null: return
	var id: String = str(instance.get("id", ""))
	if id.is_empty() or not tracker.definitions.has(id): return
	if _rows.has(id) and is_same(_rows[id].instance, instance): return
	var fields: Dictionary = tracker.definitions[id]
	var title: String = "• " + str(fields.get("title", id))
	if Groups.quest_complete(fields, instance): title += " √"
	_rows[id] = {"instance":instance, "caption":title}
	# A replacement restored instance gets a new presentation, not the old latch.
	order.erase(id)
	order.push_front(id)
	if not _populating: changed.emit()

func _completed(instance: Dictionary) -> void:
	var id: String = str(instance.get("id", ""))
	if not _rows.has(id) or not is_same(_rows[id].instance, instance): return
	if not str(_rows[id].caption).ends_with(" √"):
		_rows[id].caption += " √"
		changed.emit()

func caption(id: String) -> String:
	return str(_rows.get(id, {}).get("caption", ""))

func captions() -> Dictionary:
	var result := {}
	for id in _rows: result[id] = caption(id)
	return result

func info(id: String) -> Dictionary:
	var tracker = _tracker.get_ref() if _tracker != null else null
	if tracker == null or not _rows.has(id) or not tracker.definitions.has(id): return {}
	return Groups.quest_info(tracker.definitions[id], _rows[id].instance)
