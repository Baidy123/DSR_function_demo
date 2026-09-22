extends RefCounted

# 公共实现共用代码，每个AI独立持有实例；通过setup显式绑定上下文。
var ai: Node
var action_id: StringName
var config_section: StringName
var _standalone_settings: Dictionary = {}

var actor:
	get: return ai.get_parent() if is_instance_valid(ai) else null
var enemy:
	get: return actor
var agent:
	get: return actor.agent
var tactics:
	get: return ai.tactics
var selection:
	get: return ai.cover_selection


func setup(owner_ai: Node, section: StringName = &"") -> void:
	ai = owner_ai
	if not section.is_empty():
		config_section = section


func is_enabled() -> bool:
	return is_instance_valid(ai) and ai.can_use_action(action_id)


func _setting(key: StringName, fallback: Variant) -> Variant:
	if is_instance_valid(ai):
		return ai.get_node("../Training").get(String(config_section) + "_" + String(key))
	return _standalone_settings.get(key, fallback)


func _set_setting(key: StringName, value: Variant) -> void:
	if is_instance_valid(ai):
		ai.get_node("../Training").set(String(config_section) + "_" + String(key), value)
	else:
		# 独立测试未绑定敌人时使用；绑定后唯一配置源是Training。
		_standalone_settings[key] = value
