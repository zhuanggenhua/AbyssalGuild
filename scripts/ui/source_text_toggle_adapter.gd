extends Button
## No checkmark: source Toggle targets its two-line label and has graphic=null.
const Metadata = preload("res://scripts/ui/source_control_metadata.gd")
const Tint = preload("res://scripts/ui/selectable_tint.gd")
var allowed: Callable
var model: BaseButton
var metadata: Dictionary
var label := RichTextLabel.new()
var tint = Tint.new()
var last_time := 0
var last_text := ""
var detail_size := 0
func bind(existing: BaseButton, source: Dictionary) -> bool:
	if source.is_empty() or model != null: return false
	var expression := RegEx.new()
	expression.compile("<size=([0-9]+)>")
	var match_size := expression.search(str(source.label.m_text))
	if match_size == null: return false
	detail_size = int(match_size.get_string(1))
	model = existing
	metadata = source
	model.add_child(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	model.self_modulate.a = 0
	model.mouse_filter = Control.MOUSE_FILTER_IGNORE
	model.focus_mode = Control.FOCUS_NONE
	focus_mode = Control.FOCUS_ALL
	process_mode = Node.PROCESS_MODE_ALWAYS
	flat = true
	for state in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.bbcode_enabled = true
	label.scroll_active = false
	label.fit_content = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preload("res://scripts/ui/source_font_registry.gd").shared().bind_control(label, metadata.label)
	label.add_theme_font_size_override("normal_font_size", int(metadata.label.m_fontSize))
	tint.configure(metadata.control.m_Colors)
	pressed.connect(_activate)
	last_time = Time.get_ticks_msec()
	refresh()
	return true
func _activate() -> void:
	if model.disabled or (allowed.is_valid() and not allowed.call()): return
	model.button_pressed = not model.button_pressed
	model.pressed.emit()
	refresh()
func refresh() -> void:
	disabled = model.disabled
	if not model is Button: return
	var content: String = model.text
	if content == last_text and not label.text.is_empty(): return
	last_text = content
	var lines := content.split("\n", true, 1)
	var header: String = lines[0].replace("[", "[lb]")
	var detail: String = lines[1].replace("[", "[lb]") if lines.size() > 1 else ""
	# HorizontalAlignment=2 in the referenced Label. Other alignments stay explicit.
	var centered: bool = int(metadata.label.get("m_HorizontalAlignment", 1)) == 2
	label.text = ("[center]" if centered else "") + header + "\n[font_size=%d]%s[/font_size]" % [detail_size, detail] + ("[/center]" if centered else "")
func _process(_delta: float) -> void:
	refresh()
	var now := Time.get_ticks_msec()
	tint.set_state("Disabled" if model.disabled else ("Pressed" if is_pressed() else ("Selected" if has_focus() else ("Highlighted" if is_hovered() else "Normal"))))
	label.modulate = Metadata.color(metadata.label.m_fontColor) * tint.advance((now-last_time)/1000.0)
	var vertical := int(metadata.label.get("m_VerticalAlignment", 256))
	var content_height := float(label.get_content_height())
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.size.y = content_height
	label.position.y = maxf(0, size.y-content_height) * (0.5 if vertical == 512 else (1.0 if vertical == 1024 else 0.0))
	last_time = now
