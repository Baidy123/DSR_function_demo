@tool
extends SceneTree

var checks := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(label)

func _run() -> void:
	# --editor 的首次扫描晚于 SceneTree 初始化，避免测试先结束并中断扫描。
	await create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	var host := Node.new()
	var unit = preload("res://scripts/enemy/enemy_unit_type.gd").new()
	unit.name = "UnitType"
	unit.profile = preload("res://resources/enemy/units/ranged.tres").duplicate(true)
	var training = preload("res://scripts/enemy/enemy_training.gd").new()
	training.name = "Training"
	training.profile = EnemyTrainingProfile.new()
	host.add_child(unit)
	host.add_child(training)
	var bridge := EditorPlugin.new()
	var manager = bridge.get_undo_redo()
	var panel = preload("res://addons/enemy_training_inspector/tactics_panel.gd").new()
	panel.configure(training, manager)
	check(_checks(panel).size() == unit.profile.tactical_actions.size(), "勾选项来自当前兵种目录")
	check(_checks(panel).all(func(box): return not box.button_pressed), "新训练默认不解锁战术")
	var before: Array[StringName] = training.profile.selected_tactics.duplicate()
	panel.refresh(true)
	check(training.profile.selected_tactics == before, "打开和刷新面板不修改配置")
	panel._toggle(true, training.profile, &"exit_suppression")
	var base = _find(panel, "普通压制")
	check(base != null and base.button_pressed and base.disabled and base.text.contains("包含"), "基础项已勾选、锁定并说明包含来源")
	check(training.profile.selected_tactics == [&"exit_suppression"], "只保存手动选中的高级项")
	var history = manager.get_history_undo_redo(manager.get_object_history_id(training.profile))
	check(history.undo(), "支持编辑器撤销")
	panel.refresh(true)
	check(training.profile.selected_tactics.is_empty() and not _find(panel, "普通压制").button_pressed, "撤销更新真实资源与面板")
	check(history.redo(), "支持编辑器重做")
	panel.refresh(true)
	check(_find(panel, "普通压制").button_pressed, "重做恢复包含关系")
	unit.profile = preload("res://resources/enemy/units/melee.tres").duplicate(true)
	panel.refresh(true)
	check(_checks(panel).is_empty() and training.profile.selected_tactics == [&"exit_suppression"], "切换兵种隐藏旧项但保留选择")
	unit.profile = preload("res://resources/enemy/units/ranged.tres").duplicate(true)
	panel.refresh(true)
	check(_find(panel, "普通压制").button_pressed, "切回兵种恢复原有选择")
	unit.profile.tactical_actions.erase(unit.profile.definition(&"suppression"))
	panel.refresh(true)
	var advanced = _find(panel, "出口压制")
	check(advanced.disabled and not advanced.button_pressed and advanced.tooltip_text.contains("缺少"), "缺少关联项时高级项置灰并解释原因")
	var standalone = preload("res://addons/enemy_training_inspector/tactics_panel.gd").new()
	standalone.configure(training.profile, manager)
	check(standalone.unit() == null and _checks(standalone).is_empty(), "独立查看训练资源不会借用其他敌人的兵种")
	standalone.preview_unit = preload("res://resources/enemy/units/ranged.tres")
	standalone.refresh(true)
	check(_checks(standalone).size() == 5, "独立资源显式选择预览兵种后提供受限候选")
	standalone.free()
	panel.free()
	host.free()
	bridge.free()
	await process_frame
	print("TRAINING INSPECTOR: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)

func _checks(panel) -> Array:
	return panel.rows.get_children().filter(func(child): return child is CheckBox)

func _find(panel, prefix: String):
	for box in _checks(panel):
		if box.text.begins_with(prefix): return box
	return null
