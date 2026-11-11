extends RefCounted
## MenuToggle.cs: right-aligned half-second unscaled OutQuad slide.
## Native closed endpoint hides the panel so stale journal metadata cannot read it.
const DURATION := 0.5
var panel: Control
var button: Button
var play_click: Callable
var open_position := Vector2.ZERO
var is_animating := false
var elapsed := 0.0
var start_x := 0.0
var target_x := 0.0
var _own_visibility := false
var _visible := false

func configure(target: Control, toggle_button: Button, sound: Callable = Callable()) -> void:
	if is_instance_valid(panel) and panel.visibility_changed.is_connected(_visibility_changed):
		panel.visibility_changed.disconnect(_visibility_changed)
	panel = target
	button = toggle_button
	play_click = sound
	open_position = panel.position
	panel.visibility_changed.connect(_visibility_changed)
	reset(false)

func reset(open: bool = false) -> void:
	is_animating = false
	elapsed = 0.0
	if not is_instance_valid(panel): return
	target_x = 0.0 if open else panel.size.x
	start_x = target_x
	panel.position = open_position + Vector2(target_x, 0)
	_set_visible(open)
	_update_label()

func toggle() -> bool:
	if is_animating or not is_instance_valid(panel): return false
	start_x = panel.position.x - open_position.x
	target_x = panel.size.x if start_x <= 0.0 else 0.0
	elapsed = 0.0
	is_animating = true
	_set_visible(true)
	if play_click.is_valid(): play_click.call()
	return true

func day_ended() -> bool:
	# An opening panel with x > 0 remains open; an already animating panel
	# at exactly x = 0 ignores this request just like source Toggle().
	if is_instance_valid(panel) and panel.position.x <= open_position.x:
		return toggle()
	return false

func advance(unscaled_delta: float) -> void:
	if not is_animating or not is_instance_valid(panel): return
	elapsed = minf(DURATION, elapsed + maxf(0.0, unscaled_delta))
	var t := elapsed / DURATION
	var eased := 1.0 - (1.0 - t) * (1.0 - t)
	panel.position.x = open_position.x + lerpf(start_x, target_x, eased)
	if elapsed >= DURATION:
		is_animating = false
		_set_visible(target_x <= 0.0)
		_update_label()

func _set_visible(value: bool) -> void:
	_own_visibility = true
	_visible = value
	panel.visible = value
	_own_visibility = false

func _visibility_changed() -> void:
	# Ancestor HUD visibility changes must not be mistaken for explicit panel
	# show/hide calls. Preserve compatibility with native inspection callers.
	if not _own_visibility and panel.visible != _visible:
		reset(panel.visible)

func _update_label() -> void:
	if is_instance_valid(button): button.text = "<<" if target_x > 0.0 else ">>"

static func initial_state(data: Dictionary) -> Dictionary:
	# Resolve the specific MenuToggle reference, never an arbitrary RectTransform.
	for prefab in data.get("referenced_prefabs", []):
		if prefab.get("name", "") != "UIRoot": continue
		var documents: Array = prefab.get("documents", [])
		for component in documents:
			if component.get("script_class", "") != "MenuToggle": continue
			var target_id := str(component.get("fields", {}).get("targetRect", {}).get("fileID", ""))
			if target_id in ["", "0"]: continue
			for document in documents:
				if str(document.get("file_id", "")) != target_id or document.get("object_type", "") != "RectTransform": continue
				var position: Dictionary = document.get("fields", {}).get("m_AnchoredPosition", {})
				if not position.has("x"): continue
				return {"open": float(position.x) <= 0.0, "source_backed": true, "warning": ""}
	return {"open": false, "source_backed": false, "warning": "MenuToggle target rect unavailable; native closed fallback."}
