extends RefCounted
## Immutable-by-construction presentation descriptions; no nodes, time or RNG.
## Model health/death already resolved: never defer gameplay using these durations.

static func attack_sound(combat_type: int) -> String:
	return "Attack" + _style(combat_type)

static func _style(combat_type: int) -> String:
	match combat_type:
		2: return "Ranged"
		3: return "Magic"
	return "Melee"

## Returns the imported fields of the scene-referenced HitUI prefab, or {}.
## Missing private artwork never changes semantic text/audio/flash behavior.
static func hit_ui_fields(data: Dictionary, scene_name: String) -> Dictionary:
	var guid: String = ""
	for scene in data.get("scenes", []):
		if scene.get("name", "") != scene_name:
			continue
		for document in scene.get("documents", []):
			if document.get("script_class", "") == "CombatManager":
				guid = str(document.get("fields", {}).get("hitUIPrefab", {}).get("guid", ""))
	if guid.is_empty():
		return {}
	for prefab in data.get("referenced_prefabs", []):
		if str(prefab.get("guid", "")) != guid:
			continue
		for document in prefab.get("documents", []):
			if document.get("script_class", "") == "HitUI":
				return document.get("fields", {}).duplicate(true)
	return {}

static func describe(combat_type: int, result: Dictionary, fields: Dictionary = {}) -> Dictionary:
	var kind: String = str(result.get("type", ""))
	if kind not in ["miss", "normal", "critical"]:
		return {} # Unknown combat results must not fabricate successful-hit feedback.
	var hit: bool = kind != "miss"
	var edge: int = int(result.get("advantage", 0))
	var sounds: Array = ["Hit" + _style(combat_type)] if hit else ["Miss"]
	if kind == "critical":
		sounds.append("Critical") # Source plays type hit AND critical, in this order.
	var effectiveness_key: String = "advantageSprite" if edge == 1 else ("disadvantageSprite" if edge == -1 else "")
	var sprite_key: String = {"miss": "missSprite", "normal": "normalSprite", "critical": "criticalSprite"}[kind]
	return {
		"sounds": sounds,
		"damage_text": str(int(result.get("damage", 0))) if hit else "",
		"hit_sprite": fields.get(sprite_key, {}).duplicate(true),
		"effectiveness_visible": not effectiveness_key.is_empty(),
		"effectiveness_sprite": fields.get(effectiveness_key, {}).duplicate(true) if not effectiveness_key.is_empty() else {},
		"popup": {"defender_local_offset": Vector3(0.3, 0.1, 0.4), "duration": 1.0, "punch_scale": Vector3(0.15, 0.15, 0), "unscaled": true},
		"flash": {"enabled": hit, "peak": 1.0, "leg_duration": 0.1, "delay": 0.05, "loops": 2, "yoyo": true, "unscaled": true, "replace_previous_hurt": true},
		"hurt_rotation": {"enabled": hit, "punch_degrees": Vector3(0, 15, 0), "duration": 0.25, "vibrato": 25, "unscaled": true},
		"camera_shake": {"enabled": hit, "duration": 0.3, "strength": 0.1, "unscaled": true}
	}
