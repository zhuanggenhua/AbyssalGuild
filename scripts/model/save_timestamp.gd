extends RefCounted
## Persisted local wall clock, corresponding to GameDirector.SaveGame DateTime.Now.
## Native JSON schema, not a Unity/Newtonsoft save reader. Missing means unknown.
static func now() -> Dictionary:
	return {"local": Time.get_datetime_string_from_system(false), "utc_offset_minutes": int(Time.get_time_zone_from_system().bias)}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2:
		return false
	var local = value.get("local")
	var offset = value.get("utc_offset_minutes")
	if not local is String or local.length() != 19 or not (offset is int or offset is float):
		return false
	if not is_finite(float(offset)) or offset != floor(float(offset)) or absf(float(offset)) > 840:
		return false
	# Round-trip rejects impossible dates, normalization, fractional or extra input.
	var pattern := RegEx.new()
	pattern.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$")
	if pattern.search(local) == null or local.substr(0,4).to_int() < 1:
		return false
	var year: int = local.substr(0, 4).to_int()
	var month: int = local.substr(5, 2).to_int()
	var day: int = local.substr(8, 2).to_int()
	var days := [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month < 1 or month > 12 or day < 1 or day > days[month - 1] or local.substr(11, 2).to_int() > 23 or local.substr(14, 2).to_int() > 59 or local.substr(17, 2).to_int() > 59:
		return false
	return Time.get_datetime_string_from_unix_time(Time.get_unix_time_from_datetime_string(local)) == local

static func describe(value: Dictionary) -> String:
	if not valid(value): return "unavailable"
	var bias := int(value.utc_offset_minutes)
	return "%s %s%02d:%02d" % [str(value.local).replace("T", " "), "+" if bias >= 0 else "-", absi(bias) / 60, absi(bias) % 60]
