extends Button
## Source-backed day clock. Native controls/font; private textures are optional.
const Prefs = preload("res://scripts/ui/title_gameplay_prefs.gd")
var progress: ProgressBar
var source_config: Dictionary = {}
var assets

static func resolve(source: Dictionary, scene_name: String) -> Dictionary:
	var fallback := {"source_backed": false, "pace_icons": [], "color": Color(0.22, 0.65, 0.88, 0.8)}
	var referenced: Array = []
	for scene in source.get("scenes", []):
		if str(scene.get("name", "")) != scene_name: continue
		for document in scene.get("documents", []):
			var reference: Dictionary = document.get("fields", {}).get("m_SourcePrefab", {})
			if reference.has("guid"): referenced.append(str(reference.guid))
	for prefab in source.get("referenced_prefabs", []):
		if not referenced.has(str(prefab.get("guid", ""))): continue
		var documents: Array = prefab.get("documents", [])
		for document in documents:
			if document.get("script_class", "") != "DayTimeUI": continue
			var fields: Dictionary = document.get("fields", {})
			var fill := Prefs._fields(documents, fields.get("timeProgress", {}))
			var icons: Array = fields.get("paceIcons", [])
			if fill.is_empty() or icons.size() != 3: return fallback
			var guids: Array = []
			for reference in icons:
				if not reference is Dictionary or str(reference.get("guid", "")).is_empty(): return fallback
				guids.append(str(reference.guid))
			var color: Dictionary = fill.get("m_Color", {})
			return {"source_backed": true, "pace_icons": guids, "color": Color(float(color.get("r", 0.22)), float(color.get("g", 0.65)), float(color.get("b", 0.88)), float(color.get("a", 0.8)))}
	return fallback

func _init() -> void:
	name = "DayClock"
	custom_minimum_size = Vector2(300, 50)
	expand_icon = true
	add_theme_constant_override("icon_max_width", 30)
	progress = ProgressBar.new()
	progress.name = "DayProgress"
	progress.show_percentage = false
	progress.max_value = 1.0
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(progress)
	progress.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	progress.show_behind_parent = true
	add_theme_font_size_override("font_size", 30)
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var clear := StyleBoxEmpty.new()
	clear.content_margin_left = 10
	clear.content_margin_right = 10
	for state in ["normal", "hover", "pressed", "disabled", "focus"]: add_theme_stylebox_override(state, clear)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.8)
	progress.add_theme_stylebox_override("background", background)

func configure(source: Dictionary, scene_name: String, visual_assets) -> void:
	source_config = resolve(source, scene_name)
	assets = visual_assets
	var fill := StyleBoxFlat.new()
	fill.bg_color = source_config.color
	progress.add_theme_stylebox_override("fill", fill)

func sync(session, is_running: bool, blocked: bool) -> void:
	visible = is_running and session.phase == "playing"
	disabled = not visible or blocked
	var pace: int = session.time_pace()
	text = "Day %d" % session.day
	progress.value = clampf(session.elapsed / maxf(session.day_duration, 0.001), 0.0, 1.0)
	icon = null
	if source_config.get("source_backed", false) and assets != null:
		icon = assets.texture(str(source_config.pace_icons[pace]))
	tooltip_text = "Click: Normal → Fast → Paused → Normal"
	if icon == null: tooltip_text += "\nNative text fallback; original pace artwork unavailable."
