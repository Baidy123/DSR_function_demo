extends Node

# 兵种只提供动作及实现；权限在Training，调用决策在AI。
const ActionDefinition = preload("res://enemy_action_definition.gd")
const Library = preload("res://enemy_action_library.gd")
enum CombatType { MELEE, RANGED }

## 原近战/远程分类；近战尚无攻击动作。
@export var combat_type: CombatType = CombatType.MELEE
## 拖入enemy_actions目录中的动作资源；训练不能授予清单外的动作。
## 特殊实现：复制动作资源，保持ID，替换Implementation后拖入；同ID只保留一项。
@export var available_actions: Array[ActionDefinition] = [
	preload("res://enemy_actions/patrol.tres"),
	preload("res://enemy_actions/search.tres"),
	preload("res://enemy_actions/engage.tres"),
	preload("res://enemy_actions/cover.tres"),
	preload("res://enemy_actions/attack_position.tres"),
	preload("res://enemy_actions/suppression.tres"),
	preload("res://enemy_actions/exit_suppression.tres"),
	preload("res://enemy_actions/covering_retreat.tres"),
]


func get_action_definition(id: StringName) -> ActionDefinition:
	for definition in available_actions:
		if definition != null and definition.action_id == id:
			return definition
	return null


func has_action(id: StringName) -> bool:
	return get_action_definition(id) != null and (Library.SCRIPTS.has(id) or id == &"covering_retreat")


func create_actions() -> Dictionary:
	# 每敌人独立运行对象；能否提供给AI选择始终以has_action为准。
	return Library.create_actions(self)
