extends SceneTree
const State = preload("res://scripts/ui/audio_request_state.gd")
const Feedback = preload("res://scripts/ui/audio_feedback.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _init() -> void: call_deferred("run")
func sample(seconds: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 8000
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	var bytes := PackedByteArray()
	bytes.resize(int(16000*seconds))
	stream.data = bytes
	return stream
func run() -> void:
	var state = State.new()
	state.set_mixer(-0.01)
	check(not state.request_interrupt(1) and state.waits.is_empty(), "negative mixer gain does not duck even when audible")
	state.set_mixer(0)
	check(state.request_interrupt(2) and state.mixer_bgm_db == -80, "exact zero gain ducks immediately")
	check(not state.request_interrupt(1) and state.waits.size() == 1, "muted gain suppresses duplicate coroutine")
	state.advance_scaled_time(0)
	check(state.waits[0].remaining == 2 and state.mixer_bgm_db == -80, "timeScale zero freezes wait, not audio playback")
	state.advance_scaled_time(1)
	check(state.mixer_bgm_db == -80, "wait is clip seconds, not pitch-adjusted duration")
	state.set_mixer(-6)
	state.advance_scaled_time(1)
	check(state.mixer_bgm_db == 0, "source coroutine overwrites intervening user mixer change with captured gain")
	state.set_mixer(3)
	state.request_interrupt(3)
	state.set_mixer(0)
	state.request_interrupt(1)
	check(state.waits.size() == 2, "manual reset permits concurrent independent coroutine")
	state.advance_scaled_time(1)
	check(state.mixer_bgm_db == 0 and state.waits.size() == 1, "later short coroutine can restore before earlier long one")
	state.advance_scaled_time(2)
	check(state.mixer_bgm_db == 3, "older long coroutine restores own captured value, not latest preference")
	var first: Dictionary = state.configure_slot(0, 1.03, Vector3(2,3,4))
	check(first.spatial_blend == 1 and first.world_position == Vector3(2,3,4), "explicit position sets fully spatial blend")
	var second: Dictionary = state.configure_slot(0, 0.97)
	check(second.spatial_blend == 0 and second.world_position == Vector3(2,3,4), "null changes blend but source retains old transform position")
	state.reset()
	check(state.slots.is_empty() and state.waits.is_empty(), "destroy/reset cancels pending coroutine")
	var audio = Feedback.new()
	root.add_child(audio)
	audio.cooldown = 0
	audio.source_settings = {"_randomizeSFXPitch": false, "_defaultMusicVolume": 0.3}
	audio.clips = {"A": "a"}
	audio.stream_cache.a = sample(2)
	var slot := AudioStreamPlayer.new()
	audio.add_child(slot)
	audio.pool.append(slot)
	audio.music = AudioStreamPlayer.new()
	audio.add_child(audio.music)
	audio.music.stream = sample(4)
	audio.music.play()
	check(audio.play_source_event("A", null, true), "default renderer starts requested clip and interrupt")
	check(is_equal_approx(audio.music.volume_linear, 0.3*db_to_linear(-80)), "mixer duck multiplies source clip gain once")
	check(audio.music.playing, "duck does not pause/restart music transport")
	audio.advance_scaled_time(2)
	check(is_equal_approx(audio.music.volume_linear, 0.3), "scaled wait restores live music gain")
	var calls: Array = []
	audio.spatial_policy = func(voice, config):
		calls.append([voice, config.duplicate(true)])
	check(audio.play_source_event("A", Vector3(1,2,3), false) and calls.size() >= 2, "spatial policy configures old and new actual voices")
	check(calls[0][1].spatial_blend == 1 and calls[0][0] is AudioStreamPlayer3D, "active earlier voice migrated through logical source owner")
	check(audio.play_source_event("A", null, false) and audio._owner_for(slot).voices.all(func(v):return v is AudioStreamPlayer), "spatial-to-2D wrap converts whole-slot")
	audio.spatial_policy = Callable()
	check(not audio.play_source_event("A", Vector3.ONE), "unavailable positional renderer is explicit failure, never silent 2D substitute")
	check(audio.play_event("A"), "rejected unsupported position does not poison subsequent default 2D playback")
	audio.shutdown()
	check(audio.requests.waits.is_empty() and not audio.play_source_event("A", null, true), "shutdown cancels waits and prevents post-shutdown admission")
	audio.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Audio optional contract: %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
