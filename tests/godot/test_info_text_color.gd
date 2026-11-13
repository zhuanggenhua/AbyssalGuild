extends SceneTree
const View = preload("res://scripts/ui/card_hover_view.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var view := View.new()
	root.add_child(view)
	var theme := Theme.new()
	var header_fallback := Color(0.2,0.3,0.4,0.9)
	var body_fallback := Color(0.4,0.5,0.6,0.7)
	theme.set_color("font_color","Label",header_fallback)
	theme.set_color("default_color","RichTextLabel",body_fallback)
	view.theme = theme
	var background: StyleBox = view.get_theme_stylebox("panel")
	var background_color: Color = background.bg_color
	var original_modulate := view.modulate
	check(not view.configure_source_text_color({}), "missing source record uses native theme")
	check(view.header.get_theme_color("font_color") == header_fallback and view.body.get_theme_color("default_color") == body_fallback, "missing record preserves independent native text defaults")
	var expected := Color(0.17,0.37,0.67,0.43)
	var record := {"m_fontColor":{"r":0.17,"g":0.37,"b":0.67,"a":0.43}}
	var snapshot: Dictionary = record.duplicate(true)
	check(view.configure_source_text_color(record), "complete synthetic RGBA admitted")
	check(view.header.get_theme_color("font_color").is_equal_approx(expected), "header receives all four source channels, not a fixed alpha")
	check(view.body.get_theme_color("default_color").is_equal_approx(expected), "body receives all four source channels")
	check(record == snapshot, "source record is read only")
	for descriptor in [{"header":"Card","body":"Description"},{"header":"Quest","body":"Progress","action":"Continue"},{},{"body":"Body only"}]:
		view.set_descriptor(descriptor)
		view.set_bounds(Rect2(30,600,400,0))
		check(view.header.get_theme_color("font_color").is_equal_approx(expected) and view.body.get_theme_color("default_color").is_equal_approx(expected), "descriptor/layout changes preserve both text colors")
	check(view.modulate == original_modulate and view.self_modulate == Color.WHITE and view.header.modulate == Color.WHITE and view.body.modulate == Color.WHITE, "no container or node modulation introduced")
	check(view.get_theme_stylebox("panel") == background and background.bg_color == background_color, "panel background object and color unchanged")
	check(not view.configure_source_text_color({}), "missing replacement removes previous source binding")
	check(not view.header.has_theme_color_override("font_color") and not view.body.has_theme_color_override("default_color"), "missing source leaves no stale override")
	check(view.header.get_theme_color("font_color") == header_fallback and view.body.get_theme_color("default_color") == body_fallback, "fallback restores live native theme values, not fixed white")
	for malformed in [null, [], "white", {}, {"r":1,"g":1,"b":1}, {"r":1,"g":1,"b":1,"a":"0.8"}, {"r":1,"g":1,"b":1,"a":NAN}]:
		view.configure_source_text_color(record)
		check(not view.configure_source_text_color({"m_fontColor":malformed}), "malformed source color is not guessed")
		check(not view.header.has_theme_color_override("font_color") and not view.body.has_theme_color_override("default_color"), "malformed replacement clears both former overrides")
	check(view.configure_source_text_color({"m_fontColor":{"r":1,"g":1,"b":1,"a":0}}), "integer channels and transparent alpha supported")
	check(view.header.get_theme_color("font_color") == Color(1,1,1,0) and view.body.get_theme_color("default_color") == Color(1,1,1,0), "transparent alpha is not replaced with a default")
	view.queue_free(); await process_frame
	print("InfoText color checks: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
