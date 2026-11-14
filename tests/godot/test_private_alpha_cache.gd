extends SceneTree
const Cache = preload("res://scripts/ui/private_alpha_cache.gd")
const Assets = preload("res://scripts/ui/visual_assets.gd")
func _init() -> void:
	assert(Cache.engine_matches(Engine.get_version_info()))
	assert(not Cache.engine_matches({"string":Cache.VERSION,"hash":"0".repeat(40)}))
	assert(not Cache.engine_matches({"string":Cache.VERSION}))
	assert(Cache.byte_count(2, 2, true) == 20)
	assert(Cache.byte_count(1198, 1198, true) == 7651512)
	assert(Cache.byte_count(0, 2, true) == 0)
	assert(Cache.byte_count(2049, 2, false) == 0)
	assert(Cache.hex_id("0123456789abcdef0123456789abcdef", 32))
	for bad in [null, 1, "../escape", "ABCD", "g".repeat(32)]: assert(not Cache.hex_id(bad, 32))
	for bad in ["", "{", "null", "[]", '{"schema":1,"entries":null}', '{"schema":1,"entries":{"x":"res://evil.gd"}}']:
		assert(Cache.parse_index(bad.to_utf8_buffer()).is_empty())
	var index := {"schema": 1, "engine": Cache.VERSION, "engine_hash": Cache.ENGINE_HASH, "algorithm": Cache.ALGORITHM, "entries": {"x": "pure data"}}
	assert(Cache.parse_index(JSON.stringify(index).to_utf8_buffer()) == index.entries)
	var stale := index.duplicate(true); stale.erase("engine_hash"); assert(Cache.parse_index(JSON.stringify(stale).to_utf8_buffer()).is_empty())
	stale.engine_hash = "0".repeat(40); assert(Cache.parse_index(JSON.stringify(stale).to_utf8_buffer()).is_empty())
	var trusted_bytes := JSON.stringify(index).to_utf8_buffer()
	assert(Cache.trusted_index(trusted_bytes, Cache.digest(trusted_bytes)) == index.entries)
	assert(Cache.trusted_index(trusted_bytes, "").is_empty())
	var forged := index.duplicate(true); forged.entries = {"changed": {"payload_sha256":"a".repeat(64),"rgba_sha256":"b".repeat(64)}}
	assert(Cache.trusted_index(JSON.stringify(forged).to_utf8_buffer(), Cache.digest(trusted_bytes)).is_empty())
	index.engine = "wrong"; assert(Cache.parse_index(JSON.stringify(index).to_utf8_buffer()).is_empty())
	var cache := Cache.new(); cache._loaded = true
	var guid := "f".repeat(32)
	var importer := {"alpha_usage": 2, "mipmaps": true}
	var asset := {"sha256": "a".repeat(64), "texture_importer": importer}
	var valid := {"source_sha256": asset.sha256, "importer": importer, "path": guid + ".bin", "width": 2, "height": 2, "mipmaps": true, "decoded_size": 20}
	var remap := ConfigFile.new()
	for bad in [null, [], "res://evil.gd", 12]:
		cache._entries = {guid: bad}; assert(cache.image(guid, asset, remap) == null)
	for field in ["path", "width", "height", "mipmaps", "decoded_size", "source_sha256", "importer"]:
		var bad := valid.duplicate(true); bad[field] = null
		cache._entries = {guid: bad}; assert(cache.image(guid, asset, remap) == null)
	for path in ["../evil.bin", "/tmp/evil", "res://evil.gd", guid + ".res"]:
		var bad := valid.duplicate(true); bad.path = path
		cache._entries = {guid: bad}; assert(cache.image(guid, asset, remap) == null)
	for width in [-1, 0, 0.5, INF, NAN, 1.0e308, 2147483647]:
		var bad := valid.duplicate(true); bad.width = width
		cache._entries = {guid: bad}; assert(cache.image(guid, asset, remap) == null)
	# Pure data test: public/source-free checkouts need no asset directories.
	var raw := PackedByteArray([17,17,17,17,32,32,32,32,64,64,64,64,255,255,255,255])
	var compressed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var bound := {"width":2,"height":2,"mipmaps":false,"decoded_size":raw.size(),"payload_sha256":Cache.digest(compressed),"rgba_sha256":Cache.digest(raw)}
	var decoded := Cache.decode_payload(bound, compressed); assert(decoded != null and decoded.get_data() == raw)
	var corrupted := compressed.duplicate(); corrupted[0] ^= 255
	assert(Cache.decode_payload(bound, corrupted) == null)
	assert(Cache.decode_payload(bound, PackedByteArray()) == null)
	var wrong_size := bound.duplicate(); wrong_size.decoded_size += 1
	assert(Cache.decode_payload(wrong_size, compressed) == null)
	var wrong_raw := bound.duplicate(); wrong_raw.rgba_sha256 = "0".repeat(64)
	assert(Cache.decode_payload(wrong_raw, compressed) == null)
	var image := Image.create_from_data(1,1,false,Image.FORMAT_RGBA8,PackedByteArray([17,17,17,250]))
	assert(Assets.apply_texture_alpha(image, importer).get_data()[3] == 17)
	image.set_pixel(0,0,Color.RED); assert(Assets.apply_texture_alpha(image, importer) == null)
	print("Private alpha cache data-only bounds and rejection: PASS")
	quit()
