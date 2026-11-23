extends SceneTree

const LEVEL_ONE := preload("res://scenes/world/levels/lvl_1.tscn")
const Director := preload("res://scripts/systems/scene_director.gd")
const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const WATCHDOG_SECONDS := 20.0

var checks := 0
var failures := 0
var _finished := false
var _settings_path := ""


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1


func _run() -> void:
	create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(_on_watchdog)
	var state := root.get_node("GameState")
	var service := root.get_node("CampaignSaveService")
	service.save_path = OS.get_temp_dir().path_join(
		"dsr-reset-save-%d.cfg" % OS.get_process_id())
	_remove_save_artifacts(service.save_path)
	var settings := root.get_node("UserSettings")
	_settings_path = OS.get_temp_dir().path_join(
		"dsr-reset-settings-%d.cfg" % OS.get_process_id())
	if FileAccess.file_exists(_settings_path):
		DirAccess.remove_absolute(_settings_path)
	settings.config_path = _settings_path
	check(settings.commit_settings(
		settings.mouse_target_assist_enabled,
		settings.target_switch_sensitivity,
		settings.window_mode,
		settings.resolution_index,
		settings.vsync_enabled) == OK,
		"重置测试准备用户设置文件")
	var saved_settings := FileAccess.get_file_as_string(_settings_path)
	state.reset_game_progress()
	state.money = 100
	state.available_level = 3
	state.help_choice = "accepted"
	state.items = {&"coin": {"display_name": "硬币", "count": 1}}
	state.flags = {&"music_playing": true}
	state.opening_cinematic_played = true
	check(service.save_game(state.capture_save_state({})) == OK,
		"重置测试准备有效存档")

	var scene: Node = LEVEL_ONE.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(3):
		await process_frame
	scene.get_node("LevelFlow/PlayGuide/Backdrop/Panel/Content/Close").pressed.emit()
	var director := Director.for_node(scene)
	var loaded_paths: Array[String] = []
	director.scene_loader = func(path: String, _reload: bool) -> Error:
		loaded_paths.append(path)
		return OK
	var health := scene.get_node("Player/Health")
	health.debug_invincible = true
	await process_frame
	var button := health.get_node_or_null("Debug/Controls/ResetProgress") as Button
	check(button != null and not button.disabled, "Debug 控制栏提供可用重置按钮")
	var confirm := health.get_node_or_null("ResetProgressConfirm") as ConfirmationDialog
	check(confirm != null, "重置进度需要确认对话框")
	if button == null or confirm == null:
		_finish(scene, service.save_path)
		return
	var saved_mode: int = settings.window_mode
	var saved_sensitivity: int = settings.target_switch_sensitivity
	button.pressed.emit()
	check(state.money == 100 and FileAccess.file_exists(service.save_path),
		"确认前不重置游戏进度")
	confirm.confirmed.emit()
	await process_frame
	check(state.money == 0 and state.available_level == 1
			and state.items.is_empty() and state.flags.is_empty()
			and not state.opening_cinematic_played,
		"重置清空全部游戏进度")
	check(not FileAccess.file_exists(service.save_path),
		"重置删除正式存档")
	check(settings.window_mode == saved_mode
			and settings.target_switch_sensitivity == saved_sensitivity,
		"重置保留用户设置")
	check(loaded_paths == [MAIN_SCENE_PATH],
		"重置加载主场景返回初始酒馆")
	check(FileAccess.file_exists(_settings_path)
			and FileAccess.get_file_as_string(_settings_path) == saved_settings,
		"重置保留 settings.cfg 内容")
	check(root.get_node("DebugSettings").enabled,
		"重置保留 Debug 总开关状态")
	scene.free()
	current_scene = null
	await process_frame

	state.reset_game_progress()
	state.money = 100
	state.available_level = 3
	state.items = {&"coin": {"display_name": "硬币", "count": 1}}
	state.flags = {&"music_playing": true}
	state.opening_cinematic_played = true
	check(service.save_game(state.capture_save_state({})) == OK,
		"失败恢复测试准备有效存档")

	var failed_scene: Node = LEVEL_ONE.instantiate()
	root.add_child(failed_scene)
	current_scene = failed_scene
	for _frame in range(3):
		await process_frame
	failed_scene.get_node("LevelFlow/PlayGuide/Backdrop/Panel/Content/Close").pressed.emit()
	var failed_director := Director.for_node(failed_scene)
	failed_director.scene_loader = func(_path: String, _reload: bool) -> Error:
		return ERR_FILE_CANT_OPEN
	var failed_health := failed_scene.get_node("Player/Health")
	failed_health.debug_invincible = true
	await process_frame
	var failed_button := failed_health.get_node_or_null("Debug/Controls/ResetProgress") as Button
	var failed_confirm := failed_health.get_node_or_null("ResetProgressConfirm") as ConfirmationDialog
	check(failed_button != null and failed_confirm != null,
		"失败恢复场景提供重置确认入口")
	if failed_button == null or failed_confirm == null:
		_finish(failed_scene, service.save_path)
		return
	failed_confirm.confirmed.emit()
	for _frame in range(3):
		await process_frame
	check(state.money == 100 and FileAccess.file_exists(service.save_path),
		"重置加载失败恢复旧状态和存档")
	check(failed_director.state == &"running",
		"重置加载失败归还场景控制")
	_finish(failed_scene, service.save_path)


func _remove_save_artifacts(save_path: String) -> void:
	for path in [save_path, save_path + ".tmp", save_path + ".bak",
			save_path + ".reset-pending"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _on_watchdog() -> void:
	if _finished:
		return
	_finished = true
	paused = false
	push_error("campaign save reset test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish(scene: Node, save_path: String) -> void:
	if _finished:
		return
	_finished = true
	paused = false
	_remove_save_artifacts(save_path)
	if not _settings_path.is_empty() and FileAccess.file_exists(_settings_path):
		DirAccess.remove_absolute(_settings_path)
	if is_instance_valid(scene):
		scene.free()
	current_scene = null
	print("CAMPAIGN SAVE RESET: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
