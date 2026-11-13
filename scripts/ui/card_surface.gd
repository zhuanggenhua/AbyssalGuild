extends RefCounted
## Independent binding/math adapter; no source shader or media is embedded.
const SHADER = preload("res://scripts/ui/shaders/card_surface.gdshader")

static func create(assets, appearance: Dictionary) -> ShaderMaterial:
	var source: Dictionary = appearance.get("material", {})
	if source.get("shader_source_path", "") != "Shaders/Card.shadergraph":
		return null
	var textures: Dictionary = source.get("textures", {})
	var base_guid: String = str(textures.get("_BaseTex", {}).get("m_Texture", {}).get("guid", ""))
	var art_guid: String = str(appearance.get("art_guid", ""))
	if art_guid.is_empty():
		art_guid = str(textures.get("_OverlayTex", {}).get("m_Texture", {}).get("guid", ""))
	var base: Texture2D = assets.texture(base_guid)
	var art: Texture2D = assets.texture(art_guid)
	if base == null or art == null:
		return null
	var colors: Dictionary = source.get("colors", {})
	var floats: Dictionary = source.get("floats", {})
	var scale: float = float(floats.get("_OverlayScale", 1.0))
	if not is_finite(scale) or scale <= 0.0:
		return null
	var offset: Dictionary = colors.get("_OverlayOffset", {})
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/ui/source_lit_material.gd").card_shader(assets, source, SHADER)
	material.resource_name = str(source.get("name", "SourceCardSurface"))
	material.set_shader_parameter("base_texture", base)
	material.set_shader_parameter("overlay_texture", art)
	material.set_shader_parameter("overlay_tint", assets.source_color(colors.get("_OverlayTint", {})))
	material.set_shader_parameter("overlay_offset", Vector2(float(offset.get("r", 0.0)), float(offset.get("g", 0.0))))
	material.set_shader_parameter("overlay_scale", scale)
	material.set_shader_parameter("flash_amount", clampf(float(floats.get("_FlashAmount", 0.0)), 0.0, 1.0))
	return material

static func overlay_sample_uv(imported_uv: Vector2, offset: Vector2, scale: float) -> Vector2:
	# CPU reference used by numeric tests, including non-symmetric offsets.
	var source_uv := Vector2(imported_uv.x, 1.0 - imported_uv.y)
	var art_uv := (source_uv - offset) / scale
	return Vector2(art_uv.x, 1.0 - art_uv.y)

static func compose_sample(base: Color, overlay: Color, tint: Color, coverage: float, flash: float) -> Color:
	# Coverage is already filtered by the shader's screen-space rectangle mask.
	var art := overlay * tint * coverage
	var result := base.lerp(art, art.a).lerp(Color.WHITE, flash) * (1.0 + flash * 0.5)
	result.a = 1.0 # Source target is opaque; texture alpha masks only the artwork.
	return result
