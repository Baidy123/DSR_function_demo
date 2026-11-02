extends SceneTree

## 每关奖励：逐关开放、逐关记录领取，并读取可独立调整的关卡奖励配置。
## 运行：godot --headless --path movement_demo --script res://tests/reward_per_level_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")

const WATCHDOG_SECONDS := 30.0
const EXPECTED_CHECKS := 39

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
	var board: CanvasLayer = scene.get_node("RewardBoard")
	var player: CharacterBody3D = scene.get_node("Player")
	var health: CanvasLayer = player.get_node("Health")
	state.help_choice = "accepted"
	await _wait_until(func() -> bool:
		return quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS)
	_reset_rewards(state)
	await process_frame

	check(controller.get("reward_table") != null, "奖励控制器挂载五关奖励配置")
	for level in range(1, 6):
		state.completed_level = level
		state.available_level = level
		await process_frame
		check(controller.can_offer_reward(), "第%d关返回后可领取本关奖励" % level)
		check(controller.open_reward_for_player(player), "第%d关奖励 NPC 可打开三选一" % level)
		check(board.visible and board._buttons.size() == 3, "第%d关动态显示三个奖励" % level)
		check(controller.select_reward(&"first_aid"), "第%d关可选择奖励并结算一次" % level)
		check(bool(state.call("has_claimed_reward", level)), "第%d关领取状态独立记录" % level)
		check(not controller.can_offer_reward(), "第%d关领取后不能重复领取" % level)

	_reset_rewards(state)
	var custom_table := load("res://resources/rewards/level_rewards.tres").duplicate(true)
	var level_two = custom_table.call("for_level", 2)
	check(level_two != null and level_two.options.size() == 3, "第2关提供独立三项配置")
	if level_two != null and level_two.options.size() == 3:
		var heal_option = level_two.options[0]
		heal_option.display_name = "战术急救"
		heal_option.description = "恢复 7 点生命"
		heal_option.amount = 7
	controller.reward_table = custom_table
	state.completed_level = 2
	state.available_level = 2
	health.health = 20.0
	health._update_display()
	await process_frame
	check(controller.open_reward_for_player(player), "可读取第2关独立奖励配置")
	check(board._buttons[0].text == "战术急救", "奖励按钮标题来自关卡配置")
	check(board.get_node("Panel/Margin/Content/Buttons/FirstAid/Description").text == "恢复 7 点生命",
		"奖励说明来自关卡配置")
	check(controller.select_reward(&"first_aid"), "选择配置后的急救奖励成功")
	check(is_equal_approx(health.health, 27.0), "奖励数值使用关卡配置")
	check(bool(state.call("has_claimed_reward", 2)), "配置奖励后记录第2关已领取")
	check(not bool(state.call("has_claimed_reward", 1)), "第2关领取不会记为第1关领取")

	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d（脚本报错会中断后续检查）" % [EXPECTED_CHECKS, checks_run])
	_finish(scene)


func _reset_rewards(state: Node) -> void:
	if state.has_method(&"reset_reward_claims"):
		state.call("reset_reward_claims")
	else:
		state.set("claimed_reward_levels", {})
	state.task_a_reward_claimed = false
	state.system_progress = 0


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
	push_error("reward per level test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish(scene: Node) -> void:
	if _finished:
		return
	_finished = true
	paused = false
	if is_instance_valid(scene):
		scene.queue_free()
	if failures == 0:
		print("reward per level checks: all passed")
	else:
		print("reward per level checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)
