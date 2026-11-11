extends Node
## Source AudioId names resolved through the original AudioManager prefab.
## Call play_event only at the corresponding confirmed source event.
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

func configure(catalog, visual_assets) -> void:
	assets = visual_assets
	next_player = 0
	clips.clear()
	stream_cache.clear()
	last_played.clear()
	source_settings.clear()
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
	if pool.is_empty() or not is_inside_tree():
		return false
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - float(last_played.get(event_name, -INF)) < cooldown:
		return false
	# Source records an admitted request even when the AudioId has no clip.
	last_played[event_name] = now
	var stream := stream_for_event(event_name)
	if stream == null:
		return false
	var player: AudioStreamPlayer = pool[next_player]
	next_player = (next_player + 1) % pool.size()
	# Unity PlayOneShot overlaps even when a pooled source wraps. Reassigning a
	# Godot player's stream would cut off its earlier sound, so keep that voice
	# and add a temporary child only while this logical source is occupied.
	var voice := player
	if player.playing:
		voice = AudioStreamPlayer.new()
		player.add_child(voice)
		voice.finished.connect(voice.queue_free)
	var pitch: float = randf_range(0.95, 1.05) if bool(source_settings.get("_randomizeSFXPitch", true)) else 1.0
	# Source pitch is a property of the pooled AudioSource, including sounds
	# already playing on it. Godot child players do not inherit audio gain/pitch.
	for active_voice in _slot_voices(player):
		active_voice.volume_db = user_sfx_db
		active_voice.pitch_scale = pitch
	voice.stream = stream
	voice.play()
	return true

func _slot_voices(player: AudioStreamPlayer) -> Array[AudioStreamPlayer]:
	var voices: Array[AudioStreamPlayer] = [player]
	for child in player.get_children():
		if child is AudioStreamPlayer:
			voices.append(child)
	return voices

func _stop_slot(player: AudioStreamPlayer) -> void:
	for voice in _slot_voices(player):
		voice.stop()
		voice.stream = null

func play_music() -> bool:
	if not is_inside_tree():
		return false
	var stream := _stream(str(source_settings.get("_BGMClip", {}).get("guid", "")))
	if stream == null:
		return false # Missing licensed music is silent, never substituted.
	if music == null:
		music = AudioStreamPlayer.new()
		add_child(music)
		music.finished.connect(func(): music.play())
	music.stream = stream
	music.volume_linear = music_gain_linear()
	music.play()
	return true

func _exit_tree() -> void:
	# Stop playback and release stream references before the audio server shuts down.
	for player in pool:
		if is_instance_valid(player):
			_stop_slot(player)
	if is_instance_valid(music):
		music.stop()
		music.stream = null
	stream_cache.clear()
	last_played.clear()
	assets = null

func music_gain_linear() -> float:
	# Source per-clip gain and user mixer gain multiply once, never accumulate.
	return maxf(0.0, float(source_settings.get("_defaultMusicVolume", 0.3))) * db_to_linear(user_bgm_db)

func set_user_gains(sfx_db: float, bgm_db: float) -> bool:
	if not is_finite(sfx_db) or not is_finite(bgm_db) or sfx_db < -80 or sfx_db > 0 or bgm_db < -80 or bgm_db > 0: return false
	user_sfx_db = sfx_db
	user_bgm_db = bgm_db
	for player in pool:
		if is_instance_valid(player):
			for voice in _slot_voices(player):
				voice.volume_db = user_sfx_db
	if is_instance_valid(music): music.volume_linear = music_gain_linear()
	return true
