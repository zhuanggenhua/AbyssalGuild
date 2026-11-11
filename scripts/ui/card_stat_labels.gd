extends RefCounted
## Numeric label adapter. Source rectangles/colors; Godot font metrics, not TMP.
const SourceCamera = preload("res://scripts/ui/source_camera.gd")

static func create(assets, record: Dictionary, lift: float, source_style: bool) -> Label3D:
	var pose := SourceCamera.reflected_pose(record.get("transform_chain", []))
	var rect: Dictionary = record.get("rect_size", {})
	if pose.is_empty() or float(rect.get("x", 0.0)) <= 0 or float(rect.get("y", 0.0)) <= 0:
		return null
	var label := Label3D.new()
	label.transform = pose.transform
	label.position.y += lift
	label.font_size = 32
	label.outline_size = 0
	label.no_depth_test = false
	label.modulate = assets.source_color(record.get("color", {})) if source_style else Color("162b33")
	label.set_meta("source_rect_size", Vector2(float(rect.x), float(rect.y)))
	return label

static func set_value(label: Label3D, value: String) -> void:
	label.text = value
	var rect: Vector2 = label.get_meta("source_rect_size")
	var font := ThemeDB.fallback_font
	var pixel_width: float = maxf(font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x, 1.0)
	var pixel_height: float = maxf(font.get_height(label.font_size), 1.0)
	label.pixel_size = minf(rect.x / pixel_width, rect.y * 0.8 / pixel_height)
	label.width = rect.x / label.pixel_size
