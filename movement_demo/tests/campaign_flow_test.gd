extends SceneTree

## 五关循环：完成返酒馆、A 解锁下一关、门口传送，以及跨关玩家状态。
## 运行：godot --headless --path movement_demo --script res://tests/campaign_flow_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")
const LEVELS: Array[String] = [
	"res://scenes/world/levels/lvl_1.tscn",
	"res://scenes/world/levels/lvl_2.tscn",
	"res://scenes/world/levels/lvl_3.tscn",
	"res://scenes/world/levels/lvl_4.tscn",
	"res://scenes/world/levels/lvl_5.tscn",
]

const WATCHDOG_SECONDS := 40.0
const EXPECTED_CHECKS := 46

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
	await _check_all_levels_expose_return_portal()
	await _check_campaign_loop_and_player_state()
	await _check_final_tavern_dialogue()
	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d（脚本报错会中断后续检查）" % [EXPECTED_CHECKS, checks_run])
	_finish()


func _check_all_levels_expose_return_portal() -> void:
	for number in range(1, LEVELS.size() + 1):
		var scene: Node = load(LEVELS[number - 1]).instantiate()
		root.add_child(scene)
		current_scene = scene
		await process_frame
		await process_frame
		var portal = scene.get_node_or_null("TavernReturnPortal") as Interactable
		check(portal != null, "第%d关挂载返回酒馆传送门" % number)
		if portal != null:
			var guide = scene.get_node("LevelFlow/PlayGuide")
			guide.get_node("Backdrop/Panel/Content/Close").pressed.emit()
			await process_frame
			scene.get_node("SceneDirector").encounter_completed.emit()
			for _frame in range(4):
				await process_frame
			check(portal.visible and portal.enabled and portal.monitoring,
				"第%d关完成后只启用返回酒馆传送门" % number)
			check(not scene.get_node("LevelFlow/Result").visible,
				"第%d关不再显示直接进入下一关面板" % number)
		paused = false
		scene.queue_free()
		current_scene = null
		await process_frame


func _check_campaign_loop_and_player_state() -> void:
	var scene: Node = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var state := root.get_node("GameState")
	if not _has_campaign_fields(state):
		check(false, "GameState 提供关卡进度与待恢复玩家状态")
		await _release(scene)
		return
	check(true, "GameState 提供关卡进度与待恢复玩家状态")

	var quests: Node = scene.get_node("QuestController")
	state.help_choice = ""
	state.task_a_returned = ""
	state.completed_level = 0
	state.available_level = 1
	state.pending_player_state = {}
	quests.reset_progress()
	state.help_choice = "accepted"
	await _wait_until(func() -> bool:
		return quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS)

	var player: CharacterBody3D = scene.get_node("Player")
	var health: CanvasLayer = player.get_node("Health")
	var equipment: CanvasLayer = player.get_node("Equipment")
	health.health = 73.0
	health._update_display()
	equipment.select_slot(1)
	equipment._ammo_states[0].magazine_rounds = 3
	equipment._ammo_states[1].magazine_rounds = 5
	equipment.reserve_ammo[&"rifle"] = 11
	equipment.reserve_ammo[&"pistol"] = 7
	equipment.reserve_ammo[&"smg"] = 9
	equipment.reserve_ammo[&"shotgun"] = 2
	equipment.medkit_count = 1
	var primary: WeaponData = equipment.primary_weapon
	var secondary: WeaponData = equipment.secondary_weapon

	var portal = scene.get_node("Interactables/LevelPortal")
	check(portal.can_interact(player) and portal.display_name == "关卡1", "首次接取任务后可进入第1关")
	check(portal.interact(player), "酒馆传送门记录并携带玩家状态进入第1关")
	scene = await _wait_for_scene(LEVELS[0])
	check(scene != null, "门口传送门加载第1关")
	if scene == null:
		_finish()
		return
	await _close_level_guide(scene)
	player = scene.get_node("Player")
	health = player.get_node("Health")
	equipment = player.get_node("Equipment")
	check(is_equal_approx(health.health, 73.0), "进入第1关保留生命")
	check(equipment.active_slot == 1 and equipment.primary_weapon == primary and equipment.secondary_weapon == secondary,
		"进入第1关保留当前槽位与双武器")
	check(equipment._ammo_states[0].magazine_rounds == 3 and equipment._ammo_states[1].magazine_rounds == 5,
		"进入第1关保留双武器弹匣")
	check(equipment.reserve_ammo[&"rifle"] == 11 and equipment.reserve_ammo[&"pistol"] == 7
		and equipment.reserve_ammo[&"smg"] == 9 and equipment.reserve_ammo[&"shotgun"] == 2,
		"进入第1关保留共享备弹")
	check(equipment.medkit_count == 1, "进入第1关保留医疗包")

	var return_portal = scene.get_node("TavernReturnPortal")
	scene.get_node("SceneDirector").encounter_completed.emit()
	await _wait_until(func() -> bool: return return_portal.enabled)
	check(return_portal.interact(player), "第1关完成后返回酒馆")
	scene = await _wait_for_scene("res://scenes/main.tscn")
	check(scene != null, "返程门加载酒馆")
	if scene == null:
		_finish()
		return
	await process_frame
	await process_frame
	player = scene.get_node("Player")
	health = player.get_node("Health")
	equipment = player.get_node("Equipment")
	check(int(state.completed_level) == 1 and int(state.available_level) == 1, "回酒馆记录第1关完成且尚未解锁第2关")
	check(is_equal_approx(health.health, 73.0), "酒馆玩家保留第1关结束生命")
	check(equipment.active_slot == 1 and equipment.medkit_count == 1, "酒馆玩家保留当前武器与医疗包")
	check(equipment._ammo_states[0].magazine_rounds == 3 and equipment._ammo_states[1].magazine_rounds == 5,
		"酒馆玩家保留双武器弹匣")
	check(equipment.reserve_ammo[&"rifle"] == 11 and equipment.reserve_ammo[&"shotgun"] == 2,
		"酒馆玩家保留共享备弹")

	portal = scene.get_node("Interactables/LevelPortal")
	check(not portal.can_interact(player), "见 A 之前门口传送门保持锁定")
	await _open_a(scene, player)
	check(scene.get_node("DialogueUI").dialogue_text.text.contains("第1关"), "A 告知上一关已完成")
	await _pick(scene.get_node("DialogueUI"), "前往第2关")
	scene.get_node("DialogueUI")._close_dialogue()
	await process_frame
	await process_frame
	check(int(state.available_level) == 2, "再次与 A 交互后解锁第2关")
	check(portal.can_interact(player) and portal.display_name == "关卡2", "A 解锁后门口传送门指向第2关")
	check(portal.interact(player), "与 A 交互后仍由门口传送门进入下一关")
	scene = await _wait_for_scene(LEVELS[1])
	check(scene != null, "门口传送门加载第2关")
	if scene == null:
		_finish()
		return
	await _close_level_guide(scene)
	player = scene.get_node("Player")
	health = player.get_node("Health")
	equipment = player.get_node("Equipment")
	check(is_equal_approx(health.health, 73.0), "进入第2关继续保留生命")
	check(equipment.active_slot == 1 and equipment._ammo_states[0].magazine_rounds == 3
		and equipment._ammo_states[1].magazine_rounds == 5 and equipment.medkit_count == 1,
		"进入第2关继续保留武器、弹匣和医疗包")
	check(state.pending_player_state.is_empty(), "待恢复状态只在进入场景时消费一次")

	health.receive_hit(health.max_health)
	check(player.is_dead() and paused, "第2关死亡仍按现有规则暂停")
	health.get_node("DeathScreen/Center/Panel/Content/Restart").pressed.emit()
	scene = await _wait_for_scene(LEVELS[1])
	check(scene != null, "死亡按钮只重开当前第2关")
	if scene != null:
		player = scene.get_node("Player")
		health = player.get_node("Health")
		check(is_equal_approx(health.health, health.max_health), "死亡重开恢复第2关保存的初始生命")
	await _release(scene)


func _check_final_tavern_dialogue() -> void:
	var scene: Node = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var state := root.get_node("GameState")
	if not _has_campaign_fields(state):
		return
	state.help_choice = "accepted"
	state.completed_level = 5
	state.available_level = 5
	state.pending_player_state = {}
	await process_frame
	var player: CharacterBody3D = scene.get_node("Player")
	var portal = scene.get_node("Interactables/LevelPortal")
	check(not portal.can_interact(player), "第5关完成后不再解锁第6关")
	await _open_a(scene, player)
	check(scene.get_node("DialogueUI").dialogue_text.text.contains("五关"), "A 在第5关后告知挑战完成")
	check(scene.get_node("DialogueUI").choices.get_child_count() == 0, "第5关后 A 不再提供下一关选项")
	scene.get_node("DialogueUI")._close_dialogue()
	await _release(scene)


func _has_campaign_fields(state: Node) -> bool:
	var names: Array[StringName] = []
	for property in state.get_property_list():
		names.append(StringName(property.name))
	return names.has(&"completed_level") and names.has(&"available_level") and names.has(&"pending_player_state")


func _open_a(scene: Node, player: Node3D) -> void:
	var npc := scene.get_node("NPC")
	await scene.get_node("DialogueUI").open_dialogue(player, npc.dialogue_resource, "start")
	await process_frame


func _pick(ui, keyword: String) -> void:
	for child in ui.choices.get_children():
		if child.text.contains(keyword):
			child.pressed.emit()
			await process_frame
			await process_frame
			return
	push_error("对话缺少选项：" + keyword)


func _close_level_guide(scene: Node) -> void:
	var guide = scene.get_node("LevelFlow/PlayGuide")
	if guide.visible:
		guide.get_node("Backdrop/Panel/Content/Close").pressed.emit()
	await process_frame
	await process_frame


func _wait_for_scene(path: String) -> Node:
	for _frame in range(180):
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path:
			await process_frame
			await process_frame
			return current_scene
		await process_frame
	return null


func _wait_until(predicate: Callable) -> bool:
	for _frame in range(120):
		if predicate.call():
			return true
		await process_frame
	return false


func _release(scene: Node) -> void:
	paused = false
	if is_instance_valid(scene):
		scene.queue_free()
	current_scene = null
	await process_frame


func _on_watchdog() -> void:
	if _finished:
		return
	_finished = true
	paused = false
	push_error("campaign flow test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	if failures == 0:
		print("campaign flow checks: all passed")
	else:
		print("campaign flow checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)
