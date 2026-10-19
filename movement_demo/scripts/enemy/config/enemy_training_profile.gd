@tool
extends Resource
class_name EnemyTrainingProfile

@export var display_name: String = "训练配置"
## 手动解锁。高级动作包含的基础项由装配器计算，不重复保存。
@export_storage var selected_tactics: Array[StringName] = []
@export_group("训练参数")
@export var ai: Resource = preload("res://scripts/enemy/config/ai_settings.gd").new()
@export var tactics: Resource = preload("res://scripts/enemy/config/tactics_settings.gd").new()
@export var search: Resource = preload("res://scripts/enemy/config/search_settings.gd").new()
@export var cover: Resource = preload("res://scripts/enemy/config/cover_settings.gd").new()
@export var suppression: Resource = preload("res://scripts/enemy/config/suppression_settings.gd").new()
## 旧资源兼容字段；新训练统一编辑 suppression。
@export_storage var exit_suppression: Resource = preload("res://scripts/enemy/config/exit_suppression_settings.gd").new()
@export var fire_decision: Resource = preload("res://scripts/enemy/config/fire_decision_settings.gd").new()
@export var perception: Resource = preload("res://scripts/enemy/config/perception_settings.gd").new()
@export var selection: Resource = preload("res://scripts/enemy/config/selection_settings.gd").new()
@export var cooperation: Resource = preload("res://scripts/enemy/config/cooperation_settings.gd").new()

@export var action_overrides: Array[EnemyModuleSettings] = []

func module(section: StringName) -> Resource:
	for settings in action_overrides:
		if settings != null and settings.section == section: return settings
	var value = get(section)
	return value if value is EnemyModuleSettings else null

func setting(section: StringName, key: StringName, fallback: Variant = null, unit_defaults: Dictionary = {}) -> Variant:
	var settings = module(section)
	# 只有旧配置明确覆盖的出口值才迁入新方案，不覆盖新的显式设置。
	if section == &"suppression" and (settings == null or not settings.overridden.has(String(key))):
		var legacy_keys := {&"exit_duration_min": &"duration_min", &"exit_duration_max": &"duration_max", &"shots_per_exit_min": &"shots_per_exit_min", &"shots_per_exit_max": &"shots_per_exit_max"}
		var legacy = module(&"exit_suppression")
		if legacy_keys.has(key) and legacy != null and legacy.overridden.has(String(legacy_keys[key])):
			return legacy.get(legacy_keys[key])
	if settings != null:
		var value = settings.get(key)
		if value != null:
			if settings.overridden.has(String(key)) or not unit_defaults.has(key):
				return value
	return unit_defaults.get(key, fallback)

func set_setting(section: StringName, key: StringName, value: Variant) -> void:
	var settings = module(section)
	if settings != null and settings.get(key) != null:
		settings.set(key, value)
		emit_changed()

func fingerprint() -> int:
	var data: Array = [selected_tactics]
	for settings in action_overrides:
		if settings != null: data.append(settings.fingerprint())
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value = get(property.name)
			if value is EnemyModuleSettings:
				data.append(value.fingerprint())
	return hash(data)
