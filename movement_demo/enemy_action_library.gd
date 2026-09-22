extends RefCounted

# 公共实现登记表；每个敌人创建独立实例。掩护撤退复用cover内部流程。
const SCRIPTS = {
	&"patrol": preload("res://enemy_patrol_action.gd"),
	&"search": preload("res://enemy_search.gd"),
	&"engage": preload("res://enemy_tactics.gd"),
	&"cover": preload("res://enemy_cover_action.gd"),
	&"attack_position": preload("res://enemy_attack_position_action.gd"),
	&"suppression": preload("res://enemy_suppression_action.gd"),
	&"exit_suppression": preload("res://enemy_exit_suppression_action.gd"),
}


static func create_actions(unit: Node) -> Dictionary:
	var result: Dictionary = {}
	for id in SCRIPTS:
		var implementation: Script = unit.action_overrides.get(id, SCRIPTS[id])
		var parent: Script = implementation
		while parent != null and parent != SCRIPTS[id]:
			parent = parent.get_base_script()
		if parent == null:
			push_warning("动作替换未继承原实现，使用默认：" + String(id))
			implementation = SCRIPTS[id]
		var action = implementation.new()
		action.action_id = id
		action.config_section = &"tactics" if id == &"engage" else id
		result[id] = action
	return result
