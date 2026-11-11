extends SceneTree
const AudioFeedback = preload("res://scripts/ui/audio_feedback.gd")
const VisualAssets = preload("res://scripts/ui/visual_assets.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
var checks: int = 0
var failures: int = 0

func _init():
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func sample(seconds: float = 2.0) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 8000
	var silence := PackedByteArray()
	silence.resize(int(seconds * stream.mix_rate) * 2)
	stream.data = silence
	return stream

func voices(audio) -> Array[AudioStreamPlayer]:
	var result: Array[AudioStreamPlayer] = []
	for player in audio.pool:
		result.append(player)
		for child in player.get_children():
			if child is AudioStreamPlayer:
				result.append(child)
	return result

func run():
	var master_gain: float = AudioServer.get_bus_volume_db(0)
	var assets = VisualAssets.new()
	var catalog = Catalog.new()
	var fields: Dictionary = {
		"_SFXDataList": [
			{"audioId": 16, "audioClip": {"guid": "click"}},
			{"audioId": 3, "audioClip": {"guid": "coin"}},
			{"audioId": 4, "audioClip": {"guid": "coins"}},
			{"audioId": 14, "audioClip": {"guid": "pop"}},
		],
		"_SFXPoolSize": 2, "_SFXCooldown": 10.0, "_randomizeSFXPitch": false,
		"_BGMClip": {"guid": "music"}, "_defaultMusicVolume": 0.3,
	}
	catalog.data = {"enums": {"AudioId": {"Click": 16, "Coin": 3, "Coins": 4, "Pop": 14}}, "referenced_prefabs": [{"documents": [{"script_class": "AudioManager", "fields": fields}]}]}
	var audio = AudioFeedback.new()
	check(not audio.play_event("Click"), "detached and unconfigured audio is silent")
	check(audio.set_user_gains(-6.0206, -6.0206), "user gains can be set before configure")
	root.add_child(audio)
	audio.configure(catalog, assets)
	check(audio.clips.Click == "click" and audio.pool.size() == 2, "source AudioId mapping and logical pool size")
	check(is_equal_approx(audio.pool[0].volume_db, -6.0206), "new source slots retain user gain")
	check(audio.stream_for_event("missing") == null and not audio.play_music(), "missing SFX and music are not substituted")
	var streams: Dictionary = {}
	for event_name in audio.clips:
		streams[event_name] = sample()
		audio.stream_cache[audio.clips[event_name]] = streams[event_name]
	check(audio.play_event("Click"), "first event admitted")
	var stamp: float = audio.last_played.Click
	check(not audio.play_event("Click") and audio.last_played.Click == stamp and audio.next_player == 1, "cooldown skips without refreshing timestamp or advancing pool")
	check(audio.play_event("Coin") and audio.next_player == 0, "different AudioId has an independent cooldown")
	check(audio.play_event("Coins") and audio.next_player == 1, "third distinct clip wraps two-source pool")
	check(audio.pool[0].playing and audio.pool[0].stream == streams.Click, "wrapping preserves the previous source clip")
	check(audio.pool[0].get_child_count() == 1, "occupied source creates an overlapping one-shot voice")
	var overlap: AudioStreamPlayer = audio.pool[0].get_child(0)
	check(overlap.playing and overlap.stream == streams.Coins, "different clips play concurrently on one logical source")
	check(audio.play_event("Pop") and audio.pool[1].get_child_count() == 1, "second source also overlaps after wrapping")
	for voice in voices(audio):
		check(is_equal_approx(voice.pitch_scale, 1.0) and is_equal_approx(voice.volume_db, -6.0206), "prefab-disabled pitch and user SFX gain apply to every voice")

	check(not audio.play_event("Unknown") and audio.last_played.has("Unknown") and audio.next_player == 0, "missing AudioId records cooldown before lookup without advancing pool")
	var unknown_stamp: float = audio.last_played.Unknown
	audio.clips.Unknown = "click"
	check(not audio.play_event("Unknown") and audio.last_played.Unknown == unknown_stamp, "late-resolved AudioId still respects the failed attempt's cooldown")
	audio.last_played.Unknown = Time.get_ticks_msec() / 1000.0 - audio.cooldown - 0.1
	audio.source_settings._randomizeSFXPitch = true
	check(audio.play_event("Unknown"), "expired cooldown permits replay")
	var randomized: float = audio.pool[0].pitch_scale
	check(randomized >= 0.95 and randomized <= 1.05, "source pitch randomization remains in its original range")
	for voice in audio._slot_voices(audio.pool[0]):
		check(is_equal_approx(voice.pitch_scale, randomized), "source-slot pitch also updates earlier overlapping voices")
	check(is_equal_approx(audio.pool[1].pitch_scale, 1.0), "another source slot keeps its prior pitch")
	check(fields._randomizeSFXPitch == false, "adapter owns settings without mutating catalog")

	audio.stream_cache.music = sample()
	check(audio.play_music() and audio.music.playing, "available music starts")
	check(is_equal_approx(audio.music.volume_linear, 0.15), "0.3 source music gain is composed with user gain once")
	check(audio.set_user_gains(-12.0412, -12.0412), "live gain change accepted")
	for voice in voices(audio):
		check(is_equal_approx(voice.volume_db, -12.0412), "gain changes include active overlapping voices")
	check(is_equal_approx(audio.music.volume_linear, 0.075), "music gain changes do not accumulate")
	audio.set_user_gains(-12.0412, -12.0412)
	check(is_equal_approx(audio.music.volume_linear, 0.075), "repeated user gain remains idempotent")
	check(not audio.set_user_gains(INF, 0) and not audio.set_user_gains(0, -81) and not audio.set_user_gains(1, 0), "invalid gains are rejected")
	check(is_equal_approx(audio.user_sfx_db, -12.0412) and is_equal_approx(audio.user_bgm_db, -12.0412), "invalid gains do not partially mutate state")

	var old_voices: Array[AudioStreamPlayer] = voices(audio)
	var old_music: AudioStreamPlayer = audio.music
	audio.configure(catalog, assets)
	check(audio.pool.size() == 2 and audio.clips.size() == 4 and fields._SFXDataList.size() == 4, "reconfigure preserves catalog fields and rebuilds pool")
	check(audio.last_played.is_empty() and audio.stream_cache.is_empty() and audio.next_player == 0, "reconfigure clears transient event/stream/round-robin state")
	check(audio.music == null and old_music.stream == null and not old_music.playing, "reconfigure stops old music immediately")
	for voice in old_voices:
		check(not voice.playing and voice.stream == null, "reconfigure releases every active/overlapping voice")
	await process_frame
	for voice in old_voices:
		check(not is_instance_valid(voice), "reconfigure frees source and overflow nodes")
	check(not is_instance_valid(old_music), "reconfigure frees old music node")

	# Short silent clips verify natural completion and reusable base slots.
	audio.cooldown = 0
	audio.stream_cache.click = sample(0.05)
	for index in 6:
		check(audio.play_event("Click"), "zero-cooldown burst admits every one-shot")
	check(voices(audio).size() == 6, "repeated clip can also overlap beyond source count")
	await create_timer(0.35).timeout
	check(voices(audio).size() == 2 and not audio.pool[0].playing and not audio.pool[1].playing, "finished overflow voices are freed and base slots become idle")
	check(audio.play_event("Click") and voices(audio).size() == 2, "idle base slot reused without an extra node")

	# Licensed imports stay optional for CI. Exercise actual decode/start only,
	# never infer listening quality or perceived volume from a headless test.
	if catalog.load_file() == OK and assets.load_manifest() == OK:
		audio.configure(catalog, assets)
		check(audio.clips.size() == 18 and audio.pool.size() == 8, "locked source provides 18 SFX and eight logical sources")
		check(is_equal_approx(audio.cooldown, 0.05) and not audio.source_settings._randomizeSFXPitch, "locked prefab cooldown and pitch settings")
		for event_name in audio.clips:
			var stream: AudioStream = audio.stream_for_event(event_name)
			check(stream != null and stream.get_length() > 0, "licensed source clip decodes: " + event_name)
		for event_name in audio.clips:
			check(audio.play_event(event_name), "licensed source clip starts: " + event_name)
		check(voices(audio).size() == 18, "18 distinct licensed events overlap across eight source slots")
		var music_guid: String = str(audio.source_settings.get("_BGMClip", {}).get("guid", ""))
		if not assets.manifest.get("assets", {}).has(music_guid):
			check(not audio.play_music(), "missing licensed music stays silent")
		else:
			check(audio.play_music(), "licensed music starts")
			check(audio.music != null and audio.music.playing and audio.music.stream.get_length() > 0, "licensed music playback/length are valid")
			check(is_equal_approx(audio.music.volume_linear, 0.075), "licensed music preserves one source gain and current user preference")
		print("Private source audio: 18 SFX decoded and playback-start checked")
	else:
		print("PRIVATE SOURCE AUDIO SKIPPED: licensed catalog/manifest unavailable")

	var final_voices: Array[AudioStreamPlayer] = voices(audio)
	root.remove_child(audio)
	check(audio.stream_cache.is_empty() and audio.last_played.is_empty(), "leaving tree clears transient audio state")
	for voice in final_voices:
		check(voice.stream == null and not voice.playing, "leaving tree stops every overlapping voice")
	check(not audio.play_event("Click"), "detached configured node cannot start audio")
	audio.free()
	await process_frame
	await create_timer(0.5).timeout
	check(is_equal_approx(AudioServer.get_bus_volume_db(0), master_gain), "adapter leaves app master/host settings untouched")
	print("Audio feedback checks: %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
