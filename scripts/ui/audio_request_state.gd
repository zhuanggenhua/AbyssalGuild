extends RefCounted
## Original implementation of AudioManager's mixer coroutine and slot state.
## Caller advances only Unity-equivalent scaled time, not wall/audio time.
var mixer_bgm_db := 0.0
var waits: Array[Dictionary] = []
var slots: Dictionary = {}
func set_mixer(value: float) -> void:
	mixer_bgm_db = value
func request_interrupt(clip_seconds: float) -> bool:
	if mixer_bgm_db < 0.0: return false
	waits.append({"remaining": maxf(0.0, clip_seconds), "restore_db": mixer_bgm_db})
	mixer_bgm_db = -80.0
	return true
func advance_scaled_time(delta: float) -> void:
	# WaitForSeconds cannot finish while timeScale is zero. Resume in insertion
	# order when multiple independent coroutines become eligible in one frame.
	if delta <= 0.0 or not is_finite(delta): return
	var pending: Array[Dictionary] = []
	for wait in waits:
		wait.remaining -= delta
		if wait.remaining <= 0.000000001: mixer_bgm_db = float(wait.restore_db)
		else: pending.append(wait)
	waits = pending
func configure_slot(index: int, pitch: float, world_position: Variant = null) -> Dictionary:
	var previous: Dictionary = slots.get(index, {"world_position": Vector3.ZERO})
	var state := {"pitch": pitch, "spatial_blend": 0.0 if world_position == null else 1.0, "world_position": previous.world_position}
	if world_position is Vector3: state.world_position = world_position
	slots[index] = state
	return state
func reset() -> void:
	waits.clear()
	slots.clear()
