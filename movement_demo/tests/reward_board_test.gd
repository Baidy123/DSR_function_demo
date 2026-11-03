extends SceneTree

## 战斗奖励三选一面板检查：默认隐藏、暂停可处理、三按钮与说明文字、同轮只发一次信号。
## 运行：godot --headless --path movement_demo --script res://tests/reward_board_test.gd

const EXPECTED_CHECKS := 14

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
	var board: Node = load("res://scenes/ui/reward_board.tscn").instantiate()
	root.add_child(board)
	await process_frame

	check(not board.visible, "奖励面板默认隐藏")
	check(board.process_mode == Node.PROCESS_MODE_ALWAYS, "暂停时仍可处理输入")

	board.show_board()
	await process_frame
	check(board.visible, "show_board 显示面板")
	check(_text(board, "Panel/Margin/Content/Title") == "战斗奖励 · 三选一", "标题文字正确")
	check(_button_text(board, "Panel/Margin/Content/Buttons/FirstAid/Button") == "急救包", "急救包按钮文字正确")
	check(_button_text(board, "Panel/Margin/Content/Buttons/Ammo/Button") == "弹药补给", "弹药补给按钮文字正确")
	check(_button_text(board, "Panel/Margin/Content/Buttons/SystemProgress/Button") == "系统进度", "系统进度按钮文字正确")
	check(_label_text(board, "Panel/Margin/Content/Buttons/FirstAid/Description") == "恢复 35 点生命", "急救包说明正确")
	check(_label_text(board, "Panel/Margin/Content/Buttons/Ammo/Description") == "补满弹匣与备弹", "弹药补给说明正确")
	check(_label_text(board, "Panel/Margin/Content/Buttons/SystemProgress/Description") == "任务进度 +20", "系统进度说明正确")

	var selected: Array[StringName] = []
	board.reward_selected.connect(func(id: StringName) -> void: selected.append(id))
	check(board.select_reward(&"first_aid"), "首次选择急救包成功")
	check(selected == [&"first_aid"], "选择发出一致奖励id")
	check(not board.select_reward(&"ammo"), "同轮不能再次选择")
	check(selected.size() == 1, "重复选择不发第二次信号")

	board.queue_free()
	await process_frame

	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d（脚本报错会中断后续检查）" % [EXPECTED_CHECKS, checks_run])
	if failures == 0:
		print("reward board checks: all passed")
	else:
		print("reward board checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)


func _text(node: Node, path: String) -> String:
	var target: Control = node.get_node_or_null(path) as Control
	return "" if target == null else str(target.get("text"))


func _button_text(node: Node, path: String) -> String:
	var target: Button = node.get_node_or_null(path) as Button
	return "" if target == null else str(target.text)


func _label_text(node: Node, path: String) -> String:
	var target: Label = node.get_node_or_null(path) as Label
	return "" if target == null else str(target.text)
