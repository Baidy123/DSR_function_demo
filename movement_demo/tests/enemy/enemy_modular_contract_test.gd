extends SceneTree

const Library = preload("res://scripts/enemy/enemy_action_library.gd")
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
	var unit: EnemyUnitProfile = load("res://resources/enemy/units/ranged.tres").duplicate(true)
	var training := EnemyTrainingProfile.new()
	var base := Library.resolve(unit, training)
	check(base.definitions.size() == 4 and base.definitions.has(&"engage"), "四个默认行为无需训练授权，基础挥击不单独装配")
	check(unit.definition(&"melee_strike") == null, "近战执行不登记为默认行为或战术行为")
	check(Library.resolve(unit, null).definitions.size() == 4, "训练资源缺省不撤销兵种默认行为")
	check(base.definitions.has(&"reload") and not base.definitions.has(&"cover"), "基础換弹独立于掩体战术")
	training.selected_tactics = [&"exit_suppression"]
	var advanced := Library.resolve(unit, training)
	check(advanced.definitions.has(&"suppression") and not advanced.definitions.has(&"exit_suppression"), "旧出口选择迁移为唯一压制实例")
	check(advanced.included_by.is_empty(), "合并后的压制没有虚构父子包含关系")
	check(training.selected_tactics == [&"exit_suppression"], "解析不改写显式选择")
	training.selected_tactics.clear()
	check(not Library.resolve(unit, training).definitions.has(&"suppression"), "取消高级项撤销仅由它带来的基础权限")
	training.selected_tactics = [&"suppression", &"exit_suppression"]
	training.selected_tactics.erase(&"exit_suppression")
	check(Library.resolve(unit, training).definitions.has(&"suppression"), "原先显式选择的基础项保留")
	training.selected_tactics = [&"exit_suppression"]
	var source: EnemyActionDefinition = unit.definition(&"suppression")
	unit.tactical_actions.erase(source)
	var missing := Library.resolve(unit, training)
	check(not missing.definitions.has(&"exit_suppression") and not missing.definitions.has(&"suppression"), "目录没有压制时旧选择不能绕过目录装配")
	unit.tactical_actions.append(source)
	check(Library.resolve(unit, training).definitions.has(&"suppression"), "恢复兵种目录后恢复原有选择")
	var melee: EnemyUnitProfile = load("res://resources/enemy/units/melee.tres")
	check(not Library.resolve(melee, training).definitions.has(&"exit_suppression") and training.selected_tactics == [&"exit_suppression"], "更换兵种保留隐藏选择但不装配")
	source.includes = [&"suppression"]
	check(not Library.resolve(unit, training).errors.is_empty(), "包含关系成环被拒绝")
	source.includes.clear()
	unit.tactical_actions.append(source)
	check(not Library.resolve(unit, training).definitions.has(&"suppression"), "重复 ID 不能装配两个实例")
	unit.tactical_actions.pop_back()
	var misplaced := source.duplicate(true)
	misplaced.action_id = &"misplaced_tactic"
	unit.default_behaviors.append(misplaced)
	check(not Library.resolve(unit, training).definitions.has(&"misplaced_tactic"), "战术定义错放在默认板块不会绕过授权")
	unit.default_behaviors.erase(misplaced)
	unit.capabilities.erase(&"firearms")
	check(not Library.resolve(unit, training).definitions.has(&"suppression"), "身体能力要求不能由训练绕过")
	unit.capabilities.append(&"firearms")
	check(training.setting(&"tactics", &"ranged_min_distance", 0.0, {&"ranged_min_distance": 8.0}) == 8.0, "未显式覆盖时保留兵种动作参数")
	training.set_setting(&"tactics", &"ranged_min_distance", 3.0)
	check(training.setting(&"tactics", &"ranged_min_distance", 0.0, {&"ranged_min_distance": 8.0}) == 3.0, "显式训练覆盖优先")
	var saved := "res://logs/modular_training_roundtrip.tres"
	check(ResourceSaver.save(training, saved) == OK, "训练资源可保存")
	var reloaded = ResourceLoader.load(saved, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(reloaded.selected_tactics == training.selected_tactics and reloaded.setting(&"tactics", &"ranged_min_distance") == 3.0, "保存重载保留选择与显式参数")
	check(reloaded.setting(&"tactics", &"ranged_max_distance", 0.0, {&"ranged_max_distance": 12.0}) == 12.0, "保存不能把未设置的默认数值变成显式覆盖")
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	ai.set_physics_process(false)
	scene.get_node("Player").set_physics_process(false)
	ai.unit_type.profile = unit
	ai.training.profile = training.duplicate(true)
	ai.refresh_configuration(true)
	check(ai.actions.has(&"suppression") and not ai.actions.has(&"exit_suppression"), "旧训练仅创建统一压制执行实例")
	check(not ai.actions.has(&"cover") and not ai.actions.has(&"attack_position"), "未授权动作完全不创建")
	var search_before = ai.actions[&"search"]
	ai.training.profile.selected_tactics.clear()
	ai.refresh_configuration(true)
	check(not ai.actions.has(&"suppression") and not ai.actions.has(&"exit_suppression"), "撤销高级项移除全部不再有效的实例")
	check(ai.actions[&"search"] == search_before, "修改战术保留无关模块的执行实例")
	var custom := EnemyActionDefinition.new()
	custom.action_id = &"contract_probe"
	custom.display_name = "契约探针"
	custom.category = EnemyActionDefinition.Category.TACTICAL
	custom.implementation = preload("res://tests/enemy/modular_probe_action.gd")
	check(not Library.valid_implementation(preload("res://scripts/enemy/services/enemy_fire_decision.gd")), "公共服务不能误装配为动作")
	unit.tactical_actions.append(custom)
	ai.training.profile.selected_tactics.assign([&"contract_probe"])
	ai.refresh_configuration(true)
	for frame in range(5): await physics_frame
	var candidates: Array = ai.action_selector.assess_options(ai, false)
	var probe_options: Array = candidates.filter(func(option): return option.id == &"contract_probe")
	check(probe_options.size() == 1, "只增加定义与实现就可收集新动作候选")
	var probe = ai.actions.get(&"contract_probe")
	if not probe_options.is_empty():
		ai._start_utility_option(probe_options[0], false)
		ai.current_action.tick(0.1, false)
	check(ai.current_action == probe and probe.ticks == 1, "无需修改协调器即可执行新模块")
	ai.context.fire.request = {"owner": &"contract_probe", "mode": &"visible"}
	ai.training.profile.selected_tactics.clear()
	ai.refresh_configuration(true)
	check(probe.cancelled and ai.current_action == null and ai.utility_current.is_empty(), "运行中撤销当前模块执行统一取消")
	check(ai.context.fire.request.is_empty() and ai.agent.target_position.is_equal_approx(enemy.global_position), "取消清理射击意图与导航目标")
	check(ai.actions[&"search"] == search_before, "撤销扩展动作不重置其他模块")
	var first = Library.instantiate(custom, ai.context)
	var second = Library.instantiate(custom, ai.context)
	first.ticks = 99
	check(second.ticks == 0 and first != second, "共享定义不共享进度")
	var cloned: EnemyTrainingProfile = training.duplicate(true)
	cloned.set_setting(&"tactics", &"fire_reaction_seconds", 8.0)
	check(training.setting(&"tactics", &"fire_reaction_seconds") != 8.0, "每敌人训练快照互相隔离")
	ai.unit_type.profile = melee.duplicate(true)
	ai.refresh_configuration(true)
	check(ai.actions.has(&"melee_engage") and not ai.actions.has(&"engage") and not ai.actions.has(&"reload"), "近战模板有独立接敌模块且无枪械默认行为")
	var controller := FileAccess.get_file_as_string("res://scripts/enemy/enemy_ai.gd")
	var selector := FileAccess.get_file_as_string("res://scripts/enemy/enemy_action_selector.gd")
	var context := FileAccess.get_file_as_string("res://scripts/enemy/services/enemy_context.gd")
	for id in [&"suppression", &"exit_suppression", &"attack_position", &"covering_retreat"]:
		check(not controller.contains('&"' + String(id) + '"') and not selector.contains('&"' + String(id) + '"'), "协调器和评分器无具体战术分支：" + String(id))
	check(not context.contains("var actions") and not context.contains("var controller"), "共享上下文不暴露动作注册表")
	scene.queue_free()
	await process_frame
	print("MODULAR CONTRACT: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)
