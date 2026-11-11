extends RefCounted
## View-space camera target/velocity, independent of gameplay and combat shake.
var target := Vector3.ZERO
var velocity := Vector3.ZERO
const DEFAULTS = {"panSpeed":0.01,"smoothTime":0.15,"panPadding":0.5,"zoomSpeed":1.0,"minDistance":5.0,"maxDistance":20.0}
var settings: Dictionary = DEFAULTS.duplicate()
var bounds := Rect2(-10,-5,20,10)
var focus: Dictionary = {}
var bounds_initialized: bool = false

static func source_settings(data: Dictionary, scene_name: String) -> Dictionary:
	for scene in data.get("scenes", []):
		if str(scene.get("name", "")) != scene_name: continue
		for document in scene.get("documents", []):
			var scene_fields: Dictionary = document.get("fields", {})
			var guid: String = str(scene_fields.get("m_SourcePrefab", {}).get("guid", ""))
			for prefab in data.get("referenced_prefabs", []):
				if str(prefab.get("guid", "")) != guid: continue
				for component in prefab.get("documents", []):
					if component.get("script_class", "") != "CameraController": continue
					var result: Dictionary = component.fields.duplicate(true)
					for override in scene_fields.get("m_Modification", {}).get("m_Modifications", []):
						if str(override.get("target", {}).get("fileID", "")) == str(component.get("file_id", "")):
							var key: String = str(override.get("propertyPath", ""))
							if result.has(key): result[key] = override.get("value")
					return result
	return {}

func configure(position: Vector3, imported: Dictionary = {}) -> void:
	settings = DEFAULTS.duplicate()
	target = position
	velocity = Vector3.ZERO
	focus.clear()
	bounds_initialized = false
	for key in settings:
		if imported.has(key) and is_finite(float(imported[key])): settings[key] = float(imported[key])

func set_bounds(model_bounds: Rect2) -> void:
	var reflected := Rect2(model_bounds.position.x, -model_bounds.end.y, model_bounds.size.x, model_bounds.size.y)
	if bounds_initialized and bounds == reflected: return
	bounds = reflected
	bounds_initialized = true
	clamp_target()

func clamp_target() -> void:
	if is_zero_approx(bounds.size.x): return
	var padding: float = settings.panPadding
	target.x = clampf(target.x, bounds.position.x-padding, bounds.end.x+padding)
	target.z = clampf(target.z, bounds.position.y-padding, bounds.end.y+padding)

func pan(pixel_delta: Vector2, current_height: float) -> void:
	# Godot screen Y points down; source pointer Y and world Z are both reflected.
	target += Vector3(-pixel_delta.x,0,-pixel_delta.y) * float(settings.panSpeed) * current_height / 10.0
	clamp_target()

func zoom(scroll: float, forward: Vector3) -> bool:
	if absf(scroll) <= 0.01 or -forward.y <= 0.0001: return false
	var candidate: Vector3 = target + forward * scroll * float(settings.zoomSpeed)
	var distance: float = candidate.y / -forward.y
	if distance < float(settings.minDistance) or distance > float(settings.maxDistance): return false
	target = candidate
	clamp_target()
	return true

func move_to(current: Vector3, point: Vector3, forward: Vector3, duration: float = 0.5) -> void:
	var distance: float = lerpf(float(settings.maxDistance),float(settings.minDistance),0.8)
	focus = {"start":current,"end":point-forward*distance,"duration":maxf(duration,0),"elapsed":0.0}

func step(current: Vector3, real_delta: float, input_enabled: bool) -> Vector3:
	if not is_finite(real_delta) or real_delta <= 0: return current
	if not focus.is_empty():
		focus.elapsed += real_delta
		var t: float = 1.0 if focus.duration <= 0 else clampf(focus.elapsed/focus.duration,0,1)
		# DOTween's default OutQuad is approximated explicitly, not engine tweens.
		var result: Vector3 = focus.start.lerp(focus.end,1.0-(1.0-t)*(1.0-t))
		if t >= 1:
			target = focus.end # Source MoveTo does not clamp its focus endpoint.
			focus.clear()
		return result
	if not input_enabled: return current
	var smooth: float = maxf(0.0001,float(settings.smoothTime))
	var omega: float = 2.0/smooth
	var x: float = omega*real_delta
	var decay: float = 1.0/(1.0+x+0.48*x*x+0.235*x*x*x)
	var change: Vector3 = current-target
	var temp: Vector3 = (velocity+omega*change)*real_delta
	velocity = (velocity-omega*temp)*decay
	var output: Vector3 = target+(change+temp)*decay
	if (target-current).dot(output-target) > 0:
		output = target
		velocity = Vector3.ZERO
	return output
