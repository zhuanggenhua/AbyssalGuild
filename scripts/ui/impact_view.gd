extends Node3D
## Generated semantic popup, independent of target lifetime and simulation speed.
## Source punch amplitude/lifetime with an explicitly approximate decaying sine.
var elapsed: float = 0.0
var duration: float = 1.0
var caption: Label3D
var source_popup: Node3D
var source_scale := Vector3.ONE
func configure(descriptor: Dictionary, target: Vector3, kind: String, assets = null, scene_name: String = "Main", advantage: int = 0) -> void:
	var offset: Vector3 = descriptor.popup.defender_local_offset
	position = target + Vector3(offset.x, offset.y, -offset.z)
	duration = float(descriptor.popup.duration)
	caption = Label3D.new()
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.no_depth_test = true
	caption.font_size = 48
	caption.pixel_size = 0.008
	caption.text = "MISS" if kind == "miss" else str(descriptor.damage_text) + ("!" if kind == "critical" else "")
	caption.modulate = Color(1.0, 0.8, 0.2) if kind == "critical" else Color.WHITE
	add_child(caption)
	if assets != null and assets.has_method("create_hit_popup"):
		source_popup = assets.create_hit_popup(kind, str(descriptor.damage_text), advantage, scene_name)
		if source_popup != null:
			source_scale = source_popup.scale
			add_child(source_popup)
			caption.hide()
func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
		return
	var punch: float = 0.15 * sin(elapsed / duration * TAU * 10.0) * (1.0 - elapsed / duration)
	if source_popup != null:
		source_popup.scale = source_scale * Vector3(1.0 + punch, 1.0 + punch, 1.0)
	else:
		scale = Vector3(1.0 + punch, 1.0 + punch, 1.0)
	if caption != null:
		caption.modulate.a = clampf((duration - elapsed) * 3.0, 0.0, 1.0)
