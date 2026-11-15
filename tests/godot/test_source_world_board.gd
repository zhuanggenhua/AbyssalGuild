extends SceneTree
## Private scene lifecycle bindings, not rendered pixel equivalence.
const Board = preload("res://scripts/ui/board.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new()
	board.slot_root = "user://source-world-%d" % Time.get_ticks_usec()
	board.options_path = board.slot_root + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	var title_color: Color = board.world_environment.ambient_light_color
	var title_energy: float = board.world_environment.ambient_light_energy
	for scene_name in ["Main", "Island", "Main"]:
		board.session.configure(board.catalog, 1, scene_name)
		board.session.start_new_game()
		var old: Node3D = board.source_background
		board._enter_game()
		board.set_process(false)
		check(board.source_background != null and board.source_background.get_child_count() == 1, scene_name + " background attached")
		if is_instance_valid(old): check(old.is_queued_for_deletion() and not old.visible, "old background hidden and released")
		var instance: MeshInstance3D = board.source_background.get_child(0)
		var material: StandardMaterial3D = instance.material_override
		check(material.uv1_scale == Vector3(-20,-20,1) and material.uv1_offset == Vector3(20,1,0), scene_name + " source plane/ST/PNG orientation")
		var mapped := material.albedo_texture.get_image()
		check(mapped.get_size() == Vector2i(512,512) and mapped.has_mipmaps() and mapped.get_mipmap_count() == 9, scene_name + " complete 512-to-1 chain")
		var guid := "6f0ddc12af2166d4baa827c45ecf9594" if scene_name == "Main" else "0e37da4fd3cb8b7498704194af3d03b3"
		var source: Texture2D = board.visual_assets.texture(guid)
		var original := source.get_image()
		var base_size := 512*512*(4 if original.get_format() == Image.FORMAT_RGBA8 else 3)
		check(mapped.get_format() == original.get_format() and mapped.get_data().slice(0,base_size) == original.get_data().slice(0,base_size), scene_name + " base pixels and alpha unchanged")
		check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.texture_repeat and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, scene_name + " opaque/repeat/filter unchanged")
		check(preload("res://scripts/ui/source_world.gd").background_texture(material.albedo_texture, true) == material.albedo_texture, scene_name + " existing chain identity")
		var expected: Dictionary = board.visual_assets.scene_configuration(scene_name).render_settings
		var color: Dictionary = expected.m_AmbientSkyColor
		check(board.world_environment.ambient_light_color.is_equal_approx(Color(color.r,color.g,color.b)), scene_name + " source ambient")
		check(is_equal_approx(board.world_environment.ambient_light_energy, expected.m_AmbientIntensity), scene_name + " source ambient energy")
		await process_frame
	var old: Node3D = board.source_background
	board._restore_title_world()
	check(board.source_background == null, "Title removes gameplay-only plane")
	check(old.is_queued_for_deletion() and not old.visible, "Title hides and releases last plane")
	check(board.world_environment.ambient_light_color == title_color and board.world_environment.ambient_light_energy == title_energy, "Title restores documented native shell ambient")
	board._return_title()
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Source world scene lifecycle: ", "PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)
