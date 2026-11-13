extends SceneTree
const Assets = preload("res://scripts/ui/visual_assets.gd")
const Fonts = preload("res://scripts/ui/source_font_registry.gd")
const Card = preload("res://scripts/ui/card_view.gd")
const Trade = preload("res://scripts/ui/trade_source_binding.gd")
const Combat = preload("res://scripts/ui/combat_sprite_binding.gd")
var count := 0
func _init() -> void:
	call_deferred("run")
func verify(label: Label3D, record: Dictionary) -> void:
	var guid := Fonts.font_guid(record)
	assert(not guid.is_empty(), "Source text GUID required")
	var binding: Dictionary = Fonts.shared().resolve(guid)
	assert(binding.font != null)
	assert(label.font == binding.font)
	assert(label.get_meta("source_font_status") == "source_font_bound_native_layout")
	assert(label.get_meta("source_font_guid") == guid)
	count += 1
func run() -> void:
	var assets = Assets.new()
	assert(assets.load_manifest() == OK)
	assert(Fonts.shared().manifest.get("fonts", {}).size() > 0)
	for category in [1, 2, 3]:
		var appearance: Dictionary = assets.appearance(category, false, {}, "Main")
		var view = Card.new()
		view.configure(category, "Source font binding", category, false, assets, {}, "Main")
		verify(view.caption, appearance.prefab.title)
		for role in ["price", "nutrition", "health"]:
			if view.has_node(role.capitalize()):
				verify(view.get_node(role.capitalize()), appearance.prefab.labels[role])
		view.free()
	for scene in ["Main", "Island"]:
		var config: Dictionary = assets.scene_configuration(scene)
		for trade in config.get("trading", {}).values():
			for record in trade.get("labels", {}).values():
				var label := Trade._label(record, assets)
				assert(label != null)
				verify(label, record)
				assert(not label.get_meta("source_font_missing"))
				label.free()
		var record: Dictionary = config.combat.hit_ui
		var popup := Combat.hit_popup(assets, record, "normal", "42", 0)
		assert(popup != null)
		verify(popup.get_node("Damage"), record.roles.damage)
		popup.free()
	assert(count >= 5)
	print("Imported source 3D font components: PASS (", count, " exact source references)")
	quit()
