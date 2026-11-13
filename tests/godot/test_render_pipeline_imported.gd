extends SceneTree
const Assets = preload("res://scripts/ui/visual_assets.gd")
const Effect = preload("res://scripts/ui/world_post_process.gd")
const Board = preload("res://scripts/ui/board.gd")
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var source = JSON.parse_string(FileAccess.get_file_as_string("res://data/stackcraft.json"))
	var assets = Assets.new()
	assert(assets.load_render_pipeline(source.provenance.source_commit) == OK)
	var profile: Dictionary = assets.render_pipeline
	assert(profile.target_platform == "Standalone")
	assert(profile.execution.mode == "render_graph")
	assert(profile.execution.rule == "unity_6000_5_builtin_urp_17_5")
	assert(profile.execution.editor_version == "6000.5.4f1")
	assert(int(profile.selected_quality) == int(profile.platform_defaults.Standalone))
	var selected: String = str(profile.qualities[int(profile.selected_quality)].pipeline_guid)
	assert(not selected.is_empty() and profile.pipelines.has(selected))
	for scene in ["Main","Island"]:
		var config := Effect.resolve(source,scene)
		assert(config.source_backed)
		assert(Effect.resolve_pass(profile,config).status == "disabled")
	assert(assets.load_render_pipeline("wrong-commit") == ERR_INVALID_DATA and assets.render_pipeline.is_empty())
	var board = Board.new()
	board.slot_root = "user://pipeline-test-slots"
	board.options_path = "user://pipeline-test-options.json"
	root.add_child(board)
	await process_frame
	board.start_new()
	board.set_process(false)
	assert(not board.world_post_process.rect.visible)
	assert(board.world_post_process.config.render_pass.status == "disabled")
	board._on_session_event("time_pace_changed",{"pace":0})
	board.world_post_process.advance(0.3)
	assert(board.world_post_process.grayscale == 1.0 and not board.world_post_process.rect.visible)
	board._on_session_event("day_ended",{})
	board.world_post_process.advance(0.5)
	assert(is_equal_approx(board.world_post_process.vignette,1.2) and not board.world_post_process.rect.visible)
	board.process_mode = Node.PROCESS_MODE_DISABLED
	board.feedback.shutdown()
	# Like Board._finish_quit, recheck wall time: a slow setup frame can
	# consume a newly created timer before the audio mix thread has drained.
	var drain_started := Time.get_ticks_usec()
	var drain_usec := int(Board.QUIT_AUDIO_DRAIN_SECONDS * 1000000)
	var deadline := drain_started + drain_usec
	while Time.get_ticks_usec() < deadline:
		var remaining := float(deadline - Time.get_ticks_usec()) / 1000000.0
		if remaining > 0:
			await create_timer(remaining,true,false,true).timeout
	var drained_usec := Time.get_ticks_usec() - drain_started
	assert(drained_usec >= drain_usec)
	print("Audio drain wall time: %d us (required >= %d us)" % [drained_usec,drain_usec])
	board.queue_free()
	await process_frame
	print("Private source render pipeline: PASS")
	quit()
