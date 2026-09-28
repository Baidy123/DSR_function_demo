@tool
extends Node

enum CombatType { MELEE, RANGED }
@export var profile: EnemyUnitProfile:
	set(value):
		profile = value
		notify_property_list_changed()

func supports_firearms() -> bool:
	return profile != null and profile.capabilities.has(&"firearms")

func get_action_definition(id: StringName) -> EnemyActionDefinition:
	return profile.definition(id) if profile != null else null

func has_action(id: StringName) -> bool:
	return get_action_definition(id) != null

func _ready() -> void:
	if not Engine.is_editor_hint() and profile != null:
		profile = profile.duplicate(true)

# 旧场景/测试的分类读取入口；新兵种使用 profile 选择具体行为。
var combat_type: int:
	get: return CombatType.RANGED if supports_firearms() else CombatType.MELEE
	set(value): profile = load("res://resources/enemy/units/ranged.tres" if value == CombatType.RANGED else "res://resources/enemy/units/melee.tres").duplicate(true)
