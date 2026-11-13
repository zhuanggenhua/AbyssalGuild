extends SceneTree
## Strict private test: no copied source metrics/fixtures and no resource SKIP.
const Assets = preload("res://scripts/ui/visual_assets.gd")
const Fonts = preload("res://scripts/ui/source_font_registry.gd")
const Title = preload("res://scripts/ui/card_title_label.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
const Recipes = preload("res://scripts/model/recipe_card_definition.gd")
const Layout = preload("res://scripts/ui/tmp_single_line_layout.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _init() -> void:
	var assets = Assets.new()
	if assets.load_manifest() != OK or not FileAccess.file_exists("res://data/stackcraft.json"):
		printerr("FAIL: required private visual manifest/catalog missing")
		quit(1)
		return
	var fonts = Fonts.shared()
	if fonts.load_manifest() != OK:
		printerr("FAIL: required private font manifest missing")
		quit(1)
		return
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/stackcraft.json"))
	var model = Catalog.new()
	model.configure(catalog)
	var templates := 0
	var count := 0
	var supported := 0
	var minimum_overflows := 0
	var reasons := {}
	var sections := {"cards": 0, "packs": 0, "recipes": 0}
	for scene in ["Main", "Island"]:
		var population := {"cards": catalog.get("cards", []), "packs": catalog.get("packs", []), "recipes": []}
		for recipe in catalog.get("recipes", []):
			var generated := Recipes.build(model, str(recipe.guid), scene)
			check(not generated.is_empty(), scene + "/dynamic recipe factory")
			if not generated.is_empty(): population.recipes.append(generated)
		for section in ["cards", "packs", "recipes"]:
			for definition in population[section]:
				if definition.fields.get("displayName") == null:
					templates += 1
					var manager := Recipes.card_manager(model, scene)
					check(section == "cards" and str(definition.guid) == model.ref_guid(manager.get("recipeCardTemplate", {})), "only source-referenced unnamed recipe template is excluded from displayable title population")
					print("Non-displayable source recipe template: ", scene, "/", definition.guid, "; title absent, not substituted")
					continue
				count += 1
				sections[section] += 1
				var fields: Dictionary = definition.fields
				var appearance: Dictionary = assets.appearance(int(fields.get("category", 0)), section == "packs", fields, scene)
				var record: Dictionary = appearance.get("prefab", {}).get("title", {})
				var title := str(fields.get("displayName", ""))
				var label := Label3D.new()
				var binding: Dictionary = fonts.bind_label(label, record)
				var rect := Title.content_rect(record, Vector2.ONE)
				var source_pose := label.transform
				Title.fit(label, title, record, Vector2.ONE)
				var result: Dictionary = label.get_meta("source_layout_result", {})
				var id := "%s/%s/%s" % [scene, section, title]
				if label.get_meta("source_layout_status", "") != "source_ascii_autosize_native_raster":
					var reason := str(result.get("reason", binding.get("status", "unknown")))
					reasons[reason] = int(reasons.get(reason, 0)) + 1
					printerr("Unsupported source title: ", id, ": ", reason)
					label.free()
					continue
				supported += 1
				var baseline: Dictionary = label.get_meta("source_baseline_result", {})
				check(baseline.get("ok", false), id + " source Middle baseline supported")
				if baseline.get("ok", false):
					check(is_equal_approx(baseline.native_baseline_after, baseline.baseline), id + " native baseline corrected to source")
				check(label.transform == source_pose, id + " baseline correction leaves physical pose unchanged")
				check(binding.font != null and not binding.source_metrics.is_empty(), id + " exact private font bound")
				check(result.point_size >= float(record.font_size_min) and result.point_size <= float(record.font_size_max), id + " actual source min/max")
				check(label.font_size == roundi(float(binding.source_metrics.m_FaceInfo.m_PointSize)), id + " source raster sampling resolution")
				var multiplier := 1.0 if bool(record.is_orthographic) else 0.1
				check(is_equal_approx(label.pixel_size * label.font_size, result.point_size * multiplier), id + " physical source point size, no native width rescale")
				var measured := Layout.measure(title, record, binding.source_metrics, result.point_size)
				check(measured.ok and is_equal_approx(measured.width, result.width), id + " same private metric measurement")
				check(label.text == title and label.autowrap_mode == TextServer.AUTOWRAP_OFF, id + " exact title/no wrap")
				if result.overflow:
					minimum_overflows += 1
					check(is_equal_approx(result.point_size, float(record.font_size_min)), id + " overflow is retained at source minimum")
				# Unsupported input must remain explicit, not relabeled as source fit.
				Title.fit(label, "<b>Unsupported</b>", record, Vector2.ONE)
				check(label.get_meta("source_layout_status") == "unsupported_native_fallback" and not label.get_meta("source_layout_result").ok, id + " unsupported tags explicit fallback")
				label.free()
	check(count > 0 and sections.cards > 0 and sections.packs > 0, "nonempty actual card and pack populations")
	check(supported == count, "every current title uses source fit; unsupported counts=" + JSON.stringify(reasons))
	print("Source TMP title inventory: total=%d supported=%d cards=%d packs=%d recipes=%d unnamed_templates=%d minimum_overflows=%d unsupported=%s" % [count,supported,sections.cards,sections.packs,sections.recipes,templates,minimum_overflows,JSON.stringify(reasons)])
	if failures == 0: print("Imported source TMP title baselines: PASS")
	quit(0 if failures == 0 else 1)
