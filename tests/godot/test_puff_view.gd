extends SceneTree
const Assets = preload("res://scripts/ui/visual_assets.gd")
const PuffView = preload("res://scripts/ui/puff_view.gd")
var checks := 0
func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	assert(value,message)

func key(time: float, value: float) -> Dictionary:
	return {"time":time,"value":value,"inSlope":0,"outSlope":0,"inWeight":0.3,"outWeight":0.3,"weightedMode":0}

func fixture():
	var record := {"supported":true,"unsupported":[],"duration":1.0,"cleanup_scaled_seconds":1.1,"burst_count":7,
		"ranges":{"lifetime":{"min":0.4,"max":0.4},"speed":{"min":0.5,"max":0.9},"size":{"min":0.2,"max":0.5}},
		"shape":{"radius":0.2,"position":{"x":0,"y":0.1,"z":0},"rotation_degrees":{"x":-90,"y":0,"z":0}},
		"start_color":{"r":0.2,"g":0.3,"b":0.4,"a":0.7},"size_keys":[key(0,0),key(0.5,1),key(1,0)],
		"opacity_keys":[{"time":0.0,"value":1.0},{"time":0.7,"value":1.0},{"time":1.0,"value":0.0}],
		"renderer_mode":2,"renderer_fields":{"m_CastShadows":0,"m_ReceiveShadows":0,"m_Pivot":{"x":0,"y":0,"z":0},"m_Flip":{"x":0,"y":0,"z":0}},
		"materials":[{"guid":"material"}],"prefab_guid":"synthetic_prefab"}
	var assets = Assets.new()
	assets.manifest = {"scenes":{"Synthetic":{"puff":record}},"assets":{"texture":{"kind":"png","texture_importer":{"filter_mode":1,"wrap_u":0,"wrap_v":0,"mipmaps":1}}},
		"materials":{"material":{"colors":{"_Color":{"r":0.5,"g":0.6,"b":0.7,"a":0.9}},"textures":{"_MainTex":{"m_Texture":{"guid":"texture"},"m_Scale":{"x":1,"y":1},"m_Offset":{"x":0,"y":0}}}}}}
	var image := Image.create(8,8,false,Image.FORMAT_RGBA8)
	image.fill(Color(0.8,0.7,0.6,0.5))
	assets.texture_cache.texture = ImageTexture.create_from_image(image)
	# Exercise JSON numbers as floats even without the private manifest.
	assets.manifest = JSON.parse_string(JSON.stringify(assets.manifest))
	return assets

func inspect(view, tint: Color) -> void:
	var states: Array[Dictionary] = view.simulation.sample_states()
	check(states.size()==view.particles.size(),"inspect all still-alive particles")
	var material_ids := {}
	for state in states:
		var particle: MeshInstance3D = view.particles[int(state.index)]
		var material: StandardMaterial3D = particle.material_override
		material_ids[material.get_instance_id()]=true
		check(particle.position.is_equal_approx(state.position),"reflected simulation position applied once")
		check(particle.scale.is_equal_approx(Vector3(state.size,1,state.size)),"source per-particle world size")
		check(particle.basis.y.is_equal_approx(Vector3.UP),"horizontal plane not camera billboard")
		check(particle.mesh.get_aabb().size.is_equal_approx(Vector3(1,0,1)),"unit plane basis footprint")
		check(material.albedo_color.is_equal_approx(state.color*tint),"native multiply tint and particle alpha")
		check(material.albedo_texture==view.source_texture,"shared private texture identity")
		check(material.blend_mode==BaseMaterial3D.BLEND_MODE_MIX and material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"explicit standard-alpha approximation")
		check(material.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED and particle.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"unlit and no shadows")
		check(not material.no_depth_test and material.depth_draw_mode==BaseMaterial3D.DEPTH_DRAW_DISABLED,"depth test without transparent depth write")
	check(material_ids.size()==states.size(),"per-particle color materials not shared")

func run() -> void:
	var assets = fixture()
	seed(748)
	var expected: float = randf()
	seed(748)
	var view = assets.create_puff("Synthetic",123)
	check(view!=null and view.particles.size()==7,"optional construction")
	check(randf()==expected,"renderer construction leaves global RNG alone")
	root.add_child(view)
	view.position=Vector3(2,3,4)
	var root_pose: Transform3D = view.transform
	check(view.get_meta("material_equivalence")=="native_standard_alpha_approximation","approximation explicit in node metadata")
	check(view.get_meta("source_prefab_guid")=="synthetic_prefab","source identity")
	for particle in view.particles: check(not particle.visible,"zero-size birth hidden without singular scale")
	check(view.advance(0.1,0),"render unscaled movement while paused")
	inspect(view,Color(0.5,0.6,0.7,0.9))
	check(view.transform==root_pose,"advance never changes captured origin")
	for particle in view.particles:
		check(particle.global_position.is_equal_approx(view.position+particle.position),"world origin added exactly once")
		check(particle.material_override.texture_repeat and particle.material_override.texture_filter==BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,"source texture filter and wrap request")
	var time_before: float = view.simulation.elapsed
	check(not view.advance(NAN,0) and is_equal_approx(view.simulation.elapsed,time_before),"invalid clock leaves view unchanged")
	var snapshot: Array[Dictionary] = view.simulation.sample_states()
	var rng_before: int = view.simulation._rng.state
	view.advance(0,0)
	check(view.simulation.sample_states()==snapshot and view.simulation._rng.state==rng_before,"zero tick no geometry/RNG drift")
	var other = assets.create_puff("Synthetic",123)
	check(other!=null and other.source_texture==view.source_texture,"repeated creation safely shares texture")
	check(other.particles[0].material_override!=view.particles[0].material_override,"independent effect materials")
	other.free()
	var record: Dictionary = assets.puff_configuration("Synthetic")
	check(view.configure(assets,record,123) and view.get_child_count()==7,"reconfigure replaces, never duplicates nodes")
	var invalid: Dictionary = record.duplicate(true)
	invalid.renderer_mode=0
	check(not view.configure(assets,invalid,123) and view.get_child_count()==0 and view.is_expired(),"unsupported reconfigure clears old particles")
	check(view.configure(assets,record,123),"recover after unsupported config")
	view.advance(0.5,0)
	for particle in view.particles: check(not particle.visible,"dead particles hidden during scaled pause")
	check(not view.is_expired() and not view.is_queued_for_deletion(),"empty paused effect preserves scaled destruction")
	view.advance(0,1.1)
	check(view.is_expired() and view.is_queued_for_deletion() and not view.visible,"scaled expiry hides and queues cleanup")
	check(not view.configure(assets,record,123),"cannot revive a queued effect")
	await process_frame
	check(not is_instance_valid(view),"effect freed after expiry")
	check(assets.create_puff("missing",1)==null,"missing metadata no fabricated puff")
	var saved_texture: Texture2D = assets.texture_cache.texture
	assets.texture_cache.clear()
	check(assets.create_puff("Synthetic",1)==null,"missing PNG safely unavailable")
	assets.texture_cache.texture=saved_texture
	assets.manifest.materials.material.textures._MainTex.m_Offset.x=1
	check(assets.create_puff("Synthetic",1)==null,"unsupported UV offset rejected")
	assets.manifest.materials.material.textures._MainTex.m_Offset.x=0
	assets.manifest.assets.texture.texture_importer.wrap_v=1
	check(assets.create_puff("Synthetic",1)==null,"unequal wrap mode not guessed")
	assets.manifest.assets.texture.texture_importer.wrap_v=0
	assets.manifest.materials.material.colors.erase("_Color")
	check(assets.create_puff("Synthetic",1)==null,"missing material color not invented")
	print("Native Puff view synthetic checks: %d passed" % checks)
	await private_checks()
	quit()

func private_checks() -> void:
	var assets = Assets.new()
	if assets.load_manifest()!=OK:
		print("Private native Puff view: SKIP (private visual manifest unavailable)")
		return
	if assets.puff_configuration("Main").is_empty():
		print("Private native Puff view: SKIP (regenerate private Puff metadata)")
		return
	for scene in ["Main","Island"]:
		var record: Dictionary = assets.puff_configuration(scene)
		var view = assets.create_puff(scene,845)
		check(view!=null,"actual referenced PNG/material binding")
		root.add_child(view)
		view.position=Vector3(3,1,-4)
		check(view.particles.size()==int(record.burst_count),"actual source burst geometry count")
		view.advance(0.05,0)
		var material: Dictionary = assets.manifest.materials[str(record.materials[0].guid)]
		inspect(view,assets.source_color(material.colors._Color))
		check(view.source_texture==assets.texture(str(material.textures._MainTex.m_Texture.guid)),"actual Puff texture identity")
		check(view.get_meta("material_equivalence")=="native_standard_alpha_approximation","actual shader equivalence not asserted")
		var state: Transform3D = view.transform
		view.advance(float(record.ranges.lifetime.max),0)
		check(view.transform==state and not view.is_expired(),"actual paused origin stable after particles finish")
		view.advance(0,float(record.cleanup_scaled_seconds))
		check(view.is_queued_for_deletion(),"actual scaled cleanup scheduled")
		await process_frame
		check(not is_instance_valid(view),"actual effect freed")
	print("Private native Puff view: PASS (both scene textures, horizontal geometry, per-particle state, two-clock cleanup; alpha approximation)")
	print("Native Puff view total checks: %d passed; no GPU/manual visual acceptance" % checks)
