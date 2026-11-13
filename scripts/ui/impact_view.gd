extends Node3D
## Generated semantic popup, independent of target lifetime and simulation speed.
## Source DOTween 1.2.790 additive piecewise OutQuad punch.
const SourceTween = preload("res://scripts/ui/source_tween.gd")
var punch_plan: Dictionary = {}
var fallback_scale := Vector3.ONE
var elapsed: float = 0.0
var duration: float = 1.0
var caption: Label3D
var source_popup: Node3D
var source_scale := Vector3.ONE
func configure(descriptor: Dictionary, target: Vector3, kind: String, assets = null, scene_name: String = "Main", advantage: int = 0) -> void:
	var offset: Vector3 = descriptor.popup.defender_local_offset
	position = target + Vector3(offset.x, offset.y, -offset.z)
	duration = float(descriptor.popup.duration)
	punch_plan = SourceTween.punch_plan(descriptor.popup.punch_scale, duration)
	fallback_scale = scale
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
	if source_popup != null:
		source_popup.scale = SourceTween.punch_sample(punch_plan, source_scale, elapsed)
	else:
		scale = SourceTween.punch_sample(punch_plan, fallback_scale, elapsed)
	if elapsed >= duration:
		queue_free()
