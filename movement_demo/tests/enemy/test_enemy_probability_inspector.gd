@tool
extends "res://addons/godot_ai/testing/test_suite.gd"

func test_enemy_probability_inspector_01_select() -> void:
	EditorInterface.set_plugin_enabled("weapon_mode_inspector", false)
	EditorInterface.set_plugin_enabled("weapon_mode_inspector", true)
	var root := EditorInterface.get_edited_scene_root()
	var enemy := root.get_node_or_null("Enemy")
	if enemy == null:
		enemy = root.get_node("Arena/Enemy")
	EditorInterface.edit_node(enemy)
	EditorInterface.get_base_control().set_meta("enemy_probability_inspector_weapon", enemy.get("weapon"))
	assert_true(EditorInterface.is_plugin_enabled("weapon_mode_inspector"), "概率检查器插件已启用")

func test_enemy_probability_inspector_02_expand() -> void:
	var weapon: Resource = EditorInterface.get_base_control().get_meta("enemy_probability_inspector_weapon")
	var already_open := not _editors(EditorInterface.get_inspector(), weapon).is_empty()
	assert_true(already_open or _open_weapon(EditorInterface.get_inspector(), weapon), "展开敌人武器")
	EditorInterface.get_inspector().expand_all_folding()

func test_enemy_probability_inspector_03_check() -> void:
	var weapon: Resource = EditorInterface.get_base_control().get_meta("enemy_probability_inspector_weapon")
	var properties := _editors(EditorInterface.get_inspector(), weapon)
	assert_true(properties.has("initial_accuracy"), "显示初始中心概率；实际字段=" + str(properties.keys()) + "；检查器对象=" + str(EditorInterface.get_inspector().get_edited_object()))
	assert_true(properties.has("shot_accuracy_penalty"), "显示连射概率惩罚")
	assert_true(properties.has("player_move_accuracy_loss_per_meter"), "显示移动概率惩罚")
	assert_true(not properties.has("min_spread_angle_degrees") and not properties.has("shot_spread_penalty_degrees"), "隐藏敌人不使用的角度参数")
	assert_true(properties.has("damage") and properties.has("shot_interval"), "保留共用伤害与射速")
	if properties.has("initial_accuracy"):
		assert_true(is_equal_approx(properties.initial_accuracy.spin.value, weapon.initial_accuracy * 100.0), "原生百分比输入显示正确")
	EditorInterface.get_base_control().remove_meta("enemy_probability_inspector_weapon")

func _open_weapon(node: Node, resource: Resource) -> bool:
	if node is EditorResourcePicker and node.edited_resource == resource:
		node.emit_signal("resource_selected", resource, false)
		return true
	for child in node.get_children(true):
		if _open_weapon(child, resource):
			return true
	return false

func _editors(node: Node, resource: Resource) -> Dictionary:
	var result := {}
	if node is EditorProperty and node.get_edited_object() == resource:
		result[node.get_edited_property()] = node
	for child in node.get_children(true):
		result.merge(_editors(child, resource))
	return result
