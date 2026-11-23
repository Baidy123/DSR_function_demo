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
	service.save_path = OS.get_temp_dir().path_join(
		"dsr-level-save-%d.cfg" % OS.get_process_id())
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
