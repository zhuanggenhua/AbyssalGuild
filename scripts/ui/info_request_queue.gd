extends RefCounted
## InfoPanel.cs priority, then most recent request; request keys retain ownership.
var requests: Dictionary = {}
var serial := 0
func submit(key: String, priority: int, info: Dictionary) -> void:
	if info.is_empty():
		requests.erase(key)
		return
	if requests.has(key) and requests[key].info == info and requests[key].priority == priority: return
	serial += 1
	requests[key] = {"priority": priority, "serial": serial, "info": info.duplicate(true)}
func current() -> Dictionary:
	var winner: Dictionary = {}
	for request in requests.values():
		if winner.is_empty() or request.priority > winner.priority or (request.priority == winner.priority and request.serial > winner.serial): winner = request
	return winner.get("info", {})
