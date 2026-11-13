extends SceneTree
const Effect = preload("res://scripts/ui/world_post_process.gd")
var checks := 0
func check(value: bool) -> void:
	checks += 1
	assert(value)
func _init() -> void:
	var component := {"source_backed":true,"material_guid":"effect","material_file_id":"21","renderer_index":-1}
	var profile := {"schema_version":1,"graphics_pipeline_guid":"urp","selected_quality":0,"qualities":[{"pipeline_guid":""}],"custom_feature_script_guid":"custom-script","pipelines":{"urp":{"schema":"urp_renderer_list","default_renderer_index":0,"renderer_guids":["pc","custom"]}},"renderers":{"pc":{"features":[{"script_guid":"ssao","active":true}]},"custom":{"features":[{"script_guid":"custom-script","active":true,"material_guid":"effect","material_file_id":"21"}]}}}
	check(Effect.resolve_pass({},component).status == "unknown")
	check(Effect.resolve_pass(profile,component).status == "disabled")
	component.renderer_index = 1
	check(Effect.resolve_pass(profile,component).status == "unknown")
	check("RenderGraph" in Effect.resolve_pass(profile,component).reason)
	# Camera postprocessing cannot prove RenderGraph execution for this pass.
	component["camera_post_processing"] = false
	check(Effect.resolve_pass(profile,component).status == "unknown")
	# Unvalidated mode hints cannot turn routing into supported execution.
	profile["render_graph_enabled"] = true
	check(Effect.resolve_pass(profile,component).status == "unknown")
	profile["render_graph_enabled"] = false
	check(Effect.resolve_pass(profile,component).status == "unknown")
	profile.renderers.custom.features[0].active = false
	check(Effect.resolve_pass(profile,component).status == "disabled")
	profile.renderers.custom.features[0].active = true
	profile.renderers.custom.features[0].material_file_id = "0"
	check(Effect.resolve_pass(profile,component).status == "disabled")
	profile.renderers.custom.features[0].material_file_id = "21"
	profile.renderers.custom.features[0].material_guid = "different-material"
	check(Effect.resolve_pass(profile,component).status == "unknown")
	profile.renderers.custom.features[0].material_guid = "effect"
	profile.renderers.custom.features.append(profile.renderers.custom.features[0].duplicate())
	check(Effect.resolve_pass(profile,component).status == "unknown")
	component.renderer_index = 99
	check(Effect.resolve_pass(profile,component).status == "unknown")
	component.renderer_index = -2
	check(Effect.resolve_pass(profile,component).status == "unknown")
	component.renderer_index = -1
	profile.qualities[0].pipeline_guid = "other"
	check(Effect.resolve_pass(profile,component).status == "unknown")
	profile.qualities[0].pipeline_guid = ""
	profile.graphics_pipeline_guid = ""
	check(Effect.resolve_pass(profile,component).status == "enabled")
	component.source_backed = false
	check(Effect.resolve_pass(profile,component).status == "unknown")

	var source := {"scenes":[{"name":"Game","documents":[{"fields":{"m_SourcePrefab":{"guid":"camera-prefab"}}}]}],"guid_index":{"effect":{"kind":"mat"}},"referenced_prefabs":[{"guid":"camera-prefab","documents":[
		{"file_id":"owner","class_id":1,"fields":{"m_IsActive":1}},
		{"file_id":"camera","class_id":20,"fields":{"m_GameObject":{"fileID":"owner"},"m_Enabled":1}},
		{"file_id":"urp-data","fields":{"m_GameObject":{"fileID":"owner"},"m_RendererIndex":1,"m_RenderPostProcessing":0}},
		{"file_id":"writer","script_class":"BuiltInPostProcess","fields":{"m_GameObject":{"fileID":"owner"},"m_Enabled":1,"effectMaterial":{"guid":"effect","fileID":"21"},"grayscaleIntensity":0.0,"vignetteIntensity":0.0}}
	]}]}
	var linked = Effect.new()
	linked.attach(root)
	linked.configure(source,"Game",profile) # Built-in profile, enabled writer.
	check(linked.rect.visible and linked.config.render_pass.status == "enabled")
	profile.graphics_pipeline_guid = "urp"
	profile.renderers.custom.features.resize(1)
	linked.configure(source,"Game",profile) # Actual camera override selects custom renderer.
	check(not linked.rect.visible and linked.config.renderer_index == 1)
	check(linked.config.render_pass.status == "unknown")
	linked.event("time_pace_changed",{"pace":0})
	linked.advance(0.3)
	check(linked.grayscale == 1.0 and not linked.rect.visible)
	source.scenes[0].documents[0].fields["m_Modification"] = {"m_Modifications":[{"target":{"fileID":"urp-data","guid":"camera-prefab"},"propertyPath":"m_RendererIndex","value":"0"}]}
	linked.configure(source,"Game",profile)
	check(not linked.rect.visible and linked.config.render_pass.status == "disabled")
	linked.event("time_pace_changed",{"pace":0})
	linked.advance(0.3)
	check(linked.grayscale == 1.0 and not linked.rect.visible)
	linked.rect.get_parent().free()
	var effect = Effect.new()
	effect.attach(root)
	effect.config = {"source_backed":true,"render_pass":{"status":"disabled"}}
	effect.event("time_pace_changed",{"pace":0})
	effect.advance(0.3)
	check(effect.grayscale == 1.0 and not effect.rect.visible)
	check(effect.rect.material.get_shader_parameter("grayscale_amount") == 1.0)
	effect.config.render_pass.status = "enabled"
	effect.advance(0.01)
	check(effect.rect.visible) # Same material state now sampled by an admitted pass.
	effect.config.render_pass.status = "unknown"
	effect.advance(0.01)
	check(not effect.rect.visible)
	effect.rect.get_parent().free()
	print("Render pipeline admission: PASS (%d checks)" % checks)
	quit()
