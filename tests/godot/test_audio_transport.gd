extends SceneTree
const Feedback = preload("res://scripts/ui/audio_feedback.gd")
const Clock = preload("res://scripts/ui/audio_frame_clock.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
const Assets = preload("res://scripts/ui/visual_assets.gd")
var checks := 0
var failures := 0
var finished_count := 0
func _init(): call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",message)
func sample(seconds: float = 0.04, stereo: bool = false, bits8: bool = false) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 8000
	stream.stereo = stereo
	stream.format = AudioStreamWAV.FORMAT_8_BITS if bits8 else AudioStreamWAV.FORMAT_16_BITS
	var bytes := PackedByteArray()
	bytes.resize(roundi(seconds*8000)*(2 if stereo else 1)*(1 if bits8 else 2))
	stream.data = bytes
	return stream
func wait_wall_time(seconds: float) -> int:
	var started := Time.get_ticks_usec()
	var deadline := started + roundi(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await create_timer(maxf(0.001, (deadline - Time.get_ticks_usec()) / 1000000.0), true, false, true).timeout
	return Time.get_ticks_usec() - started
func run() -> void:
	var state := {"frame":1,"time":10.0,"samples":0}
	var clock = Clock.new()
	clock.frame_provider = func(): return state.frame
	clock.time_provider = func(): state.samples += 1; return state.time
	check(clock.now() == 10 and state.samples == 1,"first frame samples clock")
	state.time = 40.0
	check(clock.now() == 10 and state.samples == 1,"same frame never resamples wall clock")
	state.frame += 1
	check(clock.now() == 40 and state.samples == 2,"next frame samples new unscaled time")
	var audio = Feedback.new()
	root.add_child(audio)
	var catalog = Catalog.new()
	catalog.data = {"enums":{"AudioId":{"A":0}},"referenced_prefabs":[{"documents":[{"script_class":"AudioManager","fields":{"_SFXPoolSize":1,"_SFXCooldown":0.05,"_randomizeSFXPitch":false,"_SFXDataList":[{"audioId":0,"audioClip":{"guid":"a"}}],"_BGMClip":{"guid":"a"},"_defaultMusicVolume":0.3}}]}]}
	audio.configure(catalog,null)
	audio.stream_cache.a = sample()
	audio.unscaled_frame_clock = clock
	audio._sample_unscaled_frame()
	check(state.samples == 2,"production pre-process hook shares existing token sample")
	check(audio.play_event("A"),"first sound admitted")
	state.time += 1
	check(not audio.play_event("A") and state.samples == 2,"same-frame long work does not reopen cooldown")
	state.frame += 1
	check(audio.play_event("A"),"next frame beyond cooldown admits")
	state.frame += 1
	state.time += 0.01
	check(not audio.play_event("A"),"new frame within cooldown rejected")
	check(not audio.play_event("Unknown") and audio.last_played.has("Unknown"),"missing clip consumes frame-time admission")
	audio.clips.Unknown = "a"
	state.time += 1
	check(not audio.play_event("Unknown"),"same-frame late resolution does not bypass cooldown")
	state.frame += 1
	check(audio.play_event("Unknown"),"resolved clip admitted on later eligible frame")
	# Exercise the production providers, not only injected timestamps.
	audio.unscaled_frame_clock = Clock.new()
	audio.last_played.clear()
	check(audio.play_event("A"),"engine frame clock admits first event")
	var stamp: float = audio.last_played.A
	var frame: int = Engine.get_process_frames()
	OS.delay_msec(80)
	check(Engine.get_process_frames() == frame and not audio.play_event("A") and audio.last_played.A == stamp,"real stalled engine frame keeps timestamp constant")
	await process_frame
	await process_frame
	check(audio.unscaled_frame_clock.sampled_frame == Engine.get_process_frames(),"pre-process hook samples even before a new audio request")
	check(audio.play_event("A"),"next actual engine frame reopens elapsed cooldown")
	Engine.time_scale = 0
	OS.delay_msec(80)
	await process_frame
	await process_frame
	check(audio.play_event("A"),"gameplay time scale zero does not freeze cooldown")
	Engine.time_scale = 1
	for stereo in [false,true]:
		for bits8 in [false,true]:
			var stream := sample(0.04,stereo,bits8)
			var looping: AudioStreamWAV = Feedback._looping_music_stream(stream)
			check(looping != stream and looping.loop_mode == AudioStreamWAV.LOOP_FORWARD,"music has independent looping resource")
			check(looping.loop_begin == 0 and looping.loop_end == 320,"loop covers exact full PCM frame range")
			check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and looping.data == stream.data and looping.stereo == stereo and looping.format == stream.format,"loop binding preserves source bytes/channels/format without mutating cache")
	check(Feedback._looping_music_stream(AudioStreamWAV.new()) == null,"empty music is not started")
	var source: AudioStreamWAV = audio.stream_cache.a
	check(audio.play_music(),"real looping music starts")
	audio.music.finished.connect(func(): finished_count += 1)
	check(audio.music.stream != source and source.loop_mode == AudioStreamWAV.LOOP_DISABLED,"music does not turn shared SFX into a loop")
	var music_elapsed: int = await wait_wall_time(0.35)
	check(music_elapsed >= 350000 and music_elapsed >= roundi(source.get_length() * 1000000.0) * 8,"actual wall clock covers at least eight music clip periods")
	print("Music loop wall time: %d us; clip period: %d us" % [music_elapsed, roundi(source.get_length() * 1000000.0)])
	check(audio.music.playing and finished_count == 0,"music crosses multiple clip lengths without finish/restart callback")
	audio.cooldown = 0
	check(audio.play_source_event("A",null,true),"one-shot on same source stream still admitted")
	check(audio.music.playing and audio.requests.mixer_bgm_db == -80,"BGM interruption mutes but retains looping transport")
	audio.advance_scaled_time(1)
	check(audio.music.playing and audio.requests.mixer_bgm_db == 0,"wait restores mixer without replacing transport")
	var oneshot_elapsed: int = await wait_wall_time(0.2)
	check(oneshot_elapsed >= 200000,"one-shot completion wait covers actual wall-clock duration")
	check(audio.slot_owners.values().all(func(owner):return owner.voices.all(func(v):return not v.playing)),"one-shots finish normally despite shared BGM clip")
	var assets = Assets.new()
	if catalog.load_file() == OK and assets.load_manifest() == OK:
		audio.configure(catalog,assets)
		var guid: String = audio.source_settings._BGMClip.guid
		var original: AudioStream = audio._stream(guid)
		check(original is AudioStreamWAV and original.get_length() > 0,"private original BGM decodes")
		var old_mode: int = original.loop_mode
		check(audio.play_music(),"private BGM starts on independent loop")
		var music: AudioStreamWAV = audio.music.stream
		check(music != original and original.loop_mode == old_mode,"private resource/cache not modified")
		check(music.data == original.data and music.format == original.format and music.stereo == original.stereo and music.mix_rate == original.mix_rate,"private data/format/stereo/rate retained")
		check(music.loop_begin == 0 and music.loop_end == roundi(original.get_length()*original.mix_rate),"private complete frame interval retained")
		check(is_equal_approx(music.get_length(),original.get_length()),"private duration unchanged")
		print("Private audio transport: PASS (%s decode, format %d)" % ["imported" if not original.resource_path.is_empty() else "buffer",original.format])
	else:
		print("Private audio transport: SKIP (licensed inputs absent)")
	audio.shutdown()
	check(not audio.music.playing and audio.music.stream == null,"shutdown stops looping stream")
	audio.music.finished.emit()
	check(not audio.music.playing,"late finished signal cannot restart stopped music")
	# A timer alone can consume the current slow frame; verify wall time.
	await wait_wall_time(0.5)
	audio.queue_free()
	await process_frame
	print("Audio transport checks: %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
