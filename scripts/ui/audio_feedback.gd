extends Node
## Source AudioId names resolved through the original AudioManager prefab.
## Call play_event only at the corresponding confirmed source event.
const RequestState = preload("res://scripts/ui/audio_request_state.gd")
var requests = RequestState.new()
var unscaled_frame_clock = preload("res://scripts/ui/audio_frame_clock.gd").new()
var source_initialized := false
## Optional explicit acoustic policy configures real 3D voices. No policy is
## installed by default. Persistent slot ownership handles all lifecycle paths.
const SlotOwner = preload("res://scripts/ui/audio_slot_owner.gd")
var spatial_policy: Callable = Callable()
var slot_owners: Dictionary = {}
var clips: Dictionary = {}
var stream_cache: Dictionary = {}
var last_played: Dictionary = {}
var pool: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var assets
var source_settings: Dictionary = {}
var next_player: int = 0
var cooldown: float = 0.05
var user_sfx_db: float = 0.0
var user_bgm_db: float = 0.0
var shutting_down: bool = false

func _enter_tree() -> void:
	# SceneTree's pre-process signal snapshots before Node._process callbacks.
	# Input callbacks may precede it; their first sample wins for that same token.
	if not get_tree().process_frame.is_connected(_sample_unscaled_frame):
		get_tree().process_frame.connect(_sample_unscaled_frame)

func _sample_unscaled_frame() -> void:
	unscaled_frame_clock.now()

func configure(catalog, visual_assets) -> void:
	shutting_down = false
	# A source singleton survives scene loads. Explicit media refresh may rebuild
	# voices but must not cancel its live coroutine or replace live mixer gain.
	requests.slots.clear()
	if not source_initialized: requests.set_mixer(user_bgm_db)
	source_initialized = true
	assets = visual_assets
	next_player = 0
	clips.clear()
	stream_cache.clear()
	last_played.clear()
	source_settings.clear()
	for owner in slot_owners.values(): owner.shutdown()
	slot_owners.clear()
	for player in pool:
		_stop_slot(player)
		player.queue_free()
	pool.clear()
	if music != null:
		music.stop()
		music.stream = null
		music.queue_free()
		music = null
	for prefab in catalog.data.get("referenced_prefabs", []):
		for document in prefab.get("documents", []):
			if document.get("script_class", "") == "AudioManager":
				source_settings = document.get("fields", {}).duplicate(true)
				break
	if source_settings.is_empty():
		return
	var names: Dictionary = {}
	for event_name in catalog.data.get("enums", {}).get("AudioId", {}):
		names[int(catalog.data.enums.AudioId[event_name])] = event_name
	for entry in source_settings.get("_SFXDataList", []):
		var id: int = int(entry.get("audioId", -1))
		if names.has(id):
			clips[names[id]] = str(entry.get("audioClip", {}).get("guid", ""))
	cooldown = maxf(0, float(source_settings.get("_SFXCooldown", 0.05)))
	for index in clampi(int(source_settings.get("_SFXPoolSize", 8)), 1, 64):
		var player := AudioStreamPlayer.new()
		player.volume_db = user_sfx_db
		add_child(player)
		pool.append(player)

func stream_for_event(event_name: String) -> AudioStream:
	return _stream(str(clips.get(event_name, "")))

func _stream(guid: String) -> AudioStream:
	if shutting_down: return null
	if stream_cache.has(guid):
		return stream_cache[guid]
	if assets == null:
		return null
	var entry: Dictionary = assets.manifest.get("assets", {}).get(guid, {})
	if entry.get("kind", "") != "wav":
		return null
	var relative: String = str(entry.get("path", ""))
	if relative.is_empty() or relative.is_absolute_path() or relative.contains("..") or relative.contains(":") or relative.contains("\\"):
		return null
	var path: String = assets.root_path + relative
	var remap := ConfigFile.new()
	if remap.load(path + ".import") == OK and FileAccess.file_exists(str(remap.get_value("remap", "path", ""))):
		var imported = ResourceLoader.load(path, "AudioStream")
		if imported is AudioStream:
			stream_cache[guid] = imported
			return imported
	if not FileAccess.file_exists(path):
		return null
	var stream := AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes(path))
	if stream != null:
		stream_cache[guid] = stream
	return stream

func play_event(event_name: String) -> bool:
	# Keep the established default API (including existing test/host overrides).
	return play_source_event(event_name)

func play_source_event(event_name: String, world_position: Variant = null, interrupt_bgm: bool = false) -> bool:
	if world_position != null and (not world_position is Vector3 or not world_position.is_finite()): return false
	if shutting_down or pool.is_empty() or not is_inside_tree():
		return false
	var now: float = unscaled_frame_clock.now()
	if now - float(last_played.get(event_name, -INF)) < cooldown:
		return false
	# Source records an admitted request even when the AudioId has no clip.
	last_played[event_name] = now
	var stream := stream_for_event(event_name)
	if stream == null:
		return false
	if world_position != null and not spatial_policy.is_valid(): return false
	var slot_index := next_player
	var player: AudioStreamPlayer = pool[next_player]
	next_player = (next_player + 1) % pool.size()
	var pitch: float = randf_range(0.95, 1.05) if bool(source_settings.get("_randomizeSFXPitch", true)) else 1.0
	var slot_state: Dictionary = requests.configure_slot(slot_index, pitch, world_position)
	var owner = _owner_for(player)
	if not owner.play(slot_state, stream): return false
	if interrupt_bgm: requests.request_interrupt(stream.get_length())
	_apply_music_mixer()
	return true

func _owner_for(player: AudioStreamPlayer):
	var key := player.get_instance_id()
	if not slot_owners.has(key):
		slot_owners[key] = SlotOwner.new(player, spatial_policy)
		slot_owners[key].set_gain(user_sfx_db)
	slot_owners[key].spatial_policy = spatial_policy
	return slot_owners[key]

func _slot_voices(player: AudioStreamPlayer) -> Array[AudioStreamPlayer]:
	var voices: Array[AudioStreamPlayer] = [player]
	for child in player.get_children():
		if child is AudioStreamPlayer:
			voices.append(child)
	return voices

func _stop_slot(player: AudioStreamPlayer) -> void:
	if slot_owners.has(player.get_instance_id()):
		slot_owners[player.get_instance_id()].stop()
		return
	for voice in _slot_voices(player):
		voice.stop()
		voice.stream = null

func play_music() -> bool:
	if shutting_down or not is_inside_tree():
		return false
	var stream := _stream(str(source_settings.get("_BGMClip", {}).get("guid", "")))
	if stream == null:
		return false # Missing licensed music is silent, never substituted.
	var looping_stream := _looping_music_stream(stream)
	if looping_stream == null: return false
	if music == null:
		music = AudioStreamPlayer.new()
		add_child(music)
	music.stream = looping_stream
	music.volume_linear = music_gain_linear()
	music.play()
	return true

static func _looping_music_stream(source: AudioStream) -> AudioStreamWAV:
	# Source AudioSource.loop loops the whole clip in the audio transport. Never
	# mutate the cached clip: a source may also be used by a one-shot SFX request.
	if not source is AudioStreamWAV or source.mix_rate <= 0: return null
	var frames := roundi(source.get_length() * source.mix_rate)
	if frames <= 0: return null
	var result: AudioStreamWAV = source.duplicate()
	result.loop_mode = AudioStreamWAV.LOOP_FORWARD
	result.loop_begin = 0
	result.loop_end = frames
	return result

func shutdown() -> void:
	# Close admission before stopping voices. A modal action requests Click after
	# its callback, and a queued music-finished signal must not restart playback.
	shutting_down = true
	source_initialized = false
	requests.reset()
	for owner in slot_owners.values(): owner.shutdown()
	slot_owners.clear()
	for player in pool:
		if is_instance_valid(player):
			_stop_slot(player)
	if is_instance_valid(music):
		music.stop()
		music.stream = null
	stream_cache.clear()
	last_played.clear()
	assets = null

func _exit_tree() -> void:
	if get_tree().process_frame.is_connected(_sample_unscaled_frame):
		get_tree().process_frame.disconnect(_sample_unscaled_frame)
	shutdown()

func music_gain_linear() -> float:
	# Source per-clip gain and user mixer gain multiply once, never accumulate.
	return maxf(0.0, float(source_settings.get("_defaultMusicVolume", 0.3))) * db_to_linear(requests.mixer_bgm_db)

func set_user_gains(sfx_db: float, bgm_db: float) -> bool:
	if not is_finite(sfx_db) or not is_finite(bgm_db) or sfx_db < -80 or sfx_db > 0 or bgm_db < -80 or bgm_db > 0: return false
	set_user_sfx_gain(sfx_db)
	set_user_bgm_gain(bgm_db)
	return true

func set_user_sfx_gain(sfx_db: float) -> bool:
	if not is_finite(sfx_db) or sfx_db < -80 or sfx_db > 0: return false
	user_sfx_db = sfx_db
	for owner in slot_owners.values(): owner.set_gain(sfx_db)
	for player in pool:
		if is_instance_valid(player):
			for voice in _slot_voices(player):
				voice.volume_db = user_sfx_db
	return true

func set_user_bgm_gain(bgm_db: float) -> bool:
	if not is_finite(bgm_db) or bgm_db < -80 or bgm_db > 0: return false
	user_bgm_db = bgm_db
	requests.set_mixer(bgm_db)
	if is_instance_valid(music): music.volume_linear = music_gain_linear()
	return true

func live_sfx_slider_value() -> float:
	return db_to_linear(user_sfx_db)

func live_bgm_slider_value() -> float:
	# Source GetSavedBGMVolumeSlider reads the live mixer, not PlayerPrefs.
	return db_to_linear(requests.mixer_bgm_db)

func advance_scaled_time(delta: float) -> void:
	if shutting_down: return
	requests.advance_scaled_time(delta)
	_apply_music_mixer()

func _apply_music_mixer() -> void:
	if is_instance_valid(music): music.volume_linear = music_gain_linear()
