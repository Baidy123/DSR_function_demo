@tool
extends Resource
class_name EnemyModuleSettings

var section: StringName
@export_storage var overridden: PackedStringArray = []
var _cached_fingerprint := 0
var _fingerprint_dirty := true

func mark_override(key: StringName) -> void:
	_fingerprint_dirty = true
	if not overridden.has(String(key)):
		overridden.append(String(key))
	emit_changed()

func values() -> Dictionary:
	var result: Dictionary = {}
	for item in get_property_list():
		if item.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not String(item.name).begins_with("_") and item.name not in ["section", "overridden"]:
			result[StringName(item.name)] = get(item.name)
	return result

func fingerprint() -> int:
	if _fingerprint_dirty:
		_cached_fingerprint = hash(values())
		_fingerprint_dirty = false
	return hash([section, _cached_fingerprint, overridden])
