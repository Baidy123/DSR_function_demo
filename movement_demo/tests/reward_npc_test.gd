extends SceneTree

## 酒馆奖励 NPC 闭环检查：第一关返回后由 NPC 打开三选一，且每个运行周期只能领取一次。
## 运行：godot --headless --path movement_demo --script res://tests/reward_npc_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")

const WATCHDOG_SECONDS := 30.0
const MAX_FRAMES := 120
const EXPECTED_CHECKS := 17

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
	var tree := scene.get_tree()
	await tree.process_frame
	await tree.process_frame

	var state := root.get_node("GameState")
	var quests := scene.get_node_or_null("QuestController")
	var reward_npc := scene.get_node_or_null("RewardNPC")
	var controller := scene.get_node_or_null("EncounterController")
	var board := scene.get_node_or_null("RewardBoard")
	var arena := scene.get_node_or_null("Arena")
	var player: CharacterBody3D = scene.get_node_or_null("Player")
	check(reward_npc != null, "酒馆奖励 NPC 已挂载")
	check(controller != null, "奖励控制器已挂载")
	check(board != null, "三选一面板已挂载")
	if failures > 0 or quests == null or reward_npc == null or controller == null or board == null or arena == null or player == null:
		_finish(scene)
		return

	state.help_choice = ""
	state.task_a_returned = ""
	state.set("task_a_reward_claimed", false)
	state.set("completed_level", 1)
	state.set("available_level", 1)
	state.system_progress = 0
	state.clear_interaction_state()
	quests.reset_progress()
	await tree.process_frame
	await tree.process_frame
	player.set_physics_process(false)
	player.global_position = reward_npc.global_position + Vector3(0.0, 0.0, 0.9)
	for _frame in range(8):
		await tree.physics_frame
	check(not board.visible, "奖励面板默认隐藏")
	var interaction_area: Area3D = reward_npc.get_node("InteractionArea")
	check(interaction_area.overlaps_body(player), "奖励 NPC 检测到附近玩家")

	arena.combat_cleared.emit(arena)
	await tree.process_frame
	await tree.process_frame
	check(not board.visible, "竞技场清场不再自动打开奖励")
	check(not tree.paused, "竞技场清场不再暂停游戏")

	state.help_choice = "accepted"
	await _wait_until(tree, func() -> bool: return quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS)
	state.task_a_returned = "returned"
	await _wait_until(tree, func() -> bool: return quests.status_of(&"task_a") == QuestControllerScript.Status.COMPLETED)
	check(quests.status_of(&"task_a") == QuestControllerScript.Status.COMPLETED, "返回酒馆后任务已完成")
	check(controller.can_offer_reward(), "完成后奖励可领取")

	_press_interact()
	await tree.process_frame
	await tree.process_frame
	check(board.visible and tree.paused, "完成后与奖励 NPC 交互打开三选一并暂停")

	check(controller.select_reward(&"system_progress"), "可选择系统进度奖励")
	check(int(state.system_progress) == 20, "所选奖励正常结算")
	check(bool(state.get("task_a_reward_claimed")), "领取状态写入共享运行态")
	check(not board.visible and not tree.paused, "结算后关闭面板并恢复游戏")

	_press_interact()
	await tree.process_frame
	await tree.process_frame
	check(not board.visible and not tree.paused, "同一 NPC 不能重复打开奖励")

	var previous_progress: int = state.system_progress
	await _close_scene(scene)
	var reloaded: Node = MAIN_SCENE.instantiate()
	root.add_child(reloaded)
	current_scene = reloaded
	await process_frame
	await process_frame
	var reloaded_player: CharacterBody3D = reloaded.get_node("Player")
	var reloaded_npc: Node3D = reloaded.get_node("RewardNPC")
	reloaded_player.set_physics_process(false)
	reloaded_player.global_position = reloaded_npc.global_position + Vector3(0.0, 0.0, 0.9)
	await physics_frame
	await physics_frame
	_press_interact()
	await process_frame
	await process_frame
	check(not reloaded.get_node("RewardBoard").visible and int(state.system_progress) == previous_progress,
		"酒馆重载后奖励仍不可重复领取")
	state.completed_level = 2
	await process_frame
	await process_frame
	_press_interact()
	await process_frame
	await process_frame
	check(reloaded.get_node("RewardBoard").visible and paused,
		"第1关已领取不死锁，第2关返回后仍可打开三选一")

	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d（脚本报错会中断后续检查）" % [EXPECTED_CHECKS, checks_run])
	_finish(reloaded)


func _press_interact() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	root.push_input(event)
	Input.flush_buffered_events()


func _wait_until(tree: SceneTree, predicate: Callable) -> bool:
	for _frame in range(MAX_FRAMES):
		if predicate.call():
			return true
		await tree.process_frame
	return false


func _close_scene(scene: Node) -> void:
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
	push_error("reward npc test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish(scene: Node) -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(scene):
		scene.get_tree().paused = false
		scene.queue_free()
	if failures == 0:
		print("reward npc checks: all passed")
	else:
		print("reward npc checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)
