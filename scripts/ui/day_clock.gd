extends Button
## Source-backed day clock. Native controls/font; private textures are optional.
const Prefs = preload("res://scripts/ui/title_gameplay_prefs.gd")
var progress: ProgressBar
var native_progress_step := 0.01
var source_config: Dictionary = {}
var assets
const TEXT_SOURCE_COMMIT = "a11a89b04cea8370476f2559b639bb9b4cbc08d8"
const TEXT_COLORS = ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color"]
var source_text_tint_active := false
var source_text_tint := Color.TRANSPARENT
var prior_text_colors: Dictionary = {}
var source_pace_white := false
var pause_icon_tint_active := false
var prior_disabled_icon_color: Variant = null

func _sync_pause_icon_tint(ordinary_source_pause: bool) -> void:
	var admitted := ordinary_source_pause and source_pace_white and is_visible_in_tree() and disabled and icon != null
	if admitted == pause_icon_tint_active: return
	if admitted:
		prior_disabled_icon_color = get_theme_color("icon_disabled_color") if has_theme_color_override("icon_disabled_color") else null
		add_theme_color_override("icon_disabled_color", Color.WHITE)
	else:
		if prior_disabled_icon_color == null: remove_theme_color_override("icon_disabled_color")
		else: add_theme_color_override("icon_disabled_color", prior_disabled_icon_color)
		prior_disabled_icon_color = null
	pause_icon_tint_active = admitted

func _pace_visibility_changed() -> void:
	if not is_visible_in_tree(): _sync_pause_icon_tint(false)

func _configure_pace_tint(source: Dictionary) -> void:
	# Configuration changes end ownership; only the next ordinary-pause sync re-admits.
	_sync_pause_icon_tint(false)
	var provenance = source.get("provenance", {})
	var record: Dictionary = source_config.get("pace_record", {})
	var color = record.get("m_Color")
	source_pace_white = provenance is Dictionary and provenance.get("source_commit", "") == TEXT_SOURCE_COMMIT and source_config.get("source_backed", false) and source_config.get("pace_image_id", "") == "8580080717683932055" and color is Dictionary
	if source_pace_white:
		for key in ["r","g","b","a"]:
			if (not color.get(key) is float and not color.get(key) is int) or color.get(key) != 1: source_pace_white = false; break


func _configure_text_tint(source: Dictionary) -> void:
	var provenance = source.get("provenance", {})
	var record: Dictionary = source_config.get("text_record", {})
	var value = record.get("m_fontColor")
	var admitted: bool = provenance is Dictionary and provenance.get("source_commit", "") == TEXT_SOURCE_COMMIT and source_config.get("source_backed", false) and value is Dictionary and record.get("m_fontStyle", -1) == 0 and record.get("m_enableVertexGradient", -1) == 0
	if admitted:
		for channel in ["r", "g", "b", "a"]:
			if not value.get(channel) is int and not value.get(channel) is float: admitted = false; break
			if not is_finite(float(value[channel])): admitted = false; break
	if not admitted:
		if source_text_tint_active:
			for key in TEXT_COLORS:
				if prior_text_colors[key] == null: remove_theme_color_override(key)
				else: add_theme_color_override(key, prior_text_colors[key])
			prior_text_colors.clear()
			source_text_tint_active = false
		return
	var tint := Color(float(value.r), float(value.g), float(value.b), float(value.a))
	var first := not source_text_tint_active
	if first:
		for key in TEXT_COLORS: prior_text_colors[key] = get_theme_color(key) if has_theme_color_override(key) else null
		source_text_tint_active = true
	if first or tint != source_text_tint:
		for key in TEXT_COLORS: add_theme_color_override(key, tint)
		source_text_tint = tint

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
			return {"source_backed": true, "text_record": Prefs._fields(documents, fields.get("dayText", {})), "fill_record": fill, "pace_record": Prefs._fields(documents, fields.get("paceImage", {})), "pace_image_id": str(fields.get("paceImage", {}).get("fileID", "")), "pace_icons": guids, "color": Color(float(color.get("r", 0.22)), float(color.get("g", 0.65)), float(color.get("b", 0.88)), float(color.get("a", 0.8)))}
	return fallback

func _init() -> void:
	name = "DayClock"
	visibility_changed.connect(_pace_visibility_changed)
	custom_minimum_size = Vector2(300, 50)
	expand_icon = true
	add_theme_constant_override("icon_max_width", 30)
	progress = ProgressBar.new()
	native_progress_step = progress.step
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
	_configure_text_tint(source)
	_configure_progress_precision(source)
	_configure_pace_tint(source)
	preload("res://scripts/ui/source_font_registry.gd").shared().bind_control(self, source_config.get("text_record", {}))
	var fill := StyleBoxFlat.new()
	fill.bg_color = source_config.color
	progress.add_theme_stylebox_override("fill", fill)

func _configure_progress_precision(source: Dictionary) -> void:
	var provenance = source.get("provenance", {})
	var fill: Dictionary = source_config.get("fill_record", {})
	# Locked sprite-backed left-to-right Image.fillAmount has no percentage step.
	# Keep native integer-pixel draw rounding separate; this fixes value transport.
	var admitted: bool = provenance is Dictionary and provenance.get("source_commit", "") == TEXT_SOURCE_COMMIT and source_config.get("source_backed", false) and fill.get("m_Type", -1) == 3 and fill.get("m_FillMethod", -1) == 0 and fill.get("m_FillOrigin", -1) == 0 and fill.get("m_Sprite", {}) is Dictionary and str(fill.get("m_Sprite", {}).get("guid", "")) == "57fe652483042fb4ba6612b888e7a928" and str(fill.get("m_Sprite", {}).get("fileID", "")) == "21300000"
	progress.step = 0.0 if admitted else native_progress_step

func sync(session, is_running: bool, blocked: bool, ordinary_source_pause: bool = false) -> void:
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
	_sync_pause_icon_tint(ordinary_source_pause)
