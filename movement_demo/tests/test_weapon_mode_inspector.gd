@tool
extends "res://addons/godot_ai/testing/test_suite.gd"

# 逐项调用01～09；MCP测试器不等待协程，工具调用之间让原生检查器完成刷新。
const KEY := "weapon_mode_inspector_fixture"

func test_inspector_01_setup() -> void:
	var c = EditorInterface.get_edited_scene_root().get_node("Player/Combat")
	var slots = c.get_node("../Equipment")
	var fixture := {"combat": c, "slots": slots, "original_weapon": slots.get("primary_weapon")}
	fixture.weapon = fixture.original_weapon.duplicate()
	fixture.weapon.shot_accuracy_penalty = 0.12
	EditorInterface.get_base_control().set_meta(KEY, fixture)
	slots.set("primary_weapon", fixture.weapon)
	EditorInterface.edit_node(slots)
	assert_true(EditorInterface.is_plugin_enabled("weapon_mode_inspector"), "plugin enabled")


func test_inspector_02_expand() -> void:
	if _editors(EditorInterface.get_inspector(), _fixture().weapon).is_empty():
		assert_true(_open_weapon(EditorInterface.get_inspector(), _fixture().weapon), "weapon picker opened")
	EditorInterface.get_inspector().expand_all_folding()
	assert_true(EditorInterface.get_inspector().get_edited_object() == _fixture().slots, "player equipment selected")


func test_inspector_03_player_fields() -> void:
	var f := _fixture()
	var properties := _editors(EditorInterface.get_inspector(), f.weapon)
	assert_true(properties.has("player_move_spread_degrees_per_meter"), "player movement angle visible")
	assert_true(properties.has("shot_spread_penalty_degrees"), "cone fields visible: " + str(properties.keys()))
	assert_true(properties.has("spread_recovery_delay"), "player spread recovery delay visible")
	assert_true(not properties.has("player_move_accuracy_loss_per_meter") and not properties.has("shot_accuracy_penalty")
		and not properties.has("accuracy_recovery_delay"), "enemy probability fields hidden")
	assert_true(properties.has("damage") and properties.has("fire_mode"), "common fields visible in weapon slot")


func test_inspector_04_edit_cone() -> void:
	var f := _fixture()
	var properties := _editors(EditorInterface.get_inspector(), f.weapon)
	if properties.has("shot_spread_penalty_degrees"):
		f.previous_angle = f.weapon.shot_spread_penalty_degrees
		properties.shot_spread_penalty_degrees.value = 2.5


func test_inspector_05_undo() -> void:
	var f := _fixture()
	assert_true(is_equal_approx(f.weapon.shot_spread_penalty_degrees, 2.5), "angle writes actual resource")
	assert_true(is_equal_approx(f.weapon.shot_accuracy_penalty, 0.12), "angle preserves probability")
	var bridge := EditorPlugin.new()
	var manager = bridge.get_undo_redo()
	var history = manager.get_history_undo_redo(manager.get_object_history_id(f.weapon))
	assert_true(history.undo(), "native undo performed")
	assert_true(is_equal_approx(f.weapon.shot_spread_penalty_degrees, f.get("previous_angle", -1.0)), "native undo restores angle")
	assert_true(history.redo(), "native redo performed")
	assert_true(is_equal_approx(f.weapon.shot_spread_penalty_degrees, 2.5), "native redo restores edit")
	bridge.free()


func test_inspector_06_roundtrip() -> void:
	var f := _fixture()
	var path := "user://weapon_mode_roundtrip.tres"
	assert_true(ResourceSaver.save(f.weapon, path) == OK, "resource saves")
	var saved = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(is_equal_approx(saved.shot_spread_penalty_degrees, f.weapon.shot_spread_penalty_degrees), "angle survives reload")
	assert_true(is_equal_approx(saved.shot_accuracy_penalty, f.weapon.shot_accuracy_penalty), "probability survives reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	EditorInterface.edit_resource(f.weapon)


func test_inspector_07_expand_resource() -> void:
	EditorInterface.get_inspector().expand_all_folding()
	assert_true(EditorInterface.get_inspector().get_edited_object() == _fixture().weapon, "standalone resource selected")


func test_inspector_08_standalone() -> void:
	var f := _fixture()
	var properties := _editors(EditorInterface.get_inspector(), f.weapon)
	assert_true(properties.get("shot_accuracy_penalty") is EditorProperty and properties.has("accuracy_recovery_delay")
		and properties.has("shot_spread_penalty_degrees"), "standalone resource shows shared enemy probability and player spread")


func test_inspector_09_restore() -> void:
	var f := _fixture()
	f.slots.set("primary_weapon", f.original_weapon)
	EditorInterface.edit_node(f.combat)
	f.original_weapon.notify_property_list_changed()
	EditorInterface.get_base_control().remove_meta(KEY)


func _open_weapon(node: Node, resource: Resource) -> bool:
	if node is EditorResourcePicker and node.edited_resource == resource:
		node.emit_signal("resource_selected", resource, false)
		return true
	for child in node.get_children(true):
		if _open_weapon(child, resource):
			return true
	return false


func _fixture() -> Dictionary:
	return EditorInterface.get_base_control().get_meta(KEY, {})


func _editors(node: Node, resource: Resource) -> Dictionary:
	var result := {}
	if node is EditorProperty and node.get_edited_object() == resource:
		var tabs := node.get_node_or_null("AimModeTabs") as TabContainer
		if tabs == null:
			result[node.get_edited_property()] = node
		else:
			for row in tabs.get_child(0).get_children():
				result[String(row.name)] = row.get_node("Value")
	for child in node.get_children(true):
		result.merge(_editors(child, resource))
	return result
