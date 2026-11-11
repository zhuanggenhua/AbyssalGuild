extends SceneTree
const AudioFeedback = preload("res://scripts/ui/audio_feedback.gd")
const VisualAssets = preload("res://scripts/ui/visual_assets.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
func _init():
	call_deferred("run")
func run():
	var assets = VisualAssets.new()
	var catalog = Catalog.new()
	catalog.data = {"enums": {"AudioId": {"Click": 16}}, "referenced_prefabs": [{"documents": [{"script_class": "AudioManager", "fields": {"_SFXDataList": [{"audioId": 16, "audioClip": {"guid": "synthetic"}}], "_SFXPoolSize": 2, "_SFXCooldown": 10}}]}]}
	var audio = AudioFeedback.new()
	root.add_child(audio)
	audio.configure(catalog, assets)
	assert(audio.clips.Click == "synthetic")
	assert(audio.pool.size() == 2)
	assert(audio.stream_for_event("missing") == null)
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.data = PackedByteArray([0,0,0,0])
	audio.stream_cache.synthetic = sample
	assert(audio.play_event("Click"))
	assert(not audio.play_event("Click"))
	assert(not audio.play_music())
	if catalog.load_file() == OK and assets.load_manifest() == OK:
		audio.configure(catalog, assets)
		assert(audio.clips.size() == 18)
		for event_name in audio.clips:
			assert(audio.stream_for_event(event_name) != null)
		var music_guid: String = str(audio.source_settings.get("_BGMClip", {}).get("guid", ""))
		if not assets.manifest.get("assets", {}).has(music_guid):
			assert(not audio.play_music())
	audio._exit_tree()
	assert(audio.stream_cache.is_empty())
	for player in audio.pool:
		assert(player.stream == null and not player.playing)
	audio.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Audio source mappings: PASS")
	quit()
