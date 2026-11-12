extends SceneTree
const Assets = preload("res://scripts/ui/visual_assets.gd")
func _init() -> void:
	var image := Image.create_from_data(2, 2, false, Image.FORMAT_RGBA8, PackedByteArray([0,0,0,255, 64,64,64,255, 128,128,128,255, 255,255,255,255]))
	var importer := {"alpha_usage": 2, "mipmaps": true}
	var mapped := Assets.apply_texture_alpha(image, importer)
	assert(mapped.has_mipmaps())
	assert(mapped.get_pixel(0, 0).a == 0.0)
	assert(is_equal_approx(mapped.get_pixel(1, 0).a, 64.0 / 255.0))
	assert(image.get_pixel(0, 0).a == 1.0) # Input pixels remain unchanged.
	var assets = Assets.new()
	var cached := assets._imported_texture(ImageTexture.create_from_image(image), importer)
	assert(cached.get_image().get_data() == mapped.get_data())
	assert(Assets.apply_texture_alpha(image, {"alpha_usage": 1}) == image)
	assert(assets._imported_texture(cached, {"alpha_usage": 1}) == cached)
	var opaque := Assets.apply_texture_alpha(mapped, {"alpha_usage": 0})
	assert(opaque.get_pixel(0, 0).a == 1.0)
	var color := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	color.fill(Color.RED)
	assert(Assets.apply_texture_alpha(color, importer) == null)
	assert(Assets.apply_texture_alpha(image, {"alpha_usage": 3}) == null)
	assert(Assets.apply_texture_alpha(image, {}) == image) # Older manifests retain legacy behavior.
	DirAccess.make_dir_recursive_absolute("user://alpha_test")
	assert(image.save_png("user://alpha_test/synthetic.png") == OK)
	assets.root_path = "user://alpha_test/"
	assets.manifest = {"assets": {"synthetic": {"path": "synthetic.png", "kind": "png", "texture_importer": importer}}}
	var raw: Texture2D = assets.texture("synthetic")
	assert(raw.get_image().get_data() == cached.get_image().get_data())
	assert(assets.texture("synthetic") == raw)
	DirAccess.remove_absolute("user://alpha_test/synthetic.png")
	DirAccess.remove_absolute("user://alpha_test")
	print("Texture alpha importer, cached and raw paths: PASS")
	quit()
