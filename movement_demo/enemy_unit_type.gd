extends Node

# 兵种只提供动作及实现；权限在Training，调用决策在AI。
const Library = preload("res://enemy_action_library.gd")
enum CombatType { MELEE, RANGED }

## 原近战/远程分类；近战尚无攻击动作。
@export var combat_type: CombatType = CombatType.MELEE
## 本兵种具备的动作；Training不能授予清单外的动作。
@export var available_actions: PackedStringArray = PackedStringArray(["patrol", "search", "engage", "cover", "attack_position", "suppression", "exit_suppression", "covering_retreat"])
## 键使用动作名，替换脚本须继承对应公共动作。未填则复用公共实现。
@export var action_overrides: Dictionary[StringName, Script] = {}


func has_action(id: StringName) -> bool:
	return String(id) in available_actions and (Library.SCRIPTS.has(id) or id == &"covering_retreat")


func create_actions() -> Dictionary:
	# 每敌人独立运行对象；能否提供给AI选择始终以has_action为准。
	return Library.create_actions(self)
