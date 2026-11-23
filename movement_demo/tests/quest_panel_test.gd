extends SceneTree

## 任务面板检查：列出全部任务与状态、随任务变化刷新、空表占位与输入不抢占。
## 运行：godot --headless --path movement_demo --script res://tests/quest_panel_test.gd

## 断言总数；脚本报错会中断检查函数，最后用它兜住「报错却显示全绿」的假通过。
const EXPECTED_CHECKS := 21

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
	root.get_node("GameState").set_flag(&"has_mind_access_device", false)
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
	check(not _is_open(panel), "任务面板默认隐藏")
	check(_tab_is_bound(), "Tab 已绑定到任务面板切换动作")
	check(not panel.has_node("Panel/Margin/Content/SystemProgress"), "任务面板已移除旧进度节点")
	check(panel.find_children("*", "ProgressBar", true, false).is_empty(), "任务面板不显示数值进度条")
	await _press_tab(panel)
	check(_is_open(panel), "按 Tab 显示任务面板")
	check(_text(panel).contains("暂无任务"), "没有任务控制器时显示占位文本")
	check(panel.is_in_group(&"quest_panel"), "面板加入 quest_panel 组")
	var container: Control = panel.get_node("Panel")
	check(container.mouse_filter == Control.MOUSE_FILTER_IGNORE, "面板不接收鼠标事件")
	var state: Node = root.get_node("GameState")
	var flag_events: Array = []
	var record_flag := func(key: StringName, value: bool) -> void:
		flag_events.append([key, value])
	state.flag_changed.connect(record_flag)
	state.grant_shop_flag(&"has_mind_access_device")
	await process_frame
	check(state.get_flag(&"has_mind_access_device"), "商品通过旗标表示拥有")
	check(
		flag_events == [[&"has_mind_access_device", true]],
		"商品旗标变化发出布尔信号"
	)
	state.set_flag(&"has_mind_access_device")
	await process_frame
	check(flag_events.size() == 1 and _text(panel).contains("暂无任务"), "重复置位不重复通知且不改变任务列表")
	state.flag_changed.disconnect(record_flag)
	await _press_tab(panel)
	check(not _is_open(panel), "再次按 Tab 隐藏任务面板")
	panel.queue_free()
	await process_frame


func _check_live_scene() -> void:
	root.get_node("GameState").set_flag(&"has_mind_access_device", false)
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
	check(not _is_open(panel), "主场景任务面板初始隐藏")
	await _press_tab(panel)
	check(_is_open(panel), "主场景按 Tab 显示任务面板")
	var quests = get_first_node_in_group(&"quest_controller")
	check(quests != null and quests.get_quest_entries().size() >= 1, "主场景配置表里已有任务")
	check(_text(panel).contains("通关第1关"), "面板列出第1关通关任务")
	check(_text(panel).contains("未接"), "面板显示未接状态")

	var state = root.get_node("GameState")
	state.help_choice = "accepted"
	await process_frame
	check(_text(panel).contains("进行中"), "任务状态变化后面板刷新")
	state.grant_shop_flag(&"has_mind_access_device")
	await process_frame
	check(state.get_flag(&"has_mind_access_device") and panel.find_children("*", "ProgressBar", true, false).is_empty(), "获得商品不再创建任务进度条")
	await _press_tab(panel)
	check(not _is_open(panel), "主场景再次按 Tab 隐藏任务面板")
	scene.queue_free()
	await process_frame


func _text(panel: Node) -> String:
	return panel.get_node("Panel/Margin/Content/QuestList").text


func _is_open(panel: Node) -> bool:
	return (panel.get_node("Panel") as Control).visible


func _press_tab(panel: Node) -> void:
	panel.toggle()
	await process_frame


func _tab_is_bound() -> bool:
	if not InputMap.has_action(&"toggle_quest_panel"):
		return false
	for event in InputMap.action_get_events(&"toggle_quest_panel"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_TAB:
			return true
	return false
