extends SceneTree
## Lifecycle/admission assertions only. Headless execution makes no pixel claim.
const Binder = preload("res://scripts/ui/source_flat_board_lighting.gd")
const Lit = preload("res://scripts/ui/source_lit_material.gd")
class HostWithoutWorld:
	extends "res://scripts/ui/board.gd"
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
var checks := 0
var failures := 0
var binder
var mesh: MeshInstance3D
var base: ShaderMaterial
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func material(code: String = Lit.BOARD_FRAGMENT + Lit.DIRECT_LIGHT_CODE) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = Shader.new()
	result.shader.code = code
	result.set_meta("source_direct_lit", true)
	result.set_meta("source_board_cull", "back")
	result.set_shader_parameter("source_base_color", Color(.42808828,.4678468,.49056602))
	return result
func current(): return mesh.get_surface_override_material(0)
func active(label: String) -> void:
	binder.refresh()
	check(binder.active_count() == 1, label + " count")
	check(current() != base and current().get_meta("source_flat_linear_composition", false), label + " replacement")
func inactive(label: String) -> void:
	binder.refresh()
	check(binder.active_count() == 0, label + " count")
	check(current() == base, label + " original identity")
func run() -> void:
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		print("NOT RUN: requires --rendering-method gl_compatibility")
		quit(2)
		return
	check(Binder.FRAGMENT_CODE.contains("cull_back") and not Binder.FRAGMENT_CODE.contains("cull_disabled"), "flat composition retains source board cull")
	var old_double_sided := material((Lit.BOARD_FRAGMENT + Lit.DIRECT_LIGHT_CODE).replace("cull_back", "cull_disabled"))
	check(not Binder._original_supported(old_double_sided), "old double-sided material rejected")
	var missing_marker := material()
	missing_marker.remove_meta("source_board_cull")
	check(not Binder._original_supported(missing_marker), "unproven cull marker rejected")
	var host := HostWithoutWorld.new()
	check(host.flat_board_lighting == null, "Board construction does not eagerly allocate binder")
	# Existing Board Node fields normally become children during full _ready.
	# This host skips it; retain ownership for deterministic cleanup.
	host.add_child(host.feedback)
	host.add_child(host.vendor_unlock)
	root.add_child(host)
	check(host.flat_board_lighting == null, "Host skipping ready/world does not allocate binder")
	host.free()
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = 1
	env.ambient_light_color = Color(.60480005,.63552,.72)
	world.environment = env
	viewport.add_child(world)
	var board := Node3D.new()
	board.set_meta("source_prefab_guid", "synthetic-board-fixture")
	viewport.add_child(board)
	mesh = MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	base = material()
	mesh.set_surface_override_material(0, base)
	board.add_child(mesh)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	viewport.add_child(light) # Sibling of board, still in its World3D.
	binder = Binder.new()
	root.add_child(binder)
	binder.bind(board, env)
	check(RenderingServer.frame_pre_draw.is_connected(binder.refresh), "pre-draw refresh connected (not pixel verification)")
	active("shadowed sibling directional")
	check(current().get_shader_parameter("source_base_color") == base.get_shader_parameter("source_base_color"), "authored color unchanged")
	check(env.ambient_light_color == Color(.60480005,.63552,.72) and env.ambient_light_energy == 1.0, "environment untouched")
	check(light.shadow_enabled and light.light_energy == 1.0, "light untouched")
	light.shadow_enabled = false
	active("unshadowed")
	light.shadow_enabled = true
	light.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
	inactive("sky-only directional")
	light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	active("light-and-sky directional")
	env.ambient_light_color = Color(.2,.3,.4)
	env.ambient_light_energy = .75
	active("ambient update")
	var expected := env.ambient_light_color.srgb_to_linear()
	var uniform = current().get_shader_parameter("source_flat_ambient_linear")
	check(uniform is Vector3 and uniform.is_equal_approx(Vector3(expected.r,expected.g,expected.b)*.75), "ambient uniform uses current linear input")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	active("disabled ambient")
	var disabled_uniform = current().get_shader_parameter("source_flat_ambient_linear")
	check(disabled_uniform is Vector3 and disabled_uniform.is_zero_approx(), "disabled ambient uniform zero")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	viewport.remove_child(light)
	inactive("zero lights")
	viewport.add_child(light)
	var extra := DirectionalLight3D.new()
	viewport.add_child(extra)
	inactive("multiple lights")
	extra.free()
	light.light_cull_mask = 0
	inactive("cull mask excludes board")
	light.light_cull_mask = 1
	light.light_energy = 0
	inactive("zero energy")
	light.light_energy = 1
	light.light_negative = true
	inactive("negative light")
	light.light_negative = false
	light.hide()
	inactive("hidden only light")
	light.show()
	active("valid restored")
	for probe in [ReflectionProbe.new(), LightmapGI.new(), VoxelGI.new()]:
		viewport.add_child(probe)
		inactive("new sibling GI/probe")
		probe.free()
	var camera := Camera3D.new()
	camera.attributes = CameraAttributesPractical.new()
	viewport.add_child(camera)
	inactive("camera attributes")
	camera.free()
	world.environment = Environment.new()
	inactive("world environment identity changed")
	world.environment = env
	active("world environment restored")
	for property in ["fog_enabled", "glow_enabled", "adjustment_enabled"]:
		env.set(property, true)
		inactive(property)
		env.set(property, false)
	env.tonemap_exposure = 2
	inactive("exposure")
	env.tonemap_exposure = 1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	inactive("tonemap")
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.reflected_light_source = 0
	inactive("reflections")
	env.reflected_light_source = 1
	for property in ["material_override", "material_overlay"]:
		mesh.set(property, StandardMaterial3D.new())
		inactive(property)
		mesh.set(property, null)
	mesh.transparency = .5
	inactive("geometry transparency")
	mesh.transparency = 0
	base.next_pass = StandardMaterial3D.new()
	inactive("next pass")
	base.next_pass = null
	for code in [Lit.BOARD_FRAGMENT.replace("ROUGHNESS = 1.0;", "ROUGHNESS = 1.0; EMISSION = vec3(0.1);") + Lit.DIRECT_LIGHT_CODE, Lit.BOARD_FRAGMENT.replace("ROUGHNESS = 1.0;", "ROUGHNESS = 1.0; ALPHA = 0.5;") + Lit.DIRECT_LIGHT_CODE, "shader_type spatial; void fragment() { ALBEDO=vec3(1.0); }", FileAccess.get_file_as_string("res://scripts/ui/shaders/card_surface.gdshader") + Lit.DIRECT_LIGHT_CODE]:
		binder.clear()
		base = material(code)
		mesh.set_surface_override_material(0, base)
		binder.bind(board, env)
		inactive("unsupported shader " + str(checks))
	binder.clear()
	base = material()
	mesh.set_surface_override_material(0, base)
	binder.bind(board, env)
	active("original supported material rebound")
	var other_view := SubViewport.new()
	other_view.own_world_3d = true
	root.add_child(other_view)
	other_view.add_child(DirectionalLight3D.new())
	active("different World3D light ignored")
	var replacement := material()
	mesh.set_surface_override_material(0, replacement)
	binder.refresh()
	check(current() == replacement and binder.active_count() == 0, "refresh preserves external replacement")
	binder.clear()
	check(current() == replacement, "clear preserves external material replacement")
	base = replacement
	binder.bind(board, env)
	active("rebind external material")
	binder.clear()
	check(current() == base and binder.active_count() == 0, "clear restores identical original")
	binder.bind(board, env)
	var second := Node3D.new()
	second.set_meta("source_prefab_guid", "second-synthetic-board")
	viewport.add_child(second)
	var second_mesh := MeshInstance3D.new()
	second_mesh.mesh = QuadMesh.new()
	var second_base := material()
	second_mesh.set_surface_override_material(0, second_base)
	second.add_child(second_mesh)
	binder.bind(second, env)
	check(current() == base, "new board restores previous geometry")
	mesh = second_mesh
	base = second_base
	active("new board geometry")
	mesh.reparent(viewport)
	inactive("same-world geometry outside bound board")
	mesh.reparent(second)
	active("geometry returned to bound board")
	var original_mesh := mesh.mesh
	mesh.mesh = QuadMesh.new()
	inactive("changed mesh resource")
	mesh.mesh = original_mesh
	active("original mesh resource restored")
	mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	inactive("geometry fade")
	mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	active("geometry fade disabled")
	for mutation in ["shader", "next_pass"]:
		var altered = current()
		if mutation == "shader":
			var unknown := Shader.new()
			unknown.code = "shader_type spatial; void fragment() { ALBEDO=vec3(0.1); }"
			altered.shader = unknown
		else:
			altered.next_pass = StandardMaterial3D.new()
		inactive("externally changed replacement " + mutation)
		inactive("retired replacement remains retired " + mutation)
		binder.bind(second, env)
		active("explicit rebind after replacement mutation " + mutation)
	var external := material()
	mesh.set_surface_override_material(0, external)
	binder.refresh()
	check(current() == external and binder.active_count() == 0, "external material causes retirement")
	mesh.set_surface_override_material(0, base)
	inactive("returning original does not reactivate retired binding")
	binder.bind(second, env)
	active("only explicit bind reactivates retired binding")
	binder.clear()
	second.remove_meta("source_prefab_guid")
	binder.bind(second, env)
	inactive("unbound prefab rejected")
	binder.clear()
	binder.free()
	other_view.free()
	viewport.free()
	print("Flat board lighting lifecycle: %d checks, %d failures; no pixel claims" % [checks, failures])
	quit(1 if failures else 0)
