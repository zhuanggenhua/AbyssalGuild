extends RefCounted
## Independent native implementation of the source camera's event-driven effect.
const EFFECT_SHADER = preload("res://scripts/ui/world_post_process.gdshader")
var config: Dictionary = {}
var grayscale: float = 0.0
var vignette: float = 0.0
var tracks: Dictionary = {}
var rect: ColorRect

static func resolve(source: Dictionary, scene_name: String) -> Dictionary:
	var fallback := {"source_backed": false, "grayscale": 0.0, "vignette": 0.0, "warning": "Camera post-process unavailable; world is shown unchanged."}
	for scene in source.get("scenes", []):
		if str(scene.get("name", "")) != scene_name: continue
		for instance in scene.get("documents", []):
			var instance_fields: Dictionary = instance.get("fields", {})
			var prefab_guid: String = str(instance_fields.get("m_SourcePrefab", {}).get("guid", ""))
			for prefab in source.get("referenced_prefabs", []):
				if prefab_guid.is_empty() or str(prefab.get("guid", "")) != prefab_guid: continue
				var docs: Array = prefab.get("documents", []).duplicate(true)
				for removed in instance_fields.get("m_Modification", {}).get("m_RemovedComponents", []) + instance_fields.get("m_Modification", {}).get("m_RemovedGameObjects", []):
					docs = docs.filter(func(doc): return str(doc.get("file_id", "")) != str(removed.get("fileID", "")))
				for modification in instance_fields.get("m_Modification", {}).get("m_Modifications", []):
					var target_guid: String = str(modification.get("target", {}).get("guid", ""))
					if not target_guid.is_empty() and target_guid != prefab_guid: continue
					for doc in docs:
						if str(doc.get("file_id", "")) != str(modification.get("target", {}).get("fileID", "")): continue
						var property: String = str(modification.get("propertyPath", ""))
						if property in ["m_Enabled", "m_IsActive", "vignetteIntensity", "grayscaleIntensity"]:
							doc.fields[property] = float(modification.get("value", 0))
						elif property == "effectMaterial": doc.fields[property] = modification.get("objectReference", {})
				for doc in docs:
					if doc.get("script_class", "") != "BuiltInPostProcess": continue
					var fields: Dictionary = doc.get("fields", {})
					if not bool(fields.get("m_Enabled", 0)) or not _active(docs, fields.get("m_GameObject", {})): continue
					var camera_enabled := false
					for camera_doc in docs:
						if int(camera_doc.get("class_id", 0)) == 20 and camera_doc.get("fields", {}).get("m_GameObject", {}) == fields.get("m_GameObject", {}):
							camera_enabled = bool(camera_doc.get("fields", {}).get("m_Enabled", 0))
					if not camera_enabled: continue
					var material_ref: Dictionary = fields.get("effectMaterial", {})
					var material_guid: String = str(material_ref.get("guid", ""))
					if str(material_ref.get("fileID", "0")) == "0" or source.get("guid_index", {}).get(material_guid, {}).get("kind", "") != "mat": continue
					return {"source_backed": true, "prefab_guid": prefab_guid, "component_id": str(doc.file_id), "material_guid": material_guid, "grayscale": float(fields.get("grayscaleIntensity", 0)), "vignette": float(fields.get("vignetteIntensity", 0)), "warning": ""}
	return fallback

static func _active(docs: Array, game_object: Dictionary, visited: Array = []) -> bool:
	var id: String = str(game_object.get("fileID", "0"))
	if id == "0" or visited.has(id): return false
	visited.append(id)
	var found := false
	for doc in docs:
		if str(doc.get("file_id", "")) == id:
			found = bool(doc.get("fields", {}).get("m_IsActive", 0))
	if not found: return false
	for transform in docs:
		if int(transform.get("class_id", 0)) != 4 or transform.get("fields", {}).get("m_GameObject", {}) != game_object: continue
		var parent: String = str(transform.fields.get("m_Father", {}).get("fileID", "0"))
		if parent == "0": return true
		for doc in docs:
			if str(doc.get("file_id", "")) == parent: return _active(docs, doc.get("fields", {}).get("m_GameObject", {}), visited)
		return false
	return true

func attach(parent: Node) -> void:
	var layer := CanvasLayer.new()
	layer.name = "WorldPostProcessLayer"
	layer.layer = 0 # 3D world first, HUD default layer 1, scene fader 100.
	parent.add_child(layer)
	rect = ColorRect.new()
	rect.name = "WorldPostProcess"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = EFFECT_SHADER
	rect.material = material
	cancel()

func configure(source: Dictionary, scene_name: String) -> void:
	cancel()
	config = resolve(source, scene_name)
	grayscale = config.grayscale
	vignette = config.vignette
	_sync()

func cancel() -> void:
	tracks.clear()
	config = {"source_backed": false}
	grayscale = 0.0
	vignette = 0.0
	_sync()

func event(kind: String, payload: Dictionary = {}) -> void:
	if not config.get("source_backed", false): return
	if kind == "time_pace_changed": _start("grayscale", 1.0 if int(payload.get("pace", 1)) == 0 else 0.0, 0.3)
	elif kind == "day_ended": _start("vignette", 1.2, 0.5)
	elif kind == "day_started": _start("vignette", 0.0, 0.5)

func _start(property: String, target: float, duration: float) -> void:
	tracks[property] = {"from": get(property), "target": target, "duration": duration, "elapsed": 0.0}

func advance(real_delta: float) -> void:
	if not is_finite(real_delta) or real_delta <= 0: return
	for property in tracks.keys():
		var track: Dictionary = tracks[property]
		track.elapsed = minf(track.duration, track.elapsed + real_delta)
		var t: float = track.elapsed / track.duration
		set(property, lerpf(track.from, track.target, t * (2.0 - t)))
		if t >= 1.0: tracks.erase(property)
	_sync()

func _sync() -> void:
	if not is_instance_valid(rect): return
	rect.visible = config.get("source_backed", false)
	rect.material.set_shader_parameter("grayscale_amount", grayscale)
	rect.material.set_shader_parameter("vignette_power", vignette)

static func shade(color: Color, uv: Vector2, gray: float, power: float) -> Color:
	var luma: float = color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	var t: float = clampf((uv.distance_to(Vector2(0.5, 0.5)) * power - 0.2) / 0.6, 0, 1)
	var factor: float = 1.0 - t * t * (3.0 - 2.0 * t)
	return Color(lerpf(color.r, luma, gray) * factor, lerpf(color.g, luma, gray) * factor, lerpf(color.b, luma, gray) * factor, color.a)
