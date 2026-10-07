extends SceneTree

## 阶段／任务／状态控制器检查：阶段判定、任务状态机、规则解析、快照与记录。
## 运行：godot --headless --path movement_demo --script res://tests/stage_system_test.gd

const StagePhases := preload("res://scripts/systems/stage/stage_phase.gd")
const StageTableScript := preload("res://scripts/systems/stage/stage_table.gd")
const StageDefinitionScript := preload("res://scripts/systems/stage/stage_definition.gd")
const QuestDefinitionScript := preload("res://scripts/systems/stage/quest_definition.gd")
const StateRuleScript := preload("res://scripts/systems/stage/state_rule.gd")
const StageControllerScript := preload("res://scripts/systems/stage/stage_controller.gd")
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")
const StageStateControllerScript := preload("res://scripts/systems/stage/stage_state_controller.gd")
const NpcScript := preload("res://scripts/world/npc.gd")
const GameStateScript := preload("res://scripts/systems/game_state.gd")

const LOG_PATH := "res://logs/stage_system_test.log"
const TAVERN_SPOT := Vector3(-7.883234, 0.0, 3.7864947)
const SECOND_SPOT := Vector3(7.2, 0.0, 3.2)
const MOVED_SPOT := Vector3(-8.6, 0.0, 4.3)
const LATE_SPOT := Vector3(-8.1, 0.0, 2.4)

var failures: int = 0
var state
var stage_controller
var quest_controller
var state_controller
var npc_a: Node3D
var npc_b: Node3D
var player: Node3D
var tavern_zone: Area3D
var site_zone: Area3D
var dialogue_a: Resource
var dialogue_b: Resource
var dialogue_done: Resource


func _initialize() -> void:
	_install_watchdog()
	call_deferred("run_checks")


## 脚本报错会让 run_checks 提前中断，没有看门狗时 headless 进程会一直空转。
func _install_watchdog() -> void:
	var timer := Timer.new()
	timer.name = "StageTestWatchdog"
	timer.wait_time = 60.0
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		push_error("阶段自检查超时退出")
		quit(1))
	root.add_child(timer)


func check(condition: bool, label_text: String) -> void:
	if condition:
		print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)


func run_checks() -> void:
	_build_world()
	var table := _build_table()
	state_controller.stage_table = table
	state_controller.reload_table()

	_check_initial_stage()
	_check_refusal_keeps_tavern()
	_check_accept_moves_to_quest_taken()
	_check_travel_and_site()
	_check_return_completes_quest()
	_check_snapshot()
	_check_rule_override()
	_check_apply_switch()
	_check_logging()
	_check_dialogue_snapshot()
	_check_state_signal()
	await _check_scene_wiring()

	if failures == 0:
		print("stage system checks: all passed")
	else:
		print("stage system checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)


func _check_initial_stage() -> void:
	check(stage_controller.get_stage_index() == 1, "初始阶段为任务一")
	check(stage_controller.get_phase() == StagePhases.Id.TAVERN_IDLE, "未接任务时处于酒馆待命")
	check(stage_controller.get_phase_name() == "酒馆待命", "阶段名称按环节枚举给出")
	check(
		quest_controller.status_of(&"task_a") == QuestControllerScript.Status.NOT_STARTED,
		"任务初始为未接"
	)


func _check_refusal_keeps_tavern() -> void:
	state.help_choice = "refused"
	check(
		quest_controller.status_of(&"task_a") == QuestControllerScript.Status.REFUSED,
		"拒绝后任务状态为已拒绝"
	)
	check(stage_controller.get_phase() == StagePhases.Id.TAVERN_IDLE, "拒绝不算接取，仍在酒馆待命")


func _check_accept_moves_to_quest_taken() -> void:
	state.help_choice = "accepted"
	check(
		quest_controller.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS,
		"答应后任务进入进行中"
	)
	check(stage_controller.get_phase() == StagePhases.Id.QUEST_TAKEN, "接取后阶段为已接任务")
	var resolved: Dictionary = state_controller.resolve_npc_states()
	check(resolved[&"npc_b"].present, "条件不匹配的规则不生效：进行中时 B 仍在场")


func _check_travel_and_site() -> void:
	tavern_zone.body_exited.emit(player)
	check(stage_controller.get_phase() == StagePhases.Id.TRAVELING, "离开酒馆后阶段为前往场地")
	tavern_zone.body_entered.emit(player)
	check(stage_controller.get_phase() == StagePhases.Id.TRAVELING, "已出发后回到酒馆仍是前往场地")
	site_zone.body_entered.emit(player)
	check(stage_controller.get_phase() == StagePhases.Id.IN_SITE, "进入场地后阶段为场地战斗")
	check(stage_controller.get_player_zone() == &"site", "玩家区域跟随场地进出")


func _check_return_completes_quest() -> void:
	site_zone.body_exited.emit(player)
	check(stage_controller.get_phase() == StagePhases.Id.RETURNED, "离开场地后阶段为返回结算")
	check(
		quest_controller.status_of(&"task_a") == QuestControllerScript.Status.COMPLETED,
		"返回后任务按表自动完成"
	)


func _check_snapshot() -> void:
	var snapshot: Dictionary = state_controller.get_snapshot()
	check(int(snapshot["stage"]["index"]) == 1, "快照记录阶段序号")
	check(str(snapshot["stage"]["name"]) == "任务一", "快照记录阶段名称")
	check(int(snapshot["phase"]["id"]) == StagePhases.Id.RETURNED, "快照记录当前环节")
	check(str(snapshot["quest"]["status_name"]) == "已完成", "快照记录任务状态")
	check(str(snapshot["quest"]["id"]) == "task_a", "快照记录任务 id")
	check(str(snapshot["quest"]["target_area"]) == "arena", "快照记录任务目标地点")
	check(snapshot["npcs"].size() == 2, "快照列出全部 NPC")
	check(str(snapshot["npcs"][&"npc_a"]["rule"]) == "done_a_2", "快照给出最后命中的规则")
	check(
		str(snapshot["npcs"][&"npc_a"]["dialogue"]) == dialogue_done.resource_path,
		"快照给出该阶段对话资源"
	)
	check(str(snapshot["player"]["zone"]) == "tavern", "快照记录玩家所在区域")


func _check_rule_override() -> void:
	var resolved: Dictionary = state_controller.resolve_npc_states()
	check(
		resolved[&"npc_a"]["position"].is_equal_approx(LATE_SPOT),
		"同一目标的多条规则按顺序覆盖，后者生效"
	)
	check(
		str(resolved[&"npc_a"]["dialogue"]) == dialogue_done.resource_path,
		"未覆盖的字段保留前一条规则的结果"
	)
	check(resolved[&"npc_b"]["present"] == false, "任务完成后 B 按规则退场")
	check(
		resolved[&"npc_b"]["position"].is_equal_approx(SECOND_SPOT),
		"未指定站位的 NPC 保留自身坐标"
	)


func _check_apply_switch() -> void:
	check(npc_a.get("dialogue_resource") == dialogue_a, "开关关闭时不改动对话资源")
	check(npc_a.global_position.is_equal_approx(TAVERN_SPOT), "开关关闭时不改动站位")
	check(npc_b.visible, "开关关闭时不改动在场状态")

	state_controller.apply_enabled = true
	state_controller.apply_states()
	check(npc_a.get("dialogue_resource") == dialogue_done, "打开开关后按表替换对话资源")
	check(npc_a.global_position.is_equal_approx(LATE_SPOT), "打开开关后按表移动站位")
	check(not npc_b.visible, "打开开关后按表让 NPC 退场")
	check(str(npc_a.get("stage_state").get("rule", "")) == "done_a_2", "NPC 记录自己被应用的规则")


func _check_logging() -> void:
	DirAccess.remove_absolute(LOG_PATH)
	state_controller.print_log = false
	state_controller.log_to_file = false
	state_controller.log_snapshot("自检关闭记录")
	check(not FileAccess.file_exists(LOG_PATH), "关闭文件记录时不写日志")

	state_controller.log_to_file = true
	state_controller.log_snapshot("自检写入记录")
	check(FileAccess.file_exists(LOG_PATH), "打开文件记录时写入日志")
	var text := FileAccess.get_file_as_string(LOG_PATH)
	check(text.contains("返回结算"), "记录包含当前阶段")
	check(text.contains("done_a_2"), "记录包含命中的规则")
	check(text.contains("自检写入记录"), "记录包含变化原因")


func _check_dialogue_snapshot() -> void:
	var ui: Node = load("res://scenes/ui/dialogue_ui.tscn").instantiate()
	root.add_child(ui)
	ui.set("dialogue_player", player)
	ui.set("dialogue_source", npc_a)
	var snapshot: Dictionary = state_controller.get_snapshot()
	check(bool(snapshot["dialogue"]["active"]), "对话进行中时快照标记为进行中")
	check(str(snapshot["dialogue"]["source"]) == "npc_a", "快照记录对话来源")
	ui.set("dialogue_player", null)
	check(
		not bool(state_controller.get_snapshot()["dialogue"]["active"]),
		"对话结束后快照不再标记进行中"
	)
	ui.queue_free()


func _check_state_signal() -> void:
	var seen: Array = []
	state.value_changed.connect(func(key: StringName, value: Variant) -> void: seen.append([key, value]))
	state.help_choice = "accepted"
	check(seen.is_empty(), "对话状态未变化时不重复发信号")
	state.help_choice = "refused"
	check(seen.size() == 1 and seen[0][0] == &"help_choice", "对话写入会通知监听者")
	check(
		quest_controller.status_of(&"task_a") == QuestControllerScript.Status.REFUSED,
		"改投拒绝后任务状态跟随变化"
	)


## 主场景接线检查：真实场景里三个控制器是否就位、区域是否绑定、玩家是否被识别在酒馆内。
func _check_scene_wiring() -> void:
	_clear_fixture()
	await process_frame
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame
	await physics_frame

	var stage = get_first_node_in_group(&"stage_controller")
	var quests = get_first_node_in_group(&"quest_controller")
	var state_ctl = get_first_node_in_group(&"stage_state_controller")
	check(stage != null and quests != null and state_ctl != null, "主场景挂上了三个控制器")
	if stage == null or quests == null or state_ctl == null:
		return
	check(stage.tavern_zone != null and stage.site_zone != null, "阶段控制器绑定了酒馆与场地范围")
	check(stage.get_player_zone() == &"tavern", "玩家初始被识别为在酒馆内")
	check(stage.get_phase() == StagePhases.Id.TAVERN_IDLE, "主场景初始环节为酒馆待命")
	var snapshot: Dictionary = state_ctl.get_snapshot()
	check(str(snapshot["stage"]["name"]) == "任务一", "主场景读取配置表模板")
	check(snapshot["npcs"].size() == 2, "主场景快照列出两个 NPC")
	check(
		str(snapshot["npcs"][&"npc_a"]["dialogue"]) == dialogue_a.resource_path,
		"主场景 NPC 与配置表 id 对应"
	)
	check(state_ctl.apply_enabled == false, "默认不把状态落到表现上")
	scene.queue_free()
	await process_frame


## 释放替身世界，避免与主场景的同名分组互相干扰。
func _clear_fixture() -> void:
	for node in [npc_a, npc_b, player, tavern_zone, site_zone, state, quest_controller, stage_controller, state_controller]:
		if is_instance_valid(node):
			node.free()


func _build_world() -> void:
	dialogue_a = load("res://resources/dialogue/npc_a.dialogue")
	dialogue_b = load("res://resources/dialogue/npc_b.dialogue")
	dialogue_done = load("res://resources/dialogue/terminal.dialogue")

	state = GameStateScript.new()
	state.name = "StageTestState"
	root.add_child(state)

	player = Node3D.new()
	player.name = "StageTestPlayer"
	player.add_to_group(&"player")
	player.position = Vector3(0.0, 0.0, 3.423183)
	root.add_child(player)

	tavern_zone = Area3D.new()
	tavern_zone.name = "StageTestTavernZone"
	root.add_child(tavern_zone)
	site_zone = Area3D.new()
	site_zone.name = "StageTestSiteZone"
	root.add_child(site_zone)

	npc_a = _make_npc(&"npc_a", TAVERN_SPOT, dialogue_a)
	npc_b = _make_npc(&"npc_b", SECOND_SPOT, dialogue_b)

	quest_controller = QuestControllerScript.new()
	quest_controller.name = "StageTestQuestController"
	quest_controller.state_path = NodePath("/root/StageTestState")
	root.add_child(quest_controller)

	stage_controller = StageControllerScript.new()
	stage_controller.name = "StageTestStageController"
	stage_controller.tavern_zone = tavern_zone
	stage_controller.site_zone = site_zone
	root.add_child(stage_controller)

	state_controller = StageStateControllerScript.new()
	state_controller.name = "StageTestStateController"
	state_controller.state_path = NodePath("/root/StageTestState")
	state_controller.log_path = LOG_PATH
	root.add_child(state_controller)


func _make_npc(id: StringName, position: Vector3, dialogue: Resource) -> Node3D:
	var npc := StaticBody3D.new()
	npc.set_script(NpcScript)
	npc.name = str(id)
	npc.set("npc_id", id)
	npc.set("dialogue_resource", dialogue)
	npc.position = position
	var area := Area3D.new()
	area.name = "InteractionArea"
	npc.add_child(area)
	root.add_child(npc)
	return npc


func _rule(
	id: StringName,
	target: StringName,
	dialogue: Resource,
	spot: Vector3
) -> Resource:
	var rule = StateRuleScript.new()
	rule.id = id
	rule.target_npc = target
	if dialogue != null:
		rule.dialogue = dialogue
	if spot != Vector3.ZERO:
		rule.position_set = true
		rule.position = spot
	return rule


func _build_table() -> Resource:
	var table = StageTableScript.new()

	var stage = StageDefinitionScript.new()
	stage.index = 1
	stage.display_name = "任务一"
	stage.quest_id = &"task_a"
	stage.target_area = &"arena"
	table.stages.append(stage)

	var quest = QuestDefinitionScript.new()
	quest.id = &"task_a"
	quest.display_name = "帮 A 的忙"
	quest.stage_index = 1
	quest.accept_source = &"help_choice"
	quest.accept_value = "accepted"
	quest.refuse_values.assign(["refused"])
	quest.complete_on_return = true
	table.quests.append(quest)

	var back := StateRuleScript.new()
	back.id = &"b_back"
	back.target_npc = &"npc_b"
	back.quest_id = &"task_a"
	back.quest_status = &"in_progress"
	back.present = true

	var gone := StateRuleScript.new()
	gone.id = &"b_gone"
	gone.target_npc = &"npc_b"
	gone.quest_id = &"task_a"
	gone.quest_status = &"completed"
	gone.present = false

	var done := _rule(&"done_a", &"npc_a", dialogue_done, MOVED_SPOT)
	done.quest_id = &"task_a"
	done.quest_status = &"completed"

	var done_late := _rule(&"done_a_2", &"npc_a", null, LATE_SPOT)
	done_late.quest_id = &"task_a"
	done_late.quest_status = &"completed"

	table.rules.append(_rule(&"default_a", &"npc_a", dialogue_a, TAVERN_SPOT))
	table.rules.append(_rule(&"default_b", &"npc_b", dialogue_b, SECOND_SPOT))
	table.rules.append(back)
	table.rules.append(gone)
	table.rules.append(done)
	table.rules.append(done_late)
	return table
