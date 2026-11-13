extends RefCounted
## InfoPanel.cs priority, then most recent request; request keys retain ownership.
var requests: Dictionary = {}
var serial := 0
func submit(key: String, priority: int, info: Dictionary) -> void:
	if info.is_empty():
		requests.erase(key)
		return
	# Source increments RequestID on every request, even identical text.
	# Only InfoPanel.UpdateInfo suppresses redundant text writes, not arbitration.
	serial += 1
	requests[key] = {"priority": priority, "serial": serial, "info": info.duplicate(true)}
func current() -> Dictionary:
	var winner: Dictionary = {}
	for request in requests.values():
		if winner.is_empty() or request.priority > winner.priority or (request.priority == winner.priority and request.serial > winner.serial): winner = request
	return winner.get("info", {})
