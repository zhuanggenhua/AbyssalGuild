extends RefCounted
## Pointer distance is measured on the board, not in screen pixels.
static func source_settings(catalog, scene_name: String) -> Dictionary:
	var result: Dictionary = catalog.settings("CardSettings")
	for scene in catalog.data.get("scenes", []):
		if str(scene.get("name", "")) != scene_name: continue
		for document in scene.get("documents", []):
			if document.get("script_class", "") != "CardManager": continue
			var guid: String = catalog.ref_guid(document.get("fields", {}).get("cardSettings", {}))
			if not guid.is_empty() and not catalog.fields(guid).is_empty(): result = catalog.fields(guid)
		break
	return result

static func is_click(start: Vector3, destination: Vector2, settings: Dictionary) -> bool:
	# Source flattens only the released pose. A high stack member retains its
	# original Y component in the distance. Equality is deliberately not a click.
	var threshold: float = float(settings.get("clickThreshold", 0.02))
	if not start.is_finite() or not destination.is_finite() or not is_finite(threshold): return false
	return Vector3(destination.x, 0, destination.y).distance_to(start) < threshold
