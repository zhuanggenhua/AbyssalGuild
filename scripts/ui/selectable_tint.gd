extends RefCounted
const Metadata = preload("res://scripts/ui/source_control_metadata.gd")
var colors: Dictionary
var current := Color.WHITE
var start := Color.WHITE
var target := Color.WHITE
var elapsed := 0.0
func configure(value: Dictionary) -> void:
	colors = value
	current = Metadata.color(colors.get("m_NormalColor", {})) * float(colors.get("m_ColorMultiplier", 1))
	start = current
	target = current
func set_state(state: String) -> void:
	var next := Metadata.color(colors.get("m_" + state + "Color", {})) * float(colors.get("m_ColorMultiplier", 1))
	if target.is_equal_approx(next): return
	start = current
	target = next
	elapsed = 0
func advance(delta: float) -> Color:
	elapsed += maxf(0, delta)
	var duration := float(colors.get("m_FadeDuration", 0))
	current = start.lerp(target, 1.0 if duration <= 0 else minf(1, elapsed/duration))
	return current
