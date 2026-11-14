extends RefCounted
## Optional locally generated data, never a ResourceLoader/script input.
const ROOT := "res://assets/imported/alpha_cache/"
const INDEX := ROOT + "index.json"
const INDEX_SETTING := "private_alpha_cache/index_sha256"
const VERSION := "4.7.2-stable (official)"
const ENGINE_HASH := "ed1daf0bf001b61586d9930840f2f1394092c079"
const ALGORITHM := "rgba8-gray-alpha-v1"
const MAX_INDEX := 1048576
const MAX_BYTES := 33554432
const MAX_DIMENSION := 2048
var _loaded := false
var _entries: Dictionary = {}

static func engine_matches(version: Dictionary) -> bool:
	return version.get("string") == VERSION and version.get("hash") == ENGINE_HASH

static func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

static func hex_id(value: Variant, length: int) -> bool:
	if not value is String or value.length() != length: return false
	for character in value:
		if not character in "0123456789abcdef": return false
	return true

static func read_bounded(path: String, limit: int) -> PackedByteArray:
	if not FileAccess.file_exists(path): return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return PackedByteArray()
	var length := file.get_length()
	if length <= 0 or length > limit: return PackedByteArray()
	return file.get_buffer(length)

static func byte_count(width: int, height: int, mipmaps: bool) -> int:
	if width < 1 or height < 1 or width > MAX_DIMENSION or height > MAX_DIMENSION: return 0
	var total := width * height * 4
	while mipmaps and (width > 1 or height > 1):
		width = maxi(1, width / 2)
		height = maxi(1, height / 2)
		total += width * height * 4
	return total if total <= MAX_BYTES else 0

static func parse_index(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_INDEX: return {}
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK: return {}
	var index = parser.data
	if not index is Dictionary or index.get("schema") != 1 or index.get("engine") != VERSION or index.get("engine_hash") != ENGINE_HASH or index.get("algorithm") != ALGORITHM: return {}
	var entries = index.get("entries")
	if not entries is Dictionary or entries.size() > 512: return {}
	return entries

static func trusted_index(bytes: PackedByteArray, expected_hash: Variant) -> Dictionary:
	if not hex_id(expected_hash, 64) or bytes.is_empty() or bytes.size() > MAX_INDEX: return {}
	if digest(bytes) != expected_hash: return {}
	return parse_index(bytes)

func _read_index() -> void:
	_loaded = true
	var expected = ProjectSettings.get_setting(INDEX_SETTING, "")
	if not hex_id(expected, 64): return
	_entries = trusted_index(read_bounded(INDEX, MAX_INDEX), expected)

func image(guid: String, asset: Dictionary, remap: ConfigFile) -> Image:
	if not engine_matches(Engine.get_version_info()) or not hex_id(guid, 32): return null
	if not _loaded: _read_index()
	var entry = _entries.get(guid)
	if not entry is Dictionary: return null
	if entry.get("source_sha256") != asset.get("sha256") or not hex_id(entry.get("source_sha256"), 64): return null
	if not asset.get("texture_importer") is Dictionary or entry.get("importer") != asset.get("texture_importer"): return null
	if asset.texture_importer.get("alpha_usage") != 2: return null
	# No caller-selected filenames: the sole payload path is canonical GUID.bin.
	if entry.get("path") != guid + ".bin": return null
	if entry.get("mipmaps") != bool(asset.texture_importer.get("mipmaps", false)): return null
	if decoded_size(entry) == 0: return null
	var resource_path = remap.get_value("remap", "path", "")
	if not resource_path is String or not resource_path.begins_with("res://.godot/imported/") or resource_path.contains("..") or resource_path.contains("\\"): return null
	if not hex_id(entry.get("ctex_sha256"), 64) or not hex_id(entry.get("payload_sha256"), 64) or not hex_id(entry.get("rgba_sha256"), 64): return null
	var imported := read_bounded(resource_path, MAX_BYTES)
	if imported.is_empty() or digest(imported) != entry.ctex_sha256: return null
	var compressed := read_bounded(ROOT + guid + ".bin", MAX_BYTES)
	if compressed.is_empty() or digest(compressed) != entry.payload_sha256: return null
	return decode_payload(entry, compressed)

static func decoded_size(entry: Dictionary) -> int:
	var width = entry.get("width")
	var height = entry.get("height")
	if not (width is int or width is float) or not (height is int or height is float): return 0
	if not is_finite(float(width)) or not is_finite(float(height)): return 0
	if width < 1 or height < 1 or width > MAX_DIMENSION or height > MAX_DIMENSION: return 0
	if width != int(width) or height != int(height): return 0
	if not entry.get("mipmaps") is bool: return 0
	var expected := byte_count(int(width), int(height), entry.mipmaps)
	return expected if expected > 0 and entry.get("decoded_size") == expected else 0

static func decode_payload(entry: Dictionary, compressed: PackedByteArray) -> Image:
	var expected := decoded_size(entry)
	if expected == 0 or compressed.is_empty() or compressed.size() > MAX_BYTES: return null
	if not hex_id(entry.get("payload_sha256"), 64) or not hex_id(entry.get("rgba_sha256"), 64): return null
	if digest(compressed) != entry.payload_sha256: return null
	# Explicit fixed-size decompression: no Variant/object/resource deserialization.
	var decoded := compressed.decompress(expected, FileAccess.COMPRESSION_DEFLATE)
	if decoded.size() != expected or digest(decoded) != entry.rgba_sha256: return null
	return Image.create_from_data(int(entry.width), int(entry.height), entry.mipmaps, Image.FORMAT_RGBA8, decoded)
