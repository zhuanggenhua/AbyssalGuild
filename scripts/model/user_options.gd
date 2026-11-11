extends RefCounted
## Native preference data only. Never touches AudioServer/DisplayServer/Engine.
const FORMAT = "abyssal-guild-user-options"
const VERSION = 1
const MAX_BYTES = 16384
const MAX_DIMENSION = 16384 # Native safety bound, not a Unity source limit.
const FPS_CAPS = [-1, 30, 60, 120, 144, 240]
const MODES = ["borderless", "windowed"]
var resolutions: Array = []
var values: Dictionary = {"sfx_db": 0.0, "bgm_db": 0.0, "resolution": [], "fullscreen": "borderless", "vsync": 1, "fps_cap": -1, "shadow_preset": 3}

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floor(float(value)) and absf(float(value)) <= 9007199254740991.0

static func _resolution(value: Variant) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for axis in value:
		if not _integer(axis) or axis < 1 or axis > MAX_DIMENSION:
			return false
	return true

## Caller supplies actual supported hardware modes. No invented fallback list.
## Configure once at startup, before load; this initializes source defaults.
func configure(hardware_modes: Array = []) -> Dictionary:
	var accepted: Array = []
	for mode in hardware_modes:
		if not _resolution(mode):
			return _fail("Invalid hardware resolution")
		var pair := [int(mode[0]), int(mode[1])]
		if not accepted.has(pair):
			accepted.append(pair)
	accepted.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	resolutions = accepted
	reset_defaults()
	return {"ok": true, "resolution_available": not resolutions.is_empty()}

func defaults() -> Dictionary:
	var chosen: Array = []
	var score: int = 9223372036854775807
	for mode in resolutions:
		var candidate: int = (mode[0] - 1920) * (mode[0] - 1920) + (mode[1] - 1080) * (mode[1] - 1080)
		if candidate < score:
			score = candidate
			chosen = mode.duplicate()
	return {"sfx_db": 0.0, "bgm_db": 0.0, "resolution": chosen, "fullscreen": "borderless", "vsync": 1, "fps_cap": -1, "shadow_preset": 3}

## Reset only this helper; never erase campaign slots or other preferences.
func reset_defaults() -> void:
	values = defaults()

static func slider_to_db(value: float) -> float:
	return -80.0 if value <= 0.0001 else 20.0 * log(value) / log(10.0)

func set_volume(channel: String, linear: Variant) -> Dictionary:
	if not channel in ["sfx", "bgm"] or not _number(linear) or linear < 0 or linear > 1:
		return _fail("Volume must be a finite slider value from 0 to 1")
	values[channel + "_db"] = slider_to_db(float(linear))
	return {"ok": true}

func volume_slider(channel: String) -> float:
	if not channel in ["sfx", "bgm"]:
		return -1.0
	# Source returns 0.0001 at its -80 dB floor, not exactly zero.
	return clampf(pow(10.0, float(values[channel + "_db"]) / 20.0), 0.0, 1.0)

func cycle(key: String) -> Dictionary:
	var choices: Array
	match key:
		"fullscreen": choices = MODES
		"vsync": choices = [0, 1, 2]
		"fps_cap": choices = FPS_CAPS
		"shadow_preset": choices = [0, 1, 2, 3, 4]
		"resolution": choices = resolutions
		_: return _fail("Unknown option")
	if choices.is_empty():
		return _fail("No verified hardware resolutions available")
	var index: int = choices.find(values[key])
	if index < 0: index = 0 # Mirrors source cycle fallback before increment.
	values[key] = choices[(index + 1) % choices.size()]
	if values[key] is Array: values[key] = values[key].duplicate()
	return {"ok": true}

func snapshot() -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "options": values.duplicate(true)}

static func _stage(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.get("format") != FORMAT or raw.get("version") != VERSION or not raw.get("options") is Dictionary:
		return _fail("Unsupported user options format")
	var data: Dictionary = raw.options
	if data.size() != 7:
		return _fail("Unexpected or missing option fields")
	for key in ["sfx_db", "bgm_db"]:
		if not _number(data.get(key)) or data[key] < -80 or data[key] > 0:
			return _fail("Invalid audio gain")
	if not data.get("resolution") is Array or (not data.resolution.is_empty() and not _resolution(data.resolution)):
		return _fail("Invalid resolution")
	if not data.get("fullscreen") in MODES:
		return _fail("Invalid fullscreen mode")
	for key in ["vsync", "fps_cap", "shadow_preset"]:
		if not _integer(data.get(key)):
			return _fail("Invalid option integer")
	if int(data.vsync) < 0 or int(data.vsync) > 2 or not int(data.fps_cap) in FPS_CAPS or int(data.shadow_preset) < 0 or int(data.shadow_preset) > 4:
		return _fail("Unsupported option value")
	var normalized: Dictionary = data.duplicate(true)
	for key in ["vsync", "fps_cap", "shadow_preset"]:
		normalized[key] = int(data[key])
	if not data.resolution.is_empty(): normalized.resolution = [int(data.resolution[0]), int(data.resolution[1])]
	for key in ["sfx_db", "bgm_db"]: normalized[key] = float(data[key])
	return {"ok": true, "options": normalized}

func restore(raw: Variant) -> Dictionary:
	var staged := _stage(raw)
	if staged.ok: values = staged.options
	return staged

## Describes intent only; unsupported entries must be handled explicitly by UI.
func application_plan() -> Dictionary:
	var unsupported: Array = ["unity_shadow_preset"]
	if values.vsync == 2: unsupported.append("half_vsync")
	if values.resolution.is_empty() or not resolutions.has(values.resolution): unsupported.append("resolution")
	return {"options": values.duplicate(true), "unsupported": unsupported, "fps_overridden_by_vsync": values.vsync != 0}

## Adapter owns capability mapping/application and reports its own result.
## No automatic application occurs on configure/load/change/reset/save.
func apply_with(adapter: Callable) -> Dictionary:
	var valid := _stage(snapshot())
	if not valid.ok: return valid
	if not adapter.is_valid(): return _fail("No options application adapter")
	var result = adapter.call(application_plan())
	return result if result is Dictionary and result.get("ok") is bool else _fail("Adapter must return an ok/error result")

static func _read(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return _fail("Cannot read options file")
	if file.get_length() > MAX_BYTES: return _fail("Options file exceeds size limit")
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK: return _fail("Invalid options JSON")
	return _stage(parser.data)

## Invalid files remain untouched. Default fallback is explicit in the result.
func load_file(path: String = "user://options.json") -> Dictionary:
	var errors: Array = []
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate): continue
		var read := _read(candidate)
		if read.ok:
			values = read.options
			return {"ok": true, "path": candidate, "recovered": candidate != path, "used_defaults": false, "errors": errors}
		errors.append({"path": candidate, "error": read.error})
	reset_defaults()
	return {"ok": errors.is_empty(), "used_defaults": true, "recovered": false, "errors": errors}

func save_file(path: String = "user://options.json") -> Dictionary:
	var valid := _stage(snapshot())
	if not valid.ok: return valid
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return _fail("Cannot create options temporary file")
	file.store_string(JSON.stringify(snapshot(), "", true, true))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK or not _read(path + ".tmp").ok: return _fail("Options temporary write/verification failed")
	if FileAccess.file_exists(path) and _read(path).ok:
		error = DirAccess.copy_absolute(path, path + ".bak.tmp")
		if error != OK: return _fail("Options backup copy failed")
		error = DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak")
		if error != OK: return _fail("Options backup replacement failed")
	error = DirAccess.rename_absolute(path + ".tmp", path)
	if error != OK: return _fail("Options atomic replacement failed")
	return {"ok": true, "path": path}
