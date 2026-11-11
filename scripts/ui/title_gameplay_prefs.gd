extends RefCounted
## Pure Title scene reference resolver; no preferences or campaign writes.
static func resolve(source: Dictionary) -> Dictionary:
	var fallback := {"source_backed": false, "minimum": 60.0, "maximum": 180.0, "initial": 120.0, "whole_numbers": true, "friendly": false, "warning": "Title gameplay controls could not be resolved; fallback controls use 60–180 seconds (default 120), Friendly Mode OFF."}
	for scene in source.get("scenes", []):
		if str(scene.get("name", "")) != "Title": continue
		var documents: Array = scene.get("documents", [])
		for document in documents:
			if document.get("script_class", "") != "GameplayPrefsUI": continue
			var fields: Dictionary = document.get("fields", {})
			var slider := _fields(documents, fields.get("durationSlider", {}))
			var toggle := _fields(documents, fields.get("isFriendlyToggle", {}))
			for key in ["m_MinValue", "m_MaxValue", "m_Value", "m_WholeNumbers"]:
				if not slider.has(key) or not (slider[key] is float or slider[key] is int or slider[key] is bool): return fallback
			if not toggle.has("m_IsOn"): return fallback
			var minimum := float(slider.m_MinValue)
			var maximum := float(slider.m_MaxValue)
			var initial := float(slider.m_Value)
			if not is_finite(minimum) or not is_finite(maximum) or not is_finite(initial) or minimum <= 0.0 or maximum < minimum: return fallback
			var whole := bool(slider.m_WholeNumbers)
			if whole:
				minimum = roundf(minimum)
				maximum = roundf(maximum)
				initial = roundf(initial)
			return {"source_backed": true, "minimum": minimum, "maximum": maximum, "initial": clampf(initial, minimum, maximum), "whole_numbers": whole, "friendly": bool(toggle.m_IsOn), "warning": ""}
	return fallback

static func _fields(documents: Array, reference: Dictionary) -> Dictionary:
	# Local file IDs are only meaningful within the selected scene.
	if str(reference.get("fileID", "0")) == "0" or not str(reference.get("guid", "")).is_empty(): return {}
	for document in documents:
		if str(document.get("file_id", "")) == str(reference.fileID): return document.get("fields", {})
	return {}

static func duration_text(value: float) -> String:
	return "Day Duration: %d sec" % int(value)

static func friendly_text(enabled: bool) -> String:
	return "Friendly Mode: ON\n(No enemies will appear)" if enabled else "Friendly Mode: OFF\n(Enemies may appear)"
