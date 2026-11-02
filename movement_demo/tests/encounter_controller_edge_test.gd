extends SceneTree

## 酒馆奖励控制器边界检查：任务未完成、死亡、缺少面板、外部暂停和重复领取。
## 运行：godot --headless --path movement_demo --script res://tests/encounter_controller_edge_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")

const WATCHDOG_SECONDS := 30.0
const MAX_FRAMES := 120
const EXPECTED_CHECKS := 19

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
	await _check_requires_completed_quest()
	await _check_dead_player_rejected()
	await _check_missing_board()
	await _check_non_owner_pause()
	await _check_duplicate_claim()
	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d（脚本报错会中断后续检查）" % [EXPECTED_CHECKS, checks_run])
	_finish()


func _check_requires_completed_quest() -> void:
	var context := await _prepare_scene()
	var scene: Node = context["scene"]
	var tree: SceneTree = context["tree"]
	var quests: Node = context["quests"]
	var player: CharacterBody3D = context["player"]
	var controller: Node = context["controller"]
	var board: Node = context["board"]

	context["state"].help_choice = "accepted"
	await _wait_until(tree, func() -> bool:
		return quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS)
	check(not controller.can_offer_reward(), "任务进行中不能领取结算奖励")
	check(not controller.open_reward_for_player(player), "任务进行中拒绝打开面板")
	check(not board.visible and not tree.paused, "拒绝时不显示面板也不暂停")
	await _release(scene)


func _check_dead_player_rejected() -> void:
	var context := await _prepare_completed_scene()
	var scene: Node = context["scene"]
	var tree: SceneTree = context["tree"]
	var player: CharacterBody3D = context["player"]
	var health: CanvasLayer = context["health"]
	var controller: Node = context["controller"]
	var board: Node = context["board"]

	health.receive_hit(100000.0)
	check(player.is_dead(), "真实伤害使玩家死亡")
	check(not controller.open_reward_for_player(player), "死亡玩家不能领取奖励")
	check(not board.visible, "死亡玩家不显示奖励面板")
	check(tree.paused, "死亡暂停保持不变")
	await _release(scene)


func _check_missing_board() -> void:
	var context := await _prepare_completed_scene()
	var scene: Node = context["scene"]
	var tree: SceneTree = context["tree"]
	var player: CharacterBody3D = context["player"]
	var controller: Node = context["controller"]

	controller.reward_board = null
	check(not controller.open_reward_for_player(player), "缺少面板时拒绝打开")
	check(not tree.paused, "缺少面板时不暂停")
	await _release(scene)


func _check_non_owner_pause() -> void:
	var context := await _prepare_completed_scene()
	var scene: Node = context["scene"]
	var tree: SceneTree = context["tree"]
	var player: CharacterBody3D = context["player"]
	var health: CanvasLayer = context["health"]
	var controller: Node = context["controller"]
	var board: Node = context["board"]

	health.receive_hit(50.0)
	var health_before: float = health.health
	tree.paused = true
	check(controller.open_reward_for_player(player), "外部暂停时仍可由调用方打开奖励")
	check(board.visible, "外部暂停时奖励面板可见")
	check(controller.select_reward(&"first_aid"), "外部暂停时选择奖励成功")
	check(health.health > health_before, "外部暂停时奖励正常结算")
	check(tree.paused, "不解除控制器未持有的暂停")
	await _release(scene)


func _check_duplicate_claim() -> void:
	var context := await _prepare_completed_scene()
	var scene: Node = context["scene"]
	var player: CharacterBody3D = context["player"]
	var state: Node = context["state"]
	var controller: Node = context["controller"]

	check(controller.open_reward_for_player(player), "未领取时打开奖励")
	check(controller.select_reward(&"system_progress"), "首次选择成功")
	check(bool(state.task_a_reward_claimed), "共享运行态记录已领取")
	check(not controller.select_reward(&"ammo"), "当前面板不能重复提交")
	check(not controller.open_reward_for_player(player), "已领取后不能再次打开")
	await _release(scene)


func _prepare_completed_scene() -> Dictionary:
	var context := await _prepare_scene()
	var tree: SceneTree = context["tree"]
	var quests: Node = context["quests"]
	var state: Node = context["state"]
	state.help_choice = "accepted"
	await _wait_until(tree, func() -> bool:
		return quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS)
	state.task_a_returned = "returned"
	await _wait_until(tree, func() -> bool:
		return quests.status_of(&"task_a") == QuestControllerScript.Status.COMPLETED)
	return context


func _prepare_scene() -> Dictionary:
	var scene: Node = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	var tree := scene.get_tree()
	await tree.process_frame
	await tree.process_frame

	var state: Node = root.get_node("GameState")
	var quests: Node = scene.get_node("QuestController")
	var player: CharacterBody3D = scene.get_node("Player")
	state.help_choice = ""
	state.task_a_returned = ""
	state.task_a_reward_claimed = false
	state.system_progress = 0
	state.clear_interaction_state()
	quests.reset_progress()
	player.set_physics_process(false)
	await tree.process_frame
	await tree.process_frame
	return {
		"scene": scene,
		"tree": tree,
		"state": state,
		"quests": quests,
		"player": player,
		"health": player.get_node("Health"),
		"controller": scene.get_node("EncounterController"),
		"board": scene.get_node("RewardBoard"),
	}


func _wait_until(tree: SceneTree, predicate: Callable) -> bool:
	for _frame in range(MAX_FRAMES):
		if predicate.call():
			return true
		await tree.process_frame
	return false


func _release(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.get_tree().paused = false
		scene.queue_free()
	current_scene = null
	await process_frame


func _on_watchdog() -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(current_scene):
		current_scene.get_tree().paused = false
	push_error("encounter controller edge test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(current_scene):
		current_scene.get_tree().paused = false
		current_scene.queue_free()
	if failures == 0:
		print("encounter controller edge checks: all passed")
	else:
		print("encounter controller edge checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)
