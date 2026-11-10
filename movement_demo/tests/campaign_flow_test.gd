extends SceneTree

## 五关循环：完成返酒馆、A 解锁下一关、门口传送，以及跨关玩家状态。
## 运行：godot --headless --path movement_demo --script res://tests/campaign_flow_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")
const ShopItemScript := preload("res://scripts/shop/shop_item_definition.gd")
const CATALOG := preload("res://resources/shop/shop_catalog.tres")
const SHOTGUN := preload("res://resources/weapons/test_shotgun.tres")
const LEVELS: Array[String] = [
	"res://scenes/world/levels/lvl_1.tscn",
	"res://scenes/world/levels/lvl_2.tscn",
	"res://scenes/world/levels/lvl_3.tscn",
	"res://scenes/world/levels/lvl_4.tscn",
	"res://scenes/world/levels/lvl_5.tscn",
]

const WATCHDOG_SECONDS := 40.0
const EXPECTED_CHECKS := 98

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
	await _check_first_level_return_without_checkpoint()
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
	state.money = 0
	state.rewarded_task_ids = {}
	state.purchased_shop_item_ids = {}
	state.system_progress = 0
	state.pending_player_state = {}
	state.level_entry_player_state = {}
	state.campaign_checkpoint = {}
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
	var returned_quests: Node = scene.get_node("QuestController")
	await _wait_until(func() -> bool:
		return returned_quests.status_of(&"task_a") == QuestControllerScript.Status.COMPLETED)
	check(int(state.completed_level) == 1 and int(state.available_level) == 1, "回酒馆记录第1关完成且尚未解锁第2关")
	check(int(state.money) == 100, "第1关完成获得100")
	check(bool(state.rewarded_task_ids.get(&"task_a", false)), "第1关任务奖励已记录一次")
	check(int(state.campaign_checkpoint.get("money", -1)) == 100,
		"完成检查点已同步任务奖励100，即使返程门先于任务完成记录")
	check(is_equal_approx(health.health, 73.0), "酒馆玩家保留第1关结束生命")
	check(equipment.active_slot == 1 and equipment.medkit_count == 1, "酒馆玩家保留当前武器与医疗包")
	check(equipment._ammo_states[0].magazine_rounds == 3 and equipment._ammo_states[1].magazine_rounds == 5,
		"酒馆玩家保留双武器弹匣")
	check(equipment.reserve_ammo[&"rifle"] == 11 and equipment.reserve_ammo[&"shotgun"] == 2,
		"酒馆玩家保留共享备弹")

	portal = scene.get_node("Interactables/LevelPortal")
	check(not portal.can_interact(player), "见 A 之前门口传送门保持锁定")
	var shop_npc: Node3D = scene.get_node("RewardNPC")
	var shop_board: CanvasLayer = scene.get_node("ShopBoard")
	var shop_controller: Node = scene.get_node("ShopController")
	shop_controller.shop_catalog = _campaign_catalog()
	player.set_physics_process(false)
	player.global_position = shop_npc.global_position + Vector3(0.0, 0.0, 0.9)
	for _frame in range(6):
		await physics_frame
	_press_interact()
	await process_frame
	await process_frame
	var money_after_task: int = int(state.money)
	check(shop_board.visible and paused, "第1关回酒店后由蓝色NPC打开商店")
	check(shop_controller.purchase(&"ammo", -1), "购买弹药")
	check(int(state.money) == money_after_task - 30, "购买后扣款")
	shop_controller.close_shop()
	await process_frame
	check(not shop_board.visible and not paused, "第1关商店购买后关闭面板并恢复游戏")
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
	var entry_state: Dictionary = state.level_entry_player_state.duplicate(true)
	var entry_equipment: Dictionary = entry_state.get("equipment", {})
	check(is_equal_approx(health.health, 73.0), "进入第2关继续保留生命")
	check(equipment.campaign_snapshot() == entry_equipment,
		"进入第2关保留入关时的付费弹药与装备")
	check(state.pending_player_state.is_empty(), "待恢复状态只在进入场景时消费一次")
	check(not entry_equipment.is_empty(),
		"进入第2关已保存入关快照")

	health.health = 1.0
	equipment._ammo_states[0].magazine_rounds = 0
	equipment._ammo_states[1].magazine_rounds = 0
	equipment.reserve_ammo[&"rifle"] = 0
	equipment.reserve_ammo[&"pistol"] = 0
	equipment.medkit_count = 0
	health.receive_hit(health.max_health)
	check(player.is_dead() and paused, "第2关死亡暂停并提供重生选择")
	var restart_button: Button = health.get_node("DeathScreen/Center/Panel/Content/Restart")
	var hotel_button: Button = health.get_node("DeathScreen/Center/Panel/Content/ReturnToTavern")
	check(restart_button.can_process() and hotel_button.can_process(),
		"死亡界面同时提供重新挑战和返回酒店")
	restart_button.pressed.emit()
	scene = await _wait_for_scene(LEVELS[1])
	check(scene != null, "当前关重开加载第2关")
	if scene == null:
		_finish()
		return
	await _close_level_guide(scene)
	player = scene.get_node("Player")
	equipment = player.get_node("Equipment")
	check(equipment.campaign_snapshot() == entry_equipment,
		"当前关重开保留入关时的付费弹药与装备")
	check(state.pending_player_state.is_empty(), "当前关重开消费入关快照")

	health = player.get_node("Health")
	health.health = 1.0
	equipment._ammo_states[0].magazine_rounds = 0
	equipment._ammo_states[1].magazine_rounds = 0
	equipment.reserve_ammo[&"rifle"] = 0
	equipment.reserve_ammo[&"pistol"] = 0
	equipment.medkit_count = 0
	health.receive_hit(health.max_health)
	check(player.is_dead() and paused, "第2关重开后死亡仍提供重生选择")
	hotel_button = health.get_node("DeathScreen/Center/Panel/Content/ReturnToTavern")
	hotel_button.pressed.emit()
	scene = await _wait_for_scene("res://scenes/main.tscn")
	check(scene != null, "返回酒店加载酒馆")
	if scene == null:
		_finish()
		return
	player = scene.get_node("Player")
	health = player.get_node("Health")
	equipment = player.get_node("Equipment")
	check(int(state.completed_level) == 1 and int(state.available_level) == 1,
		"返回酒店回到第1关完成且 A 尚未解锁第2关的状态")
	check(int(state.money) == 100, "返回酒店恢复完成时货币")
	check(is_equal_approx(health.health, 73.0), "酒店恢复第1关完成时的生命")
	check(equipment.active_slot == 1 and equipment._ammo_states[0].magazine_rounds == 3
		and equipment._ammo_states[1].magazine_rounds == 5,
		"酒店恢复第1关完成时的槽位和双武器弹匣")
	check(equipment.reserve_ammo[&"rifle"] == 11 and equipment.reserve_ammo[&"pistol"] == 7
		and equipment.reserve_ammo[&"smg"] == 9 and equipment.reserve_ammo[&"shotgun"] == 2
		and equipment.medkit_count == 1,
		"酒店恢复第1关完成时的共享备弹和医疗包")
	check(state.pending_player_state.is_empty(), "酒店只消费一次完成时玩家快照")
	check(scene.get_node("ShopController") != null, "回到酒店后商店入口仍可用")
	check(not scene.get_node("Interactables/LevelPortal").can_interact(player),
		"回到酒店后仍须与 A 交互才能重新解锁第2关")

	shop_npc = scene.get_node("RewardNPC")
	shop_board = scene.get_node("ShopBoard")
	shop_controller = scene.get_node("ShopController")
	shop_controller.shop_catalog = _campaign_catalog()
	player.set_physics_process(false)
	player.global_position = shop_npc.global_position + Vector3(0.0, 0.0, 0.9)
	for _frame in range(6):
		await physics_frame
	_press_interact()
	await process_frame
	await process_frame
	check(shop_board.visible and paused, "酒店返还后仍可再次打开蓝色NPC商店")
	check(shop_controller.purchase(&"shop_shotgun", 0), "购买一次性武器覆盖主武器槽")
	check(equipment.primary_weapon == SHOTGUN, "一次性武器写入主武器槽")
	check(equipment.secondary_weapon == secondary, "一次性武器购买保留副武器")
	check(state.has_purchased_shop_item(&"shop_shotgun"), "一次性武器购买被记录")
	check(int(state.money) == 0, "一次性武器购买后扣款")
	check(shop_board.item_count() == 3, "一次性武器行购买后消失")
	shop_controller.close_shop()
	await process_frame
	check(not shop_board.visible and not paused, "一次性武器购买后关闭商店")

	await _open_a(scene, player)
	check(scene.get_node("DialogueUI").dialogue_text.text.contains("第1关"), "酒店返还后 A 再次告知上一关已完成")
	await _pick(scene.get_node("DialogueUI"), "前往第2关")
	scene.get_node("DialogueUI")._close_dialogue()
	await process_frame
	await process_frame
	check(int(state.available_level) == 2, "酒店返还后 A 可再次解锁第2关")
	portal = scene.get_node("Interactables/LevelPortal")
	check(portal.can_interact(player) and portal.display_name == "关卡2", "再次解锁后门口传送门指向第2关")
	check(portal.interact(player), "携带一次性武器再次进入第2关")
	scene = await _wait_for_scene(LEVELS[1])
	check(scene != null, "一次性武器购买后进入第2关")
	if scene == null:
		_finish()
		return
	await _close_level_guide(scene)
	player = scene.get_node("Player")
	health = player.get_node("Health")
	equipment = player.get_node("Equipment")
	check(equipment.primary_weapon == SHOTGUN, "进入第2关携带一次性武器")
	health.receive_hit(health.max_health)
	check(player.is_dead() and paused, "携带一次性武器死亡暂停")
	hotel_button = health.get_node("DeathScreen/Center/Panel/Content/ReturnToTavern")
	hotel_button.pressed.emit()
	scene = await _wait_for_scene("res://scenes/main.tscn")
	check(scene != null, "一次性武器死亡返回酒店")
	if scene == null:
		_finish()
		return
	player = scene.get_node("Player")
	equipment = player.get_node("Equipment")
	check(int(state.completed_level) == 1 and int(state.available_level) == 1,
		"死亡返回酒店回滚关卡进度")
	check(int(state.money) == 100, "死亡返回酒店退款且任务奖励不重复")
	check(not state.has_purchased_shop_item(&"shop_shotgun"), "死亡返回酒店清除一次性武器购买记录")
	check(equipment.primary_weapon == primary, "死亡返回酒店恢复原主武器")
	check(equipment.secondary_weapon == secondary, "死亡返回酒店恢复原副武器")
	shop_npc = scene.get_node("RewardNPC")
	shop_board = scene.get_node("ShopBoard")
	shop_controller = scene.get_node("ShopController")
	shop_controller.shop_catalog = _campaign_catalog()
	player.set_physics_process(false)
	player.global_position = shop_npc.global_position + Vector3(0.0, 0.0, 0.9)
	for _frame in range(6):
		await physics_frame
	_press_interact()
	await process_frame
	await process_frame
	check(shop_board.visible and paused, "死亡退款后可再次打开商店")
	check(shop_board.item_count() == 4, "死亡退款后一次性武器行重新可见")
	shop_controller.close_shop()
	await process_frame
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


func _check_first_level_return_without_checkpoint() -> void:
	var scene: Node = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var state := root.get_node("GameState")
	var quests: Node = scene.get_node("QuestController")
	state.help_choice = ""
	state.task_a_returned = ""
	state.completed_level = 0
	state.available_level = 1
	state.claimed_reward_levels = {}
	state.system_progress = 0
	state.pending_player_state = {}
	state.campaign_checkpoint = {}
	state.clear_interaction_state()
	quests.reset_progress()
	state.help_choice = "accepted"
	await _wait_until(func() -> bool:
		return quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS)

	var player: CharacterBody3D = scene.get_node("Player")
	var portal = scene.get_node("Interactables/LevelPortal")
	check(portal.can_interact(player), "首关死亡前任务已接取且关卡入口可用")
	check(portal.interact(player), "首关任务入口携带玩家状态进入第1关")
	scene = await _wait_for_scene(LEVELS[0])
	check(scene != null, "首关无完成检查点测试进入第1关")
	if scene == null:
		_finish()
		return
	await _close_level_guide(scene)
	player = scene.get_node("Player")
	var health = player.get_node("Health")
	health.receive_hit(health.max_health)
	check(player.is_dead() and paused, "首关未完成时死亡提供重生选择")
	health.get_node("DeathScreen/Center/Panel/Content/ReturnToTavern").pressed.emit()
	scene = await _wait_for_scene("res://scenes/main.tscn")
	check(scene != null, "首关无检查点时仍可返回酒店")
	if scene != null:
		player = scene.get_node("Player")
		portal = scene.get_node("Interactables/LevelPortal")
		var returned_quests: Node = scene.get_node("QuestController")
		check(int(state.completed_level) == 0 and int(state.available_level) == 1,
			"首关返回酒店不伪造完成或下一关进度")
		check(state.help_choice == "accepted"
			and returned_quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS,
			"首关返回酒店保留已接取任务")
		check(state.campaign_checkpoint.is_empty() and state.pending_player_state.is_empty(),
			"首关无检查点返回不会留下待消费玩家状态")
		check(not player.is_dead() and portal.can_interact(player) and portal.display_name == "关卡1",
			"首关返回酒店后玩家可重新进入第1关")
	await _release(scene)


func _campaign_catalog() -> ShopCatalog:
	var catalog: ShopCatalog = CATALOG.duplicate(true) as ShopCatalog
	var weapon := ShopItemScript.new()
	weapon.id = &"shop_shotgun"
	weapon.display_name = "商店霰弹枪"
	weapon.description = "覆盖主武器槽"
	weapon.price = 100
	weapon.unlock_level = 1
	weapon.effect = ShopItemScript.Effect.WEAPON
	weapon.weapon_data = SHOTGUN
	weapon.one_time = true
	catalog.items.append(weapon)
	return catalog


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


func _press_interact() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	root.push_input(event)
	Input.flush_buffered_events()


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
