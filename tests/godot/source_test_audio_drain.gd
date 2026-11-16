extends RefCounted
## Fixture-only guard for already-started native audio. Does not alter production
## mute, stop order, scene transitions or audio source admission.
const TIMEOUT_MS := 2500
var observed: Array[WeakRef] = []


func observe_music(player: AudioStreamPlayer) -> void:
	if not is_instance_valid(player) or not player.has_stream_playback():
		return
	var stream := player.stream
	var playback := player.get_stream_playback()
	if stream != null:
		observed.append(weakref(stream))
	if playback != null:
		observed.append(weakref(playback))


func wait_after_teardown(tree: SceneTree) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while _has_live_reference():
		if Time.get_ticks_msec() >= deadline:
			return false
		await tree.process_frame
	return true


func _has_live_reference() -> bool:
	for receipt in observed:
		if receipt.get_ref() != null:
			return true
	return false
