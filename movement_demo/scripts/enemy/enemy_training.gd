@tool
extends Node

@export var profile: EnemyTrainingProfile:
	set(value):
		profile = value
		notify_property_list_changed()

func _ready() -> void:
	if not Engine.is_editor_hint() and profile != null:
		profile = profile.duplicate(true)

func setting(section: StringName, key: StringName, fallback: Variant = null) -> Variant:
	return profile.setting(section, key, fallback) if profile != null else fallback

func set_setting(section: StringName, key: StringName, value: Variant) -> void:
	if profile != null:
		profile.set_setting(section, key, value)

# 只供旧场景参数迁移和旧测试访问；没有第二份配置存储，也不显示旧字段。
func _legacy_key(property: StringName) -> Array:
	for section in [&"exit_suppression", &"fire_decision", &"suppression", &"perception", &"selection", &"tactics", &"search", &"cover", &"ai"]:
		var prefix := String(section) + "_"
		if String(property).begins_with(prefix):
			return [section, StringName(String(property).trim_prefix(prefix))]
	return []

func _get(property: StringName) -> Variant:
	var parts := _legacy_key(property)
	return setting(parts[0], parts[1]) if parts.size() == 2 else null

func _set(property: StringName, value: Variant) -> bool:
	var parts := _legacy_key(property)
	if parts.is_empty():
		return false
	if profile == null:
		profile = EnemyTrainingProfile.new()
	set_setting(parts[0], parts[1], value)
	return true
