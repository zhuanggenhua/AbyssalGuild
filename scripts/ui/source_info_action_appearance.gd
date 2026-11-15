extends RefCounted
## Locked InfoPanel action only: TMP + TextButton, no Image or Selectable.
## Preserve native glyph layout, content margins, focus and dispatch separately.
const Layout = preload("res://scripts/ui/source_info_action_layout.gd")
const STYLES = ["normal", "hover", "pressed", "hover_pressed", "disabled"]
const COLORS = ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color"]
var active := false
var applied_tint := Color.TRANSPARENT
var saved_styles: Dictionary = {}
var saved_colors: Dictionary = {}
func apply(button: Button, data: Dictionary, label: String, record: Dictionary) -> bool:
	var value = record.get("m_fontColor")
	var admitted: bool = Layout.resolve(data, label).y > 0.0 and value is Dictionary and record.get("m_fontStyle", -1) == 0 and record.get("m_enableVertexGradient", -1) == 0
	if admitted:
		for channel in ["r", "g", "b", "a"]:
			if not value.get(channel) is float and not value.get(channel) is int: admitted = false; break
			if not is_finite(float(value[channel])): admitted = false; break
	if not admitted:
		_restore(button)
		return false
	var first_admission := not active
	if not active:
		for key in STYLES:
			saved_styles[key] = button.get_theme_stylebox(key) if button.has_theme_stylebox_override(key) else null
			var original: StyleBox = button.get_theme_stylebox(key)
			var blank := StyleBoxEmpty.new()
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: blank.set_content_margin(side, original.get_margin(side))
			button.add_theme_stylebox_override(key, blank)
		for key in COLORS: saved_colors[key] = button.get_theme_color(key) if button.has_theme_color_override(key) else null
		active = true
	var tint := Color(float(value.r), float(value.g), float(value.b), float(value.a))
	if first_admission or tint != applied_tint:
		for key in COLORS: button.add_theme_color_override(key, tint)
		applied_tint = tint
	return true
func reset(button: Button) -> void:
	_restore(button)
func _restore(button: Button) -> void:
	if not active: return
	for key in STYLES:
		if saved_styles[key] == null: button.remove_theme_stylebox_override(key)
		else: button.add_theme_stylebox_override(key, saved_styles[key])
	for key in COLORS:
		if saved_colors[key] == null: button.remove_theme_color_override(key)
		else: button.add_theme_color_override(key, saved_colors[key])
	saved_styles.clear()
	saved_colors.clear()
	active = false
