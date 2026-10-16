extends SceneTree

## 任务控制器检查：阶段窗口、六种条件来源、终态不回退、查询接口与只读阶段接口。
## 运行：godot --headless --path movement_demo --script res://tests/quest_system_test.gd

const QuestConditionScript := preload("res://scripts/systems/stage/quest_condition.gd")
const StageTableScript := preload("res://scripts/systems/stage/stage_table.gd")
const StageDefinitionScript := preload("res://scripts/systems/stage/stage_definition.gd")
const QuestDefinitionScript := preload("res://scripts/systems/stage/quest_definition.gd")
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")
const GameStateScript := preload("res://scripts/systems/game_state.gd")

## 断言总数；脚本报错会中断检查函数，最后用它兜住「报错却显示全绿」的假通过。
const EXPECTED_CHECKS := 25

var failures: int = 0
var checks_run: int = 0
var state
var quests
var stage
var player: Node3D
var arena: Area3D
var console: Node3D


## 只实现任务控制器需要的那一层：只读阶段序号 + 变化广播。
class FakeStage extends Node:
	signal stage_changed(index: int, phase: int)
	var index: int = 1

	func get_stage_index() -> int:
		return index

	func set_index(value: int) -> void:
		if index == value:
			return
		index = value
		stage_changed.emit(index, 0)


## 只为区域条件提供 zone_id 的替身，与正式 ZoneVolume 接口一致。
class FakeZone extends Area3D:
	@export var zone_id: StringName = &"arena"

	func _ready() -> void:
		add_to_group(&"zone_volume")


## 只为交互条件提供 interact_id 与信号的替身。
class FakeInteractable extends Node3D:
	signal interacted(interactable, player)
	@export var interact_id: StringName = &"console"

	func _ready() -> void:
		add_to_group(&"interactable")


func _initialize() -> void:
	call_deferred("run_checks")


func check(condition: bool, label_text: String) -> void:
	checks_run += 1
	if condition:
		print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)


func run_checks() -> void:
	await _build_world()
	_check_initial()
	_check_field_conditions()
	_check_item_and_interact_conditions()
	_check_zone_conditions_and_window()
	_check_expiry_terminal()
	_check_lock_window()
	_check_entries()
	_check_stage_readonly()
	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d（脚本报错会中断后续检查）" % [EXPECTED_CHECKS, checks_run])
	if failures == 0:
		print("quest system checks: all passed")
	else:
		print("quest system checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)


func _build_world() -> void:
	state = GameStateScript.new()
	state.name = "QuestSystemState"
	root.add_child(state)

	player = Node3D.new()
	player.name = "QuestSystemPlayer"
	player.add_to_group(&"player")
	root.add_child(player)

	arena = FakeZone.new()
	arena.name = "QuestSystemArena"
	arena.zone_id = &"arena"
	root.add_child(arena)

	console = FakeInteractable.new()
	console.name = "QuestSystemConsole"
	console.interact_id = &"console"
	root.add_child(console)

	stage = FakeStage.new()
	stage.name = "QuestSystemStage"
	root.add_child(stage)

	quests = QuestControllerScript.new()
	quests.name = "QuestSystemQuestController"
	quests.state_path = NodePath("/root/QuestSystemState")
	root.add_child(quests)
	quests.bind_stage(stage)
	quests.set_table(_build_table())
	await process_frame
	await process_frame


func _build_table() -> Resource:
	var table = StageTableScript.new()
	var definition = StageDefinitionScript.new()
	definition.index = 1
	definition.display_name = "任务一"
	definition.quest_id = &"main"
	table.stages.append(definition)

	var main_quest = QuestDefinitionScript.new()
	main_quest.id = &"main"
	main_quest.display_name = "主线"
	main_quest.stage_index = 1
	main_quest.accept_conditions.assign([QuestConditionScript.field(&"help_choice", "yes")])
	main_quest.refuse_conditions.assign([QuestConditionScript.field(&"help_choice", "no")])
	main_quest.complete_conditions.assign([
		QuestConditionScript.zone_entered(&"arena"),
		QuestConditionScript.zone_left(&"arena"),
	])
	table.quests.append(main_quest)

	# 需要拾取物品并交互过终端才接取的支线。
	var device_quest = QuestDefinitionScript.new()
	device_quest.id = &"device"
	device_quest.display_name = "设备"
	device_quest.stage_index = 1
	device_quest.accept_conditions.assign([
		QuestConditionScript.item(&"keycard", 1),
		QuestConditionScript.interacted(&"console"),
	])
	device_quest.complete_conditions.assign([QuestConditionScript.flag(&"device_fixed")])
	table.quests.append(device_quest)

	# 阶段 2 解锁、阶段 3 失效的限时支线。
	var timed_quest = QuestDefinitionScript.new()
	timed_quest.id = &"timed"
	timed_quest.display_name = "限时"
	timed_quest.stage_index = 1
	timed_quest.unlock_stage = 2
	timed_quest.expire_stage = 3
	timed_quest.accept_conditions.assign([QuestConditionScript.flag(&"timed_ready")])
	table.quests.append(timed_quest)
	return table


func _check_initial() -> void:
	check(quests.status_of(&"main") == QuestControllerScript.Status.NOT_STARTED, "任务初始为未接")
	check(not quests.is_locked(&"main"), "未填解锁阶段的任务默认可用")
	check(quests.is_locked(&"timed"), "解锁阶段 2 的任务在阶段 1 未解锁")


func _check_field_conditions() -> void:
	state.help_choice = "no"
	check(quests.status_of(&"main") == QuestControllerScript.Status.REFUSED, "状态字段命中拒绝条件")
	state.help_choice = "yes"
	check(quests.status_of(&"main") == QuestControllerScript.Status.IN_PROGRESS, "状态字段命中接取条件")


func _check_item_and_interact_conditions() -> void:
	check(quests.status_of(&"device") == QuestControllerScript.Status.NOT_STARTED, "条件不足时不接取支线")
	state.add_item(&"keycard", "门禁卡")
	check(quests.status_of(&"device") == QuestControllerScript.Status.NOT_STARTED, "只满足物品条件仍不接取")
	console.interacted.emit(console, player)
	check(quests.status_of(&"device") == QuestControllerScript.Status.IN_PROGRESS, "物品与交互条件都满足时接取")
	state.set_flag(&"device_fixed", true)
	check(quests.status_of(&"device") == QuestControllerScript.Status.COMPLETED, "旗标条件满足时完成")
	state.set_flag(&"device_fixed", false)
	check(quests.status_of(&"device") == QuestControllerScript.Status.COMPLETED, "已完成是终态，条件失效也不回退")


func _check_zone_conditions_and_window() -> void:
	check(quests.status_of(&"main") == QuestControllerScript.Status.IN_PROGRESS, "主线仍为进行中")
	arena.body_entered.emit(player)
	check(quests.status_of(&"main") == QuestControllerScript.Status.IN_PROGRESS, "只进入场地还不算完成")
	arena.body_exited.emit(player)
	check(quests.status_of(&"main") == QuestControllerScript.Status.COMPLETED, "进入并离开场地后完成")


func _check_expiry_terminal() -> void:
	state.set_flag(&"timed_ready", true)
	stage.set_index(2)
	check(quests.status_of(&"timed") == QuestControllerScript.Status.IN_PROGRESS, "进入解锁阶段后可接取")
	stage.set_index(3)
	check(quests.status_of(&"timed") == QuestControllerScript.Status.MISSED, "到达失效阶段转为已失效")
	stage.set_index(1)
	check(quests.status_of(&"timed") == QuestControllerScript.Status.MISSED, "已失效是终态，阶段回退也不恢复")
	stage.set_index(3)


func _check_lock_window() -> void:
	check(not quests.is_locked(&"timed"), "到达解锁阶段后任务不再锁定")
	check(quests.status_name(&"timed") == "已失效", "状态名回退为中文文本")


func _check_entries() -> void:
	var entries: Array = quests.get_quest_entries()
	check(entries.size() == 3, "查询返回表里全部任务")
	check(str(entries[0]["id"]) == "main", "同阶段任务保持表内顺序")
	check(str(entries[0]["name"]) == "主线", "查询返回任务名")
	check(str(entries[0]["status_name"]) == "已完成", "查询返回状态名")
	check(bool(entries[0]["locked"]) == false, "查询返回锁定标记")
	check(str(entries[1]["target_area"]) == "", "未填目标场地时返回空字符串")


func _check_stage_readonly() -> void:
	var methods: Array = []
	for entry in stage.get_method_list():
		methods.append(entry.get("name", ""))
	check(methods.has("get_stage_index") and not methods.has("set_player_in_zone"), "阶段替身只暴露只读序号接口")
