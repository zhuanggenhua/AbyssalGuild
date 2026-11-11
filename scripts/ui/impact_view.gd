extends Node3D
## Generated semantic popup, independent of target lifetime and simulation speed.
## Original sprite animation, shader flash and camera shake are not reproduced here.
var elapsed: float = 0.0
var duration: float = 1.0
var caption: Label3D
func configure(descriptor: Dictionary, target: Vector3, kind: String) -> void:
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
func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
		return
	if caption != null:
		caption.modulate.a = clampf((duration - elapsed) * 3.0, 0.0, 1.0)
