extends SceneTree

## 任务面板检查：列出全部任务与状态、随任务变化刷新、空表占位与输入不抢占。
## 运行：godot --headless --path movement_demo --script res://tests/quest_panel_test.gd

## 断言总数；脚本报错会中断检查函数，最后用它兜住「报错却显示全绿」的假通过。
const EXPECTED_CHECKS := 8

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
	await _check_empty_placeholder()
	await _check_live_scene()
	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d（脚本报错会中断后续检查）" % [EXPECTED_CHECKS, checks_run])
	if failures == 0:
		print("quest panel checks: all passed")
	else:
		print("quest panel checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)


func _check_empty_placeholder() -> void:
	var panel: Node = load("res://scenes/ui/quest_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	check(_text(panel) == "暂无任务", "没有任务控制器时显示占位文本")
	check(panel.is_in_group(&"quest_panel"), "面板加入 quest_panel 组")
	var container: Control = panel.get_node("Panel")
	check(container.mouse_filter == Control.MOUSE_FILTER_IGNORE, "面板不接收鼠标事件")
	panel.queue_free()
	await process_frame


func _check_live_scene() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	scene.add_child(load("res://scenes/ui/quest_panel.tscn").instantiate())
	root.add_child(scene)
	await process_frame
	await process_frame
	await process_frame

	var panel: Node = get_first_node_in_group(&"quest_panel")
	check(panel != null, "独立装配的任务面板已接入控制器")
	if panel == null:
		scene.queue_free()
		return
	var quests = get_first_node_in_group(&"quest_controller")
	check(quests != null and quests.get_quest_entries().size() >= 1, "主场景配置表里已有任务")
	check(_text(panel).contains("帮 A 的忙"), "面板列出主线任务")
	check(_text(panel).contains("未接"), "面板显示未接状态")

	var state = root.get_node("GameState")
	state.help_choice = "accepted"
	await process_frame
	check(_text(panel).contains("进行中"), "任务状态变化后面板刷新")
	scene.queue_free()
	await process_frame


func _text(panel: Node) -> String:
	return panel.get_node("Panel/Margin/Content/QuestList").text
