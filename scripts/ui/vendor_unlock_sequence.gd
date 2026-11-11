extends RefCounted
## Live-only vendor reveal timeline. Activation is immediate; reveals are FIFO.
## Restore uses the finalized scene/quest state and never replays unlocks.
signal sequence_started(zone: Dictionary)
signal sequence_finished(zone: Dictionary)
const FOCUS_SECONDS: float = 0.5
const HOLD_SECONDS: float = 2.0
var stage: String = "idle"
var remaining: float = 0.0
var current: Dictionary = {}
var pending: Array[int] = []
var _activated: Dictionary = {}
var _zones: Dictionary = {}
var _generation: int = 0

func is_active() -> bool:
	return stage != "idle"

func restore(zones: Array) -> void:
	cancel()
	_activated.clear()
	update_zones(zones)
	for index in _zones:
		if bool(_zones[index].get("active", false)):
			_activated[index] = true

## Geometry can change while a different vendor's reveal is in progress.
## Queued vendors sample their latest position when their camera move starts.
## Merely rebuilding UI does not manufacture a quest-completed event.
func update_zones(zones: Array) -> void:
	_zones.clear()
	for zone in zones:
		if zone.get("kind", "") == "vendor":
			_zones[int(zone.index)] = zone.duplicate(true)

func on_quest_completed(zones: Array) -> void:
	update_zones(zones)
	for zone in zones:
		if zone.get("kind", "") != "vendor" or not bool(zone.get("active", false)):
			continue
		var index: int = int(zone.index)
		if _activated.has(index):
			continue
		# Claim all eligible vendors before starting any sequence. Nested/repeated
		# quest notifications cannot enqueue a vendor twice.
		_activated[index] = true
		pending.append(index)
	_start_next()

## Unscaled, one yielded boundary per frame, like the other native timelines.
## A large frame finishes focus OR hold; it cannot skip the following wait.
func advance(real_delta: float) -> void:
	if not is_active() or not is_finite(real_delta) or real_delta <= 0:
		return
	remaining = maxf(0.0, remaining - real_delta)
	if remaining > 0.0000001:
		return
	if stage == "focus":
		stage = "hold"
		remaining = HOLD_SECONDS
		return
	var finished: Dictionary = current.duplicate(true)
	var generation: int = _generation
	stage = "idle"
	remaining = 0.0
	current.clear()
	# Listeners remove only this reveal's highlight, info and pause ownership.
	# Cancellation/rebinding from a listener must not start an old queued item.
	sequence_finished.emit(finished)
	if generation == _generation:
		_start_next()

func cancel() -> void:
	_generation += 1
	pending.clear()
	var finished: Dictionary = current.duplicate(true)
	stage = "idle"
	remaining = 0.0
	current.clear()
	_zones.clear()
	if not finished.is_empty():
		sequence_finished.emit(finished)

func _start_next() -> void:
	if is_active():
		return
	while not pending.is_empty():
		var index: int = pending.pop_front()
		if not _zones.has(index):
			continue
		current = _zones[index].duplicate(true)
		stage = "focus"
		remaining = FOCUS_SECONDS
		sequence_started.emit(current.duplicate(true))
		return

func info() -> Dictionary:
	if not is_active():
		return {}
	return {"header": "Pack Unlocked", "body": "You can buy %s card pack here." % str(current.get("title", ""))}
