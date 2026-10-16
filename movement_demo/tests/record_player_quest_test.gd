extends SceneTree

## 唱片机支线闭环检查：接取前交互不完成任务、点两次关闭、关闭状态下交差失败、重开后完成。
## 运行：godot --headless --path movement_demo --script res://tests/record_player_quest_test.gd

const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")

## 断言总数；脚本报错会中断检查函数，最后用它兜住「报错却显示全绿」的假通过。
const EXPECTED_CHECKS := 15

var failures: int = 0
var checks_run: int = 0


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
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var player: Node3D = scene.get_node("Player")
	var record = scene.get_node("Interactables/RecordPlayer")
	var quests = get_first_node_in_group(&"quest_controller")
	var state = root.get_node("GameState")
	var ui = scene.get_node("DialogueUI")

	# 场景重跑时上一次的对话状态可能残留，这里显式归零。
	state.music_quest_choice = ""
	state.music_quest_turnin = ""
	state.set_flag(&"music_playing", false)
	quests.reset_progress()

	check(record.interact(player), "接取前可以点击唱片机")
	check(state.is_flag_set(&"music_playing"), "第一次交互打开唱片机")
	check(quests.status_of(&"task_music") == QuestControllerScript.Status.NOT_STARTED, "接取前交互不完成任务")
	check(record.interact(player), "唱片机可以再次交互")
	check(not state.is_flag_set(&"music_playing"), "第二次交互回到关闭状态")
	check(quests.status_of(&"task_music") == QuestControllerScript.Status.NOT_STARTED, "关闭后任务仍未接取")

	state.music_quest_choice = "accepted"
	check(quests.status_of(&"task_music") == QuestControllerScript.Status.IN_PROGRESS, "对话选择接取后进入进行中")

	await _open_b(player, ui)
	check(ui.dialogue_text.text.contains("没响"), "关闭状态下交差对话提示没响")
	check(_choice_index(ui, "交差") < 0, "关闭状态下没有交差选项")
	ui._close_dialogue()
	await process_frame
	check(quests.status_of(&"task_music") == QuestControllerScript.Status.IN_PROGRESS, "关闭状态下任务保持进行中")

	record.interact(player)
	check(state.is_flag_set(&"music_playing"), "重新打开唱片机")

	await _open_b(player, ui)
	var turn_in := _choice_index(ui, "交差")
	check(turn_in >= 0, "播放状态下出现交差选项")
	if turn_in >= 0:
		ui.choices.get_child(turn_in).pressed.emit()
		await process_frame
		await process_frame
	check(quests.status_of(&"task_music") == QuestControllerScript.Status.COMPLETED, "交差后任务完成")
	ui._close_dialogue()
	await process_frame

	# 拒绝状态下 B 只给一句无选项台词；player_health_ui_test 用这个状态当「普通对话」夹具。
	state.music_quest_turnin = ""
	state.music_quest_choice = "refused"
	await _open_b(player, ui)
	check(
		ui.choices.get_child_count() == 0 and ui.dialogue_text.text.contains("想通了再找我"),
		"拒绝状态下 B 只有一句无选项台词"
	)
	ui._close_dialogue()
	await process_frame

	check(_panel_text(scene).contains("打开唱片机：已完成"), "任务面板显示已完成")
	scene.queue_free()
	await process_frame
	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d（脚本报错会中断后续检查）" % [EXPECTED_CHECKS, checks_run])
	if failures == 0:
		print("record player quest checks: all passed")
	else:
		print("record player quest checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)


func _open_b(player, ui) -> void:
	await ui.open_dialogue(player, load("res://resources/dialogue/npc_b.dialogue"), "start")
	await process_frame


func _choice_index(ui, keyword: String) -> int:
	var children: Array = ui.choices.get_children()
	for index in children.size():
		if children[index].text.contains(keyword):
			return index
	return -1


func _panel_text(scene: Node) -> String:
	var panel = scene.get_node("QuestPanel")
	return panel.get_node("Panel/Margin/Content/QuestList").text
