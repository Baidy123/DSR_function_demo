extends SceneTree

## 任务奖励三选一集成检查：竞技场清场不结算，返回酒馆后由奖励 NPC 结算三种奖励。
## 运行：godot --headless --path movement_demo --script res://tests/quest_encounter_loop_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")

const WATCHDOG_SECONDS := 30.0
const MAX_FRAMES := 120
const HEAL_AMOUNT := 35.0
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
	await _check_main_npc_flow()
	await _check_ammo_reward_path()
	await _check_system_progress_reward_path()
	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d（脚本报错会中断后续检查）" % [EXPECTED_CHECKS, checks_run])
	_finish(null)


func _check_main_npc_flow() -> void:
	var context := await _prepare_reward_ready()
	var scene: Node = context["scene"]
	var tree: SceneTree = context["tree"]
	var state: Node = context["state"]
	var quests: Node = context["quests"]
	var stage: Node = context["stage"]
	var player: CharacterBody3D = context["player"]
	var controller: Node = context["controller"]
	var board: Node = context["board"]
	var arena: Node = context["arena"]
	var health: CanvasLayer = player.get_node("Health")

	check(scene.get_node_or_null("Arena/CombatZone/ReturnPortal") == null, "旧竞技场返回传送门已移除")
	arena.combat_cleared.emit(arena)
	await tree.process_frame
	await tree.process_frame
	check(not board.visible and not tree.paused, "竞技场清场不再自动结算")

	health.receive_hit(50.0)
	await tree.process_frame
	var health_before: float = health.health
	_press_interact()
	await tree.process_frame
	await tree.process_frame
	check(board.visible and tree.paused, "返回酒馆后奖励 NPC 打开三选一")
	check(quests.status_of(&"task_a") == QuestControllerScript.Status.COMPLETED, "领取时任务保持已完成")
	check(stage.get_stage_index() == 2 and quests.status_of(&"task_level_2") == QuestControllerScript.Status.NOT_STARTED,
		"领取时主线推进到第2关任务且尚未由 A 接取")

	var reward_ids: Array = board.REWARD_IDS
	check(reward_ids == [&"first_aid", &"ammo", &"system_progress"], "面板保留三项奖励")
	check(controller.select_reward(&"first_aid"), "选择急救包奖励成功")
	check(is_equal_approx(health.health, minf(health.max_health, health_before + HEAL_AMOUNT)),
		"急救包恢复 35 点生命")
	check(not board.visible and not tree.paused, "奖励后面板关闭并解除暂停")
	check(bool(state.task_a_reward_claimed), "急救包领取状态已记录")
	check(not controller.open_reward_for_player(player), "已领取后不能再次打开")
	await _close_scene(scene)


func _check_ammo_reward_path() -> void:
	var context := await _prepare_reward_ready()
	var scene: Node = context["scene"]
	var tree: SceneTree = context["tree"]
	var player: CharacterBody3D = context["player"]
	var controller: Node = context["controller"]
	var board: Node = context["board"]
	var slots: Node = player.get_node("Equipment")

	slots.select_slot(1)
	slots.select_slot(0)
	for slot in range(2):
		var ammo_state = slots._ammo_states[slot]
		if ammo_state != null:
			ammo_state.magazine_rounds = 0
			ammo_state.is_reloading = true
	for ammo_type in slots.reserve_ammo.keys():
		slots.reserve_ammo[ammo_type] = 0

	_press_interact()
	await tree.process_frame
	await tree.process_frame
	check(board.visible and tree.paused, "弹药奖励：NPC 打开三选一")
	check(controller.select_reward(&"ammo"), "弹药奖励：选择成功")
	check(
		slots.reserve_ammo[&"rifle"] == slots.starting_rifle_ammo
		and slots.reserve_ammo[&"pistol"] == slots.starting_pistol_ammo
		and slots.reserve_ammo[&"smg"] == slots.starting_smg_ammo
		and slots.reserve_ammo[&"shotgun"] == slots.starting_shotgun_ammo,
		"弹药奖励：四类备弹恢复初始值"
	)
	var magazines_refilled := true
	for slot in range(2):
		var data = slots._weapon_at(slot)
		var ammo_state = slots._ammo_states[slot]
		if data != null:
			magazines_refilled = magazines_refilled and ammo_state != null \
				and ammo_state.magazine_rounds == data.magazine_capacity \
				and not ammo_state.is_reloading
	check(magazines_refilled, "弹药奖励：已初始化弹匣补满并取消换弹")
	check(not board.visible and not tree.paused, "弹药奖励：面板关闭并恢复游戏")
	await _close_scene(scene)


func _check_system_progress_reward_path() -> void:
	var context := await _prepare_reward_ready()
	var scene: Node = context["scene"]
	var tree: SceneTree = context["tree"]
	var state: Node = context["state"]
	var controller: Node = context["controller"]
	var board: Node = context["board"]
	var progress_bar: ProgressBar = scene.get_node("QuestPanel/Panel/Margin/Content/SystemProgress/Bar")
	var progress_label: Label = scene.get_node("QuestPanel/Panel/Margin/Content/SystemProgress/Label")

	_press_interact()
	await tree.process_frame
	await tree.process_frame
	check(board.visible and tree.paused, "系统进度奖励：NPC 打开三选一")
	check(progress_bar.value == 0.0 and progress_label.text.contains("0 / 100"), "系统进度奖励：选择前显示零进度")
	check(controller.select_reward(&"system_progress"), "系统进度奖励：选择成功")
	await tree.process_frame
	check(int(state.system_progress) == 20, "系统进度奖励：进度增加到 20")
	check(progress_bar.value == 20.0 and progress_label.text.contains("20 / 100"),
		"系统进度奖励：任务面板显示 20 / 100")
	check(bool(state.task_a_reward_claimed), "系统进度奖励：领取状态已记录")
	await _close_scene(scene)


func _prepare_reward_ready() -> Dictionary:
	var scene: Node = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	var tree := scene.get_tree()
	await tree.process_frame
	await tree.process_frame

	var state: Node = root.get_node("GameState")
	var quests: Node = scene.get_node("QuestController")
	state.help_choice = ""
	state.task_a_returned = ""
	state.task_a_reward_claimed = false
	state.completed_level = 1
	state.available_level = 1
	state.system_progress = 0
	state.clear_interaction_state()
	quests.reset_progress()
	await tree.process_frame
	await tree.process_frame

	state.help_choice = "accepted"
	await _wait_until(tree, func() -> bool:
		return quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS)
	state.task_a_returned = "returned"
	await _wait_until(tree, func() -> bool:
		return quests.status_of(&"task_a") == QuestControllerScript.Status.COMPLETED)

	var player: CharacterBody3D = scene.get_node("Player")
	var reward_npc: Node3D = scene.get_node("RewardNPC")
	player.set_physics_process(false)
	player.global_position = reward_npc.global_position + Vector3(0.0, 0.0, 0.9)
	for _frame in range(8):
		await tree.physics_frame
	return {
		"scene": scene,
		"tree": tree,
		"state": state,
		"quests": quests,
		"stage": scene.get_node("StageController"),
		"player": player,
		"controller": scene.get_node("EncounterController"),
		"board": scene.get_node("RewardBoard"),
		"arena": scene.get_node("Arena"),
	}


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
	push_error("quest encounter loop test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish(scene: Node) -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(scene):
		scene.get_tree().paused = false
		scene.queue_free()
	if failures == 0:
		print("quest encounter loop checks: all passed")
	else:
		print("quest encounter loop checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)
