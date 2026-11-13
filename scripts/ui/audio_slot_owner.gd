extends RefCounted
## Persistent logical AudioSource ownership. Spatial admission is deliberately
## unsupported until an explicit renderer policy supplies verified parameters.
const Coordinates = preload("res://scripts/ui/listener_coordinates.gd")
var anchor: AudioStreamPlayer
var voices: Array[Node] = []
var state: Dictionary = {"pitch":1.0, "spatial_blend":0.0, "world_position":Vector3.ZERO}
var gain_db := 0.0
var spatial_policy: Callable
var closed := false

func _init(root_voice: AudioStreamPlayer, policy: Callable = Callable()) -> void:
	anchor = root_voice
	spatial_policy = policy
	voices.append(anchor)

func supports(next_state: Dictionary) -> bool:
	return not closed and (float(next_state.get("spatial_blend", 0)) == 0 or spatial_policy.is_valid())

func _new_voice(spatial: bool) -> Node:
	var voice: Node = AudioStreamPlayer3D.new() if spatial else AudioStreamPlayer.new()
	anchor.add_child(voice)
	voice.finished.connect(_voice_finished.bind(voice))
	return voice

func _voice_finished(voice: Node) -> void:
	voices.erase(voice)
	if is_instance_valid(voice):
		voice.stream = null
		voice.queue_free()

func _remove_voice(voice: Node) -> void:
	voice.stop()
	voice.stream = null
	if voice != anchor: voice.queue_free()

func _collect_finished() -> void:
	for index in range(voices.size()-1, -1, -1):
		var voice := voices[index]
		if not is_instance_valid(voice): voices.remove_at(index)
		elif voice != anchor and not voice.playing:
			_remove_voice(voice)
			voices.remove_at(index)

func _apply(voice: Node) -> void:
	voice.volume_db = gain_db
	voice.pitch_scale = float(state.get("pitch", 1.0))
	if voice is AudioStreamPlayer3D:
		voice.global_position = Coordinates.slot_position(state)
		# Renderer must configure acoustics, never silently fold stereo to mono.
		spatial_policy.call(voice, state.duplicate(true))

func play(next_state: Dictionary, stream: AudioStream) -> bool:
	if stream == null or not supports(next_state): return false
	_collect_finished()
	var spatial := float(next_state.get("spatial_blend",0)) > 0
	state = next_state.duplicate(true)
	# Unity mutates the entire source, including its already-playing one-shots.
	# Godot node classes cannot change dimensionality. Rebuild only at that
	# boundary, preserving transport position. Mixer-buffer continuity is NOT
	# claimed across reconstruction; this requires future acoustic validation.
	for index in voices.size():
		var old := voices[index]
		if (old is AudioStreamPlayer3D) != spatial:
			var was_playing: bool = old.playing
			var old_stream: AudioStream = old.stream
			var cursor: float = old.get_playback_position() if was_playing else 0.0
			_remove_voice(old)
			var replacement := _new_voice(spatial)
			voices[index] = replacement
			_apply(replacement)
			replacement.stream = old_stream
			if was_playing: replacement.play(cursor)
		else: _apply(old)
	var voice: Node = null
	for candidate in voices:
		if not candidate.playing:
			voice = candidate
			break
	if voice == null:
		voice = _new_voice(spatial)
		voices.append(voice)
	_apply(voice)
	voice.stream = stream
	voice.play()
	return true

func set_gain(value: float) -> void:
	gain_db = value
	for voice in voices:
		if is_instance_valid(voice): voice.volume_db = value

func stop() -> void:
	for voice in voices:
		if is_instance_valid(voice): _remove_voice(voice)
	voices.clear()
	if is_instance_valid(anchor): voices.append(anchor)

func shutdown() -> void:
	stop()
	closed = true
	spatial_policy = Callable()
