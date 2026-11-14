extends SceneTree
const Lit = preload("res://scripts/ui/source_lit_material.gd")
const Assets = preload("res://scripts/ui/visual_assets.gd")
const Card = preload("res://scripts/ui/card_surface.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func profile() -> Dictionary:
	return {"execution":{"mode":"render_graph", "rule":"unity_6000_5_builtin_urp_17_5"}, "selected_quality":0, "qualities":[{"pipeline_guid":""}], "graphics_pipeline_guid":"urp", "pipelines":{"urp":{"schema":"urp_renderer_list"}}}

func source(path: String = "Shaders/SimpleLit.shadergraph") -> Dictionary:
	var item := {"name":"Synthetic", "shader_source_path":path, "keywords":[], "colors":{"_Color":{"r":0.4,"g":0.2,"b":0.6,"a":1.0}}, "source_lit":{"schema_version":2,"geometry":"unmodified_object_vertices_tangent_normal", "target":"universal_lit", "workflow":"metallic", "metallic":0,"smoothness":0,"opaque":true,"double_sided":true,"clearcoat":false,"material_override":false,"graph_sha256":"a".repeat(64)}}

	if path == "Shaders/SimpleLit.shadergraph":
		item.source_lit.merge({"schema_version":3,"double_sided":false,"render_face":2,"cull_mode":"back","normal_policy":"inverse_transpose_no_face_flip","graph_sha256":Lit.BOARD_GRAPH_SHA256}, true)
	return item

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var material_source := source()
	var manifest := {"inputs":{"Shaders/SimpleLit.shadergraph":Lit.BOARD_GRAPH_SHA256, "Shaders/Card.shadergraph":"a".repeat(64)}}
	var pipeline := profile()
	check(Lit.admission(material_source, manifest, pipeline, "gl_compatibility"), "recognized graph/pipeline")
	check(Lit.BOARD_FRAGMENT.contains("cull_back") and not Lit.BOARD_FRAGMENT.contains("cull_disabled"), "board cull follows source Front=2")
	var legacy := material_source.duplicate(true)
	legacy.source_lit.schema_version = 2
	legacy.source_lit.double_sided = true
	check(not Lit.admission(legacy, manifest, pipeline, "gl_compatibility"), "old wrong board contract rejected")
	var unknown := material_source.duplicate(true)
	unknown.source_lit.graph_sha256 = "b".repeat(64)
	var unknown_manifest := manifest.duplicate(true)
	unknown_manifest.inputs[unknown.shader_source_path] = unknown.source_lit.graph_sha256
	check(not Lit.admission(unknown, unknown_manifest, pipeline, "gl_compatibility"), "different graph rejected even with matching manifest")
	for renderer in ["", "mobile", "forward_plus"]:
		check(not Lit.admission(material_source, manifest, pipeline, renderer), "renderer rejected " + renderer)
	for key in material_source.source_lit:
		var missing := material_source.duplicate(true)
		missing.source_lit.erase(key)
		check(not Lit.admission(missing, manifest, pipeline, "gl_compatibility"), "missing contract " + key)
	for replacement in [{"schema_version":1},{"geometry":"connected_normals"},{"target":"simple_lit"},{"workflow":"specular"},{"metallic":0.1},{"smoothness":0.1},{"opaque":false},{"double_sided":true},{"render_face":0},{"cull_mode":"disabled"},{"normal_policy":"flip"},{"schema_version":2},{"clearcoat":true},{"material_override":true},{"graph_sha256":"b".repeat(64)}]:
		var changed := material_source.duplicate(true)
		changed.source_lit.merge(replacement, true)
		check(not Lit.admission(changed, manifest, pipeline, "gl_compatibility"), "unsupported contract " + str(replacement))
	for replacement in [{"source_lit":{}},{"keywords":["_NORMALMAP"]},{"shader_source_path":"unproven.shadergraph"}]:
		var changed := material_source.duplicate(true)
		changed.merge(replacement, true)
		check(not Lit.admission(changed, manifest, pipeline, "gl_compatibility"), "unsupported material " + str(replacement))
	check(not Lit.admission(material_source, {}, pipeline, "gl_compatibility"), "missing manifest inputs")
	for malformed in [{}, [], "0", true, null, NAN, INF]:
		for field in ["mode", "rule"]:
			var bad_execution := pipeline.duplicate(true)
			bad_execution.execution[field] = malformed
			check(not Lit.admission(material_source, manifest, bad_execution, "gl_compatibility"), "malformed execution field " + field)
		var bad_schema := pipeline.duplicate(true)
		bad_schema.pipelines.urp.schema = malformed
		check(not Lit.admission(material_source, manifest, bad_schema, "gl_compatibility"), "malformed pipeline schema")
		var bad_manifest := manifest.duplicate(true)
		bad_manifest.inputs[material_source.shader_source_path] = malformed
		check(not Lit.admission(material_source, bad_manifest, pipeline, "gl_compatibility"), "malformed manifest digest")
		var bad_pipeline := pipeline.duplicate(true)
		bad_pipeline.selected_quality = malformed
		check(not Lit.admission(material_source, manifest, bad_pipeline, "gl_compatibility"), "malformed quality rejected without script error")
		for key in ["schema_version", "metallic", "smoothness", "opaque", "geometry"]:
			var bad_source := material_source.duplicate(true)
			bad_source.source_lit[key] = malformed
			# A true bool is valid only for the opaque field.
			if key == "opaque" and typeof(malformed) == TYPE_BOOL: continue
			check(not Lit.admission(bad_source, manifest, pipeline, "gl_compatibility"), "malformed contract rejected " + key)
	for replacement in [{"execution":{}},{"execution":{"mode":"compatibility","rule":"unity_6000_5_builtin_urp_17_5"}},{"execution":{"mode":"render_graph","rule":"guess"}},{"selected_quality":-1},{"selected_quality":1},{"qualities":[]},{"graphics_pipeline_guid":""},{"pipelines":{}},{"pipelines":{"urp":{"schema":"unknown"}}}]:
		var changed := pipeline.duplicate(true)
		changed.merge(replacement, true)
		check(not Lit.admission(material_source, manifest, changed, "gl_compatibility"), "unsupported pipeline " + str(replacement))
	var selected := profile()
	selected.qualities[0].pipeline_guid = "quality"
	selected.pipelines.quality = {"schema":"urp_renderer_list"}
	selected.graphics_pipeline_guid = "unused"
	check(Lit.admission(material_source, manifest, selected, "gl_compatibility"), "quality override selected")
	var previous = ProjectSettings.get_setting("rendering/lights_and_shadows/use_physical_light_units", false)
	ProjectSettings.set_setting("rendering/lights_and_shadows/use_physical_light_units", true)
	check(not Lit.admission(material_source, manifest, pipeline, "gl_compatibility"), "physical lights not silently admitted")
	ProjectSettings.set_setting("rendering/lights_and_shadows/use_physical_light_units", previous)
	check(Lit.DIRECT_LIGHT_CODE.count("void light()") == 1, "one direct-light replacement")
	check(Lit.DIRECT_LIGHT_CODE.contains("1.175494351e-38"), "HLSL FLT_MIN guard retained")
	check(Lit.DIRECT_LIGHT_CODE.contains("0.96 / PI") and Lit.DIRECT_LIGHT_CODE.contains("specular_term / PI"), "Godot accumulator bridge")
	var assets = Assets.new()
	assets.manifest = manifest
	assets.render_pipeline = pipeline
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		var board: ShaderMaterial = Lit.board_material(assets, material_source)
		check(board != null, "actual board factory")
		if board != null:
			check(board.get_shader_parameter("source_base_color").is_equal_approx(Color(0.4,0.2,0.6,1)), "unchanged authored board color")
			check(board.shader.code == Lit.BOARD_FRAGMENT + Lit.DIRECT_LIGHT_CODE, "production shader assembly")
			check(board.get_meta("source_direct_lit", false), "explicit direct-light marker")
			check(board.get_meta("source_board_cull", "") == "back", "explicit audited board cull marker")
		var card_source := source("Shaders/Card.shadergraph")
		var card_shader: Shader = Lit.card_shader(assets, card_source, Card.SHADER)
		check(card_shader.code == Card.SHADER.code + Lit.DIRECT_LIGHT_CODE, "existing card fragment byte-preserved")
		check(card_shader.code.count("void light()") == 1, "card has one light function")
		var node := MeshInstance3D.new()
		node.mesh = BoxMesh.new()
		assets.manifest["materials"] = {"m":material_source}
		assets._apply_board_materials(node, [{"guid":"m"}])
		check(node.get_surface_override_material(0) is ShaderMaterial, "board binding routes through factory")
		node.free()
	assets.render_pipeline = {}
	check(Lit.board_material(assets, material_source) == null, "unproven board uses previous fallback")
	check(Lit.card_shader(assets, source("Shaders/Card.shadergraph"), Card.SHADER) == Card.SHADER, "unproven card uses previous fallback")
	print("Source direct lit synthetic: %d checks, %d failures" % [checks, failures])
	if FileAccess.file_exists("res://data/stackcraft.json"):
		var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/stackcraft.json"))
		check(assets.load_manifest() == OK, "private manifest")
		check(assets.load_render_pipeline(catalog.provenance.source_commit) == OK, "private pipeline")
		var admitted := 0
		for item in assets.manifest.materials.values():
			if item.get("shader_source_path", "") not in ["Shaders/Card.shadergraph", "Shaders/SimpleLit.shadergraph"]: continue
			check(Lit.admission(item, assets.manifest, assets.render_pipeline, "gl_compatibility"), "actual graph/material admission " + str(item.get("name", "")))
			admitted += 1
			if RenderingServer.get_current_rendering_method() != "gl_compatibility": continue
			if item.shader_source_path == "Shaders/Card.shadergraph":
				check(Lit.card_shader(assets, item, Card.SHADER).code == Card.SHADER.code + Lit.DIRECT_LIGHT_CODE, "private card fragment + custom light")
			else:
				var board := Lit.board_material(assets, item)
				check(board != null and board.get_shader_parameter("source_base_color").is_equal_approx(Assets.source_color(item.colors._Color)), "private board color unchanged")
		check(admitted > 0, "private graph material count")
		if failures == 0: print("Private source direct lit: PASS (%d materials)" % admitted)
	if failures == 0: print("Source direct lit material: PASS (%d checks)" % checks)
	quit(1 if failures else 0)
