extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# 使用编辑器实际 Inspector，验证类型变化后已有插件的显示刷新。
	for frame in 30: await process_frame
	var weapon := WeaponData.new()
	weapon.magazine_capacity = 27
	EditorInterface.edit_resource(weapon)
	for frame in 30: await process_frame
	EditorInterface.get_inspector().expand_all_folding()
	for frame in 10: await process_frame
	var ranged := _properties(EditorInterface.get_inspector(), weapon)
	check(ranged.has("fire_mode") and not ranged.has("weapon_type") and ranged.has("magazine_capacity") and ranged.has("melee_range"), "原Fire Mode和枪械近战参数可见，没有额外Weapon Type")
	var bridge := EditorPlugin.new()
	var manager = bridge.get_undo_redo()
	manager.create_action("Melee fire mode", UndoRedo.MERGE_DISABLE, weapon)
	manager.add_do_property(weapon, "fire_mode", WeaponData.FireMode.MELEE)
	manager.add_undo_property(weapon, "fire_mode", WeaponData.FireMode.SEMI_AUTO)
	manager.commit_action()
	for frame in 30: await process_frame
	var melee := _properties(EditorInterface.get_inspector(), weapon)
	check(melee.has("fire_mode") and melee.has("melee_damage") and melee.has("melee_range"), "选近战后Fire Mode仍可修改且近战参数可见")
	check(not melee.has("magazine_capacity") and not melee.has("shot_accuracy_penalty") and not melee.has("shot_spread_penalty_degrees"), "近战隐藏弹匣及两种远程准度参数")
	var history = manager.get_history_undo_redo(manager.get_object_history_id(weapon))
	check(history.undo(), "原生编辑器撤销Fire Mode切换")
	for frame in 30: await process_frame
	var restored := _properties(EditorInterface.get_inspector(), weapon)
	check(restored.has("magazine_capacity") and weapon.fire_mode == WeaponData.FireMode.SEMI_AUTO and weapon.magazine_capacity == 27, "撤销回单发恢复字段且保留原数值")
	check(history.redo(), "原生编辑器重做Fire Mode切换")
	for frame in 30: await process_frame
	check(not _properties(EditorInterface.get_inspector(), weapon).has("magazine_capacity") and weapon.magazine_capacity == 27, "重做为近战重新隐藏字段且不清零")
	EditorInterface.get_inspector().edit(null)
	bridge.free()
	for frame in 5: await process_frame
	print("Weapon fire mode inspector: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _properties(node: Node, weapon: WeaponData) -> Dictionary:
	var result := {}
	if node is EditorProperty and node.get_edited_object() == weapon:
		result[node.get_edited_property()] = true
	for child in node.get_children(true):
		result.merge(_properties(child, weapon))
	return result


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
