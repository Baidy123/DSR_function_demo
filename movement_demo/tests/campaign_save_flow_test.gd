extends SceneTree

const LEVEL_ONE := preload("res://scenes/world/levels/lvl_1.tscn")
const Director := preload("res://scripts/systems/scene_director.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1


func _run() -> void:
	var state := root.get_node("GameState")
	var service := root.get_node("CampaignSaveService")
	state.reset_game_progress()
	var save_path := OS.get_temp_dir().path_join(
		"dsr-level-save-%d.cfg" % OS.get_process_id())
	service.save_path = OS.get_temp_dir().path_join(
		"dsr-level-save-missing-%d" % OS.get_process_id()).path_join("save.cfg")
	var tavern_scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(tavern_scene)
	current_scene = tavern_scene
	for _frame in range(3):
		await process_frame
	var tavern_director := Director.for_node(tavern_scene)
	state.money = 88
	var remembered: Dictionary = state.capture_save_state(
		{"health": {"health": 70.0}})
	state.remember_tavern_state(remembered)
	var unchanged_tavern: Dictionary = state.last_tavern_state.duplicate(true)
	state.money = 999
	var failed_result: Dictionary = tavern_director.save_game()
	check(failed_result.result == &"save_failed", "无效存档路径返回保存失败")
	check(state.last_tavern_state == unchanged_tavern,
		"保存失败不替换最后酒馆状态")
	service.save_path = save_path
	if FileAccess.file_exists(service.save_path):
		DirAccess.remove_absolute(service.save_path)
	state.money = 88
	state.items = {&"coin": {"display_name": "硬币", "count": 2}}
	state.set_flag(&"opening_active")
	check(not tavern_director.can_save_game(), "酒馆开场未完成时禁用保存")
	state.set_flag(&"opening_complete")
	var player := tavern_scene.get_node("Player")
	var health := player.get_node("Health")
	var equipment := player.get_node("Equipment")
	health.health = 42.0
	health._update_display()
	equipment.medkit_count = 2
	var active_slot: int = equipment.active_slot
	var active_weapon: WeaponData = equipment.primary_weapon \
		if active_slot == 0 else equipment.secondary_weapon
	var expected_magazine := maxi(0, active_weapon.magazine_capacity - 2)
	equipment._ammo_states[active_slot].magazine_rounds = expected_magazine
	var saved_result: Dictionary = tavern_director.save_game()
	check(saved_result.result == &"tavern_saved", "酒馆内保存真实玩家状态")
	var saved_player: Dictionary = service.load_game().get("player_state", {})
	var saved_equipment: Dictionary = saved_player.get("equipment", {})
	check(saved_player.get("health", {}).get("health") == 42.0
			and saved_equipment.get("medkit_count") == 2
			and saved_equipment.get("active_slot") == active_slot
			and saved_equipment.get("magazines", [])[active_slot] == expected_magazine,
		"酒馆存档写入真实生命与装备字段")
	tavern_scene.free()
	current_scene = null
	await process_frame
	state.reset_game_progress()
	var exterior: Node = load("res://scenes/access_denied/hub/tavern_exterior.tscn").instantiate()
	root.add_child(exterior)
	current_scene = exterior
	exterior.get_node("SceneDirector").director.initialize()
	var resume_request: SceneRequest = service.resume_game(exterior)
	check(resume_request != null, "启动外景通过导演提交读档事务")
	if resume_request == null:
		quit(1)
		return
	await resume_request.wait_result()
	check(resume_request.status == &"completed", "启动读档事务完成")
	for _frame in range(3):
		await process_frame
	var restored_tavern := current_scene
	check(restored_tavern != null and restored_tavern.scene_file_path == "res://scenes/main.tscn"
		and state.get_flag(&"opening_complete") and state.money == 88,
		"有效存档从本地启动外景进入现有酒馆并恢复剧情标记")
	if restored_tavern == null or restored_tavern == exterior:
		quit(1)
		return
	var restored_player := restored_tavern.get_node("Player")
	var restored_health := restored_player.get_node("Health")
	var restored_equipment := restored_player.get_node("Equipment")
	check(restored_health.health == 42.0
			and restored_equipment.medkit_count == 2
			and restored_equipment.active_slot == active_slot
			and restored_equipment._ammo_states[active_slot].magazine_rounds == expected_magazine,
		"新酒馆玩家实际恢复生命与装备")
	restored_tavern.free()
	current_scene = null
	await process_frame

	state.reset_game_progress()
	if FileAccess.file_exists(service.save_path):
		DirAccess.remove_absolute(service.save_path)

	var scene: Node = LEVEL_ONE.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(3):
		await process_frame
	scene.get_node("LevelFlow/PlayGuide/Backdrop/Panel/Content/Close").pressed.emit()
	var director := Director.for_node(scene)
	check(not director.can_save_game()
		and director.save_game().result == &"unavailable",
		"没有最后酒馆状态时关卡不能保存")
	director.request_pause_menu()
	var menu: CanvasLayer = director.get_node("PauseMenu")
	var settings_page := menu.get_node("Backdrop/Center/Panel/Content/Settings")
	settings_page.get_parent().get_node("Main/Settings").pressed.emit()
	check(settings_page.get_node("SaveGame").disabled
		and settings_page.get_node("GameSaveNotice").text.contains("没有可保存"),
		"无最后酒馆状态时保存按钮禁用并显示独立提示")
	director.resume_from_pause_menu()
	state.money = 88
	state.items = {&"coin": {"display_name": "硬币", "count": 2}}
	var tavern_snapshot: Dictionary = state.capture_save_state(
		{"health": {"health": 70.0}})
	state.remember_tavern_state(tavern_snapshot)
	check(director.can_save_game(), "有最后酒馆状态时关卡可以保存")
	state.money = 999
	state.items = {}
	var result: Dictionary = director.save_game()
	check(result.result == &"level_saved", "关卡内保存使用最后酒馆快照")
	var loaded: Dictionary = service.load_game()
	check(loaded.money == 88 and loaded.items.has(&"coin"),
		"关卡内当前货币和物品没有写入存档")
	scene.free()
	current_scene = null
	DirAccess.remove_absolute(service.save_path)
	print("CAMPAIGN SAVE FLOW: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
