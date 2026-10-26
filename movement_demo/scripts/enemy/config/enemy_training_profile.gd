@tool
extends Resource
class_name EnemyTrainingProfile

## 适用范围：个人指无小队或0级情报共享下的 Utility；协调器指1/2级团队指挥。
## “共用”包含成员执行器、身体和火控读取，不表示协调器重新运行个人 Utility。
## 团队在本场装配时冻结训练/能力；修改后需重新加载战斗，且不能越过战术解锁。

## 【配置标识】只用于识别训练配置，不参与个人或团队决策。
@export var display_name: String = "训练配置"
## 【个人与协调器共用】个人可用动作与团队可指派能力均受训练解锁限制。
## 手动解锁。高级动作包含的基础项由装配器计算，不重复保存。
@export_storage var selected_tactics: Array[StringName] = []
@export_group("训练参数")
## 【混合范围】巡逻停留仅个人使用；受击位置误差由个人与团队共用。
@export var ai: Resource = preload("res://scripts/enemy/config/ai_settings.gd").new()
## 【混合范围】身体与火控参数大多共用；抗压阈值/支援长点射仅团队，部分选位参数仅个人。
## 作战能力：移动开火、反应、受击倍率和被动防护。内部tactics资源键保留，以兼容已有配置和外部接口。
@export var tactics: Resource = preload("res://scripts/enemy/config/tactics_settings.gd").new()
## 【混合范围】提示概率、快速追查与观察时长等共用；个人 TRACK/覆盖结束规则不用于团队。逐项见参数注释。
@export var search: Resource = preload("res://scripts/enemy/config/search_settings.gd").new()
## 【混合范围】动作速度、躲藏/观察时长共用；低掩体/换弹偏好和个人绕行参数不控制团队评分。
@export var cover: Resource = preload("res://scripts/enemy/config/cover_settings.gd").new()
## 【个人与协调器共用】解锁后的有限压制参数；并非无条件允许团队对隐藏目标开火。
@export var suppression: Resource = preload("res://scripts/enemy/config/suppression_settings.gd").new()
## 【旧资源兼容】只保留序列化值；当前个人与协调器均不以此调节动作。
## 旧资源兼容字段；新训练统一编辑 suppression。
@export_storage var exit_suppression: Resource = preload("res://scripts/enemy/config/exit_suppression_settings.gd").new()
## 【个人与协调器共用】统一火控的开火/稳枪评分，协调器命令也经过这套判断。
@export var fire_decision: Resource = preload("res://scripts/enemy/config/fire_decision_settings.gd").new()
## 【个人与协调器共用】成员的视听觉、换弹观察与近墙情报；团队使用同一感知入口。
@export var perception: Resource = preload("res://scripts/enemy/config/perception_settings.gd").new()
## 【混合范围】翻越偏好、攻击占位几何等共用；个人掩体质量参数不替代团队防御检查。
@export var selection: Resource = preload("res://scripts/enemy/config/selection_settings.gd").new()

## 【个人与协调器共用】按模块覆盖训练参数；每项适用范围仍由对应参数决定，不自动解锁动作。
@export var action_overrides: Array[EnemyModuleSettings] = []

## 旧训练文件仍可能带此字段；加载时丢弃，不暴露属性或再次序列化。
## 协作配置由 Squad/区域显式绑定提供，个人训练不再保存第二份。
func _set(property: StringName, _value: Variant) -> bool:
	return property == &"cooperation"

func module(section: StringName) -> Resource:
	# 包括旧 Action Overrides：不能借训练覆盖重新引入队级配置。
	if section == &"cooperation": return null
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
