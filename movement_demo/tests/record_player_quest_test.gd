extends SceneTree

## 唱片机支线闭环检查：接取前后都能操作唱片机、接取前操作不推进任务、关闭状态交差失败、
## 拒绝只影响对话且可重新接取。
## 运行：godot --headless --path movement_demo --script res://tests/record_player_quest_test.gd

const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")

## 断言总数；脚本报错会中断检查函数，最后用它兜住「报错却显示全绿」的假通过。
const EXPECTED_CHECKS := 25

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

	_reset(state, quests)
	_check_usable_before_accept(record, player, state, quests, scene)
	await _check_accept_close_and_turnin(ui, player, record, state, quests, scene)
	await _check_refusal(ui, player, state, quests, scene)
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


## 回到「没接过唱片机任务」的初始状态；场景重跑时上一轮数据可能残留。
func _reset(state, quests) -> void:
	quests.reset_progress()
	state.music_quest_choice = ""
	state.music_quest_turnin = ""
	state.set_flag(&"music_playing", false)


func _check_usable_before_accept(record, player, state, quests, scene) -> void:
	check(record.interact(player), "接取前也能操作唱片机")
	check(state.is_flag_set(&"music_playing"), "接取前操作照常打开音乐")
	check(record.interact(player), "接取前唱片机可以再次操作")
	check(not state.is_flag_set(&"music_playing"), "接取前第二次操作回到关闭")
	check(quests.status_of(&"task_music") == QuestControllerScript.Status.NOT_STARTED, "接取前操作不推进任务状态")
	check(_panel_text(scene).contains("打开唱片机：未接"), "接取前任务面板显示未接")


func _check_accept_close_and_turnin(ui, player, record, state, quests, scene) -> void:
	state.music_quest_choice = "accepted"
	check(quests.status_of(&"task_music") == QuestControllerScript.Status.IN_PROGRESS, "接取后任务进入进行中")
	check(_panel_text(scene).contains("打开唱片机：进行中"), "接取后任务面板显示进行中")

	# 此刻唱片机是关着的：交差不该成功。
	await _open_b(player, ui)
	check(ui.dialogue_text.text.contains("没响"), "关闭状态下交差对话提示没响")
	check(_choice_index(ui, "交差") < 0, "关闭状态下没有交差选项")
	ui._close_dialogue()
	await process_frame
	check(quests.status_of(&"task_music") == QuestControllerScript.Status.IN_PROGRESS, "关闭状态下任务保持进行中")

	check(record.interact(player), "接取后可以打开唱片机")
	check(state.is_flag_set(&"music_playing"), "打开后音乐旗标为真")

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
	check(_panel_text(scene).contains("打开唱片机：已完成"), "任务面板显示已完成")


func _check_refusal(ui, player, state, quests, scene) -> void:
	_reset(state, quests)
	await _open_b(player, ui)
	check(ui.choices.get_child_count() > 0, "复位后 B 重新提供任务")
	await _pick(ui, "现在不行")
	check(state.music_quest_choice == "refused", "拒绝写下 refusal 供对话分支使用")
	check(quests.status_of(&"task_music") == QuestControllerScript.Status.NOT_STARTED, "拒绝不改变任务状态")
	ui._close_dialogue()
	await process_frame
	check(_panel_text(scene).contains("打开唱片机：未接"), "拒绝后任务面板仍显示未接")

	await _open_b(player, ui)
	check(ui.dialogue_text.text.contains("想通了再找我"), "拒绝后再对话仍保持拒绝对话")
	check(ui.choices.get_child_count() > 0, "拒绝对话里给出重新接取的入口")
	await _pick(ui, "我改主意了")
	check(quests.status_of(&"task_music") == QuestControllerScript.Status.IN_PROGRESS, "可以重新接取任务")
	check(_panel_text(scene).contains("打开唱片机：进行中"), "重新接取后面板显示进行中")
	ui._close_dialogue()
	await process_frame

	# 已交差状态下 B 只有一句台词；player_health_ui_test 用这个状态当「普通对话」夹具。
	state.music_quest_turnin = "done"
	await _open_b(player, ui)
	check(
		ui.choices.get_child_count() == 0 and not ui.dialogue_text.text.is_empty(),
		"已交差状态下 B 只有一句无选项台词"
	)
	ui._close_dialogue()
	await process_frame


func _open_b(player, ui) -> void:
	await ui.open_dialogue(player, load("res://resources/dialogue/npc_b.dialogue"), "start")
	await process_frame


## 点选包含关键字的选项，等 ink 的 mutation 与下一句都跑完。
func _pick(ui, keyword: String) -> void:
	var index := _choice_index(ui, keyword)
	if index >= 0:
		ui.choices.get_child(index).pressed.emit()
	await process_frame
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
