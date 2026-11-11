extends SceneTree
const Feedback = preload("res://scripts/model/impact_feedback.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
var checks: int = 0
var failures: int = 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void:
	var fields := {"missSprite": {"guid": "miss"}, "normalSprite": {"guid": "normal"}, "criticalSprite": {"guid": "crit"}, "advantageSprite": {"guid": "up"}, "disadvantageSprite": {"guid": "down"}}
	for type in [0, 1, 2, 3, 999]:
		var style: String = "Ranged" if type == 2 else ("Magic" if type == 3 else "Melee")
		check(Feedback.attack_sound(type) == "Attack" + style, "attack style defaults to melee")
		var hit: Dictionary = Feedback.describe(type, {"type": "normal", "damage": 3, "advantage": 1}, fields)
		check(hit.sounds == ["Hit" + style] and hit.damage_text == "3", "normal damage/audio")
		check(hit.hit_sprite.guid == "normal" and hit.effectiveness_sprite.guid == "up" and hit.effectiveness_visible, "normal/advantage icons")
		var critical: Dictionary = Feedback.describe(type, {"type": "critical", "damage": 8, "advantage": -1}, fields)
		check(critical.sounds == ["Hit" + style, "Critical"], "critical adds rather than replaces impact sound")
		check(critical.hit_sprite.guid == "crit" and critical.effectiveness_sprite.guid == "down", "critical/disadvantage icons")
		var miss: Dictionary = Feedback.describe(type, {"type": "miss", "damage": 0, "advantage": 0}, fields)
		check(miss.sounds == ["Miss"] and miss.damage_text.is_empty(), "miss hides number and plays only miss")
		check(not miss.flash.enabled and not miss.hurt_rotation.enabled and not miss.camera_shake.enabled, "miss never shakes or flashes")
		check(not miss.effectiveness_visible and miss.effectiveness_sprite.is_empty(), "neutral effectiveness hidden")
	var result := {"type": "critical", "damage": 0, "advantage": 0}
	var copy: Dictionary = result.duplicate(true)
	var descriptor: Dictionary = Feedback.describe(1, result, fields)
	check(descriptor.damage_text == "0" and descriptor.flash.enabled, "zero-damage hit still has hit effects")
	check(descriptor.flash.peak == 1.0 and descriptor.flash.leg_duration == 0.1 and descriptor.flash.delay == 0.05 and descriptor.flash.loops == 2 and descriptor.flash.yoyo, "source flash timing metadata")
	check(descriptor.hurt_rotation.punch_degrees == Vector3(0, 15, 0) and descriptor.hurt_rotation.duration == 0.25 and descriptor.hurt_rotation.vibrato == 25, "source hurt punch metadata")
	check(descriptor.popup.defender_local_offset == Vector3(0.3, 0.1, 0.4) and descriptor.popup.duration == 1.0 and descriptor.popup.punch_scale == Vector3(0.15, 0.15, 0), "source popup placement and lifetime")
	check(descriptor.camera_shake.duration == 0.3 and descriptor.camera_shake.strength == 0.1, "source camera defaults")
	descriptor.hit_sprite.guid = "changed"
	check(fields.criticalSprite.guid == "crit" and result == copy, "descriptor does not mutate source fields/result")
	check(Feedback.describe(1, {"type": "unknown"}).is_empty(), "unknown result rejected")
	check(Feedback.describe(1, result).hit_sprite.is_empty(), "missing private icons not replaced with invented refs")
	var data := {"scenes": [{"name": "Test", "documents": [{"script_class": "CombatManager", "fields": {"hitUIPrefab": {"guid": "ui"}}}]}], "referenced_prefabs": [{"guid": "ui", "documents": [{"script_class": "HitUI", "fields": fields}]}]}
	check(Feedback.hit_ui_fields(data, "Test") == fields and Feedback.hit_ui_fields(data, "Other").is_empty(), "scene reference resolves private hit UI fields")
	var c = Catalog.new()
	c.configure({"cards": [{"guid": "p", "fields": {"category": 2, "faction": 1}}, {"guid": "m", "fields": {"category": 9, "faction": 2}}]})
	var s = Session.new()
	s.configure(c, 32)
	var p: int = s.spawn_card("p")
	var m: int = s.spawn_card("m")
	s.combat.start_combat([p], [m])
	var rng_before: int = s.rng.state
	var combat_before: Dictionary = s.combat.save_state()
	var health: int = s.cards[m].health
	for i in 100: Feedback.describe(3, result, fields)
	check(s.rng.state == rng_before and s.combat.save_state() == combat_before and s.cards[m].health == health, "feedback consumes no gameplay RNG/time/health state")
	print("Impact feedback checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
