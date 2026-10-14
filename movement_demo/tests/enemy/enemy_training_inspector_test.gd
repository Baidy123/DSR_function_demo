@tool
extends SceneTree

var checks := 0
var failed := 0

class Member extends Node:
	var faction_id: StringName = &"allies"
	var communication_group: StringName = &"test"

class Area extends Node:
	var team_cooperation_bindings: Array = []

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
	var host := Member.new()
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
	training.profile.selected_tactics.assign([&"exit_suppression"])
	panel.refresh(true)
	var base = _find(panel, "火力压制")
	check(base != null and base.button_pressed and not base.disabled and _find(panel, "出口压制") == null, "旧选择显示为唯一可编辑压制入口")
	check(training.profile.selected_tactics == [&"exit_suppression"], "检查器预览不会隐式改写旧资源")
	panel._toggle(false, training.profile, &"suppression")
	check(training.profile.selected_tactics.is_empty(), "取消统一压制会撤销旧别名解锁")
	var history = manager.get_history_undo_redo(manager.get_object_history_id(training.profile))
	check(history.undo(), "支持编辑器撤销")
	panel.refresh(true)
	check(training.profile.selected_tactics == [&"exit_suppression"] and _find(panel, "火力压制").button_pressed, "撤销准确恢复旧选择与面板")
	check(history.redo(), "支持编辑器重做")
	panel.refresh(true)
	check(not _find(panel, "火力压制").button_pressed, "重做撤销旧别名的解锁")
	panel._toggle(true, training.profile, &"suppression")
	unit.profile = preload("res://resources/enemy/units/melee.tres").duplicate(true)
	panel.refresh(true)
	check(_find(panel, "火力压制") == null and training.profile.selected_tactics == [&"suppression"], "切换兵种隐藏枪械项但保留选择")
	check(_checks(panel).size() == 4 and _find(panel, "团队协作") != null and _find(panel, "掩体躲藏与探头") != null and _find(panel, "掩体接近") != null and _find(panel, "短程突进") != null and _checks(panel).all(func(box): return not box.button_pressed), "近战目录提供基础躲藏、升级接近、独立突进及协作")
	panel._toggle(true, training.profile, &"melee_cover")
	var shelter = _find(panel, "掩体躲藏与探头")
	check(shelter.button_pressed and shelter.disabled and shelter.text.contains("包含") and not training.profile.selected_tactics.has(&"cover"), "近战升级自动勾选并锁定基础躲藏，资源仅保存显式选择")
	panel._toggle(true, training.profile, &"melee_rush")
	check(_find(panel, "掩体接近").button_pressed and _find(panel, "短程突进").button_pressed and training.profile.selected_tactics.has(&"suppression"), "近战战术可独立勾选并保留其他兵种的选择")
	check(history.undo(), "近战勾选支持原生撤销")
	panel.refresh(true)
	check(_find(panel, "掩体接近").button_pressed and not _find(panel, "短程突进").button_pressed, "撤销只取消本次突进解锁")
	check(history.redo(), "近战勾选支持原生重做")
	panel.refresh(true)
	check(_find(panel, "短程突进").button_pressed, "重做恢复近战突进选择")
	panel._toggle(false, training.profile, &"melee_cover")
	check(not _find(panel, "掩体躲藏与探头").button_pressed and not _find(panel, "掩体躲藏与探头").disabled, "撤销升级解锁会取消仅被自动包含的基础躲藏")
	panel._toggle(true, training.profile, &"cover")
	panel._toggle(true, training.profile, &"melee_cover")
	panel._toggle(false, training.profile, &"melee_cover")
	check(_find(panel, "掩体躲藏与探头").button_pressed and not _find(panel, "掩体躲藏与探头").disabled, "撤销升级保留此前手动解锁的基础躲藏")
	panel._toggle(true, training.profile, &"melee_cover")
	unit.profile = preload("res://resources/enemy/units/ranged.tres").duplicate(true)
	panel.refresh(true)
	check(_find(panel, "火力压制").button_pressed and _find(panel, "掩体接近") == null and training.profile.selected_tactics.has(&"melee_cover"), "切回兵种恢复原有选择并隐藏保留近战选择")
	unit.profile.capabilities.erase(&"firearms")
	panel.refresh(true)
	var advanced = _find(panel, "火力压制")
	check(advanced.disabled and not advanced.button_pressed and advanced.tooltip_text.contains("缺少"), "缺少关联项时高级项置灰并解释原因")
	var standalone = preload("res://addons/enemy_training_inspector/tactics_panel.gd").new()
	standalone.configure(training.profile, manager)
	check(standalone.unit() == null and _checks(standalone).is_empty(), "独立查看训练资源不会借用其他敌人的兵种")
	standalone.preview_unit = preload("res://resources/enemy/units/ranged.tres")
	standalone.refresh(true)
	check(_checks(standalone).size() == 5, "独立资源显式选择预览兵种后提供受限候选")
	var area := Area.new()
	area.add_child(host)
	var binding = preload("res://scripts/enemy/config/team_cooperation_binding.gd").new()
	binding.faction_id = &"allies"
	binding.communication_group = &"test"
	binding.profile.level = 2
	area.team_cooperation_bindings.append(binding)
	panel.refresh(true)
	var shared = _find(panel, "团队协作")
	check(shared != null and shared.disabled and shared.button_pressed and shared.text.contains("小队"), "绑定后团队协作由小队提供且不能单独取消")
	before = training.profile.selected_tactics.duplicate()
	panel._toggle(false, training.profile, &"cooperate")
	check(training.profile.selected_tactics == before, "继承权限不会改写个人训练")
	check(standalone.team_binding().is_empty(), "独立训练资源预览不虚构所属小队")
	manager.create_action("更改整队团队意识", UndoRedo.MERGE_DISABLE, binding.profile)
	manager.add_do_property(binding.profile, &"level", 0)
	manager.add_undo_property(binding.profile, &"level", 2)
	manager.commit_action()
	panel.refresh(true)
	check(not _find(panel, "团队协作").button_pressed, "整队降档立即更新检查器权限")
	var team_history = manager.get_history_undo_redo(manager.get_object_history_id(binding.profile))
	check(team_history.undo(), "共享配置支持原生撤销")
	panel.refresh(true)
	check(_find(panel, "团队协作").button_pressed, "撤销恢复整队等级")
	check(team_history.redo(), "共享配置支持原生重做")
	panel.refresh(true)
	check(not _find(panel, "团队协作").button_pressed, "重做恢复整队降档")
	var squad = preload("res://scenes/world/squad.tscn").instantiate()
	var peer = preload("res://scenes/world/squad.tscn").instantiate()
	area.add_child(squad)
	area.add_child(peer)
	check(squad.profile != peer.profile and squad.profile.level == 0, "两个新建小队使用独立的仅情报共享配置")
	host.reparent(squad, false)
	squad.profile.level = 2
	panel.refresh(true)
	check(panel.team_binding().squad == squad and _find(panel, "团队协作").button_pressed, "最近小队节点覆盖旧区域绑定并提供团队意识")
	before = training.profile.selected_tactics.duplicate()
	manager.create_action("更改节点小队等级", UndoRedo.MERGE_DISABLE, squad.profile)
	manager.add_do_property(squad.profile, &"level", 0)
	manager.add_undo_property(squad.profile, &"level", 2)
	manager.commit_action()
	panel.refresh(true)
	check(not _find(panel, "团队协作").button_pressed and peer.profile.level == 0 and before == training.profile.selected_tactics, "节点配置降档保留其他队及个人训练")
	var squad_history = manager.get_history_undo_redo(manager.get_object_history_id(squad.profile))
	check(squad_history.undo(), "节点小队配置支持原生撤销")
	panel.refresh(true)
	check(_find(panel, "团队协作").button_pressed and squad_history.redo(), "节点小队撤销恢复权限并支持重做")
	var saved_root := Node3D.new()
	saved_root.name = "SquadRoundTrip"
	var saved_squad = preload("res://scenes/world/squad.tscn").instantiate()
	var saved_peer = preload("res://scenes/world/squad.tscn").instantiate()
	saved_squad.name = "SquadA"
	saved_peer.name = "SquadB"
	saved_root.add_child(saved_squad)
	saved_root.add_child(saved_peer)
	saved_squad.owner = saved_root
	saved_peer.owner = saved_root
	saved_squad.profile.level = 2
	var packed := PackedScene.new()
	check(packed.pack(saved_root) == OK and ResourceSaver.save(packed, "res://logs/squad_profile_roundtrip.tscn") == OK, "两个小队可保存为场景资源")
	var reloaded = ResourceLoader.load("res://logs/squad_profile_roundtrip.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	var loaded_a = reloaded.get_node("SquadA")
	var loaded_b = reloaded.get_node("SquadB")
	check(loaded_a.profile.level == 2 and loaded_b.profile.level == 0 and loaded_a.profile != loaded_b.profile, "重载保留各队等级及独立配置")
	check(loaded_a.coordinator != loaded_b.coordinator and loaded_a.coordinator._coordination_plans.is_empty(), "重载重新创建独立运行状态而不序列化计划")
	reloaded.free()
	saved_root.free()
	host.reparent(area, false)
	area.remove_child(host)
	area.free()
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
