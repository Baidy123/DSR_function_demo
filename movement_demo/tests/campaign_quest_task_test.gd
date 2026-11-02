extends SceneTree

## 五关任务与奖励资格：任务随 A 解锁/关卡完成更新，奖励只在第1关接口可领取。
## 运行：godot --headless --path movement_demo --script res://tests/campaign_quest_task_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")

const WATCHDOG_SECONDS := 30.0
const EXPECTED_CHECKS := 22

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
	var controller: Node = scene.get_node("EncounterController")
	state.help_choice = ""
	state.completed_level = 0
	state.available_level = 1
	state.task_a_returned = ""
	state.task_a_reward_claimed = false
	quests.reset_progress()
	await process_frame
	await process_frame

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
	check(controller.can_offer_reward(), "第1关返回后奖励仍可领取")
	check(quests.status_of(&"task_level_2") == QuestControllerScript.Status.NOT_STARTED,
		"仅完成第1关不会自动开始第2关任务")

	state.available_level = 2
	await process_frame
	check(quests.status_of(&"task_level_2") == QuestControllerScript.Status.IN_PROGRESS,
		"A 解锁第2关后第2关任务进行中")

	state.completed_level = 2
	await process_frame
	check(quests.status_of(&"task_level_2") == QuestControllerScript.Status.COMPLETED,
		"完成第2关后第2关任务完成")
	check(controller.can_offer_reward(), "完成第2关后可领取本关奖励")
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
	check(quests.status_of(&"task_level_5") == QuestControllerScript.Status.COMPLETED, "五关任务最终全部完成")
	check(controller.can_offer_reward(), "完成全部关卡后仍可领取第5关奖励")

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
