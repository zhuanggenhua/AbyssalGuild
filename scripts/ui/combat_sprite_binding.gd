extends RefCounted
## Optional private PNG bindings. No clocks, model access, generated art or RNG.
const SourceCamera = preload("res://scripts/ui/source_camera.gd")

static func _texture(assets, reference: Dictionary) -> Texture2D:
	var guid: String = str(reference.get("guid", ""))
	var record: Dictionary = assets.manifest.get("assets", {}).get(guid, {}).get("sprite", {})
	if record.get("mode", "") != "single_full_image" or int(record.get("filter_mode", -1)) not in [0, 1]:
		return null
	var texture: Texture2D = assets.texture(guid)
	var size: Dictionary = record.get("pixel_size", {})
	if texture == null or texture.get_width() != int(size.get("x", 0)) or texture.get_height() != int(size.get("y", 0)):
		return null
	return texture

static func _sprite(assets, texture: Texture2D, color: Dictionary) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.modulate = assets.source_color(color)
	sprite.shaded = false
	sprite.double_sided = true
	sprite.no_depth_test = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return sprite

static func projectile(assets, record: Dictionary) -> Sprite3D:
	var pose: Dictionary = SourceCamera.reflected_pose(record.get("transform_chain", []))
	var materials: Array = record.get("materials", [])
	# Only the audited default SpriteRenderer material/simple mode is adapted.
	if pose.is_empty() or int(record.get("draw_mode", -1)) != 0 or materials.size() != 1:
		return null
	if str(materials[0].get("fileID", "")) != "10754" or str(materials[0].get("guid", "")) != "0000000000000000f000000000000000":
		return null
	var reference: Dictionary = record.get("sprite", {})
	var texture: Texture2D = _texture(assets, reference)
	var importer: Dictionary = assets.manifest.get("assets", {}).get(str(reference.get("guid", "")), {}).get("sprite", {})
	var ppu: float = float(importer.get("pixels_per_unit", 0.0))
	var pivot: Dictionary = importer.get("pivot", {})
	var duration: float = float(record.get("duration", 0.0))
	if texture == null or not is_finite(ppu) or ppu <= 0.0 or pivot.size() != 2 or not is_finite(duration) or duration <= 0.0:
		return null
	if int(importer.get("filter_mode", -1)) not in [0, 1]:
		return null
	var sprite: Sprite3D = _sprite(assets, texture, record.get("color", {}))
	sprite.name = "SourceProjectile"
	# Fire supplies world position/rotation. Preserve the source instance scale.
	sprite.scale = pose.transform.basis.get_scale()
	sprite.pixel_size = 1.0 / ppu
	sprite.offset = Vector2((0.5 - float(pivot.x)) * texture.get_width(), (0.5 - float(pivot.y)) * texture.get_height())
	sprite.flip_h = bool(record.get("flip_x", false))
	sprite.flip_v = bool(record.get("flip_y", false))
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if int(importer.filter_mode) == 0 else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.set_meta("source_duration", duration)
	sprite.set_meta("source_prefab_guid", str(record.get("prefab_guid", "")))
	sprite.set_meta("source_world_size", Vector2(texture.get_width(), texture.get_height()) / ppu)
	return sprite

static func _ui_sprite(assets, role: Dictionary, reference: Dictionary) -> Sprite3D:
	if int(role.get("image_type", -1)) != 0 or bool(role.get("preserve_aspect", true)):
		return null
	if str(role.get("material", {}).get("fileID", "")) != "0":
		return null
	var texture: Texture2D = _texture(assets, reference)
	var pose: Dictionary = SourceCamera.reflected_pose([role.get("pose", {})])
	var size: Dictionary = role.get("size", {})
	var pivot: Dictionary = role.get("pivot", {})
	if texture == null or pose.is_empty() or float(size.get("x", 0.0)) <= 0 or float(size.get("y", 0.0)) <= 0 or pivot.size() != 2:
		return null
	var sprite: Sprite3D = _sprite(assets, texture, role.get("color", {}))
	var importer: Dictionary = assets.manifest.assets[str(reference.guid)].sprite
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if int(importer.filter_mode) == 0 else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.pixel_size = 1.0
	sprite.transform = pose.transform
	sprite.scale *= Vector3(float(size.x) / texture.get_width(), float(size.y) / texture.get_height(), 1)
	sprite.offset = Vector2((0.5 - float(pivot.x)) * texture.get_width(), (0.5 - float(pivot.y)) * texture.get_height())
	sprite.set_meta("source_rect_size", Vector2(float(size.x), float(size.y)))
	return sprite

static func hit_popup(assets, record: Dictionary, kind: String, damage_text: String, advantage: int) -> Node3D:
	if kind not in ["miss", "normal", "critical"] or record.is_empty():
		return null
	var roles: Dictionary = record.get("roles", {})
	var sprites: Dictionary = record.get("sprites", {})
	var hit: Sprite3D = _ui_sprite(assets, roles.get("hit", {}), sprites.get(kind, {}))
	if hit == null:
		return null
	var effectiveness: Sprite3D
	if advantage in [-1, 1]:
		effectiveness = _ui_sprite(assets, roles.get("effectiveness", {}), sprites.get("advantage" if advantage == 1 else "disadvantage", {}))
		if effectiveness == null:
			hit.free()
			return null
	var damage: Dictionary = roles.get("damage", {})
	var damage_pose: Dictionary = SourceCamera.reflected_pose([damage.get("pose", {})])
	var font_size: float = float(damage.get("font_size", 0.0))
	var scale: Dictionary = record.get("root_scale", {})
	if damage_pose.is_empty() or not is_finite(font_size) or font_size <= 0 or scale.size() != 3:
		hit.free()
		if effectiveness != null: effectiveness.free()
		return null
	var popup := Node3D.new()
	popup.name = "SourceHitPopup"
	# CombatManager instantiates at X=90 degrees; reflect Unity world Z.
	popup.rotation_degrees.x = -90
	popup.scale = Vector3(float(scale.x), float(scale.y), float(scale.z))
	hit.name = "Hit"
	popup.add_child(hit)
	if effectiveness != null:
		effectiveness.name = "Effectiveness"
		effectiveness.render_priority = 1
		popup.add_child(effectiveness)
	var label := Label3D.new()
	label.name = "Damage"
	label.text = "" if kind == "miss" else damage_text
	label.transform = damage_pose.transform
	var size: Dictionary = damage.get("size", {})
	var pivot: Dictionary = damage.get("pivot", {})
	label.position += label.basis * Vector3((0.5 - float(pivot.get("x", 0.5))) * float(size.get("x", 0.0)), (0.5 - float(pivot.get("y", 0.5))) * float(size.get("y", 0.0)), 0)
	label.modulate = assets.source_color(damage.get("color", {}))
	preload("res://scripts/ui/source_font_registry.gd").shared().bind_label(label, damage)
	label.font_size = 32
	label.pixel_size = font_size / (label.font if label.font != null else ThemeDB.fallback_font).get_height(label.font_size)
	label.outline_size = 0
	label.no_depth_test = false
	label.render_priority = 2
	label.set_meta("source_font_size", font_size)
	label.set_meta("native_font_adapter", true)
	popup.add_child(label)
	popup.set_meta("source_prefab_guid", str(record.get("prefab_guid", "")))
	return popup
