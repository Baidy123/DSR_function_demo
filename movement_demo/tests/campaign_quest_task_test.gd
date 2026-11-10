extends SceneTree

## 五关任务与奖励资格：任务随 A 解锁/关卡完成更新，商店消费固定货币奖励。
## 运行：godot --headless --path movement_demo --script res://tests/campaign_quest_task_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")

const WATCHDOG_SECONDS := 30.0
const EXPECTED_CHECKS := 32

var failures := 0
var checks_run := 0
var _finished := false


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label_text: String) -> void:
	checks_run += 1
	if condition:
		print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)


func _run() -> void:
	create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(_on_watchdog)
	var scene: Node = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var state := root.get_node("GameState")
	var quests: Node = scene.get_node("QuestController")
	var shop_controller: Node = scene.get_node_or_null("ShopController")
	var shop_board: Node = scene.get_node_or_null("ShopBoard")
	state.help_choice = ""
	state.completed_level = 0
	state.available_level = 1
	state.task_a_returned = ""
	state.task_a_reward_claimed = false
	state.money = 0
	state.rewarded_task_ids = {}
	quests.reset_progress()
	await process_frame
	await process_frame
	check(shop_controller != null, "ShopController is mounted")
	check(shop_board != null, "ShopBoard is mounted")
	check(shop_controller != null and shop_controller.has_method(&"purchase"),
		"ShopController exposes purchase")

	var names: Dictionary = {}
	for entry in quests.get_quest_entries():
		names[StringName(entry["id"])] = str(entry["name"])
	check(names.get(&"task_a", "") == "通关第1关", "第一条主线任务名为通关第1关")
	for number in range(2, 6):
		check(names.get(StringName("task_level_%d" % number), "") == "通关第%d关" % number,
			"第%d关主线任务已登记" % number)

	state.help_choice = "accepted"
	await _wait_until(func() -> bool:
		return quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS)
	check(quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS, "接受 A 后通关第1关任务进行中")
	check(quests.status_of(&"task_level_2") == QuestControllerScript.Status.NOT_STARTED,
		"第2关任务在 A 解锁前未开始")

	state.completed_level = 1
	await process_frame
	check(quests.status_of(&"task_a") == QuestControllerScript.Status.COMPLETED, "完成第1关后第1关任务完成")
	check(state.money == 100, "完成第1关后任务奖励 100")
	check(shop_controller != null, "第1关返回后商店入口可用")
	check(quests.status_of(&"task_level_2") == QuestControllerScript.Status.NOT_STARTED,
		"仅完成第1关不会自动开始第2关任务")

	state.completed_level = 0
	await process_frame
	state.completed_level = 1
	await process_frame
	check(state.money == 100, "重新评估第1关完成不重复发钱")

	state.available_level = 2
	await process_frame
	check(quests.status_of(&"task_level_2") == QuestControllerScript.Status.IN_PROGRESS,
		"A 解锁第2关后第2关任务进行中")

	state.completed_level = 2
	await process_frame
	check(quests.status_of(&"task_level_2") == QuestControllerScript.Status.COMPLETED,
		"完成第2关后第2关任务完成")
	check(state.money == 200, "完成第2关后任务奖励累计到 200")
	check(shop_controller != null, "完成第2关后商店入口可用")
	check(not bool(state.task_a_reward_claimed), "第2关奖励资格不伪造第1关领取状态")

	for number in range(3, 6):
		state.available_level = number
		await process_frame
		check(quests.status_of(StringName("task_level_%d" % number)) == QuestControllerScript.Status.IN_PROGRESS,
			"A 解锁第%d关后任务进行中" % number)
		state.completed_level = number
		await process_frame
		check(quests.status_of(StringName("task_level_%d" % number)) == QuestControllerScript.Status.COMPLETED,
			"完成第%d关后任务完成" % number)
		check(state.money == number * 100, "完成第%d关后任务奖励累计到 %d" % [number, number * 100])
	check(quests.status_of(&"task_level_5") == QuestControllerScript.Status.COMPLETED, "五关任务最终全部完成")
	check(state.money == 500, "五关主线任务奖励合计 500")
	check(shop_controller != null, "完成全部关卡后商店入口仍可用")

	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d（脚本报错会中断后续检查）" % [EXPECTED_CHECKS, checks_run])
	_finish(scene)


func _wait_until(predicate: Callable) -> bool:
	for _frame in range(120):
		if predicate.call():
			return true
		await process_frame
	return false


func _on_watchdog() -> void:
	if _finished:
		return
	_finished = true
	paused = false
	push_error("campaign quest task test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish(scene: Node) -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(scene):
		scene.queue_free()
	if failures == 0:
		print("campaign quest task checks: all passed")
	else:
		print("campaign quest task checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)
