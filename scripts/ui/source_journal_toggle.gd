extends Button
## Authored Journal Toggle: selectable TMP tint and on/off Image are independent.
const Metadata = preload("res://scripts/ui/source_control_metadata.gd")
const Tint = preload("res://scripts/ui/selectable_tint.gd")
const Fonts = preload("res://scripts/ui/source_font_registry.gd")
var source: Dictionary = {}
var image := ColorRect.new()
var label := Label.new()
var tint = Tint.new()
var binding: Dictionary = {}
var selected := false
var image_alpha := 0.0
var alpha_start := 0.0
var alpha_target := 0.0
var alpha_elapsed := 0.0
var last_time := 0

static func resolve(docs: Array, owner: Dictionary) -> Dictionary:
	var control := Metadata.component(docs, owner, "m_IsOn")
	if control.get("m_Transition", -1) != 1 or control.get("toggleTransition", -1) != 1: return {}
	var graphic := Metadata.fields(docs, control.get("graphic", {}))
	var target := Metadata.fields(docs, control.get("m_TargetGraphic", {}))
	var group := Metadata.fields(docs, control.get("m_Group", {}))
	if group.get("m_AllowSwitchOff", -1) != 0: return {}
	if not graphic.has("m_Color") or str(graphic.get("m_Sprite", {}).get("fileID", "")) != "0": return {}
	if not target.has("m_fontSize") or not target.has("m_text") or not control.has("m_Colors"): return {}
	return {"control":control,"graphic":graphic,"label":target,"label_rect":Metadata.rect(docs,target),"image_rect":Metadata.rect(docs,graphic)}

func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	process_mode = Node.PROCESS_MODE_ALWAYS
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(image)
	add_child(label)
	last_time = Time.get_ticks_msec()
	resized.connect(place)

func configure(value: Dictionary) -> void:
	if value == source: return
	source = value.duplicate(true)
	if source.is_empty():
		if not label.text.is_empty(): text = label.text
		binding.clear()
		for control in [self, label]:
			control.remove_theme_font_override("font")
			for key in ["source_font_status", "source_font_guid", "source_baseline_down"]:
				if control.has_meta(key): control.remove_meta(key)
		image.hide()
		label.hide()
		return
	image.show()
	label.show()
	text = ""
	label.text = str(source.label.m_text)
	label.add_theme_font_size_override("font_size", int(source.label.m_fontSize))
	binding = Fonts.shared().bind_control(label, source.label)
	# Retain the Button binding metadata for existing source-font audits.
	Fonts.shared().bind_control(self, source.label)
	image.color = Metadata.color(source.graphic.m_Color)
	tint.configure(source.control.m_Colors)
	set_selected(bool(source.control.m_IsOn), true)
	place()

func set_selected(value: bool, instant := false, replay := false) -> void:
	if selected == value and not instant and not replay: return
	selected = value
	alpha_start = image_alpha
	alpha_target = 1.0 if value else 0.0
	alpha_elapsed = 0
	if instant:
		image_alpha = alpha_target
		alpha_start = alpha_target
		alpha_elapsed = .1
		image.modulate.a = image_alpha

func advance_visual(delta: float, state: String) -> void:
	if source.is_empty(): return
	tint.set_state(state)
	label.modulate = Metadata.color(source.label.m_fontColor) * tint.advance(delta)
	alpha_elapsed += maxf(0, delta)
	# uGUI Toggle.PlayEffect(false): Graphic.CrossFadeAlpha(target, .1, true).
	image_alpha = lerpf(alpha_start, alpha_target, minf(1, alpha_elapsed / .1))
	image.modulate.a = image_alpha

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	advance_visual((now-last_time)/1000.0, "Disabled" if disabled else ("Pressed" if is_pressed() else ("Selected" if has_focus() else ("Highlighted" if is_hovered() else "Normal"))))
	last_time = now

func place() -> void:
	if source.is_empty(): return
	var graphic_rect := Metadata.rectangle(source.image_rect, size)
	image.position = graphic_rect.position
	image.size = graphic_rect.size
	var area := Metadata.rectangle(source.label_rect, size)
	label.size = Vector2(area.size.x, label.get_combined_minimum_size().y)
	label.position = area.position + Vector2(0, (area.size.y-label.size.y)/2)
	var metrics: Dictionary = binding.get("source_metrics", {})
	if not metrics.has("m_FaceInfo"): return # Explicit native fallback without private face data.
	var face: Dictionary = metrics.m_FaceInfo
	var font_size := int(source.label.m_fontSize)
	var line := TextLine.new()
	line.add_string(label.text, label.get_theme_font("font"), font_size)
	var baseline := area.size.y/2 + (float(face.m_AscentLine)+float(face.m_DescentLine))*font_size/float(face.m_PointSize)*float(face.m_Scale)/2
	label.position.y = area.position.y + baseline - line.get_line_ascent()
	set_meta("source_baseline_down", area.position.y + baseline)
